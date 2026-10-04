"""Parking for the traffic system's parked cars (docs/TRAFFIC.md, "parking").

Three kinds, all from OSM:
- lots: amenity=parking areas that aren't kerbside (surface, multi-storey, ...).
- kerbs: lines along a road where cars park. From parking:left/right/both
  tags on the road, and from amenity=parking + parking=street_side|lane
  areas (Perth maps most on-street bays this way).
- spaces: single amenity=parking_space bays, with the way a car faces.
"""
from __future__ import annotations

import math

import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

from .places import godot_yaw

KERB_KINDS = ("street_side", "lane", "on_kerb", "half_on_kerb", "shoulder")
NOT_PARKING = ("no", "separate", "none", "no_parking", "no_stopping")
LOT_KINDS = ("surface", "multi-storey", "underground", "rooftop", "carports", "garage_boxes", "sheds")
KERB_OFFSET = 0.35  # parked cars sit this far inside the carriageway edge, in metres


def _orientation(depth: float) -> str:
    if depth < 3.6:
        return "parallel"
    return "perpendicular" if depth > 5.2 else "diagonal"


def _side_tags(tags, side: str):
    """(parks, orientation) for one side of a road from the parking:* scheme
    (parking:left=lane) and the older parking:lane:left=parallel one."""
    for key in (f"parking:{side}", "parking:both"):
        v = tags.get(key)
        if v:
            if v in NOT_PARKING:
                return False, ""
            o = tags.get(f"{key}:orientation") or tags.get("parking:orientation") or "parallel"
            return v in KERB_KINDS or v == "yes", o
    for key in (f"parking:lane:{side}", "parking:lane:both"):
        v = tags.get(key)
        if v:
            if v in NOT_PARKING:
                return False, ""
            return v in ("parallel", "diagonal", "perpendicular", "marked"), "parallel" if v == "marked" else v
    return False, ""


def _xyz(hf, xy) -> list:
    return [[float(e), float(hf.sample(e, n)), float(-n)] for e, n in xy]


def _long_axis(geom):
    """(centre line through the bay's long side as two plan points, depth)."""
    mrr = geom.minimum_rotated_rectangle
    if mrr.geom_type != "Polygon":
        return None, 0.0
    c = np.asarray(mrr.exterior.coords)[:4]
    a, b = np.linalg.norm(c[1] - c[0]), np.linalg.norm(c[2] - c[1])
    if a >= b:
        mid0, mid1, depth = (c[0] + c[3]) / 2, (c[1] + c[2]) / 2, b
    else:
        mid0, mid1, depth = (c[0] + c[1]) / 2, (c[3] + c[2]) / 2, a
    return np.array([mid0, mid1]), float(depth)


