"""Generate the project's original, gentle 8-bit style home loop."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Assests" / "Audio" / "bgm_sunny_8bit.wav"
SAMPLE_RATE = 22_050
OUTPUT_RATE = 22_050
BPM = 104
BEAT_SECONDS = 60.0 / BPM
STEP_SECONDS = BEAT_SECONDS / 2.0
BAR_SECONDS = BEAT_SECONDS * 4.0
BAR_COUNT = 8

MELODY = [
    [72, 76, 79, 76, 74, 72, 67, None],
    [69, 72, 76, 79, 76, 72, 69, None],
    [69, 72, 77, 81, 79, 77, 76, None],
    [67, 71, 74, 79, 76, 74, 71, None],
    [72, 76, 79, 84, 79, 76, 74, None],
    [69, 72, 76, 81, 79, 76, 72, None],
    [77, 76, 72, 69, 72, 76, 77, None],
    [79, 76, 74, 71, 74, 76, 79, None],
]
CHORD_ROOTS = [48, 45, 41, 43, 48, 45, 41, 43]  # C, Am, F, G


def midi_hz(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def add_note(
    buffer: list[float],
    start_seconds: float,
    duration: float,
    note: int,
    volume: float,
    voice: str,
    duty: float = 0.25,
) -> None:
    start = int(round(start_seconds * SAMPLE_RATE))
    end = min(len(buffer), start + int(round(duration * SAMPLE_RATE)))
    frequency = midi_hz(note)
    attack = min(0.018, duration * 0.25)
    release = min(0.045, duration * 0.32)

    for frame in range(start, end):
        elapsed = (frame - start) / SAMPLE_RATE
        remaining = (end - frame) / SAMPLE_RATE
        envelope = min(1.0, elapsed / max(attack, 0.001))
        envelope *= min(1.0, remaining / max(release, 0.001))
        phase = (frame * frequency / SAMPLE_RATE) % 1.0

        if voice == "square":
            pulse = 1.0 if phase < duty else -1.0
            triangle = 1.0 - 4.0 * abs(phase - 0.5)
            sample = pulse * 0.68 + triangle * 0.32
        elif voice == "triangle":
            sample = 1.0 - 4.0 * abs(phase - 0.5)
        else:
            sample = math.sin(phase * math.tau)

        buffer[frame] += sample * volume * envelope


def build_mix() -> list[float]:
    duration = BAR_COUNT * BAR_SECONDS
    mix = [0.0] * int(round(duration * SAMPLE_RATE))

    for bar_index, notes in enumerate(MELODY):
        bar_start = bar_index * BAR_SECONDS
        for step, note in enumerate(notes):
            if note is None:
                continue
            add_note(
                mix,
                bar_start + step * STEP_SECONDS,
                STEP_SECONDS * 0.72,
                note,
                0.145,
                "square",
                duty=0.25,
            )

        root = CHORD_ROOTS[bar_index]
        for beat in range(4):
            bass_note = root if beat % 2 == 0 else root + 7
            add_note(
                mix,
                bar_start + beat * BEAT_SECONDS,
                BEAT_SECONDS * 0.72,
                bass_note,
                0.055,
                "triangle",
            )

        chord_tones = [root + 12, root + 16, root + 19]
        for beat, note in zip((1, 3), (chord_tones[1], chord_tones[2])):
            add_note(
                mix,
                bar_start + beat * BEAT_SECONDS,
                0.13,
                note + 12,
                0.026,
                "triangle",
            )

    return mix


def write_loop(mix: list[float]) -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    hold_frames = max(1, OUTPUT_RATE // SAMPLE_RATE)
    fade_frames = int(SAMPLE_RATE * 0.015)

    for index, sample in enumerate(mix):
        if index < fade_frames:
            sample *= index / max(fade_frames, 1)
        elif index >= len(mix) - fade_frames:
            sample *= (len(mix) - 1 - index) / max(fade_frames, 1)

        # Keep an 8-bit amplitude texture without the roughness of an
        # 11.025 kHz sample hold.
        sample = max(-0.92, min(0.92, sample))
        sample = round(sample * 127.0) / 127.0
        pcm = int(round(sample * 32767.0))
        packed = struct.pack("<h", pcm)
        for _ in range(hold_frames):
            frames.extend(packed)

    stereo_frames = bytearray()
    for offset in range(0, len(frames), 2):
        stereo_frames.extend(frames[offset : offset + 2])
        stereo_frames.extend(frames[offset : offset + 2])

    with wave.open(str(OUTPUT), "wb") as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(OUTPUT_RATE)
        wav_file.writeframes(stereo_frames)


if __name__ == "__main__":
    write_loop(build_mix())
    print(f"Wrote {OUTPUT}")
