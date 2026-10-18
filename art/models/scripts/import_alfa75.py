"""The 1988 Alfa 75 you can buy at the car yard, from the bought model in
art/models/source/alfa75/ (a reworked CC BY 4.0 model: see CREDITS.txt
there), put on the cars/ contract (art/models/README.md):

- cars/alfa75/alfa75.glb: the body and cabin as one mesh, the opening front
  doors, SteeringWheel, the speedo, rev and fuel needles, the odometer
  window, a gear knob, and the contract's empties (hubs, seats, exits,
  eye, mounts). Its own Simmons B45 wheels come off; the car takes its
  stock wheels like the other cars (WheelStyle_a75, build_alfa75.py).
- cars/parts/wheel_a75_simmons_l/_r.glb: those B45 wheels, as the Simmons
  wheel part.
- cars/parts/seatcover_a75_beads.glb: the bead seat cover part
  (lib/alfa75_parts.py), laid over these seats' profile.

The source has a sticker, plates and a radio display from another
project; they come off or are rewritten. No real badges: the source's
grille and boot badges are already plain discs.

The source is a Blender 5.2 file, so this runs on the bpy 5.2 module
(Python 3.13), not the 4.2 one the other build scripts use:

    python3.13 -m pip install bpy==5.2.2
    python3.13 art/models/scripts/import_alfa75.py
"""
import math
import os
import sys

import bpy
import bmesh  # noqa: I100 (only importable once bpy is)
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import alfa75_parts as AP  # noqa: E402
from lib import common as C  # noqa: E402
from lib import textures as TX  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCE = os.path.join(REPO, "art/models/source/alfa75/alfa75.blend")
CAR_OUT = "art/models/cars/alfa75/alfa75.glb"
WHEEL_OUT = "art/models/cars/parts/wheel_a75_simmons_%s.glb"
BEADS_OUT = "art/models/cars/parts/seatcover_a75_beads.glb"

CAR_PLATE = "6BA-275"   # made up: a late-80s WA plate
WHEEL_STYLE = "a75"
# Bianco Argento: warm, so it reads champagne under the game's blue sky
# fill (notes/alfa75.md); the source's #B9B2A6 reads blue-grey in game.
PAINT = ("#c5a984", 0.6, 0.1)   # colour, roughness, metallic
# The cabin's hard plastics (dash, consoles, door cards). The source's
# charcoal (#2b2c2f) draws near black in game and the wheel vanishes into
# it; the earlier Alfa's mid grey (#6c6d70, #142) read too light on this
# one, so Ash asked for one between. `--cabin-tone #hex` tries another.
CABIN_TONE = "#46474a"
RADIO_TEXT = "FM 98.5"
DOOR_OPEN = 60.0   # degrees, as the classics

# The source faces +X with its left at +Y. The contract builds face +Y with
# the driver (right) at +X: a quarter turn about Z.
TURN = Matrix.Rotation(math.radians(90), 4, "Z")

# In the turned frame (front +Y, right +X, ground z = 0), measured off the
# source: the driver's eye (the source's Cam_Driver, centred on the wheel),
# the front seats' hip points, the gear boot's top, the tailpipe.
EYE = Vector((0.36, -0.10, 1.035))
HIP = Vector((0.36, -0.13, 0.50))
GEAR_TOP = Vector((0.0, 0.341, 0.612))
PIPE = Vector((0.495, -2.24, 0.198))
# A front door: every loose piece wholly inside this box (turned frame,
# |x| from the inner limit out) rides on it: skin, glass, frame, card.
DOOR_Y = (-0.28, 0.76)
DOOR_Z = (0.20, 1.27)
DOOR_X_IN = 0.555


def main():
    path = build_car()
    build_wheels()
    build_beads(path)


def _open():
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT") or o.name == "Ground":
            bpy.data.objects.remove(o, do_unlink=True)


def _bake(o, m=TURN):
    """Put the object's world transform (and the turn) into its mesh."""
    if o.data.users > 1:
        o.data = o.data.copy()
    o.data.transform(m @ o.matrix_world)
    o.parent = None
    o.matrix_world = Matrix.Identity(4)


