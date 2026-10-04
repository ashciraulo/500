"""The modern 500 ladder after the Pop: Lounge/Sport, TwinAir and the Abarths.

    python3.11 art/models/scripts/build_modern.py [--render] [--only abarth500]

Writes cars/<name>/<name>.glb for each car in CARS. Wheels and exhausts are
the shared parts from build_pop.py (cars/parts/).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import common as C  # noqa: E402
from lib import fiat500_modern as F  # noqa: E402
from lib import previews  # noqa: E402
from build_pop import PAINTS, export_car  # noqa: E402

PLATE = "1CIN-500"  # made-up plate shared by every car

CARS = {
    # 1.4 16v Lounge: chrome trim, glass roof, 15" alloys
    "lounge": {
        "paint": PAINTS["rosso_passione"], "front": "pop", "wheels": "alloy15", "chrome": True,
        "roof": "glass", "dash": PAINTS["rosso_passione"],
        "seat_upper": "#d9d2c3", "seat_lower": "#2a2b2e", "exhaust": "stock",
    },
    # 1.4 Sport: body-coloured dash, roof spoiler, sport wheels, twin-tip exhaust
    "sport": {
        "paint": PAINTS["bianco"], "front": "pop", "wheels": "sport16", "spoiler": True,
        "mirror_color": "#c8c8c8", "dash": PAINTS["bianco"], "seat_upper": "#1d1d1f",
        "seat_lower": "#8a1218", "exhaust": "sport",
    },
    # 0.9 TwinAir: the two-cylinder, usually in pastel colours with a white roof
    "twinair": {
        "paint": PAINTS["verde_chiaro"], "front": "pop", "wheels": "alloy15", "roof_color": PAINTS["bianco"],
        "chrome": True, "dash": PAINTS["verde_chiaro"], "seat_upper": "#efe8da", "seat_lower": "#3a3b3e",
        "exhaust": "stock",
    },
    # Abarth 500 (2008): first turbo, red mirrors and side stripe
    "abarth500": {
        "paint": PAINTS["bianco"], "front": "abarth", "wheels": "abarth17", "spoiler": True,
        "mirror_color": "#b3121c", "stripes": "#b3121c", "dash": "#1a1a1b",
        "seat_upper": "#1a1a1b", "seat_lower": "#1a1a1b", "exhaust": "abarth_quad",
    },
    # Abarth 595 Turismo: brown leather, grey paint
    "abarth595": {
        "paint": PAINTS["grigio_carbone"], "front": "abarth", "wheels": "abarth17", "spoiler": True,
        "mirror_color": "#2a2b2e", "dash": "#1a1a1b", "seat_upper": "#5a3a24", "seat_lower": "#5a3a24",
        "exhaust": "abarth_quad",
    },
    # Abarth 595 Competizione: yellow with grey roof, black sports seats
    "abarth595c": {
        "paint": "#e9b80f", "front": "abarth", "wheels": "abarth17", "spoiler": True,
        "roof_color": "#3a3c3f", "mirror_color": "#3a3c3f", "dash": "#1a1a1b",
        "seat_upper": "#1a1a1b", "seat_lower": "#1a1a1b", "exhaust": "abarth_quad",
    },
    # Abarth 695 biposto: grey, red stripes, two seats
    "abarth695": {
        "paint": "#8c8f92", "front": "abarth", "wheels": "abarth17", "spoiler": True,
        "stripes": "#b3121c", "mirror_color": "#b3121c", "dash": "#1a1a1b",
        "seat_upper": "#1a1a1b", "seat_lower": "#b3121c", "exhaust": "abarth_quad",
    },
}


def main():
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else list(CARS)
    render = "--render" in sys.argv
    for name in only:
        spec = dict(CARS[name], name=name, plate=PLATE)
        C.reset()
        C.clear_material_cache()
        objs = F.build(spec)
        print(name, "triangles:", C.tri_count(objs))
        if render:
            out = sys.argv[sys.argv.index("--render") + 1] if len(sys.argv) > sys.argv.index("--render") + 1 \
                and not sys.argv[sys.argv.index("--render") + 1].startswith("--") else "docs/renders"
            previews.car("%s/%s" % (out, name), spec, samples=16)
        export_car("art/models/cars/%s/%s.glb" % (name, name))


if __name__ == "__main__":
    main()
    C.done()
