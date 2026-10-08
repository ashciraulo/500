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
PATH_TOUCH = 1.0        # a path's node this close to a jetty leads onto it
LANDING = 3.0           # a jetty is level with the shore this far in from the water
JETTY_PAD = 7.5         # ground this close to a jetty's shore end is level with its deck (every
BOARDWALK_DECK = 0.5  # a boardwalk's deck over the reeds or the water under it
                        # grid cell its edge crosses, or the ground drawn there leaves a ledge)...
JETTY_RAMP = 8.0        # ...and eases back to its own height over at least this...
SEAT_GRADE = 0.2        # ...and wide enough that the change in grade stays under this
SEAT_REACH = 40.0       # (but never further out than this)
# River between a deck and the bank, where they're this close (deck distance
# plus bank distance), is filled up to the deck, and so is river under a deck
# next to ground at its height: a quay along the shore (Elizabeth Quay) kept
# a strip of river bed between it and the bank, or under its edge, and the
# ground drawn across that left a 1.5 m pit or slope at the deck's side.
SHORE_FILL = 8.0
SHORE_LEVEL = 0.75  # (only where the bank, or the ground beside it, is up at the deck's height,
SHORE_UP = 2.5      # this far up from the water's edge,
SHORE_RUN = 2       # and along more than one ground point)
SHORE_PIT = 1.5     # a river node this far under the ground on three sides of it comes up
SHORE_PIT_MAX = 4.0  # (not a creek between high banks)
# A jetty's edge over dry ground more than RAIL_DROP under it (too high to
# step back up) has a rail RAIL_H high: off Fremantle's boardwalk you dropped
# into a strip of dry river bed between it and the quay and couldn't get out.
RAIL_DROP = 0.45
RAIL_H = 0.9
JETTY_ABOVE = 1.2       # a jetty's deck over the water it stands in
JETTY_GRADE = 1.0 / 8   # a jetty off a high bank ramps down to that at this grade...
JETTY_DROP = 6.0        # ...from a bank up to this much higher (past that it's a cliff or a lookout: level)
DECK_STEP = 1.0         # grid a ramped deck is draped on
ROAD_OFFSET = 0.02      # road surface above terrain
PATH_OFFSET = 0.04
SIDEWALK_TOP = 0.16
MARK_OFFSET = 0.07
TUNNEL_HEIGHT = 5.6
TUNNEL_ROOF = 0.6       # thickness of a tunnel's roof
TUNNEL_SLOT = 0.3       # ground less than this above a tunnel's roof comes away over it
LID_DROP = 0.15         # a tunnel's lid stays this far under the ground over it
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
PIER_SPACING = 30.0  # a bridge's piers stand about this far apart...
PIER_CLEAR = 0.6     # ...this far off the asphalt of a road (or a railway) under it,
PIER_SHIFT = 12.0    # moved along the deck up to this far to find room,
PIER_STEP = 1.5      # in steps of this
PARAPET_H = 0.9
# A bridge's parapet stops where it would stand this far inside another
# road's lane (a slip road off the deck), if that road is within JOIN_DROP
# of the deck's height there (not passing under or over it).
JOIN_MARGIN = 0.2
JOIN_STEP = 1.0  # spacing of a deck's points where a road joins it
CONTINUE_COS = float(np.cos(np.radians(20.0)))  # a way within this of straight on carries on
# Two bridge ways meeting end to end at an angle of more than JOINT_MIN
# degrees (and under JOINT_MAX) get the wedge outside the bend filled in.
JOINT_MIN = 1.0
JOINT_MAX = 150.0
# An at-grade road this much higher than another road, or a railway, whose
# asphalt (or ballast) it overlaps (a slip road leaving a bridge over the
# freeway it then joins) is carried on a deck there: one ground can't be
# under both. Their asphalt counts as overlapping out to STACK_MARGIN past
# the kerbs. Beside a freeway, a highway or a railway it's STACK_WIDE: the
# 5 m ground can't slope from one to the other in less than about two
# cells without tilting their edges (a service road 6 m over the rail
# cutting by Milligan Street dropped 0.8 m in 3 m; the freeway lanes beside
# the railway in its median, a slip road beside the freeway), so the higher
# one stands on a wall there instead, as those do.
LIFT = 1.0
STACK_MARGIN = 1.0
STACK_WIDE = 10.0
STACK_RAIL_HALF = 1.6  # a railway's half width for that
WALLED = ("motorway", "motorway_link", "trunk", "trunk_link")
# Two roads that meet don't count as stacked this close to where they meet:
# one climbing away from a junction on a hill is higher than the other there
# by its own grade (Fraser Avenue off Malcolm Street was lifted on a deck,
# with a 0.7 m side over Malcolm Street).
STACK_JUNCTION = 15.0
# ... and carried on until the ground is within LIFT_LAND of it (at most LIFT_REACH further).
LIFT_LAND = 0.15
LIFT_REACH = 40.0
# Lifted stretches of a road less than this apart are one deck.
LIFT_GAP = 30.0
# A road running off the built map (into a square with no tile) is closed
# this far back from the edge by a row of concrete barriers, and traffic
# turns before them: it read as a road going nowhere, and the car fell off
# the end.
EDGE_INSET = 8.0
BARRIER_LEN = 2.0
BARRIER_GAP = 0.15
# The bank down into a rail cutting (landuse=railway) has a row of barriers
# along its top, where the ground falls more than CUT_DROP within CUT_REACH
# past it, in runs of at least CUT_MIN: the car went off Roe St, over the
# footpath and down the bank into the rail yard, and couldn't get out. The
# top is the first point within CUT_SEARCH of the area's edge where the
# ground falls more than CUT_STEEP over 3 m.
CUT_DROP = 2.0
CUT_REACH = 8.0
CUT_SEARCH = 10.0
CUT_STEEP = 1.0
CUT_MIN = 3
CUT_SHIFT = 3.0
# A "New Jersey" barrier's cross-section: (across, up).
JERSEY = ((-0.3, 0.0), (-0.28, 0.08), (-0.12, 0.3), (-0.1, 0.85), (0.1, 0.85), (0.12, 0.3), (0.28, 0.08), (0.3, 0.0))
# The ground under a lifted stretch's deck is at least LIFT_UNDER below it
# (no more: a road beside it at its height is cut down to that too), and
# rises from a ground cell past its edges no steeper than LIFT_BANK (looked
# for out to LIFT_CUT past them).
LIFT_UNDER = 0.05
LIFT_BANK = 1.0
LIFT_CUT = 15.0
LIFT_END = 3  # (not within this many 2 m steps of its ends)
# Under a lifted stretch, its sides come down to the ground as walls where
# there's less than this much room under the deck.
LIFT_WALL_CLEAR = 3.0
# A building closer than this to a lifted deck's side (one low over the
# ground) has the ground between them come up level with the deck.
LIFT_CREVICE = 3.0
LIFT_CREVICE_DEPTH = 4.0  # (no deeper than this: a building down in a hollow keeps it)
# Ground between two lifted decks side by side, out to SLOT_REACH past the
# edge of each, comes up level with the lower of them where one of them is
# walled and the other walled or under SLOT_OPEN over the ground (Esplanade:
# a slot beside a walled ramp ran in under the open end of the next deck;
# Mounts Bay Rd: the gap between two walled decks was wider than a node).
SLOT_REACH = 7.5
SLOT_OPEN = 5.0
SLOT_ENDS = 1  # (not at a deck's very ends, where it lands)
SLOT_ALONG = 0.8  # (side by side: running the same way, give or take)
JOIN_DROP = 1.5
PARAPET_LOW = 1.0  # a road bridge's parapets fade in between this and twice this over the ground
LIGHT_BACK = 2.0   # street lights stand this far off the asphalt on a footpath...
LIGHT_VERGE = 1.8  # ...or on a verge...
LIGHT_CLEAR = 1.5  # ...and none closer than this to any asphalt
BEVEL_MAX = 1.0    # a road bridge's side lower than this over the ground beside it slopes down to it...
BEVEL_RUN = 4.0    # ...over this many metres per metre of height
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
    # Per node: carried on a deck over another road (World._lift_stacked).
    lift: np.ndarray | None = None

    @property
    def grade_separated(self) -> bool:
        return self.bridge or self.tunnel

    def ground_runs(self):
        """(xy, h) of each stretch that lies on the ground (all of an
        unlifted at-grade way; none of a bridge or tunnel)."""
        if self.grade_separated:
            return []
        if self.lift is None:
            return [(self.xy, self.h)]
        on = ~(self.lift[:-1] | self.lift[1:])
        return [(self.xy[a:b + 1], self.h[a:b + 1]) for a, b in _runs(on)]

    def pieces(self) -> list:
        """The way as drawn: a lifted way splits into stretches on the
        ground and stretches on decks (drawn as bridges)."""
        if self.lift is None or self.grade_separated:
            return [self]
        lifted = self.lift[:-1] | self.lift[1:]
        out = []
        cuts = np.nonzero(lifted[1:] != lifted[:-1])[0] + 1
        for a, b in zip(np.r_[0, cuts], np.r_[cuts, len(lifted)]):
            k = slice(a, b + 1)
            out.append(replace(self, xy=self.xy[k], h=self.h[k], nodes=self.nodes[k], lift=None,
                               bridge=bool(lifted[a]), sidewalk=self.sidewalk and not lifted[a]))
        return out


@dataclass
class WaterBody:
    geom: object
    level: float
    big: bool
    name: str = ""


@dataclass
class Deck:
    """A pier, groyne or platform deck, `top` where it leaves the land. A
    jetty off a bank high over the water ramps down from its `landing` (the
    deck over dry land, and where paths meet it) to `low` over the water."""
    poly: object
    kind: str
    oid: int
    top: float
    bottom: float
    low: float | None = None
    landing: object = None

    def heights(self, e, n) -> np.ndarray:
        e, n = np.broadcast_arrays(np.asarray(e, dtype=np.float64), np.asarray(n, dtype=np.float64))
        if self.landing is None or self.low is None or self.low >= self.top:
            return np.full(e.shape, self.top)
        d = shapely.distance(self.landing, shapely.points(e, n))
        return np.maximum(self.low, self.top - JETTY_GRADE * d)


