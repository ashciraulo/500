"""Found-only accessories that bolt onto any car, one glb each in
art/models/cars/parts/ (origin at the car's mount empty, front toward -Z):

  roofrack_surf.glb      chrome gutter rack with a mini-mal surfboard
                         strapped on, at Mount_Roof
  spotlights_period.glb  a pair of round 1960s driving lamps on a bar,
                         at Mount_Spotlights

    python3.11 art/models/scripts/build_accessories.py [--render]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

from lib import carkit as K  # noqa: E402
from lib import common as C  # noqa: E402

PARTS = "art/models/cars/parts/"


def roofrack_surf():
    """Rack feet stand on the roof either side of the mount (the 500's roof
    falls ~5 cm to the gutters), two chrome bars across, and a 7'0" board
    nose-forward (Blender -Y) with its fin up, held by two straps."""
    chrome = C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9)
    rubber = C.mat("RackRubber", "#1c1c1d", rough=0.9)
    board_mat = C.mat("Surfboard", "#efe6cf", rough=0.4)
    stripe = C.mat("SurfStripe", "#2f7f8a", rough=0.4)
    strap = C.mat("Strap", "#c4372b", rough=0.9)
    bits = []
    for y in (-0.42, 0.42):
        bits.append(C.cylinder("bar", 0.014, 1.10, segs=8, axis="X", loc=(0, y, 0.085), material=chrome))
        for sx in (-1, 1):
            foot = C.box_minmax("foot", (sx * 0.52 - 0.03, y - 0.04, -0.05), (sx * 0.52 + 0.03, y + 0.04, 0.0), rubber)
            post = C.cylinder("post", 0.012, 0.13, segs=6, loc=(sx * 0.52, y, 0.03), material=chrome)
            bits += [foot, post]
    rack = C.join(bits, "RoofRack")

    # board: an elongated, slightly rockered ellipse lofted in plan
    length, width, thick = 2.13, 0.56, 0.07
    n = 16
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n                                   # 0 nose .. 1 tail
        y = -length / 2 + t * length
        # widest just behind the middle, pointed nose, rounded square tail
        half = width / 2 * (math.sin(math.pi * min(1.0, t * 1.05)) ** 0.55 if t < 0.95 else 0.55)
        half = max(half, 0.02)
        rocker = 0.06 * (1 - t) ** 3 + 0.02 * t ** 4
        z0 = 0.10 + rocker
        for x, z in ((-half, z0 + thick * 0.35), (-half * 0.8, z0 + thick), (half * 0.8, z0 + thick),
                     (half, z0 + thick * 0.35), (half * 0.8, z0), (-half * 0.8, z0)):
            verts.append((x, y, z))
    ring = 6
    for i in range(n):
        for j in range(ring):
            a, b = i * ring + j, i * ring + (j + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    faces.append(tuple(range(ring - 1, -1, -1)))
    faces.append(tuple(n * ring + j for j in range(ring)))
    mesh = bpy.data.meshes.new("Surfboard")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    board = bpy.data.objects.new("Surfboard", mesh)
    C.link(board)
    board.data.materials.append(board_mat)
    stripe_bar = C.box_minmax("stringer", (-0.006, -length / 2 + 0.12, 0.10 + thick + 0.001),
                              (0.006, length / 2 - 0.06, 0.10 + thick + 0.004), stripe)
    fin = C.box_minmax("fin", (-0.006, length / 2 - 0.30, 0.10 + thick), (0.006, length / 2 - 0.12, 0.10 + thick + 0.11),
                       stripe)
    straps = [C.box_minmax("strap", (-0.31, y - 0.02, 0.095), (0.31, y + 0.02, 0.10 + thick + 0.008), strap)
              for y in (-0.42, 0.42)]
    board = C.join([board, stripe_bar, fin] + straps, "Surfboard")
    return [rack, board]


def spotlights():
    """Two chrome-backed round lamps (Carello-style) on short stalks from a
    bar that clamps to the bumper; lenses face forward (Blender -Y)."""
    chrome = C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9)
    lens = C.mat("LampSpot", "#fff3d6", rough=0.1, emit="#fff1c8", emit_strength=0.4)
    dark = C.mat("SpotDark", "#202022", rough=0.6)
    bits = [C.cylinder("bar", 0.012, 0.70, segs=6, axis="X", loc=(0, 0, 0.0), material=dark)]
    for sx in (-1, 1):
        x = sx * 0.30
        bits.append(C.cylinder("stalk", 0.01, 0.07, segs=6, loc=(x, 0, 0.035), material=dark))
        bits.append(C.cylinder("rim", 0.075, 0.05, segs=14, axis="Y", loc=(x, -0.02, 0.14), material=chrome))
        bits.append(C.cylinder("bowl", 0.05, 0.05, segs=12, axis="Y", loc=(x, 0.025, 0.14), material=chrome))
        bits.append(K.lamp_disc("lens", 0.068, 0.012, (x, -0.046, 0.14), (0, -1, 0), lens, segs=14))
        bits.append(C.box_minmax("grille_bar", (x - 0.068, -0.054, 0.137), (x + 0.068, -0.05, 0.143), chrome))
    return [C.join(bits, "Spotlights")]


def export(builder, name):
    C.reset()
    C.clear_material_cache()
    objs = builder()
    print(name, "triangles:", C.tri_count(objs))
    C.turn_scene_z180()
    C.export_glb(PARTS + name)


def main():
    export(roofrack_surf, "roofrack_surf.glb")
    export(spotlights, "spotlights_period.glb")
    if "--render" in sys.argv:
        out = sys.argv[sys.argv.index("--render") + 1]
        for builder, name in ((roofrack_surf, "roofrack"), (spotlights, "spotlights")):
            C.reset()
            C.clear_material_cache()
            builder()
            C.render_setup((720, 480), 16, world="#c9d6e0", strength=0.9)
            C.sun(rot=(50, 10, 150), energy=3.5)
            far = 3.2 if name == "roofrack" else 1.3
            C.camera_look((far * 0.8, -far, far * 0.6), (0, 0, 0.12), lens=40)
            C.render("%s_%s.png" % (out, name))


if __name__ == "__main__":
    main()
    C.done()
