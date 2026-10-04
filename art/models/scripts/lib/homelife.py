"""Home life: the courtyard cat, its bowl, plant cuttings that grow, and a
watering can.

Every function returns (meshes, sockets): meshes is a dict of node name ->
parts (authored like furniture.py: front toward -Y, origin at the base
centre, metres) and sockets a dict of empty name -> location.

The cat comes as four poses in one file (Pose_Sit, Pose_Loaf, Pose_Sleep,
Pose_Walk) that share the origin; the game shows one at a time. Each pose
has a Head_<pose> empty to look at or pet. The plants likewise come as
Stage_1 (a cutting), Stage_2 (young) and Stage_3 (grown, in flower).
"""
import math
import random

from mathutils import Vector

from . import common as C
from . import furniture as F

bx, cyl = F.bx, F.cyl


def _m(name, col, rough=0.7, metal=0.0):
    return C.mat("HL_" + name, col, rough=rough, metal=metal)


def _cat_mats():
    return {
        "fur": _m("Ginger", "#c06a2b", 0.95),
        "stripe": _m("GingerDark", "#8f4517", 0.95),
        "white": _m("CatWhite", "#ece4d4", 0.95),
        "pink": _m("CatNose", "#c98a86", 0.6),
        "eye": _m("CatEye", "#b8b23a", 0.15),
        "pupil": _m("CatPupil", "#141414", 0.2),
        "inner": _m("EarInner", "#b9837a", 0.9),
    }


def _ell(c, r, mat, rot=(0, 0, 0), segs=10, rings=6):
    o = C.sphere("f", 1.0, (0, 0, 0), mat, segs=segs, rings=rings, scale=r)
    o.rotation_euler = rot
    o.location = c
    return o


def _stripes(o, stripe, axis=1, period=0.05, duty=0.4, phase=0.0, min_nz=-0.1):
    """Tabby bands painted onto o's faces (no extra geometry): faces whose
    centre falls in the band along axis (in object-placed space) and that
    face up or sideways get the stripe material."""
    from mathutils import Matrix
    m = Matrix.LocRotScale(o.location, o.rotation_euler, o.scale)
    rot = o.rotation_euler.to_matrix()
    o.data.materials.append(stripe)
    idx = len(o.data.materials) - 1
    for poly in o.data.polygons:
        c = m @ poly.center
        n = rot @ poly.normal
        if n.z < min_nz:
            continue
        if ((c[axis] + phase) / period) % 1.0 < duty:
            poly.material_index = idx
    return o


