"""Shared configuration, paths and the map projection."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from pyproj import Transformer

TOOL_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = TOOL_DIR.parent.parent
CACHE_DIR = TOOL_DIR / "cache"
MAP_DIR = REPO_DIR / "map"
TILES_DIR = MAP_DIR / "tiles"


def load_config(path: Path | None = None) -> dict:
    with open(path or TOOL_DIR / "config.json", encoding="utf-8") as f:
        return json.load(f)


class Projector:
    """Transverse Mercator centred on the map origin.

    Python code works in plan coordinates (e, n): metres east and north of the
    origin. Godot gets X = e, Y = height, Z = -n.
    """

    def __init__(self, lat0: float, lon0: float):
        self.lat0, self.lon0 = lat0, lon0
        crs = (f"+proj=tmerc +lat_0={lat0} +lon_0={lon0} +k=1 +x_0=0 +y_0=0 "
               "+ellps=WGS84 +units=m +no_defs")
        self._fwd = Transformer.from_crs("EPSG:4326", crs, always_xy=True)
        self._inv = Transformer.from_crs(crs, "EPSG:4326", always_xy=True)

    def fwd(self, lon, lat):
        return self._fwd.transform(lon, lat)

    def inv(self, e, n):
        return self._inv.transform(e, n)

    @classmethod
    def from_config(cls, cfg: dict) -> "Projector":
        return cls(cfg["origin"]["lat"], cfg["origin"]["lon"])


@dataclass(frozen=True)
class TileKey:
    i: int  # east index
    j: int  # north index

    def bounds(self, size: float) -> tuple[float, float, float, float]:
        """(e0, n0, e1, n1) in plan coordinates."""
        return (self.i * size, self.j * size, (self.i + 1) * size, (self.j + 1) * size)

    @property
    def name(self) -> str:
        return f"{self.i}_{self.j}"


def tiles_for_bbox(e0, n0, e1, n1, size) -> list[TileKey]:
    return [TileKey(i, j)
            for i in range(math.floor(e0 / size), math.ceil(e1 / size))
            for j in range(math.floor(n0 / size), math.ceil(n1 / size))]


def stable_rng(*keys) -> np.random.Generator:
    """Deterministic RNG from integers/strings so rebuilds are reproducible."""
    h = 1469598103934665603
    for k in keys:
        for b in str(k).encode():
            h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return np.random.default_rng(h)
