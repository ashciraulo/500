"""Small set dressing for city buildings the map builds from OSM, placed by
the map from map/tiles/props.json:

  royal_st_roller_door
                 An old goods door set into the crescent on Royal Street,
                 East Perth (the "warehouse on Royal Street" of the 500 L
                 barn find and the magnesium wheels): a faded green roller
                 door half a metre up in its steel guides, a dark gap under
                 it, the drum hood over the top, a painted name across the
                 wall above, a bulkhead light that's always on, and a few boxes and a drum put out by whoever's
                 clearing it.

  lockup_garage  A single tin lock-up off a back lane (the 500 F's "lock-up
                 garage off Bulwer Street"): corrugated walls and a skillion
                 roof, the roller door wound right up, old tyres and boxes.
  lane_carport   A backyard carport off a rear lane (the Nuova's carport
                 behind Hensman Road): four steel posts and a flat tin roof.
  kensington_shed
                 A tin shed with a side window and a bench along one wall (the
                 595's "shed on Kensington Street"); the sliding door is pushed
                 half open.

Each builder returns (parts, sockets, collision boxes). Front toward -Y in
Blender (Godot +Z). The roller door's origin is on the ground at the wall
face, so the back of the model sits flush with the building; the garage,
carport and shed stand on their own, with the origin on the ground in the
middle, where the car sits.
"""
from . import common as C
from . import furniture as F
from . import field_places as FP

bx, cyl = F.bx, F.cyl


def _m(name, col, rough=0.8, metal=0.0, **kw):
    return C.mat("CD_" + name, col, rough=rough, metal=metal, **kw)


