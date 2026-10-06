"""Townhouse decor bought with job money (lib/decor.py), for the Decorate
feature; one glb each:

  props/home/decor/<kind>_<name>.glb
                                rug_jute, rug_persian, rug_retro,
                                lamp_arc, lamp_paper, lamp_tripod (Light empty
                                on the bulb; shades use Lampshade_Glow),
                                poster_band, poster_surf, poster_map,
                                poster_film (origin mid-poster, back on the
                                wall), plant_monstera, plant_fiddle,
                                plant_cactus, chair_rattan, chair_velvet,
                                chair_eames_style.

  props/home/magnets/magnet_<name>.glb
                                fridge magnets from places round Perth
                                (lib/magnets.py), origin at the middle of
                                the back; they go on the Magnet_1..12 empties
                                on the townhouse fridge door.

Origin at the base centre, front toward -Y in Blender (+Z in Godot).

    python3.11 art/models/scripts/build_decor.py [--render out/prefix]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from lib import common as C  # noqa: E402
from lib import decor as D  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import magnets as MG  # noqa: E402

OUT = "art/models/props/home/decor/"
MAGNETS = "art/models/props/home/magnets/"


def fresh():
    C.reset()
    C.clear_material_cache()


def build_decor(kind, name, pos=(0, 0, 0), rot=0):
    parts, sockets = getattr(D, kind)(name)
    o = F.item("%s_%s" % (kind.capitalize(), name), parts, pos, rot)
    for nm, loc in sockets.items():
        C.empty(nm, tuple(Vector(loc) + Vector(pos)), size=0.05)
    return o


DECOR = ([("rug", n) for n in D.RUGS] + [("lamp", n) for n in D.LAMPS] + [("poster", n) for n in D.POSTERS]
         + [("plant", n) for n in D.PLANTS] + [("chair", n) for n in D.CHAIRS])


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, name in DECOR:
        fresh()
        build_decor(kind, name)
        print("%s_%s triangles:" % (kind, name), C.tri_count([x for x in bpy.data.objects if x.type == "MESH"]))
        C.export_glb(OUT + "%s_%s.glb" % (kind, name))
    os.makedirs(MAGNETS, exist_ok=True)
    for name in MG.NAMES:
        fresh()
        o = F.item("Magnet_" + name, MG.magnet(name), (0, 0, 0))
        print("magnet_%s triangles:" % name, C.tri_count([o]))
        C.export_glb(MAGNETS + "magnet_%s.glb" % name)

    if "--render" in sys.argv:
        prefix = sys.argv[sys.argv.index("--render") + 1]

        def room(w, d):
            floor = D._m("RenderFloor", "#b9a58a", 0.8)
            wall = D._m("RenderWall", "#e8e2d6", 0.9)
            F.item("Floor", [F.bx((-w / 2, -d / 2, -0.02), (w / 2, d / 2, 0.0), floor)], (0, 0, 0))
            F.item("Wall", [F.bx((-w / 2, d / 2, 0.0), (w / 2, d / 2 + 0.05, 2.6), wall)], (0, 0, 0))

        fresh()
        room(9, 4)
        for i, name in enumerate(D.RUGS):
            build_decor("rug", name, (-2.6 + i * 2.6, -1.5, 0))
        others = [(k, n) for k, n in DECOR if k not in ("rug", "poster")]
        for i, (kind, name) in enumerate(others):
            build_decor(kind, name, (-3.6 + i * 0.8, 0.9, 0))
        # rugs on the floor in front, posters on the back wall
        for i, name in enumerate(D.POSTERS):
            build_decor("poster", name, (-1.8 + i * 1.2, 1.99, 1.7))
        C.render_setup((1400, 700), 24, world="#c9d6e0", strength=0.9)
        C.sun(rot=(45, 10, 160), energy=3.0)
        C.camera_look((0, -5.2, 2.4), (0, 0.6, 0.9), lens=30)
        C.render(prefix + "_decor.png")
        C.camera_look((-1.2, -2.2, 1.5), (-2.6, 0.8, 0.9), lens=35)
        C.render(prefix + "_decor_left.png")
        C.camera_look((3.6, -1.6, 1.3), (2.3, 0.9, 0.5), lens=35)
        C.render(prefix + "_decor_right.png")

        # the magnets on a fridge door
        fresh()
        door = D._m("FridgeDoor", "#e9e7e2", 0.4)
        F.item("Door", [F.bx((-0.42, 0.0, -0.32), (0.42, 0.04, 0.32), door)], (0, 0, 0))
        for i, name in enumerate(MG.NAMES):
            F.item("Magnet_" + name, MG.magnet(name), (-0.3 + (i % 5) * 0.15, 0.0, 0.2 - (i // 5) * 0.16))
        C.render_setup((960, 720), 24, world="#c9d6e0", strength=0.9)
        C.sun(rot=(40, 10, 200), energy=3.0)
        C.camera_look((0.25, -0.75, 0.25), (0.0, 0.0, 0.03), lens=40)
        C.render(prefix + "_magnets.png")


if __name__ == "__main__":
    main()
    C.done()