class Parking:
    def __init__(self, world, roads):
        """roads: TrafficNetwork.roads (for kerb lines on tagged roads)."""
        hf = world.hf
        nj, ni = hf.H.shape
        e_max, n_max = hf.e0 + hf.step * (ni - 1), hf.n0 + hf.step * (nj - 1)

        def on_map(e, n):
            return hf.e0 <= e <= e_max and hf.n0 <= n <= n_max

        self.lots, self.kerbs, self.spaces = [], [], []
        by_id = {}
        for r in roads:
            by_id.setdefault(r["id"].split("/")[0], []).append(r)
        lines = [LineString(r["pts"][:, [0, 2]] * [1, -1]) for r in roads]
        tree = STRtree(lines) if lines else None
        for w in world.ways:
            if w.group != "road":
                continue
            t = w.tags
            for side, sign in (("left", 1.0), ("right", -1.0)):
                parks, orient = _side_tags(t, side)
                if not parks:
                    continue
                try:
                    line = LineString(w.xy).offset_curve(sign * (w.width / 2 - KERB_OFFSET))
                except Exception:
                    continue
                if line.is_empty or line.geom_type != "LineString" or line.length < 5:
                    continue
                xy = np.asarray(line.coords)
                if not on_map(*xy[0]):
                    continue
                part = by_id.get(f"w{w.id}", [{}])[0]
                self.kerbs.append({"pts": _xyz(hf, xy), "road": part.get("id", f"w{w.id}"),
                                   "side": side, "orientation": orient, "_mid": tuple(line.interpolate(0.5, True).coords[0])})
        for a in world.parking:
            t = a.tags
            g = a.geom
            if g.is_empty or g.area < 6:
                continue
            c = g.representative_point()
            if not on_map(c.x, c.y):
                continue
            if t.get("amenity") == "parking_space":
                axis, depth = _long_axis(g)
                if axis is None:
                    continue
                along = axis[1] - axis[0]
                long_side = float(np.linalg.norm(along))
                if long_side < 1:
                    continue
                u = along / long_side
                if long_side <= 7.0:
                    bays = [(np.array([c.x, c.y]), u, long_side, depth)]
                else:
                    # A row of bays mapped as one area: perpendicular bays
                    # side by side if it is deep enough, else parallel ones
                    # nose to tail.
                    deep = depth >= 4.2
                    pitch = 2.5 if deep else 6.0
                    n = max(1, int(round(long_side / pitch)))
                    mid = axis.mean(axis=0)
                    face = np.array([-u[1], u[0]]) if deep else u
                    bays = [(mid + u * (k + 0.5 - n / 2) * (long_side / n), face,
                             depth if deep else long_side / n, long_side / n if deep else depth)
                            for k in range(n)]
                for p, face, length, width in bays:
                    self.spaces.append({"p": _xyz(hf, [p])[0], "yaw": godot_yaw(*face),
                                        "length": round(float(length), 2), "width": round(float(width), 2),
                                        "kind": t.get("parking_space", "normal"), "_mid": (float(p[0]), float(p[1]))})
                continue
            kind = t.get("parking", "surface")
            if kind in KERB_KINDS:
                axis, depth = _long_axis(g)
                if axis is None:
                    continue
                road_id, side = "", ""
                if tree is not None:
                    k = int(tree.nearest(Point(c.x, c.y)))
                    r = roads[k]
                    road_id = r["id"]
                    ln = lines[k]
                    s = ln.project(Point(c.x, c.y))
                    p0 = np.asarray(ln.interpolate(max(0.0, s - 1)).coords[0])
                    p1 = np.asarray(ln.interpolate(min(ln.length, s + 1)).coords[0])
                    tdir = p1 - p0
                    rel = np.array([c.x, c.y]) - p0
                    side = "left" if tdir[0] * rel[1] - tdir[1] * rel[0] > 0 else "right"
                    # Run the bay the way its road runs.
                    if np.dot(axis[1] - axis[0], tdir) < 0:
                        axis = axis[::-1]
                self.kerbs.append({"pts": _xyz(hf, axis), "road": road_id, "side": side,
                                   "orientation": t.get("orientation") or _orientation(depth),
                                   "_mid": (c.x, c.y)})
                continue
            if kind not in LOT_KINDS and kind != "surface":
                kind = "surface"
            ring = np.asarray(g.exterior.coords if g.geom_type == "Polygon" else
                              max(g.geoms, key=lambda p: p.area).exterior.coords)
            lot = {"outline": _xyz(hf, ring[:-1]), "center": _xyz(hf, [(c.x, c.y)])[0],
                   "area": round(float(g.area), 1), "kind": kind, "_mid": (c.x, c.y)}
            cap = t.get("capacity", "")
            if cap.isdigit():
                lot["capacity"] = int(cap)
            if t.get("access") in ("customers", "private", "permissive", "yes", "public"):
                lot["access"] = t["access"]
            if "name" in t:
                lot["name"] = t["name"]
            self.lots.append(lot)

        self.spots = self._spots(world)

    def _spots(self, world) -> list:
        """Every place a parked car can sit: (e, n, y, yaw, kind), kind
        "street" or "lot". Kerb lines get bays at the usual pitch, surface car
        parks are filled with rows of bays, and spots near driveways, paths or
        street-light poles are dropped."""
        hf = world.hf
        blockers = [LineString(w.xy) for w in world.ways
                    if (w.group == "foot" or w.tags.get("service") == "driveway") and len(w.xy) > 1]
        block_tree = STRtree(blockers) if blockers else None

        def clear(e, n, r):
            if block_tree is None:
                return True
            return not len(block_tree.query(Point(e, n).buffer(r), predicate="intersects"))

        out = []
        for sp in self.spaces:
            e, n = sp["_mid"]
            out.append((e, n, sp["p"][1], sp["yaw"], "lot"))
        for k in self.kerbs:
            xy = np.array([[p[0], -p[2]] for p in k["pts"]])
            line = LineString(xy)
            pitch = 6.0 if k["orientation"] == "parallel" else 2.6
            n_bays = int((line.length - 2.0) // pitch)
            for i in range(max(0, n_bays)):
                s0 = 1.0 + (i + 0.5) * pitch
                p0 = np.asarray(line.interpolate(s0 - 0.5).coords[0])
                p1 = np.asarray(line.interpolate(s0 + 0.5).coords[0])
                c = (p0 + p1) / 2
                d = p1 - p0
                if k["orientation"] != "parallel":
                    d = np.array([-d[1], d[0]]) if k["side"] == "left" else np.array([d[1], -d[0]])
                if not clear(c[0], c[1], 1.2):
                    continue
                out.append((float(c[0]), float(c[1]), float(hf.sample(*c)), godot_yaw(*d), "street"))
        for lot in self.lots:
            if lot["kind"] != "surface":
                continue
            ring = np.array([[p[0], -p[2]] for p in lot["outline"]])
            if len(ring) < 3:
                continue
            inner = Polygon(ring).buffer(-1.0)
            pieces = list(getattr(inner, "geoms", [inner]))
            count = 0
            for poly in pieces:
                if poly.is_empty or poly.geom_type != "Polygon" or poly.area < 30:
                    continue
                axis, _ = _long_axis(poly)
                if axis is None:
                    continue
                u = (axis[1] - axis[0]) / max(np.linalg.norm(axis[1] - axis[0]), 1e-6)
                v = np.array([-u[1], u[0]])
                c0 = np.asarray(poly.centroid.coords[0])
                pts = np.asarray(poly.exterior.coords)
                su, sv = (pts - c0) @ u, (pts - c0) @ v
                # Double rows of 5 m bays either side of a 6 m aisle: 16 m a pair.
                for row in np.arange(sv.min() + 2.5, sv.max() - 2.4, 16.0):
                    for off, face in ((0.0, 1.0), (10.5, -1.0)):
                        rv = row + off
                        if rv > sv.max() - 2.4:
                            continue
                        for su_i in np.arange(su.min() + 1.3, su.max() - 1.2, 2.6):
                            if count >= 300:
                                break
                            c = c0 + u * su_i + v * rv
                            bay = Polygon([c + u * 1.2 + v * 2.4, c - u * 1.2 + v * 2.4,
                                           c - u * 1.2 - v * 2.4, c + u * 1.2 - v * 2.4])
                            if not poly.contains(bay) or not clear(c[0], c[1], 1.5):
                                continue
                            out.append((float(c[0]), float(c[1]), float(hf.sample(*c)),
                                        godot_yaw(*(v * face)), "lot"))
                            count += 1
        return out

    def tile_data(self, bounds) -> list:
        """docs/TRAFFIC.md: [{"pos": [x, y, z], "yaw": rad, "kind": "street" | "lot"}]."""
        e0, n0, e1, n1 = bounds
        return [{"pos": np.array([e, y, -n], dtype=np.float32), "yaw": round(float(yaw), 4), "kind": kind}
                for e, n, y, yaw, kind in self.spots if e0 <= e < e1 and n0 <= n < n1]
