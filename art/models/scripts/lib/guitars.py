"""The studio's guitars, built to their real proportions: scale length, fret
spacing, body outline, pickguard, pickups, bridge, controls, headstock,
tuners and strings. No maker logos.

  tele        Squier 40th Anniversary Telecaster, Gold Edition: gold
              anodised one-ply guard, gold hardware, bound laurel board with
              pearloid blocks, 3-saddle string-through bridge
  jazzmaster  Squier J Mascis Jazzmaster: vintage white, gold anodised guard,
              laurel board with dots, Adjusto-Matic bridge and floating
              vibrato, rhythm circuit on the bass horn
  jbass       Squier Affinity Jazz Bass in black: 3-ply black guard, maple
              board with black dots, chrome control plate, black knobs
  dove        Gibson Dove: square-shoulder dreadnought, cherry sunburst
              spruce top, flame maple back and sides, multi-ply binding,
              moustache bridge with pearl doves, the dove pickguard,
              parallelogram inlays

Each hangs on the wall: back toward y=0 (8 mm off it), face toward -Y,
headstock up, bass side on -X, bottom of the body at z=0.
"""
import math
import random

import bmesh
from mathutils import Vector

from . import common as C


def _mat(name, color, rough=0.5, metal=0.0, image=None):
    return C.mat("G_" + name, color, rough=rough, metal=metal, image=image)


# ------------------------------------------------------------------ curves

def smooth(points, sharp=(), n=5):
    """Closed Hermite curve through points (x, z); corners at `sharp`."""
    m = len(points)
    P = [Vector(p) for p in points]
    T = []
    for i in range(m):
        if i in sharp:
            T.append(Vector((0, 0)))
        else:
            T.append((P[(i + 1) % m] - P[i - 1]) * 0.5)
    out = []
    for i in range(m):
        a, b = P[i], P[(i + 1) % m]
        ta, tb = T[i], T[(i + 1) % m]
        steps = 1 if (i in sharp and (i + 1) % m in sharp) else n
        for k in range(steps):
            t = k / steps
            h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
            h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
            p = a * h00 + ta * h10 + b * h01 + tb * h11
            out.append((p.x, p.y))
    return out


def _area(pts):
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts))) / 2


def inset(pts, d):
    """Move each point d inward along the bisector of its edges."""
    ccw = _area(pts) > 0
    out = []
    m = len(pts)
    for i in range(m):
        a, b, c = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % m])
        e1, e2 = (b - a).normalized(), (c - b).normalized()
        n1 = Vector((-e1.y, e1.x)) if ccw else Vector((e1.y, -e1.x))
        n2 = Vector((-e2.y, e2.x)) if ccw else Vector((e2.y, -e2.x))
        nb = n1 + n2
        if nb.length < 1e-6:
            nb = n1
        nb.normalize()
        k = 1.0 / max(0.35, nb.dot(n1))
        p = b + nb * d * k
        out.append((p.x, p.y))
    return out


def body(name, outline, y_front, y_back, round_r, mats, uv_front=False):
    """A slab of the outline with its front and back edges rounded over.
    y_front may be a function of (x, z) (an acoustic's top is not parallel to
    its back). mats = (front, sides, back)."""
    yf = y_front if callable(y_front) else (lambda x, z, v=y_front: v)
    rings = []
    r = round_r
    inner = inset(outline, r)
    mid = inset(outline, r * 0.3)
    rings.append([(x, yf(x, z), z) for x, z in inner])
    rings.append([(x, yf(x, z) + r * 0.3, z) for x, z in mid])
    rings.append([(x, yf(x, z) + r, z) for x, z in outline])
    rings.append([(x, y_back - r, z) for x, z in outline])
    rings.append([(x, y_back - r * 0.3, z) for x, z in mid])
    rings.append([(x, y_back, z) for x, z in inner])
    n = len(outline)
    verts = [v for ring in rings for v in ring]
    faces, fm = [], []
    faces.append(tuple(range(n)) if _area(outline) < 0 else tuple(reversed(range(n))))
    fm.append(0)
    last = (len(rings) - 1) * n
    faces.append(tuple(last + i for i in range(n)) if _area(outline) > 0 else
                 tuple(last + i for i in reversed(range(n))))
    fm.append(2)
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
            fm.append(0 if k == 0 else (2 if k == len(rings) - 2 else 1))
    o = C.mesh_obj(name, verts, faces, mats=list(mats))
    for p, mi in zip(o.data.polygons, fm):
        p.material_index = mi
    _fix(o)
    if uv_front:
        xs = [p[0] for p in outline]
        zs = [p[1] for p in outline]
        uvl = o.data.uv_layers.new(name="UVMap")
        for p in o.data.polygons:
            for li in p.loop_indices:
                co = o.data.vertices[o.data.loops[li].vertex_index].co
                uvl.data[li].uv = ((co.x - min(xs)) / (max(xs) - min(xs)), (co.z - min(zs)) / (max(zs) - min(zs)))
    return o


def plate(name, outline, y0, y1, mat, side_mat=None):
    """Thin flat part (guard, plate, inlay): outline in XZ from y0 to y1."""
    n = len(outline)
    verts = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in outline]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    o = C.mesh_obj(name, verts, faces, mats=[mat, side_mat or mat])
    for p in o.data.polygons[2:]:
        p.material_index = 1
    _fix(o)
    return o


def _fix(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


def box(lo, hi, mat, name="g"):
    return C.box_minmax(name, lo, hi, mat)


def disc(r, x, z, y0, y1, mat, segs=10, name="disc"):
    return C.cylinder(name, r, abs(y1 - y0), segs=segs, axis="Y", loc=(x, (y0 + y1) / 2, z), material=mat)


def rounded_rect(cx, cz, w, h, r, angle=0.0, segs=4):
    """Outline of a w x h rectangle with corner radius r, turned by angle."""
    pts = []
    for qx, qz, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ox, oz = qx * (w / 2 - r), qz * (h / 2 - r)
        for k in range(segs + 1):
            a = math.radians(a0 + 90 * k / segs)
            pts.append((ox + math.cos(a) * r, oz + math.sin(a) * r))
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + x * ca - z * sa, cz + x * sa + z * ca) for x, z in pts]


