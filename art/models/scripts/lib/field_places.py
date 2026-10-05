"""Places for the field journal: a timber jetty kit and a rock groyne kit
for the map to lay along the river and the coast, and the two Lake Street
shopfronts (the photo lab and the tackle shop).

Every function returns (parts, sockets) like lib/field.py: front toward -Y,
metres, sockets a dict of empty name -> location.

Jetty pieces: origin at the middle of the deck top at the landward end, the
piece running out along -Y (`JETTY_LEN` long), so pieces chain by moving
the next one -JETTY_LEN along. The water surface is `WATER_Z` below the deck.
Groyne pieces: origin on the crest's centre line at the landward end at
water level, running out along -Y (`GROYNE_LEN` long).
Shopfronts: origin at the base centre of the shop window line (the
building line), the footpath and verandah out toward -Y.
"""
import math
import random

from . import common as C
from . import furniture as F
from . import mystery as MY

bx, cyl = F.bx, F.cyl

JETTY_LEN = 3.0
JETTY_W = 2.6
WATER_Z = -1.3
GROYNE_LEN = 6.0


def _m(name, col, rough=0.8, metal=0.0, image=None):
    return C.mat("FP_" + name, col, rough=rough, metal=metal, image=image)


def _mats():
    return {
        "jarrah": _m("Jarrah", "#6e3f2a", 0.9),             # weathered jarrah deck
        "jarrah_dark": _m("JarrahWet", "#3f2a20", 0.9),     # pylons, darker where wet
        "weed": _m("Weed", "#3f4b2c", 1.0),
        "galv": _m("Galv", "#a4a8a6", 0.45, 0.7),
        "limestone": _m("Limestone", "#d8cba6", 1.0),
        "granite": _m("Granite", "#8a8580", 0.95),
        "granite_dk": _m("GraniteDark", "#6c6862", 0.95),
        "path": _m("PathLime", "#e2d7b8", 1.0),
        "render": _m("Render", "#d9cdb2", 0.9),
        "brick": _m("Brick", "#9a5a3c", 0.95),
        "frame": _m("ShopFrame", "#2a2c2b", 0.5),
        "glass": _m("ShopGlass", "#5f7a85", 0.08, 0.4),
        "verandah": _m("Verandah", "#ced2cf", 0.5, 0.4),
        "post": _m("Post", "#2c4b3e", 0.6),                 # heritage green posts
        "floor": _m("ShopFloor", "#8c8577", 0.9),
        "counter": _m("Counter", "#7a5236", 0.7),
        "shelf": _m("Shelf", "#e6e1d6", 0.8),
        "awning": _m("Awning", "#b0302a", 0.9),
        "lamp": C.mat("FP_JettyLamp", "#fff2c8", rough=0.4, emit="#ffe9b0", emit_strength=0.0),
    }


# ------------------------------------------------------------------ jetty

def _pylon(x, y, top, M, r=0.15):
    """A round jarrah pylon from the river bed up to under the deck, dark
    and weedy below the tide line."""
    bed = WATER_Z - 2.0
    return [cyl(r, top - (WATER_Z + 0.3), (x, y, (top + WATER_Z + 0.3) / 2), M["jarrah_dark"], segs=8),
            cyl(r * 1.04, (WATER_Z + 0.3) - bed, (x, y, (WATER_Z + 0.3 + bed) / 2), M["weed"], segs=8)]


