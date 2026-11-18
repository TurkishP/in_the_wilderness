"""Makes the game's short sound effects: swings, blows landing, the sling and the bow, landing
from a jump, things picked up, the smith's hammer and the clicks of the menus.

    python tools/make_effects.py          (needs numpy)

Writes mono .wav files into assets/sounds/, several takes of each (swing_1.wav, swing_2.wav ...)
so the game can vary them; it also shifts the pitch a little each time it plays one
(Game.play_sound). Everything is synthesized here from noise and decaying tones: nothing is
recorded. After running it, let Godot import the new files once:

    godot --headless --path . --import
"""
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def band(rng, n, lo, hi, tilt=0.0):
    """Noise kept between lo and hi Hz, with soft edges; tilt < 0 darkens it."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR) + 1.0
    gain = 1.0 / (1.0 + (lo / f) ** 4) / (1.0 + (f / hi) ** 4) * (f / 1000.0) ** tilt
    out = np.fft.irfft(spec * gain, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def bump(n, peak, sharp=2.0):
    """Rises to 1 at `peak` (0..1 of the way through) and falls away again."""
    t = np.linspace(0.0, 1.0, n)
    up = np.clip(t / max(peak, 1e-3), 0.0, 1.0)
    down = np.clip((1.0 - t) / max(1.0 - peak, 1e-3), 0.0, 1.0)
    return (np.sin(up * np.pi / 2) * np.sin(down * np.pi / 2)) ** sharp


def decay(n, tau, attack=0.002):
    t = np.arange(n) / SR
    return np.minimum(t / attack, 1.0) * np.exp(-t / tau)


def whoosh(rng, seconds, low, high, peak=0.55):
    """Something swept through the air: noise whose pitch rises to the middle and falls."""
    n = int(seconds * SR)
    out = np.zeros(n)
    steps = 7
    for k in range(steps):
        where = k / (steps - 1.0)
        centre = low * (high / low) ** (1.0 - abs(where - peak) / max(peak, 1.0 - peak))
        t = np.linspace(0.0, 1.0, n)
        window = np.exp(-((t - where) / 0.16) ** 2)
        out += band(rng, n, centre * 0.7, centre * 1.4) * window
    return out * bump(n, peak, 1.5)


def thump(seconds, start, end, tau):
    """A dull blow: a low tone that drops in pitch as it dies."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    freq = end + (start - end) * np.exp(-t / (tau * 0.5))
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * decay(n, tau)


