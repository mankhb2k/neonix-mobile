#!/usr/bin/env python3
"""Synthesizes the starter sound-effect set (20 effects, 5 categories) with the standard library only.

    python3 scripts/generate_sfx.py            # writes public/preview/sounds/<category>/<id>.m4a + sounds.json
    python3 scripts/generate_sfx.py --wav      # also keeps the 16-bit WAVs next to them

Every sound is made from sines, pulse waves and filtered noise (nothing sampled, nothing licensed), mono 44.1 kHz,
loudness-matched to one RMS level (a short peaky sound stays under it, held by the peak ceiling), then encoded to AAC with `afconvert` (macOS).
These are stand-ins in the spirit of `SoundEffectCatalog.swift`: good for UI / transition / game / cartoon cues; real
recordings (applause, camera, nature) would need a licensed pack.
"""
import json
import math
import random
import subprocess
import sys
import wave
from pathlib import Path

SR = 44100
TAU = 2 * math.pi
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "public/preview/sounds"


# ---------- building blocks ----------

def n_samples(seconds):
    return int(seconds * SR)


def noise(seconds, rng):
    return [rng.uniform(-1, 1) for _ in range(n_samples(seconds))]


def env_exp(i, decay):
    """exp(-t / decay) at sample i."""
    return math.exp(-i / SR / decay)


def sweep_phase(freq_at, count):
    """Phase accumulator for a time-varying frequency; returns sin(phase) samples."""
    phase, out = 0.0, []
    for i in range(count):
        phase += TAU * freq_at(i / SR) / SR
        out.append(math.sin(phase))
    return out


def svf_bandpass(x, center_at, q):
    """State-variable band-pass with a moving centre frequency (Chamberlin form)."""
    low = band = 0.0
    out = []
    damp = 1.0 / q
    for i, s in enumerate(x):
        f = 2 * math.sin(math.pi * min(center_at(i / SR), SR / 6.5) / SR)
        low += f * band
        high = s - low - damp * band
        band += f * high
        out.append(band)
    return out


def lowpass(x, cutoff):
    a = 1 - math.exp(-TAU * cutoff / SR)
    y, out = 0.0, []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [s - l for s, l in zip(x, lp)]


def mix(*tracks):
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def place(track, at_seconds, length):
    """`track` starting `at_seconds` into a silent buffer of `length` seconds."""
    out = [0.0] * n_samples(length)
    start = n_samples(at_seconds)
    for i, s in enumerate(track):
        if start + i < len(out):
            out[start + i] += s
    return out


def shaped(x, fn):
    return [s * fn(i / SR) for i, s in enumerate(x)]


def bell(freq, seconds, decay, partials=((1, 1.0), (2.0, 0.35), (3.01, 0.15))):
    """A struck-bell note: a few decaying sine partials."""
    out = [0.0] * n_samples(seconds)
    for ratio, amp in partials:
        for i in range(len(out)):
            t = i / SR
            out[i] += amp * math.sin(TAU * freq * ratio * t) * math.exp(-t / (decay / ratio ** 0.5))
    return out


def pulse(freq, seconds, duty=0.5, decay=None):
    out = []
    for i in range(n_samples(seconds)):
        t = i / SR
        v = 1.0 if (t * freq) % 1.0 < duty else -1.0
        out.append((v - (2 * duty - 1)) * (math.exp(-t / decay) if decay else 1.0))   # minus the wave's DC (duty != 0.5)
    return out


def reverse(x):
    return x[::-1]


# ---------- the 20 effects ----------

def whoosh_soft(rng):
    d = 0.75
    x = svf_bandpass(noise(d, rng), lambda t: 350 + 2400 * math.sin(math.pi * t / d) ** 1.5, 1.4)
    return shaped(x, lambda t: math.sin(math.pi * t / d) ** 2)


def whoosh_fast(rng):
    d = 0.4
    x = svf_bandpass(noise(d, rng), lambda t: 600 + 5200 * (t / d) ** 1.6, 2.2)
    return shaped(x, lambda t: math.sin(math.pi * min(t / d, 1) ** 0.7) ** 2)


def riser(rng):
    d = 2.0
    n = svf_bandpass(noise(d, rng), lambda t: 250 * math.exp(math.log(24) * t / d), 3.0)
    tone = sweep_phase(lambda t: 180 * math.exp(math.log(9) * t / d), n_samples(d))
    x = [a * 1.0 + b * 0.35 for a, b in zip(n, tone)]
    return shaped(x, lambda t: (t / d) ** 2.2)


def reverse_sweep(rng):
    d = 1.1
    x = svf_bandpass(noise(d, rng), lambda t: 6500 * math.exp(-t * 2.6) + 500, 1.8)
    x = shaped(x, lambda t: math.exp(-t / 0.45))
    return shaped(reverse(x), lambda t: min(t / 0.02, 1.0))


def pop(rng):
    body = sweep_phase(lambda t: 150 + 520 * math.exp(-t / 0.018), n_samples(0.18))
    body = shaped(body, lambda t: math.exp(-t / 0.045))
    tick = shaped(highpass(noise(0.02, rng), 2500), lambda t: math.exp(-t / 0.004))
    return mix(body, [s * 0.4 for s in tick])


