"""Stage 5 landmarks for the map (lib/coast_landmarks.py), one glb each:

  art/models/props/landmarks/mole_light_north.glb, mole_light_south.glb,
  herdsman_hide.glb, trigg_surf_club.glb

plus the stage 6 river ones (lib/river_landmarks.py) and city dressing
(lib/city_dressing.py: royal_st_roller_door, lockup_garage, lane_carport,
kensington_shed .glb) and railway platform pieces (lib/station_props.py:
platform_slab(_island), platform_edge, platform_canopy, platform_bench,
station_board_<name> .glb, in art/models/props/station/).

Origin on the ground at the anchor, front toward -Y in Blender (Godot +Z).
Each has a `<Name>_Col` static body (from `-colonly`) of plain boxes and
empties for its sockets.

    python3.11 art/models/scripts/build_landmarks.py [--render out/prefix]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import city_dressing as CD  # noqa: E402
from lib import coast_landmarks as LM  # noqa: E402
from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import river_landmarks as RL  # noqa: E402
from lib import station_props as SP  # noqa: E402

OUT = "art/models/props/landmarks/"
STATION = "art/models/props/station/"
ALL = dict(LM.LANDMARKS, **RL.LANDMARKS, **CD.LANDMARKS, **SP.LANDMARKS)


def build(name):
    parts, sockets, col = ALL[name]()
    title = "".join(w.capitalize() for w in name.split("_"))
    objs = [F.item(title, parts, (0, 0, 0))]
    cmat = C.mat("Collision", "#ff00ff")
    cobj = F.item(title + "_Col-colonly", [F.bx(lo, hi, cmat) for lo, hi in col], (0, 0, 0)) if col else None
    for nm, loc in sockets.items():
        C.empty(nm, loc, size=0.2)
    return objs, cobj


VIEWS = {   # camera, target, lens: front three-quarter and a closer look
    "mole_light_north": [((-9, -14, 6), (0, 0, 4.6), 40), ((-2.5, -4.5, 9.5), (0, 0, 8.2), 40)],
    "mole_light_south": [((9, -14, 6), (0, 0, 4.6), 40)],
    "herdsman_hide": [((-9, -9, 5), (0.5, 3.0, 1.2), 32), ((1.0, 6.0, 2.4), (0.0, -1.0, 1.4), 30),
                      ((1.0, 0.9, 1.95), (-0.4, -1.2, 1.45), 22)],
    "kent_st_weir": [((-30, -34, 12), (0, 0, 0.0), 32), ((-8, -9, 2.5), (-2, 0, 0.0), 30),
                     ((28, -12, 4), (24, -2, 0.0), 32), ((-1.0, -0.8, 3.0), (6, 0.4, 2.0), 30)],
    "jetty_rail": [((-5, 3, 2.5), (0, -5, 0.5), 32)],
    "jetty_lamp": [((-3, -3, 2.5), (0, 0, 1.8), 32)],
    "pelican_fence": [((6, -14, 3), (10, 0, 0.9), 32), ((10, -2.2, 1.4), (10, 0, 1.3), 30)],
    "pelican_lookout": [((-4, -7, 3), (0, 0, 0.6), 32), ((2.3, -0.3, 1.6), (1.55, -1.15, 1.5), 30)],
    "pelican_sailing_club": [((-18, -26, 9), (0, -2, 2.0), 32), ((14, -14, 3), (2, -5, 2.5), 32)],
    "trigg_surf_club": [((-26, -30, 10), (0, 0, 4.0), 32), ((22, -18, 5), (4, -6, 4.5), 32)],
    "royal_st_roller_door": [((-5, -9, 2.5), (-0.6, 0, 1.8), 32), ((1.5, -3.5, 1.4), (0.3, 0, 1.2), 30)],
    "lockup_garage": [((-6, -10, 3.5), (0, 0, 1.2), 30), ((1.2, -6, 1.5), (0, 0.5, 1.0), 28)],
    "lane_carport": [((-6, -9, 3.5), (0, 0, 1.2), 30), ((5, 4, 2.5), (0, 0, 1.0), 30)],
    "kensington_shed": [((-6, -10, 3.5), (0, 0, 1.2), 30), ((8, -2, 2.0), (0, -0.4, 1.4), 30)],
    "platform_slab": [((-7, -11, 4), (0, 0, 0.6), 32), ((-3.2, -6.5, 1.6), (-1.6, -3, 0.95), 30)],
    "platform_slab_island": [((-8, -12, 4.5), (0, 0, 0.6), 32)],
    "platform_edge": [((-2, -3, 1.5), (0.4, 0, 0), 32)],
    "platform_canopy": [((-8, -12, 4), (0, 0, 2.4), 32), ((-1.5, -2, 1.6), (0.5, 2, 3.4), 28)],
    "platform_bench": [((-1.6, -2.4, 1.2), (0, 0, 0.45), 32)],
    "station_board_perth": [((-1.5, -3.5, 2.0), (0, 0, 2.0), 32), ((1.5, 3.5, 2.0), (0, 0, 2.0), 32)],
    "station_board_perth_underground": [((-1.5, -4.5, 2.0), (0, 0, 2.0), 32)],
    "station_board_elizabeth_quay": [((-1.5, -4.5, 2.0), (0, 0, 2.0), 32)],
}


def main():
    only = [a for a in sys.argv[sys.argv.index("--") + 1:] if a in ALL] if "--" in sys.argv else []
    for name in (only or ALL):
        C.reset()
        C.clear_material_cache()
        objs, cobj = build(name)
        print(name, "triangles:", C.tri_count(objs))
        out = STATION if name in SP.LANDMARKS else OUT
        os.makedirs(os.path.join(C.REPO, out), exist_ok=True)
        C.export_glb(out + name + ".glb")
        if "--render" in sys.argv:
            prefix = sys.argv[sys.argv.index("--render") + 1]
            if cobj is not None:
                cobj.hide_render = True
            C.render_setup((960, 640), 24, world="#c9d6e0", strength=0.9)
            C.sun(rot=(50, 10, 210), energy=3.5)
            for i, (cam, tgt, lens) in enumerate(VIEWS[name]):
                C.camera_look(cam, tgt, lens=lens)
                C.render("%s_%s_%d.png" % (prefix, name, i))


if __name__ == "__main__":
    main()
    C.done()
