"""The 2007-on Fiat 500 (type 312) and its derivatives.

Real proportions: length 3.546 m, width 1.627 m, height 1.488 m,
wheelbase 2.300 m, track ~1.41 m. The origin is on the ground, midway
between the axles; the car faces -Y in Blender (+Z in Godot). Right hand
drive: the driver sits at -X. The body shape lives in fiat500_shell.py.

`build(spec)` returns the exported objects. Spec keys (all optional):
  paint            body colour (hex)
  wear             0..1 sun fade / grime on the paint texture (0 = showroom)
  roof             'steel' | 'glass' | 'fabric';  roof_color for two-tone
  front            'pop' | 'abarth'
  wheels           wheels.STYLES key
  chrome           chrome trim instead of satin/black
  mirror_color     mirror caps (hex)
  stripes          hex or None: side stripe along the doors (Abarth style)
  racing_stripes   hex or None: twin stripes over bonnet and roof
  spoiler          bool: roof spoiler over the rear window
  seat_upper, seat_lower, seat_wear (bool: tape + scuffed bolster on the driver's seat)
  dash             fascia colour
  plate            plate text;  phone_holder (bool)
"""
import math

import bpy  # noqa: I001  (bpy must load before bmesh)
import bmesh
from mathutils import Vector

from . import carkit as K
from . import common as C
from . import fiat500_shell as S
from . import textures as TX
from . import wheels as W

TRACK = 1.41
AXLE_F, AXLE_R = S.AXLE_F, S.AXLE_R
DOOR_Y0, DOOR_Y1 = S.DOOR_Y0, S.DOOR_Y1


def materials(spec, st):
    paint = spec.get("paint", "#f2f0ea")
    wear = spec.get("wear", 0.0)
    if wear > 0:
        img = TX.worn_paint("paint_worn", paint, S.zone_fn(st), fade=wear)
        paint_mat = C.mat("Paint", image=img, rough=0.4, metal=0.3)
    else:
        paint_mat = C.mat("Paint", paint, rough=0.35, metal=0.15)
    satin = "#d8dadc" if spec.get("chrome") else "#4a4b4d"
    return {
        "paint": paint_mat,
        "glass": _glass(),
        "trim": C.mat("TrimBlack", "#1b1c1e", rough=0.7),
        "seam": C.mat("Seam", "#0b0b0c", rough=1.0),
        "under": C.mat("Underbody", "#141414", rough=0.9),
        "cabin": C.mat("CabinTrim", spec.get("cabin", "#3a3b3e"), rough=0.85),
        "headliner": C.mat("Headliner", spec.get("headliner", "#cbc4b6"), rough=0.95),
        "chrome": C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9),
        "satin": C.mat("Moustache", satin, rough=0.35, metal=0.6),
        "insert": C.mat("BumperInsert", "#3c3d40", rough=0.6),
        "head": C.mat("LampHead", "#a3adb3", rough=0.05, metal=0.5, emit="#fff6dc", emit_strength=0.0),
        "reflector": C.mat("LampReflector", "#8a9094", rough=0.2, metal=0.9),
        "tail": C.mat("LampTail", "#a8121a", rough=0.3, emit="#ff1a10", emit_strength=0.0),
        "amber": C.mat("LampAmber", "#e08a20", rough=0.3),
        "white": C.mat("LampClear", "#e6e6e6", rough=0.2),
        "badge": C.mat("BadgeRed", "#a0101a", rough=0.4),
        "dark": C.mat("Grille", "#0c0c0d", rough=0.8),
        "plate": C.mat("Plate", image=TX.plate(spec.get("plate", "1CIN-500")), rough=0.6),
        "mirror": C.mat("MirrorCap", spec.get("mirror_color", paint), rough=0.35),
        "roof": C.mat("RoofPaint", spec.get("roof_color", paint), rough=0.35, metal=0.1),
        "stripe": C.mat("Stripe", spec.get("stripes") or "#ffffff", rough=0.4),
        "abarth_red": C.mat("AbarthRed", "#b0141c", rough=0.4),
        "abarth_yellow": C.mat("AbarthYellow", "#f0c419", rough=0.4),
        "honeycomb": C.mat("Honeycomb", image=TX.honeycomb(), rough=0.7),
        "dash": C.mat("DashFascia", spec.get("dash", paint), rough=0.35, metal=0.4),
        "dashmat": C.mat("DashMat", image=TX.carpet("dashmat", "#1d1d1e", 9), rough=1.0),
        "rubber": C.mat("FloorMat", image=TX.carpet("floormat", "#121213", 4, 8), rough=0.9),
        "gauge": C.mat("Gauges", image=TX.gauges(), rough=0.4, emit="#203040", emit_strength=0.2),
        "knob": C.mat("KnobBlack", "#0e0e0f", rough=0.25),
        "post": C.mat("HeadrestPost", "#b9bcc0", rough=0.3, metal=0.8),
    }


def _glass():
    # light and barely tinted, so the cabin and the view out both read
    m = C.mat("Glass", "#9fb4bd", rough=0.05, metal=0.2, alpha=0.18)
    m.use_backface_culling = False
    return m


