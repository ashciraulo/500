"""Build Godot map tiles from OpenStreetMap.

    cd tools/osm_import
    python -m osm_import.build --region first_slice
    python -m osm_import.build --stage 2          # every region in stage 2
    python -m osm_import.build --tiles 0_-1 1_-1  # just these tiles

Output goes to map/tiles/ (one .p5t file per 500 m tile plus index.json).
"""
from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon, box as sbox
from shapely.geometry.polygon import orient

from . import fetch, landmarks, places, pois, styles, textures
from .traffic import TrafficNetwork
from .common import (CACHE_DIR, MAP_DIR, TILES_DIR, Projector, TileKey, load_config,
                     stable_rng, tiles_for_bbox)
from .extract import extract
from .overview import build_overview
from .heights import compute_node_heights, way_group
from .meshbuild import (CellGrid, MeshBuilder, Surface, densify, drape, flat_cap,
                        offset_polyline, polygons_of, ribbon, triangulate, walls)
from .terrain import HeightField, build_heightfield
from .tilewriter import write_tile
from .variant import pack_tile

RIVER_LEVEL = 0.0
HOME_RAMP = 30.0        # roads ease to the townhouse's ground over this distance
ROAD_OFFSET = 0.02      # road surface above terrain
PATH_OFFSET = 0.04
SIDEWALK_TOP = 0.16
MARK_OFFSET = 0.07
TUNNEL_HEIGHT = 5.6
DECK_THICKNESS = 1.1
PARAPET_H = 0.9


@dataclass
class LinearWay:
    id: int
    tags: dict
    group: str
    xy: np.ndarray
    h: np.ndarray
    nodes: np.ndarray
    width: float
    bridge: bool
    tunnel: bool
    sidewalk: bool

    @property
    def grade_separated(self) -> bool:
        return self.bridge or self.tunnel


@dataclass
class WaterBody:
    geom: object
    level: float
    big: bool


# ---------------------------------------------------------------------------
# World preparation (shared by every tile in a build)
# ---------------------------------------------------------------------------

