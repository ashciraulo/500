#!/usr/bin/env python3
"""Fills in world x/z for every lat/lon place in data/field/habitats.json,
using the map's projection (fishing spots are placed in the map by
tools/field/place_spots.gd).

    python3 tools/field/gen_field.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from project import ROOT, to_world  # noqa: E402

FILES = {"habitats.json": "habitats"}


def main():
    for name, key in FILES.items():
        path = ROOT / "data/field" / name
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        for entry in data[key]:
            entry["x"], entry["z"] = to_world(entry["lat"], entry["lon"])
            # nudge [dx, dz]: where the map's water covers the real place,
            # moved toward the shore so it can be walked into.
            if "nudge" in entry:
                entry["x"] = round(entry["x"] + entry["nudge"][0], 1)
                entry["z"] = round(entry["z"] + entry["nudge"][1], 1)
        text = json.dumps(data, indent="\t", ensure_ascii=False)
        path.write_text(text + "\n")
        print(name, len(data[key]))


if __name__ == "__main__":
    main()
