"""Points of interest for side activities (index.json "pois", docs/HOOKS.md).

Every entry is somewhere worth driving to: lookouts, beaches, servos,
drive-thrus, quiet spots to park and watch the city, fishing spots on jetties,
groynes and foreshores, and the hand-built landmarks. Each has a spot on the
ground to stop the car (`p`, snapped to a road or in a car park), the facing
for that spot, and the feature itself (`at`; for a jetty, its far end).
"""
from __future__ import annotations

import math
import re

import numpy as np
import shapely
from shapely.geometry import Point
from shapely.strtree import STRtree

from . import places
from .meshbuild import polygons_of
from .places import godot_yaw

LOOKOUT_PARK = 250.0  # metres from a lookout to the road or car park you leave the car in
BEACH_PARK = 350.0
SPOT_PARK = 250.0
NOT_A_VIEW = re.compile(r"enclosure|exhibit|aviary|penguin|tiger|giraffe|elephant|rhino|baboon|gibbon|"
                        r"orangutan|meerkat|crocodile|cassowary|kangaroo|tortoise|balcony|level", re.I)
MAX_CLIMB = 8.0  # a stop this much above or below the feature is on another road (under a cliff)


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


class _Lots:
    """Public car parks, for parking near a lookout or a beach."""

    def __init__(self, world):
        self.polys = []
        for a in world.parking:
            t = a.tags
            if t.get("amenity") != "parking" or t.get("access") in ("private", "customers", "no"):
                continue
            if t.get("parking", "surface") not in ("surface", "street_side", "lane"):
                continue
            for p in getattr(a.geom, "geoms", [a.geom]):
                if p.geom_type == "Polygon" and p.area > 80:
                    self.polys.append(p)
        self.tree = STRtree(self.polys) if self.polys else None

    def near(self, e, n, radius, ok=lambda e, n: True):
        """Point inside the nearest car park within `radius` that passes `ok`, or None."""
        if self.tree is None:
            return None
        hits = self.tree.query(Point(e, n).buffer(radius))
        for poly in sorted((self.polys[int(k)] for k in hits), key=lambda p: p.distance(Point(e, n))):
            c = poly.representative_point()
            if ok(c.x, c.y):
                return float(c.x), float(c.y)
        return None


