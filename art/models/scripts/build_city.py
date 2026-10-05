"""The night shift's city vehicles for traffic/ (lib/city_vehicles.py), one
glb each:

  art/models/props/city/sweeper.glb, bin_truck.glb, wheelie_bin.glb,
  food_van.glb

Front toward +Y in Blender (-Z in Godot), kerb side on -X, origin on the
ground at the centre of the footprint. Moving parts are their own nodes
with origins on their pivots; sockets are empties.

    python3.11 art/models/scripts/build_city.py [--render out/prefix]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import city_vehicles as CV  # noqa: E402
from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402

OUT = "art/models/props/city/"


def build(name, offset=None):
    """Build one vehicle. For exports its nodes sit at the top of the scene
    (Godot's scene root is the file); for previews they hang off a root
    empty moved to `offset`."""
    objs, empties = CV.VEHICLES[name]()
    root = C.empty(name, (0, 0, 0), size=0.3) if offset is not None else None
    made = {}
    for nm, parts, pivot, parent in objs:
        if parts:
            o = F.item(nm, parts, (0, 0, 0))
            bpy.context.view_layer.update()   # single-part items keep a stale matrix
            if pivot is None:   # lamps: origin at their own centre
                from mathutils import Vector
                vs = [o.matrix_world @ v.co for v in o.data.vertices]
                pivot = sum(vs, Vector()) / len(vs)
            C.set_origin(o, pivot)
        else:
            o = C.empty(nm, pivot, size=0.1)
        made[nm] = (o, parent)
    bpy.context.view_layer.update()
    for nm, (o, parent) in made.items():
        p = made[parent][0] if parent else root
        if p is None:
            continue
        mw = o.matrix_world.copy()
        o.parent = p
        o.matrix_world = mw
        bpy.context.view_layer.update()
    for nm, (loc, rz) in empties.items():
        e = C.empty(nm, loc, size=0.1)
        e.rotation_euler = (0, 0, math.radians(rz))
        e.parent = root
    # shift the whole vehicle once everything hangs off the root
    if root is not None:
        root.location = offset
    bpy.context.view_layer.update()
    tris = C.tri_count([o for o, _ in made.values() if o.type == "MESH"])
    return root, tris


def main():
    os.makedirs(os.path.join(C.REPO, OUT), exist_ok=True)
    for name in CV.VEHICLES:
        C.reset()
        C.clear_material_cache()
        root, tris = build(name)
        print(name, "triangles:", tris)
        C.export_glb(OUT + name + ".glb")
    if "--render" in sys.argv:
        prefix = sys.argv[sys.argv.index("--render") + 1]
        # each vehicle from the kerb side, front three-quarter, then the back
        size = {"sweeper": 6.5, "bin_truck": 10.5, "wheelie_bin": 2.0,
                "food_van": 7.0}
        for name, d in size.items():
            C.reset()
            C.clear_material_cache()
            build(name, (0, 0, 0))
            h = {"wheelie_bin": 0.5}.get(name, 1.3)
            C.render_setup((960, 600), 24, world="#c9d6e0", strength=0.9)
            C.sun(rot=(50, 10, 210), energy=3.5)
            C.camera_look((-0.8 * d, 0.75 * d, 0.45 * d), (0, 0, h), lens=35)
            C.render(prefix + "_" + name + "_front.png")
            C.camera_look((0.75 * d, -0.8 * d, 0.4 * d), (0, 0, h), lens=35)
            C.render(prefix + "_" + name + "_back.png")

if __name__ == "__main__":
    main()
    C.done()
