"""Period cars for the late city (lib/period_vehicles.py), one glb each in
art/models/vehicles/period/: valiant.

Front toward -Z in Godot, kerb side -X, origin on the ground at the
footprint centre, no wheel nodes.

    python3.11 art/models/scripts/build_period.py [--render out/prefix] [-- name ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

import build_city as BC  # noqa: E402
from lib import common as C  # noqa: E402
from lib import period_vehicles as PV  # noqa: E402

OUT = "art/models/vehicles/period/"
SIZE = {}


def main():
    only = [a for a in sys.argv[sys.argv.index("--") + 1:] if a in PV.VEHICLES] if "--" in sys.argv else []
    names = only or list(PV.VEHICLES)
    for name in names:
        C.reset()
        C.clear_material_cache()
        _, tris = BC.build(name, table=PV.VEHICLES)
        print(name, "triangles:", tris)
        C.export_glb(OUT + name + ".glb")
    if "--render" in sys.argv:
        prefix = sys.argv[sys.argv.index("--render") + 1]
        for name in names:
            C.reset()
            C.clear_material_cache()
            BC.build(name, (0, 0, 0), table=PV.VEHICLES)
            d, h = SIZE.get(name, (6.5, 0.75))
            C.render_setup((960, 600), 24, world="#c9d6e0", strength=0.9)
            C.sun(rot=(50, 10, 210), energy=3.5)
            C.camera_look((-0.8 * d, 0.75 * d, 0.42 * d), (0, 0, h), lens=35)
            C.render(prefix + "_" + name + "_front.png")
            C.camera_look((0.75 * d, -0.8 * d, 0.4 * d), (0, 0, h), lens=35)
            C.render(prefix + "_" + name + "_back.png")


if __name__ == "__main__":
    main()
    C.done()
