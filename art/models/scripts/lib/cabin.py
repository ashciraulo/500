"""Cabin detail for the modern 500s: the instrument cluster and its needles,
vents, radio and climate panel, glovebox, column stalks and key, a shaped
steering wheel, pedals, handbrake and cup holders, door trim, seat belts and
the bits on the headliner.

Coordinates are the car's (Blender): -Y is forward, the driver sits at
x = -0.36 (right-hand drive), z up from the ground at zero ride height.
Every part gets a short name; parts that are meant to sit into each other
are listed in check_car_clipping.ATTACHED.
"""
import math

from mathutils import Matrix, Vector

from . import carkit as K
from . import common as C
from . import textures as TX

# instrument cluster: centre of the dial, and how far it leans back
GAUGE_C = Vector((-0.36, -0.555, 1.025))
GAUGE_TILT = 0.12
GAUGE_R = 0.086
SPEED_MAX, REV_MAX = 200, 7
SWEEP = 240.0                    # degrees, both dials, starting lower left


def mats(spec):
    """Materials only the cabin detail uses."""
    return {
        "carpet": C.mat("Carpet", image=TX.carpet("carpet", spec.get("carpet", "#29292b"), 21, 16), rough=1.0),
        "lcd": C.mat("RadioLCD", image=_radio_tex(), rough=0.3, emit="#ff9a3a", emit_strength=0.25, emit_image=True),
        "climate": C.mat("ClimatePanel", image=_climate_tex(), rough=0.4),
        "needle": C.mat("Needle", "#f05a14", rough=0.4, emit="#ff6a20", emit_strength=0.3),
        "pad": C.mat("PedalRubber", image=TX.carpet("pedal_rubber", "#141415", 5, 8), rough=0.95),
        "belt": C.mat("SeatBelt", image=_belt_tex(), rough=0.9),
        "dome": C.mat("DomeLens", "#e9e4d6", rough=0.3, emit="#fff1d0", emit_strength=0.0),
        "key": C.mat("KeyMetal", "#c9cbcd", rough=0.25, metal=0.9),
        "marker": C.mat("KnobMarker", "#e8e6e0", rough=0.4),
    }


# ------------------------------------------------------------------ textures

def _put_text(px, w, h, text, cx, cy, ink, scale=1):
    """Stamp centred plate-font text into a flat [w*h] list of rgb tuples."""
    cw = 4 * scale
    x0 = int(round(cx - (cw * len(text) - scale) / 2))
    y0 = int(round(cy - 5 * scale / 2))
    for i, ch in enumerate(text):
        bits = TX.FONT.get(ch, TX.FONT[" "])
        for ly in range(5):
            for lx in range(3):
                if bits[(4 - ly) * 3 + lx] != "1":
                    continue
                for sy in range(scale):
                    for sx in range(scale):
                        x = x0 + i * cw + lx * scale + sx
                        y = y0 + ly * scale + sy
                        if 0 <= x < w and 0 <= y < h:
                            px[y * w + x] = ink


def _image(name, w, h, px):
    return C.make_image(name, w, h, lambda x, y: px[y * w + x])


def _dial_angle(t):
    """Fraction t of a dial's sweep -> degrees clockwise from straight up."""
    return -SWEEP / 2 + SWEEP * t


def gauges_tex(name="gauges_hd"):
    """The 500's concentric cluster: speedo round the outside, rev counter
    inside it, a small LCD in the middle. u runs to the driver's right."""
    s = 128
    px = [(0.02, 0.02, 0.025)] * (s * s)
    white, red, grey = (0.92, 0.92, 0.9), (0.85, 0.12, 0.08), (0.35, 0.35, 0.37)
    for y in range(s):
        for x in range(s):
            u, v = (x + 0.5) / s * 2 - 1, (y + 0.5) / s * 2 - 1
            r = math.hypot(u, v)
            a = math.degrees(math.atan2(u, v))          # clockwise from up
            t_rev = (a + SWEEP / 2) / SWEEP
            if r > 0.985:
                continue
            if r > 0.955:
                px[y * s + x] = grey                     # outer bezel shadow
            elif 0.86 < r < 0.955 and -SWEEP / 2 <= a <= SWEEP / 2:
                kmh = (a + SWEEP / 2) / SWEEP * SPEED_MAX
                major = abs(kmh - round(kmh / 20) * 20) < 1.4
                minor = abs(kmh - round(kmh / 10) * 10) < 0.9
                if major or (minor and r > 0.9):
                    px[y * s + x] = white
            elif 0.44 < r < 0.56 and -SWEEP / 2 <= a <= SWEEP / 2:
                rpm = t_rev * REV_MAX
                if rpm > 6.0 and r > 0.5:
                    px[y * s + x] = red
                elif abs(rpm - round(rpm)) < 0.06 or (abs(rpm - round(rpm * 2) / 2) < 0.04 and r > 0.5):
                    px[y * s + x] = white
            elif r < 0.30 and abs(v + 0.02) < 0.16:
                px[y * s + x] = (0.10, 0.17, 0.16)      # LCD window
            elif 0.6 < r < 0.62 and -SWEEP / 2 <= a <= SWEEP / 2:
                px[y * s + x] = grey                     # ring between the dials
    for k in range(0, SPEED_MAX + 1, 40):
        a = math.radians(_dial_angle(k / SPEED_MAX))
        cx, cy = (math.sin(a) * 0.75 + 1) * s / 2, (math.cos(a) * 0.75 + 1) * s / 2
        _put_text(px, s, s, str(k), cx, cy, white)
    for k in range(1, REV_MAX + 1):
        a = math.radians(_dial_angle(k / REV_MAX))
        cx, cy = (math.sin(a) * 0.36 + 1) * s / 2, (math.cos(a) * 0.36 + 1) * s / 2
        _put_text(px, s, s, str(k), cx, cy, red if k > 6 else white)
    _put_text(px, s, s, "04712", s / 2, s / 2 + 1, (0.55, 0.85, 0.75))
    _put_text(px, s, s, "KM", s / 2, s / 2 - 7, (0.4, 0.65, 0.58))
    _put_text(px, s, s, "KMH", s / 2, s * 0.17, grey)
    return _image(name, s, s, px)


