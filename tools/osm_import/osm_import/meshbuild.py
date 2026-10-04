"""Geometry primitives that turn 2D plan shapes into triangle meshes.

Conventions: plan coordinates (e, n), height h. Triangles are wound
counter-clockwise seen from outside, normals point outwards. tilewriter
converts to Godot's axes and winding.
"""
from __future__ import annotations

from collections import defaultdict

import mapbox_earcut as earcut
import numpy as np
import shapely
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

from .terrain import HeightField


class Surface:
    def __init__(self):
        self.v, self.nrm, self.uv, self.idx = [], [], [], []
        self.count = 0

    def add(self, v, nrm, uv, tris):
        v = np.asarray(v, dtype=np.float64).reshape(-1, 3)
        if len(v) == 0 or len(tris) == 0:
            return
        self.v.append(v)
        self.nrm.append(np.asarray(nrm, dtype=np.float64).reshape(-1, 3))
        self.uv.append(np.asarray(uv, dtype=np.float64).reshape(-1, 2))
        self.idx.append(np.asarray(tris, dtype=np.int64).reshape(-1, 3) + self.count)
        self.count += len(v)

    def arrays(self):
        if not self.v:
            return None
        return (np.concatenate(self.v), np.concatenate(self.nrm), np.concatenate(self.uv),
                np.concatenate(self.idx))


class MeshBuilder:
    """Groups surfaces by mesh name (one Godot MeshInstance each) and material."""

    def __init__(self):
        self.meshes: dict[str, dict[str, Surface]] = defaultdict(lambda: defaultdict(Surface))
        self.collision: dict[str, str | None] = {}

    def surface(self, mesh: str, material: str, collision: str | None) -> Surface:
        self.collision.setdefault(mesh, collision)
        return self.meshes[mesh][material]


# --- helpers -------------------------------------------------------------------

def polygons_of(geom) -> list[Polygon]:
    if geom is None or geom.is_empty:
        return []
    if geom.geom_type == "Polygon":
        return [geom]
    if hasattr(geom, "geoms"):
        out = []
        for g in geom.geoms:
            out.extend(polygons_of(g))
        return out
    return []


def triangulate(poly: Polygon) -> tuple[np.ndarray, np.ndarray]:
    """Earcut a polygon (with holes). Returns (verts (k,2), tris (m,3)) CCW."""
    poly = orient(poly, 1.0)
    rings = [np.asarray(poly.exterior.coords)[:-1]]
    rings += [np.asarray(r.coords)[:-1] for r in poly.interiors]
    rings = [r for r in rings if len(r) >= 3]
    if not rings:
        return np.zeros((0, 2)), np.zeros((0, 3), dtype=np.int64)
    verts = np.concatenate(rings)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    tris = earcut.triangulate_float64(verts, ends).reshape(-1, 3).astype(np.int64)
    if len(tris):
        a, b, c = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
        cross = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
        flip = cross < 0
        tris[flip] = tris[flip][:, [0, 2, 1]]
    return verts, tris


class CellGrid:
    """The ground grid cells of one tile, for clipping shapes so they follow terrain."""

    def __init__(self, hf: HeightField, bounds):
        e0, n0, e1, n1 = bounds
        s = hf.step
        self.hf = hf
        i0 = int(round((e0 - hf.e0) / s))
        j0 = int(round((n0 - hf.n0) / s))
        ni = int(round((e1 - e0) / s))
        nj = int(round((n1 - n0) / s))
        self.i0, self.j0, self.ni, self.nj = i0, j0, ni, nj
        # Two triangles per grid square (split like HeightField.sample), so
        # shapes clipped to these cells are flush with the ground mesh.
        ii, jj, tt = np.meshgrid(np.arange(ni), np.arange(nj), np.arange(2))
        self.ci, self.cj, self.ct = ii.ravel(), jj.ravel(), tt.ravel()
        x0 = hf.e0 + (i0 + self.ci) * s
        y0 = hf.n0 + (j0 + self.cj) * s
        x1, y1 = x0 + s, y0 + s
        lower = self.ct == 0
        coords = np.empty((len(x0), 4, 2))
        coords[:, 0] = np.column_stack([x0, y0])
        coords[:, 1] = np.where(lower[:, None], np.column_stack([x1, y0]), np.column_stack([x1, y1]))
        coords[:, 2] = np.where(lower[:, None], np.column_stack([x1, y1]), np.column_stack([x0, y1]))
        coords[:, 3] = coords[:, 0]
        self.cells = shapely.polygons(coords)
        self.tree = shapely.STRtree(self.cells)

    def node_xy(self, ci, cj):
        s = self.hf.step
        return self.hf.e0 + (self.i0 + ci) * s, self.hf.n0 + (self.j0 + cj) * s