def jetty(end=False, seed=0):
    """One 3 m bay of a timber jetty: a headstock on two pylons at the
    landward end, stringers, cross planks with gaps, a low kerb each side and
    a galvanised handrail on posts. `end`: the last bay, with pylons at the
    seaward end too, a ladder down to the water and a lamp post."""
    M = _mats()
    rnd = random.Random(seed)
    L, W = JETTY_LEN, JETTY_W
    p = []
    deck = 0.0
    t = 0.06
    # planks run across, 0.19 wide with 12 mm gaps, a little uneven
    n = int(L / 0.2)
    for i in range(n):
        y0 = -i * L / n - 0.006
        y1 = -(i + 1) * L / n + 0.006
        dz = rnd.uniform(-0.006, 0.004)
        p.append(bx((-W / 2, y1, deck - t + dz), (W / 2, y0, deck + dz), M["jarrah"]))
    # stringers under the planks, headstocks across the pylons
    for x in (-W / 2 + 0.15, -0.45, 0.45, W / 2 - 0.15):
        p.append(bx((x - 0.08, -L, deck - t - 0.25), (x + 0.08, 0.0, deck - t), M["jarrah_dark"]))
    ends = (0.0, -L) if end else (0.0,)
    for y in ends:
        yy = y - 0.15 if y == 0.0 else y + 0.15
        p.append(bx((-W / 2 - 0.25, yy - 0.15, deck - t - 0.55), (W / 2 + 0.25, yy + 0.15, deck - t - 0.25),
                    M["jarrah_dark"]))
        for x in (-W / 2 - 0.05, W / 2 + 0.05):
            p += _pylon(x, yy, deck - t - 0.55, M)
    # kerbs and handrail
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.08)
        p.append(bx((x - 0.08, -L, deck), (x + 0.08, 0.0, deck + 0.15), M["jarrah"]))
        for y in (-0.1, -L / 2, -L + 0.1):
            p.append(bx((x - 0.03, y - 0.03, deck + 0.15), (x + 0.03, y + 0.03, deck + 1.0), M["galv"]))
        for z in (deck + 0.55, deck + 1.0):
            p.append(cyl(0.022, L, (x, -L / 2, z), M["galv"], segs=6, axis="Y"))
    sockets = {}
    if end:
        # ladder down the seaward end, a lamp post on the corner
        for x in (-0.25, 0.25):
            p.append(bx((x - 0.03, -L - 0.08, WATER_Z - 0.6), (x + 0.03, -L - 0.02, deck + 0.9), M["galv"]))
        for k in range(8):
            z = WATER_Z - 0.4 + k * 0.3
            p.append(cyl(0.016, 0.5, (0, -L - 0.05, z), M["galv"], segs=6, axis="X"))
        lx = W / 2 - 0.08
        p.append(cyl(0.05, 3.2, (lx, -L + 0.25, deck + 1.6), M["galv"], segs=8))
        p.append(bx((lx - 0.35, -L + 0.19, deck + 3.15), (lx + 0.02, -L + 0.31, deck + 3.22), M["galv"]))
        p.append(bx((lx - 0.42, -L + 0.16, deck + 3.02), (lx - 0.24, -L + 0.34, deck + 3.15), M["lamp"]))
        sockets["Ladder"] = (0, -L - 0.3, WATER_Z)
        sockets["Lamp"] = (lx - 0.33, -L + 0.25, deck + 3.0)
    # where an angler stands and drops a line, on both sides
    for sx, nm in ((-1, "Cast_L"), (1, "Cast_R")):
        sockets[nm] = (sx * (W / 2 - 0.4), -L / 2, deck)
    sockets["Water"] = (0, -L / 2, WATER_Z)
    return p, sockets


def jetty_bench():
    """A jarrah bench to bolt to the deck (origin on the deck at its middle)."""
    M = _mats()
    p = [bx((-0.2, -0.9, 0.42), (0.2, 0.9, 0.47), M["jarrah"])]       # runs along the jetty
    for y in (-0.75, 0.75):
        p.append(bx((-0.18, y - 0.04, 0.0), (0.18, y + 0.04, 0.42), M["galv"]))
    return p, {}


# ------------------------------------------------------------------ groyne

def _rock(rnd, loc, size, mat):
    """A faceted boulder: a low sphere with its points pushed about."""
    sx, sy, sz = size
    o = C.sphere("rock", 1.0, loc, mat, segs=6, rings=4, scale=(sx, sy, sz))
    for v in o.data.vertices:
        v.co *= rnd.uniform(0.78, 1.12)
    o.rotation_euler.z = rnd.uniform(0, math.pi)
    return o