def _join(objs, name):
    objs = [o for o in objs if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = o.data.name = name
    return o


def _set_origin(o, frame):
    """Give the object the axes and origin `frame`, mesh staying put."""
    o.data.transform(frame.inverted() @ o.matrix_world)
    o.matrix_world = frame


def _empty(name, loc, frame=None, rx=0.0, rz=0.0):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.08
    bpy.context.scene.collection.objects.link(e)
    if frame is not None:
        e.matrix_world = frame
    else:
        e.matrix_world = (Matrix.Translation(loc) @ Matrix.Rotation(math.radians(rz), 4, "Z")
                          @ Matrix.Rotation(math.radians(rx), 4, "X"))
    return e


def _mat(name, color, rough=0.8, metal=0.0, image=None):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if image is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def _islands(bm):
    """Loose parts of a bmesh, as lists of faces."""
    seen, out = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, comp = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        out.append(comp)
    return out


def _split(o, pick, name):
    """Move the faces pick(bmesh) returns out of o into a new object."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    bm.faces.index_update()
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        f.select_set(False)
    faces = pick(bm)
    for f in faces:
        f.select_set(True)
    bmesh.update_edit_mesh(o.data)
    if faces:
        bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    if not faces:
        return None
    new = [s for s in bpy.context.selected_objects if s is not o][0]
    new.name = new.data.name = name
    return new


# ------------------------------------------------------------------ the car

def build_car():
    _open()
    wheels = bpy.data.objects["Alfa75_Wheels"]
    for o in [wheels] + list(wheels.children_recursive):
        bpy.data.objects.remove(o, do_unlink=True)
    for o in list(bpy.data.objects):
        n = o.name
        if n == "Sticker_Decal" or n.startswith("Plate") and ("_Text" in n or "_Border" in n):
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.objects["Radio_Text"].data.body = RADIO_TEXT
    _text_to_mesh(bpy.data.objects["Radio_Text"])
    root = bpy.data.objects["Alfa75_Body"]
    parts = [o for o in root.children_recursive if o.type == "MESH"]
    for o in parts:
        _bake(o)
    bpy.data.objects.remove(root, do_unlink=True)
    _materials(parts)
    parts += _plates()

    knob = _gear_knob()
    wheel_parts = [o for o in parts if o.name in ("Object_5", "Object_15", "Object_2")]
    parts = [o for o in parts if o not in wheel_parts]
    wheel = _steering_wheel(wheel_parts)
    _needles()
    doors = [_door(parts, side) for side in ("L", "R")]
    body = _join(parts, "Alfa75")
    path = _bead_path(body)
    _backs([body, wheel, knob] + doors + [d.children[0] for d in doors if d.children], CAR_VIEWS)
    _empties(wheel)
    mid = (bpy.data.objects["Hub_FL"].location.y + bpy.data.objects["Hub_RL"].location.y) / 2
    for o in bpy.data.objects:
        if o.parent is None:
            o.matrix_world = Matrix.Translation((0, -mid, 0)) @ o.matrix_world
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    print("alfa75 car triangles:", tris, "body", body.name)
    _export(CAR_OUT)
    return path


def _text_to_mesh(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")


def _materials(parts):
    """The material names the game drives: Paint, Glass, LampHead,
    LampTail. The brake lenses light with the tails (car_body.gd)."""
    mats = bpy.data.materials
    paint = mats["Alfa_270_Champagne"]
    paint.name = "Paint"
    bsdf = paint.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*C.srgb_to_linear(C._hex(PAINT[0])), 1)
    bsdf.inputs["Roughness"].default_value = PAINT[1]
    bsdf.inputs["Metallic"].default_value = PAINT[2]
    tone = sys.argv[sys.argv.index("--cabin-tone") + 1] if "--cabin-tone" in sys.argv else CABIN_TONE
    if tone:
        plastic = mats["Interior_Charcoal"].node_tree.nodes["Principled BSDF"]
        plastic.inputs["Base Color"].default_value = (*C.srgb_to_linear(C._hex(tone)), 1)
    mats["Glass_Dark_Tint"].name = "Glass"
    mats["Headlight_Lens"].name = "LampHead"
    mats["Tail_Lens_Red"].name = "LampTail"
    for o in parts:
        for slot in o.material_slots:
            if slot.material and slot.material.name == "Brake_Lens_Red":
                slot.material = mats["LampTail"]


def _plates():
    """Our plate over the source's plate blanks, a little proud of them."""
    mat = _mat("Plate", (1, 1, 1), rough=0.6, image=TX.plate(CAR_PLATE))
    out = []
    # (y of the plate face, outward sign, z bottom, z top), turned frame
    for name, y, s, z0, z1 in (("PlateF", 2.134, 1, 0.342, 0.446), ("PlateR", -2.163, -1, 0.586, 0.689)):
        me = bpy.data.meshes.new(name)
        y += s * 0.003
        w = 0.217
        # read from in front of the car its right is -X, from behind +X
        vs = [(s * w, y, z0), (-s * w, y, z0), (-s * w, y, z1), (s * w, y, z1)]
        me.from_pydata(vs, [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new(name="UVMap")
        for li, c in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
            uv.data[li].uv = c
        me.materials.append(mat)
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        out.append(o)
    return out


def _gear_knob():
    """The source's gear boot has no lever: a short one and a black ball."""
    dark = bpy.data.materials["Trim_Black_Satin"]
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.021,
                                         location=GEAR_TOP + Vector((0, 0, 0.055)))
    knob = bpy.context.active_object
    knob.scale = (1, 1, 1.15)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    knob.data.materials.append(dark)
    bpy.ops.object.shade_smooth()
    knob.name = knob.data.name = "GearKnob"
    _set_origin(knob, Matrix.Translation(GEAR_TOP + Vector((0, 0, 0.034))))
    return knob


def _steering_wheel(objs):
    """Rim, spokes and pad turn on the column: local Y down the column
    toward the dash, Z to twelve (as lib/alfa75_cabin.py's frame)."""
    hub_obj = bpy.data.objects["Object_2"]
    hub = sum((v.co for v in hub_obj.data.vertices), Vector()) / len(hub_obj.data.vertices)
    w = _join(objs, "SteeringWheel")
    # all near black, so the rim stands out against the dash (the source
    # makes it the dash's charcoal)
    w.data.materials.clear()
    w.data.materials.append(bpy.data.materials["Trim_Black_Satin"])
    for p in w.data.polygons:
        p.material_index = 0
    # the rim's plane: its thinnest direction is the column
    pts = [v.co for v in w.data.vertices]
    c = sum(pts, Vector()) / len(pts)
    cov = [[sum((p[i] - c[i]) * (p[j] - c[j]) for p in pts) for j in range(3)] for i in range(3)]
    axis = _smallest_eigen(cov)
    if axis.y < 0:
        axis = -axis
    tilt = math.atan2(axis.z, axis.y)   # negative: the column runs down to the dash
    frame = Matrix.Translation(hub) @ Matrix.Rotation(tilt, 4, "X")
    _set_origin(w, frame)
    w["column_tilt_deg"] = math.degrees(tilt)
    return w


def _smallest_eigen(m):
    """Unit eigenvector of a symmetric 3x3 for its smallest eigenvalue, by
    inverse iteration."""
    a = Matrix(m)
    shift = Matrix.Identity(3) * (1e-9 * (a[0][0] + a[1][1] + a[2][2]))
    inv = (a + shift).inverted()
    v = Vector((0.3, 0.6, 0.7))
    for _ in range(60):
        v = (inv @ v).normalized()
    return v


def _needles():
    """The speedo, rev counter and fuel gauge's pointers out of the
    instrument panel, each on its own pivot: local Z the dial normal (Godot
    turns them about local Y, clockwise as the value rises), at rest on
    the dial's zero. The speedo and rev counter sweep 240 degrees from
    lower left (220 km/h, 8000 rpm), like the old cluster; the fuel gauge
    rests on E at the top left of its small dial. The temperature gauge
    stays put."""
    panel = bpy.data.objects["Instrument_Panel"]
    me = panel.data
    names = [s.material.name if s.material else "" for s in panel.material_slots]
    dials = []
    bm = bmesh.new()
    bm.from_mesh(me)
    for comp in _islands(bm):
        if names[comp[0].material_index] == "Dial_Face":
            vs = {v for f in comp for v in f.verts}
            c = sum((v.co for v in vs), Vector()) / len(vs)
            r = max((v.co - c).length for v in vs)
            n = sum((f.normal * f.calc_area() for f in comp), Vector()).normalized()
            if n.y > 0:
                n = -n   # toward the driver (rearward)
            dials.append((c, r, n))
    bm.free()
    dials.sort(key=lambda d: (-d[1], d[0].x))
    big = sorted(dials[:2], key=lambda d: d[0].x)      # speedo inboard, rev counter outboard
    small = sorted(dials[2:], key=lambda d: d[0].z)    # fuel below, temperature above
    plan = [("Needle_Speed_220", big[0], 210.0), ("Needle_Rev_8", big[1], 210.0),
            ("Needle_Fuel_3", small[0], 135.0)]
    for name, (c, r, n), rest in plan:
        def pick(bm, c=c, r=r):
            for comp in _islands(bm):
                if names[comp[0].material_index] != "Dial_Needle":
                    continue
                vs = {v for f in comp for v in f.verts}
                cc = sum((v.co for v in vs), Vector()) / len(vs)
                if (cc - c).length < r * 0.6:
                    return comp
            return []
        o = _split(panel, pick, name)
        frame = _dial_frame(c, n)
        _set_origin(o, frame)
        tip = max((v.co for v in o.data.vertices), key=lambda p: p.xy.length)
        now = math.degrees(math.atan2(tip.y, tip.x))
        # in the dial frame x is the driver's right, y up the dial
        o.data.transform(Matrix.Rotation(math.radians(rest - now), 4, "Z"))
    c, r, n = big[0]
    odo = _dial_frame(c, n)
    rt, up = odo.col[0].xyz, odo.col[1].xyz
    m = Matrix((rt, -n, up)).transposed().to_4x4()
    m.translation = c - up * (0.3125 * r) + n * 0.001
    _empty("Odometer_%d" % round(5 / 64 * r * 1000), None, frame=m)


def _dial_frame(c, n):
    """Columns: the driver's right, up the dial, the normal toward him."""
    up = (Vector((0, 0, 1)) - n * n.z).normalized()
    rt = up.cross(n)
    m = Matrix((rt, up, n)).transposed().to_4x4()
    m.translation = c
    return m


def _door(parts, side):
    """A front door: every loose piece wholly inside the door's box comes
    off the body onto Door_<side>, its origin on the hinge at the door's
    front edge; the glass is its child Door_<side>_Glass."""
    sx = -1 if side == "L" else 1

    def inside(comp):
        vs = {v for f in comp for v in f.verts}
        xs = [v.co.x * sx for v in vs]
        ys = [v.co.y for v in vs]
        zs = [v.co.z for v in vs]
        return (min(xs) >= DOOR_X_IN and DOOR_Y[0] <= min(ys) and max(ys) <= DOOR_Y[1]
                and DOOR_Z[0] <= min(zs) and max(zs) <= DOOR_Z[1])

    pieces = []
    for o in list(parts):
        if o.type != "MESH":
            continue
        got = _split(o, lambda bm: [f for comp in _islands(bm) if inside(comp) for f in comp],
                     "Door_%s_%s" % (side, o.name))
        if got:
            pieces.append(got)
    door = _join(pieces, "Door_" + side)
    glass_idx = [i for i, s in enumerate(door.material_slots) if s.material and s.material.name == "Glass"]
    glass = _split(door, lambda bm: [f for f in bm.faces if f.material_index in glass_idx], "Door_%s_Glass" % side)
    # the hinge is on the skin's front edge (the mirror stands proud of it)
    paint = [i for i, s in enumerate(door.material_slots) if s.material and s.material.name == "Paint"]
    vs = [door.data.vertices[i].co for p in door.data.polygons if p.material_index in paint for i in p.vertices]
    hinge = Vector((sx * max(v.x * sx for v in vs), max(v.y for v in vs), 0.6))
    _set_origin(door, Matrix.Translation(hinge))
    if glass:
        _set_origin(glass, Matrix.Translation(hinge))
        glass.parent = door
        glass.matrix_parent_inverse = Matrix.Identity(4)
        glass.matrix_world = Matrix.Translation(hinge)
    _empty("DoorOpen_" + side, hinge, rz=-sx * DOOR_OPEN)
    return door


def _ray_down(x, y, z_from):
    dg = bpy.context.evaluated_depsgraph_get()
    ok, loc, _n, _i, _o, _m = bpy.context.scene.ray_cast(dg, Vector((x, y, z_from)), Vector((0, 0, -1)))
    if not ok:
        raise RuntimeError("ray missed at %s" % ((x, y, z_from),))
    return loc


def _empties(wheel):
    for nm, sx, y in (("FL", -1, 1.2555), ("FR", 1, 1.2555), ("RL", -1, -1.2555), ("RR", 1, -1.2555)):
        _empty("Hub_" + nm, (sx * 0.709, y, 0.2975))
    _empty("WheelStyle_" + WHEEL_STYLE, (0, 0, 0))
    _empty("Cam_Cockpit", EYE)
    for nm, sx in (("L", -1), ("R", 1)):
        _empty("Seat_" + nm, (sx * HIP.x, HIP.y, HIP.z))
        # beside the front door, facing away from the car (Godot -Z out)
        _empty("Exit_" + nm, (sx * 1.33, 0.25, 0.0), rz=90 * -sx)
        _empty("Mount_MudFlap_" + nm, (sx * 0.709, -1.655, 0.26))
    # a fitted wheel: Godot -Z down the column toward the dash, +Y to twelve
    _empty("Mount_SteeringWheel", None, frame=wheel.matrix_world.copy())
    _empty("Mount_GearKnob", GEAR_TOP + Vector((0, 0, 0.034)))
    _empty("Mount_Exhaust", PIPE)
    _empty("Mount_Roof", (0.0, -0.3, 1.31))
    _empty("Mount_Spotlights", (0.0, 2.08, 0.47))
    _empty("Mount_BumperF", (0.0, 2.135, 0.425))
    _empty("Mount_BumperR", (0.0, -2.30, 0.49))
    _empty("Mount_TowBar", (0.0, -2.29, 0.30))
    _empty("Mount_Mirror", (0.0, 0.28, 1.16))
    _empty("Mount_Dash", _ray_down(-0.3, 0.66, 0.93))
    _empty("Mount_Shelf", _ray_down(-0.35, -1.60, 1.05))
    _empty("Mount_Gear", _ray_down(0.0, 0.05, 0.6))
    _empty("Mount_Glovebox", (-0.31, 0.49, 0.80))


def _ring(r, z, n=16, y0=0.0):
    return [Vector((r * math.sin(a), y0 + r * math.cos(a), z)) for a in (k * 2 * math.pi / n for k in range(n))]


# Where the car is seen from: the seats, the cabin cameras, round it at
# kerb, eye and first-floor height, and low into each wheel arch.
CAR_VIEWS = ([Vector(v) for v in ((0.36, -0.10, 1.035), (-0.36, -0.10, 1.035), (0.36, -0.95, 1.0),
                                  (-0.36, -0.95, 1.0), (0.0, 0.30, 1.0), (0.0, -0.50, 1.05))]
             + _ring(3.0, 0.8) + _ring(3.0, 1.8) + _ring(4.5, 0.4) + _ring(4.5, 1.2) + _ring(4.5, 2.2)
             + _ring(6.0, 3.0) + _ring(9.0, 1.5)
             + [Vector((sx * 2.2, y + dy, 0.35)) for sx in (-1, 1) for y in (1.2555, -1.2555) for dy in (-0.6, 0.6)])


def _backs(objs, views):
    """The source was drawn two-sided; the game's PS1 shader culls back
    faces, and some of the source's faces point away from where they are
    seen (the steering wheel's from the driver, the arch liners'). Every
    face seen from its back from one of `views` gets a flipped twin, with
    its corner normals flipped too, joined into its object."""
    verts, polys, owner = [], [], []
    glass = set()
    for o in objs:
        me, mw = o.data, o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in me.vertices]
        for p in me.polygons:
            m = o.material_slots[p.material_index].material if o.material_slots else None
            if m is not None and m.name == "Glass":
                glass.add((o.name, p.index))
                continue
            polys.append([base + i for i in p.vertices])
            owner.append((o, p.index))
    bvh = BVHTree.FromPolygons(verts, polys)
    found = 0
    for o in objs:
        me, mw = o.data, o.matrix_world
        rot = mw.to_3x3()
        flagged = []
        for p in me.polygons:
            if (o.name, p.index) in glass:
                continue
            c, n = mw @ p.center, (rot @ p.normal).normalized()
            for v in views:
                d = c - v
                dist = d.length
                if dist < 1e-4 or n.dot(d) <= 0:
                    continue
                hit = bvh.ray_cast(v, d / dist, dist + 1e-3)
                if hit[0] is not None and owner[hit[2]] == (o, p.index):
                    flagged.append(p)
                    break
        if flagged:
            found += len(flagged)
            _twin(o, flagged)
    print("flipped twins for", found, "faces")


def _twin(o, faces):
    me = o.data
    cn = me.corner_normals
    uvs = me.uv_layers.active.data if me.uv_layers.active else None
    vs, fs, ns, uv, mats = [], [], [], [], []
    for p in faces:
        loops = list(p.loop_indices)[::-1]
        fs.append(list(range(len(vs), len(vs) + len(loops))))
        for li in loops:
            vs.append(me.vertices[me.loops[li].vertex_index].co.copy())
            ns.append(-Vector(cn[li].vector))
            uv.append(tuple(uvs[li].uv) if uvs else (0.0, 0.0))
        mats.append(p.material_index)
    tw = bpy.data.meshes.new(o.name + "_backs")
    tw.from_pydata(vs, [], fs)
    for m in o.data.materials:
        tw.materials.append(m)
    for p, mi in zip(tw.polygons, mats):
        p.material_index = mi
        p.use_smooth = True
    layer = tw.uv_layers.new(name=me.uv_layers.active.name if me.uv_layers.active else "UVMap")
    for li, t in enumerate(uv):
        layer.data[li].uv = t
    tw.normals_split_custom_set(ns)
    t = bpy.data.objects.new(tw.name, tw)
    bpy.context.scene.collection.objects.link(t)
    t.matrix_world = o.matrix_world.copy()
    bpy.ops.object.select_all(action="DESELECT")
    t.select_set(True)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()


def _export(path):
    path = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False,
        export_apply=True, export_lights=False, export_cameras=False,
        export_yup=True, export_extras=False, export_materials="EXPORT",
        export_image_format="AUTO")
    print("exported", path, os.path.getsize(path), "bytes")