# ---------------------------------------------------------------------------
# World preparation (shared by every tile in a build)
# ---------------------------------------------------------------------------

def deck_heights(hf, poly, kind: str, water=None, level: float = RIVER_LEVEL) -> tuple[float, float]:
    """Top and bottom of one pier, groyne or platform deck on its own.

    A jetty is level with the shore where it leaves the land: the ground on
    the deck's dry side within LANDING of the water (`water`, the union of
    water areas). Not the highest ground it touches, which can be metres up
    the bank or a mound the DEM keeps."""
    ring = np.asarray(poly.exterior.coords)
    gh = hf.sample(ring[:, 0], ring[:, 1])
    if kind in ("pier", "groyne"):
        floor = level + (JETTY_ABOVE if kind == "pier" else 1.6)
        bottom = min(float(np.min(gh)), level) - 1.0
        if kind == "groyne":
            return max(float(np.median(gh)) + 0.6, floor), bottom
        pts = _deck_samples(poly)
        h = hf.sample(pts[:, 0], pts[:, 1])
        if water is not None and not water.is_empty:
            dry = ~shapely.contains_xy(water, pts[:, 0], pts[:, 1])
            landing = dry & shapely.dwithin(water, shapely.points(pts), LANDING)
        else:
            dry = landing = np.ones(len(pts), bool)
        if landing.any():
            land = float(np.median(h[landing]))
        elif dry.any():
            land = float(np.median(h[dry]))
        else:
            land = -np.inf
        return max(land, floor), bottom
    return float(np.median(gh)) + 0.9, float(np.min(gh)) - 0.3


