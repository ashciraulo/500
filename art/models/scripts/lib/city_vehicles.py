"""The night shift's vehicles for traffic/ (traffic_models.gd loads these
when present): a compact street sweeper, a side-loader bin truck, a 240 L
wheelie bin and a step-van food truck.

Authored in Blender with the front toward +Y (Godot -Z), the kerb side on
-X (Godot -X, as Australia drives on the left), origin on the ground at the
centre of the footprint, metres. The body colours sit on two materials the
traffic code recolours per vehicle: "Paint" (the main body) and "Livery"
(the stripe or trim). Night lamps are their own meshes, HeadL/HeadR/
TailL/TailR, so lit materials can be swapped in. Moving parts are their
own objects with their origins on their pivots:

  sweeper    BroomL, BroomR (gutter brooms, spun about their own up axis),
             Beacon/A, Beacon/B (amber roof lamps)
  bin_truck  BinArm (root on the kerb side, 3.0 m back from the bumper)
             with Rail (the 3 m guide) and Grip (the clamp, origin on its
             face, at the foot of the rail), Beacon/A, Beacon/B
  wheelie_bin  Lid (hinged at the back, its own "Lid" material)
  food_van   Awning (hinged on the top edge of the hatch, shown open), and
             empties HatchLight, SignSide (faces -X) and SignFront (faces
             forward) for the lights and Label3D signs; no baked text.

Each builder returns a list of (name, parts, pivot, parent_name) objects and
a dict of empties {name: (location, turn about Z in degrees)}.
"""
import math

from . import common as C
from . import furniture as F

bx, cyl = F.bx, F.cyl


def _m(name, col, rough=0.6, metal=0.0, **kw):
    return C.mat(name, col, rough=rough, metal=metal, **kw)


def _common():
    return {
        "tyre": _m("CV_Tyre", "#1a1a1b", 0.9),
        "rim": _m("CV_Rim", "#b9bcbd", 0.4, 0.6),
        "glass": _m("CV_Glass", "#2a3a44", 0.1, 0.3),
        "black": _m("CV_Black", "#1d1e20", 0.7),
        "grey": _m("CV_Grey", "#5c6064", 0.6, 0.3),
        "steel": _m("CV_Steel", "#a6aaac", 0.4, 0.7),
        "white": _m("CV_White", "#ecebe6", 0.5),
        "head": _m("CV_HeadLamp", "#f4f2e6", 0.2),
        "tail": _m("CV_TailLamp", "#9a1a14", 0.3),
        "amber": _m("CV_Amber", "#e8961e", 0.3),
        "plate": _m("CV_Plate", "#f2f2ee", 0.6),
    }


def _wheel(x, y, r, w, M, segs=12):
    return [cyl(r, w, (x, y, r), M["tyre"], segs=segs, axis="X"),
            cyl(r * 0.62, w + 0.01, (x, y, r), M["rim"], segs=segs, axis="X"),
            cyl(r * 0.2, w + 0.03, (x, y, r), M["grey"], segs=8, axis="X")]


def _wheels(track, ys, r, w, M):
    p = []
    for y in ys:
        for sx in (-1, 1):
            p += _wheel(sx * (track / 2), y, r, w, M)
    return p


def _lamps(front_y, rear_y, x, z_head, z_tail, M, size=(0.18, 0.12)):
    """HeadL/HeadR on the front face, TailL/TailR on the back."""
    w, h = size
    out = []
    for name, sx in (("HeadL", -1), ("HeadR", 1)):
        out.append((name, [bx((sx * x - w / 2, front_y, z_head - h / 2), (sx * x + w / 2, front_y + 0.03, z_head + h / 2),
                              M["head"])], None, None))
    for name, sx in (("TailL", -1), ("TailR", 1)):
        out.append((name, [bx((sx * x - 0.06, rear_y - 0.03, z_tail - 0.09), (sx * x + 0.06, rear_y, z_tail + 0.09),
                              M["tail"])], None, None))
    return out