def _bead_path(body):
    """The passenger seat's profile down its middle, (y, z) from the
    cushion's front edge up the back to its top: a fan of rays from over
    the cushion, kept while the hits run on without a jump: the crease
    between cushion and back is a 6.5 cm step, the gap up to the headrest
    8 cm."""
    me = body.data
    bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices for p in me.polygons])
    o = Vector((-HIP.x, HIP.y + 0.12, HIP.z + 0.32))
    fan = []
    for k in range(75):
        a = math.radians(-50.0 - k * 2.5)
        hit = bvh.ray_cast(o, Vector((0.0, math.cos(a), math.sin(a))), 1.5)
        fan.append(hit[0])
    mid = 16   # straight down, onto the cushion
    run = [fan[mid]]
    for step in (-1, 1):
        k = mid + step
        while 0 <= k < len(fan) and fan[k] is not None and (fan[k] - fan[k - step]).length < 0.072:
            run.insert(0, fan[k]) if step < 0 else run.append(fan[k])
            k += step
    pts = [(p.y, p.z) for p in run]
    # over the cushion's front lip and a little way down behind the top
    front, top = pts[0], pts[-1]
    return [(front[0] - 0.01, front[1] - 0.06)] + pts + [(top[0] - 0.04, top[1] - 0.03)]