def _deck_samples(poly, spacing: float = 1.5) -> np.ndarray:
    """Points round a deck's edge and across it."""
    r = poly.exterior
    edge = [r.interpolate(t).coords[0] for t in np.arange(0.0, r.length, spacing)]
    b = poly.bounds
    E, N = np.meshgrid(np.arange(b[0], b[2], spacing * 2), np.arange(b[1], b[3], spacing * 2))
    E, N = E.ravel(), N.ravel()
    inside = shapely.contains_xy(poly, E, N)
    return np.concatenate([np.asarray(edge, float).reshape(-1, 2), np.c_[E[inside], N[inside]]])


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
        pairs = _carriageway_pairs(src_ways)
        node_h = compute_node_heights(src_ways, self.bare, pairs)
        wide = _median_pairs(src_ways, node_h.get("road", {}))
        if wide:
            roads = [w for w in src_ways if way_group(w.tags) == "road"]
            node_h["road"] = compute_node_heights(roads, self.bare, pairs, tie=wide)["road"]
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
        self._lift_stacked()
        self.doubled_paths = streets.doubled_footways(self.ways)

        self.water: list[WaterBody] = []
        self.cover: list[tuple[str, int, object]] = []
        self.rail_land = []    # landuse=railway areas, for _cutting_guards
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
            if t.get("landuse") == "railway":
                self.rail_land.append(a.geom)
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
        self._land_lifts()
        self._cut_under_lifts()
        self._seat_boardwalks()
        self._land_footbridges()
        self.deck_parts = self._level_decks()
        print(f"  world prepared in {time.time() - t0:.1f}s: {len(self.ways)} ways, "
              f"{len(self.buildings)} buildings, {len(self.water)} water bodies")

    # -- preparation helpers --
    def _seat_boardwalks(self):
        """Boardwalks run just over the reeds and the water. Their profiles
        come from the bare DEM, but the ground under them is fitted and the
        lake beds sculpted afterwards, which left decks metres up on piers.
        Each point sits BOARDWALK_DECK over the ground or the water under it,
        whichever is higher."""
        hf = self.hf
        for w in self.ways:
            if w.group != "foot" or w.tags.get("bridge") != "boardwalk" or len(w.xy) < 2:
                continue
            top = np.asarray(hf.sample(w.xy[:, 0], w.xy[:, 1]), dtype=float)
            line = shapely.LineString(w.xy)
            for wb in self.water:
                if wb.geom.intersects(line):
                    wet = shapely.contains_xy(wb.geom, w.xy[:, 0], w.xy[:, 1])
                    top[wet] = np.maximum(top[wet], wb.level)
            w.h = top + BOARDWALK_DECK

    def _land_footbridges(self):
        """Footbridges and boardwalks come up to meet the ground where they
        land. Their profiles are taken from the DEM before the ground is fitted
        to the streets, and where that raised the ground the deck's end was
        left under it: a hole you drop through onto a deck you can't climb
        off. A free end (not joined to another bridge) that is below the
        ground lifts to it, and the lift eases out along the deck."""
        hf = self.hf
        ends: dict[int, int] = {}
        for w in self.ways:
            if w.grade_separated and len(w.nodes) > 1:
                for n in (int(w.nodes[0]), int(w.nodes[-1])):
                    ends[n] = ends.get(n, 0) + 1
        for w in self.ways:
            if w.group != "foot" or not w.bridge or len(w.xy) < 2:
                continue
            lift = []
            for k in (0, -1):
                g = float(hf.sample(w.xy[k, 0], w.xy[k, 1]))
                free = ends.get(int(w.nodes[k]), 0) <= 1
                lift.append(max(g - float(w.h[k]), 0.0) if free else 0.0)
            if max(lift) <= 0.0:
                continue
            s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.xy, axis=0), axis=1))])
            t = s / max(s[-1], 1e-6)
            w.h = w.h + lift[0] * (1.0 - t) + lift[1] * t

    def _level_decks(self) -> list[Deck]:
        """Every deck polygon with its heights.

        Jetties that touch share one top, the highest of theirs, so the
        fingers off a walkway are level with it and a walkway is level with
        the quay it leaves (and you can walk back up off any of them). Off a
        bank high over the water, they ramp down to JETTY_ABOVE over it (Mends
        St's bank is 4.8 m up, the real jetty about a metre over the river).
        Groynes keep their own: a mole's rocks run along the water."""
        water = self.water_union
        shapely.prepare(water)
        parts = []
        for g, kind, oid in self.decks:
            for p in polygons_of(g):
                if p.area < 1.0:
                    continue
                # The lowest water it stands in: a harbour drawn over the sea
                # can take a level off the DEM a metre above it.
                level = min((wb.level for wb in self.water if wb.big and wb.geom.intersects(p)), default=RIVER_LEVEL)
                top, bottom = deck_heights(self.hf, p, kind, water, level)
                parts.append([p, kind, oid, top, bottom, level])
        jetty = [k for k, d in enumerate(parts) if d[1] == "pier"]
        # A street or path that leads onto a jetty from the land meets it at
        # its own height: the deck comes up (or down) to a street, or you step
        # down onto the jetty and can't step back up, or a car meets a kerb.
        # Footpaths only lift it: they are drawn on the ground (their profiles
        # are the bare DEM's and can be metres off it), which comes to the
        # deck anyway. Touching means the path's edge, not its middle line,
        # within PATH_TOUCH.
        touch = {k: np.zeros((0, 2)) for k in jetty}
        legs = []
        for w in self.ways:
            if w.group not in ("foot", "road") or w.grade_separated or len(w.xy) < 2:
                continue
            xy, h = densify(w.xy, w.h, 2.0)
            if w.group == "foot":
                h = self.hf.sample(xy[:, 0], xy[:, 1])
            half = w.width / 2 + (styles.SIDEWALK_WIDTH if w.sidewalk else 0.0)
            legs.append((xy, h, np.full(len(xy), half + PATH_TOUCH), np.full(len(xy), w.group == "road")))
        if legs and jetty:
            xy, hh, rad, road = (np.concatenate(c) for c in zip(*legs))
            dry = ~shapely.contains_xy(water, xy[:, 0], xy[:, 1])
            xy, hh, rad, road = xy[dry], hh[dry], rad[dry], road[dry]
            pts = shapely.points(xy)
            tree = shapely.STRtree(pts)
            for k in jetty:
                near = tree.query(parts[k][0], predicate="dwithin", distance=float(rad.max()) if len(rad) else 0.0)
                near = near[shapely.distance(parts[k][0], pts[near]) <= rad[near]]
                if not len(near):
                    continue
                streets = near[road[near]]
                if len(streets):
                    parts[k][3] = float(np.max(hh[streets])) - 0.05
                foot = near[~road[near]]
                if len(foot):
                    parts[k][3] = max(parts[k][3], float(np.max(hh[foot])) - 0.05)
                touch[k] = xy[near]
        tree = shapely.STRtree([parts[k][0] for k in jetty])
        group = list(range(len(jetty)))

        def root(a):
            while group[a] != a:
                group[a] = group[group[a]]
                a = group[a]
            return a

        for a, k in enumerate(jetty):
            for b in tree.query(parts[k][0], predicate="dwithin", distance=0.5):
                group[root(a)] = root(int(b))
        top, low, land = {}, {}, {}
        for a, k in enumerate(jetty):
            p, r = parts[k][0], root(a)
            top[r] = max(top.get(r, -np.inf), parts[k][3])
            low[r] = max(low.get(r, -np.inf), parts[k][5] + JETTY_ABOVE)
            land.setdefault(r, []).extend([p.difference(water) if not water.is_empty else p,
                                           shapely.multipoints(touch[k]) if len(touch[k]) else Polygon()])
        decks = []
        at = {k: a for a, k in enumerate(jetty)}
        for k, d in enumerate(parts):
            deck = Deck(*d[:5])
            if d[1] == "pier":
                r = root(at[k])
                deck.top = top[r]
                landing = shapely.union_all(land[r])
                if not landing.is_empty and 0.3 < top[r] - low[r] <= JETTY_DROP:
                    deck.low, deck.landing = low[r], landing
            decks.append(deck)
        self._seat_jetties([d for d in decks if d.kind in ("pier", "groyne")])
        return decks

    def _seat_jetties(self, decks: list[Deck]):
        """Ground meets jetties where they leave the shore, level with their
        decks, so you walk on and off instead of dropping down or climbing up
        a wall. (Deepening the water round them, so a fall off the side put
        you back on the bank, cut off more shallows than it rescued.)

        Within JETTY_PAD of a deck near the water the ground takes the deck's
        height (where a ramp comes down beside a bank, the ramp's). Past that
        the change eases out smoothly (a harmonic blend of it, the way a sheet
        hangs, keeping the lie of the land under it): out to JETTY_RAMP or
        further, so it stays under SEAT_GRADE, held at the streets round it
        and left to run along the water's edge, with the river bed left as
        it is. All jetties in one blend: one at a time, each blending to its
        own deck, left towers, pits and steps where two met or where a blend
        was cut off short."""
        from scipy.ndimage import binary_closing, binary_dilation, label
        from scipy.sparse import coo_matrix, diags
        from scipy.sparse.linalg import spsolve
        hf = self.hf
        H = hf.H
        es, ns = hf.node_coords()
        water = self.water_union
        core = getattr(self, "road_core", np.zeros(H.shape, bool))
        want = np.full(H.shape, np.nan)   # the pad: the height each node takes...
        near = np.full(H.shape, np.inf)   # ...from its nearest deck
        floor = np.full(H.shape, np.inf)  # river bed lower than this is left alone
        reach = np.zeros(H.shape, bool)   # nodes the blend may move
        clash = np.zeros(H.shape, bool)   # pad nodes two decks at different heights both claim
        bank = water.boundary  # the river's banks
        filled = np.zeros(H.shape, bool)  # river filled up to a deck (its rise isn't spread round it)
        for deck in decks:
            b = deck.poly.bounds
            i0, i1 = np.searchsorted(es, [b[0] - JETTY_PAD, b[2] + JETTY_PAD])
            j0, j1 = np.searchsorted(ns, [b[1] - JETTY_PAD, b[3] + JETTY_PAD])
            if i1 <= i0 or j1 <= j0:
                continue
            E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
            pts = shapely.points(E, N)
            d = shapely.distance(deck.poly, pts)
            # The deck's height at its nearest point (past the land end of a
            # ramped one, its top, not the ramp carried on down).
            at = shapely.get_coordinates(shapely.get_point(shapely.shortest_line(deck.poly, pts.ravel()), 0))
            top = deck.heights(at[:, 0], at[:, 1]).reshape(E.shape) - 0.05
            sub = H[j0:j1, i0:i1]
            wet = shapely.contains_xy(water, E, N)
            # Inside the water's outline the DEM can keep the bank standing
            # higher than the deck (Mends St): that comes down to it too.
            low = wet & (sub <= top) & (d < JETTY_PAD)
            # Under the deck, beside ground up at its height.
            solid = (np.abs(sub - top) < SHORE_LEVEL) & (d < JETTY_PAD)
            fill = low & (d < 0.5) & binary_dilation(solid, np.ones((3, 3), bool))
            # Beside the deck, with the bank the other way.
            gap = low & (d >= 0.5)
            if gap.any():
                g = pts[gap]
                to_bank = shapely.get_coordinates(shapely.get_point(shapely.shortest_line(g, bank), 1))
                to_deck = at.reshape(E.shape + (2,))[gap]
                me = np.stack([E[gap], N[gap]], axis=1)
                u, v = to_deck - me, to_bank - me
                lu, lv = np.linalg.norm(u, axis=1), np.linalg.norm(v, axis=1)
                cos = (u * v).sum(axis=1) / np.maximum(lu * lv, 1e-9)
                # (the ground just up the bank, past the slope down to the water)
                up = to_bank + v / np.maximum(lv, 1e-9)[:, None] * SHORE_UP
                level = np.abs(hf.sample(up[:, 0], up[:, 1]) - top[gap]) < SHORE_LEVEL
                fill[gap] = (lu + lv < SHORE_FILL) & (cos < -0.5) & level
            # A quay's strip, not a corner at a jetty's root.
            lab, _ = label(fill, np.ones((3, 3), bool))
            fill &= (np.bincount(lab.ravel()) >= SHORE_RUN)[lab] & (lab > 0)
            # No single river node left deep between filled ones: a deck along
            # the shore filled the nodes under its edge every other one, and
            # the pits between were holes in the shallows you couldn't climb
            # out of (Fremantle).
            fill |= binary_closing(fill, np.ones((3, 3), bool)) & low
            filled[j0:j1, i0:i1] |= fill
            pad = (d < JETTY_PAD) & (~wet | (sub > top) | fill) & ~core[j0:j1, i0:i1]
            if deck.kind != "pier":
                pad &= shapely.dwithin(water, pts, LANDING + JETTY_RAMP)
            # (A jetty's deck meets the ground all along its dry sides, not
            # only at the shore: a boardwalk or a quay's promenade on grass
            # that fell away from it left a 0.4-0.5 m ledge, Fremantle,
            # Elizabeth Quay.)
            if not pad.any():
                continue
            mine = pad & (d < near[j0:j1, i0:i1])
            nd, wd = near[j0:j1, i0:i1], want[j0:j1, i0:i1]
            # A node two decks at different heights both reach: the nearer one
            # (and where it's well clear of that one too, the ground between
            # them just eases from one to the other, no step where they meet).
            other = pad & ~mine & np.isfinite(wd)
            mine2 = mine & np.isfinite(wd)
            clash[j0:j1, i0:i1] |= (other & (np.abs(wd - top) > 0.25) & (nd > 1.0)) \
                | (mine2 & (np.abs(wd - top) > 0.25) & (d > 1.0))
            wd[mine] = top[mine]
            nd[mine] = d[mine]
            lowest = deck.low if deck.low is not None else deck.top
            # Wide enough to keep the blend gentle.
            run = min(max(JETTY_RAMP, float(np.abs(top[pad] - sub[pad]).max()) / SEAT_GRADE), SEAT_REACH)
            r = JETTY_PAD + run
            i0, i1 = np.searchsorted(es, [b[0] - r, b[2] + r])
            j0, j1 = np.searchsorted(ns, [b[1] - r, b[3] + r])
            E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
            inside = shapely.dwithin(deck.poly, shapely.points(E, N), r)
            reach[j0:j1, i0:i1] |= inside
            fl = floor[j0:j1, i0:i1]
            fl[inside] = np.minimum(fl[inside], lowest - 0.05)
        pad = np.isfinite(want) & ~clash
        if not pad.any():
            return
        wet = np.zeros(H.shape, bool)
        js, is_ = np.nonzero(reach)
        wet[js, is_] = shapely.contains_xy(water, es[is_], ns[js])
        bed = reach & wet & (H < floor) & ~pad          # left as it is, and not pulled on
        free = reach & ~pad & ~core & ~bed
        delta = np.where(pad, want - H, 0.0)
        idx = -np.ones(H.shape, dtype=np.int64)
        fj, fi = np.nonzero(free)
        idx[fj, fi] = np.arange(len(fj))
        n = len(fj)
        if n:
            rows, cols, vals = [], [], []
            rhs = np.zeros(n)
            diag = np.full(n, 1e-6)
            nj, ni = H.shape
            for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                j2, i2 = fj + dj, fi + di
                ok = (j2 >= 0) & (j2 < nj) & (i2 >= 0) & (i2 < ni)
                j2c, i2c = np.clip(j2, 0, nj - 1), np.clip(i2, 0, ni - 1)
                ok &= ~(bed | filled)[j2c, i2c]
                diag += ok
                other = idx[j2c, i2c]
                link = ok & (other >= 0)
                rows.append(np.nonzero(link)[0])
                cols.append(other[link])
                vals.append(-np.ones(int(link.sum())))
                fixed = ok & (other < 0)
                rhs[fixed] += delta[j2c[fixed], i2c[fixed]]
            A = coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)).tocsr()
            A = A + diags(diag, format="csr")
            delta[fj, fi] = spsolve(A.tocsc(), rhs)
        H += delta
        # No river node left as a pit with the ground up round three sides
        # of it: a deck along the shore had the nodes under its edge filled
        # every other one, and the holes between were in the shallows, with
        # no way to climb out (Fremantle's quays).
        pit = reach & wet & ~pad
        for _ in range(2):
            nb = np.stack([np.roll(H, 1, 0), np.roll(H, -1, 0), np.roll(H, 1, 1), np.roll(H, -1, 1)])
            up = (nb > H + SHORE_PIT) & (nb < H + SHORE_PIT_MAX)
            sink = pit & (up.sum(axis=0) >= 3)
            if not sink.any():
                break
            H[sink] = np.nanmin(np.where(up, nb, np.nan)[:, sink], axis=0)

    def deck_top(self, oid) -> float:
        """The deck height of a jetty or platform where it leaves the land (its largest piece)."""
        return max((d for d in self.deck_parts if d.oid == oid), key=lambda d: d.poly.area).top

    def deck_height(self, oid, e, n) -> float:
        """The deck height of a jetty or platform at (e, n), on its piece nearest there."""
        pt = Point(e, n)
        d = min((d for d in self.deck_parts if d.oid == oid), key=lambda d: d.poly.distance(pt))
        return float(d.heights(e, n))

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

    def _lift_stacked(self):
        """Mark the nodes of at-grade roads (and railways) that run over or
        close beside another at-grade road (or railway) a metre or more
        below them (`LinearWay.lift`). OSM often tags only the main deck as a
        bridge: a slip road leaving it, or a ramp climbing beside the
        freeway, is drawn on the ground, and one ground fitted under both
        roads made a wall or a slope across the lower one. Those stretches
        are drawn on decks instead, walled down to the ground, and the
        ground keeps to the lower road."""
        from scipy.spatial import cKDTree
        ground = [w for w in self.ways if w.group in ("road", "rail") and not w.grade_separated and len(w.xy) > 1]
        if len(ground) < 2:
            return
        walled = np.array([w.group == "rail" or w.tags.get("highway") in WALLED for w in ground])
        pts, ph, half, owner = [], [], [], []
        for i, w in enumerate(ground):
            xy, h = densify(w.xy, w.h, 2.0)
            pts.append(xy)
            ph.append(h)
            half.append(np.full(len(xy), w.width / 2 if w.group == "road" else STACK_RAIL_HALF))
            owner.append(np.full(len(xy), i))
        pts, ph, half, owner = (np.concatenate(v) for v in (pts, ph, half, owner))
        tree = cKDTree(pts)
        reach = float(half.max()) + STACK_WIDE
        where = {}  # node id -> (x, y), for the nodes roads share
        for w in ground:
            for nid, p in zip(w.nodes, w.xy):
                where[int(nid)] = p
        node_sets = [set(int(n) for n in w.nodes) for w in ground]
        is_rail = np.array([w.group == "rail" for w in ground])
        for i, w in enumerate(ground):
            lift = np.zeros(len(w.xy), dtype=bool)
            shared = {}
            wide = walled[i]
            for k, near in enumerate(tree.query_ball_point(w.xy, w.width / 2 + reach)):
                if not near:
                    continue
                near = np.asarray(near)
                near = near[owner[near] != i]
                for j in np.unique(owner[near]):
                    if j not in shared:
                        shared[j] = node_sets[i] & node_sets[j]
                    for nid in shared[j]:
                        p = where[nid]
                        if np.linalg.norm(w.xy[k] - p) < STACK_JUNCTION:
                            near = near[(owner[near] != j) | (np.linalg.norm(pts[near] - p, axis=1) >= STACK_JUNCTION)]
                dh = w.h[k] - ph[near]
                d = np.linalg.norm(pts[near] - w.xy[k], axis=1)
                # (Tracks side by side only when they overlap: a rail yard's aren't all level.)
                room = np.where((wide | walled[owner[near]]) & ~(is_rail[i] & is_rail[owner[near]]),
                                STACK_WIDE, STACK_MARGIN)
                lift[k] = bool(((dh > LIFT) & (d < w.width / 2 + half[near] + room)).any())
            if lift.any():
                w.lift = _close_gaps(w, lift)

    def edge_closures(self, map_tiles: set[str]) -> list[dict]:
        """Where each road leaves the built map (`map_tiles`, tile names):
        a closure EDGE_INSET back from the edge, on the map. Each is a dict
        with the way's id, the distance `s` along it, the point `xy`, height
        `h` and `out` (the way's direction there, pointing off the map), and
        the road's `half` width out to its sidewalks."""
        size = self.tile_size

        def on(p):
            return f"{int(np.floor(p[0] / size))}_{int(np.floor(p[1] / size))}" in map_tiles

        out = []
        for w in self.ways:
            if w.group != "road" or len(w.xy) < 2:
                continue
            xy, h = densify(w.xy, w.h, 2.0)
            s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(xy, axis=0), axis=1))])
            inside = np.array([on(p) for p in xy])
            for k in np.nonzero(inside[:-1] != inside[1:])[0]:
                sign = 1.0 if inside[k] else -1.0  # +1: going on along the way leaves the map
                sb = (s[k] + s[k + 1]) / 2 - sign * EDGE_INSET
                if not 0.0 <= sb <= s[-1]:
                    continue
                p = np.array([np.interp(sb, s, xy[:, 0]), np.interp(sb, s, xy[:, 1])])
                if not on(p):
                    continue
                a, b = np.interp([sb - 1.0, sb + 1.0], s, xy[:, 0]), np.interp([sb - 1.0, sb + 1.0], s, xy[:, 1])
                d = np.array([a[1] - a[0], b[1] - b[0]])
                d = sign * d / max(float(np.linalg.norm(d)), 1e-9)
                out.append({"way": w.id, "s": float(sb), "sign": sign, "xy": p, "h": float(np.interp(sb, s, h)),
                            "out": d, "grade_separated": w.grade_separated,
                            "half": w.width / 2 + (styles.SIDEWALK_WIDTH if w.sidewalk else 0.6)})
        return out

    def _land_lifts(self):
        """A lifted stretch's deck carries on along its road until the ground
        under the road has come up (or down) to meet it: where the stacked
        roads part, the ground between them is still a blend of the two, and
        a deck ending there left a step."""
        hf = self.hf
        for w in self.ways:
            if w.lift is None:
                continue
            gap = np.abs(w.h - hf.sample(w.xy[:, 0], w.xy[:, 1])) > LIFT_LAND
            s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.xy, axis=0), axis=1))])
            lift = w.lift.copy()
            for a, b in _runs(w.lift):
                # The deck ends at the nodes either side of the run; move each
                # end on while the road there is off the ground.
                k = a - 1
                while k > 0 and gap[k] and s[a] - s[k] < LIFT_REACH:
                    lift[k] = True
                    k -= 1
                k = b
                while k < len(lift) - 1 and gap[k] and s[k] - s[b - 1] < LIFT_REACH:
                    lift[k] = True
                    k += 1
            w.lift = _close_gaps(w, lift)

    def _cut_under_lifts(self):
        """The ground comes down under a lifted stretch's deck, and slopes
        back up from its edges, wherever it was higher: the ground there is
        fitted to the road below, and on the deck's other side it could be
        higher than the deck (a freeway beside the railway in its median, in
        a cutting), coming up through it. Roads' own ground stays put."""
        from scipy.spatial import cKDTree
        hf = self.hf
        H = hf.H
        es, ns = hf.node_coords()
        core = getattr(self, "road_core", np.zeros(H.shape, bool))
        near = np.zeros(H.shape, np.int8)  # walled or low decks a node is beside
        wnear = np.zeros(H.shape, np.int8)  # (walled ones)
        close = np.zeros(H.shape, np.int8)  # walled decks a node is at the very edge of
        level0 = np.full(H.shape, np.inf, np.float32)  # and the lowest of them
        level = np.full(H.shape, np.inf, np.float32)  # and the lowest of them
        roof = np.full(H.shape, np.inf, np.float32)  # under an open deck: room under it
        towers = shapely.STRtree([b.geom for b in self.buildings]) if getattr(self, "buildings", None) else None
        way = np.zeros(H.shape + (2,), np.float32)  # which way the first of them is
        run = np.zeros(H.shape + (2,), np.float32)  # and which way it runs
        across = np.zeros(H.shape, bool)  # and another the other way: between them
        under1 = np.zeros(H.shape, bool)  # (or one of them over it)
        for w in self.ways:
            if w.lift is None:
                continue
            for p in w.pieces():
                if not p.bridge or len(p.xy) < 2:
                    continue
                xy, h = densify(p.xy, p.h, 2.0)
                half = p.width / 2
                b = (xy[:, 0].min() - half - LIFT_CUT, xy[:, 1].min() - half - LIFT_CUT,
                     xy[:, 0].max() + half + LIFT_CUT, xy[:, 1].max() + half + LIFT_CUT)
                i0, i1 = np.searchsorted(es, [b[0], b[2]])
                j0, j1 = np.searchsorted(ns, [b[1], b[3]])
                if i1 <= i0 or j1 <= j0:
                    continue
                E, N = np.meshgrid(es[i0:i1], ns[j0:j1])
                d, k = cKDTree(xy).query(np.column_stack([E.ravel(), N.ravel()]))
                d = d.reshape(E.shape)
                # (Level for a ground cell past its edge first: a node any
                # higher there tilts the cell up through the deck's side.)
                cap = h[k].reshape(E.shape) - LIFT_UNDER + np.maximum(d - half - hf.step, 0.0) * LIFT_BANK
                sub = H[j0:j1, i0:i1]
                # (Under the deck itself, even another road's ground; but not
                # where it lands, or the road on from it would start in a dip.)
                inner = ((k >= LIFT_END) & (k < len(xy) - LIFT_END)).reshape(E.shape)
                cut = inner & (~core[j0:j1, i0:i1] | (d < half + hf.step)) & (sub > cap)
                # Where a side is walled down to the ground (see _bridges), the
                # ground under the deck comes up to its underside: a walled
                # deck with room to stand under it is a box you can drop into
                # where the wall stops and never climb out of.
                if not styles.is_bridge(w.tags):
                    t = np.gradient(xy, axis=0)
                    nrm = np.column_stack([-t[:, 1], t[:, 0]]) / np.maximum(
                        np.linalg.norm(t, axis=1), 1e-9)[:, None] * half
                    gl, gr = hf.sample(*(xy + nrm).T), hf.sample(*(xy - nrm).T)
                    edge = np.minimum(gl, gr)
                    walled = (h - edge < LIFT_WALL_CLEAR)[k].reshape(E.shape)
                    under = h[k].reshape(E.shape) - DECK_THICKNESS
                    fill = inner & walled & (d < half) & ~core[j0:j1, i0:i1] & (sub < under)
                    sub[fill] = under[fill]
                    edge = inner & walled & (d < half + hf.step) & ~core[j0:j1, i0:i1]
                    close[j0:j1, i0:i1] += edge
                    l0 = level0[j0:j1, i0:i1]
                    l0[edge] = np.minimum(l0[edge], cap[edge])
                    # (Each deck by its side facing the node.)
                    to = (xy[k] - np.column_stack([E.ravel(), N.ravel()])).reshape(E.shape + (2,))
                    left = (nrm[k].reshape(E.shape + (2,)) * to).sum(axis=-1) < 0
                    clear = h[k].reshape(E.shape) - np.where(left, gl[k].reshape(E.shape), gr[k].reshape(E.shape))
                    walled = clear < LIFT_WALL_CLEAR
                    # A building standing close beside a walled side leaves a
                    # crevice you drop into off the deck and can't climb out
                    # of (the Esplanade, by the office tower): the ground there,
                    # and under the deck beside it, comes up level with the deck.
                    level_k = h[k].reshape(E.shape) - LIFT_UNDER
                    gap = inner & (clear < SLOT_OPEN) & (d < half + LIFT_CREVICE) & ~core[j0:j1, i0:i1] & (sub < level_k) \
                        & (sub > level_k - LIFT_CREVICE_DEPTH)
                    if gap.any() and towers is not None:
                        # (Within LIFT_CREVICE of the deck's edge.)
                        q = shapely.points(E[gap], N[gap])
                        qi, bi = towers.query(q, predicate="dwithin", distance=hf.step)
                        reach = (half + LIFT_CREVICE - d[gap])[qi]
                        hit = np.zeros(len(q), bool)
                        hit[qi[shapely.distance(q[qi], towers.geometries[bi]) <= reach]] = True
                        gap[gap] = hit
                        sub[gap] = level_k[gap]
                    ends = (k >= SLOT_ENDS) & (k < len(xy) - SLOT_ENDS)
                    side = (d < half + SLOT_REACH) & ~core[j0:j1, i0:i1] & (clear < SLOT_OPEN) & ends.reshape(E.shape)
                    to /= np.maximum(np.linalg.norm(to, axis=-1), 1e-9)[..., None]
                    wy = way[j0:j1, i0:i1]
                    first = side & (near[j0:j1, i0:i1] == 0)
                    over = d < half
                    tk = (t[k] / np.maximum(np.linalg.norm(t[k], axis=1), 1e-9)[:, None]).reshape(E.shape + (2,))
                    ru = run[j0:j1, i0:i1]
                    along = np.abs((ru * tk).sum(axis=-1)) > SLOT_ALONG
                    across[j0:j1, i0:i1] |= side & ~first & along & (((wy * to).sum(axis=-1) < -0.5) | over
                                                                     | under1[j0:j1, i0:i1])
                    wy[first] = to[first]
                    ru[first] = tk[first]
                    u1 = under1[j0:j1, i0:i1]
                    u1[first] = over[first]
                    near[j0:j1, i0:i1] += side
                    wnear[j0:j1, i0:i1] += side & walled
                    lv = level[j0:j1, i0:i1]
                    top = h[k].reshape(E.shape) - LIFT_UNDER
                    lv[side] = np.minimum(lv[side], top[side])
                    rf = roof[j0:j1, i0:i1]
                    op = side & ~walled & (d < half + 0.5)
                    rf[op] = np.minimum(rf[op], under[op] - 0.3)
                sub[cut] = cap[cut]
        # Between two decks side by side (a dual carriageway, a ramp beside the
        # freeway), one of them walled, the ground comes up level with the
        # lower: the strip between them is a slot you'd drop into and never
        # climb out of (SLOT_REACH). Not into an open deck's underside.
        slot = (close >= 2) & (H < level0)
        H[slot] = level0[slot]
        level = np.minimum(level, roof)
        slot = across & (wnear >= 1) & (H < level) & (H > level - LIFT_WALL_CLEAR)
        H[slot] = level[slot]

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
        best, target, fall, best2, target2, fall2 = self._road_corridors(HeightField(hf.e0, hf.n0, s, ref))
        core = best <= CORE_MARGIN
        self.road_core = core
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
        fall2 = np.maximum(fall2, 2.0 * np.abs(target2 - ground) + 3.0)
        ramp = ~core & (best < CORE_MARGIN + fall)
        t = np.where(ramp, _smoothstep((best - CORE_MARGIN) / fall), 1.0)
        out = ground.copy()
        out[ramp] = target[ramp] + t[ramp] * (ground[ramp] - target[ramp])
        # Between two roads (a median, the corner of a junction, a street
        # beside an embankment) each one's side slope is weighed by how near
        # it is, so the ground passes smoothly from one to the other instead
        # of stepping where the nearer one changes over (0.4-0.9 m ridges
        # beside Pearson St's carriageways).
        two = ramp & np.isfinite(best2) & (best2 < CORE_MARGIN + fall2)
        if two.any():
            t2 = _smoothstep((best2[two] - CORE_MARGIN) / fall2[two])
            out2 = target2[two] + t2 * (ground[two] - target2[two])
            w1 = 1.0 / (best[two] - CORE_MARGIN + 0.5) ** 2
            w2 = 1.0 / (best2[two] - CORE_MARGIN + 0.5) ** 2
            out[two] = (w1 * out[two] + w2 * out2) / (w1 + w2)
        out[core] = target[core]
        hf.H[:] = out

    def _road_corridors(self, ref: HeightField):
        """For every grid node near a road or railway: how far it is outside
        the paved width of the nearest one (`best`, metres, <= 0 inside), the
        height of that road's centre line at the nearest point (`target`) and
        how wide its side slopes are (`fall`); and the same for the next
        nearest (`best2`, `target2`, `fall2`)."""
        hf = ref
        H = ref.H
        es, ns = hf.node_coords()
        s = hf.step
        best = np.full(H.shape, np.inf)
        target = np.zeros(H.shape)
        best2 = np.full(H.shape, np.inf)
        target2 = np.zeros(H.shape)
        fall = np.full(H.shape, EDGE_BLEND)
        fall2 = np.full(H.shape, EDGE_BLEND)
        owner = np.full(H.shape, -1)       # which run each of those is (a road's
        owner2 = np.full(H.shape, -1)      # own next stretch isn't another road)
        runs = [(w, xy, h) for w in self.ways if w.group != "foot" for xy, h in w.ground_runs()]
        for ri, (w, wxy, wh) in enumerate(runs):
            if len(wxy) < 2:
                continue
            hw = w.width / 2 + (styles.SIDEWALK_WIDTH if w.sidewalk else 0.6)
            dh_all = np.abs(wh - hf.sample(wxy[:, 0], wxy[:, 1]))
            for k0 in range(0, len(wxy) - 1, CHUNK):
                k1 = min(k0 + CHUNK, len(wxy) - 1)
                A = wxy[k0:k1]
                B = wxy[k0 + 1:k1 + 1]
                ha, hb = wh[k0:k1], wh[k0 + 1:k1 + 1]
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
                sf, sf2 = fall[j0:j1, i0:i1], fall2[j0:j1, i0:i1]
                so, so2 = owner[j0:j1, i0:i1], owner2[j0:j1, i0:i1]
                upd = score < sb
                same = so == ri
                second = ~upd & ~same & (score < sb2)
                shift = upd & ~same
                if shift.any():
                    sb2[shift] = sb[shift]
                    st2[shift] = st[shift]
                    sf2[shift] = sf[shift]
                    so2[shift] = so[shift]
                if upd.any():
                    sb[upd] = score[upd]
                    st[upd] = hh[upd] - 0.02
                    sf[upd] = fl
                    so[upd] = ri
                if second.any():
                    sb2[second] = score[second]
                    st2[second] = hh[second] - 0.02
                    sf2[second] = fl
                    so2[second] = ri
        # Where two roads overlap (slip roads merging, a street passing an
        # embankment) and their heights differ, ease between them instead of
        # leaving a step where the nearer one takes over.
        both = best2 <= CORE_MARGIN
        gap = np.where(both, best2 - np.minimum(best, CORE_MARGIN), OVERLAP_BLEND)
        w2 = np.where(both, 0.5 * (1.0 - _smoothstep(gap / OVERLAP_BLEND)), 0.0)
        target = target + w2 * (np.where(both, target2, target) - target)
        return best, target, fall, best2, target2, fall2

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
MEDIAN = 8.0     # the halves of a divided street this far apart past their kerbs are still one road...
WIDE_APART = ("motorway", "motorway_link", "trunk", "trunk_link")  # ...but not a freeway's or highway's


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