def dial_tex(name, vmax, label_step, face=(0.9, 0.87, 0.78), ink=(0.08, 0.08, 0.08), tick_step=None,
             red_from=None, units="KMH", odo=True, s=128):
    """A single period dial: ticks and numbers over the 240 degree sweep,
    an odometer window and the units. u runs to the viewer's right."""
    tick_step = tick_step or label_step / 2
    px = [face] * (s * s)
    red = (0.8, 0.1, 0.06)
    for y in range(s):
        for x in range(s):
            u, v = (x + 0.5) / s * 2 - 1, (y + 0.5) / s * 2 - 1
            r = math.hypot(u, v)
            a = math.degrees(math.atan2(u, v))
            if r > 0.985:
                px[y * s + x] = (0.02, 0.02, 0.02)
                continue
            if not (-SWEEP / 2 - 1 <= a <= SWEEP / 2 + 1):
                continue
            val = (a + SWEEP / 2) / SWEEP * vmax
            col = red if red_from is not None and val >= red_from else ink
            if 0.83 < r < 0.95:
                if abs(val - round(val / label_step) * label_step) < vmax * 0.006:
                    px[y * s + x] = col
                elif abs(val - round(val / tick_step) * tick_step) < vmax * 0.004 and r > 0.88:
                    px[y * s + x] = col
            if 0.945 < r < 0.96:
                px[y * s + x] = col
    k = 0
    while k <= vmax + 1e-6:
        a = math.radians(_dial_angle(k / vmax))
        cx, cy = (math.sin(a) * 0.66 + 1) * s / 2, (math.cos(a) * 0.66 + 1) * s / 2
        lbl = str(int(k)) if k >= 1 or k == 0 else str(k)
        _put_text(px, s, s, lbl, cx, cy, red if red_from is not None and k >= red_from else ink)
        k += label_step
    if odo:
        for y in range(int(s * 0.30), int(s * 0.38)):
            for x in range(int(s * 0.36), int(s * 0.64)):
                px[y * s + x] = (0.05, 0.05, 0.05)
        _put_text(px, s, s, "31415", s / 2, s * 0.34, (0.9, 0.9, 0.88))
    _put_text(px, s, s, units, s / 2, s * 0.6, ink)
    return _image(name, s, s, px)


def needle(name, m, r0, r1, w, mat, lift=0.0):
    """A pointer pivoted on the dial centre, at rest on the dial's zero
    (lower left). Its local Z is the dial normal, so in Godot it turns
    about its local Y, clockwise (negative) as the value rises through
    240 degrees. The name ends in the dial's full-scale value."""
    vs = [(-w / 2, r0, 0), (w / 2, r0, 0), (w / 4, r1, 0), (-w / 4, r1, 0),
          (-w / 2, r0, 0.002), (w / 2, r0, 0.002), (w / 4, r1, 0.002), (-w / 4, r1, 0.002)]
    fs = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    o = C.mesh_obj(name, vs, fs, mat)
    o.data.transform(Matrix.Rotation(math.radians(SWEEP / 2), 4, "Z"))
    o.matrix_world = m @ Matrix.Translation((0, 0, lift))
    return o


def _radio_tex():
    """Head unit face: amber display, preset buttons, a CD slot."""
    w, h = 64, 24
    body, btn, slot = (0.035, 0.035, 0.04), (0.11, 0.11, 0.12), (0.0, 0.0, 0.0)
    px = [body] * (w * h)
    for y in range(h):
        for x in range(w):
            if 14 <= x < 50 and 12 <= y < 20:
                px[y * w + x] = (0.08, 0.05, 0.02)
            if 14 <= x < 50 and y == 22:
                px[y * w + x] = slot
            if 14 <= x < 50 and 3 <= y < 8 and (x - 14) % 6 < 5:
                px[y * w + x] = btn
    _put_text(px, w, h, "FM 98.5", 32, 16, (1.0, 0.62, 0.2))
    for i, n in enumerate("123456"):
        _put_text(px, w, h, n, 16 + i * 6 + 1, 5, (0.7, 0.7, 0.72))
    return _image("radio_face", w, h, px)