def _limb(a, b, r0, r1, mat, segs=6):
    """Tapered cylinder from a to b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder("f", r0, d.length, segs=segs, material=mat, r_top=r1)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.location = (a + b) / 2
    return o


def _chain(pts, r0, r1, mat, mat_tip=None):
    """A tail: tapered segments with a ball at every joint so it never
    shows a gap at the bends."""
    parts, n = [], len(pts) - 1
    for i in range(n):
        ra = r0 + (r1 - r0) * i / n
        rb = r0 + (r1 - r0) * (i + 1) / n
        m = mat_tip if (mat_tip and i == n - 1) else mat
        parts.append(_limb(pts[i], pts[i + 1], ra, rb, m))
        parts.append(_ell(pts[i + 1], (rb, rb, rb), m, segs=6, rings=4))
    return parts


def _head(c, M, yaw=0.0, tilt=0.0, asleep=False):
    """Head centred at c, face toward -Y turned by yaw (radians, about Z)
    and nodded by tilt (about X). Returns the parts."""
    parts = []
    local = []
    local.append(((0, 0, 0), (0.052, 0.050, 0.046), M["fur"]))            # skull
    local.append(((0, -0.036, -0.016), (0.030, 0.024, 0.022), M["white"]))  # muzzle
    local.append(((0, -0.058, -0.004), (0.007, 0.005, 0.006), M["pink"]))   # nose
    local.append(((0, 0.006, 0.040), (0.026, 0.030, 0.010), M["stripe"]))   # forehead M
    for sx in (-1, 1):
        local.append(((sx * 0.038, -0.006, -0.012), (0.024, 0.030, 0.026), M["fur"]))  # cheeks
        if asleep:
            local.append(((sx * 0.021, -0.041, 0.010), (0.011, 0.004, 0.0025), M["stripe"]))
        else:
            local.append(((sx * 0.021, -0.039, 0.011), (0.011, 0.006, 0.010), M["eye"]))
            local.append(((sx * 0.021, -0.0445, 0.011), (0.0025, 0.002, 0.008), M["pupil"]))
    rot = Vector((tilt, 0, yaw))
    from mathutils import Euler
    R = Euler(rot).to_matrix()
    cv = Vector(c)
    for off, r, m in local:
        o = _ell(tuple(cv + R @ Vector(off)), r, m, rot=tuple(rot), segs=8, rings=5)
        parts.append(o)
    for sx in (-1, 1):
        # ears: a three-sided pyramid with a pink inner face
        base = [Vector((sx * 0.014, 0.006, 0.034)), Vector((sx * 0.046, 0.012, 0.022)),
                Vector((sx * 0.030, 0.026, 0.030))]
        tip = Vector((sx * 0.034, 0.010, 0.074))
        vs = [tuple(cv + R @ v) for v in base + [tip]]
        o = C.mesh_obj("ear", vs, [(0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3)], M["fur"])
        o.data.materials.append(M["inner"])
        o.data.polygons[1].material_index = 1
        parts.append(o)
    return parts


def _paw(c, M, length=0.04):
    return _ell(c, (0.016, length / 2, 0.012), M["white"], segs=6, rings=4)


def _body(c, r, M, rot=(0, 0, 0), axis=1, period=None, phase=None, segs=12, rings=11):
    """A furry ellipsoid of radii r (world x, y, z) whose rings run across
    axis, every other ring painted as a tabby band on the top and sides
    (the belly stays plain)."""
    rx, ry, rz = r
    if axis == 1:
        local, pole = (rx, rz, ry), (-math.pi / 2, 0, 0)
    elif axis == 0:
        local, pole = (rz, ry, rx), (0, math.pi / 2, 0)
    else:
        local, pole = (rx, ry, rz), (0, 0, 0)
    o = C.sphere("f", 1.0, (0, 0, 0), M["fur"], segs=segs, rings=rings, scale=local)
    from mathutils import Euler
    R = Euler(rot).to_matrix() @ Euler(pole).to_matrix()
    o.rotation_euler = R.to_euler()
    o.location = c
    o.data.materials.append(M["stripe"])
    for i, poly in enumerate(o.data.polygons):
        band = 0 if i < segs else min(rings - 1, 1 + (i - segs) // segs)
        if band % 2 == 0 or band in (0, rings - 1) or (R @ poly.normal).z < -0.15:
            continue
        poly.material_index = 1
    return o


def cat_sit():
    M = _cat_mats()
    p = []
    p.append(_body((0, 0.055, 0.085), (0.085, 0.10, 0.085), M, axis=1, period=0.045))   # haunches
    p.append(_body((0, -0.005, 0.165), (0.062, 0.062, 0.11), M, rot=(math.radians(-20), 0, 0),
                   axis=2, period=0.05, phase=0.01))
    p.append(_ell((0, -0.045, 0.165), (0.040, 0.030, 0.075), M["white"], rot=(math.radians(-20), 0, 0)))
    for sx in (-1, 1):
        p.append(_body((sx * 0.060, 0.06, 0.07), (0.030, 0.075, 0.06), M, axis=1, period=0.04))  # thigh
        p.append(_ell((sx * 0.05, -0.0, 0.012), (0.018, 0.045, 0.012), M["white"]))  # hind foot
        p.append(_limb((sx * 0.026, -0.045, 0.012), (sx * 0.024, -0.035, 0.17), 0.015, 0.019, M["fur"]))
        p.append(_paw((sx * 0.026, -0.06, 0.012), M))
    head_c = (0, -0.045, 0.285)
    p += _head(head_c, M)
    tail = [(0.05, 0.14, 0.02), (0.09, 0.08, 0.012), (0.10, 0.0, 0.012), (0.08, -0.07, 0.012),
            (0.03, -0.11, 0.014)]
    p += _chain(tail, 0.017, 0.012, M["fur"], M["stripe"])
    return p, {"Head_Sit": head_c}


def cat_loaf():
    M = _cat_mats()
    p = []
    p.append(_body((0, 0.03, 0.085), (0.092, 0.15, 0.085), M, axis=1, period=0.05))
    p.append(_ell((0, -0.095, 0.072), (0.062, 0.045, 0.062), M["white"]))
    for sx in (-1, 1):
        p.append(_paw((sx * 0.03, -0.13, 0.012), M, 0.03))
    head_c = (0, -0.12, 0.165)
    p += _head(head_c, M, tilt=math.radians(-6))
    tail = [(-0.05, 0.17, 0.02), (-0.095, 0.10, 0.014), (-0.10, 0.0, 0.014), (-0.08, -0.09, 0.014)]
    p += _chain(tail, 0.017, 0.012, M["fur"], M["stripe"])
    return p, {"Head_Loaf": head_c}


def cat_sleep():
    """Curled up nose to tail, as on the end of the bed: a round cushion of
    cat, chin resting on the tail at the front edge."""
    M = _cat_mats()
    p = []
    p.append(_body((0, 0.01, 0.062), (0.15, 0.13, 0.066), M, axis=0, period=0.05))
    p.append(_body((-0.045, 0.045, 0.085), (0.095, 0.085, 0.07), M, axis=0, period=0.05, phase=0.02))
    tail = []
    for a in range(-10, 200, 30):
        t = math.radians(-a)
        tail.append((math.cos(t) * 0.155, math.sin(t) * 0.14 + 0.005, 0.02))
    p += _chain(tail, 0.019, 0.013, M["fur"], M["stripe"])
    head_c = (0.05, -0.10, 0.07)
    p += _head(head_c, M, yaw=math.radians(25), tilt=math.radians(-8), asleep=True)
    for sx in (-0.02, 0.025):
        p.append(_paw((head_c[0] + sx - 0.06, -0.13, 0.03), M, 0.035))
    return p, {"Head_Sleep": head_c}


def cat_walk():
    M = _cat_mats()
    p = []
    p.append(_body((0, 0.02, 0.20), (0.068, 0.17, 0.072), M, axis=1, period=0.05))
    p.append(_ell((0, -0.115, 0.185), (0.045, 0.045, 0.06), M["white"]))
    # mid-stride: one diagonal pair forward, the other back
    legs = [(-1, -0.10, 0.04), (1, -0.10, -0.03), (-1, 0.12, -0.035), (1, 0.12, 0.04)]
    for sx, y, swing in legs:
        top = (sx * 0.035, y, 0.17)
        knee = (sx * 0.036, y + swing * 0.5 + (0.02 if y > 0 else 0), 0.085)
        foot = (sx * 0.035, y + swing, 0.012)
        p.append(_limb(top, knee, 0.024, 0.017, M["fur"]))
        p.append(_ell(knee, (0.017, 0.017, 0.017), M["fur"], segs=6, rings=4))
        p.append(_limb(knee, foot, 0.016, 0.013, M["fur"] if y > 0 else M["white"]))
        p.append(_paw(foot, M))
    head_c = (0, -0.19, 0.27)
    p.append(_limb((0, -0.12, 0.22), head_c, 0.04, 0.035, M["fur"], 8))   # neck
    p += _head(head_c, M, tilt=math.radians(5))
    tail = [(0, 0.17, 0.23), (0, 0.23, 0.30), (0, 0.25, 0.38), (0, 0.23, 0.45), (0, 0.19, 0.48)]
    p += _chain(tail, 0.018, 0.012, M["fur"], M["stripe"])
    return p, {"Head_Walk": head_c}


def cat():
    meshes, sockets = {}, {}
    for name, fn in (("Pose_Sit", cat_sit), ("Pose_Loaf", cat_loaf),
                     ("Pose_Sleep", cat_sleep), ("Pose_Walk", cat_walk)):
        parts, s = fn()
        meshes[name] = parts
        sockets.update(s)
    return meshes, sockets


def _lathe(profile, mat, segs=16):
    """Revolve (r, z) points about Z into a closed-top-to-bottom shell."""
    vs, fs, n = [], [], len(profile)
    for i in range(segs):
        a = 2 * math.pi * i / segs
        for r, z in profile:
            vs.append((math.cos(a) * r, math.sin(a) * r, z))
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(n - 1):
            fs.append((i * n + k, j * n + k, j * n + k + 1, i * n + k + 1))
    vs.append((0, 0, profile[0][1]))
    vs.append((0, 0, profile[-1][1]))
    for i in range(segs):
        j = (i + 1) % segs
        fs.append((len(vs) - 2, j * n, i * n))
        fs.append((len(vs) - 1, i * n + n - 1, j * n + n - 1))
    o = C.mesh_obj("lathe", vs, fs, mat)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def cat_bowl():
    """A glazed bowl with a separate Food mesh to hide once it's eaten."""
    bowl = _m("BowlGlaze", "#3f6f8f", 0.25)
    inside = _m("BowlInside", "#e9e5da", 0.25)
    food = _m("Biscuits", "#7a4a26", 0.9)
    o = _lathe([(0.062, 0.0), (0.085, 0.045), (0.074, 0.047), (0.058, 0.012)], bowl)
    # glaze the inner wall and floor cream
    o.data.materials.append(inside)
    for poly in o.data.polygons:
        if poly.normal.z > 0.3 and poly.center.z < 0.04:
            poly.material_index = 1
        elif poly.center.z > 0.01 and (poly.center.x ** 2 + poly.center.y ** 2) ** 0.5 < 0.07 \
                and poly.normal.z > -0.2 and poly.center.z < 0.046:
            poly.material_index = 1
    p = [o]
    rnd = random.Random(5)
    f = [_ell((0, 0, 0.012), (0.05, 0.05, 0.02), food, segs=10, rings=4)]
    for _ in range(16):
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 0.04)
        z = 0.012 + 0.02 * math.sqrt(max(0.0, 1 - (r / 0.05) ** 2))
        f.append(_ell((math.cos(a) * r, math.sin(a) * r, z), (0.008, 0.008, 0.005), food,
                      segs=5, rings=3))
    return {"CatBowl": p, "Food": f}, {}