def groyne(end=False, seed=0):
    """6 m of a granite rock groyne: armour stone piled on both slopes from
    below the water up to a flat crushed-limestone path along the crest.
    `end`: the rounded head, the rocks wrapping round the seaward end."""
    M = _mats()
    rnd = random.Random(seed or 7)
    L = GROYNE_LEN
    crest, path_w = 1.4, 2.0
    p = []
    # core: a trapezoid mound the rocks sit on (hidden under them)
    half_top, half_base = path_w / 2 + 0.6, path_w / 2 + 0.6 + (crest + 1.5) * 1.4
    y_end = -L if not end else -L + 1.0
    core = C.mesh_obj("core", [(-half_base, 0, -1.5), (half_base, 0, -1.5), (half_top, 0, crest),
                               (-half_top, 0, crest), (-half_base, y_end, -1.5), (half_base, y_end, -1.5),
                               (half_top, y_end, crest), (-half_top, y_end, crest)],
                      [(0, 3, 2, 1), (4, 5, 6, 7), (0, 4, 7, 3), (1, 2, 6, 5), (3, 7, 6, 2)], M["granite_dk"])
    p.append(core)
    # path on top
    p.append(bx((-path_w / 2, y_end, crest), (path_w / 2, 0.0, crest + 0.08), M["path"]))
    # armour stones on the slopes, rows from the crest down into the water
    for sx in (-1, 1):
        for row in range(5):
            off = half_top + row * 0.8
            z = crest - row * 0.62
            k = 0
            y = -0.3
            while y > y_end - 0.1:
                s = rnd.uniform(0.55, 0.85)
                mat = M["granite"] if rnd.random() < 0.7 else M["granite_dk"]
                p.append(_rock(rnd, (sx * (off + rnd.uniform(-0.15, 0.15)), y, z + rnd.uniform(-0.1, 0.1)),
                               (s * 1.1, s, s * 0.8), mat))
                y -= s * 1.3
                k += 1
    if end:
        # the head: rocks round the seaward end, the path ending in a ring
        for i in range(9):
            a = math.pi * (i + 0.5) / 9
            for row in range(3):
                r = 1.4 + row * 1.0
                z = crest - row * 0.9
                s = rnd.uniform(0.6, 0.9)
                p.append(_rock(rnd, (math.cos(a) * r, y_end - math.sin(a) * r, z), (s * 1.1, s, s * 0.8),
                                M["granite"] if rnd.random() < 0.7 else M["granite_dk"]))
        ring = [(math.cos(2 * math.pi * i / 12) * (path_w / 2 + 0.4), y_end + math.sin(2 * math.pi * i / 12) *
                 (path_w / 2 + 0.4), crest + 0.07) for i in range(12)]
        ring.append((0, y_end, crest + 0.07))   # just under the path so the two never fight
        p.append(C.mesh_obj("path_end", ring, [(12, i, (i + 1) % 12) for i in range(12)], M["path"]))
        p.append(cyl(0.06, 1.2, (0, y_end - 0.6, crest + 0.6), M["galv"], segs=6))   # navigation post
    sockets = {"Cast_L": (-path_w / 2 + 0.2, -L / 2, crest + 0.08),
               "Cast_R": (path_w / 2 - 0.2, -L / 2, crest + 0.08),
               "Water": (0, -L / 2, 0.0)}
    if end:
        sockets["Cast_End"] = (0, y_end - 0.4, crest + 0.08)
    return p, sockets


# ------------------------------------------------------------------ shopfronts