def royal_st_roller_door():
    """3.6 m wide, 3.3 m to the top of the guides. The door is wound up
    0.5 m, so it reads as a door someone uses; the gap behind is a dark panel
    just proud of the wall (nothing is drawn inside the building's own mesh). `Wheels` is the spot beside the door, against the
    wall, where something can lean."""
    steel = _m("Steel", "#6c706e", 0.6, 0.5)
    slat = _m("Slat", "#5f7a63", 0.75, 0.3)            # faded Brunswick-ish green
    slat_dark = _m("SlatRib", "#4a5f4e", 0.8, 0.3)
    rust = _m("Rust", "#7a5236", 0.95)
    dark = _m("Dark", "#151514", 1.0)
    conc = _m("Sill", "#9c9890", 0.95)
    card = _m("Cardboard", "#a07d52", 0.95)
    tape = _m("Tape", "#c9b27a", 0.7)
    drum = _m("Drum", "#2f4d6b", 0.6, 0.4)
    lamp = _m("Bulkhead", "#f4e2a8", 0.3, emit="#f2d27c", emit_strength=3.0)
    W, H, UP = 3.6, 3.3, 0.5
    hw = W / 2
    p = []
    # The gap under the door: a shallow dark recess in front of the wall.
    p.append(bx((-hw, -0.05, -0.15), (hw, 0.0, UP), dark))
    # Concrete sill and guides.
    p.append(bx((-hw - 0.15, -0.25, -0.15), (hw + 0.15, 0.0, 0.03), conc))
    for sx in (-1, 1):
        x = sx * (hw + 0.06)
        p.append(bx((x - 0.08, -0.14, -0.1), (x + 0.08, 0.0, H), steel))
        p.append(bx((x - 0.08, -0.145, 0.0), (x + 0.08, -0.135, 0.4), rust))
    # The curtain: horizontal slats with a darker rib every 0.15 m, a
    # bottom rail and a handle.
    p.append(bx((-hw, -0.1, UP), (hw, -0.06, H - 0.05), slat))
    z = UP + 0.15
    while z < H - 0.1:
        p.append(bx((-hw, -0.115, z - 0.02), (hw, -0.1, z + 0.02), slat_dark))
        z += 0.15
    p.append(bx((-hw, -0.13, UP - 0.02), (hw, -0.06, UP + 0.08), steel))
    p.append(bx((-0.2, -0.19, UP + 0.15), (0.2, -0.13, UP + 0.2), steel))
    p.append(bx((0.75, -0.16, UP + 0.02), (0.85, -0.13, UP + 0.12), rust))      # padlock hasp
    # Drum hood over the top.
    p.append(bx((-hw - 0.15, -0.42, H - 0.05), (hw + 0.15, 0.0, H + 0.42), steel))
    p.append(bx((-hw - 0.15, -0.43, H - 0.05), (hw + 0.15, -0.41, H - 0.02), rust))
    # Painted name on a board above the hood.
    img = FP._sign("roller_door_sign", ["ROYAL ST STORES"], 192, 24, "#2b3a30", "#e8dcbc", scale=2)
    p.append(bx((-2.15, -0.05, H + 0.5), (2.15, 0.0, H + 1.15), steel))
    p.append(FP._sign_quad(img, "RollerDoorSign", 4.1, 0.56, (0.0, -0.06, H + 0.825), facing=-1))
    # A caged bulkhead light beside the hood, always on.
    p.append(bx((hw + 0.3, -0.12, H - 0.1), (hw + 0.62, 0.0, H + 0.12), steel))
    p.append(bx((hw + 0.34, -0.15, H - 0.06), (hw + 0.58, -0.12, H + 0.08), lamp))
    # Put out on the footpath side of the door: boxes and a drum.
    p.append(bx((-hw - 1.35, -0.75, 0.0), (-hw - 0.6, -0.15, 0.45), card))
    p.append(bx((-hw - 1.3, -0.72, 0.45), (-hw - 0.75, -0.2, 0.8), card))
    p.append(bx((-hw - 1.3, -0.48, 0.79), (-hw - 0.75, -0.44, 0.81), tape))
    p.append(cyl(0.29, 0.88, (-hw - 1.85, -0.45, 0.44), drum, segs=10))
    p.append(cyl(0.3, 0.03, (-hw - 1.85, -0.45, 0.3), rust, segs=10))
    sockets = {"Wheels": (hw + 1.2, -0.25, 0.0)}
    col = [((-hw - 0.15, -0.42, 0.0), (hw + 0.15, 0.0, H + 0.42)),
           ((-hw - 1.35, -0.75, 0.0), (-hw - 0.6, -0.15, 0.8)),
           ((-hw - 2.15, -0.75, 0.0), (-hw - 1.55, -0.15, 0.88))]
    return p, sockets, col


def _tin(name, col):
    return _m(name, col, 0.7, 0.45)


