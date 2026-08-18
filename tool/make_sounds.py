#!/usr/bin/env python3
"""Synthesises the game's sound effects.

Committed as a script rather than four opaque .wav files: a sound you cannot
regenerate is a sound nobody can adjust. Run it from the repository root.

    python3 tool/make_sounds.py

Everything here is built from scratch — noise bursts, decaying sine modes and
envelopes. Nothing is sampled or taken from another game; the style is meant
to sit where a board game's sounds usually sit (hard little clacks, a bright
arrival, a blunt knock), but every waveform is generated below.
"""

import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path("app/assets/sounds")


def one_pole_lp(x, cutoff):
    a = math.exp(-2 * math.pi * cutoff / SR)
    y, prev = [0.0] * len(x), 0.0
    for i, v in enumerate(x):
        prev = (1 - a) * v + a * prev
        y[i] = prev
    return y


def one_pole_hp(x, cutoff):
    lp = one_pole_lp(x, cutoff)
    return [v - l for v, l in zip(x, lp)]


def strike(n, modes, noise_amp, noise_cut, noise_decay, rnd):
    """One impact: a click of filtered noise, then the body ringing.

    A struck object makes both — the click is the contact, the ringing is the
    material. Only the click and you get a tap on nothing; only the ringing
    and you get a bell.
    """
    burst = [rnd.uniform(-1, 1) * math.exp(-i / SR * noise_decay) for i in range(n)]
    burst = one_pole_hp(burst, noise_cut)
    out = [noise_amp * v for v in burst]
    for freq, amp, decay in modes:
        phase = rnd.uniform(0, 2 * math.pi)
        w = 2 * math.pi * freq / SR
        for i in range(n):
            out[i] += amp * math.sin(w * i + phase) * math.exp(-i / SR * decay)
    return out


def mix(buf, sound, at, gain=1.0):
    start = int(at * SR)
    for i, v in enumerate(sound):
        j = start + i
        if 0 <= j < len(buf):
            buf[j] += v * gain


def write(name, buf, peak=0.86, fade=0.02):
    tail = int(fade * SR)
    for i in range(tail):
        buf[len(buf) - tail + i] *= 1 - i / tail
    high = max(1e-9, max(abs(v) for v in buf))
    scale = peak / high
    frames = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(v * scale * 32767))))
        for v in buf
    )
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"{name}: {len(buf) / SR:.2f}s, {len(frames)} bytes")


# --- the die -----------------------------------------------------------------
# An acrylic cube on a wooden board. The cube's own modes are high and die
# away fast; the board answers with a low thump that lasts a little longer.
def die_clack(rnd, pitch=1.0, wood=1.0):
    n = int(0.20 * SR)
    modes = [
        (2050 * pitch, 0.55, 62),
        (3260 * pitch, 0.38, 78),
        (4720 * pitch, 0.24, 96),
        (6350 * pitch, 0.13, 120),
        (238 * (0.9 + 0.2 * pitch), 0.34 * wood, 26),
        (392 * (0.9 + 0.2 * pitch), 0.18 * wood, 33),
    ]
    return strike(n, modes, 0.5, 1600, 520, rnd)


def dice_roll():
    """Shaken, thrown, bouncing, settling.

    The timing carries most of it: bounces come closer together and quieter as
    the die loses energy, the way a dropped thing actually behaves. Evenly
    spaced clacks sound like a machine.
    """
    rnd = random.Random(11)
    buf = [0.0] * int(0.95 * SR)

    # Two soft knocks in the hand before the throw.
    for at, gain in ((0.00, 0.30), (0.075, 0.24)):
        mix(buf, die_clack(rnd, pitch=1.06, wood=0.4), at, gain)

    # The throw, then the bounces.
    t, gap, gain = 0.20, 0.115, 1.0
    for k in range(9):
        mix(buf, die_clack(rnd, pitch=1.0 + rnd.uniform(-0.07, 0.07)), t, gain)
        t += gap * rnd.uniform(0.86, 1.14)
        gap *= 0.80
        gain *= 0.80

    # And the last, quietest tip onto its face.
    mix(buf, die_clack(rnd, pitch=0.95, wood=1.4), t + 0.06, 0.16)
    return buf


# --- a chip landing ----------------------------------------------------------
# A plastic peg set down on a printed board: duller and shorter than the die,
# with no long ring at all.
def chip_step():
    rnd = random.Random(3)
    n = int(0.16 * SR)
    modes = [
        (860, 0.5, 95),
        (1490, 0.32, 120),
        (2380, 0.16, 150),
        (196, 0.30, 40),
    ]
    out = strike(n, modes, 0.42, 900, 700, rnd)
    return one_pole_lp(out, 5200)


# --- reaching home -----------------------------------------------------------
def chip_home():
    """Two notes going up, struck like small bells.

    Arriving is the one good thing that happens to a chip, so this is the only
    sound in the game with a pitch you could hum.
    """
    rnd = random.Random(5)
    n = int(0.85 * SR)
    buf = [0.0] * n

    def bell(freq, amp, decay):
        out = [0.0] * n
        # Slightly stretched partials, which is what stops it sounding like an
        # organ and starts it sounding struck.
        for ratio, level, extra in ((1.0, 1.0, 1.0), (2.02, 0.42, 1.5), (3.05, 0.2, 2.1)):
            w = 2 * math.pi * freq * ratio / SR
            for i in range(n):
                out[i] += level * math.sin(w * i) * math.exp(-i / SR * decay * extra)
        # A breath of noise on the attack, for the strike itself.
        for i in range(int(0.01 * SR)):
            out[i] += rnd.uniform(-1, 1) * 0.25 * math.exp(-i / SR * 900)
        return [v * amp for v in out]

    mix(buf, bell(784.0, 0.85, 4.6), 0.0)  # G5
    mix(buf, bell(1174.7, 0.7, 4.2), 0.115)  # D6, a fifth above
    return buf


# --- a capture ---------------------------------------------------------------
def capture():
    """A blunt knock and something sliding away.

    Lower and softer-edged than the die so it never reads as a roll, and the
    downward sweep is the chip going back where it came from.
    """
    rnd = random.Random(9)
    n = int(0.55 * SR)
    modes = [
        (147, 0.85, 17),
        (233, 0.5, 24),
        (585, 0.3, 48),
        (1180, 0.18, 70),
    ]
    buf = strike(n, modes, 0.55, 500, 380, rnd)

    # A short falling tone, swept by hand so the pitch really does bend.
    phase, f0, f1 = 0.0, 520.0, 130.0
    for i in range(int(0.34 * SR)):
        t = i / (0.34 * SR)
        f = f0 * (f1 / f0) ** t
        phase += 2 * math.pi * f / SR
        env = math.sin(math.pi * min(1.0, t * 1.05)) * math.exp(-t * 1.6)
        buf[i + int(0.02 * SR)] += 0.42 * math.sin(phase) * env

    # And air moving past it.
    hiss = [rnd.uniform(-1, 1) for _ in range(n)]
    hiss = one_pole_lp(hiss, 2600)
    for i in range(n):
        t = i / n
        buf[i] += 0.22 * hiss[i] * math.sin(math.pi * min(1.0, t * 2.2)) * math.exp(-t * 3.4)
    return buf


if __name__ == "__main__":
    write("dice_roll.wav", dice_roll())
    write("chip_step.wav", chip_step())
    write("chip_home.wav", chip_home())
    write("capture.wav", capture())