class World:
    def __init__(self, cfg: dict, proj: Projector, feats, hf: HeightField):
        self.cfg, self.proj, self.hf = cfg, proj, hf
        self.tile_size = cfg["tile_size"]
        t0 = time.time()
        cb = cfg.get("cbd_bbox")
        if cb:
            (e0, e1), (n0, n1) = proj.fwd([cb[0], cb[2]], [cb[1], cb[3]])
            self.cbd = sbox(e0, n0, e1, n1)
        else:
            self.cbd = Polygon()

        # The townhouse scene is flat and replaces whatever OSM has on its block.
        self.home = places.home_site(cfg, proj)
        src_ways = feats.ways
        if self.home:
            self.home.h = self._home_ground()
            src_ways = [_split_at_edge(w, self.home.footprint) for w in feats.ways]
        node_h = compute_node_heights(src_ways, hf)
        self.carriageway_moves = _level_carriageways(src_ways, node_h)
        if self.home:
            self._level_to_home(src_ways, node_h)
        self.ways: list[LinearWay] = []
        for w in src_ways:
            g = way_group(w.tags)
            if not g:
                continue
            hmap = node_h[g]
            h = np.array([hmap[int(n)] for n in w.nodes])
            t = w.tags
            if g == "road":
                width = styles.road_width(t)
                sidewalk = t.get("highway") in styles.SIDEWALK and t.get("sidewalk") != "no"
            elif g == "foot":
                width = styles.FOOT_WIDTH.get(t.get("highway"), 2.0)
                sidewalk = False
            else:
                width = 3.2
                sidewalk = False
            self.ways.append(LinearWay(w.id, t, g, w.coords, h, w.nodes, width,
                                       styles.is_bridge(t), styles.is_tunnel(t), sidewalk))
        self.junctions = self._junction_nodes()

        self.water: list[WaterBody] = []
        self.cover: list[tuple[str, int, object]] = []
        self.buildings = []
        self.parts = []
        self.decks = []        # piers and platforms: (polygon, kind)
        self.parking = []      # amenity=parking / parking_space areas, for traffic
        for a in feats.areas:
            t = a.tags
            if t.get("amenity") in ("parking", "parking_space"):
                self.parking.append(a)
            if "building:part" in t:
                self.parts.append(a)
                continue
            if "building" in t and t.get("building") not in ("no", "roof", "construction") \
                    and t.get("location") not in ("underground",) and t.get("layer", "0") not in ("-1", "-2"):
                self.buildings.append(a)
                continue
            if t.get("man_made") == "pier" or t.get("railway") == "platform":
                self.decks.append((a.geom, "pier" if t.get("man_made") == "pier" else "platform"))
                continue
            lc = styles.landcover(t)
            if lc is None:
                continue
            mat, prio = lc
            if mat == "water":
                self.water.append(self._water_body(a))
            else:
                self.cover.append((mat, prio, a.geom))
        self._resolve_building_parts()
        if self.home:
            fp = self.home.footprint.buffer(0.5)
            self.buildings = [b for b in self.buildings if not fp.contains(b.geom.representative_point())]
        self.water_union = shapely.union_all([w.geom for w in self.water]) if self.water else Polygon()
        # Hand-built landmarks replace whatever OSM buildings stand on them.
        self.landmarks = landmarks.collect(feats, self.ways)
        zones = [z for z in (lm.clear_zone() for lm in self.landmarks) if not z.is_empty]
        self.landmark_zone = shapely.union_all(zones) if zones else Polygon()
        if zones:
            self.buildings = [b for b in self.buildings
                              if not self.landmark_zone.contains(b.geom.representative_point())]
        self.trees = feats.trees
        if zones and len(self.trees):
            self.trees = self.trees[~shapely.contains(self.landmark_zone, shapely.points(self.trees))]
        if self.home and len(self.trees):
            inside = shapely.contains(self.home.footprint, shapely.points(self.trees))
            self.trees = self.trees[~inside]
        self.named = feats.named_nodes
        self.control_nodes = feats.control_nodes
        self.bus_routes = getattr(feats, "bus_routes", [])
        self.poi_nodes = getattr(feats, "poi_nodes", [])
        self.poi_areas = [a for a in feats.areas if a.tags.get("natural") == "beach"
                          or a.tags.get("amenity") in ("fuel", "fast_food") or a.tags.get("tourism") == "zoo"]
        self._sculpt_terrain()
        print(f"  world prepared in {time.time() - t0:.1f}s: {len(self.ways)} ways, "
              f"{len(self.buildings)} buildings, {len(self.water)} water bodies")

    # -- preparation helpers --
    def _home_ground(self) -> float:
        """Ground height for the townhouse scene: the median DEM height under it."""
        hf = self.hf
        nj, ni = hf.H.shape
        E, N = np.meshgrid(hf.e0 + hf.step * np.arange(ni), hf.n0 + hf.step * np.arange(nj))
        b = self.home.footprint.bounds
        win = (E > b[0]) & (E < b[2]) & (N > b[1]) & (N < b[3])
        inside = shapely.contains(self.home.footprint, shapely.points(E[win], N[win]))
        return float(np.median(hf.H[win][inside])) if inside.any() else float(hf.sample(self.home.e, self.home.n))

    def _level_to_home(self, ways, node_h, ramp=HOME_RAMP):
        """Bring roads and paths up (or down) to the scene's flat ground where
        they meet it, easing back to their own height over `ramp` metres. The
        block falls about 2 m from Little Shenton Lane to the carport lane
        behind, so without this the carport lane ends in a step the car can't
        climb."""
        fp, h0 = self.home.footprint, self.home.h
        near = fp.buffer(ramp)
        for w in ways:
            g = way_group(w.tags)
            if g not in node_h or g == "rail" or not near.intersects(LineString(w.coords)):
                continue
            hmap = node_h[g]
            for nid, (e, n) in zip(w.nodes, w.coords):
                d = fp.distance(Point(e, n))
                if d < ramp:
                    t = d / ramp
                    t = t * t * (3 - 2 * t)
                    hmap[int(nid)] = h0 + (hmap[int(nid)] - h0) * t

    def _junction_nodes(self) -> dict[int, int]:
        count: dict[int, int] = {}
        for w in self.ways:
            if w.group != "road":
                continue
            for k, n in enumerate(w.nodes):
                n = int(n)
                arms = 1 if k in (0, len(w.nodes) - 1) else 2
                count[n] = count.get(n, 0) + arms
        # Three or more road arms meet here (two ways joined end to end is just a continuation).
        return {n: c for n, c in count.items() if c >= 3}

    def _water_body(self, a) -> WaterBody:
        g = a.geom
        t = a.tags
        area = g.area
        river = t.get("water") in ("river", "canal", "lagoon", "bay", "stream_pool") or \
            "river" in t.get("name", "").lower() or t.get("waterway") == "riverbank" or \
            t.get("natural") in ("bay", "strait")
        if river:
            return WaterBody(g, RIVER_LEVEL, True)
        ring = np.concatenate([np.asarray(p.exterior.coords) for p in polygons_of(g)])
        hb = self.hf.sample(ring[:, 0], ring[:, 1])
        big = area > 3000
        level = float(np.percentile(hb, 10)) - (0.4 if big else 0.0)
        return WaterBody(g, level, big)

    def _resolve_building_parts(self):
        """Buildings drawn from building:part pieces skip their outline."""
        if not self.parts:
            return
        tree = shapely.STRtree([p.geom.representative_point() for p in self.parts])
        keep = []
        for b in self.buildings:
            idx = tree.query(b.geom, predicate="contains")
            if len(idx):
                covered = sum(self.parts[i].geom.area for i in idx)
                if covered > 0.4 * b.geom.area:
                    continue
            keep.append(b)
        self.buildings = keep + self.parts

    def _sculpt_terrain(self):
        """Lower riverbeds and fit the ground to road and rail profiles."""
        hf = self.hf
        H = hf.H
        es, ns = hf.node_coords()
        # Water: riverbeds under big water, a lip just above water level along banks.
        for wb in self.water:
            if not wb.big:
                continue
            for p in polygons_of(wb.geom):
                b = p.bounds
                i0, i1 = np.searchsorted(es, [b[0] - 10, b[2] + 10])
                j0, j1 = np.searchsorted(ns, [b[1] - 10, b[3] + 10])
                if i1 <= i0 or j1 <= j0:
                    continue
                E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
                pts = shapely.points(E.ravel(), N.ravel())
                inner = p.buffer(-3.0)
                ins = shapely.contains(inner, pts).reshape(E.shape) if not inner.is_empty else np.zeros(E.shape, bool)
                sub = H[j0:j1, i0:i1]
                sub[ins] = np.minimum(sub[ins], wb.level - 2.5)
                near = shapely.contains(p.buffer(6.0), pts).reshape(E.shape) & ~ins
                sub[near] = np.maximum(sub[near], wb.level + 0.35)
                H[j0:j1, i0:i1] = sub
        # Roads and rail: flatten the cross-section and follow ramps/cuttings.
        best = np.full(H.shape, np.inf)
        target = np.zeros(H.shape)
        fall = np.ones(H.shape)
        s = hf.step
        for w in self.ways:
            if w.group == "foot" or w.grade_separated:
                continue
            hw = w.width / 2 + (styles.SIDEWALK_WIDTH if w.sidewalk else 0.6)
            for k in range(len(w.xy) - 1):
                a, b = w.xy[k], w.xy[k + 1]
                ha, hb = w.h[k], w.h[k + 1]
                dh = max(abs(ha - hf.sample(a[0], a[1])), abs(hb - hf.sample(b[0], b[1])))
                fl = max(3.0, 2.0 * float(dh)) + 1.0
                r = hw + fl
                i0 = max(int((min(a[0], b[0]) - r - hf.e0) / s), 0)
                i1 = min(int((max(a[0], b[0]) + r - hf.e0) / s) + 2, H.shape[1])
                j0 = max(int((min(a[1], b[1]) - r - hf.n0) / s), 0)
                j1 = min(int((max(a[1], b[1]) + r - hf.n0) / s) + 2, H.shape[0])
                if i1 <= i0 or j1 <= j0:
                    continue
                E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
                d = b - a
                L2 = max(float(d @ d), 1e-9)
                t = np.clip(((E - a[0]) * d[0] + (N - a[1]) * d[1]) / L2, 0, 1)
                dist = np.hypot(E - (a[0] + t * d[0]), N - (a[1] + t * d[1]))
                score = dist - hw
                sb = best[j0:j1, i0:i1]
                upd = score < sb
                if upd.any():
                    sb[upd] = score[upd]
                    target[j0:j1, i0:i1][upd] = (ha + t * (hb - ha))[upd] - 0.02
                    fall[j0:j1, i0:i1][upd] = fl
        core = best <= 0
        ramp = (best > 0) & (best < fall)
        wgt = np.where(ramp, best / fall, 0.0)
        H[core] = target[core]
        H[ramp] = target[ramp] * (1 - wgt[ramp]) + H[ramp] * wgt[ramp]
        if self.home:
            self._sculpt_home(es, ns)

    def _sculpt_home(self, es, ns, falloff=8.0, sink=0.35):
        """Level the townhouse block. The scene brings its own ground, so the
        terrain under it sits a little lower and only shows through gaps. The
        last grid cell in from the edge stays almost level with the scene:
        roads are draped on the terrain, and a dip there would leave a lip
        where the lanes run into the block."""
        H = self.hf.H
        fp = self.home.footprint
        E, N = np.meshgrid(es, ns)
        b = fp.bounds
        win = (E > b[0] - falloff - 5) & (E < b[2] + falloff + 5) & (N > b[1] - falloff - 5) & (N < b[3] + falloff + 5)
        pts = shapely.points(E[win], N[win])
        d = shapely.distance(fp, pts)
        inside = d <= 0
        if not inside.any():
            return
        sub = H[win]
        h = self.home.h
        ramp = (d > 0) & (d < falloff)
        w = d[ramp] / falloff
        sub[ramp] = h * (1 - w) + sub[ramp] * w
        edge = np.zeros_like(inside)
        edge[inside] = shapely.distance(fp.exterior, pts[inside]) < self.hf.step * 1.2
        sub[inside] = h - sink
        sub[edge] = h - 0.03
        H[win] = sub

    # -- queries --
    def ways_near(self, bounds, margin=60.0):
        e0, n0, e1, n1 = bounds
        out = []
        for w in self.ways:
            if (w.xy[:, 0].max() < e0 - margin or w.xy[:, 0].min() > e1 + margin or
                    w.xy[:, 1].max() < n0 - margin or w.xy[:, 1].min() > n1 + margin):
                continue
            out.append(w)
        return out


