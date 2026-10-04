"""Building blocks shared by every car: lofted bodies, wheels, lamps, interiors.

A body is a loft through cross-section "stations" along the car's length.
Each station gives a half profile on the +X side (nine points from the
underside centre round to the roof centre) which is mirrored to -X. Faces
are tagged by region (paint, glass, trim, doors) while lofting, the wheel
arches are cut with a boolean, then the shell is split into the separate
nodes the game needs.
"""
import math

import bpy  # noqa: I001  (bpy must load before bmesh)
import bmesh
from mathutils import Vector

from . import common as C

# Tag indices used as temporary material slots on the lofted shell.
T_PAINT, T_GLASS, T_TRIM, T_UNDER, T_DL, T_DR, T_DLG, T_DRG = range(8)
TAG_NAMES = ["Paint", "Glass", "Trim", "Under", "DoorL", "DoorR", "DoorLGlass", "DoorRGlass"]


class Station:
    """One cross-section: y plus a half profile on +X, bottom centre to roof centre."""

    def __init__(self, y, pts):
        self.y = y
        self.pts = pts


def body_station(y, zb, wb, zrock, wrock, zs, wmax, zbelt, wbelt, zrs, wrs, zr, bulge=0.012):
    """Eleven point profile for a modern rounded hatch.

    0 bottom centre, 1 bottom edge, 2 rocker, 3 lower bulge, 4 shoulder (max
    width), 5 upper bulge, 6 belt, 7 window top, 8 roof edge, 9 roof mid,
    10 roof centre.
    """
    lo = ((wrock + wmax) / 2 + bulge, (zrock + zs) / 2)
    hi = ((wmax + wbelt) / 2 + bulge * 0.8, (zs + zbelt) / 2)
    return Station(y, [
        (0.0, zb), (wb, zb), (wrock, zrock), lo, (wmax, zs), hi, (wbelt, zbelt),
        (wrs, zrs), (wrs * 0.9, zr - (zr - zrs) * 0.3), (wrs * 0.5, zr - (zr - zrs) * 0.03),
        (0.0, zr),
    ])


def loft(stations, classify):
    """Return (verts, faces, tags, uvs).

    classify(y0, y1, jseg, side) -> tag, where jseg is the profile segment
    (0 = underside centre strip ... n-2 = roof centre strip) and side is +1/-1.
    UVs: u runs along the car (front 0 -> rear 1), v around the half profile
    (underside 0 -> roof centre 1) on both sides, so one texture covers
    the shell symmetrically.
    """
    npts = len(stations[0].pts)
    ring = 2 * (npts - 1)
    n = len(stations)
    verts, faces, tags, uvs = [], [], [], []
    for st in stations:
        for k in range(ring):
            if k < npts:
                x, z = st.pts[k]
            else:
                x, z = st.pts[2 * (npts - 1) - k]
                x = -x
            verts.append((x, st.y, z))

    def vcoord(k):
        return (k if k < npts else 2 * (npts - 1) - k) / (npts - 1)

    for i in range(n - 1):
        y0, y1 = stations[i].y, stations[i + 1].y
        for k in range(ring):
            k2 = (k + 1) % ring
            a, b = i * ring + k, i * ring + k2
            c, d = (i + 1) * ring + k2, (i + 1) * ring + k
            if k < npts - 1:
                jseg, side = k, 1
            else:
                jseg, side = 2 * (npts - 1) - 1 - k, -1
            faces.append((a, b, c, d))
            tags.append(classify(y0, y1, jseg, side))
            u0, u1 = i / (n - 1), (i + 1) / (n - 1)
            v0 = vcoord(k)
            v1 = vcoord(k2) if k2 != 0 else 0.0
            uvs.append(((u0, v0), (u0, v1), (u1, v1), (u1, v0)))
    last = (n - 1) * ring
    for base, u in ((0, 0.0), (last, 1.0)):
        faces.append(tuple(base + k for k in range(ring)))
        tags.append(T_PAINT)
        uvs.append(tuple((u, 0.5) for _ in range(ring)))
    return verts, faces, tags, uvs


