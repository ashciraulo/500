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
from scipy.ndimage import distance_transform_edt, gaussian_filter

from . import fetch, landmarks, places, pois, streets, styles, textures
from .traffic import TrafficNetwork
from .common import (CACHE_DIR, MAP_DIR, TILES_DIR, Projector, TileKey, load_config,
                     stable_rng, tiles_for_bbox)
from .extract import extract
from .overview import build_overview
from .sea import sea_polygon
from .heights import compute_node_heights, densify_ways, way_group
from .meshbuild import (CellGrid, MeshBuilder, Surface, densify, drape, flat_cap,
                        offset_polyline, polygons_of, ribbon, triangulate, walls)
from .terrain import HeightField, build_heightfield
from .tilewriter import write_tile
from .variant import pack_tile

RIVER_LEVEL = 0.0
SEA_NAME = "Indian Ocean"
SEA_SHELF = 0.05   # sea floor drop per metre from the shore
SEA_FLOOR = -6.0
COAST_BAND = 80.0  # metres inland of the sea where low unmapped ground becomes beach
MOLE_CREST = {"breakwater": 3.0, "groyne": 2.0}  # rock walls stand this high above the sea
HOME_RAMP = 30.0        # roads ease to the townhouse's ground over this distance
PIER_WIDTH = {"pier": 3.0, "breakwater": 6.0, "groyne": 5.0}  # metres, when OSM has no width
ROAD_OFFSET = 0.02      # road surface above terrain
PATH_OFFSET = 0.04
SIDEWALK_TOP = 0.16
MARK_OFFSET = 0.07
TUNNEL_HEIGHT = 5.6
TUNNEL_ROOF = 0.6       # thickness of a tunnel's roof
TUNNEL_SLOT = 0.3       # ground less than this above a tunnel's roof comes away over it
TUNNEL_HEADROOM = {"road": 4.0, "service": 2.5, "foot": 2.5}  # least a ceiling comes down to
TUNNEL_STEP = 4.0
# Ground fit to roads (World._fit_ground_to_roads).
CORE_MARGIN = 2.5     # metres past a road's kerb or sidewalk held level with it (half a grid cell)
EDGE_BLEND = 12.0     # at least this wide an ease from a road's edge back to the ground
SHORE_GRADE = 0.15    # lake banks rise from the water no steeper than this (1 in 7)
SHORE_REACH = 60.0    # ...out to this far from the water
SEED_TOLERANCE = 1.5  # roads further than this from the DEM (ramps, cuttings) don't shape the ground
DEM_NEAR = 10.0       # open ground starts to take the DEM this far from a road...
DEM_FAR = 45.0        # ...and has all of it from here
BUILT_REACH = 20.0    # ground this close to a building is interpolated from the roads
BUILT_SOFT = 15.0     # softening of the built-up edge (metres)
BARE_WINDOW = 75.0    # building mounds narrower than this come out of the DEM among buildings
BARE_SOFT = 10.0
FILL_SCALES = (12.0, 40.0, 120.0, 400.0)  # metres, finest first
CHUNK = 12            # segments per vectorised corridor step
OVERLAP_BLEND = 6.0   # metres over which overlapping roads at different heights ease into each other
DECK_THICKNESS = 1.1
PARAPET_H = 0.9
KERB_RADIUS = 1.5       # road gaps narrower than twice this close up; junction corners round off
SLIVER = 0.4            # path pieces thinner than twice this are dropped


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
    name: str = ""


# ---------------------------------------------------------------------------
# World preparation (shared by every tile in a build)
# ---------------------------------------------------------------------------

