"""Field gear for bird-watching and fishing (lib/field.py), one glb each:

  art/models/props/field/<name>.glb

Front toward -Y in Blender (+Z in Godot), origin at the base centre (the
rod: at the butt, lying along -Y). Each prop is one mesh named after it;
empties mark where things attach (`Tip` on the rod, `Eyepiece` on the
binoculars, ...). The esky and tackle box have a separate `Lid` mesh whose
origin is its hinge, to open by rotating about local X.

    python3.11 art/models/scripts/build_field.py [--render out/prefix]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import common as C  # noqa: E402
from lib import field as FG  # noqa: E402
from lib import furniture as F  # noqa: E402

OUT = "art/models/props/field/"


def build(name, pos=(0, 0, 0)):
    """The prop, its sockets and lid placed at pos; returns the objects."""
    make, lid = FG.PROPS[name]
    parts, sockets = make()
    title = "".join(w.capitalize() for w in name.split("_"))
    o = F.item(title, parts, pos)
    objs = [o]
    for nm, loc in sockets.items():
        if nm == "Lid" and lid:
            lo = F.item("Lid", lid(), tuple(a + b for a, b in zip(loc, pos)))
            C.set_origin(lo, tuple(a + b for a, b in zip(loc, pos)))
            objs.append(lo)
        else:
            C.empty(nm, tuple(a + b for a, b in zip(loc, pos)), size=0.03)
    return objs


def main():
    for name in FG.PROPS:
        C.reset()
        C.clear_material_cache()
        objs = build(name)
        print(name, "triangles:", C.tri_count(objs))
        C.export_glb(OUT + name + ".glb")


if __name__ == "__main__":
    main()
    C.done()
