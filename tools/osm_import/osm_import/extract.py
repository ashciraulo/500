"""Read the OSM extract and pull out the features the map uses."""
from __future__ import annotations

import hashlib
import pickle
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import osmium
import shapely
from osmium.filter import KeyFilter

from .common import CACHE_DIR, Projector

KEYS = ("highway", "building", "building:part", "landuse", "leisure", "natural",
        "waterway", "railway", "water", "amenity", "man_made", "place", "area:highway", "route",
        "tourism")

# Tag keys kept on features (everything else is dropped to keep the cache small).
KEEP = {"highway", "building", "building:part", "landuse", "leisure", "natural", "waterway",
        "railway", "water", "amenity", "man_made", "place", "name", "lanes", "oneway",
        "bridge", "tunnel", "layer", "cutting", "embankment", "width", "height",
        "min_height", "building:levels", "building:min_level", "roof:shape", "roof:levels",
        "roof:height", "roof:colour", "building:colour", "building:material", "service",
        "area", "surface", "historic", "heritage", "parking", "golf", "sport", "covered",
        "location", "level", "junction", "lit", "leaf_type", "genus", "species", "denotation",
        "gauge", "usage", "construction", "disused", "tracks", "access", "type", "maxspeed",
        "lanes:forward", "lanes:backward", "motor_vehicle", "parking_space", "capacity",
        "orientation", "tourism", "drive_through", "brand", "footway", "bicycle", "foot"}
# Prefixes kept as well (street parking: parking:left=lane, parking:both:orientation=...).
KEEP_PREFIX = ("parking:", "cycleway")


@dataclass
class Way:
    id: int
    tags: dict
    nodes: np.ndarray      # int64 node ids
    coords: np.ndarray     # (k, 2) plan coordinates


@dataclass
class Area:
    id: int
    tags: dict
    geom: object           # shapely (Multi)Polygon in plan coordinates


@dataclass
class Features:
    bbox_lonlat: tuple
    ways: list[Way] = field(default_factory=list)
    areas: list[Area] = field(default_factory=list)
    trees: np.ndarray = field(default_factory=lambda: np.zeros((0, 2)))
    named_nodes: list = field(default_factory=list)
    # Traffic control and transit nodes: (id, tags, e, n).
    control_nodes: list = field(default_factory=list)
    # route=bus relations: (id, ref, name, colour, [way ids in member order]).
    bus_routes: list = field(default_factory=list)
    # Points of interest mapped as nodes (viewpoints, servos, fast food): (id, tags, e, n).
    poi_nodes: list = field(default_factory=list)


CONTROL = ("traffic_signals", "give_way", "stop", "bus_stop")
POI_AMENITY = ("fuel", "fast_food", "school")


def _keep(tags) -> dict:
    return {t.k: t.v for t in tags if t.k in KEEP or t.k.startswith(KEEP_PREFIX)}


PIER_LINES = ("pier", "breakwater", "groyne")


def _linear_way(tags) -> bool:
    if "highway" in tags or "railway" in tags:
        return tags.get("area") != "yes"
    if tags.get("man_made") in PIER_LINES:
        return True  # areas come through as areas too; build.World keeps only open ways
    if tags.get("natural") == "coastline":
        return True  # the sea is built from it (build.World._sea)
    return tags.get("natural") == "tree_row" or tags.get("waterway") in ("river", "stream", "canal", "drain")


def _area_way(tags) -> bool:
    if "building" in tags or "building:part" in tags:
        return True
    if "highway" in tags:
        return tags.get("area") == "yes" or "area:highway" in tags
    if tags.get("tourism") in ("viewpoint", "zoo"):
        return True
    return any(k in tags for k in ("landuse", "leisure", "natural", "water", "amenity", "place", "man_made", "area:highway"))


def extract(pbf: Path, proj: Projector, bbox_lonlat: tuple, use_cache: bool = True) -> Features:
    """bbox_lonlat = (lon0, lat0, lon1, lat1)."""
    key = hashlib.sha1(repr((str(pbf), pbf.stat().st_mtime, bbox_lonlat, proj.lat0, proj.lon0, 12)).encode()).hexdigest()[:16]
    cache = CACHE_DIR / f"features_{key}.pkl"
    if use_cache and cache.exists():
        with open(cache, "rb") as f:
            return pickle.load(f)

    lon0, lat0, lon1, lat1 = bbox_lonlat
    feats = Features(bbox_lonlat)
    wkb = osmium.geom.WKBFactory()
    trees = []

    def inside(lon, lat):
        return lon0 <= lon <= lon1 and lat0 <= lat <= lat1

    fp = (osmium.FileProcessor(str(pbf)).with_locations().with_areas()
          .with_filter(KeyFilter(*KEYS)))
    for o in fp:
        if o.is_node():
            loc = o.location
            if not loc.valid() or not inside(loc.lon, loc.lat):
                continue
            t = o.tags
            if t.get("natural") == "tree":
                trees.append((loc.lon, loc.lat))
            elif t.get("highway") in CONTROL or t.get("railway") in ("station", "halt"):
                e, n = proj.fwd(loc.lon, loc.lat)
                feats.control_nodes.append((o.id, _keep(t), float(e), float(n)))
            elif t.get("tourism") == "viewpoint" or t.get("amenity") in POI_AMENITY:
                e, n = proj.fwd(loc.lon, loc.lat)
                feats.poi_nodes.append((o.id, _keep(t), float(e), float(n)))
            elif "name" in t and ("place" in t or "amenity" in t or "leisure" in t):
                feats.named_nodes.append((o.id, _keep(t), loc.lon, loc.lat))
        elif o.is_way():
            if not _linear_way(o.tags):
                continue
            try:
                ll = np.array([(n.lon, n.lat) for n in o.nodes])
            except osmium.InvalidLocationError:
                continue
            if len(ll) < 2:
                continue
            if (ll[:, 0].max() < lon0 or ll[:, 0].min() > lon1 or
                    ll[:, 1].max() < lat0 or ll[:, 1].min() > lat1):
                continue
            e, n = proj.fwd(ll[:, 0], ll[:, 1])
            feats.ways.append(Way(o.id, _keep(o.tags), np.array([n.ref for n in o.nodes], dtype=np.int64),
                                  np.column_stack([e, n])))
        elif o.is_relation():
            t = o.tags
            if t.get("type") == "route" and t.get("route") == "bus":
                ways = [m.ref for m in o.members if m.type == "w" and m.role in ("", "forward", "backward")]
                if ways:
                    feats.bus_routes.append((o.id, t.get("ref", ""), t.get("name", ""),
                                             t.get("colour", ""), ways))
        elif o.is_area():
            if not _area_way(o.tags):
                continue
            try:
                g = shapely.from_wkb(wkb.create_multipolygon(o))
            except Exception:
                continue
            b = g.bounds
            if b[2] < lon0 or b[0] > lon1 or b[3] < lat0 or b[1] > lat1:
                continue
            g = shapely.transform(g, lambda xy: np.column_stack(proj.fwd(xy[:, 0], xy[:, 1])))
            if not g.is_valid:
                g = shapely.make_valid(g)
            feats.areas.append(Area(o.orig_id(), _keep(o.tags), g))

    if trees:
        t = np.array(trees)
        e, n = proj.fwd(t[:, 0], t[:, 1])
        feats.trees = np.column_stack([e, n])
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with open(cache, "wb") as f:
        pickle.dump(feats, f, protocol=pickle.HIGHEST_PROTOCOL)
    return feats