def _climate_tex():
    """Climate panel: blue-to-red temperature arc, fan speeds, vent modes,
    and the A/C, recirculation and rear demist buttons along the bottom."""
    w, h = 64, 32
    px = [(0.05, 0.05, 0.055)] * (w * h)
    centres = (11, 32, 53)
    for y in range(h):
        for x in range(w):
            for i, cx in enumerate(centres):
                r = math.hypot(x + 0.5 - cx, y + 0.5 - 18)
                a = math.degrees(math.atan2(x + 0.5 - cx, y + 0.5 - 18))
                if 8.5 < r < 10 and -130 < a < 130:
                    t = (a + 130) / 260
                    if i == 0:
                        px[y * w + x] = (0.15 + 0.75 * t, 0.25, 0.9 - 0.75 * t)
                    elif int(t * 8) % 2 == 0:
                        px[y * w + x] = (0.7, 0.7, 0.72)
            if 1 <= y < 6 and (x % 16) not in (0, 15) and x < 63:
                px[y * w + x] = (0.13, 0.13, 0.14)
    for lbl, cx in (("AC", 8), ("R", 24), ("D", 40), ("F", 56)):
        _put_text(px, w, h, lbl, cx, 3.5, (0.75, 0.75, 0.78))
    return _image("climate_face", w, h, px)


def _belt_tex():
    w, h = 4, 16
    return C.make_image("seat_belt", w, h,
                        lambda x, y: (0.05, 0.05, 0.055) if x in (0, 3) or y % 4 == 0 else (0.09, 0.09, 0.1))


# ------------------------------------------------------------------ helpers

def _frame(center, right, up):
    """Matrix taking a local (x right, y up, z toward the viewer) frame."""
    r, u = Vector(right).normalized(), Vector(up).normalized()
    n = r.cross(u)
    m = Matrix((r, u, n)).transposed().to_4x4()
    m.translation = Vector(center)
    return m


def _place(o, m):
    C.apply_transform(o)            # bake any loc/rot the primitive was made with
    o.data.transform(m)
    return o


def _quad(name, w, h, m, mat, uv=True, flip_u=False):
    """w x h quad in the local XY plane facing local +Z."""
    vs = [(-w / 2, -h / 2, 0), (w / 2, -h / 2, 0), (w / 2, h / 2, 0), (-w / 2, h / 2, 0)]
    o = C.mesh_obj(name, vs, [(0, 1, 2, 3)], mat)
    if uv:
        o.data.uv_layers.new(name="UVMap")
        d = o.data.uv_layers.active.data
        for li, (uu, vv) in zip(range(4), ((0, 0), (1, 0), (1, 1), (0, 1))):
            d[li].uv = (1 - uu if flip_u else uu, vv)
    return _place(o, m)


def _disc(name, r, m, mat, segs=24):
    """Round face in the local XY plane, the texture's circle fitted to it."""
    vs = [(math.cos(2 * math.pi * i / segs) * r, math.sin(2 * math.pi * i / segs) * r, 0) for i in range(segs)]
    o = C.mesh_obj(name, vs, [tuple(range(segs))], mat)
    o.data.uv_layers.new(name="UVMap")
    d = o.data.uv_layers.active.data
    for li in range(segs):
        x, y, _ = vs[li]
        d[li].uv = (0.5 + x / (2 * r), 0.5 + y / (2 * r))
    return _place(o, m)


def _ring(name, r0, r1, depth, m, mat, segs=20):
    """Flat annulus of radii r0..r1 and some depth in the local XY plane."""
    vs, fs = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        for r, z in ((r0, 0), (r1, 0), (r1, depth), (r0, depth)):
            vs.append((c * r, s * r, z))
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(4):
            k2 = (k + 1) % 4
            fs.append((i * 4 + k, j * 4 + k, j * 4 + k2, i * 4 + k2))
    return _place(C.mesh_obj(name, vs, fs, mat), m)


def _between(name, a, b, r, mat, segs=6, r_top=None):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder(name, r, d.length, segs=segs, material=mat, r_top=r_top)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.location = (a + b) / 2
    C.apply_transform(o)
    return o


