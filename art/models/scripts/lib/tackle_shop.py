"""The bait and tackle shop on Mends Street, South Perth, up from the jetty:
the fishing side's dock, where the esky is weighed in.

An Inter-War shop like the ones still on Mends Street: a rendered
stripped-classical parapet between two pilasters, a bullnose verandah
cantilevered over the footpath on wrought-iron brackets (no posts), a
green-tiled stallriser under timber shop windows, amber highlight windows
over a recessed door. The ice freezer and a sandwich board sit out front.

Inside, a small walk-in room: rods standing in a floor rack down the left
wall, a pegboard of hooks, sinkers and lures down the right with eskies
stacked under it, a gondola of reels and line in the middle, a glass-front
upright bait fridge, crab drop nets hung from the ceiling, and the counter
across the back with the till, a fish measuring board and the weigh-in
scale (a spring balance hanging a steel tray from a little gantry). Behind
the counter: the brag board of customers' catch photos, a chalkboard of
the month's biggest fish, a mounted dhufish, the bait chest freezer and
the door to the back room.

shop() returns (parts, sockets, collision): front toward -Y, origin at the
base centre of the building line, the room running back along +Y. The
collision parts are plain boxes for the walls, counter and fittings (the
build exports them as a `-colonly` node so Godot makes them a static body).
All names are made up.
"""
import math
import random

from . import common as C
from . import furniture as F
from . import field_places as FP

bx, cyl = F.bx, F.cyl

W = 5.6           # frontage
D = 7.0           # depth of the shop, building line to back wall
CEIL = 3.2
PARAPET = 4.7
WALL_T = 0.22
DOOR_X, DOOR_W, DOOR_H = -0.5, 1.0, 2.25
RECESS = 0.9      # the door sits this far back from the building line
SILL, HEAD = 0.6, 2.55
COUNTER_Y = (4.75, 5.4)
COUNTER_X = (-2.0, 1.35)
COUNTER_H = 1.0


def _m(name, col, rough=0.8, metal=0.0, **kw):
    return C.mat("TS_" + name, col, rough=rough, metal=metal, **kw)


def _mats():
    M = FP._mats()
    M.update({
        "render": _m("Render", "#e3d6b8", 0.9),             # cream render
        "trim": _m("Trim", "#2f5a46", 0.6),                 # Brunswick green
        "tile": _m("Tile", "#1f4a3c", 0.25),                # glazed stallriser tiles
        "tile_cap": _m("TileCap", "#d9cfb2", 0.4),
        "sash": _m("Sash", "#efe7d2", 0.6),
        "amber": _m("Amber", "#c98a2e", 0.2, emit="#a06a1e", emit_strength=0.15),
        "iron": _m("Iron", "#1d201f", 0.6, 0.3),
        "roof": _m("Corrugated", "#b9bfbd", 0.45, 0.6),
        "soffit": _m("Soffit", "#e9e3d3", 0.8),
        "lino": _m("Lino", "#9a8e74", 0.85),
        "mat": _m("DoorMat", "#3a3330", 1.0),
        "wall_in": _m("WallIn", "#d9dccf", 0.9),            # pale green-grey paint
        "ply": _m("Ply", "#c79f6a", 0.75),
        "peg": _m("Pegboard", "#b48a5a", 0.9),
        "white": _m("WhiteGoods", "#ecebe6", 0.45),
        "steel": _m("Steel", "#c3c6c8", 0.3, 0.8),
        "glass": _m("CaseGlass", "#a9c4cc", 0.05, alpha=0.3),
        "dark": _m("BackRoom", "#1a1816", 0.9),
        "cork": _m("Cork", "#b98c5a", 1.0),
        "chalk": _m("Chalkboard", "#26302b", 0.9),
        "photo": _m("PhotoBorder", "#f3efe4", 0.6),
        "rubber": _m("Rubber", "#1b1b1c", 0.9),
        "blue": _m("EskyBlue", "#2f62a8", 0.5),
        "red": _m("EskyRed", "#b4302a", 0.5),
        "yellow": _m("Yellow", "#e2b21f", 0.5),
        "cork_grip": _m("CorkGrip", "#b88c5a", 0.95),
        "net": _m("Net", "#4f5d4a", 0.9, alpha=0.6),
        "tube": F.emissive("TS_Tube", "#f4f8ff", 2.0),
        "fish": _m("Dhufish", "#8c8a8f", 0.35, 0.4),
        "fish_dark": _m("DhufishDark", "#4d4a55", 0.4, 0.3),
        "bait": _m("BaitTub", "#e8e4d8", 0.5),
        "bait_lid": _m("BaitLid", "#d8582a", 0.5),
        "fridge_lit": F.emissive("TS_FridgeLight", "#eef6ff", 0.6),
    })
    return M


def _quad_image(img, name, w, h, loc, facing="-y"):
    """A flat textured quad facing -Y (default), +X or -X, centred on loc."""
    mat = C.mat("TS_" + name, "#ffffff", rough=0.85, image=img)
    x, y, z = loc
    if facing == "-y":
        v = [(x - w / 2, y, z - h / 2), (x + w / 2, y, z - h / 2), (x + w / 2, y, z + h / 2), (x - w / 2, y, z + h / 2)]
    elif facing == "+x":     # seen from +X: left is -Y
        v = [(x, y - w / 2, z - h / 2), (x, y + w / 2, z - h / 2), (x, y + w / 2, z + h / 2), (x, y - w / 2, z + h / 2)]
    else:                    # -x: seen from -X, left is +Y
        v = [(x, y + w / 2, z - h / 2), (x, y - w / 2, z - h / 2), (x, y - w / 2, z + h / 2), (x, y + w / 2, z + h / 2)]
    o = C.mesh_obj("quad", v, [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, vv) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, vv)
    return o


