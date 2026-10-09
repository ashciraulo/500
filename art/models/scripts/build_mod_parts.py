"""Mod parts from the plan that had no model yet, one glb each in
art/models/cars/parts/, plus custom number plates:

  foglamps_yellow.glb  a pair of small yellow fog lamps in black bowls on a
                       low bar, at Mount_Spotlights (the lights slot, like
                       spotlights_period). Lenses use LampFog; light them
                       with the headlights.
  sump_finned.glb      the finned alloy oil sump of a big-bore/carb kit on
                       the classics (the Abarth tell), hanging under the
                       engine; origin at the classic Mount_Exhaust, so it
                       goes on with the same mount as the exhaust.
  ../plates/plate_<id>.png
                       custom WA-style number plates, 64 x 16 like the
                       plate texture in every car: swap the albedo of the
                       car's Plate material. Every number is made up.
  ../roofs/roof_<colour>.png
                       canvas roof colours for the 500C and the canvas-roof
                       classics, 32 x 32 like the roof_canvas texture: swap
                       the albedo of the car's RoofFabric material.

    python3.11 art/models/scripts/build_mod_parts.py [--render out/prefix]
    python3.11 art/models/scripts/build_mod_parts.py --plates old_black   (just those plates)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import carkit as K  # noqa: E402
from lib import common as C  # noqa: E402
from lib import textures as TX  # noqa: E402

PARTS = "art/models/cars/parts/"
PLATES = "art/models/cars/plates/"
ROOFS = "art/models/cars/roofs/"

# Canvas roof colours, the period and factory-style choices.
ROOF_COLOURS = [
    ("black", "#1f1e1d"),
    ("red", "#7a1c20"),
    ("ivory", "#cdbf9c"),
    ("navy", "#26344f"),
    ("grey", "#6a6866"),
    ("tan", "#9a7650"),
    ("bottle_green", "#2c4632"),
]

# Custom plates: (id, text, ink, background). Personalised-plate style
# words, nothing real; at most 8 characters so they fit the 64 px plate.
CUSTOM_PLATES = [
    ("standard", "1CIN-500", (0.09, 0.16, 0.50), (0.95, 0.95, 0.93)),
    ("ciao", "CIAO", (0.09, 0.16, 0.50), (0.95, 0.95, 0.93)),
    ("pop_500", "POP 500", (0.95, 0.95, 0.93), (0.08, 0.08, 0.09)),
    ("nite_drv", "NITE DRV", (0.95, 0.95, 0.93), (0.08, 0.08, 0.09)),
    ("birdo", "BIRDO", (0.08, 0.08, 0.09), (0.95, 0.95, 0.93)),
    ("slow", "SLOW 1", (0.82, 0.66, 0.24), (0.08, 0.08, 0.09)),
    ("bream", "BREAM", (0.95, 0.95, 0.93), (0.12, 0.26, 0.52)),
    # a found part: an old black-and-white sixties plate, made-up number
    ("old_black", "UFB-064", (0.93, 0.92, 0.88), (0.07, 0.07, 0.08)),
]


def foglamps():
    """Two small round yellow lamps in black bowls on stalks from a low bar;
    lenses face forward (Blender -Y), as spotlights_period does."""
    black = C.mat("FogBowl", "#141415", rough=0.45, metal=0.3)
    lens = C.mat("LampFog", "#f2c230", rough=0.1, emit="#ffd24a", emit_strength=0.4)
    trim = C.mat("FogTrim", "#c9cbcd", rough=0.25, metal=0.85)
    bits = [C.cylinder("bar", 0.01, 0.76, segs=6, axis="X", loc=(0, 0, 0.0), material=black)]
    for sx in (-1, 1):
        x = sx * 0.33          # clear of the front plate holder (0.21 half-width)
        bits.append(C.cylinder("stalk", 0.009, 0.05, segs=6, loc=(x, 0, 0.025), material=black))
        bits.append(C.sphere("bowl", 0.055, (x, 0.005, 0.105), black, segs=12, rings=6, scale=(1.0, 0.75, 1.0)))
        bits.append(C.cylinder("rim", 0.058, 0.014, segs=14, axis="Y", loc=(x, -0.036, 0.105), material=trim))
        bits.append(K.lamp_disc("lens", 0.05, 0.01, (x, -0.044, 0.105), (0, -1, 0), lens, segs=14))
        # the period black cross-strap over the lens, for daytime
        bits.append(C.box_minmax("strap", (x - 0.05, -0.051, 0.101), (x + 0.05, -0.048, 0.109), black))
    return [C.join(bits, "FogLamps")]


# The sump hangs under the engine, ahead of the classic exhaust mount
# (x 0.24 to the side, at the tail): its centre relative to that mount.
SUMP_AT = (-0.24, -0.33, -0.12)


def sump():
    """Cast alloy sump, deeper than stock, with ten fins along its length."""
    alloy = C.mat("SumpAlloy", "#b9b6ae", rough=0.4, metal=0.7)
    dark = C.mat("SumpBolt", "#3a3a3a", rough=0.5, metal=0.6)
    cx, cy, cz = SUMP_AT
    w, d, h = 0.30, 0.24, 0.07
    bits = [C.box_minmax("pan", (cx - w / 2, cy - d / 2, cz), (cx + w / 2, cy + d / 2, cz + h), alloy),
            C.box_minmax("flange", (cx - w / 2 - 0.012, cy - d / 2 - 0.012, cz + h - 0.012),
                         (cx + w / 2 + 0.012, cy + d / 2 + 0.012, cz + h), alloy)]
    for i in range(10):
        x = cx - w / 2 + 0.015 + i * (w - 0.03) / 9
        bits.append(C.box_minmax("fin", (x - 0.004, cy - d / 2 + 0.01, cz - 0.03), (x + 0.004, cy + d / 2 - 0.01, cz),
                                 alloy))
    bits.append(C.cylinder("drain", 0.012, 0.01, segs=6, loc=(cx, cy + d / 2 - 0.03, cz - 0.035), material=dark))
    for sx in (-1, 1):
        for sy in (-1, 1):
            bits.append(C.cylinder("bolt", 0.006, 0.008, segs=6,
                                   loc=(cx + sx * (w / 2 + 0.004), cy + sy * (d / 2 + 0.004), cz + h + 0.003),
                                   material=dark))
    return [C.join(bits, "Sump")]


def export(builder, name):
    C.reset()
    C.clear_material_cache()
    objs = builder()
    print(name, "triangles:", C.tri_count(objs))
    C.turn_scene_z180()
    C.export_glb(PARTS + name)


def plates():
    os.makedirs(PLATES, exist_ok=True)
    only = sys.argv[sys.argv.index("--plates") + 1].split(",") if "--plates" in sys.argv else None
    for pid, text, ink, bg in CUSTOM_PLATES:
        if only and pid not in only:
            continue
        img = TX.plate(text, name="plate_" + pid, ink=ink, bg=bg)
        img.filepath_raw = os.path.abspath(PLATES + "plate_%s.png" % pid)
        img.file_format = "PNG"
        img.save()
        print("plate", pid, text)


def roofs():
    os.makedirs(ROOFS, exist_ok=True)
    for rid, col in ROOF_COLOURS:
        # same weave and seed as the cars' own roof_canvas
        img = TX.fabric("roof_" + rid, col, seed=31, seams=False)
        img.filepath_raw = os.path.abspath(ROOFS + "roof_%s.png" % rid)
        img.file_format = "PNG"
        img.save()
        print("roof", rid)


def main():
    if "--plates" in sys.argv:
        plates()
        return
    export(foglamps, "foglamps_yellow.glb")
    export(sump, "sump_finned.glb")
    plates()
    roofs()
    if "--render" in sys.argv:
        out = sys.argv[sys.argv.index("--render") + 1]
        for builder, name, far, tgt in ((foglamps, "foglamps", 1.2, (0, 0, 0.08)),
                                        (sump, "sump", 1.0, SUMP_AT)):
            C.reset()
            C.clear_material_cache()
            builder()
            C.render_setup((720, 480), 16, world="#c9d6e0", strength=0.9)
            C.sun(rot=(50, 10, 150), energy=3.5)
            if name == "sump":
                C.camera_look((tgt[0] + 0.5, tgt[1] - 0.6, tgt[2] - 0.35), tgt, lens=40)
            else:
                C.camera_look((far * 0.6, -far, far * 0.45), tgt, lens=40)
            C.render("%s_%s.png" % (out, name))


if __name__ == "__main__":
    main()
    C.done()