def _rbox(name, lo, hi, mat, bevel=0.006):
    """Box with its vertical edges chamfered (cheap rounded corners)."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    b = min(bevel, (x1 - x0) / 3, (y1 - y0) / 3)
    ring = [(x0 + b, y0), (x1 - b, y0), (x1, y0 + b), (x1, y1 - b),
            (x1 - b, y1), (x0 + b, y1), (x0, y1 - b), (x0, y0 + b)]
    vs = [(x, y, z0) for x, y in ring] + [(x, y, z1) for x, y in ring]
    fs = [tuple(reversed(range(8))), tuple(range(8, 16))]
    for i in range(8):
        j = (i + 1) % 8
        fs.append((i, j, 8 + j, 8 + i))
    return C.mesh_obj(name, vs, fs, mat)


def _pixel_text(name, text, m, px_size, depth, mat):
    """Chrome letters built from the plate font, one block per run of lit
    pixels, standing proud of the local XY plane."""
    parts = []
    cw = 4
    total = cw * len(text) - 1
    for i, ch in enumerate(text):
        bits = TX.FONT.get(ch, TX.FONT[" "])
        for ly in range(5):
            row = bits[(4 - ly) * 3:(4 - ly) * 3 + 3]
            lx = 0
            while lx < 3:
                if row[lx] == "1":
                    e = lx
                    while e + 1 < 3 and row[e + 1] == "1":
                        e += 1
                    x0 = (i * cw + lx - total / 2) * px_size
                    x1 = (i * cw + e + 1 - total / 2) * px_size
                    y0 = (ly - 2.5) * px_size
                    parts.append(C.box_minmax(name, (x0, y0, 0), (x1, y0 + px_size, depth), mat))
                    lx = e + 1
                else:
                    lx += 1
    o = C.join(parts, name)
    return _place(o, m)


# ------------------------------------------------------------------ dash

def _gauge_frame():
    n = Vector((0, math.cos(GAUGE_TILT), math.sin(GAUGE_TILT)))
    up = Vector((0, -math.sin(GAUGE_TILT), math.cos(GAUGE_TILT)))
    return _frame(GAUGE_C, (-1, 0, 0), up), n


def cluster(M, X):
    """Pod, hooded cowl, dial and bezel. Returns (parts, needles)."""
    m, n = _gauge_frame()
    out = []
    # the pod: a short drum pushed into the dash top, open toward the driver
    pod = C.cylinder("binnacle", 0.1, 0.12, segs=16, axis="Z", loc=(0, 0, -0.055), material=M["cabin"])
    out.append(_place(pod, m))
    # hood over the top half, standing out past the dial face
    cowl_v, cowl_f = [], []
    segs = 12
    for i in range(segs + 1):
        a = math.radians(-12 + (204 * i / segs))
        c, s = math.cos(a), math.sin(a)
        for r, z in ((0.1, 0.0), (0.11, 0.0), (0.11, 0.042), (0.1, 0.038)):
            cowl_v.append((c * r, s * r, z))
    for i in range(segs):
        for k in range(4):
            k2 = (k + 1) % 4
            cowl_f.append((i * 4 + k, i * 4 + k2, (i + 1) * 4 + k2, (i + 1) * 4 + k))
    cowl_f.append((0, 1, 2, 3))
    e = segs * 4
    cowl_f.append((e + 3, e + 2, e + 1, e))
    out.append(_place(C.mesh_obj("cowl", cowl_v, cowl_f, M["cabin"]), m))
    face = _disc("gauge", GAUGE_R, m @ Matrix.Translation((0, 0, 0.0055)),
                 C.mat("GaugesHD", image=gauges_tex(), rough=0.35, emit="#c8d4e0", emit_strength=0.25, emit_image=True))
    out.append(face)
    out.append(_ring("bezel", GAUGE_R - 0.002, GAUGE_R + 0.008, 0.012, m @ Matrix.Translation((0, 0, 0.0)),
                     M["chrome"], segs=24))
    out.append(_ring("dial_ring", 0.60 * GAUGE_R, 0.63 * GAUGE_R, 0.003, m @ Matrix.Translation((0, 0, 0.006)),
                     M["chrome"], segs=20))
    # warning-light strip below the dial, under the hood's shadow
    needles = [needle("Needle_Speed_%d" % SPEED_MAX, m, 0.86 * GAUGE_R, 0.97 * GAUGE_R, 0.005, X["needle"], 0.0075),
               needle("Needle_Rev_%d" % REV_MAX, m, 0.43 * GAUGE_R, 0.58 * GAUGE_R, 0.004, X["needle"], 0.0075)]
    return out, needles


def fascia_details(M, X, spec):
    """Things on the fascia band and the lower dash."""
    out = []
    # round side vents with a chrome ring, three vanes and a thumb wheel
    for x in (-0.64, 0.64):
        m = _frame((x, -0.552, 0.79), (-1, 0, 0), (0, 0, 1))
        out.append(_ring("vent_ring", 0.044, 0.056, 0.012, m @ Matrix.Translation((0, 0, -0.004)), M["chrome"]))
        out.append(_place(C.cylinder("vent", 0.045, 0.02, segs=16, loc=(0, 0, -0.008), material=M["dark"]), m))
        for k in (-1, 0, 1):
            out.append(_place(C.box_minmax("vane", (-0.042, k * 0.024 - 0.002, -0.012),
                                           (0.042, k * 0.024 + 0.002, 0.002), M["trim"]), m))
        out.append(_place(C.cylinder("vent_knob", 0.008, 0.012, segs=8, loc=(0, 0, 0.004), material=M["knob"]), m))
    # the pair of square vents at the top of the centre
    for x in (-0.075, 0.075):
        m = _frame((x, -0.553, 0.89), (-1, 0, 0), (0, 0, 1))
        out.append(_place(_rbox("vent_c", (-0.06, -0.028, -0.02), (0.06, 0.028, 0.0), M["chrome"], 0.012), m))
        out.append(_place(_rbox("vent_c_in", (-0.053, -0.021, -0.019), (0.053, 0.021, 0.001), M["dark"], 0.008), m))
        for k in range(4):
            yy = -0.0135 + k * 0.009
            out.append(_place(C.box_minmax("vane_c", (-0.05, yy - 0.0015, -0.014), (0.05, yy + 0.0015, 0.002),
                                           M["trim"]), m))
    # head unit: textured face in a bezel, two knobs
    out.append(C.box_minmax("radio", (-0.12, -0.556, 0.752), (0.12, -0.548, 0.842), M["dark"]))
    out.append(_quad("radio_face", 0.20, 0.075, _frame((0, -0.5475, 0.797), (-1, 0, 0), (0, 0, 1)),
                     X["lcd"]))
    for x in (-0.103, 0.103):
        out.append(C.cylinder("radio_knob", 0.012, 0.016, segs=10, axis="Y", loc=(x, -0.542, 0.797),
                              material=M["knob"]))
        out.append(C.box_minmax("radio_knob_mark", (x - 0.0012, -0.5355, 0.803), (x + 0.0012, -0.533, 0.807),
                                X["marker"]))
    # hazard switch between the radio and the climate pod
    tri = C.cylinder("hazard", 0.016, 0.01, segs=3, axis="Y", loc=(0, -0.546, 0.728), material=M["badge"],
                     rot_offset=math.pi / 2)
    out.append(tri)
    # "500" in chrome blocks on the passenger side of the fascia
    out.append(_pixel_text("logo", "500", _frame((0.36, -0.556, 0.775), (-1, 0, 0), (0, 0, 1)),
                           0.009, 0.004, M["chrome"]))
    # glovebox lid outline and catch on the sloping lower dash (passenger side)
    a, b = Vector((0, -0.560, 0.70)), Vector((0, -0.60, 0.62))
    up = (a - b).normalized()
    n = Vector((0, 1, 0)).cross(up).normalized() * -1
    if n.y < 0:
        n = -n
    mid = (a + b) / 2 + n * 0.003
    m = _frame((0.36, mid.y, mid.z), (-1, 0, 0), up)
    w, h = 0.40, 0.07
    for nm, lo, hi in (("glove_line", (-w / 2, h / 2 - 0.003), (w / 2, h / 2)),
                       ("glove_line", (-w / 2, -h / 2), (w / 2, -h / 2 + 0.003)),
                       ("glove_line", (-w / 2, -h / 2), (-w / 2 + 0.003, h / 2)),
                       ("glove_line", (w / 2 - 0.003, -h / 2), (w / 2, h / 2))):
        out.append(_place(C.box_minmax(nm, (lo[0], lo[1], -0.001), (hi[0], hi[1], 0.002), M["seam"]), m))
    out.append(_place(_rbox("glove_catch", (-0.045, 0.010, -0.002), (0.045, 0.026, 0.008), M["chrome"]), m))
    return out


def climate(M, X):
    """Climate panel on the face of the centre pod: three knobs and a row
    of buttons. The pod's face is at y = -0.50."""
    out = []
    m = _frame((0, -0.4985, 0.635), (-1, 0, 0), (0, 0, 1))
    out.append(_quad("climate", 0.22, 0.11, m, X["climate"], flip_u=False))
    for i, x in enumerate((-0.0756, 0.0, 0.0756)):
        # texture centres at u = 11, 32, 53 of 64 and v = 18 of 32
        lx = (11 + 21 * i) / 64 * 0.22 - 0.11
        km = m @ Matrix.Translation((lx, (18 / 32 - 0.5) * 0.11, 0))
        out.append(_place(C.cylinder("hvac_ring", 0.022, 0.006, segs=14, loc=(0, 0, 0.003), material=M["chrome"]), km))
        out.append(_place(C.cylinder("hvac", 0.019, 0.022, segs=14, loc=(0, 0, 0.012), material=M["knob"]), km))
        out.append(_place(C.box_minmax("hvac_mark", (-0.0015, 0.004, 0.0225), (0.0015, 0.016, 0.0235), X["marker"]),
                          km))
    return out