def build_beads(path):
    C.reset()
    C.clear_material_cache()
    AP.seatcover_beads(path, Vector((-HIP.x, HIP.y, HIP.z)))
    _export(BEADS_OUT)


# ------------------------------------------------------------------ wheels

def build_wheels():
    """The B45s as the Simmons wheel part: one mesh, origin on the hub,
    axle along X, the face outward (-X on the left)."""
    for side, src in (("l", "B45_FL"), ("r", "B45_FR")):
        _open()
        hub = bpy.data.objects[src]
        keep = [o for o in hub.children_recursive if o.type == "MESH"]
        for o in keep:
            if o.modifiers:
                bpy.context.view_layer.objects.active = o
                for mod in list(o.modifiers):
                    bpy.ops.object.modifier_apply(modifier=mod.name)
        at = TURN @ hub.matrix_world.translation
        for o in keep:
            _bake(o, Matrix.Translation(-at) @ TURN)
        for o in list(bpy.data.objects):
            if o not in keep:
                bpy.data.objects.remove(o, do_unlink=True)
        w = _join(keep, "Wheel")
        sx = -1 if side == "l" else 1
        _backs([w], [Vector((sx * 1.5, 1.5 * math.cos(a), 0.3 + 1.2 * math.sin(a)))
                     for a in (k * math.pi / 4 for k in range(8))])
        _export(WHEEL_OUT % side)


if __name__ == "__main__":
    main()
