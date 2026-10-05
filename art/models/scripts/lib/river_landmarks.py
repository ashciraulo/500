"""Stage 6 river landmarks, placed by the map from map/tiles/props.json:

  kent_st_weir   Kent Street Weir on the Canning at Wilson, as rebuilt in
                 2017: 17 concrete bays with stainless lay-flat gates
                 holding the fresh pool back from the tide, a fishway
                 stepping down beside them, and the footbridge across the
                 top with timber decking and steel balustrades.
  jetty_rail, jetty_lamp
                 Railings and a lamp to dress the map's plain OSM jetty deck
                 at Garratt Rd.
  pelican_fence, pelican_lookout, pelican_sailing_club
                 Pelican Point: a run of the sanctuary's chain-wire fence,
                 the viewing deck with its waders board, and a sailing club
                 on the north side (a made-up club).

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


# ------------------------------------------------------------------ Garratt Rd jetty dressing

def jetty_rail():
    """Dressing for an existing 3 m jetty deck (the map's OSM deck): kerbs
    and a galvanised two-rail handrail down both sides of a 10 m run.
    Origin on the deck surface at the centre of the run's landward end; the
    run goes toward -Y (Godot +Z). Repeat it every 10 m."""
    galv = _m("Galv", "#a9adab", 0.45, 0.7)
    jarrah = _m("Jarrah", "#6a4632", 0.9)
    W, L = 3.0, 10.0
    p = []
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.08)
        p.append(bx((x - 0.08, -L, 0.0), (x + 0.08, 0.0, 0.15), jarrah))
        for y in (-0.1, -2.5, -5.0, -7.5, -L + 0.1):
            p.append(bx((x - 0.03, y - 0.03, 0.15), (x + 0.03, y + 0.03, 1.0), galv))
        for z in (0.55, 1.0):
            p.append(cyl(0.022, L, (x, -L / 2, z), galv, segs=6, axis="Y"))
    sockets = {"Cast_L": (-(W / 2 - 0.4), -L / 2, 0.0), "Cast_R": (W / 2 - 0.4, -L / 2, 0.0)}
    col = [((-W / 2, -L, 0.0), (-W / 2 + 0.16, 0.0, 1.0)), ((W / 2 - 0.16, -L, 0.0), (W / 2, 0.0, 1.0))]
    return p, sockets, col


def jetty_lamp():
    """A jetty lamp post, its arm reaching over the deck toward -X. Origin
    at the foot of the post; `Lamp` is the lantern."""
    galv = _m("Galv", "#a9adab", 0.45, 0.7)
    lamp = _m("JettyLamp", "#f2e2b0", 0.3, emit="#f2d890", emit_strength=2.0)
    p = [cyl(0.09, 0.12, (0, 0, 0.06), galv, segs=8),
         cyl(0.05, 3.4, (0, 0, 1.7), galv, segs=8),
         bx((-0.45, -0.03, 3.33), (0.02, 0.03, 3.39), galv),
         bx((-0.52, -0.09, 3.18), (-0.34, 0.09, 3.33), lamp),
         cyl(0.12, 0.06, (-0.43, 0, 3.36), galv, segs=8)]
    return p, {"Lamp": (-0.43, 0.0, 3.15)}, [((-0.06, -0.06, 0.0), (0.06, 0.06, 3.4))]


# ------------------------------------------------------------------ Pelican Point

def pelican_fence():
    """A 20 m run of the sanctuary's chain-wire fence. Origin on the ground
    at the run's west end, running along +X; the public side is -Y
    (Godot +Z). A reserve sign hangs at the middle, facing the public."""
    galv = _m("Galv", "#a9adab", 0.45, 0.7)
    wire = _m("ChainWire", "#8e9493", 0.6, 0.6, alpha=0.4)
    post = _m("Post", "#5a4a3a", 0.95)
    L, H = 20.0, 1.8
    p = []
    for k in range(9):
        x = k * L / 8
        p.append(cyl(0.03, H + 0.05, (x, 0, (H + 0.05) / 2), galv, segs=6))
    p.append(cyl(0.02, L, (L / 2, 0, H), galv, segs=6, axis="X"))
    p.append(bx((0, -0.003, 0.05), (L, 0.003, H), wire))
    for z in (0.05, H * 0.5):
        p.append(cyl(0.006, L, (L / 2, 0, z), galv, segs=4, axis="X"))
    img = FP._sign("reserve_sign", ["NATURE RESERVE", "BIRDS NESTING", "NO ENTRY"], 64, 24, "#f2efe4", "#2f5a3e")
    p.append(bx((L / 2 - 0.45, -0.03, 1.0), (L / 2 + 0.45, -0.01, 1.6), post))
    p.append(FP._sign_quad(img, "ReserveSign", 0.86, 0.32, (L / 2, -0.035, 1.3), facing=-1))
    return p, {}, [((0, -0.05, 0.0), (L, 0.05, H))]


def pelican_lookout():
    """The viewing spot at the sanctuary edge: a low timber deck with a
    rail, a bench and an interpretive board of the waders. Origin on the
    ground at the deck's centre; front (toward the birds) is -Y (Godot +Z)."""
    deck = _m("Deck", "#8b7258", 0.9)
    gap = _m("DeckGap", "#3b3027", 0.9)
    post = _m("Post", "#5a4a3a", 0.95)
    galv = _m("Galv", "#a9adab", 0.45, 0.7)
    p = []
    W, D, Z = 4.5, 3.0, 0.3
    for x in (-W / 2 + 0.15, 0.0, W / 2 - 0.15):
        for y in (-D / 2 + 0.15, D / 2 - 0.15):
            p.append(bx((x - 0.06, y - 0.06, 0.0), (x + 0.06, y + 0.06, Z - 0.05), post))
    p.append(bx((-W / 2, -D / 2, Z - 0.05), (W / 2, D / 2, Z), deck))
    for k in range(1, 15):
        x = -W / 2 + k * W / 15
        p.append(bx((x - 0.008, -D / 2 + 0.02, Z), (x + 0.008, D / 2 - 0.02, Z + 0.002), gap))
    # rail along the front and the sides
    for k in range(7):
        x = -W / 2 + 0.05 + k * (W - 0.1) / 6
        p.append(bx((x - 0.04, -D / 2, Z), (x + 0.04, -D / 2 + 0.08, Z + 1.0), post))
    p.append(bx((-W / 2, -D / 2 - 0.02, Z + 1.0), (W / 2, -D / 2 + 0.1, Z + 1.06), deck))
    p.append(bx((-W / 2 + 0.08, -D / 2 + 0.02, Z + 0.5), (W / 2 - 0.08, -D / 2 + 0.06, Z + 0.55), post))
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.04)
        for y in (-D / 2 + 0.75, -D / 2 + 1.45, D / 2 - 0.84):
            p.append(bx((x - 0.04, y - 0.04, Z), (x + 0.04, y + 0.04, Z + 1.0), post))
        p.append(bx((x - 0.05, -D / 2 + 0.1, Z + 1.0), (x + 0.05, D / 2 - 0.8, Z + 1.06), deck))
        p.append(bx((x - 0.02, -D / 2 + 0.08, Z + 0.5), (x + 0.02, D / 2 - 0.8, Z + 0.55), post))
    # a bench facing the water
    p.append(bx((-1.0, 0.3, Z + 0.42), (1.0, 0.7, Z + 0.47), deck))
    p.append(bx((-1.0, 0.68, Z + 0.47), (1.0, 0.72, Z + 0.85), deck))
    for x in (-0.85, 0.85):
        p.append(bx((x - 0.04, 0.35, Z), (x + 0.04, 0.7, Z + 0.42), galv))
    # the interpretive board, angled up from the rail at one end
    img = FP._sign("waders_board", ["PELICAN POINT", "WADERS OF THE", "SWAN ESTUARY", "",
                                   "WATCH QUIETLY"], 64, 40, "#efe8d4", "#2f4a5a")
    bx_, by_ = W / 2 - 0.7, -D / 2 + 0.35
    for dx in (-0.35, 0.35):
        p.append(bx((bx_ + dx - 0.04, by_ - 0.04, Z), (bx_ + dx + 0.04, by_ + 0.04, Z + 0.95), galv))
    p.append(bx((bx_ - 0.45, by_ - 0.02, Z + 0.95), (bx_ + 0.45, by_ + 0.02, Z + 1.5), post))
    p.append(FP._sign_quad(img, "WadersBoard", 0.84, 0.52, (bx_, by_ + 0.025, Z + 1.225), facing=1))
    sockets = {"View": (0.0, -D / 2 + 0.5, Z), "Bench": (0.0, 0.5, Z + 0.45)}
    col = [((-W / 2, -D / 2, 0.0), (W / 2, D / 2, Z)),
           ((-W / 2, -D / 2, Z), (W / 2, -D / 2 + 0.1, Z + 1.06)),
           ((-W / 2, -D / 2, Z), (-W / 2 + 0.08, D / 2 - 0.8, Z + 1.06)),
           ((W / 2 - 0.08, -D / 2, Z), (W / 2, D / 2 - 0.8, Z + 1.06))]
    return p, sockets, col


