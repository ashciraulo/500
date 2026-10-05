"""Road data for the traffic system (docs/TRAFFIC.md), one file per tile.

Ways are split at junctions and at give-way/stop nodes so every road runs
between two graph nodes, keyed by OSM node ids so pieces in neighbouring
tiles join up. Signals tagged just before a junction move onto it.
"""
from __future__ import annotations

import re

import numpy as np
from shapely.geometry import LineString, Point

from . import styles
from .parking import Parking

TRAFFIC_KINDS = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
    "residential", "living_street",
}
SIGNAL_REACH = 35.0  # metres along a way a signal tag may sit from its junction
SIGNAL_SPREAD = 30.0  # junctions this close along a road share one set of lights
LANE_WIDTH = 3.2  # traffic/scripts/traffic_graph.gd
STADIUM_WALK = 600.0  # metres around Optus Stadium whose footpaths carry event crowds
BRIDGE_APPROACH = 150.0  # footpaths this close to the Matagarup Bridge's ends join it
# The CBD and Northbridge (plan metres e0, n0, e1, n1): malls, plazas and
# footpaths here go out as footways for crowds and night-life walkers.
CITY_WALK = (-560.0, -1780.0, 2180.0, 440.0)
CITY_FOOT = {"pedestrian", "footway", "path", "steps"}
CARRIAGEWAY_GAP = 0.6  # clear space kept between opposing one-way carriageways
MAX_SHIFT = 3.0  # most two carriageways are pulled apart, in metres
MERGE_ZONE = 15.0  # metres from a node both sides share where they may converge
NO_CARS = {"private", "no"}


def _int(v):
    m = re.match(r"\s*(\d+)", v or "")
    return int(m.group(1)) if m else None


