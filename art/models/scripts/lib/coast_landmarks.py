"""Stage 5 landmarks, placed by the map from map/tiles/props.json:

  mole_light_north  Fremantle North Mole light (1906): a 9 m cast-iron
                    tower by Chance Bros to C. Y. O'Connor's design, painted
                    red with a white gallery and lantern. Shows red.
  mole_light_south  The South Mole light (1903), the same tower in green.
                    Shows green.
  herdsman_hide     A timber bird hide on stilts at the reedy edge of
                    Herdsman Lake, like the Balgay and Baumea hides off Jon
                    Sanders Drive: a long viewing slot with its flap propped
                    open, a bench inside, and a boardwalk out to it.
  trigg_surf_club   The surf club on West Coast Drive, Trigg (the 1993
                    clubrooms): boat sheds at beach level, the function room
                    upstairs behind a glass balustrade, a skillion roof
                    lifting toward the sea and a glazed patrol tower.

Each builder returns (parts, sockets, collision boxes). Origin on the
ground at the anchor, front toward -Y in Blender (Godot +Z): the lights'
doors, the hide's viewing slot and the club's beach side.
"""
import math

from . import common as C
from . import furniture as F
from . import field_places as FP
from . import tackle_shop as TS

bx, cyl = F.bx, F.cyl
_beam = TS._beam


def _m(name, col, rough=0.8, metal=0.0, **kw):
    return C.mat("LM_" + name, col, rough=rough, metal=metal, **kw)


def _ring(r, z, n, rad, mat, segs=4):
    """A polygonal ring of bars (a handrail) of n sides."""
    out = []
    for i in range(n):
        a0, a1 = i * math.tau / n, (i + 1) * math.tau / n
        out.append(_beam((r * math.cos(a0), r * math.sin(a0), z), (r * math.cos(a1), r * math.sin(a1), z),
                         rad, mat, segs=segs))
    return out


# ------------------------------------------------------------------ the moles

