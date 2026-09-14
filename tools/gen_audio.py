#!/usr/bin/env python3
"""gen_audio.py -- deterministic procedural synthesis of G16 node-5 audio.

Generates, into ./audio (relative to the repo root), a family of 16-bit mono
44.1 kHz WAV files:

  * pew_0/1/2.wav   -- crisp, high-pitched "pew-pew" laser fire (3 variants).
  * crash_small/medium/large/huge.wav -- rumbly, resonant destruction
    crash/explosion sounds with real low-end weight, scaled by structure size.
  * impact.wav      -- a short single-debris impact (lighter than any crash).

Everything is deterministic for a fixed seed, so regenerating reproduces the
exact same samples. Pure Python standard library only (wave/struct/math/random).
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def write_wav(path, samples):
    """Write a list of float samples in [-1, 1] as 16-bit mono PCM WAV."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Clip defensively, then convert to 16-bit signed little-endian.
    pcm = bytearray()
    for s in samples:
        s = max(-1.0, min(1.0, s))
        v = int(round(s * 32767.0))
        pcm += struct.pack("<h", v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(pcm))


def normalize(samples, peak):
    m = max(abs(s) for s in samples) or 1.0
    return [s / m * peak for s in samples]


def env_exp(n, tau, attack=0.001):
    """Exponential-decay envelope with a short linear attack."""
    a = max(int(attack * SR), 1)
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            t = (i - a) / SR
            out.append(math.exp(-t / tau))
    return out


def lowpass_1p(x, alpha):
    """First-order IIR low-pass (y[n] = y[n-1] + alpha * (x[n] - y[n-1]))."""
    y = [0.0] * len(x)
    prev = 0.0
    for i, s in enumerate(x):
        prev += alpha * (s - prev)
        y[i] = prev
    return y


def synth_pew(rng, f_start, f_end, dur, brightness):
    """A crisp laser 'pew': saw/square down-chirp plus a noise 'zap' transient."""
    n = int(dur * SR)
    samples = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        # Exponential downward chirp from f_start to f_end.
        f = f_start * ((f_end / f_start) ** (t / dur))
        phase += 2.0 * math.pi * f / SR
        p = (phase % (2.0 * math.pi)) / (2.0 * math.pi)  # 0..1
        saw = 2.0 * p - 1.0
        sq = 1.0 if p < 0.5 else -1.0
        samples[i] = brightness * saw + (1.0 - brightness) * sq

    # Crisp noise 'zap' at the very start (high-frequency energy).
    zap = int(0.016 * SR)
    for i in range(min(zap, n)):
        fade = 1.0 - (i / zap)
        samples[i] += 0.7 * rng.uniform(-1.0, 1.0) * fade

    env = env_exp(n, dur * 0.38, attack=0.002)
    for i in range(n):
        samples[i] *= env[i]
    return normalize(samples, 0.85)


def synth_crash(rng, dur, sub_freq, sub_gain, res_freqs, impact_amp, body_alpha, body_gain):
    """A rumbly, resonant destruction crash/explosion.

    Layers:
      1. sub-bass rumble   -- detuned sines at sub_freq (the 'real low end').
      2. resonance body    -- decaying sine partials at resonant frequencies.
      3. low-passed noise  -- a rumbly, broadband body texture.
      4. impact transient  -- a short broadband 'crack' on the initial hit.
    """
    n = int(dur * SR)
    out = [0.0] * n

    # 1. Sub-bass rumble (two slightly detuned sines for a beating low end).
    for detune in (1.0, 1.006):
        f = sub_freq * detune
        phase = rng.uniform(0.0, 2.0 * math.pi)
        env = env_exp(n, dur * 0.5, attack=0.004)
        for i in range(n):
            phase += 2.0 * math.pi * f / SR
            out[i] += sub_gain * math.sin(phase) * env[i]

    # 2. Resonance partials (decaying 'ringing' of the structure).
    for rf in res_freqs:
        phase = rng.uniform(0.0, 2.0 * math.pi)
        tau = dur * (0.28 if rf > 220.0 else 0.48)
        for i in range(n):
            t = i / SR
            phase += 2.0 * math.pi * rf / SR
            out[i] += 0.42 * math.sin(phase) * math.exp(-t / tau)

    # 3. Low-passed noise body (the rumbly texture under the resonance).
    noise_sig = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    lp = lowpass_1p(noise_sig, body_alpha)
    env_body = env_exp(n, dur * 0.34, attack=0.001)
    for i in range(n):
        out[i] += body_gain * lp[i] * env_body[i]

    # 4. Impact transient ('crack' of the initial hit).
    trans = int(0.05 * SR)
    for i in range(min(trans, n)):
        fade = 1.0 - (i / trans)
        out[i] += impact_amp * rng.uniform(-1.0, 1.0) * fade

    return normalize(out, 0.85)


def synth_impact(rng):
    """A short single-debris impact: low thump + brief noise crack."""
    dur = 0.35
    n = int(dur * SR)
    out = [0.0] * n

    # Low thump.
    phase = rng.uniform(0.0, 2.0 * math.pi)
    env = env_exp(n, 0.12, attack=0.002)
    for i in range(n):
        phase += 2.0 * math.pi * 90.0 / SR
        out[i] += 0.9 * math.sin(phase) * env[i]

    # Brief noise crack.
    crack = int(0.04 * SR)
    for i in range(min(crack, n)):
        fade = 1.0 - (i / crack)
        out[i] += 0.6 * rng.uniform(-1.0, 1.0) * fade

    return normalize(out, 0.8)


def main():
    # --- Pew variants (crisp, high-pitched) ---
    pew_specs = [
        (2000.0, 520.0, 0.12, 0.62, 101),
        (1750.0, 460.0, 0.11, 0.66, 102),
        (2250.0, 600.0, 0.13, 0.58, 103),
    ]
    for idx, (fs, fe, dur, br, seed) in enumerate(pew_specs):
        rng = random.Random(seed)
        samples = synth_pew(rng, fs, fe, dur, br)
        write_wav(os.path.join(OUT_DIR, "pew_%d.wav" % idx), samples)

    # --- Crash tiers (low-end weight and length scale with size) ---
    crash_specs = [
        ("small",  0.60, 70.0, 0.60, [140.0, 210.0], 0.60, 0.060, 0.45, 201),
        ("medium", 1.10, 55.0, 0.80, [110.0, 165.0, 250.0], 0.80, 0.045, 0.55, 202),
        ("large",  1.70, 45.0, 1.00, [90.0, 135.0, 200.0, 280.0], 1.00, 0.035, 0.65, 203),
        ("huge",   2.40, 38.0, 1.20, [75.0, 110.0, 160.0, 220.0, 300.0], 1.20, 0.028, 0.75, 204),
    ]
    for name, dur, sub, sg, res, imp, ba, bg, seed in crash_specs:
        rng = random.Random(seed)
        samples = synth_crash(rng, dur, sub, sg, res, imp, ba, bg)
        write_wav(os.path.join(OUT_DIR, "crash_%s.wav" % name), samples)

    # --- Single-debris impact ---
    rng = random.Random(301)
    write_wav(os.path.join(OUT_DIR, "impact.wav"), synth_impact(rng))

    print("Wrote audio files to", os.path.abspath(OUT_DIR))
    for f in sorted(os.listdir(OUT_DIR)):
        print("  ", f)


if __name__ == "__main__":
    main()
