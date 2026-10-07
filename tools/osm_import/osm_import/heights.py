"""Vertical alignment of roads, rail and paths.

Every node of a linear network gets a height. Ground-level ways follow the
(smoothed) terrain; bridges are lifted to clear what is under them, tunnels and
cuttings are sunk, and the change is spread along connected ways at a maximum
grade so approaches become ramps.
"""
from __future__ import annotations

import heapq
from collections import defaultdict
from dataclasses import replace

import numpy as np
from scipy import sparse
from scipy.sparse.linalg import spsolve

from . import styles
from .terrain import HeightField

GRADE = {"road": 0.06, "rail": 0.03, "foot": 0.10}
SERVICE_GRADE = 0.12
BRIDGE_CLEARANCE = {"road": 6.0, "rail": 6.5, "foot": 5.5}
TUNNEL_DEPTH = {"road": 7.5, "rail": 9.0, "foot": 4.0}
# Least ground over a tunnel's floor between its portals: the tunnel box
# (build.TUNNEL_HEIGHT plus its roof) has to fit under the road on top, or the
# ground over it is cut away and the road above drops onto the tunnel roof.
TUNNEL_COVER = {"road": 8.0, "rail": 9.0, "foot": 2.4}
# How far along a way its profile is smoothed (metres). The DEM is a 30 m
# surface model with buildings and trees in it: roads take out bumps up to a
# few hundred metres long, rail is smoother still.
SMOOTH_LENGTH = {"road": 30.0, "rail": 60.0, "foot": 15.0}
DENSE_STEP = 5.0         # metres between solved heights along a way
COUPLE_LENGTH = 2.0      # a carriageway's tie to the one beside it acts like this much road
# Deck to the road under it: clearance for a truck plus the deck's thickness.
HEADROOM = {"road": 5.6, "rail": 6.2, "foot": 3.6}
FINISH_LENGTH = 8.0      # metres of the last smoothing pass, after the bounds
HEADROOM_GRADE = 0.12    # steepest a ramp gets where it has to dip under a bridge
REACH = 30.0             # bridge/tunnel bounds stop spreading this far past the ground
VIRTUAL_BASE = 1 << 50   # ids of nodes added by densify_ways: -(VIRTUAL_BASE + k)


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


# Ways within this angle of a bridge's line run beside it, not under it.
PARALLEL_COS = float(np.cos(np.radians(25.0)))


def _keep_headroom(group: str, ways, index, xy, lo):
    """A way passing under a bridge of its own network stays low enough to
    clear it: the DEM often has the underpass dip, and smoothing would fill
    it in. Returns an upper bound for the nodes under each bridge span (the
    ends of the span, where the approaches join, are left alone)."""
    from scipy.spatial import cKDTree
    head = np.full(len(xy), 1e9)
    under = []
    way_of = {}
    heading = {}
    for wi, w in enumerate(ways):
        if not styles.is_bridge(w.tags) and not styles.is_tunnel(w.tags):
            c = w.coords
            for i, n in enumerate(w.nodes):
                under.append(index[int(n)])
                way_of.setdefault(index[int(n)], set()).add(wi)
                t = c[min(i + 1, len(c) - 1)] - c[max(i - 1, 0)]
                heading.setdefault(index[int(n)], []).append(t / max(np.linalg.norm(t), 1e-9))
    if not under:
        return head
    under = np.unique(np.array(under))
    tree = cKDTree(xy[under])
    node_ways = {}
    for wi, w in enumerate(ways):
        for n in w.nodes:
            node_ways.setdefault(index[int(n)], set()).add(wi)
    for w in ways:
        if not styles.is_bridge(w.tags) or len(w.coords) < 3:
            continue
        half = _width(group, w.tags) / 2 + 3.0
        span = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.coords, axis=0), axis=1))])
        ends = np.array([w.coords[0], w.coords[-1]])
        k_idx = np.array([index[int(n)] for n in w.nodes])
        # Ways joined to the span are its approaches or slip roads leaving
        # it, not under it.
        joined = set().union(*(node_ways.get(k, set()) for k in k_idx))
        for k in range(1, len(w.coords) - 1):
            if span[k] < half or span[-1] - span[k] < half:
                continue
            t = w.coords[k + 1] - w.coords[k - 1]
            t = t / max(np.linalg.norm(t), 1e-9)
            for j in tree.query_ball_point(w.coords[k], half):
                node = under[j]
                if way_of[node] & joined or np.min(np.linalg.norm(ends - xy[node], axis=1)) < half:
                    continue
                # A way running alongside the deck (a slip road climbing
                # beside the other carriageway) is beside it, not under it.
                if all(abs(float(t @ u)) > PARALLEL_COS for u in heading[node]):
                    continue
                head[node] = min(head[node], lo[k_idx[k]] - HEADROOM[group])
    return head


