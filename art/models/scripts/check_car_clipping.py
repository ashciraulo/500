"""Clipping check for the scripted Fiat 500s, modern and classic.

    python3.11 art/models/scripts/check_car_clipping.py [pop|lounge|abarth500|nuova|giardiniera|...]

Builds the car with every joined sub-part tagged, then intersects the parts
with BVH trees: interior vs interior, interior vs body/glass/doors, closed
doors vs body and glass, doors opened 15/30/45/65 deg vs body, interior and
glass, wheels (fronts steered 0 and +-35 deg) vs body and interior, lamps vs
interior and doors. Triangles are shrunk by EPS first, so parts that only
touch along an edge (seams, shut gaps) are not counted; parts deliberately
pushed into each other inside one object are listed in ATTACHED and reported
separately. Writes nothing.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from lib import common as C
from lib import fiat500_modern as F

PART = []
EPS = 0.002
_orig_join = C.join


def _tag(o):
    me = o.data
    if "part_id" not in me.attributes:
        a = me.attributes.new("part_id", "INT", "FACE")
        PART.append(o.name)
        pid = len(PART)  # 0 = untagged
        for i in range(len(me.polygons)):
            a.data[i].value = pid


def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in objs:
        if o.type == "MESH":
            _tag(o)
    return _orig_join(objs, name)


C.join = join


def part_trees(obj, matrix=None):
    """{part name: (bvh, verts)} for one object in world space."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = obj.evaluated_get(dg).to_mesh()
    M = matrix if matrix is not None else obj.matrix_world
    att = me.attributes.get("part_id")
    groups = {}
    for p in me.polygons:
        pid = att.data[p.index].value if att else 0
        nm = PART[pid - 1] if pid else obj.name
        groups.setdefault(nm, []).append([v for v in p.vertices])
    out = {}
    wv = [M @ v.co for v in me.vertices]
    for nm, polys in groups.items():
        # triangulate and shrink every triangle by EPS toward its centroid:
        # parts that only touch along an edge (seams, joins) drop out, real
        # crossings stay.
        verts, tris = [], []
        for p in polys:
            for k in range(1, len(p) - 1):
                tri = [wv[p[0]], wv[p[k]], wv[p[k + 1]]]
                c = (tri[0] + tri[1] + tri[2]) / 3
                sh = []
                for v in tri:
                    d = v - c
                    L = d.length
                    sh.append(c + d * max(0.0, (L - EPS) / L) if L > 1e-9 else c)
                n = len(verts)
                verts += sh
                tris.append([n, n + 1, n + 2])
        out["%s/%s" % (obj.name, nm)] = (BVHTree.FromPolygons(verts, tris), verts, tris)
    obj.evaluated_get(dg).to_mesh_clear()
    return out


def overlaps(ta, tb):
    bva, va, pa = ta
    bvb, vb, pb = tb
    return bva.overlap(bvb)


def depth_hint(ta, pairs):
    _, va, pa = ta
    pts = [sum((va[k] for k in pa[i]), Vector()) / len(pa[i]) for i, _ in pairs[:200]]
    lo = Vector([min(p[k] for p in pts) for k in range(3)])
    hi = Vector([max(p[k] for p in pts) for k in range(3)])
    return "(%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)" % (*lo, *hi)


# parts deliberately pushed into each other (all inside one object)
ATTACHED = {frozenset(p.split("-")) if p.count("-") == 1 else frozenset([p]) for p in """
back-post binnacle-column binnacle-gauge column-gauge cushion-back cushion-bolster dash-binnacle
dash-column dash-stack dash-vent dash-vent_c dash-vent_ring dash-firewall dash-logo dash-radio
gaiter-gear_stick gear_stick-gear_knob post-headrest rear_back_up-rear_headrest rear_cushion-rear_back
rear_back-rear_back_up stack-gaiter stack-hvac stack-console stack-radio vent_ring-vent hub-hub_ring
hub-spoke hub_ring-sw_badge rim rim-spoke phone_clip-phone_cradle column-hub floor-mat floor-footwell
tunnel-gear_stick tunnel-gaiter tunnel-choke dash-speedo_pod dash-switch speedo_pod-gauge pedal-pedal_arm
cushion-piping hub-horn floor-floor_r floor_r-tunnel floor-tunnel floor-seat_leg parcel_tray-parcel_lip binnacle-gauge dash-binnacle
""".split()}


def _base(k):
    return k.split("/")[1].split(".")[0]