def drape(surf: Surface, geom, grid: CellGrid, offset: float, uv_scale: float,
          skip_cells: np.ndarray | None = None):
    """Add `geom` as a surface lying `offset` above the terrain, split along grid cells."""
    polys = polygons_of(geom)
    if not polys:
        return
    geom = shapely.union_all(polys) if len(polys) > 1 else polys[0]
    shapely.prepare(geom)
    cand = grid.tree.query(geom, predicate="intersects")
    if skip_cells is not None and len(cand):
        cand = cand[~skip_cells[cand]]
    if len(cand) == 0:
        return
    full = shapely.contains_properly(geom, grid.cells[cand])
    hf = grid.hf
    # Whole cells share the grid's own vertices.
    fc = cand[full]
    if len(fc):
        ci, cj, ct = grid.ci[fc], grid.cj[fc], grid.ct[fc]
        stride = grid.ni + 1
        n00 = cj * stride + ci
        n10, n11, n01 = n00 + 1, n00 + stride + 1, n00 + stride
        lower = ct == 0
        corners = np.stack([n00, np.where(lower, n10, n11), np.where(lower, n11, n01)], axis=1)
        uniq, inv = np.unique(corners.ravel(), return_inverse=True)
        tris = inv.reshape(-1, 3)
        ui, uj = uniq % stride, uniq // stride
        x, y = grid.node_xy(ui, uj)
        h = hf.H[grid.j0 + uj, grid.i0 + ui] + offset
        v = np.column_stack([x, y, h])
        surf.add(v, hf.normal(x, y), np.column_stack([x, y]) / uv_scale, tris)
    # Partial cells get clipped and triangulated.
    pc = cand[~full]
    if len(pc):
        pieces = shapely.intersection(grid.cells[pc], geom)
        vs, ts, n = [], [], 0
        for piece in pieces:
            for p in polygons_of(piece):
                if p.area < 0.01:
                    continue
                pv, pt = triangulate(p)
                if len(pt):
                    vs.append(pv)
                    ts.append(pt + n)
                    n += len(pv)
        if vs:
            pv = np.concatenate(vs)
            h = hf.sample(pv[:, 0], pv[:, 1]) + offset
            surf.add(np.column_stack([pv, h]), hf.normal(pv[:, 0], pv[:, 1]), pv / uv_scale,
                     np.concatenate(ts))


def walls(surf: Surface, ring: np.ndarray, bottom, top, u_scale: float, v_scale: float,
          v_origin=None, closed: bool = True):
    """Vertical quads along a ring or polyline; faces point to the right of travel
    (outwards for a CCW ring)."""
    ring = np.asarray(ring, dtype=np.float64)
    k = len(ring)
    bottom = np.broadcast_to(np.asarray(bottom, dtype=np.float64), (k,))
    top = np.broadcast_to(np.asarray(top, dtype=np.float64), (k,))
    v_origin = bottom if v_origin is None else np.broadcast_to(np.asarray(v_origin, dtype=np.float64), (k,))
    if closed and k > 2 and np.allclose(ring[0], ring[-1]):
        ring, bottom, top, v_origin = ring[:-1], bottom[:-1], top[:-1], v_origin[:-1]
        k -= 1
    if k < 2:
        return
    a = ring
    b = np.roll(ring, -1, axis=0)
    ib = (np.arange(k) + 1) % k
    seg = b - a
    length = np.linalg.norm(seg, axis=1)
    ok = length > 0.05
    if not closed:
        ok[-1] = False
    a, b, seg, length = a[ok], b[ok], seg[ok], length[ok]
    ia, ib2 = np.arange(k)[ok], ib[ok]
    m = len(a)
    if m == 0:
        return
    u0 = np.concatenate([[0.0], np.cumsum(length)[:-1]])
    nrm = np.column_stack([seg[:, 1] / length, -seg[:, 0] / length, np.zeros(m)])
    v = np.empty((m, 4, 3))
    v[:, 0, :2], v[:, 0, 2] = a, bottom[ia]
    v[:, 1, :2], v[:, 1, 2] = b, bottom[ib2]
    v[:, 2, :2], v[:, 2, 2] = b, top[ib2]
    v[:, 3, :2], v[:, 3, 2] = a, top[ia]
    uv = np.empty((m, 4, 2))
    uv[:, 0, 0] = uv[:, 3, 0] = u0 / u_scale
    uv[:, 1, 0] = uv[:, 2, 0] = (u0 + length) / u_scale
    uv[:, 0, 1] = -(bottom[ia] - v_origin[ia]) / v_scale
    uv[:, 1, 1] = -(bottom[ib2] - v_origin[ib2]) / v_scale
    uv[:, 2, 1] = -(top[ib2] - v_origin[ib2]) / v_scale
    uv[:, 3, 1] = -(top[ia] - v_origin[ia]) / v_scale
    base = np.arange(m)[:, None] * 4
    tris = np.concatenate([base + [0, 1, 2], base + [0, 2, 3]])
    surf.add(v.reshape(-1, 3), np.repeat(nrm, 4, axis=0), uv.reshape(-1, 2), tris)