def _beam(a, b, r, mat, segs=4):
    """A thin bar from a to b (a wrought-iron strut, a chain, a rod)."""
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder("bar", r, d.length, segs=segs, material=mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (a + b) / 2
    return o


def fish_shape(length, depth, mat, fin_mat, loc=(0, 0, 0), facing=1, thick=0.35):
    """A deep-bodied fish in profile in the XZ plane (head toward +X when
    facing is 1), flattened across Y: a lofted body and a forked tail."""
    x0, y0, z0 = loc
    L, H, T = length, depth, depth * thick
    stations = [(0.0, 0.05), (0.08, 0.55), (0.25, 0.92), (0.45, 1.0), (0.65, 0.8), (0.82, 0.38), (0.88, 0.22)]
    ring = [(0, 1), (0.7, 0.55), (1, 0), (0.7, -0.6), (0, -1), (-0.7, -0.6), (-1, 0), (-0.7, 0.55)]
    v, f = [], []
    n = len(ring)
    for t, s in stations:
        x = (0.5 - t) * L * facing
        for cy, cz in ring:
            v.append((x0 + x, y0 + cy * T / 2 * s, z0 + cz * H / 2 * s))
    for i in range(len(stations) - 1):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            f.append((a, b, b + n, a + n) if facing > 0 else (a, a + n, b + n, b))
    f.append(tuple(range(n))[::-1] if facing > 0 else tuple(range(n)))
    last = (len(stations) - 1) * n
    f.append(tuple(range(last, last + n)) if facing > 0 else tuple(range(last, last + n))[::-1])
    body = C.mesh_obj("fish", v, f, mat)
    # forked tail and a dorsal fin, thin plates
    xt = (0.5 - 0.88) * L * facing
    xe = (0.5 - 1.0) * L * facing
    tail = C.mesh_obj("tail", [(x0 + xt, y0 - 0.004, z0 - H * 0.08), (x0 + xe, y0, z0 - H * 0.42),
                               (x0 + xe + 0.04 * L * facing, y0, z0), (x0 + xe, y0, z0 + H * 0.42),
                               (x0 + xt, y0 + 0.004, z0 + H * 0.08)],
                      [(0, 1, 2), (0, 2, 4), (4, 2, 3), (2, 1, 0), (4, 2, 0), (3, 2, 4)], fin_mat)
    xd0, xd1 = (0.5 - 0.22) * L * facing, (0.5 - 0.7) * L * facing
    dorsal = C.mesh_obj("dorsal", [(x0 + xd0, y0, z0 + H * 0.44), (x0 + xd1, y0, z0 + H * 0.36),
                                   (x0 + (xd0 + xd1) / 2, y0, z0 + H * 0.68)],
                        [(0, 1, 2), (2, 1, 0)], fin_mat)
    return [body, tail, dorsal]


# ------------------------------------------------------------------ outside

def _facade(M):
    p = []
    w2 = W / 2
    # parapet and wall above the verandah, pilasters, cornice
    p.append(bx((-w2, 0.0, HEAD + 0.45), (w2, WALL_T, PARAPET), M["render"]))
    p.append(bx((-w2 - 0.02, -0.08, 3.85), (w2 + 0.02, 0.05, 3.97), M["render"]))          # cornice band
    p.append(bx((-w2 - 0.04, -0.06, PARAPET - 0.12), (w2 + 0.04, WALL_T + 0.04, PARAPET), M["render"]))
    p.append(bx((-1.6, -0.03, 4.08), (1.6, 0.0, 4.52), M["render"]))                       # raised panel
    for sx in (-1, 1):
        x0, x1 = sorted((sx * w2, sx * (w2 - 0.38)))
        p.append(bx((x0, -0.06, 0.0), (x1, WALL_T, PARAPET + 0.18), M["render"]))          # pilaster
        p.append(bx((x0 - 0.02, -0.08, PARAPET + 0.1), (x1 + 0.02, WALL_T + 0.02, PARAPET + 0.22), M["render"]))
        p.append(bx((x0 - 0.02, -0.08, 0.0), (x1 + 0.02, 0.02, 0.35), M["tile"]))           # plinth
    # the name on the panel and the year in the parapet
    p.append(_quad_image(FP._sign("ts_name", ["MENDS ST BAIT"], 64, 8, "#2f5a46", "#e3d6b8"), "Name",
                         3.0, 0.38, (0, -0.035, 4.3)))
    # a stepped centre with the year
    p.append(bx((-0.75, 0.0, PARAPET), (0.75, WALL_T, PARAPET + 0.32), M["render"]))
    p.append(bx((-0.8, -0.04, PARAPET + 0.32), (0.8, WALL_T + 0.04, PARAPET + 0.4), M["render"]))
    p.append(_quad_image(FP._sign("ts_year", ["1928"], 24, 8, "#8a7a5a", "#e3d6b8"), "Year",
                         0.6, 0.2, (0, -0.005, PARAPET + 0.16)))
    # wall between the window heads and the verandah, highlight windows
    inner = w2 - 0.38
    p.append(bx((-inner, 0.0, HEAD), (inner, WALL_T, HEAD + 0.45), M["render"]))
    # stallriser and sills either side of the door recess
    dl, dr = DOOR_X - DOOR_W / 2 - 0.1, DOOR_X + DOOR_W / 2 + 0.1
    for x0, x1 in ((-inner, dl), (dr, inner)):
        p.append(bx((x0, 0.02, 0.0), (x1, 0.18, SILL - 0.05), M["tile"]))
        p.append(bx((x0, -0.01, SILL - 0.05), (x1, 0.2, SILL), M["tile_cap"]))
        # timber frame: sill rail, head rail, a transom at 2.1, mullions
        p.append(bx((x0, 0.05, SILL), (x1, 0.15, SILL + 0.07), M["sash"]))
        p.append(bx((x0, 0.05, HEAD - 0.08), (x1, 0.15, HEAD), M["sash"]))
        p.append(bx((x0, 0.05, 2.08), (x1, 0.15, 2.14), M["sash"]))
        p.append(bx((x0, 0.05, SILL), (x0 + 0.07, 0.15, HEAD), M["sash"]))
        p.append(bx((x1 - 0.07, 0.05, SILL), (x1, 0.15, HEAD), M["sash"]))
        if x1 - x0 > 1.4:
            xm = (x0 + x1) / 2
            p.append(bx((xm - 0.03, 0.05, SILL), (xm + 0.03, 0.15, 2.08), M["sash"]))
        p.append(bx((x0 + 0.07, 0.095, SILL + 0.07), (x1 - 0.07, 0.105, 2.08), M["glass"]))
        p.append(bx((x0 + 0.07, 0.095, 2.14), (x1 - 0.07, 0.105, HEAD - 0.08), M["amber"]))
        for k in range(1, 4):                                                         # leadlight bars
            x = x0 + (x1 - x0) * k / 4
            p.append(bx((x - 0.008, 0.09, 2.14), (x + 0.008, 0.11, HEAD - 0.08), M["iron"]))
    # door recess: tiled floor, reveals, the door and its highlight
    p.append(bx((dl, 0.0, -0.02), (dr, RECESS, 0.0), M["tile_cap"]))
    for x in (dl, dr):
        p.append(bx((x - 0.05, 0.0, 0.0), (x + 0.05, RECESS, HEAD), M["sash"]))
    p.append(bx((dl, 0.0, DOOR_H), (dr, RECESS + 0.1, HEAD), M["sash"]))
    p.append(bx((dl + 0.05, RECESS - 0.02, DOOR_H + 0.06), (dr - 0.05, RECESS, HEAD - 0.06), M["amber"]))
    # a little OPEN sign in the left window
    p.append(_quad_image(FP._sign("ts_open", ["OPEN"], 20, 8, "#f2ecd8", "#b4302a"), "Open",
                         0.42, 0.17, (dl - 0.45, 0.085, 1.75)))
    p.append(bx((dl - 0.66, 0.0, 0.0), (dl - 0.1, 0.02, 0.0), M["iron"]))
    return p


def _door(M):
    """The shop door, standing open into the shop (hinged on its left)."""
    p = []
    x0 = DOOR_X - DOOR_W / 2
    a = math.radians(70)
    ca, sa = math.cos(a), math.sin(a)
    def pt(u, z, t=0.0):
        return (x0 + u * ca - t * sa, RECESS + u * sa + t * ca, z)
    w = DOOR_W - 0.04
    frame = [((0, 0.0), (w, 0.1)), ((0, DOOR_H - 0.1), (w, DOOR_H)), ((0, 0.0), (0.1, DOOR_H)),
             ((w - 0.1, 0.0), (w, DOOR_H)), ((0, 0.9), (w, 1.05))]
    for (u0, z0), (u1, z1) in frame:
        v = [pt(u0, z0, -0.02), pt(u1, z0, -0.02), pt(u1, z0, 0.02), pt(u0, z0, 0.02),
             pt(u0, z1, -0.02), pt(u1, z1, -0.02), pt(u1, z1, 0.02), pt(u0, z1, 0.02)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        p.append(C.mesh_obj("door", v, f, M["trim"]))
    for z0, z1 in ((0.1, 0.9), (1.05, DOOR_H - 0.1)):
        v = [pt(0.1, z0), pt(w - 0.1, z0), pt(w - 0.1, z1), pt(0.1, z1)]
        p.append(C.mesh_obj("pane", v, [(0, 1, 2, 3), (3, 2, 1, 0)], M["glass"]))
    # push plate and a little bell on the frame above
    hx, hy, _ = pt(w - 0.15, 0, -0.03)
    p.append(bx((hx - 0.03, hy - 0.01, 1.0), (hx + 0.03, hy + 0.01, 1.3), M["steel"]))
    p.append(cyl(0.035, 0.05, (DOOR_X + 0.1, RECESS + 0.12, DOOR_H - 0.04), M["brass"] if "brass" in M else M["steel"],
                 segs=8, r_top=0.012))
    return p


def _verandah(M):
    """Bullnose corrugated iron on three wrought-iron brackets."""
    p = []
    w2 = W / 2
    depth, z0 = 2.5, 3.05
    # the bullnose profile: flat back, rolling down at the front edge
    prof = [(0.0, z0 + 0.25)]
    for i in range(1, 9):
        t = i / 8
        a = t * math.pi / 2
        prof.append((-(depth - 0.55) - 0.55 * math.sin(a), z0 + 0.25 - 0.08 * t - 0.4 * (1 - math.cos(a))))
    prof.insert(1, (-(depth - 0.55), z0 + 0.2))
    v, f = [], []
    for x in (-w2 - 0.05, w2 + 0.05):
        for y, z in prof:
            v.append((x, y, z))
    n = len(prof)
    for i in range(n - 1):
        f.append((i, i + 1, n + i + 1, n + i))
    p.append(C.mesh_obj("roof", v, f, M["roof"]))
    v2 = [(x, y, z - 0.02) for x, y, z in v]
    f2 = [(a, d, c, b) for a, b, c, d in f]
    p.append(C.mesh_obj("soffit", v2, f2, M["soffit"]))
    # corrugations as faint ribs along the slope
    for k in range(10):
        x = -w2 + (k + 0.5) * W / 10
        for i in range(n - 1):
            p.append(_beam((x, prof[i][0], prof[i][1] + 0.008), (x, prof[i + 1][0], prof[i + 1][1] + 0.008),
                           0.008, M["roof"], segs=3))
    # brackets: a top arm, a diagonal strut and a scroll ring, fixed to the facade
    for x in (-w2 + 0.19, w2 - 0.19):
        arm_y = -(depth - 0.5)
        p.append(_beam((x, 0.0, z0 + 0.17), (x, arm_y, z0 + 0.17), 0.022, M["iron"]))
        p.append(_beam((x, 0.0, z0 - 0.9), (x, arm_y * 0.75, z0 + 0.17), 0.02, M["iron"]))
        p.append(_beam((x, 0.0, z0 - 0.9), (x, 0.0, z0 + 0.17), 0.022, M["iron"]))
        for i in range(10):
            a0, a1 = 2 * math.pi * i / 10, 2 * math.pi * (i + 1) / 10
            cy, cz, r = -0.2 - 0.06, z0 - 0.05, 0.2
            p.append(_beam((x, cy + r * math.cos(a0), cz + r * math.sin(a0)),
                           (x, cy + r * math.cos(a1), cz + r * math.sin(a1)), 0.012, M["iron"], segs=3))
    # gutter along the front edge, the fascia sign
    fy, fz = prof[-1]
    p.append(cyl(0.06, W + 0.1, (0, fy - 0.02, fz + 0.02), M["roof"], segs=6, axis="X"))
    # the signwriting on the wall under the verandah
    p.append(_quad_image(FP._sign("ts_fascia", ["LIVE BAIT · ICE · RODS · REELS · WEIGH-INS"], 192, 8,
                                  "#f2ecd8", "#2f5a46"), "Fascia", W - 1.0, 0.24, (0, -0.005, HEAD + 0.22)))
    # the hanging sign under the verandah, both faces
    hang = FP._sign("ts_hang", ["BAIT"], 24, 10, "#f2ecd8", "#2f5a46")
    hx = w2 - 1.1
    for fy_, face in ((-1.3 - 0.012, -1), (-1.3 + 0.012, 1)):
        q = FP._sign_quad(hang, "TS_Hang", 0.9, 0.36, (hx, fy_, 2.75), facing=face)
        p.append(q)
    for x in (hx - 0.35, hx + 0.35):
        p.append(bx((x - 0.01, -1.31, 2.93), (x + 0.01, -1.29, z0 + 0.15), M["galv"]))
    return p


def _ice_freezer(M, at):
    """A white chest freezer of bagged ice on the footpath, ICE on the front."""
    x, y = at
    w, d, h = 1.25, 0.68, 0.88
    p = [bx((x - w / 2, y - d / 2, 0.06), (x + w / 2, y + d / 2, h - 0.06), M["white"]),
         bx((x - w / 2 - 0.01, y - d / 2 - 0.01, h - 0.06), (x + w / 2 + 0.01, y + d / 2 + 0.01, h), M["white"]),
         bx((x - w / 2 + 0.05, y - d / 2 + 0.05, 0.0), (x + w / 2 - 0.05, y + d / 2 - 0.05, 0.06), M["rubber"]),
         bx((x - 0.18, y - d / 2 - 0.03, h - 0.12), (x + 0.18, y - d / 2 - 0.01, h - 0.08), M["steel"])]
    p.append(_quad_image(FP._sign("ts_ice", ["ICE"], 16, 8, "#2f62a8", "#ecebe6"), "Ice",
                         0.75, 0.38, (x, y - d / 2 - 0.004, 0.45)))
    p.append(_quad_image(FP._sign("ts_ice2", ["BAGGED · BLOCK"], 64, 8, "#2f62a8", "#ecebe6"), "IceSub",
                         0.9, 0.11, (x, y - d / 2 - 0.004, 0.19)))
    return p


def _sandwich_board(M, at):
    x, y = at
    p = []
    img = FP._sign("ts_board", ["LIVE BAIT", "WORMS", "PRAWNS", "MULIES", "SQUID"], 40, 36, "#f4f0e2", "#26302b")
    for s in (-1, 1):
        # each leaf leans in to meet at the top
        top = (x, y, 1.0)
        bot = (x, y + s * 0.42 * math.sin(math.radians(25)), 0.0)
        v = [(x - 0.32, bot[1], 0.0), (x + 0.32, bot[1], 0.0), (x + 0.32, top[1], 1.0), (x - 0.32, top[1], 1.0)]
        if s > 0:
            v = [v[1], v[0], v[3], v[2]]
        o = C.mesh_obj("board", v, [(0, 1, 2, 3)], C.mat("TS_Board", "#ffffff", rough=0.9, image=img))
        uv = o.data.uv_layers.new(name="UVMap")
        for li, (u, vv) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
            uv.data[li].uv = (u, vv)
        p.append(o)
        back = C.mesh_obj("boardback", [(vv[0], vv[1] - 0.002 * s, vv[2]) for vv in v][::-1], [(0, 1, 2, 3)],
                          M["trim"])
        p.append(back)
    return p


# ------------------------------------------------------------------ inside

def _room(M):
    p = []
    w2 = W / 2
    xi = w2 - WALL_T
    p.append(bx((-w2, RECESS, -0.02), (w2, D, 0.0), M["lino"]))
    p.append(bx((DOOR_X - 0.5, RECESS + 0.05, 0.0), (DOOR_X + 0.5, RECESS + 0.75, 0.012), M["mat"]))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * w2, sx * xi))
        p.append(bx((x0, WALL_T, 0.0), (x1, D, CEIL + 0.1), M["wall_in"]))
    p.append(bx((-w2, D - WALL_T, 0.0), (w2, D, CEIL + 0.1), M["wall_in"]))
    p.append(bx((-w2, WALL_T, CEIL), (w2, D, CEIL + 0.06), M["soffit"]))
    # the shopfront's inside: the window backs are open; walls either side of the recess
    dl, dr = DOOR_X - DOOR_W / 2 - 0.1, DOOR_X + DOOR_W / 2 + 0.1
    for x0, x1 in ((-xi, dl - 0.05), (dr + 0.05, xi)):
        p.append(bx((x0, 0.2, 0.0), (x1, 0.32, SILL), M["wall_in"]))                  # window back under sill
        p.append(bx((x0, 0.2, SILL - 0.02), (x1, 0.62, SILL), M["ply"]))              # display platform
    for x in (dl - 0.05, dr + 0.05):
        p.append(bx((x - 0.05, 0.2, 0.0), (x + 0.05, RECESS, CEIL), M["wall_in"]))     # recess side walls
    # fluorescent tube fittings and a ceiling fan
    for y in (2.2, 4.4):
        p.append(bx((-0.65, y - 0.07, CEIL - 0.06), (0.65, y + 0.07, CEIL), M["white"]))
        p.append(cyl(0.016, 1.2, (0, y, CEIL - 0.08), M["tube"], segs=6, axis="X"))
    p.append(cyl(0.012, 0.35, (0.4, 3.3, CEIL - 0.18), M["steel"], segs=5))
    p.append(cyl(0.09, 0.1, (0.4, 3.3, CEIL - 0.38), M["white"], segs=8))
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        p.append(_beam((0.4, 3.3, CEIL - 0.36), (0.4 + 0.6 * math.cos(a), 3.3 + 0.6 * math.sin(a), CEIL - 0.36),
                       0.045, M["ply"], segs=3))
    # the back room door in the left wall behind the counter, ajar onto the dark
    xw = -w2 + WALL_T
    y0, y1 = 5.85, 6.65
    p.append(bx((xw, y0, 0.0), (xw + 0.005, y1, 2.05), M["dark"]))
    p.append(bx((xw, y0 - 0.05, 2.05), (xw + 0.03, y1 + 0.05, 2.12), M["sash"]))
    for y in (y0 - 0.025, y1 + 0.025):
        p.append(bx((xw, y - 0.025, 0.0), (xw + 0.03, y + 0.025, 2.12), M["sash"]))
    v = [(xw + 0.02, y1, 0.02), (xw + 0.55, y1 - 0.58, 0.02), (xw + 0.55, y1 - 0.58, 2.0), (xw + 0.02, y1, 2.0)]
    p.append(C.mesh_obj("backdoor", v, [(0, 1, 2, 3), (3, 2, 1, 0)], M["trim"]))
    return p


