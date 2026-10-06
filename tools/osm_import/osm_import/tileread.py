"""Read built tiles back (.p5t meshes, .p5r road data) for checks and surveys.

`roughness.py` uses this to measure how smooth the roads really are in the
tiles the game loads.
"""
from __future__ import annotations

import struct
from pathlib import Path

import numpy as np

from .tilewriter import NRM_Q, POS_Q
from .variant import (ARRAY, BOOL, DICTIONARY, FLAG_64, FLOAT, INT, NIL, PACKED_BYTE,
                      PACKED_FLOAT32, PACKED_INT32, PACKED_INT64, PACKED_VECTOR2,
                      PACKED_VECTOR3, STRING, unpack_tile)


def decode(raw: bytes):
    v, _ = _dec(memoryview(raw), 0)
    return v


def _dec(b, o):
    head = struct.unpack_from("<I", b, o)[0]
    t, flags = head & 0xFFFF, head & FLAG_64
    o += 4
    if t == NIL:
        return None, o
    if t == BOOL:
        return bool(struct.unpack_from("<I", b, o)[0]), o + 4
    if t == INT:
        if flags:
            return struct.unpack_from("<q", b, o)[0], o + 8
        return struct.unpack_from("<i", b, o)[0], o + 4
    if t == FLOAT:
        if flags:
            return struct.unpack_from("<d", b, o)[0], o + 8
        return struct.unpack_from("<f", b, o)[0], o + 4
    if t == STRING:
        n = struct.unpack_from("<I", b, o)[0]
        o += 4
        s = bytes(b[o:o + n]).decode("utf-8")
        return s, o + n + (-n % 4)
    if t == DICTIONARY:
        n = struct.unpack_from("<I", b, o)[0] & 0x7FFFFFFF
        o += 4
        out = {}
        for _ in range(n):
            k, o = _dec(b, o)
            v, o = _dec(b, o)
            out[k] = v
        return out, o
    if t == ARRAY:
        n = struct.unpack_from("<I", b, o)[0] & 0x7FFFFFFF
        o += 4
        out = []
        for _ in range(n):
            v, o = _dec(b, o)
            out.append(v)
        return out, o
    n = struct.unpack_from("<I", b, o)[0]
    o += 4
    if t == PACKED_BYTE:
        return np.frombuffer(b, np.uint8, n, o).copy(), o + n + (-n % 4)
    if t == PACKED_INT32:
        return np.frombuffer(b, "<i4", n, o).copy(), o + 4 * n
    if t == PACKED_INT64:
        return np.frombuffer(b, "<i8", n, o).copy(), o + 8 * n
    if t == PACKED_FLOAT32:
        return np.frombuffer(b, "<f4", n, o).copy(), o + 4 * n
    if t == PACKED_VECTOR2:
        return np.frombuffer(b, "<f4", 2 * n, o).reshape(n, 2).copy(), o + 8 * n
    if t == PACKED_VECTOR3:
        return np.frombuffer(b, "<f4", 3 * n, o).reshape(n, 3).copy(), o + 12 * n
    raise ValueError(f"unsupported variant type {t}")


def read_container(path: Path):
    return decode(unpack_tile(Path(path).read_bytes()))


def surface_arrays(s: dict):
    """(positions in tile-local Godot space, triangles) of one encoded surface."""
    n = s["count"]
    pos = s["pos"].view("<i2").reshape(3, n).T.astype(np.float64) / POS_Q
    idx = np.cumsum(s["idx"].astype(np.int64)).reshape(-1, 3)
    return pos, idx


def tile_surfaces(path: Path, meshes=None, materials=None):
    """{(mesh, material): (world positions in Godot space, triangles)}."""
    d = read_container(path)
    ox, oy, oz = d["origin"]
    out = {}
    for m in d["meshes"]:
        if meshes is not None and m["name"] not in meshes:
            continue
        for s in m["surfaces"]:
            if materials is not None and s["material"] not in materials:
                continue
            pos, tri = surface_arrays(s)
            pos += (ox, oy, oz)
            out[(m["name"], s["material"])] = (pos, tri)
    return out


class HeightQuery:
    """Top height of a set of triangles at plan points (Godot x, z).

    Triangles are bucketed on a regular grid; a query tests the triangles of
    its bucket with barycentric coordinates and keeps the highest hit.
    """

    def __init__(self, pos: np.ndarray, tri: np.ndarray, cell: float = 4.0):
        self.pos, self.tri, self.cell = pos, tri, cell
        p = pos[tri]  # (T, 3, 3)
        x, z = p[:, :, 0], p[:, :, 2]
        self.x0, self.z0 = float(x.min()), float(z.min())
        i0 = np.floor((x.min(1) - self.x0) / cell).astype(np.int64)
        i1 = np.floor((x.max(1) - self.x0) / cell).astype(np.int64)
        j0 = np.floor((z.min(1) - self.z0) / cell).astype(np.int64)
        j1 = np.floor((z.max(1) - self.z0) / cell).astype(np.int64)
        self.ni = int(i1.max()) + 1 if len(i1) else 1
        buckets: dict[int, list] = {}
        for t in range(len(tri)):
            for i in range(i0[t], i1[t] + 1):
                for j in range(j0[t], j1[t] + 1):
                    buckets.setdefault(j * self.ni + i, []).append(t)
        self.buckets = {k: np.array(v, dtype=np.int64) for k, v in buckets.items()}
        self.p = p

    def heights(self, x, z) -> np.ndarray:
        return self.heights_near(x, z, None)

    def heights_near(self, x, z, ref, above: float | None = None) -> np.ndarray:
        """Like heights(), but where surfaces overlap keep the hit closest to
        `ref`, or with `above`, the lowest hit more than that above `ref`."""
        x = np.asarray(x, dtype=np.float64)
        z = np.asarray(z, dtype=np.float64)
        out = np.full(len(x), np.nan)
        ki = np.floor((x - self.x0) / self.cell).astype(np.int64)
        kj = np.floor((z - self.z0) / self.cell).astype(np.int64)
        for q in range(len(x)):
            ts = self.buckets.get(int(kj[q] * self.ni + ki[q]))
            if ts is None:
                continue
            p = self.p[ts]
            ax, az = p[:, 0, 0], p[:, 0, 2]
            v0x, v0z = p[:, 1, 0] - ax, p[:, 1, 2] - az
            v1x, v1z = p[:, 2, 0] - ax, p[:, 2, 2] - az
            wx, wz = x[q] - ax, z[q] - az
            den = v0x * v1z - v1x * v0z
            ok = np.abs(den) > 1e-12
            den = np.where(ok, den, 1.0)
            u = (wx * v1z - v1x * wz) / den
            v = (v0x * wz - wx * v0z) / den
            inside = ok & (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6)
            if not inside.any():
                continue
            h = p[:, 0, 1] + u * (p[:, 1, 1] - p[:, 0, 1]) + v * (p[:, 2, 1] - p[:, 0, 1])
            h = h[inside]
            if above is not None:
                h = h[h > ref[q] + above]
                if len(h):
                    out[q] = float(h.min())
                continue
            out[q] = float(h.max() if ref is None else h[np.argmin(np.abs(h - ref[q]))])
        return out
