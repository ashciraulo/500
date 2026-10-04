"""2013 Fiat 500 Pop 1.2 (the starter car) plus its swappable parts.

    blender -b -P tools/blender/build_pop.py            # or: python tools/blender/build_pop.py
    ... -- --render                                      # also write preview renders

Writes cars/pop/pop.glb, cars/pop/parts/*.glb, cars/paints.json.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import common as C  # noqa: E402
from lib import fiat500_modern as F  # noqa: E402
from lib import previews  # noqa: E402
from lib import wheels as W  # noqa: E402

# Period-correct 2013 colours for the 500 (approximate sRGB).
PAINTS = {
    "grigio": "#727477",
    "bianco": "#f2f0ea",
    "rosso_passione": "#b3121c",
    "nero": "#151515",
    "blu_volare": "#2e4a74",
    "grigio_carbone": "#4a4c4f",
    "argento": "#b7b9bb",
    "giallo": "#e7c51a",
    "verde_chiaro": "#9fc6a8",
    "azzurro": "#8fb8d6",
    "beige": "#d9c9a8",
    "arancio": "#dd6a20",
    "rosa": "#e7a8b8",
}

# Ash's own car: grey 2013 Pop, sun-faded bonnet and roof, black mirror caps,
# silver Pop fascia under a fuzzy dash mat, phone holder on the centre vent,
# gaffer tape on the driver's backrest bolster and a scuffed cushion.
POP = {
    "name": "pop",
    "paint": PAINTS["grigio"],
    "wear": 1.0,
    "front": "pop",
    "wheels": "pop_trim",
    "chrome": False,
    "mirror_color": "#161617",
    "dash": "#b9b6af",
    "seat_upper": "#2a2b2e",
    "seat_lower": "#5e6064",
    "seat_wear": True,
    "phone_holder": True,
    "plate": "1CIN-500",  # made-up plate; never the real one
}


def main():
    C.reset()
    objs = F.build(POP)
    print("pop triangles:", C.tri_count(objs))
    if "--render" in sys.argv:
        previews.car("docs/renders/pop", POP)
    export_car("art/models/cars/pop/pop.glb")

    # Swappable parts: one glb each, origin at the wheel centre / exhaust mount.
    # In Godot the car's left is -X, so the left wheel's face points to -X.
    for style in ("pop_trim", "steel", "alloy15", "sport16", "abarth17", "turbine16", "pepper15"):
        for side, right in (("l", True), ("r", False)):
            C.reset()
            C.clear_material_cache()
            W.build("Wheel", style, right=right)
            C.export_glb("art/models/cars/parts/wheel_%s_%s.glb" % (style, side))
    for style in ("stock", "sport", "twin", "abarth_quad"):
        C.reset()
        C.clear_material_cache()
        F.exhaust(style)
        C.turn_scene_z180()
        C.export_glb("art/models/cars/parts/exhaust_%s.glb" % style)

    path = os.path.join(C.REPO, "art", "models", "cars", "paints.json")
    with open(path, "w") as fh:
        json.dump(PAINTS, fh, indent=2)
        fh.write("\n")


def export_car(path):
    """Drop preview-only objects and the wheels (the car scene instances wheel
    glbs under its suspension nodes), turn to face -Z and export."""
    import bpy
    for o in list(bpy.data.objects):
        if o.name.startswith(("Wheel_", "Preview", "Sun")):
            bpy.data.objects.remove(o, do_unlink=True)
    C.turn_scene_z180()
    C.export_glb(path)


if __name__ == "__main__":
    main()
    C.done()