def _width(group: str, tags) -> float:
    if group == "road":
        return styles.road_width(tags)
    return {"rail": 3.2, "foot": 2.0}[group]


def _grade(group: str, tags) -> float:
    """Steepest ramp allowed on a way (car park and bus station ramps are steep)."""
    if group == "road" and tags.get("highway") == "service":
        return SERVICE_GRADE
    return GRADE[group]


def _way_length(coords) -> float:
    return float(np.linalg.norm(np.diff(coords, axis=0), axis=1).sum())


def compute_node_heights(ways, hf: HeightField, couple=(), tie=()) -> dict[str, dict[int, float]]:
    """Heights of every node of the road, rail and path networks. `couple`
    lists (node, node) pairs that should end up level with each other (the
    two carriageways of a divided road). `tie` pairs are held level through
    every pass, not just the first (halves of a street across a median, which
    the side streets at a crossroads would otherwise pull apart)."""
    out: dict[str, dict[int, float]] = {}
    by_group = defaultdict(list)
    for w in ways:
        g = way_group(w.tags)
        if g:
            by_group[g].append(w)
    for g, ws in by_group.items():
        out[g] = _solve_group(g, ws, hf, couple if g == "road" else (), tie if g == "road" else ())
    return out


def densify_ways(ways, step: float = DENSE_STEP):
    """Ways of the linear networks with extra nodes so no segment is longer
    than `step`. Heights are solved at every node, so a road's profile curves
    smoothly between OSM nodes that may be 100 m apart instead of running in
    straight chords from one noisy sample to the next. Added nodes get
    negative ids of their own."""
    out = []
    serial = 0
    for w in ways:
        if not way_group(w.tags) or len(w.coords) < 2:
            out.append(w)
            continue
        seg = np.linalg.norm(np.diff(w.coords, axis=0), axis=1)
        cuts = np.maximum(1, np.ceil(seg / step).astype(int))
        if (cuts == 1).all():
            out.append(w)
            continue
        xy, ids = [w.coords[:1]], [w.nodes[:1]]
        for k, n in enumerate(cuts):
            t = np.arange(1, n + 1) / n
            xy.append(w.coords[k] + t[:, None] * (w.coords[k + 1] - w.coords[k]))
            extra = -(VIRTUAL_BASE + serial + np.arange(n - 1, dtype=np.int64))
            serial += n - 1
            ids.append(np.concatenate([extra, w.nodes[k + 1:k + 2]]))
        out.append(replace(w, coords=np.concatenate(xy), nodes=np.concatenate(ids).astype(np.int64)))
    return out


def _smooth(h0, a, b, d, length, fixed=None, fixed_h=None):
    """Smooth heights along the network over about `length` metres.

    Solves (M + t L) h = M h0 on the graph (L the edge Laplacian with weights
    1/d, M each node's share of way length, t = length^2): an implicit
    diffusion that measures distance in metres along the ways, however densely
    OSM placed the nodes. Junctions share their node, so every arm meets at
    one height. `fixed` nodes keep `fixed_h`."""
    n = len(h0)
    w = 1.0 / d
    t = length * length
    L = sparse.coo_matrix((np.concatenate([-w, -w]), (np.concatenate([a, b]), np.concatenate([b, a]))),
                          shape=(n, n)).tocsr()
    L = L - sparse.diags(np.asarray(L.sum(axis=1)).ravel())  # positive semi-definite
    mass = np.zeros(n)
    np.add.at(mass, a, d / 2)
    np.add.at(mass, b, d / 2)
    mass = np.maximum(mass, 1e-3)
    A = (sparse.diags(mass) + t * L).tocsr()
    rhs = mass * h0
    if fixed is None or not fixed.any():
        return spsolve(A.tocsc(), rhs)
    free = ~fixed
    h = np.array(h0, dtype=np.float64)
    h[fixed] = fixed_h[fixed]
    Aff = A[free][:, free]
    Afc = A[free][:, fixed]
    h[free] = spsolve(Aff.tocsc(), rhs[free] - Afc @ h[fixed])
    return h


