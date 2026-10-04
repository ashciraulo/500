"""Field gear for bird-watching and fishing: binoculars, a film camera and
roll, a fishing rod with an Alvey sidecast reel, an esky and a tackle box.

Every function returns (parts, sockets): parts authored like furniture.py
(front toward -Y, origin at the base centre, metres) and sockets, a dict of
empty name -> location (for example the rod tip the line hangs from).
Sizes are the real things': 7x50 porro binoculars, a 1970s manual SLR
with a 50 mm lens, a 2.1 m spin rod, a 25 litre esky.
"""
import math

from . import common as C
from . import furniture as F

bx, cyl = F.bx, F.cyl


def _m(name, col, rough=0.6, metal=0.0):
    return C.mat("FG_" + name, col, rough=rough, metal=metal)


def _mats():
    return {
        "rubber": _m("Rubber", "#1b1b1c", 0.9),
        "body": _m("BinoBody", "#26282a", 0.55),
        "paint": _m("BinoPaint", "#3d4a3a", 0.6),           # army-green enamel
        "scratch": _m("Scratch", "#b9b6ad", 0.35, 0.8),      # bare metal under the paint
        "lens": _m("LensCoat", "#4d6a8c", 0.08, 0.3),        # blue-purple coated glass
        "chrome": _m("Chrome", "#cfd1d3", 0.2, 0.9),
        "leather": _m("Leatherette", "#151515", 0.85),
        "cork": _m("Cork", "#b88c5a", 0.95),
        "blank": _m("RodBlank", "#5a1d1a", 0.35),            # wine-red glass blank
        "wrap": _m("RodWrap", "#d8c27a", 0.5),
        "bakelite": _m("Bakelite", "#3a2618", 0.4),
        "line": _m("Line", "#d9e2d0", 0.4),
        "esky": _m("EskyBlue", "#2f62a8", 0.5),
        "esky_white": _m("EskyWhite", "#ecebe5", 0.55),
        "ice": _m("Ice", "#d8edf4", 0.15),
        "tackle": _m("TackleGreen", "#3f6b3a", 0.5),
        "tackle_dark": _m("TackleDark", "#26402a", 0.6),
        "film": _m("FilmYellow", "#e2b21f", 0.45),
        "film_black": _m("FilmBlack", "#1a1a1a", 0.5),
        "film_tongue": _m("FilmBase", "#4a2c1a", 0.4),
    }


def _y_cyl(r, y0, y1, x, z, mat, segs=10, r_top=None):
    """Cylinder along Y from y0 to y1."""
    return cyl(r, abs(y1 - y0), (x, (y0 + y1) / 2, z), mat, segs=segs, r_top=r_top, axis="Y")


def binoculars(scratched=True):
    """7x50 porro-prism binoculars, objectives toward -Y, eyepieces at +Y.
    The starter pair has an M scratched through the paint on the right
    prism cover."""
    M = _mats()
    p = []
    eye_z, obj_z = 0.050, 0.038
    for sx in (-1, 1):
        # prism housing, the paint over a darker body
        x0, x1 = sorted((sx * 0.022, sx * 0.088))
        p.append(bx((x0, -0.015, 0.012), (x1, 0.058, 0.074), M["paint"]))
        x0, x1 = sorted((sx * 0.030, sx * 0.080))
        p.append(bx((x0, 0.058, 0.026), (x1, 0.064, 0.068), M["body"]))
        # objective barrel and its coated lens
        p.append(_y_cyl(0.031, -0.105, -0.012, sx * 0.064, obj_z, M["rubber"], segs=12))
        p.append(_y_cyl(0.034, -0.110, -0.096, sx * 0.064, obj_z, M["body"], segs=12))
        p.append(_y_cyl(0.026, -0.1105, -0.109, sx * 0.064, obj_z, M["lens"], segs=12))
        # eyepiece and rubber cup
        p.append(_y_cyl(0.016, 0.060, 0.082, sx * 0.032, eye_z, M["body"], segs=10))
        p.append(_y_cyl(0.019, 0.082, 0.098, sx * 0.032, eye_z, M["rubber"], segs=10))
        p.append(_y_cyl(0.011, 0.0985, 0.099, sx * 0.032, eye_z, M["lens"], segs=10))
        # strap lug
        p.append(bx((sx * 0.088 - 0.004, 0.030, 0.050), (sx * 0.088 + 0.004, 0.040, 0.062), M["chrome"]))
    # centre hinge and focus wheel
    p.append(_y_cyl(0.012, -0.020, 0.066, 0, 0.052, M["body"], segs=8))
    p.append(cyl(0.015, 0.022, (0, 0.040, 0.066), M["rubber"], segs=12, axis="X"))
    if scratched:
        # an M scratched into the paint on top of the right-hand cover (-X
        # in Blender is the right hand once the export turns it round)
        top = 0.0745
        cx, cy = -0.055, 0.022
        strokes = [((-0.012, -0.010), (-0.012, 0.010)), ((-0.012, 0.010), (0.0, -0.002)),
                   ((0.0, -0.002), (0.012, 0.010)), ((0.012, 0.010), (0.012, -0.010))]
        for (ax, ay), (bx_, by) in strokes:
            L = math.hypot(bx_ - ax, by - ay)
            s = C.box("scratch", (0.0016, L, 0.0006), (cx + (ax + bx_) / 2, cy + (ay + by) / 2, top), M["scratch"])
            s.rotation_euler.z = math.atan2(bx_ - ax, by - ay) * -1
            p.append(s)
    return p, {"Eyepiece": (0, 0.099, eye_z), "Objective": (0, -0.111, obj_z)}