def _rods(M, rnd):
    """Rods standing in a floor rack down the left wall."""
    p = []
    x = -W / 2 + WALL_T + 0.16
    y0, y1 = 1.4, 4.3
    p.append(bx((x - 0.12, y0, 0.0), (x + 0.12, y1, 0.12), M["ply"]))
    p.append(bx((x - 0.12, y0, 1.25), (x + 0.12, y1, 1.31), M["ply"]))
    for y in (y0, y1):
        p.append(bx((x - 0.12, y - 0.02, 0.0), (x + 0.12, y + 0.02, 1.31), M["ply"]))
    blanks = [M["fish_dark"], M["red"], M["blue"], M["rubber"], M["yellow"], M["trim"]]
    n = 22
    for i in range(n):
        y = y0 + 0.08 + i * (y1 - y0 - 0.16) / (n - 1)
        xx = x + (0.05 if i % 2 else -0.05)
        h = rnd.uniform(1.9, 2.5)
        blank = rnd.choice(blanks)
        p.append(cyl(0.014, 0.4, (xx, y, 0.32), M["cork_grip"] if i % 3 else M["rubber"], segs=5))
        p.append(cyl(0.008, h - 0.52, (xx, y, 0.52 + (h - 0.52) / 2), blank, segs=4, r_top=0.002))
        if i % 4 == 1:  # a spinning reel on a few
            p.append(cyl(0.035, 0.05, (xx + 0.05, y, 0.6), M["steel"], segs=8, axis="X"))
    # a price tag strip on the top bar
    p.append(_quad_image(FP._sign("ts_rods", ["RODS FROM 49"], 64, 8, "#26302b", "#f4f0e2"), "RodsTag",
                         1.4, 0.07, (x + 0.122, (y0 + y1) / 2, 1.28), facing="+x"))
    return p, [((x - 0.14, y0, 0.0), (x + 0.14, y1, 2.0))]


