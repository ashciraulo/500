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

Each builder returns (parts, sockets, collision boxes). Front toward -Y in
Blender (Godot +Z); the origin is on the ground at the wall face, so the
back of the model sits flush with the building.
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


LANDMARKS = {
    "royal_st_roller_door": royal_st_roller_door,
}
