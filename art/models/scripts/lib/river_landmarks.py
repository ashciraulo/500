"""Stage 6 river landmarks, placed by the map from map/tiles/props.json:

  kent_st_weir   Kent Street Weir on the Canning at Wilson, as rebuilt in
                 2017: 17 concrete bays with stainless lay-flat gates
                 holding the fresh pool back from the tide, a fishway
                 stepping down beside them, and the footbridge across the
                 top with timber decking and steel balustrades.

Each builder returns (parts, sockets, collision boxes). Front toward -Y in
Blender (Godot +Z). Heights are from the upstream pool's surface (0); see
each builder for where its origin sits.
"""
import math

from . import common as C
from . import furniture as F
from . import field_places as FP
from . import tackle_shop as TS

bx, cyl = F.bx, F.cyl
_beam = TS._beam


def _m(name, col, rough=0.8, metal=0.0, **kw):
    return C.mat("RL_" + name, col, rough=rough, metal=metal, **kw)


def _prism(name, v, mat):
    """A closed box from 8 corners: the bottom 4 then the top 4, both anticlockwise from above."""
    return C.mesh_obj(name, v, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                                (2, 3, 7, 6), (3, 0, 4, 7)], mat)


# ------------------------------------------------------------------ Kent St

def kent_st_weir():
    """Origin on the weir's centre line at the upstream pool surface; the
    weir runs along X across the river, the downstream (tide) side toward
    -Y. The banks are at +-26 m, where the footbridge lands at path height
    (1.5 m above the pool)."""
    conc = _m("Concrete", "#b3aea3", 0.95)
    conc_dark = _m("ConcreteWet", "#7d7a72", 0.9)
    gate = _m("Gate", "#a7adb0", 0.35, 0.8)                 # super duplex stainless
    deck = _m("Deck", "#8b7258", 0.9)
    gap = _m("DeckGap", "#3b3027", 0.9)
    rail = _m("Rail", "#5d6467", 0.5, 0.6)
    mesh = _m("RailMesh", "#4b5255", 0.6, 0.5, alpha=0.55)
    spill = _m("Spill", "#e8eef0", 0.3, alpha=0.6)
    kiosk = _m("Kiosk", "#4e6b52", 0.6, 0.3)
    sign_post = _m("Post", "#5a4a3a", 0.95)
    p = []
    N, BAY, PIER = 17, 2.3, 0.5
    L = N * BAY + (N + 1) * PIER                              # 48.1 m between the abutments
    x0 = -L / 2
    BED, CREST, DECK = -1.6, 0.0, 1.35
    PY0, PY1 = -1.6, 1.4                                      # pier length, downstream to upstream
    # the sill and the downstream apron the water spills onto
    p.append(bx((x0, -6.0, BED - 0.3), (-x0, PY1 + 0.6, BED), conc_dark))
    p.append(bx((x0, PY0 - 0.2, BED), (-x0, PY1, -1.0), conc))
    # piers with cutwaters on the upstream noses
    for i in range(N + 1):
        x = x0 + i * (BAY + PIER)
        p.append(bx((x, PY0, -1.0), (x + PIER, PY1, DECK - 0.05), conc))
        v = [(x, PY1, -1.0), (x + PIER, PY1, -1.0), (x + PIER / 2, PY1 + 0.45, -1.0), (x + PIER / 2, PY1 + 0.45, -1.0),
             (x, PY1, DECK - 0.4), (x + PIER, PY1, DECK - 0.4), (x + PIER / 2, PY1 + 0.45, DECK - 0.4),
             (x + PIER / 2, PY1 + 0.45, DECK - 0.4)]
        p.append(C.mesh_obj("nose", v, [(0, 2, 1), (4, 5, 6), (0, 1, 5, 4), (1, 2, 6, 5), (2, 0, 4, 6)], conc))
        p.append(bx((x - 0.01, PY0 - 0.01, -1.0), (x + PIER + 0.01, PY1 + 0.01, -0.55), conc_dark))  # tide line
    # the lay-flat gates, raised, and the thin sheet of water going over them
    for i in range(N):
        xa = x0 + PIER + i * (BAY + PIER)
        xb = xa + BAY
        a = math.radians(70)
        h = 1.05
        y_hinge = -0.3
        v = [(xa, y_hinge, -1.0), (xb, y_hinge, -1.0),
             (xb, y_hinge - 0.08, -1.0), (xa, y_hinge - 0.08, -1.0)]
        top = [(x, y - h * math.cos(a), z + h * math.sin(a)) for x, y, z in v]
        p.append(_prism("gate", v + top, gate))
        # spill: a clear lip of water curving down off the gate edge
        yt, zt = y_hinge - h * math.cos(a), -1.0 + h * math.sin(a)
        sv = [(xa + 0.05, yt, zt + 0.04), (xb - 0.05, yt, zt + 0.04),
              (xb - 0.05, yt - 0.35, zt - 0.3), (xa + 0.05, yt - 0.35, zt - 0.3),
              (xb - 0.05, yt - 0.55, -1.0), (xa + 0.05, yt - 0.55, -1.0)]
        p.append(C.mesh_obj("spill", sv, [(0, 1, 2, 3), (3, 2, 4, 5)], spill))
    # the hydraulic rams behind every second gate, under the deck
    for i in range(0, N, 2):
        xc = x0 + PIER + i * (BAY + PIER) + BAY / 2
        p.append(_beam((xc, 0.6, -1.0), (xc, -0.4, -0.2), 0.06, gate))
    # the footbridge: steel cross-beams on the piers, timber deck, balustrades
    DW = 2.6
    dy0, dy1 = -DW / 2 + 0.1, DW / 2 + 0.1
    p.append(bx((x0 - 4.0, dy0 + 0.05, DECK - 0.35), (-x0 + 4.0, dy1 - 0.05, DECK - 0.05), rail))
    p.append(bx((x0 - 4.0, dy0, DECK - 0.05), (-x0 + 4.0, dy1, DECK + 0.05), deck))
    xx = x0 - 4.0 + 0.6
    while xx < -x0 + 4.0:
        p.append(bx((xx - 0.012, dy0 + 0.02, DECK + 0.05), (xx + 0.012, dy1 - 0.02, DECK + 0.052), gap))
        xx += 0.6
    for yy in (dy0, dy1):
        sgn = -1 if yy == dy0 else 1
        p.append(bx((x0 - 4.0, yy - 0.04, DECK + 1.15), (-x0 + 4.0, yy + 0.04, DECK + 1.22), rail))     # top rail
        p.append(bx((x0 - 4.0, yy - 0.02, DECK + 0.12), (-x0 + 4.0, yy + 0.02, DECK + 0.16), rail))     # bottom rail
        p.append(bx((x0 - 4.0, yy - 0.004, DECK + 0.16), (-x0 + 4.0, yy + 0.004, DECK + 1.15), mesh))   # mesh infill
        for k in range(29):
            x = x0 - 4.0 + k * (L + 8.0) / 28
            p.append(bx((x - 0.04, yy - 0.04, DECK + 0.05), (x + 0.04, yy + 0.04, DECK + 1.15), rail))
        # light handrail on timber, inside the steel
        p.append(bx((x0 - 4.0, yy - sgn * 0.08 - 0.03, DECK + 0.95), (-x0 + 4.0, yy - sgn * 0.08 + 0.03, DECK + 1.0),
                    deck))
    # abutments and wing walls into the banks, the path continuing at deck height
    for sx in (-1, 1):
        xa, xb = (x0 - 4.0, x0) if sx < 0 else (-x0, -x0 + 4.0)
        p.append(bx((xa, PY0 - 1.5, BED), (xb, PY1 + 1.0, DECK - 0.35), conc))
    # the fishway: a stepped concrete channel on the east bank, pools dropping
    # downstream beside the weir
    fx0, fx1 = -x0 + 0.4, -x0 + 2.4
    for k in range(6):
        y_a, y_b = PY1 - k * 1.3, PY1 - (k + 1) * 1.3
        floor = -0.35 - k * 0.18
        p.append(bx((fx0, y_b, BED), (fx1, y_a, floor), conc_dark))
        p.append(bx((fx0, y_b, floor), (fx0 + 0.75, y_b + 0.15, floor + 0.3), conc))        # baffle with a
        p.append(bx((fx0 + 1.05, y_b, floor), (fx1, y_b + 0.15, floor + 0.3), conc))        # vertical slot
    for wx in (fx0 - 0.25, fx1):
        p.append(bx((wx, PY1 - 7.8, BED), (wx + 0.25, PY1 + 0.2, 0.25), conc))
    # the gate control kiosk on the west bank, and the park sign
    p.append(bx((x0 - 6.5, 3.0, DECK - 0.35), (x0 - 5.3, 3.6, DECK + 1.25), kiosk))
    p.append(bx((x0 - 6.55, 2.95, DECK + 1.25), (x0 - 5.25, 3.65, DECK + 1.32), kiosk))
    img = FP._sign("weir_sign", ["KENT ST WEIR", "CANNING RIVER"], 64, 16, "#efe8d4", "#3b5a3e")
    sx_, sy_ = x0 - 7.5, -1.8
    for dx in (-0.4, 0.4):
        p.append(cyl(0.05, 1.7, (sx_ + dx, sy_, DECK - 0.35 + 0.85), sign_post, segs=6))
    p.append(bx((sx_ - 0.5, sy_ - 0.02, DECK + 0.6), (sx_ + 0.5, sy_ + 0.02, DECK + 1.1), sign_post))
    p.append(FP._sign_quad(img, "WeirSign", 0.96, 0.24, (sx_, sy_ - 0.03, DECK + 0.85), facing=-1))
    sockets = {"BridgeMid": (0.0, 0.1, DECK + 0.05), "WestEnd": (x0 - 4.0, 0.1, DECK + 0.05),
               "EastEnd": (-x0 + 4.0, 0.1, DECK + 0.05), "Fishway": ((fx0 + fx1) / 2, PY1 - 4.0, 0.0),
               "Spill": (0.0, -1.2, -0.8)}
    col = [((x0 - 4.0, dy0, DECK - 0.35), (-x0 + 4.0, dy1, DECK + 0.05)),
           ((x0 - 4.0, dy0 - 0.05, DECK), (-x0 + 4.0, dy0 + 0.05, DECK + 1.22)),
           ((x0 - 4.0, dy1 - 0.05, DECK), (-x0 + 4.0, dy1 + 0.05, DECK + 1.22)),
           ((x0 - 4.0, PY0 - 1.5, BED), (x0, PY1 + 1.0, DECK - 0.35)),
           ((-x0, PY0 - 1.5, BED), (-x0 + 4.0, PY1 + 1.0, DECK - 0.35)),
           ((x0, PY0, BED), (-x0, PY1, DECK - 0.35)),
           ((x0 - 6.5, 3.0, DECK - 0.35), (x0 - 5.3, 3.6, DECK + 1.32))]
    return p, sockets, col


LANDMARKS = {
    "kent_st_weir": kent_st_weir,
}