def _pegboard(M, rnd):
    """Hooks, sinkers and lure packets on a pegboard down the right wall,
    eskies stacked under it."""
    p = []
    x = W / 2 - WALL_T
    y0, y1 = 1.1, 3.7
    p.append(bx((x - 0.02, y0, 0.95), (x, y1, 2.25), M["peg"]))
    cols = [M["red"], M["blue"], M["yellow"], M["white"], M["trim"], M["bait_lid"], M["steel"]]
    for r in range(4):
        z = 1.1 + r * 0.29
        for c in range(12):
            y = y0 + 0.12 + c * (y1 - y0 - 0.24) / 11
            if rnd.random() < 0.15:
                continue
            p.append(bx((x - 0.08, y - 0.003, z + 0.17), (x - 0.02, y + 0.003, z + 0.175), M["steel"]))   # peg
            for k in range(rnd.randint(1, 3)):
                kz = z - k * 0.012
                p.append(bx((x - 0.075 + k * 0.012, y - 0.045, kz), (x - 0.065 + k * 0.012, y + 0.045, kz + 0.17),
                            rnd.choice(cols)))
    p.append(_quad_image(FP._sign("ts_peg", ["HOOKS · SINKERS · LURES"], 96, 8, "#f4f0e2", "#2f5a46"), "PegTag",
                         2.4, 0.16, (x - 0.025, (y0 + y1) / 2, 2.38), facing="-x"))
    # eskies on the floor under it, biggest at the bottom
    y = y0 + 0.1
    for w, d, h, col in ((0.75, 0.45, 0.45, "blue"), (0.6, 0.4, 0.4, "red"), (0.48, 0.32, 0.3, "blue")):
        cx = x - d / 2 - 0.03
        p.append(bx((cx - d / 2, y, 0.0), (cx + d / 2, y + w, h), M[col]))
        p.append(bx((cx - d / 2 - 0.01, y - 0.01, h), (cx + d / 2 + 0.01, y + w + 0.01, h + 0.05), M["white"]))
        p.append(bx((cx - 0.012, y + 0.05, h + 0.05), (cx + 0.012, y + w - 0.05, h + 0.07), M["white"]))
        y += w + 0.08
    # one on top of the first
    p.append(bx((x - 0.4, y0 + 0.15, 0.5), (x - 0.06, y0 + 0.65, 0.78), M["red"]))
    p.append(bx((x - 0.41, y0 + 0.14, 0.78), (x - 0.05, y0 + 0.66, 0.82), M["white"]))
    return p, [((x - 0.5, y0, 0.0), (x, y1, 0.9))]


