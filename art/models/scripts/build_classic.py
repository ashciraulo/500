"""The classic Fiat 500s (1957-1975): Nuova, D, F, L, R, Giardiniera, Sport,
the Abarth 595/695 and the Ghia Jolly.

    python3.11 art/models/scripts/build_classic.py [--render [dir]] [--only nuova,classic_f]

Writes cars/<name>/<name>.glb for each car in CARS, plus the classic wheel
glbs (cars/parts/wheel_<style>_l/_r.glb) and exhaust_abarth_classic.glb.
Body shape and parts live in lib/fiat500_classic.py. Paint colours follow
data/cars/restoration.json "original_colors" (the clean restored car; the
game rusts barn finds in the shader).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from lib import common as C  # noqa: E402
from lib import fiat500_classic as F  # noqa: E402
from lib import wheels as W  # noqa: E402
from build_pop import export_car  # noqa: E402

PLATE = "1CIN-500"  # made-up plate shared by every car

CARS = {
    # 1957 Nuova 500: canvas roof all the way back to the engine lid (the rear
    # window is sewn into it), suicide doors, small round lamps, wide louvres
    "nuova": {
        "paint": "#9eb8c7", "roof": "fabric_full", "fabric": "#4a4540", "doors": "suicide",
        "wheels": "classic12", "tail": "small", "louvres": "wide", "badge": "nuova",
        "seat": "#cfc2a6", "seat_piping": "#8c261f", "wheel_color": "#e9e1cc", "cabin": "#5a554c",
    },
    # 1958 Sport: fixed steel roof, cream with a red side stripe
    "classic_sport": {
        "paint": "#ebe5d6", "roof": "steel", "doors": "suicide", "wheels": "classic12", "tail": "small",
        "louvres": "wide", "badge": "nuova", "stripe": "#b3121c", "seat": "#9a1c1c", "seat_piping": "#ebe5d6",
        "wheel_color": "#e9e1cc",
    },
    # 1960 500 D: shorter canvas roof ending over the rear seat, suicide doors
    "classic_d": {
        "paint": "#8c261f", "roof": "fabric", "fabric": "#2b2927", "doors": "suicide", "wheels": "classic12",
        "tail": "small", "louvres": "banks", "badge": "nuova", "seat": "#d8cbb0", "seat_piping": "#8c261f",
        "wheel_color": "#e9e1cc",
    },
    # 1965 500 F: front-hinged doors, bigger lamps
    "classic_f": {
        "paint": "#e6d999", "roof": "fabric", "fabric": "#2b2927", "doors": "front", "wheels": "classic12",
        "tail": "large", "louvres": "banks", "badge": "nuova", "seat": "#3a3632", "seat_piping": "#c9c2b0",
        "wheel_color": "#1a1a1a",
    },
    # 1968 500 L (Lusso): tubular over-riders, black dash, chrome side trim, vent windows
    "classic_l": {
        "paint": "#334d73", "roof": "fabric", "fabric": "#1f1e1d", "doors": "front", "wheels": "classic12",
        "tail": "large", "louvres": "banks", "badge": "nuova", "nerf": True, "dash": "black",
        "side_trim": True, "quarterlight": True, "seat": "#26231f", "seat_piping": "#8a8478",
        "wheel_color": "#141414",
    },
    # 1972 500 R: as the F, plain badge, small hubcaps
    "classic_r": {
        "paint": "#f28c33", "roof": "fabric", "fabric": "#1f1e1d", "doors": "front", "wheels": "classic_steel",
        "tail": "large", "louvres": "banks", "badge": "plain", "seat": "#2b2826", "seat_piping": "#2b2826",
        "wheel_color": "#141414",
    },
    # Giardiniera estate: longer wheelbase, flat roof, canvas the whole way back,
    # side-hinged rear door, engine flat under the load floor. It kept the
    # rear-hinged front doors to the end of production (1977).
    "giardiniera": {
        "body": "estate", "paint": "#73997f", "roof": "fabric", "fabric": "#d4c8a8", "fabric_rib": "#9a8f74",
        "doors": "suicide", "wheels": "classic12", "tail": "small", "badge": "nuova", "seat": "#d8cbb0",
        "seat_piping": "#4a6a55", "wheel_color": "#e9e1cc",
    },
    # Abarth 595 (on the D): lowered, wide steel wheels, lid propped open
    "abarth595_classic": {
        "paint": "#bf1a1a", "roof": "fabric", "fabric": "#1f1e1d", "doors": "suicide", "wheels": "abarth_classic",
        "tail": "small", "louvres": "banks", "badge": "abarth", "abarth": "595", "ride": -0.03,
        "seat": "#1d1d1d", "seat_piping": "#bf1a1a", "wheel_color": "#141414",
    },
    # Abarth 695 SS: as the 595 plus flared arches
    "abarth695_classic": {
        "paint": "#e6e6e0", "roof": "fabric", "fabric": "#1f1e1d", "doors": "suicide", "wheels": "abarth_classic",
        "tail": "small", "louvres": "banks", "badge": "abarth", "abarth": "695", "ride": -0.03,
        "seat": "#1d1d1d", "seat_piping": "#b3121c", "wheel_color": "#141414",
    },
    # Ghia Jolly: no roof, no doors, wicker seats, fringed canopy
    "jolly": {
        "body": "jolly", "paint": "#66bfbf", "roof": "canopy", "doors": None, "wheels": "classic12",
        "tail": "small", "louvres": "wide", "badge": "nuova", "wheel_color": "#e9e1cc", "cabin": "#e6e0d0",
    },
}

WHEEL_STYLES = ("classic12", "classic_steel", "abarth_classic", "campagnolo")
EXHAUSTS = ("abarth_classic",)

# preview cameras: name -> (location, target, lens)
VIEWS = {
    "front34": ((-3.3, -4.0, 1.45), (0, -0.05, 0.52), 40),
    "rear34": ((3.4, 4.0, 1.6), (0, 0.1, 0.52), 40),
    "side": ((6.4, 0, 0.75), (0, 0, 0.62), 45),
    "front": ((0, -6.4, 0.80), (0, 0, 0.62), 45),
    "rear": ((0, 6.4, 0.95), (0, 0, 0.62), 45),
}


def render_views(prefix, views, samples=24, res=(960, 540)):
    C.render_setup(res, samples, world="#c9d6e0", strength=0.8)
    C.box("PreviewGround", (40, 40, 0.02), (0, 0, -0.01), C.mat("PreviewGround", "#8a8780", rough=0.9))
    C.sun(rot=(48, 10, 140), energy=3.5)
    for v in views:
        if v == "interior":
            cam = bpy.data.objects["Cam_Cockpit"].location
            C.camera_look(tuple(cam), (cam.x + 0.12, cam.y - 2.0, cam.z - 0.45), lens=20)
        elif v == "doors":
            for d in ("Door_L", "Door_R"):
                o = bpy.data.objects.get(d)
                if o:
                    o.rotation_euler.z = math.radians(60) * o.get("open_sign", 1)
            C.camera_look((-3.0, -1.2, 2.2), (0, 0, 0.55), lens=35)
        else:
            loc, tgt, lens = VIEWS[v]
            C.camera_look(loc, tgt, lens)
        C.render("%s_%s.png" % (prefix, v))
        if v == "doors":
            for d in ("Door_L", "Door_R"):
                o = bpy.data.objects.get(d)
                if o:
                    o.rotation_euler.z = 0


def build_car(name):
    spec = dict(CARS[name], name=name, plate=PLATE)
    C.reset()
    C.clear_material_cache()
    objs = F.build(spec)
    return spec, objs


def build_parts():
    # In Godot the car's left is -X, so the left wheel's face points to -X.
    for style in WHEEL_STYLES:
        for side, right in (("l", True), ("r", False)):
            C.reset()
            C.clear_material_cache()
            W.build("Wheel", style, right=right)
            C.export_glb("art/models/cars/parts/wheel_%s_%s.glb" % (style, side))
    for style in EXHAUSTS:
        C.reset()
        C.clear_material_cache()
        F.exhaust(style)
        C.turn_scene_z180()
        C.export_glb("art/models/cars/parts/exhaust_%s.glb" % style)


def main():
    argv = sys.argv
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(CARS)
    render = "--render" in argv
    out = "docs/renders/classics"
    if render and len(argv) > argv.index("--render") + 1 and not argv[argv.index("--render") + 1].startswith("--"):
        out = argv[argv.index("--render") + 1]
    views = argv[argv.index("--views") + 1].split(",") if "--views" in argv else \
        ["front34", "rear34", "side", "front", "rear", "interior", "doors"]
    if "--no-parts" not in argv and "--only" not in argv:
        build_parts()
    for name in only:
        spec, objs = build_car(name)
        print(name, "triangles:", C.tri_count([o for o in objs if not o.name.startswith("Wheel_")]))
        if render:
            render_views("%s/%s" % (out, name), views)
        if "--no-export" not in argv:
            export_car("art/models/cars/%s/%s.glb" % (name, name))


if __name__ == "__main__":
    main()
    C.done()