def watering_can():
    """A galvanised two-gallon can with a brass rose, spout toward -Y."""
    zinc = _m("Galvanised", "#a6abad", 0.45, 0.8)
    brass = _m("Brass", "#b08d45", 0.35, 0.9)
    p = [cyl(0.10, 0.24, (0, 0.03, 0.12), zinc, 14, r_top=0.085),
         cyl(0.088, 0.012, (0, 0.03, 0.246), zinc, 14)]
    p.append(_limb((0, -0.045, 0.05), (0, -0.30, 0.30), 0.02, 0.011, zinc))
    p.append(_limb((0, -0.30, 0.30), (0, -0.33, 0.32), 0.012, 0.03, brass, segs=10))
    # carry handle over the top and a back handle for pouring
    arc = [(0, 0.03 + 0.07 * math.cos(math.radians(a)), 0.25 + 0.09 * math.sin(math.radians(a)))
           for a in range(0, 181, 30)]
    p += _chain(arc, 0.008, 0.008, zinc)
    back = [(0, 0.12, 0.06), (0, 0.17, 0.10), (0, 0.17, 0.18), (0, 0.11, 0.22)]
    p += _chain(back, 0.008, 0.008, zinc)
    return {"WateringCan": p}, {"Spout": (0, -0.335, 0.322)}