def _solve_group(group: str, ways, hf: HeightField, couple=(), tie=()) -> dict[int, float]:
    index: dict[int, int] = {}
    pos = []
    ea, eb, ed, eg = [], [], [], []
    for w in ways:
        k_idx = []
        for k, nid in enumerate(w.nodes):
            nid = int(nid)
            if nid not in index:
                index[nid] = len(pos)
                pos.append(w.coords[k])
            k_idx.append(index[nid])
        if len(k_idx) > 1:
            d = np.linalg.norm(np.diff(w.coords, axis=0), axis=1)
            ea.extend(k_idx[:-1])
            eb.extend(k_idx[1:])
            ed.extend(d.tolist())
            eg.extend([_grade(group, w.tags)] * len(d))
    ids = list(index)
    xy = np.array(pos)
    a, b, d = np.array(ea, dtype=np.int64), np.array(eb, dtype=np.int64), np.maximum(np.array(ed), 0.05)
    eg = np.array(eg)
    keep = a != b
    a, b, d, eg = a[keep], b[keep], d[keep], eg[keep]
    # Two carriageways of one street: tie each node to the one beside it.
    # Ties come first and take part in every pass; couples only in the first.
    for pp in (tie, couple):
        if pp is couple:
            n_own = len(a)
        ca = [index[i] for i, j in pp if i in index and j in index]
        cb = [index[j] for i, j in pp if i in index and j in index]
        if ca:
            a = np.concatenate([a, ca])
            b = np.concatenate([b, cb])
            d = np.concatenate([d, np.full(len(ca), COUPLE_LENGTH)])
            eg = np.concatenate([eg, np.full(len(ca), GRADE[group])])
    base = hf.sample(xy[:, 0], xy[:, 1])
    # Bounds spread along the roads themselves (and the ties), never across a
    # couple: a slip road climbing beside the freeway must not be pulled down
    # by the headroom the freeway keeps under a bridge, nor lift the freeway.
    adj: dict[int, dict[int, tuple]] = defaultdict(dict)
    for i, j, dd, gg in zip(a[:n_own].tolist(), b[:n_own].tolist(), d[:n_own].tolist(), eg[:n_own].tolist()):
        adj[i][j] = adj[j][i] = (dd, gg)

    n = len(ids)
    lo = np.full(n, -1e9)
    hi = np.full(n, 1e9)
    for w in ways:
        t = w.tags
        lyr = styles.layer(t)
        k_idx = np.array([index[int(nid)] for nid in w.nodes])
        if styles.is_bridge(t):
            short = _way_length(w.coords) < 15.0
            clr = 1.0 if short else BRIDGE_CLEARANCE[group] + 5.0 * max(0, lyr - 1)
            # Clear the lowest ground anywhere under the span, not just at nodes.
            span_min = float(base[k_idx].min())
            under = np.linspace(0, 1, 9)
            pts = w.coords[0] + under[:, None] * (w.coords[-1] - w.coords[0])
            span_min = min(span_min, float(hf.sample(pts[:, 0], pts[:, 1]).min()))
            lo[k_idx] = np.maximum(lo[k_idx], np.maximum(base[k_idx], span_min) + clr)
        elif styles.is_tunnel(t):
            # Portals sit `depth` below ground; in between the tunnel runs straight
            # (not following surface bumps) but always keeps some cover.
            depth = TUNNEL_DEPTH[group] + 4.0 * max(0, -lyr - 1)
            h0, h1 = base[k_idx[0]] - depth, base[k_idx[-1]] - depth
            dist = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(w.coords, axis=0), axis=1))])
            frac = dist / max(dist[-1], 1e-6)
            lerp = h0 + (h1 - h0) * frac
            cover = max(0.6 * depth, TUNNEL_COVER[group])
            hi[k_idx] = np.minimum(hi[k_idx], np.minimum(lerp, base[k_idx] - cover))
        elif t.get("cutting") in ("yes", "both", "left", "right"):
            hi[k_idx] = np.minimum(hi[k_idx], base[k_idx] - 4.0)
        elif t.get("embankment") in ("yes", "both", "left", "right"):
            lo[k_idx] = np.maximum(lo[k_idx], base[k_idx] + 2.5)

    head = _keep_headroom(group, ways, index, xy, lo)
    on_bridge = np.zeros(n, dtype=bool)
    for w in ways:
        if styles.is_bridge(w.tags):
            on_bridge[[index[int(nid)] for nid in w.nodes]] = True
    lo = _propagate(lo, adj, raise_=True, floor=base - REACH)
    hi = _propagate(hi, adj, raise_=False, floor=base + REACH)
    hi = np.maximum(hi, lo)
    # Smooth the DEM along the network (bumps from noise and from buildings
    # left in the surface model). Then bridges, tunnels and cuttings take
    # their bounds (with ramps at the grade limit) and the result is smoothed
    # again, which rounds the foot and top of each ramp. Smoothing can pull a
    # deck below its clearance or steepen a ramp, so last the bounds are put
    # back as cones at the grade limit from the bound nodes.
    # The ties between neighbouring roads only take part in the first pass:
    # a street must not be dragged up a bridge ramp that runs beside it.
    length = SMOOTH_LENGTH[group]
    h = _smooth(base, a, b, d, length)
    own = np.arange(len(a)) < n_own
    h = _smooth(np.clip(np.minimum(h, head), lo, hi), a[own], b[own], d[own], length)
    # The bounds go back on as cones, then once more after a light smoothing
    # that rounds the corners where a cone meets the smoothed profile.
    for k in range(2):
        if k:
            h = _smooth(h, a[own], b[own], d[own], FINISH_LENGTH)
        h = _apply_bounds(h, lo, hi, head, adj, on_bridge)
    hs = h
    return {nid: float(hs[k]) for k, nid in enumerate(ids)}


