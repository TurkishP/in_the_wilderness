"""Makes the sounds of the dust wind: three looping beds of wind, each with its own character.

    python tools/make_sounds.py          (needs numpy, and ffmpeg on the PATH)

Writes assets/sounds/wind_1.ogg (a low, moaning wind), wind_2.ogg (a gusty hiss) and wind_3.ogg
(sand rattling over the ground under a steady blow). Each loops without a seam: its end is
faded into its start. The game picks one for each gust and varies its pitch and loudness.
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
SECONDS = 24.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def band(rng, n, lo, hi, tilt=0.0):
    """Noise kept between lo and hi Hz, with soft edges; tilt < 0 darkens it."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR) + 1.0
    gain = 1.0 / (1.0 + (lo / f) ** 4) / (1.0 + (f / hi) ** 4) * (f / 1000.0) ** tilt
    out = np.fft.irfft(spec * gain, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def swell(rng, n, rate, depth):
    """A slow, uneven rise and fall: summed slow sines at loop-friendly rates."""
    t = np.arange(n) / SR
    out = np.ones(n)
    for k in range(4):
        cycles = max(1, int(round(rate * SECONDS * (k + 1) * rng.uniform(0.7, 1.3))))
        out += depth / (k + 1) * np.sin(2 * np.pi * cycles / SECONDS * t + rng.uniform(0, 6.3))
    return np.clip(out, 0.05, None)


def moan(rng, n):
    """Wind round rocks: dark noise, and a few faint whistles that slide in pitch."""
    base = band(rng, n, 60.0, 700.0, -0.6) * swell(rng, n, 0.12, 0.6)
    t = np.arange(n) / SR
    for f0 in (310.0, 470.0):
        drift = 1.0 + 0.08 * np.sin(2 * np.pi * round(SECONDS * 0.07) / SECONDS * t + rng.uniform(0, 6.3))
        tone = np.sin(2 * np.pi * np.cumsum(f0 * drift) / SR)
        reed = band(rng, n, f0 * 0.9, f0 * 1.1) * 0.6 + tone * 0.4
        base += reed * 0.12 * swell(rng, n, 0.2, 0.9) ** 2
    return base


def hiss(rng, n):
    """Gusts: bright noise that surges and drops."""
    gusts = swell(rng, n, 0.3, 1.0) ** 2
    return band(rng, n, 400.0, 6000.0, 0.2) * gusts + band(rng, n, 80.0, 500.0, -0.5) * 0.4 * gusts


def rattle(rng, n):
    """Sand grains ticking over the ground, under a steady low blow."""
    blow = band(rng, n, 80.0, 900.0, -0.4) * swell(rng, n, 0.1, 0.4) * 0.7
    ticks = np.zeros(n)
    count = int(SECONDS * 900)
    where = rng.integers(0, n - 200, count)
    loud = rng.uniform(0.2, 1.0, count) ** 3
    for i, a in zip(where, loud):
        ticks[i] += a * (1 if rng.random() < 0.5 else -1)
    grains = np.convolve(ticks, np.exp(-np.arange(60) / 8.0), mode="same")
    grains = band_filter(grains, 2500.0, 9000.0)
    return blow + grains * 0.5 * swell(rng, n, 0.25, 0.8)


def band_filter(x, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR) + 1.0
    gain = 1.0 / (1.0 + (lo / f) ** 4) / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * gain, len(x))


def loop(x, fade_seconds=2.0):
    """Fades the end into the start, so the sound loops without a seam."""
    k = int(fade_seconds * SR)
    ramp = np.linspace(0.0, 1.0, k)
    out = x[: len(x) - k].copy()
    out[:k] = x[:k] * ramp + x[len(x) - k:] * (1.0 - ramp)
    return out


def write(rng, mono, path):
    left = loop(mono)
    right = loop(np.roll(mono, int(0.013 * SR)) * 0.9 + band(rng, len(mono), 200.0, 4000.0) * 0.05)
    stereo = np.stack([left, right], axis=1)
    stereo *= 0.6 / np.max(np.abs(stereo))
    pcm = (stereo * 32767).astype(np.int16)
    wav = path[:-4] + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", path], check=True)
    os.remove(wav)
    print("wrote %s" % os.path.normpath(path))


def main():
    os.makedirs(OUT, exist_ok=True)
    n = int(SECONDS * SR)
    for name, make, seed in (("wind_1", moan, 41), ("wind_2", hiss, 42), ("wind_3", rattle, 43)):
        rng = np.random.default_rng(seed)
        write(rng, make(rng, n), os.path.join(OUT, name + ".ogg"))


if __name__ == "__main__":
    sys.exit(main())