def console_bits(M, X):
    """Window and lock switches, cup holders, a handbrake with a gaiter."""
    out = []
    for x in (-0.045, 0.045):
        out.append(_rbox("win_switch", (x - 0.016, -0.40, 0.399), (x + 0.016, -0.36, 0.412), M["knob"], 0.004))
    out.append(_rbox("lock_switch", (-0.012, -0.40, 0.399), (0.012, -0.375, 0.41), M["knob"], 0.004))
    for y in (-0.27, -0.17):
        out.append(C.cylinder("cup", 0.036, 0.004, segs=14, loc=(0, y, 0.4015), material=M["dark"]))
        out.append(_ring("cup_rim", 0.036, 0.040, 0.003, Matrix.Translation((0, y, 0.4005)), M["trim"], 14))
    # handbrake: lever rising from a gaiter, release button at the tip
    a, b = Vector((0, 0.17, 0.40)), Vector((0, -0.06, 0.47))
    out.append(_between("handbrake", a, b, 0.022, M["trim"], segs=8, r_top=0.018))
    out.append(C.sphere("hb_button", 0.009, tuple(b + (b - a).normalized() * 0.006), M["chrome"], segs=8, rings=4))
    out.append(C.cylinder("hb_gaiter", 0.045, 0.03, segs=10, loc=(0, 0.13, 0.41), material=M["knob"], r_top=0.026))
    return out


def gear_lever(M, X):
    """High-mounted lever: pleated gaiter, chrome collar, knob with the
    shift pattern on top. The knob centre stays on Mount_Gear."""
    out = []
    tilt = math.radians(-40)
    rot = Matrix.Rotation(tilt, 4, "X")
    base = Vector((0, -0.44, 0.50))
    for i, (r0, r1) in enumerate(((0.062, 0.05), (0.052, 0.04), (0.042, 0.028))):
        c = C.cylinder("gaiter", r0, 0.03, segs=10, loc=(0, 0, 0.014 + i * 0.026), material=M["knob"], r_top=r1)
        c.data.transform(Matrix.Translation(base) @ rot)
        out.append(c)
    lever = C.cylinder("gear_stick", 0.011, 0.06, segs=8, loc=(0, 0, 0.09), material=M["chrome"])
    lever.data.transform(Matrix.Translation(base) @ rot)
    out.append(lever)
    knob_c = Vector((0, -0.37, 0.595))
    knob = C.sphere("gear_knob", 0.034, (0, 0, 0), M["knob"], segs=12, rings=7, scale=(1, 1, 0.85))
    knob.data.transform(Matrix.Translation(knob_c) @ rot)
    out.append(knob)
    top = Matrix.Translation(knob_c) @ rot @ Matrix.Translation((0, 0, 0.0285))
    out.append(_place(C.cylinder("gear_badge", 0.017, 0.002, segs=12, material=M["trim"]), top))
    # the H of the shift pattern in white lines
    for lo, hi in (((-0.009, -0.007), (-0.0075, 0.007)), ((-0.00075, -0.007), (0.00075, 0.007)),
                   ((0.0075, -0.007), (0.009, 0.007)), ((-0.009, -0.00075), (0.009, 0.00075))):
        out.append(_place(C.box_minmax("gear_pattern", (lo[0], lo[1], 0.001), (hi[0], hi[1], 0.0016), X["marker"]),
                          top))
    return out


