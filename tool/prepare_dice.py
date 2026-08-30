#!/usr/bin/env python3
"""Turns the recorded dice throw into the game's dice_roll.wav.

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
OUT = Path("app/assets/sounds/dice_roll.wav")
RATE = 44100  # what the rest of the sounds use


def one_pole_highpass(x, cutoff, sr):
    a = np.exp(-2 * np.pi * cutoff / sr)
    lp = np.zeros_like(x)
    prev = 0.0
    for i, v in enumerate(x):
        prev = (1 - a) * v + a * prev
        lp[i] = prev
    return x - lp


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

    # A touch of soft clipping before normalising: it lifts the body of the
    # roll without letting the first crack hit the ceiling.
    audio = np.tanh(audio * 1.25) / np.tanh(1.25)
    audio *= 0.89 / np.max(np.abs(audio))

    frames = (audio * 32767).astype("<i2").tobytes()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"{OUT}: {len(audio) / RATE:.2f}s, {len(frames)} bytes")


if __name__ == "__main__":
    main()
