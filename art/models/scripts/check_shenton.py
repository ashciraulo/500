"""Layout audit for the townhouse: run after editing build_shenton.py.

    python3.11 art/models/scripts/check_shenton.py [--plan out/prefix]

Builds the house and its furniture, then reports:
  - furniture blocking a door's swing or its doorway
  - furniture overlapping walls or other furniture
  - rooms you can't walk to from the front door (0.25 m body radius)
With --plan it also renders top-down plans of both floors with every door's
swing drawn in red (prefix_ground.png, prefix_upper.png).
Exits 1 if anything is flagged.
"""
import math
import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_argv = sys.argv
sys.argv = [sys.argv[0]]  # keep build_shenton from seeing our flags

import bpy  # noqa: E402,I001
from mathutils import Vector  # noqa: E402

import build_shenton as B  # noqa: E402
from lib import arch as A  # noqa: E402
from lib import common as C  # noqa: E402

sys.argv = _argv
OPEN_ANGLE = math.radians(100)   # HomeBase.DOOR_OPEN_ANGLE
SLIDE = 1.05
_WALLS = []
FLOORS = {"ground": (B.FZ0, B.CZ0), "upper": (B.FZ1, B.CZ1)}
# things that lie flat or hang high and never block anyone
FLAT = ("Rug", "Gallery", "Pendant", "TV_Screen", "Corkboard", "AC_", "Intercom", "Plant_Hanging", "TowelRail",
        "candle", "Photo_", "Books_", "BedLamp", "Laptop", "DeskLamp", "TableLamp", "CoffeeMachine", "Kettle",
        "Herbs", "Succulent", "Plant_Bath", "Bar_Top", "porch_light", "Balcony_")


# ------------------------------------------------------------------ 2D geometry