def _tin_walls(p, col, W, D, H_front, H_back, tin, rib, front_wall=False, hole=None):
    """Corrugated side and back walls (ribbed outside) and a skillion roof
    falling to the back; the front is left open unless front_wall. `hole`
    (y0, y1, z0, z1) cuts an opening in the right-hand (+x) wall."""
    hw, hd = W / 2, D / 2
    t = 0.05
    p.append(bx((-hw - t, -hd, 0.0), (-hw, hd, H_back), tin))
    if hole:
        y0, y1, z0, z1 = hole
        p.append(bx((hw, -hd, 0.0), (hw + t, y0, H_back), tin))
        p.append(bx((hw, y1, 0.0), (hw + t, hd, H_back), tin))
        p.append(bx((hw, y0, 0.0), (hw + t, y1, z0), tin))
        p.append(bx((hw, y0, z1), (hw + t, y1, H_back), tin))
    else:
        p.append(bx((hw, -hd, 0.0), (hw + t, hd, H_back), tin))
    # The side walls rise to the roof line at the front.
    p.append(bx((-hw - t, -hd, H_back), (-hw, 0.0, H_front), tin))
    p.append(bx((hw, -hd, H_back), (hw + t, 0.0, H_front), tin))
    p.append(bx((-hw - t, hd - t, 0.0), (hw + t, hd, H_back), tin))
    x = -hw + 0.15
    while x < hw:
        p.append(bx((x - 0.025, hd, 0.0), (x + 0.025, hd + 0.03, H_back - 0.02), rib))
        x += 0.3
    for sx in (-1, 1):
        y = -hd + 0.15
        while y < hd:
            spans = [(0.0, H_back - 0.02)]
            if hole and sx == 1 and hole[0] - 0.025 < y < hole[1] + 0.025:
                spans = [(0.0, hole[2]), (hole[3], H_back - 0.02)]
            for z0, z1 in spans:
                p.append(bx((sx * (hw + t) - 0.015, y - 0.025, z0), (sx * (hw + t) + 0.015, y + 0.025, z1), rib))
            y += 0.3
    # Roof: two slabs stepping down front to back, overhanging all round.
    mid = (H_front + H_back) / 2
    p.append(bx((-hw - 0.2, -hd - 0.25, mid), (hw + 0.2, 0.0, H_front + 0.04), tin))
    p.append(bx((-hw - 0.2, 0.0, H_back), (hw + 0.2, hd + 0.2, mid + 0.04), tin))
    if front_wall:
        p.append(bx((-hw - t, -hd - t, 0.0), (hw + t, -hd, H_front), tin))
    else:
        # A header over the opening.
        p.append(bx((-hw - t, -hd - t, H_front - 0.3), (hw + t, -hd, H_front), tin))


def lockup_garage():
    """3.4 m wide, 6 m deep, 2.6 m high at the front. A car fits inside with
    room to walk round it."""
    tin = _tin("LockupTin", "#7d8a7f")
    rib = _tin("LockupRib", "#68746a")
    rust = _m("Rust", "#7a5236", 0.95)
    steel = _m("Steel", "#6c706e", 0.6, 0.5)
    slat = _m("Slat", "#5f7a63", 0.75, 0.3)
    floor = _m("Floor", "#77736b", 0.95)
    oil = _m("Oil", "#2a2926", 0.9)
    rubber = _m("Tyre", "#1d1d1c", 0.95)
    card = _m("Cardboard", "#a07d52", 0.95)
    W, D, HF, HB = 3.4, 6.0, 2.6, 2.35
    hw, hd = W / 2, D / 2
    p = []
    _tin_walls(p, None, W, D, HF, HB, tin, rib)
    p.append(bx((-hw, -hd, -0.1), (hw, hd, 0.02), floor))
    p.append(bx((-0.6, -0.4, 0.02), (0.5, 0.7, 0.025), oil))
    # The roller door wound up into its drum under the header, with rust
    # bleeding down the guides.
    p.append(bx((-hw + 0.05, -hd - 0.45, HF - 0.75), (hw - 0.05, -hd - 0.05, HF - 0.3), steel))
    p.append(bx((-hw + 0.05, -hd - 0.46, HF - 0.77), (hw - 0.05, -hd - 0.44, HF - 0.72), slat))
    for sx in (-1, 1):
        x = sx * (hw - 0.06)
        p.append(bx((x - 0.06, -hd - 0.1, 0.0), (x + 0.06, -hd, HF - 0.3), steel))
        p.append(bx((x - 0.06, -hd - 0.105, 0.0), (x + 0.06, -hd - 0.095, 0.5), rust))
    # Old tyres stacked at the back corner, boxes on the other side.
    for k in range(3):
        p.append(cyl(0.3, 0.19, (hw - 0.4, hd - 0.45, 0.1 + k * 0.2), rubber, segs=10))
    p.append(bx((-hw + 0.1, hd - 0.75, 0.0), (-hw + 0.75, hd - 0.1, 0.5), card))
    p.append(bx((-hw + 0.15, hd - 0.7, 0.5), (-hw + 0.65, hd - 0.2, 0.85), card))
    col = [((-hw - 0.05, -hd, 0.0), (-hw, hd, HB)), ((hw, -hd, 0.0), (hw + 0.05, hd, HB)),
           ((-hw - 0.05, hd - 0.05, 0.0), (hw + 0.05, hd, HB)),
           ((-hw - 0.2, -hd - 0.25, HB), (hw + 0.2, hd + 0.2, HF + 0.04))]
    return p, {}, col


