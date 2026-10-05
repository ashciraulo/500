"""What's under the dust sheet in the player's shed: M.'s night-time
broadcasting table, found at the end of the mystery.

A folding card table with a green vinyl top. On it: a 1970s portable
cassette recorder with piano keys and a tape in it, a chrome desk
microphone, and the transmitter, home-built in a grey tin box with a cream
tuning dial, a meter, two knobs, a toggle and one valve standing up out of
the lid, its aerial wire running up into the roof. A stack of NIGHT DRIVE
tapes, M.'s field journal open at a bird sketch with a pencil, a tartan
thermos and an ashtray. Leaning on the wall behind: a board with the
street directory map, red pins and Polaroids, and a March 1979 calendar
pinned above it.

reveal() returns (parts, sockets). Origin at the centre of the table's
footprint on the floor; the wall is toward -Y and you stand at +Y (the
shed's Shed_Sheeted dust sheet covers exactly this table: 1.0 wide, 0.55
deep, 0.78 high). Sockets: DeckLight and TxLight (the two red lamps),
Valve (the glowing valve), Bulb (where the shed's bare bulb hangs).
"""
import math
import random

from . import common as C
from . import furniture as F
from . import mystery as MY

bx, cyl = F.bx, F.cyl

TW, TD, TH = 1.0, 0.55, 0.78
WALL_Y = -TD / 2 - 0.01


def _m(name, col, rough=0.7, metal=0.0, **kw):
    return C.mat("SR_" + name, col, rough=rough, metal=metal, **kw)


def _mats():
    return {
        "vinyl": _m("Vinyl", "#2f4a3a", 0.55),
        "leg": _m("TableLeg", "#2a2724", 0.5, 0.4),
        "silver": _m("Silver", "#b9bcbd", 0.35, 0.7),
        "black": _m("Black", "#18181a", 0.6),
        "chrome": _m("Chrome", "#d6d8da", 0.15, 0.9),
        "tin": _m("Tin", "#7c827d", 0.45, 0.5),
        "cream": _m("Cream", "#e8dfc4", 0.6),
        "bakelite": _m("Bakelite", "#3a2618", 0.4),
        "glass": _m("ValveGlass", "#cfd8d6", 0.05, alpha=0.35),
        "glow": _m("ValveGlow", "#ff8a3a", 0.5, emit="#ff7a2a", emit_strength=3.0),
        "red": _m("Lamp", "#ff2a1a", 0.4, emit="#ff2a1a", emit_strength=2.0),
        "wire": _m("Wire", "#1b1b1b", 0.6),
        "copper": _m("Copper", "#b8733a", 0.4, 0.8),
        "porcelain": _m("Porcelain", "#efece4", 0.3),
        "board": _m("Board", "#8c6a48", 0.9),
        "paper": _m("Paper", "#ece4cc", 0.95),
        "tartan": _m("Tartan", "#8e2a24", 0.7),
        "tartan2": _m("TartanBand", "#2d4a33", 0.7),
        "glass_tray": _m("Ashtray", "#9fb4ad", 0.15, alpha=0.7),
        "butt": _m("Butt", "#e2c99a", 0.9),
        "pencil": _m("Pencil", "#d9a21f", 0.6),
        "journal": _m("JournalCloth", "#3b4a30", 0.85),
        "pin": _m("Pin", "#c0141a", 0.5),
    }


def _img(name, w, h, px):
    return C.make_image("sr_" + name, w, h, px)


def _dial_img():
    """A cream tuning dial: a scale arc of ticks, a red needle near the top."""
    def px(x, y):
        dx, dy = x - 15.5, y - 4
        r = math.hypot(dx, dy)
        a = math.degrees(math.atan2(dy, dx))
        if 11 <= r <= 13 and 20 < a < 160 and int(a) % 14 < 4:
            return (0.15, 0.13, 0.1)
        if abs(dx - dy * 0.35) < 0.7 and 0 < dy < 12:
            return (0.75, 0.12, 0.08)
        return (0.91, 0.87, 0.74)
    return _img("dial", 32, 18, px)


