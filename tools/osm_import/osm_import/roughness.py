"""Survey how smooth the roads are in built tiles.

    cd tools/osm_import
    python -m osm_import.roughness                  # every tile in the index
    python -m osm_import.roughness --region first_slice
    python -m osm_import.roughness --tiles 0_0 0_-1 --worst 20

Each road in the tiles' traffic data (.p5r) is walked along its centre line
every metre, reading the height of the road surface the game actually loads
(the asphalt in the .p5t, or a bridge deck or tunnel floor). It reports:

- bump: how far the surface strays from a straight line through the points
  2.5 m either side (the second difference). A real road's vertical curves
  keep this to a centimetre or two; a lump the car feels is 5 cm or more.
- kink: change of grade between the 5 m before and the 5 m after a point.
- cross: height difference across the road between points 0.8 m in from
  each edge, per metre of width (camber or a crossfall).
- seam: height step where the road crosses a tile edge.
- low decks: places where a bridge passes less than 4 m over the road.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .common import TILES_DIR
from .tileread import HeightQuery, read_container, tile_surfaces

STEP = 1.0
BUMP_D = 2.5      # half span of the bump (second difference) test, metres
KINK_D = 5.0
BUMP_LIMIT = 0.05
KINK_LIMIT = 0.04
CROSS_LIMIT = 0.04
SEAM_LIMIT = 0.05
CLEARANCE_MIN = 4.0  # headroom under a bridge deck over a road
CROSS_REACH = 1.0  # cross samples further than this from the road's own height hit something else
EDGE_REACH = 6.0  # metres from a tile edge where the neighbour tile is checked too
SURFACES = {("roads", "asphalt"), ("tunnels", "asphalt"), ("bridges", "asphalt"),
            ("bridges", "deck"), ("roads", "kerb"), ("roads", "sidewalk")}
ROAD_ONLY = {("roads", "asphalt"), ("tunnels", "asphalt"), ("bridges", "asphalt"), ("bridges", "deck")}


class TileSurfaces:
    """Lazily loaded road-surface height queries per tile."""

    def __init__(self, tiles_dir: Path, size: float):
        self.dir, self.size = tiles_dir, size
        self.cache: dict[str, HeightQuery | None] = {}

    def query(self, name: str):
        if name not in self.cache:
            path = self.dir / f"{name}.p5t"
            q = None
            if path.exists():
                surf = tile_surfaces(path)
                parts = [v for k, v in surf.items() if k in ROAD_ONLY or k[0] == "bridges"]
                if parts:
                    pos, tris, off = [], [], 0
                    for p, t in parts:
                        pos.append(p)
                        tris.append(t + off)
                        off += len(p)
                    q = HeightQuery(np.concatenate(pos), np.concatenate(tris))
            self.cache[name] = q
        return self.cache[name]

    def heights(self, x, z, ref, above=None):
        """Road height at Godot (x, z), the hit nearest `ref` (the road's own
        height, so an overpass above doesn't count)."""
        x, z, ref = map(np.asarray, (x, z, ref))
        out = np.full(len(x), np.nan)
        ti = np.floor(x / self.size).astype(int)
        tj = np.floor(-z / self.size).astype(int)
        # A ribbon (bridge deck, tunnel floor) crossing a tile edge belongs to
        # one of the two tiles, so points near an edge look in the neighbours too.
        fx = x / self.size - ti
        fz = -z / self.size - tj
        edge = EDGE_REACH / self.size
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                near = np.ones(len(x), dtype=bool)
                if di:
                    near &= (fx < edge) if di < 0 else (fx > 1 - edge)
                if dj:
                    near &= (fz < edge) if dj < 0 else (fz > 1 - edge)
                for key in set(zip((ti[near] + di).tolist(), (tj[near] + dj).tolist())):
                    sel = near & (ti + di == key[0]) & (tj + dj == key[1])
                    q = self.query(f"{key[0]}_{key[1]}")
                    if q is None:
                        continue
                    h = q.heights_near(x[sel], z[sel], ref[sel], above)
                    cur = out[sel]
                    if above is None:
                        better = np.isfinite(h) & (~np.isfinite(cur) | (np.abs(h - ref[sel]) < np.abs(cur - ref[sel])))
                    else:
                        better = np.isfinite(h) & (~np.isfinite(cur) | (h < cur))
                    cur[better] = h[better]
                    out[sel] = cur
        return out


@dataclass
class Report:
    samples: int = 0
    metres: float = 0.0
    bumps: list = field(default_factory=list)     # (value, x, z, road name, tile)
    kinks: list = field(default_factory=list)
    cross: list = field(default_factory=list)
    seams: list = field(default_factory=list)
    low: list = field(default_factory=list)       # (clearance, x, z, road name) under a deck
    bump_vals: list = field(default_factory=list)
    kink_vals: list = field(default_factory=list)
    cross_vals: list = field(default_factory=list)

    def summary(self) -> dict:
        def stats(v, lim):
            v = np.abs(np.asarray(v)) if len(v) else np.zeros(1)
            return {"p50": round(float(np.percentile(v, 50)), 3), "p95": round(float(np.percentile(v, 95)), 3),
                    "p99": round(float(np.percentile(v, 99)), 3), "max": round(float(v.max()), 3),
                    "over_per_km": round(float((v > lim).sum()) / max(self.metres / 1000.0, 1e-6), 1)}
        return {"km": round(self.metres / 1000.0, 1),
                "bump": stats(self.bump_vals, BUMP_LIMIT), "kink": stats(self.kink_vals, KINK_LIMIT),
                "cross": stats(self.cross_vals, CROSS_LIMIT),
                "low_decks": len(self.low),
                "seams_over": sum(1 for s in self.seams if abs(s[0]) > SEAM_LIMIT),
                "seam_max": round(max((abs(s[0]) for s in self.seams), default=0.0), 3)}


def _walk(pts: np.ndarray, step: float):
    xz = pts[:, [0, 2]].astype(np.float64)
    seg = np.linalg.norm(np.diff(xz, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] < 4 * BUMP_D:
        return None
    ss = np.arange(0.0, s[-1] + 1e-6, step)
    x = np.interp(ss, s, xz[:, 0])
    z = np.interp(ss, s, xz[:, 1])
    y = np.interp(ss, s, pts[:, 1].astype(np.float64))
    k = np.clip(np.searchsorted(s, ss, side="right") - 1, 0, len(seg) - 1)
    d = np.diff(xz, axis=0)[k]
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    return ss, x, z, y, d


def survey(tile_names, tiles_dir: Path = TILES_DIR, size: float = 500.0,
           junction_clear: float = 12.0) -> Report:
    ts = TileSurfaces(tiles_dir, size)
    rep = Report()
    seen = set()
    for name in tile_names:
        path = tiles_dir / f"{name}.p5r"
        if not path.exists():
            continue
        data = read_container(path)
        for r in data.get("roads", []):
            if r["id"] in seen:
                continue
            seen.add(r["id"])
            walk = _walk(r["pts"], STEP)
            if walk is None:
                continue
            ss, x, z, y, d = walk
            ref = y - 0.05
            h = ts.heights(x, z, ref)
            # Junctions: roads cross and merge there, so the profile of one
            # arm isn't meant to be smooth through the middle.
            keep = (ss > junction_clear) & (ss < ss[-1] - junction_clear)
            n = int(round(BUMP_D / STEP))
            m = int(round(KINK_D / STEP))
            ok = np.isfinite(h)
            label = r.get("name") or r.get("kind", "")
            if len(h) > 2 * m:
                b = np.full(len(h), np.nan)
                b[n:-n] = h[n:-n] - 0.5 * (h[:-2 * n] + h[2 * n:])
                kk = np.full(len(h), np.nan)
                kk[m:-m] = (h[2 * m:] - h[m:-m]) / KINK_D - (h[m:-m] - h[:-2 * m]) / KINK_D
                for vals, store, lim, arr in ((b, rep.bumps, BUMP_LIMIT, rep.bump_vals),
                                              (kk, rep.kinks, KINK_LIMIT, rep.kink_vals)):
                    good = keep & np.isfinite(vals)
                    arr.extend(vals[good].tolist())
                    for q in np.nonzero(good & (np.abs(vals) > lim))[0]:
                        store.append((float(vals[q]), float(x[q]), float(z[q]), label))
            # Across the road.
            half = max(float(r["width"]) / 2 - 0.8, 0.5)
            nx, nz = -d[:, 1], d[:, 0]
            hl = ts.heights(x + nx * half, z + nz * half, ref)
            hr = ts.heights(x - nx * half, z - nz * half, ref)
            # Off this road's asphalt (another road's, a deck, a tunnel): not a crossfall.
            hl[np.abs(hl - ref) > CROSS_REACH] = np.nan
            hr[np.abs(hr - ref) > CROSS_REACH] = np.nan
            c = (hl - hr) / (2 * half)
            good = keep & np.isfinite(c) & ok
            rep.cross_vals.extend(c[good].tolist())
            for q in np.nonzero(good & (np.abs(c) > CROSS_LIMIT))[0]:
                rep.cross.append((float(c[q]), float(x[q]), float(z[q]), label))
            # Headroom under bridges over this road.
            top = ts.heights(x, z, h, above=1.2)  # (not its own parapets)
            clear = top - h
            for q in np.nonzero(np.isfinite(clear) & (clear < CLEARANCE_MIN))[0]:
                rep.low.append((float(clear[q]), float(x[q]), float(z[q]), label))
            # Tile seams.
            ti = np.floor(x / size).astype(int)
            tj = np.floor(-z / size).astype(int)
            for q in np.nonzero((np.diff(ti) != 0) | (np.diff(tj) != 0))[0]:
                if ok[q] and ok[q + 1] and keep[q]:
                    # Expected change from the slope on either side.
                    lo, hi = max(q - 2, 0), min(q + 3, len(h) - 1)
                    slope = 0.5 * ((h[q] - h[lo]) / max(q - lo, 1) + (h[hi] - h[q + 1]) / max(hi - q - 1, 1))
                    rep.seams.append((float(h[q + 1] - h[q] - slope), float(x[q]), float(z[q]), label))
            rep.samples += int(ok.sum())
            rep.metres += float(ss[-1])
    return rep


def _tiles_for(args, index) -> list[str]:
    tiles = index["tiles"]
    if args.tiles:
        return args.tiles
    if args.region:
        return [k for k, v in tiles.items() if v.get("region") in args.region]
    return list(tiles)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tiles", nargs="*")
    ap.add_argument("--region", nargs="*")
    ap.add_argument("--dir", default=str(TILES_DIR))
    ap.add_argument("--worst", type=int, default=10)
    ap.add_argument("--json", help="write the summary and worst spots here")
    args = ap.parse_args(argv)
    tiles_dir = Path(args.dir)
    index = json.loads((tiles_dir / "index.json").read_text())
    names = _tiles_for(args, index)
    rep = survey(names, tiles_dir, float(index.get("tile_size", 500)))
    summ = rep.summary()
    print(json.dumps(summ, indent=1))
    worst = {}
    for kind, items in (("bumps", rep.bumps), ("kinks", rep.kinks), ("cross", rep.cross), ("seams", rep.seams),
                        ("low_decks", rep.low)):
        items = sorted(items, key=lambda t: abs(t[0]) if kind == "low_decks" else -abs(t[0]))[:args.worst]
        worst[kind] = [{"v": round(v, 3), "x": round(x, 1), "z": round(z, 1), "road": nm} for v, x, z, nm in items]
        print(f"worst {kind}:")
        for it in worst[kind]:
            print(f"  {it['v']:+.3f}  at ({it['x']:.0f}, {it['z']:.0f})  {it['road']}")
    if args.json:
        Path(args.json).write_text(json.dumps({"summary": summ, "worst": worst}, indent=1))


if __name__ == "__main__":
    main()
