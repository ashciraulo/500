"""The 1988 Alfa 75 2.5 V6 you can buy at the car yard (lib/alfa75.py), on
the cars/ contract (art/models/README.md): cars/alfa75/alfa75.glb, its stock
wheels cars/parts/wheel_a75_l/_r.glb and its parts' wheels and bolt-ons
(lib/alfa75_parts.py). `--car-render out/prefix` renders the car with its
wheels on from the front, back, side and the driver's seat.

    python3.11 art/models/scripts/build_alfa75.py [--car-render out/prefix]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

import build_city as BC  # noqa: E402
from lib import common as C  # noqa: E402
from lib import alfa75 as A  # noqa: E402
from lib import alfa75_parts as AP  # noqa: E402

CAR_OUT = "art/models/cars/alfa75/alfa75.glb"
WHEEL_OUT = "art/models/cars/parts/wheel_%s_%s.glb"
PART_OUT = "art/models/cars/parts/%s.glb"


def main():
    build_car()
    build_parts()
    if "--car-render" in sys.argv:
        render_car(sys.argv[sys.argv.index("--car-render") + 1])


def build_car():
    _car()
    made = [o for o in bpy.data.objects if o.type == "MESH"]
    print("alfa75 car triangles:", C.tri_count(made))
    C.export_glb(CAR_OUT)


def build_parts():
    """Every wheel style (the stock one included) and the bolt-ons."""
    for style, fn in AP.WHEELS.items():
        for side, sx in (("l", -1), ("r", 1)):
            C.reset()
            C.clear_material_cache()
            fn(sx)
            C.export_glb(WHEEL_OUT % (style, side))
    for name, fn in AP.PARTS.items():
        C.reset()
        C.clear_material_cache()
        objs = fn()
        print(name, "triangles:", C.tri_count(objs))
        C.export_glb(PART_OUT % name)


def _car():
    C.reset()
    C.clear_material_cache()
    BC.build("alfa_car", table={"alfa_car": A.alfa_car})
    A.alfa_car_finish()


def render_car(prefix, style=A.WHEEL_STYLE):
    """Preview the car with its wheels at the hubs, as the game puts them."""
    _car()
    for nm in ("FL", "FR", "RL", "RR"):
        hub = bpy.data.objects["Hub_" + nm]
        w = AP.WHEELS[style](1 if nm.endswith("R") else -1)
        w.location = hub.location
    C.render_setup((960, 600), 24, world="#c9d6e0", strength=0.9)
    C.box("PreviewGround", (40, 40, 0.02), (0, 0, -0.01), C.mat("PreviewGround", "#8a8780", rough=0.9))
    C.sun(rot=(50, 10, 210), energy=3.5)
    d = 6.2
    C.camera_look((-0.8 * d, 0.75 * d, 0.42 * d), (0, 0, 0.7), lens=35)
    C.render(prefix + "_front.png")
    C.camera_look((0.75 * d, -0.8 * d, 0.4 * d), (0, 0, 0.7), lens=35)
    C.render(prefix + "_back.png")
    C.camera_look((7.0, 0, 0.8), (0, 0, 0.7), lens=40)
    C.render(prefix + "_side.png")
    eye = bpy.data.objects["Cam_Cockpit"].location
    C.camera_look(tuple(eye), (eye.x - 0.05, eye.y + 2.0, eye.z - 0.35), lens=20)
    C.render(prefix + "_cockpit.png")


if __name__ == "__main__":
    main()
    C.done()