# ---------------------------------------------------------------------------
# Per-tile building
# ---------------------------------------------------------------------------

TOUCH = 1.0      # carriageways closer than this past their kerbs share one road surface
MISMATCH = 0.3   # height difference across a divided road that shows as a step


def _level_carriageways(ways, node_h, passes=3):
    """Bring the two halves of a divided road to the same height.

    Each carriageway's heights come from the DEM along its own centre line, so
    on a street that runs across a slope (St Georges Terrace) the uphill half
    sits a metre above the downhill one. Both are draped into one road
    surface, and where they meet the ground saw-tooths between the two. Nodes
    of a one-way road move towards the height of the opposite one-way of the
    same name beside it. Returns {node id: (e, n, change)} for nodes that
    moved, so a rebuild can find the tiles that changed."""
    hmap = node_h.get("road")
    if not hmap:
        return {}
    by_name: dict[str, list] = {}
    for w in ways:
        t = w.tags
        if way_group(t) == "road" and t.get("oneway") in ("yes", "-1") and t.get("name") \
                and not styles.is_bridge(t) and not styles.is_tunnel(t) and len(w.coords) > 1:
            by_name.setdefault(t["name"], []).append(w)
    before = dict(hmap)
    for _ in range(passes):
        targets: dict[int, list] = {}
        for group in by_name.values():
            if len(group) < 2:
                continue
            lines = [(w, LineString(w.coords), styles.road_width(w.tags)) for w in group]
            for wa, la, wid_a in lines:
                for wb, lb, wid_b in lines:
                    reach = (wid_a + wid_b) / 2 + TOUCH
                    if wb is wa or not la.distance(lb) < reach:
                        continue
                    seg = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(wb.coords, axis=0), axis=1))])
                    hb = np.array([hmap[int(n)] for n in wb.nodes])
                    for nid, (e, n) in zip(wa.nodes, wa.coords):
                        pt = Point(e, n)
                        if lb.distance(pt) >= reach:
                            continue
                        sp = lb.project(pt)
                        if sp <= 0.5 or sp >= lb.length - 0.5:
                            continue  # past the partner's end: a junction, not alongside
                        hp = float(np.interp(sp, seg, hb))
                        if MISMATCH < abs(hp - hmap[int(nid)]) < 2.0:  # more is a real level change
                            targets.setdefault(int(nid), []).append(hp)
        if not targets:
            break
        for nid, hs in targets.items():
            hmap[nid] = 0.5 * hmap[nid] + 0.5 * float(np.mean(hs))
    pos = {int(n): (float(e), float(nn)) for w in ways for n, (e, nn) in zip(w.nodes, w.coords)}
    return {nid: (*pos[nid], hmap[nid] - before[nid]) for nid in hmap if abs(hmap[nid] - before[nid]) > 0.01}


def _split_at_edge(w, poly):
    """`w` with a node added wherever it crosses `poly`'s edge, so a road that
    runs into the townhouse block is exactly level with it there."""
    if len(w.coords) < 2:
        return w
    line = LineString(w.coords)
    if not line.crosses(poly.boundary) and not line.touches(poly.boundary):
        return w
    xy, ids = [w.coords[0]], [int(w.nodes[0])]
    added = 0
    for k in range(len(w.coords) - 1):
        a, b = w.coords[k], w.coords[k + 1]
        cut = LineString([a, b]).intersection(poly.boundary)
        pts = [cut] if cut.geom_type == "Point" else [g for g in getattr(cut, "geoms", []) if g.geom_type == "Point"]
        seg = b - a
        L2 = float(seg @ seg)
        ts = sorted(float((np.array(p.coords[0]) - a) @ seg / L2) for p in pts) if L2 > 0 else []
        for t in ts:
            if 0.02 < t * math.sqrt(L2) < math.sqrt(L2) - 0.02:
                added += 1
                xy.append(a + seg * t)
                ids.append(-(int(w.id) * 64 + added))
        xy.append(b)
        ids.append(int(w.nodes[k + 1]))
    if not added:
        return w
    return replace(w, coords=np.array(xy), nodes=np.array(ids, dtype=np.int64))


def _clip_runs(xy, h, bounds):
    """Split a polyline into runs whose segment midpoints lie inside bounds."""
    e0, n0, e1, n1 = bounds
    mid = (xy[:-1] + xy[1:]) / 2
    inside = (mid[:, 0] >= e0) & (mid[:, 0] < e1) & (mid[:, 1] >= n0) & (mid[:, 1] < n1)
    runs, k = [], 0
    while k < len(inside):
        if not inside[k]:
            k += 1
            continue
        start = k
        while k < len(inside) and inside[k]:
            k += 1
        runs.append((xy[start:k + 1], h[start:k + 1]))
    return runs