def _close_gaps(w, lift):
    """`lift` with the gaps shorter than LIFT_GAP between lifted stretches
    of `w` lifted too: a string of short decks, each landing on a scrap of
    ground, made a bump at every end."""
    lift = lift.copy()
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.xy, axis=0), axis=1))])
    for a, b in _runs(~lift):
        if a > 0 and b < len(lift) and s[b] - s[a - 1] < LIFT_GAP:
            lift[a:b] = True
    return lift


def _runs(mask):
    """(start, stop) of each run of True in `mask`."""
    d = np.diff(np.concatenate([[0], mask.astype(np.int8), [0]]))
    return list(zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]))


def _cutting_fence(ring, hf, open_):
    """(position, direction, base) of each barrier along the top of the bank
    where the ground on the left of `ring` falls away (CUT_DROP), leaving out
    any that would stand in `open_` (a road or path leading in)."""
    step = BARRIER_LEN + BARRIER_GAP
    xy, _s = _resample(ring, step)
    if len(xy) > 1 and np.allclose(xy[0], xy[-1]):
        xy = xy[:-1]
    if len(xy) < CUT_MIN:
        return []
    t = np.gradient(xy, axis=0)
    t /= np.maximum(np.linalg.norm(t, axis=1), 1e-9)[:, None]
    inward = np.column_stack([-t[:, 1], t[:, 0]])

    def ground(d):  # d: one distance per block
        q = xy + inward * d[:, None]
        return hf.sample(q[:, 0], q[:, 1])

    ds = np.arange(0.0, CUT_SEARCH + 0.01, 0.5)
    q = xy[:, None, :] + inward[:, None, :] * ds[None, :, None]
    g = hf.sample(q[..., 0].ravel(), q[..., 1].ravel()).reshape(q.shape[:2])
    steep = g[:, :-6] - g[:, 6:] > CUT_STEEP
    top = np.where(steep.any(axis=1), ds[steep.argmax(axis=1)], np.nan)
    # Steady the line: each block at the middle of its neighbours' tops.
    pad = np.concatenate([top[-2:], top, top[:2]])
    win = np.lib.stride_tricks.sliding_window_view(pad, 5)
    have = ~np.isnan(win).all(axis=1)
    mid = np.full(len(top), np.nan)
    mid[have] = np.nanmedian(win[have], axis=1)
    d = np.where(np.isnan(mid), 0.0, mid)
    on = have & (ground(d) - ground(d + CUT_REACH) > CUT_DROP)
    # Close gaps of a block or two between rows, so the car can't slip through.
    for a, b in _runs(~on):
        if 0 < a and b < len(on) and b - a <= 2:
            on[a:b] = True
    d = np.maximum(d - 0.5, 0.0)
    # Off a street or path along the top, onto the bank past it (a gap there
    # let the car through behind the row); left out only where none is near.
    pos = xy + inward * d[:, None]
    for _ in range(int(CUT_SHIFT / 0.5)):
        inside = shapely.contains_xy(open_, pos[:, 0], pos[:, 1])
        if not inside.any():
            break
        d = np.where(inside, d + 0.5, d)
        pos = xy + inward * d[:, None]
    on &= ~shapely.contains_xy(open_, pos[:, 0], pos[:, 1])
    along = np.gradient(pos, axis=0)
    along /= np.maximum(np.linalg.norm(along, axis=1), 1e-9)[:, None]
    # Standing on the ground on its top side, its foot down to the bank's: a
    # block based on the slope stood only 0.3 m over the street beside it.
    # Where the ground climbs on behind it, its top is as high over the
    # ground a metre back: lower, it was a step up off the slope, and over.
    g = np.stack([hf.sample(q[:, 0], q[:, 1]) for q in
                  (pos - inward, pos - inward * 0.7, pos - inward * 0.35, pos, pos + inward * 0.35)])
    base, foot = g.max(axis=0), g.min(axis=0) - 0.15
    out = []
    for a, b in _runs(on):
        if b - a >= CUT_MIN:
            out.extend((pos[k], along[k], float(base[k]), float(foot[k])) for k in range(a, b))
    return out


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


