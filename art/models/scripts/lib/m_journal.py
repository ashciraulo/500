"""M.'s 1979 field journal and the things that go with it.

M. is the tenant who made the NIGHT DRIVE tapes (lib/mystery.py). Each of
the seven wrong night birds (data/field/birds.json, wrong: true) has a page
in M.'s journal; the last one, the grey bird on the shed roof, is in the
player's own handwriting.

  journal()        the journal closed, cloth-bound in the same green as the
                   open copy on the shed table (lib/shed_reveal.py). The
                   cover is its own part so it can swing open on the spine.
  page(bird)       one page torn out of it, lying face up: the date line,
                   a pencil sketch, the handwriting, 1979 in the corner.
  boobook_hollow() a dead marri stump with the boobook's hollow, the nest
                   lined with brown cassette tape and a scrap of label.
  bream_tag()      the yellow dart tag from the 1979 bream's jaw.

Front toward -Y, origin at the base centre, metres, like lib/mystery.py.
All pictures are tiny procedural images, all original.
"""
import math
import random

from . import common as C
from . import furniture as F
from . import mystery as MY

PAPER = (0.92, 0.88, 0.76)
PENCIL = (0.30, 0.29, 0.30)
BIRO = (0.16, 0.22, 0.52)        # the last page: the player's blue ballpoint

BIRDS = ("frogmouth", "magpie", "swan", "cockatoos", "ibis", "boobook", "grey_bird")

PW, PH = 72, 96                   # page image, pixels
K = 2                             # sketches are drawn on a 36 x 48 grid, inked at K x


# ------------------------------------------------------------------ drawing

class _Canvas:
    """A set of inked pixels with a few pencil strokes."""

    def __init__(self):
        self.ink = set()

    def dot(self, x, y):
        self.ink.add((int(round(x * K)), int(round(y * K))))

    def line(self, x0, y0, x1, y1):
        n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) * 1.5 * K))
        for k in range(n + 1):
            t = k / n
            self.dot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)

    def ellipse(self, cx, cy, rx, ry, a0=0, a1=360, fill=False):
        if fill:
            for x in range(int((cx - rx) * K) - 1, int((cx + rx) * K) + 2):
                for y in range(int((cy - ry) * K) - 1, int((cy + ry) * K) + 2):
                    if ((x / K - cx) / rx) ** 2 + ((y / K - cy) / ry) ** 2 <= 1.0:
                        self.ink.add((x, y))
            return
        steps = max(12, int((rx + ry) * 3 * K))
        for k in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * k / steps)
            self.dot(cx + rx * math.cos(a), cy + ry * math.sin(a))

    def poly(self, pts):
        for a, b in zip(pts, pts[1:]):
            self.line(*a, *b)

    def text(self, lines, x, y, w=36, h=8):
        ink = MY._text(lines, w, h)
        for gx in range(w):
            for gy in range(h):
                if ink(gx, gy):
                    self.ink.add((int(x * K) + gx, int(y * K) + gy))


def _branch(c, y, x0=3, x1=30):
    c.line(x0, y, x1, y + 1)
    c.line(x0 + 6, y, x0 + 3, y - 2)


def _frogmouth(c):
    # upright on the branch like a broken stump, the wide flat head turned
    # full round to face out, two big eyes on it
    _branch(c, 17)
    c.poly([(14, 18), (13, 24), (14, 29), (16, 31), (19, 31), (21, 29), (22, 24), (21, 18), (17.5, 16), (14, 18)])
    c.ellipse(17.5, 31.5, 5.5, 2.6)
    c.ellipse(15.3, 32, 1.1, 1.1, fill=True)
    c.ellipse(19.7, 32, 1.1, 1.1, fill=True)
    c.line(16, 30, 19, 30)                    # the gape
    c.line(16.5, 18, 16, 14)                  # tail down past the branch
    c.line(18.5, 18, 19, 14)
    for y in (21, 24, 27):                    # streaky breast
        c.line(16, y, 17, y - 1)
        c.line(19, y, 20, y - 1)
    # two little ticks by the head: it has just turned
    c.line(25, 33, 26.5, 34.5)
    c.line(25, 31, 27, 31)


