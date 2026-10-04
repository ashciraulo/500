"""Write a built tile as a compressed Godot Variant (.p5t).

Tile format 1 (decoded by map/scripts/tile_loader.gd)::

    {
      "format": 1, "tile": [i, j],
      "origin": [x, 0, z],              # tile node position in Godot
      "meshes": [{"name", "collision": "" | "world" | "buildings",
                  "surfaces": [{"material", "count",
                                "pos": bytes,  # int16 SoA x[], y[], z[] in 1/32 m
                                "nrm": bytes,  # int8 SoA in 1/127
                                "uv":  bytes,  # int16 SoA u[], v[] in 1/uvq
                                "uvq": float,  # UV quantisation (64 unless the surface spans a lot)
                                "idx": PackedInt32Array}]}],  # delta-coded, clockwise
      "instances": {kind: PackedFloat32Array [x, y, z, yaw, scale] * n}
    }
"""
from __future__ import annotations

from pathlib import Path

import numpy as np

from .variant import pack_tile

FORMAT_VERSION = 1
POS_Q = 32.0
NRM_Q = 127.0
UV_Q = 64.0


def _soa_i16(a: np.ndarray, q: float) -> np.ndarray:
    v = np.round(a * q)
    if v.size and (v.min() < -32768 or v.max() > 32767):
        raise ValueError(f"value out of int16 range ({a.min():.1f}..{a.max():.1f})")
    return np.ascontiguousarray(v.astype("<i2").T).view(np.uint8).ravel()


def encode_surface(mat, pos, nrm, uv, tris) -> dict:
    # World-space UVs can be large; texture repeat makes integer shifts free.
    uv = uv - np.floor(uv.min(axis=0)) if len(uv) else uv
    span = float(np.abs(uv).max()) if len(uv) else 0.0
    uvq = UV_Q
    while span * uvq > 32000 and uvq > 1:
        uvq /= 2
    pos, nrm, uv, tris = _weld(pos, nrm, uv, tris, uvq)
    idx = tris.astype(np.int64).ravel()
    delta = np.diff(np.concatenate([[0], idx])).astype(np.int32)
    n8 = np.clip(np.round(nrm * NRM_Q), -127, 127).astype(np.int8)
    return {"material": mat, "count": int(len(pos)),
            "pos": _soa_i16(pos, POS_Q), "nrm": np.ascontiguousarray(n8.T).view(np.uint8).ravel(),
            "uv": _soa_i16(uv, uvq), "uvq": uvq, "idx": delta}


def to_godot(data: dict) -> dict:
    e0, n0 = data["origin"]
    meshes = []
    for name, collision, surfaces in data["meshes"]:
        out = []
        for mat, v, nrm, uv, idx in surfaces:
            pos = np.column_stack([v[:, 0] - e0, v[:, 2], -(v[:, 1] - n0)])
            nr = np.column_stack([nrm[:, 0], nrm[:, 2], -nrm[:, 1]])
            tris = idx[:, [0, 2, 1]]  # Godot front faces are clockwise
            out.append(encode_surface(mat, pos, nr, uv, tris))
        meshes.append({"name": name, "collision": collision or "", "surfaces": out})
    instances = {}
    for kind, arr in data["instances"].items():
        if len(arr) == 0:
            continue
        a = np.column_stack([arr[:, 0] - e0, arr[:, 2], -(arr[:, 1] - n0), arr[:, 3], arr[:, 4]])
        instances[kind] = (np.round(a * 64) / 64).astype(np.float32).ravel()
    key = data["key"]
    return {"format": FORMAT_VERSION, "tile": [key.i, key.j], "origin": [float(e0), 0.0, float(-n0)],
            "meshes": meshes, "instances": instances}


def write_tile(path: Path, data: dict) -> int:
    blob = pack_tile(to_godot(data))
    path.write_bytes(blob)
    return len(blob)


def _weld(pos, nrm, uv, tris, uvq):
    """Merge vertices that are identical after quantisation; drop degenerate triangles."""
    key = np.column_stack([pos * POS_Q, nrm * NRM_Q, uv * uvq]).round().astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.ravel()
    t = inv[tris]
    ok = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    return pos[first], nrm[first], uv[first], t[ok]
