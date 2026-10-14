"""The VC Valiant's opening front doors (and, below, its cockpit).

The body in lib/period_vehicles.py is one closed shell; `split_doors` cuts
each front door out of it along the shut lines and takes with it whatever
sits on the door: the glass, its chrome frame, the handle, the driver's
mirror and the door's length of the side spear. Each door becomes its own
object, Door_L / Door_R, with its origin on the hinge line at the front
edge and its glass as a child (art/models/README.md, "Door_L, Door_R").

Coordinates as in period_vehicles: front toward +Y (Godot -Z), the kerb
side on -X (Door_L), the driver on +X (Door_R).
"""
import bpy  # noqa: F401,I001  (bpy must load before bmesh)
import bmesh
from mathutils import Vector

from . import common as C
from . import carkit as K
from . import period_vehicles as PV

DOOR_OPEN_DEG = 60          # the classics' full swing (README)
DOOR_Y0, DOOR_Y1 = -0.035, 0.93   # rear and front shut lines (the B pillar and the cowl)
DOOR_Z0 = 0.37                    # bottom edge, above the sill
HINGE_DY = -0.02                  # hinge just behind the front shut line


def door_outline():
    """Side outline (y, z) of the front door: up the front shut line to the
    belt, forward along the belt to the A pillar's foot, up the pillar just
    outside the glass to the drip rail, back along it to the B pillar and
    down the rear shut line."""
    z_top = PV.DLO_Z1 + 0.026            # just over the glass frame, under the drip rail
    a0 = PV._a_line(PV.ZB) - 0.012
    a1 = PV._a_line(z_top) - 0.012
    return [(DOOR_Y0, DOOR_Z0), (DOOR_Y1, DOOR_Z0), (DOOR_Y1, PV.ZB - 0.006), (a0, PV.ZB - 0.006),
            (a1, z_top), (DOOR_Y0, z_top)]


def _slice(bm, edge, xmin):
    """Bisect the side faces (|x| > xmin) along a (y, z) polyline."""
    for (y0, z0), (y1, z1) in zip(edge, edge[1:]):
        n = Vector((0, -(z1 - z0), y1 - y0)).normalized()
        lo_y, hi_y = min(y0, y1) - 0.01, max(y0, y1) + 0.01
        lo_z, hi_z = min(z0, z1) - 0.01, max(z0, z1) + 0.01

        def near(f):
            ys = [v.co.y for v in f.verts]
            zs = [v.co.z for v in f.verts]
            return min(ys) < hi_y and max(ys) > lo_y and min(zs) < hi_z and max(zs) > lo_z
        faces = [f for f in bm.faces if abs(f.calc_center_median().x) > xmin and near(f)]
        if not faces:
            continue
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, y0, z0)), plane_no=n, dist=1e-5)


def _inside(p, poly):
    return K.inside_poly(p, poly)


def _take(obj, keep, name):
    """Move the faces of obj for which keep(face) is true into a new object."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    out = bm.copy()
    gone = [f for f in bm.faces if keep(f)]
    stay = [f for f in out.faces if not keep(f)]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bmesh.ops.delete(out, geom=stay, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    me = bpy.data.meshes.new(name)
    out.to_mesh(me)
    out.free()
    for m in obj.data.materials:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    C.link(o)
    return o


def split_doors(parts):
    """Cut both front doors out of the body (parts[0]) and gather the parts
    that ride on them. Returns (body parts, door items, empties) in
    lib/city_vehicles.py's form."""
    body = parts[0]
    C.apply_transform(body)
    outline = door_outline()
    bm = bmesh.new()
    bm.from_mesh(body.data)
    _slice(bm, outline + outline[:1], 0.5)
    bm.to_mesh(body.data)
    bm.free()
    items, empties = [], {}
    rest = list(parts[1:])
    for side, sx in (("L", -1), ("R", 1)):
        def on_door(f, sx=sx):
            c = f.calc_center_median()
            return sx * c.x > 0.5 and _inside((c.y, c.z), outline)
        door = _take(body, on_door, "door_" + side)
        ride, glass = [door], []
        for o in list(rest):
            if o.type != "MESH" or not len(o.data.vertices):
                continue
            C.apply_transform(o)
            vs = [v.co for v in o.data.vertices]
            cx = sum(v.x for v in vs) / len(vs)
            if sx * cx < 0.5:
                continue
            ys = [v.y for v in vs]
            c = (sum(ys) / len(ys), sum(v.z for v in vs) / len(vs))
            if min(ys) > DOOR_Y0 - 0.002 and _inside(c, outline):
                rest.remove(o)
                (glass if o.name.startswith("glass") else ride).append(o)
            elif min(ys) < DOOR_Y0 and max(ys) > DOOR_Y1 and min(v.z for v in vs) > DOOR_Z0:
                # a run along the whole car (the side spear): the door keeps its length
                piece = _take(o, lambda f: DOOR_Y0 < f.calc_center_median().y < DOOR_Y1, o.name + "_door")
                ride.append(piece)
        _cut_runs(ride[1:])
        hinge = (sx * (PV.HW - 0.01), DOOR_Y1 + HINGE_DY, 0.6)
        items.append(("Door_" + side, ride, hinge, None))
        items.append(("Door_%s_Glass" % side, glass, hinge, "Door_" + side))
        # the open pose, sign applied: a front-hinged left door opens with a
        # negative turn (README)
        sign = -1 if side == "L" else 1
        empties["DoorOpen_" + side] = (hinge, DOOR_OPEN_DEG * sign)
    return [body] + rest, items, empties


def _cut_runs(objs):
    """Bisect pieces taken off a long run so their ends sit on the shut lines."""
    for o in objs:
        if not o.name.endswith("_door"):
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for y, keep_neg in ((DOOR_Y1, True), (DOOR_Y0, False)):
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                         plane_co=(0, y, 0), plane_no=(0, 1, 0), clear_outer=keep_neg,
                                         clear_inner=not keep_neg)
            del res
        bm.to_mesh(o.data)
        bm.free()
