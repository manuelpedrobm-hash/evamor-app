#!/usr/bin/env python3
"""Print the exact opening/silence/closing timeline for one or more session lengths."""
from pathlib import Path
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("minutes", nargs="*", type=int, default=[5, 60, 120, 480])
parser.add_argument("--without-chanting", action="store_true")
parser.add_argument("--without-metta", action="store_true")
args = parser.parse_args()

manifest = json.loads((Path(__file__).resolve().parents[1] / "iOS/Resources/AudioManifest.json").read_text())
audio = manifest["assets"]

def clock(seconds):
    seconds = int(round(seconds))
    return f"{seconds // 3600:d}:{(seconds % 3600) // 60:02d}:{seconds % 60:02d}"

for minutes in args.minutes:
    if not 5 <= minutes <= 480 or minutes % 5:
        raise SystemExit(f"Duración inválida: {minutes}. Usa múltiplos de 5 entre 5 y 480.")
    base = minutes * 60
    opening = [("Introducción", audio["introduction"])]
    if not args.without_chanting:
        opening.append(("Chanting", audio["chanting"]))
    closing = audio["closing"]
    cursor = 0
    phases = []
    for name, duration in opening:
        phases.append((name, cursor, cursor + duration)); cursor += duration
    phases.append(("Silencio", cursor, base - closing))
    phases.append(("Cierre", base - closing, base))
    if not args.without_metta:
        phases.append(("Metta extendido", base, base + audio["metta"]))
    print(f"\n{minutes} minutos de base")
    for name, start, end in phases:
        print(f"  {clock(start)}–{clock(end)}  {name}")
