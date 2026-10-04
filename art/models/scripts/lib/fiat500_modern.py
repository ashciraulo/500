"""The 2007-on Fiat 500 (type 312) and its derivatives.

Real proportions: length 3.546 m, width 1.627 m, height 1.488 m,
wheelbase 2.300 m, track ~1.41 m. The origin is on the ground, midway
between the axles; the car faces -Y in Blender (+Z in Godot). Right hand
drive: the driver sits at -X.

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

from mathutils import Vector

from . import carkit as K
from . import common as C
from . import textures as TX
from . import wheels as W

WHEELBASE = 2.30
TRACK = 1.41
AXLE_F, AXLE_R = -WHEELBASE / 2, WHEELBASE / 2
DOOR_Y0, DOOR_Y1 = -0.70, 0.50
WS_Y0, WS_Y1 = -0.78, -0.12        # windscreen base / top
DG_Y0 = -0.12                       # door glass front
QG_Y0, QG_Y1 = 0.62, 0.98          # rear quarter glass
RW_Y0, RW_Y1 = 1.12, 1.47          # rear window top / bottom

# profile segments (see carkit.body_station)
J_UNDER, J_SILL = 0, 1
J_SIDE = (2, 3, 4, 5)
J_GLASS_SIDE = 6
J_TOP = (7, 8, 9)

# Key curves along the length. Columns: zb wb zrock wrock zs wmax zbelt wbelt zrs wrs zr
KEYS = [
    (-1.800, (0.34, 0.20, 0.40, 0.36, 0.55, 0.50, 0.70, 0.42, 0.72, 0.28, 0.73)),
    (-1.792, (0.29, 0.40, 0.35, 0.54, 0.55, 0.62, 0.76, 0.55, 0.775, 0.40, 0.785)),
    (-1.770, (0.25, 0.52, 0.31, 0.66, 0.55, 0.71, 0.795, 0.64, 0.81, 0.49, 0.82)),
    (-1.730, (0.22, 0.59, 0.29, 0.73, 0.55, 0.765, 0.82, 0.70, 0.835, 0.55, 0.845)),
    (-1.660, (0.21, 0.64, 0.28, 0.775, 0.56, 0.795, 0.845, 0.735, 0.86, 0.585, 0.87)),
    (-1.540, (0.20, 0.66, 0.27, 0.795, 0.57, 0.81, 0.87, 0.755, 0.885, 0.61, 0.895)),
    (-1.300, (0.19, 0.67, 0.27, 0.80, 0.58, 0.815, 0.905, 0.765, 0.92, 0.63, 0.93)),
    (-1.000, (0.18, 0.68, 0.27, 0.80, 0.59, 0.815, 0.945, 0.77, 0.96, 0.65, 0.97)),
    (WS_Y0, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 0.965, 0.77, 0.98, 0.665, 0.99)),
    (DOOR_Y0, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 0.970, 0.77, 1.06, 0.66, 1.08)),
    (-0.450, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 0.985, 0.765, 1.27, 0.64, 1.30)),
    (-0.250, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 0.990, 0.76, 1.37, 0.625, 1.42)),
    (WS_Y1, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 0.995, 0.755, 1.405, 0.615, 1.465)),
    (0.200, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 1.000, 0.75, 1.42, 0.61, 1.488)),
    (DOOR_Y1, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 1.005, 0.75, 1.42, 0.605, 1.486)),
    (QG_Y0, (0.18, 0.68, 0.27, 0.80, 0.60, 0.815, 1.005, 0.75, 1.415, 0.60, 1.482)),
    (QG_Y1, (0.19, 0.68, 0.28, 0.80, 0.60, 0.81, 1.005, 0.745, 1.37, 0.59, 1.455)),
    (RW_Y0, (0.20, 0.68, 0.28, 0.795, 0.60, 0.805, 1.000, 0.74, 1.36, 0.58, 1.43)),
    (1.300, (0.21, 0.67, 0.29, 0.79, 0.60, 0.80, 0.995, 0.735, 1.25, 0.575, 1.29)),
    (RW_Y1, (0.22, 0.66, 0.30, 0.78, 0.60, 0.79, 0.985, 0.725, 1.02, 0.57, 1.035)),
    (1.580, (0.23, 0.64, 0.31, 0.76, 0.59, 0.775, 0.950, 0.71, 0.965, 0.56, 0.975)),
    (1.665, (0.25, 0.59, 0.33, 0.71, 0.58, 0.73, 0.885, 0.665, 0.90, 0.525, 0.91)),
    (1.720, (0.28, 0.49, 0.36, 0.61, 0.57, 0.63, 0.805, 0.58, 0.82, 0.45, 0.83)),
    (1.750, (0.33, 0.30, 0.42, 0.40, 0.56, 0.44, 0.71, 0.40, 0.725, 0.30, 0.735)),
]


def stations(abarth=False):
    out = []
    for y, vals in KEYS:
        if abarth and y < -1.6:
            y -= 0.06 * (1 - (y + 1.8) / 0.2)
        out.append(K.body_station(y, *vals))
    return out


def classify(y0, y1, j, side):
    ym = (y0 + y1) / 2
    in_door = DOOR_Y0 <= ym <= DOOR_Y1
    L = side > 0
    if j == J_UNDER:
        return K.T_UNDER
    if j == J_SILL:
        return K.T_TRIM
    if j in J_SIDE:
        if in_door:
            return K.T_DL if L else K.T_DR
        return K.T_PAINT
    if j == J_GLASS_SIDE:
        if DG_Y0 <= ym <= DOOR_Y1:
            return K.T_DLG if L else K.T_DRG
        if WS_Y0 <= ym <= DG_Y0 and ym >= DOOR_Y0:
            return K.T_DL if L else K.T_DR
        if QG_Y0 <= ym <= QG_Y1:
            return K.T_GLASS
        return K.T_PAINT
    if j in J_TOP:
        if WS_Y0 <= ym <= WS_Y1 or RW_Y0 <= ym <= RW_Y1:
            return K.T_GLASS
    return K.T_PAINT


def _u_to_y(st):
    ys = [s.y for s in st]
    n = len(ys) - 1

    def f(u):
        x = min(max(u, 0), 1) * n
        i = min(int(x), n - 1)
        return ys[i] + (ys[i + 1] - ys[i]) * (x - i)
    return f


def materials(spec, st):
    paint = spec.get("paint", "#f2f0ea")
    npts = len(st[0].pts)
    wear = spec.get("wear", 0.0)
    if wear > 0:
        img = TX.worn_paint("paint_worn", paint, _u_to_y(st), lambda v: v * (npts - 1), fade=wear)
        paint_mat = C.mat("Paint", image=img, rough=0.45, metal=0.15)
    else:
        paint_mat = C.mat("Paint", paint, rough=0.35, metal=0.15)
    satin = "#d8dadc" if spec.get("chrome") else "#4a4b4d"
    return {
        "paint": paint_mat,
        "glass": _glass(),
        "trim": C.mat("TrimBlack", "#1b1c1e", rough=0.7),
        "under": C.mat("Underbody", "#141414", rough=0.9),
        "cabin": C.mat("CabinTrim", spec.get("cabin", "#3a3b3e"), rough=0.85),
        "headliner": C.mat("Headliner", spec.get("headliner", "#cbc4b6"), rough=0.95),
        "chrome": C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9),
        "satin": C.mat("Moustache", satin, rough=0.35, metal=0.6),
        "head": C.mat("LampHead", "#b9c3c8", rough=0.1, metal=0.3, emit="#fff6dc", emit_strength=0.0),
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
    st = stations(abarth)
    M = materials(spec, st)
    ride = spec.get("ride", 0.0)

    verts, faces, tags, uvs = K.loft(st, classify)
    shell = K.shell_object("shell", verts, faces, tags, uvs)
    K.cut_arches(shell, (AXLE_F, AXLE_R), 0.335, 0.53, 0.29)
    parts = K.split_by_tag(shell, {
        "Body": {"Paint": M["paint"], "Trim": M["trim"], "Under": M["under"]},
        "Glass": {"Glass": M["glass"]},
        "Door_L": {"DoorL": M["paint"]},
        "Door_R": {"DoorR": M["paint"]},
        "Door_L_Glass": {"DoorLGlass": M["glass"]},
        "Door_R_Glass": {"DoorRGlass": M["glass"]},
    }, smooth_angle=38)
    body = parts["Body"]
    _two_tone_roof(body, M, spec)

    # details are placed by ray casting onto the outer shell
    body_bits = []
    body_bits += _front(body, M, spec, abarth)
    body_bits += _rear(body, M, spec, abarth)
    body_bits += _sides(body, M, spec)
    if spec.get("spoiler"):
        body_bits.append(_spoiler(M))
    if spec.get("stripes"):
        body_bits += _stripes(body, M)
    roof = spec.get("roof", "steel")
    if roof == "glass":
        body_bits.append(K.stick_box("sunroof", K.on_top(body, 0, 0.45), (1.0, 0.95, 0.012), M["glass"]))
    elif roof == "fabric":
        body_bits.append(_fabric_roof(body, spec))

    K.solidify(body, 0.025, M["cabin"])
    _headliner(body, M)
    root_objs = [body, parts["Glass"]]

    for side, sx in (("L", 1), ("R", -1)):
        door = parts["Door_" + side]
        handle = K.stick_box("handle", K.on_side(door, sx, 0.30, 0.865), (0.13, 0.03, 0.025),
                             M["chrome"] if spec.get("chrome", True) else M["trim"])
        card = _door_card(door, sx, M)
        K.solidify(door, 0.04, M["cabin"])
        door = C.join([door, handle, _mirror(sx, M)] + card, "Door_" + side)
        C.set_origin(door, (sx * 0.78, DOOR_Y0, 0.6))
        g = parts["Door_%s_Glass" % side]
        mw = g.matrix_world.copy()
        g.parent = door
        g.matrix_world = mw
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


# ------------------------------------------------------------------ details

def _two_tone_roof(body, M, spec):
    if "roof_color" not in spec:
        return
    me = body.data
    me.materials.append(M["roof"])
    idx = len(me.materials) - 1
    pm = list(me.materials).index(M["paint"])
    for p in me.polygons:
        if p.material_index == pm and p.center.z > 1.40 and -0.12 < p.center.y < 1.2:
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


def _mirror(sx, M):
    arm = C.box("mirror_arm", (0.10, 0.06, 0.04), (sx * 0.80, -0.60, 1.01), M["trim"])
    cap = C.box("mirror_cap", (0.09, 0.12, 0.13), (sx * 0.885, -0.60, 1.05), M["mirror"])
    cap2 = C.box("mirror_cap2", (0.06, 0.10, 0.11), (sx * 0.935, -0.605, 1.05), M["mirror"])
    glass = C.box("mirror_glass", (0.10, 0.01, 0.10), (sx * 0.895, -0.535, 1.05), M["glass"])
    return C.join([arm, cap, cap2, glass], "Mirror")


def _door_card(door, sx, M):
    """Round speaker, armrest and pull on the inside of the door."""
    loc, nor = K.hit(door, (0, -0.35, 0.45), (sx, 0, 0))
    spk = K.stick_disc("speaker", door, (loc, -nor), 0.085, 0.02, M["dark"], segs=12, proud=0.045)
    loc2, nor2 = K.hit(door, (0, 0.05, 0.72), (sx, 0, 0))
    arm = C.box("armrest", (0.06, 0.40, 0.05), loc2 - nor2 * 0.07, M["cabin"])
    pull = C.box("pull", (0.03, 0.12, 0.02), loc2 - nor2 * 0.075 + Vector((0, -0.1, 0.12)), M["chrome"])
    return [spk, arm, pull]


def _front(body, M, spec, abarth):
    out = []
    chrome = M["chrome"] if spec.get("chrome", False) else M["satin"]
    for sx in (1, -1):
        # big round headlamps up at the corners, small round lamps under them
        w = K.on_front(body, sx * 0.535, 0.70)
        h = K.stick_disc("head", body, w, 0.112, 0.05, M["head"], segs=14, proud=0.006)
        h["lamp"] = "head"
        out.append(K.stick_disc("head_ring", body, w, 0.124, 0.035, M["satin"], segs=14))
        out.append(K.stick_disc("head_reflector", body, w, 0.06, 0.05, M["reflector"], segs=8, proud=0.008))
        lo = K.stick_disc("drl", body, K.on_front(body, sx * 0.585, 0.52), 0.05, 0.04, M["head"], segs=10,
                          proud=0.004)
        lo["lamp"] = "head"
        out += [h, lo]
        # moustache: a long bar either side of the badge
        for x in (0.10, 0.17, 0.24, 0.30):
            out.append(K.stick_box("whisker", K.on_front(body, sx * x, 0.615 + (x - 0.1) * 0.08),
                                   (0.075, 0.022, 0.02), chrome))
    out.append(K.stick_disc("badge", body, K.on_front(body, 0, 0.615), 0.045, 0.03, M["badge"], segs=12))
    out.append(K.stick_disc("badge_ring", body, K.on_front(body, 0, 0.615), 0.05, 0.02, M["chrome"], segs=12))
    if abarth:
        out.append(K.stick_box("grille", K.on_front(body, 0, 0.36), (0.80, 0.20, 0.05), M["dark"]))
        for sx in (1, -1):
            out.append(K.stick_box("intake", K.on_front(body, sx * 0.55, 0.34), (0.20, 0.12, 0.05), M["dark"]))
        out.append(C.box("splitter", (1.30, 0.14, 0.03), (0, -1.80, 0.235), M["trim"]))
    else:
        out.append(K.stick_box("grille", K.on_front(body, 0, 0.33), (0.72, 0.10, 0.04), M["dark"]))
        for sx in (1, -1):
            out.append(K.stick_box("vent", K.on_front(body, sx * 0.50, 0.34), (0.14, 0.07, 0.04), M["dark"]))
    out.append(K.stick_box("plate_holder", K.on_front(body, 0, 0.465), (0.56, 0.14, 0.03), M["trim"]))
    plate = K.stick_box("plate_f", K.on_front(body, 0, 0.465), (0.50, 0.11, 0.01), M["plate"], proud=0.03)
    K.planar_uv(plate, 0, 2)
    out.append(plate)
    # wipers parked at the base of the windscreen
    for x, ln in ((-0.30, 0.52), (0.18, 0.46)):
        out.append(K.stick_box("wiper", K.on_top(body, x, -0.80), (ln, 0.02, 0.015), M["trim"], proud=0.01))
    out.append(K.stick_box("cowl", K.on_top(body, 0, -0.83), (1.10, 0.06, 0.01), M["trim"]))
    return out


def _rear(body, M, spec, abarth):
    out = []
    chrome = M["chrome"]
    for sx in (1, -1):
        # tall rounded tail lamps: clear outer ring, red centre
        w = K.on_rear(body, sx * 0.60, 0.84)
        out.append(K.stick_disc("tail", body, w, 0.145, 0.04, M["white"], segs=12, sx=0.6, proud=0.004))
        c = K.stick_disc("tail_red", body, w, 0.125, 0.04, M["tail"], segs=12, sx=0.55, proud=0.010)
        c["lamp"] = "tail"
        out.append(c)
    out.append(K.stick_box("bumper_strip", K.on_rear(body, 0, 0.40), (1.25, 0.05, 0.03), M["trim"]))
    out.append(K.stick_box("plate_recess", K.on_rear(body, 0, 0.63), (0.44, 0.17, 0.01), M["trim"]))
    plate = K.stick_box("plate_r", K.on_rear(body, 0, 0.62), (0.36, 0.11, 0.01), M["plate"], proud=0.012)
    K.planar_uv(plate, 0, 2, flip_u=True)
    out.append(plate)
    out.append(K.stick_box("plate_chrome", K.on_rear(body, 0, 0.705), (0.42, 0.035, 0.02), chrome))
    out.append(K.stick_disc("badge_r", body, K.on_rear(body, 0, 0.82), 0.045, 0.02, M["badge"], segs=12))
    out.append(K.stick_disc("badge_r_ring", body, K.on_rear(body, 0, 0.82), 0.05, 0.015, chrome, segs=12))
    # rear wiper parked across the bottom of the rear window
    wiper = C.box("rear_wiper", (0.40, 0.02, 0.02), (-0.10, 1.445, 1.09), M["trim"])
    wiper.rotation_euler = (math.atan2(1.43 - 1.035, RW_Y1 - RW_Y0) - math.pi / 2, 0, math.radians(-8))
    C.apply_transform(wiper)
    out.append(wiper)
    # roof antenna, raked back
    loc, nor = K.on_top(body, 0, 1.12)
    ant = C.cylinder("antenna", 0.006, 0.30, segs=5, material=M["trim"])
    ant.rotation_euler = (math.radians(-35), 0, 0)
    ant.location = loc + Vector((0, 0.08, 0.12))
    C.apply_transform(ant)
    out.append(ant)
    out.append(K.stick_box("antenna_base", (loc, nor), (0.03, 0.06, 0.02), M["trim"]))
    if abarth:
        out.append(C.box("diffuser", (0.9, 0.10, 0.06), (0, 1.70, 0.25), M["dark"]))
    return out


def _sides(body, M, spec):
    out = []
    for sx in (1, -1):
        out.append(K.stick_box("side_ind", K.on_side(body, sx, -0.98, 0.66), (0.04, 0.025, 0.01), M["white"]))
        if spec.get("chrome"):
            out.append(K.stick_box("sill_trim", K.on_side(body, sx, -0.10, 0.25), (1.30, 0.025, 0.01), M["chrome"]))
    # fuel flap on the right rear quarter
    out.append(K.stick_disc("fuel_flap", body, K.on_side(body, -1, 1.20, 0.80), 0.07, 0.01, M["paint"],
                            segs=12, proud=0.002))
    return out


def _spoiler(M):
    return C.box("spoiler", (1.10, 0.28, 0.04), (0, 1.33, 1.40), M["paint"])


def _stripes(body, M):
    out = []
    for sx in (1, -1):
        for y in (-0.95, 0.75):
            out.append(K.stick_box("stripe_side", K.on_side(body, sx, y, 0.32), (0.40, 0.06, 0.004), M["stripe"]))
    for x in (0.16, -0.16):
        for y in (0.0, 0.45, 0.9):
            out.append(K.stick_box("stripe_roof", K.on_top(body, x, y), (0.16, 0.46, 0.004), M["stripe"]))
        for y in (-1.45, -1.1):
            out.append(K.stick_box("stripe_hood", K.on_top(body, x, y), (0.16, 0.36, 0.004), M["stripe"]))
    return out


def _fabric_roof(body, spec):
    fab = C.mat("RoofFabric", spec.get("fabric", "#2a1f1a"), rough=1.0)
    return K.stick_box("fabric_roof", K.on_top(body, 0, 0.42), (1.12, 1.30, 0.02), fab)


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
    bits.append(C.box_minmax("parcel_shelf", (-0.66, 1.30, 0.95), (0.66, 1.48, 0.97), M["cabin"]))
    for x in (-0.40, 0.40):
        visor = C.box("visor", (0.36, 0.16, 0.02), (x, -0.20, 1.38), M["headliner"])
        visor.rotation_euler = (math.radians(15), 0, 0)
        C.apply_transform(visor)
        bits.append(visor)
    bits.append(C.box("rear_mirror", (0.22, 0.03, 0.065), (0, -0.25, 1.33), M["knob"]))
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