# ------------------------------------------------------------------ plants

def _plant_mats():
    return {
        "pot": _m("Terracotta", "#b5603a", 0.9),
        "soil": _m("Soil", "#3b2a1e", 1.0),
        "jar": _m("JarGlass", "#cfe3e0", 0.08),
        "water": _m("JarWater", "#9cc4c4", 0.05),
        "stem": _m("Stem", "#5f6b3a", 0.8),
        "bark": _m("FrangiBark", "#8b8a78", 0.9),
        "leaf": _m("Leaf", "#3e6b35", 0.7),
        "leaf_grey": _m("LeafGrey", "#6f8a67", 0.8),
        "paw_red": _m("PawRed", "#b8262a", 0.8),
        "paw_green": _m("PawGreen", "#5d8a3a", 0.85),
        "wax": _m("WaxPink", "#d98fb2", 0.6),
        "frangi": _m("FrangiWhite", "#f3efe2", 0.6),
        "frangi_eye": _m("FrangiYellow", "#e8c23a", 0.6),
    }


def _pot(M, r, h):
    return [cyl(r, h, (0, 0, h / 2), M["pot"], 12, r_top=r * 1.18),
            cyl(r * 1.22, 0.025, (0, 0, h - 0.0125), M["pot"], 12),
            cyl(r * 1.1, 0.004, (0, 0, h - 0.006), M["soil"], 12)]


