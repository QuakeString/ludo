#!/usr/bin/env python3
"""Synthesises the game's sound effects.

Four of the six. The dice roll and the chip landing both come out of a
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
    """A chip arriving: set down, then a little rising flourish over it.

    Two notes struck like small bells was the first attempt and it was too
    plain to be worth hearing — the shape of a notification, not of finishing
    something. Arriving home is the one unambiguously good thing that happens
    to a chip in a whole game, and it should sound like an event.

    Three things make it one. The chip is set down first, on wood, so the
    sound is anchored to the same board everything else happens on. Then a
    rising figure that resolves on the octave, which is what makes it read as
    arrival rather than as an alert: it goes somewhere and stops there. And the
    last note is left shimmering, its partials beating slightly against each
    other, so the sound thins out instead of being cut off.
    """
    rnd = random.Random(5)
    n = int(1.15 * SR)
    buf = [0.0] * n

    def chime(freq, amp, decay, at, shimmer=0.0):
        """One struck metal note.

        The partials are stretched, and stretched by uneven amounts, which is
        the whole difference between a glockenspiel and an organ: a bar's
        overtones are not whole multiples of its fundamental, and ears know it.
        """
        length = n - int(at * SR)
        if length <= 0:
            return
        out = [0.0] * length
        for ratio, level, faster in (
            (1.0, 1.0, 1.0),
            (2.76, 0.34, 1.35),
            (5.40, 0.16, 1.9),
            (8.93, 0.07, 2.6),
        ):
            w = 2 * math.pi * freq * ratio / SR
            phase = rnd.uniform(0, 2 * math.pi)
            for i in range(length):
                out[i] += level * math.sin(w * i + phase) * math.exp(
                    -i / SR * decay * faster
                )
        # A second voice a hair sharp, so the tail beats slowly against itself
        # rather than sitting dead still. Only on the note that is held.
        if shimmer:
            w = 2 * math.pi * freq * 1.004 / SR
            for i in range(length):
                out[i] += shimmer * math.sin(w * i) * math.exp(-i / SR * decay)
        # The mallet. Without it a note starts out of nowhere, which is the
        # sound of a synthesiser and not of anything being hit.
        for i in range(int(0.006 * SR)):
            out[i] += rnd.uniform(-1, 1) * 0.30 * math.exp(-i / SR * 1400)
        mix(buf, [v * amp for v in out], at)

    # The chip meeting the board: low, short, wooden. Quiet enough to be felt
    # rather than listened to.
    tap = strike_sound(
        int(0.07 * SR),
        [(320, 0.5, 120), (760, 0.3, 190), (1500, 0.14, 300)],
        0.5,
        900,
        700,
        rnd,
    )
    mix(buf, tap, 0.0, 0.34)

    # C6, G6, C7 — up a fifth, then up a fourth to the octave. Short, short,
    # held.
    chime(1046.50, 0.62, 7.0, 0.030)
    chime(1567.98, 0.66, 6.4, 0.105)
    chime(2093.00, 0.78, 2.6, 0.185, shimmer=0.30)

    # Sparkle over the top of the last note: high noise, gated into a fast
    # tremolo so it glitters instead of hissing.
    spark = [rnd.uniform(-1, 1) for _ in range(n)]
    spark = one_pole_hp(spark, 5200)
    start = int(0.185 * SR)
    for i in range(start, n):
        t = (i - start) / SR
        tremolo = 0.5 + 0.5 * math.sin(2 * math.pi * 17 * t)
        buf[i] += spark[i] * tremolo * 0.16 * math.exp(-t * 5.5)

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


# --- crackers ----------------------------------------------------------------
def crackers():
    """Fireworks going off — the noise of the room, not another tune.

    It plays under the fanfare, so it deliberately has no pitch of its own:
    two melodies at once fight, but a melody over a crowd of bangs is a
    celebration. Everything here is noise shaped in time.

    Three layers. A string of small cracks, thickest at the start and
    scattering away — a chain of firecrackers is not evenly spaced, and evenly
    spaced is instantly heard as a machine. Two shells that go off properly,
    each a low thump with a spray of crackle falling out of it, the second one
    announced by a rising whistle. And under all of it a tail of soft
    reflections, because bangs outdoors come back off things and bangs with no
    tail sound like they happened inside a box.
    """
    rnd = random.Random(2024)
    n = int(2.2 * SR)
    out = [0.0] * n

    def crack(level, bright):
        """One firecracker: a click of very high noise over a small thump."""
        m = int(0.075 * SR)
        burst = [rnd.uniform(-1, 1) * math.exp(-i / SR * 320) for i in range(m)]
        burst = one_pole_hp(burst, bright)
        body = [
            0.45 * math.sin(2 * math.pi * 140 * i / SR) * math.exp(-i / SR * 90)
            for i in range(m)
        ]
        # The very first sample or two of a bang is the loudest part of it, so
        # the attack is left completely unsmoothed.
        return [(b + c) * level for b, c in zip(burst, body)]

    # The chain. Density falls away across the whole thing, and the gaps are
    # drawn at random rather than stepped, so no two are alike.
    at = 0.02
    while at < 1.75:
        loud = 0.30 + 0.55 * rnd.random()
        mix(out, crack(loud, 2200 + rnd.random() * 2600), at)
        # Gaps grow as the chain dies down: fast at the start, thinning out.
        at += 0.012 + 0.10 * rnd.random() * (0.25 + at)

    def shell(at, boom_freq, spread):
        """A shell: the thump, then crackle raining down out of it."""
        m = int(0.9 * SR)
        body = [0.0] * m
        for i in range(m):
            t = i / SR
            # Two low tones a little apart, so the thump has some size to it
            # instead of being one clean note.
            body[i] += 0.9 * math.sin(2 * math.pi * boom_freq * t) * math.exp(-t * 11)
            body[i] += 0.5 * math.sin(2 * math.pi * boom_freq * 1.6 * t) * math.exp(
                -t * 16
            )
        # The initial rip: broadband, very short.
        rip = [rnd.uniform(-1, 1) * math.exp(-i / SR * 260) for i in range(int(0.1 * SR))]
        rip = one_pole_hp(rip, 800)
        for i, v in enumerate(rip):
            body[i] += v * 0.85
        mix(out, body, at, 0.8)
        # And the sparks: twenty-odd small cracks strewn through the second
        # after it, getting quieter as they fall.
        for _ in range(26):
            when = at + 0.05 + spread * rnd.random() ** 0.7
            fade = max(0.0, 1 - (when - at) / spread)
            mix(out, crack(0.20 * fade, 4000 + rnd.random() * 3000), when)

    # A whistle climbing into the second shell. Rising pitch is the one cue
    # that says "something is about to go off" before it does.
    rise_at, rise_for = 0.62, 0.30
    phase = 0.0
    for i in range(int(rise_for * SR)):
        t = i / (rise_for * SR)
        freq = 620 + 1750 * t ** 1.6
        phase += 2 * math.pi * freq / SR
        j = int(rise_at * SR) + i
        if j < n:
            # Fades in and then ducks out just before the bang, so the bang is
            # the loudest thing and not a continuation of the whistle.
            out[j] += 0.20 * math.sin(phase) * math.sin(math.pi * t) ** 0.6

    shell(0.16, 62.0, 0.62)
    shell(0.94, 48.0, 0.85)

    # The room: a handful of delayed, softened copies. Cheaper than a real
    # reverb and doing the only job wanted here, which is to put the bangs
    # somewhere with walls a long way off.
    tail = one_pole_lp(out, 2400)
    for delay, gain in ((0.055, 0.20), (0.101, 0.14), (0.163, 0.09)):
        d = int(delay * SR)
        for i in range(d, n):
            out[i] += tail[i - d] * gain

    # Fade the last third out under the fanfare, which is still ringing.
    from_at = int(1.5 * SR)
    for i in range(from_at, n):
        out[i] *= 1 - (i - from_at) / (n - from_at)

    return out


if __name__ == "__main__":
    # dice_roll.wav and chip_step.wav are not made here — prepare_dice.py cuts
    # both from the recording, and running this would overwrite them.
    write("chip_home.wav", chip_home())
    write("victory.wav", victory())
    write("crackers.wav", crackers())
    write("capture.wav", capture())
