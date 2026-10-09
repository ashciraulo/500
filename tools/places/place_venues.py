#!/usr/bin/env python3
"""Finds each Northbridge venue's shopfront on the built map and writes
data/world/venues.json.

The venues (cafes, bars, pubs, restaurants) are real places from
OpenStreetMap, listed by hand in tools/places/venues_src.json with made-up
names and the look of the real one (see art/models/scripts/lib/venues.py).
Each is built as a shopfront on the front wall of its building, so this
reads the built tiles (map/tiles/*.p5t, no Godot needed) and for every venue:

- finds the building wall nearest the venue's OSM point that faces its
  street (outside is open ground and a road is within reach in front);
- takes a stretch of that wall as wide as the venue wants (or as the wall
  allows), centred on the venue, and keeps neighbours on one wall apart;
- measures the footpath in front: its height on a 0.5 m grid (local x along
  the wall, z out from it) and how far it is to the kerb;
- lists the street trees and lights in front, so tables and posts miss them.

    python3 tools/places/place_venues.py [--only=id,id] [--plot=out.png]

Frame (scripts/world/venue.gd): origin on the footpath at the wall, at the
middle of the shopfront; +x along the wall, +z out to the street. `yaw`
turns that frame about Y (Basis(UP, yaw)). y is the footpath at the wall.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/osm_import"))

from osm_import.common import Projector, load_config  # noqa: E402
from osm_import.tileread import HeightQuery, read_container, tile_surfaces  # noqa: E402

SRC = ROOT / "tools/places/venues_src.json"
OUT = ROOT / "data/world/venues.json"
TILES = ROOT / "map/tiles"
TILE = 500.0

REACH = 35.0          # how far from the OSM point the shopfront may be
MIN_WALL = 3.0        # shortest wall worth a shopfront
END_MARGIN = 0.25     # keep the shopfront this far in from the wall's ends
NEIGHBOUR_GAP = 0.6   # between two venues on one wall
KERB_SEARCH = 16.0    # metres out from the wall to look for the road
GRID = 0.5            # footpath sample spacing
SIDE = 1.5            # sample this far past each end of the shopfront
OBSTACLE_KINDS = ("tree_round", "tree_gum", "tree_palm", "street_light")


def frame(yaw):
    """Unit x and z of a node rotated `yaw` about Y (Godot), in world x/z."""
    return np.array([math.cos(yaw), -math.sin(yaw)]), np.array([math.sin(yaw), math.cos(yaw)])


class Map:
    """The built tiles around the venues: walls, roofs, ground and props."""

    def __init__(self, keys):
        roofs, walk, road, walls = [], [], [], []
        self.obstacles = []
        self.streets = []   # (name, points (n, 2) in world x/z)
        for key in keys:
            rpath = TILES / f"{key[0]}_{key[1]}.p5r"
            if rpath.exists():
                for r in read_container(rpath).get("roads", []):
                    if r.get("name"):
                        self.streets.append((r["name"], np.asarray(r["pts"], dtype=np.float64)[:, [0, 2]]))
            path = TILES / f"{key[0]}_{key[1]}.p5t"
            if not path.exists():
                continue
            for (mesh, mat), (pos, tri) in tile_surfaces(path).items():
                if mesh == "buildings" and mat.startswith("facade"):
                    walls.append(pos[tri])
                elif mesh in ("buildings", "landmarks"):
                    roofs.append((pos, tri))
                elif mesh in ("ground", "roads") and mat != "kerb":
                    (road if mat == "asphalt" else walk).append((pos, tri))
            d = read_container(path)
            ox, _, oz = d["origin"]
            for kind, arr in d.get("instances", {}).items():
                if kind not in OBSTACLE_KINDS:
                    continue
                a = np.asarray(arr, dtype=np.float64).reshape(-1, 5)
                for x, y, z, _yaw, scale in a:
                    self.obstacles.append((kind, x + ox, z + oz, scale))
        self.roof = _query(roofs)
        self.walk = _query(walk)
        self.road = _query(road)
        self.segs = _wall_segments(walls)

    def has_roof(self, x, z):
        return not np.isnan(self.roof.heights([x], [z])[0])

    def is_road(self, x, z):
        return not np.isnan(self.road.heights([x], [z])[0])

    def street_at(self, x, z):
        """Name of the named street nearest a point."""
        best, name = math.inf, ""
        q = np.array([x, z])
        for n, pts in self.streets:
            a, b = pts[:-1], pts[1:]
            ab = b - a
            t = np.clip(((q - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
            d = float(np.min(np.linalg.norm(a + ab * t[:, None] - q, axis=1)))
            if d < best:
                best, name = d, n
        return name


def _query(parts):
    pos, tri, base = [], [], 0
    for p, t in parts:
        pos.append(p)
        tri.append(t + base)
        base += len(p)
    return HeightQuery(np.vstack(pos), np.vstack(tri))


def _wall_segments(walls):
    """Plan segments (a, b) of the vertical wall quads, joined where one wall
    runs straight on into the next."""
    seen = {}
    segs = []
    for p in walls:
        n = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
        ln = np.linalg.norm(n, axis=1)
        for t in p[np.abs(n[:, 1]) < 0.05 * np.maximum(ln, 1e-9)]:
            pts = []
            for q in t[:, [0, 2]]:
                if not any(math.hypot(*(q - r)) < 0.02 for r in pts):
                    pts.append(q)
            if len(pts) != 2:
                continue
            a, b = sorted([tuple(np.round(pts[0], 2)), tuple(np.round(pts[1], 2))])
            top = float(t[:, 1].max())
            if (a, b) not in seen:
                seen[(a, b)] = len(segs)
                segs.append([np.array(a), np.array(b), top])
            else:
                seg = segs[seen[(a, b)]]
                seg[2] = max(seg[2], top)
    return segs


def frontage(m: Map, v: dict, at: np.ndarray):
    """The wall (a, b, outward normal, metres to the road) the venue fronts."""
    best = None
    for a, b, top in m.segs:
        ab = b - a
        length = float(np.linalg.norm(ab))
        if length < MIN_WALL:
            continue
        t = float(np.clip(np.dot(at - a, ab) / length ** 2, 0.0, 1.0))
        dist = float(np.linalg.norm(at - (a + ab * t)))
        if dist > REACH:
            continue
        u = ab / length
        nrm = np.array([-u[1], u[0]])
        mid = (a + b) / 2
        out_roof, in_roof = m.has_roof(*(mid + nrm * 0.6)), m.has_roof(*(mid - nrm * 0.6))
        if out_roof == in_roof:
            continue  # a party wall, or a freestanding one
        if out_roof:
            nrm = -nrm
        kerb = None
        for s in np.arange(0.5, KERB_SEARCH, 0.5):
            x, z = mid + nrm * s
            if m.has_roof(x, z):
                break
            if m.is_road(x, z):
                kerb = float(s)
                break
        if kerb is None and not v.get("lane"):
            continue
        # The street it's on: "William St" matches "William Street".
        named = m.street_at(*(mid + nrm * ((kerb or 2.0) + 2.0)))
        on_street = named.split(" ")[0] == v["street"].split(" ")[0]
        score = dist - min(length, 12.0) * 0.3 + (0.0 if kerb is not None else 6.0) + \
            (0.0 if on_street or v.get("lane") else 15.0)
        if best is None or score < best[0]:
            best = (score, a, b, nrm, kerb if kerb is not None else 0.0, top)
    return best


def main():
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--only=")), None)
    plot = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--plot=")), None)
    src = json.loads(SRC.read_text())
    proj = Projector.from_config(load_config())
    venues = src["venues"]
    for v in venues:
        e, n = proj.fwd(v["lon"], v["lat"])
        # `at` (world x, z) moves the search to the real frontage when OSM's
        # point is deep inside a block (a food court's middle).
        v["_at"] = np.array(v["at"], dtype=np.float64) if "at" in v else np.array([e, -n])
    keys = sorted({(math.floor(v["_at"][0] / TILE) + di, math.floor(-v["_at"][1] / TILE) + dj)
                   for v in venues for di in (-1, 0, 1) for dj in (-1, 0, 1)})
    m = Map(keys)
    print(f"{len(m.segs)} wall segments, {len(m.obstacles)} trees and lights")
    placed = []
    for v in venues:
        f = frontage(m, v, v["_at"])
        if f is None:
            print(f"  {v['id']}: no wall faces a street near it")
            continue
        _, a, b, nrm, kerb, top = f
        length = float(np.linalg.norm(b - a))
        u = (b - a) / length
        # Godot frame: +z out of the wall, +x along it (x = z rotated -90 deg about Y).
        yaw = math.atan2(nrm[0], nrm[1])
        ux, _ = frame(yaw)
        if np.dot(ux, u) < 0:
            a, b, u = b, a, -u
        t = float(np.dot(v["_at"] - a, u))
        placed.append({"v": v, "a": a, "u": u, "len": length, "t": t, "yaw": yaw, "nrm": nrm, "kerb": kerb,
                       "top": top})
    _share_walls(placed)
    out_prev = {e["id"]: e for e in json.loads(OUT.read_text())["venues"]} if OUT.exists() else {}
    out = []
    for p in placed:
        v = p["v"]
        if only and v["id"] not in only:
            if v["id"] in out_prev:
                out.append(out_prev[v["id"]])
            continue
        centre = p["a"] + p["u"] * p["mid"]
        width = p["width"]
        ux, uz = frame(p["yaw"])
        depth = max(p["kerb"], 1.5)
        xs = np.arange(-width / 2 - SIDE, width / 2 + SIDE + 1e-6, GRID)
        zs = np.arange(0.0, depth + 1e-6, GRID)
        gx, gz = np.meshgrid(xs, zs)
        wx = centre[0] + gx.ravel() * ux[0] + gz.ravel() * uz[0]
        wz = centre[1] + gx.ravel() * ux[1] + gz.ravel() * uz[1]
        # Just off the wall, so the sample sees the footpath not the facade foot.
        wx0 = wx + uz[0] * np.where(gz.ravel() == 0.0, 0.15, 0.0)
        wz0 = wz + uz[1] * np.where(gz.ravel() == 0.0, 0.15, 0.0)
        h = m.walk.heights(wx0, wz0)
        y0 = float(np.nanmedian(h[gz.ravel() < 1.01]))
        h = np.where(np.isnan(h), y0, h) - y0
        obstacles = []
        for kind, ox, oz, scale in m.obstacles:
            d = np.array([ox, oz]) - centre
            lx, lz = float(np.dot(d, ux)), float(np.dot(d, uz))
            if abs(lx) <= width / 2 + 2.0 and -0.5 <= lz <= depth + 1.0:
                obstacles.append([kind, round(lx, 2), round(lz, 2)])
        moved = float(np.linalg.norm(centre - v["_at"]))
        entry = {
            "id": v["id"], "name": v["name"], "kind": v["kind"], "street": v["street"],
            "position": [round(float(centre[0]), 2), round(y0, 2), round(float(centre[1]), 2)],
            "yaw": round(p["yaw"], 4), "width": round(width, 2), "depth": round(depth, 2),
            "wall_top": round(p["top"] - y0, 2),
            "scene": f"res://art/models/props/venues/{v['id']}.glb",
            "ground_x": [round(float(xs[0]), 2), len(xs)], "ground_z": len(zs),
            "ground": [round(float(x), 2) for x in h],
            "obstacles": obstacles,
        }
        for k in ("sound", "hours", "outdoor"):
            if k in v:
                entry[k] = v[k]
        out.append(entry)
        print(f"  {v['id']:24s} {v['street']:16s} wall {p['len']:5.1f} m, shopfront {width:4.1f} m, "
              f"kerb {p['kerb']:4.1f} m out, {len(obstacles)} in front, {moved:4.1f} m from OSM")
    out.sort(key=lambda e: e["id"])
    OUT.write_text(json.dumps({"_comment": (
        "Northbridge cafes, bars, pubs and restaurants, from tools/places/place_venues.py "
        "(tools/places/venues_src.json). position is the middle of the shopfront on the footpath at "
        "the building's wall; yaw turns scripts/world/venue.gd's frame (+z out to the street); width "
        "is the shopfront along the wall and depth the footpath out to the kerb; wall_top how high the building's wall goes; ground is the "
        "footpath's height above position on a 0.5 m grid (x from ground_x[0], ground_x[1] points, "
        "fastest; z from 0 out, ground_z points); obstacles are street trees and lights in front "
        "(kind, local x, z). scene is the venue's model (art/models/scripts/build_venues.py)."),
        "venues": out}, indent=None, separators=(", ", ": ")).replace("}, {", "},\n{") + "\n")
    print(f"{len(out)} venues -> {OUT.relative_to(ROOT)}")
    if plot:
        _plot(m, out, plot)


def _share_walls(placed):
    """Width and centre (along its wall) of each venue's shopfront; venues
    on one wall split it between them."""
    groups = {}
    for p in placed:
        key = (tuple(np.round(p["a"], 1)), tuple(np.round(p["u"], 2)))
        groups.setdefault(key, []).append(p)
    for group in groups.values():
        group.sort(key=lambda p: p["t"])
        lo_all, hi_all = END_MARGIN, group[0]["len"] - END_MARGIN
        for i, p in enumerate(group):
            want = float(p["v"].get("width", 8.0))
            lo = lo_all if i == 0 else (group[i - 1]["t"] + p["t"]) / 2 + NEIGHBOUR_GAP / 2
            hi = hi_all if i == len(group) - 1 else (p["t"] + group[i + 1]["t"]) / 2 - NEIGHBOUR_GAP / 2
            width = min(want, hi - lo)
            mid = float(np.clip(p["t"] + p["v"].get("shift", 0.0), lo + width / 2, hi - width / 2))
            p["width"], p["mid"] = width, mid


def _plot(m, out, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    xs = [e["position"][0] for e in out]
    zs = [e["position"][2] for e in out]
    fig, ax = plt.subplots(figsize=(18, 14), dpi=100)
    for a, b, _top in m.segs:
        if min(xs) - 60 < a[0] < max(xs) + 60 and min(zs) - 60 < a[1] < max(zs) + 60:
            ax.plot([a[0], b[0]], [a[1], b[1]], color="#b08060", lw=0.6)
    for e in out:
        ux, uz = frame(e["yaw"])
        c = np.array([e["position"][0], e["position"][2]])
        w = e["width"]
        p0, p1 = c - ux * w / 2, c + ux * w / 2
        ax.plot([p0[0], p1[0]], [p0[1], p1[1]], color="red", lw=2.5)
        q = c + uz * e["depth"]
        ax.plot([c[0], q[0]], [c[1], q[1]], color="blue", lw=0.8)
        ax.text(c[0] + uz[0] * 3, c[1] + uz[1] * 3, e["name"], fontsize=6)
    ax.set_xlim(min(xs) - 40, max(xs) + 40)
    ax.set_ylim(max(zs) + 40, min(zs) - 40)
    ax.set_aspect("equal")
    plt.savefig(path, bbox_inches="tight")


if __name__ == "__main__":
    main()