def _dinghy(x, y, hull, deck_col, z=0.0):
    """A little sailing dinghy on its trolley, bow toward -Y."""
    Lh, Wh = 3.4, 1.3
    v = [(0, -Lh / 2, 0.15), (Wh * 0.35, -Lh / 2 + 0.6, 0.12), (Wh / 2, 0.0, 0.1), (Wh * 0.45, Lh / 2, 0.15),
         (-Wh * 0.45, Lh / 2, 0.15), (-Wh / 2, 0.0, 0.1), (-Wh * 0.35, -Lh / 2 + 0.6, 0.12)]
    top = [(a, b, 0.55 if i else 0.62) for i, (a, b, _) in enumerate(v)]
    keel = [(a * 0.4, b * 0.95, 0.0) for a, b, _ in v]
    n = len(v)
    verts = [(x + a, y + b, z + c + 0.35) for a, b, c in keel + top]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    out = [C.mesh_obj("hull", verts, faces, hull)]
    out.append(C.mesh_obj("deck", [(x + a, y + b, z + 0.355 + c + 0.002) for a, b, c in top], [tuple(range(n))],
                          deck_col))
    # trolley: an axle and two wheels
    out.append(cyl(0.02, 1.4, (x, y + 0.2, z + 0.2), deck_col, segs=6, axis="X"))
    for sx in (-1, 1):
        out.append(cyl(0.18, 0.08, (x + sx * 0.7, y + 0.2, z + 0.18), hull, segs=8, axis="X"))
    return out


