"""Details of the 2020-on 500 body (fiat500_shell.use('gen2')): the 500e,
the Abarth 500e and the 2025 500 Hybrid. Same conventions as the 2007-car
details in fiat500_modern: parts projected or stuck onto the uncut shell
`ref`, front at -Y. Shapes read off Commons reference photos (credited in
art/models/README.md); nothing is traced or textured from them.

What sets the 2020 car apart, front to back: the round eye split by the
bonnet's shut line (a thin LED "eyelid" on the bonnet edge, the wide lamp
below it), a small oval lamp lower down, no grille: a 500 script between
chrome whiskers, a wide perforated intake under the plate; flush door
handles in a recess; tall rounded tail lamps, FIAT spelt out on the
tailgate, a black diffuser with a strip lamp."""
import math

from mathutils import Vector

from . import carkit as K
from . import common as C
from . import fiat500_shell as S

LAMP_X, LAMP_Z = 0.50, 0.765          # main lamp centre, under the bonnet line
LAMP_W, LAMP_H = 0.245, 0.140
LID_Z = 0.835                           # the eyelid, just above the shut line
LOW_X, LOW_Z = 0.565, 0.600             # small oval lamp
BONNET_Z = 0.815                        # bonnet shut line across the nose


def _oval(w, h, n=14, flat_top=None):
    """Ellipse outline; flat_top cuts it level at that height (lamp tops
    trimmed by the bonnet)."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, z = w / 2 * math.cos(a), h / 2 * math.sin(a)
        if flat_top is not None:
            z = min(z, flat_top)
        pts.append((x, z))
    return pts


def _bonnet_line(ref, M):
    """Clamshell bonnet: level across the nose above the lamps, round the
    front corners and back along the wings to the A-pillar bases."""
    rays = []
    fr = K.front_frame()

    def wing(sx, ys):
        for y in ys:
            t = min(1.0, max(0.0, (y + 1.12) / 0.20))
            z = 0.86 + (0.995 - 0.86) * t * t
            rays.append(((sx * 3, y, z), (-sx, 0, 0)))
    corner_y = K.on_front(ref, 0.70, BONNET_Z)[0].y
    ys = [-0.95 + (corner_y + 0.07 + 0.95) * i / 11 for i in range(12)]
    wing(-1, ys)
    for i in range(13):
        x = -0.70 + i * 1.40 / 12
        rays.append(fr(x, BONNET_Z + 0.03 * (1 - (x / 0.70) ** 2)))
    wing(1, list(reversed(ys)))
    return S.ribbon("bonnet_line", ref, rays, 0.010, M["seam"])


def front(ref, M, spec, abarth):
    out = [_bonnet_line(ref, M)]
    fr = K.front_frame()
    chrome = M["chrome"] if spec.get("chrome", True) else M["satin"]
    for sx in (1, -1):
        cx = sx * LAMP_X
        # the main lamp: a wide oval with its top cut off by the bonnet line
        body = [(cx + u, LAMP_Z + v) for u, v in _oval(LAMP_W, LAMP_H * 1.35, 16, flat_top=LAMP_H / 2)]
        rim = K.project_poly("head_rim", ref, body, fr, M["trim"], offset=0.005, cuts=1)
        lens = K.project_poly("head", ref, [(cx + u * 0.9, LAMP_Z + v * 0.9 - 0.004) for u, v in
                                             _oval(LAMP_W, LAMP_H * 1.35, 16, flat_top=LAMP_H / 2)],
                              fr, M["head"], offset=0.007, cuts=1)
        lens["lamp"] = "head"
        # the LED ring along the lamp's lower edge and the projector outboard
        ring = [(cx + LAMP_W * 0.42 * math.cos(math.radians(a)), LAMP_Z - 0.005 + LAMP_H * 0.5 *
                 math.sin(math.radians(a))) for a in range(200, 341, 20)]
        out.append(K.project_line("head_led", ref, ring, fr, 0.012, M["white"], offset=0.009))
        w = K.hit(ref, *fr(cx + sx * 0.055, LAMP_Z + 0.008))
        out.append(K.stick_disc("projector", ref, w, 0.03, 0.02, M["reflector"], segs=10, proud=0.004))
        # the eyelid: a thin curved light on the bonnet edge
        lid = [(cx + LAMP_W * 0.47 * math.cos(math.radians(a)), LID_Z - 0.012 + 0.03 *
                math.sin(math.radians(a))) for a in range(25, 156, 13)]
        eyelid = K.project_line("eyelid", ref, lid, fr, 0.016, M["head"], offset=0.006)
        eyelid["lamp"] = "head"
        # small oval lamp lower down, a ring round a body-coloured centre
        lo = [(sx * LOW_X + u, LOW_Z + v) for u, v in _oval(0.15, 0.11, 14)]
        out.append(K.project_poly("low_ring", ref, lo, fr, M["white"], offset=0.006, cuts=1))
        out.append(K.project_poly("low_centre", ref, [(sx * LOW_X + u * 0.72, LOW_Z + v * 0.68) for u, v in
                                                     _oval(0.15, 0.11, 14)], fr, M["paint"], offset=0.008, cuts=1))
        out += [rim, lens, eyelid]
        if not abarth:
            # chrome whiskers either side of the 500 script
            for k, dz in enumerate((0.012, -0.004, -0.020)):
                bar = [(sx * 0.10, 0.705 + dz), (sx * (0.30 - 0.015 * k), 0.712 + dz)]
                out.append(K.project_line("whisker", ref, bar, fr, 0.008, chrome, offset=0.006))
            # corner vents: small black upright slots
            vent = [(sx * 0.60, 0.30), (sx * 0.66, 0.31), (sx * 0.67, 0.41), (sx * 0.62, 0.40)]
            out.append(K.project_poly("corner_vent", ref, vent, fr, M["dark"], offset=0.005, cuts=1))
    if abarth:
        out += abarth_front(ref, M)
    else:
        out += _script_500(ref, M, fr, 0.706)
        # the wide perforated intake under the plate
        intake = [(-0.42, 0.26), (0.42, 0.26), (0.47, 0.30), (0.45, 0.385), (-0.45, 0.385), (-0.47, 0.30)]
        out.append(K.project_poly("intake", ref, intake, fr, M["insert"], offset=0.006, cuts=5, border=0.014,
                                  border_mat=M["trim"]))
        for row, z in enumerate((0.285, 0.315, 0.345)):
            for i in range(-9, 10):
                x = i * 0.044 + (0.022 if row % 2 else 0)
                if abs(x) > 0.40:
                    continue
                out.append(K.stick_box("intake_hole", K.on_front(ref, x, z), (0.024, 0.016, 0.01), M["dark"],
                                       proud=0.004))
        if spec.get("grille_slot"):
            # the 2025 Hybrid's added slot under the whiskers, for the radiator
            slot = [(-0.24, 0.585), (0.24, 0.585), (0.26, 0.615), (-0.26, 0.615)]
            out.append(K.project_poly("hybrid_slot", ref, slot, fr, M["dark"], offset=0.006, cuts=3))
    pz = 0.50
    out.append(K.stick_box("plate_holder", K.on_front(ref, 0, pz), (0.42, 0.15, 0.02), M["trim"], proud=0.015))
    plate = K.stick_box("plate_f", K.on_front(ref, 0, pz), (0.372, 0.134, 0.01), M["plate"], proud=0.035)
    K.planar_uv(plate, 0, 2)
    out.append(plate)
    # cowl panel and wipers at the foot of the windscreen
    ws = S.WINDSCREEN
    yb = min(y for _, y in ws)          # base of the glass (most forward is the lowest y)
    cowl = [(-0.55, yb - 0.04), (0.0, yb - 0.07), (0.55, yb - 0.04), (0.60, yb + 0.03), (0.0, yb), (-0.60, yb + 0.03)]
    out.append(K.project_poly("cowl", ref, cowl, K.top_frame(), M["trim"], offset=0.004, cuts=3))
    for x, dy, ln in ((-0.30, 0.055, 0.56), (0.20, 0.04, 0.50)):
        out.append(K.stick_box("wiper", K.on_top(ref, x, yb + dy), (ln, 0.02, 0.015), M["trim"], proud=0.01))
    return out


def _script_500(ref, M, fr, z):
    """The '500' script badge: three chrome rings, the 5 a hooked stroke."""
    out = []
    for i, x in enumerate((-0.062, 0.0, 0.062)):
        if i == 0:
            five = [(x + 0.022, z + 0.028), (x - 0.012, z + 0.028), (x - 0.016, z + 0.004),
                    (x + 0.016, z + 0.004), (x + 0.022, z - 0.014), (x + 0.008, z - 0.028), (x - 0.02, z - 0.024)]
            out.append(K.project_line("script_5", ref, five, fr, 0.009, M["chrome"], offset=0.008))
        else:
            ring = [(x + 0.026 * math.cos(2 * math.pi * k / 12), z + 0.028 * math.sin(2 * math.pi * k / 12))
                    for k in range(13)]
            out.append(K.project_line("script_0", ref, ring, fr, 0.009, M["chrome"], offset=0.008))
    return out


def abarth_front(ref, M):
    """Abarth 500e nose: ABARTH across the face, a deeper full-width
    honeycomb intake, mesh corner intakes and a silver splitter."""
    fr = K.front_frame()
    out = []
    # the black lettering reads as a row of small blocks at this size
    for i in range(6):
        x = -0.125 + i * 0.05
        out.append(K.stick_box("abarth_letter", K.on_front(ref, x, 0.705), (0.034, 0.042, 0.008), M["dark"],
                               proud=0.004))
    # honeycomb intake under the plate and a mesh pocket in each corner;
    # dense outlines so the mesh hugs the curved bumper instead of cutting it
    intake = [(-0.40, 0.23), (0.40, 0.23), (0.43, 0.27), (0.42, 0.41), (-0.42, 0.41), (-0.43, 0.27)]
    out.append(K.project_poly("abarth_intake", ref, _dense(intake + intake[:1], 0.05)[:-1], fr, M["dark"],
                              offset=0.008, cuts=2, border=0.012, border_mat=M["trim"]))
    for sx in (1, -1):
        pocket = [(sx * 0.48, 0.25), (sx * 0.60, 0.27), (sx * 0.61, 0.38), (sx * 0.47, 0.37)]
        out.append(K.project_poly("abarth_pocket", ref, _dense(pocket + pocket[:1], 0.04)[:-1], fr, M["dark"],
                                  offset=0.008, cuts=2, border=0.01, border_mat=M["trim"]))
    split = [(x / 20, 0.215) for x in range(-12, 13)]
    out.append(K.project_line("splitter", ref, split, fr, 0.022, M["chrome"], offset=0.012))
    return out


def tail_lamp(ref, sx, M, smoked=False):
    """Tall rounded lamp on the rear corner: dark rim, red lens, a light
    bar across it."""
    centre = Vector((sx * 0.645, 1.62, 0.87))
    normal = Vector((sx * 0.35, 0.94, 0))
    fr = S.plane_frame(centre, normal)
    outline = S.rounded_rect(0.19, 0.27, 0.065)
    rim = K.project_poly("tail_rim", ref, outline, fr, None, offset=0.006, cuts=1, border=0.016,
                         border_mat=M["trim"])
    lens = K.project_poly("tail_red", ref, S.rounded_rect(0.16, 0.24, 0.055), fr,
                          M["tail"], offset=0.008, cuts=2)
    lens["lamp"] = "tail"
    bar = K.project_line("tail_bar", ref, [(-0.055, 0.0), (0.055, 0.0)], fr, 0.026, M["white"], offset=0.011)
    return [rim, lens, bar]


def rear(ref, M, spec, abarth):
    out = []
    rf = K.rear_frame()
    for sx in (1, -1):
        out += tail_lamp(ref, sx, M, smoked=abarth)
    # tailgate shut line: round the glass, down inside the lamps, across the bumper top
    gate = [(-0.52, 0.68), (-0.53, 0.86), (-0.54, 1.02), (-0.58, 1.10), (-0.595, 1.24), (-0.57, 1.37),
            (-0.50, 1.425), (0.50, 1.425), (0.57, 1.37), (0.595, 1.24), (0.58, 1.10), (0.54, 1.02),
            (0.53, 0.86), (0.52, 0.68)]
    out.append(K.project_line("tailgate_line", ref, _dense(gate + gate[:1], 0.05), rf, 0.012, M["seam"]))
    pz = 0.89
    out.append(K.stick_box("plate_recess", K.on_rear(ref, 0, pz), (0.43, 0.16, 0.01), M["trim"]))
    plate = K.stick_box("plate_r", K.on_rear(ref, 0, pz), (0.372, 0.134, 0.01), M["plate"], proud=0.008)
    K.planar_uv(plate, 0, 2, flip_u=True)
    out.append(plate)
    # FIAT (or ABARTH) spelt out over the plate
    word = 6 if abarth else 4
    for i in range(word):
        x = (i - (word - 1) / 2) * 0.042
        out.append(K.stick_box("rear_letter", K.on_rear(ref, x, 1.07), (0.03, 0.04, 0.008), M["chrome"],
                               proud=0.004))
    # the small model badge on the right of the tailgate
    if not abarth:
        wide = 0.16 if spec.get("badge") == "hybrid" else 0.10      # HYBRID is spelt out
        out.append(K.stick_box("model_badge", K.on_rear(ref, -0.38, 0.84), (wide, 0.025, 0.006),
                               M["chrome"], proud=0.004))
    # black diffuser across the bottom with a strip lamp in the middle
    diff = [(-0.62, 0.19), (0.62, 0.19), (0.60, 0.30), (-0.60, 0.30)]
    out.append(K.project_poly("diffuser", ref, diff, rf, M["trim"], offset=0.006, cuts=3))
    strip = K.project_poly("strip_lamp", ref, [(-0.16, 0.235), (0.16, 0.235), (0.16, 0.258), (-0.16, 0.258)],
                           rf, M["white"], offset=0.009, cuts=2)
    red = K.project_poly("strip_red", ref, [(-0.045, 0.236), (0.045, 0.236), (0.045, 0.257), (-0.045, 0.257)],
                         rf, M["tail"], offset=0.011, cuts=1)
    red["lamp"] = "tail"
    out += [strip, red]
    if abarth:
        u = [(-0.40, 0.30), (-0.40, 0.21), (0.40, 0.21), (0.40, 0.30)]
        out.append(K.project_line("diffuser_u", ref, u, rf, 0.018, M["chrome"], offset=0.012))
    # roof spoiler lip over the rear window, and the rear wiper
    # the roof runs on past the glass as a lip, overhanging it
    lip_y = K.on_top(ref, 0, 1.16)[0]
    # (the Abarth's is longer and deeper, with a black underside)
    if abarth:
        out.append(C.box("roof_lip", (1.06, 0.24, 0.05), (0, 1.20, lip_y.z - 0.012), M["paint"]))
        out.append(C.box("roof_lip_under", (1.0, 0.20, 0.012), (0, 1.22, lip_y.z - 0.04), M["trim"]))
    else:
        out.append(C.box("roof_lip", (1.0, 0.16, 0.04), (0, 1.17, lip_y.z - 0.012), M["paint"]))
    loc, nor = K.on_rear(ref, -0.17, 1.16)
    out.append(K.stick_box("rear_wiper", (loc, nor), (0.40, 0.02, 0.02), M["trim"], proud=0.012))
    # shark-fin aerial on the roof
    loc, _ = K.on_top(ref, 0, 0.98)
    out.append(_fin(loc, M["trim"]))
    return out


def _fin(base, mat):
    """Shark-fin aerial: a swept wedge, its foot on the roof at `base`."""
    prof = [(-0.08, 0.0), (0.08, 0.0), (0.075, 0.012), (0.02, 0.06), (-0.01, 0.065)]   # (y, z)
    verts = []
    for x in (-0.022, 0.022):
        verts += [(base.x + x * (0.6 if z > 0.03 else 1.0), base.y + y, base.z - 0.01 + z) for y, z in prof]
    n = len(prof)
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return C.mesh_obj("antenna_fin", verts, faces, mat)


def _dense(pts, step):
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.dist(a, b) / step + 0.999))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]
    return out + [pts[-1]]


def sides(ref, M, spec, abarth):
    out = []
    for sx in (1, -1):
        sf = K.side_frame(sx)
        if abarth:
            skirt = [(-0.76, 0.235), (0.76, 0.235), (0.76, 0.30), (-0.76, 0.30)]
            out.append(K.project_poly("skirt", ref, skirt, sf, M["trim"], offset=0.008, cuts=3))
        # chrome strip along the foot of the rear quarter glass, kicking up at the back
        strip = [(0.47, 1.068), (0.80, 1.074), (0.98, 1.085), (1.02, 1.105)]
        out.append(K.project_line("quarter_chrome", ref, strip, sf, 0.012, M["chrome"], offset=0.006))
        out.append(K.stick_box("side_ind", K.on_side(ref, sx, -0.95, 0.83), (0.05, 0.018, 0.01), M["white"]))
    if spec.get("half_door"):
        # the 3+1's small rear-hinged door on the passenger side (left here,
        # right-hand drive): its shut line ahead of and over the rear arch, up
        # to the quarter glass
        half = [(S.DOOR_Y1, 0.28), (0.74, 0.28), (0.78, 0.36), (0.80, 0.62), (0.86, 0.76), (0.97, 0.86),
                (1.00, 1.07)]
        out.append(K.project_line("half_door_line", ref, _dense(half, 0.04), K.side_frame(1), 0.009, M["seam"]))
    # charging flap on the right rear quarter (the Hybrid's fuel flap)
    w = K.on_side(ref, -1, 1.25, 0.86)
    out.append(K.stick_disc("flap_seam", ref, w, 0.072, 0.01, M["seam"], segs=14, proud=0.001))
    out.append(K.stick_disc("flap", ref, w, 0.064, 0.01, M["paint"], segs=14, proud=0.003))
    return out


def handle(ref, sx, M):
    """Flush door pull in a dark recess, toward the rear of the door."""
    return K.project_poly("handle_recess", ref, [(0.29, 0.855), (0.43, 0.855), (0.44, 0.882), (0.28, 0.882)],
                          K.side_frame(sx), M["trim"], offset=0.004, cuts=2)