def shell_object(name, verts, faces, tags, uvs=None):
    tagmats = [C.mat("tag_" + n) for n in TAG_NAMES]
    obj = C.mesh_obj(name, verts, faces, mats=tagmats, face_mats=tags)
    if uvs:
        layer = obj.data.uv_layers.new(name="UVMap")
        for p, fuv in zip(obj.data.polygons, uvs):
            for li, uv in zip(p.loop_indices, fuv):
                layer.data[li].uv = uv
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def cut_arches(body, axles, radius, x_inner, hub_z):
    """Boolean the wheel arches out of the shell (both sides, each axle).

    x_inner is the inner wall of the wheel tubs: one value, or one per axle
    (the front tubs need to be deeper so the steered wheels clear them)."""
    xs = x_inner if isinstance(x_inner, (tuple, list)) else [x_inner] * len(axles)
    for y, x_in in zip(axles, xs):
        cutter = C.cylinder("arch", radius, 2.4, segs=14, axis="X", loc=(0, y, hub_z))
        inner = C.box("arch_keep", (2 * x_in, 1.0, 1.0), (0, y, hub_z))
        # cutter minus the middle keeps the cabin floor intact
        C.boolean(cutter, inner, "DIFFERENCE")
        cutter.data.materials.clear()
        cutter.data.materials.append(bpy.data.materials["tag_Under"])
        mod = body.modifiers.new("bool", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        with bpy.context.temp_override(object=body, active_object=body):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)


def split_by_tag(obj, groups, smooth_angle=None):
    """groups: {name: {tag_name: material}} -> {name: object}. Deletes obj.

    UVs are carried across. smooth_angle (degrees) shades smooth with hard
    edges above that angle, which reads as rounded at low poly counts.
    """
    me = obj.data
    slot_tag = [m.name[4:] if m and m.name.startswith("tag_") else "Under" for m in me.materials]
    src_uv = me.uv_layers.active.data if me.uv_layers else None
    out = {}
    for gname, tmap in groups.items():
        vmap, verts, faces, fm, mats, fuvs = {}, [], [], [], [], []
        for p in me.polygons:
            t = slot_tag[p.material_index]
            if t not in tmap:
                continue
            m = tmap[t]
            if m not in mats:
                mats.append(m)
            f = []
            for vi in p.vertices:
                if vi not in vmap:
                    vmap[vi] = len(verts)
                    verts.append(tuple(me.vertices[vi].co))
                f.append(vmap[vi])
            faces.append(f)
            fm.append(mats.index(m))
            fuvs.append([tuple(src_uv[li].uv) if src_uv else (0, 0) for li in p.loop_indices])
        if not faces:
            continue
        o = C.mesh_obj(gname, verts, faces, mats=mats, face_mats=fm)
        layer = o.data.uv_layers.new(name="UVMap")
        for p, fuv in zip(o.data.polygons, fuvs):
            for li, uv in zip(p.loop_indices, fuv):
                layer.data[li].uv = uv
        if smooth_angle:
            smooth(o, smooth_angle)
        out[gname] = o
    bpy.data.objects.remove(obj, do_unlink=True)
    return out


def smooth(obj, angle=35):
    me = obj.data
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(angle))


