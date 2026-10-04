"""Hand-built low-poly landmarks, placed on their OSM footprints.

The generic building extruder turns the Bell Tower into a box and Optus
Stadium into nothing at all, so a few places Perth people know on sight get
a model of their own here. Each one is built from simple lofts and boxes in
the same PS1 style as the rest of the map, on the footprint (or the bridge
deck) OSM gives it, so it lands in the right spot at the right size. OSM
buildings inside a landmark's footprint are dropped so they don't poke
through.

Coordinates are plan metres (e, n) with height h, like the rest of the
importer.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from shapely.geometry import LineString, Point, Polygon

from .meshbuild import MeshBuilder, Surface, flat_cap, polygons_of, triangulate

MESH = "landmarks"          # solid parts: drawn with buildings' collision layer
DETAIL = "landmark_detail"  # hangers, cables: no collision


@dataclass
class Landmark:
    id: str
    name: str
    kind: str                   # builder below
    osm: tuple                  # ("area" | "way", osm id)
    suburb: str = ""
    geom: object = None         # footprint polygon or deck line, filled from OSM
    h: object = None            # deck heights for a bridge line
    params: dict = field(default_factory=dict)

    @property
    def center(self) -> tuple[float, float]:
        c = self.geom.centroid if self.geom.geom_type != "LineString" else self.geom.interpolate(0.5, normalized=True)
        return float(c.x), float(c.y)

    def clear_zone(self):
        """Ground where OSM buildings are dropped for this landmark."""
        if self.geom.geom_type == "LineString":
            return Polygon()
        return self.geom.buffer(self.params.get("clear", 1.0))


# Perth landmarks. Ids are stable (the POI export and saves use them).
CATALOGUE = [
    Landmark("bell_tower", "The Bell Tower", "bell_tower", ("area", 147704624), "Perth"),
    Landmark("state_war_memorial", "State War Memorial", "obelisk", ("area", 51138412), "Kings Park"),
    Landmark("optus_stadium", "Optus Stadium", "stadium", ("area", 695799456), "Burswood", params={"clear": 8.0}),
    Landmark("round_house", "Round House", "round_house", ("area", 49965210), "Fremantle"),
    Landmark("indiana_tea_house", "Indiana Tea House", "tea_house", ("area", 44961447), "Cottesloe"),
    Landmark("elizabeth_quay_bridge", "Elizabeth Quay Bridge", "eq_bridge", ("way", 396347498), "Perth"),
    Landmark("matagarup_bridge", "Matagarup Bridge", "matagarup", ("way", 404705281), "East Perth"),
]


def collect(feats, ways) -> list[Landmark]:
    """The catalogue entries whose OSM feature is in this extract."""
    areas = {a.id: a for a in feats.areas}
    lines = {w.id: w for w in ways}
    out = []
    for lm in CATALOGUE:
        kind, oid = lm.osm
        found = Landmark(lm.id, lm.name, lm.kind, lm.osm, lm.suburb, params=dict(lm.params))
        if kind == "area" and oid in areas:
            polys = polygons_of(areas[oid].geom)
            if not polys:
                continue
            found.geom = max(polys, key=lambda p: p.area)
        elif kind == "way" and oid in lines:
            w = lines[oid]
            found.geom = LineString(w.xy)
            found.h = np.asarray(w.h, dtype=float)
        else:
            continue
        out.append(found)
    return out


# ---------------------------------------------------------------------------
# Geometry helpers. Rings are (k, 3) arrays of (e, n, h), counter-clockwise in
# plan; faces are flat-shaded (one normal a quad) for the PS1 look.
# ---------------------------------------------------------------------------

def _quad(surf: Surface, a, b, c, d, u0=0.0, u1=1.0, v0=0.0, v1=1.0, double=False):
    """Quad a-b-c-d (a, b bottom; c, d top), front face like meshbuild.walls."""
    v = np.array([a, b, c, d], dtype=float)
    mid = (v[2] + v[3]) / 2
    nrm = np.cross(v[1] - v[0], mid - v[0])
    ln = np.linalg.norm(nrm)
    if ln < 1e-9:
        nrm = np.cross(v[2] - v[0], v[3] - v[1])
        ln = np.linalg.norm(nrm)
        if ln < 1e-9:
            return
    nrm = nrm / ln
    uv = np.array([[u0, -v0], [u1, -v0], [u1, -v1], [u0, -v1]])
    surf.add(v, np.tile(nrm, (4, 1)), uv, np.array([[0, 1, 2], [0, 2, 3]]))
    if double:
        surf.add(v, np.tile(-nrm, (4, 1)), uv, np.array([[0, 2, 1], [0, 3, 2]]))


def loft(surf: Surface, lower, upper, u_scale=4.0, v_scale=4.0, closed=True, double=False):
    """Quads between two rings with the same vertex count (lower to upper)."""
    lower, upper = np.asarray(lower, float), np.asarray(upper, float)
    k = len(lower)
    seg = np.linalg.norm(np.diff(np.vstack([lower, lower[:1]]) if closed else lower, axis=0)[:, :2], axis=1)
    u = np.concatenate([[0.0], np.cumsum(seg)]) / u_scale
    for i in range(k if closed else k - 1):
        j = (i + 1) % k
        dv = float(np.linalg.norm(upper[i] - lower[i])) / v_scale
        _quad(surf, lower[i], lower[j], upper[j], upper[i], u[i], u[i + 1], 0.0, dv, double)


def circle(cx, cy, r, h, k=12, rot=0.0, rx=None):
    a = rot + np.arange(k) * math.tau / k
    return np.column_stack([cx + (rx or r) * np.cos(a), cy + r * np.sin(a), np.full(k, float(h))])


def scaled(ring, c, s, h=None):
    """`ring` scaled about plan point c, optionally set to height h."""
    out = np.array(ring, dtype=float)
    out[:, :2] = c + (out[:, :2] - c) * s
    if h is not None:
        out[:, 2] = h
    return out


def cap(surf: Surface, ring, uv_scale=4.0, down=False):
    """Flat cap over a ring (at its mean height)."""
    ring = np.asarray(ring, float)
    poly = Polygon(ring[:, :2])
    if not poly.is_valid or poly.area < 0.01:
        return
    flat_cap(surf, poly, float(ring[:, 2].mean()), uv_scale, down=down)


def apex(surf: Surface, ring, top, u_scale=4.0, v_scale=4.0):
    """Cone or pyramid from a ring up to one point."""
    loft(surf, ring, np.tile(np.asarray(top, float), (len(ring), 1)), u_scale, v_scale)


def prism(surf: Surface, ring2, bottom, top, u_scale=4.0, v_scale=4.0, top_surf=None):
    """Upright prism on a plan ring (k, 2): walls plus a lid."""
    ring2 = np.asarray(ring2, float)
    lo = np.column_stack([ring2, np.full(len(ring2), bottom)])
    hi = np.column_stack([ring2, np.full(len(ring2), top)])
    loft(surf, lo, hi, u_scale, v_scale)
    cap(top_surf or surf, hi, u_scale)


def tube(surf: Surface, path, w, d=None, u_scale=4.0):
    """A square-section beam (w wide, d deep) along a 3D path."""
    path = np.asarray(path, float)
    d = w if d is None else d
    rings = []
    for i, p in enumerate(path):
        t = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        t = t / max(np.linalg.norm(t), 1e-9)
        side = np.cross(t, [0, 0, 1.0])
        if np.linalg.norm(side) < 1e-6:
            side = np.array([1.0, 0, 0])
        side /= np.linalg.norm(side)
        up = np.cross(side, t)
        rings.append([p + side * w / 2 - up * d / 2, p + side * w / 2 + up * d / 2,
                      p - side * w / 2 + up * d / 2, p - side * w / 2 - up * d / 2])
    rings = np.asarray(rings)
    for i in range(len(path) - 1):
        for f in range(4):
            g = (f + 1) % 4
            _quad(surf, rings[i, g], rings[i, f], rings[i + 1, f], rings[i + 1, g], 0, w / u_scale, 0,
                  float(np.linalg.norm(path[i + 1] - path[i])) / u_scale)


def _resample_ring(poly: Polygon, k: int) -> np.ndarray:
    ext = LineString(poly.exterior.coords)
    return _ccw([ext.interpolate(i / k, normalized=True).coords[0] for i in range(k)])


def _signed(pts) -> float:
    x, y = pts[:, 0], pts[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y))


def _ccw(pts):
    pts = np.asarray(pts, float)
    return pts if _signed(pts) > 0 else pts[::-1]


def _axis(poly: Polygon) -> float:
    """Angle of the footprint's long side (radians from east)."""
    c = np.asarray(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    a, b = c[1] - c[0], c[2] - c[1]
    v = a if np.linalg.norm(a) >= np.linalg.norm(b) else b
    return math.atan2(v[1], v[0])


def _ground(hf, geom) -> float:
    if geom.geom_type == "LineString":
        xy = np.asarray(geom.coords)
    else:
        xy = np.asarray(geom.exterior.coords)
    return float(np.min(hf.sample(xy[:, 0], xy[:, 1]))) - 0.3


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

def build(mb: MeshBuilder, lm: Landmark, hf):
    BUILDERS[lm.kind](mb, lm, hf)


def _bell_tower(mb, lm, hf):
    """Glass spire between two copper sails (Barrack Square, 82.5 m)."""
    g = _ground(hf, lm.geom)
    c = np.array(lm.center)
    ang = _axis(lm.geom)
    glass = mb.surface(MESH, "facade_glass", "buildings")
    copper = mb.surface(MESH, "copper", "buildings")
    concrete = mb.surface(MESH, "concrete", "buildings")
    r0 = min(9.0, math.sqrt(lm.geom.area / math.pi) * 0.8)
    # Plinth and bell chamber shaft, tapering to a needle.
    prism(concrete, circle(*c, r0 + 2.0, 0, k=8, rot=ang)[:, :2], g, g + 1.2)
    levels = [(0.0, r0), (34.0, r0 * 0.78), (52.0, r0 * 0.6), (60.0, r0 * 0.32), (82.5, 0.25)]
    rings = [circle(*c, r, g + 1.2 + h, k=8, rot=ang + math.pi / 8) for h, r in levels]
    for lo, hi in zip(rings, rings[1:]):
        loft(glass, lo, hi, 4.0, 3.4)
    # Two copper sails, either side of the shaft, sweeping up and in.
    for side in (1.0, -1.0):
        out = np.array([math.cos(ang), math.sin(ang)]) * side
        across = np.array([-out[1], out[0]])
        pts_l, pts_r = [], []
        for t in np.linspace(0.0, 1.0, 9):
            reach = r0 + 4.5 * (1 - t) ** 0.7 + 0.5
            h = g + 1.2 + 74.0 * t
            half = 0.6 + 5.5 * (1 - t) ** 1.5
            p = c + out * reach * (1 - 0.85 * t ** 2)
            pts_l.append([*(p + across * half), h])
            pts_r.append([*(p - across * half), h])
        pts_l, pts_r = np.array(pts_l), np.array(pts_r)
        for i in range(len(pts_l) - 1):
            _quad(copper, pts_r[i], pts_l[i], pts_l[i + 1], pts_r[i + 1], 0, 1, i / 2, (i + 1) / 2, double=True)


def _obelisk(mb, lm, hf):
    """Kings Park's State War Memorial: a limestone obelisk on stepped terraces."""
    g = _ground(hf, lm.geom) + 0.3
    c = np.array(lm.center)
    ang = _axis(lm.geom) + math.pi / 4
    stone = mb.surface(MESH, "limestone", "buildings")
    h = g
    for half, step in ((8.0, 0.6), (6.5, 0.6), (5.0, 0.8), (2.6, 2.4)):
        prism(stone, circle(*c, half * math.sqrt(2), 0, k=4, rot=ang)[:, :2], h, h + step, 2.0, 2.0)
        h += step
    base = circle(*c, 2.0 * math.sqrt(2), h, k=4, rot=ang)
    top = circle(*c, 1.3 * math.sqrt(2), h + 15.5, k=4, rot=ang)
    loft(stone, base, top, 2.0, 2.0)
    apex(stone, top, [*c, h + 18.0], 2.0, 2.0)


def _stadium(mb, lm, hf):
    """Optus Stadium: bronze-finned bowl, white roof ring, the oval inside."""
    g = _ground(hf, lm.geom) + 0.3
    poly = lm.geom.buffer(-4.0)
    if poly.is_empty:
        poly = lm.geom
    poly = max(polygons_of(poly), key=lambda p: p.area)
    c = np.array(poly.centroid.coords[0])
    ring = _ccw(_resample_ring(poly.convex_hull, 48))
    bronze = mb.surface(MESH, "stadium_bronze", "buildings")
    fabric = mb.surface(MESH, "roof_fabric", "buildings")
    seats = mb.surface(MESH, "stadium_seats", "buildings")
    concrete = mb.surface(MESH, "concrete", "buildings")
    turf = mb.surface(MESH, "turf", "buildings")
    # Façade, leaning out a little as it rises.
    lo = np.column_stack([ring, np.full(len(ring), g)])
    mid = scaled(np.column_stack([ring, np.full(len(ring), g + 34.0)]), c, 1.03)
    loft(bronze, lo, mid, 2.0, 4.0)
    # Roof ring: up from the façade's lip, then in over the seats.
    lip = scaled(mid, c, 1.0, g + 37.0)
    inner = scaled(mid, c, 0.74, g + 42.0)
    loft(fabric, mid, lip, 6.0, 6.0)
    loft(fabric, lip, inner, 6.0, 6.0, double=True)
    # Seating bowl, raked down to the oval (faces inwards).
    top_seat = scaled(mid, c, 0.95, g + 30.0)
    field_edge = scaled(mid, c, 0.58, g + 1.5)
    loft(seats, top_seat, field_edge, 2.0, 1.2)
    loft(concrete, scaled(mid, c, 1.0, g + 30.0), top_seat, 4.0, 4.0)
    loft(concrete, scaled(field_edge, c, 1.0, g)[::-1], field_edge[::-1], 4.0, 4.0)  # faces the oval
    cap(turf, scaled(field_edge, c, 1.0, g + 0.2), 12.0)


def _round_house(mb, lm, hf):
    """Fremantle's Round House (1831): twelve limestone sides, a low roof."""
    g = _ground(hf, lm.geom)
    c = np.array(lm.center)
    r = max(4.0, math.sqrt(lm.geom.area / math.pi))
    stone = mb.surface(MESH, "limestone", "buildings")
    roof = mb.surface(MESH, "roof_metal", "buildings")
    ring = circle(*c, r, 0, k=12)[:, :2]
    prism(stone, ring, g, g + 5.4, 3.0, 3.0, top_surf=roof)
    # Parapet and a squat central lantern.
    loft(stone, circle(*c, r, g + 5.4, k=12), circle(*c, r, g + 6.0, k=12), 3.0, 3.0)
    prism(stone, circle(*c, r * 0.28, 0, k=12)[:, :2], g + 5.4, g + 6.6, 2.0, 2.0)


def _tea_house(mb, lm, hf):
    """Cottesloe's Indiana: cream walls, terracotta roofs, a tall central pavilion."""
    g = _ground(hf, lm.geom)
    poly = lm.geom.simplify(0.5)
    rect = poly.minimum_rotated_rectangle
    c = np.array(rect.centroid.coords[0])
    ang = _axis(rect)
    walls = mb.surface(MESH, "facade_render", "buildings")
    tiles = mb.surface(MESH, "roof_tiles", "buildings")
    ring = _ccw(np.asarray(poly.exterior.coords)[:-1])
    lo = np.column_stack([ring, np.full(len(ring), g)])
    hi = np.column_stack([ring, np.full(len(ring), g + 7.2)])
    loft(walls, lo, hi, 4.0, 3.6)
    cap(mb.surface(MESH, "roof_flat", "buildings"), hi, 6.0)
    # Hipped terracotta roof over the main block.
    cr = np.asarray(rect.exterior.coords)[:4]
    eave = scaled(np.column_stack([cr, np.full(4, g + 7.2)]), c, 0.92)
    ridge = scaled(np.column_stack([cr, np.full(4, g + 10.0)]), c, 0.45)
    loft(tiles, _ccw3(eave), _ccw3(ridge), 3.0, 3.0)
    cap(tiles, _ccw3(ridge), 3.0)
    # Central pavilion with its steep pyramid roof.
    side = min(11.0, math.sqrt(rect.area) * 0.35)
    sq = circle(*c, side / math.sqrt(2), 0, k=4, rot=ang + math.pi / 4)[:, :2]
    prism(walls, sq, g + 7.2, g + 13.0, 4.0, 3.6)
    top = circle(*c, side / math.sqrt(2) * 1.15, g + 13.0, k=4, rot=ang + math.pi / 4)
    apex(tiles, top, [*c, g + 21.0], 3.0, 3.0)


def _ccw3(ring3):
    ring3 = np.asarray(ring3, float)
    return ring3 if _signed(ring3[:, :2]) > 0 else ring3[::-1]


def _deck(lm, step):
    """Points along the bridge deck: (s, e, n, h) every `step` metres."""
    line = lm.geom
    seg = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(np.asarray(line.coords), axis=0), axis=1))])
    ss = np.linspace(0.0, line.length, max(2, int(line.length / step) + 1))
    out = []
    for s in ss:
        p = line.interpolate(s)
        out.append((s, p.x, p.y, float(np.interp(s, seg, lm.h)) + 0.6))
    return np.array(out)


