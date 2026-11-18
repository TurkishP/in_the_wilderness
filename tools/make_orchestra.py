"""Makes orchestral music for the game: original pieces in the manner of a sweeping fantasy
film score (broad strings, horns, woodwinds, harp, choir, timpani), with a touch of the Middle East
(the Hijaz mode) for the Sinai setting.

    uv venv --python 3.12 sfenv
    uv pip install --python sfenv/Scripts/python.exe --no-deps tinysoundfont==0.3.7 numpy
    sfenv/Scripts/python.exe tools/make_orchestra.py SOUNDFONT [OUT_DIR [NAME ...]]

(tinysoundfont lists pyaudio as a dependency, but only needs it for live playback, hence
--no-deps.) SOUNDFONT is MuseScore_General.sf3 (MIT licence, from the MuseScore project): the
instrument banks below are that soundfont's. OUT_DIR defaults to assets/music/samples. Needs ffmpeg
on the PATH. The pieces are written out note by note below; nothing is taken from other music.

  orchestra_1_wilderness.ogg  The Wilderness: a broad theme in D Dorian, horn alone, then violins,
                              then the whole orchestra.
  orchestra_2_evening.ogg     Evening at the Camp: a flute melody in 3/4 over harp and strings, with
                              an oboe in the Hijaz mode in the middle.
  orchestra_3_mountain.ogg    The Mountain of God: a slow chorale in Hijaz on D, from murmuring
                              strings and choir to full brass, choir and timpani.
  orchestra_4_empty_hall.ogg  The Empty Hall: spare; a solo violin over a held low fifth in E minor,
                              a horn's answer, one short swell, the solo again.
  orchestra_5_psalm.ogg       A Psalm in the Desert: spare; an English horn in Hijaz over a held D,
                              a solo violin answering, the choir rising once.
"""
import os
import random
import subprocess
import sys
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# (bank, program) in MuseScore_General. Banks 20, 40 and 50 are its separate violin, cello and
# double-bass sections; bank 8 program 40 is a solo violin with a soft attack. Each piece gets a
# channel per instrument it uses (at most 15; channel 9 is the percussion kit).
INSTRUMENTS = {
    "violins": (20, 48), "strings": (0, 49), "celli": (40, 49), "basses": (50, 49), "horns": (0, 60),
    "brass": (0, 61), "trombones": (0, 57), "flute": (0, 73), "oboe": (0, 68), "harp": (0, 46),
    "timpani": (0, 47), "choir": (0, 52), "oohs": (0, 53), "pizz": (0, 45), "tremolo": (0, 44),
    "solo_violin": (8, 40), "english_horn": (0, 69),
}
PANS = {"violins": 40, "strings": 70, "celli": 84, "basses": 92, "horns": 52, "brass": 74, "trombones": 82,
        "flute": 56, "oboe": 70, "harp": 30, "timpani": 64, "choir": 64, "oohs": 64, "pizz": 88, "tremolo": 48,
        "solo_violin": 58, "english_horn": 68}
# Channel levels in dB, to even out the soundfont: its string sections are about 10 dB quieter per
# note than its brass.
LEVELS = {"violins": 0, "strings": 0, "celli": 0, "basses": 0, "tremolo": 0, "pizz": 0, "harp": 0,
          "choir": -2, "oohs": -2, "flute": -3, "oboe": -3, "timpani": -3, "horns": -7, "trombones": -8,
          "brass": -10, "drums": -9, "solo_violin": 0, "english_horn": -3}
DRUMS = 9
ORCHESTRA_KIT = 48
CRASH, SUSPENDED, BASS_DRUM = 57, 59, 36   # the orchestra kit's concert cymbals and bass drum


