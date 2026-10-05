"""The far-distance backdrop: a coarse heightfield draped with a painted map.

Streamed tiles only reach about a kilometre; past that the game draws this
instead, so the horizon shows the rest of the city, the river and the hills.
"""
from __future__ import annotations

import io
import math

import numpy as np
import shapely
from shapely.geometry import box as sbox
from PIL import Image, ImageDraw

from . import styles
from .common import Projector
from .extract import extract
from .fetch import osm_pbf
from .meshbuild import polygons_of, triangulate
from .sea import merged_coast, sea_polygon
from .terrain import build_heightfield
from .variant import pack_tile

TOWER_MIN_H = 24.0  # buildings at least this tall stand up out of the backdrop
TOWER_COLORS = {"facade_glass": (118, 140, 158), "facade_office": (168, 168, 160),
                "facade_apartment": (192, 184, 168), "facade_heritage": (176, 142, 112),
                "facade_carpark": (150, 150, 146)}
SUN = np.array([0.55, 0.0, -0.83])  # a north-easterly light for the baked wall shading

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
    sea = sea_polygon(merged_coast(feats.ways), sbox(e0, n0, e1, n1))
    if sea is not None:
        fill(sea, COLORS["water"])
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

    towers = _towers(cfg, proj, feats, hf)
    sea_mesh = _sea_mesh(sea, tiles, size)
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
        # Tall buildings as plain blocks so the skyline shows from anywhere:
        # triangle soup. uv = (metres along the wall, metres up) for walls,
        # (-1, -1) on roofs; colour alpha is a per-building seed for which
        # windows are lit at night.
        **towers,
        # The sea surface past the streamed tiles (they draw their own), at
        # height 0 and drawn near the camera too: triangle soup, Godot x/z.
        **sea_mesh,
    }
    blob = pack_tile(data)
    out_path.write_bytes(blob)
    return len(blob)


def _sea_mesh(sea, tiles: dict, size: float) -> dict:
    if sea is None:
        return {}
    built = shapely.union_all([sbox(t["i"] * size, t["j"] * size, (t["i"] + 1) * size, (t["j"] + 1) * size)
                               for t in tiles.values()])
    rest = sea.difference(built).simplify(PX)
    verts = []
    for p in polygons_of(rest):
        if p.area < 100:
            continue
        pv, pt = triangulate(p)
        if len(pt):
            verts.append(pv[np.asarray(pt).ravel()])
    if not verts:
        return {}
    v = np.concatenate(verts)
    return {"sea_xz": np.column_stack([v[:, 0], -v[:, 1]]).astype(np.float32)}


def _towers(cfg, proj, feats, hf) -> dict:
    import shapely
    from shapely.geometry import box as sbox
    cb = cfg.get("cbd_bbox")
    cbd = None
    if cb:
        (ce0, ce1), (cn0, cn1) = proj.fwd([cb[0], cb[2]], [cb[1], cb[3]])
        cbd = sbox(ce0, cn0, ce1, cn1)
    pos, uv, col = [], [], []
    count = 0
    for a in feats.areas:
        t = a.tags
        if not ("building" in t or "building:part" in t) or t.get("building") in ("no", "roof", "construction"):
            continue
        g = a.geom
        if g.is_empty or g.area < 60:
            continue
        rp = g.representative_point()
        incbd = bool(cbd is not None and cbd.contains(rp))
        minh, h = styles.building_height(t, g.area, a.id, incbd)
        if h < TOWER_MIN_H or (minh > 0 and "building:part" in t and minh > h * 0.8):
            continue
        poly = max(g.geoms, key=lambda p: p.area) if g.geom_type == "MultiPolygon" else g
        poly = poly.buffer(-0.6).simplify(1.5)
        if poly.is_empty or poly.geom_type != "Polygon":
            continue
        ring = np.asarray(poly.exterior.coords)[:-1]
        if len(ring) > 24:
            ring = np.asarray(poly.minimum_rotated_rectangle.exterior.coords)[:-1]
        if not shapely.LinearRing(ring).is_ccw:
            ring = ring[::-1]
        base = min(float(hf.sample(e, n)) for e, n in ring)
        y0, y1 = base + max(0.0, minh), base + h - 0.6
        _, upper = styles.facade(t, h, g.area, incbd, a.id)
        c = np.array(TOWER_COLORS.get(upper, TOWER_COLORS["facade_office"]), float)
        seed = int(styles.stable_rng("tw", a.id).integers(0, 256))
        along = 0.0
        for k in range(len(ring)):
            (ea, na), (eb, nb) = ring[k], ring[(k + 1) % len(ring)]
            L = math.hypot(eb - ea, nb - na)
            if L < 0.3:
                continue
            # Outward normal of a CCW ring in plan (e, n): (dn, -de).
            nrm = np.array([(nb - na) / L, 0.0, (eb - ea) / L])  # Godot (x, y, z=-n)
            shade = 0.72 + 0.28 * max(0.0, float(nrm @ SUN))
            quad = [(ea, y0, na, along), (eb, y0, nb, along + L), (eb, y1, nb, along + L), (ea, y1, na, along)]
            for i in (0, 1, 2, 0, 2, 3):
                e, y, n, s = quad[i]
                pos.append((e, y, -n))
                uv.append((s, y - y0))
                col.append((*np.clip(c * shade, 0, 255), seed))
            along += L
        roof = shapely.Polygon(ring)
        try:
            from .meshbuild import triangulate
            v, tri = triangulate(roof)
        except Exception:
            continue
        rc = np.clip(c * 0.82, 0, 255)
        for t3 in tri:
            for i in t3[::-1]:
                pos.append((v[i][0], y1, -v[i][1]))
                uv.append((-1.0, -1.0))
                col.append((*rc, seed))
        count += 1
    print(f"  overview towers: {count}")
    return {
        "tower_pos": np.asarray(pos, np.float32).reshape(-1, 3),
        "tower_uv": np.asarray(uv, np.float32).reshape(-1, 2),
        "tower_col": np.asarray(col, np.uint8).reshape(-1),
    }