def _beacons(x, y, z, M):
    out = [("Beacon", [], (0, y, z), None)]
    for name, sx in (("A", -1), ("B", 1)):
        out.append((name, [cyl(0.08, 0.04, (sx * x, y, z + 0.02), M["black"], segs=8),
                           cyl(0.065, 0.12, (sx * x, y, z + 0.1), M["amber"], segs=8, r_top=0.055)],
                    (sx * x, y, z), "Beacon"))
    return out


def _glass_box(x0, x1, y0, y1, z0, z1, M, pillar=0.06):
    """Window glass on the four faces of a cab box, with corner pillars."""
    p = [bx((x0 - 0.005, y1, z0), (x1 + 0.005, y1 + 0.01, z1), M["glass"]),          # windscreen
         bx((x0 - 0.01, y0, z0), (x0, y1, z1), M["glass"]),
         bx((x1, y0, z0), (x1 + 0.01, y1, z1), M["glass"])]
    for xx in (x0, x1 - pillar):
        p.append(bx((xx - 0.005, y1 - pillar, z0), (xx + pillar + 0.005, y1 + 0.015, z1), M["black"]))
    return p


# ------------------------------------------------------------------ sweeper

def sweeper():
    """A compact cab-forward street sweeper, 5.4 x 1.95 x 2.6: tall glass
    cab, a hopper behind it, white with an orange stripe, gutter brooms
    out front either side."""
    M = _common()
    paint = _m("Paint", "#eceae4", 0.45)
    livery = _m("Livery", "#e0661e", 0.45)
    L, W, H = 5.4, 1.95, 2.6
    yf, yr = L / 2, -L / 2
    p = []
    # chassis rails and the low deck
    p.append(bx((-0.6, yr + 0.2, 0.35), (0.6, yf - 0.3, 0.55), M["black"]))
    # the cab: lower body, glass upper, roof
    cy0 = 1.05
    p.append(bx((-W / 2, cy0, 0.45), (W / 2, yf - 0.05, 1.2), paint))
    p.append(bx((-W / 2 + 0.02, yf - 0.06, 0.5), (W / 2 - 0.02, yf, 1.15), paint))               # front panel
    p.append(bx((-W / 2, cy0, 1.2), (W / 2, yf - 0.15, 2.3), paint))                              # cab back block
    p += _glass_box(-W / 2 - 0.005, W / 2 + 0.005, cy0 + 0.25, yf - 0.15, 1.22, 2.25, M)
    p.append(bx((-W / 2 - 0.01, cy0, 2.3), (W / 2 + 0.01, yf - 0.1, 2.42), paint))               # roof
    p.append(bx((-W / 2, yf - 0.1, 1.15), (W / 2, yf, 1.22), M["black"]))                         # scuttle
    # mirrors on stalks
    for sx in (-1, 1):
        p.append(bx((sx * (W / 2 + 0.05) - 0.01, yf - 0.3, 1.6), (sx * (W / 2 + 0.05) + 0.01, yf - 0.28, 1.65),
                    M["black"]))
        p.append(bx((sx * (W / 2 + 0.12) - 0.03, yf - 0.32, 1.45), (sx * (W / 2 + 0.12) + 0.03, yf - 0.26, 1.75),
                    M["black"]))
    # the hopper: a tall box with a rounded top and a tipping seam, the stripe
    hy0, hy1 = yr + 0.05, cy0 - 0.08
    p.append(bx((-W / 2 + 0.02, hy0, 0.6), (W / 2 - 0.02, hy1, 2.2), paint))
    # the rounded back-top edge as a prism, quarter round of radius 0.3
    prof = [(hy0 + 0.3, 2.2)] + [(hy0 + 0.3 - 0.3 * math.cos(a), 2.2 + 0.3 * math.sin(a))
                                  for a in (k * math.pi / 8 for k in range(5))]
    x0, x1 = -W / 2 + 0.02, W / 2 - 0.02
    v = [(x0, y, z) for y, z in prof] + [(x1, y, z) for y, z in prof]
    n = len(prof)
    f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    f += [(i, i + 1, n + i + 1, n + i) for i in range(1, n - 1)]
    p.append(C.mesh_obj("round", v, f, paint))
    p.append(bx((-W / 2 + 0.02, hy0 + 0.3, 2.2), (W / 2 - 0.02, hy1, 2.5), paint))
    p.append(bx((-W / 2 + 0.01, hy0, 1.2), (W / 2 - 0.01, hy1, 1.42), livery))
    p.append(bx((-W / 2 + 0.01, cy0, 0.8), (W / 2 + 0.01, yf - 0.05, 0.95), livery))
    p.append(bx((-W / 2 + 0.005, hy0 + 0.6, 0.6), (-W / 2 + 0.015, hy0 + 0.62, 2.2), M["grey"]))  # door seam
    # the water tank and hose reel on the back, the suction nozzle under the middle
    p.append(bx((-0.6, yr, 0.7), (0.6, yr + 0.05, 1.9), M["grey"]))
    p.append(cyl(0.22, 0.2, (0.55, yr - 0.1, 1.5), M["grey"], segs=10, axis="Y"))                 # hose reel
    p.append(cyl(0.17, 0.22, (0.55, yr - 0.1, 1.5), M["black"], segs=10, axis="Y"))
    p.append(bx((-0.55, -0.4, 0.05), (0.55, 0.2, 0.35), M["grey"]))
    p.append(cyl(0.12, 0.6, (0.0, -0.1, 0.55), M["grey"], segs=8))
    # wheels: small front, rear under the hopper
    p += _wheels(1.72, (1.9, -1.55), 0.4, 0.28, M)
    # broom arms reaching forward to the gutter brooms
    for sx in (-1, 1):
        p.append(bx((sx * 0.7 - 0.04, yf - 0.4, 0.38), (sx * 0.7 + 0.04, 2.45, 0.44), M["grey"]))
        p.append(bx((sx * 1.0 - 0.04, 2.38, 0.12), (sx * 1.0 + 0.04, 2.52, 0.44), M["grey"]))
        p.append(bx((sx * 1.0 - 0.3, 2.41, 0.4), (sx * 0.7, 2.49, 0.44), M["grey"]))
    # plate and the step to the cab
    p.append(bx((-0.25, yf, 0.5), (0.25, yf + 0.01, 0.62), M["plate"]))
    p.append(bx((-W / 2 - 0.05, cy0 + 0.3, 0.4), (-W / 2, cy0 + 0.7, 0.45), M["steel"]))
    objs = [("Sweeper", p, (0, 0, 0), None)]
    bristle = _m("CV_Bristle", "#3a3a3a", 0.95)
    tip = _m("CV_BristleTip", "#c9a227", 0.9)
    for name, sx in (("BroomL", -1), ("BroomR", 1)):
        c = (sx * 1.0, 2.45, 0.08)
        b = [cyl(0.15, 0.08, (c[0], c[1], 0.12), M["grey"], segs=8),
             cyl(0.55, 0.06, (c[0], c[1], 0.07), bristle, segs=16, r_top=0.4),
             cyl(0.56, 0.03, (c[0], c[1], 0.02), tip, segs=16)]
        # tufts so the spin reads
        for k in range(6):
            a = k * math.tau / 6
            b.append(bx((c[0] + 0.42 * math.cos(a) - 0.05, c[1] + 0.42 * math.sin(a) - 0.05, 0.0),
                        (c[0] + 0.42 * math.cos(a) + 0.05, c[1] + 0.42 * math.sin(a) + 0.05, 0.1), tip))
        objs.append((name, b, c, None))
    objs += _lamps(yf, yr, 0.72, 0.8, 0.85, M)
    objs += _beacons(0.65, cy0 + 0.6, 2.42, M)
    return objs, {}