def flat_cap(surf: Surface, poly: Polygon, height: float, uv_scale: float, down: bool = False):
    pv, pt = triangulate(poly)
    if len(pt) == 0:
        return
    v = np.column_stack([pv, np.full(len(pv), height)])
    nrm = np.tile([0.0, 0.0, -1.0 if down else 1.0], (len(pv), 1))
    if down:
        pt = pt[:, [0, 2, 1]]
    surf.add(v, nrm, pv / uv_scale, pt)


def offset_polyline(xy: np.ndarray, offset: float) -> np.ndarray:
    """Offset a polyline sideways (positive = left) with mitred joins."""
    d = np.diff(xy, axis=0)
    ln = np.linalg.norm(d, axis=1, keepdims=True)
    ln[ln == 0] = 1
    d = d / ln
    nseg = np.column_stack([-d[:, 1], d[:, 0]])
    nv = np.empty_like(xy)
    nv[0], nv[-1] = nseg[0], nseg[-1]
    if len(xy) > 2:
        s = nseg[:-1] + nseg[1:]
        sl = np.linalg.norm(s, axis=1, keepdims=True)
        sl[sl < 1e-6] = 1
        s = s / sl
        cosang = np.clip((s * nseg[1:]).sum(axis=1, keepdims=True), 0.35, 1.0)
        nv[1:-1] = s / cosang
    return xy + nv * offset


def densify(xy: np.ndarray, h: np.ndarray, step: float):
    """Insert points so no segment exceeds `step`; heights interpolated."""
    out_xy, out_h = [xy[:1]], [h[:1]]
    for k in range(len(xy) - 1):
        seg = xy[k + 1] - xy[k]
        n = max(1, int(np.ceil(np.linalg.norm(seg) / step)))
        t = np.arange(1, n + 1) / n
        out_xy.append(xy[k] + t[:, None] * seg)
        out_h.append(h[k] + t * (h[k + 1] - h[k]))
    return np.concatenate(out_xy), np.concatenate(out_h)


def ribbon(surf: Surface, xy: np.ndarray, h: np.ndarray, width: float, u_scale: float,
           lateral: float = 0.0, up: bool = True):
    """A strip of `width` following a polyline at the given heights. UV: u across, v along."""
    if len(xy) < 2:
        return
    left = offset_polyline(xy, lateral + width / 2)
    right = offset_polyline(xy, lateral - width / 2)
    k = len(xy)
    along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(xy, axis=0), axis=1))])
    v = np.empty((k, 2, 3))
    v[:, 0, :2], v[:, 1, :2] = right, left
    v[:, 0, 2] = v[:, 1, 2] = h
    uv = np.empty((k, 2, 2))
    uv[:, 0, 0], uv[:, 1, 0] = 0.0, width / u_scale
    uv[:, 0, 1] = uv[:, 1, 1] = along / u_scale
    i = np.arange(k - 1) * 2
    # right[k], right[k+1], left[k+1] / right[k], left[k+1], left[k] -> CCW from above
    tris = np.concatenate([np.column_stack([i, i + 2, i + 3]), np.column_stack([i, i + 3, i + 1])])
    nrm = _ribbon_normals(v)
    if not up:
        tris = tris[:, [0, 2, 1]]
        nrm = -nrm
    surf.add(v.reshape(-1, 3), nrm, uv.reshape(-1, 2), tris)
    return left, right


def _ribbon_normals(v):
    k = v.shape[0]
    fwd = np.zeros((k, 3))
    fwd[1:-1] = v[2:, 0] - v[:-2, 0]
    fwd[0] = v[1, 0] - v[0, 0]
    fwd[-1] = v[-1, 0] - v[-2, 0]
    side = v[:, 1] - v[:, 0]
    nrm = np.cross(side, fwd)
    nrm[nrm[:, 2] < 0] *= -1
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    return np.repeat(nrm, 2, axis=0)


def box(surf: Surface, center, size, yaw: float = 0.0, uv_scale: float = 1.0):
    """Axis-aligned (in its own yaw) box. center = (e, n, h_bottom)."""
    sx, sy, sz = size
    c, s = np.cos(yaw), np.sin(yaw)
    corners = np.array([[-sx, -sy], [sx, -sy], [sx, sy], [-sx, sy]]) / 2
    rot = corners @ np.array([[c, s], [-s, c]])
    ring = rot + np.asarray(center[:2])
    walls(surf, ring, center[2], center[2] + sz, uv_scale, uv_scale)
    flat_cap(surf, Polygon(ring), center[2] + sz, uv_scale)