def _parapet_heights(w, edge, top, hf) -> np.ndarray:
    """How high a bridge's parapet along one edge stands. A road bridge's
    comes down to nothing where its deck is back near the ground on that side
    (under PARAPET_LOW): a parapet's blunt end standing in the road where a
    bridge starts at street level is a wall a car turning onto it gets
    caught on. Each side goes by its own ground: a deck with a bank up to it
    on one side still has a parapet over the drop on the other."""
    if w.group != "road":
        return np.full(len(top), PARAPET_H)
    ground = hf.sample(edge[:, 0], edge[:, 1])
    return PARAPET_H * np.clip((top - ground - PARAPET_LOW) / PARAPET_LOW, 0.0, 1.0)


def _end_heading(w, k: int) -> np.ndarray:
    """Unit direction of `w` leaving its end `k` (0 or -1), pointing out of it."""
    d = w.xy[k] - w.xy[1 if k == 0 else -2]
    return d / max(float(np.linalg.norm(d)), 1e-9)


def _continues(w, o) -> bool:
    """`o` carries straight on from an end of `w` (a bridge split into several
    ways, or its approach): its lanes are `w`'s own, not a road joining."""
    for k in (0, -1):
        for m in (0, -1):
            if int(w.nodes[k]) == int(o.nodes[m]) and len(o.xy) > 1 and \
                    float(_end_heading(w, k) @ -_end_heading(o, m)) > CONTINUE_COS:
                return True
    return False