def ellipse(cx, cz, rx, rz, segs=16):
    return [(cx + math.cos(2 * math.pi * i / segs) * rx, cz + math.sin(2 * math.pi * i / segs) * rz)
            for i in range(segs)]


def strip(a, b, w, y0, y1, mat, name="strip"):
    """A flat bar from a to b (points in XZ), w wide."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    nrm = Vector((-d.y, d.x)) * (w / 2)
    pts = [tuple(a + nrm), tuple(b + nrm), tuple(b - nrm), tuple(a - nrm)]
    return plate(name, pts, y0, y1, mat)


# ------------------------------------------------------------------ the guitars
# Outlines are control points (x, z) in metres, bass side -X, from the bottom
# round clockwise (seen from the front); indices in `sharp` are the corners
# of the neck pocket.

TELE_BODY = dict(
    pts=[(0.0, 0.0), (0.085, 0.006), (0.138, 0.035), (0.16, 0.085), (0.161, 0.14), (0.15, 0.19), (0.141, 0.232),
         (0.142, 0.27), (0.141, 0.305), (0.128, 0.333), (0.1, 0.341), (0.068, 0.33), (0.04, 0.312),
         (0.0285, 0.305), (0.0285, 0.403), (-0.0285, 0.403), (-0.06, 0.403), (-0.1, 0.394), (-0.128, 0.37),
         (-0.142, 0.33), (-0.141, 0.28), (-0.141, 0.232), (-0.15, 0.19), (-0.161, 0.14), (-0.16, 0.085),
         (-0.138, 0.035), (-0.085, 0.006)],
    sharp=(13, 14, 15))

JM_BODY = dict(
    pts=[(0.0, -0.004), (0.07, 0.0), (0.128, 0.024), (0.163, 0.072), (0.17, 0.132), (0.154, 0.188),
         (0.128, 0.232), (0.12, 0.27), (0.132, 0.312), (0.152, 0.356), (0.158, 0.392), (0.145, 0.418),
         (0.116, 0.42), (0.082, 0.401), (0.047, 0.377), (0.0285, 0.37), (0.0285, 0.445), (-0.0285, 0.45),
         (-0.06, 0.468), (-0.095, 0.484), (-0.128, 0.48), (-0.148, 0.455), (-0.147, 0.41), (-0.13, 0.36),
         (-0.117, 0.315), (-0.128, 0.266), (-0.158, 0.214), (-0.178, 0.15), (-0.18, 0.09), (-0.158, 0.04),
         (-0.11, 0.006), (-0.05, -0.006)],
    sharp=(15, 16, 17))

JB_BODY = dict(
    pts=[(0.0, -0.004), (0.065, 0.0), (0.118, 0.024), (0.152, 0.072), (0.159, 0.132), (0.143, 0.188),
         (0.118, 0.234), (0.112, 0.275), (0.127, 0.33), (0.146, 0.388), (0.152, 0.425), (0.141, 0.448),
         (0.116, 0.449), (0.085, 0.432), (0.05, 0.404), (0.0285, 0.395), (0.0285, 0.452), (-0.0285, 0.457),
         (-0.058, 0.476), (-0.085, 0.497), (-0.112, 0.507), (-0.136, 0.497), (-0.146, 0.466), (-0.141, 0.42),
         (-0.124, 0.37),
         (-0.108, 0.326), (-0.122, 0.27), (-0.153, 0.215), (-0.17, 0.15), (-0.171, 0.09), (-0.15, 0.04),
         (-0.104, 0.006), (-0.05, -0.006)],
    sharp=(15, 16, 17))
JB_BODY["sharp"] = (15, 16, 17)

# Dove: 405 mm across the lower bout, 514 mm long, square shoulders
DOVE_BODY = dict(
    pts=[(0.0, 0.0), (0.105, 0.009), (0.168, 0.042), (0.199, 0.095), (0.203, 0.15), (0.19, 0.212),
         (0.158, 0.27), (0.139, 0.31), (0.141, 0.352), (0.147, 0.405), (0.147, 0.452), (0.138, 0.49),
         (0.112, 0.508), (0.06, 0.514), (0.0, 0.515), (-0.06, 0.514), (-0.112, 0.508), (-0.138, 0.49),
         (-0.147, 0.452), (-0.147, 0.405), (-0.141, 0.352), (-0.139, 0.31), (-0.158, 0.27), (-0.19, 0.212),
         (-0.203, 0.15), (-0.199, 0.095), (-0.168, 0.042), (-0.105, 0.009)],
    sharp=())

# headstocks, relative to the centre of the nut (z up the head)
TELE_HEAD = [(-0.021, 0.0), (-0.031, 0.012), (-0.036, 0.03), (-0.037, 0.16), (-0.031, 0.181), (-0.014, 0.187),
             (0.006, 0.18), (0.019, 0.158), (0.024, 0.115), (0.028, 0.07), (0.033, 0.04), (0.031, 0.02),
             (0.022, 0.0)]
JM_HEAD = [(-0.021, 0.0), (-0.032, 0.014), (-0.038, 0.035), (-0.039, 0.172), (-0.032, 0.195), (-0.012, 0.205),
           (0.014, 0.198), (0.04, 0.178), (0.054, 0.152), (0.05, 0.124), (0.034, 0.098), (0.027, 0.066),
           (0.031, 0.036), (0.03, 0.016), (0.022, 0.0)]
JB_HEAD = [(-0.0195, 0.0), (-0.03, 0.016), (-0.036, 0.04), (-0.037, 0.205), (-0.03, 0.228), (-0.01, 0.236),
           (0.016, 0.226), (0.04, 0.2), (0.052, 0.168), (0.046, 0.132), (0.032, 0.1), (0.026, 0.066),
           (0.029, 0.034), (0.028, 0.014), (0.0195, 0.0)]
DOVE_HEAD = [(-0.022, 0.0), (-0.031, 0.02), (-0.039, 0.06), (-0.044, 0.12), (-0.046, 0.166), (-0.042, 0.181),
             (-0.022, 0.178), (0.0, 0.17), (0.022, 0.178), (0.042, 0.181), (0.046, 0.166), (0.044, 0.12),
             (0.039, 0.06), (0.031, 0.02), (0.022, 0.0)]

GUITARS = {
    "tele": dict(body=TELE_BODY, depth=0.0445, round_r=0.005, scale=0.648, saddle=0.12, frets=21, strings=6,
                 nut_w=0.042, end_w=0.056, head=TELE_HEAD, tuners="fender_l"),
    "jazzmaster": dict(body=JM_BODY, depth=0.0445, round_r=0.008, scale=0.648, saddle=0.142, frets=21,
                       strings=6, nut_w=0.0425, end_w=0.056, head=JM_HEAD, tuners="fender_l"),
    "jbass": dict(body=JB_BODY, depth=0.0445, round_r=0.008, scale=0.864, saddle=0.085, frets=20, strings=4,
                  nut_w=0.0385, end_w=0.064, head=JB_HEAD, tuners="bass_l"),
    "dove": dict(body=DOVE_BODY, depth=(0.124, 0.104), round_r=0.006, scale=0.648, saddle=0.2254, frets=20,
                 strings=6, nut_w=0.0438, end_w=0.057, head=DOVE_HEAD, tuners="gibson_3x3"),
}


def colours(kind, tele_colour="black"):
    """Finish materials for each guitar."""
    if kind == "tele":
        paint = {"black": "#0d0d0f", "green": "#1f3d2c"}[tele_colour]
        return dict(body=_mat("tele_paint_" + tele_colour, paint, 0.15, 0.35 if tele_colour == "green" else 0.1),
                    hw=_mat("gold", "#d6b25a", 0.22, 0.95), guard=_mat("gold_anod", "#c9a24a", 0.32, 0.8),
                    guard_edge=_mat("gold_edge", "#e2c27a", 0.2, 0.9), board=_mat("laurel", "#4b2d1d", 0.6),
                    neck=_mat("maple_gloss", "#d6a463", 0.3), inlay=_mat("pearloid", "#ece7da", 0.25),
                    binding=_mat("binding", "#ece4cf", 0.4))
    if kind == "jazzmaster":
        return dict(body=_mat("vintage_white", "#ece2c4", 0.2), hw=_mat("chrome", "#d6d8da", 0.18, 0.95),
                    guard=_mat("gold_anod", "#c9a24a", 0.32, 0.8), guard_edge=_mat("gold_edge", "#e2c27a", 0.2, 0.9),
                    board=_mat("laurel", "#4b2d1d", 0.6), neck=_mat("maple_gloss", "#d6a463", 0.3),
                    inlay=_mat("pearloid", "#ece7da", 0.25), binding=None)
    if kind == "jbass":
        return dict(body=_mat("jb_black", "#0b0b0c", 0.15, 0.1), hw=_mat("chrome", "#d6d8da", 0.18, 0.95),
                    guard=_mat("guard_black", "#101010", 0.35), guard_edge=_mat("guard_ply", "#e8e6df", 0.5),
                    board=_mat("maple_board", "#dcae6b", 0.35), neck=_mat("maple_gloss", "#d6a463", 0.3),
                    inlay=_mat("dot_black", "#141414", 0.4), binding=None)
    # dove
    return dict(body=_mat("dove_top", "#ffffff", 0.2, image=_sunburst()), sides=_mat("dove_cherry", "#6e1a12", 0.2),
                hw=_mat("nickel", "#c9c6bd", 0.2, 0.9), board=_mat("rosewood", "#3a2318", 0.6),
                neck=_mat("dove_neck", "#5c1a11", 0.25), inlay=_mat("mop", "#eef0ea", 0.15),
                binding=_mat("binding_aged", "#e6dcc0", 0.35), black=_mat("head_black", "#0e0d0d", 0.2))


def _sunburst():
    """Vintage cherry sunburst: amber centre, through orange, to cherry red
    at the edge (u across the top, v up it)."""
    img = None
    import bpy
    img = bpy.data.images.get("dove_sunburst")
    if img:
        return img

    def px(x, y):
        u, v = x / 63 - 0.5, y / 63 - 0.42
        d = math.sqrt((u / 0.5) ** 2 + (v / 0.62) ** 2)
        if d < 0.45:
            return (0.86, 0.6, 0.26)
        if d < 0.75:
            t = (d - 0.45) / 0.3
            return (0.86 - 0.26 * t, 0.6 - 0.42 * t, 0.26 - 0.16 * t)
        t = min(1.0, (d - 0.75) / 0.2)
        return (0.6 - 0.22 * t, 0.18 - 0.12 * t, 0.1 - 0.05 * t)
    return C.make_image("dove_sunburst", 64, 64, px)


def fret_z(g, n):
    """Height of fret n (0 = nut) on the wall."""
    nut = g["saddle"] + g["scale"]
    return nut - g["scale"] * (1 - 2 ** (-n / 12.0))


def guitar_height(kind):
    g = GUITARS[kind]
    return g["saddle"] + g["scale"] + max(z for _, z in g["head"])


def build(kind, tele_colour="black"):
    g = GUITARS[kind]
    M = colours(kind, tele_colour)
    acoustic = kind == "dove"
    outline = smooth(g["body"]["pts"], g["body"]["sharp"], 3)
    y_back = -0.008
    if acoustic:
        d0, d1 = g["depth"]
        top_z = max(z for _, z in outline)

        def yf(x, z):
            return y_back - (d0 + (d1 - d0) * z / top_z)
        front_at = yf
    else:
        yf = y_back - g["depth"]

        def front_at(x, z):
            return yf
    parts = []
    mats = (M["body"], M.get("sides", M["body"]), M.get("sides", M["body"]))
    parts.append(body("body", outline, yf, y_back, g["round_r"], mats, uv_front=acoustic))

    nut_z = g["saddle"] + g["scale"]
    joint_z = max(z for x, z in g["body"]["pts"] if abs(x) < 0.03)
    face_joint = front_at(0, joint_z)
    # fretboard: top 16 mm proud of an electric's face, 12 mm off the Dove's top
    y_fb = face_joint - (0.012 if acoustic else 0.016)
    z_end = fret_z(g, g["frets"]) - 0.007

    def width(z):
        t = (nut_z - z) / (nut_z - z_end)
        return g["nut_w"] + (g["end_w"] - g["nut_w"]) * t

    board = [(-width(nut_z) / 2, nut_z), (width(nut_z) / 2, nut_z), (width(z_end) / 2, z_end),
             (-width(z_end) / 2, z_end)]
    parts.append(plate("board", board, y_fb, y_fb + 0.006, M["board"]))
    # the neck behind the board, down to the heel
    heel_z = (joint_z - 0.085) if not acoustic else joint_z
    neck_pts = [(-width(nut_z) / 2, nut_z), (width(nut_z) / 2, nut_z), (width(heel_z) / 2 + 0.001, heel_z),
                (-width(heel_z) / 2 - 0.001, heel_z)]
    neck_back = y_fb + (0.027 if g["strings"] == 6 else 0.03)
    neck = plate("neck", neck_pts, y_fb + 0.006, neck_back, M["neck"])
    _round_neck(neck, y_fb + 0.006, neck_back)
    parts.append(neck)
    if acoustic:
        # heel and the neck block it meets on the top
        parts.append(plate("heel", rounded_rect(0, joint_z - 0.004, width(joint_z) + 0.006, 0.02, 0.008),
                           y_fb + 0.006, front_at(0, joint_z) + 0.002, M["neck"]))
    if M.get("binding"):
        for s in (-1, 1):
            parts.append(plate("board_binding", [(s * width(nut_z) / 2, nut_z), (s * (width(nut_z) / 2 + 0.0016), nut_z),
                                                 (s * (width(z_end) / 2 + 0.0016), z_end), (s * width(z_end) / 2, z_end)],
                               y_fb - 0.0002, y_fb + 0.006, M["binding"]))
        parts.append(plate("board_binding", [(-width(z_end) / 2 - 0.0016, z_end), (width(z_end) / 2 + 0.0016, z_end),
                                             (width(z_end) / 2 + 0.0016, z_end - 0.0016),
                                             (-width(z_end) / 2 - 0.0016, z_end - 0.0016)],
                           y_fb - 0.0002, y_fb + 0.006, M["binding"]))
    fret_mat = _mat("fretwire", "#c8c6bf", 0.25, 0.9)
    for n in range(1, g["frets"] + 1):
        z = fret_z(g, n)
        w = width(z) / 2
        parts.append(box((-w, y_fb - 0.0013, z - 0.0011), (w, y_fb, z + 0.0011), fret_mat, "fret"))
    parts += _inlays(kind, g, M, y_fb, width)
    parts.append(box((-width(nut_z) / 2, y_fb - 0.0035, nut_z - 0.002), (width(nut_z) / 2, y_fb + 0.006, nut_z + 0.003),
                     _mat("nut", "#ece6d6", 0.35), "nut"))
    head_parts, posts = _headstock(kind, g, M, nut_z, y_fb)
    parts += head_parts
    hw_parts, saddle = _hardware(kind, g, M, front_at, outline, y_fb)
    parts += hw_parts
    parts += _strings(g, nut_z, y_fb, saddle, posts, width)
    parts += _hanger(nut_z, posts)
    return parts


def _round_neck(o, y0, y1):
    """Pull the back corners of the neck in so it reads round, not square."""
    for v in o.data.vertices:
        if abs(v.co.y - y1) < 1e-6:
            v.co.x *= 0.62


def _inlays(kind, g, M, y_fb, width):
    out = []
    marks = {"tele": (3, 5, 7, 9, 12, 15, 17, 19, 21), "jazzmaster": (3, 5, 7, 9, 12, 15, 17, 19, 21),
             "jbass": (3, 5, 7, 9, 12, 15, 17, 19), "dove": (1, 3, 5, 7, 9, 12, 15, 17)}[kind]
    y0, y1 = y_fb - 0.0003, y_fb + 0.002
    for n in marks:
        za, zb = fret_z(g, n - 1), fret_z(g, n)
        zc = (za + zb) / 2
        h = za - zb
        if kind == "tele":
            w = width(zc) * 0.78
            hh = h * 0.31
            out.append(plate("inlay", [(-w / 2, zc - hh), (w / 2, zc - hh), (w / 2, zc + hh), (-w / 2, zc + hh)],
                             y0, y1, M["inlay"]))
        elif kind == "dove":
            w = width(zc) * 0.74
            hh, sk = h * 0.34, h * 0.14
            out.append(plate("inlay", [(-w / 2, zc - hh / 2 - sk), (w / 2, zc - hh / 2 + sk),
                                       (w / 2, zc + hh / 2 + sk), (-w / 2, zc + hh / 2 - sk)], y0, y1, M["inlay"]))
        else:
            r = 0.0032 if kind != "jbass" else 0.0035
            for x in ((-0.0085, 0.0085) if n == 12 else (0,)):
                out.append(disc(r, x, zc, y0, y1, M["inlay"], 10, "dot"))
    return out


def _headstock(kind, g, M, nut_z, y_fb):
    """Headstock, tuners and string trees. Returns (parts, string post
    positions (x, z, y) in order bass to treble)."""
    out = []
    pts = [(x, nut_z + z) for x, z in smooth(g["head"], (0, len(g["head"]) - 1), 4)]
    posts = []
    if kind == "dove":
        # Gibson head: 14 degrees back toward the wall; built flat then tilted
        face = y_fb + 0.002
        head = plate("head", pts, face, face + 0.014, M["black"], M["neck"])
        veneer_tilt = math.radians(14)
        objs = [head]
        # bell truss-rod cover with a white edge
        bell = smooth([(-0.006, 0.014), (0.006, 0.014), (0.011, 0.04), (0.012, 0.052), (0.0, 0.056),
                       (-0.012, 0.052), (-0.011, 0.04)], (), 3)
        objs.append(plate("trc_edge", [(x * 1.12, nut_z + z * 1.04) for x, z in bell], face - 0.0012, face, M["binding"]))
        objs.append(plate("trc", [(x, nut_z + z) for x, z in bell], face - 0.0022, face - 0.0012, M["black"]))
        tuner_z = (0.058, 0.098, 0.138)
        for s, side in ((-1, "bass"), (1, "treble")):
            for z in tuner_z:
                px, pz = s * 0.031, nut_z + z
                objs.append(disc(0.0055, px, pz, face - 0.003, face, M["hw"], 8, "bushing"))
                objs.append(disc(0.003, px, pz, face - 0.016, face, M["hw"], 6, "post"))
                # Grover keystone buttons out to each side, behind the head
                objs.append(box((s * 0.046, face + 0.008, pz - 0.0025), (s * 0.058, face + 0.012, pz + 0.0025), M["hw"], "shaft"))
                objs.append(plate("keystone", [(s * 0.056, pz - 0.006), (s * 0.072, pz - 0.009), (s * 0.072, pz + 0.009),
                                               (s * 0.056, pz + 0.006)], face + 0.006, face + 0.014, M["hw"]))
        for o in objs:
            C.apply_transform(o)
            o.data.transform(_tilt_about(nut_z, y_fb, veneer_tilt))
        out += objs
        order = [(-0.031, 0.138), (-0.031, 0.098), (-0.031, 0.058), (0.031, 0.058), (0.031, 0.098), (0.031, 0.138)]
        for x, z in order:
            p = _tilt_about(nut_z, y_fb, veneer_tilt) @ Vector((x, face - 0.01, nut_z + z))
            posts.append((p.x, p.z, p.y))
        return out, posts
    # Fender heads: flat, a little below the board, tuners down the bass side
    face = y_fb + 0.004
    if kind == "jbass":
        out.append(plate("head", pts, face, face + 0.014, M["neck"]))
    else:
        # the Gold Edition Tele and the J Mascis both have a matching painted
        # face on the head; the back and edges stay natural maple
        head = plate("head", pts, face, face + 0.014, M["body"], M["neck"])
        head.data.polygons[1].material_index = 1
        out.append(head)
    n = g["strings"]
    if kind == "jbass":
        zs = [0.205, 0.155, 0.105, 0.055]
        for z in zs:
            pz = nut_z + z
            out.append(disc(0.0075, -0.021, pz, face - 0.004, face, M["hw"], 10, "post_base"))
            out.append(disc(0.0042, -0.021, pz, face - 0.02, face, M["hw"], 8, "post"))
            # open-gear housing behind the head, the clover key out to the left
            out.append(box((-0.044, face + 0.014, pz - 0.011), (-0.024, face + 0.03, pz + 0.011), M["hw"], "gear"))
            out.append(plate("clover", rounded_rect(-0.06, pz, 0.026, 0.03, 0.01, segs=2), face + 0.018, face + 0.025, M["hw"]))
            posts.append((-0.021, pz, face - 0.016))
        out.append(plate("tree", rounded_rect(0.002, nut_z + 0.105, 0.012, 0.006, 0.002), face - 0.005, face, M["hw"]))
    else:
        top = max(z for _, z in g["head"])
        zs = [top - 0.024 - i * (top - 0.065) / (n - 1) for i in range(n)]
        for z in zs:
            pz = nut_z + z
            out.append(disc(0.005, -0.026, pz, face - 0.003, face, M["hw"], 8, "bushing"))
            out.append(disc(0.0032, -0.026, pz, face - 0.014, face, M["hw"], 6, "post"))
            out.append(box((-0.044, face + 0.014, pz - 0.006), (-0.03, face + 0.024, pz + 0.006), M["hw"], "gear"))
            out.append(plate("key", rounded_rect(-0.053, pz, 0.016, 0.011, 0.004, segs=2), face + 0.016, face + 0.022, M["hw"]))
            posts.append((-0.026, pz, face - 0.011))
        out.append(plate("tree", rounded_rect(0.006, nut_z + 0.072, 0.01, 0.005, 0.002), face - 0.005, face, M["hw"]))
    return out, posts


def _tilt_about(nut_z, y, angle):
    from mathutils import Matrix
    return (Matrix.Translation((0, y, nut_z)) @ Matrix.Rotation(angle, 4, "X") @
            Matrix.Translation((0, -y, -nut_z)))


def _knob(x, z, y_face, mat, r=0.0095, h=0.016, name="knob"):
    return C.cylinder(name, r, h, segs=10, axis="Y", loc=(x, y_face - h / 2, z), material=mat, r_top=r * 0.82)


def _hardware(kind, g, M, front_at, outline, y_fb):
    out = []
    zs = g["saddle"]
    f = front_at(0, zs)
    black = _mat("pickup_black", "#121212", 0.45)
    pole = _mat("pole", "#b9b9b4", 0.3, 0.8)
    if kind == "tele":
        guard = smooth([(-0.0285, 0.403), (-0.075, 0.393), (-0.115, 0.37), (-0.131, 0.325), (-0.129, 0.27),
                        (-0.12, 0.22), (-0.092, 0.192), (-0.05, 0.184), (0.048, 0.184), (0.074, 0.196),
                        (0.103, 0.218), (0.127, 0.24), (0.13, 0.276), (0.126, 0.31), (0.102, 0.326),
                        (0.066, 0.316), (0.0285, 0.3), (0.0285, 0.403)], (0, 16, 17), 3)
        out.append(plate("guard", guard, f - 0.0015, f, M["guard"], M["guard_edge"]))
        # neck pickup under its cover, just below the end of the board
        out.append(plate("neck_pu", rounded_rect(0, 0.286, 0.068, 0.019, 0.009), f - 0.009, f - 0.0015, M["hw"]))
        # the bridge: a plate with its sides turned up, the slanted bridge
        # pickup, three barrel saddles, strings into the ferrules behind
        bp = rounded_rect(0, 0.132, 0.086, 0.094, 0.008)
        out.append(plate("bridge_plate", bp, f - 0.0015, f, M["hw"]))
        for x0, x1, z0, z1 in ((-0.043, -0.04, 0.09, 0.176), (0.04, 0.043, 0.09, 0.176), (-0.043, 0.043, 0.085, 0.09)):
            out.append(box((x0, f - 0.011, z0), (x1, f - 0.0015, z1), M["hw"], "plate_wall"))
        pu = rounded_rect(0, 0.158, 0.07, 0.017, 0.006, math.radians(-7))
        out.append(plate("bridge_pu", pu, f - 0.007, f - 0.0015, black))
        for i in range(6):
            x = -0.026 + i * 0.0105
            out.append(disc(0.002, x, 0.158 + x * math.tan(math.radians(-7)), f - 0.0075, f - 0.006, pole, 6))
        for x in (-0.0175, 0.0, 0.0175):
            out.append(C.cylinder("saddle", 0.0042, 0.016, segs=8, axis="X", loc=(x, f - 0.0075, zs), material=M["hw"]))
        for i in range(6):
            out.append(disc(0.0018, -0.026 + i * 0.0105, 0.097, f - 0.0018, f - 0.0013, black, 6, "ferrule"))
        # control plate along the lower treble edge: switch, volume, tone
        ang = math.radians(-22)
        c = Vector((0.104, 0.162))
        d = Vector((-math.sin(ang), math.cos(ang)))
        out.append(plate("control_plate", rounded_rect(c.x, c.y, 0.026, 0.135, 0.013, ang), f - 0.0015, f, M["hw"]))
        sw = c + d * 0.045
        out.append(box((sw.x - 0.002, f - 0.012, sw.y - 0.004), (sw.x + 0.002, f - 0.0015, sw.y + 0.004), M["hw"], "switch"))
        out.append(C.cylinder("switch_tip", 0.0045, 0.012, segs=8, axis="Y", loc=(sw.x, f - 0.017, sw.y), material=black))
        for t in (0.0, -0.042):
            k = c + d * t
            out.append(_knob(k.x, k.y, f - 0.0015, M["hw"], 0.0095, 0.017))
        return out, zs

    if kind == "jazzmaster":
        guard = smooth([(0.0285, 0.37), (0.052, 0.378), (0.086, 0.396), (0.118, 0.406), (0.14, 0.398),
                        (0.146, 0.37), (0.134, 0.332), (0.118, 0.292), (0.112, 0.258), (0.128, 0.222),
                        (0.149, 0.178), (0.153, 0.132), (0.14, 0.088), (0.112, 0.073), (0.082, 0.09),
                        (0.064, 0.122), (0.05, 0.155), (0.0, 0.158), (-0.05, 0.156), (-0.092, 0.15),
                        (-0.13, 0.138), (-0.157, 0.14), (-0.166, 0.175), (-0.158, 0.215), (-0.138, 0.258),
                        (-0.117, 0.3), (-0.113, 0.335), (-0.126, 0.372), (-0.137, 0.41), (-0.134, 0.45),
                        (-0.113, 0.465), (-0.085, 0.462), (-0.052, 0.452), (-0.0285, 0.448)], (0, 33), 3)
        out.append(plate("guard", guard, f - 0.0015, f, M["guard"], M["guard_edge"]))
        cream = _mat("jm_cover", "#efe6cc", 0.45)
        for z in (0.29, 0.187):
            out.append(plate("pickup", rounded_rect(0, z, 0.089, 0.038, 0.006), f - 0.008, f - 0.0015, cream))
            for i in range(6):
                out.append(disc(0.0022, -0.026 + i * 0.0105, z, f - 0.0085, f - 0.007, pole, 6))
        # Adjusto-Matic bridge on two posts, six threaded saddles
        out.append(box((-0.038, f - 0.016, zs - 0.004), (0.038, f - 0.009, zs + 0.004), M["hw"], "bridge"))
        for x in (-0.037, 0.037):
            out.append(disc(0.0035, x, zs, f - 0.016, f, M["hw"], 6, "bridge_post"))
        for i in range(6):
            out.append(box((-0.029 + i * 0.0116, f - 0.019, zs - 0.0025), (-0.023 + i * 0.0116, f - 0.016, zs + 0.0025),
                           M["hw"], "saddle"))
        # floating vibrato: the tailpiece plate, its lock button and arm
        out.append(plate("vibrato", rounded_rect(0, 0.062, 0.092, 0.058, 0.012), f - 0.004, f, M["hw"]))
        out.append(box((-0.033, f - 0.012, 0.074), (0.033, f - 0.004, 0.082), M["hw"], "string_bar"))
        out.append(disc(0.0035, 0.03, 0.045, f - 0.008, f - 0.004, M["hw"], 6, "lock"))
        arm = [Vector((0.038, 0.06)), Vector((0.06, 0.05)), Vector((0.1, 0.025)), Vector((0.135, 0.018))]
        for a, b in zip(arm, arm[1:]):
            out.append(_bar3((a.x, f - 0.008 - (0.004 if a.x > 0.05 else 0), a.y), (b.x, f - 0.012, b.y), 0.0028, M["hw"]))
        out.append(C.sphere("arm_tip", 0.005, (0.137, f - 0.012, 0.018), _mat("arm_tip", "#efe6cc", 0.4), segs=8, rings=4))
        # lead controls: volume and tone on the lower treble horn, jack below
        for x, z in ((0.122, 0.13), (0.104, 0.098)):
            out.append(_knob(x, z, f - 0.0015, M["hw"], 0.0105, 0.016))
        out.append(disc(0.006, 0.136, 0.098, f - 0.006, f - 0.0015, M["hw"], 8, "jack"))
        # lead/rhythm slide switch plate on the upper treble horn
        out.append(plate("toggle_plate", rounded_rect(0.123, 0.384, 0.03, 0.016, 0.006, math.radians(-25)),
                         f - 0.003, f - 0.0015, M["hw"]))
        out.append(box((0.118, f - 0.007, 0.38), (0.126, f - 0.003, 0.388), black, "toggle"))
        # rhythm circuit on the upper bass horn: plate, two rollers, slider
        ang = math.radians(28)
        out.append(plate("rhythm_plate", rounded_rect(-0.117, 0.43, 0.026, 0.07, 0.008, ang), f - 0.003, f - 0.0015,
                         M["hw"]))
        for t in (-0.018, 0.006):
            p = Vector((-0.117, 0.43)) + Vector((-math.sin(ang), math.cos(ang))) * t
            out.append(C.cylinder("roller", 0.0095, 0.006, segs=12, axis="X", loc=(p.x - 0.006, f - 0.006, p.y),
                                  material=black))
        p = Vector((-0.117, 0.43)) + Vector((-math.sin(ang), math.cos(ang))) * 0.026
        out.append(box((p.x - 0.003, f - 0.007, p.y - 0.002), (p.x + 0.003, f - 0.003, p.y + 0.002), black, "slider"))
        return out, zs

    if kind == "jbass":
        guard = smooth([(0.0285, 0.392), (0.06, 0.405), (0.098, 0.426), (0.128, 0.432), (0.141, 0.418),
                        (0.136, 0.38), (0.12, 0.33), (0.108, 0.29), (0.103, 0.25), (0.078, 0.21), (0.06, 0.17),
                        (0.05, 0.125), (0.0, 0.114), (-0.06, 0.116), (-0.11, 0.122), (-0.145, 0.133),
                        (-0.158, 0.17), (-0.15, 0.215), (-0.126, 0.262), (-0.11, 0.302), (-0.113, 0.342),
                        (-0.13, 0.4), (-0.133, 0.458), (-0.12, 0.49), (-0.093, 0.485), (-0.06, 0.466),
                        (-0.0285, 0.452)], (0, 26), 3)
        out.append(plate("guard", guard, f - 0.0024, f, M["guard"], M["guard_edge"]))
        for z, ang in ((0.243, 0.0), (0.133, math.radians(-3))):
            out.append(plate("pickup", rounded_rect(0, z, 0.096, 0.019, 0.0094, ang), f - 0.009, f - 0.0024, black))
            for i in range(4):
                x = -0.0285 + i * 0.019
                for dx in (-0.004, 0.004):
                    out.append(disc(0.0019, x + dx, z + (x + dx) * math.tan(ang), f - 0.0095, f - 0.008, pole, 6))
        # bridge: a bent chrome plate, four saddles, strings through the back
        out.append(plate("bridge_plate", rounded_rect(0, 0.075, 0.074, 0.072, 0.004), f - 0.0015, f, M["hw"]))
        out.append(box((-0.037, f - 0.015, 0.04), (0.037, f - 0.0015, 0.044), M["hw"], "bridge_back"))
        for i in range(4):
            x = -0.0285 + i * 0.019
            out.append(C.cylinder("saddle", 0.0045, 0.013, segs=8, axis="X", loc=(x, f - 0.009, zs), material=M["hw"]))
            out.append(disc(0.0015, x, 0.05, f - 0.002, f - 0.0014, black, 6, "ferrule"))
        # chrome control plate on the lower treble bout, three black knobs
        ang = math.radians(-27)
        c = Vector((0.106, 0.128))
        d = Vector((-math.sin(ang), math.cos(ang)))
        out.append(plate("control_plate", rounded_rect(c.x, c.y, 0.034, 0.142, 0.017, ang), f - 0.0015, f, M["hw"]))
        knob_mat = _mat("knob_black", "#141414", 0.35)
        for t in (0.046, 0.012, -0.03):
            k = c + d * t
            out.append(_knob(k.x, k.y, f - 0.0015, knob_mat, 0.0115, 0.018))
        j = c + d * -0.06
        out.append(disc(0.0065, j.x, j.y, f - 0.006, f - 0.0015, M["hw"], 8, "jack"))
        return out, zs

    # the Dove
    hole_z = 0.393
    for r, mat, d in ((0.064, M["binding"], 0.0004), (0.0605, M["black"], 0.0006), (0.0575, M["binding"], 0.0008)):
        out.append(_on_top(plate("rosette", ellipse(0, hole_z, r, r, 24), -d, 0.0, mat), front_at))
    out.append(_on_top(plate("soundhole", ellipse(0, hole_z, 0.0508, 0.0508, 24), -0.001, 0.0,
                             _mat("hole_dark", "#060504", 0.9)), front_at))
    # top binding: a narrow cream band all round the edge
    outline_b = smooth(GUITARS["dove"]["body"]["pts"], (), 3)
    ring_in = inset(outline_b, 0.006)
    verts, faces = [], []
    n = len(outline_b)
    for (x, z), (xi, zi) in zip(outline_b, ring_in):
        verts.append((x, front_at(x, z) - 0.0004, z))
        verts.append((xi, front_at(xi, zi) - 0.0004, zi))
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
    bind = C.mesh_obj("binding", verts, faces, M["binding"])
    _fix(bind)
    out.append(bind)
    # the dove pickguard: tortoise, round the treble side of the hole and
    # down toward the bridge, a pearl dove inlaid in it
    tort = _mat("tortoise", "#3a1d0f", 0.3, image=_tortoise())
    guard = smooth([(0.03, 0.452), (0.05, 0.43), (0.059, 0.4), (0.053, 0.368), (0.036, 0.344), (0.03, 0.312),
                    (0.044, 0.275), (0.075, 0.258), (0.106, 0.262), (0.122, 0.292), (0.124, 0.332),
                    (0.114, 0.372), (0.094, 0.414), (0.066, 0.446)], (), 4)
    out.append(_on_top(plate("guard", guard, -0.0012, 0.0, tort), front_at))
    out.append(_on_top(plate("dove_inlay", _dove_shape(0.083, 0.318, 0.058, 1), -0.0018, -0.0011, M["inlay"]),
                       front_at))
    # the moustache bridge, two pearl doves in its wings, slanted saddle, pins
    rose = _mat("bridge_rose", "#2d1a12", 0.5)
    bz = zs - 0.006
    bridge = smooth([(-0.096, bz + 0.012), (-0.074, bz + 0.004), (-0.05, bz + 0.012), (-0.043, bz + 0.017),
                     (0.043, bz + 0.017), (0.05, bz + 0.012), (0.074, bz + 0.004), (0.096, bz + 0.012),
                     (0.088, bz - 0.003), (0.064, bz - 0.011), (0.043, bz - 0.014), (-0.043, bz - 0.014),
                     (-0.064, bz - 0.011), (-0.088, bz - 0.003)], (0, 7), 3)
    fb = front_at(0, bz)
    out.append(plate("bridge", bridge, fb - 0.009, fb + 0.0005, rose))
    for s in (-1, 1):
        out.append(plate("bridge_dove", _dove_shape(s * 0.068, bz + 0.003, 0.03, s), fb - 0.0095, fb - 0.0085,
                         M["inlay"]))
    out.append(strip((-0.037, zs - 0.0025), (0.037, zs + 0.0015), 0.0028, fb - 0.0125, fb - 0.009,
                     _mat("bone", "#efe8d6", 0.35), "saddle"))
    pin = _mat("pin", "#ece6d6", 0.4)
    dot = _mat("pin_dot", "#1a1a1a", 0.4)
    for i in range(6):
        x = -0.026 + i * 0.0105
        out.append(disc(0.0028, x, bz - 0.009, fb - 0.0115, fb - 0.009, pin, 8, "pin"))
        out.append(disc(0.0011, x, bz - 0.009, fb - 0.0118, fb - 0.0115, dot, 6, "pin_dot"))
    return out, zs


def _on_top(o, front_at):
    """Lay a part built at y=0 onto the sloping top."""
    for v in o.data.vertices:
        v.co.y += front_at(v.co.x, v.co.z)
    return o


def _bar3(a, b, r, mat):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder("bar", r, d.length, segs=6, loc=(0, 0, 0), material=mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (a + b) / 2
    return o


def _dove_shape(cx, cz, size, facing=1):
    """A flying dove in profile (head toward +X when facing is 1)."""
    pts = [(-0.5, -0.12), (-0.28, -0.02), (-0.12, 0.02), (-0.02, 0.26), (0.08, 0.5), (0.12, 0.22),
           (0.18, 0.08), (0.34, 0.1), (0.44, 0.06), (0.5, 0.02), (0.4, -0.04), (0.2, -0.1), (0.0, -0.16),
           (-0.2, -0.14), (-0.42, -0.24)]
    return [(cx + facing * x * size, cz + z * size) for x, z in pts]


def _tortoise():
    import bpy
    img = bpy.data.images.get("tortoise")
    if img:
        return img
    rnd = random.Random(7)
    blobs = [(rnd.random() * 32, rnd.random() * 32, 2 + rnd.random() * 4) for _ in range(14)]

    def px(x, y):
        v = 0.0
        for bx_, by_, r in blobs:
            d = math.hypot(x - bx_, y - by_)
            v = max(v, 1 - d / r)
        return (0.16 + 0.45 * v, 0.07 + 0.2 * v, 0.03 + 0.05 * v)
    return C.make_image("tortoise", 32, 32, px)


def _strings(g, nut_z, y_fb, saddle_z, posts, width):
    n = g["strings"]
    bass = n == 4
    steel = _mat("string_steel", "#cfcfc9", 0.25, 0.9)
    wound = _mat("string_wound", "#b9aa86", 0.35, 0.8) if g is GUITARS["dove"] else steel
    out = []
    span_nut = width(nut_z) - (0.007 if not bass else 0.008)
    span_saddle = (0.0525 if not bass else 0.057)
    y = y_fb - 0.0026
    for i in range(n):
        t = i / (n - 1)
        xn = -span_nut / 2 + span_nut * t
        xs = -span_saddle / 2 + span_saddle * t
        th = (0.0012 - 0.0006 * t) if not bass else (0.0024 - 0.001 * t)
        mat = wound if (i < 4 and not bass) else steel
        out.append(_string((xs, y - 0.002, saddle_z), (xn, y, nut_z), th, mat))
        px, pz, py = posts[i]
        out.append(_string((xn, y, nut_z), (px, py, pz), th, mat))
    return out


def _string(a, b, th, mat):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.box("string", (th, th, d.length), (0, 0, 0), mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (a + b) / 2
    return o


def _hanger(nut_z, posts):
    """Wall hanger: a timber block on the wall and a padded yoke under the
    headstock, just above the nut."""
    wood = _mat("hanger_wood", "#5a3a26", 0.7)
    blackm = _mat("hanger_black", "#141414", 0.6)
    z = nut_z + 0.012
    back = max(p[2] for p in posts) + 0.027      # the back of the headstock
    return [C.box_minmax("hanger_block", (-0.035, -0.012, z - 0.06), (0.035, 0.0, z + 0.02), wood),
            C.cylinder("hanger_arm", 0.006, abs(back) - 0.012, segs=6, axis="Y",
                       loc=(0, (back - 0.012) / 2, z), material=blackm)] + \
        [C.cylinder("hanger_fork", 0.006, 0.03, segs=6, axis="Y", loc=(s * 0.029, back - 0.015, z + 0.004),
                    material=blackm) for s in (-1, 1)]
