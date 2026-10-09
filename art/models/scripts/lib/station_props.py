"""Railway platform pieces, plain and unbranded, laid along the OSM
platform outlines (railway=platform) by the map from map/tiles/props.json:

  platform_slab  A 12 m length of raised platform, 4 m wide and 0.95 m up
                 from the rail-level ground it stands on, for platforms the
                 map has no deck for (OSM draws Perth Underground's and
                 Elizabeth Quay's as lines): concrete deck, a coping
                 overhanging both edges, a white edge line and a yellow
                 tactile strip back from each edge. Origin on the ground in
                 the middle; the long side runs along Y.
  platform_slab_island
                 The same 7.5 m wide, for an island platform between two
                 tracks (Perth Underground, Elizabeth Quay).
  platform_edge  The same edge markings on their own, a 12 m strip 1 cm
                 thick to lay on a deck the map already builds (the surface
                 platforms): origin on the deck top at the platform edge, the
                 strip running along Y and reaching 0.75 m in toward +X.
  platform_canopy
                 12 m of canopy for an island or side platform: two steel
                 columns down the middle, a shallow butterfly roof 5 m wide
                 with a gutter in the fold, and light strips underneath.
                 Origin on the deck top in the middle.
  platform_bench A 1.8 m steel bench with slatted seat and back and two
                 legs, facing -Y. Origin on the deck under the middle.
  station_board_<name>
                 A plain name board on two posts, white letters on navy, the
                 same both sides: perth, perth_underground, elizabeth_quay.

Each builder returns (parts, sockets, collision boxes).
"""
from . import common as C
from . import furniture as F
from . import field_places as FP
from . import tackle_shop as TS

bx, cyl = F.bx, F.cyl

L = 12.0            # module length
TOP = 0.95          # platform top above rail-level ground


def _m(name, col, rough=0.8, metal=0.0, **kw):
    return C.mat("ST_" + name, col, rough=rough, metal=metal, **kw)


def _mats():
    return {
        "deck": _m("Deck", "#a9a59c", 0.95),
        "face": _m("Face", "#86837c", 0.95),
        "coping": _m("Coping", "#c9c5bb", 0.9),
        "white": _m("EdgeWhite", "#ecebe4", 0.7),
        "tactile": _m("Tactile", "#e3b52a", 0.8),
        "steel": _m("Steel", "#5d6466", 0.5, 0.6),
        "roof": _m("Roof", "#d8dad6", 0.5, 0.4),
        "under": _m("Soffit", "#9ea3a3", 0.7),
        "light": _m("Light", "#f4f0de", 0.5, emit="#fff4d6", emit_strength=1.2),
        "slat": _m("BenchSlat", "#7d8486", 0.45, 0.6),
    }


def _markings(p, M, x_edge, inward, z):
    """Edge line on the coping and a tactile strip 0.6 m in, along Y."""
    s = 1 if inward > 0 else -1

    def band(a, b, mat, h=0.01):
        x0, x1 = sorted((x_edge + s * a, x_edge + s * b))
        p.append(bx((x0, -L / 2, z), (x1, L / 2, z + h), mat))
    band(0.0, 0.1, M["white"])
    band(0.45, 0.75, M["tactile"])


def platform_slab(W=4.0):
    M = _mats()
    p = []
    # the body stands back from the coping so the edge throws a shadow line
    p.append(bx((-W / 2 + 0.25, -L / 2, 0.0), (W / 2 - 0.25, L / 2, TOP - 0.15), M["face"]))
    p.append(bx((-W / 2 + 0.1, -L / 2, TOP - 0.15), (W / 2 - 0.1, L / 2, TOP), M["deck"]))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (W / 2 - 0.1), sx * W / 2))
        p.append(bx((x0, -L / 2, TOP - 0.15), (x1, L / 2, TOP), M["coping"]))
        _markings(p, M, sx * W / 2, -sx, TOP)
    col = [((-W / 2, -L / 2, 0.0), (W / 2, L / 2, TOP))]
    return p, {"Top": (0, 0, TOP)}, col


def platform_edge():
    M = _mats()
    p = []
    _markings(p, M, 0.0, 1, 0.0)
    return p, {}, []


def _arm_faces(sx):
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return f if sx > 0 else [tuple(reversed(q)) for q in f]