def _parapet_runs(ph, gap) -> list[slice]:
    """Index ranges of a parapet: each run where it stands, plus the point
    either side where it comes up off the deck (but not into a gap left for
    a joining road)."""
    out = []
    for a, b in _runs(ph > 0.0):
        a = a - 1 if a > 0 and not gap[a - 1] else a
        b = b + 1 if b < len(ph) and not gap[b] else b
        if b - a >= 2:
            out.append(slice(a, b))
    return out


def _bevel(surf, xy, edge, top, hf, joined=None):
    """Where a road bridge leaves the street its deck's side stands a little
    over the ground beside it: a ledge a car running wide snags on (William
    St). Under BEVEL_MAX, the side slopes down to the ground instead, along
    `edge` (one side of the deck, beside centre line `xy`), but not into the
    lanes of a road it joins (`joined`)."""
    out = edge - xy
    out /= np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)
    ledge = top - hf.sample(edge[:, 0], edge[:, 1])
    run = BEVEL_RUN * np.clip(ledge, 0.0, BEVEL_MAX)
    low = (ledge > 0.05) & (ledge < BEVEL_MAX)
    if joined is not None:
        low &= ~joined
    for a, b in _runs(low):
        k = slice(max(a - 1, 0), min(b + 1, len(xy)))  # down to nothing either end
        e, o = edge[k], edge[k] + out[k] * run[k, None]
        if len(e) < 2:
            continue
        ho = np.minimum(hf.sample(o[:, 0], o[:, 1]) + 0.02, top[k])
        v = np.concatenate([np.column_stack([e, top[k]]), np.column_stack([o, ho])])
        n = len(e)
        i = np.arange(n - 1)
        tris = np.concatenate([np.column_stack([i, i + 1, n + i + 1]), np.column_stack([i, n + i + 1, n + i])])
        t = v[tris]
        up = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])[:, 2]
        tris[up < 0] = tris[up < 0][:, ::-1]
        nrm = np.zeros_like(v)
        t = v[tris]
        fn = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        for c in range(3):
            np.add.at(nrm, tris[:, c], fn)
        ln = np.linalg.norm(nrm, axis=1, keepdims=True)
        nrm = np.where(ln > 1e-9, nrm / np.maximum(ln, 1e-9), [0.0, 0.0, 1.0])
        surf.add(v, nrm, v[:, :2] / 2.0, tris)


def _lid(surf, xy, roof, half: float, hf, spacing: float = 1.25):
    """The top of a tunnel's box: its roof, or just under the ground where
    the ground over it is higher. Where the ground is cut away over the roof
    it fills the slot nearly level with the street, and elsewhere it leaves
    no hollow between roof and ground to fall into. Returns the heights
    along its left and right edges."""
    m = int(np.ceil(2 * half / spacing)) + 1
    offs = np.linspace(half, -half, m)  # left to right
    cols = [offset_polyline(xy, d) for d in offs]
    k = len(xy)
    h = np.column_stack([np.maximum(roof, hf.sample(c[:, 0], c[:, 1]) - LID_DROP) for c in cols])
    v = np.empty((k, m, 3))
    for j, c in enumerate(cols):
        v[:, j, :2] = c
    v[:, :, 2] = h
    along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(xy, axis=0), axis=1))])
    uv = np.empty((k, m, 2))
    uv[:, :, 0] = (half - offs)[None, :] / 4.0
    uv[:, :, 1] = along[:, None] / 4.0
    # Normals from the grid's slopes along and across.
    fwd = np.gradient(v, axis=0) if k > 1 else np.zeros_like(v)
    side = np.gradient(v, axis=1)
    nrm = np.cross(fwd, side)
    nrm[nrm[..., 2] < 0] *= -1
    nrm /= np.maximum(np.linalg.norm(nrm, axis=2, keepdims=True), 1e-9)
    idx = np.arange(k * m).reshape(k, m)
    a, b = idx[:-1, 1:].ravel(), idx[:-1, :-1].ravel()   # right, left at station i
    c, d = idx[1:, 1:].ravel(), idx[1:, :-1].ravel()     # right, left at station i + 1
    # CCW from above, as ribbon(): right[i], right[i+1], left[i+1] / right[i], left[i+1], left[i]
    tris = np.concatenate([np.column_stack([a, c, d]), np.column_stack([a, d, b])])
    surf.add(v.reshape(-1, 3), nrm.reshape(-1, 3), uv.reshape(-1, 2), tris)
    return h[:, 0], h[:, -1]


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


