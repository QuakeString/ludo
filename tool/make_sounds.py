#!/usr/bin/env python3
"""Synthesises the game's sound effects.

Three of the four. The dice roll is a recording — see prepare_dice.py, and the
note there about why synthesising that one kept coming out wrong.

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


# --- a chip landing ----------------------------------------------------------
# A plastic peg set down on a printed board: duller and shorter than the die,
# with no long ring at all.
def chip_step():
    """A plastic peg set down on a printed board.

    The first attempt was low-passed almost to a thud and lasted a sixth of a
    second, which is a sound you can play a hundred times without anyone
    noticing it is there. A piece meeting a board has a bright edge to it, so
    the top end stays and the peg is allowed to ring for a moment.
    """
    rnd = random.Random(3)
    n = int(0.22 * SR)
    modes = [
        (1240, 0.55, 70),
        (2010, 0.40, 88),
        (3150, 0.24, 110),
        (4600, 0.12, 150),
        (214, 0.34, 34),
    ]
    out = strike(n, modes, 0.55, 1200, 620, rnd)
    return one_pole_lp(out, 9000)


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
    # dice_roll.wav is not made here — prepare_dice.py builds it from the
    # recording, and regenerating it from this script would overwrite that.
    write("chip_step.wav", chip_step())
    write("chip_home.wav", chip_home())
    write("capture.wav", capture())
