"""Download source data into tools/osm_import/cache (not committed)."""
from __future__ import annotations

import io
import math
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

from .common import CACHE_DIR


def _download(url: str, dest: Path, retries: int = 4) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            tmp.replace(dest)
            return dest
        except Exception as exc:  # network hiccups: back off and retry
            if attempt == retries - 1:
                raise
            print(f"  retry {url}: {exc}", file=sys.stderr)
            time.sleep(2 ** (attempt + 1))
    return dest


def osm_pbf(cfg: dict, refresh: bool = False) -> Path:
    dest = CACHE_DIR / "perth.osm.pbf"
    if refresh or not dest.exists():
        print(f"Downloading {cfg['sources']['osm_pbf']}")
        _download(cfg["sources"]["osm_pbf"], dest)
    return dest


def _lonlat_to_tile(lon, lat, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2.0 * n
    return x, y


def dem_mosaic(cfg: dict, lon0, lat0, lon1, lat1):
    """Return (heights, georef) for a Terrarium mosaic covering the bbox.

    georef maps lon/lat to fractional pixel coordinates of the mosaic.
    """
    z = cfg["sources"]["dem_zoom"]
    x0, y0 = _lonlat_to_tile(lon0, lat1, z)
    x1, y1 = _lonlat_to_tile(lon1, lat0, z)
    tx0, ty0, tx1, ty1 = int(x0), int(y0), int(x1), int(y1)
    w, h = (tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256
    out = np.zeros((h, w), dtype=np.float32)
    for tx in range(tx0, tx1 + 1):
        for ty in range(ty0, ty1 + 1):
            dest = CACHE_DIR / "dem" / str(z) / f"{tx}_{ty}.png"
            if not dest.exists():
                _download(cfg["sources"]["dem_tiles"].format(z=z, x=tx, y=ty), dest)
            a = np.asarray(Image.open(dest).convert("RGB")).astype(np.float32)
            hh = a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0
            out[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = hh

    def georef(lon, lat):
        px, py = _lonlat_to_tile(np.asarray(lon), np.asarray(lat), z)
        return (px - tx0) * 256.0 - 0.5, (py - ty0) * 256.0 - 0.5

    return out, georef
