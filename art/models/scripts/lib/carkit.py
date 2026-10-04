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
    """Boolean the wheel arches out of the shell (both sides, each axle)."""
    for y in axles:
        cutter = C.cylinder("arch", radius, 2.4, segs=14, axis="X", loc=(0, y, hub_z))
        inner = C.box("arch_keep", (2 * x_inner, 1.0, 1.0), (0, y, hub_z))
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


def solidify(obj, thickness, inner_mat, rim=True):
    obj.data.materials.append(inner_mat)
    mod = obj.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1
    mod.use_rim = rim
    mod.material_offset = len(obj.data.materials) - 1
    mod.material_offset_rim = len(obj.data.materials) - 1
    mod.use_even_offset = True
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
