"""Road data for the traffic system (docs/TRAFFIC.md), one file per tile.

Ways are split at junctions and at give-way/stop nodes so every road runs
between two graph nodes, keyed by OSM node ids so pieces in neighbouring
tiles join up. Signals tagged just before a junction move onto it.
"""
from __future__ import annotations

import re

import numpy as np

from . import styles

TRAFFIC_KINDS = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
    "residential", "living_street",
}
SIGNAL_REACH = 35.0  # metres along a way a signal tag may sit from its junction
SIGNAL_SPREAD = 30.0  # junctions this close along a road share one set of lights
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


def _speed(tags):
    m = re.match(r"\s*(\d+)", tags.get("maxspeed", ""))
    return int(m.group(1)) if m else None


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
                self.roads.append(r)
        self._spread_signals(ways)
        self.rails = [w for w in world.ways if w.group == "rail" and w.tags.get("railway") == "rail"]
        self.stations = []
        self.bus_stops = []
        nj, ni = hf.H.shape
        for nid, t, e, n in world.control_nodes:
            if not (hf.e0 <= e <= hf.e0 + hf.step * (ni - 1) and hf.n0 <= n <= hf.n0 + hf.step * (nj - 1)):
                continue
            y = float(hf.sample(e, n))
            if t.get("railway") in ("station", "halt"):
                self.stations.append((e, n, y, t.get("name", "")))
            elif t.get("highway") == "bus_stop":
                self.bus_stops.append((e, n, y))

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
        return {
            "nodes": nodes,
            "roads": [{k: v for k, v in r.items() if k != "_mid"} for r in roads],
            "rail": rail,
            "stations": [{"p": np.array([e, y, -n], dtype=np.float32), "name": name}
                         for e, n, y, name in self.stations if inside(e, n)],
            "bus_stops": [{"p": np.array([e, y, -n], dtype=np.float32)}
                          for e, n, y in self.bus_stops if inside(e, n)],
        }