def _mole_light(paint_col, lamp_col, tag):
    paint = _m("Paint" + tag, paint_col, 0.55, 0.2)
    white = _m("White", "#ece9e1", 0.55, 0.2)
    conc = _m("Concrete", "#a9a59c", 0.95)
    dark = _m("IronDark", "#262a2c", 0.6, 0.5)
    glass = _m("LanternGlass", "#9fb3b8", 0.05, 0.3)
    lamp = _m("Lamp" + tag, lamp_col, 0.3, emit=lamp_col, emit_strength=3.0)
    p = []
    # the concrete plinth on the mole head, a step, then the tower
    p.append(cyl(1.9, 0.5, (0, 0, 0.25), conc, segs=16))
    p.append(cyl(1.5, 0.2, (0, 0, 0.6), conc, segs=16))
    z0, z1, r0, r1 = 0.7, 6.7, 1.15, 0.8

    def rad(z):
        return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    p.append(cyl(r0, z1 - z0, (0, 0, (z0 + z1) / 2), paint, segs=16, r_top=r1))
    p.append(cyl(r0 + 0.04, 0.18, (0, 0, z0 + 0.09), paint, segs=16, r_top=r0 + 0.02))   # base flange
    # bolted flange rings where the cast-iron sections meet
    for z in (2.2, 3.7, 5.2):
        p.append(cyl(rad(z) + 0.035, 0.07, (0, 0, z), paint, segs=16))
    # the door on the front, with its frame and a little hood
    dr = rad(1.6)
    p.append(bx((-0.36, -dr - 0.06, 0.72), (0.36, -dr + 0.25, 2.55), white))
    p.append(bx((-0.3, -dr - 0.08, 0.75), (0.3, -dr + 0.2, 2.45), dark))
    p.append(bx((-0.44, -dr - 0.22, 2.58), (0.44, -dr + 0.2, 2.68), white))
    p.append(bx((0.18, -dr - 0.11, 1.55), (0.24, -dr - 0.08, 1.62), white))                 # handle
    # portholes up the tower, front and back, offset like the stair turns
    for z, sgn in ((3.0, 1), (4.5, -1), (5.9, 1)):
        rr = rad(z)
        p.append(cyl(0.16, 0.14, (0, sgn * rr, z), white, segs=10, axis="Y"))
        p.append(cyl(0.11, 0.16, (0, sgn * rr, z), glass, segs=10, axis="Y"))
    # the corbelled gallery, its deck and railing
    p.append(cyl(r1, 0.5, (0, 0, z1 + 0.25), white, segs=16, r_top=1.3))
    p.append(cyl(1.38, 0.12, (0, 0, z1 + 0.56), white, segs=16))
    n = 12
    for i in range(n):
        a = i * math.tau / n
        p.append(_beam((1.32 * math.cos(a), 1.32 * math.sin(a), z1 + 0.62),
                       (1.32 * math.cos(a), 1.32 * math.sin(a), z1 + 1.62), 0.025, white))
    p += _ring(1.32, z1 + 1.62, n, 0.035, white)
    p += _ring(1.32, z1 + 1.12, n, 0.02, white)
    # the lantern: a pedestal, a 12-sided glazed room with astragals, a domed
    # roof, the ball ventilator and a lightning finial
    zl0 = z1 + 0.62
    p.append(cyl(0.72, 0.6, (0, 0, zl0 + 0.3), white, segs=12))
    p.append(cyl(0.6, 1.0, (0, 0, zl0 + 1.1), glass, segs=12))
    for i in range(12):
        a = (i + 0.5) * math.tau / 12
        p.append(_beam((0.61 * math.cos(a), 0.61 * math.sin(a), zl0 + 0.6),
                       (0.61 * math.cos(a), 0.61 * math.sin(a), zl0 + 1.6), 0.025, white))
    p.append(cyl(0.68, 0.08, (0, 0, zl0 + 1.64), white, segs=12))
    p.append(cyl(0.72, 0.42, (0, 0, zl0 + 1.89), white, segs=12, r_top=0.18))
    p.append(C.sphere("vent", 0.16, (0, 0, zl0 + 2.22), dark, segs=8, rings=5))
    p.append(_beam((0, 0, zl0 + 2.3), (0, 0, zl0 + 2.75), 0.015, dark))
    # the light itself: a lens drum glowing inside the glazing
    p.append(cyl(0.22, 0.5, (0, 0, zl0 + 1.1), lamp, segs=10))
    sockets = {"Lamp": (0.0, 0.0, zl0 + 1.1), "Door": (0.0, -dr - 0.6, 0.7)}
    col = [((-1.9, -1.9, 0.0), (1.9, 1.9, 0.7)),
           ((-1.05, -1.05, 0.7), (1.05, 1.05, z1)),
           ((-1.38, -1.38, z1), (1.38, 1.38, zl0 + 2.1))]
    return p, sockets, col


def mole_light_north():
    return _mole_light("#a8231c", "#ff3a2a", "Red")


def mole_light_south():
    return _mole_light("#2f6b3a", "#3aff6a", "Green")


# ------------------------------------------------------------------ Herdsman