def _magpie(c):
    _branch(c, 18)
    c.ellipse(15, 23, 6, 3.5)
    c.ellipse(21, 27, 3, 3)
    c.line(24, 28, 28, 30)                    # the bill, open
    c.line(24, 27, 28, 26)
    c.line(9, 22, 4, 19)                      # tail
    c.line(14, 19, 14, 17)
    c.line(16, 19, 16, 17)
    # notes coming out of it
    for x, y in ((29, 32), (31, 35), (27, 35)):
        c.ellipse(x, y, 1, 0.8, fill=True)
        c.line(x + 1, y, x + 1, y + 3)


def _swan(c):
    # dead still on the current, facing upstream (left), the lights rising
    for x in range(2, 33):
        c.dot(x, 17 + (1 if (x // 3) % 2 else 0))
    c.ellipse(19, 20, 7, 3, 0, 180)
    c.line(12, 20, 26, 20)
    neck = [(14, 21), (12, 24), (12, 28), (14, 31), (13, 33), (10, 33)]
    c.poly(neck)
    c.line(10, 33, 7, 32)                     # bill
    for x, y in ((5, 22), (28, 24), (31, 28), (24, 30)):
        c.dot(x, y)
        c.dot(x, y - 1)


def _cockatoos(c):
    # thirteen, in two rows on the lemon gum branches, and the count
    _branch(c, 18)
    _branch(c, 27, 6, 31)
    rows = ((18, (5, 8, 11, 14, 17, 20, 23)), (27, (10, 13, 16, 19, 22, 25)))
    for y, xs in rows:
        for x in xs:
            c.ellipse(x, y + 2.6, 1.1, 2.2)
            c.dot(x, y + 5)
    c.text(["13"], 24, 30, 10, 6)


def _ibis(c):
    # on the white line, a traffic light beside it
    for x in range(2, 33, 4):
        c.line(x, 15, x + 2, 15)
    c.line(12, 16, 12, 22)                    # legs
    c.line(15, 16, 14, 22)
    c.ellipse(14, 25, 5, 3.4)
    c.poly([(18, 26), (20, 29), (20, 32)])    # neck
    c.ellipse(20, 33, 1.6, 1.4)
    c.poly([(21, 33), (24, 32), (26, 30), (27, 28)])  # the long curved bill
    c.line(29, 15, 29, 27)                    # the lights
    c.ellipse(29, 31, 2, 4)
    for y in (29, 31, 33):
        c.dot(29, y)


def _boobook(c):
    # by the hollow, ribbon spilling out of it
    c.ellipse(24, 26, 5, 7)                   # the hollow
    c.ellipse(11, 24, 5, 6)
    c.ellipse(11, 32, 4.5, 3.5)
    c.ellipse(9, 32, 1.4, 1.4)
    c.ellipse(13, 32, 1.4, 1.4)
    c.dot(11, 31)
    for k in range(9):
        x = 21 + k * 1.3
        c.dot(x, 21 + 2 * math.sin(k * 1.3))
    c.poly([(22, 22), (19, 19), (21, 16), (18, 15)])
    c.text(["?"], 26, 13, 6, 6)


def _grey_bird(c):
    # small and plain on the shed roof, looking at the house
    c.poly([(2, 17), (20, 23), (33, 19)])     # the roof
    c.line(22, 26, 32, 30)                    # the house over the lane
    c.line(22, 26, 22, 16)
    c.line(32, 30, 32, 16)
    c.ellipse(11, 23, 3.5, 2.6)
    c.ellipse(14, 26, 2, 2)
    c.line(16, 26, 18, 26)
    c.dot(15, 26)
    c.line(7, 22, 5, 21)


SKETCHES = {"frogmouth": _frogmouth, "magpie": _magpie, "swan": _swan, "cockatoos": _cockatoos,
            "ibis": _ibis, "boobook": _boobook, "grey_bird": _grey_bird}


# ------------------------------------------------------------------ images

def _img_page(bird):
    """One journal page: date line, sketch, handwriting, 1979 in the corner.
    Foxing spots and a faint rule; the player's page is in blue biro."""
    seed = 1979 + BIRDS.index(bird)
    mine = bird == "grey_bird"
    rnd = random.Random(seed)
    canvas = _Canvas()
    SKETCHES[bird](canvas)
    head = MY._scribble(seed, PW, PH, 1, x0=4, x1=40, y_top=PH - 7)
    body = MY._scribble(seed + 7, PW, PH, 4, x0=4, x1=PW - 5, gap=6, y_top=22)
    year = MY._text(["1979"], 18, 7) if not mine else None
    rules = (24, 18, 12, 6)
    spots = [(rnd.randint(0, PW - 1), rnd.randint(0, PH - 1)) for _ in range(14)]
    ink_col = BIRO if mine else PENCIL

    def px(x, y):
        c = PAPER
        if (x, y) in spots or (x + 1, y) in spots:
            c = (0.80, 0.70, 0.52)                         # foxing
        elif y + 2 in rules and x > 3:
            c = (0.84, 0.84, 0.80)                         # faint rule
        if x >= PW - 2 or y <= 1:
            c = (0.86, 0.80, 0.66)                         # browned edge
        if (x, y) in head or (x, y) in body or (x, y) in canvas.ink:
            return ink_col
        if year and year(x - (PW - 22), y - (PH - 10)):
            return ink_col
        return c
    return C.make_image("mj_page_" + bird, PW, PH, px)


def _img_label():
    """The paper label on the cover: M. and 1979 in M.'s capitals."""
    ink = MY._text(["M.", "1979"], 16, 14, 1, 1)
    return C.make_image("mj_label", 16, 14, lambda x, y: (0.2, 0.19, 0.2) if ink(x, y) else (0.9, 0.85, 0.7))


def _img_bark():
    rnd = random.Random(31)
    cols = [rnd.uniform(0.75, 1.1) for _ in range(16)]

    def px(x, y):
        k = cols[x] * (0.85 if (y + x * 3) % 7 == 0 else 1.0)
        return (0.33 * k, 0.25 * k, 0.2 * k)
    return C.make_image("mj_bark", 16, 32, px)


def _img_tag():
    ink = MY._text(["1979"], 18, 7)
    return C.make_image("mj_tag", 18, 7, lambda x, y: (0.1, 0.1, 0.1) if ink(x, y) else (0.95, 0.78, 0.12))


def _img_label_scrap():
    ink = MY._text(["NIGHT", "DR"], 22, 13, 1, 1)
    return C.make_image("mj_scrap", 22, 13, lambda x, y: (0.15, 0.15, 0.2) if ink(x, y) else (0.93, 0.9, 0.8))


# ------------------------------------------------------------------ props

JW, JD, JT = 0.155, 0.215, 0.022  # closed journal: width, depth, thickness


def _m(name, color, rough=0.8, metal=0.0):
    return MY._mat(name, color, rough, metal)


def journal():
    """Returns (body parts, cover parts, hinge). The body is the back board
    and the page block, the top page showing the frogmouth; the cover lies
    on top, hinged along the spine at x = -JW/2, with the label, the
    elastic and the pencil tucked under it."""
    cloth = _m("JournalCloth", "#3b4a30", 0.85)
    paper = _m("JournalPaper", "#e2d8bd", 0.95)
    body = [F.bx((-JW / 2, -JD / 2, 0.0), (JW / 2, JD / 2, 0.0025), cloth),
            F.bx((-JW / 2 + 0.003, -JD / 2 + 0.004, 0.0025), (JW / 2 - 0.004, JD / 2 - 0.004, JT - 0.0028), paper),
            F.bx((-JW / 2, -JD / 2, 0.0), (-JW / 2 + 0.006, JD / 2, JT), cloth)]   # spine
    top = MY._flat_quad("mj_page_frogmouth", _img_page("frogmouth"), JW - 0.012, JD - 0.012, z=JT - 0.0027)
    top.location.x = 0.0015
    body.append(top)
    z0 = JT - 0.0025
    cover = [F.bx((-JW / 2, -JD / 2, z0), (JW / 2 + 0.001, JD / 2, JT), cloth),
             # the endpaper inside the cover, seen when it swings open
             F.bx((-JW / 2 + 0.006, -JD / 2 + 0.004, z0 - 0.0004), (JW / 2 - 0.003, JD / 2 - 0.004, z0),
                  _m("Endpaper", "#cdbf98", 0.95))]
    lab = MY._flat_quad("mj_label", _img_label(), 0.06, 0.052, z=JT + 0.0004)
    lab.location = (0.012, 0.04, 0)
    cover.append(lab)
    elastic = _m("Elastic", "#151414", 0.6)
    cover.append(F.bx((JW / 2 - 0.03, -JD / 2 - 0.0005, JT), (JW / 2 - 0.022, JD / 2 + 0.0005, JT + 0.0015), elastic))
    pencil = C.cylinder("f", 0.0038, 0.17, segs=6, axis="Y", loc=(-JW / 2 + 0.012, 0.0, JT + 0.004),
                        material=_m("Pencil", "#d9a21f", 0.6))
    tip = C.cylinder("f", 0.0038, 0.014, segs=6, axis="Y", loc=(-JW / 2 + 0.012, -0.092, JT + 0.004),
                     material=_m("PencilWood", "#d8b98c", 0.8), r_top=0.0008)
    cover += [pencil, tip]
    return body, cover, (-JW / 2, 0.0, z0)


def page(bird):
    """One page torn out along the left edge, lying face up, centred."""
    w, d = 0.148, 0.2
    rnd = random.Random(BIRDS.index(bird) + 7)
    left = [(-w / 2 + rnd.uniform(0.0, 0.004), -d / 2 + d * k / 10) for k in range(11)]
    pts = [(-w / 2 + 0.002, -d / 2), (w / 2, -d / 2), (w / 2, d / 2)] + list(reversed(left))[:-1]
    z = 0.0006
    verts = [(x, y, z) for x, y in pts]
    mat = C.mat("MY_mj_page_" + bird, "#ffffff", rough=0.9, image=_img_page(bird))
    o = C.mesh_obj("page", verts, [tuple(range(len(verts)))], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li in o.data.polygons[0].loop_indices:
        vx, vy, _ = verts[o.data.loops[li].vertex_index]
        uv.data[li].uv = ((vx + w / 2) / w, (vy + d / 2) / d)
    mat.use_backface_culling = False
    return [o]


HOLLOW_Z = 0.92                    # the hollow's lip, on the -Y face


def boobook_hollow():
    """Returns (parts, sockets). A dead marri stump 1.5 m tall with a broken
    top and one side branch; the hollow faces -Y with the nest inside,
    lined with brown tape that spills over the lip; a scrap of label on a
    twig. Socket Bird: where the boobook stands, on the lip."""
    bark = C.mat("MY_mj_bark", "#ffffff", rough=0.95, image=_img_bark())
    wood = _m("DeadWood", "#8a7458", 0.9)
    dark = _m("HollowDark", "#120e0b", 1.0)
    twig = _m("Twig", "#5e4a36", 0.9)
    tape = _m("CassetteTape", "#6a3a18", 0.3, 0.35)
    parts = []
    trunk = C.cylinder("f", 0.2, 1.5, segs=10, axis="Z", loc=(0, 0, 0.75), material=bark, r_top=0.15)
    C.box_uv(trunk, 0.5)
    parts.append(trunk)
    flare = C.cylinder("f", 0.27, 0.18, segs=10, axis="Z", loc=(0, 0, 0.09), material=bark, r_top=0.2)
    C.box_uv(flare, 0.5)
    parts.append(flare)
    # broken top: a jagged cap of pale dead wood
    for k in range(5):
        a = k * 2 * math.pi / 5
        parts.append(F.bx((0.08 * math.cos(a) - 0.03, 0.08 * math.sin(a) - 0.03, 1.5),
                          (0.08 * math.cos(a) + 0.03, 0.08 * math.sin(a) + 0.03, 1.53 + 0.05 * (k % 3)), wood))
    br = C.cylinder("f", 0.05, 0.6, segs=6, axis="X", loc=(0.36, 0.0, 1.22), material=bark, r_top=0.02)
    br.rotation_euler = (0, math.radians(-35), 0)
    parts.append(br)
    # the hollow: a dark oval set into the -Y face, pale rim round it
    r_face = 0.19
    hole = C.cylinder("f", 1.0, 0.04, segs=12, axis="Y", loc=(0, -r_face + 0.015, HOLLOW_Z + 0.09),
                      material=dark)
    hole.scale = (0.075, 1.0, 0.11)
    parts.append(hole)
    rim = C.cylinder("f", 1.0, 0.03, segs=12, axis="Y", loc=(0, -r_face + 0.02, HOLLOW_Z + 0.09), material=wood)
    rim.scale = (0.095, 1.0, 0.13)
    parts.append(rim)
    # nest of twigs in the bottom of the hollow
    rnd = random.Random(6)
    for _ in range(9):
        a = rnd.uniform(0, math.pi)
        x0 = rnd.uniform(-0.05, 0.05)
        parts.append(F.bx((x0 - 0.035, -r_face - 0.018, HOLLOW_Z + 0.0), (x0 + 0.035, -r_face + 0.01, HOLLOW_Z + 0.008),
                          twig))
        parts[-1].rotation_euler = (0, a * 0.3, 0)
    # tape: strands looped through the nest and hanging over the lip
    for k, (x, ln) in enumerate(((-0.03, 0.16), (0.0, 0.24), (0.035, 0.11), (0.018, 0.3))):
        y = -r_face - 0.022 - 0.002 * k
        # each strand hangs in short kinked lengths, the way loose tape falls
        z, cx = HOLLOW_Z + 0.02, x
        while z > HOLLOW_Z - ln:
            nx = cx + rnd.uniform(-0.008, 0.008)
            parts.append(F.bx((min(cx, nx) - 0.0025, y - 0.0006, z - 0.03), (max(cx, nx) + 0.0025, y + 0.0006, z), tape))
            z, cx = z - 0.03, nx
        parts.append(F.bx((x - 0.03, y - 0.0006, HOLLOW_Z + 0.004), (x + 0.01, y + 0.0006, HOLLOW_Z + 0.009), tape))
    # the scrap of label on a twig poking out under the hollow
    stick = F.bx((0.05, -r_face - 0.06, HOLLOW_Z - 0.2), (0.12, -r_face - 0.052, HOLLOW_Z - 0.193), twig)
    parts.append(stick)
    scrap = MY._quad("mj_scrap", _img_label_scrap(), 0.045, 0.027, y=-r_face - 0.062)
    scrap.location = (0.1, 0, HOLLOW_Z - 0.225)
    scrap.rotation_euler = (0, math.radians(8), 0)
    parts.append(scrap)
    return parts, {"Bird": (0.0, -r_face - 0.04, HOLLOW_Z + 0.012)}


def bream_tag():
    """A yellow plastic dart tag, origin at the barb (which sits in the jaw),
    the streamer running along +Y; 1979 printed on it."""
    yellow = _m("TagYellow", "#f0c419", 0.5)
    parts = [F.bx((-0.0015, 0.0, -0.0015), (0.0015, 0.012, 0.0015), _m("TagBarb", "#d8d2bc", 0.4)),
             F.bx((-0.002, 0.012, -0.0018), (0.002, 0.065, 0.0018), yellow)]
    # printed along the streamer: the quad is laid along X, then turned
    lab = MY._flat_quad("mj_tag", _img_tag(), 0.04, 0.0034, z=0.0019)
    lab.rotation_euler = (0, 0, math.radians(90))
    lab.location.y = 0.04
    parts.append(lab)
    return parts