def build(spec):
    C.clear_material_cache()
    abarth = spec.get("front") == "abarth"
    shell, st = S.shell(abarth)
    M = materials(spec, st)
    ride = spec.get("ride", 0.0)

    # an uncut copy of the surface: glass, seals and details are projected onto it
    ref = C.link(bpy.data.objects.new("ref", shell.data.copy()))
    S.cut_windows(shell)
    S.classify(shell)
    seams = S.shut_lines(shell, M["seam"], width=0.009)   # narrower than the doors' shut gap
    nrm = K.vertex_normals(shell)
    parts = K.split_by_tag(shell, {
        "Body": {"Paint": M["paint"], "Trim": M["trim"], "Under": M["under"]},
        "Door_L": {"DoorL": M["paint"]},
        "Door_R": {"DoorR": M["paint"]},
    }, smooth_angle=50)
    body = parts["Body"]
    _two_tone_roof(body, M, spec)

    glass, door_glass = _windows(ref, M)
    body_bits = [seams] + glass["seals"]
    body_bits += _front(ref, M, spec, abarth)
    body_bits += _rear(ref, M, spec, abarth)
    body_bits += _sides(ref, M, spec, abarth)
    door_bits = {1: [], -1: []}
    if spec.get("spoiler"):
        body_bits.append(_spoiler(ref, M, abarth))
    if spec.get("stripes"):
        body_bits += _side_stripes(ref, M, door_bits)
    if spec.get("racing_stripes"):
        body_bits += _racing_stripes(ref, spec["racing_stripes"])
    roof = spec.get("roof", "steel")
    if roof == "glass":
        body_bits.append(K.stick_box("sunroof", K.on_top(ref, 0, 0.45), (1.0, 0.95, 0.012), M["glass"]))
    elif roof == "fabric":
        body_bits.append(_fabric_roof(ref, spec))

    K.solidify_along(body, 0.025, M["cabin"], nrm)
    _headliner(body, M)
    root_objs = [body, C.join(glass["panes"], "Glass")]

    for side, sx in (("L", 1), ("R", -1)):
        door = parts["Door_" + side]
        handle = K.stick_box("handle", K.on_side(ref, sx, 0.33, 0.85), (0.19, 0.028, 0.03),
                             M["chrome"] if spec.get("chrome", True) else M["trim"])
        card = _door_card(door, sx, M)
        K.solidify_along(door, 0.03, M["cabin"], nrm, gap=0.005, level=0.6)   # with a real shut gap
        door = C.join([door, handle, _mirror(ref, sx, M)] + card + door_glass[sx]["seals"] + door_bits[sx],
                      "Door_" + side)
        # hinge out at the skin and just ahead of the shut line, so the
        # frame up the A-pillar swings clear of the wing and the dash
        C.set_origin(door, (sx * HINGE_X, HINGE_Y, 0.6))
        g = C.join(door_glass[sx]["panes"], "Door_%s_Glass" % side)
        g.parent = door
        g.matrix_parent_inverse = door.matrix_world.inverted()
        root_objs.append(door)

    lamps_h = [o for o in body_bits if o.get("lamp") == "head"]
    lamps_t = [o for o in body_bits if o.get("lamp") == "tail"]
    rest = [o for o in body_bits if o not in lamps_h and o not in lamps_t]
    body = C.join([body] + rest, "Body")
    root_objs[0] = body
    root_objs.append(C.join(lamps_h, "Lights_Head"))
    root_objs.append(C.join(lamps_t, "Lights_Tail"))

    cab = _cabin_bvh(root_objs)
    interior, wheel_obj = _interior(M, spec, cab)
    root_objs += [interior, wheel_obj]
    # where a pair of period spotlights clamps on, just proud of the bumper
    spot, _ = K.on_front(ref, 0, 0.40)
    bpy.data.objects.remove(ref, do_unlink=True)

    ws = spec.get("wheels", "pop_trim")
    hub_z = W.radius(ws)
    for nm, x, y in (("FL", 1, AXLE_F), ("FR", -1, AXLE_F), ("RL", 1, AXLE_R), ("RR", -1, AXLE_R)):
        root_objs.append(W.build("Wheel_" + nm, ws, loc=(x * TRACK / 2, y, hub_z), right=x < 0))

    C.empty("Cam_Cockpit", (-0.36, 0.20, 1.17 + ride))
    C.empty("Mount_Exhaust", (0.42, 1.70, 0.24 + ride))
    C.empty("Mount_Roof", (0, 0.35, 1.49 + ride))
    # trinket slots (scripts/vehicle/trinkets.gd): under the rear-view mirror,
    # on the passenger side of the dash mat, the parcel shelf and the gear knob
    C.empty("Mount_Mirror", (0, -0.30, 1.295 + ride))
    C.empty("Mount_Dash", (0.18, -0.77, 0.985 + ride))
    C.empty("Mount_Shelf", (0.32, 1.38, 0.95 + ride))
    C.empty("Mount_Gear", (0, -0.37, 0.595 + ride))
    C.empty("Mount_Spotlights", (0, spot.y - 0.03, spot.z + ride))
    if ride:
        for o in root_objs:
            if not o.name.startswith("Wheel_"):
                o.location.z += ride
    return root_objs


HINGE_X, HINGE_Y = 0.83, -0.87