def lane_carport():
    """3 m wide, 5.6 m long, 2.3 m clear under the roof."""
    steel = _m("CarportSteel", "#c9c6bc", 0.6, 0.4)
    tin = _tin("CarportTin", "#a9b0a8")
    rib = _tin("CarportRib", "#959c94")
    rust = _m("Rust", "#7a5236", 0.95)
    conc = _m("Slab", "#9c9890", 0.95)
    oil = _m("Oil", "#2a2926", 0.9)
    W, D, H = 3.0, 5.6, 2.3
    hw, hd = W / 2, D / 2
    p = []
    p.append(bx((-hw - 0.1, -hd - 0.1, -0.1), (hw + 0.1, hd + 0.1, 0.03), conc))
    p.append(bx((-0.5, -0.2, 0.03), (0.4, 0.8, 0.035), oil))
    posts = [(sx * (hw - 0.05), sy * (hd - 0.05)) for sx in (-1, 1) for sy in (-1, 1)]
    for x, y in posts:
        p.append(bx((x - 0.05, y - 0.05, 0.0), (x + 0.05, y + 0.05, H), steel))
        p.append(bx((x - 0.055, y - 0.055, 0.0), (x + 0.055, y + 0.055, 0.12), rust))
    for sx in (-1, 1):
        p.append(bx((sx * (hw - 0.05) - 0.05, -hd - 0.05, H - 0.15), (sx * (hw - 0.05) + 0.05, hd + 0.05, H), steel))
    p.append(bx((-hw - 0.15, -hd - 0.2, H), (hw + 0.15, hd + 0.2, H + 0.05), tin))
    y = -hd - 0.05
    while y < hd + 0.1:
        p.append(bx((-hw - 0.15, y - 0.03, H + 0.05), (hw + 0.15, y + 0.03, H + 0.08), rib))
        y += 0.3
    col = [((x - 0.05, y - 0.05, 0.0), (x + 0.05, y + 0.05, H)) for x, y in posts]
    col.append(((-hw - 0.15, -hd - 0.2, H), (hw + 0.15, hd + 0.2, H + 0.08)))
    return p, {}, col


