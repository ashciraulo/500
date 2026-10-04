"""Minimal encoder for Godot 4's binary Variant format (what bytes_to_var reads).

Tiles are stored this way so Godot decodes whole vertex arrays natively instead
of looping in GDScript. Format reference: Godot docs, "Binary serialization API".
"""
from __future__ import annotations

import struct
import zlib

import brotli
import numpy as np

NIL, BOOL, INT, FLOAT, STRING = 0, 1, 2, 3, 4
DICTIONARY, ARRAY = 27, 28
PACKED_BYTE, PACKED_INT32, PACKED_INT64, PACKED_FLOAT32 = 29, 30, 31, 32
PACKED_VECTOR2, PACKED_VECTOR3 = 35, 36
FLAG_64 = 1 << 16

MAGIC = b"P5TB"  # tile container: magic, u32 uncompressed size, brotli stream
MAGIC_ZLIB = b"P5TZ"  # older tiles: same layout with a zlib stream (still read)


def _pad4(b: bytes) -> bytes:
    return b + b"\0" * (-len(b) % 4)


def encode(v) -> bytes:
    if v is None:
        return struct.pack("<I", NIL)
    if isinstance(v, (bool, np.bool_)):
        return struct.pack("<II", BOOL, int(v))
    if isinstance(v, (int, np.integer)):
        v = int(v)
        if -2**31 <= v < 2**31:
            return struct.pack("<Ii", INT, v)
        return struct.pack("<Iq", INT | FLAG_64, v)
    if isinstance(v, (float, np.floating)):
        return struct.pack("<Id", FLOAT | FLAG_64, float(v))
    if isinstance(v, str):
        b = v.encode("utf-8")
        return struct.pack("<II", STRING, len(b)) + _pad4(b)
    if isinstance(v, dict):
        out = [struct.pack("<II", DICTIONARY, len(v))]
        for k, val in v.items():
            out.append(encode(k))
            out.append(encode(val))
        return b"".join(out)
    if isinstance(v, (list, tuple)):
        return b"".join([struct.pack("<II", ARRAY, len(v))] + [encode(x) for x in v])
    if isinstance(v, np.ndarray):
        if v.dtype.kind == "f":
            a = np.ascontiguousarray(v, dtype="<f4")
            if a.ndim == 2 and a.shape[1] == 3:
                return struct.pack("<II", PACKED_VECTOR3, a.shape[0]) + a.tobytes()
            if a.ndim == 2 and a.shape[1] == 2:
                return struct.pack("<II", PACKED_VECTOR2, a.shape[0]) + a.tobytes()
            a = a.ravel()
            return struct.pack("<II", PACKED_FLOAT32, a.size) + a.tobytes()
        if v.dtype == np.uint8:
            return struct.pack("<II", PACKED_BYTE, v.size) + _pad4(v.tobytes())
        a = np.ascontiguousarray(v, dtype="<i4").ravel()
        return struct.pack("<II", PACKED_INT32, a.size) + a.tobytes()
    raise TypeError(f"cannot encode {type(v)}")


def pack_tile(data: dict) -> bytes:
    raw = encode(data)
    # Brotli at full quality is about a quarter smaller than zlib -9 on tiles,
    # and Godot decompresses it natively.
    return MAGIC + struct.pack("<I", len(raw)) + brotli.compress(raw, quality=11, lgwin=24)


def unpack_tile(blob: bytes) -> bytes:
    """The raw Variant bytes of a container, either compression."""
    size = struct.unpack("<I", blob[4:8])[0]
    if blob[:4] == MAGIC_ZLIB:
        raw = zlib.decompress(blob[8:])
    else:
        assert blob[:4] == MAGIC
        raw = brotli.decompress(blob[8:])
    assert len(raw) == size
    return raw


def unpack_header(blob: bytes) -> int:
    assert blob[:4] in (MAGIC, MAGIC_ZLIB)
    return struct.unpack("<I", blob[4:8])[0]