def column(M, X):
    """Shroud, indicator and wiper stalks, key in the barrel."""
    out = []
    tilt = math.radians(24)
    hub = Vector((-0.36, -0.40, 0.93))
    axis = Vector((0, math.cos(tilt), math.sin(tilt)))
    m = Matrix.Translation(hub - axis * 0.11) @ Matrix.Rotation(tilt, 4, "X")
    shroud = _rbox("shroud", (-0.055, -0.07, -0.05), (0.055, 0.055, 0.02), M["cabin"], 0.02)
    out.append(_place(shroud, m))
    # stalks: indicators on the left (toward the centre, +X), wipers right
    for sx, nm in ((1, "stalk_ind"), (-1, "stalk_wipe")):
        a = m @ Vector((sx * 0.05, 0.02, 0.0))
        b = m @ Vector((sx * 0.215, 0.045, 0.015))
        out.append(_between(nm, a, b, 0.008, M["knob"], segs=6, r_top=0.011))
        out.append(C.sphere(nm + "_tip", 0.012, tuple(b), M["knob"], segs=8, rings=4, scale=(1.4, 1, 1)))
    # ignition barrel on the right of the shroud, the key and its fob hanging
    barrel = m @ Vector((-0.062, -0.03, -0.025))
    out.append(C.cylinder("ign", 0.016, 0.012, segs=10, axis="X", loc=tuple(barrel), material=M["chrome"]))
    out.append(C.box("key", (0.03, 0.004, 0.016), tuple(barrel + Vector((-0.02, 0, 0))), X["key"]))
    out.append(C.box("key_fob", (0.012, 0.03, 0.05), tuple(barrel + Vector((-0.04, 0.0, -0.03))), M["knob"]))
    return out