def pitch(name):
    """'D4' -> 62, 'F#3' -> 54, 'Bb2' -> 46 (C4 is 60)."""
    n = NAMES[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        n += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return n + 12 * (int(rest) + 1)


QUALITIES = {"": [0, 4, 7], "m": [0, 3, 7], "sus4": [0, 5, 7], "add9": [0, 4, 7, 2], "madd9": [0, 3, 7, 2], "5": [0, 7]}


def chord(sym):
    """'Dm' -> (pitch classes, bass class); 'Gm/D' has D in the bass."""
    bass = None
    if "/" in sym:
        sym, b = sym.split("/")
        bass = pitch(b + "0") % 12
    root = sym[0]
    i = 1
    while i < len(sym) and sym[i] in "#b":
        root += sym[i]
        i += 1
    r = pitch(root + "0") % 12
    pcs = [(r + x) % 12 for x in QUALITIES[sym[i:]]]
    return pcs, (r if bass is None else bass)


class Score:
    def __init__(self, bpm, meter):
        self.bpm = bpm
        self.meter = meter
        self.notes = []     # (beat, beats, part, pitch, velocity)
        self.ccs = []       # (beat, part, controller, value)
        self.rng = random.Random(1491)

    def bar(self, n):
        return (n - 1) * self.meter

    def seconds(self, beat):
        return beat * 60.0 / self.bpm

    def note(self, part, beat, beats, p, vel):
        self.notes.append((beat, beats, part, p, max(1, min(127, int(vel)))))

    def swell(self, part, beat0, beat1, v0, v1):
        """Expression (CC 11) going from v0 to v1 between two beats."""
        steps = max(2, int((beat1 - beat0) * 4))
        for k in range(steps + 1):
            f = k / steps
            self.ccs.append((beat0 + (beat1 - beat0) * f, part, 11, int(v0 + (v1 - v0) * f)))

    def line(self, part, bar, text, vel, shift=0, legato=0.97, accent=True):
        """A melody: 'D4 1.5, E4 .5, F4 1 | G4 2, r 2'. Bars ('|') are only for reading."""
        beat = self.bar(bar)
        for tok in text.replace("|", ",").split(","):
            tok = tok.strip()
            if not tok:
                continue
            name, dur = tok.split()
            dur = float(dur)
            if name != "r":
                lift = 6 if accent and abs(beat % self.meter) < 1e-6 else 0
                self.note(part, beat, dur * legato, pitch(name) + shift, vel + lift + self.rng.randint(-4, 4))
            beat += dur
        return beat

    def progression(self, bar, chords):
        """[(beat, beats, pcs, bass), ...] from a list of bars, each bar 'C' or 'Bb C' (split evenly)."""
        out = []
        beat = self.bar(bar)
        for b in chords:
            syms = b.split()
            each = self.meter / len(syms)
            for s in syms:
                pcs, bass = chord(s)
                out.append((beat, each, pcs, bass))
                beat += each
        return out


def nearest(pcs, prev, lo, hi, avoid=()):
    best = None
    for p in range(lo, hi + 1):
        if p % 12 in pcs and p not in avoid:
            if best is None or abs(p - prev) < abs(best - prev):
                best = p
    return best if best is not None else prev


def harmony(s, part, prog, vel, voices=3, lo=55, hi=76, top=67):
    """Sustained chords on one part, voice-led: each voice moves to the nearest chord tone."""
    prev = [top - 7, top - 3, top][-voices:]
    for beat, beats, pcs, _ in prog:
        chosen = []
        for v in prev:
            p = nearest(pcs, v, lo, hi, chosen)
            chosen.append(p)
        for p in chosen:
            s.note(part, beat, beats * 0.98, p, vel + s.rng.randint(-3, 3))
        prev = chosen


def bass(s, part, prog, vel, octave=2, every=None):
    """The bass of each chord, held (or repeated each `every` beats)."""
    for beat, beats, pcs, b in prog:
        p = b + 12 * (octave + 1)
        if every:
            t = 0.0
            while t < beats - 1e-6:
                s.note(part, beat + t, min(every, beats - t) * 0.9, p, vel + s.rng.randint(-3, 3))
                t += every
        else:
            s.note(part, beat, beats * 0.98, p, vel + s.rng.randint(-3, 3))


def arpeggio(s, part, prog, vel, step=0.5, low=50, span=24):
    """Harp: the chord broken upward and back over two octaves."""
    for beat, beats, pcs, b in prog:
        tones = [p for p in range(low, low + span + 1) if p % 12 in pcs]
        if not tones:
            continue
        cycle = tones + tones[-2:0:-1]
        t = 0.0
        i = 0
        while t < beats - 1e-6:
            s.note(part, beat + t, step * 2.5, cycle[i % len(cycle)], vel + s.rng.randint(-6, 4))
            t += step
            i += 1


def roll(s, part, beat, beats, p, v0, v1, rate=10.0):
    """A roll (timpani or cymbal): quick strokes growing or dying from v0 to v1."""
    n = max(2, int(beats * 60.0 / s.bpm * rate))
    for k in range(n):
        f = k / (n - 1)
        s.note(part, beat + beats * k / n, beats / n * 1.5, p, v0 + (v1 - v0) * f)


# ---------------------------------------------------------------- the pieces

def wilderness():
    """The Wilderness: 4/4, D Dorian. Horn alone, then violins, then everyone."""
    s = Score(72, 4)
    theme = ("D4 1.5, E4 .5, F4 1, A4 1 | G4 1.5, F4 .5, E4 1, D4 1 | C4 1, D4 1, F4 1, E4 1 | D4 3, A3 1 |"
             "D4 1.5, E4 .5, F4 1, A4 1 | C5 2, B4 1, A4 1 | G4 1.5, A4 .5, F4 1, E4 1 | D4 4")
    chords = ["Dm", "C", "Bb", "A", "Dm", "G", "Bb C", "Dm"]
    counter = "A3 2, F3 2 | E3 2, G3 2 | F3 2, D3 2 | E3 2, C#3 2 | A3 2, F3 2 | B3 2, D4 2 | D4 1, C4 1, Bb3 1, C4 1 | A3 4"
    # Bars 1-2: a held D, harp, a distant timpani roll.
    intro = s.progression(1, ["Dmadd9", "Dmadd9"])
    bass(s, "basses", intro, 60)
    bass(s, "celli", intro, 55, octave=3)
    harmony(s, "strings", intro, 45, lo=57, hi=74)
    arpeggio(s, "harp", intro, 50)
    roll(s, "timpani", s.bar(2), 4, pitch("D3"), 25, 55)
    s.swell("strings", 0, 8, 40, 90)
    # Bars 3-10: the horn alone with the theme.
    p1 = s.progression(3, chords)
    s.line("horns", 3, theme, 78)
    harmony(s, "strings", p1, 50, lo=55, hi=72)
    bass(s, "celli", p1, 55, octave=3)
    bass(s, "basses", p1, 52)
    arpeggio(s, "harp", p1, 46)
    # Bars 11-18: violins take it up an octave, celli answer below, flute joins halfway.
    p2 = s.progression(11, chords)
    s.line("violins", 11, theme, 84, shift=12)
    s.line("celli", 11, counter, 70)
    harmony(s, "horns", p2, 40, voices=2, lo=53, hi=67, top=62)
    harmony(s, "strings", p2, 52, lo=57, hi=74)
    bass(s, "basses", p2, 60)
    arpeggio(s, "harp", p2, 48, step=0.5, low=55)
    s.line("flute", 15, "D4 1.5, E4 .5, F4 1, A4 1 | C5 2, B4 1, A4 1 | G4 1.5, A4 .5, F4 1, E4 1 | D4 4", 58, shift=12)
    for b in (11, 15):
        s.note("timpani", s.bar(b), 1, pitch("D3"), 70)
    s.swell("violins", s.bar(11), s.bar(19), 100, 125)
    roll(s, "timpani", s.bar(18), 4, pitch("A2"), 40, 100)
    roll(s, DRUMS, s.bar(18), 4, SUSPENDED, 15, 60)
    # Bars 19-26: the whole orchestra; the theme ends on D major.
    big = ["Dm", "Bb", "F", "C", "Dm", "G", "Bb C", "D"]
    p3 = s.progression(19, big)
    s.line("violins", 19, theme, 104, shift=12)
    s.line("flute", 19, theme, 82, shift=12)
    s.line("horns", 19, theme, 100)
    harmony(s, "brass", p3, 70, lo=55, hi=72, top=65)
    harmony(s, "choir", p3, 78, lo=57, hi=76, top=69)
    harmony(s, "strings", p3, 70, lo=55, hi=79, top=72)
    bass(s, "trombones", p3, 84, octave=2)
    bass(s, "celli", p3, 84, octave=2)
    bass(s, "basses", p3, 88, octave=1)
    arpeggio(s, "harp", p3, 60, step=0.25, low=55)
    s.note(DRUMS, s.bar(19), 4, CRASH, 85)
    for b in range(19, 27):
        s.note("timpani", s.bar(b), 1, pitch("D3") if b % 2 else pitch("A2"), 92)
    # Bars 27-28: the last chord rings and fades.
    end = s.progression(27, ["D", "D"])
    harmony(s, "strings", end, 70, lo=55, hi=79, top=74)
    harmony(s, "choir", end, 70, lo=57, hi=76, top=69)
    harmony(s, "horns", end, 75, lo=50, hi=67, top=62)
    bass(s, "basses", end, 80, octave=1)
    roll(s, "timpani", s.bar(26) + 2, 6, pitch("D3"), 95, 30)
    for part in ("strings", "choir", "horns", "basses", "brass"):
        s.swell(part, s.bar(27), s.bar(29), 120, 10)
    return s, s.bar(29) + 3


def evening():
    """Evening at the Camp: 3/4 in G; flute, harp and strings, an oboe in Hijaz on D in the middle."""
    s = Score(80, 3)
    tune = ("B4 1, D5 1, G5 1 | F#5 1.5, E5 .5, D5 1 | E5 1, C5 1, A4 1 | B4 3 |"
            "B4 1, D5 1, G5 1 | A5 1.5, G5 .5, F#5 1 | E5 1, D5 1, F#5 1 | G5 3")
    tune_chords = ["G", "D/F#", "C", "Em", "G", "D", "C D", "G"]
    hijaz = ("D5 1, Eb5 1, F#5 1 | G5 2, F#5 1 | Eb5 1, F#5 .5, Eb5 .5, D5 1 | D5 3 |"
             "A4 1, Bb4 1, C5 1 | D5 1.5, Eb5 .5, D5 1 | C5 1, Bb4 1, A4 1 | D5 3")
    hijaz_chords = ["D", "Gm/D", "Eb/D", "D", "Cm/D", "D", "Cm Bb", "D"]
    # Bars 1-2: the harp alone, then strings come in under it.
    intro = s.progression(1, ["G", "Gsus4"])
    arpeggio(s, "harp", intro, 52, step=0.5, low=55)
    harmony(s, "strings", intro, 38, lo=55, hi=74, top=71)
    s.swell("strings", 0, 6, 30, 80)
    # Bars 3-10: the flute.
    p1 = s.progression(3, tune_chords)
    s.line("flute", 3, tune, 72)
    arpeggio(s, "harp", p1, 46, step=0.5, low=55)
    harmony(s, "strings", p1, 45, lo=55, hi=74, top=71)
    bass(s, "pizz", p1, 58, octave=2, every=3)
    bass(s, "celli", p1, 40, octave=3)
    # Bars 11-18: the oboe in Hijaz over a held D, the strings trembling softly.
    p2 = s.progression(11, hijaz_chords)
    s.line("oboe", 11, hijaz, 74)
    harmony(s, "tremolo", p2, 48, lo=57, hi=74, top=69)
    for b in range(11, 19):
        s.note("celli", s.bar(b), 2.9, pitch("D3"), 52)
        s.note("basses", s.bar(b), 2.9, pitch("D2"), 50)
    for b in (11, 13, 15, 17):
        arpeggio(s, "harp", s.progression(b, [hijaz_chords[b - 11].split()[0]]), 38, step=1.0, low=50)
    s.swell("tremolo", s.bar(11), s.bar(15), 60, 100)
    s.swell("tremolo", s.bar(15), s.bar(19), 100, 70)
    # Bars 19-26: the flute again, violins below it, a horn holding the harmony.
    p3 = s.progression(19, tune_chords)
    s.line("flute", 19, tune, 76)
    s.line("violins", 19, tune, 58, shift=-12)
    harmony(s, "strings", p3, 52, lo=55, hi=76, top=71)
    harmony(s, "horns", p3, 34, voices=2, lo=55, hi=67, top=62)
    arpeggio(s, "harp", p3, 48, step=0.5, low=55)
    bass(s, "pizz", p3, 60, octave=2, every=3)
    bass(s, "celli", p3, 48, octave=3)
    bass(s, "basses", p3, 46, octave=2)
    # Bars 27-28: a last G, the harp rolled up to the top.
    end = s.progression(27, ["G", "G"])
    harmony(s, "strings", end, 48, lo=55, hi=79, top=74)
    arpeggio(s, "harp", s.progression(27, ["G"]), 50, step=0.25, low=43, span=36)
    bass(s, "celli", end, 45, octave=2)
    s.swell("strings", s.bar(27), s.bar(29), 100, 10)
    return s, s.bar(29) + 3


def mountain():
    """The Mountain of God: 4/4, Hijaz on D (D Eb F# G A Bb C). Low and dark, then everyone."""
    s = Score(63, 4)
    chorale = "D3 2, Eb3 2 | F#3 2, G3 2 | A3 3, G3 1 | F#3 4 | G3 2, A3 2 | Bb3 2, A3 1, G3 1 | F#3 2, Eb3 2 | D3 4"
    chords = ["D Eb", "D Gm", "D", "D", "Gm D", "Gm Cm", "D Eb", "D"]
    # Bars 1-2: trembling low strings and distant voices on the bare fifth.
    for b in (1, 2):
        s.note("tremolo", s.bar(b), 3.95, pitch("D3"), 80)
        s.note("tremolo", s.bar(b), 3.95, pitch("A3"), 76)
        s.note("basses", s.bar(b), 3.95, pitch("D2"), 50)
        s.note("oohs", s.bar(b), 3.95, pitch("D4"), 48)
        s.note("oohs", s.bar(b), 3.95, pitch("A4"), 44)
    s.swell("tremolo", 0, 8, 60, 100)
    s.swell("oohs", 0, 8, 30, 85)
    roll(s, "timpani", s.bar(2), 4, pitch("D3"), 20, 60)
    # Bars 3-10: the chorale in the trombones, horns and strings in the harmony.
    p1 = s.progression(3, chords)
    s.line("trombones", 3, chorale, 78, accent=False)
    harmony(s, "horns", p1, 45, lo=53, hi=67, top=62)
    harmony(s, "strings", p1, 48, lo=55, hi=72, top=66)
    harmony(s, "oohs", p1, 46, lo=57, hi=72, top=69)
    bass(s, "basses", p1, 60, octave=1)
    bass(s, "celli", p1, 55, octave=2)
    for b in (3, 7):
        s.note("timpani", s.bar(b), 2, pitch("D3"), 60)
    # Bars 11-18: violins high, the choir opens, the horns take the chorale; the drums drive.
    p2 = s.progression(11, chords)
    s.line("violins", 11, chorale, 82, shift=24)
    s.line("horns", 11, chorale, 80, shift=12)
    harmony(s, "choir", p2, 70, lo=57, hi=76, top=69)
    harmony(s, "strings", p2, 60, lo=55, hi=74, top=66)
    s.line("trombones", 11, chorale, 70, accent=False)
    bass(s, "basses", p2, 72, octave=1)
    bass(s, "celli", p2, 70, octave=2)
    for b in range(11, 19):
        for q in range(4):
            s.note("timpani", s.bar(b) + q, 0.9, pitch("D3") if q % 2 == 0 else pitch("A2"), 50 + (b - 11) * 6 + (10 if q == 0 else 0))
    for part in ("violins", "choir", "strings", "horns"):
        s.swell(part, s.bar(11), s.bar(19), 70, 120)
    roll(s, DRUMS, s.bar(18), 4, SUSPENDED, 15, 70)
    # Bars 19-22: the climax; the first half of the chorale from everyone, ending on D major.
    p3 = s.progression(19, ["D Eb", "D Gm", "D", "D"])
    half = "D3 2, Eb3 2 | F#3 2, G3 2 | A3 3, G3 1 | F#3 4"
    s.line("violins", 19, half, 110, shift=24)
    s.line("horns", 19, half, 108, shift=12)
    s.line("trombones", 19, half, 104, accent=False)
    s.line("flute", 19, half, 86, shift=36)
    harmony(s, "brass", p3, 95, lo=55, hi=72, top=66)
    harmony(s, "choir", p3, 100, lo=57, hi=79, top=74)
    harmony(s, "strings", p3, 90, lo=55, hi=79, top=74)
    bass(s, "basses", p3, 100, octave=1)
    bass(s, "celli", p3, 96, octave=2)
    s.note(DRUMS, s.bar(19), 4, CRASH, 110)
    s.note(DRUMS, s.bar(19), 2, BASS_DRUM, 110)
    for b in range(19, 22):
        s.note("timpani", s.bar(b), 1, pitch("D3"), 100)
        s.note("timpani", s.bar(b) + 2, 1, pitch("A2"), 90)
    # Bars 23-24: the D major chord held, the timpani rolling away.
    end = s.progression(23, ["D", "D"])
    harmony(s, "choir", end, 95, lo=57, hi=79, top=74)
    harmony(s, "strings", end, 88, lo=55, hi=79, top=78)
    harmony(s, "horns", end, 90, lo=50, hi=67, top=62)
    bass(s, "basses", end, 95, octave=1)
    roll(s, "timpani", s.bar(22) + 2, 8, pitch("D3"), 100, 30)
    for part in ("choir", "strings", "horns", "basses", "brass", "violins"):
        s.swell(part, s.bar(23), s.bar(25), 120, 8)
    return s, s.bar(25) + 3


def empty_hall():
    """The Empty Hall: 4/4, E minor (Aeolian), slow and spare. A solo violin over a held low fifth,
    phrases with room between them; a horn answers; one short swell of the whole string body; then
    the solo again over the drone."""
    s = Score(56, 4)
    phrase_1 = "B4 2, A4 1, G4 1 | E4 3, r 1 | G4 1.5, A4 .5, B4 1, D5 1 | B4 3, r 1"
    phrase_2 = "E5 2, D5 1, B4 1 | C5 3, r 1 | B4 1, A4 1, G4 1, A4 1 | E4 4"
    # Bars 1-6: an open fifth (E, B) in the low strings, growing out of nothing; the violin enters.
    s.note("basses", 0, s.bar(7) - 0.1, pitch("E2"), 56)
    s.note("celli", 0, s.bar(7) - 0.1, pitch("B2"), 46)
    s.swell("basses", 0, 8, 40, 90)
    s.swell("celli", 0, 8, 40, 85)
    s.line("solo_violin", 3, phrase_1, 68)
    # Bars 7-10: the second phrase; a soft string chord under it, one per bar.
    p2 = s.progression(7, ["C", "C", "D", "Em"])
    s.line("solo_violin", 7, phrase_2, 72)
    harmony(s, "strings", p2, 40, lo=52, hi=67, top=64)
    bass(s, "basses", p2, 55, octave=2)
    s.swell("strings", s.bar(7), s.bar(8), 50, 85)
    # Bars 11-14: the violin rests; a horn answers low, one rolled harp chord.
    p3 = s.progression(11, ["Em", "Am", "D", "Em"])
    s.line("horns", 11, "B3 2, E4 2 | C4 3, B3 1 | A3 2, D4 2 | B3 4", 64)
    harmony(s, "strings", p3, 42, lo=52, hi=67, top=64)
    bass(s, "basses", p3, 55, octave=2)
    for i, p in enumerate((40, 47, 52, 55, 59, 64)):
        s.note("harp", s.bar(11) + i * 0.12, 4, p, 44)
    roll(s, "timpani", s.bar(14) + 2, 2, pitch("E3"), 25, 75)
    # Bars 15-18: the one swell: the violins take the first phrase, horns an octave under them.
    p4 = s.progression(15, ["Em", "C", "G", "Bm"])
    s.line("violins", 15, phrase_1, 108)
    s.line("horns", 15, phrase_1, 92, shift=-12)
    harmony(s, "strings", p4, 78, lo=52, hi=71, top=67)
    bass(s, "celli", p4, 86, octave=2)
    bass(s, "basses", p4, 86, octave=1)
    s.note("timpani", s.bar(15), 1, pitch("E3"), 100)
    for part in ("violins", "strings", "horns", "celli", "basses"):
        s.swell(part, s.bar(15), s.bar(16), 95, 127)
        s.swell(part, s.bar(17), s.bar(19), 127, 70)
    # Bars 19-22: back to the bare fifth and the solo violin, fading away.
    s.note("basses", s.bar(19), 15.8, pitch("E2"), 52)
    s.note("celli", s.bar(19), 15.8, pitch("B2"), 44)
    s.swell("basses", s.bar(19), s.bar(23), 80, 10)
    s.swell("celli", s.bar(19), s.bar(23), 80, 10)
    s.line("solo_violin", 19, "B4 2, A4 1, G4 1 | E4 4 | G4 2, F#4 2 | E4 4", 66)
    s.swell("solo_violin", s.bar(21), s.bar(23), 100, 40)
    return s, s.bar(23) + 3


def desert_psalm():
    """A Psalm in the Desert: 4/4, Hijaz on D, slow and spare. An English horn over a held D and
    distant voices; a solo violin answers higher with the choir rising softly under it; the English
    horn closes."""
    s = Score(52, 4)
    # Bars 1-6: a low D and A, voices far off; the English horn, then a bar of nothing but the drone.
    s.note("basses", 0, s.bar(11) - 0.1, pitch("D2"), 60)
    s.note("celli", 0, s.bar(7) - 0.1, pitch("A2"), 50)
    s.note("oohs", s.bar(2), s.bar(7) - s.bar(2) - 0.1, pitch("D4"), 42)
    s.swell("basses", 0, 8, 25, 95)
    s.swell("celli", 0, 8, 25, 90)
    s.swell("oohs", s.bar(2), s.bar(4), 30, 80)
    s.line("english_horn", 3, "A4 2, Bb4 1, A4 1 | G4 1, F#4 1, Eb4 2 | D4 3, r 1 | r 4", 72)
    # Bars 7-10: the second phrase, a soft string chord over the held D.
    p2 = s.progression(7, ["Gm/D", "D", "Cm/D", "D"])
    s.line("english_horn", 7, "D5 2, C5 1, Bb4 1 | A4 2, Bb4 1, G4 1 | F#4 1, G4 1, Eb4 1, F#4 1 | D4 4", 74)
    harmony(s, "strings", p2, 40, lo=55, hi=70, top=66)
    s.swell("strings", s.bar(7), s.bar(8), 50, 85)
    # Bars 11-14: a solo violin answers above; the choir and strings swell gently and fall back.
    p3 = s.progression(11, ["Gm/D", "Cm/D", "D", "D"])
    s.line("solo_violin", 11, "A5 2, G5 1, F#5 1 | G5 2, Eb5 2 | F#5 1, Eb5 1, D5 1, C5 1 | D5 4", 82)
    harmony(s, "choir", p3, 66, lo=57, hi=72, top=69)
    harmony(s, "strings", p3, 60, lo=55, hi=70, top=66)
    bass(s, "basses", p3, 60, octave=2)
    for part in ("choir", "strings"):
        s.swell(part, s.bar(11), s.bar(13), 60, 125)
        s.swell(part, s.bar(13), s.bar(15), 125, 60)
    for i, p in enumerate((50, 57, 62, 66, 69, 74)):
        s.note("harp", s.bar(14) + i * 0.12, 4, p, 40)
    # Bars 15-16: the English horn closes over the drone, and everything fades.
    s.note("basses", s.bar(15), 7.8, pitch("D2"), 55)
    s.note("celli", s.bar(15), 7.8, pitch("A2"), 46)
    s.line("english_horn", 15, "A4 1, G4 1, F#4 1, Eb4 1 | D4 4", 70)
    for part in ("basses", "celli", "english_horn"):
        s.swell(part, s.bar(15) + 2, s.bar(17), 95, 15)
    return s, s.bar(17) + 3


# ---------------------------------------------------------------- playing it

def volume(db):
    """CC 7 for a level in dB (TinySoundFont cubes the controller)."""
    return int(round(127 * 10 ** (db / 60.0)))


def render(score, length_beats, soundfont):
    import tinysoundfont
    synth = tinysoundfont.Synth(samplerate=SR, gain=-6)
    sfid = synth.sfload(soundfont)
    used = sorted({n[2] for n in score.notes if not isinstance(n[2], int)})
    channel = dict(zip(used, [c for c in range(16) if c != DRUMS]))
    assert len(channel) == len(used), "more than 15 instruments in one piece"
    for name, chan in channel.items():
        bank, program = INSTRUMENTS[name]
        synth.program_select(chan, sfid, bank, program)
        synth.control_change(chan, 10, PANS[name])
        synth.control_change(chan, 7, volume(LEVELS[name]))
        synth.control_change(chan, 11, 100)
    synth.program_select(DRUMS, sfid, 128, ORCHESTRA_KIT, True)
    synth.control_change(DRUMS, 7, volume(LEVELS["drums"]))
    rng = random.Random(7)
    events = []
    for beat, beats, part, p, vel in score.notes:
        chan = part if isinstance(part, int) else channel[part]
        t = score.seconds(beat) + rng.uniform(-0.008, 0.012)   # players are never quite together
        events.append((max(0.0, t), 1, chan, p, vel))
        events.append((max(0.0, t) + score.seconds(beats), 0, chan, p, 0))
    for beat, part, ctl, value in score.ccs:
        if not isinstance(part, int) and part not in channel:
            continue
        chan = part if isinstance(part, int) else channel[part]
        events.append((score.seconds(beat), 2, chan, ctl, value))
    events.sort(key=lambda e: (e[0], e[1]))
    total = int(score.seconds(length_beats) * SR)
    chunks = []
    done = 0
    for t, kind, chan, a, b in events:
        at = min(total, int(t * SR))
        if at > done:
            chunks.append(np.frombuffer(synth.generate(at - done), dtype=np.float32))
            done = at
        if kind == 1:
            synth.noteon(chan, a, b)
        elif kind == 0:
            synth.noteoff(chan, a)
        else:
            synth.control_change(chan, a, b)
    if total > done:
        chunks.append(np.frombuffer(synth.generate(total - done), dtype=np.float32))
    return np.concatenate(chunks).reshape(-1, 2).astype(np.float64)


def hall(stereo, seconds=3.4, decay=0.9, wet=0.3, seed=11):
    """A large hall: each side convolved with a darkening noise tail."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.empty_like(stereo)
    size = 1 << int(np.ceil(np.log2(len(stereo) + n)))
    for c in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / decay)
        ir = np.convolve(ir, np.ones(9) / 9.0, mode="same")   # duller as it goes
        ir[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
        ir /= np.sqrt(np.sum(ir ** 2))
        tail = np.fft.irfft(np.fft.rfft(stereo[:, c], size) * np.fft.rfft(ir, size), size)[: len(stereo)]
        out[:, c] = stereo[:, c] * (1.0 - wet) + tail * wet * 1.6
    return out


def write(stereo, path, peak):
    stereo = hall(stereo)
    fade = int(2.5 * SR)
    stereo[-fade:] *= np.linspace(1, 0, fade)[:, None]
    stereo *= peak / max(1e-9, np.max(np.abs(stereo)))
    pcm = (stereo * 32767).astype(np.int16)
    wav = path[:-4] + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.remove(wav)
    print("wrote %s  (%.0f s)" % (os.path.normpath(path), len(stereo) / SR))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    soundfont = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "assets", "music", "samples")
    os.makedirs(out, exist_ok=True)
    # The peak each is scaled to: the quiet evening piece sits lower than the big ones.
    pieces = (("orchestra_1_wilderness", wilderness, 0.84), ("orchestra_2_evening", evening, 0.6),
              ("orchestra_3_mountain", mountain, 0.84), ("orchestra_4_empty_hall", empty_hall, 0.8),
              ("orchestra_5_psalm", desert_psalm, 0.6))
    only = sys.argv[3:]   # names (or parts of names) to render just those pieces
    pieces = [x for x in pieces if not only or any(o in x[0] for o in only)]
    for name, piece, peak in pieces:
        score, length = piece()
        write(render(score, length, soundfont), os.path.join(out, name + ".ogg"), peak)
    return 0


if __name__ == "__main__":
    sys.exit(main())