def deck_heights(hf, poly, kind: str) -> tuple[float, float]:
    """Top and bottom of a pier, groyne or platform deck."""
    ring = np.asarray(poly.exterior.coords)
    gh = hf.sample(ring[:, 0], ring[:, 1])
    if kind in ("pier", "groyne"):
        # Out over the water: above the waves, or level with the shore it leaves.
        top = max(float(np.max(gh)) if kind == "pier" else float(np.median(gh)) + 0.6,
                  RIVER_LEVEL + (1.2 if kind == "pier" else 1.6))
        return top, min(float(np.min(gh)), RIVER_LEVEL) - 1.0
    return float(np.median(gh)) + 0.9, float(np.min(gh)) - 0.3


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
        # One width per street, and no car park decks or roads inside buildings.
        src_ways = streets.normalise(src_ways, [
            a.geom for a in feats.areas
            if "building" in a.tags and a.tags.get("building") not in ("no", "roof", "construction")])
        self.lifted_tiles = set()  # tiles whose ground _raise_moles / _sculpt_sea lifted
        # Ground the road fit must leave as the DEM shaped it: water, banks, moles.
        self.keep_dem = np.zeros(hf.H.shape, dtype=bool)
        self._raise_moles(feats)
        self.built = self._built_up_mask([a.geom for a in feats.areas if _is_building(a.tags)])
        self.built_soft = gaussian_filter(self.built.astype(np.float64), BUILT_SOFT / hf.step)
        src_ways = densify_ways(src_ways)
        self.bare = self._bare_earth()
        node_h = compute_node_heights(src_ways, self.bare, _carriageway_pairs(src_ways))
        self.carriageway_moves = _level_carriageways(src_ways, node_h)
        if self.home:
            self._level_to_home(src_ways, node_h)
        self.ways: list[LinearWay] = []
        self.decks = []        # piers and platforms: (polygon, kind, osm id)
        coast = []
        for w in src_ways:
            g = way_group(w.tags)
            if not g:
                if w.tags.get("natural") == "coastline":
                    coast.append(LineString(w.coords))
                    continue
                mm = w.tags.get("man_made")
                if mm in PIER_WIDTH and len(w.coords) > 1 and not np.allclose(w.coords[0], w.coords[-1]):
                    # Jetties and groynes drawn as a line: a deck of their usual width.
                    width = styles._num(w.tags.get("width"), PIER_WIDTH[mm]) or PIER_WIDTH[mm]
                    self.decks.append((LineString(w.coords).buffer(width / 2, cap_style=2),
                                       "pier" if mm == "pier" else "groyne", w.id))
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
        # Hand-placed decks for jetties and groynes OSM draws as coastline, or not at all.
        for i, d in enumerate(cfg.get("hand_decks", [])):
            lat, lon = np.asarray(d["line"], dtype=float).T
            e, n = proj.fwd(lon, lat)
            width = d.get("width", PIER_WIDTH[d["kind"]])
            self.decks.append((LineString(np.c_[e, n]).buffer(width / 2, cap_style=2),
                               "pier" if d["kind"] == "pier" else "groyne", -(i + 1)))
        self.junctions = self._junction_nodes()
        self.doubled_paths = streets.doubled_footways(self.ways)

        self.water: list[WaterBody] = []
        self.cover: list[tuple[str, int, object]] = []
        self.buildings = []
        self.parts = []
        self.parking = []      # amenity=parking / parking_space areas, for traffic
        for a in feats.areas:
            t = a.tags
            if t.get("amenity") in ("parking", "parking_space"):
                self.parking.append(a)
            if "building:part" in t:
                self.parts.append(a)
                continue
            if _is_building(t):
                self.buildings.append(a)
                continue
            if t.get("man_made") == "pier" or t.get("railway") == "platform":
                # (Breakwater and groyne areas stay terrain: some carry roads, like North Mole.)
                self.decks.append((a.geom, "pier" if t.get("man_made") == "pier" else "platform", a.id))
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
        self.coast = shapely.line_merge(shapely.union_all(coast)) if coast else None
        sea = self._sea()
        if sea is not None:
            self.water.append(sea)
        self.water_union = shapely.union_all([w.geom for w in self.water]) if self.water else Polygon()
        # Hand-built landmarks replace whatever OSM buildings stand on them.
        self.landmarks = landmarks.collect(feats, self.ways)
        zones = [z for z in (lm.clear_zone() for lm in self.landmarks) if not z.is_empty]
        self.landmark_zone = shapely.union_all(zones) if zones else Polygon()
        if zones:
            self.buildings = [b for b in self.buildings
                              if not self.landmark_zone.contains(b.geom.representative_point())]
        # Hand-made models placed on the map (config "placed_props", props.json)
        # replace the OSM buildings under them.
        self.placed = []
        for spec, e, n in _expand_placed(cfg.get("placed_props", []), proj):
            self.placed.append((spec, e, n))
            if spec.get("clear"):
                zone = Point(e, n).buffer(spec["clear"])
                self.buildings = [b for b in self.buildings if not zone.contains(b.geom.representative_point())]
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
        # Wetlands and beaches for the field journal's birds (habitats.json).
        self.habitats = [a for a in feats.areas if a.tags.get("natural") in ("wetland", "beach")]
        self.poi_areas = [a for a in feats.areas if a.tags.get("natural") == "beach"
                          or a.tags.get("amenity") in ("fuel", "fast_food", "school") or a.tags.get("tourism") == "zoo"]
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
        return WaterBody(g, level, big, t.get("name", ""))

    def _sea(self) -> WaterBody | None:
        """The ocean, cut to this build's terrain."""
        hf = self.hf
        nj, ni = hf.H.shape
        frame = sbox(hf.e0, hf.n0, hf.e0 + (ni - 1) * hf.step, hf.n0 + (nj - 1) * hf.step)
        g = sea_polygon(self.coast, frame)
        return WaterBody(g, RIVER_LEVEL, True, SEA_NAME) if g is not None else None

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

    def _raise_moles(self, feats):
        """Breakwaters and groynes drawn as areas stand up out of the sea as rock
        walls (the DEM has them at sea level). Done before road heights, so a
        road along a mole rides on top."""
        hf = self.hf
        es, ns = hf.node_coords()
        moles = [(MOLE_CREST[a.tags["man_made"]], a.geom) for a in feats.areas
                 if a.tags.get("man_made") in MOLE_CREST]
        # Moles drawn only as a line (South Mole): the land OSM's coastline gives them, out to
        # 25 m from the line (the sea sculpt takes back whatever of that is water).
        coast = [LineString(w.coords) for w in feats.ways if w.tags.get("natural") == "coastline"]
        coast = shapely.union_all(coast) if coast else None
        for w in feats.ways:
            if w.tags.get("man_made") == "breakwater" and len(w.coords) > 1 and coast is not None:
                line = LineString(w.coords)
                if line.distance(coast) < 50.0:  # on the sea, not in the river
                    moles.append((MOLE_CREST["breakwater"], line.buffer(25.0)))
        for crest, geom in moles:
            for p in polygons_of(geom):
                if p.area < 200:
                    continue
                b = p.bounds
                i0, i1 = np.searchsorted(es, [b[0] - 5, b[2] + 5])
                j0, j1 = np.searchsorted(ns, [b[1] - 5, b[3] + 5])
                if i1 <= i0 or j1 <= j0:
                    continue
                E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
                ins = shapely.contains_xy(p, E, N)
                core = shapely.contains_xy(p.buffer(-3.0), E, N)
                sub = hf.H[j0:j1, i0:i1]
                lift = np.where(core, crest, np.where(ins, crest * 0.6, -np.inf))
                self._note_lift(E[lift > sub], N[lift > sub])
                hf.H[j0:j1, i0:i1] = np.maximum(sub, lift)
                self.keep_dem[j0:j1, i0:i1] |= ins

    def _note_lift(self, e, n):
        size = self.tile_size
        self.lifted_tiles.update(f"{int(i)}_{int(j)}" for i, j in
                                 set(zip(np.floor(np.ravel(e) / size), np.floor(np.ravel(n) / size))))

    def _sculpt_sea(self, wb: WaterBody):
        """The sea floor shelves gently away from the shore (no bank lip, so
        beaches run into the water)."""
        from scipy.ndimage import distance_transform_edt
        hf = self.hf
        es, ns = hf.node_coords()
        E, N = np.meshgrid(es, ns)
        wet = shapely.contains_xy(wb.geom, E, N)
        if not wet.any():
            return
        dist = distance_transform_edt(wet) * hf.step
        bed = np.maximum(-0.3 - SEA_SHELF * dist, SEA_FLOOR)
        hf.H[wet] = np.minimum(hf.H[wet], bed[wet])
        self.keep_dem |= wet
        # Low ground just inland that OSM leaves unmapped (Trigg, Leighton) would
        # sit below the water line as lawn: lift it clear and make it beach.
        near = ~wet & (distance_transform_edt(~wet) * hf.step <= COAST_BAND) & (hf.H < 0.6)
        if near.any():
            self._note_lift(E[near], N[near])
            hf.H[near] = np.maximum(hf.H[near], 0.25)
            self.keep_dem |= near
            h = hf.step / 2
            cells = shapely.box(E[near] - h, N[near] - h, E[near] + h, N[near] + h)
            self.cover.append(("sand", 62, shapely.union_all(cells)))

    def _sculpt_terrain(self):
        """Lower riverbeds and fit the ground to road and rail profiles."""
        hf = self.hf
        H = hf.H
        es, ns = hf.node_coords()
        # Water: riverbeds under big water, a lip just above water level along banks.
        for wb in self.water:
            if not wb.big:
                continue
            if wb.name == SEA_NAME:
                self._sculpt_sea(wb)
                continue
            lake = wb.level != RIVER_LEVEL
            pad = SHORE_REACH if lake else 10.0
            for p in polygons_of(wb.geom):
                b = p.bounds
                i0, i1 = np.searchsorted(es, [b[0] - pad, b[2] + pad])
                j0, j1 = np.searchsorted(ns, [b[1] - pad, b[3] + pad])
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
                kept = ins | near
                if lake:
                    # The DEM is a surface model: the reeds and paperbarks round a
                    # wetland read as a bank metres above the water. Grade the shore
                    # down to the water instead of leaving a wall.
                    wet = shapely.contains(p, pts).reshape(E.shape)
                    d_out = (distance_transform_edt(~wet) - 0.5) * hf.step  # to the shoreline
                    cap = wb.level + 0.35 + SHORE_GRADE * np.maximum(d_out - 3.0, 0.0)
                    ramp = ~ins & (d_out <= SHORE_REACH) & (sub > cap)
                    sub[ramp] = cap[ramp]
                    kept |= ramp
                H[j0:j1, i0:i1] = sub
                self.keep_dem[j0:j1, i0:i1] |= kept
        self._fit_ground_to_roads()
        if self.home:
            self._sculpt_home(es, ns)

    def _fit_ground_to_roads(self):
        """Fit the ground to the road and rail profiles.

        Under each road (out to its kerbs or sidewalks, plus a margin) the
        ground takes the road's height at the nearest point of its centre line,
        so cross-sections are level and the asphalt draped on it is as smooth
        as the profile. Away from roads the DEM can't be trusted in built-up
        areas: it is a surface model and keeps a mound wherever buildings stood,
        so streets end up in trenches between swollen blocks. There the ground
        is interpolated from the heights of the roads around it instead, and
        only open ground well clear of roads (parks, bush, beaches) and water
        keep the DEM. Raised or sunk roads (bridge ramps, cuttings) get side
        slopes back to that ground.
        """
        hf = self.hf
        s = hf.step
        # Among buildings, the ground to compare roads with is the bare earth
        # (taken before riverbeds were dug, so keep the water as sculpted).
        H0 = hf.H.copy()
        ref = np.where(self.keep_dem, H0, H0 + self.built_soft * (self.bare.H - H0))
        best, target, fall = self._road_corridors(HeightField(hf.e0, hf.n0, s, ref))
        core = best <= CORE_MARGIN
        # Roads at ground level seed the interpolated ground; ramps and
        # cuttings don't, or they would lift or sink whole neighbourhoods.
        seed = core & (np.abs(target - ref) < SEED_TOLERANCE)
        ground = _fill_from(target, seed, s)
        # How much of the DEM shows: none near roads or among buildings, all
        # of it on open ground well away from them and on water and moles.
        d_road = distance_transform_edt(~core) * s
        w_dem = _smoothstep((d_road - DEM_NEAR) / (DEM_FAR - DEM_NEAR))
        w_dem *= 1.0 - self.built_soft
        w_dem = np.maximum(w_dem, gaussian_filter(self.keep_dem.astype(np.float64), 2.0))
        w_dem = np.clip(w_dem, 0.0, 1.0)
        ground = ground + w_dem * (H0 - ground)
        ground = np.where(np.isfinite(ground), ground, H0)
        # Under the roads: their own heights. Beside them: ease back to the
        # ground, over at least EDGE_BLEND metres (more for embankments).
        fall = np.maximum(fall, 2.0 * np.abs(target - ground) + 3.0)
        ramp = ~core & (best < CORE_MARGIN + fall)
        t = np.where(ramp, _smoothstep((best - CORE_MARGIN) / fall), 1.0)
        out = ground.copy()
        out[ramp] = target[ramp] + t[ramp] * (ground[ramp] - target[ramp])
        out[core] = target[core]
        hf.H[:] = out

    def _road_corridors(self, ref: HeightField):
        """For every grid node near a road or railway: how far it is outside
        the paved width of the nearest one (`best`, metres, <= 0 inside), the
        height of that road's centre line at the nearest point (`target`) and
        how wide its side slopes are (`fall`)."""
        hf = ref
        H = ref.H
        es, ns = hf.node_coords()
        s = hf.step
        best = np.full(H.shape, np.inf)
        target = np.zeros(H.shape)
        best2 = np.full(H.shape, np.inf)
        target2 = np.zeros(H.shape)
        fall = np.full(H.shape, EDGE_BLEND)
        for w in self.ways:
            if w.group == "foot" or w.grade_separated or len(w.xy) < 2:
                continue
            hw = w.width / 2 + (styles.SIDEWALK_WIDTH if w.sidewalk else 0.6)
            dh_all = np.abs(w.h - hf.sample(w.xy[:, 0], w.xy[:, 1]))
            for k0 in range(0, len(w.xy) - 1, CHUNK):
                k1 = min(k0 + CHUNK, len(w.xy) - 1)
                A = w.xy[k0:k1]
                B = w.xy[k0 + 1:k1 + 1]
                ha, hb = w.h[k0:k1], w.h[k0 + 1:k1 + 1]
                fl = max(EDGE_BLEND, 2.0 * float(dh_all[k0:k1 + 1].max()) + 3.0)
                r = hw + CORE_MARGIN + fl
                lo_e = min(A[:, 0].min(), B[:, 0].min()) - r
                hi_e = max(A[:, 0].max(), B[:, 0].max()) + r
                lo_n = min(A[:, 1].min(), B[:, 1].min()) - r
                hi_n = max(A[:, 1].max(), B[:, 1].max()) + r
                i0 = max(int((lo_e - hf.e0) / s), 0)
                i1 = min(int((hi_e - hf.e0) / s) + 2, H.shape[1])
                j0 = max(int((lo_n - hf.n0) / s), 0)
                j1 = min(int((hi_n - hf.n0) / s) + 2, H.shape[0])
                if i1 <= i0 or j1 <= j0:
                    continue
                E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
                E, N = E[..., None], N[..., None]
                d = B - A
                L2 = np.maximum((d * d).sum(axis=1), 1e-9)
                t = np.clip(((E - A[:, 0]) * d[:, 0] + (N - A[:, 1]) * d[:, 1]) / L2, 0, 1)
                dist = np.hypot(E - (A[:, 0] + t * d[:, 0]), N - (A[:, 1] + t * d[:, 1]))
                kmin = np.argmin(dist, axis=2)[..., None]
                dist = np.take_along_axis(dist, kmin, axis=2)[..., 0]
                tt = np.take_along_axis(t, kmin, axis=2)[..., 0]
                hh = ha[kmin[..., 0]] + tt * (hb[kmin[..., 0]] - ha[kmin[..., 0]])
                score = dist - hw
                sb = best[j0:j1, i0:i1]
                st = target[j0:j1, i0:i1]
                sb2 = best2[j0:j1, i0:i1]
                st2 = target2[j0:j1, i0:i1]
                upd = score < sb
                second = ~upd & (score < sb2)
                if upd.any():
                    sb2[upd] = sb[upd]
                    st2[upd] = st[upd]
                    sb[upd] = score[upd]
                    st[upd] = hh[upd] - 0.02
                    fall[j0:j1, i0:i1][upd] = fl
                if second.any():
                    sb2[second] = score[second]
                    st2[second] = hh[second] - 0.02
        # Where two roads overlap (slip roads merging, a street passing an
        # embankment) and their heights differ, ease between them instead of
        # leaving a step where the nearer one takes over.
        both = best2 <= CORE_MARGIN
        gap = np.where(both, best2 - np.minimum(best, CORE_MARGIN), OVERLAP_BLEND)
        w2 = np.where(both, 0.5 * (1.0 - _smoothstep(gap / OVERLAP_BLEND)), 0.0)
        target = target + w2 * (np.where(both, target2, target) - target)
        return best, target, fall

    def _bare_earth(self) -> HeightField:
        """The DEM with building mounds taken out where there are buildings.

        A grey opening (the highest surface a 75 m square can't poke above)
        removes bumps narrower than the square but keeps slopes. It would
        also shave hilltops, so it is only used among buildings; open ground
        keeps the DEM. Road profiles are sampled from this."""
        from scipy.ndimage import maximum_filter, minimum_filter
        hf = self.hf
        size = int(round(BARE_WINDOW / hf.step)) | 1
        opened = maximum_filter(minimum_filter(hf.H, size=size), size=size)
        opened = gaussian_filter(opened, BARE_SOFT / hf.step)
        bare = hf.H + self.built_soft * (np.minimum(opened, hf.H) - hf.H)
        bare = np.where(self.keep_dem, hf.H, bare)
        return HeightField(hf.e0, hf.n0, hf.step, bare)

    def _built_up_mask(self, geoms):
        """Grid nodes within BUILT_REACH of a building."""
        from PIL import Image, ImageDraw
        hf = self.hf
        nj, ni = hf.H.shape
        img = Image.new("L", (ni, nj), 0)
        draw = ImageDraw.Draw(img)
        s = hf.step

        def paint(geom):
            for p in polygons_of(geom):
                xy = np.asarray(p.exterior.coords)
                px = (xy[:, 0] - hf.e0) / s
                py = (xy[:, 1] - hf.n0) / s
                if px.max() < 0 or py.max() < 0 or px.min() > ni or py.min() > nj:
                    continue
                draw.polygon(list(zip(px.tolist(), py.tolist())), fill=1)

        for g in geoms:
            paint(g)
        mask = np.asarray(img, dtype=bool)
        near = distance_transform_edt(~mask) * s <= BUILT_REACH
        return near

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
    return [(xy[a:b + 1], h[a:b + 1]) for a, b in _clip_spans(xy, bounds)]