# ------------------------------------------------------------------ bin truck

def bin_truck():
    """A side-loader bin truck, 9.2 x 2.5 x 3.4: white cab, green compactor
    body with the hopper opening on top just behind the cab, the lift arm on
    the kerb side."""
    M = _common()
    paint = _m("Paint", "#2f7a46", 0.5)
    livery = _m("Livery", "#e8e4d4", 0.45)
    cab = _m("CV_CabWhite", "#ecebe6", 0.45)
    L, W, H = 9.2, 2.5, 3.4
    yf, yr = L / 2, -L / 2
    p = []
    p.append(bx((-0.55, yr + 0.3, 0.45), (0.55, yf - 0.3, 0.75), M["black"]))                     # chassis
    # cab: a low-entry cab-over, big windscreen, black bumper and grille
    cy0 = 2.3
    p.append(bx((-W / 2, cy0, 0.5), (W / 2, yf - 0.05, 1.55), cab))
    p.append(bx((-W / 2, cy0, 1.55), (W / 2, yf - 0.25, 2.85), cab))
    p += _glass_box(-W / 2 - 0.005, W / 2 + 0.005, cy0 + 1.0, yf - 0.25, 1.6, 2.6, M)
    p.append(bx((-W / 2 + 0.05, yf - 0.25, 1.55), (W / 2 - 0.05, yf - 0.05, 1.62), cab))
    p.append(bx((-W / 2 - 0.02, cy0, 2.85), (W / 2 + 0.02, yf - 0.2, 2.98), cab))
    p.append(bx((-W / 2, yf - 0.05, 0.35), (W / 2, yf + 0.08, 0.6), M["black"]))                  # bumper
    p.append(bx((-0.7, yf - 0.06, 0.7), (0.7, yf, 1.3), M["black"]))                              # grille
    for k in range(5):
        z = 0.78 + k * 0.11
        p.append(bx((-0.66, yf, z), (0.66, yf + 0.01, z + 0.04), M["grey"]))
    p.append(bx((-W / 2 - 0.01, cy0 + 0.1, 0.9), (W / 2 + 0.01, yf - 0.1, 1.0), livery))
    for sx in (-1, 1):
        p.append(bx((sx * (W / 2 + 0.2) - 0.04, yf - 0.4, 1.7), (sx * (W / 2 + 0.2) + 0.04, yf - 0.3, 2.3),
                    M["black"]))
        p.append(bx((sx * (W / 2) - 0.02, yf - 0.38, 2.2), (sx * (W / 2 + 0.2), yf - 0.34, 2.24), M["black"]))
        p.append(bx((sx * (W / 2) - 0.01, cy0 + 0.5, 0.5), (sx * (W / 2) + 0.01, cy0 + 0.52, 2.6), M["grey"]))
    # compactor body: the hopper box behind the cab, the tapered body, the tailgate
    hy0, hy1 = 1.1, cy0 - 0.08
    p.append(bx((-W / 2, hy0, 0.75), (W / 2, hy1, 1.6), paint))                                   # hopper floor box
    for sx in (-1, 1):
        p.append(bx((sx * W / 2 - (0.06 if sx > 0 else 0), hy0, 1.6), (sx * W / 2 + (0.06 if sx < 0 else 0), hy1, 3.3),
                    paint))
    p.append(bx((-W / 2, hy1 - 0.08, 1.6), (W / 2, hy1, 3.3), paint))
    p.append(bx((-W / 2, hy0, 1.6), (W / 2, hy0 + 0.08, 3.3), paint))
    p.append(bx((-W / 2 + 0.06, hy0 + 0.08, 1.58), (W / 2 - 0.06, hy1 - 0.08, 1.62), M["black"]))  # the dark well
    p.append(bx((-W / 2 + 0.05, hy0 + 0.1, 1.6), (W / 2 - 0.05, hy0 + 0.2, 2.6), M["steel"]))     # packer plate
    by0, by1 = yr + 0.7, hy0
    p.append(bx((-W / 2, by0, 0.75), (W / 2, by1, 3.4), paint))
    for k in range(5):                                                                             # side ribs
        y = by0 + 0.3 + k * (by1 - by0 - 0.6) / 4
        for sx in (-1, 1):
            p.append(bx((sx * (W / 2 + 0.02) - 0.03, y - 0.05, 0.85), (sx * (W / 2 + 0.02) + 0.03, y + 0.05, 3.3),
                        paint))
    p.append(bx((-W / 2 - 0.035, by0, 1.9), (W / 2 + 0.035, by1, 2.15), livery))                 # the stripe
    # tailgate with its hinge at the top and two rams
    p.append(bx((-W / 2 + 0.05, yr + 0.05, 0.65), (W / 2 - 0.05, by0, 3.35), paint))
    p.append(cyl(0.08, W - 0.2, (0, by0 - 0.05, 3.35), M["grey"], segs=8, axis="X"))
    for sx in (-1, 1):
        p.append(bx((sx * (W / 2) - 0.05, by0 - 0.2, 1.0), (sx * (W / 2) + 0.05, by0 - 0.1, 3.2), M["steel"]))
    p.append(bx((-0.3, yr + 0.02, 0.7), (0.3, yr + 0.05, 0.82), M["plate"]))
    # wheels: steer axle and tandem drive
    p += _wheels(2.1, (3.3, -1.9, -3.25), 0.52, 0.32, M)
    for sx in (-1, 1):
        for yy in (-1.9, -3.25):
            p.append(bx((sx * 1.05 - 0.16, yy - 0.62, 1.05), (sx * 1.05 + 0.16, yy + 0.62, 1.12), M["black"]))  # guards
    objs = [("BinTruck", p, (0, 0, 0), None)]
    # the lift arm: the root on the kerb side, a 3 m rail, the clamp at its foot
    root = (-W / 2, 1.6, 0.0)
    objs.append(("BinArm", [], root, None))
    rail = [bx((-W / 2 - 0.12, 1.5, 0.3), (-W / 2 - 0.02, 1.7, 3.3), M["steel"]),
            bx((-W / 2 - 0.14, 1.45, 0.3), (-W / 2 - 0.12, 1.75, 3.3), M["grey"]),
            bx((-W / 2 - 0.12, 1.45, 3.25), (-W / 2, 1.75, 3.35), M["grey"])]
    objs.append(("Rail", rail, root, "BinArm"))
    gx = -W / 2 - 0.16                                       # the clamp face, out from the rail
    grip = [bx((gx, 1.42, 0.3), (-W / 2 - 0.14, 1.78, 0.75), M["grey"])]
    for sy in (-1, 1):
        y = 1.6 + sy * 0.33
        grip.append(bx((gx - 0.5, y - 0.03, 0.45), (gx, y + 0.03, 0.55), M["black"]))
        grip.append(bx((gx - 0.52, y - 0.03 - (0.06 if sy > 0 else 0), 0.45),
                       (gx - 0.46, y + 0.03 + (0.06 if sy < 0 else 0), 0.55), M["black"]))
    objs.append(("Grip", grip, (gx, 1.6, 0.0), "BinArm"))
    objs += _lamps(yf + 0.05, yr + 0.05, 0.95, 0.75, 0.9, M, size=(0.24, 0.14))
    objs += _beacons(0.8, cy0 + 0.6, 2.98, M)
    return objs, {}


