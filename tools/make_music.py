"""Makes the background music: two calm pieces in the manner of Middle Eastern music, played on
an oud-like plucked string, a breathy ney flute, a low drone and a soft frame drum.

    python tools/make_music.py          (needs numpy, and ffmpeg on the PATH)

Writes assets/music/wilderness_1.ogg (maqam Hijaz) and wilderness_2.ogg (maqam Bayati, with its
quarter-tone second). Everything is synthesised here, so the music is the project's own. The
melodies are built from short phrases typical of each maqam; a fixed seed makes the result the
same every time.
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "music")

# Semitones above the tonic of each step of the scale (7 steps to the octave).
HIJAZ = [0, 1, 4, 5, 7, 8, 10]      # D Eb F# G A Bb C
BAYATI = [0, 1.5, 3, 5, 7, 8, 10]   # D E-half-flat F G A Bb C
D3 = 146.83


def freq(scale, step, base=D3):
    octave, within = divmod(step, 7)
    return base * 2.0 ** ((scale[within] + 12 * octave) / 12.0)


class Mix:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.l = np.zeros(self.n)
        self.r = np.zeros(self.n)

    def add(self, sound, at, gain=1.0, pan=0.0):
        """Adds a mono sound at `at` seconds, panned -1 (left) .. 1 (right)."""
        i = int(at * SR)
        if i >= self.n:
            return
        sound = sound[: self.n - i] * gain
        a = (pan + 1.0) * np.pi / 4.0
        self.l[i:i + len(sound)] += sound * np.cos(a)
        self.r[i:i + len(sound)] += sound * np.sin(a)


def shaped_noise(rng, n, centers, width=0.25, hiss=0.0):
    """White noise kept only near the given frequencies (Gaussian bands, width in octaves)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR) + 1e-3
    gainf = np.zeros_like(f)
    for c, g in centers:
        gainf += g * np.exp(-0.5 * (np.log2(f / c) / width) ** 2)
    gainf += hiss * np.clip((f - 2000.0) / 6000.0, 0.0, 1.0)
    out = np.fft.irfft(spec * gainf, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def oud(rng, f, ring=2.2, vel=1.0):
    """One pluck: decaying partials, the upper ones dying first, on a doubled string."""
    n = int(ring * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for detune, level in ((1.0, 1.0), (1.0017, 0.55)):
        for k in range(1, 16):
            fk = f * detune * k * (1.0 + 0.0003 * k * k)
            if fk > 9000.0:
                break
            amp = abs(np.sin(np.pi * k * 0.17)) / k ** 1.05
            tau = 1.5 / (1.0 + 0.55 * (k - 1))
            out += level * amp * np.sin(2 * np.pi * fk * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t / tau)
    click = rng.standard_normal(int(0.006 * SR)) * np.linspace(1, 0, int(0.006 * SR))
    out[: len(click)] += click * 0.25
    fade = np.ones(n)
    fade[-int(0.3 * SR):] = np.linspace(1, 0, int(0.3 * SR))
    return out * fade * vel * 0.22


def ney(rng, f, dur, vel=1.0):
    """A breathy flute note with a slow swell and vibrato that comes in late."""
    n = int((dur + 0.45) * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.0045 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.4) / 0.5, 0, 1)
    scoop = 1.0 - 0.012 * np.exp(-t / 0.05)
    phase = 2 * np.pi * np.cumsum(f * vib * scoop) / SR
    tone = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.07 * np.sin(3 * phase) + 0.03 * np.sin(4 * phase)
    breath = shaped_noise(rng, n, [(f, 1.0), (2 * f, 0.5), (3 * f, 0.2)], 0.12, hiss=0.15)
    env = np.clip(t / 0.16, 0, 1) ** 1.5 * (1.0 + 0.12 * np.clip(t / max(dur, 0.1), 0, 1))
    env *= np.clip((dur + 0.45 - t) / 0.45, 0, 1)
    return (tone * 0.7 + breath * 0.45) * env * vel * 0.16


def drone(rng, f, seconds):
    """A low, slowly breathing drone."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 11):
        lfo = 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(0.03, 0.09) * t + rng.uniform(0, 6.3))
        out += lfo * np.sin(2 * np.pi * f * k * (1 + rng.uniform(-0.0006, 0.0006)) * t) / k ** 1.3
    return out * 0.05


def dum(rng, vel=1.0):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = 62.0 + 48.0 * np.exp(-t / 0.04)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.2)
    thump = shaped_noise(rng, n, [(180.0, 1.0)], 0.6) * np.exp(-t / 0.02)
    return (body + thump * 0.3) * vel * 0.5


def tek(rng, vel=1.0):
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    snap = shaped_noise(rng, n, [(3500.0, 1.0), (1200.0, 0.4)], 0.5) * np.exp(-t / 0.025)
    skin = np.sin(2 * np.pi * 480.0 * t) * np.exp(-t / 0.05)
    return (snap + skin * 0.25) * vel * 0.3


def reverb(rng, x, seconds=2.8, decay=0.6):
    """A hall: convolution with a decaying noise burst that darkens as it fades."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / decay)
    ir = np.convolve(ir, np.ones(5) / 5.0, mode="same")
    ir[0] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]


