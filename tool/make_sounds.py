#!/usr/bin/env python3
"""Synthesises the game's sound effects.

Two of the five. The dice roll and the chip landing both come out of a
recording — see prepare_dice.py — because they have to sound like the same die
on the same table, and a synthesised tap beside a recorded throw was audibly a
different material in a different room.

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


def strike_sound(n, modes, noise_amp, noise_cut, noise_decay, rnd):
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
    """A snake striking.

    Three parts in a tenth of a second, and the order is the whole thing: a
    hiss that rises as the head comes forward, the snap of the strike landing,
    and then a hiss falling away as it draws back.

    What makes it read as a bite rather than a hit is that the noise sweeps
    *upward* into the snap. A rising band tightening over sixty milliseconds is
    heard as something coming at you; the same noise falling is heard as
    something leaving. The snap itself is dry and doubled — jaws are two hard
    surfaces meeting a moment apart, and one clean click sounds like a switch.
    """
    rnd = random.Random(31)
    n = int(0.52 * SR)
    out = [0.0] * n
    strike = int(0.085 * SR)

    # The lunge: noise through a resonator climbing from 700Hz to 3.4kHz, and
    # getting louder the whole way in.
    y1 = y2 = 0.0
    for i in range(strike):
        t = i / strike
        x = rnd.uniform(-1, 1)
        centre = 700 + 2700 * (t ** 1.7)
        r = 0.93 + 0.03 * t  # tightens as it comes
        w = 2 * math.pi * centre / SR
        b1 = -2 * r * math.cos(w)
        b2 = r * r
        y = (1 - r) * x - b1 * y1 - b2 * y2
        y2, y1 = y1, y
        # Steeper than it looks like it should be, and deliberately so: a
        # tightening resonator has more gain when it is wide, so a gentle
        # envelope comes out loudest at the start — the opposite of a lunge.
        out[i] += y * (0.06 + 0.94 * t ** 2.6) * 2.6

    # The bite. Two hard, dry impacts a few milliseconds apart, high and
    # short — teeth, not a drum.
    for k, (at, level) in enumerate([(0.0, 1.0), (0.009, 0.62)]):
        j = strike + int(at * SR)
        modes = [
            (1850 + 260 * k, 0.55, 180),
            (3100 + 400 * k, 0.42, 230),
            (5200, 0.22, 300),
            (420, 0.30, 90),
        ]
        hit = strike_sound(int(0.09 * SR), modes, 0.7, 1500, 900, rnd)
        for i, v in enumerate(hit):
            if j + i < n:
                out[j + i] += v * level

    # Drawing back: the hiss again, falling this time, and quieter than it
    # arrived — the snake is already leaving.
    y1 = y2 = 0.0
    tail_at = strike + int(0.03 * SR)
    for i in range(tail_at, n):
        t = (i - tail_at) / (n - tail_at)
        x = rnd.uniform(-1, 1)
        centre = 3000 * math.exp(-2.2 * t) + 480
        r = 0.95
        w = 2 * math.pi * centre / SR
        b1 = -2 * r * math.cos(w)
        b2 = r * r
        y = (1 - r) * x - b1 * y1 - b2 * y2
        y2, y1 = y1, y
        out[i] += y * math.exp(-4.0 * t) * 0.9

    return one_pole_lp(out, 9000)


# --- winning --------------------------------------------------------------
def victory():
    """A short fanfare: four notes up, then the chord left ringing.

    Struck rather than blown — the same slightly stretched partials as the
    arrival chime, so the two belong to the same game — and the last three
    notes are held so they pile into a major chord instead of arriving one at
    a time and leaving. Under it, a swell of noise that rises and falls like a
    room reacting.
    """
    rnd = random.Random(77)
    n = int(1.9 * SR)
    buf = [0.0] * n

    def bell(freq, amp, decay, at):
        length = n - int(at * SR)
        if length <= 0:
            return
        out = [0.0] * length
        for ratio, level, faster in (
            (1.0, 1.0, 1.0),
            (2.01, 0.38, 1.5),
            (3.02, 0.18, 2.2),
            (4.04, 0.09, 3.0),
        ):
            w = 2 * math.pi * freq * ratio / SR
            for i in range(length):
                out[i] += level * math.sin(w * i) * math.exp(-i / SR * decay * faster)
        for i in range(int(0.008 * SR)):
            out[i] += rnd.uniform(-1, 1) * 0.22 * math.exp(-i / SR * 800)
        mix(buf, [v * amp for v in out], at)

    # C5 E5 G5 C6, each one held from where it lands.
    for k, (freq, at) in enumerate(
        [(523.25, 0.0), (659.25, 0.10), (783.99, 0.20), (1046.50, 0.30)]
    ):
        bell(freq, 0.55 + 0.15 * k, 3.0 if k < 3 else 1.9, at)

    # The room. Noise rising into the last note and falling away after it.
    hiss = [rnd.uniform(-1, 1) for _ in range(n)]
    hiss = one_pole_lp(hiss, 3200)
    hiss = [v - w for v, w in zip(hiss, one_pole_lp(hiss, 300))]
    for i in range(n):
        t = i / n
        swell = math.exp(-((t - 0.22) ** 2) / 0.012)
        buf[i] += hiss[i] * swell * 0.30

    return buf


if __name__ == "__main__":
    # dice_roll.wav and chip_step.wav are not made here — prepare_dice.py cuts
    # both from the recording, and running this would overwrite them.
    write("chip_home.wav", chip_home())
    write("victory.wav", victory())
    write("capture.wav", capture())