def _bait_fridge(M):
    """A glass-door upright fridge of bait tubs, lit inside."""
    p = []
    x1 = W / 2 - WALL_T
    x0 = x1 - 0.72
    y0, y1 = 3.85, 4.55
    h = 2.0
    t = 0.05
    p.append(bx((x1 - t, y0, 0.0), (x1, y1, h), M["white"]))                       # back, on the wall
    p.append(bx((x0, y0, 0.0), (x1, y0 + t, h), M["white"]))
    p.append(bx((x0, y1 - t, 0.0), (x1, y1, h), M["white"]))
    p.append(bx((x0, y0, 0.0), (x1, y1, 0.12), M["white"]))
    p.append(bx((x0, y0, h - 0.25), (x1, y1, h), M["white"]))
    p.append(bx((x1 - t - 0.002, y0 + t, 0.12), (x1 - t, y1 - t, h - 0.25), M["fridge_lit"]))
    p.append(bx((x0 - 0.02, y0 + 0.02, 0.1), (x0 - 0.01, y1 - 0.02, h - 0.22), M["glass"]))
    p.append(bx((x0 - 0.04, y1 - 0.08, 0.7), (x0 - 0.02, y1 - 0.05, 1.3), M["steel"]))     # handle
    p.append(_quad_image(FP._sign("ts_bait", ["LIVE BAIT"], 40, 8, "#f4f0e2", "#b4302a"), "BaitTag",
                         0.62, 0.13, (x0 - 0.004, (y0 + y1) / 2, h - 0.12), facing="-x"))
    # tubs on four shelves behind the glass
    for s in range(4):
        z = 0.22 + s * 0.42
        p.append(bx((x0 + 0.01, y0 + 0.05, z - 0.02), (x1 - 0.05, y1 - 0.05, z), M["steel"]))
        for k in range(4):
            y = y0 + 0.13 + k * 0.15
            p.append(cyl(0.05, 0.08, (x0 + 0.12, y, z + 0.04), M["bait"], segs=6))
            p.append(cyl(0.053, 0.015, (x0 + 0.12, y, z + 0.085), M["bait_lid"] if (s + k) % 3 else M["blue"],
                         segs=6))
    return p, [((x0 - 0.05, y0, 0.0), (x1, y1, h))]