def _journal_img():
    """Two pages: handwriting on the left, a pencil sketch of a bird on a
    branch on the right, 1979 in the corner."""
    w, h = 48, 32
    ink = MY._scribble(1979, 23, h, 8, x0=2, x1=21, gap=3)
    year = MY._text(["1979"], 24, 8)

    def px(x, y):
        paper = (0.92, 0.88, 0.76)
        if x in (23, 24):
            return (0.7, 0.65, 0.52)                       # the gutter
        if x < 23:
            return (0.25, 0.24, 0.3) if (x, y) in ink else paper
        u, v = x - 24, y
        if 4 <= u <= 20 and v == 8 + (u // 5):
            return (0.3, 0.28, 0.26)                       # the branch
        if ((u - 11) / 5.0) ** 2 + ((v - 16) / 3.4) ** 2 < 1 and not (
                ((u - 11) / 4.0) ** 2 + ((v - 16) / 2.4) ** 2 < 1):
            return (0.3, 0.28, 0.26)                       # the body outline
        if ((u - 15) / 2.2) ** 2 + ((v - 20) / 2.2) ** 2 < 1:
            return (0.3, 0.28, 0.26)                       # the head
        if 17 <= u <= 19 and v == 20:
            return (0.3, 0.28, 0.26)                       # the bill
        if 5 <= u <= 8 and v == 14 + (8 - u) // 2:
            return (0.3, 0.28, 0.26)                       # the tail
        if 12 <= u <= 13 and 9 + (u // 5) <= v <= 12:
            return (0.3, 0.28, 0.26)                       # legs
        if year(u - 2, y - 23):
            return (0.3, 0.28, 0.26)
        return paper
    return _img("journal", w, h, px)


def _calendar_img():
    """MARCH 1979 over a grid of days, the 14th coloured in red."""
    text = MY._text(["MARCH", "1979"], 28, 30, 1, 1)

    def px(x, y):
        if text(x, y):
            return (0.12, 0.12, 0.14)
        if 1 <= y <= 16 and 1 <= x <= 25:
            if (x - 1) % 4 == 0 or (16 - y) % 3 == 0:
                return (0.55, 0.5, 0.42)
            if (x - 1) // 4 == 2 and (16 - y) // 3 == 2:
                return (0.75, 0.1, 0.08)
        return (0.95, 0.93, 0.86)
    return _img("calendar", 28, 30, px)


def _quad_y(name, img, w, h, centre, tilt=0.0, facing=1):
    """A picture standing up, facing +Y (toward you), tilted back by tilt
    radians about its bottom edge."""
    cx, cy, cz = centre
    ct, st = math.cos(tilt), math.sin(tilt)
    def p(u, v):
        return (cx + u, cy - v * st, cz + v * ct)
    v = [p(w / 2, 0), p(-w / 2, 0), p(-w / 2, h), p(w / 2, h)]
    mat = C.mat("SR_" + name, "#ffffff", rough=0.85, image=img)
    o = C.mesh_obj("pic", v, [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (a, b) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (a, b)
    return o


def _beam(a, b, r, mat, segs=4):
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder("bar", r, d.length, segs=segs, material=mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (a + b) / 2
    return o


def _move(parts, dx, dy, dz, rot=0.0):
    """Turn parts about Z by rot (radians), then move them."""
    from mathutils import Matrix, Vector
    m = Matrix.Translation(Vector((dx, dy, dz))) @ Matrix.Rotation(rot, 4, "Z")
    for o in parts:
        C.apply_transform(o)
        o.data.transform(m)
    return parts


def _table(M):
    p = [bx((-TW / 2, -TD / 2, TH - 0.03), (TW / 2, TD / 2, TH), M["vinyl"]),
         bx((-TW / 2 - 0.005, -TD / 2 - 0.005, TH - 0.045), (TW / 2 + 0.005, TD / 2 + 0.005, TH - 0.03), M["leg"])]
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (TW / 2 - 0.04), sy * (TD / 2 - 0.04)
            p.append(bx((x - 0.012, y - 0.012, 0.0), (x + 0.012, y + 0.012, TH - 0.045), M["leg"]))
        # folding braces under the top
        p.append(_beam((sx * (TW / 2 - 0.04), -TD / 2 + 0.04, TH - 0.3), (sx * (TW / 2 - 0.2), 0.0, TH - 0.05),
                       0.005, M["leg"]))
    return p


def _deck(M):
    """A portable cassette recorder, keys toward you (+Y), its tape in."""
    w, d, h = 0.34, 0.2, 0.075
    p = [bx((-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), M["silver"]),
         bx((-w / 2 + 0.005, -d / 2 + 0.005, h), (w / 2 - 0.005, d / 2 - 0.005, h + 0.004), M["black"])]
    # speaker grille on the left, the cassette well and window on the right
    for k in range(7):
        y = -d / 2 + 0.03 + k * 0.02
        p.append(bx((-w / 2 + 0.02, y - 0.003, h + 0.004), (-w / 2 + 0.14, y + 0.003, h + 0.006), M["silver"]))
    p.append(bx((0.0, -0.06, h + 0.004), (0.14, 0.04, h + 0.006), M["silver"]))
    tape = MY.cassette("NIGHT\nDRIVE 12")
    _move(tape, 0.07, -0.01, h - 0.006, math.pi)
    p += tape
    p.append(bx((0.005, -0.055, h + 0.006), (0.135, 0.035, h + 0.008), M["glass"]))
    # six piano keys along the front, one held down (play)
    for k in range(6):
        x = -0.02 + k * 0.03
        down = 0.008 if k == 1 else 0.0
        p.append(bx((x, d / 2 - 0.045, h - 0.012 - down), (x + 0.026, d / 2 + 0.005, h + 0.014 - down),
                    M["silver"] if k != 5 else M["black"]))
    # carry handle folded back, a volume knob
    for sx in (-1, 1):
        p.append(bx((sx * (w / 2 - 0.01) - 0.006, -d / 2 - 0.01, h - 0.03), (sx * (w / 2 - 0.01) + 0.006, -d / 2 + 0.01,
                                                                          h + 0.01), M["black"]))
    p.append(bx((-w / 2 + 0.01, -d / 2 - 0.02, h - 0.004), (w / 2 - 0.01, -d / 2 - 0.008, h + 0.006), M["black"]))
    p.append(cyl(0.012, 0.012, (-w / 2 + 0.17, d / 2 - 0.03, h + 0.01), M["black"], segs=8))
    led = (w / 2 - 0.03, d / 2 - 0.02, h + 0.004)
    p.append(bx((led[0] - 0.006, led[1] - 0.004, led[2]), (led[0] + 0.006, led[1] + 0.004, led[2] + 0.004), M["red"]))
    return p, led


def _mic(M):
    p = [cyl(0.055, 0.015, (0, 0, 0.0075), M["black"], segs=10),
         cyl(0.007, 0.13, (0, 0, 0.08), M["chrome"], segs=6)]
    # the head: a chrome lozenge tilted toward the chair
    head = C.sphere("mic", 0.04, (0, 0, 0), M["chrome"], segs=10, rings=6)
    head.scale = (0.75, 0.55, 1.0)
    head.rotation_euler = (math.radians(-25), 0, 0)
    head.location = (0, 0.01, 0.18)
    p.append(head)
    p.append(cyl(0.032, 0.012, (0, 0.01, 0.18), M["black"], segs=10))           # the band round the head
    # the cable off the back
    p.append(_beam((0, -0.05, 0.004), (0, -0.2, 0.004), 0.004, M["wire"]))
    return p


def _transmitter(M):
    """The home-built transmitter: a tin box, panel toward you."""
    w, d, h = 0.26, 0.18, 0.16
    p = [bx((-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), M["tin"]),
         bx((-w / 2 - 0.004, d / 2, 0.0), (w / 2 + 0.004, d / 2 + 0.006, h + 0.004), M["black"])]
    # the panel: dial, meter, two knobs, a toggle
    dial = _quad_y("Dial", _dial_img(), 0.11, 0.062, (-0.055, d / 2 + 0.009, 0.08))
    p.append(dial)
    p.append(bx((-0.115, d / 2 + 0.006, 0.075), (0.005, d / 2 + 0.007, 0.147), M["cream"]))
    p.append(cyl(0.022, 0.02, (0.075, d / 2 + 0.016, 0.115), M["black"], segs=10, axis="Y"))
    p.append(bx((0.06, d / 2 + 0.026, 0.1), (0.09, d / 2 + 0.027, 0.13), M["cream"]))
    for x in (-0.07, 0.0):
        p.append(cyl(0.016, 0.018, (x, d / 2 + 0.015, 0.035), M["bakelite"], segs=8, axis="Y"))
    p.append(cyl(0.006, 0.01, (0.06, d / 2 + 0.011, 0.035), M["chrome"], segs=6, axis="Y"))
    p.append(_beam((0.06, d / 2 + 0.014, 0.035), (0.06, d / 2 + 0.03, 0.05), 0.003, M["chrome"]))
    # the valve standing out of the lid: glass envelope, glowing heart
    p.append(cyl(0.022, 0.02, (0.06, -0.03, h + 0.01), M["bakelite"], segs=8))
    p.append(cyl(0.018, 0.075, (0.06, -0.03, h + 0.0575), M["glass"], segs=8, r_top=0.016))
    p.append(cyl(0.008, 0.04, (0.06, -0.03, h + 0.05), M["glow"], segs=6))
    # a coil on the lid, terminals and the aerial lead
    p.append(cyl(0.02, 0.06, (-0.06, -0.03, h + 0.02), M["copper"], segs=8, axis="X"))
    p.append(cyl(0.008, 0.012, (-0.08, -d / 2 + 0.02, h + 0.006), M["porcelain"], segs=6))
    p.append(C.sphere("led", 0.007, (0.105, d / 2 + 0.01, 0.13), M["red"], segs=6, rings=4))
    return p, (0.105, d / 2 + 0.007, 0.13), (0.06, -0.03, h + 0.05), (-0.08, -d / 2 + 0.02, h + 0.012)


def _thermos(M):
    p = [cyl(0.04, 0.24, (0, 0, 0.12), M["tartan"], segs=10),
         cyl(0.041, 0.03, (0, 0, 0.06), M["tartan2"], segs=10),
         cyl(0.041, 0.03, (0, 0, 0.17), M["tartan2"], segs=10),
         cyl(0.043, 0.06, (0, 0, 0.27), M["chrome"], segs=10)]
    return p


def _ashtray(M):
    p = [cyl(0.05, 0.02, (0, 0, 0.01), M["glass_tray"], segs=10)]
    rnd = random.Random(79)
    for k in range(4):
        a = rnd.uniform(0, math.tau)
        p.append(_beam((0.01 * math.cos(a), 0.01 * math.sin(a), 0.022),
                       (0.05 * math.cos(a), 0.05 * math.sin(a), 0.028), 0.004, M["butt"]))
    return p


def _journal(M):
    """M.'s field journal lying open, a pencil across it."""
    w, d = 0.3, 0.2
    p = [bx((-w / 2 - 0.006, -d / 2 - 0.006, 0.0), (w / 2 + 0.006, d / 2 + 0.006, 0.006), M["journal"]),
         bx((-w / 2, -d / 2, 0.006), (w / 2, d / 2, 0.012), M["paper"])]
    page = MY._flat_quad("sr_journal", _journal_img(), w, d, z=0.0122)
    p.append(page)
    p.append(_beam((-0.05, -0.12, 0.016), (0.12, 0.02, 0.016), 0.0035, M["pencil"], segs=6))
    return p


def _board(M):
    """The pinboard leaning on the wall: the street map, pins, Polaroids."""
    p = []
    w, h = 0.82, 0.52
    tilt = math.radians(10)
    y0 = WALL_Y + h * math.sin(tilt) + 0.012
    ct, st = math.cos(tilt), math.sin(tilt)
    def at(u, v, out=0.0):
        return (u, y0 - v * st + out * ct, TH + v * ct + out * st)
    # the board itself, a slab tilted back against the wall
    v = []
    for oy in (-0.012, 0.0):
        for (u, vv) in ((-w / 2, 0), (w / 2, 0), (w / 2, h), (-w / 2, h)):
            v.append(at(u, vv, oy))
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    p.append(C.mesh_obj("board", v, f, M["board"]))
    p.append(_quad_y("Map", MY._img_map(), 0.6, 0.4, at(-0.06, 0.06, 0.002), tilt=tilt))
    rnd = random.Random(1979)
    for _ in range(12):
        u, vv = rnd.uniform(-0.33, 0.21), rnd.uniform(0.1, 0.44)
        p.append(C.sphere("pin", 0.007, at(u, vv, 0.012), M["pin"], segs=6, rings=4))
    # Polaroids down the right side
    for k, kind in enumerate(("carport", "lane", "river", "park")):
        u, vv = 0.33, 0.39 - k * 0.12
        p.append(_quad_y("Pol_" + kind, MY._img_photo(kind), 0.075, 0.075, at(u, vv - 0.035, 0.004), tilt=tilt))
        p.append(_quad_y("PolFrame", _img("polframe", 2, 2, lambda x, y: (0.93, 0.91, 0.84)), 0.088, 0.105,
                         at(u, vv - 0.05, 0.003), tilt=tilt))
        p.append(C.sphere("pin", 0.006, at(u, vv + 0.045, 0.01), M["pin"], segs=6, rings=4))
    # the calendar on the wall above it
    cal = _quad_y("Calendar", _calendar_img(), 0.28, 0.3, (-0.25, WALL_Y + 0.004, TH + 0.62))
    p.append(cal)
    return p


def reveal():
    M = _mats()
    p = _table(M)
    deck, deck_led = _deck(M)
    p += _move(deck, -0.24, -0.02, TH, math.radians(4))
    p += _move(_mic(M), -0.01, 0.1, TH, math.radians(-8))
    tx, tx_led, valve, lead = _transmitter(M)
    p += _move(tx, 0.27, -0.06, TH)
    p += _move(_thermos(M), -0.44, -0.11, TH)
    p += _move(_ashtray(M), 0.07, -0.1, TH)
    # labels and pages are drawn top toward +Y, so turn them to read from the chair
    p += _move(_journal(M), 0.27, 0.15, TH, math.radians(180 - 12))
    # the tapes stacked at the front left, NIGHT DRIVE 2 to 7
    for k in range(6):
        tape = MY.cassette("NIGHT\nDRIVE %d" % (k + 2))
        p += _move(tape, -0.4, 0.17, TH + k * 0.0125, math.radians(180 + (k % 3 - 1) * 6))
    # leads: deck to transmitter across the table, the aerial up into the roof
    p.append(_beam((-0.07, -0.04, TH + 0.004), (0.14, -0.1, TH + 0.004), 0.0035, M["wire"]))
    ax, ay, az = 0.27 + lead[0], -0.06 + lead[1], TH + lead[2]
    p.append(_beam((ax, ay, az), (ax + 0.05, WALL_Y + 0.02, 1.6), 0.002, M["copper"], segs=3))
    p.append(_beam((ax + 0.05, WALL_Y + 0.02, 1.6), (ax + 0.05, WALL_Y + 0.02, 2.26), 0.002, M["copper"], segs=3))
    p.append(cyl(0.012, 0.04, (ax + 0.05, WALL_Y + 0.03, 2.27), M["porcelain"], segs=6))
    p += _board(M)
    sockets = {
        "DeckLight": tuple(a + b for a, b in zip((-0.24, -0.02, TH), deck_led)),
        "TxLight": (0.27 + tx_led[0], -0.06 + tx_led[1], TH + tx_led[2]),
        "Valve": (0.27 + valve[0], -0.06 + valve[1], TH + valve[2]),
        "Bulb": (0.0, 0.0, TH + 1.0),
    }
    return p, sockets