def kensington_shed():
    """3.8 m wide, 6.6 m deep, 2.7 m at the front. A window in the right-hand
    wall, a bench along it inside; `Bench` is the middle of the bench top."""
    tin = _tin("ShedTin", "#8e8f86")
    rib = _tin("ShedRib", "#7a7b73")
    rust = _m("Rust", "#7a5236", 0.95)
    steel = _m("Steel", "#6c706e", 0.6, 0.5)
    floor = _m("Floor", "#77736b", 0.95)
    wood = _m("BenchWood", "#8a6a45", 0.9)
    glass = _m("ShedGlass", "#9fb4ba", 0.1, 0.2, alpha=0.22)
    frame = _m("ShedFrame", "#d8d3c4", 0.8)
    rubber = _m("Tyre", "#1d1d1c", 0.95)
    W, D, HF, HB = 3.8, 6.6, 2.7, 2.45
    hw, hd = W / 2, D / 2
    # Window in the right-hand wall, over the bench (centre y, z; size).
    wy, wz, ww, wh = -0.4, 1.55, 1.4, 0.8
    hole = (wy - ww / 2, wy + ww / 2, wz - wh / 2, wz + wh / 2)
    p = []
    _tin_walls(p, None, W, D, HF, HB, tin, rib, hole=hole)
    p.append(bx((-hw, -hd, -0.1), (hw, hd, 0.02), floor))
    # Front: a fixed panel on the left, the sliding door pushed back over it,
    # leaving the right half open.
    p.append(bx((-hw - 0.05, -hd - 0.05, 0.0), (-0.1, -hd, HF - 0.3), tin))
    p.append(bx((-hw + 0.1, -hd - 0.12, 0.05), (0.2, -hd - 0.07, HF - 0.35), tin))
    p.append(bx((-hw - 0.05, -hd - 0.16, HF - 0.36), (hw + 0.05, -hd - 0.06, HF - 0.3), steel))
    p.append(bx((-hw + 0.1, -hd - 0.125, 0.05), (0.2, -hd - 0.115, 0.45), rust))
    # The window: one pane of dusty, see-through glass in a cream frame, in
    # the opening cut from the tin, so the bench and the car show through.
    p.append(bx((hw + 0.022, wy - ww / 2, wz - wh / 2), (hw + 0.028, wy + ww / 2, wz + wh / 2), glass))
    p.append(bx((hw + 0.05, wy - ww / 2 - 0.06, wz - wh / 2 - 0.06), (hw + 0.08, wy + ww / 2 + 0.06, wz - wh / 2), frame))
    p.append(bx((hw + 0.05, wy - ww / 2 - 0.06, wz + wh / 2), (hw + 0.08, wy + ww / 2 + 0.06, wz + wh / 2 + 0.06), frame))
    for e in (-1, 1):
        p.append(bx((hw + 0.05, wy + e * ww / 2 - 0.03, wz - wh / 2), (hw + 0.08, wy + e * ww / 2 + 0.03, wz + wh / 2), frame))
    p.append(bx((hw + 0.05, wy - 0.02, wz - wh / 2), (hw + 0.08, wy + 0.02, wz + wh / 2), frame))
    # The bench under the window.
    bt = 0.9
    p.append(bx((hw - 0.6, -1.6, bt - 0.05), (hw - 0.02, 1.0, bt), wood))
    for y in (-1.5, 0.9):
        for x in (hw - 0.55, hw - 0.1):
            p.append(bx((x - 0.03, y - 0.03, 0.0), (x + 0.03, y + 0.03, bt - 0.05), wood))
    p.append(bx((hw - 0.55, -1.55, 0.25), (hw - 0.07, 0.95, 0.28), wood))
    # A vice and a tyre leaning on the back wall.
    p.append(bx((hw - 0.5, 0.6, bt), (hw - 0.3, 0.8, bt + 0.12), steel))
    p.append(cyl(0.3, 0.18, (-hw + 0.55, hd - 0.25, 0.3), rubber, segs=10, axis="Y"))
    sockets = {"Bench": (hw - 0.3, -0.6, bt)}
    # The right-hand wall's collider leaves the window open, so a look (or
    # a ray) through it reaches the bench and the car.
    col = [((-hw - 0.05, -hd, 0.0), (-hw, hd, HB)),
           ((hw, -hd, 0.0), (hw + 0.05, hole[0], HB)), ((hw, hole[1], 0.0), (hw + 0.05, hd, HB)),
           ((hw, hole[0], 0.0), (hw + 0.05, hole[1], hole[2])), ((hw, hole[0], hole[3]), (hw + 0.05, hole[1], HB)),
           ((-hw - 0.05, hd - 0.05, 0.0), (hw + 0.05, hd, HB)),
           ((-hw - 0.05, -hd - 0.16, 0.0), (0.2, -hd, HF - 0.3)),
           ((hw - 0.6, -1.6, 0.0), (hw, 1.0, bt)),
           ((-hw - 0.2, -hd - 0.25, HB), (hw + 0.2, hd + 0.2, HF + 0.04))]
    return p, sockets, col


LANDMARKS = {
    "royal_st_roller_door": royal_st_roller_door,
    "lockup_garage": lockup_garage,
    "lane_carport": lane_carport,
    "kensington_shed": kensington_shed,
}