def herdsman_hide():
    timber = _m("HideTimber", "#6e5844", 0.95)
    batten = _m("HideBatten", "#57442f", 0.95)
    deck = _m("Deck", "#8a7a66", 0.95)
    gap = _m("DeckGap", "#3a3128", 0.95)
    post = _m("Post", "#5a4a3a", 0.95)
    roof = _m("Roof", "#7b8a74", 0.5, 0.4)            # pale eucalypt sheeting
    inside = _m("HideInside", "#4a3a2c", 0.95)
    dark = _m("HideDark", "#1c1712", 0.95)
    p = []
    FL = 0.6                                          # floor height above the ground/water
    W, D = 3.6, 2.4
    y0, y1 = -D / 2, D / 2
    zf, zb = FL + 2.35, FL + 2.65                     # wall tops: front low, back high
    T = 0.08
    SL0, SL1 = FL + 0.95, FL + 1.35                   # the viewing slot

    def wall_top(y):
        return zf + (zb - zf) * (y - y0) / D
    # stilts and bearers under the floor
    for x in (-W / 2 + 0.1, 0.0, W / 2 - 0.1):
        for y in (y0 + 0.1, y1 - 0.1):
            p.append(cyl(0.08, FL + 0.6, (x, y, (FL - 0.6) / 2), post, segs=6))
    p.append(bx((-W / 2, y0, FL - 0.15), (W / 2, y1, FL), timber))
    p.append(bx((-W / 2 + T, y0 + T, FL), (W / 2 - T, y1 - T, FL + 0.03), deck))
    # front wall with the long slot
    p.append(bx((-W / 2, y0, FL), (W / 2, y0 + T, SL0), timber))
    p.append(bx((-W / 2, y0, SL1), (W / 2, y0 + T, zf), timber))
    p.append(bx((-W / 2, y0, SL0), (-W / 2 + 0.3, y0 + T, SL1), timber))
    p.append(bx((W / 2 - 0.3, y0, SL0), (W / 2, y0 + T, SL1), timber))
    p.append(bx((-W / 2 + 0.3, y0 - 0.02, SL0 - 0.06), (W / 2 - 0.3, y0 + 0.28, SL0), timber))   # ledge
    # the flap, top-hung and propped out on two stays
    a = math.radians(55)
    fl = 0.5
    v = [(-W / 2 + 0.3, y0, SL1 + 0.02), (W / 2 - 0.3, y0, SL1 + 0.02),
         (W / 2 - 0.3, y0 - fl * math.sin(a), SL1 + 0.02 - fl * math.cos(a)),
         (-W / 2 + 0.3, y0 - fl * math.sin(a), SL1 + 0.02 - fl * math.cos(a))]
    v2 = [(x, y, z + 0.04) for x, y, z in v]
    p.append(C.mesh_obj("flap", v + v2, [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
                                          (2, 6, 7, 3), (3, 7, 4, 0)], timber))
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.45)
        p.append(_beam((x, y0 - 0.01, SL0 + 0.05), (x, y0 - fl * math.sin(a) * 0.85,
                                                     SL1 - fl * math.cos(a) * 0.85), 0.012, dark))
    # side walls (sloped tops), back wall with the doorway at +X
    for sx in (-1, 1):
        x0, x1 = (-W / 2, -W / 2 + T) if sx < 0 else (W / 2 - T, W / 2)
        v = [(x0, y0, FL), (x1, y0, FL), (x1, y1, FL), (x0, y1, FL),
             (x0, y0, zf), (x1, y0, zf), (x1, y1, zb), (x0, y1, zb)]
        p.append(C.mesh_obj("side", v, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                                         (2, 3, 7, 6), (3, 0, 4, 7)], timber))
    DX0, DX1 = 0.45, 1.35
    p.append(bx((-W / 2, y1 - T, FL), (DX0, y1, zb), timber))
    p.append(bx((DX1, y1 - T, FL), (W / 2, y1, zb), timber))
    p.append(bx((DX0, y1 - T, FL + 2.1), (DX1, y1, zb), timber))
    # the doorway's frame
    for x in (DX0, DX1 - 0.06):
        p.append(bx((x, y1 - 0.01, FL), (x + 0.06, y1 + 0.02, FL + 2.1), batten))
    # board-and-batten lines on the outside
    for i in range(1, 12):
        x = -W / 2 + i * W / 12
        p.append(bx((x - 0.02, y0 - 0.015, FL), (x + 0.02, y0, SL0 - 0.06), batten))
        p.append(bx((x - 0.02, y0 - 0.015, SL1), (x + 0.02, y0, zf), batten))
    for sx in (-1, 1):
        for i in range(1, 8):
            y = y0 + i * D / 8
            xx = sx * (W / 2 + 0.0075)
            p.append(bx((xx - 0.0075, y - 0.02, FL), (xx + 0.0075, y + 0.02, wall_top(y) - 0.02), batten))
    # the skillion roof, overhanging
    ov = 0.35
    rz0, rz1 = zf + 0.02 - ov * (zb - zf) / D, zb + 0.02 + ov * (zb - zf) / D
    v = [(-W / 2 - ov, y0 - ov, rz0), (W / 2 + ov, y0 - ov, rz0), (W / 2 + ov, y1 + ov, rz1), (-W / 2 - ov, y1 + ov, rz1)]
    v2 = [(x, y, z + 0.06) for x, y, z in v]
    p.append(C.mesh_obj("roof", v + v2, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                                          (2, 3, 7, 6), (3, 0, 4, 7)], roof))
    # inside: dark walls, the bench, a bird chart over the doorway
    p.append(bx((-W / 2 + T, y0 + T, FL), (W / 2 - T, y0 + T + 0.01, SL0 - 0.06), inside))
    p.append(bx((-W / 2 + 0.2, y0 + 0.45, FL + 0.42), (W / 2 - 0.2, y0 + 0.8, FL + 0.47), timber))
    for x in (-W / 2 + 0.3, 0.0, W / 2 - 0.3):
        p.append(bx((x - 0.04, y0 + 0.55, FL), (x + 0.04, y0 + 0.7, FL + 0.42), timber))
    img = FP._sign("hide_chart", ["WATERBIRDS OF", "HERDSMAN LAKE", "", "QUIET PLEASE"], 64, 32,
                   "#e9e2cc", "#2f4a3a")
    p.append(TS._quad_image(img, "HideChart", 0.9, 0.45, (-0.6, y1 - T - 0.01, FL + 1.75), facing="-y"))
    # the boardwalk out to it from the +Y side, the last stretch down to the bank
    BW, BL = 1.6, 14.0
    bx0, bx1 = DX0 + 0.45 - BW / 2, DX0 + 0.45 + BW / 2
    by0, by1 = y1 + 0.1, y1 + 0.1 + BL
    p.append(bx((bx0, y1, FL - 0.12), (bx1, by1, FL), deck))
    for i in range(int((by1 - y1) / 0.5)):
        y = y1 + 0.25 + i * 0.5
        p.append(bx((bx0 + 0.02, y - 0.01, FL), (bx1 - 0.02, y + 0.01, FL + 0.002), gap))
    for sx, xx in ((-1, bx0), (1, bx1)):
        p.append(bx((xx - 0.05, by0, FL), (xx + 0.05, by1, FL + 0.12), timber))               # kerb
        y = by0 + 0.2
        while y < by1:
            p.append(cyl(0.07, FL + 1.6, (xx, y, (FL + 1.0 - 0.6) / 2), post, segs=6))
            y += 2.0
        p.append(bx((xx - 0.05, by0, FL + 0.95), (xx + 0.05, by1, FL + 1.02), timber))         # handrail
        p.append(bx((xx - 0.03, by0, FL + 0.5), (xx + 0.03, by1, FL + 0.56), timber))
    # the ramp down to the bank at the far end
    v = [(bx0, by1, FL), (bx1, by1, FL), (bx1, by1 + 3.0, 0.0), (bx0, by1 + 3.0, 0.0)]
    v2 = [(x, y, z - 0.12) for x, y, z in v]
    p.append(C.mesh_obj("ramp", v + v2, [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
                                          (2, 6, 7, 3), (3, 7, 4, 0)], deck))
    # the trail sign at the start of the boardwalk
    img = FP._sign("hide_sign", ["BIRD HIDE", "HERDSMAN LAKE"], 64, 16, "#efe8d4", "#3b5a3e")
    sx_ = bx1 + 0.6
    p.append(cyl(0.05, 1.6, (sx_ - 0.35, by1 + 2.6, 0.8), post, segs=6))
    p.append(cyl(0.05, 1.6, (sx_ + 0.35, by1 + 2.6, 0.8), post, segs=6))
    p.append(bx((sx_ - 0.45, by1 + 2.6, 1.05), (sx_ + 0.45, by1 + 2.64, 1.5), post))
    p.append(FP._sign_quad(img, "HideSign", 0.88, 0.22, (sx_, by1 + 2.65, 1.28), facing=1))
    sockets = {"View": (0.0, y0 + 0.55, FL), "Entry": ((bx0 + bx1) / 2, by1 + 3.4, 0.0)}
    col = [((-W / 2, y0, 0.0), (W / 2, y1, FL)),
           ((-W / 2, y0, FL), (W / 2, y0 + T, SL0)),
           ((-W / 2, y0, FL), (-W / 2 + T, y1, zb)),
           ((W / 2 - T, y0, FL), (W / 2, y1, zb)),
           ((-W / 2, y1 - T, FL), (DX0, y1, zb)),
           ((bx0, y1, 0.0), (bx1, by1, FL)),
           ((bx0 - 0.05, by0, FL), (bx0 + 0.05, by1, FL + 1.02)),
           ((bx1 - 0.05, by0, FL), (bx1 + 0.05, by1, FL + 1.02))]
    return p, sockets, col