def _median_pairs(ways, hmap) -> list[tuple[int, int]]:
    """Nodes of the two halves of a divided street across a wider, planted
    median (up to MEDIAN past their kerbs) whose heights came out between
    MISMATCH and 2 m apart (more is a real level change). Where a short link crosses
    the median between them the gap showed as lumps and steep little ramps
    (Pearson St at Campus Way).
    Freeways and highways keep their own levels: their halves part at
    interchanges."""
    from scipy.spatial import cKDTree
    by_name: dict[str, list] = {}
    for w in ways:
        t = w.tags
        if way_group(t) == "road" and t.get("oneway") in ("yes", "-1") and t.get("name") \
                and t.get("highway") not in WIDE_APART and not styles.is_bridge(t) \
                and not styles.is_tunnel(t) and len(w.coords) > 1:
            by_name.setdefault(t["name"], []).append(w)
    pairs = []
    for group in by_name.values():
        if len(group) < 2:
            continue
        for wa in group:
            others = [w for w in group if w is not wa]
            xy = np.concatenate([w.coords for w in others])
            ids = np.concatenate([w.nodes for w in others])
            ends = np.concatenate([np.r_[True, np.zeros(len(w.nodes) - 2, bool), True] for w in others])
            tree = cKDTree(xy)
            d, k = tree.query(wa.coords, distance_upper_bound=styles.road_width(wa.tags) + MEDIAN)
            for nid, dd, kk in zip(wa.nodes, d, k):
                if np.isfinite(dd) and not ends[kk] and \
                        MISMATCH < abs(hmap.get(int(nid), 0.0) - hmap.get(int(ids[kk]), 0.0)) < 2.0:
                    pairs.append((int(nid), int(ids[kk])))
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
        self.ways = [p for w in world.ways_near(self.bounds) for p in w.pieces()]

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
        self._edge_barriers()
        self._cutting_guards()
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
                half = w.width / 2
                # No parapet across a slip road leaving the deck, or across the
                # deck it joins: each side stops where the other road's lane is
                # (found on a finer spacing wherever there is one).
                for step in (None, JOIN_STEP):
                    if step:
                        rxy, rh = densify(rxy, rh, step)
                    top = rh + 0.02
                    pl = offset_polyline(rxy, half - 0.3)
                    pr = offset_polyline(rxy, -half + 0.3)
                    gl, gr = self._joined_lane(w, pl, top), self._joined_lane(w, pr, top)
                    if not (gl.any() or gr.any()):
                        break
                surf = self.mb.surface("bridges", deck_mat, "world")
                ribbon(surf, rxy, top, w.width, textures.UV_SCALE.get(deck_mat, 4.0))
                conc = self.mb.surface("bridges", "concrete", "world")
                left = offset_polyline(rxy, half)
                right = offset_polyline(rxy, -half)
                bot = top - DECK_THICKNESS
                phl = np.where(gl, 0.0, _parapet_heights(w, left, top, hf))
                phr = np.where(gr, 0.0, _parapet_heights(w, right, top, hf))
                # Deck edges and underside. A deck OSM doesn't call a bridge
                # (a lifted slip road) is walled down to the ground where
                # there's no room under it: a retaining wall, not a gap.
                bl = br = bot
                if w.group in ("road", "rail") and not styles.is_bridge(w.tags):
                    hl, hr = hf.sample(left[:, 0], left[:, 1]), hf.sample(right[:, 0], right[:, 1])
                    bl = np.where(top - hl < LIFT_WALL_CLEAR, np.minimum(hl - 0.3, bot), bot)
                    br = np.where(top - hr < LIFT_WALL_CLEAR, np.minimum(hr - 0.3, bot), bot)
                walls(conc, left[::-1], bl[::-1], top[::-1] + phl[::-1], 2.0, 2.0, closed=False)
                walls(conc, right, br, top + phr, 2.0, 2.0, closed=False)
                ribbon(conc, rxy, bot, w.width + 0.6, 4.0, up=False)
                if w.group == "road":
                    _bevel(conc, rxy, left, top, hf, gl)
                    _bevel(conc, rxy, right, top, hf, gr)
                # Parapets (inner faces and tops) so cars can't drive off.
                for k in _parapet_runs(phl, gl):
                    walls(conc, pl[k], top[k], top[k] + phl[k], 2.0, 2.0, closed=False)
                    ribbon(conc, rxy[k], top[k] + phl[k], 0.3, 2.0, lateral=half - 0.15)
                for k in _parapet_runs(phr, gr):
                    walls(conc, pr[k][::-1], top[k][::-1], top[k][::-1] + phr[k][::-1], 2.0, 2.0, closed=False)
                    ribbon(conc, rxy[k], top[k] + phr[k], 0.3, 2.0, lateral=-half + 0.15)
                # Piers every ~30 m where there's room underneath, but not in
                # the lanes of a road or on a railway passing under (a
                # footbridge's pier stood in the Graham Farmer Fwy): moved
                # along the deck to the nearest spot clear of them, or left out.
                for p, yaw, foot, top_k in self._pier_spots(w, rxy, bot):
                    _box(conc, p, foot, top_k, (1.4, min(w.width * 0.6, 6.0)), yaw)
        self._deck_joints()

    def _deck_joints(self):
        """Where two bridge ways meet end to end at an angle (a deck split
        into several ways at a bend), each is drawn square to its own end and
        the outside of the bend was left open: a wedge-shaped crack through
        the deck and its side wall, which the player fell through to the
        ground under the deck (Mounts Bay Rd's slip road). The wedge gets
        its deck, underside, side wall and parapet."""
        hf = self.w.hf
        e0, n0, e1, n1 = self.bounds
        ends = {}
        for w in self.ways:
            if w.bridge and len(w.xy) > 1:
                for k in (0, -1):
                    ends.setdefault(int(w.nodes[k]), []).append((w, k))
        ends = {n: v for n, v in ends.items() if len(v) == 2}
        if not ends:
            return
        # Only where nothing else meets them (not a junction on the deck).
        ids, counts = np.unique(np.concatenate([w.nodes for w in self.ways]), return_counts=True)
        seen = dict(zip(ids.tolist(), counts.tolist()))
        for nid, ((a, ka), (b, kb)) in ends.items():
            if seen.get(nid, 0) != 2 or a.group != b.group:
                continue
            p = a.xy[ka]
            if not (e0 <= p[0] < e1 and n0 <= p[1] < n1):
                continue
            ta, tb = _end_heading(a, ka), -_end_heading(b, kb)  # along a into the node, along b out of it
            ang = math.degrees(math.acos(float(np.clip(ta @ tb, -1.0, 1.0))))
            if not JOINT_MIN < ang < JOINT_MAX:
                continue
            side = -1.0 if ta[0] * tb[1] - ta[1] * tb[0] > 0 else 1.0  # outside the bend: right of a left turn
            na, nb = np.array([-ta[1], ta[0]]) * side, np.array([-tb[1], tb[0]]) * side
            ha, hb = a.width / 2, b.width / 2
            top = (float(a.h[ka]) + float(b.h[kb])) / 2 + 0.02
            bot = top - DECK_THICKNESS
            mat = "asphalt" if a.group == "road" else "ballast" if a.group == "rail" else "path"
            # Corners walked along the bend's outside the way the deck goes.
            edge = np.array([p + na * ha, p + nb * hb])
            under = np.array([p + na * (ha + 0.3), p + nb * (hb + 0.3)])
            deck = orient(Polygon([p, *edge]), 1.0)
            if deck.area < 0.01:
                continue
            flat_cap(self.mb.surface("bridges", mat, "world"), deck, top, textures.UV_SCALE.get(mat, 4.0))
            conc = self.mb.surface("bridges", "concrete", "world")
            flat_cap(conc, orient(Polygon([p, *under]), 1.0), bot, 4.0, down=True)
            tops = np.full(2, top)
            ph = np.minimum(_parapet_heights(a, edge, tops, hf), _parapet_heights(b, edge, tops, hf))
            inner = np.array([p + na * (ha - 0.3), p + nb * (hb - 0.3)])
            if self._joined_lane(a, inner, tops).any() or self._joined_lane(b, inner, tops).any():
                ph[:] = 0.0
            low = np.full(2, bot)
            if a.group in ("road", "rail") and not styles.is_bridge(a.tags):
                g = hf.sample(edge[:, 0], edge[:, 1])
                low = np.where(top - g < LIFT_WALL_CLEAR, np.minimum(g - 0.3, bot), bot)
            # walls() faces right of travel: out of the bend on the right
            # side, so walk it backwards on the left.
            fwd = slice(None) if side < 0 else slice(None, None, -1)
            walls(conc, edge[fwd], low[fwd], (tops + ph)[fwd], 2.0, 2.0, closed=False)
            if (ph > 0).all():
                back = slice(None, None, -1) if side < 0 else slice(None)
                walls(conc, inner[back], tops[back], (tops + ph)[back], 2.0, 2.0, closed=False)
                flat_cap(conc, orient(Polygon([*edge, *inner[::-1]]), 1.0), top + float(ph.min()), 2.0)

    def _pier_spots(self, w, rxy, bot) -> list:
        """(xy, yaw, foot, top) of the piers under a bridge run `rxy` with deck
        underside `bot`: about every PIER_SPACING where there's room under
        the deck, each shifted along it (up to PIER_SHIFT) off the asphalt of
        any road, and any railway, passing under it, or dropped."""
        hf = self.w.hf
        s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(rxy, axis=0), axis=1))])
        if s[-1] < 1e-6:
            return []
        lo, hi = rxy.min(axis=0) - 30.0, rxy.max(axis=0) + 30.0
        under = []
        for o in self.ways:
            if o.id == w.id or o.group not in ("road", "rail") or o.tunnel or len(o.xy) < 2:
                continue
            if (o.xy.max(axis=0) < lo).any() or (o.xy.min(axis=0) > hi).any():
                continue
            os_ = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(o.xy, axis=0), axis=1))])
            half = (o.width if o.group == "road" else 3.0) / 2 + PIER_CLEAR
            under.append((LineString(o.xy), os_, o.h, half))
        across = min(w.width * 0.6, 6.0)

        def at(si):
            p = np.array([np.interp(si, s, rxy[:, 0]), np.interp(si, s, rxy[:, 1])])
            a, b = (np.array([np.interp(t, s, rxy[:, 0]), np.interp(t, s, rxy[:, 1])])
                    for t in (max(si - 2.0, 0.0), min(si + 2.0, s[-1])))
            return p, math.atan2(b[1] - a[1], b[0] - a[0]), float(np.interp(si, s, bot))

        def clear(p, yaw, hb):
            c, sn = math.cos(yaw), math.sin(yaw)
            corners = np.array([[-1.4, -across], [1.4, -across], [1.4, across], [-1.4, across]]) / 2
            foot = Polygon(corners @ np.array([[c, sn], [-sn, c]]) + p)
            for line, os_, oh, half in under:
                if foot.distance(line) >= half:
                    continue
                if np.interp(line.project(Point(p)), os_, oh) < hb:
                    return False
            return True

        out = []
        n = max(2, int(np.ceil(s[-1] / PIER_SPACING)) + 1)
        ss = np.linspace(0.0, s[-1], n)
        for k in range(1, n - 1):
            for shift in (0.0, *[sg * d for d in np.arange(PIER_STEP, PIER_SHIFT + 1e-6, PIER_STEP) for sg in (1, -1)]):
                si = ss[k] + shift
                if not 2.0 < si < s[-1] - 2.0:
                    continue
                p, yaw, hb = at(si)
                g = float(hf.sample(p[0], p[1]))
                if hb - g > 2.5 and clear(p, yaw, hb):
                    out.append((p, yaw, g - 1.5, hb))
                    break
        return out

    def _joined_lane(self, w, pts, top) -> np.ndarray:
        """Which of `pts` (a bridge's parapet line, at deck heights `top`) stand
        in the lanes of another way of its network at about the same height: a
        slip road branching off the deck, or the deck a ramp merges onto. Roads
        passing under or over are far off in height and don't count."""
        hit = np.zeros(len(pts), dtype=bool)
        lo, hi = pts.min(axis=0) - 30.0, pts.max(axis=0) + 30.0
        p = shapely.points(pts)
        for o in self.ways:
            if o is w or o.group != w.group or o.tunnel:
                continue
            if (o.xy.max(axis=0) < lo).any() or (o.xy.min(axis=0) > hi).any():
                continue
            if _continues(w, o):
                continue
            line = LineString(o.xy)
            near = shapely.distance(p, line) < o.width / 2 - JOIN_MARGIN
            if not near.any():
                continue
            s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(o.xy, axis=0), axis=1))])
            oh = np.interp(shapely.line_locate_point(line, p[near]), s, o.h)
            near[near] = np.abs(oh - top[near]) < JOIN_DROP
            hit |= near
        return hit

    def _edge_barriers(self):
        """A row of concrete barriers across each road where it is closed at
        the edge of the built map (World.edge_closures)."""
        e0, n0, e1, n1 = self.bounds
        surf = self.mb.surface("props", "concrete", "world")
        here = [c for c in getattr(self.w, "closures", ()) if e0 <= c["xy"][0] < e1 and n0 <= c["xy"][1] < n1]
        for c in _merge_closures(here):
            across = np.array([-c["out"][1], c["out"][0]])
            n = max(1, int(np.ceil(2 * c["half"] / (BARRIER_LEN + BARRIER_GAP))))
            for k in range(n):
                t = (k - (n - 1) / 2) * (BARRIER_LEN + BARRIER_GAP)
                p = c["xy"] + across * t
                base = c["h"] + ROAD_OFFSET if c["grade_separated"] else float(self.w.hf.sample(p[0], p[1]))
                _jersey(surf, p, across, BARRIER_LEN, base)

    def _cutting_guards(self):
        """Barriers along the top of the bank into a rail cutting (CUT_DROP)."""
        e0, n0, e1, n1 = self.bounds
        near = [g for g in getattr(self.w, "rail_land", ()) if g.intersects(self.box.buffer(CUT_SEARCH))]
        if not near:
            return
        surf = self.mb.surface("props", "concrete", "world")
        open_ = shapely.union_all([self.road_area, self.sidewalk_area, self.path_area, self.rail_area,
                                   self.w.water_union.intersection(self.box.buffer(20))])
        shapely.prepare(open_)
        for g in near:
            for p in getattr(g, "geoms", [g]):
                p = orient(p, 1.0)
                for ring in (p.exterior, *p.interiors):
                    for xy, along, base, foot in _cutting_fence(np.asarray(ring.coords)[:, :2], self.w.hf, open_):
                        if e0 <= xy[0] < e1 and n0 <= xy[1] < n1:
                            _jersey(surf, xy, along, BARRIER_LEN, base, foot)

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
                # Outside of the box: its lid shows where the ground over it is cut away
                # (_tunnel_cut), and its sides rise to meet the lid.
                outer = self.mb.surface("tunnels", "concrete", "world")
                lt, rt = _lid(outer, rxy, roof, w.width / 2 + 1.0, hf)
                walls(outer, lo[::-1], floor[::-1] - 0.5, lt[::-1], 3.0, 3.0, closed=False)
                walls(outer, ro, floor - 0.5, rt, 3.0, 3.0, closed=False)

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
        for d in self.w.deck_parts:
            p = d.poly
            c = p.representative_point()
            if not self.box.contains(c):
                continue
            p = orient(p, 1.0)
            surf = self.mb.surface("props", {"pier": "path", "groyne": "concrete"}.get(d.kind, "sidewalk"), "world")
            side = self.mb.surface("props", "concrete", "world")
            if d.kind == "pier":
                self._deck_rails(d, p, side)
            if d.landing is None:
                flat_cap(surf, p, d.top, 3.0)
                for r in [p.exterior, *p.interiors]:
                    walls(side, np.asarray(r.coords), d.bottom, d.top, 2.0, 2.0)
                continue
            # A ramp: the cap draped on its own fine grid of deck heights.
            b = p.bounds
            es = np.arange(math.floor(b[0]) - 1.0, b[2] + 2.0, DECK_STEP)
            ns = np.arange(math.floor(b[1]) - 1.0, b[3] + 2.0, DECK_STEP)
            E, N = np.meshgrid(es, ns)
            dhf = HeightField(es[0], ns[0], DECK_STEP, d.heights(E, N))
            drape(surf, p, CellGrid(dhf, (es[0], ns[0], es[-1], ns[-1])), 0.0, 3.0)
            for r in [p.exterior, *p.interiors]:
                xy, _ = densify(np.asarray(r.coords), np.zeros(len(r.coords)), DECK_STEP)
                walls(side, xy, d.bottom, d.heights(xy[:, 0], xy[:, 1]), 2.0, 2.0)

    def _deck_rails(self, d, p, surf):
        """A rail along the edges of jetty `d` (its piece `p`, anticlockwise)
        over dry ground it's too high to step back up from (RAIL_DROP), but
        not where it meets another deck, a street or a path."""
        hf = self.w.hf
        level = min((wb.level for wb in self.w.water if wb.big and wb.geom.intersects(p)), default=RIVER_LEVEL)
        others = [o.poly for o in self.w.deck_parts if o is not d and o.poly.distance(p) < 2.0]
        open_ = shapely.union_all([getattr(self, a, Polygon()) for a in ("road_area", "sidewalk_area", "path_area")]
                                  + others)
        shapely.prepare(open_)
        for r in [p.exterior, *p.interiors]:
            xy, _ = densify(np.asarray(r.coords), np.zeros(len(r.coords)), DECK_STEP)
            if len(xy) < 3:
                continue
            top = d.heights(xy[:, 0], xy[:, 1])
            t = np.gradient(xy, axis=0)
            t /= np.maximum(np.linalg.norm(t, axis=1), 1e-9)[:, None]
            out = xy - np.column_stack([-t[:, 1], t[:, 0]]) * 0.2
            g = hf.sample(out[:, 0], out[:, 1])
            on = (top - g > RAIL_DROP) & (g > level + 0.2) & ~shapely.contains_xy(open_, out[:, 0], out[:, 1])
            for a, b in _runs(on):
                # (on to the next point either side, so it meets the corner
                # or the deck beside it with no gap to step off through)
                a, b = max(a - 1, 0), min(b + 1, len(xy))
                seg, h = xy[a:b], top[a:b] + RAIL_H
                walls(surf, seg, top[a:b], h, 2.0, 2.0, closed=False)
                inner = offset_polyline(seg, 0.15)
                walls(surf, inner[::-1], top[a:b][::-1], h[::-1], 2.0, 2.0, closed=False)
                ribbon(surf, seg, h, 0.15, 2.0, lateral=0.075)

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
            # Lights stand on the left verge (right for motorways) with the arm
            # over the road, at the back of the footpath where there is one.
            motorway = w.tags.get("highway") == "motorway"
            side = w.width / 2 + (LIGHT_BACK if w.sidewalk else LIGHT_VERGE)
            off = offset_polyline(xy, -side if motorway else side)
            d = np.gradient(xy, axis=0)
            for k in range(1, len(xy) - 1):
                e, n = off[k]
                if not (self.bounds[0] <= e < self.bounds[2] and self.bounds[1] <= n < self.bounds[3]):
                    continue
                # Clear of the asphalt, junction corners and other roads' too:
                # a pole at the kerb stops a car that runs a wheel over it.
                if self.road_area.distance(Point(e, n)) < LIGHT_CLEAR:
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