def play_phrase(mix, rng, scale, phrase, at, beat, voice, octave=0, vel=1.0, pan=0.0, rubato=0.0):
    """Plays a phrase of (step, beats) pairs from `at`; returns when it ends."""
    t = at
    for step, beats in phrase:
        dur = beats * beat * (1.0 + rng.uniform(-rubato, rubato))
        f = freq(scale, step + 7 * octave)
        if voice == "ney":
            mix.add(ney(rng, f, dur, vel * rng.uniform(0.9, 1.05)), t, 1.0, pan)
        else:
            mix.add(oud(rng, f, vel=vel * rng.uniform(0.85, 1.05)), t, 1.0, pan)
            if dur >= 1.6 * beat:
                # Long notes on the oud are tremolo: quick repeated strokes of the plectrum.
                k = 0.12
                while k < dur - 0.15:
                    mix.add(oud(rng, f, ring=0.5, vel=vel * 0.45 * (1.0 - 0.3 * k / dur)), t + k)
                    k += 0.11
        t += dur
    return t


def ostinato(mix, rng, scale, at, bars, beat, vel=0.7):
    """The oud keeps time low down: tonic and fifth."""
    for b in range(bars):
        t0 = at + b * 4 * beat
        for when, step, v in ((0.0, -7, 0.8), (1.5, -3, 0.45), (2.0, -7, 0.6), (3.0, -4 if b % 2 else -3, 0.4)):
            mix.add(oud(rng, freq(scale, step), vel=v * vel), t0 + when * beat, 1.0, -0.25)


def drums(mix, rng, at, bars, beat, vel=0.4, sparse=False):
    """A slow, soft frame drum: dum on the beat, tek between."""
    for b in range(bars):
        t0 = at + b * 4 * beat
        fade = vel * min(1.0, (bars - b) / 3.0)
        if sparse:
            if b % 2 == 0:
                mix.add(dum(rng, fade), t0, 1.0, 0.15)
            continue
        mix.add(dum(rng, fade), t0, 1.0, 0.15)
        mix.add(tek(rng, fade * 0.45), t0 + 1.5 * beat, 1.0, 0.2)
        mix.add(dum(rng, fade * 0.7), t0 + 2.0 * beat, 1.0, 0.15)
        mix.add(tek(rng, fade * 0.6), t0 + 3.0 * beat, 1.0, 0.2)
        mix.add(tek(rng, fade * 0.3), t0 + 3.5 * beat, 1.0, 0.2)


def sequence(mix, rng, scale, phrases, at, beat, voice, octave, vel, pan, rest=1.0, rubato=0.03):
    t = at
    for p in phrases:
        t = play_phrase(mix, rng, scale, p, t, beat, voice, octave, vel, pan, rubato) + rest * beat
    return t


def hijaz(rng):
    beat = 60.0 / 64.0
    m = {
        1: [(0, 1), (1, .5), (2, 1.5), (1, .5), (0, 2.5)],
        2: [(3, 1), (2, .5), (1, .5), (2, 1), (1, .5), (0, 2.5)],
        3: [(4, 1.5), (5, .5), (4, .5), (3, .5), (2, 1), (3, 2)],
        4: [(2, .5), (3, .5), (4, 1), (5, 1), (6, .5), (5, .5), (4, 2)],
        5: [(7, 1.5), (6, .5), (5, 1), (4, 1), (3, .5), (2, .5), (1, 1), (0, 3)],
        6: [(0, 1), (-1, .5), (0, .5), (1, 1), (2, .5), (1, .5), (0, 2)],
        7: [(4, 2), (3, 1), (2, 1), (3, .5), (4, .5), (3, 2)],
    }
    mix = Mix(172.0)
    mix.add(drone(rng, D3 / 2, 172.0), 0.0, 1.0, -0.1)
    mix.add(drone(rng, freq(HIJAZ, 4) / 2, 172.0), 0.0, 0.6, 0.1)
    # A free opening on the oud (taqsim).
    t = sequence(mix, rng, HIJAZ, [m[6], m[1], m[2]], 3.0, beat * 1.15, "oud", 0, 0.9, 0.1, rest=1.5, rubato=0.18)
    # The ney sings over the drum and the oud.
    start = t + beat
    end = sequence(mix, rng, HIJAZ, [m[1], m[2], m[3], m[7], m[4], m[5], m[1], m[2]], start, beat, "ney", 1, 1.0, 0.15)
    # The oud takes the tune for a while; then the ney returns, and the drum fades away.
    end = sequence(mix, rng, HIJAZ, [m[3], m[4], m[5]], end + beat, beat, "oud", 1, 0.85, 0.1, rubato=0.02)
    end = sequence(mix, rng, HIJAZ, [m[7], m[4], m[5], m[1]], end + beat, beat, "ney", 1, 1.0, 0.15)
    bars = int(np.ceil((end - start) / (4 * beat)))
    ostinato(mix, rng, HIJAZ, start, bars, beat)
    drums(mix, rng, start, bars, beat)
    t = sequence(mix, rng, HIJAZ, [m[2]], start + bars * 4 * beat + beat, beat * 1.2, "oud", 0, 0.9, 0.1, rubato=0.15)
    mix.add(oud(rng, D3 / 2, ring=4.0, vel=0.9), t + 0.5)
    return mix, t + 6.0