def _resample(xy, step):
    seg = np.linalg.norm(np.diff(xy, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return xy[:1], s[:1]
    n = max(2, int(np.ceil(s[-1] / step)) + 1)
    ss = np.linspace(0, s[-1], n)
    return np.column_stack([np.interp(ss, s, xy[:, 0]), np.interp(ss, s, xy[:, 1])]), ss


class TileBuilder:
    def __init__(self, world: World, key: TileKey):
        self.w = world
        self.key = key
        self.size = world.tile_size
        self.bounds = key.bounds(self.size)
        self.box = sbox(*self.bounds)
        self.mb = MeshBuilder()
        self.instances: dict[str, list] = {}
        self.grid = CellGrid(world.hf, self.bounds)
        self.ways = world.ways_near(self.bounds)

    # ---------------- main ----------------
    def build(self) -> dict:
        self._road_geoms()
        self._tunnel_cells()
        self._ground()
        self._roads()
        self._sidewalks_paths()
        self._markings()
        self._bridges()
        self._tunnels()
        self._rail()
        self._decks()
        self._buildings()
        self._landmarks()
        self._trees()
        self._street_lights()
        return self._pack()

    # ---------------- shared geometry ----------------
    def _buffer_ways(self, ways, extra=0.0, cap=1):
        geoms = [LineString(w.xy).buffer(w.width / 2 + extra, quad_segs=2, cap_style=cap)
                 for w in ways if len(w.xy) >= 2]
        return shapely.union_all(geoms) if geoms else Polygon()

    def _road_geoms(self):
        clip = self.box.buffer(20)
        at_grade = [w for w in self.ways if w.group == "road" and not w.grade_separated]
        self.road_area = self._buffer_ways(at_grade).intersection(clip)
        side = [w for w in at_grade if w.sidewalk]
        self.sidewalk_area = (self._buffer_ways(side, styles.SIDEWALK_WIDTH, cap=2)
                              .intersection(clip).difference(self.road_area)
                              .difference(self.w.water_union))
        foot = [w for w in self.ways if w.group == "foot" and not w.grade_separated
                and w.tags.get("highway") != "corridor"]
        self.path_area = (self._buffer_ways(foot).intersection(clip)
                          .difference(self.road_area).difference(self.sidewalk_area)
                          .difference(self.w.water_union))
        rails = [w for w in self.ways if w.group == "rail" and not w.grade_separated]
        self.rail_area = self._buffer_ways(rails).intersection(clip)
        if self.w.home:
            fp = self.w.home.footprint
            self.road_area = self.road_area.difference(fp)
            self.sidewalk_area = self.sidewalk_area.difference(fp)
            self.path_area = self.path_area.difference(fp)

    def _tunnel_cells(self):
        """Ground cells that would cut into a shallow tunnel are left out."""
        g = self.grid
        skip = np.zeros(len(g.cells), dtype=bool)
        for w in self.ways:
            if not w.tunnel or w.group == "rail" or self._shallow_path(w):
                continue
            xy, h = densify(w.xy, w.h, 2.5)
            line = LineString(xy)
            corridor = line.buffer(w.width / 2 + 1.0, cap_style=2)
            idx = g.tree.query(corridor, predicate="intersects")
            if not len(idx):
                continue
            cx, cy = g.node_xy(g.ci[idx] + 0.5, g.cj[idx] + 0.5)
            # Tunnel floor height under each cell centre (nearest densified point).
            d2 = (cx[:, None] - xy[None, :, 0]) ** 2 + (cy[:, None] - xy[None, :, 1]) ** 2
            th = h[np.argmin(d2, axis=1)]
            ground = self.w.hf.sample(cx, cy)
            skip[idx] |= ground < th + TUNNEL_HEIGHT + 1.2
        self.skip_cells = skip

    # ---------------- ground ----------------
    def _ground(self):
        tile = self.box
        # Nothing is drawn under roads and paths: overlapping layers z-fight once
        # the PS1 vertex snapping wobbles them.
        paved = shapely.union_all([self.road_area, self.sidewalk_area, self.path_area])
        taken = paved.intersection(tile)
        layers = []
        water_parts = []
        for wb in self.w.water:
            if wb.geom.intersects(tile):
                water_parts.append((wb, wb.geom.intersection(tile)))
        if water_parts:
            big = shapely.union_all([p for wb, p in water_parts if wb.big]) if any(wb.big for wb, _ in water_parts) else Polygon()
            if not big.is_empty:
                big = big.difference(taken)
                layers.append(("riverbed", big))
                taken = taken.union(big)
        cover = sorted((c for c in self.w.cover if c[2].intersects(tile)), key=lambda c: -c[1])
        for mat, prio, g in cover:
            part = g.intersection(tile).simplify(0.4).difference(taken)
            if part.is_empty:
                continue
            layers.append((mat, part))
            taken = taken.union(part)
        rest = tile.difference(taken)
        layers.append(("ground_urban", rest))
        merged: dict[str, list] = {}
        for mat, g in layers:
            merged.setdefault(mat, []).append(g)
        for mat, gs in merged.items():
            g = shapely.union_all(gs)
            surf = self.mb.surface("ground", mat, "world")
            drape(surf, g, self.grid, 0.0, textures.UV_SCALE.get(mat, 8.0), self.skip_cells)
        # Water surfaces (no collision).
        for wb, part in water_parts:
            surf = self.mb.surface("water", "water", None)
            for p in polygons_of(part):
                if wb.big:
                    pv, pt = triangulate(p)
                    if len(pt):
                        v = np.column_stack([pv, np.full(len(pv), wb.level)])
                        surf.add(v, np.tile([0, 0, 1.0], (len(pv), 1)), pv / 16.0, pt)
                else:
                    drape(surf, p, self.grid, 0.05, 6.0)
        self.cover_layers = merged

    # ---------------- roads ----------------
    def _roads(self):
        area = self.road_area.intersection(self.box)
        drape(self.mb.surface("roads", "asphalt", "world"), area, self.grid, ROAD_OFFSET,
              textures.UV_SCALE["asphalt"], self.skip_cells)

    def _sidewalks_paths(self):
        hf = self.w.hf
        sw = self.sidewalk_area.intersection(self.box).simplify(0.2)
        drape(self.mb.surface("roads", "sidewalk", "world"), sw, self.grid, SIDEWALK_TOP,
              textures.UV_SCALE["sidewalk"], self.skip_cells)
        kerb = self.mb.surface("roads", "kerb", "world")
        for p in polygons_of(sw):
            p = orient(p, 1.0)
            for ring in [p.exterior, *p.interiors]:
                xy = np.asarray(ring.coords)
                xy, _ = densify(xy, np.zeros(len(xy)), 6.0)
                g = hf.sample(xy[:, 0], xy[:, 1])
                walls(kerb, xy, g, g + SIDEWALK_TOP, 2.0, 0.5)
        pa = self.path_area.intersection(self.box)
        drape(self.mb.surface("roads", "path", "world"), pa, self.grid, PATH_OFFSET,
              textures.UV_SCALE["path"], self.skip_cells)

    def _markings(self):
        surf = self.mb.surface("markings", "line_white", None)
        hf = self.w.hf
        for w in self.ways:
            if w.group != "road" or w.width < 5.5 or w.tags.get("highway") in ("service", "track", "living_street"):
                continue
            lanes = styles.road_lanes(w.tags)
            if lanes < 2:
                continue
            xy, s = _resample(w.xy, 1.5)
            if len(xy) < 2:
                continue
            seg_s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.xy, axis=0), axis=1))])
            h_line = np.interp(s, seg_s, w.h)
            # No paint through intersections.
            near_junction = np.zeros(len(xy), dtype=bool)
            for k, n in enumerate(w.nodes):
                if int(n) in self.w.junctions:
                    near_junction |= np.abs(s - seg_s[k]) < max(9.0, w.width)
            W = w.width
            lines = []  # (lateral, dashed)
            if styles.is_oneway(w.tags):
                lines = [(-W / 2 + k * W / lanes, True) for k in range(1, lanes)]
            else:
                lines.append((0.0, lanes < 4))
                per = lanes // 2
                for k in range(1, per):
                    off = k * W / lanes
                    lines += [(off, True), (-off, True)]
            for lateral, dashed in lines:
                on = ~near_junction
                if dashed:
                    on &= (s % 12.0) < 3.0
                k = 0
                while k < len(on) - 1:
                    if not (on[k] and on[k + 1]):
                        k += 1
                        continue
                    a = k
                    while k < len(on) - 1 and on[k] and on[k + 1]:
                        k += 1
                    for rxy, rh in _clip_runs(xy[a:k + 1], h_line[a:k + 1], self.bounds):
                        if w.grade_separated:
                            hh = rh + 0.05
                        else:
                            off = offset_polyline(rxy, lateral)
                            hh = hf.sample(off[:, 0], off[:, 1]) + MARK_OFFSET
                        ribbon(surf, rxy, hh, 0.13 if dashed else 0.11, 1.0, lateral=lateral)

    # ---------------- grade-separated structures ----------------
    def _bridges(self):
        hf = self.w.hf
        for w in self.ways:
            if not w.bridge:
                continue
            xy, h = densify(w.xy, w.h, 4.0)
            for rxy, rh in _clip_runs(xy, h, self.bounds):
                if len(rxy) < 2:
                    continue
                if w.group == "road":
                    deck_mat = "asphalt"
                elif w.group == "rail":
                    deck_mat = "ballast"
                else:
                    deck_mat = "path"
                top = rh + 0.02
                surf = self.mb.surface("bridges", deck_mat, "world")
                ribbon(surf, rxy, top, w.width, textures.UV_SCALE.get(deck_mat, 4.0))
                conc = self.mb.surface("bridges", "concrete", "world")
                half = w.width / 2
                left = offset_polyline(rxy, half)
                right = offset_polyline(rxy, -half)
                bot = top - DECK_THICKNESS
                # Deck edges and underside.
                walls(conc, left[::-1], bot[::-1], top[::-1] + PARAPET_H, 2.0, 2.0, closed=False)
                walls(conc, right, bot, top + PARAPET_H, 2.0, 2.0, closed=False)
                ribbon(conc, rxy, bot, w.width + 0.6, 4.0, up=False)
                # Parapets (inner faces and tops) so cars can't drive off.
                pl = offset_polyline(rxy, half - 0.3)
                pr = offset_polyline(rxy, -half + 0.3)
                walls(conc, pl, top, top + PARAPET_H, 2.0, 2.0, closed=False)
                walls(conc, pr[::-1], top[::-1], top[::-1] + PARAPET_H, 2.0, 2.0, closed=False)
                ribbon(conc, rxy, top + PARAPET_H, 0.3, 2.0, lateral=half - 0.15)
                ribbon(conc, rxy, top + PARAPET_H, 0.3, 2.0, lateral=-half + 0.15)
                # Piers every ~30 m where there's room underneath.
                ps, ss = _resample(rxy, 30.0)
                hh = np.interp(ss, np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(rxy, axis=0), axis=1))]), bot)
                g = hf.sample(ps[:, 0], ps[:, 1])
                for k in range(1, len(ps) - 1):
                    if hh[k] - g[k] > 2.5:
                        d = ps[min(k + 1, len(ps) - 1)] - ps[k - 1]
                        yaw = math.atan2(d[1], d[0])
                        _box(conc, ps[k], g[k] - 1.5, hh[k], (1.4, min(w.width * 0.6, 6.0)), yaw)

    def _shallow_path(self, w) -> bool:
        """A footpath tunnel the terrain doesn't cover (a coarse DEM over a small hill,
        like Fremantle's Whaling Tunnel): left out, so it isn't a box sticking out."""
        if w.group == "road":
            return False
        xy, h = densify(w.xy, w.h, 2.5)
        ground = self.w.hf.sample(xy[:, 0], xy[:, 1])
        return float(np.mean(ground < h + TUNNEL_HEIGHT + 0.6)) > 0.5

    def _tunnels(self):
        for w in self.ways:
            if not w.tunnel or w.group == "rail" or self._shallow_path(w):
                continue
            xy, h = densify(w.xy, w.h, 4.0)
            for rxy, rh in _clip_runs(xy, h, self.bounds):
                if len(rxy) < 2:
                    continue
                floor = rh + 0.02
                mat = "asphalt" if w.group == "road" else "path"
                ribbon(self.mb.surface("tunnels", mat, "world"), rxy, floor, w.width + 1.0,
                       textures.UV_SCALE.get(mat, 4.0))
                surf = self.mb.surface("tunnels", "tunnel_wall", "world")
                half = w.width / 2 + 0.5
                left = offset_polyline(rxy, half)
                right = offset_polyline(rxy, -half)
                walls(surf, left, floor, floor + TUNNEL_HEIGHT, 3.0, TUNNEL_HEIGHT, closed=False)
                walls(surf, right[::-1], floor[::-1], floor[::-1] + TUNNEL_HEIGHT, 3.0, TUNNEL_HEIGHT, closed=False)
                ribbon(surf, rxy, floor + TUNNEL_HEIGHT, w.width + 1.0, 4.0, up=False)
                # Outside of the box (visible where ground cells were removed near portals).
                outer = self.mb.surface("tunnels", "concrete", "world")
                ribbon(outer, rxy, floor + TUNNEL_HEIGHT + 0.6, w.width + 2.0, 4.0)
                lo = offset_polyline(rxy, half + 0.5)
                ro = offset_polyline(rxy, -half - 0.5)
                walls(outer, lo[::-1], floor[::-1] - 0.5, floor[::-1] + TUNNEL_HEIGHT + 0.6, 3.0, 3.0, closed=False)
                walls(outer, ro, floor - 0.5, floor + TUNNEL_HEIGHT + 0.6, 3.0, 3.0, closed=False)

    def _rail(self):
        for w in self.ways:
            if w.group != "rail" or w.tunnel:
                continue
            xy, h = densify(w.xy, w.h, 4.0)
            for rxy, rh in _clip_runs(xy, h, self.bounds):
                if len(rxy) < 2:
                    continue
                base = rh + (0.04 if w.bridge else 0.12)
                ribbon(self.mb.surface("rail", "ballast", "world"), rxy, base, 3.0, 3.0)
                steel = self.mb.surface("rail", "rail_steel", None)
                for lat in (-0.54, 0.54):
                    ribbon(steel, rxy, base + 0.16, 0.09, 1.0, lateral=lat)

    def _decks(self):
        hf = self.w.hf
        for g, kind in self.w.decks:
            for p in polygons_of(g):
                c = p.representative_point()
                if not self.box.contains(c):
                    continue
                p = orient(p, 1.0)
                ring = np.asarray(p.exterior.coords)
                gh = hf.sample(ring[:, 0], ring[:, 1])
                if kind == "pier":
                    top = max(float(np.max(gh)), RIVER_LEVEL + 1.2)
                    bottom = RIVER_LEVEL - 1.0
                else:
                    top = float(np.median(gh)) + 0.9
                    bottom = float(np.min(gh)) - 0.3
                surf = self.mb.surface("props", "path" if kind == "pier" else "sidewalk", "world")
                flat_cap(surf, p, top, 3.0)
                side = self.mb.surface("props", "concrete", "world")
                for r in [p.exterior, *p.interiors]:
                    walls(side, np.asarray(r.coords), bottom, top, 2.0, 2.0)

    # ---------------- buildings ----------------
    def _buildings(self):
        hf = self.w.hf
        for b in self.w.buildings:
            for p in polygons_of(b.geom):
                if p.area < 6:
                    continue
                c = p.representative_point()
                if not self.box.contains(c):
                    continue
                self._building(b, orient(p.simplify(0.15), 1.0), hf)

    def _building(self, b, p: Polygon, hf):
        t = b.tags
        area = p.area
        cbd = self.w.cbd.contains(p.representative_point())
        minh, height = styles.building_height(t, area, b.id, cbd)
        ring = np.asarray(p.exterior.coords)
        gh = hf.sample(ring[:, 0], ring[:, 1])
        ground = float(np.max(gh))
        base = float(np.min(gh)) - 0.4 if minh <= 0 else ground + minh
        top = ground + height
        mrr = p.minimum_rotated_rectangle
        rect_ratio = area / max(mrr.area, 1e-6)
        roof = styles.roof_kind(t, area, height, rect_ratio)
        g_mat, u_mat = styles.facade(t, height, area, cbd, b.id)
        eave = top
        if roof == "gabled":
            short = _mrr_short_side(mrr)
            roof_h = min(0.35 * short, 4.0)
            eave = top - roof_h
            if eave - ground < 2.4:
                eave = ground + 2.4
                top = eave + roof_h
        band = ground + 4.0
        rings = [np.asarray(r.coords) for r in [p.exterior, *p.interiors]]
        if minh <= 0 and eave > band + 1.0 and g_mat != u_mat:
            sg = self.mb.surface("buildings", g_mat, "buildings")
            su = self.mb.surface("buildings", u_mat, "buildings")
            for r in rings:
                walls(sg, r, base, band, 4.0, 4.0, v_origin=ground)
                walls(su, r, band, eave, 4.0, styles.LEVEL_H, v_origin=band)
        else:
            s = self.mb.surface("buildings", u_mat if minh > 0 else g_mat, "buildings")
            for r in rings:
                walls(s, r, base, eave, 4.0, styles.LEVEL_H if minh > 0 or eave - ground > 5 else 4.0,
                      v_origin=ground)
        if minh > 0:
            flat_cap(self.mb.surface("buildings", "concrete", "buildings"), p, base, 4.0, down=True)
        if roof == "gabled":
            _gable_roof(self.mb, mrr, eave, top, b.id)
        else:
            mat = "roof_flat_dark" if stable_rng("roof", b.id).random() < 0.4 else "roof_flat"
            flat_cap(self.mb.surface("buildings", mat, "buildings"), p, eave, 6.0)

    def _landmarks(self):
        for lm in self.w.landmarks:
            if self.box.contains(Point(*lm.center)):
                landmarks.build(self.mb, lm, self.w.hf)

    # ---------------- props ----------------
    def _trees(self):
        hf = self.w.hf
        items = []
        rng = stable_rng("trees", self.key.i, self.key.j)
        if len(self.w.trees):
            m = ((self.w.trees[:, 0] >= self.bounds[0]) & (self.w.trees[:, 0] < self.bounds[2]) &
                 (self.w.trees[:, 1] >= self.bounds[1]) & (self.w.trees[:, 1] < self.bounds[3]))
            for e, n in self.w.trees[m]:
                items.append(("tree_round" if rng.random() < 0.6 else "tree_gum", e, n))
        blockers = shapely.union_all([self.road_area, self.path_area, self.sidewalk_area,
                                      self.rail_area.buffer(3)])
        bld = [p for b in self.w.buildings for p in polygons_of(b.geom)
               if p.intersects(self.box)]
        if bld:
            blockers = blockers.union(shapely.union_all(bld).buffer(2.0))
        if self.w.home:
            blockers = blockers.union(self.w.home.footprint.buffer(1.0))
        if not self.w.landmark_zone.is_empty:
            blockers = blockers.union(self.w.landmark_zone)
        for mat, density, kinds in (("bush", 1 / 90.0, ("tree_gum", "tree_gum", "shrub")),
                                    ("grass", 1 / 450.0, ("tree_round", "tree_gum", "tree_palm")),
                                    ("wetland", 1 / 200.0, ("shrub",))):
            gs = self.cover_layers.get(mat)
            if not gs:
                continue
            g = shapely.union_all(gs).difference(blockers)
            if g.is_empty:
                continue
            count = rng.poisson(g.area * density)
            if count == 0:
                continue
            x0, y0, x1, y1 = g.bounds
            pts = np.column_stack([rng.uniform(x0, x1, count * 3), rng.uniform(y0, y1, count * 3)])
            shapely.prepare(g)
            ok = shapely.contains_xy(g, pts[:, 0], pts[:, 1])
            for e, n in pts[ok][:count]:
                items.append((kinds[rng.integers(len(kinds))], e, n))
        for kind, e, n in items:
            hgt = float(hf.sample(e, n))
            scale = 0.75 + rng.random() * 0.6
            self.instances.setdefault(kind, []).append((e, n, hgt, rng.random() * math.tau, scale))

    def _street_lights(self):
        hf = self.w.hf
        for w in self.ways:
            if w.group != "road" or w.grade_separated or w.tags.get("highway") not in (
                    "primary", "secondary", "tertiary", "trunk", "residential", "motorway"):
                continue
            xy, s = _resample(w.xy, 38.0)
            if len(xy) < 3:
                continue
            # Lights stand on the left verge (right for motorways) with the arm over the road.
            motorway = w.tags.get("highway") == "motorway"
            side = w.width / 2 + 0.9
            off = offset_polyline(xy, -side if motorway else side)
            d = np.gradient(xy, axis=0)
            for k in range(1, len(xy) - 1):
                e, n = off[k]
                if not (self.bounds[0] <= e < self.bounds[2] and self.bounds[1] <= n < self.bounds[3]):
                    continue
                if self.road_area.contains(Point(e, n)):
                    continue
                if self.w.home and self.w.home.footprint.buffer(1.0).contains(Point(e, n)):
                    continue
                yaw = math.atan2(d[k][1], d[k][0]) + (math.pi if motorway else 0.0)
                self.instances.setdefault("street_light", []).append(
                    (e, n, float(hf.sample(e, n)) + SIDEWALK_TOP, yaw, 1.0))

    # ---------------- output ----------------
    def _pack(self) -> dict:
        e0, n0 = self.bounds[0], self.bounds[1]
        meshes = []
        hmin, hmax = 1e9, -1e9
        for name, surfaces in self.mb.meshes.items():
            out = []
            for mat, surf in surfaces.items():
                arr = surf.arrays()
                if arr is None:
                    continue
                v, nrm, uv, idx = arr
                hmin, hmax = min(hmin, v[:, 2].min()), max(hmax, v[:, 2].max())
                out.append((mat, v, nrm, uv, idx))
            if out:
                meshes.append((name, self.mb.collision.get(name), out))
        inst = {k: np.array(v, dtype=np.float64) for k, v in self.instances.items()}
        return {"key": self.key, "origin": (e0, n0), "meshes": meshes, "instances": inst,
                "hrange": (float(hmin), float(hmax))}