def _gondola(M, rnd):
    """A double-sided low shelf unit of reels, line spools and sinker tubs."""
    p = []
    cx, cy = 0.35, 2.7
    w, d, h = 1.5, 0.6, 1.35
    p.append(bx((cx - w / 2, cy - 0.02, 0.0), (cx + w / 2, cy + 0.02, h), M["peg"]))
    for sx in (-1, 1):
        p.append(bx((cx + sx * w / 2 - 0.02, cy - d / 2, 0.0), (cx + sx * w / 2 + 0.02, cy + d / 2, h), M["white"]))
    p.append(bx((cx - w / 2, cy - d / 2, 0.0), (cx + w / 2, cy + d / 2, 0.12), M["white"]))
    for side in (-1, 1):
        for s, z in enumerate((0.12, 0.5, 0.88)):
            y0, y1 = sorted((cy + side * 0.02, cy + side * d / 2))
            p.append(bx((cx - w / 2, y0, z), (cx + w / 2, y1, z + 0.025), M["white"]))
            for k in range(6):
                x = cx - w / 2 + 0.13 + k * 0.245
                yc = (y0 + y1) / 2
                if s == 0:          # boxed reels
                    p.append(bx((x - 0.08, yc - 0.08, z + 0.025), (x + 0.08, yc + 0.08, z + 0.2),
                                rnd.choice([M["red"], M["blue"], M["rubber"]])))
                elif s == 1:        # spools of line
                    p.append(cyl(0.05, 0.07, (x, yc, z + 0.066), rnd.choice([M["yellow"], M["trim"], M["white"]]),
                                 segs=8, axis="X"))
                    for fx in (-0.038, 0.038):     # the spool's flanges
                        p.append(cyl(0.065, 0.006, (x + fx, yc, z + 0.066), M["ply"], segs=8, axis="X"))
                else:               # sinker tubs
                    p.append(cyl(0.05, 0.1, (x, yc, z + 0.075), M["glass"], segs=6))
                    p.append(cyl(0.035, 0.05, (x, yc, z + 0.05), M["steel"], segs=6))
    # a price card on top
    p.append(_quad_image(FP._sign("ts_reels", ["REELS · LINE"], 48, 8, "#26302b", "#f4f0e2"), "ReelsTag",
                         0.9, 0.15, (cx, cy - 0.025, h + 0.1)))
    p.append(bx((cx - 0.01, cy - 0.01, h), (cx + 0.01, cy + 0.01, h + 0.03), M["steel"]))
    return p, [((cx - w / 2, cy - d / 2, 0.0), (cx + w / 2, cy + d / 2, h))]


def _crab_nets(M):
    """Drop nets hung from the ceiling: a hoop with a shallow net cone."""
    p = []
    for i, (x, y) in enumerate(((-1.2, 2.1), (-0.8, 3.3), (1.4, 1.6))):
        z = CEIL - 0.85 - 0.1 * i
        r, segs = 0.3, 10
        for k in range(segs):
            a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
            p.append(_beam((x + r * math.cos(a0), y + r * math.sin(a0), z),
                           (x + r * math.cos(a1), y + r * math.sin(a1), z), 0.008, M["steel"], segs=3))
        v = [(x, y, z - 0.18)] + [(x + r * math.cos(2 * math.pi * k / segs), y + r * math.sin(2 * math.pi * k / segs), z)
                                  for k in range(segs)]
        f = [(0, 1 + (k + 1) % segs, 1 + k) for k in range(segs)] + [(0, 1 + k, 1 + (k + 1) % segs)
                                                                       for k in range(segs)]
        p.append(C.mesh_obj("net", v, f, M["net"]))
        for k in range(3):
            a = 2 * math.pi * k / 3
            p.append(_beam((x + r * math.cos(a), y + r * math.sin(a), z), (x, y, CEIL), 0.003, M["rubber"], segs=3))
        p.append(cyl(0.03, 0.06, (x, y, z - 0.2), M["bait_lid"], segs=6))       # the float
    return p