def click(rng):
    tick = shaped(highpass(noise(0.05, rng), 1800), lambda t: math.exp(-t / 0.006))
    tone = shaped(sweep_phase(lambda t: 2600, n_samples(0.05)), lambda t: math.exp(-t / 0.007))
    return mix(tick, [s * 0.6 for s in tone])


def notification(rng):
    a = bell(1175, 0.9, 0.35)
    b = place(bell(1568, 0.75, 0.38), 0.14, 0.9)
    return mix(a, b)


def success(rng):
    notes = [523.25, 659.25, 783.99, 1046.5]
    return mix(*[place(bell(f, 1.0, 0.45), 0.11 * i, 1.2) for i, f in enumerate(notes)])


def error(rng):
    def buzz(seconds):
        raw = [((i / SR * 140) % 1.0) * 2 - 1 for i in range(n_samples(seconds))]   # saw at 140 Hz
        return shaped(lowpass(raw, 900), lambda t: min(t / 0.005, 1.0) * min((seconds - t) / 0.015, 1.0))
    return mix(buzz(0.16), place(buzz(0.16), 0.22, 0.4))


def boom(rng):
    d = 2.2
    sub = shaped(sweep_phase(lambda t: 34 + 70 * math.exp(-t / 0.12), n_samples(d)), lambda t: math.exp(-t / 0.7))
    thump = shaped(lowpass(noise(d, rng), 220), lambda t: math.exp(-t / 0.25))
    crack = shaped(highpass(noise(0.1, rng), 1200), lambda t: math.exp(-t / 0.015))
    return mix(sub, [s * 1.6 for s in thump], [s * 0.35 for s in crack])


def punch(rng):
    body = shaped(sweep_phase(lambda t: 55 + 110 * math.exp(-t / 0.03), n_samples(0.3)), lambda t: math.exp(-t / 0.07))
    slap = shaped(lowpass(noise(0.1, rng), 1800), lambda t: math.exp(-t / 0.018))
    return mix(body, [s * 0.9 for s in slap])


def kick(rng):
    body = shaped(sweep_phase(lambda t: 48 + 130 * math.exp(-t / 0.035), n_samples(0.45)), lambda t: math.exp(-t / 0.13))
    click_ = shaped(highpass(noise(0.015, rng), 3000), lambda t: math.exp(-t / 0.003))
    return mix(body, [s * 0.3 for s in click_])


def boing(rng):
    d = 0.9
    def freq(t):
        return 210 + 380 * math.exp(-t / 0.22) * (0.55 + 0.45 * math.cos(TAU * 9 * t))
    f1 = sweep_phase(freq, n_samples(d))
    f2 = sweep_phase(lambda t: freq(t) * 2.01, n_samples(d))
    x = [a + 0.3 * b for a, b in zip(f1, f2)]
    return shaped(x, lambda t: min(t / 0.004, 1.0) * math.exp(-t / 0.32))


def _slide(rng, lo, hi, d):
    ratio = hi / lo
    def freq(t):
        base = lo * ratio ** (t / d)
        return base * (1 + 0.025 * math.sin(TAU * 6 * t))
    a = sweep_phase(freq, n_samples(d))
    b = sweep_phase(lambda t: freq(t) * 2, n_samples(d))
    x = [p + 0.15 * q for p, q in zip(a, b)]
    return shaped(x, lambda t: min(t / 0.03, 1.0) * min((d - t) / 0.06, 1.0))


def slide_up(rng):
    return _slide(rng, 420, 2300, 0.85)


def slide_down(rng):
    return _slide(rng, 2300, 320, 0.85)


def bonk(rng):
    x = mix(*[
        shaped(sweep_phase(lambda t, r=r: (420 * math.exp(-t / 0.05) + 260) * r, n_samples(0.3)), lambda t, a=a, k=k: a * math.exp(-t / k))
        for r, a, k in ((1.0, 1.0, 0.07), (2.76, 0.45, 0.04), (5.4, 0.2, 0.02))
    ])
    tick = shaped(highpass(noise(0.01, rng), 2000), lambda t: math.exp(-t / 0.002))
    return mix(x, [s * 0.3 for s in tick])


def coin(rng):
    first = shaped(pulse(988, 0.07, 0.5), lambda t: min(t / 0.002, 1.0) * min((0.07 - t) / 0.01, 1.0))
    second = shaped(pulse(1319, 0.4, 0.5), lambda t: min(t / 0.002, 1.0) * math.exp(-t / 0.13))
    return mix(first, place(second, 0.07, 0.5))


def power_up(rng):
    steps = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0]
    parts = [place(shaped(pulse(f, 0.09, 0.25), lambda t: min(t / 0.002, 1.0) * min((0.09 - t) / 0.01, 1.0)), 0.07 * i, 0.9)
             for i, f in enumerate(steps)]
    ring = place(shaped(pulse(2093, 0.4, 0.25), lambda t: math.exp(-t / 0.12)), 0.07 * len(steps), 0.9)
    return mix(*parts, [s * 0.8 for s in ring])