def _box(surf, center_xy, bottom, top, size, yaw):
    sx, sy = size
    c, s = math.cos(yaw), math.sin(yaw)
    corners = np.array([[-sx, -sy], [sx, -sy], [sx, sy], [-sx, sy]]) / 2
    rot = corners @ np.array([[c, s], [-s, c]])
    walls(surf, rot + center_xy, bottom, top, 2.0, 2.0)


def _mrr_short_side(mrr) -> float:
    c = np.asarray(mrr.exterior.coords)
    return float(min(np.linalg.norm(c[1] - c[0]), np.linalg.norm(c[2] - c[1])))


def _gable_roof(mb: MeshBuilder, mrr, eave: float, top: float, osm_id: int):
    c = np.asarray(orient(mrr, 1.0).exterior.coords)[:4]
    if np.linalg.norm(c[2] - c[1]) > np.linalg.norm(c[1] - c[0]):
        c = np.roll(c, -1, axis=0)  # c0-c1 is a long side
    ctr = c.mean(axis=0)
    p0, p1, p2, p3 = ctr + (c - ctr) * 1.04  # small overhang
    r0, r1 = (p3 + p0) / 2, (p1 + p2) / 2
    mat = ("roof_tiles", "roof_metal", "roof_tiles_dark")[stable_rng("gable", osm_id).integers(3)]
    surf = mb.surface("buildings", mat, "buildings")
    for quad in ((p0, p1, r1, r0), (p2, p3, r0, r1)):
        v = np.array([[*quad[0], eave], [*quad[1], eave], [*quad[2], top], [*quad[3], top]])
        nrm = np.cross(v[1] - v[0], v[3] - v[0])
        nrm /= max(np.linalg.norm(nrm), 1e-9)
        run = np.linalg.norm(quad[1] - quad[0]) / 3.0
        slope = np.linalg.norm(v[3] - v[0]) / 3.0
        uv = np.array([[0, 0], [run, 0], [run, -slope], [0, -slope]])
        surf.add(v, np.tile(nrm, (4, 1)), uv, [[0, 1, 2], [0, 2, 3]])
    wall = mb.surface("buildings", "facade_render", "buildings")
    for a, b, r in ((p1, p2, r1), (p3, p0, r0)):
        v = np.array([[*a, eave], [*b, eave], [*r, top]])
        nrm = np.cross(v[1] - v[0], v[2] - v[0])
        nrm /= max(np.linalg.norm(nrm), 1e-9)
        w = np.linalg.norm(b - a) / 4.0
        uv = np.array([[0, 0], [w, 0], [w / 2, -(top - eave) / 3.2]])
        wall.add(v, np.tile(nrm, (3, 1)), uv, [[0, 1, 2]])


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def region_tiles(cfg, proj, name, feats=None) -> list[TileKey]:
    r = cfg["regions"][name]
    size = cfg["tile_size"]
    keys = set()

    def add_bbox(bb):
        (ex0, ex1), (ny0, ny1) = proj.fwd([bb[0], bb[2]], [bb[1], bb[3]])
        keys.update(tiles_for_bbox(min(ex0, ex1), min(ny0, ny1), max(ex0, ex1), max(ny0, ny1), size))

    if "bbox" in r:
        add_bbox(r["bbox"])
    if "extra_bbox" in r:
        add_bbox(r["extra_bbox"])
    if "corridor" in r:
        c = r["corridor"]
        if feats is None:
            feats = extract(fetch.osm_pbf(cfg), proj, tuple(c["bbox"]))
        lines = [LineString(w.coords) for w in feats.ways
                 if w.tags.get("name") in c["roads"] and w.tags.get("highway") in styles.DRIVABLE]
        if lines:
            g = shapely.union_all(lines).buffer(c["buffer"])
            b = g.bounds
            for k in tiles_for_bbox(*b, size):
                if g.intersects(sbox(*k.bounds(size))):
                    keys.add(k)
    return sorted(keys, key=lambda k: (k.j, k.i))


