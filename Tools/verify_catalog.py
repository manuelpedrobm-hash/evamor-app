#!/usr/bin/env python3
"""Verify the bundled dynamic audio catalog and media metadata."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

root = Path(__file__).resolve().parents[1]
resources = root / "iOS/Resources"
catalog = json.loads((resources / "AudioCatalog.json").read_text())

assert catalog["schemaVersion"] == 1
assert catalog["revision"]
tracks = catalog["tracks"]
assert len({track["id"] for track in tracks}) == len(tracks)

for track in tracks:
    path = resources / track["bundledResource"]
    payload = path.read_bytes()
    assert len(payload) == track["byteCount"], (path, len(payload), track["byteCount"])
    assert hashlib.sha256(payload).hexdigest() == track["sha256"]
    info = subprocess.run(["afinfo", str(path)], check=True, capture_output=True, text=True).stdout
    match = re.search(r"estimated duration: ([0-9.]+) sec", info)
    assert match, f"No duration in afinfo for {path}"
    actual = float(match.group(1))
    assert abs(actual - track["durationSeconds"]) < 0.05, (path, actual, track["durationSeconds"])
    print(f"PASS {track['id']:42} {actual:8.3f}s sha256={track['sha256']}")

track_ids = {track["id"] for track in tracks}
for profile in catalog["profiles"]:
    assert 5 <= profile["minutes"] <= 480
    assert profile.get("trackID") in track_ids
print(f"PASS {len(catalog['profiles'])} catalog profiles")