def ring(rng, seconds, partials):
    """Struck metal or wood: tones that are not in tune with each other, each dying at its own
    rate. partials: (Hz, seconds to die, loudness)."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for freq, tau, amp in partials:
        out += amp * np.sin(2 * np.pi * freq * t + rng.uniform(0, 6.3)) * decay(n, tau, 0.0006)
    return out


def slap(rng, seconds, lo, hi, tau):
    n = int(seconds * SR)
    return band(rng, n, lo, hi) * decay(n, tau, 0.001)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def late(x, seconds):
    return np.concatenate([np.zeros(int(seconds * SR)), x])


# ---------------------------------------------------------------- the sounds

def swing(rng, heavy):
    if heavy:
        return whoosh(rng, rng.uniform(0.36, 0.42), 180.0, rng.uniform(900.0, 1200.0)) * 0.9
    return whoosh(rng, rng.uniform(0.24, 0.3), 350.0, rng.uniform(2200.0, 3200.0))


def hit_flesh(rng):
    return mix(thump(0.22, rng.uniform(150, 190), 60.0, 0.05), slap(rng, 0.12, 300.0, 2500.0, 0.02) * 0.6,
        slap(rng, 0.2, 80.0, 500.0, 0.05) * 0.5)


def hit_blade(rng):
    base = rng.uniform(1700.0, 2300.0)
    metal = ring(rng, 0.45, [(base, 0.09, 1.0), (base * 1.47, 0.07, 0.7), (base * 2.09, 0.05, 0.5), (base * 2.83, 0.035, 0.35), (base * 3.6, 0.02, 0.25)])
    return mix(metal * 0.55, thump(0.2, 170.0, 70.0, 0.045) * 0.9, slap(rng, 0.1, 1500.0, 7000.0, 0.012) * 0.5)


def hit_wood(rng):
    base = rng.uniform(420.0, 560.0)
    wood = ring(rng, 0.25, [(base, 0.035, 1.0), (base * 1.9, 0.025, 0.6), (base * 2.7, 0.018, 0.4), (base * 4.1, 0.01, 0.25)])
    return mix(wood * 0.8, thump(0.2, 140.0, 65.0, 0.05), slap(rng, 0.08, 500.0, 4000.0, 0.012) * 0.4)


def punch(rng):
    return mix(thump(0.18, rng.uniform(170, 210), 80.0, 0.035), slap(rng, 0.09, 400.0, 3000.0, 0.014) * 0.8)


def hurt(rng):
    """A blow taken: a heavy body thud with the rustle of cloth."""
    return mix(thump(0.3, 120.0, 45.0, 0.08), slap(rng, 0.25, 150.0, 1200.0, 0.06) * 0.5, late(slap(rng, 0.2, 1500.0, 6000.0, 0.05) * 0.15, 0.03))


def sling_throw(rng):
    return mix(whoosh(rng, 0.22, 500.0, 3800.0, 0.35), late(slap(rng, 0.06, 1500.0, 8000.0, 0.008) * 0.8, 0.06))


def bow_twang(rng):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    freq = 150.0 + 70.0 * np.exp(-t / 0.03)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    string = (np.sin(phase) + 0.5 * np.sin(2 * phase) + 0.3 * np.sin(3 * phase) + 0.2 * np.sin(5 * phase)) * decay(n, 0.09, 0.0005)
    return mix(string * 0.8, slap(rng, 0.05, 1200.0, 6000.0, 0.008) * 0.7, late(whoosh(rng, 0.25, 800.0, 4500.0, 0.2) * 0.5, 0.01))


def thock(rng):
    """A stone or an arrow striking home."""
    return mix(thump(0.15, 220.0, 90.0, 0.03), ring(rng, 0.12, [(rng.uniform(700, 900), 0.02, 1.0), (1900.0, 0.01, 0.4)]) * 0.5, slap(rng, 0.06, 800.0, 5000.0, 0.01) * 0.5)


def land(rng):
    """Feet coming down on sand: a soft thump and the hiss of grit."""
    return mix(thump(0.25, 110.0, 45.0, 0.06), slap(rng, 0.3, 1500.0, 7000.0, 0.07) * 0.35, late(slap(rng, 0.2, 2500.0, 9000.0, 0.06) * 0.15, 0.05))


def fall(rng):
    """A body going down."""
    return mix(thump(0.4, 95.0, 38.0, 0.11), slap(rng, 0.35, 200.0, 2000.0, 0.09) * 0.5, late(land(rng) * 0.5, 0.12))


def coin(rng):
    a = rng.uniform(3900.0, 4500.0)
    one = ring(rng, 0.3, [(a, 0.08, 1.0), (a * 1.51, 0.05, 0.6), (a * 2.26, 0.03, 0.35)])
    two = ring(rng, 0.3, [(a * 1.12, 0.09, 1.0), (a * 1.7, 0.05, 0.6), (a * 2.5, 0.03, 0.3)])
    return mix(one * 0.7, late(two * 0.8, 0.07))


def find(rng):
    """Something worth having: three soft rising notes."""
    out = np.zeros(1)
    for i, f in enumerate((523.25, 659.25, 783.99)):
        note = ring(rng, 0.7, [(f, 0.22, 1.0), (f * 2.0, 0.12, 0.35), (f * 3.01, 0.06, 0.15)])
        out = mix(out, late(note, 0.09 * i))
    return out


def anvil(rng):
    """The smith's hammer on bronze: a hard strike and a long bright ring."""
    base = rng.uniform(1250.0, 1400.0)
    bell = ring(rng, 1.3, [(base, 0.5, 1.0), (base * 1.63, 0.38, 0.7), (base * 2.41, 0.25, 0.5), (base * 3.37, 0.14, 0.35), (base * 4.9, 0.08, 0.2)])
    return mix(bell * 0.6, thump(0.15, 260.0, 120.0, 0.03) * 0.8, slap(rng, 0.05, 2000.0, 9000.0, 0.006) * 0.7)


def click(rng):
    return mix(ring(rng, 0.06, [(1900.0, 0.012, 1.0), (3100.0, 0.007, 0.5)]), slap(rng, 0.03, 2000.0, 8000.0, 0.004) * 0.5)


def page(rng):
    """A menu opening: a short soft sweep, like cloth drawn aside."""
    return whoosh(rng, 0.2, 700.0, 2600.0, 0.4) * 0.8


SOUNDS = [
    # name, how many takes, maker, loudness
    ("swing", 3, lambda r: swing(r, False), 0.7),
    ("swing_heavy", 2, lambda r: swing(r, True), 0.8),
    ("hit_flesh", 3, hit_flesh, 0.9),
    ("hit_blade", 3, hit_blade, 0.9),
    ("hit_wood", 2, hit_wood, 0.9),
    ("punch", 2, punch, 0.85),
    ("hurt", 2, hurt, 0.9),
    ("sling_throw", 2, sling_throw, 0.7),
    ("bow_twang", 2, bow_twang, 0.8),
    ("thock", 2, thock, 0.8),
    ("land", 2, land, 0.8),
    ("fall", 2, fall, 0.85),
    ("coin", 2, coin, 0.5),
    ("find", 1, find, 0.55),
    ("anvil", 2, anvil, 0.75),
    ("click", 1, click, 0.4),
    ("page", 1, page, 0.5),
]


def write(mono, path, loudness):
    mono = mono / (np.max(np.abs(mono)) + 1e-9) * loudness
    tail = min(len(mono), int(0.01 * SR))
    mono[-tail:] *= np.linspace(1.0, 0.0, tail)      # no click at the end
    pcm = (mono * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for i, (name, takes, make, loudness) in enumerate(SOUNDS):
        for take in range(takes):
            rng = np.random.default_rng(1000 + i * 10 + take)
            write(make(rng), os.path.join(OUT, "%s_%d.wav" % (name, take + 1)), loudness)
            count += 1
    print("wrote %d sounds to %s" % (count, os.path.normpath(OUT)))


if __name__ == "__main__":
    sys.exit(main())