def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _sign(name, lines, w_px, h_px, ink, paper, scale=1):
    """A painted signboard image from the plate font."""
    f = MY._text(lines, w_px, h_px, scale=scale, top=max(1, (h_px - 6 * scale * len(lines)) // 2))
    ink, paper = _rgb(ink), _rgb(paper)
    return C.make_image(name, w_px, h_px, lambda x, y: ink if f(x, y) else paper)


def _sign_quad(img, name, w, h, loc, facing=-1):
    """A sign facing -Y (facing=-1) or +Y, centred on loc."""
    mat = C.mat("FP_" + name, "#ffffff", rough=0.8, image=img)
    x, y, z = loc
    v = [(x - w / 2, y, z - h / 2), (x + w / 2, y, z - h / 2), (x + w / 2, y, z + h / 2), (x - w / 2, y, z + h / 2)]
    if facing > 0:
        v = [v[1], v[0], v[3], v[2]]
    o = C.mesh_obj("sign", v, [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, vv) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, vv)
    return o


def shopfront(kind="photo_lab"):
    """A single-storey Northbridge shop on the building line: rendered
    parapet with the shop's name, a bullnose-ish verandah on green posts over
    the footpath, a timber-framed window either side of a recessed door, a
    hanging sign under the verandah and a shallow lit room behind the glass
    (counter and shelves) so the window isn't a black hole."""
    M = _mats()
    p = []
    W, H, D = 5.0, 5.3, 4.0          # width, parapet top, room depth
    door_w, door_h = 1.0, 2.3
    sill, head = 0.55, 2.6
    if kind == "photo_lab":
        name, sub, tag = ["LAKE ST PHOTO"], ["1 HR DEVELOPING", "FILM · PRINTS"], ["PHOTO"]
        wall, ink, paper = M["render"], "#1d3f6e", "#efe6cf"
    else:
        name, sub, tag = ["BAIT AND TACKLE"], ["LIVE BAIT · ICE", "RODS · REELS"], ["BAIT"]
        wall, ink, paper = M["brick"], "#f2ecd8", "#1f4a3a"
    # front wall around the openings, the side walls and roof of the room
    p.append(bx((-W / 2, 0.0, 0.0), (-W / 2 + 0.25, 0.25, H), wall))
    p.append(bx((W / 2 - 0.25, 0.0, 0.0), (W / 2, 0.25, H), wall))
    p.append(bx((-W / 2, 0.0, head), (W / 2, 0.25, H), wall))
    p.append(bx((-W / 2 + 0.25, 0.0, 0.0), (W / 2 - 0.25, 0.25, sill), M["brick"]))
    p.append(bx((-W / 2, -0.05, H - 0.12), (W / 2, 0.30, H), wall))              # parapet coping
    for sx in (-1, 1):
        p.append(bx((sx * W / 2 - (0.12 if sx > 0 else 0), 0.25, 0.0), (sx * W / 2 + (0.12 if sx < 0 else 0), D, H),
                    wall))
    p.append(bx((-W / 2, D - 0.12, 0.0), (W / 2, D, H), wall))
    p.append(bx((-W / 2, 0.25, 3.0), (W / 2, D, 3.12), M["shelf"]))               # ceiling
    p.append(bx((-W / 2, 0.0, -0.02), (W / 2, D, 0.0), M["floor"]))
    # recessed door between two windows
    dx = -0.3
    p.append(bx((dx - door_w / 2, 0.25, 0.0), (dx + door_w / 2, 0.85, 0.02), M["floor"]))
    for sx in (-1, 1):
        x = dx + sx * door_w / 2
        p.append(bx((x - 0.06, 0.0, sill), (x + 0.06, 0.9, head), M["frame"]))      # reveal / mullion
    p.append(bx((dx - door_w / 2, 0.80, 0.0), (dx + door_w / 2, 0.86, door_h), M["frame"]))
    p.append(bx((dx - door_w / 2 + 0.08, 0.79, 0.25), (dx + door_w / 2 - 0.08, 0.80, door_h - 0.1), M["glass"]))
    p.append(bx((dx - door_w / 2, 0.25, door_h), (dx + door_w / 2, 0.9, head), M["frame"]))
    for x0, x1 in ((-W / 2 + 0.25, dx - door_w / 2 - 0.06), (dx + door_w / 2 + 0.06, W / 2 - 0.25)):
        p.append(bx((x0, 0.06, sill - 0.06), (x1, 0.14, sill), M["frame"]))
        p.append(bx((x0, 0.06, head - 0.06), (x1, 0.14, head), M["frame"]))
        p.append(bx((x0, 0.095, sill), (x1, 0.105, head - 0.06), M["glass"]))
    # inside: a counter, shelves along the back, a ceiling light panel
    p.append(bx((-1.6, 2.4, 0.0), (1.4, 2.9, 1.05), M["counter"]))
    for z in (0.6, 1.2, 1.8):
        p.append(bx((-W / 2 + 0.2, D - 0.5, z), (W / 2 - 0.2, D - 0.12, z + 0.03), M["shelf"]))
    p.append(bx((-1.2, 1.4, 2.98), (1.2, 2.2, 3.0), F.emissive("FP_ShopLight", "#fff4dc", 1.2)))
    if kind == "photo_lab":
        # the processing machine behind the counter, prints pegged on a line
        p.append(bx((0.6, 3.1, 0.0), (1.9, 3.8, 1.3), M["shelf"]))
        p.append(bx((0.7, 3.09, 0.9), (1.1, 3.1, 1.1), M["frame"]))
        for i in range(6):
            p.append(bx((-1.8 + i * 0.3, 2.95, 2.0), (-1.62 + i * 0.3, 2.96, 2.22), M["shelf"]))
    else:
        # rods standing in a rack, a bait fridge with a glass door
        for i in range(8):
            p.append(cyl(0.008, 2.3, (-2.1 + i * 0.12, 3.6, 1.15), M["frame"], segs=4))
        p.append(bx((1.2, 3.2, 0.0), (2.2, 3.85, 1.9), M["shelf"]))
        p.append(bx((1.25, 3.19, 0.1), (2.15, 3.2, 1.8), M["glass"]))
    # verandah over the footpath on two posts, a fascia board
    vd = 2.6
    p.append(bx((-W / 2, -vd, 3.15), (W / 2, 0.0, 3.22), M["verandah"]))
    p.append(bx((-W / 2, -vd - 0.03, 3.0), (W / 2, -vd + 0.03, 3.3), M["post"]))
    for x in (-W / 2 + 0.2, W / 2 - 0.2):
        p.append(cyl(0.05, 3.15, (x, -vd + 0.15, 1.575), M["post"], segs=8))
    # signs: the parapet name, a band on the fascia, a hanging sign under the verandah
    p.append(_sign_quad(_sign("sign_" + kind, name, 64, 10, ink, paper), "Sign_" + kind, 4.2, 0.65,
                        (0, -0.01, H - 0.62)))
    p.append(_sign_quad(_sign("fascia_" + kind, [" · ".join(sub)], 128, 8, ink, paper), "Fascia_" + kind, 4.6, 0.28,
                        (0, -vd - 0.035, 3.15), facing=-1))
    hang = _sign("hang_" + kind, tag, 24, 10, ink, paper)
    for fy in (-1, 1):
        p.append(_sign_quad(hang, "Hang_" + kind, 0.9, 0.36, (W / 2 - 1.0, -1.3 + fy * 0.012, 2.85), facing=fy))
    for x in (W / 2 - 1.35, W / 2 - 0.65):
        p.append(bx((x - 0.01, -1.31, 3.03), (x + 0.01, -1.29, 3.15), M["galv"]))
    return p, {"Door": (dx, -0.4, 0.0), "Counter": (-0.1, 2.2, 0.0)}


def _tackle_shop():
    """The Mends Street tackle shop has its own module (a walk-in room)."""
    from . import tackle_shop as TS
    return TS.shop()


PLACES = {
    "jetty_bay": (lambda: jetty(False, 1)),
    "jetty_end": (lambda: jetty(True, 2)),
    "jetty_bench": jetty_bench,
    "groyne_section": (lambda: groyne(False, 3)),
    "groyne_head": (lambda: groyne(True, 4)),
    "shop_photo_lab": (lambda: shopfront("photo_lab")),
    "shop_tackle": (lambda: _tackle_shop()),
}