# ------------------------------------------------------------------ Trigg

def trigg_surf_club():
    render = _m("ClubRender", "#e4dccb", 0.9)
    lime = _m("ClubLimestone", "#d6c7a2", 0.95)
    roof = _m("ClubRoof", "#e9ecea", 0.45, 0.4)
    fascia = _m("ClubFascia", "#2e4f6e", 0.6)
    glass = _m("ClubGlass", "#3a5664", 0.08, 0.3)
    frame = _m("ClubFrame", "#c9ccc8", 0.4, 0.6)
    door = _m("ClubRoller", "#bfc4c4", 0.5, 0.5)
    conc = _m("ClubConcrete", "#b5b0a5", 0.95)
    red = _m("FlagRed", "#c8261e", 0.7)
    yel = _m("FlagYellow", "#f2c51a", 0.7)
    dark = _m("ClubDark", "#24282a", 0.7)
    p = []
    L, D = 28.0, 14.0
    x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
    G = 3.6                    # ground floor height
    UP0 = y0 + 3.0             # the upper floor sits back behind the balcony
    zr_back, zr_front = 7.2, 8.2
    # the concrete apron to the beach
    p.append(bx((x0 - 1.0, y0 - 4.0, 0.0), (x1 + 1.0, y0, 0.08), conc))
    # ground floor: a rendered block on a limestone plinth course, boat sheds at
    # the beach side
    p.append(bx((x0, y0, 0.0), (x1, y1, G), render))
    p.append(bx((x0 - 0.02, y0 - 0.02, 0.0), (x1 + 0.02, y1 + 0.02, 0.5), lime))
    for i, xc in enumerate((-9.5, -4.5, 0.5)):
        p.append(bx((xc - 2.0, y0 - 0.04, 0.08), (xc + 2.0, y0 + 0.02, 2.9), door))
        for k in range(9):
            z = 0.3 + k * 0.3
            p.append(bx((xc - 2.0, y0 - 0.05, z), (xc + 2.0, y0 - 0.04, z + 0.03), frame))
        p.append(bx((xc - 2.15, y0 - 0.08, 2.9), (xc + 2.15, y0 + 0.02, 3.05), frame))
    # first aid room: a glazed door and a window; the club sign over the sheds
    p.append(bx((5.0, y0 - 0.04, 0.08), (6.1, y0 + 0.02, 2.3), glass))
    p.append(bx((4.95, y0 - 0.06, 2.3), (6.15, y0 + 0.02, 2.38), frame))
    p.append(bx((7.0, y0 - 0.04, 1.0), (12.5, y0 + 0.02, 2.4), glass))
    for x in (8.4, 9.8, 11.1):
        p.append(bx((x - 0.03, y0 - 0.06, 1.0), (x + 0.03, y0 + 0.02, 2.4), frame))
    img = FP._sign("club_sign", ["SURF LIFE SAVING CLUB"], 96, 8, "#f4f1e8", "#2e4f6e")
    p.append(TS._quad_image(img, "ClubSign", 10.0, 0.83, (-4.5, y0 - 0.07, 3.3), facing="-y"))
    p.append(bx((x0 - 0.05, y0 - 0.06, 3.05), (x1 + 0.05, y0 + 0.02, 3.55), fascia))
    # the balcony slab and glass balustrade across the front
    p.append(bx((x0 - 0.3, y0 - 1.2, G), (x1 + 0.3, UP0, G + 0.25), render))
    p.append(bx((x0 - 0.3, y0 - 1.2, G + 0.25), (x1 + 0.3, y0 - 1.1, G + 1.25), glass))
    p.append(bx((x0 - 0.32, y0 - 1.22, G + 1.25), (x1 + 0.32, y0 - 1.08, G + 1.32), frame))
    for xx in (x0 - 0.3, x1 + 0.2):
        p.append(bx((xx, y0 - 1.2, G + 0.25), (xx + 0.1, UP0, G + 1.25), glass))
    for i in range(15):
        x = x0 - 0.3 + i * (L + 0.6) / 14
        p.append(bx((x - 0.04, y0 - 1.22, G + 0.25), (x + 0.04, y0 - 1.08, G + 1.25), frame))
    # the upper floor: the function room glazed floor to ceiling to the sea
    p.append(bx((x0 + 0.5, UP0, G + 0.25), (x1 - 0.5, y1, zr_back), render))
    p.append(bx((x0 + 0.5, UP0 - 0.04, G + 0.35), (x1 - 0.5, UP0 + 0.02, zr_back - 0.2), glass))
    n = 14
    for i in range(n + 1):
        x = x0 + 0.5 + i * (L - 1.0) / n
        p.append(bx((x - 0.05, UP0 - 0.07, G + 0.25), (x + 0.05, UP0 + 0.02, zr_back - 0.1), frame))
    p.append(bx((x0 + 0.5, UP0 - 0.07, G + 2.4), (x1 - 0.5, UP0 + 0.02, G + 2.47), frame))
    # the wedge of wall that carries the skillion up toward the sea
    for xx in (x0 + 0.5, x1 - 0.9):
        v = [(xx, UP0, zr_back), (xx, y1, zr_back), (xx, UP0, zr_front - 0.1)]
        v2 = [(xx + 0.4, y, z) for _, y, z in v]
        p.append(C.mesh_obj("gable", v + v2, [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)],
                            render))
    p.append(bx((x0 + 0.5, UP0 - 0.04, zr_back - 0.2), (x1 - 0.5, UP0 + 0.02, zr_front - 0.1), glass))
    # the skillion roof, out over the balcony
    ry0, ry1 = y0 - 1.6, y1 + 0.5
    slope = (zr_front - zr_back) / (UP0 - y1)

    def rz(y):
        return zr_back + slope * (y - y1)
    v = [(x0 - 0.2, ry0, rz(ry0)), (x1 + 0.2, ry0, rz(ry0)), (x1 + 0.2, ry1, rz(ry1)), (x0 - 0.2, ry1, rz(ry1))]
    v2 = [(x, y, z + 0.25) for x, y, z in v]
    p.append(C.mesh_obj("roof", v + v2, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                                          (2, 3, 7, 6), (3, 7, 4, 0)], roof))
    p.append(bx((x0 - 0.22, ry0 - 0.06, rz(ry0) - 0.2), (x1 + 0.22, ry0, rz(ry0) + 0.3), fascia))
    for x in (x0 + 0.5, -7.0, 0.0, 7.0, x1 - 0.5):                     # posts under the roof edge
        p.append(bx((x - 0.08, y0 - 1.15, G + 0.25), (x + 0.08, y0 - 0.99, rz(y0 - 1.07)), frame))
    # the patrol tower on the north end of the roof, glazed all round
    tx, ty = 10.0, 0.0
    tz = rz(ty) + 0.25
    p.append(bx((tx - 1.6, ty - 1.6, tz - 0.6), (tx + 1.6, ty + 1.6, tz + 1.0), render))
    p.append(bx((tx - 1.62, ty - 1.62, tz + 1.0), (tx + 1.62, ty + 1.62, tz + 2.3), glass))
    for cx in (-1.6, 1.6):
        for cy in (-1.6, 1.6):
            p.append(bx((tx + cx - 0.07, ty + cy - 0.07, tz + 1.0), (tx + cx + 0.07, ty + cy + 0.07, tz + 2.3), frame))
    p.append(bx((tx - 2.0, ty - 2.0, tz + 2.3), (tx + 2.0, ty + 2.0, tz + 2.5), fascia))
    # the flagpole with the red and yellow patrol flag
    fx, fy = tx + 1.2, ty + 1.2
    p.append(_beam((fx, fy, tz + 2.5), (fx, fy, tz + 6.5), 0.04, frame))
    p.append(bx((fx, fy - 0.01, tz + 5.6), (fx + 0.6, fy + 0.01, tz + 5.9), red))
    p.append(bx((fx, fy - 0.01, tz + 5.9), (fx + 0.6, fy + 0.01, tz + 6.2), yel))
    # the stair up the south end to the balcony and the restaurant
    for k in range(18):
        z = (k + 1) * G / 18
        y = y1 - 0.35 - k * 0.3
        p.append(bx((x0 - 1.6, y - 0.3, z - 0.18), (x0 - 0.05, y, z), conc))
    p.append(bx((x0 - 1.6, y0 - 1.2, G), (x0 - 0.05, y1 - 0.35 - 18 * 0.3 + 0.3, G + 0.25), conc))
    p.append(_beam((x0 - 1.6, y1 - 0.35, 1.0), (x0 - 1.6, y1 - 0.35 - 17 * 0.3, G + 1.0), 0.03, frame))
    # rinse showers and a bench on the apron
    for x in (-13.0, 13.0):
        p.append(_beam((x, y0 - 3.0, 0.08), (x, y0 - 3.0, 2.2), 0.04, frame))
        p.append(bx((x - 0.05, y0 - 3.3, 2.15), (x + 0.05, y0 - 3.0, 2.2), frame))
    p.append(bx((2.5, y0 - 2.5, 0.42), (4.5, y0 - 2.1, 0.47), dark))
    for x in (2.7, 4.3):
        p.append(bx((x - 0.04, y0 - 2.45, 0.08), (x + 0.04, y0 - 2.15, 0.42), frame))
    sockets = {"Front": (5.55, y0 - 0.8, 0.08), "Apron": (0.0, y0 - 3.0, 0.08),
               "Tower": (tx, ty, tz + 1.5)}
    col = [((x0, y0, 0.0), (x1, y1, G)),
           ((x0 - 0.3, y0 - 1.2, G), (x1 + 0.3, y1, G + 0.25)),
           ((x0 + 0.5, UP0, G), (x1 - 0.5, y1, zr_back)),
           ((x0 - 1.6, y0 - 1.2, 0.0), (x0 - 0.05, y1, 1.0)),
           ((tx - 1.6, ty - 1.6, zr_back), (tx + 1.6, ty + 1.6, tz + 2.5))]
    return p, sockets, col


LANDMARKS = {
    "mole_light_north": mole_light_north,
    "mole_light_south": mole_light_south,
    "herdsman_hide": herdsman_hide,
    "trigg_surf_club": trigg_surf_club,
}