def report(title, A, B, skip=lambda a, b: False, same=False):
    hits = []
    keys_a = list(A)
    for ia, a in enumerate(keys_a):
        for b in (keys_a[ia + 1:] if same else B):
            if skip(a, b):
                continue
            pr = overlaps(A[a], (A if same else B)[b])
            if pr:
                hits.append((a, b, len(pr), depth_hint(A[a], pr)))
    if same:
        att = [h for h in hits if frozenset([_base(h[0]), _base(h[1])]) in ATTACHED]
        hits = [h for h in hits if h not in att]
        print("== %s: %d attached-by-design pairs (%s)" % (title, len(att), ", ".join(
            sorted({"%s+%s" % (_base(a), _base(b)) for a, b, _, _ in att}))))
    print("== %s: %d intersecting pairs" % (title, len(hits)))
    for h in hits:
        print("   %-40s x %-40s %4d tris  %s" % h)
    return hits


def main(spec_name="pop"):
    import build_classic as BC
    builder = F.build
    if spec_name == "pop":
        import build_pop as B
        spec = B.POP
    elif spec_name in BC.CARS:
        from lib import fiat500_classic as FC
        builder = FC.build
        spec = dict(BC.CARS[spec_name], plate="1CIN-500")
    else:
        import build_modern as BM
        spec = dict(BM.CARS[spec_name], plate="1CIN-500")
    C.reset()
    builder(spec)
    bpy.context.view_layer.update()
    ob = bpy.data.objects
    body = part_trees(ob["Body"])
    glass = part_trees(ob["Glass"])
    shell = {k: v for k, v in body.items() if k.split("/")[1].startswith(("Body", "shell"))}
    interior = part_trees(ob["Interior"])
    interior.update(part_trees(ob["SteeringWheel"]))
    doors_closed = {}
    door_names = [d for d in ("Door_L", "Door_R") if d in ob]
    for d in door_names:
        doors_closed.update(part_trees(ob[d]))
        doors_closed.update(part_trees(ob[d + "_Glass"]))
    total = 0
    print("body parts:", sorted({k.split('/')[1] for k in body})[:80])
    total += len(report("interior vs interior", interior, None, same=True))
    total += len(report("interior vs body", interior, body))
    total += len(report("interior vs glass", interior, glass))
    total += len(report("interior vs doors (closed)", interior, doors_closed))
    total += len(report("doors (closed) vs body shell+glass", doors_closed, {**shell, **glass},
                        skip=lambda a, b: False))
    # open doors
    for ang in ((15, 30, 45, 65) if door_names else ()):
        opened = {}
        for d in door_names:
            o = ob[d]
            # front-hinged doors open with Door_L negative; rear-hinged
            # (suicide) doors carry open_sign = +1 on Door_L
            o.rotation_euler.z = math.radians(ang * o.get("open_sign", -1 if d == "Door_L" else 1))
            bpy.context.view_layer.update()
            opened.update(part_trees(o))
            opened.update(part_trees(ob[d + "_Glass"]))
            o.rotation_euler.z = 0
        bpy.context.view_layer.update()
        total += len(report("doors open %d vs body" % ang, opened, body))
        total += len(report("doors open %d vs interior" % ang, opened, interior))
        total += len(report("doors open %d vs glass" % ang, opened, glass))
    # wheels
    for steer in (0, 35, -35):
        wheels = {}
        for nm in ("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"):
            o = ob[nm]
            if nm.startswith("Wheel_F"):
                o.rotation_euler.z = math.radians(steer)
            bpy.context.view_layer.update()
            wheels.update(part_trees(o))
            o.rotation_euler.z = 0
        bpy.context.view_layer.update()
        total += len(report("wheels steer %d vs body" % steer, wheels, {**body, **interior}))
        total += len(report("wheels steer %d vs doors" % steer, wheels, doors_closed))
    # convertible roofs: each state against everything fixed around it
    for rn in ("Roof_Closed", "Roof_Open"):
        if rn in ob:
            roof = part_trees(ob[rn])
            total += len(report("%s vs body/glass" % rn, roof, {**body, **glass}))
            total += len(report("%s vs interior/doors" % rn, roof, {**interior, **doors_closed}))
    lights = {**part_trees(ob["Lights_Head"]), **part_trees(ob["Lights_Tail"])}
    total += len(report("lights vs interior/doors", lights, {**interior, **doors_closed}))
    print("TOTAL intersecting pairs:", total)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "pop")
    C.done()
