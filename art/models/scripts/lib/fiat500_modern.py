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
  stripes          hex or None;  spoiler (bool)
  seat_upper, seat_lower, seat_wear (bool: tape + scuffed bolster on the driver's seat)
  dash             fascia colour
  plate            plate text;  phone_holder (bool)
"""
import math

import bpy
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
        "dash": C.mat("DashFascia", spec.get("dash", paint), rough=0.35, metal=0.4),
        "dashmat": C.mat("DashMat", image=TX.carpet("dashmat", "#1d1d1e", 9), rough=1.0),
        "rubber": C.mat("FloorMat", image=TX.carpet("floormat", "#121213", 4, 8), rough=0.9),
        "gauge": C.mat("Gauges", image=TX.gauges(), rough=0.4, emit="#203040", emit_strength=0.2),
        "knob": C.mat("KnobBlack", "#0e0e0f", rough=0.25),
        "post": C.mat("HeadrestPost", "#b9bcc0", rough=0.3, metal=0.8),
    }


def _glass():
    m = C.mat("Glass", "#1d2830", rough=0.05, metal=0.3, alpha=0.55)
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
    seams = S.shut_lines(shell, M["seam"])
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
    body_bits += _sides(ref, M, spec)
    if spec.get("spoiler"):
        body_bits.append(_spoiler(ref, M))
    if spec.get("stripes"):
        body_bits += _stripes(ref, M)
    roof = spec.get("roof", "steel")
    if roof == "glass":
        body_bits.append(K.stick_box("sunroof", K.on_top(ref, 0, 0.45), (1.0, 0.95, 0.012), M["glass"]))
    elif roof == "fabric":
        body_bits.append(_fabric_roof(ref, spec))

    K.solidify(body, 0.025, M["cabin"])
    _headliner(body, M)
    root_objs = [body, C.join(glass["panes"], "Glass")]

    for side, sx in (("L", 1), ("R", -1)):
        door = parts["Door_" + side]
        handle = K.stick_box("handle", K.on_side(ref, sx, 0.30, 0.80), (0.14, 0.028, 0.03),
                             M["chrome"] if spec.get("chrome", True) else M["trim"])
        card = _door_card(door, sx, M)
        K.solidify(door, 0.04, M["cabin"])
        door = C.join([door, handle, _mirror(ref, sx, M)] + card + door_glass[sx]["seals"], "Door_" + side)
        C.set_origin(door, (sx * 0.78, DOOR_Y0, 0.6))
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

    interior, wheel_obj = _interior(M, spec)
    root_objs += [interior, wheel_obj]
    bpy.data.objects.remove(ref, do_unlink=True)

    ws = spec.get("wheels", "pop_trim")
    hub_z = W.radius(ws)
    for nm, x, y in (("FL", 1, AXLE_F), ("FR", -1, AXLE_F), ("RL", 1, AXLE_R), ("RR", -1, AXLE_R)):
        root_objs.append(W.build("Wheel_" + nm, ws, loc=(x * TRACK / 2, y, hub_z), right=x < 0))

    C.empty("Cam_Cockpit", (-0.36, 0.20, 1.17 + ride))
    C.empty("Mount_Exhaust", (0.42, 1.70, 0.24 + ride))
    C.empty("Mount_Roof", (0, 0.35, 1.49 + ride))
    if ride:
        for o in root_objs:
            if not o.name.startswith("Wheel_"):
                o.location.z += ride
    return root_objs


# ------------------------------------------------------------------ glass

def _pane(name, ref, poly, frame, M):
    """Glass slightly bigger than the opening, sitting just inside the surface."""
    return K.project_poly(name, ref, K.offset_poly(poly, -0.015), frame, M["glass"], offset=-0.012, cuts=3)


def _seal(name, ref, poly, frame, M):
    """Black rubber seal / frit ring round an opening."""
    return K.project_poly(name, ref, K.offset_poly(poly, -0.02), frame, None, offset=0.004, cuts=1,
                          border=0.045, border_mat=M["trim"])


def _windows(ref, M):
    body = {"panes": [], "seals": []}
    doors = {}
    door_poly = S.clip_y(S.DLO, hi=S.B_PILLAR[0])
    quarter = S.clip_y(S.DLO, lo=S.B_PILLAR[1])
    pillar = S.clip_y(K.offset_poly(S.DLO, -0.03), lo=S.B_PILLAR[0] - 0.01, hi=S.B_PILLAR[1] + 0.01)
    for sx in (1, -1):
        fr = K.side_frame(sx)
        doors[sx] = {"panes": [_pane("door_glass", ref, door_poly, fr, M)],
                     "seals": [_seal("door_seal", ref, door_poly, fr, M)]}
        body["panes"].append(_pane("quarter_glass", ref, quarter, fr, M))
        body["seals"].append(_seal("quarter_seal", ref, quarter, fr, M))
        body["seals"].append(K.project_poly("b_pillar", ref, pillar, fr, M["trim"], offset=0.005, cuts=2))
    for name, poly, fr in (("windscreen", S.WINDSCREEN, K.top_frame()),
                           ("rear_window", S.REAR_WINDOW, K.rear_frame())):
        body["panes"].append(_pane(name, ref, poly, fr, M))
        body["seals"].append(_seal(name + "_seal", ref, poly, fr, M))
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
    """Rounded black mirror on a stubby arm at the front corner of the door glass."""
    loc, nor = K.on_side(ref, sx, -0.60, 0.99)
    arm = C.box("mirror_arm", (0.10, 0.07, 0.035), loc + Vector((sx * 0.04, 0, 0.015)), M["trim"])
    cap = C.sphere("mirror_cap", 0.08, loc + Vector((sx * 0.115, 0.0, 0.045)), M["mirror"], segs=10, rings=6,
                   scale=(1.05, 0.62, 0.78))
    glass = K.lamp_disc("mirror_glass", 0.072, 0.01, loc + Vector((sx * 0.115, 0.047, 0.045)), (0, 1, 0),
                        M["reflector"], segs=10, sx=1.05, sz=0.75)
    return C.join([arm, cap, glass], "Mirror")


def _door_card(door, sx, M):
    """Round speaker, armrest and pull on the inside of the door."""
    loc, nor = K.hit(door, (0, -0.35, 0.45), (sx, 0, 0))
    spk = K.stick_disc("speaker", door, (loc, -nor), 0.085, 0.02, M["dark"], segs=12, proud=0.045)
    loc2, nor2 = K.hit(door, (0, 0.05, 0.72), (sx, 0, 0))
    arm = C.box("armrest", (0.06, 0.40, 0.05), loc2 - nor2 * 0.07, M["cabin"])
    pull = C.box("pull", (0.03, 0.12, 0.02), loc2 - nor2 * 0.075 + Vector((0, -0.1, 0.12)), M["chrome"])
    return [spk, arm, pull]


def _bonnet_line(ref, M):
    """Clamshell bonnet shut line: across the nose just above the headlamps,
    round the corners and back along the top of the wings to the A-pillars."""
    rays = []

    def side(sx, ys):
        for y in ys:
            z = 0.845 + (0.935 - 0.845) * (y + 1.55) / 0.69
            rays.append(((sx * 3, y, z), (-sx, 0, 0)))

    def corner(sx, angles):
        for a in angles:
            d = Vector((sx * math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
            z = 0.805 + 0.04 * a / 90
            o = Vector((sx * 0.50, -1.55, z))
            rays.append((tuple(o + d * 2), tuple(-d)))
    ys = [-0.86 - 0.069 * i for i in range(11)]
    side(-1, ys)
    corner(-1, [90 - 15 * i for i in range(6)])
    for i in range(11):
        x = -0.50 + i * 0.10
        rays.append(((x, -3, 0.785 + 0.02 * (x / 0.5) ** 2), (0, 1, 0)))
    corner(1, [15 * i for i in range(1, 7)])
    side(1, list(reversed(ys)))
    return S.ribbon("bonnet_line", ref, rays, 0.012, M["seam"])


def _front(ref, M, spec, abarth):
    out = [_bonnet_line(ref, M)]
    chrome = M["chrome"] if spec.get("chrome", False) else M["satin"]
    for sx in (1, -1):
        # big round headlamps under the bonnet line, small round lamps below
        w = K.on_front(ref, sx * 0.625, 0.685)
        h = K.stick_disc("head", ref, w, 0.104, 0.05, M["head"], segs=16, proud=0.012)
        h["lamp"] = "head"
        out.append(K.stick_disc("head_ring", ref, w, 0.116, 0.035, M["chrome"], segs=16, proud=0.004))
        out.append(K.stick_disc("head_reflector", ref, w, 0.065, 0.05, M["reflector"], segs=12, proud=0.016))
        lo = K.stick_disc("drl", ref, K.on_front(ref, sx * 0.645, 0.495), 0.046, 0.04, M["head"], segs=10,
                          proud=0.004)
        lo["lamp"] = "head"
        out.append(K.stick_disc("drl_ring", ref, K.on_front(ref, sx * 0.645, 0.495), 0.054, 0.03, M["insert"],
                                segs=10))
        out += [h, lo]
        # moustache: a slim bar either side of the badge, rising slightly outward
        for x in (0.11, 0.19, 0.27, 0.35):
            out.append(K.stick_box("whisker", K.on_front(ref, sx * x, 0.565 + (x - 0.1) * 0.03),
                                   (0.075, 0.020, 0.018), chrome))
        # grey inserts in the bumper either side of the plate
        out.append(K.stick_box("insert", K.on_front(ref, sx * 0.43, 0.425), (0.26, 0.035, 0.015), M["insert"]))
    out.append(K.stick_disc("badge", ref, K.on_front(ref, 0, 0.565), 0.045, 0.03, M["badge"], segs=12))
    out.append(K.stick_disc("badge_ring", ref, K.on_front(ref, 0, 0.565), 0.051, 0.02, M["chrome"], segs=12))
    if abarth:
        out.append(K.stick_box("grille", K.on_front(ref, 0, 0.33), (0.80, 0.20, 0.05), M["dark"]))
        for sx in (1, -1):
            out.append(K.stick_box("intake", K.on_front(ref, sx * 0.55, 0.32), (0.20, 0.12, 0.05), M["dark"]))
        out.append(C.box("splitter", (1.30, 0.14, 0.03), (0, -1.76, 0.235), M["trim"]))
    else:
        grille = [(-0.46, 0.225), (0.46, 0.225), (0.53, 0.27), (0.52, 0.36), (-0.52, 0.36), (-0.53, 0.27)]
        out.append(K.project_poly("grille", ref, grille, K.front_frame(), M["dark"], offset=0.004, cuts=2))
    out.append(K.stick_box("plate_holder", K.on_front(ref, 0, 0.405), (0.56, 0.14, 0.03), M["trim"]))
    plate = K.stick_box("plate_f", K.on_front(ref, 0, 0.405), (0.50, 0.11, 0.01), M["plate"], proud=0.03)
    K.planar_uv(plate, 0, 2)
    out.append(plate)
    # cowl panel and wipers parked at the base of the windscreen
    cowl = [(-0.52, -0.86), (0.52, -0.86), (0.56, -0.805), (-0.56, -0.805)]
    out.append(K.project_poly("cowl", ref, cowl, K.top_frame(), M["trim"], offset=0.004, cuts=3))
    for x, ln in ((-0.30, 0.52), (0.18, 0.46)):
        out.append(K.stick_box("wiper", K.on_top(ref, x, -0.78), (ln, 0.02, 0.015), M["trim"], proud=0.01))
    return out


def _tail_lamp(ref, sx, M):
    """Tall rounded lamp wrapping the rear corner: red above, clear below
    with the round reversing lamp, in a white rim."""
    centre = Vector((sx * 0.625, 1.58, 0.81))
    normal = Vector((sx * 0.38, 0.925, 0))
    fr = S.plane_frame(centre, normal)
    outline = S.rounded_rect(0.155, 0.33, 0.05)
    rim = K.project_poly("tail_rim", ref, outline, fr, None, offset=0.006, cuts=1, border=0.014,
                         border_mat=M["white"])
    red = [(u, v + 0.04) for u, v in S.rounded_rect(0.132, 0.232, 0.04)]
    lens = K.project_poly("tail_red", ref, red, fr, M["tail"], offset=0.008, cuts=2)
    lens["lamp"] = "tail"
    clear = [(u, v - 0.115) for u, v in S.rounded_rect(0.132, 0.074, 0.03)]
    clear = K.project_poly("tail_clear", ref, clear, fr, M["white"], offset=0.007, cuts=1)
    loc, nor = K.hit(ref, fr(0, -0.115)[0], fr(0, -0.115)[1])
    rev = K.stick_disc("reverse", ref, (loc, nor), 0.022, 0.02, M["reflector"], segs=8, proud=0.006)
    return [rim, lens, clear, rev]


def _rear(ref, M, spec, abarth):
    out = []
    chrome = M["chrome"]
    for sx in (1, -1):
        out += _tail_lamp(ref, sx, M)
    # tailgate shut line: round the glass and down inside the lamps
    gate = [(-0.50, 0.64), (-0.52, 0.80), (-0.53, 0.985), (-0.62, 1.05), (-0.625, 1.20), (-0.60, 1.30),
            (-0.53, 1.365), (0.53, 1.365), (0.60, 1.30), (0.625, 1.20), (0.62, 1.05), (0.53, 0.985),
            (0.52, 0.80), (0.50, 0.64)]
    out.append(K.project_line("tailgate_line", ref, gate, K.rear_frame(), 0.012, M["seam"], closed=True))
    out.append(K.project_line("bumper_groove", ref, [(x / 10, 0.315) for x in range(-6, 7)], K.rear_frame(),
                              0.035, M["dark"]))
    out.append(K.stick_box("plate_recess", K.on_rear(ref, 0, 0.715), (0.42, 0.15, 0.01), M["insert"]))
    plate = K.stick_box("plate_r", K.on_rear(ref, 0, 0.71), (0.36, 0.11, 0.01), M["plate"], proud=0.008)
    K.planar_uv(plate, 0, 2, flip_u=True)
    out.append(plate)
    out.append(K.stick_box("plate_chrome", K.on_rear(ref, 0, 0.805), (0.42, 0.035, 0.02), chrome))
    out.append(K.stick_disc("badge_r", ref, K.on_rear(ref, 0, 0.965), 0.042, 0.02, M["badge"], segs=12))
    out.append(K.stick_disc("badge_r_ring", ref, K.on_rear(ref, 0, 0.965), 0.048, 0.015, chrome, segs=12))
    # roof lip over the rear window
    out.append(K.stick_box("roof_lip", K.on_rear(ref, 0, 1.372), (0.84, 0.035, 0.03), M["paint"]))
    # rear wiper parked along the bottom of the glass
    loc, nor = K.on_rear(ref, -0.17, 1.105)
    out.append(K.stick_box("rear_wiper", (loc, nor), (0.40, 0.02, 0.02), M["trim"], proud=0.012))
    # roof antenna, raked back
    loc, nor = K.on_top(ref, 0, 1.02)
    ant = C.cylinder("antenna", 0.006, 0.36, segs=5, material=M["trim"])
    ant.rotation_euler = (math.radians(-38), 0, 0)
    ant.location = loc + Vector((0, 0.11, 0.14))
    C.apply_transform(ant)
    out.append(ant)
    out.append(K.stick_box("antenna_base", (loc, nor), (0.03, 0.07, 0.025), M["trim"]))
    if abarth:
        out.append(C.box("diffuser", (0.9, 0.10, 0.06), (0, 1.68, 0.25), M["dark"]))
    return out


def _sides(ref, M, spec):
    out = []
    for sx in (1, -1):
        out.append(K.stick_box("side_ind", K.on_side(ref, sx, -1.33, 0.74), (0.045, 0.022, 0.01), M["white"]))
        if spec.get("chrome"):
            out.append(K.stick_box("sill_trim", K.on_side(ref, sx, -0.10, 0.30), (1.10, 0.02, 0.01), M["chrome"]))
    # round fuel flap on the right rear quarter
    w = K.on_side(ref, -1, 1.22, 0.83)
    out.append(K.stick_disc("fuel_seam", ref, w, 0.078, 0.01, M["seam"], segs=14, proud=0.001))
    out.append(K.stick_disc("fuel_flap", ref, w, 0.07, 0.01, M["paint"], segs=14, proud=0.003))
    return out


def _spoiler(ref, M):
    return K.stick_box("spoiler", K.on_top(ref, 0, 1.15), (1.05, 0.22, 0.04), M["paint"])


def _stripes(ref, M):
    out = []
    for sx in (1, -1):
        for y in (-0.95, 0.75):
            out.append(K.stick_box("stripe_side", K.on_side(ref, sx, y, 0.36), (0.40, 0.06, 0.004), M["stripe"]))
    for x in (0.16, -0.16):
        for y in (0.0, 0.45, 0.9):
            out.append(K.stick_box("stripe_roof", K.on_top(ref, x, y), (0.16, 0.46, 0.004), M["stripe"]))
        for y in (-1.45, -1.1):
            out.append(K.stick_box("stripe_hood", K.on_top(ref, x, y), (0.16, 0.36, 0.004), M["stripe"]))
    return out


def _fabric_roof(ref, spec):
    fab = C.mat("RoofFabric", spec.get("fabric", "#2a1f1a"), rough=1.0)
    return K.stick_box("fabric_roof", K.on_top(ref, 0, 0.42), (1.12, 1.30, 0.02), fab)


# ------------------------------------------------------------------ interior

def _interior(M, spec):
    bits = []
    # floor, mats, firewall
    bits.append(C.box_minmax("floor", (-0.70, -0.85, 0.20), (0.70, 1.45, 0.26), M["cabin"]))
    for x in (-0.36, 0.36):
        bits.append(C.box_minmax("mat", (x - 0.22, -0.82, 0.26), (x + 0.22, -0.25, 0.27), M["rubber"]))
        bits.append(C.box_minmax("mat_r", (x - 0.20, 0.62, 0.26), (x + 0.20, 0.82, 0.27), M["rubber"]))
    bits.append(C.box_minmax("firewall", (-0.75, -0.95, 0.26), (0.75, -0.85, 0.80), M["cabin"]))
    # dashboard: fuzzy dash mat on top, silver fascia band across the car
    bits.append(C.box_minmax("dash_top", (-0.74, -0.98, 0.84), (0.74, -0.58, 0.97), M["dashmat"]))
    bits.append(C.box_minmax("dash_fascia", (-0.72, -0.62, 0.70), (0.72, -0.56, 0.86), M["dash"]))
    bits.append(C.box_minmax("dash_low", (-0.72, -0.85, 0.50), (0.72, -0.62, 0.70), M["cabin"]))
    # round vents at each end and a pair in the middle
    for x in (-0.64, 0.64):
        bits.append(K.lamp_disc("vent_ring", 0.055, 0.03, (x, -0.555, 0.79), (0, 1, 0), M["chrome"], segs=10))
        bits.append(K.lamp_disc("vent", 0.042, 0.03, (x, -0.548, 0.79), (0, 1, 0), M["dark"], segs=10))
    bits.append(C.box_minmax("vent_c", (-0.14, -0.57, 0.86), (0.14, -0.55, 0.92), M["dark"]))
    # "500" logo on the passenger side of the fascia
    for i in range(3):
        bits.append(K.lamp_disc("logo", 0.016, 0.01, (0.30 + i * 0.04, -0.556, 0.76), (0, 1, 0), M["chrome"], segs=6))
    # instrument binnacle in front of the driver (RHD: -X)
    bits.append(C.cylinder("binnacle", 0.11, 0.14, segs=12, axis="Y", loc=(-0.36, -0.64, 0.99), material=M["cabin"]))
    face = K.lamp_disc("gauge", 0.095, 0.01, (-0.36, -0.565, 0.99), (0, 1, 0.12), M["gauge"], segs=12)
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
    bits.append(C.box_minmax("parcel_shelf", (-0.64, 1.30, 0.93), (0.64, 1.42, 0.95), M["cabin"]))
    for x in (-0.40, 0.40):
        visor = C.box("visor", (0.36, 0.16, 0.02), (x, -0.08, 1.36), M["headliner"])
        visor.rotation_euler = (math.radians(15), 0, 0)
        C.apply_transform(visor)
        bits.append(visor)
    bits.append(C.box("rear_mirror", (0.22, 0.03, 0.065), (0, -0.14, 1.32), M["knob"]))
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


def _rear_bench(sm, head_mat):
    cush = C.box_minmax("rear_cushion", (-0.62, 0.78, 0.26), (0.62, 1.22, 0.44), sm["cushion"])
    K.planar_uv(cush, 0, 1)
    back = C.box("rear_back", (1.24, 0.14, 0.56), (0, 1.22, 0.72), sm["back"])
    K.planar_uv(back, 0, 2)
    back.rotation_euler = (math.radians(-14), 0, 0)
    C.apply_transform(back)
    out = [cush, back]
    for x in (-0.36, 0.36):
        out.append(C.cylinder("rear_headrest", 0.10, 0.08, segs=12, axis="Y", loc=(x, 1.33, 1.08),
                              material=head_mat))
    return out


def _steering_wheel(M, interior):
    """Built in the XZ plane facing the driver, then tilted to the column angle."""
    rim_r, tube = 0.185, 0.022
    segs = 16
    bits = []
    for i in range(segs):
        a = 2 * math.pi * (i + 0.5) / segs
        seg = C.cylinder("rim", tube, 2 * math.pi * rim_r / segs * 1.08, segs=6, axis="X", material=M["knob"])
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
    sw = C.join(bits, "SteeringWheel")
    sw.rotation_euler = (math.radians(-24), 0, 0)
    sw.location = (-0.36, -0.40, 0.95)
    column = C.cylinder("column", 0.035, 0.32, segs=6, axis="Y", loc=(-0.36, -0.55, 0.89), material=M["cabin"])
    column.rotation_euler = (math.radians(-24), 0, 0)
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