def build(world, cfg, proj, size: float, built_tiles: set, inside_hf) -> list[dict]:
    """POIs inside this build's terrain and on built tiles."""
    from .build import deck_heights  # build imports this module
    hf = world.hf
    lots = _Lots(world)
    zoo = shapely.union_all([a.geom for a in world.poi_areas if a.tags.get("tourism") == "zoo"]) \
        if any(a.tags.get("tourism") == "zoo" for a in world.poi_areas) else None
    out: dict[str, dict] = {}

    def on_map(e, n):
        return inside_hf(e, n) and f"{math.floor(e / size)}_{math.floor(n / size)}" in built_tiles

    def add(pid, kind, name, at, park, yaw=None, **extra):
        e, n = park
        if not on_map(e, n) or not on_map(*at):
            return
        if yaw is None:
            de, dn = at[0] - e, at[1] - n
            yaw = godot_yaw(de, dn) if math.hypot(de, dn) > 2 else 0.0
        base = pid
        k = 2
        while pid in out:
            pid = f"{base}_{k}"
            k += 1
        entry = {"id": pid, "kind": kind, "name": name,
                 "p": [round(e, 2), round(float(hf.sample(e, n)) + 0.3, 2), round(-n, 2)],
                 "yaw": round(float(yaw), 4),
                 "at": [round(at[0], 2), round(float(hf.sample(*at)), 2), round(-at[1], 2)]}
        entry.update({k: v for k, v in extra.items() if v})
        out[pid] = entry

    def park_near(e, n, radius):
        """A car park or road near (e, n) at about its height."""
        h0 = max(float(hf.sample(e, n)), 1.0)  # a feature over the water is at the shore's height

        def level(pe, pn):
            return abs(float(hf.sample(pe, pn)) - h0) < MAX_CLIMB

        lot = lots.near(e, n, radius, level)
        if lot:
            return lot, None
        near = [w for w in world.ways if w.group == "road"
                and np.min(np.hypot(w.xy[:, 0] - e, w.xy[:, 1] - n)) < radius + 300
                and np.min(np.abs(w.h - h0)) < MAX_CLIMB]
        snap = places.snap_to_road(near, e, n, radius)
        if snap and level(snap[0], snap[1]):
            return (snap[0], snap[1]), snap[2]
        return None, None

    decks = {oid: (g, kind) for g, kind, oid in world.decks}
    seen = []
    # Hand-picked quiet spots, lookouts and fishing spots (config "pois").
    for spec in cfg.get("pois", {}).get("spots", []):
        if "pier" in spec:
            # Fishing off a jetty or groyne: park at its shore end, `at` is the far end.
            if spec["pier"] not in decks:
                continue
            g, kind = decks[spec["pier"]]
            ring = np.asarray(max(polygons_of(g), key=lambda q: q.area).exterior.coords)
            land = ring[int(np.argmax(hf.sample(ring[:, 0], ring[:, 1])))]
            # The far end, a step in from the edge so it is on the deck.
            deck = max(polygons_of(g), key=lambda q: q.area)
            inset = deck.buffer(-1.0)
            inner = np.asarray(max(polygons_of(inset), key=lambda q: q.area).exterior.coords) \
                if not inset.is_empty else ring
            far = inner[int(np.argmax(np.hypot(*(inner - land).T)))]
            top, _ = deck_heights(hf, max(polygons_of(g), key=lambda q: q.area), kind)
            park, _ = park_near(float(land[0]), float(land[1]), SPOT_PARK)
            if park is None:
                continue
            at = (float(far[0]), float(far[1]))
            add(spec["id"], spec["kind"], spec["name"], at, park,
                godot_yaw(at[0] - park[0], at[1] - park[1]), suburb=spec.get("suburb", ""))
            if spec["id"] in out:
                out[spec["id"]]["at"][1] = round(top, 2)
            continue
        e, n = proj.fwd(spec["lon"], spec["lat"])
        at = proj.fwd(*spec["look_at"]) if "look_at" in spec else (e, n)
        park, yaw = (e, n), None
        if spec.get("snap", True):
            park, yaw = park_near(e, n, SPOT_PARK)
            if park is None:
                continue
        if spec["kind"] == "fishing":
            # Cast from the water's edge nearest the car.
            edge = _water_edge(world, park, 150.0)
            if edge is not None:
                at = edge[:2]
        if "look_at" in spec or spec["kind"] == "fishing":
            yaw = godot_yaw(at[0] - park[0], at[1] - park[1])
        add(spec["id"], spec["kind"], spec["name"], at, park, yaw, suburb=spec.get("suburb", ""))
        if spec["kind"] == "fishing" and spec["id"] in out:
            out[spec["id"]]["at"][1] = round(edge[2], 2) if edge is not None else max(out[spec["id"]]["at"][1], 0.0)
        seen.append((e, n))
    # Lookouts: OSM viewpoints, named or not (zoo enclosures aren't views).
    for oid, t, e, n in world.poi_nodes:
        if t.get("tourism") != "viewpoint":
            continue
        name = t.get("name", "")
        if (name and NOT_A_VIEW.search(name)) or (zoo is not None and zoo.contains(Point(e, n))):
            continue
        if any(math.hypot(e - a, n - b) < 120 for a, b in seen):
            continue  # one stop for a cluster of platforms
        park, yaw = park_near(e, n, LOOKOUT_PARK)
        if park is None:
            continue
        seen.append((e, n))
        if name and name == name.lower():
            name = ""  # a mapper's note, not a name
        suburb = _suburb(world, e, n)
        add(f"lookout_{slug(name)}" if name else f"lookout_{oid}", "lookout",
            name or (f"{suburb} lookout" if suburb else "Lookout"), (e, n), park, yaw, suburb=suburb)
    # Beaches: one stop each, in the nearest car park.
    for a in world.poi_areas:
        t = a.tags
        if t.get("natural") != "beach" or not t.get("name"):
            continue
        c = a.geom.representative_point()
        park, yaw = park_near(c.x, c.y, BEACH_PARK)
        if park is None:
            continue
        add(f"beach_{slug(t['name'])}", "beach", t["name"], (c.x, c.y), park, yaw, suburb=_suburb(world, c.x, c.y))
    # Servos and drive-thrus, nodes or areas, on their own forecourt.
    shops = [(oid, t, e, n) for oid, t, e, n in world.poi_nodes if t.get("amenity") in ("fuel", "fast_food")]
    for a in world.poi_areas:
        if a.tags.get("amenity") in ("fuel", "fast_food"):
            c = a.geom.representative_point()
            shops.append((a.id, a.tags, c.x, c.y))
    for oid, t, e, n in shops:
        if t.get("amenity") == "fast_food" and t.get("drive_through") != "yes":
            continue
        kind = "servo" if t.get("amenity") == "fuel" else "drive_thru"
        name = t.get("name") or t.get("brand") or ("Servo" if kind == "servo" else "Drive-thru")
        snap = places.snap_to_road(world.ways, e, n, 80.0)
        yaw = snap[2] if snap else 0.0
        add(f"{kind}_{oid}", kind, name, (e, n), (e, n), yaw, brand=t.get("brand", ""), suburb=_suburb(world, e, n))
    # Landmarks.
    for lm in world.landmarks:
        e, n = lm.center
        park, yaw = park_near(e, n, 300.0)
        if park is None:
            continue
        add(f"landmark_{lm.id}", "landmark", lm.name, (e, n), park, None, suburb=lm.suburb)
    return list(out.values())


def _water_edge(world, park, radius: float):
    """Nearest point on a shore at about sea level (the river, its coves and
    marinas) within `radius` of park, as (e, n, water level), or None."""
    from shapely.ops import nearest_points
    p = Point(*park)
    best = None
    for wb in world.water:
        if wb.level > 3.0:  # a pond up in a park, not the river
            continue
        d = wb.geom.distance(p)
        if d < radius and (best is None or d < best[0]):
            best = (d, wb.geom, wb.level)
    if best is None:
        return None
    q = nearest_points(best[1].boundary if best[0] == 0 else best[1], p)[0]
    return float(q.x), float(q.y), float(best[2])


def _suburb(world, e, n) -> str:
    """Nearest suburb or locality name within 2.5 km."""
    if not hasattr(world, "_suburb_xy"):
        named = [(t["name"], lon, lat) for _, t, lon, lat in world.named
                 if t.get("place") in ("suburb", "locality", "neighbourhood")]
        world._suburb_names = [x[0] for x in named]
        if named:
            pe, pn = world.proj.fwd([x[1] for x in named], [x[2] for x in named])
            world._suburb_xy = np.column_stack([pe, pn])
        else:
            world._suburb_xy = np.zeros((0, 2))
    if not len(world._suburb_xy):
        return ""
    d = np.hypot(*(world._suburb_xy - [e, n]).T)
    k = int(np.argmin(d))
    return world._suburb_names[k] if d[k] < 2500 else ""
