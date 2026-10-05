"""Shared helpers for the scripted Blender models.

Runs either inside Blender (`blender -b -P script.py`) or with the `bpy`
module from PyPI (`python script.py`). Everything is built from code so a
model can be regenerated and diffed; no .blend files are committed.

Conventions (Blender space; the glTF exporter converts to Godot's +Y up):
  * metres, Z up
  * vehicles face -Y in Blender, which becomes +Z in Godot
  * low poly: flat shading, small nearest-filtered textures
"""
import math
import os
import random

import bpy  # noqa: I001  (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))


# ---------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                  bpy.data.objects, bpy.data.lights, bpy.data.cameras):
        for item in list(block):
            block.remove(item)


def link(obj, parent=None, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(name, loc=(0, 0, 0), parent=None, size=0.2):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = size
    obj.location = loc
    return link(obj, parent)


# ---------------------------------------------------------------- textures

def _hex(c):
    if isinstance(c, str):
        c = c.lstrip("#")
        return tuple(int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return tuple(c[:3])


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def make_image(name, w, h, pixel_fn):
    """pixel_fn(x, y) -> (r, g, b) in sRGB 0..1; y=0 is the bottom row."""
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = []
    for y in range(h):
        for x in range(w):
            r, g, b = pixel_fn(x, y)
            px.extend((min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1), 1.0))
    img.pixels = px
    img.pack()
    return img


def noise_rng(seed):
    rnd = random.Random(seed)
    return lambda a=1.0: (rnd.random() * 2 - 1) * a


# ---------------------------------------------------------------- materials

_MATS = {}


def mat(name, color="#ffffff", rough=0.8, metal=0.0, emit=None, emit_strength=1.0,
        image=None, alpha=None, uv_scale=None, emit_image=False):
    """Principled material. `image` is a bpy image (nearest filtered)."""
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    base = srgb_to_linear(_hex(color))
    bsdf.inputs["Base Color"].default_value = (*base, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*srgb_to_linear(_hex(emit)), 1)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
        if emit_image and image is not None:
            # the texture glows (a lit dial or display), not a flat colour
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
    m.diffuse_color = (*base, 1 if alpha is None else alpha)
    _MATS[name] = m
    return m


def clear_material_cache():
    _MATS.clear()


# ---------------------------------------------------------------- meshes

def mesh_obj(name, verts, faces, material=None, parent=None, loc=(0, 0, 0),
             mats=None, face_mats=None, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    for m in (mats or ([material] if material else [])):
        me.materials.append(m)
    if face_mats:
        for p, mi in zip(me.polygons, face_mats):
            p.material_index = mi
    for p in me.polygons:
        p.use_smooth = smooth
    link(obj, parent)
    return obj


def box(name, size, loc=(0, 0, 0), material=None, parent=None, origin="center"):
    """Axis aligned box. origin 'center' or 'bottom' (z at base)."""
    sx, sy, sz = (s / 2 for s in size)
    z0 = 0 if origin == "bottom" else -sz
    z1 = 2 * sz if origin == "bottom" else sz
    v = [(-sx, -sy, z0), (sx, -sy, z0), (sx, sy, z0), (-sx, sy, z0),
         (-sx, -sy, z1), (sx, -sy, z1), (sx, sy, z1), (-sx, sy, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return mesh_obj(name, v, f, material, parent, loc)


def box_minmax(name, lo, hi, material=None, parent=None):
    size = [hi[i] - lo[i] for i in range(3)]
    c = [(hi[i] + lo[i]) / 2 for i in range(3)]
    return box(name, size, c, material, parent)


def cylinder(name, r, depth, segs=8, axis="Z", loc=(0, 0, 0), material=None,
             parent=None, r_top=None, cap=True, rot_offset=0.0):
    r_top = r if r_top is None else r_top
    v, f = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs + rot_offset
        v.append((math.cos(a) * r, math.sin(a) * r, -depth / 2))
    for i in range(segs):
        a = 2 * math.pi * i / segs + rot_offset
        v.append((math.cos(a) * r_top, math.sin(a) * r_top, depth / 2))
    for i in range(segs):
        j = (i + 1) % segs
        f.append((i, j, segs + j, segs + i))
    if cap:
        f.append(tuple(reversed(range(segs))))
        f.append(tuple(range(segs, 2 * segs)))
    v = [_axis(p, axis) for p in v]
    return mesh_obj(name, v, f, material, parent, loc)


def _axis(p, axis):
    x, y, z = p
    if axis == "X":
        return (z, y, -x)
    if axis == "Y":
        return (x, z, -y)
    return p


def sphere(name, r, loc=(0, 0, 0), material=None, parent=None, segs=8, rings=5,
           scale=(1, 1, 1)):
    v, f = [(0, 0, -r)], []
    for j in range(1, rings):
        phi = math.pi * j / rings - math.pi / 2
        for i in range(segs):
            a = 2 * math.pi * i / segs
            v.append((math.cos(a) * math.cos(phi) * r, math.sin(a) * math.cos(phi) * r,
                      math.sin(phi) * r))
    v.append((0, 0, r))
    top = len(v) - 1
    for i in range(segs):
        f.append((0, 1 + (i + 1) % segs, 1 + i))
    for j in range(rings - 2):
        for i in range(segs):
            a = 1 + j * segs + i
            b = 1 + j * segs + (i + 1) % segs
            f.append((a, b, b + segs, a + segs))
    base = 1 + (rings - 2) * segs
    for i in range(segs):
        f.append((base + i, base + (i + 1) % segs, top))
    v = [(x * scale[0], y * scale[1], z * scale[2]) for x, y, z in v]
    return mesh_obj(name, v, f, material, parent, loc)


def join(objs, name):
    """Join meshes into the first; returns the joined object."""
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        objs[0].data.name = name
        return objs[0]
    ctx = bpy.context.copy()
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs,
                                   selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def apply_transform(obj):
    me = obj.data
    me.transform(obj.matrix_basis)
    obj.matrix_basis = Matrix.Identity(4)


def set_origin(obj, point):
    """Move the object's origin to `point` (world space) without moving geometry."""
    point = Vector(point)
    mw = obj.matrix_world.copy()
    local = mw.inverted() @ point
    obj.data.transform(Matrix.Translation(-local))
    obj.matrix_world = mw @ Matrix.Translation(local)


def boolean(target, cutter, op="DIFFERENCE"):
    mod = target.modifiers.new("bool", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    mod.solver = "EXACT"
    with bpy.context.temp_override(object=target, active_object=target):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def box_uv(obj, scale=1.0):
    """World-ish box projection so textures tile at `scale` metres per repeat."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            uv[li].uv = (u / scale, v / scale)


def tri_count(objs):
    n = 0
    for o in objs:
        if o.type == "MESH":
            n += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return n


# ---------------------------------------------------------------- export

def export_glb(path, objects=None, lights=False):
    path = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(objects is None or o in objects)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=objects is not None,
        export_apply=True, export_lights=lights, export_cameras=False,
        export_yup=True, export_extras=True, export_materials="EXPORT",
        export_image_format="AUTO")
    print("exported", path, os.path.getsize(path), "bytes")
    return path


# ---------------------------------------------------------------- previews

def render_setup(res=(960, 540), samples=24, world="#9fb8cc", strength=0.6):
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.samples = samples
    s.cycles.use_denoising = True
    s.render.resolution_x, s.render.resolution_y = res
    s.render.resolution_percentage = 100
    s.view_settings.view_transform = "Standard"
    if s.world is None:
        s.world = bpy.data.worlds.new("World")
    s.world.use_nodes = True
    bg = s.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*srgb_to_linear(_hex(world)), 1)
    bg.inputs[1].default_value = strength
    return s


def sun(name="Sun", rot=(50, 0, 30), energy=3.0, color="#fff4e0"):
    l = bpy.data.lights.new(name, "SUN")
    l.energy = energy
    l.color = srgb_to_linear(_hex(color))
    o = bpy.data.objects.new(name, l)
    o.rotation_euler = [math.radians(a) for a in rot]
    return link(o)


def camera_look(loc, target, lens=35, name="PreviewCam"):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = link(bpy.data.objects.new(name, bpy.data.cameras.new(name)))
    cam.data.lens = lens
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(path, lo_fi=None):
    """Render to repo-relative path. lo_fi=(w,h) also writes a pixelated copy."""
    path = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    s = bpy.context.scene
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)
    if lo_fi:
        img = bpy.data.images.load(path)
        w, h = img.size
        img.scale(*lo_fi)
        img.scale(w, h)  # bilinear up; fine for a preview
        img.filepath_raw = path.replace(".png", "_lofi.png")
        img.save()
    print("rendered", path)


def hide_for_render(objs, hide=True):
    for o in objs:
        o.hide_render = hide


def turn_scene_z180():
    """Rotate the whole scene 180 degrees about Z (world origin).

    Cars are authored facing -Y (glTF +Z); this project's Godot convention
    is nose toward -Z, i.e. Blender +Y. Mesh data whose object has no
    rotation is baked so nodes keep clean transforms; objects that carry a
    meaningful rotation (the tilted steering wheel) keep it, premultiplied.
    """
    R = Matrix.Rotation(math.pi, 4, "Z")
    bpy.context.view_layer.update()  # new objects' matrix_world is stale until then
    worlds = {o: o.matrix_world.copy() for o in bpy.data.objects}

    def has_rotation(o):
        m = o.matrix_basis.to_3x3()
        return any(abs(m[i][j] - (1.0 if i == j else 0.0)) > 1e-6 for i in range(3) for j in range(3))

    def place(o):
        mw = worlds[o]
        if has_rotation(o):
            target = R @ mw
        else:
            if o.type == "MESH":
                o.data.transform(R)
            target = Matrix.Translation(R @ mw.translation)
        if o.parent is not None:
            o.matrix_parent_inverse = Matrix.Identity(4)
            o.matrix_basis = o.parent.matrix_world.inverted() @ target
        else:
            o.matrix_basis = target
        bpy.context.view_layer.update()
        for c in o.children:
            place(c)

    for o in [o for o in bpy.data.objects if o.parent is None]:
        place(o)


def done():
    """Exit without tearing bpy down (the PyPI bpy module can segfault at exit)."""
    import sys
    sys.stdout.flush()
    if not bpy.app.binary_path or "python" in os.path.basename(bpy.app.binary_path).lower():
        os._exit(0)
