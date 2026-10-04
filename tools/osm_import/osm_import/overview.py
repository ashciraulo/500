"""The far-distance backdrop: a coarse heightfield draped with a painted map.

Streamed tiles only reach about a kilometre; past that the game draws this
instead, so the horizon shows the rest of the city, the river and the hills.
"""
from __future__ import annotations

import io
import math

import numpy as np
from PIL import Image, ImageDraw

from . import styles
from .common import Projector
from .extract import extract
from .fetch import osm_pbf
from .terrain import build_heightfield
from .variant import pack_tile

PX = 10.0          # metres per texture pixel
HSTEP = 50.0       # metres per height sample
MARGIN = 3000.0    # backdrop extends this far past the outermost tile

COLORS = {
    "urban": (150, 146, 132), "water": (40, 72, 88), "grass": (92, 116, 60), "bush": (74, 84, 50),
    "turf": (88, 128, 60), "sand": (210, 194, 152), "wetland": (70, 82, 60), "paving": (150, 148, 142),
    "dirt": (132, 108, 78), "concrete": (160, 158, 152), "road": (64, 64, 66), "major": (52, 52, 54),
    "building": (176, 170, 160), "tower": (120, 136, 150), "rail": (100, 92, 84),
}


def build_overview(cfg: dict, proj: Projector, tiles: dict, out_path):
    size = cfg["tile_size"]
    i0 = min(t["i"] for t in tiles.values())
    i1 = max(t["i"] for t in tiles.values()) + 1
    j0 = min(t["j"] for t in tiles.values())
    j1 = max(t["j"] for t in tiles.values()) + 1
    e0, n0 = i0 * size - MARGIN, j0 * size - MARGIN
    e1, n1 = i1 * size + MARGIN, j1 * size + MARGIN
    lon, lat = proj.inv([e0, e1, e0, e1], [n0, n0, n1, n1])
    feats = extract(osm_pbf(cfg), proj, (min(lon), min(lat), max(lon), max(lat)))
    hf = build_heightfield(cfg, proj, e0, n0, e1, n1, HSTEP)

    w = int(math.ceil((e1 - e0) / PX))
    h = int(math.ceil((n1 - n0) / PX))
    img = Image.new("RGB", (w, h), COLORS["urban"])
    draw = ImageDraw.Draw(img)

    def px(xy):
        return [((x - e0) / PX, (n1 - y) / PX) for x, y in xy]

    def fill(geom, color):
        polys = [geom] if geom.geom_type == "Polygon" else getattr(geom, "geoms", [])
        for p in polys:
            if p.geom_type != "Polygon" or p.area < PX * PX * 0.5:
                continue
            draw.polygon(px(p.exterior.coords), fill=color)
            for hole in p.interiors:
                draw.polygon(px(hole.coords), fill=COLORS["urban"])

    covers = []
    for a in feats.areas:
        lc = styles.landcover(a.tags)
        if lc:
            covers.append((lc[1], lc[0], a.geom))
    for prio, mat, g in sorted(covers, key=lambda c: c[0]):
        fill(g, COLORS.get(mat, COLORS["urban"]))
    for a in feats.areas:
        if "building" in a.tags:
            lv = styles._num(a.tags.get("building:levels"), 1)
            fill(a.geom, COLORS["tower"] if lv and lv > 8 else COLORS["building"])
    for wy in feats.ways:
        t = wy.tags
        hw = t.get("highway")
        if hw in styles.DRIVABLE and hw not in ("service", "track") and not styles.is_tunnel(t):
            width = max(1, int(round(styles.road_width(t) / PX)))
            major = hw in ("motorway", "trunk", "primary", "motorway_link", "trunk_link")
            draw.line(px(wy.coords), fill=COLORS["major" if major else "road"], width=width)
        elif t.get("railway") == "rail" and not styles.is_tunnel(t):
            draw.line(px(wy.coords), fill=COLORS["rail"], width=1)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    heights = hf.H.astype(np.float32)
    # Rivers sit a little under the tiles' water surface.
    heights = np.maximum(heights, -1.0)
    nj, ni = heights.shape
    data = {
        "format": 1,
        # Godot position of height sample (0, 0) and of the texture's top-left corner.
        "origin": [float(e0), 0.0, float(-n0)],
        "step": HSTEP, "nx": int(ni), "nz": int(nj),
        "heights": heights.ravel(),  # row-major, rows going north
        "texture_png": np.frombuffer(buf.getvalue(), dtype=np.uint8),
        "texture_rect": [float(e0), float(-n1), float(e1 - e0), float(n1 - n0)],  # x, z, width, depth
    }
    blob = pack_tile(data)
    out_path.write_bytes(blob)
    return len(blob)
