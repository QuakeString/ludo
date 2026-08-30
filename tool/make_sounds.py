#!/usr/bin/env python3
"""Synthesises the game's sound effects.

Two of the four. The dice roll and the chip landing both come out of a
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
    """Air let out of a balloon.

    Not a thud. A knocked-out chip is deflation, and the sound of it is a
    balloon's neck opened: a rush of air that falls in pitch and volume as the
    pressure drops, with the neck flapping against itself the whole way.

    Three things have to be right or it reads as steam instead. The noise is
    band-passed by a resonator that glides *down* — a jet slows as the pressure
    behind it goes. The neck flutter is an amplitude wobble that slows with it,
    from about sixty flaps a second to twenty-five. And a second, narrower
    resonance an octave up gives the squeal, the part that makes it a balloon
    and not a tyre.
    """
    rnd = random.Random(21)
    n = int(0.80 * SR)
    out = [0.0] * n

    # Two resonators, run sample by sample because their centre frequencies
    # move the whole time.
    wide_y1 = wide_y2 = 0.0
    thin_y1 = thin_y2 = 0.0
    wobble = rnd.uniform(0, 2 * math.pi)
    flap_phase = 0.0

    for i in range(n):
        t = i / n
        x = rnd.uniform(-1, 1)

        # Pressure falling away: everything follows this one curve.
        pressure = math.exp(-3.1 * t)

        # The jet's pitch, wobbling as the neck flutters.
        wobble += 2 * math.pi * 7.0 / SR
        centre = (2500 * pressure + 620) * (1 + 0.09 * math.sin(wobble))

        def resonate(freq, r, y1, y2):
            w = 2 * math.pi * min(freq, SR * 0.45) / SR
            b1 = -2 * r * math.cos(w)
            b2 = r * r
            y = (1 - r) * x - b1 * y1 - b2 * y2
            return y, y1

        wide, wide_y2 = resonate(centre, 0.955, wide_y1, wide_y2)
        wide_y1 = wide
        thin, thin_y2 = resonate(centre * 2.1, 0.992, thin_y1, thin_y2)
        thin_y1 = thin

        # The neck slapping shut and open again, slowing as it goes.
        flap_phase += 2 * math.pi * (62 * pressure + 22) / SR
        flap = 1 + 0.34 * math.sin(flap_phase)

        # Opens fast, then rides the pressure down.
        attack = min(1.0, i / (0.004 * SR))
        out[i] = attack * flap * pressure * (0.80 * wide + 0.55 * thin)

    # And the last of it: the neck going slack, a couple of loose flaps. Built
    # apart and filtered down to a mutter before being mixed in — left as raw
    # noise they came out brighter than the jet they follow, which undoes the
    # whole falling-away the rest of this is built on.
    flaps = [0.0] * n
    for k, at in enumerate([0.545, 0.63]):
        j = int(at * SR)
        for i in range(int(0.05 * SR)):
            if j + i < n:
                env = math.sin(math.pi * i / (0.05 * SR)) * (0.5 - 0.16 * k)
                flaps[j + i] += env * rnd.uniform(-1, 1)
    # Three times over: one pole rolls off at six decibels an octave, which
    # still let four kilohertz of hiss through and made the flaps brighter and
    # louder than the jet dying underneath them.
    for _ in range(3):
        flaps = one_pole_lp(flaps, 850)
    for i in range(n):
        out[i] += flaps[i] * 2.2

    return one_pole_lp(out, 7000)


if __name__ == "__main__":
    # dice_roll.wav and chip_step.wav are not made here — prepare_dice.py cuts
    # both from the recording, and running this would overwrite them.
    write("chip_home.wav", chip_home())
    write("capture.wav", capture())