def _jar(M):
    """A cutting standing in a jar of water on the windowsill."""
    return [cyl(0.04, 0.12, (0, 0, 0.06), M["jar"], 12),
            cyl(0.037, 0.075, (0, 0, 0.040), M["water"], 12)]


def _blade(base, angle, lean, length, width, mat):
    """A strap leaf from base, leaning outward by lean (radians) in direction
    angle; two triangles folded at the midrib."""
    d = Vector((math.cos(angle) * math.sin(lean), math.sin(angle) * math.sin(lean), math.cos(lean)))
    side = Vector((-math.sin(angle), math.cos(angle), 0)) * (width / 2)
    b = Vector(base)
    tip = b + d * length
    mid = b + d * (length * 0.45)
    fold = Vector((0, 0, 0.0)) + d.cross(side).normalized() * (width * 0.25)
    vs = [tuple(b), tuple(mid + side + fold), tuple(tip), tuple(mid - side + fold)]
    o = C.mesh_obj("blade", vs, [(0, 1, 2, 3)], mat)
    mat.use_backface_culling = False
    return o


def kangaroo_paw():
    """Red-and-green kangaroo paw, the Kings Park cutting."""
    M = _plant_mats()
    rnd = random.Random(11)
    st = {}
    # 1: a division with three leaves in a jar
    p = _jar(M)
    for i in range(3):
        p.append(_blade((0, 0, 0.03), i * 2.1, 0.25, 0.20, 0.022, M["leaf"]))
    st["Stage_1"] = p
    # 2: a fan of strap leaves in a small pot
    p = _pot(M, 0.09, 0.15)
    for i in range(9):
        p.append(_blade((rnd.uniform(-0.02, 0.02), rnd.uniform(-0.02, 0.02), 0.14), i * 0.7,
                        rnd.uniform(0.15, 0.45), rnd.uniform(0.25, 0.35), 0.03, M["leaf"]))
    st["Stage_2"] = p
    # 3: flowering, tall red stems with clusters of furry green-tipped paws
    p = _pot(M, 0.13, 0.24)
    for i in range(14):
        p.append(_blade((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), 0.23), i * 0.45,
                        rnd.uniform(0.15, 0.55), rnd.uniform(0.3, 0.45), 0.035, M["leaf"]))
    for i in range(5):
        a = i * 1.26 + rnd.uniform(-0.2, 0.2)
        top = (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.78 + rnd.uniform(-0.1, 0.08))
        p.append(_limb((math.cos(a) * 0.02, math.sin(a) * 0.02, 0.23), top, 0.011, 0.008, M["paw_red"], 5))
        for k in range(5):
            b = a + (k - 2) * 0.55
            fl = (top[0] + math.cos(b) * 0.05, top[1] + math.sin(b) * 0.05, top[2] + 0.02 + k % 2 * 0.02)
            p.append(_limb(top, fl, 0.006, 0.006, M["paw_red"], 4))
            p.append(_limb(fl, (fl[0] + math.cos(b) * 0.015, fl[1] + math.sin(b) * 0.015, fl[2] + 0.055),
                           0.011, 0.007, M["paw_red"], 5))
            tip = (fl[0] + math.cos(b) * 0.02, fl[1] + math.sin(b) * 0.02, fl[2] + 0.07)
            p.append(_ell(tip, (0.009, 0.009, 0.012), M["paw_green"], segs=5, rings=3))
    st["Stage_3"] = p
    return st, {}