def build(cfg: dict, keys: list[TileKey], region_of: dict, out_dir: Path = TILES_DIR,
          refresh: bool = False, only: list[TileKey] | None = None, traffic_only: bool = False,
          index_only: bool = False):
    """Build `keys` (or, with `only`, prepare the world for `keys` but rewrite
    just those tiles and the index, leaving the rest and the backdrop alone).
    `traffic_only` rewrites just the traffic road data of those tiles."""
    proj = Projector.from_config(cfg)
    size = cfg["tile_size"]
    step = cfg["grid_step"]
    margin = cfg["data_margin"]
    e0 = min(k.i for k in keys) * size - margin
    n0 = min(k.j for k in keys) * size - margin
    e1 = (max(k.i for k in keys) + 1) * size + margin
    n1 = (max(k.j for k in keys) + 1) * size + margin
    lon, lat = proj.inv([e0, e1, e0, e1], [n0, n0, n1, n1])
    bbox_ll = (min(lon), min(lat), max(lon), max(lat))
    print(f"Building {len(keys)} tiles; data bbox {tuple(round(v, 4) for v in bbox_ll)}")
    pbf = fetch.osm_pbf(cfg, refresh)
    feats = extract(pbf, proj, bbox_ll)
    hf = build_heightfield(cfg, proj, e0, n0, e1, n1, step)
    world = World(cfg, proj, feats, hf)
    out_dir.mkdir(parents=True, exist_ok=True)
    textures.write_all(MAP_DIR)
    index_path = out_dir / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {"tiles": {}}
    total = 0
    if index_only:
        _write_index(cfg, proj, world, index, index_path, region_of)
        print(f"Index: {len(index.get('pois', []))} points of interest")
        return
    todo = [k for k in keys if k in set(only)] if only is not None else keys
    net = TrafficNetwork(world)
    for n, key in enumerate(todo):
        t0 = time.time()
        tname = f"{key.name}.p5r"
        tbytes = write_traffic(out_dir / tname, net.tile_data(key.bounds(size)))
        if traffic_only:
            if key.name in index["tiles"]:
                index["tiles"][key.name]["traffic"] = tname
            total += tbytes
            continue
        data = TileBuilder(world, key).build()
        nbytes = write_tile(out_dir / f"{key.name}.p5t", data)
        total += nbytes
        index["tiles"][key.name] = {
            "i": key.i, "j": key.j, "file": f"{key.name}.p5t", "region": region_of.get(key, "custom"),
            "hmin": round(data["hrange"][0], 2), "hmax": round(data["hrange"][1], 2), "bytes": nbytes,
            "traffic": tname,
        }
        print(f"  [{n + 1}/{len(todo)}] tile {key.name}: {nbytes / 1024:.0f} KB in {time.time() - t0:.1f}s")
    _write_index(cfg, proj, world, index, index_path, region_of)
    if traffic_only:
        print(f"Traffic data: {total / 1e6:.2f} MB")
        return
    if only is None or not (out_dir / "overview.p5o").exists():
        nbytes = build_overview(cfg, proj, index["tiles"], out_dir / "overview.p5o")
        print(f"  overview: {nbytes / 1024:.0f} KB")
    print(f"Done: {total / 1e6:.1f} MB")