def _side(lm, s):
    line = lm.geom
    a = np.asarray(line.interpolate(max(0.0, s - 1)).coords[0])
    b = np.asarray(line.interpolate(min(line.length, s + 1)).coords[0])
    t = (b - a) / max(np.linalg.norm(b - a), 1e-9)
    return np.array([-t[1], t[0]])


def _hangers(mb, arch, deck_h, every=3):
    det = mb.surface(DETAIL, "steel_white", None)
    for k in range(1, len(arch) - 1, every):
        p = arch[k]
        if p[2] - deck_h[k] < 1.5:
            continue
        tube(det, [[p[0], p[1], deck_h[k]], p], 0.12)


def _eq_bridge(mb, lm, hf):
    """Elizabeth Quay Bridge: two white arches crossing over an S-shaped deck."""
    d = _deck(lm, 4.0)
    steel = mb.surface(MESH, "steel_white", "buildings")
    n = len(d)
    for sign in (1.0, -1.0):
        path, deck_h = [], []
        for k, (s, e, nn, h) in enumerate(d):
            t = k / (n - 1)
            off = sign * 3.2 * (1 - 2 * t)  # the two arches cross mid-span
            p = np.array([e, nn]) + _side(lm, s) * off
            path.append([p[0], p[1], h + 22.0 * math.sin(math.pi * t)])
            deck_h.append(h)
        tube(steel, path, 0.9)
        _hangers(mb, np.array(path), deck_h)


def _matagarup(mb, lm, hf):
    """Matagarup Bridge: two tall steel arches, one from each bank, meeting
    the deck mid-river (the swans' necks)."""
    d = _deck(lm, 6.0)
    steel = mb.surface(MESH, "steel_white", "buildings")
    n = len(d)
    half = n // 2
    for idx in (range(0, half + 1), range(half, n)):
        idx = list(idx)
        m = len(idx)
        path, deck_h = [], []
        for q, k in enumerate(idx):
            s, e, nn, h = d[k]
            t = q / (m - 1)
            rise = 70.0 * math.sin(math.pi * t) ** 0.9
            path.append([e, nn, h + 1.0 + rise])
            deck_h.append(h)
        tube(steel, path, 3.0, 4.0, 6.0)
        _hangers(mb, np.array(path), deck_h, every=2)


BUILDERS = {
    "bell_tower": _bell_tower, "obelisk": _obelisk, "stadium": _stadium, "round_house": _round_house,
    "tea_house": _tea_house, "eq_bridge": _eq_bridge, "matagarup": _matagarup,
}