def pelican_sailing_club():
    """A sailing club on the north side of the point: a long single-storey
    clubhouse and boatshed in pale blockwork, the roller doors and a deep
    verandah facing the water, dinghies on trolleys out front and the
    club's flagpole. Origin on the ground at the footprint centre; front
    (the water side) is -Y (Godot +Z). Footprint 20 x 10 m. The name is
    made up."""
    block = _m("Block", "#ddd5c4", 0.95)
    roof = _m("Roof", "#4c6f8c", 0.45, 0.4)                # deep ocean colorbond
    trim = _m("Trim", "#f1efe8", 0.6)
    door = _m("Roller", "#c3c8c8", 0.5, 0.5)
    glass = _m("Glass", "#3a5664", 0.08, 0.3)
    post = _m("SteelPost", "#e9e9e4", 0.5, 0.4)
    conc = _m("Concrete", "#b3aea3", 0.95)
    hulls = [_m("HullWhite", "#f2f2ee", 0.4), _m("HullRed", "#b8352a", 0.4), _m("HullBlue", "#2f5d8c", 0.4)]
    deck_col = _m("DinghyDeck", "#d8d4c8", 0.6)
    flag = _m("ClubFlag", "#2f5d8c", 0.7)
    p = []
    L, D, H = 20.0, 10.0, 3.4
    x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
    p.append(bx((x0 - 2.0, y0 - 8.0, 0.0), (x1 + 2.0, y1 + 0.5, 0.06), conc))     # hardstand to the water
    p.append(bx((x0, y0, 0.06), (x1, y1, H), block))
    # the boatshed's roller doors at the west end and the clubroom's glass at the east
    for xc in (-7.2, -3.6):
        p.append(bx((xc - 1.5, y0 - 0.04, 0.06), (xc + 1.5, y0 + 0.02, 2.8), door))
        for k in range(8):
            z = 0.35 + k * 0.3
            p.append(bx((xc - 1.5, y0 - 0.05, z), (xc + 1.5, y0 - 0.04, z + 0.025), trim))
    p.append(bx((-1.0, y0 - 0.04, 0.3), (x1 - 1.0, y0 + 0.02, 2.7), glass))
    for k in range(7):
        x = -1.0 + k * (x1 - 1.0 + 1.0) / 6 - (0.04 if k == 6 else 0.0)
        p.append(bx((x - 0.04, y0 - 0.06, 0.3), (x + 0.04, y0 + 0.02, 2.7), trim))
    p.append(bx((-1.0, y0 - 0.06, 2.7), (x1 - 1.0, y0 + 0.02, 2.76), trim))
    # skillion roof falling to the back, the verandah running out over the front
    ry0, ry1 = y0 - 3.0, y1 + 0.4
    z_f, z_b = H + 0.6, H + 0.1

    def rz(y):
        return z_f + (z_b - z_f) * (y - ry0) / (ry1 - ry0)
    v = [(x0 - 0.3, ry0, rz(ry0)), (x1 + 0.3, ry0, rz(ry0)), (x1 + 0.3, ry1, rz(ry1)), (x0 - 0.3, ry1, rz(ry1))]
    v2 = [(a, b, c + 0.18) for a, b, c in v]
    p.append(_prism("roof", v + v2, roof))
    p.append(bx((x0 - 0.32, ry0 - 0.05, rz(ry0) - 0.12), (x1 + 0.32, ry0, rz(ry0) + 0.2), trim))
    for k in range(6):
        x = x0 + 0.3 + k * (L - 0.6) / 5
        p.append(bx((x - 0.06, ry0 + 0.1, 0.06), (x + 0.06, ry0 + 0.22, rz(ry0 + 0.16)), post))
    # the sign over the glass, no real club's name
    img = FP._sign("club_sign2", ["POINT SAILING CLUB"], 80, 8, "#2f5d8c", "#f1efe8")
    p.append(TS._quad_image(img, "SailClubSign", 6.0, 0.6, (4.5, y0 - 0.07, 3.05), facing="-y"))
    # dinghies out front and the flagpole with its yardarm
    for i, (x, y) in enumerate(((-8.0, y0 - 5.0), (-6.2, y0 - 5.2), (-4.4, y0 - 5.0), (-2.6, y0 - 5.3))):
        p += _dinghy(x, y, hulls[i % 3], deck_col, 0.06)
    fx, fy = x1 + 1.2, y0 - 5.0
    p.append(cyl(0.3, 0.2, (fx, fy, 0.16), conc, segs=8))
    p.append(_beam((fx, fy, 0.2), (fx, fy, 9.0), 0.06, post))
    p.append(_beam((fx - 1.2, fy, 6.5), (fx + 1.2, fy, 6.5), 0.03, post))
    p.append(bx((fx, fy - 0.01, 8.2), (fx + 1.0, fy + 0.01, 8.8), flag))
    sockets = {"Door": (6.0, y0 - 1.0, 0.06), "Dinghies": (-5.3, y0 - 5.0, 0.06), "Flag": (fx, fy, 9.0)}
    col = [((x0, y0, 0.0), (x1, y1, H)),
           ((fx - 0.3, fy - 0.3, 0.0), (fx + 0.3, fy + 0.3, 9.0))]
    return p, sockets, col


LANDMARKS = {
    "kent_st_weir": kent_st_weir,
    "jetty_rail": jetty_rail,
    "jetty_lamp": jetty_lamp,
    "pelican_fence": pelican_fence,
    "pelican_lookout": pelican_lookout,
    "pelican_sailing_club": pelican_sailing_club,
}