def _merge_closures(closures) -> list[dict]:
    """One row of barriers across the carriageways of a divided road where
    they leave the map side by side, instead of overlapping rows."""
    out = []
    for c in sorted(closures, key=lambda c: -c["half"]):
        for m in out:
            across = np.array([-m["out"][1], m["out"][0]])
            d = c["xy"] - m["xy"]
            if abs(float(d @ m["out"])) < 3.0 and abs(float(d @ across)) < m["half"] + c["half"] and \
                    abs(c["h"] - m["h"]) < 1.0 and c["grade_separated"] == m["grade_separated"]:
                t = float(d @ across)
                lo, hi = min(-m["half"], t - c["half"]), max(m["half"], t + c["half"])
                m["xy"] = m["xy"] + across * (lo + hi) / 2
                m["half"] = (hi - lo) / 2
                break
        else:
            out.append(dict(c))
    return out


def _jersey(surf, center_xy, along, length: float, base: float, foot: float | None = None):
    """A concrete barrier block `length` long in the direction `along`,
    standing on `base` (sunk a little so it sits on sloping ground), its
    foot down to `foot` if that's lower."""
    side = np.array([along[1], -along[0]])
    prof = np.array(JERSEY)
    half = along * length / 2
    low = base - 0.15 if foot is None else min(foot, base - 0.15)
    ring = [(center_xy + side * a, base - 0.1 + z if z > 0 else low) for a, z in prof]
    v, nrm, uv, tris = [], [], [], []

    mid = np.array([center_xy[0], center_xy[1], base + 0.35])

    def quad(p):
        p = np.asarray(p)
        nv = np.cross(p[1] - p[0], p[2] - p[0])
        nv = nv / max(float(np.linalg.norm(nv)), 1e-9)
        if nv @ (p.mean(axis=0) - mid) < 0:  # face outwards
            p, nv = p[::-1], -nv
        i = len(v)
        v.extend(p)
        nrm.extend([nv] * len(p))
        uv.extend([(q[0] + q[1], q[2]) for q in p / 2.0])
        tris.extend([(i, i + 1, i + 2), (i, i + 2, i + 3)] if len(p) == 4 else
                    [(i, i + k, i + k + 1) for k in range(1, len(p) - 1)])

    def pt(k, end):
        (xy, z) = ring[k]
        q = xy + half * end
        return (q[0], q[1], z)

    m = len(ring)
    for k in range(m):
        k2 = (k + 1) % m
        quad([pt(k, -1), pt(k, 1), pt(k2, 1), pt(k2, -1)])
    quad([pt(k, 1) for k in range(m)])
    quad([pt(k, -1) for k in reversed(range(m))])
    surf.add(np.array(v), np.array(nrm), np.array(uv), np.array(tris, dtype=np.int64))


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
    world.closures = world.edge_closures(set(index["tiles"]) | {k.name for k in keys})
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
            if run.get("axis", "z") == "z":
                one["_end"] = (ue * step, un * step)  # where the piece ends, to follow a sloping deck
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
            # On a jetty: the deck top MeshBuilder draws.
            y = world.deck_height(spec["deck"], e, n)
        else:
            y = float(world.hf.sample(e, n))
        fresh[spec["id"]] = {"id": spec["id"], "scene": spec["scene"],
                             "p": [round(e, 2), round(y, 2), round(-n, 2)],
                             "yaw": round(math.pi - math.radians(spec["bearing"]), 4)}
        if "deck" in spec and "_end" in spec:
            # A run piece along a jetty that ramps to the water: tilt it (about
            # its local X, Godot's convention) so its far end sits on the deck too.
            de, dn = spec["_end"]
            rise = world.deck_height(spec["deck"], e + de, n + dn) - y
            pitch = -math.atan2(rise, math.hypot(de, dn))
            if abs(pitch) > 1e-3:
                fresh[spec["id"]]["pitch"] = round(pitch, 4)
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