def laser(rng):
    d = 0.4
    saw_phase, x = 0.0, []
    for i in range(n_samples(d)):
        t = i / SR
        saw_phase += 2800 * math.exp(-t / 0.09) / SR + 150 / SR
        x.append(((saw_phase % 1.0) * 2 - 1) * 0.6 + math.sin(TAU * saw_phase) * 0.4)
    return shaped(x, lambda t: min(t / 0.002, 1.0) * math.exp(-t / 0.11))


def sparkle(rng):
    d = 1.3
    parts = []
    for _ in range(26):
        at = (rng.random() ** 1.7) * 0.95
        f = rng.choice([2093, 2349, 2637, 3136, 3520, 4186, 5274])
        amp = rng.uniform(0.35, 1.0) * (1 - at / 1.4)
        parts.append(place([s * amp for s in bell(f, 0.35, 0.09, partials=((1, 1.0), (2.0, 0.2)))], at, d))
    return mix(*parts)


# id, title, category, builder
SOUNDS = [
    ("whoosh-soft", "Whoosh Soft", "transitions", whoosh_soft),
    ("whoosh-fast", "Whoosh Fast", "transitions", whoosh_fast),
    ("riser", "Riser", "transitions", riser),
    ("reverse-sweep", "Reverse Sweep", "transitions", reverse_sweep),
    ("pop", "Pop", "ui", pop),
    ("click", "Click", "ui", click),
    ("notification", "Notification", "ui", notification),
    ("success", "Success", "ui", success),
    ("error", "Error", "ui", error),
    ("boom", "Boom", "impacts", boom),
    ("punch", "Punch", "impacts", punch),
    ("kick", "Kick Drum", "impacts", kick),
    ("boing", "Boing", "fun", boing),
    ("slide-up", "Slide Whistle Up", "fun", slide_up),
    ("slide-down", "Slide Whistle Down", "fun", slide_down),
    ("bonk", "Bonk", "fun", bonk),
    ("coin", "Coin", "game", coin),
    ("power-up", "Power Up", "game", power_up),
    ("laser", "Laser", "game", laser),
    ("sparkle", "Sparkle", "game", sparkle),
]
CATEGORIES = [("transitions", "Transitions"), ("ui", "UI"), ("impacts", "Impacts"), ("fun", "Fun"), ("game", "Game & Magic")]


TARGET_RMS_DB = -13.0   # every sound is brought to this RMS ...
PEAK_CEILING = 0.89     # ... unless that would push its peak past -1 dBFS (clicks, laser: peaky, so they stay quieter)


def finish(x):
    """Fade the ends (no clicks), soft-clip, then scale to `TARGET_RMS_DB` under the peak ceiling."""
    fade_in, fade_out = n_samples(0.002), n_samples(0.012)
    n = len(x)
    for i in range(min(fade_in, n)):
        x[i] *= i / fade_in
    for i in range(min(fade_out, n)):
        x[n - 1 - i] *= i / fade_out
    x = [math.tanh(s * 1.1) for s in x]
    mean = sum(x) / n
    x = [s - mean for s in x]   # no DC offset (pulse waves have some, and the soft clip adds more)
    rms = math.sqrt(sum(s * s for s in x) / n) or 1.0
    peak = max(abs(s) for s in x) or 1.0
    scale = min(10 ** (TARGET_RMS_DB / 20) / rms, PEAK_CEILING / peak)
    return [s * scale for s in x]


PEAK_BARS = 48


def peaks(x, bars=PEAK_BARS):
    """Loudness per slice (0...1), for the picker's mini waveform: each slice's peak against the loudest slice, lifted by ^0.6 like the timeline's waveform."""
    size = len(x) / bars
    raw = [max(abs(s) for s in x[int(i * size):max(int((i + 1) * size), int(i * size) + 1)]) for i in range(bars)]
    top = max(raw) or 1.0
    return [round((v / top) ** 0.6, 2) for v in raw]


def write_wav(path, x):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(int(max(-1, min(1, s)) * 32767).to_bytes(2, "little", signed=True) for s in x))


def main():
    keep_wav = "--wav" in sys.argv
    manifest = {"version": 1, "categories": [{"id": c, "title": t} for c, t in CATEGORIES], "sounds": []}
    for sid, title, category, build in SOUNDS:
        samples = finish(build(random.Random(sid)))
        folder = OUT / category
        folder.mkdir(parents=True, exist_ok=True)
        wav, m4a = folder / f"{sid}.wav", folder / f"{sid}.m4a"
        write_wav(wav, samples)
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", str(wav), str(m4a)], check=True)
        if not keep_wav:
            wav.unlink()
        manifest["sounds"].append({"id": f"sfx-{sid}", "name": title, "category": category, "file": f"sounds/{category}/{sid}.m4a",
                                   "durationMs": round(len(samples) / SR * 1000), "peaks": peaks(samples)})
        print(f"{sid:14s} {len(samples) / SR:5.2f} s")
    (OUT / "sounds.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
