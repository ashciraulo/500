"""Jetty and groyne kit pieces and the Lake Street shopfronts
(lib/field_places.py), one glb each:

  art/models/props/field/places/<name>.glb

Each is one mesh named after it plus empties for where things happen
(`Cast_L`/`Cast_R` where an angler stands, `Water` on the surface below,
`Door` and `Counter` at the shops). Front toward -Y in Blender (+Z in Godot).

    python3.11 art/models/scripts/build_field_places.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import common as C  # noqa: E402
from lib import field_places as FP  # noqa: E402
from lib import furniture as F  # noqa: E402

OUT = "art/models/props/field/places/"


def build(name, pos=(0, 0, 0)):
    built = FP.PLACES[name]()
    parts, sockets = built[0], built[1]
    title = "".join(w.capitalize() for w in name.split("_"))
    objs = [F.item(title, parts, pos)]
    if len(built) > 2:
        # plain boxes Godot turns into a static body (the `-colonly` suffix)
        cmat = C.mat("Collision", "#ff00ff")
        objs.append(F.item(title + "_Col-colonly", [F.bx(lo, hi, cmat) for lo, hi in built[2]], pos))
    for nm, loc in sockets.items():
        C.empty(nm, tuple(a + b for a, b in zip(loc, pos)), size=0.2)
    return objs


def main():
    for name in FP.PLACES:
        C.reset()
        C.clear_material_cache()
        objs = build(name)
        print(name, "triangles:", C.tri_count(objs))
        C.export_glb(OUT + name + ".glb")


if __name__ == "__main__":
    main()
    C.done()