def geraldton_wax():
    """Geraldton wax from the Fremantle nursery: needle leaves and small
    pink waxy flowers."""
    M = _plant_mats()
    rnd = random.Random(23)

    def sprig(base, d, n, length, flowers):
        out = []
        end = tuple(Vector(base) + Vector(d).normalized() * length)
        out.append(_limb(base, end, 0.005, 0.003, M["stem"], 4))
        for k in range(n):
            t = (k + 1) / (n + 1)
            c = Vector(base) + (Vector(end) - Vector(base)) * t
            # a tuft of needles either side of the stem
            for j in range(3):
                a = rnd.uniform(0, 2 * math.pi)
                off = Vector((math.cos(a) * 0.018, math.sin(a) * 0.018, rnd.uniform(-0.01, 0.01)))
                out.append(_ell(tuple(c + off), (0.022, 0.013, 0.013), M["leaf_grey"],
                                rot=(0, rnd.uniform(-0.6, 0.6), a), segs=4, rings=3))
            if flowers and k % 2 == 0:
                for j in range(3):
                    a = rnd.uniform(0, 2 * math.pi)
                    off = Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 0.012))
                    out.append(_ell(tuple(c + off), (0.01, 0.01, 0.008), M["wax"], segs=4, rings=3))
        return out

    st = {}
    p = _jar(M) + sprig((0, 0, 0.02), (0.1, 0, 1), 4, 0.22, False)
    st["Stage_1"] = p
    p = _pot(M, 0.09, 0.15)
    for i in range(5):
        a = i * 1.25
        p += sprig((0, 0, 0.14), (math.cos(a) * 0.4, math.sin(a) * 0.4, 1), 4, 0.25, False)
    st["Stage_2"] = p
    p = _pot(M, 0.15, 0.28)
    p.append(_limb((0, 0, 0.27), (0, 0, 0.45), 0.018, 0.012, M["bark"], 6))
    for i in range(11):
        a = i * 2.4 + rnd.uniform(-0.2, 0.2)
        base = (math.cos(a) * 0.02, math.sin(a) * 0.02, 0.32 + rnd.uniform(0, 0.13))
        d = (math.cos(a) * rnd.uniform(0.5, 1.0), math.sin(a) * rnd.uniform(0.5, 1.0), 1)
        p += sprig(base, d, 5, rnd.uniform(0.3, 0.45), True)
    st["Stage_3"] = p
    return st, {}


def frangipani():
    """A frangipani stick off a neglected verge: a bare cutting, then leaves,
    then a forked little tree with white and yellow flowers."""
    M = _plant_mats()
    rnd = random.Random(31)

    def leaves(top, n, size):
        out = []
        for k in range(n):
            a = k * 2 * math.pi / n + rnd.uniform(-0.2, 0.2)
            out.append(_blade(top, a, rnd.uniform(0.9, 1.2), size, size * 0.38, M["leaf"]))
        return out

    def flower(c):
        out = []
        for k in range(5):
            a = k * 2 * math.pi / 5
            out.append(_ell((c[0] + math.cos(a) * 0.026, c[1] + math.sin(a) * 0.026, c[2]),
                            (0.028, 0.015, 0.005), M["frangi"], rot=(0, 0, a), segs=6, rings=3))
        out.append(_ell((c[0], c[1], c[2] + 0.003), (0.01, 0.01, 0.004), M["frangi_eye"], segs=6, rings=3))
        return out

    st = {}
    p = _pot(M, 0.08, 0.13)
    p.append(_limb((0, 0, 0.1), (0, 0, 0.42), 0.022, 0.02, M["bark"], 7))
    p.append(_ell((0, 0, 0.42), (0.02, 0.02, 0.012), M["bark"], segs=7, rings=3))
    st["Stage_1"] = p
    p = _pot(M, 0.11, 0.18)
    p.append(_limb((0, 0, 0.15), (0, 0, 0.55), 0.024, 0.021, M["bark"], 7))
    p += leaves((0, 0, 0.55), 6, 0.2)
    st["Stage_2"] = p
    p = _pot(M, 0.17, 0.3)
    p.append(_limb((0, 0, 0.28), (0, 0, 0.75), 0.034, 0.03, M["bark"], 8))
    for i, a in enumerate((0.3, 2.4, 4.4)):
        top = (math.cos(a) * 0.22, math.sin(a) * 0.22, 1.12 + i * 0.06)
        p.append(_limb((0, 0, 0.73), top, 0.028, 0.022, M["bark"], 7))
        p.append(_ell((0, 0, 0.74), (0.033, 0.033, 0.03), M["bark"], segs=8, rings=4))
        p += leaves(top, 7, 0.24)
        for k in range(4):
            b = k * 1.6 + a
            p.append(_limb(top, (top[0] + math.cos(b) * 0.06, top[1] + math.sin(b) * 0.06, top[2] + 0.11),
                            0.005, 0.004, M["stem"], 4))
            p += flower((top[0] + math.cos(b) * 0.06, top[1] + math.sin(b) * 0.06, top[2] + 0.115))
    st["Stage_3"] = p
    return st, {}


PROPS = {
    "cat": cat,
    "cat_bowl": cat_bowl,
    "watering_can": watering_can,
    "kangaroo_paw": kangaroo_paw,
    "geraldton_wax": geraldton_wax,
    "frangipani": frangipani,
}
