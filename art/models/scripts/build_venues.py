"""Northbridge's cafes, bars, pubs and restaurants (lib/venues.py), one glb
each in art/models/props/venues/<id>.glb, from data/world/venues.json (where
each shopfront is, from tools/places/place_venues.py) and
tools/places/venues_src.json (how each looks).

Origin on the footpath at the building's wall, in the middle of the
shopfront; the street toward -Y in Blender (Godot +Z). Each has a
`<Name>_Col` static body (from `-colonly`) of plain boxes.

    blender -b -P art/models/scripts/build_venues.py [-- id ...] [--render out/prefix] [--night]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import venues as V  # noqa: E402

OUT = "art/models/props/venues/"


def load():
    placed = {e["id"]: e for e in json.load(open(os.path.join(C.REPO, "data/world/venues.json")))["venues"]}
    looks = {v["id"]: v.get("look", {}) for v in
             json.load(open(os.path.join(C.REPO, "tools/places/venues_src.json")))["venues"]}
    return placed, looks


def build(entry, look):
    parts, sockets, col = V.build(entry, look)
    title = "".join(w.capitalize() for w in entry["id"].split("_"))
    obj = F.item(title, [q for q in parts if q is not None], (0, 0, 0))
    cmat = C.mat("Collision", "#ff00ff")
    cobj = F.item(title + "_Col-colonly", [F.bx(lo, hi, cmat) for lo, hi in col], (0, 0, 0)) if col else None
    for nm, loc in sockets.items():
        C.empty(nm, loc, size=0.2)
    return obj, cobj


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    placed, looks = load()
    only = [a for a in args if a in placed]
    for vid in (only or sorted(placed)):
        C.reset()
        C.clear_material_cache()
        V._FONT_CACHE.clear()
        obj, cobj = build(placed[vid], looks.get(vid, {}))
        print(vid, "triangles:", C.tri_count([obj]))
        C.export_glb(OUT + vid + ".glb")
        if "--render" in args:
            prefix = args[args.index("--render") + 1]
            if cobj is not None:
                cobj.hide_render = True
            w = placed[vid]["width"]
            night = "--night" in args
            C.render_setup((960, 640), 24, world="#1a2030" if night else "#c9d6e0", strength=0.15 if night else 0.9)
            C.sun(rot=(50, 10, 210), energy=0.05 if night else 3.5)
            # the footpath and a bit of wall either side, for scale
            gnd = C.mat("PreviewGround", "#8e8a82", rough=0.95)
            C.box_minmax("ground", (-w / 2 - 4, -placed[vid]["depth"] - 3, -0.3), (w / 2 + 4, 0.0, -0.01), gnd)
            C.box_minmax("wall", (-w / 2 - 4, 0.0, -0.3), (w / 2 + 4, 6.0, 6.0), C.mat("PreviewWall", "#b8ad9a"))
            views = [((-w * 0.5 - 3.5, -9.5, 2.4), (0.5, -1.5, 1.8), 30), ((0.0, -8.0, 1.6), (0.0, 0.0, 2.0), 35)]
            for i, (cam, tgt, lens) in enumerate(views):
                C.camera_look(cam, tgt, lens=lens)
                C.render("%s_%s_%d%s.png" % (prefix, vid, i, "_night" if night else ""))


if __name__ == "__main__":
    main()
    C.done()