def _cabin_bvh(objs):
    """BVH of the closed shell, doors and glass, to fit the interior inside."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    dg = bpy.context.evaluated_depsgraph_get()
    todo = list(objs)
    for o in objs:
        todo += [c for c in o.children if c.type == "MESH"]
    for o in todo:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        o.evaluated_get(dg).to_mesh_clear()
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def _half_width(cab, y, z, margin=0.015, cap=0.72):
    """Inner half width of the cabin at (y, z), less a margin."""
    hit = cab.ray_cast(Vector((0, y, z)), Vector((1, 0, 0)), 2.0)
    return cap if hit[0] is None else min(cap, hit[0].x - margin)


def _roof_z(cab, x, y):
    hit = cab.ray_cast(Vector((x, y, 1.2)), Vector((0, 0, 1)), 1.0)
    return 1.45 if hit[0] is None else hit[0].z


def _fitted_profile(name, prof, cab, mats, seg_mat, margin=0.015, cap=0.72):
    """Closed (y, z) side profile extruded across the cabin, each point as
    wide as the cabin allows there. seg_mat[i] is the material of the band
    from point i to i+1."""
    n = len(prof)
    verts = []
    for y, z in prof:
        hw = _half_width(cab, y, z, margin, cap)
        verts += [(-hw, y, z), (hw, y, z)]
    faces, fm = [], []
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
        fm.append(seg_mat[i])
    faces.append(tuple(2 * i for i in range(n)))
    fm.append(seg_mat[-1])
    faces.append(tuple(2 * i + 1 for i in reversed(range(n))))
    fm.append(seg_mat[-1])
    o = C.mesh_obj(name, verts, faces, mats=mats, face_mats=fm)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


# ------------------------------------------------------------------ glass

def _pane(name, ref, poly, frame, M):
    """Glass slightly bigger than the opening, sitting just inside the surface."""
    return K.project_poly(name, ref, K.offset_poly(poly, -0.015), frame, M["glass"], offset=-0.012, cuts=3)


def _seal(name, ref, poly, frame, M, border=0.045):
    """Black rubber seal / frit ring round an opening."""
    return K.project_poly(name, ref, K.offset_poly(poly, -0.02), frame, None, offset=0.004, cuts=1,
                          border=border, border_mat=M["trim"])


def _windows(ref, M):
    body = {"panes": [], "seals": []}
    doors = {}
    door_poly = S.clip_y(S.DLO, hi=S.B_PILLAR[0])
    quarter = S.clip_y(S.DLO, lo=S.B_PILLAR[1])
    pillar = S.clip_y(K.offset_poly(S.DLO, -0.03), lo=S.B_PILLAR[0] - 0.01, hi=S.B_PILLAR[1] + 0.01)
    for sx in (1, -1):
        fr = K.side_frame(sx)
        doors[sx] = {"panes": [_pane("door_glass", ref, door_poly, fr, M)],
                     "seals": [_seal("door_seal", ref, door_poly, fr, M, border=0.032)]}
        body["panes"].append(K.project_poly("quarter_glass", ref,
                                            S.clip_y(K.offset_poly(quarter, -0.015), lo=S.B_PILLAR[1] + 0.026),
                                            fr, M["glass"], offset=-0.012, cuts=2))
        body["seals"].append(_seal("quarter_seal", ref, quarter, fr, M))
        body["seals"].append(K.project_poly("b_pillar", ref, pillar, fr, M["trim"], offset=0.005, cuts=2))
    for name, poly, fr in (("windscreen", S.WINDSCREEN, K.top_frame()),
                           ("rear_window", S.REAR_WINDOW, K.rear_frame())):
        body["panes"].append(_pane(name, ref, poly, fr, M))
        body["seals"].append(_seal(name + "_seal", ref, poly, fr, M, border=0.035))
    return body, doors


# ------------------------------------------------------------------ details

def _two_tone_roof(body, M, spec):
    if "roof_color" not in spec:
        return
    me = body.data
    me.materials.append(M["roof"])
    idx = len(me.materials) - 1
    pm = list(me.materials).index(M["paint"])
    for p in me.polygons:
        if p.material_index == pm and p.center.z > 1.38 and -0.12 < p.center.y < 1.2:
            p.material_index = idx


def _headliner(body, M):
    """Inner faces high in the cabin read as the beige headliner and pillars."""
    me = body.data
    ci = list(me.materials).index(M["cabin"])
    me.materials.append(M["headliner"])
    hi = len(me.materials) - 1
    for p in me.polygons:
        if p.material_index == ci and p.center.z > 1.0:
            p.material_index = hi


def _mirror(ref, sx, M):
    """Rounded mirror on a short arm from the door skin just below the
    front of the side glass (the head sits level with the middle of the
    windscreen in plan, as on the real car)."""
    loc, nor = K.on_side(ref, sx, -0.55, 1.0)
    head = Vector((sx * 0.85, -0.51, 1.065))
    mid = (loc + head) / 2
    arm = C.box("mirror_arm", ((head.x - loc.x) * sx + 0.02, 0.06, 0.035), mid + Vector((0, 0, -0.01)), M["trim"])
    arm.rotation_euler = (0, sx * -math.atan2(head.z - loc.z, (head.x - loc.x) * sx), 0)
    C.apply_transform(arm)
    cap = C.sphere("mirror_cap", 0.088, head, M["mirror"], segs=10, rings=6, scale=(1.05, 0.62, 0.74))
    glass = K.lamp_disc("mirror_glass", 0.072, 0.01, head + Vector((0, 0.047, 0)), (0, 1, 0),
                        M["reflector"], segs=10, sx=1.05, sz=0.72)
    return C.join([arm, cap, glass], "Mirror")


def _door_card(door, sx, M):
    """Round speaker, armrest and pull on the inside of the door."""
    loc, nor = K.hit(door, (0, -0.35, 0.45), (sx, 0, 0))
    spk = K.stick_disc("speaker", door, (loc, -nor), 0.085, 0.02, M["dark"], segs=12, proud=0.045)
    loc2, nor2 = K.hit(door, (0, 0.05, 0.72), (sx, 0, 0))
    arm = C.box("armrest", (0.06, 0.40, 0.05), loc2 - nor2 * 0.07, M["cabin"])
    pull = C.box("pull", (0.03, 0.12, 0.02), loc2 - nor2 * 0.075 + Vector((0, -0.1, 0.12)), M["chrome"])
    return [spk, arm, pull]


HEAD_X, HEAD_Z, HEAD_R = 0.555, 0.775, 0.098   # big round lamps at the bonnet's front corners
DRL_X, DRL_Z, DRL_R = 0.650, 0.545, 0.05       # small round lamps in the bumper below them


def _bonnet_line(ref, M):
    """Clamshell bonnet shut line: across the nose at headlamp-centre height,
    up over each lamp, then back along the top of the wings to the base of
    the A-pillars."""
    rays = []
    fr = K.front_frame()

    def wing(sx, ys):
        # measured off the side photo: drops from the A-pillar base, then
        # runs nearly level over the front wheel
        for y in ys:
            t = min(1.0, max(0.0, (y + 1.10) / 0.16))
            z = 0.835 + (0.99 - 0.835) * t * t - 0.02 * max(0.0, (-1.25 - y) / 0.25)
            rays.append(((sx * 3, y, z), (-sx, 0, 0)))

    def over_lamp(sx):
        # starts on the lamp's outer shoulder, level with the end of the wing run
        r = HEAD_R + 0.008
        for a in [160 - 20 * i for i in range(9)]:
            u = sx * HEAD_X + r * math.cos(math.radians(a))
            v = HEAD_Z + r * math.sin(math.radians(a))
            rays.append(fr(u, v))
    # the wing run ends just behind the lamp (further forward on the
    # Abarth's longer nose)
    lamp_y = K.on_front(ref, HEAD_X, HEAD_Z)[0].y
    end = lamp_y + 0.185
    ys = [-0.94 + (end + 0.94) * i / 11 for i in range(12)]
    wing(-1, ys)
    over_lamp(-1)
    half = HEAD_X - HEAD_R - 0.008
    for i in range(1, 12):
        x = -half + i * half / 6
        rays.append(fr(x, HEAD_Z + 0.055 * (1 - (x / half) ** 2)))
    over_lamp(1)
    wing(1, list(reversed(ys)))
    return S.ribbon("bonnet_line", ref, rays, 0.010, M["seam"])


def _front(ref, M, spec, abarth):
    out = [_bonnet_line(ref, M)]
    chrome = M["chrome"] if spec.get("chrome", False) else M["satin"]
    for sx in (1, -1):
        # big round headlamps set into the bonnet's corners, small round lamps below
        w = K.on_front(ref, sx * HEAD_X, HEAD_Z)
        h = K.stick_disc("head", ref, w, HEAD_R - 0.01, 0.04, M["head"], segs=16, proud=-0.002)
        h["lamp"] = "head"
        out.append(K.stick_disc("head_ring", ref, w, HEAD_R, 0.03, M["chrome"], segs=16, proud=-0.004))
        out.append(K.stick_disc("head_reflector", ref, w, 0.05, 0.04, M["reflector"], segs=12, proud=0.0))
        wl = K.on_front(ref, sx * DRL_X, DRL_Z)
        lo = K.stick_disc("drl", ref, wl, DRL_R - 0.008, 0.04, M["head"], segs=10, proud=0.004)
        lo["lamp"] = "head"
        out.append(K.stick_disc("drl_ring", ref, wl, DRL_R, 0.03, M["insert"], segs=10))
        out += [h, lo]
        if abarth:
            continue
        # moustache: a slim bar either side of the badge, rising slightly outward
        for x in (0.11, 0.18, 0.25, 0.32):
            out.append(K.stick_box("whisker", K.on_front(ref, sx * x, 0.668 + (x - 0.1) * 0.02),
                                   (0.075, 0.017, 0.016), chrome))
    if abarth:
        out += _abarth_front(ref, M)
    else:
        out.append(K.stick_disc("badge", ref, K.on_front(ref, 0, 0.672), 0.040, 0.03, M["badge"], segs=12))
        out.append(K.stick_disc("badge_ring", ref, K.on_front(ref, 0, 0.672), 0.046, 0.02, M["chrome"], segs=12))
        grille = [(-0.42, 0.30), (0.42, 0.30), (0.47, 0.33), (0.46, 0.43), (-0.46, 0.43), (-0.47, 0.33)]
        out.append(K.project_poly("grille", ref, grille, K.front_frame(), M["dark"], offset=0.006, cuts=5))
        # black lower lip across the bottom of the bumper
        lip = [(-0.50, 0.24), (0.50, 0.24), (0.54, 0.265), (0.52, 0.30), (-0.52, 0.30), (-0.54, 0.265)]
        out.append(K.project_poly("bumper_lip", ref, lip, K.front_frame(), M["trim"], offset=0.006, cuts=6))
    pz = 0.36 if abarth else 0.48
    out.append(K.stick_box("plate_holder", K.on_front(ref, 0, pz), (0.42, 0.16, 0.03), M["trim"], proud=0.02))
    plate = K.stick_box("plate_f", K.on_front(ref, 0, pz), (0.372, 0.134, 0.01), M["plate"], proud=0.05)
    K.planar_uv(plate, 0, 2)
    out.append(plate)
    # cowl panel and wipers parked at the base of the windscreen
    cowl = [(-0.53, -1.025), (0.0, -1.06), (0.53, -1.025), (0.58, -0.955), (0.0, -0.99), (-0.58, -0.955)]
    out.append(K.project_poly("cowl", ref, cowl, K.top_frame(), M["trim"], offset=0.004, cuts=3))
    for x, y, ln in ((-0.30, -0.935, 0.56), (0.20, -0.95, 0.50)):
        wp = K.stick_box("wiper", K.on_top(ref, x, y), (ln, 0.02, 0.015), M["trim"], proud=0.01)
        out.append(wp)
    return out


def _densify(pts, step):
    """Extra points along a polyline so a projected ribbon hugs the surface."""
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.dist(a, b) / step + 0.999))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]
    return out + [pts[-1]]


def _tail_lamp(ref, sx, M):
    """Tall rounded lamp on the rear corner: red above, clear below with the
    round reversing lamp, in a white rim."""
    centre = Vector((sx * 0.645, 1.43, 0.875))
    normal = Vector((sx * 0.50, 0.866, 0))
    fr = S.plane_frame(centre, normal)
    outline = S.rounded_rect(0.165, 0.265, 0.055)
    rim = K.project_poly("tail_rim", ref, outline, fr, None, offset=0.006, cuts=1, border=0.013,
                         border_mat=M["white"])
    red = [(u, v + 0.035) for u, v in S.rounded_rect(0.14, 0.175, 0.045)]
    lens = K.project_poly("tail_red", ref, red, fr, M["tail"], offset=0.008, cuts=2)
    lens["lamp"] = "tail"
    clear = [(u, v - 0.088) for u, v in S.rounded_rect(0.14, 0.064, 0.028)]
    clear = K.project_poly("tail_clear", ref, clear, fr, M["white"], offset=0.007, cuts=1)
    loc, nor = K.hit(ref, fr(0, -0.088)[0], fr(0, -0.088)[1])
    rev = K.stick_disc("reverse", ref, (loc, nor), 0.022, 0.02, M["reflector"], segs=8, proud=0.006)
    return [rim, lens, clear, rev]


def _rear(ref, M, spec, abarth):
    out = []
    chrome = M["chrome"]
    for sx in (1, -1):
        out += _tail_lamp(ref, sx, M)
    # tailgate shut line: round the glass and down inside the lamps
    gate = [(-0.47, 0.72), (-0.49, 0.85), (-0.51, 0.99), (-0.575, 1.065), (-0.585, 1.20), (-0.56, 1.34),
            (-0.49, 1.405), (0.49, 1.405), (0.56, 1.34), (0.585, 1.20), (0.575, 1.065), (0.51, 0.99),
            (0.49, 0.85), (0.47, 0.72)]
    out.append(K.project_line("tailgate_line", ref, _densify(gate + gate[:1], 0.05), K.rear_frame(), 0.012,
                              M["seam"]))
    out.append(K.project_line("bumper_groove", ref, [(x / 20, 0.34) for x in range(-11, 12)], K.rear_frame(),
                              0.03, M["dark"]))
    pz = 0.83
    out.append(K.stick_box("plate_recess", K.on_rear(ref, 0, pz), (0.43, 0.17, 0.01), M["insert"]))
    plate = K.stick_box("plate_r", K.on_rear(ref, 0, pz), (0.372, 0.134, 0.01), M["plate"], proud=0.008)
    K.planar_uv(plate, 0, 2, flip_u=True)
    out.append(plate)
    out.append(K.stick_box("plate_chrome", K.on_rear(ref, 0, pz + 0.105), (0.44, 0.04, 0.02), chrome))
    if abarth:
        out += _abarth_badge(ref, K.rear_frame(), 0, 1.025, M, 0.8)
    else:
        out.append(K.stick_disc("badge_r", ref, K.on_rear(ref, 0, 1.025), 0.040, 0.02, M["badge"], segs=12))
        out.append(K.stick_disc("badge_r_ring", ref, K.on_rear(ref, 0, 1.025), 0.046, 0.015, chrome, segs=12))
    # roof lip over the rear window
    out.append(K.stick_box("roof_lip", K.on_rear(ref, 0, 1.418), (0.84, 0.035, 0.03), M["paint"]))
    # rear wiper parked along the bottom of the glass
    loc, nor = K.on_rear(ref, -0.17, 1.13)
    out.append(K.stick_box("rear_wiper", (loc, nor), (0.40, 0.02, 0.02), M["trim"], proud=0.012))
    # roof antenna, raked back
    loc, nor = K.on_top(ref, 0, 0.93)
    ant = C.cylinder("antenna", 0.006, 0.36, segs=5, material=M["trim"])
    ant.rotation_euler = (math.radians(-38), 0, 0)
    ant.location = loc + Vector((0, 0.11, 0.14))
    C.apply_transform(ant)
    out.append(ant)
    out.append(K.stick_box("antenna_base", (loc, nor), (0.03, 0.07, 0.025), M["trim"]))
    if abarth:
        # black diffuser across the bottom of the bumper, cut away for the pipes
        diff = [(-0.62, 0.235), (0.62, 0.235), (0.58, 0.31), (-0.58, 0.31)]
        out.append(K.project_poly("diffuser", ref, diff, K.rear_frame(), M["dark"], offset=0.006, cuts=3))
        for x in (-0.30, -0.10, 0.10, 0.30):
            out.append(K.project_line("diffuser_fin", ref, [(x, 0.24), (x, 0.305)], K.rear_frame(), 0.018,
                                      M["trim"], offset=0.012))
    return out


def _sides(ref, M, spec, abarth=False):
    out = []
    for sx in (1, -1):
        if abarth:
            # side skirt between the arches
            skirt = [(-0.80, 0.215), (0.80, 0.215), (0.80, 0.285), (-0.80, 0.285)]
            out.append(K.project_poly("skirt", ref, skirt, K.side_frame(sx), M["trim"], offset=0.008, cuts=3))
        out.append(K.stick_box("side_ind", K.on_side(ref, sx, -0.90, 0.80), (0.045, 0.022, 0.01), M["white"]))
        if spec.get("chrome"):
            out.append(K.stick_box("sill_trim", K.on_side(ref, sx, -0.10, 0.30), (1.10, 0.02, 0.01), M["chrome"]))
    # round fuel flap on the right rear quarter
    w = K.on_side(ref, -1, 1.22, 0.84)
    out.append(K.stick_disc("fuel_seam", ref, w, 0.078, 0.01, M["seam"], segs=14, proud=0.001))
    out.append(K.stick_disc("fuel_flap", ref, w, 0.07, 0.01, M["paint"], segs=14, proud=0.003))
    return out


def _spoiler(ref, M, abarth=False):
    """Wedge carrying the roof line out over the rear window."""
    reach = 0.17 if abarth else 0.11
    xs = [i / 8 * 0.56 for i in range(-8, 9)]
    ring = []
    for x in xs:
        p0 = K.on_top(ref, x * 0.98, 0.98)[0]
        p1 = K.on_top(ref, x, 1.10)[0]
        p2 = p1 + Vector((0, reach, -0.03))
        p3 = p2 + Vector((0, -0.03, -0.035))
        p4 = p1 + Vector((0, 0.0, -0.035))
        ring.append([p0 + Vector((0, 0, 0.004)), p1 + Vector((0, 0, 0.012)), p2, p3, p4])
    verts = [v for r in ring for v in r]
    n = 5
    faces = []
    for i in range(len(ring) - 1):
        for k in range(n):
            a, b = i * n + k, i * n + (k + 1) % n
            faces.append((a, b, b + n, a + n))
    faces.append(tuple(range(n - 1, -1, -1)))
    last = (len(ring) - 1) * n
    faces.append(tuple(last + k for k in range(n)))
    o = C.mesh_obj("spoiler", verts, faces, M["paint"])
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def _side_stripes(ref, M, door_bits):
    """Stripe along the bottom of the doors, split at the shut lines so the
    door part swings with the door."""
    out = []
    z0, z1 = 0.36, 0.43
    for sx in (1, -1):
        fr = K.side_frame(sx)
        for y0, y1, dst in ((-0.80, DOOR_Y0 - 0.006, out), (DOOR_Y0 + 0.006, DOOR_Y1 - 0.006, door_bits[sx]),
                            (DOOR_Y1 + 0.006, 0.80, out)):
            poly = [(y0, z0), (y1, z0), (y1, z1), (y0, z1)]
            dst.append(K.project_poly("stripe_side", ref, poly, fr, M["stripe"], offset=0.006, cuts=3))
    return out


def _racing_stripes(ref, color):
    """Twin stripes over the bonnet and the roof (the glass stays clear)."""
    mat = C.mat("RacingStripe", color, rough=0.35, metal=0.15)
    out = []
    for x0, x1 in ((0.07, 0.21), (-0.21, -0.07)):
        for y0, y1 in ((-1.70, -0.87), (-0.10, 1.06)):
            poly = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
            out.append(K.project_poly("racing_stripe", ref, poly, K.top_frame(), mat, offset=0.006, cuts=4))
    return out


def _abarth_badge(ref, frame, u, v, M, scale=1.0):
    """The shield: red top, yellow-and-red striped bottom (scorpion implied)."""
    w, h = 0.07 * scale, 0.085 * scale
    shield = [(u - w / 2, v + h / 2), (u - w / 2, v - h * 0.1), (u - w * 0.3, v - h * 0.38), (u, v - h / 2),
              (u + w * 0.3, v - h * 0.38), (u + w / 2, v - h * 0.1), (u + w / 2, v + h / 2)]
    out = [K.project_poly("abarth_badge", ref, shield, frame, M["abarth_red"], offset=0.008, cuts=1,
                          border=0.006 * scale, border_mat=M["chrome"])]
    band = [(u - w * 0.4, v - h * 0.05), (u + w * 0.4, v - h * 0.05), (u + w * 0.4, v - h * 0.2),
            (u - w * 0.4, v - h * 0.2)]
    out.append(K.project_poly("abarth_band", ref, band, frame, M["abarth_yellow"], offset=0.010, cuts=1))
    return out


def _abarth_front(ref, M):
    """Abarth bumper: big honeycomb mouth, two side intakes, a slot between
    the small lamps and the shield on the nose."""
    fr = K.front_frame()
    mouth = [(-0.40, 0.19), (0.40, 0.19), (0.47, 0.25), (0.45, 0.36), (-0.45, 0.36), (-0.47, 0.25)]
    out = [K.project_poly("mouth", ref, mouth, fr, M["honeycomb"], offset=0.008, cuts=8, border=0.022,
                          border_mat=M["trim"])]
    C.box_uv(out[0], 0.08)
    for sx in (1, -1):
        intake = [(sx * 0.51, 0.21), (sx * 0.63, 0.235), (sx * 0.645, 0.34), (sx * 0.53, 0.35)]
        if sx < 0:
            intake = intake[::-1]
        out.append(K.project_poly("intake", ref, intake, fr, M["honeycomb"], offset=0.008, cuts=5, border=0.016,
                                  border_mat=M["trim"]))
        C.box_uv(out[-1], 0.08)
    slot = [(-0.30, 0.445), (0.30, 0.445), (0.27, 0.49), (-0.27, 0.49)]
    out.append(K.project_poly("slot", ref, slot, fr, M["dark"], offset=0.006, cuts=6))
    out.append(K.project_line("splitter", ref, [(x / 20, 0.175) for x in range(-9, 10)], fr, 0.03, M["trim"],
                              offset=0.012))
    out += _abarth_badge(ref, fr, 0, 0.575, M)
    return out


def _fabric_roof(ref, spec):
    fab = C.mat("RoofFabric", spec.get("fabric", "#2a1f1a"), rough=1.0)
    return K.stick_box("fabric_roof", K.on_top(ref, 0, 0.42), (1.12, 1.30, 0.02), fab)


# ------------------------------------------------------------------ interior

def _interior(M, spec, cab):
    """Cabin fitted inside the shell: everything stays clear of the wheel
    tubs (front inner wall x 0.44, rear 0.53), the glass and the doors."""
    bits = []
    # floor between the tubs (the rear floor steps up over the axle)
    bits.append(C.box_minmax("floor", (-0.66, -0.775, 0.222), (0.66, 0.775, 0.25), M["cabin"]))
    bits.append(C.box_minmax("footwell", (-0.42, -0.86, 0.222), (0.42, -0.775, 0.25), M["cabin"]))
    bits.append(C.box_minmax("floor_r", (-0.49, 0.775, 0.25), (0.49, 1.44, 0.27), M["cabin"]))
    for x in (-0.36, 0.36):
        bits.append(C.box_minmax("mat", (x - 0.21, -0.78, 0.25), (x + 0.21, -0.25, 0.26), M["rubber"]))
        bits.append(C.box_minmax("mat_r", (x - 0.18, 0.64, 0.25), (x + 0.18, 0.77, 0.26), M["rubber"]))
    bits.append(C.box_minmax("firewall", (-0.42, -0.90, 0.25), (0.42, -0.86, 0.66), M["cabin"]))
    # dashboard: one profile from the foot of the windscreen back to the
    # fascia, as wide as the cabin allows. Fuzzy dash mat on top, the
    # painted fascia band facing the driver, dark plastic underneath.
    prof = [(-0.93, 0.968), (-0.80, 0.982), (-0.67, 0.988), (-0.605, 0.975), (-0.575, 0.94),
            (-0.565, 0.86), (-0.56, 0.70), (-0.60, 0.62), (-0.86, 0.62), (-0.92, 0.80)]
    dash = _fitted_profile("dash", prof, cab, [M["dashmat"], M["dash"], M["cabin"]],
                           [0, 0, 0, 1, 1, 1, 2, 2, 2, 2], margin=0.02, cap=0.72)
    K.planar_uv(dash, 0, 1)
    bits.append(dash)
    # round vents at each end and a pair in the middle
    for x in (-0.64, 0.64):
        bits.append(K.lamp_disc("vent_ring", 0.055, 0.03, (x, -0.555, 0.79), (0, 1, 0), M["chrome"], segs=10))
        bits.append(K.lamp_disc("vent", 0.042, 0.03, (x, -0.548, 0.79), (0, 1, 0), M["dark"], segs=10))
    bits.append(C.box_minmax("vent_c", (-0.14, -0.57, 0.86), (0.14, -0.55, 0.92), M["dark"]))
    # "500" logo on the passenger side of the fascia
    for i in range(3):
        bits.append(K.lamp_disc("logo", 0.016, 0.01, (0.30 + i * 0.04, -0.556, 0.76), (0, 1, 0), M["chrome"], segs=6))
    # instrument binnacle in front of the driver (RHD: -X)
    bits.append(C.cylinder("binnacle", 0.10, 0.13, segs=12, axis="Y", loc=(-0.36, -0.63, 0.975), material=M["cabin"]))
    face = K.lamp_disc("gauge", 0.087, 0.01, (-0.36, -0.562, 0.975), (0, 1, 0.12), M["gauge"], segs=12)
    K.planar_uv(face, 0, 2)
    bits.append(face)
    # centre stack: radio, hazard button, climate pod, then the high gear lever
    bits.append(C.box_minmax("radio", (-0.12, -0.555, 0.75), (0.12, -0.545, 0.84), M["dark"]))
    bits.append(K.lamp_disc("hazard", 0.015, 0.01, (0, -0.545, 0.725), (0, 1, 0), M["badge"], segs=6))
    bits.append(C.box_minmax("stack", (-0.13, -0.80, 0.30), (0.13, -0.50, 0.70), M["cabin"]))
    for x in (-0.07, 0.0, 0.07):
        bits.append(K.lamp_disc("hvac", 0.025, 0.03, (x, -0.49, 0.64), (0, 1, 0.3), M["knob"], segs=8))
    gaiter = C.cylinder("gaiter", 0.06, 0.08, segs=8, loc=(0, -0.44, 0.50), material=M["knob"], r_top=0.025)
    gaiter.rotation_euler = (math.radians(-40), 0, 0)
    C.apply_transform(gaiter)
    lever = C.cylinder("gear_stick", 0.012, 0.12, segs=6, loc=(0, -0.40, 0.56), material=M["trim"])
    lever.rotation_euler = (math.radians(-40), 0, 0)
    C.apply_transform(lever)
    bits += [gaiter, lever, C.sphere("gear_knob", 0.034, (0, -0.37, 0.61), M["knob"], segs=8, rings=5)]
    bits.append(C.box_minmax("console", (-0.10, -0.50, 0.26), (0.10, 0.20, 0.40), M["cabin"]))
    hb = C.box("handbrake", (0.04, 0.25, 0.04), (0, 0.05, 0.45), M["trim"])
    hb.rotation_euler = (math.radians(12), 0, 0)
    C.apply_transform(hb)
    bits.append(hb)
    if spec.get("phone_holder"):
        bits.append(C.box_minmax("phone_clip", (-0.03, -0.54, 0.86), (0.03, -0.50, 0.90), M["knob"]))
        bits.append(C.box_minmax("phone_cradle", (-0.07, -0.50, 0.89), (0.07, -0.48, 0.96), M["knob"]))
    for x in (-0.48, -0.38, -0.27):
        bits.append(C.box("pedal", (0.06, 0.02, 0.08), (x, -0.76, 0.36), M["trim"]))
    # seats
    sm = _seat_mats(spec)
    bits += _seat(-0.36, 0.20, sm["driver"], sm["head"], M)
    bits += _seat(0.36, 0.20, sm["passenger"], sm["head"], M)
    bits += _rear_bench(sm["rear"], sm["head"])
    # parcel shelf from the back of the rear seat to the tailgate
    sy = 1.34
    hw = min(_half_width(cab, sy, 0.94), _half_width(cab, 1.42, 0.94))
    bits.append(C.box_minmax("parcel_shelf", (-hw, sy, 0.93), (hw, 1.42, 0.95), M["cabin"]))
    # sun visors folded up flat under the headliner behind the header rail
    for x in (-0.36, 0.36):
        y0, y1, half = -0.22, -0.06, 0.15
        top = min(_roof_z(cab, x + dx, yy) for dx in (-half, 0, half) for yy in (y0, y1)) - 0.008
        bits.append(C.box_minmax("visor", (x - half, y0, top - 0.012), (x + half, y1, top), M["headliner"]))
    # rear-view mirror on a short stalk glued to the top of the windscreen
    bits.append(C.box("rear_mirror", (0.21, 0.03, 0.06), (0, -0.30, 1.325), M["knob"]))
    hit = cab.ray_cast(Vector((0, -0.31, 1.37)), Vector((0, -1, 0)), 0.5)
    gy = hit[0].y + 0.004 if hit[0] is not None else -0.36
    bits.append(C.box_minmax("mirror_stem", (-0.015, gy, 1.35), (0.015, -0.315, 1.37), M["knob"]))
    interior = C.join(bits, "Interior")
    return _steering_wheel(M, interior)


def _seat_mats(spec):
    upper = spec.get("seat_upper", "#2c2d30")
    lower = spec.get("seat_lower", "#5d5f63")
    worn = spec.get("seat_wear", False)

    def back_tex(name, seed, tape):
        # lower fabric with the dark upper panel across the top of the backrest
        img = TX.fabric(name, lower, seed=seed,
                        tape=[(0.0, 0.10, 0.17, 0.45)] if tape else None,
                        wear=[(0.0, 0.0, 0.12, 0.08)] if tape else None)
        up = C.srgb_to_linear(C._hex(upper))
        w, h = img.size
        px = list(img.pixels)
        for y in range(int(h * 0.62), h):
            for x in range(w):
                i = (y * w + x) * 4
                k = 0.9 + 0.1 * ((x + y) % 2)
                px[i:i + 3] = [c * k for c in up]
        img.pixels = px
        img.pack()
        return img

    cushion_d = TX.fabric("seat_cushion_d", lower, seed=11,
                          wear=[(0.0, 0.0, 0.22, 0.30)] if worn else None)
    cushion_p = TX.fabric("seat_cushion_p", lower, seed=12)
    rear = TX.fabric("seat_rear", lower, seed=13)
    return {
        "driver": {"back": C.mat("SeatBackDriver", image=back_tex("seat_back_d", 21, worn), rough=0.95),
                   "cushion": C.mat("SeatCushionDriver", image=cushion_d, rough=0.95)},
        "passenger": {"back": C.mat("SeatBack", image=back_tex("seat_back_p", 22, False), rough=0.95),
                      "cushion": C.mat("SeatCushion", image=cushion_p, rough=0.95)},
        "rear": {"back": C.mat("RearSeat", image=rear, rough=0.95),
                 "cushion": C.mat("RearSeat", image=rear, rough=0.95)},
        "head": C.mat("Headrest", upper, rough=0.9),
    }


def _seat(x, y, sm, head_mat, M):
    """500 seat: rounded backrest (dark top panel), big round headrest on posts.

    Texture u runs across the seat from the car's right (-X) to its left, so
    the driver's outboard bolster (where the tape is) sits at u ~ 0.
    """
    out = []
    cush = C.box_minmax("cushion", (x - 0.24, y - 0.08, 0.26), (x + 0.24, y + 0.42, 0.40), sm["cushion"])
    bol = C.box_minmax("bolster", (x - 0.25, y - 0.06, 0.38), (x + 0.25, y + 0.40, 0.44), sm["cushion"])
    for o in (cush, bol):
        K.planar_uv(o, 0, 1)
    out += [cush, bol]
    pts = []
    for i in range(13):
        a = math.pi * i / 12
        pts.append((math.cos(a) * 0.24, 0.40 + math.sin(a) * 0.20))
    outline = [(0.24, 0.0)] + pts + [(-0.24, 0.0)]
    verts, faces = [], []
    n = len(outline)
    for yy in (-0.06, 0.06):
        for px, pz in outline:
            verts.append((px, yy, pz))
    faces.append(tuple(range(n)))
    faces.append(tuple(reversed(range(n, 2 * n))))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    back = C.mesh_obj("back", verts, faces, sm["back"])
    K.planar_uv(back, 0, 2)
    back.rotation_euler = (math.radians(-14), 0, 0)
    back.location = (x, y + 0.46, 0.38)
    C.apply_transform(back)
    out.append(back)
    head_y, head_z = y + 0.62, 1.10
    for px in (-0.06, 0.06):
        out.append(C.cylinder("post", 0.007, 0.12, segs=5, loc=(x + px, head_y - 0.02, head_z - 0.12),
                              material=M["post"]))
    out.append(C.cylinder("headrest", 0.12, 0.08, segs=12, axis="Y", loc=(x, head_y, head_z), material=head_mat))
    return out


def _leaned_box(name, size, base, h, lean, mat):
    """Box whose centre sits h up a line leaning back by lean degrees from base (y, z)."""
    a = math.radians(lean)
    o = C.box(name, size, (0, base[0] + h * math.sin(a), base[1] + h * math.cos(a)), mat)
    o.rotation_euler = (-a, 0, 0)
    C.apply_transform(o)
    return o


REAR_BACK = ((1.12, 0.44), 14)   # foot of the rear backrest (y, z) and its lean


def _rear_bench(sm, head_mat):
    """Narrow below the tub tops (z 0.66), full width above them."""
    cush = C.box_minmax("rear_cushion", (-0.49, 0.80, 0.27), (0.49, 1.14, 0.44), sm["cushion"])
    K.planar_uv(cush, 0, 1)
    base, lean = REAR_BACK
    low = _leaned_box("rear_back", (0.98, 0.13, 0.26), base, 0.13, lean, sm["back"])
    up = _leaned_box("rear_back_up", (1.22, 0.13, 0.30), base, 0.42, lean, sm["back"])
    for o in (low, up):
        K.planar_uv(o, 0, 2)
    out = [cush, low, up]
    for x in (-0.34, 0.34):
        out.append(C.cylinder("rear_headrest", 0.085, 0.07, segs=12, axis="Y", loc=(x, 1.25, 1.03),
                              material=head_mat))
    return out


def _steering_wheel(M, interior):
    """Built in the XZ plane facing the driver, then tilted to the column angle."""
    rim_r, tube = 0.185, 0.022
    segs = 16
    bits = []
    for i in range(segs):
        a = 2 * math.pi * (i + 0.5) / segs
        seg = C.cylinder("rim", tube, 2 * math.pi * rim_r / segs * 1.08, segs=6, axis="X", material=M["knob"],
                         cap=False)
        seg.rotation_euler = (0, -a - math.pi / 2, 0)
        seg.location = (math.cos(a) * rim_r, 0, math.sin(a) * rim_r)
        C.apply_transform(seg)
        bits.append(seg)
    bits.append(C.cylinder("hub", 0.075, 0.06, segs=12, axis="Y", material=M["knob"]))
    bits.append(K.lamp_disc("hub_ring", 0.05, 0.01, (0, 0.035, 0), (0, 1, 0), M["chrome"], segs=12))
    bits.append(K.lamp_disc("sw_badge", 0.032, 0.01, (0, 0.042, 0), (0, 1, 0), M["badge"], segs=10))
    for a in (0, math.pi, -math.pi / 2):
        sp = C.box("spoke", (rim_r - 0.05, 0.03, 0.05),
                   (math.cos(a) * (rim_r / 2 + 0.03), 0, math.sin(a) * (rim_r / 2 + 0.03)), M["knob"])
        sp.rotation_euler = (0, -a, 0)
        C.apply_transform(sp)
        bits.append(sp)
    # the column rises 24 degrees toward the driver; the wheel sits square
    # on it (top leaning away from the driver)
    tilt = math.radians(24)
    hub = Vector((-0.36, -0.40, 0.93))
    axis = Vector((0, math.cos(tilt), math.sin(tilt)))
    sw = C.join(bits, "SteeringWheel")
    sw.rotation_euler = (tilt, 0, 0)
    sw.location = hub
    column = C.cylinder("column", 0.035, 0.30, segs=6, axis="Y", loc=hub - axis * 0.17, material=M["cabin"])
    column.rotation_euler = (tilt, 0, 0)
    C.apply_transform(column)
    interior = C.join([interior, column], "Interior")
    return interior, sw


# ------------------------------------------------------------------ parts

def exhaust(style):
    """Exhaust tip as its own object; origin = Mount_Exhaust."""
    chrome = C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9)
    dark = C.mat("ExhaustDark", "#2a2826", rough=0.6, metal=0.6)
    if style == "stock":
        p = C.cylinder("pipe", 0.022, 0.30, segs=8, axis="Y", loc=(0, -0.12, 0), material=dark)
        p.rotation_euler = (math.radians(12), 0, 0)
        C.apply_transform(p)
        return C.join([p], "Exhaust")
    if style == "sport":
        p = C.cylinder("pipe", 0.025, 0.25, segs=8, axis="Y", loc=(0, -0.12, 0), material=dark)
        tip = C.cylinder("tip", 0.045, 0.14, segs=12, axis="Y", loc=(0, 0.02, 0), material=chrome)
        return C.join([p, tip], "Exhaust")
    if style == "twin":
        bits = [C.box("box", (0.30, 0.25, 0.10), (0, -0.16, 0.02), dark)]
        for sx in (-1, 1):
            bits.append(C.cylinder("tip", 0.04, 0.16, segs=12, axis="Y", loc=(sx * 0.07, 0.02, 0), material=chrome))
        return C.join(bits, "Exhaust")
    if style == "abarth_quad":
        bits = []
        for sx in (-1, 1):
            for dz in (-0.03, 0.03):
                bits.append(C.cylinder("tip", 0.028, 0.14, segs=10, axis="Y",
                                       loc=(sx * 0.06, 0.02, dz), material=chrome))
        return C.join(bits, "Exhaust")
    raise ValueError(style)
