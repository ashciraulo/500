"""Everyday traffic vehicles for traffic/ (lib/traffic_vehicles.py), one
glb each in art/models/vehicles/traffic/: hatch, sedan, suv, ute, van,
taxi, bus, police, ambulance, fire, carriage_cab and carriage_mid.

Front toward -Z in Godot, kerb side -X, origin on the ground at the
footprint centre (rail level for the railcar), no wheel nodes.

    python3.11 art/models/scripts/build_traffic.py [--render out/prefix] [-- name ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

import build_city as BC  # noqa: E402
from lib import common as C  # noqa: E402
from lib import traffic_vehicles as TV  # noqa: E402

OUT = "art/models/vehicles/traffic/"
SIZE = {"bus": (16.0, 1.6), "fire": (11.0, 1.6), "ambulance": (8.5, 1.3),
        "carriage_cab": (24.0, 2.0), "carriage_mid": (24.0, 2.0)}


def main():
    only = [a for a in sys.argv[sys.argv.index("--") + 1:] if a in TV.VEHICLES] if "--" in sys.argv else []
    names = only or list(TV.VEHICLES)
    for name in names:
        C.reset()
        C.clear_material_cache()
        _, tris = BC.build(name, table=TV.VEHICLES)
        print(name, "triangles:", tris)
        C.export_glb(OUT + name + ".glb")
    if "--render" in sys.argv:
        prefix = sys.argv[sys.argv.index("--render") + 1]
        for name in names:
            C.reset()
            C.clear_material_cache()
            BC.build(name, (0, 0, 0), table=TV.VEHICLES)
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
