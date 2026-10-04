"""Vertical alignment of roads, rail and paths.

Every node of a linear network gets a height. Ground-level ways follow the
(smoothed) terrain; bridges are lifted to clear what is under them, tunnels and
cuttings are sunk, and the change is spread along connected ways at a maximum
grade so approaches become ramps.
"""
from __future__ import annotations

import heapq
from collections import defaultdict

import numpy as np

from . import styles
from .terrain import HeightField

GRADE = {"road": 0.06, "rail": 0.03, "foot": 0.10}
BRIDGE_CLEARANCE = {"road": 6.0, "rail": 6.5, "foot": 5.5}
TUNNEL_DEPTH = {"road": 7.5, "rail": 9.0, "foot": 4.0}


def way_group(tags) -> str | None:
    hw = tags.get("highway")
    if hw in styles.DRIVABLE:
        return "road"
    if hw in styles.FOOT:
        return "foot"
    rw = tags.get("railway")
    if rw in ("rail", "light_rail", "narrow_gauge", "tram", "subway") and not tags.get("disused"):
        return "rail"
    return None


def _way_length(coords) -> float:
    return float(np.linalg.norm(np.diff(coords, axis=0), axis=1).sum())


def compute_node_heights(ways, hf: HeightField) -> dict[str, dict[int, float]]:
    out: dict[str, dict[int, float]] = {}
    by_group = defaultdict(list)
    for w in ways:
        g = way_group(w.tags)
        if g:
            by_group[g].append(w)
    for g, ws in by_group.items():
        out[g] = _solve_group(g, ws, hf)
    return out


def _solve_group(group: str, ways, hf: HeightField) -> dict[int, float]:
    pos: dict[int, tuple[float, float]] = {}
    adj: dict[int, dict[int, float]] = defaultdict(dict)
    for w in ways:
        for k, nid in enumerate(w.nodes):
            pos[int(nid)] = (w.coords[k, 0], w.coords[k, 1])
        d = np.linalg.norm(np.diff(w.coords, axis=0), axis=1)
        for k in range(len(w.nodes) - 1):
            a, b = int(w.nodes[k]), int(w.nodes[k + 1])
            if a != b:
                adj[a][b] = adj[b][a] = max(float(d[k]), 0.01)
    ids = list(pos)
    xy = np.array([pos[i] for i in ids])
    base = hf.sample(xy[:, 0], xy[:, 1])
    h = dict(zip(ids, base))

    # Smooth DEM noise along the network.
    for _ in range(6):
        nh = {}
        for i in ids:
            nb = adj.get(i)
            nh[i] = 0.5 * h[i] + 0.5 * (sum(h[j] for j in nb) / len(nb)) if nb else h[i]
        h = nh

    lo = {i: -1e9 for i in ids}
    hi = {i: 1e9 for i in ids}
    base_d = dict(zip(ids, base))
    for w in ways:
        t = w.tags
        lyr = styles.layer(t)
        if styles.is_bridge(t):
            short = _way_length(w.coords) < 15.0
            clr = 1.0 if short else BRIDGE_CLEARANCE[group] + 5.0 * max(0, lyr - 1)
            # Clear the lowest ground anywhere under the span, not just at nodes.
            span_min = min(base_d[int(n)] for n in w.nodes)
            under = np.linspace(0, 1, 9)
            pts = w.coords[0] + under[:, None] * (w.coords[-1] - w.coords[0])
            span_min = min(span_min, float(hf.sample(pts[:, 0], pts[:, 1]).min()))
            for n in w.nodes:
                n = int(n)
                lo[n] = max(lo[n], max(base_d[n], span_min) + clr)
        elif styles.is_tunnel(t):
            # Portals sit `depth` below ground; in between the tunnel runs straight
            # (not following surface bumps) but always keeps some cover.
            depth = TUNNEL_DEPTH[group] + 4.0 * max(0, -lyr - 1)
            n0, n1 = int(w.nodes[0]), int(w.nodes[-1])
            h0, h1 = base_d[n0] - depth, base_d[n1] - depth
            dist = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.coords, axis=0), axis=1))])
            frac = dist / max(dist[-1], 1e-6)
            for k, n in enumerate(w.nodes):
                n = int(n)
                lerp = h0 + (h1 - h0) * frac[k]
                hi[n] = min(hi[n], min(lerp, base_d[n] - 0.6 * depth))
        elif t.get("cutting") in ("yes", "both", "left", "right"):
            for n in w.nodes:
                n = int(n)
                hi[n] = min(hi[n], base_d[n] - 4.0)
        elif t.get("embankment") in ("yes", "both", "left", "right"):
            for n in w.nodes:
                n = int(n)
                lo[n] = max(lo[n], base_d[n] + 2.5)

    g = GRADE[group]
    lo = _propagate(lo, adj, g, raise_=True)
    hi = _propagate(hi, adj, g, raise_=False)
    # Constrained smoothing so profiles don't inherit terrain noise.
    for _ in range(12):
        nh = {}
        for i in ids:
            nb = adj.get(i)
            v = 0.5 * h[i] + 0.5 * (sum(h[j] for j in nb) / len(nb)) if nb else h[i]
            nh[i] = min(max(v, lo[i]), hi[i]) if hi[i] >= lo[i] else lo[i]
        h = nh
    res = {}
    for i in ids:
        v = h[i]
        if v < lo[i]:
            v = lo[i]
        if v > hi[i]:
            v = hi[i] if hi[i] >= lo[i] else lo[i]
        res[i] = float(v)
    return res


def _propagate(bound: dict, adj, grade: float, raise_: bool) -> dict:
    """Spread lower (raise_) or upper bounds through the graph at a max grade."""
    sign = -1.0 if raise_ else 1.0
    active = {i: v for i, v in bound.items() if abs(v) < 1e8}
    out = dict(bound)
    heap = [(sign * v, i) for i, v in active.items()]
    heapq.heapify(heap)
    while heap:
        key, i = heapq.heappop(heap)
        v = sign * key
        if v != out[i]:
            continue
        for j, d in adj.get(i, {}).items():
            nv = v - grade * d if raise_ else v + grade * d
            if (raise_ and nv > out[j]) or (not raise_ and nv < out[j]):
                out[j] = nv
                heapq.heappush(heap, (sign * nv, j))
    return out
