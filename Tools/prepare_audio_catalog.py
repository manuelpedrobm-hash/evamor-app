#!/usr/bin/env python3
"""Build a static HTTPS audio catalog directory from a source JSON file."""
from pathlib import Path
from urllib.parse import quote
import argparse
import hashlib
import json
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path, help="JSON containing tracks with sourceFile and durationSeconds")
parser.add_argument("output", type=Path, help="Directory to upload to a static HTTPS host")
parser.add_argument("--base-url", required=True, help="Public HTTPS URL corresponding to output")
args = parser.parse_args()

if not args.base_url.startswith("https://"):
    raise SystemExit("--base-url must use HTTPS")

document = json.loads(args.source.read_text())
if document.get("schemaVersion") != 1 or not document.get("revision"):
    raise SystemExit("schemaVersion must be 1 and revision is required")

args.output.mkdir(parents=True, exist_ok=True)
seen = set()
for track in document.get("tracks", []):
    track_id = track.get("id", "")
    source = Path(track.pop("sourceFile", ""))
    if not track_id or track_id in seen or not source.is_file():
        raise SystemExit(f"Invalid or duplicate track: {track_id!r}")
    if float(track.get("durationSeconds", 0)) <= 0:
        raise SystemExit(f"durationSeconds is required for {track_id}")
    seen.add(track_id)
    extension = source.suffix.lower()
    if extension not in {".m4a", ".mp3", ".wav", ".aac"}:
        raise SystemExit(f"Unsupported audio extension for {source}")
    filename = f"{track_id}{extension}"
    destination = args.output / filename
    shutil.copyfile(source, destination)
    payload = destination.read_bytes()
    track["sha256"] = hashlib.sha256(payload).hexdigest()
    track["byteCount"] = len(payload)
    track["downloadURL"] = args.base_url.rstrip("/") + "/" + quote(filename)
    track.pop("bundledResource", None)

profile_ids = [profile.get("id") for profile in document.get("profiles", [])]
if len(profile_ids) != len(set(profile_ids)):
    raise SystemExit("Profile IDs must be unique")
if any(profile.get("trackID") not in seen for profile in document.get("profiles", []) if profile.get("trackID")):
    raise SystemExit("Every profile trackID must exist in tracks")

(args.output / "catalog.json").write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
print(f"Prepared {len(seen)} tracks in {args.output}")
print(f"Catalog URL: {args.base_url.rstrip('/')}/catalog.json")
