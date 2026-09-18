#!/usr/bin/env python3
"""Original synthesized demonstration cues, not teaching recordings or vocal chanting."""
import math
import pathlib
import struct
import wave

destination = pathlib.Path(__file__).resolve().parents[1] / "iOS/Resources"
destination.mkdir(parents=True, exist_ok=True)
durations = {"introduction": 8, "chanting": 12, "closing": 8, "metta": 20, "gong": 3}
rate = 22050
for index, (name, seconds) in enumerate(durations.items()):
    if (destination / (name + ".wav")).exists():
        print(f"Preserved existing {name}.wav")
        continue
    samples = bytearray()
    base = [220, 196, 174.61, 146.83, 110][index]
    for number in range(seconds * rate):
        t = number / rate
        attack = min(1, t / 0.03)
        fade = min(1, max(0, (seconds - t) / 1.5))
        decay = math.exp(-t / (seconds * 0.45))
        tone = sum(math.sin(2 * math.pi * base * ratio * t) * amplitude for ratio, amplitude in [(1, 0.5), (2.76, 0.25), (4.07, 0.12)])
        value = int(10000 * attack * fade * decay * tone)
        samples.extend(struct.pack("<h", value))
    with wave.open(str(destination / (name + ".wav")), "wb") as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(rate); output.writeframes(samples)
print("Generated missing demonstration audio files; existing recordings preserved")
