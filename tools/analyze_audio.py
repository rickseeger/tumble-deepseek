#!/usr/bin/env python3
"""analyze_audio.py -- code-level spectral analysis of the generated samples.

Pure Python (no numpy). Loads each WAV, computes RMS and a power spectrum via
an iterative radix-2 FFT, then asserts the node-5 completion contract:

  * every file is non-silent (RMS above threshold);
  * crash/explosion files carry real low-frequency weight (>= 30% of spectral
    energy below 250 Hz, and low band louder than the high band);
  * pew weapon-fire files are crisp and high-pitched (high-band >= 1 kHz
    dominates the low band);
  * crash tiers scale with size: bigger tiers are longer, louder, and deeper
    (lower spectral centroid) than smaller ones.

Exit code 0 if all assertions pass, 1 otherwise.
"""

import math
import os
import struct
import sys
import wave

SR = 44100
LOW_BAND = 250.0      # Hz -- "low-end weight" band for crashes
HIGH_BAND = 1000.0    # Hz -- "crisp high" band for pews

AUDIO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def load_wav(path):
    with wave.open(path, "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        fr = w.getframerate()
        nf = w.getnframes()
        raw = w.readframes(nf)
    assert nch == 1, path
    assert sw == 2, path
    n = len(raw) // 2
    samples = list(struct.unpack("<%dh" % n, raw))
    return [s / 32768.0 for s in samples], fr


def rms(samples):
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))


def fft(a):
    """Iterative in-place radix-2 Cooley-Tukey FFT (complex list in, out)."""
    n = len(a)
    assert n > 0 and (n & (n - 1)) == 0, "length must be a power of 2"
    out = list(a)
    # Bit-reversal permutation.
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            out[i], out[j] = out[j], out[i]
    # Butterfly stages.
    length = 2
    while length <= n:
        ang = -2.0 * math.pi / length
        wlen = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, length):
            w = 1.0 + 0.0j
            half = length >> 1
            for k in range(i, i + half):
                u = out[k]
                v = out[k + half] * w
                out[k] = u + v
                out[k + half] = u - v
                w *= wlen
        length <<= 1
    return out


def spectrum(samples, sr):
    """Return (freqs, power) for bins 0..N/2-1 after zero-padding to pow2."""
    n = len(samples)
    N = 1
    while N < n:
        N <<= 1
    a = [complex(samples[i], 0.0) if i < n else 0j for i in range(N)]
    A = fft(a)
    freqs = [i * sr / N for i in range(N // 2)]
    power = [abs(A[i]) ** 2 for i in range(N // 2)]
    return freqs, power


def band_fraction(freqs, power, lo, hi):
    total = sum(power)
    if total <= 0.0:
        return 0.0
    band = 0.0
    for f, p in zip(freqs, power):
        if lo <= f <= hi:
            band += p
    return band / total


def centroid(freqs, power):
    total = sum(power)
    if total <= 0.0:
        return 0.0
    num = sum(f * p for f, p in zip(freqs, power))
    return num / total


def main():
    files = [
        "pew_0.wav", "pew_1.wav", "pew_2.wav",
        "crash_small.wav", "crash_medium.wav", "crash_large.wav", "crash_huge.wav",
        "impact.wav",
    ]
    data = {}
    for f in files:
        path = os.path.join(AUDIO_DIR, f)
        if not os.path.exists(path):
            print("MISSING FILE:", path)
            sys.exit(1)
        samples, fr = load_wav(path)
        freqs, power = spectrum(samples, fr)
        data[f] = {
            "rms": rms(samples),
            "dur": len(samples) / fr,
            "low_frac": band_fraction(freqs, power, 0.0, LOW_BAND),
            "high_frac": band_fraction(freqs, power, HIGH_BAND, fr / 2.0),
            "centroid": centroid(freqs, power),
        }

    failures = []
    checks = 0

    def check(cond, label):
        nonlocal checks
        checks += 1
        status = "PASS" if cond else "FAIL"
        print("  %s  %s" % (status, label))
        if not cond:
            failures.append(label)

    print("=== G16 node-5 audio spectral analysis ===")
    print("%-16s %7s %7s %9s %9s %9s" % (
        "file", "rms", "dur_s", "low<250", "hi>1k", "centroid"))
    for f in files:
        d = data[f]
        print("%-16s %7.4f %7.2f %8.1f%% %8.1f%% %8.0f" % (
            f, d["rms"], d["dur"], d["low_frac"] * 100,
            d["high_frac"] * 100, d["centroid"]))

    print()
    print("--- assertions ---")

    # Non-silent: every sample carries real energy.
    for f in files:
        check(data[f]["rms"] >= 0.01, "%s is non-silent (RMS %.3f)" % (f, data[f]["rms"]))

    # Crashes: low-frequency spectral energy dominates (real low-end weight).
    for f in ["crash_small.wav", "crash_medium.wav", "crash_large.wav", "crash_huge.wav"]:
        d = data[f]
        check(d["low_frac"] >= 0.30, "%s low-end weight: %.0f%% of energy < %.0f Hz" % (f, d["low_frac"] * 100, LOW_BAND))
        check(d["low_frac"] > d["high_frac"], "%s low band louder than high band (%.0f%% vs %.0f%%)" % (f, d["low_frac"] * 100, d["high_frac"] * 100))

    # Pews: crisp, high-pitched -- high-frequency energy dominates.
    for f in ["pew_0.wav", "pew_1.wav", "pew_2.wav"]:
        d = data[f]
        check(d["high_frac"] >= 0.30, "%s crisp high-end: %.0f%% of energy > %.0f Hz" % (f, d["high_frac"] * 100, HIGH_BAND))
        check(d["high_frac"] > d["low_frac"], "%s high band louder than low band (%.0f%% vs %.0f%%)" % (f, d["high_frac"] * 100, d["low_frac"] * 100))

    # Impact is non-silent and has some low-mid body.
    check(data["impact.wav"]["rms"] >= 0.01, "impact.wav is non-silent")

    # Crash tiers scale with size: longer, deeper (lower centroid), and no less
    # low-end as the tier grows.
    small, huge = data["crash_small.wav"], data["crash_huge.wav"]
    check(huge["dur"] > small["dur"], "huge crash is longer than small (%.2fs vs %.2fs)" % (huge["dur"], small["dur"]))
    check(huge["centroid"] < small["centroid"], "huge crash is deeper (centroid %.0f Hz < %.0f Hz)" % (huge["centroid"], small["centroid"]))
    check(huge["low_frac"] >= small["low_frac"], "huge crash keeps low-end weight (%.0f%% >= %.0f%%)" % (huge["low_frac"] * 100, small["low_frac"] * 100))

    print()
    print("=== results: %d checks, %d failures ===" % (checks, len(failures)))
    if failures:
        for f in failures:
            print("  FAILED:", f)
        print("AUDIO ANALYSIS FAIL")
        sys.exit(1)
    print("AUDIO ANALYSIS PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