def torus_rim(name, rim_r, tube, segs, mat, ts=8, squash=1.0):
    """A wheel rim: one torus in the XZ plane (facing Y), its section
    stretched by squash along Y."""
    import bmesh
    vs, fs = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, sn = math.cos(a), math.sin(a)
        for j in range(ts):
            b = 2 * math.pi * j / ts
            r = rim_r + math.cos(b) * tube
            vs.append((c * r, math.sin(b) * tube * squash, sn * r))
    for i in range(segs):
        i2 = (i + 1) % segs
        for j in range(ts):
            j2 = (j + 1) % ts
            fs.append((i * ts + j, i * ts + j2, i2 * ts + j2, i2 * ts + j))
    rim = C.mesh_obj(name, vs, fs, mat)
    bm = bmesh.new()
    bm.from_mesh(rim.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(rim.data)
    bm.free()
    return rim


def ribbed_mat_tex(name="mat_ribbed", color="#1b1b1c"):
    """Rubber floor mat with raised ribs."""
    base = C._hex(color)
    return C.make_image(name, 16, 16, lambda x, y: TX.mul(base, 1.5 if y % 4 == 0 else (0.75 if y % 4 == 1 else 1.0)))


def steering_wheel(M, spec):
    """Thick rim, horizontal spokes into a rounded horn pad with the badge,
    a lower spoke pair; built facing the driver then set on the column."""
    rim_r, tube, segs = 0.185, 0.025, 28
    leather = C.mat("WheelLeather", "#151516", rough=0.7)
    bits = []
    rim = torus_rim("rim", rim_r, tube, segs, leather, squash=1.15)
    bits.append(rim)
    pad = C.sphere("horn", 1.0, (0, 0.012, 0), leather, segs=14, rings=7, scale=(0.09, 0.028, 0.07))
    bits.append(pad)
    bits.append(C.cylinder("hub", 0.05, 0.05, segs=12, axis="Y", loc=(0, -0.02, 0), material=leather))
    bits.append(K.lamp_disc("hub_ring", 0.026, 0.006, (0, 0.056, 0.006), (0, 1, 0), M["chrome"], segs=12))
    bits.append(K.lamp_disc("sw_badge", 0.021, 0.006, (0, 0.058, 0.006), (0, 1, 0), M["badge"], segs=12))
    for sx in (-1, 1):
        # built along +X with its height on local Y, then stood up in the
        # wheel's XZ plane (and turned round for the left-hand spoke)
        sp = _rbox("spoke", (0.06, -0.03, -0.016), (rim_r - 0.005, 0.022, 0.016), leather, 0.012)
        sp.data.transform(Matrix.Rotation(math.pi if sx < 0 else 0, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X"))
        bits.append(sp)
        if spec.get("sw_buttons"):
            for k in range(2):
                bits.append(C.box("sw_btn", (0.014, 0.006, 0.012), (sx * 0.105, 0.018, 0.01 - k * 0.02), M["chrome"]))
        low = _between("spoke_low", (sx * 0.03, 0, -0.05), (sx * 0.06, 0, -rim_r + 0.015), 0.014, leather, segs=6)
        bits.append(low)
    return bits


# ------------------------------------------------------------------ floor and pedals

def pedals(M, X):
    """Hanging clutch and brake with ribbed pads, a slimmer throttle and a
    footrest by the tunnel. RHD: from the tunnel out, clutch, brake, throttle."""
    out = []
    for x, w, h, nm in ((-0.245, 0.065, 0.055, "clutch"), (-0.345, 0.075, 0.055, "brake"), (-0.46, 0.045, 0.09, "throttle")):
        top = Vector((x, -0.80, 0.62))
        pad_c = Vector((x, -0.74, 0.34 if nm != "throttle" else 0.36))
        out.append(_between("pedal_arm", top, pad_c + Vector((0, 0.01, 0.02)), 0.008, M["trim"], segs=5))
        pad = C.box("pedal", (w, 0.016, h), tuple(pad_c), X["pad"])
        pad.rotation_euler = (math.radians(-18), 0, 0)
        C.apply_transform(pad)
        out.append(pad)
    rest = C.box("footrest", (0.05, 0.02, 0.16), (-0.165, -0.79, 0.33), X["pad"])
    rest.rotation_euler = (math.radians(-45), 0, 0)
    C.apply_transform(rest)
    out.append(rest)
    return out


# ------------------------------------------------------------------ seats

def seat(x, y, sm, head_mat, M, X, driver=False, inboard=1):
    """Front seat: bolstered cushion and backrest (one textured object each,
    so the driver's tape and scuffs land on the outboard bolsters), round
    headrest, plastic side covers, rails, a recline lever and the belt buckle.
    inboard is the sign of x toward the tunnel."""
    out = []
    # cushion: centre panel slightly dished, raised bolsters, front roll
    cs = [C.box_minmax("cushion", (x - 0.17, y - 0.06, 0.27), (x + 0.17, y + 0.40, 0.395), sm["cushion"]),
          _rbox("cushion", (x - 0.245, y - 0.07, 0.27), (x - 0.165, y + 0.41, 0.43), sm["cushion"], 0.02),
          _rbox("cushion", (x + 0.165, y - 0.07, 0.27), (x + 0.245, y + 0.41, 0.43), sm["cushion"], 0.02)]
    roll = C.cylinder("cushion", 0.035, 0.33, segs=8, axis="X", loc=(x, y - 0.06, 0.385), material=sm["cushion"])
    cs.append(roll)
    cush = C.join(cs, "cushion")
    K.planar_uv(cush, 0, 1)
    out.append(cush)
    # side covers and rails under the cushion
    for sx in (-1, 1):
        out.append(C.box_minmax("seat_side", (x + sx * 0.25 - 0.006, y - 0.04, 0.255), (x + sx * 0.25 + 0.006, y + 0.38, 0.33),
                                M["cabin"]))
        out.append(C.box_minmax("seat_rail", (x + sx * 0.17 - 0.012, y - 0.12, 0.26), (x + sx * 0.17 + 0.012, y + 0.48, 0.272),
                                M["post"]))
    outboard = -inboard
    lever = C.box("recline", (0.012, 0.11, 0.022), (x + outboard * 0.262, y + 0.36, 0.33), M["knob"])
    lever.rotation_euler = (math.radians(15), 0, 0)
    C.apply_transform(lever)
    out.append(lever)
    # backrest: rounded-top slab with side wings, leaning back 14 degrees
    pts = []
    for i in range(13):
        a = math.pi * i / 12
        pts.append((math.cos(a) * 0.24, 0.40 + math.sin(a) * 0.20))
    outline = [(0.24, 0.0)] + pts + [(-0.24, 0.0)]
    verts, faces = [], []
    nn = len(outline)
    for yy in (-0.06, 0.06):
        for px, pz in outline:
            verts.append((px, yy, pz))
    faces.append(tuple(range(nn)))
    faces.append(tuple(reversed(range(nn, 2 * nn))))
    for i in range(nn):
        j = (i + 1) % nn
        faces.append((i, j, nn + j, nn + i))
    parts = [C.mesh_obj("back", verts, faces, sm["back"])]
    for sx in (-1, 1):
        w = _rbox("back", (sx * 0.24 - (0.07 if sx > 0 else 0), -0.105, 0.03),
                  (sx * 0.24 + (0.07 if sx < 0 else 0), 0.0, 0.46), sm["back"], 0.025)
        parts.append(w)
    # a raised lumbar roll across the middle panel
    lum = C.cylinder("back", 0.03, 0.34, segs=8, axis="X", loc=(0, -0.065, 0.16), material=sm["back"])
    parts.append(lum)
    back = C.join(parts, "back")
    K.planar_uv(back, 0, 2)
    back.rotation_euler = (math.radians(-14), 0, 0)
    back.location = (x, y + 0.46, 0.38)
    C.apply_transform(back)
    out.append(back)
    # plastic hinge covers where the backrest meets the cushion
    for sx in (-1, 1):
        out.append(C.cylinder("hinge_cover", 0.045, 0.014, segs=10, axis="X",
                              loc=(x + sx * 0.258, y + 0.42, 0.40), material=M["cabin"]))
    head_y, head_z = y + 0.62, 1.10
    for px in (-0.06, 0.06):
        out.append(C.cylinder("post", 0.007, 0.12, segs=6, loc=(x + px, head_y - 0.02, head_z - 0.12),
                              material=M["post"]))
    out.append(C.cylinder("headrest", 0.12, 0.08, segs=16, axis="Y", loc=(x, head_y, head_z), material=head_mat))
    out.append(C.cylinder("headrest_rim", 0.112, 0.084, segs=16, axis="Y", loc=(x, head_y, head_z),
                          material=M["cabin"]))
    # belt buckle on its stalk, inboard of the cushion
    bx = x + inboard * 0.275
    out.append(_between("buckle_stalk", (bx, y + 0.40, 0.28), (bx, y + 0.33, 0.43), 0.009, X["belt"], segs=5))
    out.append(C.box("buckle", (0.02, 0.05, 0.03), (bx, y + 0.325, 0.45), M["knob"]))
    out.append(C.box("buckle_btn", (0.012, 0.016, 0.006), (bx, y + 0.31, 0.466), M["badge"]))
    return out


# ------------------------------------------------------------------ doors

def door_card(door, sx, M, X, fabric=None):
    """Inside of a front door: armrest with a pull cup, a chrome opening
    lever in its recess, a map pocket, the speaker and a fabric insert."""
    out = []
    loc, nor = K.hit(door, (0, -0.35, 0.45), (sx, 0, 0))
    out.append(K.stick_disc("speaker", door, (loc, -nor), 0.085, 0.02, M["dark"], segs=14, proud=0.045))
    out.append(K.stick_disc("speaker_ring", door, (loc, -nor), 0.093, 0.012, M["cabin"], segs=14, proud=0.04))
    for k in range(3):
        out.append(K.stick_disc("speaker_cone", door, (loc, -nor), 0.06 - k * 0.018, 0.004, M["trim"], segs=12,
                                proud=0.05 + k * 0.003))
    loc2, nor2 = K.hit(door, (0, 0.05, 0.72), (sx, 0, 0))
    arm = C.box("armrest", (0.07, 0.42, 0.055), loc2 - nor2 * 0.075, M["cabin"])
    out.append(arm)
    out.append(C.box("armrest_top", (0.06, 0.36, 0.008), loc2 - nor2 * 0.078 + Vector((0, 0, 0.03)), M["knob"]))
    out.append(C.box("pull", (0.03, 0.12, 0.02), loc2 - nor2 * 0.075 + Vector((0, -0.1, 0.12)), M["chrome"]))
    # opening lever toward the front, high up
    loc3, nor3 = K.hit(door, (0, -0.30, 0.86), (sx, 0, 0))
    out.append(C.box("lever_recess", (0.012, 0.13, 0.05), loc3 - nor3 * 0.012, M["dark"]))
    out.append(C.box("door_lever", (0.012, 0.09, 0.018), loc3 - nor3 * 0.02, M["chrome"]))
    # map pocket along the bottom
    loc4, nor4 = K.hit(door, (0, 0.0, 0.45), (sx, 0, 0))
    out.append(C.box("pocket", (0.05, 0.36, 0.08), loc4 - nor4 * 0.048, M["cabin"]))
    out.append(C.box("pocket_lip", (0.012, 0.36, 0.012), loc4 - nor4 * 0.068 + Vector((0, 0, 0.04)), M["trim"]))
    # fabric insert between the armrest and the window
    loc5, nor5 = K.hit(door, (0, 0.02, 0.88), (sx, 0, 0))
    ins = C.box("door_insert", (0.012, 0.44, 0.10), loc5 - nor5 * 0.026, fabric or M["cabin"])
    K.planar_uv(ins, 1, 2)
    out.append(ins)
    return out


# ------------------------------------------------------------------ roof

def headliner_bits(M, X, cab, roof_z):
    """Dome light, grab handle over the passenger door, visors with their
    clips, and a rear-view mirror with a proper back."""
    out = []
    zt = roof_z(0, 0.30) - 0.006
    out.append(_rbox("dome_base", (-0.07, 0.26, zt - 0.014), (0.07, 0.34, zt), M["headliner"], 0.02))
    out.append(_rbox("dome", (-0.045, 0.275, zt - 0.018), (0.045, 0.325, zt - 0.012), X["dome"], 0.012))
    return out


def seatbelts(M, X, half_width):
    """Front belts: a D-ring high on the pillar behind each door, the strap
    down the trim to the retractor at the sill, the tongue parked up top."""
    out = []
    for sx in (-1, 1):
        ya, za, yb, zb = 0.585, 1.06, 0.625, 0.36
        xa = sx * (half_width(ya, za) - 0.035)
        xb = sx * (half_width(yb, zb) - 0.06)
        a, b = Vector((xa, ya, za)), Vector((xb, yb, zb))
        d = b - a
        mid = (a + b) / 2
        strap = C.box("belt", (0.004, 0.045, d.length), (0, 0, 0), X["belt"])
        strap.data.transform(Matrix.Translation(mid) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
                             @ Matrix.Rotation(math.pi / 2, 4, "Z"))
        out.append(strap)
        out.append(C.box("belt_ring", (0.012, 0.06, 0.07), tuple(a + Vector((-sx * 0.004, 0, 0.01))), M["cabin"]))
        out.append(C.box("belt_tongue", (0.012, 0.035, 0.05), tuple(a + Vector((-sx * 0.01, 0, -0.07))), M["chrome"]))
        out.append(C.box("retractor", (0.05, 0.10, 0.12), tuple(b + Vector((-sx * 0.01, 0, 0.03))), M["cabin"]))
    return out
