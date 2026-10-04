"""The townhouse mystery: clue props, the shed key, the things that turn up in
the under-stair cupboard, the small wrong things around the house, and what
is inside the player's shed.

Every function returns a list of parts authored like furniture.py: front
toward -Y, origin at the base centre (or the wall contact point for things
that hang), metres. Textures are tiny procedural images, all original.

The story (data/progression/mystery.json, scripts/world/mystery.gd): someone
at 15 Little Shenton Lane kept a round little car in the carport and taped
their night drives around Perth, one to twelve. The clues are theirs; the
shed holds the rest. Under the dust sheet in the shed sits whatever
MysteryProps.build_shed puts there when the game reveals it.
"""
import math
import random

from mathutils import Vector

from . import common as C
from . import furniture as F
from . import textures as TX

# ------------------------------------------------------------------ helpers


def _quad(img_name, img, w, h, y=-0.001, rough=0.85, emit=None):
    """A picture facing -Y, origin at its bottom centre."""
    mat = C.mat("MY_" + img_name, "#ffffff", rough=rough, image=img)
    if emit:
        mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = emit
    o = C.mesh_obj("pic", [(-w / 2, y, 0), (w / 2, y, 0), (w / 2, y, h), (-w / 2, y, h)], [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    return o


def _flat_quad(img_name, img, w, d, z=0.001, rough=0.85):
    """A picture lying face up, origin at its centre, top of the image toward +Y."""
    mat = C.mat("MY_" + img_name, "#ffffff", rough=rough, image=img)
    o = C.mesh_obj("pic", [(-w / 2, -d / 2, z), (w / 2, -d / 2, z), (w / 2, d / 2, z), (-w / 2, d / 2, z)],
                   [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    return o


def _mat(name, color, rough=0.7, metal=0.0, emit=None, strength=1.0):
    return C.mat("MY_" + name, color, rough=rough, metal=metal, emit=emit, emit_strength=strength)


def _text(lines, w, h, scale=1, top=1):
    """ink(x, y) for centred rows of the plate font."""
    cw = 4 * scale
    rows = []
    for i, line in enumerate(lines):
        x0 = (w - cw * len(line) + scale) // 2
        y0 = h - top - (i + 1) * 6 * scale
        rows.append((line, x0, y0))

    def ink(x, y):
        for line, x0, y0 in rows:
            gx, gy = x - x0, y - y0
            if 0 <= gx < cw * len(line) and 0 <= gy < 5 * scale:
                ch = line[gx // cw]
                lx, ly = (gx % cw) // scale, gy // scale
                if lx < 3 and TX.FONT.get(ch, TX.FONT[" "])[(4 - ly) * 3 + lx] == "1":
                    return True
        return False
    return ink


def _scribble(seed, w, h, rows, x0=1, x1=None, gap=3, y_top=None):
    """Handwriting: rows of short wobbly dashes. Returns a set of (x, y)."""
    rnd = random.Random(seed)
    x1 = w - 2 if x1 is None else x1
    y = (h - 3) if y_top is None else y_top
    ink = set()
    for _ in range(rows):
        x = x0 + rnd.randint(0, 1)
        end = rnd.randint((x0 + x1) // 2, x1)
        while x < end:
            ln = rnd.randint(2, 5)
            for k in range(ln):
                ink.add((x + k, y + (1 if rnd.random() < 0.25 else 0)))
            x += ln + 1
        y -= gap
    return ink


# ------------------------------------------------------------------ images

def _img_photo(kind, w=24, h=24):
    """Small faded photos. kinds: carport (a classic 500 by the open shed at
    night), lane (headlights at the end of the lane), river (lights over the
    water), park (headlights through trees), courtyard (the courtyard by day)
    and courtyard_figure (the same, with someone standing at the gate)."""
    rnd = C.noise_rng(sum(map(ord, kind)))
    fade = (0.12, 0.08, 0.02)

    def tone(c):
        # old print: warm, lifted blacks
        return tuple(min(1.0, v * 0.82 + f + rnd(0.025)) for v, f in zip(c, fade))

    if kind == "carport":
        def px(x, y):
            # roof line, shed wall with an open lit door, a little round car
            if y > 19:
                return tone((0.05, 0.05, 0.08))
            if 8 <= x <= 12 and 3 <= y <= 15:
                return tone((0.95, 0.82, 0.5))                       # lit shed door
            car = ((x - 15) / 6.5) ** 2 + ((y - 5) / 3.6) ** 2
            if car < 1 and y >= 3:
                return tone((0.62, 0.15, 0.12) if y < 6 else (0.25, 0.3, 0.35))
            if y < 3 and (x in (11, 12, 18, 19)):
                return tone((0.03, 0.03, 0.03))                      # tyres
            if y < 3:
                return tone((0.2, 0.19, 0.18))
            return tone((0.33, 0.3, 0.27))
        return C.make_image("photo_carport", w, h, px)
    if kind == "lane":
        def px(x, y):
            for hx in (10, 14):
                if (x - hx) ** 2 + (y - 8) ** 2 < 2.2:
                    return tone((1.0, 0.95, 0.75))
                if (x - hx) ** 2 + (y - 8) ** 2 < 6:
                    return tone((0.55, 0.5, 0.38))
            if y < 6:
                return tone((0.12, 0.1, 0.1) if (x + y) % 5 else (0.2, 0.12, 0.1))
            if x < 4 or x > 20:
                return tone((0.1, 0.1, 0.12))
            return tone((0.03, 0.03, 0.05))
        return C.make_image("photo_lane", w, h, px)
    if kind == "river":
        def px(x, y):
            for lx, ly in ((5, 15), (11, 17), (17, 14), (20, 18)):
                if (x - lx) ** 2 + (y - ly) ** 2 < 2:
                    return tone((1.0, 0.86, 0.55))
                if 8 < y < 12 and abs(x - lx) < 1:
                    return tone((0.45, 0.38, 0.26))
            if y < 11:
                return tone((0.05, 0.08, 0.13))
            if y < 12:
                return tone((0.15, 0.15, 0.17))
            return tone((0.04, 0.04, 0.08))
        return C.make_image("photo_river", w, h, px)
    if kind == "park":
        def px(x, y):
            for hx in (11, 13):
                if (x - hx) ** 2 + (y - 7) ** 2 < 1.2:
                    return tone((1.0, 0.95, 0.8))
            trunk = x in (2, 3, 7, 18, 21, 22)
            if trunk and y > 4:
                return tone((0.02, 0.02, 0.02))
            if y < 6:
                return tone((0.14, 0.13, 0.11))
            return tone((0.08, 0.1, 0.09))
        return C.make_image("photo_park", w, h, px)
    if kind in ("courtyard", "courtyard_figure"):
        def px(x, y):
            # herringbone pavers, render wall, the gate with its posts, a palm
            # (drawn on a 24 x 24 grid, stretched to the image)
            x, y = x * 24 // w, y * 24 // h
            if kind == "courtyard_figure":
                # someone standing by the gate post, dark against the wall
                legs = x in (3, 5) and 3 <= y <= 7
                torso = 3 <= x <= 5 and 8 <= y <= 12
                arms = x in (2, 6) and 8 <= y <= 11
                head = x == 4 and 13 <= y <= 15 or (3 <= x <= 5 and y == 14)
                if legs or torso or arms or head:
                    return tone((0.07, 0.06, 0.06))
            if y < 6:
                return tone((0.62, 0.3, 0.22) if (x + 2 * y) % 4 else (0.45, 0.22, 0.17))
            if 8 <= x <= 13 and y < 15:
                return tone((0.5, 0.4, 0.28) if x % 2 else (0.42, 0.33, 0.23))   # timber gate
            if x in (7, 14) and y < 16:
                return tone((0.85, 0.83, 0.78))
            if (x - 19) ** 2 + (y - 15) ** 2 < 12 or (x == 19 and y < 14):
                return tone((0.25, 0.42, 0.22) if y > 12 else (0.4, 0.3, 0.2))
            if y < 17:
                return tone((0.9, 0.86, 0.74))
            return tone((0.62, 0.74, 0.86))
        return C.make_image("photo_" + kind, w, h, px)
    raise ValueError(kind)


def _img_map(w=96, h=64):
    """A hand-annotated street map of inner Perth: the river curling under the
    city, Kings Park, the street grid, four places ringed in red."""
    rnd = random.Random(65)
    stains = TX.fbm(651, 3, 3)

    def river(x, y):
        # the Swan: wide below the city, narrowing toward the east
        cy = 14 + 6 * math.sin((x - 10) / 22.0) - (x / w) * 4
        half = 9 - x / 20.0
        return abs(y - cy) < half

    rings = [(22, 33), (54, 40), (70, 23), (47, 50)]

    def px(x, y):
        base = TX.lerp((0.93, 0.89, 0.76), (0.8, 0.72, 0.55), stains(x / w, y / h) * 0.7)
        for rx, ry in rings:
            d = math.hypot(x - rx, y - ry)
            if 3.2 < d < 4.4:
                return (0.75, 0.1, 0.08)
        if river(x, y):
            return (0.55, 0.72, 0.82)
        if 10 < x < 30 and 26 < y < 40 and (x - 20) ** 2 / 110 + (y - 33) ** 2 / 50 < 1:
            return (0.62, 0.76, 0.5)                               # Kings Park
        if (x % 8 == 0 and y > 24) or (y % 7 == 3 and x > 30 and y > 24):
            return (0.62, 0.58, 0.5)
        if x == 2 or y == 2 or x == w - 3 or y == h - 3:
            return (0.4, 0.36, 0.3)
        return base
    return C.make_image("mystery_map", w, h, px)


def _img_drawing(w=32, h=40):
    """A child's crayon drawing: a red round car outside a house, someone in
    the upstairs window, a big sun. Wax strokes, uneven fills."""
    rnd = C.noise_rng(77)

    def px(x, y):
        paper = (0.97, 0.96, 0.92)
        n = rnd(0.5)
        if (x - 26) ** 2 + (y - 34) ** 2 < 14 and n > -0.3:
            return (0.98, 0.78, 0.15)                              # sun
        if 3 <= x <= 16 and 12 <= y <= 27:
            if 6 <= x <= 8 and 20 <= y <= 23:
                return (0.1, 0.1, 0.12)                            # someone in the window
            if (x in (3, 16) or y in (12, 27)):
                return (0.35, 0.2, 0.12)
            return (0.85, 0.75, 0.55) if n > 0.1 else paper
        if 3 <= x <= 16 and 27 < y <= 27 + (16 - abs(2 * x - 19)) // 3:
            return (0.6, 0.15, 0.12)                               # roof
        car = ((x - 23) / 6.5) ** 2 + ((y - 8) / 4.0) ** 2
        if car < 1 and y >= 5:
            return (0.85, 0.12, 0.1) if n > -0.4 else paper
        if y in (3, 4) and (19 <= x <= 21 or 25 <= x <= 27):
            return (0.1, 0.1, 0.1)
        if y == 2 and n > -0.2:
            return (0.3, 0.6, 0.25)                                # grass line
        return paper
    return C.make_image("mystery_drawing", w, h, px)


def _img_tape_label(text, w=36, h=14):
    """A cassette label: red stripe, two lines of marker pen."""
    ink = _text(text.split("\n"), w, h, 1, 1)

    def px(x, y):
        if y == 1:
            return (0.75, 0.15, 0.12)
        if ink(x, y):
            return (0.1, 0.1, 0.12)
        return (0.92, 0.88, 0.76)
    return C.make_image("mystery_tape_" + text.lower().replace("\n", "_").replace(" ", "_"), w, h, px)


def _img_ticket(w=30, h=44):
    """A 1979 parking ticket: council red header, the date, ruled lines, the
    plate box scratched out in biro."""
    head = _text(["CITY", "PERTH"], w, 13, 1, 1)
    date = _text(["14 3 79"], w, 8, 1, 1)
    rnd = random.Random(1979)
    scratch = {(x, y) for x in range(4, 26) for y in range(9, 14) if rnd.random() < 0.7}

    def px(x, y):
        if y >= h - 13:
            return (0.92, 0.88, 0.8) if head(x, y - (h - 13)) else (0.68, 0.14, 0.12)
        if 18 <= y < 26 and date(x, y - 18):
            return (0.12, 0.12, 0.15)
        if 3 <= x <= 26 and 8 <= y <= 14:
            if (x, y) in scratch:
                return (0.1, 0.12, 0.3)
            if x in (3, 26) or y in (8, 14):
                return (0.35, 0.32, 0.28)
        if y in (4, 16) and 2 <= x <= w - 3:
            return (0.6, 0.56, 0.48)
        return (0.9, 0.87, 0.78) if (x * 5 + y * 3) % 13 else (0.86, 0.82, 0.72)
    return C.make_image("mystery_ticket", w, h, px)


def _img_old_plate(text="CIN 065", w=64, h=16):
    """A made-up sixties plate: black, silver characters."""
    cw = 7
    x0 = (w - cw * len(text)) // 2 + 1

    def px(x, y):
        if x in (0, w - 1) or y in (0, h - 1):
            return (0.6, 0.6, 0.6)
        gx = x - x0
        if 0 <= gx < cw * len(text):
            ch = text[gx // cw]
            lx, ly = (gx % cw) // 2, (y - 3) // 2
            if lx < 3 and 0 <= ly < 5 and TX.FONT.get(ch, TX.FONT[" "])[(4 - ly) * 3 + lx] == "1":
                return (0.82, 0.82, 0.8)
        return (0.06, 0.06, 0.07)
    return C.make_image("mystery_old_plate", w, h, px)


def _img_tag(text, w=16, h=10):
    ink = _text(text.split("\n"), w, h, 1, 2)

    def px(x, y):
        if (x - 2) ** 2 + (y - 5) ** 2 < 2:
            return (0.3, 0.25, 0.2)      # eyelet
        if ink(x, y):
            return (0.15, 0.12, 0.35)
        return (0.86, 0.8, 0.62)
    return C.make_image("mystery_tag_" + text.lower().replace("\n", "_").replace(" ", "_"), w, h, px)


def _img_radio_dial(w=32, h=8):
    def px(x, y):
        if y in (0, h - 1):
            return (0.3, 0.22, 0.1)
        if x == 21:
            return (0.9, 0.2, 0.1)       # needle parked off the stations
        if y == 2 and x % 3 == 0:
            return (0.35, 0.25, 0.1)
        if y in (4, 5) and x % 6 in (1, 2):
            return (0.4, 0.3, 0.12)
        return (0.95, 0.78, 0.42)
    return C.make_image("mystery_radio_dial", w, h, px)


# ------------------------------------------------------------------ clues

def cassette(label="NIGHT\nDRIVE 1"):
    """A compact cassette lying flat, origin at its base centre."""
    shell = _mat("CassetteShell", "#2a2a2c", 0.5)
    parts = [F.bx((-0.05, -0.032, 0), (0.05, 0.032, 0.012), shell)]
    if label:
        img = _img_tape_label(label)
        lab = _flat_quad(img.name, img, 0.084, 0.033, z=0.0122)
        lab.location.y = 0.0
        parts.append(lab)
    return parts


def polaroid(kind="carport"):
    """A Polaroid lying face up, origin at its centre, picture toward +Y."""
    w, h = 0.088, 0.107
    parts = [F.bx((-w / 2, -h / 2, 0), (w / 2, h / 2, 0.0015), _mat("PolaroidWhite", "#efeadc", 0.9))]
    pic = _flat_quad("photo_" + kind, _img_photo(kind), w * 0.88, w * 0.88, z=0.0017)
    pic.location.y = h / 2 - 0.006 - w * 0.44
    return parts + [pic]


def ticket():
    """The 1979 parking ticket, lying flat, header toward +Y."""
    return [_flat_quad("ticket", _img_ticket(), 0.08, 0.117, z=0.0008)]


def atlas_page():
    """A page torn from a street directory, lying flat, a fold across it."""
    w, d = 0.2, 0.134
    page = _flat_quad("atlas_page", _img_map(), w, d, z=0.0008)
    fold = F.bx((-w / 2, -0.001, 0.0), (w / 2, 0.001, 0.0011), _mat("PageFold", "#b8a888", 1.0))
    return [page, fold]


def _ring_and_tag(text, img, tw=0.065):
    """A split ring at x=-0.034 with a cardboard tag tied to it."""
    ring = _mat("KeyRing", "#b0b2b4", 0.3, 0.9)
    parts = []
    for i in range(10):
        a = i * 2 * math.pi / 10
        parts.append(F.bx((-0.034 + math.cos(a) * 0.013 - 0.0015, math.sin(a) * 0.013 - 0.0015, 0.0),
                          (-0.034 + math.cos(a) * 0.013 + 0.0015, math.sin(a) * 0.013 + 0.0015, 0.0025), ring))
    tag = F.bx((-0.045 - tw, -0.03, 0.0), (-0.045, 0.012, 0.0015), _mat("TagCard", "#d9cba3", 0.95))
    label = _flat_quad("tag_" + text.lower().replace("\n", "_").replace(" ", "_"), img, tw - 0.005, 0.036, z=0.0017)
    label.location = (-0.045 - tw / 2, -0.009, 0)
    string = F.bx((-0.05, -0.002, 0.0), (-0.028, 0.002, 0.0012), _mat("TagString", "#e8e0c8", 1.0))
    return parts + [tag, label, string]


def keyring():
    """The keyring from the glovebox: the tag says 15 LSL, SHED; the ring is
    empty."""
    return _ring_and_tag("15 LSL\nSHED", _img_tag("15 LSL\nSHED", 28, 15), 0.075)


def hubcap(r=0.17):
    """A dented classic 500 hubcap lying face up, origin at its base."""
    chrome = _mat("OldChrome", "#c9c7c0", 0.25, 0.85)
    rust = _mat("HubcapRust", "#7a4a2a", 0.9)
    parts = [F.cyl(r, 0.02, (0, 0, 0.01), chrome, 14, r_top=r * 0.82),
             F.cyl(r * 0.45, 0.015, (0, 0, 0.026), chrome, 10, r_top=r * 0.35),
             F.cyl(r * 0.18, 0.004, (0, 0, 0.0335), _mat("FiatBadge", "#7a1c1a", 0.5), 8)]
    for i in range(3):
        a = i * 2.1 + 0.4
        parts.append(F.bx((math.cos(a) * r * 0.7 - 0.012, math.sin(a) * r * 0.7 - 0.012, 0.016),
                          (math.cos(a) * r * 0.7 + 0.012, math.sin(a) * r * 0.7 + 0.012, 0.021), rust))
    # a dent: one rim sector pushed down
    return parts


def old_key(blade="#c9a24a", head="#1b1b1b"):
    """An old car or padlock key lying flat, origin at its centre, blade
    toward +X. 9 cm long so it reads at PS1 resolution."""
    brass = _mat("KeyBrass_" + blade[1:], blade, 0.35, 0.8)
    bow = _mat("KeyHead_" + head[1:], head, 0.5, 0.3 if head != "#1b1b1b" else 0.0)
    parts = [F.cyl(0.016, 0.004, (-0.03, 0, 0.002), bow, 10),
             F.cyl(0.005, 0.0045, (-0.038, 0, 0.0023), _mat("KeyHole", "#0a0a0a", 0.9), 6),
             F.bx((-0.016, -0.004, 0.0005), (0.045, 0.004, 0.0035), brass)]
    for i, x in enumerate((0.02, 0.028, 0.036)):
        parts.append(F.bx((x - 0.003, -0.008 + (i % 2) * 0.002, 0.0005), (x + 0.003, -0.004, 0.0035), brass))
    return parts


def shed_key():
    """The shed key: a brass padlock key on a split ring with a cardboard
    tag that says SHED, lying flat, origin at its centre."""
    parts = old_key("#c9a24a", "#c9a24a")
    for p in parts:
        C.apply_transform(p)
        p.location.x += 0.02
    return parts + _ring_and_tag("SHED", _img_tag("SHED"))


# The clues in data/progression/mystery.json, by id, in the order the game
# finds them. build_mystery.py exports each one alone; the game's own
# MysteryProps draws the same kinds.
CLUES = [
    ("tape_1", lambda: cassette("NIGHT\nDRIVE 1")),
    ("polaroid", lambda: polaroid("carport")),
    ("ticket", ticket),
    ("atlas_page", atlas_page),
    ("keyring", keyring),
    ("tape_12", lambda: cassette("DRIVE 12\nLAST")),
    ("shed_key", shed_key),
]


# ------------------------------------------------------------------ oddities

def crayon_drawing():
    """A child's drawing held on the fridge with a magnet; faces -Y, origin
    at its bottom centre."""
    w, h = 0.16, 0.2
    return [_quad("drawing", _img_drawing(), w, h, y=-0.0005),
            F.bx((-0.012, -0.006, h - 0.03), (0.012, 0.0, h - 0.006), _mat("Magnet", "#2f7a8a", 0.5))]


def wall_photo(kind, w=0.34, h=0.26):
    """A framed photo hanging on a wall (faces -Y), origin at its centre."""
    return [F.bx((-w / 2, -0.025, -h / 2), (w / 2, 0.0, h / 2), F.M("frame")),
            F.bx((-w / 2 + 0.025, -0.027, -h / 2 + 0.025), (w / 2 - 0.025, -0.025, h / 2 - 0.025), F.M("cream")),
            _picture_centered("photo_" + kind, _img_photo(kind, 32, 24), w - 0.08, h - 0.08, y=-0.0275)]


def _picture_centered(name, img, w, h, y):
    o = _quad(name, img, w, h, y=y)
    for v in o.data.vertices:
        v.co.z -= h / 2
    return o


def leaning_plant(seed=41):
    """A pothos-ish plant whose leaves all reach one way (toward -Y, the
    plant's front). Turn it and it is looking somewhere else."""
    rnd = random.Random(seed)
    pot = F.M("pot_white")
    parts = [F.cyl(0.07, 0.11, (0, 0, 0.055), pot, 10, r_top=0.08),
             F.cyl(0.075, 0.01, (0, 0, 0.105), F.M("soil"), 10)]
    for i in range(9):
        a = -math.pi / 2 + rnd.uniform(-0.6, 0.6)
        ln = rnd.uniform(0.1, 0.2)
        h = 0.11 + rnd.uniform(0.06, 0.16)
        tip = (math.cos(a) * ln, math.sin(a) * ln, h)
        parts.append(F._stem((rnd.uniform(-0.02, 0.02), rnd.uniform(-0.02, 0.02), 0.11), tip, F.M("leaf_dark")))
        parts.append(F._leaf(tip, a, 0.08, 0.07, F.M(rnd.choice(["leaf", "leaf_light"])), droop=rnd.uniform(-10, 20)))
    return parts


def bricked_fireplace(w, h):
    """Brick infill for the old fireplace opening, facing -Y (bricks in the
    plane y=0..-0.01), origin at its bottom centre; one brick left out (the
    loose one is separate)."""
    rnd = random.Random(12)
    mortar = _mat("Mortar", "#5a5048", 1.0)
    parts = [F.bx((-w / 2, 0.0, 0), (w / 2, 0.012, h), mortar)]
    bw, bh = 0.115, 0.055
    rows = int(h / (bh + 0.008))
    for r in range(rows):
        z = 0.004 + r * (bh + 0.008)
        off = 0 if r % 2 else bw / 2
        x = -w / 2 - off
        while x < w / 2:
            x0, x1 = max(x + 0.004, -w / 2), min(x + bw, w / 2)
            if x1 - x0 > 0.02 and not (r == LOOSE_ROW and abs((x0 + x1) / 2 - LOOSE_X) < 0.03):
                c = rnd.choice(["#6e2f22", "#7a3626", "#5e281e", "#83402c"])
                parts.append(F.bx((x0, -0.006, z), (x1, 0.0, z + bh), _mat("Brick_" + c[1:], c, 0.95)))
            x += bw + 0.008
    return parts


LOOSE_ROW = 5          # the loose brick's row in bricked_fireplace
LOOSE_X = 0.06         # and its centre across the opening (snapped to the bond)


def loose_brick(out=0.025):
    """The loose brick, sitting proud of the infill by `out`; origin at its
    centre on the wall plane."""
    return [F.bx((-0.0555, -0.006 - out, -0.0275), (0.0555, 0.05, 0.0275), _mat("Brick_83402c", "#83402c", 0.95))]


def wet_footprints(n=8, stride=0.62, seed=5):
    """Small muddy bare footprints walking toward -Y, lying on the floor,
    origin at the first print."""
    damp = _mat("MudPrint", "#8a7660", 0.9)
    rnd = random.Random(seed)
    parts = []
    for i in range(n):
        side = -1 if i % 2 else 1
        x, y = side * 0.07 + rnd.uniform(-0.01, 0.01), -i * stride / 2
        sole = C.sphere("sole", 0.055, (x, y - 0.01, 0.002), damp, segs=8, rings=3, scale=(0.75, 1.5, 0.03))
        heel = C.sphere("heel", 0.033, (x, y + 0.075, 0.002), damp, segs=7, rings=3, scale=(1.0, 1.2, 0.05))
        parts += [sole, heel]
        for t in range(4):
            parts.append(C.sphere("toe", 0.011, (x + (t - 1.5) * 0.017 * -side, y - 0.1 + abs(t - 1) * 0.006, 0.002),
                                  damp, segs=5, rings=2, scale=(1, 1, 0.2)))
    return parts


# ------------------------------------------------------------------ the shed

def valve_radio():
    """A 1950s mantel radio in a timber case: cloth grille, glowing dial,
    two knobs. Faces -Y, origin at its base centre."""
    case = _mat("RadioCase", "#5e3a22", 0.45)
    grille = _mat("RadioCloth", "#b59b6e", 1.0)
    parts = [F.bx((-0.21, -0.11, 0), (0.21, 0.11, 0.25), case),
             F.bx((-0.18, -0.112, 0.1), (0.02, -0.11, 0.22), grille),
             _quad("radio_dial", _img_radio_dial(), 0.14, 0.035, y=-0.112, emit=0.8)]
    parts[-1].location = (0.1, 0, 0.17)
    for x in (0.06, 0.15):
        parts.append(F.cyl(0.02, 0.025, (x, -0.12, 0.07), _mat("Bakelite", "#1e1712", 0.4), 10, axis="Y"))
    for x in (-0.16, 0.16):
        parts.append(F.bx((x - 0.015, -0.1, -0.012), (x + 0.015, 0.1, 0.0), case))
    # aerial wire trailing up the wall
    parts.append(F.bx((0.19, 0.11, 0.2), (0.195, 0.115, 0.75), _mat("Wire", "#2a2a2a", 0.8)))
    return parts


def key_board():
    """A small key board for the left wall (faces -Y): three hooks, an old
    Fiat key on one, the other two empty."""
    parts = [F.bx((-0.16, -0.015, -0.06), (0.16, 0.0, 0.06), F.M("wood_mid"))]
    for x in (-0.09, 0.0, 0.09):
        parts.append(F.cyl(0.004, 0.03, (x, -0.03, -0.01), F.M("brass"), 5, axis="Y"))
    key = old_key("#b9b9b4", "#1b1b1b")
    for p in key:
        C.apply_transform(p)
        p.rotation_euler = (math.radians(90), math.radians(90), 0)
        p.location = (-0.09, -0.04, -0.05)
        parts.append(p)
    return parts


def old_plate():
    """The made-up sixties plate, nailed up (faces -Y), origin at its centre."""
    w, h = 0.37, 0.09
    return [F.bx((-w / 2, -0.004, -h / 2), (w / 2, 0.0, h / 2), _mat("PlateBack", "#2a2a2a", 0.6, 0.3)),
            _picture_centered("old_plate", _img_old_plate(), w * 0.98, h * 0.94, y=-0.0045)]


def folding_chair():
    """Timber folding chair, faces -Y."""
    wood = F.M("wood_light")
    parts = [F.bx((-0.2, -0.18, 0.44), (0.2, 0.2, 0.47), wood),
             F.bx((-0.2, 0.18, 0.47), (0.2, 0.21, 0.85), wood)]
    for sx in (-1, 1):
        for a, b in (((-0.17, 0.0), (0.2, 0.86)), ((0.18, 0.0), (-0.17, 0.44))):
            leg = F.bx((-0.012, -0.012, 0), (0.012, 0.012, Vector((0, b[0] - a[0], b[1] - a[1])).length), wood)
            leg.rotation_euler = (math.atan2(-(b[0] - a[0]), b[1] - a[1]), 0, 0)
            leg.location = (sx * 0.19, a[0], a[1])
            parts.append(leg)
    return parts


def tea_chest():
    """A tea chest of photo envelopes and slides."""
    ply = _mat("TeaChest", "#b79565", 0.95)
    strip = F.M("metal")
    parts = []
    s, h = 0.42, 0.48
    for (lo, hi) in (((-s / 2, -s / 2, 0), (s / 2, -s / 2 + 0.01, h)), ((-s / 2, s / 2 - 0.01, 0), (s / 2, s / 2, h)),
                     ((-s / 2, -s / 2, 0), (-s / 2 + 0.01, s / 2, h)), ((s / 2 - 0.01, -s / 2, 0), (s / 2, s / 2, h)),
                     ((-s / 2, -s / 2, 0), (s / 2, s / 2, 0.01))):
        parts.append(F.bx(lo, hi, ply))
    for z in (0.0, h - 0.03):
        parts.append(F.bx((-s / 2 - 0.003, -s / 2 - 0.003, z), (s / 2 + 0.003, s / 2 + 0.003, z + 0.03), strip))
    rnd = random.Random(4)
    for i in range(9):
        x, y = rnd.uniform(-0.13, 0.13), rnd.uniform(-0.13, 0.13)
        c = rnd.choice(["#e6dcc4", "#c9b48c", "#d9cfa8", "#a88d6a"])
        p = F.bx((x - 0.06, y - 0.045, h - 0.1 + i * 0.006), (x + 0.06, y + 0.045, h - 0.095 + i * 0.006),
                 _mat("PhotoEnv_" + c[1:], c, 0.9))
        p.rotation_euler = (0, 0, math.radians(rnd.uniform(-30, 30)))
        parts.append(p)
    return parts


def bare_bulb(drop=0.35):
    """A bare bulb on a cord; origin at the ceiling."""
    return [F.bx((-0.004, -0.004, -drop), (0.004, 0.004, 0), _mat("Wire", "#2a2a2a", 0.8)),
            F.cyl(0.022, 0.05, (0, 0, -drop - 0.02), _mat("BulbHolder", "#1e1e1e", 0.5), 8),
            C.sphere("bulb", 0.032, (0, 0, -drop - 0.07), F.emissive("ShedBulbGlow", "#ffcf8a", 1.5),
                     segs=8, rings=5, scale=(1, 1, 1.25))]
