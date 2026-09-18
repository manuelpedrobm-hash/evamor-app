#!/usr/bin/env python3
"""Validate bundled WAV cues and print reproducible hashes. Standard library only."""
from pathlib import Path
import hashlib
import json
import wave

root = Path(__file__).resolve().parents[1]
resources = root / "iOS/Resources"
manifest = json.loads((resources / "AudioManifest.json").read_text())

assert manifest["sessionRangeMinutes"] == {"minimum": 5, "maximum": 480}
for name, expected in manifest["assets"].items():
    path = resources / f"{name}.wav"
    assert path.exists(), f"Falta {path.name}"
    with wave.open(str(path), "rb") as source:
        duration = source.getnframes() / source.getframerate()
        assert source.getnchannels() == 1, f"{name}: debe ser mono"
        assert source.getsampwidth() == 2, f"{name}: se esperan muestras PCM de 16 bits"
        assert abs(duration - expected) < 0.02, f"{name}: {duration:.3f}s, manifiesto {expected}s"
        rate = source.getframerate()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"PASS {name:12} {duration:6.2f}s {rate}Hz sha256={digest}")