def bayati(rng):
    beat = 60.0 / 56.0
    m = {
        1: [(0, 1), (1, 1), (2, 1.5), (1, .5), (0, 2)],
        2: [(3, 1.5), (2, .5), (1, 1), (2, .5), (1, .5), (0, 2)],
        3: [(2, 1), (3, 1), (4, 2), (3, 1), (2, 1), (3, 2)],
        4: [(4, 1), (5, .5), (4, .5), (3, 1), (2, .5), (1, .5), (2, 1), (1, .5), (0, 2.5)],
        5: [(7, 2), (6, 1), (5, 1), (4, 2), (3, 1), (2, 1), (1, 1), (0, 3)],
        6: [(-1, 1), (0, 1), (1, .5), (2, .5), (1, 1), (0, 2)],
    }
    mix = Mix(170.0)
    mix.add(drone(rng, D3 / 2, 170.0), 0.0, 1.0, -0.1)
    mix.add(drone(rng, freq(BAYATI, 4) / 2, 170.0), 0.0, 0.5, 0.1)
    # The ney alone first, unhurried.
    t = sequence(mix, rng, BAYATI, [m[1], m[2]], 4.0, beat * 1.2, "ney", 1, 0.95, 0.1, rest=2.0, rubato=0.15)
    start = t + beat
    end = sequence(mix, rng, BAYATI, [m[3], m[4], m[6], m[2], m[3], m[5]], start, beat, "ney", 1, 1.0, 0.15, rest=2.0)
    bars = int(np.ceil((end - start) / (4 * beat)))
    for b in range(bars):
        # Slow broken chords on the oud: tonic, fifth, octave, fifth.
        t0 = start + b * 4 * beat
        for when, step, v in ((0.0, -7, 0.7), (1.0, -3, 0.45), (2.0, 0, 0.5), (3.0, -3, 0.4)):
            mix.add(oud(rng, freq(BAYATI, step), vel=v), t0 + when * beat, 1.0, -0.3)
    drums(mix, rng, start, bars, beat, vel=0.35, sparse=True)
    t = sequence(mix, rng, BAYATI, [m[1]], start + bars * 4 * beat + beat, beat * 1.2, "oud", 0, 0.9, 0.1, rubato=0.15)
    mix.add(oud(rng, D3 / 2, ring=4.0, vel=0.9), t + 0.4)
    return mix, t + 6.0


def finish(rng, mix, length, path):
    n = min(mix.n, int(length * SR))
    out = []
    for ch in (mix.l[:n], mix.r[:n]):
        wet = reverb(rng, ch)
        out.append(ch * 0.78 + wet * 0.42)
    stereo = np.stack(out, axis=1)
    fade_in = int(4.0 * SR)
    fade_out = int(7.0 * SR)
    stereo[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    stereo[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None] ** 1.5
    stereo *= 0.7 / np.max(np.abs(stereo))
    pcm = (stereo * 32767).astype(np.int16)
    wav = path[:-4] + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.remove(wav)
    print("wrote %s  (%.0f s)" % (os.path.normpath(path), n / SR))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, piece, seed in (("wilderness_1", hijaz, 1522), ("wilderness_2", bayati, 1601)):
        rng = np.random.default_rng(seed)
        mix, length = piece(rng)
        finish(rng, mix, length, os.path.join(OUT, name + ".ogg"))


if __name__ == "__main__":
    sys.exit(main())