def platform_canopy():
    M = _mats()
    p = []
    W = 5.0
    z_mid, z_edge = 3.35, 3.7          # the roof folds down to a gutter in the middle
    t = 0.12
    for y in (-L / 4, L / 4):
        p.append(cyl(0.12, z_mid - 0.2, (0, y, (z_mid - 0.2) / 2), M["steel"], segs=8))
        p.append(bx((-0.2, y - 0.2, 0.0), (0.2, y + 0.2, 0.08), M["steel"]))           # base plate
        for sx in (-1, 1):                                                              # tapered arms
            p.append(C.mesh_obj("arm", [(0, y - 0.08, z_mid - 0.35), (0, y + 0.08, z_mid - 0.35),
                                        (sx * (W / 2 - 0.1), y + 0.08, z_edge - 0.06),
                                        (sx * (W / 2 - 0.1), y - 0.08, z_edge - 0.06),
                                        (0, y - 0.08, z_mid - 0.05), (0, y + 0.08, z_mid - 0.05),
                                        (sx * (W / 2 - 0.1), y + 0.08, z_edge + 0.01),
                                        (sx * (W / 2 - 0.1), y - 0.08, z_edge + 0.01)],
                                _arm_faces(sx), M["steel"]))
    for sx in (-1, 1):
        xo = sx * W / 2
        v = [(0, -L / 2, z_mid), (0, L / 2, z_mid), (xo, L / 2, z_edge), (xo, -L / 2, z_edge)]
        top = [(x, y, z + t) for x, y, z in v]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        if sx > 0:      # the faces above wind outward for the -X wing; mirror them for +X
            f = [tuple(reversed(q)) for q in f]
        p.append(C.mesh_obj("roof", v + top, f, M["roof"]))
        # a fascia along the outer edge and a light strip under each side
        x0, x1 = sorted((xo, xo + sx * 0.05))
        p.append(bx((x0, -L / 2, z_edge - 0.2), (x1, L / 2, z_edge + t + 0.02), M["steel"]))
        xl = sx * 1.3
        zl = z_mid + (z_edge - z_mid) * 1.3 / (W / 2) - 0.06
        p.append(bx((xl - 0.06, -L / 2 + 0.6, zl - 0.04), (xl + 0.06, L / 2 - 0.6, zl), M["light"]))
    p.append(bx((-0.15, -L / 2, z_mid - 0.12), (0.15, L / 2, z_mid + 0.02), M["steel"]))   # gutter
    col = [((-0.15, y - 0.15, 0.0), (0.15, y + 0.15, z_mid)) for y in (-L / 4, L / 4)]
    col.append(((-W / 2, -L / 2, z_mid), (W / 2, L / 2, z_edge + t)))
    return p, {}, col


def platform_bench():
    M = _mats()
    p = []
    w = 1.8
    for x in (-w / 2 + 0.2, w / 2 - 0.2):
        p.append(bx((x - 0.03, -0.25, 0.0), (x + 0.03, 0.2, 0.42), M["steel"]))        # leg frame
        p.append(bx((x - 0.03, 0.12, 0.42), (x + 0.03, 0.2, 0.85), M["steel"]))        # back upright
        p.append(bx((x - 0.03, -0.25, 0.6), (x + 0.03, 0.05, 0.64), M["steel"]))       # arm
        p.append(bx((x - 0.03, -0.25, 0.42), (x + 0.03, -0.21, 0.64), M["steel"]))
    for i in range(5):                                                                   # seat slats
        y = -0.22 + i * 0.075
        p.append(bx((-w / 2, y, 0.42), (w / 2, y + 0.055, 0.45), M["slat"]))
    for i in range(4):                                                                   # back slats
        z = 0.5 + i * 0.09
        p.append(bx((-w / 2, 0.16 + (z - 0.5) * 0.12, z), (w / 2, 0.19 + (z - 0.5) * 0.12, z + 0.065), M["slat"]))
    return p, {}, [((-w / 2, -0.25, 0.0), (w / 2, 0.22, 0.45))]


BOARDS = {"perth": "PERTH", "perth_underground": "PERTH UNDERGROUND", "elizabeth_quay": "ELIZABETH QUAY"}


def _board(name):
    M = _mats()
    p = []
    text = BOARDS[name]
    w = 0.9 + 0.17 * len(text)
    h, z = 0.5, 2.35
    px = 8 + 8 * len(text)
    img = FP._sign("station_" + name, [text], px, 12, "#f4f2ea", "#1f3558", scale=1)
    navy = _m("BoardNavy", "#1f3558", 0.6)
    p.append(bx((-w / 2, -0.03, z - h / 2), (w / 2, 0.03, z + h / 2), navy))
    p.append(TS._quad_image(img, "Board_" + name, w - 0.08, h - 0.06, (0, -0.032, z), facing="-y"))
    # the back reads the right way round from behind: same image, mirrored
    mat = C.mat("TS_Board_" + name, "#ffffff", rough=0.85, image=img)
    bw, bh = (w - 0.08) / 2, (h - 0.06) / 2
    back = C.mesh_obj("quad", [(bw, 0.032, z - bh), (-bw, 0.032, z - bh), (-bw, 0.032, z + bh), (bw, 0.032, z + bh)],
                      [(0, 1, 2, 3)], mat)
    uv = back.data.uv_layers.new(name="UVMap")
    for li, (u, vv) in zip(back.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, vv)
    p.append(back)
    for x in (-w / 2 + 0.15, w / 2 - 0.15):
        p.append(bx((x - 0.04, -0.04, 0.0), (x + 0.04, 0.04, z - h / 2), M["steel"]))
    return p, {}, [((-w / 2, -0.05, 0.0), (w / 2, 0.05, z + h / 2))]


LANDMARKS = {
    "platform_slab": platform_slab,
    "platform_slab_island": lambda: platform_slab(7.5),
    "platform_edge": platform_edge,
    "platform_canopy": platform_canopy,
    "platform_bench": platform_bench,
}
for _n in BOARDS:
    LANDMARKS["station_board_" + _n] = (lambda n: lambda: _board(n))(_n)