def write_traffic(path: Path, data: dict) -> int:
    blob = pack_tile({"format": 1, **data})
    path.write_bytes(blob)
    return len(blob)


def _write_index(cfg, proj, world: World, index: dict, path: Path, region_of: dict):
    sp = cfg["spawn"]
    se, sn = proj.fwd(sp["lon"], sp["lat"])
    nj, ni = world.hf.shape

    def inside_hf(e, n):
        return (world.hf.e0 <= e <= world.hf.e0 + world.hf.step * (ni - 1) and
                world.hf.n0 <= n <= world.hf.n0 + world.hf.step * (nj - 1))

    inside = inside_hf(se, sn)
    if not inside and "spawn" in index:
        sh = index["spawn"]["position"][1] - 0.6
    else:
        sh = float(world.hf.sample(se, sn))
    index.update({
        "format": 1,
        "tile_size": cfg["tile_size"],
        "origin": {"lat": cfg["origin"]["lat"], "lon": cfg["origin"]["lon"], "name": cfg["origin"]["name"]},
        "projection": "Transverse Mercator centred on origin; Godot X = east, Z = -north, 1 unit = 1 m",
        "spawn": {"position": [round(se, 2), round(sh + 0.6, 2), round(-sn, 2)],
                  "yaw": round(-math.radians(sp["heading_deg"]), 4), "name": cfg["origin"]["name"]},
        "materials": sorted(p.stem for p in (MAP_DIR / "materials").glob("*.tres")),
        "attribution": "Map data © OpenStreetMap contributors (ODbL). Elevation: Mapzen Terrain Tiles "
                       "(SRTM, Geoscience Australia and others).",
    })
    landmarks = index.get("landmarks", {})
    for nid, tags, lon, lat in world.named:
        if "place" in tags and tags["place"] in ("suburb", "neighbourhood", "quarter", "locality", "square"):
            e, n = proj.fwd(lon, lat)
            landmarks[tags["name"]] = [round(e, 1), round(-n, 1)]
    index["landmarks"] = dict(sorted(landmarks.items()))
    _write_places(cfg, proj, world, index, inside_hf, region_of)
    index["tiles"] = dict(sorted(index["tiles"].items(), key=lambda kv: (kv[1]["j"], kv[1]["i"])))
    path.write_text(json.dumps(index, indent=1) + "\n")