def lane_split(tags, oneway: bool) -> tuple[int, int]:
    """(forward, backward) lanes. lanes:forward/backward win; otherwise an odd
    lane count gives the extra lane to the forward direction."""
    lanes = styles.road_lanes(tags)
    if oneway:
        return max(1, lanes), 0
    fwd, back = _int(tags.get("lanes:forward")), _int(tags.get("lanes:backward"))
    if fwd and back:
        return fwd, back
    if fwd:
        return fwd, max(1, lanes - fwd)
    if back:
        return max(1, lanes - back), back
    back = max(1, lanes // 2)
    return max(1, lanes - back), back


def drives(tags) -> bool:
    return tags.get("highway") in TRAFFIC_KINDS and tags.get("access") not in NO_CARS \
        and tags.get("motor_vehicle") not in NO_CARS


def _bike_lane(tags) -> bool:
    """A painted bike lane on the carriageway (cycleway=lane, either side)."""
    return any(tags.get(k) in ("lane", "shared_lane") for k in
               ("cycleway", "cycleway:both", "cycleway:left", "cycleway:right"))


def _speed(tags):
    m = re.match(r"\s*(\d+)", tags.get("maxspeed", ""))
    return int(m.group(1)) if m else None


def _path(w) -> dict:
    """A foot or bike path for the traffic data: Godot points, its name, and
    the plan midpoint that decides which tile carries it."""
    return {"pts": np.column_stack([w.xy[:, 0], w.h + 0.05, -w.xy[:, 1]]).astype(np.float32),
            "name": w.tags.get("name", ""), "_mid": tuple(w.xy[len(w.xy) // 2]), "_way": w}


def _densify(pts, step: float):
    """pts with extra points so no segment is longer than `step` (float64)."""
    pts = np.asarray(pts, dtype=np.float64)
    out = [pts[:1]]
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(np.ceil(np.linalg.norm(b[[0, 2]] - a[[0, 2]]) / step)))
        t = (np.arange(1, n + 1) / n)[:, None]
        out.append(a + (b - a) * t)
    return np.concatenate(out)


def _tangents(xyz):
    d = np.gradient(xyz[:, [0, 2]], axis=0)
    return d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)


class TrafficNetwork:
    """Built once per build from the World; tile_data() slices it."""

    def __init__(self, world):
        self.w = world
        hf = world.hf
        ways = [w for w in world.ways if w.group == "road" and drives(w.tags)]
        ctrl_tags = {int(nid): t for nid, t, _, _ in world.control_nodes}
        # Where ways must be split: junctions plus give-way/stop nodes.
        split = set(world.junctions)
        for nid, t in ctrl_tags.items():
            if t.get("highway") in ("give_way", "stop"):
                split.add(nid)
        self.ctrl: dict[int, str] = {}
        for nid, t in ctrl_tags.items():
            hw = t.get("highway")
            if hw in ("give_way", "stop"):
                self.ctrl[nid] = hw
        self.pos: dict[int, tuple] = {}
        self.roads = []  # dicts in TRAFFIC.md form, plus "_mid": (e, n)
        for w in ways:
            nodes = [int(n) for n in w.nodes]
            seg = np.linalg.norm(np.diff(w.xy, axis=0), axis=1)
            s = np.concatenate([[0.0], np.cumsum(seg)])
            # Signals on this way snap to the nearest junction within reach.
            for k, n in enumerate(nodes):
                if ctrl_tags.get(n, {}).get("highway") != "traffic_signals":
                    continue
                if n in world.junctions:
                    self.ctrl[n] = "signals"
                    continue
                best = None
                for kk, m in enumerate(nodes):
                    if m in world.junctions and abs(s[kk] - s[k]) <= SIGNAL_REACH:
                        if best is None or abs(s[kk] - s[k]) < abs(s[best] - s[k]):
                            best = kk
                if best is not None:
                    self.ctrl[nodes[best]] = "signals"
            cuts = [0] + [k for k in range(1, len(nodes) - 1) if nodes[k] in split] + [len(nodes) - 1]
            reverse = w.tags.get("oneway") == "-1"
            oneway = styles.is_oneway(w.tags) or reverse
            fwd, back = lane_split(w.tags, oneway)
            speed = _speed(w.tags)
            for part, (k0, k1) in enumerate(zip(cuts[:-1], cuts[1:])):
                xy = w.xy[k0:k1 + 1]
                h = w.h[k0:k1 + 1]
                a, b = nodes[k0], nodes[k1]
                if reverse:
                    xy, h, a, b = xy[::-1], h[::-1], b, a
                pts = np.column_stack([xy[:, 0], h, -xy[:, 1]]).astype(np.float32)
                for k in (k0, k1):
                    self.pos[nodes[k]] = (float(w.xy[k, 0]), float(w.h[k]), float(-w.xy[k, 1]))
                mid_s = (s[k0] + s[k1]) / 2
                r = {
                    "a": a, "b": b, "pts": pts,
                    "kind": w.tags["highway"],
                    "lanes_fwd": fwd, "lanes_back": back,
                    "oneway": oneway,
                    "roundabout": w.tags.get("junction") == "roundabout",
                    "width": round(float(w.width), 2),
                    "sidewalks": bool(w.sidewalk),
                    "id": f"w{w.id}/{part}",
                    "_mid": (float(np.interp(mid_s, s, w.xy[:, 0])), float(np.interp(mid_s, s, w.xy[:, 1]))),
                }
                if speed:
                    r["speed_kmh"] = speed
                if "name" in w.tags:
                    r["name"] = w.tags["name"]
                if _bike_lane(w.tags):
                    r["bike_lane"] = True
                self.roads.append(r)
        self._spread_signals(ways)
        self.separate_carriageways()
        self.parking = Parking(world, self.roads)
        # Bus routes: OSM route=bus relations as the road pieces they use.
        parts: dict[int, list[str]] = {}
        for r in self.roads:
            parts.setdefault(int(r["id"][1:].split("/")[0]), []).append(r["id"])
        self.bus_routes = []
        for rid, ref, name, colour, way_ids in getattr(world, "bus_routes", []):
            ids = [pid for w in way_ids for pid in parts.get(int(w), [])]
            if ids:
                self.bus_routes.append({"ref": ref or f"r{rid}", "name": name or ref, "colour": colour,
                                        "roads": ids})
        self._road_mid = {r["id"]: r["_mid"] for r in self.roads}
        self.rails = [w for w in world.ways if w.group == "rail" and w.tags.get("railway") == "rail"]
        self.stations = []
        self.bus_stops = []
        self.keep_clear = self._home_exits()
        self.footways = self._event_footways()
        self.footways += self._city_footways({id(f["_way"]) for f in self.footways})
        self.cycleways = self._cycleways()
        nj, ni = hf.H.shape
        self.schools = []
        schools = [(t, e, n) for _, t, e, n in world.poi_nodes if t.get("amenity") == "school"]
        for a in world.poi_areas:
            if a.tags.get("amenity") == "school":
                c = a.geom.representative_point()
                schools.append((a.tags, c.x, c.y))
        for t, e, n in schools:
            if hf.e0 <= e <= hf.e0 + hf.step * (ni - 1) and hf.n0 <= n <= hf.n0 + hf.step * (nj - 1):
                self.schools.append((e, n, float(hf.sample(e, n)), t.get("name", "")))
        for nid, t, e, n in world.control_nodes:
            if not (hf.e0 <= e <= hf.e0 + hf.step * (ni - 1) and hf.n0 <= n <= hf.n0 + hf.step * (nj - 1)):
                continue
            y = float(hf.sample(e, n))
            if t.get("railway") in ("station", "halt"):
                self.stations.append((e, n, y, t.get("name", "")))
            elif t.get("highway") == "bus_stop":
                self.bus_stops.append((e, n, y))

    def _home_exits(self) -> list:
        """Where the lanes beside the townhouse (front lane and carport lane) meet
        traffic roads: kept clear so the player can always pull out."""
        home = getattr(self.w, "home", None)
        if home is None:
            return []
        ends = {r["a"] for r in self.roads} | {r["b"] for r in self.roads}
        out = []
        for w in self.w.ways:
            if w.group != "road" or w.tags.get("highway") != "service" \
                    or LineString(w.xy).distance(home.footprint) > 5.0:
                continue
            for nid in w.nodes:
                nid = int(nid)
                if nid in ends and self.pos[nid] not in out:
                    out.append(self.pos[nid])
        return out

    def _event_footways(self) -> list:
        """Paths for event-day crowds (docs/TRAFFIC.md "footways"): every footpath
        within STADIUM_WALK of Optus Stadium, the Matagarup Bridge, and the paths
        meeting the bridge at either end."""
        lms = {lm.id: lm for lm in getattr(self.w, "landmarks", [])}
        if "optus_stadium" not in lms:
            return []
        stadium = Point(*lms["optus_stadium"].center)
        foot = [w for w in self.w.ways if w.group == "foot" and len(w.xy) > 1]
        bridge = [w for w in foot if w.tags.get("name") == "Matagarup Bridge"]
        ends = [Point(*w.xy[k]) for w in bridge for k in (0, -1)]
        out = []
        for w in foot:
            line = LineString(w.xy)
            if w in bridge or line.distance(stadium) < STADIUM_WALK or \
                    any(line.distance(p) < BRIDGE_APPROACH for p in ends):
                out.append(_path(w))
        return out

    def _city_footways(self, taken) -> list:
        """Malls, plazas and footpaths in the CBD and Northbridge (not the
        sidewalks drawn along roads, which walkers already use)."""
        e0, n0, e1, n1 = CITY_WALK
        out = []
        for w in self.w.ways:
            t = w.tags
            if w.group != "foot" or len(w.xy) < 2 or id(w) in taken or t.get("highway") not in CITY_FOOT:
                continue
            if t.get("footway") == "sidewalk" or t.get("access") in NO_CARS:
                continue
            e, n = w.xy[len(w.xy) // 2]
            if e0 <= e < e1 and n0 <= n < n1:
                f = _path(w)
                if t.get("highway") == "pedestrian":
                    f["kind"] = "mall"
                out.append(f)
        return out

    def _cycleways(self) -> list:
        """Bike paths and shared paths (highway=cycleway, or a path or footway
        signed for bikes), for cyclists riding off the road."""
        out = []
        for w in self.w.ways:
            t = w.tags
            if w.group != "foot" or len(w.xy) < 2:
                continue
            hw = t.get("highway")
            if hw == "cycleway" or (hw in ("path", "footway") and t.get("bicycle") in ("designated", "yes")
                                    and t.get("footway") != "sidewalk"):
                out.append(_path(w))
        return out

    def _spread_signals(self, ways):
        """Dual carriageways cross as two or four junction nodes a few metres
        apart; OSM often tags only one. Give their neighbours along the road
        the same lights so both halves run one cycle."""
        junctions = self.w.junctions
        add = set()
        for w in ways:
            nodes = [int(n) for n in w.nodes]
            seg = np.linalg.norm(np.diff(w.xy, axis=0), axis=1)
            s = np.concatenate([[0.0], np.cumsum(seg)])
            js = [k for k, n in enumerate(nodes) if n in junctions]
            for k in js:
                if self.ctrl.get(nodes[k]) != "signals":
                    continue
                for kk in js:
                    if kk != k and abs(s[kk] - s[k]) <= SIGNAL_SPREAD:
                        add.add(nodes[kk])
        for n in add:
            self.ctrl[n] = "signals"

    def separate_carriageways(self, passes: int = 1, step: float = 3.0) -> int:
        """Dual carriageways are mapped as two one-way ways whose centre lines
        can sit closer than their lanes need (Barrack St at the Esplanade is
        6.5 m apart for five 3.2 m lanes), so opposing cars overlap. Push each
        side away from the other until the lanes clear. Junction nodes move
        with the average of what their roads ask for, so roads still meet.
        Returns how many roads moved."""
        from scipy.spatial import cKDTree
        ow = [r for r in self.roads if r["oneway"] and not r["roundabout"]]
        if len(ow) < 2:
            return 0
        work = [_densify(r["pts"], step) for r in ow]
        lanes = np.array([r["lanes_fwd"] for r in ow])
        touched = np.zeros(len(ow), bool)
        ends_of = [{r["a"], r["b"]} for r in ow]
        # Two sides of one street share its name; a different street close by
        # (a ramp, a parallel service road) is left where OSM puts it.
        names = [r.get("name", "") for r in ow]
        node_moves: dict[int, np.ndarray] = {}
        for _ in range(passes):
            P = np.concatenate(work)
            O = np.concatenate([np.full(len(w), k) for k, w in enumerate(work)])
            T = np.concatenate([_tangents(w) for w in work])
            tree = cKDTree(P[:, [0, 2]])
            reach = lanes.max() * LANE_WIDTH + CARRIAGEWAY_GAP
            push = np.zeros((len(P), 2))
            for i, near in enumerate(tree.query_ball_point(P[:, [0, 2]], reach)):
                best = None
                for j in near:
                    if O[j] == O[i] or names[O[i]] != names[O[j]] or T[i] @ T[j] > -0.9 \
                            or abs(P[i, 1] - P[j, 1]) > 2.5:
                        continue
                    # Where the two sides split from or join one node they
                    # are meant to converge.
                    shared = ends_of[O[i]] & ends_of[O[j]]
                    if any(np.hypot(*(P[i, [0, 2]] - self._xz(n))) < MERGE_ZONE for n in shared):
                        continue
                    need = (lanes[O[i]] + lanes[O[j]]) * LANE_WIDTH / 2 + CARRIAGEWAY_GAP
                    off = P[i, [0, 2]] - P[j, [0, 2]]
                    side = off - (off @ T[i]) * T[i]  # across the road only
                    dist = np.linalg.norm(side)
                    if dist < 1e-3 or dist >= need:
                        continue
                    want = min(need - dist, MAX_SHIFT) / 2 * side / dist
                    if best is None or want @ want > best @ best:
                        best = want
                if best is not None:
                    push[i] = best
            if not push.any():
                break
            ends: dict[int, list] = {}
            base = 0
            for k, (r, w) in enumerate(zip(ow, work)):
                n = len(w)
                ends.setdefault(r["a"], []).append(push[base])
                ends.setdefault(r["b"], []).append(push[base + n - 1])
                inner = push[base + 1:base + n - 1]
                if inner.any():
                    touched[k] = True
                    w[1:-1, 0] += inner[:, 0]
                    w[1:-1, 2] += inner[:, 1]
                base += n
            # Shared ends move once per node, on every road that uses them.
            users: dict[int, list] = {}
            for k, r in enumerate(ow):
                users.setdefault(r["a"], []).append((k, 0))
                users.setdefault(r["b"], []).append((k, -1))
            for nid, v in ends.items():
                mv = np.mean(v, axis=0)
                if not mv.any():
                    continue
                node_moves[nid] = node_moves.get(nid, 0) + mv
                for k, idx in users[nid]:
                    work[k][idx, 0] += mv[0]
                    work[k][idx, 2] += mv[1]
                    touched[k] = True
        for k, r in enumerate(ow):
            if touched[k]:
                r["pts"] = work[k].astype(np.float32)
        for nid, mv in node_moves.items():
            x, y, z = self.pos[nid]
            self.pos[nid] = (x + float(mv[0]), y, z + float(mv[1]))
        moved_nodes = set(node_moves)
        for r in self.roads:
            if r["oneway"] and not r["roundabout"]:
                continue
            for end, idx in ((r["a"], 0), (r["b"], -1)):
                if end in moved_nodes:
                    r["pts"][idx, 0], r["pts"][idx, 2] = self.pos[end][0], self.pos[end][2]
        return int(touched.sum())

    def _xz(self, nid):
        x, _, z = self.pos[nid]
        return np.array([x, z])

    def tile_data(self, bounds) -> dict:
        e0, n0, e1, n1 = bounds

        def inside(e, n):
            return e0 <= e < e1 and n0 <= n < n1

        roads = [r for r in self.roads if inside(*r["_mid"])]
        ids = set()
        for r in roads:
            ids.update((r["a"], r["b"]))
        nodes = [{"id": i, "p": np.array(self.pos[i], dtype=np.float32), "ctrl": self.ctrl.get(i, "")}
                 for i in sorted(ids)]
        rail = []
        for w in self.rails:
            mid = (w.xy[:-1] + w.xy[1:]) / 2
            on = (mid[:, 0] >= e0) & (mid[:, 0] < e1) & (mid[:, 1] >= n0) & (mid[:, 1] < n1)
            k = 0
            while k < len(on):
                if not on[k]:
                    k += 1
                    continue
                a = k
                while k < len(on) and on[k]:
                    k += 1
                xy, h = w.xy[a:k + 1], w.h[a:k + 1]
                rail.append({"pts": np.column_stack([xy[:, 0], h, -xy[:, 1]]).astype(np.float32)})
        data = {
            "nodes": nodes,
            "roads": [{k: v for k, v in r.items() if k != "_mid"} for r in roads],
            "rail": rail,
            "stations": [{"p": np.array([e, y, -n], dtype=np.float32), "name": name}
                         for e, n, y, name in self.stations if inside(e, n)],
            "bus_stops": [{"p": np.array([e, y, -n], dtype=np.float32)}
                          for e, n, y in self.bus_stops if inside(e, n)],
            "parking": self.parking.tile_data(bounds),
            "schools": [{"p": np.array([e, y, -n], dtype=np.float32), "name": name}
                        for e, n, y, name in self.schools if inside(e, n)],
            "keep_clear": [{"p": np.array(p, dtype=np.float32), "radius": 6.0}
                           for p in self.keep_clear if inside(p[0], -p[2])],
            "bus_routes": self._bus_routes_in(inside),
        }
        footways = [{k: v for k, v in f.items() if k not in ("_mid", "_way") and (k != "name" or v)}
                    for f in self.footways if inside(*f["_mid"])]
        if footways:  # only near the stadium and in the city, so most tiles go without the key
            data["footways"] = footways
        cycleways = [{k: v for k, v in f.items() if k not in ("_mid", "_way") and (k != "name" or v)}
                     for f in self.cycleways if inside(*f["_mid"])]
        if cycleways:
            data["cycleways"] = cycleways
        return data

    def _bus_routes_in(self, inside) -> list:
        """Each route's pieces that lie in this tile; tiles join them by ref.
        One OSM route usually has a relation per direction, so merge by ref."""
        out: dict[str, dict] = {}
        for br in self.bus_routes:
            ids = [i for i in br["roads"] if inside(*self._road_mid[i])]
            if not ids:
                continue
            e = out.setdefault(br["ref"], {"ref": br["ref"], "name": br["name"], "colour": br["colour"], "roads": []})
            e["roads"].extend(i for i in ids if i not in e["roads"])
        return list(out.values())
