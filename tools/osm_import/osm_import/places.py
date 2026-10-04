"""Hand-placed things the map puts in the world: the player's townhouse, job
sites and workshop bays.

They are listed in config.json by latitude/longitude (or, for things at home,
by position in the townhouse scene) and written to index.json, where
map/scripts/map_streamer.gd instances them.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from shapely.geometry import Polygon

from .common import Projector

# Roads a marker is never snapped onto.
NO_SNAP = {"motorway", "motorway_link", "trunk", "trunk_link"}
KERB_GAP = 1.3  # metres between a snapped marker and the road edge


@dataclass
class HomeSite:
    """The townhouse scene's frame: local (x, z) in the scene to plan (e, n)."""
    e: float
    n: float
    yaw: float            # Godot rotation about Y
    footprint: Polygon    # ground the scene covers, in plan coordinates
    h: float = 0.0        # ground height, set once the terrain is sculpted

    def to_plan(self, x, z):
        c, s = math.cos(self.yaw), math.sin(self.yaw)
        return self.e + x * c + z * s, self.n + x * s - z * c


def home_site(cfg: dict, proj: Projector) -> HomeSite | None:
    home = cfg.get("home")
    if not home:
        return None
    e, n = proj.fwd(home["lon"], home["lat"])
    # heading_deg is the compass direction the scene's +Z (towards the street) faces.
    yaw = math.pi - math.radians(home["heading_deg"])
    site = HomeSite(float(e), float(n), yaw, Polygon())
    x0, z0, x1, z1 = home["footprint"]
    site.footprint = Polygon([site.to_plan(x, z) for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))])
    return site


def godot_yaw(de: float, dn: float) -> float:
    """Yaw that points a node's -Z (forward) along plan direction (de, dn)."""
    return -math.atan2(de, dn)


def snap_to_road(ways, e: float, n: float, max_dist: float = 120.0):
    """Nearest point on an at-grade road, kept on the near side, a lane in from
    the kerb. Returns (e, n, yaw) or None when no road is close."""
    best = None
    p = np.array([e, n])
    for w in ways:
        if w.group != "road" or w.grade_separated or w.tags.get("highway") in NO_SNAP:
            continue
        a, b = w.xy[:-1], w.xy[1:]
        d = b - a
        L2 = np.maximum((d * d).sum(1), 1e-9)
        t = np.clip(((p - a) * d).sum(1) / L2, 0, 1)
        q = a + t[:, None] * d
        dist = np.hypot(*(p - q).T)
        k = int(np.argmin(dist))
        if dist[k] < max_dist and (best is None or dist[k] < best[0]):
            best = (float(dist[k]), q[k], d[k], w.width)
    if best is None:
        return None
    dist, q, d, width = best
    lateral = min(dist, max(width / 2 - KERB_GAP, 0.0))
    off = (p - q) / dist * lateral if dist > 1e-6 else np.zeros(2)
    # Face along the road, in the direction traffic on this side drives (left-hand traffic).
    side = d[0] * (p - q)[1] - d[1] * (p - q)[0]
    if side < 0:
        d = -d
    return float(q[0] + off[0]), float(q[1] + off[1]), godot_yaw(d[0], d[1])


def place(spec: dict, proj: Projector, ways, home: HomeSite | None):
    """(e, n, at_home, yaw) for a config entry, or None if it needs the home.
    Entries use "home": [x, z] (townhouse scene coordinates) or "lat"/"lon"
    (snapped to the nearest road unless "snap" is false)."""
    if "home" in spec:
        if home is None:
            return None
        x, z = spec["home"]
        e, n = home.to_plan(x, z)
        yaw = home.yaw + math.radians(spec.get("yaw_deg", 0.0))
        return e, n, True, yaw
    e, n = proj.fwd(spec["lon"], spec["lat"])
    e, n = float(e), float(n)
    yaw = -math.radians(spec["heading_deg"]) if "heading_deg" in spec else 0.0
    if spec.get("snap", True):
        snapped = snap_to_road(ways, e, n)
        if snapped:
            e, n, road_yaw = snapped
            if "heading_deg" not in spec:
                yaw = road_yaw
    return e, n, False, yaw


def _badge_candidates(ways, home: HomeSite | None):
    """Out-of-the-way spots a car can reach: dead ends, laneways, car park
    aisles and park roads. Yields (e, n, weight)."""
    ends: dict[int, int] = {}
    for w in ways:
        if w.group != "road":
            continue
        for k, n in enumerate(w.nodes):
            ends[int(n)] = ends.get(int(n), 0) + (1 if k in (0, len(w.nodes) - 1) else 2)
    for w in ways:
        if w.group != "road" or w.grade_separated:
            continue
        t = w.tags
        if t.get("highway") in NO_SNAP or t.get("access") in ("private", "no"):
            continue
        for k in (0, len(w.nodes) - 1):
            if ends.get(int(w.nodes[k])) == 1:
                yield float(w.xy[k, 0]), float(w.xy[k, 1]), 2.0
        if t.get("service") in ("alley", "parking_aisle") or t.get("highway") == "track":
            mid = len(w.xy) // 2
            yield float(w.xy[mid, 0]), float(w.xy[mid, 1]), 1.0


def pick_badges(ways, hf_sample, region_keys: dict, quotas: dict, size: float,
                home: HomeSite | None, seed_fn) -> list[dict]:
    """`quotas[region]` badges per region, spread out over its tiles by
    farthest-point sampling. Ids are "<region>_<n>", so growing the map never
    moves a badge someone may already have found."""
    cands = list(_badge_candidates(ways, home))
    if home:
        from shapely.geometry import Point
        fp = home.footprint.buffer(20)
        cands = [c for c in cands if not fp.contains(Point(c[0], c[1]))]
    if not cands:
        return []
    pts = np.array([(c[0], c[1]) for c in cands])
    wgt = np.array([c[2] for c in cands])
    tile = [(int(np.floor(e / size)), int(np.floor(n / size))) for e, n in pts]
    out = []
    for region, quota in quotas.items():
        keys = region_keys.get(region)
        if not keys:
            continue
        mask = np.array([t in keys for t in tile])
        idx = np.flatnonzero(mask)
        if len(idx) == 0:
            continue
        rng = seed_fn("badges", region)
        chosen = [int(idx[rng.integers(len(idx))])]
        d = np.hypot(*(pts[idx] - pts[chosen[0]]).T)
        while len(chosen) < min(quota, len(idx)):
            k = int(np.argmax(d * wgt[idx] * rng.uniform(0.8, 1.0, len(idx))))
            chosen.append(int(idx[k]))
            d = np.minimum(d, np.hypot(*(pts[idx] - pts[idx[k]]).T))
        for n, c in enumerate(chosen):
            e, nn = pts[c]
            out.append({"id": f"{region}_{n + 1:02d}", "region": region,
                        "position": [round(float(e), 2), round(float(hf_sample(e, nn)) + 0.02, 2), round(float(-nn), 2)]})
    return out