def vertex_normals(obj):
    """{rounded position: normal} of a surface, to solidify the pieces split
    off it along the same directions (so neighbouring pieces' rims run
    side by side instead of crossing)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    out = {_key(v.co): v.normal.copy() for v in bm.verts}
    bm.free()
    return out


def _key(co):
    return (round(co.x, 4), round(co.y, 4), round(co.z, 4))


def solidify_along(obj, thickness, inner_mat, normals, gap=0.0, level=0.0):
    """Like solidify(), but offsets each vertex along normals[position]
    (from vertex_normals() of the surface it was cut from); vertices not
    found fall back to their own normal. Call before moving any vertex.
    gap > 0 first pulls the open border in along the surface by that much
    (a door's shut gap). level > 0 offsets surfaces facing up by less than
    that (normal z in 0..level) straight inward instead, so a door's inner
    skin never dips below its outer edge where it swings past the body."""
    me = obj.data
    me.materials.append(inner_mat)
    mi = len(me.materials) - 1
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    uv = bm.loops.layers.uv.active
    outer = list(bm.faces)
    nrm = {v: normals.get(_key(v.co), v.normal).copy() for v in bm.verts}
    for v, n in nrm.items():
        if 0.0 < n.z < level and n.xy.length > 1e-6:
            n.z = 0.0
            n.normalize()
    if gap:
        moves = {}
        for v in bm.verts:
            bed = [e for e in v.link_edges if e.is_boundary]
            if len(bed) != 2:
                continue
            a, b = (e.other_vert(v).co for e in bed)
            d = nrm[v].cross((b - a).normalized()).normalized()
            inside = sum((f.calc_center_median() for f in v.link_faces), Vector()) / len(v.link_faces) - v.co
            moves[v] = (d if d.dot(inside) > 0 else -d) * gap
        for v, m in moves.items():
            v.co += m
    inner = {}
    for v in list(bm.verts):
        inner[v] = bm.verts.new(v.co - nrm[v] * thickness)
    for f in outer:
        nf = bm.faces.new([inner[lp.vert] for lp in reversed(f.loops)])
        nf.material_index = mi
        nf.smooth = f.smooth
        if uv:
            for lp, src in zip(nf.loops, reversed(f.loops)):
                lp[uv].uv = src[uv].uv
    for e in list(bm.edges):
        if len(e.link_faces) != 1 or e.verts[0] not in inner:
            continue
        f = e.link_faces[0]
        for lp in f.loops:
            if lp.edge == e:
                a, b = lp.vert, lp.link_loop_next.vert
                break
        rf = bm.faces.new([b, a, inner[a], inner[b]])
        rf.material_index = mi
    bm.to_mesh(me)
    bm.free()
    me.update()


def solidify(obj, thickness, inner_mat, rim=True):
    obj.data.materials.append(inner_mat)
    mod = obj.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1
    mod.use_rim = rim
    mod.material_offset = len(obj.data.materials) - 1
    mod.material_offset_rim = len(obj.data.materials) - 1
    mod.use_even_offset = False
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=mod.name)


# ---------------------------------------------------------------- revolve

def revolve(name, profile, segs, material_for, loc=(0, 0, 0), parent=None, axis="X",
            uv_face=None):
    """Revolve (radius, offset) profile points around the X axis.

    material_for(i) -> material for the band between profile[i] and [i+1].
    A closing centre disc is added when the profile starts/ends at r=0.
    uv_face: index of a band whose UVs are planar (for hubcap textures).
    """
    verts, faces, fm, mats = [], [], [], []
    n = len(profile)
    for r, off in profile:
        for s in range(segs):
            a = 2 * math.pi * s / segs
            verts.append((off, math.cos(a) * r, math.sin(a) * r))
    for i in range(n - 1):
        m = material_for(i)
        if m not in mats:
            mats.append(m)
        for s in range(segs):
            s2 = (s + 1) % segs
            faces.append((i * segs + s, i * segs + s2, (i + 1) * segs + s2, (i + 1) * segs + s))
            fm.append(mats.index(m))
    obj = C.mesh_obj(name, verts, faces, mats=mats, face_mats=fm, loc=loc, parent=parent)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    # planar UVs (YZ) for every face: hubcap textures read radially
    me = obj.data
    uvl = me.uv_layers.new(name="UVMap")
    rmax = max(r for r, _ in profile)
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uvl.data[li].uv = (0.5 + co.y / (2 * rmax), 0.5 + co.z / (2 * rmax))
    if axis != "X":
        raise ValueError("only X supported")
    return obj


def radial_texture(name, size, fn):
    """fn(r 0..1, theta radians) -> rgb. Square image mapped by revolve UVs."""
    def px(x, y):
        u = (x + 0.5) / size * 2 - 1
        v = (y + 0.5) / size * 2 - 1
        return fn(math.hypot(u, v), math.atan2(v, u))
    return C.make_image(name, size, size, px)


# ---------------------------------------------------------------- simple parts

def lamp_disc(name, r, depth, loc, normal, material, parent=None, segs=10, sx=1.0, sz=1.0):
    """Flattened cylinder (optionally oval) facing `normal`."""
    o = C.cylinder(name, r, depth, segs=segs, axis="Z", material=material)
    o.scale = (sx, sz, 1)
    C.apply_transform(o)
    o.rotation_euler = Vector(normal).to_track_quat("Z", "Y").to_euler()
    o.location = loc
    C.apply_transform(o)
    if parent:
        o.parent = parent
    return o


def mirror_x(obj, name=None):
    """Duplicate obj mirrored across X (geometry only, object at origin)."""
    me = obj.data.copy()
    me.transform(obj.matrix_basis)
    for v in me.vertices:
        v.co.x = -v.co.x
    for p in me.polygons:
        p.flip()
    o = bpy.data.objects.new(name or obj.name + "_m", me)
    C.link(o, obj.parent)
    return o


def plate_texture(text_seed=7, blue=True):
    """WA style plate: white with a dark blue border and blocky characters."""
    rnd = C.noise_rng(text_seed)
    w, h = 64, 16
    glyph = {}
    for i in range(7):
        glyph[i] = [[rnd() > -0.1 for _ in range(3)] for _ in range(5)]
    ink = (0.08, 0.15, 0.45) if blue else (0.05, 0.05, 0.05)

    def px(x, y):
        if x < 1 or x >= w - 1 or y < 1 or y >= h - 1:
            return ink
        cx = (x - 6) // 7
        lx = (x - 6) % 7
        ly = y - 5
        if 0 <= cx < 7 and 0 <= lx < 6 and 0 <= ly < 10 and cx != 3:
            g = glyph[cx][min(4, ly // 2)][min(2, lx // 2)]
            if g:
                return ink
        return (0.95, 0.95, 0.92)
    return C.make_image("plate_wa", w, h, px)


def planar_uv(obj, axis_u, axis_v, flip_u=False):
    """Fit the object's bounds to 0..1 using two axes (0=x,1=y,2=z)."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    cos = [v.co for v in me.vertices]
    lo_u, hi_u = min(c[axis_u] for c in cos), max(c[axis_u] for c in cos)
    lo_v, hi_v = min(c[axis_v] for c in cos), max(c[axis_v] for c in cos)
    uv = me.uv_layers.active.data
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            u = (co[axis_u] - lo_u) / max(hi_u - lo_u, 1e-6)
            uv[li].uv = (1 - u if flip_u else u, (co[axis_v] - lo_v) / max(hi_v - lo_v, 1e-6))


def hit(obj, origin, direction):
    """Ray cast against obj (identity transform assumed): (location, normal)."""
    ok, loc, nor, _ = obj.ray_cast(Vector(origin), Vector(direction).normalized())
    if not ok:
        raise RuntimeError("ray missed %s from %s" % (obj.name, origin))
    return loc, nor


def on_front(obj, x, z):
    return hit(obj, (x, -5, z), (0, 1, 0))


def on_rear(obj, x, z):
    return hit(obj, (x, 5, z), (0, -1, 0))


def on_side(obj, sx, y, z):
    return hit(obj, (sx * 5, y, z), (-sx, 0, 0))


def on_top(obj, x, y):
    return hit(obj, (x, y, 5), (0, 0, -1))


def stick_disc(name, obj, where, r, depth, material, segs=10, sx=1.0, sz=1.0, proud=0.0):
    """Disc sitting on the surface hit `where` = (loc, normal)."""
    loc, nor = where
    return lamp_disc(name, r, depth, loc + nor * (depth / 2 - 0.01 + proud), nor, material,
                     segs=segs, sx=sx, sz=sz)


def stick_box(name, where, size, material, up=(0, 0, 1), proud=0.0):
    """Box whose local Z follows the surface normal (size = x, y, thickness)."""
    loc, nor = where
    o = C.box(name, (size[0], size[1], size[2]), material=material)
    q = nor.to_track_quat("Z", "Y")
    o.rotation_euler = q.to_euler()
    o.location = loc + nor * (size[2] / 2 - 0.005 + proud)
    C.apply_transform(o)
    return o


# ------------------------------------------------------------------ smooth curves

def pchip(xs, ys):
    """Monotone cubic interpolation (no overshoot) -> f(x)."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(x):
        if x <= xs[0]:
            return ys[0]
        if x >= xs[-1]:
            return ys[-1]
        i = max(j for j in range(n - 1) if xs[j] <= x)
        t = (x - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])
    return f


def catmull(points, counts):
    """Sample a Catmull-Rom spline through 2D control points; counts[i] points
    are generated for segment i (excluding its end). Returns the list plus
    the index of each control point in it."""
    P = [points[0]] + list(points) + [points[-1]]
    out, idx = [], []
    for i in range(len(points) - 1):
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        idx.append(len(out))
        for k in range(counts[i]):
            t = k / counts[i]
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[c]) + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
                                    + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3) for c in range(2)))
    idx.append(len(out))
    out.append(tuple(points[-1]))
    return out, idx


# ------------------------------------------------------------------ decals

def _point_in_poly(p, poly):
    x, y = p
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def _dist_to_poly(p, poly):
    best = 1e9
    for i in range(len(poly)):
        a, b = Vector(poly[i - 1]), Vector(poly[i])
        ab = b - a
        t = max(0, min(1, (Vector(p) - a).dot(ab) / max(ab.length_squared, 1e-12)))
        best = min(best, (Vector(p) - (a + ab * t)).length)
    return best


def inside_poly(p, poly, inset=0.0):
    return _point_in_poly(p, poly) and _dist_to_poly(p, poly) >= inset


def offset_poly(poly, d):
    """Inset (d > 0) a convex-ish polygon by moving each vertex along its bisector."""
    out = []
    n = len(poly)
    area = sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(n))
    sgn = 1 if area > 0 else -1
    for i in range(n):
        a, b, c = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        e1, e2 = (b - a).normalized(), (c - b).normalized()
        n1 = Vector((-e1.y, e1.x)) * sgn
        n2 = Vector((-e2.y, e2.x)) * sgn
        bis = (n1 + n2)
        if bis.length < 1e-6:
            bis = n1
        bis.normalize()
        k = d / max(bis.dot(n1), 0.7)  # miter limit: no spikes at sharp corners
        out.append(tuple(b + bis * k))
    return out


def surface_ray(target, origin, direction):
    """ray_cast that does not slip through the seam between two faces when
    the ray lands exactly on a shared edge: retries with tiny offsets."""
    o, d = Vector(origin), Vector(direction).normalized()
    res = target.ray_cast(o, d)
    if res[0]:
        return res
    side = d.orthogonal().normalized()
    up = d.cross(side)
    for j in (side, -side, up, -up):
        res = target.ray_cast(o + j * 2e-4, d)
        if res[0]:
            return res
    return res


def project_poly(name, target, poly, frame, material, offset=0.004, cuts=4, border=None, border_mat=None):
    """Mesh covering `poly` (2D) projected onto `target`'s surface.

    frame(u, v) -> (origin, direction) gives the ray for a 2D point. With
    `border` (metres), an outer ring of that width gets `border_mat` and the
    inside gets `material` (window glass with a black seal); material None
    leaves just the ring.
    """
    def build(p2, mat):
        bm = bmesh.new()
        vs = [bm.verts.new((u, v, 0)) for u, v in p2]
        bm.faces.new(vs)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        if cuts:
            bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for v in me.vertices:
            o, d = frame(v.co.x, v.co.y)
            ok, loc, nor, _ = surface_ray(target, o, d)
            if ok:
                v.co = loc + nor * offset
            else:
                v.co = Vector(o) + Vector(d) * 4.6
        o = bpy.data.objects.new(name, me)
        me.materials.append(mat)
        C.link(o)
        return o

    parts = []
    if border:
        inner = offset_poly(poly, border)
        ring = []
        n = len(poly)
        for i in range(n):
            ring.append((poly[i], poly[(i + 1) % n], inner[(i + 1) % n], inner[i]))
        for q in ring:
            parts.append(build(list(q), border_mat))
        if material is not None:
            parts.append(build(inner, material))
    else:
        parts.append(build(poly, material))
    o = C.join(parts, name)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(o.data)
    bm.free()
    smooth(o, 60)
    return o


def project_line(name, target, pts, frame, width, material, offset=0.003, closed=False):
    """A thin ribbon along a 2D polyline, projected onto the surface (shut lines)."""
    seq = list(pts) + ([pts[0]] if closed else [])
    verts, faces = [], []
    for i, p in enumerate(seq):
        a = Vector(seq[max(i - 1, 0)])
        b = Vector(seq[min(i + 1, len(seq) - 1)])
        t = (b - a).normalized()
        nrm = Vector((-t.y, t.x)) * width / 2
        for s in (-1, 1):
            u, v = Vector(p) + nrm * s
            o, d = frame(u, v)
            ok, loc, nor, _ = surface_ray(target, o, d)
            verts.append(tuple(loc + nor * offset) if ok else tuple(Vector(o) + Vector(d) * 4.6))
    for i in range(len(seq) - 1):
        faces.append((2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2))
    o = C.mesh_obj(name, verts, faces, material)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    material.use_backface_culling = False
    return o


def side_frame(sx):
    """2D (y, z) -> ray from outside on side sx toward the car."""
    return lambda u, v: ((sx * 5, u, v), (-sx, 0, 0))


def top_frame():
    """2D (x, y) -> ray from above."""
    return lambda u, v: ((u, v, 5), (0, 0, -1))


def front_frame():
    """2D (x, z) -> ray from the front (cars face -Y while being built)."""
    return lambda u, v: ((u, -5, v), (0, 1, 0))


def rear_frame():
    return lambda u, v: ((u, 5, v), (0, -1, 0))
