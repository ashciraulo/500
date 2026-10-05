#!/usr/bin/env python3
"""Latitude/longitude to game world metres, the same projection as the map
(tools/osm_import common.Projector: transverse Mercator on WGS84, centred on
Little Shenton Lane; Godot X = east, Z = -north).

    python3 tools/field/project.py -31.9959 115.8441   # prints x z

Also used by tools/field/gen_field.py to place habitats and fishing spots.
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
A = 6378137.0
F = 1 / 298.257223563
E2 = F * (2 - F)
EP2 = E2 / (1 - E2)


def _origin():
    cfg = json.loads((ROOT / "tools/osm_import/config.json").read_text())
    o = cfg["origin"]
    return float(o["lat"]), float(o["lon"])


def _meridian(phi):
    e4, e6 = E2 * E2, E2 * E2 * E2
    return A * ((1 - E2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi
                - (3 * E2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * math.sin(2 * phi)
                + (15 * e4 / 256 + 45 * e6 / 1024) * math.sin(4 * phi)
                - (35 * e6 / 3072) * math.sin(6 * phi))


LAT0, LON0 = _origin()
M0 = _meridian(math.radians(LAT0))


def to_world(lat: float, lon: float) -> tuple[float, float]:
    """(x, z) in world metres."""
    phi = math.radians(lat)
    lam = math.radians(lon - LON0)
    n = A / math.sqrt(1 - E2 * math.sin(phi) ** 2)
    t = math.tan(phi) ** 2
    c = EP2 * math.cos(phi) ** 2
    a = lam * math.cos(phi)
    m = _meridian(phi)
    east = n * (a + (1 - t + c) * a ** 3 / 6 + (5 - 18 * t + t * t + 72 * c - 58 * EP2) * a ** 5 / 120)
    north = (m - M0) + n * math.tan(phi) * (a * a / 2 + (5 - t + 9 * c + 4 * c * c) * a ** 4 / 24
                                            + (61 - 58 * t + t * t + 600 * c - 330 * EP2) * a ** 6 / 720)
    return round(east, 1), round(-north, 1)


if __name__ == "__main__":
    print(*to_world(float(sys.argv[1]), float(sys.argv[2])))