def _apply_bounds(h, lo, hi, head, adj, on_bridge):
    """Push `h` back inside the bounds, easing in and out at the grade limit."""
    if (lo > -1e8).any():
        src = np.where(lo > -1e8, np.maximum(h, lo), -1e9)
        h = np.maximum(h, _propagate(src, adj, raise_=True, floor=h))
    if (hi < 1e8).any():
        src = np.where(hi < 1e8, np.minimum(h, hi), 1e9)
        h = np.minimum(h, _propagate(src, adj, raise_=False, floor=h))
    if (head < 1e8).any():
        # Headroom under bridges wins over a bridge's approach ramp running
        # down to the street below (the ramp just gets steeper near the
        # street), but never lowers a bridge itself.
        src = np.where(head < 1e8, np.minimum(h, head), 1e9)
        h = np.minimum(h, _propagate(src, adj, raise_=False, floor=np.where(on_bridge, -np.inf, h),
                                     grade=HEADROOM_GRADE))
    return h


def _propagate(bound: np.ndarray, adj, raise_: bool, floor: np.ndarray, grade=None) -> np.ndarray:
    """Spread lower (raise_) or upper bounds through the graph at each edge's max grade.
    A bound stops spreading once it is `REACH` past the ground (`floor`),
    where it can no longer matter."""
    sign = -1.0 if raise_ else 1.0
    out = bound.copy()
    active = np.nonzero(np.abs(bound) < 1e8)[0]
    heap = [(sign * out[i], int(i)) for i in active]
    heapq.heapify(heap)
    while heap:
        key, i = heapq.heappop(heap)
        v = sign * key
        if v != out[i]:
            continue
        for j, (d, g) in adj.get(i, {}).items():
            g = grade or g
            nv = v - g * d if raise_ else v + g * d
            if (raise_ and nv > out[j] and nv > floor[j]) or (not raise_ and nv < out[j] and nv < floor[j]):
                out[j] = nv
                heapq.heappush(heap, (sign * nv, j))
    return out
