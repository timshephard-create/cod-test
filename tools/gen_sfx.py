#!/usr/bin/env python3
"""Generate every sound effect for the project procedurally (no recorded samples).

All output is 44.1 kHz, 16-bit mono WAV written to assets/sfx/.  Every sound is
synthesised from noise, sines and envelopes, so the whole set is original and
free of any third-party licence.  Run:  python3 tools/gen_sfx.py
"""
import math
import os
import struct
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")
rng = np.random.default_rng(1337)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env_exp(dur, decay, attack=0.0):
    x = t(dur)
    e = np.exp(-x / decay)
    if attack > 0:
        e *= np.clip(x / attack, 0, 1)
    return e


def noise(dur):
    return rng.standard_normal(int(SR * dur))


def lowpass(x, cutoff):
    """One-pole lowpass with a (possibly time-varying) cutoff in Hz."""
    y = np.zeros_like(x)
    cut = np.broadcast_to(cutoff, x.shape)
    a = np.exp(-2.0 * math.pi * cut / SR)
    acc = 0.0
    for i in range(len(x)):
        acc = a[i] * acc + (1.0 - a[i]) * x[i]
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def sine(freq, dur, phase=0.0):
    x = t(dur)
    f = np.broadcast_to(freq, x.shape)
    ph = 2 * math.pi * np.cumsum(f) / SR + phase
    return np.sin(ph)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write(name, data):
    data = normalize(data)
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", path, f"{len(pcm) / SR:.2f}s")


# --- Gunshots -----------------------------------------------------------------

def gunshot(dur, crack_cut, thump_f0, thump_f1, thump_decay, body_decay, tail_decay, drive):
    x = t(dur)
    # Supersonic crack: very short bright transient.
    crack = highpass(noise(dur), 1500) * env_exp(dur, 0.006)
    # Muzzle blast body: band-limited noise with a cutoff that sweeps down.
    cut = crack_cut * np.exp(-x / body_decay) + 300
    body = lowpass(noise(dur), cut) * env_exp(dur, body_decay) * 3.0
    # Low thump: pitch-dropping sine.
    f = thump_f0 * np.exp(-x / 0.03) + thump_f1
    thump = sine(f, dur) * env_exp(dur, thump_decay) * 1.6
    # Room tail: darker noise with long decay.
    tail = lowpass(noise(dur), 900) * env_exp(dur, tail_decay, attack=0.01) * 0.9
    s = mix(crack * 1.2, body, thump, tail)
    return soft_clip(s, drive)


write("rifle_shot", gunshot(0.42, 6000, 220, 55, 0.07, 0.045, 0.16, 1.6))
write("pistol_shot", gunshot(0.30, 7500, 300, 80, 0.045, 0.03, 0.10, 1.4))
# Distant/softer variant used for the reverb "slapback" layer.
write("shot_tail", lowpass(noise(0.6), 700) * env_exp(0.6, 0.18, attack=0.02))


# --- Feedback ticks -----------------------------------------------------------

def tick(freq, dur, decay, harm=0.0):
    s = sine(freq, dur) + harm * sine(freq * 2.01, dur)
    return s * env_exp(dur, decay)


# Hitmarker: the iconic double "tik-tik" — two short bright clicks.
hm = np.zeros(int(SR * 0.16))
a = tick(2600, 0.06, 0.012, 0.4)
b = tick(2600, 0.06, 0.012, 0.4)
hm[: len(a)] += a
off = int(SR * 0.055)
hm[off : off + len(b)] += b * 0.85
hm += highpass(noise(0.16), 4000) * env_exp(0.16, 0.004) * 0.3
write("hitmarker", hm)

# Headshot: higher, ringier ping with a little shimmer.
hs = mix(tick(3400, 0.22, 0.05, 0.3), tick(5100, 0.22, 0.03) * 0.5, tick(6800, 0.22, 0.02) * 0.25)
write("headshot", hs)

# Kill confirm: low thud + bright tick together.
kill = mix(sine(180 * np.exp(-t(0.25) / 0.05) + 70, 0.25) * env_exp(0.25, 0.09), tick(3000, 0.12, 0.02) * 0.8)
write("kill", kill)

# --- Mechanical ----------------------------------------------------------------

def clack(dur, cut, decay, low=0.0):
    s = lowpass(noise(dur), cut) * env_exp(dur, decay)
    if low:
        s += sine(low, dur) * env_exp(dur, decay * 0.8) * 0.5
    return s


write("mag_out", mix(clack(0.12, 3000, 0.02, 160), clack(0.12, 1200, 0.05) * 0.4))
mi = np.zeros(int(SR * 0.2))
c1 = clack(0.1, 2500, 0.015, 140)
c2 = clack(0.12, 4000, 0.02, 220)
mi[: len(c1)] += c1
mi[int(SR * 0.06) : int(SR * 0.06) + len(c2)] += c2 * 1.1
write("mag_in", mi)
bolt = np.zeros(int(SR * 0.22))
b1 = clack(0.1, 5000, 0.01, 300)
b2 = clack(0.1, 3500, 0.018, 200)
bolt[: len(b1)] += b1
bolt[int(SR * 0.09) : int(SR * 0.09) + len(b2)] += b2 * 1.2
write("bolt", bolt)
write("dry_fire", clack(0.08, 4500, 0.008, 400))
write("swap", mix(clack(0.18, 1800, 0.05), lowpass(noise(0.18), 600) * env_exp(0.18, 0.08) * 0.6))

# Target falling over: metallic clank with ring.
clank = mix(
    tick(820, 0.35, 0.08, 0.6),
    tick(1370, 0.35, 0.05, 0.4) * 0.6,
    tick(2210, 0.35, 0.03) * 0.3,
    clack(0.1, 2500, 0.02) * 0.8,
)
write("target_fall", clank)
write("target_up", mix(clack(0.12, 1500, 0.03, 120), tick(600, 0.2, 0.04) * 0.3))

# Bullet impact on concrete / metal.
write("impact", mix(clack(0.08, 3500, 0.012), lowpass(noise(0.08), 500) * env_exp(0.08, 0.02) * 0.6))

# Footsteps: soft thud.
write("footstep", mix(lowpass(noise(0.12), 400) * env_exp(0.12, 0.03), clack(0.05, 2000, 0.006) * 0.3))

# Course cues.
write("start", mix(tick(880, 0.15, 0.08), np.concatenate([np.zeros(int(SR * 0.18)), tick(1320, 0.3, 0.12)])))
fin = np.zeros(int(SR * 0.9))
for i, f in enumerate([660, 880, 1100, 1320]):
    s = tick(f, 0.3, 0.1, 0.3)
    o = int(SR * 0.15 * i)
    fin[o : o + len(s)] += s
write("finish", fin)
write("countdown", tick(1000, 0.12, 0.04))
