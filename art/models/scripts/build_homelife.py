"""Home life props (lib/homelife.py), one glb each:

  art/models/props/home/<name>.glb

Front toward -Y in Blender (+Z in Godot), origin at the base centre. Each
file holds one or more named meshes that share the origin: the cat's four
poses (Pose_Sit, Pose_Loaf, Pose_Sleep, Pose_Walk), the plants' three growth
stages (Stage_1..3), the bowl and its Food. Empties mark points the game
uses (Head_<pose> on the cat, Spout on the watering can).

    python3.11 art/models/scripts/build_homelife.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import homelife as HL  # noqa: E402

OUT = "art/models/props/home/"


def build(name, pos=(0, 0, 0)):
    """The prop's meshes and sockets placed at pos; returns the objects."""
    meshes, sockets = HL.PROPS[name]()
    objs = [F.item(nm, parts, pos) for nm, parts in meshes.items()]
    for nm, loc in sockets.items():
        C.empty(nm, tuple(a + b for a, b in zip(loc, pos)), size=0.03)
    return objs


def main():
    for name in HL.PROPS:
        C.reset()
        C.clear_material_cache()
        objs = build(name)
        print(name, "triangles:", C.tri_count(objs))
        C.export_glb(OUT + name + ".glb")


if __name__ == "__main__":
    main()
    C.done()
