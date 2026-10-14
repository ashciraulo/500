"""Period cars for the late city (lib/period_vehicles.py), one glb each in
art/models/vehicles/period/: valiant.

Front toward -Z in Godot, kerb side -X, origin on the ground at the
footprint centre, no wheel nodes.

It also writes the Valiant you can buy at the car yard, on the cars/
contract (art/models/README.md): cars/valiant/valiant.glb and its wheels,
cars/parts/wheel_vc_l.glb and wheel_vc_r.glb. `--car-render out/prefix`
renders that one (with its wheels on) from the front, back and the
driver's seat.

    python3.11 art/models/scripts/build_period.py [--render out/prefix] [--car-render out/prefix] [-- name ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

import build_city as BC  # noqa: E402
from lib import common as C  # noqa: E402
from lib import period_vehicles as PV  # noqa: E402
from lib import valiant_parts as VP  # noqa: E402

OUT = "art/models/vehicles/period/"
CAR_OUT = "art/models/cars/valiant/valiant.glb"
WHEEL_OUT = "art/models/cars/parts/wheel_%s_%s.glb"
PART_OUT = "art/models/cars/parts/%s.glb"
# The Valiant's bolt-ons (lib/valiant_parts.py): glb name -> builder.
PARTS = {"seatcover_vc_sheepskin": VP.seatcover_sheepskin, "exhaust_vc_twin": VP.exhaust_twin}
# Its other wheels: style -> builder(sx), written as wheel_<style>_l/_r.
WHEELS = {"vc_whitewall": VP.wheel_whitewall, "vc_slot": VP.wheel_slot}
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
    if not only or "valiant" in only:
        build_car()
        build_parts()
    if "--car-render" in sys.argv:
        render_car(sys.argv[sys.argv.index("--car-render") + 1])


def build_car():
    """The driveable Valiant and its two wheels."""
    for side, sx in (("l", -1), ("r", 1)):
        C.reset()
        C.clear_material_cache()
        PV.valiant_wheel(sx)
        C.export_glb(WHEEL_OUT % (PV.WHEEL_STYLE, side))
    _car()
    made = [o for o in bpy.data.objects if o.type == "MESH"]
    print("valiant car triangles:", C.tri_count(made))
    C.export_glb(CAR_OUT)


def build_parts():
    """The Valiant's bolt-on parts, each at its mount, and its wheels."""
    for style, fn in WHEELS.items():
        for side, sx in (("l", -1), ("r", 1)):
            C.reset()
            C.clear_material_cache()
            fn(sx)
            C.export_glb(WHEEL_OUT % (style, side))
    for name, fn in PARTS.items():
        C.reset()
        C.clear_material_cache()
        objs = fn()
        print(name, "triangles:", C.tri_count(objs))
        C.export_glb(PART_OUT % name)


def _car():
    C.reset()
    C.clear_material_cache()
    BC.build("valiant_car", table={"valiant_car": PV.valiant_car})
    PV.valiant_car_finish()


def render_car(prefix):
    """Preview the car with its wheels at the hubs, as the game puts them."""
    _car()
    for nm in ("FL", "FR", "RL", "RR"):
        hub = bpy.data.objects["Hub_" + nm]
        w = PV.valiant_wheel(1 if nm.endswith("R") else -1)
        w.location = hub.location
    C.render_setup((960, 600), 24, world="#c9d6e0", strength=0.9)
    C.box("PreviewGround", (40, 40, 0.02), (0, 0, -0.01), C.mat("PreviewGround", "#8a8780", rough=0.9))
    C.sun(rot=(50, 10, 210), energy=3.5)
    d = 6.5
    C.camera_look((-0.8 * d, 0.75 * d, 0.42 * d), (0, 0, 0.75), lens=35)
    C.render(prefix + "_front.png")
    C.camera_look((0.75 * d, -0.8 * d, 0.4 * d), (0, 0, 0.75), lens=35)
    C.render(prefix + "_back.png")
    C.camera_look((7.0, 0, 0.8), (0, 0, 0.7), lens=40)
    C.render(prefix + "_side.png")
    eye = bpy.data.objects["Cam_Cockpit"].location
    C.camera_look(tuple(eye), (eye.x - 0.05, eye.y + 2.0, eye.z - 0.35), lens=20)
    C.render(prefix + "_cockpit.png")


if __name__ == "__main__":
    main()
    C.done()