# ------------------------------------------------------------------ wheelie bin

def wheelie_bin():
    """A 240 L wheelie bin, 0.58 x 0.73 x 1.07: tapered green body, axle and
    wheels and the handle at the back (-Y, Godot +Z), the lid on its own."""
    body = _m("CV_BinGreen", "#2a5a34", 0.6)
    lid = _m("Lid", "#2a5a34", 0.55)
    M = _common()
    W, D, H = 0.58, 0.73, 1.07
    top_h = H - 0.05
    # the tub: narrower at the base, open at the top, made as a lofted shell
    b0 = (W / 2 - 0.05, D / 2 - 0.07)
    b1 = (W / 2 - 0.01, D / 2 - 0.02)
    v = []
    for (hw, hd), z in ((b0, 0.06), (b1, top_h)):
        v += [(-hw, -hd, z), (hw, -hd, z), (hw, hd, z), (-hw, hd, z)]
    f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (3, 2, 1, 0)]
    p = [C.mesh_obj("tub", v, f, body)]
    p.append(bx((-W / 2, -D / 2, top_h - 0.06), (W / 2, D / 2, top_h), body))                     # the rim
    p.append(bx((-W / 2 + 0.02, -D / 2 - 0.04, top_h - 0.05), (W / 2 - 0.02, -D / 2, top_h + 0.02), body))  # handle bar
    # the back: axle housing, wheels, foot bar
    p.append(cyl(0.035, W - 0.02, (0, -D / 2 + 0.04, 0.1), body, segs=8, axis="X"))
    for sx in (-1, 1):
        p.append(cyl(0.1, 0.05, (sx * (W / 2 - 0.0), -D / 2 + 0.04, 0.1), M["tyre"], segs=10, axis="X"))
    p.append(bx((-W / 2 + 0.06, -D / 2 + 0.02, 0.0), (W / 2 - 0.06, -D / 2 + 0.1, 0.05), body))
    # front toe at the bottom so it stands level
    p.append(bx((-W / 2 + 0.08, D / 2 - 0.12, 0.0), (W / 2 - 0.08, D / 2 - 0.06, 0.06), body))
    # a white number stencil panel on the front
    p.append(bx((-0.08, D / 2 - 0.02, 0.6), (0.08, D / 2 - 0.015, 0.68), M["white"]))
    objs = [("WheelieBin", p, (0, 0, 0), None)]
    hinge = (0, -D / 2 + 0.01, top_h)
    lp = [bx((-W / 2 - 0.01, -D / 2 + 0.01, top_h), (W / 2 + 0.01, D / 2 + 0.02, top_h + 0.04), lid),
          bx((-W / 2 + 0.03, D / 2 + 0.0, top_h - 0.04), (W / 2 - 0.03, D / 2 + 0.03, top_h + 0.03), lid),
          bx((-0.12, D / 2 + 0.02, top_h - 0.03), (0.12, D / 2 + 0.05, top_h + 0.02), lid)]        # front lip
    objs.append(("Lid", lp, hinge, None))
    return objs, {}