def camera():
    """A 1970s manual 35 mm SLR (the shape of a K1000): black leatherette,
    chrome top plate and prism hump, a 50 mm lens toward -Y."""
    M = _mats()
    p = []
    w, d = 0.143, 0.050
    p.append(bx((-w / 2, -d / 2, 0.0), (w / 2, d / 2, 0.064), M["leather"]))
    p.append(bx((-w / 2, -d / 2 - 0.001, 0.0), (w / 2, d / 2 + 0.001, 0.006), M["chrome"]))
    p.append(bx((-w / 2, -d / 2, 0.064), (w / 2, d / 2, 0.088), M["chrome"]))
    # pentaprism hump: a wedge over the lens axis
    hump = C.mesh_obj("hump", [(-0.030, -0.025, 0.088), (0.030, -0.025, 0.088), (0.030, 0.025, 0.088),
                               (-0.030, 0.025, 0.088), (-0.020, -0.006, 0.112), (0.020, -0.006, 0.112),
                               (0.020, 0.012, 0.112), (-0.020, 0.012, 0.112)],
                      [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
                      M["chrome"])
    p.append(hump)
    p.append(bx((-0.018, d / 2, 0.080), (0.018, d / 2 + 0.004, 0.100), M["film_black"]))   # eyepiece
    # lens: mount ring, focus ring, front glass
    p.append(_y_cyl(0.031, -d / 2 - 0.008, -d / 2, 0, 0.040, M["chrome"], segs=14))
    p.append(_y_cyl(0.030, -d / 2 - 0.042, -d / 2 - 0.008, 0, 0.040, M["leather"], segs=14))
    p.append(_y_cyl(0.027, -d / 2 - 0.052, -d / 2 - 0.042, 0, 0.040, M["chrome"], segs=14))
    p.append(_y_cyl(0.020, -d / 2 - 0.0525, -d / 2 - 0.0515, 0, 0.040, M["lens"], segs=14))
    # dials: rewind knob, shutter speed, advance lever
    p.append(cyl(0.011, 0.010, (0.050, 0.004, 0.093), M["chrome"], segs=10))
    p.append(cyl(0.012, 0.007, (-0.040, 0.004, 0.0915), M["film_black"], segs=10))
    p.append(bx((-0.068, 0.002, 0.0905), (-0.040, 0.010, 0.0935), M["chrome"]))
    return p, {"Lens": (0, -d / 2 - 0.053, 0.040), "Viewfinder": (0, d / 2 + 0.004, 0.090)}


def film_roll():
    """A 35 mm film canister standing on end, the leader poking out."""
    M = _mats()
    p = [cyl(0.0125, 0.046, (0, 0, 0.027), M["film"], segs=12),
         cyl(0.0122, 0.008, (0, 0, 0.003), M["film_black"], segs=12),
         cyl(0.0122, 0.004, (0, 0, 0.052), M["film_black"], segs=12),
         cyl(0.004, 0.006, (0, 0, 0.057), M["film_black"], segs=8),
         # the felt-lipped slot and the film leader poking out of it
         bx((-0.0128, -0.0135, 0.010), (-0.0040, -0.0115, 0.044), M["film_black"]),
         bx((-0.034, -0.0134, 0.016), (-0.006, -0.0126, 0.040), M["film_tongue"])]
    return p, {}


def _ring(r, t, centre, mat, segs=8):
    """A guide ring standing in the XZ plane: short bars round a circle."""
    cx, cy, cz = centre
    out = []
    for i in range(segs):
        a = 2 * math.pi * (i + 0.5) / segs
        seg = 2 * r * math.sin(math.pi / segs) + t
        b = C.box("ring", (seg, t, t), (cx + r * math.cos(a), cy, cz + r * math.sin(a)), mat)
        b.rotation_euler.y = -(a + math.pi / 2)
        out.append(b)
    return out


def fishing_rod():
    """A 2.1 m spin rod lying along -Y from the butt (origin), with an Alvey
    sidecast reel under the cork grip, its spool axis across the rod as it
    sits for retrieving, the rod resting on the ground on its reel. Sockets:
    the tip the line hangs from, the reel, the grip."""
    M = _mats()
    p = []
    L = 2.1
    z = 0.143       # resting on the reel: the rod's axis height when laid down
    p.append(_y_cyl(0.015, 0.0, -0.012, 0, z, M["rubber"], segs=10))                 # butt cap
    p.append(_y_cyl(0.0135, -0.012, -0.30, 0, z, M["cork"], segs=10, r_top=0.0125))  # rear grip
    p.append(_y_cyl(0.011, -0.30, -0.40, 0, z, M["chrome"], segs=10))                # reel seat
    p.append(_y_cyl(0.012, -0.40, -0.52, 0, z, M["cork"], segs=10))                 # fore grip
    # the blank tapers to the tip in a few sections
    ys = [-0.52, -0.95, -1.40, -1.80, -L]
    rs = [0.0070, 0.0055, 0.0040, 0.0026, 0.0014]
    for (y0, y1), (r0, r1) in zip(zip(ys, ys[1:]), zip(rs, rs[1:])):
        p.append(_y_cyl(r0, y0, y1, 0, z, M["blank"], segs=8, r_top=r1))
    # runner guides: thread wraps and rings standing up off the blank
    for i, (y, ring) in enumerate(((-0.70, 0.016), (-1.00, 0.012), (-1.28, 0.010), (-1.55, 0.008),
                                   (-1.80, 0.007), (-2.00, 0.006))):
        r = 0.0068 - 0.0009 * i
        p.append(_y_cyl(r + 0.0012, y - 0.012, y + 0.012, 0, z, M["wrap"], segs=8))
        p.append(bx((-0.0008, y - 0.002, z - r - ring * 1.4), (0.0008, y + 0.002, z - r), M["chrome"]))
        p += _ring(ring, 0.0012, (0, y, z - r - ring * 1.4 - ring), M["chrome"])
    p.append(_y_cyl(0.0022, -L + 0.004, -L - 0.004, 0, z, M["chrome"], segs=8))      # tip top
    # Alvey reel hanging under the seat: foot, drum, spool face, handle
    ry, rz = -0.35, z - 0.085
    p.append(bx((-0.006, ry - 0.030, z - 0.034), (0.006, ry + 0.030, z - 0.010), M["chrome"]))
    p.append(bx((-0.005, ry - 0.008, rz + 0.040), (0.005, ry + 0.008, z - 0.030), M["chrome"]))
    p.append(cyl(0.056, 0.030, (0.006, ry, rz), M["bakelite"], segs=16, axis="X"))
    p.append(cyl(0.050, 0.004, (0.023, ry, rz), M["chrome"], segs=16, axis="X"))
    p.append(cyl(0.045, 0.026, (0.006, ry, rz), M["line"], segs=16, axis="X"))       # line on the spool
    p.append(cyl(0.006, 0.020, (0.034, ry + 0.030, rz + 0.012), M["bakelite"], segs=8, axis="X"))
    p.append(cyl(0.008, 0.004, (0.024, ry, rz), M["bakelite"], segs=8, axis="X"))
    return p, {"Tip": (0, -L - 0.004, z), "Reel": (0.006, ry, rz), "Grip": (0, -0.20, z)}


def _box_shell(lo, hi, t, mat):
    """An open-topped box: floor and four walls of thickness t."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    return [bx((x0, y0, z0), (x1, y1, z0 + t), mat),
            bx((x0, y0, z0), (x1, y0 + t, z1), mat), bx((x0, y1 - t, z0), (x1, y1, z1), mat),
            bx((x0, y0 + t, z0), (x0 + t, y1 - t, z1), mat), bx((x1 - t, y0 + t, z0), (x1, y1 - t, z1), mat)]


def esky():
    """A 25 litre esky: blue tub, white lid hinged at the back, a white swing
    handle, an ice tray inside. Returns the tub parts; the lid is built by
    esky_lid() so the game can swing it open about its own origin."""
    M = _mats()
    w, d, h = 0.48, 0.32, 0.30
    p = _box_shell((-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), 0.03, M["esky"])
    p += _box_shell((-w / 2 + 0.03, -d / 2 + 0.03, 0.03), (w / 2 - 0.03, d / 2 - 0.03, h), 0.004, M["esky_white"])
    # feet, and the handle pivots on the ends
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (w / 2 - 0.01), sx * (w / 2 - 0.05)))
        p.append(bx((x0, -d / 2 + 0.02, -0.012), (x1, d / 2 - 0.02, 0.0), M["esky_white"]))
        p.append(cyl(0.016, 0.012, (sx * (w / 2 + 0.006), 0, h - 0.06), M["esky_white"], segs=10, axis="X"))
        p.append(bx((sx * (w / 2 + 0.006) - 0.006, -0.012, h - 0.06), (sx * (w / 2 + 0.006) + 0.006, 0.012, h + 0.10),
                    M["esky_white"]))
    p.append(bx((-w / 2 - 0.012, -0.014, h + 0.088), (w / 2 + 0.012, 0.014, h + 0.11), M["esky_white"]))
    # ice tray sitting on a ledge near the top, a few cubes in it
    p.append(bx((-w / 2 + 0.04, -d / 2 + 0.04, h - 0.075), (w / 2 - 0.04, d / 2 - 0.04, h - 0.068), M["esky_white"]))
    for i in range(6):
        x = -0.15 + (i % 3) * 0.15
        y = -0.05 + (i // 3) * 0.10
        p.append(bx((x - 0.025, y - 0.025, h - 0.068), (x + 0.025, y + 0.025, h - 0.030), M["ice"]))
    return p, {"Lid": (0, d / 2, h)}


def esky_lid():
    """The esky's lid, origin on its hinge line along the back top edge."""
    M = _mats()
    w, d = 0.50, 0.34
    p = [bx((-w / 2, -d, 0.0), (w / 2, 0.0, 0.05), M["esky_white"]),
         bx((-w / 2 + 0.05, -d + 0.04, 0.05), (w / 2 - 0.05, -0.04, 0.058), M["esky_white"]),
         bx((-0.05, -d - 0.012, 0.012), (0.05, -d, 0.040), M["esky"])]     # front catch
    return p


def tackle_box():
    """A green two-tray plastic tackle box, closed: the lid is built by
    tackle_lid() so it can open about its hinge."""
    M = _mats()
    w, d, h = 0.36, 0.20, 0.13
    p = _box_shell((-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), 0.008, M["tackle"])
    # cantilever tray with compartments, sinkers and lures in it
    p.append(bx((-w / 2 + 0.01, -d / 2 + 0.01, h - 0.04), (w / 2 - 0.01, d / 2 - 0.01, h - 0.035), M["tackle_dark"]))
    for i in range(1, 5):
        x = -w / 2 + i * w / 5
        p.append(bx((x - 0.002, -d / 2 + 0.01, h - 0.035), (x + 0.002, d / 2 - 0.01, h - 0.005), M["tackle_dark"]))
    for i, col in enumerate(("chrome", "film", "esky", "chrome", "blank")):
        x = -w / 2 + (i + 0.5) * w / 5
        p.append(bx((x - 0.012, -0.02, h - 0.035), (x + 0.012, 0.02, h - 0.022), M[col]))
    for sx in (-1, 1):  # latches
        p.append(bx((sx * 0.11 - 0.015, -d / 2 - 0.006, h - 0.03), (sx * 0.11 + 0.015, -d / 2, h + 0.01),
                    M["tackle_dark"]))
    return p, {"Lid": (0, d / 2, h)}


def tackle_lid():
    M = _mats()
    w, d = 0.36, 0.20
    p = [bx((-w / 2, -d, 0.0), (w / 2, 0.0, 0.035), M["tackle"]),
         bx((-0.07, -d / 2 - 0.01, 0.035), (-0.055, -d / 2 + 0.01, 0.06), M["tackle_dark"]),
         bx((0.055, -d / 2 - 0.01, 0.035), (0.07, -d / 2 + 0.01, 0.06), M["tackle_dark"]),
         bx((-0.07, -d / 2 - 0.01, 0.055), (0.07, -d / 2 + 0.01, 0.07), M["tackle_dark"])]
    return p


# name -> (parts and sockets, lid builder or None)
PROPS = {
    "binoculars": (binoculars, None),
    "camera": (camera, None),
    "film_roll": (film_roll, None),
    "fishing_rod": (fishing_rod, None),
    "esky": (esky, esky_lid),
    "tackle_box": (tackle_box, tackle_lid),
}