def _clip_spans(xy, bounds):
    """(first, last) point index of each run of _clip_runs."""
    e0, n0, e1, n1 = bounds
    mid = (xy[:-1] + xy[1:]) / 2
    inside = (mid[:, 0] >= e0) & (mid[:, 0] < e1) & (mid[:, 1] >= n0) & (mid[:, 1] < n1)
    return [(int(a), int(b)) for a, b in _runs(inside)]


def _runs(mask):
    """(start, stop) of each run of True in `mask`."""
    d = np.diff(np.concatenate([[0], mask.astype(np.int8), [0]]))
    return list(zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]))


def _resample(xy, step):
    seg = np.linalg.norm(np.diff(xy, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return xy[:1], s[:1]
    n = max(2, int(np.ceil(s[-1] / step)) + 1)
    ss = np.linspace(0, s[-1], n)
    return np.column_stack([np.interp(ss, s, xy[:, 0]), np.interp(ss, s, xy[:, 1])]), ss


def _is_building(t) -> bool:
    return "building" in t and t.get("building") not in ("no", "roof", "construction") \
        and t.get("location") not in ("underground",) and t.get("layer", "0") not in ("-1", "-2")


def _smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def _fill_from(values: np.ndarray, seed: np.ndarray, step: float) -> np.ndarray:
    """A smooth surface through `values` at the `seed` nodes, filling the
    rest of the grid (normalised Gaussian convolution, finest scale first:
    each scale fills in where the finer ones had too little data)."""
    out = np.full(values.shape, np.nan)
    have = np.zeros(values.shape)
    v = np.where(seed, values, 0.0)
    w = seed.astype(np.float64)
    for sigma in FILL_SCALES:
        sg = sigma / step
        if sg > 8:
            # Big kernels on a coarser grid, then back up (bilinear).
            f = int(sg // 4)
            sv = _block_mean(v, f)
            sw = _block_mean(w, f)
            gv = _upsample(gaussian_filter(sv, sg / f), f, values.shape)
            gw = _upsample(gaussian_filter(sw, sg / f), f, values.shape)
        else:
            gv = gaussian_filter(v, sg)
            gw = gaussian_filter(w, sg)
        est = gv / np.maximum(gw, 1e-12)
        # Confidence: enough seed weight in reach (a road's worth across the kernel).
        conf = np.clip(gw * sg * 2.0, 0.0, 1.0)
        take = (1.0 - have) * conf
        out = np.where(np.isnan(out), 0.0, out) + take * np.where(gw > 1e-9, est, 0.0)
        have = have + take
    done = have > 1e-6
    out = np.where(done, out / np.maximum(have, 1e-12), np.nan)
    return out


def _block_mean(a, f):
    nj, ni = a.shape
    pj, pi = (-nj) % f, (-ni) % f
    a = np.pad(a, ((0, pj), (0, pi)), mode="edge")
    return a.reshape(a.shape[0] // f, f, a.shape[1] // f, f).mean(axis=(1, 3))


def _upsample(a, f, shape):
    from scipy.ndimage import map_coordinates
    jj = (np.arange(shape[0]) + 0.5) / f - 0.5
    ii = (np.arange(shape[1]) + 0.5) / f - 0.5
    J, I = np.meshgrid(jj, ii, indexing="ij")
    return map_coordinates(a, [J, I], order=1, mode="nearest")


def _carriageway_pairs(ways) -> list[tuple[int, int]]:
    """(node, node) pairs of roads that should come out level with each other.
    Heights are solved with these as short links:

    - each node of a named one-way carriageway and the nearest node of its
      other half beside it (each half's DEM samples differ on a cross slope,
      St Georges Tce);
    - nodes of any two at-grade roads whose asphalt touches (a slip road
      alongside the freeway, a lane beside a street), which otherwise end up
      a few tenths apart and draped into one lumpy surface.
    """
    from scipy.spatial import cKDTree
    pairs = []
    by_name: dict[str, list] = {}
    flat = [w for w in ways if way_group(w.tags) == "road" and not styles.is_bridge(w.tags)
            and not styles.is_tunnel(w.tags) and len(w.coords) > 1]
    for w in flat:
        t = w.tags
        if t.get("oneway") in ("yes", "-1") and t.get("name"):
            by_name.setdefault(t["name"], []).append(w)
    for group in by_name.values():
        if len(group) < 2:
            continue
        for wa in group:
            others = [w for w in group if w is not wa]
            xy = np.concatenate([w.coords for w in others])
            ids = np.concatenate([w.nodes for w in others])
            ends = np.concatenate([np.r_[True, np.zeros(len(w.nodes) - 2, bool), True] for w in others])
            tree = cKDTree(xy)
            reach = styles.road_width(wa.tags) + TOUCH + 2.0
            d, k = tree.query(wa.coords, distance_upper_bound=reach)
            for nid, dd, kk in zip(wa.nodes, d, k):
                if np.isfinite(dd) and not ends[kk]:
                    pairs.append((int(nid), int(ids[kk])))
    # Touching asphalt.
    if flat:
        xy = np.concatenate([w.coords for w in flat])
        ids = np.concatenate([w.nodes for w in flat]).astype(np.int64)
        way = np.concatenate([np.full(len(w.nodes), k) for k, w in enumerate(flat)])
        half = np.concatenate([np.full(len(w.nodes), styles.road_width(w.tags) / 2) for w in flat])
        tree = cKDTree(xy)
        found = tree.query_pairs(r=2 * float(half.max()) + TOUCH, output_type="ndarray")
        if len(found):
            i, j = found[:, 0], found[:, 1]
            dist = np.linalg.norm(xy[i] - xy[j], axis=1)
            ok = (way[i] != way[j]) & (ids[i] != ids[j]) & (dist < half[i] + half[j] + TOUCH)
            pairs.extend(zip(ids[i[ok]].tolist(), ids[j[ok]].tolist()))
    return pairs


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
        self._tunnel_cut()
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
        # Closing the union fills slivers of ground between carriageways and
        # rounds the kerb at junction corners instead of leaving a notch.
        self.road_area = streets.close_gaps(self._buffer_ways(at_grade), KERB_RADIUS).intersection(clip)
        side = [w for w in at_grade if w.sidewalk]
        self.sidewalk_area = (self._buffer_ways(side, styles.SIDEWALK_WIDTH)
                              .intersection(clip).difference(self.road_area)
                              .difference(self.w.water_union))
        foot = [w for w in self.ways if w.group == "foot" and not w.grade_separated
                and w.tags.get("highway") != "corridor" and w.id not in self.w.doubled_paths]
        self.path_area = (self._buffer_ways(foot).intersection(clip)
                          .difference(self.road_area).difference(self.sidewalk_area)
                          .difference(self.w.water_union))
        # Paths that end up as thin slivers along a kerb or a road edge.
        self.path_area = self.path_area.buffer(-SLIVER, quad_segs=1).buffer(SLIVER, quad_segs=1) \
            .intersection(self.path_area)
        rails = [w for w in self.ways if w.group == "rail" and not w.grade_separated]
        self.rail_area = self._buffer_ways(rails).intersection(clip)
        if self.w.home:
            fp = self.w.home.footprint
            self.road_area = self.road_area.difference(fp)
            self.sidewalk_area = self.sidewalk_area.difference(fp)
            self.path_area = self.path_area.difference(fp)
        # Simplified once here, so the ground leaves exactly the gap the footpaths fill
        # (simplifying only the drawn footpaths opened sky-coloured cracks along them).
        self.sidewalk_area = self.sidewalk_area.simplify(0.2)

    def _box_tunnels(self):
        return [w for w in self.ways if w.tunnel and w.group != "rail" and not self._shallow_path(w)]

    def _tunnel_outline(self, w, xy, h):
        """The box of tunnel `w` along `xy`: its outside edges, ceiling and roof
        heights, and which segments have ground or streets above that come
        down to within TUNNEL_SLOT of the roof (there the roof shows).

        Where the ground over it is lower than a full-height box, the ceiling
        comes down (to no less than TUNNEL_HEADROOM) to keep the roof under
        the ground: a box built full height stuck up out of streets and
        squares over shallow tunnels and underground car parks."""
        half = w.width / 2 + 1.0
        left, right = offset_polyline(xy, half), offset_polyline(xy, -half)
        hf = self.w.hf
        floor = h + 0.02
        # Lowest ground across the box, sampled finer than the ground grid.
        lines = [offset_polyline(xy, d) for d in np.linspace(-half, half, int(np.ceil(half / 1.25)) + 1)]
        ground = np.minimum.reduce([hf.sample(p[:, 0], p[:, 1]) for p in lines])
        fits = ground - floor - TUNNEL_ROOF - TUNNEL_SLOT - 0.05
        least = TUNNEL_HEADROOM["service" if w.tags.get("highway") == "service" else w.group]
        head = np.clip(fits, least, TUNNEL_HEIGHT)
        # Steady along the tunnel, and never above what fits under the ground either side.
        p = np.pad(head, 1, mode="edge")
        p = np.pad(np.minimum.reduce([p[:-2], p[1:-1], p[2:]]), 1, mode="edge")
        ceiling = floor + (p[:-2] + p[1:-1] + p[2:]) / 3
        roof = ceiling + TUNNEL_ROOF
        near = ground < roof + TUNNEL_SLOT
        mid_ground = np.minimum.reduce([hf.sample((p[:-1, 0] + p[1:, 0]) / 2, (p[:-1, 1] + p[1:, 1]) / 2)
                                        for p in lines])
        low = near[:-1] | near[1:] | (mid_ground < (roof[:-1] + roof[1:]) / 2 + TUNNEL_SLOT)
        return left, right, ceiling, roof, low

    def _tunnel_cut(self):
        """Ground and streets come away over a tunnel's roof where they would
        cut into it, along the roof's own outline. (Leaving out the whole 5 m
        ground cells there left open holes either side of the roof that the
        car could fall into.)"""
        pieces = []
        for w in self._box_tunnels():
            xy, h = densify(w.xy, w.h, TUNNEL_STEP)
            left, right, _, _, low = self._tunnel_outline(w, xy, h)
            k = np.nonzero(low)[0]
            if len(k):
                quads = np.stack([right[k], right[k + 1], left[k + 1], left[k], right[k]], axis=1)
                pieces.extend(shapely.make_valid(shapely.polygons(quads)))
        cut = shapely.union_all(pieces) if pieces else Polygon()
        self.tunnel_cut = cut.intersection(self.box.buffer(20))

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
            drape(surf, g.difference(self.tunnel_cut), self.grid, 0.0, textures.UV_SCALE.get(mat, 8.0))
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
        area = self.road_area.intersection(self.box).difference(self.tunnel_cut)
        drape(self.mb.surface("roads", "asphalt", "world"), area, self.grid, ROAD_OFFSET,
              textures.UV_SCALE["asphalt"])

    def _sidewalks_paths(self):
        hf = self.w.hf
        sw = self.sidewalk_area.intersection(self.box)
        drape(self.mb.surface("roads", "sidewalk", "world"), sw.difference(self.tunnel_cut), self.grid,
              SIDEWALK_TOP, textures.UV_SCALE["sidewalk"])
        kerb = self.mb.surface("roads", "kerb", "world")
        cut = self.tunnel_cut
        shapely.prepare(cut)
        for p in polygons_of(sw):
            p = orient(p, 1.0)
            for ring in [p.exterior, *p.interiors]:
                xy = np.asarray(ring.coords)
                xy, _ = densify(xy, np.zeros(len(xy)), 6.0)
                g = hf.sample(xy[:, 0], xy[:, 1])
                over = shapely.contains_xy(cut, xy[:, 0], xy[:, 1]) if not cut.is_empty else None
                if over is None or not over.any():
                    walls(kerb, xy, g, g + SIDEWALK_TOP, 2.0, 0.5)
                    continue
                # No kerb across a tunnel roof.
                for a, b in _runs(~over):
                    if b - a >= 2:
                        walls(kerb, xy[a:b], g[a:b], g[a:b] + SIDEWALK_TOP, 2.0, 0.5, closed=False)
        pa = self.path_area.intersection(self.box)
        drape(self.mb.surface("roads", "path", "world"), pa.difference(self.tunnel_cut), self.grid,
              PATH_OFFSET, textures.UV_SCALE["path"])

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
        hf = self.w.hf
        for w in self._box_tunnels():
            xy, h = densify(w.xy, w.h, TUNNEL_STEP)
            outline = self._tunnel_outline(w, xy, h)
            for a, b in _clip_spans(xy, self.bounds):
                rxy, rh = xy[a:b + 1], h[a:b + 1]
                lo, ro, ceiling, roof = (v[a:b + 1] for v in outline[:4])
                low = outline[4][a:b]
                floor = rh + 0.02
                mat = "asphalt" if w.group == "road" else "path"
                ribbon(self.mb.surface("tunnels", mat, "world"), rxy, floor, w.width + 1.0,
                       textures.UV_SCALE.get(mat, 4.0))
                surf = self.mb.surface("tunnels", "tunnel_wall", "world")
                half = w.width / 2 + 0.5
                left = offset_polyline(rxy, half)
                right = offset_polyline(rxy, -half)
                walls(surf, left, floor, ceiling, 3.0, TUNNEL_HEIGHT, closed=False)
                walls(surf, right[::-1], floor[::-1], ceiling[::-1], 3.0, TUNNEL_HEIGHT, closed=False)
                ribbon(surf, rxy, ceiling, w.width + 1.0, 4.0, up=False)
                # Outside of the box: its roof shows where the ground over it is cut away
                # (_tunnel_cut), and its sides rise to meet the ground at the cut's edges.
                outer = self.mb.surface("tunnels", "concrete", "world")
                ribbon(outer, rxy, roof, w.width + 2.0, 4.0)
                lt = np.maximum(roof, np.minimum(hf.sample(lo[:, 0], lo[:, 1]), roof + 1.0))
                rt = np.maximum(roof, np.minimum(hf.sample(ro[:, 0], ro[:, 1]), roof + 1.0))
                walls(outer, lo[::-1], floor[::-1] - 0.5, lt[::-1], 3.0, 3.0, closed=False)
                walls(outer, ro, floor - 0.5, rt, 3.0, 3.0, closed=False)
                # Where the cut ends along the tunnel, a face from the roof up to the ground.
                for k in np.nonzero(low[1:] != low[:-1])[0] + 1:
                    edge = np.array([lo[k], rxy[k], ro[k]])
                    top = np.maximum(roof[k], np.minimum(hf.sample(edge[:, 0], edge[:, 1]), roof[k] + 1.0))
                    walls(outer, edge, roof[k], top, 3.0, 3.0, closed=False)
                    walls(outer, edge[::-1], roof[k], top[::-1], 3.0, 3.0, closed=False)

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
        for g, kind, _ in self.w.decks:
            for p in polygons_of(g):
                c = p.representative_point()
                if not self.box.contains(c):
                    continue
                p = orient(p, 1.0)
                top, bottom = deck_heights(hf, p, kind)
                surf = self.mb.surface("props", {"pier": "path", "groyne": "concrete"}.get(kind, "sidewalk"), "world")
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
        bld = [p for b in self.w.buildings for p in polygons_of(b.geom)
               if p.intersects(self.box)]
        bld = shapely.union_all(bld) if bld else Polygon()
        if len(self.w.trees):
            m = ((self.w.trees[:, 0] >= self.bounds[0]) & (self.w.trees[:, 0] < self.bounds[2]) &
                 (self.w.trees[:, 1] >= self.bounds[1]) & (self.w.trees[:, 1] < self.bounds[3]))
            # OSM's own trees keep their spot, but not on a carriageway, the
            # railway or inside a building (street trees drawn at the kerb
            # land on our wider roads).
            hard = shapely.union_all([self.road_area, self.rail_area.buffer(1.0), bld.buffer(0.5)])
            shapely.prepare(hard)
            for e, n in self.w.trees[m]:
                kind = "tree_round" if rng.random() < 0.6 else "tree_gum"
                items.append((kind, e, n, not shapely.contains_xy(hard, e, n)))
        blockers = shapely.union_all([self.road_area, self.path_area, self.sidewalk_area,
                                      self.rail_area.buffer(3)])
        if not bld.is_empty:
            blockers = blockers.union(bld.buffer(2.0))
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
                items.append((kinds[rng.integers(len(kinds))], e, n, True))
        # Dropped trees still take their random draws, so the rest keep their look.
        for kind, e, n, keep in items:
            hgt = float(hf.sample(e, n))
            scale = 0.75 + rng.random() * 0.6
            yaw = rng.random() * math.tau
            if keep:
                self.instances.setdefault(kind, []).append((e, n, hgt, yaw, scale))

    def _street_lights(self):
        hf = self.w.hf
        bld = [p for b in self.w.buildings for p in polygons_of(b.geom) if p.intersects(self.box)]
        bld = shapely.union_all(bld).buffer(0.5) if bld else Polygon()
        shapely.prepare(bld)
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
                if shapely.contains_xy(bld, e, n):
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
          index_only: bool = False, jobs: int = 1):
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
        if world.lifted_tiles:
            print("Moles and low coast lifted in tiles: " + " ".join(sorted(world.lifted_tiles)))
        _write_index(cfg, proj, world, index, index_path, region_of)
        print(f"Index: {len(index.get('pois', []))} points of interest")
        return
    todo = [k for k in keys if k in set(only)] if only is not None else keys
    net = TrafficNetwork(world)
    global _JOB
    _JOB = (world, net, out_dir, size, traffic_only)
    if jobs > 1 and len(todo) > 1:
        import multiprocessing as mp
        # Forked workers share the prepared world; each writes its own tiles.
        with mp.get_context("fork").Pool(jobs) as pool:
            results = pool.imap(_build_one, todo)
            results = list(_report(results, len(todo)))
    else:
        results = list(_report(map(_build_one, todo), len(todo)))
    for key, tname, tbytes, entry in results:
        if traffic_only:
            if key.name in index["tiles"]:
                index["tiles"][key.name]["traffic"] = tname
            total += tbytes
            continue
        entry["region"] = region_of.get(key, "custom")
        index["tiles"][key.name] = entry
        total += entry["bytes"]
    _write_index(cfg, proj, world, index, index_path, region_of)
    if traffic_only:
        print(f"Traffic data: {total / 1e6:.2f} MB")
        return
    if only is None or not (out_dir / "overview.p5o").exists():
        nbytes = build_overview(cfg, proj, index["tiles"], out_dir / "overview.p5o")
        print(f"  overview: {nbytes / 1024:.0f} KB")
    print(f"Done: {total / 1e6:.1f} MB")


_JOB = None


def _build_one(key: TileKey):
    world, net, out_dir, size, traffic_only = _JOB
    t0 = time.time()
    tname = f"{key.name}.p5r"
    tbytes = write_traffic(out_dir / tname, net.tile_data(key.bounds(size)))
    if traffic_only:
        return key, tname, tbytes, None, time.time() - t0
    data = TileBuilder(world, key).build()
    nbytes = write_tile(out_dir / f"{key.name}.p5t", data)
    entry = {"i": key.i, "j": key.j, "file": f"{key.name}.p5t", "region": "custom",
             "hmin": round(data["hrange"][0], 2), "hmax": round(data["hrange"][1], 2), "bytes": nbytes,
             "traffic": tname}
    return key, tname, tbytes, entry, time.time() - t0


def _report(results, total):
    for n, (key, tname, tbytes, entry, dt) in enumerate(results):
        if entry is not None:
            print(f"  [{n + 1}/{total}] tile {key.name}: {entry['bytes'] / 1024:.0f} KB in {dt:.1f}s", flush=True)
        yield key, tname, tbytes, entry


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
    # Lakes and ponds with their water level, in lakes.json (MapStreamer.water_level_at):
    # each lake belongs to the stage owning the tile under its outline's mean point,
    # so stages with overlapping terrain don't write it twice.
    own = {k.name for k in region_of}
    size = cfg["tile_size"]

    def owned(outline):
        x, z = np.mean(np.asarray(outline, dtype=float), axis=0)
        return f"{math.floor(x / size)}_{math.floor(-z / size)}" in own
    lakes = {}
    for wb in world.water:
        if wb.level == RIVER_LEVEL or wb.geom.area < 1500:
            continue
        for poly in polygons_of(wb.geom):
            c = poly.representative_point()
            if not inside_hf(c.x, c.y) or poly.area < 1500:
                continue
            ring = np.asarray(poly.exterior.simplify(4.0).coords)[:-1]
            lake = {"name": wb.name, "level": round(wb.level, 2),
                    "outline": [[round(float(e), 1), round(float(-n), 1)] for e, n in ring]}
            if owned(lake["outline"]):
                lakes[(wb.name, round(c.x), round(c.y))] = lake
    lakes_path = path.with_name("lakes.json")
    old = json.loads(lakes_path.read_text()) if lakes_path.exists() else []
    kept = [l for l in old if not owned(l["outline"])]
    # One lake per line: the outlines would be most of index.json in its layout.
    rows = [json.dumps(l, separators=(",", ":")) for l in
            sorted(kept + list(lakes.values()), key=lambda l: (l["name"], l["outline"][0]))]
    lakes_path.write_text("[\n" + ",\n".join(rows) + "\n]\n")
    index.pop("lakes", None)
    _write_habitats(world, path.with_name("habitats.json"), inside_hf, owned)
    _write_placed(world, path.with_name("props.json"), inside_hf, region_of, size)
    _write_places(cfg, proj, world, index, inside_hf, region_of)
    index["tiles"] = dict(sorted(index["tiles"].items(), key=lambda kv: (kv[1]["j"], kv[1]["i"])))
    path.write_text(json.dumps(index, indent=1) + "\n")


def _expand_placed(specs: list, proj: Projector):
    """Config placed_props as (spec, e, n). A spec with `run` ({"to": [lat, lon],
    "step": m, "axis": "z" or "x"}) repeats its model every `step` metres from
    lat/lon toward `to`, the model's local axis along the line; ids get _1, _2..."""
    for spec in specs:
        e, n = (float(v) for v in proj.fwd(spec["lon"], spec["lat"]))
        run = spec.get("run")
        if not run:
            yield spec, e, n
            continue
        e1, n1 = (float(v) for v in proj.fwd(run["to"][1], run["to"][0]))
        length = math.hypot(e1 - e, n1 - n)
        ue, un = (e1 - e) / length, (n1 - n) / length
        along = math.degrees(math.atan2(ue, un)) % 360
        bearing = along if run.get("axis", "z") == "z" else (along + 90) % 360
        step = float(run["step"])
        for k in range(int(length // step + 1e-6)):
            one = {key: v for key, v in spec.items() if key != "run"}
            one.update(id=f"{spec['id']}_{k + 1}", bearing=round(bearing, 2))
            yield one, e + ue * step * k, n + un * step * k


def _write_placed(world: World, path: Path, inside_hf, region_of: dict, size: float):
    """Hand-made models to place (MapStreamer._add_placed_props): id, scene,
    p (Godot, on the ground) and yaw turning the model's +Z front to its
    compass bearing. Each belongs to the stage owning its tile."""
    own = {k.name for k in region_of}
    fresh = {}
    for spec, e, n in world.placed:
        key = f"{math.floor(e / size)}_{math.floor(n / size)}"
        if key not in own or not inside_hf(e, n):
            continue
        if "y" in spec:
            y = float(spec["y"])
        elif "deck" in spec:
            # On a jetty: the deck top MeshBuilder draws (deck_heights).
            g = next(g for g, _, oid in world.decks if oid == spec["deck"])
            y = deck_heights(world.hf, max(polygons_of(g), key=lambda q: q.area), "pier")[0]
        else:
            y = float(world.hf.sample(e, n))
        fresh[spec["id"]] = {"id": spec["id"], "scene": spec["scene"],
                             "p": [round(e, 2), round(y, 2), round(-n, 2)],
                             "yaw": round(math.pi - math.radians(spec["bearing"]), 4)}
    old = json.loads(path.read_text()) if path.exists() else []
    kept = [p for p in old if p["id"] not in fresh and
            f"{math.floor(p['p'][0] / size)}_{math.floor(-p['p'][2] / size)}" not in own]
    path.write_text(json.dumps(sorted(kept + list(fresh.values()), key=lambda p: p["id"]), indent=1) + "\n")


def _write_habitats(world: World, path: Path, inside_hf, owned):
    """Wetland and beach outlines (OSM natural=wetland / beach) where the bird
    thread spawns reed birds and shorebirds. Ids are `<kind>_<osm id>`, stable
    across builds; like lakes, each belongs to the stage owning its tile."""
    fresh = {}
    for a in world.habitats:
        t = a.tags
        kind = t["natural"]
        for k, poly in enumerate(sorted(polygons_of(a.geom), key=lambda q: -q.area)):
            c = poly.representative_point()
            if poly.area < 400 or not inside_hf(c.x, c.y):
                continue
            ring = np.asarray(poly.exterior.simplify(3.0).coords)[:-1]
            if len(ring) < 3:
                continue
            hid = f"{kind}_{a.id}" + (f"_{k + 1}" if k else "")
            h = {"id": hid, "kind": kind, "name": t.get("name", ""), "area": round(poly.area),
                 "outline": [[round(float(e), 1), round(float(-n), 1)] for e, n in ring]}
            if kind == "wetland" and t.get("wetland"):
                h["wetland"] = t["wetland"]
            if owned(h["outline"]):
                fresh[hid] = h
    old = json.loads(path.read_text()) if path.exists() else []
    kept = [h for h in old if h["id"] not in fresh and not owned(h["outline"])]
    rows = [json.dumps(h, separators=(",", ":")) for h in sorted(kept + list(fresh.values()), key=lambda h: h["id"])]
    path.write_text("[\n" + ",\n".join(rows) + "\n]\n")


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
    # Points of interest: rebuilt on this build's own tiles, kept elsewhere. Each
    # stage owns the stops on its tiles, so a neighbouring stage whose terrain
    # overlaps them (with less of the road network) can't drop or change them.
    own = {k.name for k in region_of}

    def owned(p):
        return f"{math.floor(p['p'][0] / size)}_{math.floor(-p['p'][2] / size)}" in own

    fresh = [p for p in pois.build(world, cfg, proj, size, set(index["tiles"]), inside_hf) if owned(p)]
    ids = {p["id"] for p in fresh}
    kept = [p for p in index.get("pois", []) if p["id"] not in ids and not owned(p)]
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
    ap.add_argument("--jobs", type=int, default=1, help="build this many tiles at once")
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
    build(cfg, keys, region_of, a.out, a.refresh, only, a.traffic_only, a.index_only, a.jobs)


if __name__ == "__main__":
    main()