def _counter(M, rnd):
    """The counter across the back: a glass-front lure case, the till, a
    measuring board and the weigh-in scale."""
    p = []
    x0, x1 = COUNTER_X
    y0, y1 = COUNTER_Y
    h = COUNTER_H
    p.append(bx((x0, y0 + 0.08, 0.0), (x1, y1, 0.1), M["rubber"]))                       # kick
    p.append(bx((x0, y0 + 0.05, 0.1), (x1, y1, 0.55), M["ply"]))
    p.append(bx((x0, y0 + 0.02, 0.55), (x0 + 0.04, y1, h - 0.04), M["ply"]))
    p.append(bx((x1 - 0.04, y0 + 0.02, 0.55), (x1, y1, h - 0.04), M["ply"]))
    p.append(bx((x0, y0 + 0.36, 0.55), (x1, y1, h - 0.04), M["ply"]))
    p.append(bx((x0 + 0.04, y0 + 0.02, 0.56), (x1 - 0.04, y0 + 0.03, h - 0.05), M["glass"]))
    p.append(bx((x0 - 0.02, y0, h - 0.04), (x1 + 0.02, y1 + 0.02, h), M["ply"]))
    p.append(bx((x0 + 0.04, y0 + 0.03, 0.55), (x1 - 0.04, y0 + 0.36, 0.57), M["white"]))
    # lures in the case: little bright fish shapes on the shelf
    for i in range(18):
        x = x0 + 0.15 + i * (x1 - x0 - 0.3) / 17
        y = y0 + rnd.uniform(0.1, 0.28)
        col = rnd.choice([M["red"], M["yellow"], M["blue"], M["steel"], M["bait_lid"], M["white"]])
        p.append(bx((x - 0.04, y - 0.008, 0.57), (x + 0.04, y + 0.008, 0.6), col))
        p.append(bx((x + 0.04, y - 0.006, 0.575), (x + 0.055, y + 0.006, 0.585), M["steel"]))
    # the till, left end
    tx = x0 + 0.45
    p.append(bx((tx - 0.22, y0 + 0.15, h), (tx + 0.22, y0 + 0.5, h + 0.12), M["rubber"]))
    v = [(tx - 0.2, y0 + 0.17, h + 0.12), (tx + 0.2, y0 + 0.17, h + 0.12), (tx + 0.2, y0 + 0.42, h + 0.26),
         (tx - 0.2, y0 + 0.42, h + 0.26)]
    p.append(C.mesh_obj("keys", v, [(0, 1, 2, 3)], M["white"]))
    p.append(bx((tx - 0.2, y0 + 0.42, h + 0.12), (tx + 0.2, y0 + 0.5, h + 0.3), M["rubber"]))
    p.append(bx((tx - 0.12, y0 + 0.42, h + 0.3), (tx + 0.12, y0 + 0.47, h + 0.38), M["fish_dark"]))
    # the measuring board: white, a black rule, a stop at the left end
    mx = -0.25
    p.append(bx((mx - 0.6, y0 + 0.12, h), (mx + 0.6, y0 + 0.32, h + 0.02), M["white"]))
    p.append(bx((mx - 0.6, y0 + 0.3, h + 0.02), (mx - 0.58, y0 + 0.32, h + 0.08), M["white"]))
    p.append(bx((mx - 0.62, y0 + 0.12, h + 0.02), (mx - 0.6, y0 + 0.32, h + 0.08), M["white"]))
    for k in range(25):
        x = mx - 0.58 + k * 0.05
        p.append(bx((x - 0.002, y0 + 0.13, h + 0.02), (x + 0.002, y0 + (0.2 if k % 2 else 0.24), h + 0.022),
                    M["rubber"]))
    # the weigh-in scale: a galvanised gantry with a spring balance hanging
    # a stainless tray on three chains
    sx, sy = 0.9, y0 + 0.28
    for gx in (sx - 0.3, sx + 0.3):
        p.append(cyl(0.018, 0.75, (gx, sy, h + 0.375), M["galv"], segs=6))
    p.append(cyl(0.02, 0.64, (sx, sy, h + 0.75), M["galv"], segs=6, axis="X"))
    p.append(cyl(0.008, 0.04, (sx, sy, h + 0.72), M["steel"], segs=4))
    p.append(cyl(0.035, 0.22, (sx, sy, h + 0.59), M["brass"] if "brass" in M else M["yellow"], segs=8))
    p.append(cyl(0.03, 0.004, (sx, sy - 0.036, h + 0.62), M["white"], segs=10, axis="Y"))
    p.append(bx((sx - 0.002, sy - 0.04, h + 0.62), (sx + 0.002, sy - 0.038, h + 0.645), M["red"]))
    p.append(cyl(0.004, 0.06, (sx, sy, h + 0.45), M["steel"], segs=4))
    tz = h + 0.22
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.5
        p.append(_beam((sx, sy, h + 0.42), (sx + 0.17 * math.cos(a), sy + 0.12 * math.sin(a), tz + 0.03), 0.003,
                       M["steel"], segs=3))
    p.append(bx((sx - 0.2, sy - 0.13, tz), (sx + 0.2, sy + 0.13, tz + 0.012), M["steel"]))
    for sgn in (-1, 1):
        p.append(bx((sx - 0.2, sy + sgn * 0.13 - 0.006, tz), (sx + 0.2, sy + sgn * 0.13 + 0.006, tz + 0.04),
                    M["steel"]))
    return p, [((x0, y0, 0.0), (x1, y1, h))], (sx, sy, tz + 0.02)


