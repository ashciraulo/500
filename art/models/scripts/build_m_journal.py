"""M.'s 1979 field journal and its props (lib/m_journal.py), one glb each in
art/models/home/mystery/:

  m_journal.glb          the journal closed: Journal (back board, pages) with
                         a child Cover whose origin is on the spine hinge;
                         swing it about its local Z in Godot (Blender Y) to
                         open it. Open, the top page shows the frogmouth.
  m_page_<bird>.glb      one loose page per wrong night bird: frogmouth,
                         magpie, swan, cockatoos, ibis, boobook, grey_bird
                         (the last in the player's blue biro, no year)
  boobook_hollow.glb     the dead marri stump with the taped nest, empty
                         Bird on the hollow's lip
  bream_tag.glb          the yellow 1979 dart tag; origin at the barb

Origin at the base centre, front toward -Y in Blender (+Z in Godot).

    python3.11 art/models/scripts/build_m_journal.py [--render out/prefix]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import m_journal as MJ  # noqa: E402

OUT = "art/models/home/mystery/"


def build_journal(pos=(0, 0, 0)):
    body, cover, hinge = MJ.journal()
    j = F.item("Journal", body, pos)
    c = F.item("Cover", cover, pos)
    bpy.context.view_layer.update()
    C.set_origin(c, (hinge[0] + pos[0], hinge[1] + pos[1], hinge[2] + pos[2]))
    mw = c.matrix_world.copy()
    c.parent = j
    c.matrix_world = mw
    return j, c


def build_hollow(pos=(0, 0, 0)):
    parts, sockets = MJ.boobook_hollow()
    o = F.item("BoobookHollow", parts, pos)
    for nm, loc in sockets.items():
        C.empty(nm, tuple(a + b for a, b in zip(loc, pos)), size=0.05)
    return o


def fresh():
    C.reset()
    C.clear_material_cache()


def main():
    fresh()
    j, _ = build_journal()
    print("m_journal triangles:", C.tri_count([o for o in bpy.data.objects if o.type == "MESH"]))
    C.export_glb(OUT + "m_journal.glb")
    for bird in MJ.BIRDS:
        fresh()
        F.item("Page_" + bird, MJ.page(bird), (0, 0, 0))
        C.export_glb(OUT + "m_page_" + bird + ".glb")
    fresh()
    o = build_hollow()
    print("boobook_hollow triangles:", C.tri_count([o]))
    C.export_glb(OUT + "boobook_hollow.glb")
    fresh()
    F.item("BreamTag", MJ.bream_tag(), (0, 0, 0))
    C.export_glb(OUT + "bream_tag.glb")

    if "--render" in sys.argv:
        prefix = sys.argv[sys.argv.index("--render") + 1]
        # the journal, closed and open, with the pages laid out round it
        fresh()
        build_journal((0.3, 0.12, 0))
        _, c = build_journal((0.02, 0.0, 0))
        c.rotation_euler.y = math.radians(-178)
        for i, bird in enumerate(MJ.BIRDS):
            F.item("Page_" + bird, MJ.page(bird), (-0.36 + (i % 4) * 0.165, 0.24 + (i // 4) * 0.215, 0),
                   rot=(i % 3 - 1) * 3)
        F.item("BreamTag", MJ.bream_tag(), (0.26, -0.05, 0.0))
        F.item("Desk", [F.bx((-0.6, -0.3, -0.02), (0.5, 0.75, 0.0), MJ._m("DeskTop", "#6d5138", 0.7))], (0, 0, 0))
        C.render_setup((960, 760), 24, world="#c9d6e0", strength=0.9)
        C.sun(rot=(40, 10, 160), energy=3.5)
        C.camera_look((-0.05, -0.32, 0.95), (-0.05, 0.25, 0.0), lens=34)
        C.render(prefix + "_journal.png")
        C.camera_look((-0.12, -0.02, 0.36), (-0.12, 0.06, 0.0), lens=40)
        C.render(prefix + "_journal_close.png")
        C.camera_look((0.26, -0.12, 0.1), (0.26, -0.02, 0.0), lens=60)
        C.render(prefix + "_tag.png")
        fresh()
        build_hollow()
        C.render_setup((760, 960), 24, world="#c9d6e0", strength=0.9)
        C.sun(rot=(40, 10, 160), energy=3.0)
        C.camera_look((0.6, -2.0, 1.3), (0, 0, 0.85), lens=45)
        C.render(prefix + "_hollow.png")
        C.camera_look((0.12, -0.75, 1.0), (0, -0.19, 0.9), lens=50)
        C.render(prefix + "_hollow_close.png")


if __name__ == "__main__":
    main()
    C.done()
