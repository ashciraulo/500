"""The Alfa 75's stock wheels cars/parts/wheel_a75_l/_r.glb and its parts'
wheels and bolt-ons (lib/alfa75_parts.py). The car itself, and the Simmons
B45 wheels, come from the bought model: import_alfa75.py. (lib/alfa75.py
and lib/alfa75_cabin.py are the earlier, hand-built car; the parts still
take their seat and mount positions from them.)

    python3.11 art/models/scripts/build_alfa75.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import common as C  # noqa: E402
from lib import alfa75_parts as AP  # noqa: E402

WHEEL_OUT = "art/models/cars/parts/wheel_%s_%s.glb"
PART_OUT = "art/models/cars/parts/%s.glb"
IMPORTED = ("a75_simmons", "seatcover_a75_beads")  # import_alfa75.py writes these, fitted to the bought model


def main():
    build_parts()


def build_parts():
    """Every wheel style and bolt-on but the imported ones."""
    for style, fn in AP.WHEELS.items():
        if style in IMPORTED:
            continue
        for side, sx in (("l", -1), ("r", 1)):
            C.reset()
            C.clear_material_cache()
            fn(sx)
            C.export_glb(WHEEL_OUT % (style, side))
    for name, fn in AP.PARTS.items():
        if name in IMPORTED:
            continue
        C.reset()
        C.clear_material_cache()
        objs = fn()
        print(name, "triangles:", C.tri_count(objs))
        C.export_glb(PART_OUT % name)


if __name__ == "__main__":
    main()
    C.done()