def _write_places(cfg, proj, world: World, index: dict, inside_hf, region_of: dict):
    """The townhouse, job sites and workshop bays. Entries outside this build's
    terrain keep what an earlier build wrote; entries off the built map are left
    out until a region covers them."""
    size = cfg["tile_size"]
    home = world.home
    if home and inside_hf(home.e, home.n):
        hc = cfg["home"]
        index["home"] = {"scene": hc["scene"], "name": hc.get("name", ""),
                         "position": [round(home.e, 3), round(home.h, 3), round(-home.n, 3)],
                         "yaw": round(home.yaw, 5), "spawn_marker": hc.get("spawn_marker", "")}
    home_h = index.get("home", {}).get("position", [0, 0, 0])[1]
    for group, fields in (("job_sites", ("name", "suburb", "kinds")),
                          ("workshops", ("name", "kinds", "color"))):
        old = {p["id"]: p for p in index.get(group, [])}
        out = []
        for spec in cfg.get("places", {}).get(group, []):
            placed = places.place(spec, proj, world.ways, home)
            if placed is None:
                continue
            e, n, at_home, yaw = placed
            key = TileKey(math.floor(e / size), math.floor(n / size))
            if key.name not in index["tiles"]:
                continue
            if at_home:
                h = home_h
            elif inside_hf(e, n):
                h = float(world.hf.sample(e, n)) + ROAD_OFFSET
            elif spec["id"] in old:
                out.append(old[spec["id"]])
                continue
            else:
                continue
            entry = {"id": spec["id"], "position": [round(e, 2), round(h, 2), round(-n, 2)], "yaw": round(yaw, 4)}
            entry.update({f: spec[f] for f in fields if f in spec})
            out.append(entry)
        index[group] = out
    # Badges (Collectible): a quota per region, picked when the region is built.
    region_keys: dict[str, set] = {}
    for key, region in region_of.items():
        region_keys.setdefault(region, set()).add((key.i, key.j))
    quotas = {r: q for r, q in cfg.get("places", {}).get("badges", {}).items() if r in region_keys}
    if quotas:
        fresh = places.pick_badges(world.ways, world.hf.sample, region_keys, quotas, size, home, stable_rng)
        old_order = {b["id"]: k for k, b in enumerate(index.get("badges", []))}
        kept = [b for b in index.get("badges", []) if b.get("region") not in quotas]
        index["badges"] = sorted(kept + fresh, key=lambda b: old_order.get(b["id"], len(old_order)))
    # Points of interest: rebuilt where this build has terrain, kept elsewhere.
    fresh = pois.build(world, cfg, proj, size, set(index["tiles"]), inside_hf)
    ids = {p["id"] for p in fresh}
    kept = [p for p in index.get("pois", []) if p["id"] not in ids and not inside_hf(p["p"][0], -p["p"][2])]
    index["pois"] = sorted(kept + fresh, key=lambda p: p["id"])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", action="append", default=[], help="region name from config.json")
    ap.add_argument("--stage", type=int, action="append", default=[], help="build every region of a stage")
    ap.add_argument("--tiles", nargs="+", action="extend", default=[], help="explicit tile names like 0_-1")
    ap.add_argument("--only", nargs="+", action="extend", default=None,
                    help="with --region/--stage: rewrite just these tiles (and the index); "
                         "the region still sets the terrain and road network they are built from")
    ap.add_argument("--traffic-only", action="store_true",
                    help="rewrite only the traffic road data (.p5r) of the tiles")
    ap.add_argument("--index-only", action="store_true",
                    help="rewrite only index.json (places, badges, points of interest)")
    ap.add_argument("--out", type=Path, default=TILES_DIR)
    ap.add_argument("--refresh", action="store_true", help="re-download the OSM extract")
    ap.add_argument("--list", action="store_true", help="list regions and their tile counts")
    a = ap.parse_args(argv)
    cfg = load_config()
    proj = Projector.from_config(cfg)
    if a.list:
        for name, r in cfg["regions"].items():
            print(f"{name:28s} stage {r['stage']}  {len(region_tiles(cfg, proj, name))} tiles  {r['description']}")
        return
    region_of: dict[TileKey, str] = {}
    names = list(a.region) + [n for n, r in cfg["regions"].items() if r["stage"] in a.stage]
    if not names and not a.tiles:
        names = ["first_slice"]
    # Tiles already built for a region outside this run belong to it: they are
    # left alone (an earlier stage wins where regions overlap).
    index_path = a.out / "index.json"
    built = json.loads(index_path.read_text())["tiles"] if index_path.exists() else {}
    names.sort(key=lambda n: cfg["regions"][n]["stage"])
    for name in names:
        for k in region_tiles(cfg, proj, name):
            owner = built.get(k.name, {}).get("region")
            if owner and owner != name and owner not in names and owner != "custom":
                continue
            region_of.setdefault(k, name)
    for t in a.tiles:
        i, j = t.split("_")
        region_of.setdefault(TileKey(int(i), int(j)), "custom")
    keys = sorted(region_of, key=lambda k: (k.j, k.i))
    only = [TileKey(*map(int, t.split("_"))) for t in a.only] if a.only else None
    build(cfg, keys, region_of, a.out, a.refresh, only, a.traffic_only, a.index_only)


if __name__ == "__main__":
    main()