# ------------------------------------------------------------------ food van

def food_van():
    """A converted step van, 5.6 x 2.2 x 2.9: the serving hatch on the kerb
    side with a lit kitchen behind it (counter, menu board, coffee machine,
    flat grill), the awning propped open over the hatch."""
    M = _common()
    paint = _m("Paint", "#d8c9a0", 0.5)
    livery = _m("Livery", "#2f5a46", 0.5)
    inside = _m("CV_Inside", "#d9d4c8", 0.8)
    counter = _m("CV_Counter", "#9a9c9e", 0.35, 0.6)
    board = _m("CV_MenuBoard", "#1f2622", 0.85)
    L, W, H = 5.6, 2.2, 2.9
    yf, yr = L / 2, -L / 2
    p = []
    p.append(bx((-0.5, yr + 0.3, 0.35), (0.5, yf - 0.3, 0.55), M["black"]))
    # the box body, built round the hatch opening on -X
    hx = -W / 2
    hy0, hy1, hz0, hz1 = -1.5, 0.5, 1.05, 2.05
    by0, by1 = yr + 0.05, 1.0
    z0, z1 = 0.55, H - 0.1
    p.append(bx((hx, by0, z0), (hx + 0.05, by1, hz0), paint))                                     # below the hatch
    p.append(bx((hx, by0, hz1), (hx + 0.05, by1, z1), paint))                                     # above it
    p.append(bx((hx, by0, hz0), (hx + 0.05, hy0, hz1), paint))
    p.append(bx((hx, hy1, hz0), (hx + 0.05, by1, hz1), paint))
    p.append(bx((W / 2 - 0.05, by0, z0), (W / 2, by1, z1), paint))                                # the road side
    p.append(bx((-W / 2 + 0.05, by0, z0), (W / 2 - 0.05, by0 + 0.05, z1), paint))                 # the back
    p.append(bx((-W / 2 - 0.01, by0 - 0.01, z1), (W / 2 + 0.01, by1 + 0.02, H), paint))           # roof
    p.append(bx((-W / 2 + 0.05, by0 + 0.05, z0), (W / 2 - 0.05, by1, z0 + 0.05), inside))        # floor
    p.append(bx((-W / 2 + 0.05, by1 - 0.05, z0), (W / 2 - 0.05, by1, z1), inside))                # bulkhead
    # inside walls (so the lit kitchen reads through the hatch)
    p.append(bx((W / 2 - 0.06, by0, z0), (W / 2 - 0.05, by1, z1), inside))
    p.append(bx((-W / 2 + 0.05, by0 + 0.05, z0), (W / 2 - 0.06, by0 + 0.06, z1), inside))
    p.append(bx((-W / 2 + 0.05, by0 + 0.05, z1 - 0.01), (W / 2 - 0.06, by1 - 0.05, z1), inside))
    # the livery band round the body and the hatch frame
    p.append(bx((-W / 2 - 0.01, by0 - 0.01, 0.75), (W / 2 + 0.01, by1, 0.95), livery))
    p.append(bx((-W / 2 - 0.01, by0 - 0.01, z1 - 0.12), (W / 2 + 0.01, by1, z1), livery))
    for (a, b) in (((hx - 0.02, hy0 - 0.05, hz0 - 0.05), (hx + 0.01, hy1 + 0.05, hz0)),
                   ((hx - 0.02, hy0 - 0.05, hz1), (hx + 0.01, hy1 + 0.05, hz1 + 0.05)),
                   ((hx - 0.02, hy0 - 0.05, hz0), (hx + 0.01, hy0, hz1)),
                   ((hx - 0.02, hy1, hz0), (hx + 0.01, hy1 + 0.05, hz1))):
        p.append(bx(a, b, M["steel"]))
    p.append(bx((hx - 0.25, hy0, hz0 - 0.03), (hx + 0.05, hy1, hz0), M["steel"]))                 # serving shelf
    # inside: the counter under the hatch, the menu board on the far wall, a
    # coffee machine and a flat grill on the back bench
    p.append(bx((hx + 0.05, hy0, z0), (hx + 0.6, hy1, hz0), counter))
    p.append(bx((W / 2 - 0.65, hy0, z0), (W / 2 - 0.06, hy1, 1.0), counter))
    p.append(bx((W / 2 - 0.08, hy0 + 0.2, 1.5), (W / 2 - 0.06, hy1 - 0.2, 2.2), board))
    p.append(bx((W / 2 - 0.5, -0.5, 1.0), (W / 2 - 0.1, 0.0, 1.45), M["steel"]))                 # coffee machine
    p.append(bx((W / 2 - 0.45, -0.45, 1.3), (W / 2 - 0.4, -0.05, 1.33), M["black"]))
    for k in range(2):
        p.append(cyl(0.025, 0.06, (W / 2 - 0.42, -0.4 + k * 0.3, 1.2), M["black"], segs=6))
    p.append(bx((W / 2 - 0.6, -1.4, 1.0), (W / 2 - 0.1, -0.7, 1.05), M["black"]))                 # flat grill
    p.append(bx((W / 2 - 0.6, -1.4, 1.05), (W / 2 - 0.1, -1.37, 1.15), M["steel"]))
    p.append(bx((W / 2 - 0.6, -1.4, 1.6), (W / 2 - 0.1, -0.7, 1.95), M["steel"]))                 # range hood
    p.append(cyl(0.12, 0.15, (0.2, -1.05, H + 0.07), M["steel"], segs=8))                        # roof vent
    # the step-van front: the cab with a tall flat windscreen, a short bonnet
    p.append(bx((-W / 2, by1, z0), (W / 2, yf - 0.45, 1.25), paint))
    p.append(bx((-W / 2, by1, 1.25), (W / 2, yf - 0.6, z1), paint))
    p += _glass_box(-W / 2 - 0.005, W / 2 + 0.005, by1 + 0.4, yf - 0.6, 1.3, z1 - 0.1, M)
    p.append(bx((-W / 2, yf - 0.6, 1.25), (W / 2, yf - 0.45, 1.3), paint))
    p.append(bx((-W / 2 + 0.1, yf - 0.45, 0.45), (W / 2 - 0.1, yf - 0.05, 1.15), paint))          # bonnet
    p.append(bx((-0.55, yf - 0.06, 0.6), (0.55, yf, 1.05), M["grey"]))                            # grille
    p.append(bx((-W / 2 + 0.05, yf - 0.05, 0.35), (W / 2 - 0.05, yf + 0.05, 0.55), M["steel"]))   # bumper
    p.append(bx((-W / 2 - 0.01, by1, 0.75), (W / 2 + 0.01, yf - 0.45, 0.95), livery))
    p.append(bx((-0.25, yf + 0.05, 0.4), (0.25, yf + 0.06, 0.52), M["plate"]))
    p.append(bx((-W / 2 + 0.1, yr - 0.05, 0.35), (W / 2 - 0.1, yr + 0.05, 0.55), M["steel"]))
    p += _wheels(1.9, (1.75, -1.6), 0.42, 0.26, M)
    for sx in (-1, 1):
        for yy in (1.75, -1.6):
            p.append(bx((sx * 1.1 - 0.02, yy - 0.5, 0.88), (sx * 1.1 + 0.02, yy + 0.5, 0.95), M["black"]))
    # the back: twin doors with small windows, a seam and a handle
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.03, sx * (W / 2 - 0.12)))
        p.append(bx((x0, by0 - 0.02, z0 + 0.1), (x1, by0, z1 - 0.18), paint))
        p.append(bx((x0 + 0.15, by0 - 0.03, 1.75), (x1 - 0.15, by0 - 0.02, 2.3), M["glass"]))
    p.append(bx((-0.03, by0 - 0.025, z0 + 0.1), (0.03, by0 - 0.015, z1 - 0.18), M["black"]))
    p.append(bx((0.06, by0 - 0.06, 1.35), (0.22, by0 - 0.02, 1.4), M["steel"]))
    objs = [("FoodVan", p, (0, 0, 0), None)]
    # the awning: hinged on the hatch's top edge, propped up and out
    a = math.radians(70)
    depth = 1.0
    ca, sa = math.cos(a), math.sin(a)
    def aw(u, y, t=0.0):          # u along the awning away from the hinge
        return (hx - u * sa - t * ca, y, hz1 + 0.05 + u * ca - t * sa)
    v = []
    for t in (0.0, 0.03):
        v += [aw(0, hy0 - 0.05, t), aw(0, hy1 + 0.05, t), aw(depth, hy1 + 0.05, t), aw(depth, hy0 - 0.05, t)]
    f = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    awn = [C.mesh_obj("awning", v, f, livery)]
    for y in (hy0 + 0.05, hy1 - 0.05):                                                            # props
        awn.append(_bar(aw(depth * 0.9, y, 0.03), (hx - 0.01, y, hz0 + 0.3), 0.012, M["steel"]))
    objs.append(("Awning", awn, (hx, 0.0, hz1 + 0.05), None))
    objs += _lamps(yf + 0.05, yr, 0.82, 0.85, 1.0, M)
    empties = {
        "HatchLight": ((hx + 0.6, (hy0 + hy1) / 2, z1 - 0.15), 0),
        "SignSide": ((hx - 0.02, (hy0 + hy1) / 2, hz1 + 0.35), -90),
        "SignFront": ((0.0, yf - 0.58, z1 - 0.02), 180),
    }
    return objs, empties


def _bar(a, b, r, mat):
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder("bar", r, d.length, segs=5, material=mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (a + b) / 2
    return o


VEHICLES = {
    "sweeper": sweeper,
    "bin_truck": bin_truck,
    "wheelie_bin": wheelie_bin,
    "food_van": food_van,
}
