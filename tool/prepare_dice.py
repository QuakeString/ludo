#!/usr/bin/env python3
"""Builds three of the game's sounds from the recorded dice throw.

The roll itself, and one impact lifted out of it for a chip landing. Taking
the tap from the same recording is not a shortcut: the two sounds have to
belong to the same table, and a synthesised tap next to a recorded throw was
audibly a different material in a different room.

The other three sounds are synthesised — see make_sounds.py. This one is not:
a synthesised die kept coming out as glass, all long ringing modes, where a
real one is a short dry broadband click. Measuring the recording said why.
Its first impact puts 32% of its energy between 4 and 8 kHz, centres at about
3.9 kHz, and falls to a tenth of its level in 15 milliseconds. Mine rang for
ten times that.

    pip install soundfile numpy
    python3 tool/prepare_dice.py

Source: tool/sources/dice_roll_source.mp3, supplied for this purpose.
"""

import wave
from pathlib import Path

import numpy as np
import soundfile as sf

SRC = Path("tool/sources/dice_roll_source.mp3")
OUT = Path("app/assets/sounds")
RATE = 44100  # what the rest of the sounds use

# The impact to lift out for a chip landing. The throw's later bounces are
# quieter and better separated — this one has 190ms of clear air in front of
# it — and a chip being set down is a softer thing than a die being thrown.
TAP_AT = 0.560


def one_pole_lowpass(x, cutoff, sr):
    a = np.exp(-2 * np.pi * cutoff / sr)
    out = np.zeros_like(x)
    prev = 0.0
    for i, v in enumerate(x):
        prev = (1 - a) * v + a * prev
        out[i] = prev
    return out


def one_pole_highpass(x, cutoff, sr):
    a = np.exp(-2 * np.pi * cutoff / sr)
    lp = np.zeros_like(x)
    prev = 0.0
    for i, v in enumerate(x):
        prev = (1 - a) * v + a * prev
        lp[i] = prev
    return x - lp


def save(name, audio, rate=RATE):
    frames = (audio * 32767).astype("<i2").tobytes()
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames)
    print(f"{name}: {len(audio) / rate:.2f}s, {len(frames)} bytes")


def main():
    audio, sr = sf.read(str(SRC))
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    audio = audio.astype(np.float64)
    audio /= np.max(np.abs(audio))

    # Trim. The recording opens with 40ms of nothing and closes with a long
    # room tail; -50dB catches the throw without clipping the last bounce off.
    smooth = np.convolve(np.abs(audio), np.ones(220) / 220, mode="same")
    loud = np.where(smooth > smooth.max() * 10 ** (-50 / 20))[0]
    start = max(0, loud[0] - int(0.004 * sr))
    end = min(len(audio), loud[-1] + int(0.02 * sr))
    audio = audio[start:end]

    # Rumble out. Nothing below 70Hz belongs to a small plastic cube, and on a
    # phone speaker it is only cone travel that costs headroom.
    audio = one_pole_highpass(audio, 70, sr)

    # Edges, so neither end clicks.
    fade_in = int(0.003 * sr)
    fade_out = int(0.030 * sr)
    audio[:fade_in] *= np.linspace(0, 1, fade_in)
    audio[-fade_out:] *= np.linspace(1, 0, fade_out)

    # To 44.1k, linearly. The content is broadband noise bursts; there is no
    # tone here for interpolation error to beat against.
    n = int(round(len(audio) * RATE / sr))
    audio = np.interp(
        np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio
    )

    # Taken off the top. The recording is a hard crack close to the
    # microphone; through a phone it came out sharp, all edge and no wood.
    # Mixing back a little of the original keeps the attack from going soft.
    dull = one_pole_lowpass(audio, 5200, RATE)
    audio = 0.72 * dull + 0.28 * audio

    # A touch of soft clipping before normalising: it lifts the body of the
    # roll without letting the first crack hit the ceiling.
    audio = np.tanh(audio * 1.25) / np.tanh(1.25)
    audio *= 0.89 / np.max(np.abs(audio))
    save("dice_roll.wav", audio)

    # --- one impact, for a chip landing --------------------------------
    tap_at = int((TAP_AT * sr - start) * RATE / sr)
    tap = audio[tap_at - int(0.004 * RATE) : tap_at + int(0.13 * RATE)].copy()

    # Duller again, and shorter. A pawn set on a board is a smaller, softer
    # event than a die thrown at one, and this plays once per square — a tap
    # with any ring left in it becomes a nuisance by the third square.
    tap = one_pole_lowpass(tap, 2600, RATE)
    tail = int(0.06 * RATE)
    tap[-tail:] *= np.linspace(1, 0, tail) ** 1.5
    tap[: int(0.002 * RATE)] *= np.linspace(0, 1, int(0.002 * RATE))
    tap *= 0.72 / np.max(np.abs(tap))
    save("chip_step.wav", tap)

    # --- landing somewhere safe ----------------------------------------
    # The same chip, set down and settling: the tap, then a quieter one a
    # breath later, over a short warm body the plain tap does not have.
    #
    # This was a struck chime before — a bell note with partials, which is a
    # perfectly nice sound and completely wrong here. Every other sound in the
    # game is a plastic thing on a board, and a musical tone beside them is
    # heard as a different object in a different room. Safety should sound like
    # something settling into place, not like a notification.
    span = int(0.34 * RATE)
    safe = np.zeros(span)
    first = min(len(tap), span)
    safe[:first] += tap[:first] * 0.95
    echo_at = int(0.075 * RATE)
    second = min(len(tap), span - echo_at)
    safe[echo_at : echo_at + second] += tap[:second] * 0.55

    # A low body under it, struck once and gone. Two decaying sines and nothing
    # above them, so it reads as weight rather than as a note.
    t = np.arange(span) / RATE
    body = (
        np.sin(2 * np.pi * 196 * t) * np.exp(-11 * t) * 0.30
        + np.sin(2 * np.pi * 262 * t) * np.exp(-15 * t) * 0.18
    )
    safe += body

    fade = int(0.05 * RATE)
    safe[-fade:] *= np.linspace(1, 0, fade)
    safe *= 0.80 / np.max(np.abs(safe))
    save("safe.wav", safe)


if __name__ == "__main__":
    main()