def _behind(M, rnd):
    """The back wall behind the counter: brag board, chalkboard, mount,
    shelves of stock and the bait chest freezer."""
    p = []
    yw = D - WALL_T
    # brag board: cork with customers' photos of their catches
    bx0, bx1, bz0, bz1 = 0.2, 2.3, 1.3, 2.35
    p.append(bx((bx0, yw - 0.03, bz0), (bx1, yw, bz1), M["sash"]))
    p.append(bx((bx0 + 0.04, yw - 0.035, bz0 + 0.04), (bx1 - 0.04, yw - 0.03, bz1 - 0.04), M["cork"]))
    p.append(_quad_image(FP._sign("ts_brag", ["CATCH OF THE MONTH"], 80, 8, "#2f5a46", "#f4f0e2"), "BragTag",
                         1.6, 0.13, ((bx0 + bx1) / 2, yw - 0.04, bz1 + 0.1)))
    photos = []
    for i in range(16):
        r, c = divmod(i, 6)
        x = bx0 + 0.2 + c * 0.32 + rnd.uniform(-0.04, 0.04)
        z = bz0 + 0.18 + r * 0.32 + rnd.uniform(-0.03, 0.03)
        if z > bz1 - 0.15:
            continue
        photos.append((x, z))
    for x, z in photos:
        tilt = rnd.uniform(-0.12, 0.12)
        def q(u, v):
            return (x + u * math.cos(tilt) - v * math.sin(tilt), z + u * math.sin(tilt) + v * math.cos(tilt))
        pts = [q(-0.11, -0.08), q(0.11, -0.08), q(0.11, 0.08), q(-0.11, 0.08)]
        p.append(C.mesh_obj("photo", [(a, yw - 0.04, b) for a, b in pts], [(3, 2, 1, 0)], M["photo"]))
        sky = rnd.choice([M["blue"], M["trim"], M["fish_dark"]])
        pts = [q(-0.095, -0.05), q(0.095, -0.05), q(0.095, 0.07), q(-0.095, 0.07)]
        p.append(C.mesh_obj("print", [(a, yw - 0.042, b) for a, b in pts], [(3, 2, 1, 0)], sky))
        # someone holding up a fish: a silver sliver across the print
        pts = [q(-0.045, 0.0), q(0.0, -0.022), q(0.055, 0.0), q(0.0, 0.022), q(-0.075, 0.02), q(-0.075, -0.02)]
        p.append(C.mesh_obj("catch", [(a, yw - 0.044, b) for a, b in pts], [(3, 2, 1, 0), (0, 4, 5)], M["steel"]))
        p.append(cyl(0.008, 0.01, (x, yw - 0.046, z + 0.07), M["red"], segs=4, axis="Y"))
    # the chalkboard of the month's biggest
    chalk = FP._sign("ts_chalk", ["BIGGEST THIS MONTH", "", "DHUFISH  9·2KG", "TAILOR   2·1KG",
                                  "BREAM    1·4KG", "WHITING  0·6KG", "HERRING  0·4KG"], 80, 48, "#e8e6dc", "#26302b")
    p.append(bx((-1.95, yw - 0.03, 1.25), (-0.2, yw, 2.35), M["ply"]))
    p.append(_quad_image(chalk, "Chalk", 1.65, 1.0, (-1.075, yw - 0.035, 1.8)))
    # the mounted dhufish on a jarrah board above
    p.append(bx((-0.75, yw - 0.03, 2.55), (0.75, yw, 2.95), M["jarrah"]))
    p += fish_shape(1.05, 0.38, M["fish"], M["fish_dark"], loc=(0.0, yw - 0.08, 2.75), facing=1, thick=0.3)
    p.append(cyl(0.022, 0.01, (0.37, yw - 0.117, 2.79), M["rubber"], segs=8, axis="Y"))
    p.append(_quad_image(FP._sign("ts_mount", ["DHUFISH 14KG · ROTTNEST 1979"], 112, 8, "#f4f0e2", "#3f2a20"),
                         "MountTag", 0.9, 0.05, (0.0, yw - 0.005, 2.49)))
    # the bait chest freezer under the brag board
    fx0, fx1 = 1.45, 2.55 - 0.05
    p.append(bx((fx0, yw - 0.68, 0.0), (fx1, yw - 0.02, 0.86), M["white"]))
    p.append(bx((fx0 - 0.01, yw - 0.69, 0.86), (fx1 + 0.01, yw - 0.01, 0.92), M["white"]))
    p.append(_quad_image(FP._sign("ts_frozen", ["FROZEN BAIT"], 48, 8, "#2f62a8", "#ecebe6"), "FrozenTag",
                         0.8, 0.13, ((fx0 + fx1) / 2, yw - 0.684, 0.62)))
    # a box of pilchards on the freezer lid, a radio, a mug
    p.append(bx((fx0 + 0.1, yw - 0.5, 0.92), (fx0 + 0.42, yw - 0.28, 0.99), M["blue"]))
    p.append(bx((fx1 - 0.35, yw - 0.25, 0.92), (fx1 - 0.08, yw - 0.12, 1.08), M["fish_dark"]))
    p.append(cyl(0.04, 0.09, (fx1 - 0.5, yw - 0.45, 0.965), M["white"], segs=8))
    # a calendar from the marine supplier
    p.append(_quad_image(FP._sign("ts_cal", ["MARINE SUPPLY", "", "MARCH"], 56, 28, "#26302b", "#f4f0e2"), "Calendar",
                         0.4, 0.5, (W / 2 - WALL_T - 0.004, yw - 0.6, 1.7), facing="-x"))
    return p, [((fx0, yw - 0.7, 0.0), (fx1, yw, 0.92))]


# ------------------------------------------------------------------ build

def shop():
    rnd = random.Random(500)
    M = _mats()
    M["brass"] = _m("Brass", "#b8913f", 0.35, 0.8)
    parts = []
    parts += _facade(M)
    parts += _door(M)
    parts += _verandah(M)
    parts += _ice_freezer(M, (1.5, -0.45))
    parts += _sandwich_board(M, (-1.7, -1.6))
    parts += _room(M)
    col = []
    for fn in (_rods, _pegboard, _gondola):
        p, c = fn(M, rnd)
        parts += p
        col += c
    p, c = _bait_fridge(M)
    parts += p
    col += c
    parts += _crab_nets(M)
    p, c, scale = _counter(M, rnd)
    parts += p
    col += c
    p, c = _behind(M, rnd)
    parts += p
    col += c
    # collision: side and back walls, the shopfront either side of the door
    # opening, the floor, the ice freezer
    w2 = W / 2
    dl, dr = DOOR_X - DOOR_W / 2, DOOR_X + DOOR_W / 2
    col += [((-w2, 0.0, 0.0), (-w2 + WALL_T, D, CEIL)), ((w2 - WALL_T, 0.0, 0.0), (w2, D, CEIL)),
            ((-w2, D - WALL_T, 0.0), (w2, D, CEIL)),
            ((-w2, 0.0, 0.0), (dl - 0.05, 0.32, CEIL)), ((dr + 0.05, 0.0, 0.0), (w2, 0.32, CEIL)),
            ((dl - 0.15, 0.0, 0.0), (dl - 0.05, RECESS, CEIL)), ((dr + 0.05, 0.0, 0.0), (dr + 0.15, RECESS, CEIL)),
            ((-w2, 0.0, -0.1), (w2, D, 0.0)), ((-w2, 0.0, CEIL), (w2, D, CEIL + 0.1)),
            ((1.5 - 0.63, -0.45 - 0.35, 0.0), (1.5 + 0.63, -0.45 + 0.35, 0.9))]
    sockets = {
        "Door": (DOOR_X, -0.4, 0.0),
        "Inside": (DOOR_X + 0.2, RECESS + 1.0, 0.0),
        "Counter": (0.3, COUNTER_Y[0] - 0.45, 0.0),
        "Scale": scale,
        "BragBoard": (1.25, D - WALL_T - 0.05, 1.8),
        "BaitFridge": (W / 2 - WALL_T - 1.1, 4.2, 0.0),
        "IceBox": (1.5, -0.45 - 0.75, 0.0),
    }
    return parts, sockets, col