def hull(points):
    pts = sorted(set((round(p[0], 4), round(p[1], 4)) for p in points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def overlap(a, b, tol=0.015):
    """Separating-axis test for convex polygons; touching within tol is fine."""
    for poly in (a, b):
        for i in range(len(poly)):
            p, q = poly[i], poly[(i + 1) % len(poly)]
            n = (q[1] - p[1], p[0] - q[0])
            ln = math.hypot(*n) or 1
            n = (n[0] / ln, n[1] / ln)
            pa = [n[0] * x + n[1] * y for x, y in a]
            pb = [n[0] * x + n[1] * y for x, y in b]
            if max(pa) < min(pb) + tol or max(pb) < min(pa) + tol:
                return False
    return True


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# ------------------------------------------------------------------ scene

def footprint(o, zlo=-1e9, zhi=1e9):
    """Convex 2D hull of the object's vertices between zlo and zhi, and its
    full height range."""
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    sel = [v for v in vs if zlo <= v.z <= zhi] or vs
    return hull([(v.x, v.y) for v in sel]), min(v.z for v in vs), max(v.z for v in vs)


def islands(o):
    """World-space vertex lists of the object's separate mesh pieces."""
    me = o.data
    parent = list(range(len(me.vertices)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    groups = {}
    for v in me.vertices:
        groups.setdefault(find(v.index), []).append(o.matrix_world @ v.co)
    return list(groups.values())


def door_info(o):
    """Hinge, closed leaf direction and length, from the leaf's geometry."""
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    h = o.matrix_world.translation
    far = max(vs, key=lambda v: (v.x - h.x) ** 2 + (v.y - h.y) ** 2)
    d = Vector((far.x - h.x, far.y - h.y))
    return Vector((h.x, h.y)), d, min(v.z for v in vs), max(v.z for v in vs)


def swing_polys(o):
    """Polygons the leaf passes through between closed and open."""
    h, d, _, _ = door_info(o)
    if o.name == "Door_Sliding":
        u = d.normalized()
        n = Vector((-u.y, u.x)) * 0.03
        a, b = h, h + d + u * SLIDE
        return [[tuple(a + n), tuple(b + n), tuple(b - n), tuple(a - n)]]
    sign = -1 if d_name(o) in B.OPEN_CLOCKWISE else 1
    polys = []
    steps = 10
    for i in range(steps):
        a0 = OPEN_ANGLE * i / steps
        a1 = OPEN_ANGLE * (i + 1) / steps
        polys.append([tuple(h), tuple(h + rot(d, sign * a0)), tuple(h + rot(d, sign * a1))])
    return polys


def d_name(o):
    return o.name.split(".")[0]


def rot(v, a):
    c, s = math.cos(a), math.sin(a)
    return Vector((v.x * c - v.y * s, v.x * s + v.y * c))


def doorway(o, depth=0.7):
    """Clear zone both sides of the opening the leaf closes."""
    h, d, _, _ = door_info(o)
    u = d.normalized()
    n = Vector((-u.y, u.x))
    a, b = h, h + d
    return [tuple(a + n * depth), tuple(b + n * depth), tuple(b - n * depth), tuple(a - n * depth)]


def floor_of(z):
    return "upper" if z > B.FZ1 - 0.2 else "ground"


def build():
    C.reset()
    C.clear_material_cache()
    A.reset()
    M = B.mats()
    M["granite"] = C.mat("Granite", image=A.tex_granite(), rough=0.35)
    doors = B.house(M)
    walls = []
    for bucket, objs in A._BUCKETS.items():
        if bucket.startswith("House") and "Roof" not in bucket:
            for o in objs:
                fp, z0, z1 = footprint(o)
                # floors, ceilings and thin trim aren't walls
                if z1 - z0 > 1.5:
                    walls.append((fp, z0, z1))
    A.finish()
    items = B.interior(M)
    _WALLS[:] = walls
    return M, doors, walls, items


def audit():
    M, doors, walls, items = build()
    problems = []
    solid = []
    for o in items:
        fp, z0, z1 = footprint(o)
        if o.name.startswith(FLAT) or z0 > floor_z(z0) + 1.0:
            continue
        if o.name.startswith("Curtains"):
            # each drape on its own; the rod runs above the door heads
            for isl in islands(o):
                if max(v.z for v in isl) < z1 - 0.05:
                    solid.append((o.name, hull([(v.x, v.y) for v in isl]), z0, z1))
            continue
        if o.name.startswith("Sofa"):
            # the L couch: its two runs on their own, not the hull across the L
            for isl in islands(o):
                solid.append((o.name, hull([(v.x, v.y) for v in isl]), z0, z1))
            continue
        solid.append((o.name, fp, z0, z1))

    for d in doors:
        h, dv, dz0, dz1 = door_info(d)
        fl = floor_of(dz0)
        zone = swing_polys(d) + [doorway(d, 0.4 if d_name(d) == "Door_Storage" else 0.7)]
        for name, fp, z0, z1 in solid:
            if floor_of(z0) != fl or z0 > dz1 or z1 < dz0 + 0.05:
                continue
            if any(overlap(p, fp) for p in zone):
                problems.append("%s blocks %s" % (name, d.name))

    for i, (n1, f1, a0, a1) in enumerate(solid):
        for fp, z0, z1 in walls:
            if a0 < z1 - 0.02 and a1 > z0 + 0.02 and overlap(f1, fp, tol=0.03):
                problems.append("%s goes into a wall" % n1)
                break
        for n2, f2, b0, b1 in solid[i + 1:]:
            if n1 == n2:
                continue   # pieces of one item (curtain drapes, couch runs)
            if {n1.split("_")[0].split("-")[0], n2.split("_")[0].split("-")[0]} == {"Chair", "Dining"}:
                continue   # chairs tucked under the table
            if a0 < b1 - 0.02 and a1 > b0 + 0.02 and overlap(f1, f2, tol=0.03):
                problems.append("%s overlaps %s" % (n1, n2))

    problems += reach(doors, walls, solid)
    return problems


def floor_z(z):
    return B.FZ1 if z > B.FZ1 - 0.2 else B.FZ0


def reach(doors, walls, solid, cell=0.05, radius=0.25):
    """Flood fill each floor from where you arrive (front door / top of the
    stairs); doors can be pushed either way, so they don't block. Report
    doors whose either side is unreachable."""
    out = []
    starts = {"ground": (0.9, 0.5), "upper": (0.5, 4.6)}
    for fl, (fz, cz) in FLOORS.items():
        obst = [fp for fp, z0, z1 in walls if z0 < fz + 1.0 and z1 > fz + 0.3]
        obst += [fp for _, fp, z0, z1 in solid if floor_z(z0) == fz and z1 > fz + 0.15]
        if fl == "ground":
            # the stairs, apart from their bottom step
            obst.append(rect(0.0, 5.0, 1.0, 8.6))
        nx, ny = int((B.W + 0.4) / cell), int((B.D + 0.4) / cell)
        free = [[True] * ny for _ in range(nx)]
        for poly in obst:
            xs = [p[0] for p in poly]
            ys = [p[1] for p in poly]
            for ix in range(max(0, int((min(xs) - radius + 0.2) / cell)), min(nx, int((max(xs) + radius + 0.2) / cell) + 1)):
                for iy in range(max(0, int((min(ys) - radius + 0.2) / cell)), min(ny, int((max(ys) + radius + 0.2) / cell) + 1)):
                    if free[ix][iy]:
                        x, y = ix * cell - 0.2, iy * cell - 0.2
                        if overlap([(x - radius, y - radius), (x + radius, y - radius), (x + radius, y + radius),
                                    (x - radius, y + radius)], poly, tol=0.0):
                            free[ix][iy] = False
        sx, sy = starts[fl]
        seen = set()
        q = deque([(int((sx + 0.2) / cell), int((sy + 0.2) / cell))])
        while q:
            c = q.popleft()
            if c in seen or not (0 <= c[0] < nx and 0 <= c[1] < ny) or not free[c[0]][c[1]]:
                continue
            seen.add(c)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q.append((c[0] + dx, c[1] + dy))
        if os.environ.get("REACH_MAP"):
            from PIL import Image
            img = Image.new("RGB", (nx, ny))
            for ix in range(nx):
                for iy in range(ny):
                    img.putpixel((ix, ny - 1 - iy), (60, 200, 90) if (ix, iy) in seen else
                                 ((235, 235, 235) if free[ix][iy] else (200, 40, 40)))
            img.resize((nx * 4, ny * 4)).save("%s_%s.png" % (os.environ["REACH_MAP"], fl))
        for d in doors:
            h, dv, dz0, _ = door_info(d)
            if floor_of(dz0) != fl:
                continue
            mid = h + dv / 2
            nrm = Vector((-dv.y, dv.x)).normalized()
            for side in (1, -1):
                p = mid + nrm * side * 0.45
                c = (int((p.x + 0.2) / cell), int((p.y + 0.2) / cell))
                inside = 0 <= p.x <= B.W and 0 <= p.y <= B.D
                if d_name(d) == "Door_Storage" and side < 0:
                    inside = False   # a cupboard: you reach in, you don't walk in
                if inside and c not in seen:
                    out.append("can't walk to the %s side of %s" % ("+" if side > 0 else "-", d.name))
    return out


# ------------------------------------------------------------------ plans

def plans(prefix):
    sc = bpy.context.scene
    C.render_setup((900, 1500), 8, world="#ffffff", strength=1.0)
    sun = C.sun(rot=(0, 0, 0), energy=3.0)
    for lt in bpy.data.lights:
        lt.use_shadow = False
    del sun
    for o in bpy.data.objects:
        if o.name.startswith(("House_Roof", "House_Guard")):
            o.hide_render = True
    red = C.mat("SwingRed", "#e0201a")
    for d in [o for o in bpy.data.objects if o.name.startswith(("Door_", "Shed_Door"))]:
        polys = swing_polys(d)
        _, _, z0, _ = door_info(d)
        for p in polys:
            o = C.mesh_obj("swing", [(x, y, z0 + 0.05) for x, y in p], [tuple(range(len(p)))], red)
            o.name = "SwingArc"
    black = C.mat("WallCut", "#202022")
    for fl, (fz, cz) in FLOORS.items():
        # walls cut at the camera height, drawn solid black
        caps = []
        for fp, z0, z1 in _WALLS:
            if z0 < fz + 1.6 < z1:
                caps.append(C.mesh_obj("cap", [(x, y, fz + 1.65) for x, y in fp], [tuple(range(len(fp)))], black))
        cam = bpy.data.cameras.new("plan")
        cam.type = "ORTHO"
        cam.ortho_scale = B.D + 1.6
        cam.clip_start = 0.01
        cam.clip_end = 20
        o = C.link(bpy.data.objects.new("PlanCam", cam))
        o.location = (B.W / 2, B.D / 2 - 0.4, fz + 1.7)
        sc.camera = o
        C.render("%s_%s.png" % (prefix, fl))
        for c in caps:
            bpy.data.objects.remove(c, do_unlink=True)


if __name__ == "__main__":
    probs = audit()
    for p in probs:
        print("PROBLEM:", p)
    print("%d problems" % len(probs))
    if "--plan" in sys.argv:
        plans(sys.argv[sys.argv.index("--plan") + 1])
    sys.stdout.flush()
    os._exit(1 if probs else 0)
