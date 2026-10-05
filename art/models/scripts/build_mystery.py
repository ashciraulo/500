"""The mystery's seven clues as standalone props, one glb each, named by
their ids in data/progression/mystery.json (lib/mystery.py CLUES):

  art/models/home/mystery/tape_1.glb .. shed_key.glb

and shed_reveal.glb, M.'s broadcasting table under the dust sheet in the
shed (lib/shed_reveal.py): origin at the table's footprint centre on the
floor, the wall toward -Y (Godot +Z), empties DeckLight, TxLight, Valve
and Bulb.

Origin at the prop's base centre, front toward -Y in Blender (+Z in Godot),
the same way round as the townhouse models.

    python3.11 art/models/scripts/build_mystery.py [--render out/prefix]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import mystery as MY  # noqa: E402
from lib import shed_reveal as SR  # noqa: E402

OUT = "art/models/home/mystery/"


def props():
    return list(MY.CLUES)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, build in props():
        C.reset()
        C.clear_material_cache()
        o = F.item(name, build(), (0, 0, 0))
        print(name, "triangles:", C.tri_count([o]))
        C.export_glb(OUT + name + ".glb")
    # what's under the sheet in the shed, with empties for its lamps
    C.reset()
    C.clear_material_cache()
    parts, sockets = SR.reveal()
    o = F.item("ShedReveal", parts, (0, 0, 0))
    for nm, loc in sockets.items():
        C.empty(nm, loc, size=0.05)
    print("shed_reveal triangles:", C.tri_count([o]))
    C.export_glb(OUT + "shed_reveal.glb")
    if "--render" in sys.argv:
        prefix = sys.argv[sys.argv.index("--render") + 1]
        C.reset()
        C.clear_material_cache()
        for i, (name, build) in enumerate(props()):
            F.item(name, build(), ((i % 4) * 0.22 - 0.33, (i // 4) * 0.22, 0))
        C.render_setup((960, 600), 16, world="#c9d6e0", strength=0.9)
        C.sun(rot=(50, 10, 150), energy=3.5)
        C.camera_look((0.0, -0.75, 0.55), (0.0, 0.1, 0.03), lens=40)
        C.render(prefix + "_props.png")


if __name__ == "__main__":
    main()
    C.done()
