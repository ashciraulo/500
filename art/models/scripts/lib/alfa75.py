"""The 1988 Alfa 75 2.5 V6 ("2.5 6V Iniezione", European spec) you can buy at
the car yard, on the cars/ contract (art/models/README.md).

  4.331 x 1.631 x 1.349 m, wheelbase 2.51, track 1.36, 195/60 R14 tyres.
  Paint: Bianco Argento metallizzato (Alfa code 270), a pale warm
  champagne silver that reads silver where it mirrors the sky.

The 75 is a wedge: a low sharp nose under a long bonnet sloping down to it,
a belt line that climbs toward the tail, a tall flat boot with a lip, and
the black band that ties it together: across the front bumper, up each
front wing to the foot of the windscreen, along under the side windows and
round the tail as the boot lid's lip spoiler. Rectangular headlamps either
side of a slatted black grille with the shield in the middle (here with a
made-up round badge, never a real logo), a wide strip of tail lamps, black
window frames and B pillars, black door pulls, body-coloured lower bumpers
under black rubbing strips.

The reference photos (1985-88 European 75s, two of them 2.5 V6s, and Ash's
own photo of the car) are in /mnt/project-files/alfa-75/ref/ with their
sources in SOURCES.txt.

Same conventions as lib/period_vehicles.py while building: front toward +Y,
driver (right-hand drive) on +X, origin on the ground at the footprint
centre. `alfa_car_finish` moves the origin midway between the axles.

The body is lofted through cross sections along the car. Each section is a
half profile (x >= 0) from the underside centre round the side to the top
centre; the other side is mirrored.
"""
import math

import bpy  # noqa: F401,I001  (bpy must load before bmesh)
import bmesh
from mathutils import Vector

from . import common as C
from . import furniture as F
from . import city_vehicles as CV
from . import carkit as K
from . import period_vehicles as PV
from . import alfa75_parts as AP

bx, cyl = F.bx, F.cyl
_m = CV._m
_loft, _prism, _cutter, _cut = PV._loft, PV._prism, PV._cutter, PV._cut
_round_poly, _ring, _dense, _sweep = PV._round_poly, PV._ring, PV._dense, PV._sweep
_smoothed, _fix_normals, _flat = PV._smoothed, PV._fix_normals, PV._flat

L, W, H = 4.331, 1.631, 1.349
WB = 2.51
# the bumpers' faces at the centre line: the front 12 cm ahead of the lamps
# as the photos show it, the rear out to make 4.26 m overall (the books say
# 4.33, the side photos measure 4.29)
YF, YR = 2.10, -2.16
AXLE_F = 1.3055
AXLE_R = AXLE_F - WB
HW = W / 2
TYRE_R = 0.295
TRACK_X = 0.68                     # the wheels' centre planes, either side

PAINT = "#ccc4b8"                  # Bianco Argento: see /mnt/project-files/alfa-75/paint/


def _mats():
    M = CV._common()
    M.update({
        "paint": _m("Paint", PAINT, 0.3, 0.45),
        "glass": C.mat("A75_Glass", "#5f7480", rough=0.03, metal=0.35, alpha=0.5),
        # the band, bumper strips, window frames: a dark grey satin plastic
        "band": _m("A75_Band", "#1c1d1f", 0.8),
        "black": _m("A75_Black", "#121314", 0.85),
        "trim": _m("A75_Trim", "#3a3b3d", 0.85),
        "under": _m("A75_Under", "#1c1d1f", 0.9),
        "shut": _m("A75_Shut", "#6e6a62", 0.7),
        "chrome": _m("A75_Chrome", "#d9dcdd", 0.18, 0.95),
        "head": _m("A75_HeadLamp", "#a2acb0", 0.04, 0.5),
        "amber": _m("A75_Amber", "#d9741c", 0.15, 0.2),
        # the front corner lamps are clear glass over an amber bulb
        "clear_ind": _m("A75_CornerLamp", "#d6d6cf", 0.04, 0.5),
        "slat": _m("A75_GrilleSlat", "#a9a59c", 0.4, 0.5),
        "crease_hi": _m("A75_CreaseHi", "#ddd7cc", 0.35, 0.4),
        "lampline": _m("A75_LampLine", "#7f8b90", 0.2, 0.4),
        "tail": _m("A75_TailLamp", "#a4141a", 0.25),
        "reverse": _m("A75_Reverse", "#cfcfca", 0.15, 0.3),
        "plate": _m("A75_Plate", "#f1f0ea", 0.7),
        "reflector": _m("A75_TailStrip", "#c4521a", 0.3, 0.1),
        "red": _m("A75_BadgeRed", "#a01b1e", 0.4),
        # the bonnet's creases: a hair darker than the paint
        "crease": _m("A75_Crease", "#a39a88", 0.45, 0.3),
        "tyre": _m("A75_Tyre", "#18181a", 0.92),
    })
    return M


# ------------------------------------------------------------------ the shell
#
# Every key below is a curve along the car read off the side photo of the
# Bianco Argento car (ba_co6.jpg, scaled by its wheelbase) and checked on
# the others with matched cameras.

Y0, Y1 = -2.05, 1.99                 # shell ends: the tail panel, the nose (bumpers beyond)
WS_B, WS_T = 0.80, 0.30              # windscreen base and top (centre line)
BL_B, BL_T = -1.60, -1.06            # backlight base and top: a long, flat screen (about 27 deg)
ZR = 1.355                           # roof centre
WR = 0.545                           # roof edge half width: the glass leans well in
ZRE = 1.305                          # roof edge (the rail over the side glass)
FIL_F, FIL_R = 0.015, 0.03           # end fillet radii (in side view): a thin bonnet lip

# half width in plan: the ends draw in round the corners
# (the nose's corners are cut back at 45 degrees from y 1.85, with the
# indicators on the cut)
# (the tail tapers in from behind the rear arch, about 5 cm a side, and
# rounds its corners)
_W = K.pchip([Y0, Y0 + 0.01, Y0 + 0.03, Y0 + 0.06, Y0 + 0.1, -1.8, -1.6, -1.3, 1.3, 1.62, 1.84, 1.9, 1.95, Y1],
             [HW - 0.15, HW - 0.12, HW - 0.095, HW - 0.075, HW - 0.06, HW - 0.037, HW - 0.012, HW, HW, HW - 0.004,
              HW - 0.01, HW - 0.058, HW - 0.108, HW - 0.148])
# underside
_ZBOT = K.pchip([Y0, -1.78, -1.55, 1.62, 1.8, Y1], [0.46, 0.34, 0.275, 0.275, 0.34, 0.46])


# the black band's centre in side view (ba_co6.jpg, measured along the
# whole car): one straight line rising from the windscreen's foot right to
# the tail, where the lip spoiler comes down to meet it; at the front it
# falls away along the wing's shoulder to the headlamp's corner
def _band_lin(y):
    return 0.85 - 0.0464 * (y - 0.756)


BAND = K.pchip([Y0 + 0.04, -1.5, -0.5, 0.5, 1.0] + [1.3, 1.54, 1.75, 1.95],
               [_band_lin(y) for y in (Y0 + 0.04, -1.5, -0.5, 0.5, 1.0)] + [0.822, 0.785, 0.748, 0.705])
# it is even under the glass and tapers along the wing to a thin line at
# the headlamp's corner
BAND_W = K.pchip([Y0 + 0.04, -1.0, 0.72, 1.0, 1.4, 1.95], [0.036, 0.036, 0.036, 0.032, 0.024, 0.012])


def band_at(y):
    y = min(max(y, Y0 + 0.04), 1.95)
    return float(BAND(y)), float(BAND_W(y))


# the character line along the side under the band: the side is widest
# here and leans in above it to the shoulder. It runs from the tail lamps'
# middle along the doors, over the front arch and down to the corner lamp's
# foot
CREASE_U = K.pchip([Y0, -1.2, -0.27, 0.75, 1.25, 1.6, Y1], [0.74, 0.72, 0.707, 0.70, 0.69, 0.64, 0.575])


def ZB(y):
    """The side glass's base (the belt): it sits on the band, so it is one
    straight line too."""
    y = min(max(y, -1.15), 0.72)
    return float(BAND(y)) + 0.5 * float(BAND_W(y)) + 0.002


# the bonnet: its centre and its edge along the top of each wing
# (the shoulder runs just over the band; the bonnet stays high and crowned
# and only falls away over the last 0.4 m)
# (its centre in side view is nearly a straight wedge down to the nose, as
# the side photo traces it: no hump)
_ZD_F = K.pchip([WS_B, 1.0, 1.2, 1.4, 1.6, 1.8, Y1], [0.915, 0.888, 0.859, 0.826, 0.785, 0.739, 0.698])
_ZE_F = K.pchip([WS_B, 1.2, 1.6, Y1], [0.884, 0.852, 0.796, 0.712])   # just over the band's top edge
_CROWN_F = 0.02
# the boot: a flat, very slightly falling deck, and its edge over the quarters
# (it falls about 6 cm from the screen's foot to the lip: the tail tapers
# down in side view)
# and over its last 7 cm the lid rolls down round the tail, where the lip
# spoiler wraps it at the band's height
_ZD_R = K.pchip([Y0, Y0 + 0.03, Y0 + 0.07, -1.8, BL_B], [0.968, 0.995, 1.01, 1.024, 1.05])
_ZE_R = K.pchip([Y0, Y0 + 0.03, Y0 + 0.07, -1.8, BL_B, -1.15], [0.96, 0.99, 1.0, 1.005, 1.0, 0.95])
_CROWN_R = 0.008


def _screen_frac(t, top):
    return K.pchip([0.0, 0.5, 0.88, 1.0], [0.0, 0.5, top, 1.0])(t)


def _crown(x0, z0, zt, f):
    """A point on the parabola from (x0, z0) at the shoulder to zt on the
    centre line, f of the way out: one smooth curve, flat across the middle."""
    return (f * x0, z0 + (zt - z0) * (1 - f * f))


def _deck(y, w):
    """Upper five points over the bonnet (y > 0) or boot (y < 0): the edge,
    a rolled shoulder, then one smooth crown over the middle."""
    if y > 0:
        zd, ze, c = _ZD_F(y), _ZE_F(y), _CROWN_F
    else:
        zd, ze, c = _ZD_R(y), _ZE_R(y), _CROWN_R
    xe, z2 = w - 0.07, ze + 0.006
    zt = max(zd + c, z2 + 0.004)
    return [(w - 0.044, ze), (xe, z2), _crown(xe, z2, zt, 0.66), _crown(xe, z2, zt, 0.33), (0.0, zt)]


def roof_drop(y):
    """How far the roof sits below ZR / ZRE at y: it slopes down slightly
    toward the front, most over the front seats."""
    return (0.012 * min(max((y + 1.0) / 0.8, 0.0), 1.0) +
            0.022 * min(max((y + 0.2) / 0.5, 0.0), 1.0))


def _cabin(y, w, k=1.0):
    """Upper five points through the greenhouse: out over the belt, the side
    glass leaning in to the roof rail, the roof. k < 1 flattens the crown
    (over the backlight, so the C pillars stand as high as the glass and
    hide it from the side)."""
    zb, dz = ZB(y), roof_drop(y)
    zr, zre = ZR - dz, ZR - dz - (ZR - ZRE) * k
    return [(w - 0.044, zb - 0.006), (w - 0.07, zb), (WR, zre), _crown(WR, zre, zr, 0.5), (0.0, zr)]


def _controls(y):
    w, zb = _W(y), _ZBOT(y)
    if y >= WS_B:
        top = _deck(y, w)
    elif y <= BL_B:
        top = _deck(y, w)
    elif WS_T <= y < WS_B:
        f = _screen_frac((WS_B - y) / (WS_B - WS_T), 0.93)
        top = [(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
               for a, b in zip(_deck(WS_B, w), _cabin(y, w))]
    elif BL_B < y <= BL_T:
        u = (y - BL_B) / (BL_T - BL_B)
        f = _screen_frac(u, 0.92)
        top = [(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
               for a, b in zip(_deck(BL_B, w), _cabin(y, w, 0.1 + 0.9 * u ** 3))]
    else:
        top = _cabin(y, w)
    zs = top[0][1] - 0.006                 # the shoulder, under the deck edge or the belt: a crisp edge
    zc = min(max(float(CREASE_U(y)), zb + 0.14), zs - 0.06)
    # the side: tucked under at the sill, plumb up to the character line,
    # then leaning in about 3.5 cm to the shoulder
    side = [(0.0, zb), (w - 0.1, zb), (w - 0.03, zb + 0.02), (w - 0.008, zb + 0.1),
            (w - 0.0015, zc - 0.025), (w, zc), (w - 0.005, zc + 0.02), (w - 0.036, zs)]
    return side + top


_COUNTS = [3, 2, 2, 3, 1, 1, 3, 1, 2, 3, 3, 3]


def _catmull_sym(pts, counts):
    """Catmull-Rom through pts, mirrored about the centre line at both ends,
    so the section crosses it level: no ridge down the bonnet, roof or
    floor."""
    ext = [(-pts[1][0], pts[1][1])] + list(pts) + [(-pts[-2][0], pts[-2][1])]
    return PV._catmull(ext, [0] + list(counts) + [0])[:-1] + [tuple(pts[-1])]


def _profile(y):
    return _catmull_sym(_controls(y), _COUNTS)


def _station_ys():
    keys = [Y0, -1.75, BL_B, BL_T, 0.0, WS_T, WS_B, 1.6, Y1]
    ys = set()
    for a, b in zip(keys, keys[1:]):
        n = max(1, round((b - a) / 0.05))
        ys.update(round(a + (b - a) * k / n, 4) for k in range(n + 1))
    for end, r, sgn in ((Y0, FIL_R, 1), (Y1, FIL_F, -1)):
        for deg in (20, 40, 55, 70, 80, 90):
            ys.add(round(end + sgn * r * (1 - math.cos(math.radians(deg))), 4))
    out = []
    for y in sorted(ys):
        if out and y - out[-1] < 0.003:
            continue
        out.append(y)
    return out


def _stations():
    st = []
    for y in _station_ys():
        pts = _profile(y)
        for end, r in ((Y0, FIL_R), (Y1, FIL_F)):
            s = abs(y - end)
            if s < r:
                d = r - math.sqrt(max(r * r - (r - s) ** 2, 0.0))
                nrm = PV._normals2d(pts)
                pts = [(max(x - nx * d, 0.0) if i not in (0, len(pts) - 1) else 0.0, z - nz * d)
                       for i, ((x, z), (nx, nz)) in enumerate(zip(pts, nrm))]
        st.append(K.Station(y, pts))
    return st


def _a_line(z):
    """Side view (y) of the A pillar's outer edge at height z."""
    return 0.724 - (0.724 - 0.28) * (z - 0.868) / (ZRE - roof_drop(0.28) - 0.868)


def _c_line(z):
    """Side view (y) of the C pillar's edge along the backlight."""
    return -1.44 + (-1.06 + 1.44) * (z - 1.05) / (ZRE - 1.05)


DLO_Z1 = ZRE - 0.04                 # top of the side glass (at the back: it follows the roof down)
B_FRONT, B_REAR = -0.215, -0.275    # the B pillar between the door glasses: narrow, body colour
GLASS_REAR = (-1.08, -0.895)        # the rear door glass's back edge, at the belt and at the top
REAR_DIVIDER = -0.858               # the bar splitting the rear door glass from its fixed quarter light


def dlo_top(y):
    return DLO_Z1 - roof_drop(y)


def _dlo(y0, y1, z_inset=0.016):
    return lambda y: ZB(y) + z_inset


def side_front():
    """Front door glass (y, z): the A pillar, the belt, the B pillar."""
    zb = _dlo(0, 0)
    ya0 = _a_line(zb(0.7)) - 0.035
    ya1 = _a_line(dlo_top(0.3)) - 0.035
    return _round_poly([(ya0, zb(ya0)), (B_FRONT, zb(B_FRONT)), (B_FRONT, dlo_top(B_FRONT)), (ya1, dlo_top(ya1))],
                       0.03)


def side_rear():
    zb = _dlo(0, 0)
    g0, g1 = GLASS_REAR
    return _round_poly([(B_REAR, zb(B_REAR)), (g0, zb(g0)), (g1, dlo_top(g1)), (B_REAR, dlo_top(B_REAR))], 0.05)


def windscreen():
    return _round_poly([(-0.72, WS_B - 0.02), (0.72, WS_B - 0.02), (WR - 0.05, WS_T + 0.025),
                        (-(WR - 0.05), WS_T + 0.025)], 0.06)


def backlight():
    # narrow enough at its foot that the C pillars hide it from the side
    return _round_poly([(-0.57, BL_B + 0.025), (-(WR - 0.08), BL_T - 0.025), (WR - 0.08, BL_T - 0.025),
                        (0.57, BL_B + 0.025)], 0.06)


ARCH_F, ARCH_R = 0.345, 0.34      # the openings, inside the flares
FLARE_F, FLARE_R = 0.413, 0.40     # the flares' outer edges
ARCH_N, ARCH_TOP = 3.4, 0.95       # the arches' tops flatten off: a superellipse, a little lower


def arch_pt(a_deg, r):
    """(dy, dz) from the axle of the arch outline of radius r at angle a
    (0 forward, 90 up): round at the sides, flattened over the top."""
    a = math.radians(a_deg)
    c, s = math.cos(a), math.sin(a)
    if s <= 0:
        return r * c, r * s
    e = 2.0 / ARCH_N
    return r * math.copysign(abs(c) ** e, c), r * ARCH_TOP * s ** e


def arch_poly(y0, r, step=6):
    return [(y0 + dy, TYRE_R + dz) for dy, dz in (arch_pt(a, r) for a in range(0, 360, step))]

# the nose (x, z) under the bonnet's lip, NOSE_Y back from the lip
NOSE_Y = 1.958
NOSE = [(-0.69, 0.523), (0.69, 0.523), (0.69, 0.707), (-0.69, 0.707)]
# the tail lamps' strip (x, z), TAIL_Y in from the tail panel
TAIL_Y = -2.035
TAIL = [(-0.665, 0.61), (0.665, 0.61), (0.665, 0.80), (-0.665, 0.80)]
TAIL_Z0, TAIL_Z1, TAIL_TOP = 0.64, 0.762, 0.79   # the lamps, and the amber strip over them to TAIL_TOP
PLATE_Z0 = 0.622                   # the rear plate, low in its recess
TAIL_X1 = 0.66                     # the lamps' flat part ends here; they then wrap the corner


def _shell(M):
    """The painted body, cut and thickened, plus a copy of the uncut surface
    to lay glass and trim on. Returns (body, reference surface)."""
    st = _stations()
    verts, faces, tags, uvs = K.loft(st, lambda *a: K.T_PAINT)
    body = K.shell_object("shell", verts, faces, tags, uvs)
    from mathutils.geometry import tessellate_polygon
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for f in [f for f in bm.faces if len(f.verts) > 4]:
        vs, mi = list(f.verts), f.material_index
        tris = tessellate_polygon([[v.co.copy() for v in vs]])
        bm.faces.remove(f)
        for t in tris:
            nf = bm.faces.new([vs[i] for i in t])
            nf.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    ref = body.copy()
    ref.data = body.data.copy()
    C.link(ref)
    for y, r in ((AXLE_F, ARCH_F), (AXLE_R, ARCH_R)):
        for sx in (-1, 1):
            _cut(body, _cutter("arch", arch_poly(y, r), PV._side_place(sx), 0.55, 1.2, "Under"))
    # under the bonnet's lip the nose steps back: lamps and grille sit in it
    _cut(body, _cutter("nose", _round_poly(NOSE, 0.02, 3), lambda u, v, d: (u, d, v), NOSE_Y, 3.0, "Under"))
    # the tail lamps and the plate sit in a full-width recess in the tail
    _cut(body, _cutter("tail", _round_poly(TAIL, 0.02, 3), lambda u, v, d: (u, d, v), -3.0, TAIL_Y, "Under"))
    for sx in (-1, 1):
        for poly in (side_front(), side_rear()):
            _cut(body, _cutter("win", poly, PV._side_place(sx), 0.45, 1.5, "Glass"))
    _cut(body, _cutter("ws", windscreen(), lambda u, v, d: (u, v, d), 0.95, 2.5, "Glass"))
    _cut(body, _cutter("bl", backlight(), lambda u, v, d: (u, v, d), 1.0, 2.5, "Glass"))
    parts = K.split_by_tag(body, {"body": {"Paint": M["paint"], "Under": M["under"], "Trim": M["trim"]}},
                           smooth_angle=38)
    body = parts["body"]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(body.data)
    bm.free()
    K.solidify(body, 0.012, M["trim"])
    return body, ref


def _glass(M, ref, body, frames=True):
    p = []
    top = K.top_frame()
    for sx in (-1, 1):
        fr = K.side_frame(sx)
        for poly in (side_front(), side_rear()):
            p.append(K.project_poly("glass", ref, K.offset_poly(poly, -0.012), fr, M["glass"], offset=-0.006))
            if frames:
                p.append(K.project_poly("frame", body, K.offset_poly(poly, -0.02), fr, None, offset=0.004,
                                        border=0.02, border_mat=M["black"]))
    for poly in (windscreen(), backlight()):
        p.append(K.project_poly("glass", ref, K.offset_poly(poly, -0.012), top, M["glass"], offset=-0.006))
        if frames:
            p.append(K.project_poly("frame", body, K.offset_poly(poly, -0.016), top, None, offset=0.004,
                                    border=0.014, border_mat=M["black"]))
    return p


def _hit_y(ref, x, z, front=True):
    """Where the uncut surface is, along y, at (x, z) seen from the front or back."""
    o, d = ((x, 5.0, z), (0, -1, 0)) if front else ((x, -5.0, z), (0, 1, 0))
    ok, loc, _, _ = K.surface_ray(ref, o, d)
    return loc.y if ok else None


def _box_pts(x0, x1, z0, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def _facing(o, out):
    """Flip o's faces if they face away from the direction `out`."""
    me = o.data
    me.update()
    if sum((pl.normal.dot(Vector(out)) * pl.area for pl in me.polygons)) < 0:
        me.flip_normals()
    return o


def _flares(M, ref):
    """The wheel arches' flares: a body-coloured lip round each opening,
    standing proud of the side at the opening and fairing back into it at
    the outer edge, turned in at the opening."""
    p = []
    for y0, r0, r1 in ((AXLE_F, ARCH_F, FLARE_F), (AXLE_R, ARCH_R, FLARE_R)):
        for sx in (-1, 1):
            fr = K.side_frame(sx)
            rings = [(r0, 0.02), (r0 + 0.3 * (r1 - r0), 0.016), (r0 + 0.65 * (r1 - r0), 0.008), (r1, 0.002)]
            rows = []
            for a in range(4, 177, 4):
                row = []
                for r, lift in rings:
                    dy, dz = arch_pt(a, r)
                    ok, loc, nor, _ = K.surface_ray(ref, *fr(y0 + dy, TYRE_R + dz))
                    if not ok:
                        break
                    row.append(loc + Vector((sx, 0, 0)) * lift)
                if len(row) == len(rings):
                    # turned in round the opening
                    row.insert(0, row[0] - Vector((sx * 0.045, 0, 0)))
                    rows.append(row)
            m = len(rows[0])
            verts = [v for row in rows for v in row]
            faces = [(i * m + j, i * m + j + 1, (i + 1) * m + j + 1, (i + 1) * m + j)
                     for i in range(len(rows) - 1) for j in range(m - 1)]
            p.append(_smoothed(_facing(C.mesh_obj("flare", verts, faces, M["paint"]), (sx, 0, 0)), 50))
    return p


def _ribbon(name, target, pts, frame, width, mat, offset, across=4):
    """A strip `width` wide along a 2D polyline, projected onto the surface
    `across` points at a time so it follows the curve both ways."""
    rows = []
    for i, q in enumerate(pts):
        a, b = Vector(pts[max(i - 1, 0)]), Vector(pts[min(i + 1, len(pts) - 1)])
        t = (b - a).normalized()
        nrm = Vector((-t.y, t.x))
        row = []
        wd = width(q[0]) if callable(width) else width
        for k in range(across):
            u, v = Vector(q) + nrm * wd * (k / (across - 1) - 0.5)
            ok, loc, nor, _ = K.surface_ray(target, *frame(u, v))
            row.append(loc + nor * offset if ok else None)
        if None not in row:
            rows.append(row)
    verts = [v for row in rows for v in row]
    faces = [(i * across + j, i * across + j + 1, (i + 1) * across + j + 1, (i + 1) * across + j)
             for i in range(len(rows) - 1) for j in range(across - 1)]
    return _smoothed(C.mesh_obj(name, verts, faces, mat), 50)


SILL_Z0, SILL_Z1 = 0.278, 0.338    # the body-colour skirt between the arches; a bright strip over it
CREASE_Z = 0.535                   # the crease along the doors from arch to arch


def _sills(M, ref):
    """Between the arches along the doors' foot: a dark grey skirt with a
    bright strip along its top, and the crease along the doors above."""
    p = []
    y0, y1 = AXLE_R + FLARE_R - 0.004, AXLE_F - FLARE_F + 0.004
    for sx in (-1, 1):
        fr = K.side_frame(sx)
        mid = (SILL_Z0 + SILL_Z1) / 2
        p.append(_facing(_ribbon("sill", ref, _dense([(y0, mid), (y1, mid)], 0.05), fr, SILL_Z1 - SILL_Z0,
                                 M["paint"], 0.007), (sx, 0, 0)))
        p.append(_facing(_ribbon("sill_strip", ref, _dense([(y0, SILL_Z1 + 0.006), (y1, SILL_Z1 + 0.006)], 0.05), fr,
                                 0.01, M["chrome"], 0.007, across=2), (sx, 0, 0)))
        c0, c1 = AXLE_R + FLARE_R + 0.01, AXLE_F - FLARE_F - 0.01
        p.append(_facing(_ribbon("crease_hi", ref, _dense([(c0, CREASE_Z + 0.003), (c1, CREASE_Z + 0.003)], 0.05),
                                 fr, 0.005, M["crease_hi"], 0.003, across=2), (sx, 0, 0)))
        p.append(_facing(_ribbon("crease", ref, _dense([(c0, CREASE_Z - 0.003), (c1, CREASE_Z - 0.003)], 0.05),
                                 fr, 0.006, M["crease"], 0.003, across=2), (sx, 0, 0)))
    return p


# ------------------------------------------------------------------ the nose
#
# Headlamps: a big rectangular glass each side, the indicator round the cut
# corner beside it; between them the grille, dark slots with bright slats
# in a body-coloured panel, and the shield standing down through it over
# the bumper's band.

LAMP_X0, LAMP_X1, LAMP_Z0, LAMP_Z1 = 0.40, 0.675, 0.535, 0.70
GRILLE_X, GRILLE_Z0, GRILLE_Z1 = 0.386, 0.535, 0.703
# the indicators sit on the nose's cut corners, from the headlamp's end back
# along the cut (x, y)
CORNER_A, CORNER_B = (0.685, 1.97), (0.79, 1.865)
SHIELD_W, SHIELD_TOP, SHIELD_TIP = 0.13, 0.703, 0.521


def _plan_front(x):
    """The face of the nose recess the lamps and grille stand on."""
    return NOSE_Y


SHIELD_LOW = 0.538                 # below this the shield lies over the bumper


def _apron_y(z):
    """Where the front bumper's surface is, along y, at height z on the
    centre line: up its face to the band's top edge, then back up the
    apron to under the lamps."""
    if z <= BUMPER_F_TOP:
        return YF + 0.009
    return YF - 0.006 - (z - BUMPER_F_TOP) / APRON_RISE * (APRON_DEPTH - 0.006)


def _drape(name, poly, mat, lift):
    """A flat (x, z) outline laid over the front bumper's apron and face,
    `lift` clear of them."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, z, 0)) for x, z in poly]
    bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=5, use_grid_fill=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for v in me.vertices:
        x, z = v.co.x, v.co.y
        on_face = z <= BUMPER_F_TOP
        v.co = (x, _apron_y(z) + (lift if on_face else 0.0), z + (0.0 if on_face else lift))
    o = bpy.data.objects.new(name, me)
    me.materials.append(mat)
    C.link(o)
    return _facing(o, (0, 1, 1))


def _shield_x(z):
    """Half width of the shield's outline at height z, on its straight sides."""
    sh = shield_outline()
    (x0, z0), (x1, z1) = sh[2], sh[3]
    return x0 + (x1 - x0) * (z0 - z) / (z0 - z1)


def shield_outline(inset=0.0):
    """(x, z) outline of the shield: straight sides drawing in from the top
    corners to a rounded point."""
    w, t, b = SHIELD_W - inset, SHIELD_TOP - inset, SHIELD_TIP + inset * 1.6
    pts = [(-w, t), (w, t), (w * 0.98, t - 0.05)]
    pts += [(w * 0.18 * math.cos(math.radians(a)), b + 0.022 + 0.022 * math.sin(math.radians(a)))
            for a in range(-20, -161, -35)]
    pts += [(-w * 0.98, t - 0.05)]
    return pts


def _nose(M, ref):
    p = []
    yb = _plan_front(0.0)
    # grille: a body-coloured panel with a dark slotted panel either side
    # of the shield, thin bright slats across the slots
    gy = yb + 0.02
    frame = _round_poly(_box_pts(-GRILLE_X, GRILLE_X, GRILLE_Z0, GRILLE_Z1), 0.008, 2)
    p.append(_prism("grille_panel", frame, "y", gy - 0.02, gy, M["paint"]))
    for sx in (-1, 1):
        xo = GRILLE_X - 0.022
        x_in = lambda z: _shield_x(z) + 0.014
        slot = [(sx * x_in(GRILLE_Z1 - 0.016), GRILLE_Z1 - 0.016), (sx * xo, GRILLE_Z1 - 0.016),
                (sx * xo, GRILLE_Z0 + 0.016), (sx * x_in(GRILLE_Z0 + 0.016), GRILLE_Z0 + 0.016)]
        p.append(_prism("grille_slot", slot, "y", gy - 0.004, gy + 0.001, M["black"]))
        for i in range(5):
            z = GRILLE_Z0 + 0.028 + i * (GRILLE_Z1 - GRILLE_Z0 - 0.056) / 4
            xs = x_in(z)
            p.append(bx((min(sx * xs, sx * xo), gy - 0.003, z - 0.003), (max(sx * xs, sx * xo), gy + 0.002,
                        z + 0.003), M["slat"]))
    # the shield: a chrome rim, black inside, a made-up round badge at the top
    sh = shield_outline()
    shi = shield_outline(0.012)
    p.append(_prism("shield", sh, "y", gy - 0.01, gy + 0.012, M["chrome"]))
    p.append(_prism("shield_in", shi, "y", gy + 0.012, gy + 0.016, M["black"]))
    badge = K.revolve("badge", [(0.0, 0.006), (0.026, 0.006), (0.03, 0.0)], 16, lambda i: M["chrome"],
                      loc=(0, gy + 0.016, SHIELD_TOP - 0.042))
    badge.rotation_euler = (0, 0, math.radians(90))
    p.append(badge)
    p.append(K.revolve("badge_in", [(0.0, 0.0075), (0.018, 0.0075)], 16, lambda i: M["red"],
                       loc=(0, gy + 0.016, SHIELD_TOP - 0.042)))
    p[-1].rotation_euler = (0, 0, math.radians(90))
    return p


def _corner_frame(sx, a, b):
    """(u, z) -> a ray square onto the cut corner from a to b (x, y), u
    metres along it from a."""
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    ln = math.hypot(dx, dy)
    tx, ty = dx / ln, dy / ln
    nx, ny = ty, -tx                       # outward for sx = +1 (a inboard, b outboard)
    if nx < 0:
        nx, ny = -nx, -ny
    return lambda u, v: ((sx * (ax + tx * u + nx * 0.5), ay + ty * u + ny * 0.5, v), (-sx * nx, -ny, 0.0)), ln


def _head_lamps(M, ref):
    """HeadL/HeadR (lamp glass, LampHead) over one wide reflector each, the
    amber indicator round the cut corner beside it."""
    out, p = [], []
    for name, sx in (("HeadL", -1), ("HeadR", 1)):
        x0, x1 = LAMP_X0, LAMP_X1
        yb = _plan_front(0.6)
        bowl = _box_pts(*sorted((sx * x0, sx * (x1 + 0.012))), LAMP_Z0, LAMP_Z1)
        p.append(_prism("lamp_bowl", bowl, "y", yb - 0.002, yb + 0.016, M["black"]))
        box = _box_pts(*sorted((sx * x0, sx * x1)), LAMP_Z0, LAMP_Z1)
        glass = _prism("lamp_glass", K.offset_poly(_round_poly(box, 0.008, 2), 0.006), "y", yb + 0.014, yb + 0.022,
                       M["head"])
        # one wide reflector behind the glass, and a dark divider line
        refl = K.offset_poly(box, 0.012)
        p.append(_prism("reflector", refl, "y", yb + 0.004, yb + 0.008, M["chrome"]))
        xd = 0.4 * x0 + 0.6 * x1
        p.append(bx((sx * xd - 0.003, yb + 0.006, LAMP_Z0 + 0.012), (sx * xd + 0.003, yb + 0.012,
                    LAMP_Z1 - 0.012), M["black"]))
        out.append((name, [glass], None, None))
        # the indicator: a clear lens wrapped round the cut corner, in a
        # thin black surround
        # its top falls away with the wing's line to a narrow tail at the back
        fr, ln = _corner_frame(sx, CORNER_A, CORNER_B)
        tip = LAMP_Z0 + 0.028
        p.append(_facing(K.project_poly("indicator_rim", ref, [(0.0, LAMP_Z0), (ln, LAMP_Z0), (ln, tip),
                                                               (0.0, LAMP_Z1)], fr, M["black"],
                                        offset=0.004, cuts=3), (sx, 1, 0)))
        p.append(_facing(K.project_poly("indicator", ref, _round_poly([(0.006, LAMP_Z0 + 0.006),
                                                                       (ln - 0.006, LAMP_Z0 + 0.006),
                                                                       (ln - 0.006, tip - 0.006),
                                                                       (0.006, LAMP_Z1 - 0.008)], 0.008, 2),
                                        fr, M["clear_ind"], offset=0.007, cuts=3), (sx, 1, 0)))
    return out, p


# ------------------------------------------------------------------ bumpers
#
# Both bumpers are a black rubbing strip over a body-coloured lower half,
# wrapping round the corners back to the wheel arches.

BUMPER_F_TOP = 0.525              # the front band's top edge, just under the lamps
APRON_DEPTH, APRON_RISE = 0.12, 0.01    # its apron back and up to under the lamps


def _bumper_profile(z0, z_split, z1, slope, apron=False):
    """Two (d, z) profiles: the lower, body-coloured part and the black strip
    over it. d <= 0 is in from the face. The top `slope` metres lean back in
    to the body before the face goes straight down; the foot tucks under.
    With `apron` the strip's top runs back and up to the lamps, closing the
    gap under them."""
    lower = [(-0.07, z0 + 0.02), (-0.05, z0), (-0.02, z0 + 0.012), (-0.004, z0 + 0.05), (0.0, z_split - 0.02),
             (-0.002, z_split), (-0.06, z_split)]
    lean = 1.1 * slope
    upper = [(-0.06, z_split - 0.004), (0.006, z_split - 0.004), (0.01, z_split + 0.012), (0.01, z1 - slope),
             (0.006, z1 - slope + 0.008), (0.01 - lean + 0.008, z1 - 0.006), (0.01 - lean, z1), (-0.06 - lean, z1)]
    if apron:
        upper[-1:] = [(-APRON_DEPTH, z1 + APRON_RISE), (-APRON_DEPTH - 0.01, z1 - 0.01)]
    return lower, upper


def _arch_trim(o):
    """Cut a bumper's ends round the wheel arches' flares."""
    for y, r in ((AXLE_F, FLARE_F), (AXLE_R, FLARE_R)):
        for sx in (-1, 1):
            _cut(o, _cutter("arch", arch_poly(y, r + 0.004), PV._side_place(sx), 0.4, 1.2, "Under"))
    return o


def _bumpers(M):
    p = []
    # front: 12 cm ahead of the lamps at the centre, round the body's
    # corners just clear of them and back along the sides to the arch
    # (both run on into the wheel arches and are cut round the flares)
    fplan = [(0.0, YF, 1), (0.3, YF - 0.005, 1), (0.48, YF - 0.02, 1), (0.6, YF - 0.045, 1), (0.68, YF - 0.075, 1),
             (0.735, YF - 0.11, 1), (0.775, YF - 0.155, 1), (0.805, YF - 0.21, 1), (0.822, YF - 0.28, 1),
             (0.828, 1.70, 1), (0.83, 1.56, 1)]
    # the front's black strip is a thin one, under the lamps
    lo, up = _bumper_profile(0.245, 0.455, BUMPER_F_TOP, 0.03, apron=True)
    p.append(_arch_trim(_sweep("bumper_f", fplan, lo, (0.0, YF - 1.0), M["paint"])))
    p.append(_arch_trim(_sweep("bumper_f_band", fplan, up, (0.0, YF - 1.0), M["band"])))
    # the tail is only 11 cm behind the body, so the rear corners turn
    # tighter to stay outside it, and follow its taper forward
    rplan = [(0.0, YR, 1), (0.3, YR + 0.006, 1), (0.5, YR + 0.018, 1), (0.62, YR + 0.036, 1), (0.69, YR + 0.06, 1),
             (0.735, YR + 0.095, 1), (0.762, YR + 0.14, 1), (0.78, YR + 0.2, 1), (0.795, YR + 0.3, 1),
             (0.808, -1.72, 1), (0.818, -1.6, 1), (0.822, -1.4, 1)]
    lo, up = _bumper_profile(0.25, 0.53, 0.628, 0.04)
    p.append(_arch_trim(_sweep("bumper_r", rplan, lo, (0.0, YR + 1.0), M["paint"])))
    p.append(_arch_trim(_sweep("bumper_r_band", rplan, up, (0.0, YR + 1.0), M["band"])))
    # a groove along the front bumper's lower half, following its face
    groove = [(-0.001, 0.4), (0.002, 0.4), (0.002, 0.407), (-0.001, 0.407)]
    p.append(_sweep("groove", [pt for pt in fplan if pt[0] <= 0.6], groove, (0.0, YF - 1.0), M["under"]))
    return p


# ------------------------------------------------------------------ the tail

def _tail(M, ref):
    out, p = [], []
    yb = TAIL_Y
    z0, z1, zt = TAIL_Z0, TAIL_Z1, TAIL_TOP
    # the plate recess between the lamps: black, down to the bumper, with
    # the plate in it
    p.append(_prism("plate_recess", _box_pts(-0.205, 0.205, PLATE_Z0 - 0.01, z1), "y", yb - 0.004, yb + 0.006,
                    M["black"]))
    for name, sx in (("TailL", -1), ("TailR", 1)):
        x0, x1 = 0.215, TAIL_X1
        wrap, wrap_ln = _corner_frame(sx, (x1 - 0.004, Y0 + 0.004), (float(_W(-1.905)) - 0.006, -1.905))
        # its end on the quarter slants: full height at the corner, its top
        # cut back along the side
        end = [(0.0, z0), (wrap_ln, z0), (wrap_ln * 0.5, zt), (0.0, zt)]
        end_in = [(0.004, z0 + 0.004), (wrap_ln - 0.012, z0 + 0.004), (wrap_ln * 0.5 - 0.006, zt - 0.004),
                  (0.004, zt - 0.004)]
        # one red lens from the plate recess out to the corner and round it
        # onto the quarter (the game lights it for the brakes); over it, a
        # white reversing lamp by the plate and the amber indicator at the
        # outer end and round the corner, all under the amber top strip
        lens = [_prism("tail_red", _box_pts(*sorted((sx * x0, sx * x1)), z0, z1), "y", yb - 0.008, yb, M["tail"]),
                _facing(K.project_poly("tail_wrap", ref, end, wrap, M["tail"], offset=0.004, cuts=4), (sx, -1, 0))]
        out.append((name, lens, None, None))
        p.append(_prism("tail_reverse", _box_pts(*sorted((sx * 0.215, sx * 0.29)), z0, z1),
                        "y", yb - 0.011, yb - 0.007, M["reverse"]))
        p.append(_prism("tail_amber", _box_pts(*sorted((sx * (x1 - 0.06), sx * (x1 - 0.004))), z0, z1),
                        "y", yb - 0.011, yb - 0.007, M["amber"]))
        p.append(_facing(K.project_poly("tail_wrap_amber", ref, end_in, wrap, M["amber"], offset=0.0065, cuts=4),
                         (sx, -1, 0)))
        # the lens's ribs: one across the middle, and between the colours
        zm = 0.5 * (z0 + z1)
        p.append(bx((min(sx * 0.29, sx * (x1 - 0.06)), yb - 0.013, zm - 0.002), (max(sx * 0.29, sx * (x1 - 0.06)),
                    yb - 0.009, zm + 0.002), M["black"]))
        for xr in (0.29, x1 - 0.06):
            p.append(bx((sx * xr - 0.0025, yb - 0.013, z0 + 0.002), (sx * xr + 0.0025, yb - 0.009, z1 - 0.002),
                        M["black"]))
    # an amber strip right across the top of the lamps and the recess
    p.append(_prism("tail_strip", _box_pts(-TAIL_X1, TAIL_X1, z1, zt), "y", yb - 0.008, yb, M["reflector"]))
    return out, p


# ------------------------------------------------------------------ the band

def band_line():
    """Side view (y, z) of the black band's centre from where it starts to
    rise into the lip spoiler to the headlamp's corner."""
    return [(y, float(BAND(y))) for y in [BAND_REAR + 0.04 * k for k in range(int((1.95 - BAND_REAR) / 0.04) + 1)]]


BAND_REAR = -1.48                  # the side band hands over to the rear sweep here
LIP_Z = 0.97                       # the lip's root along the tail, on the boot lid's roll
# the lip spoiler's section across the tail (d out from its root, z): the
# band, carried round the back at its own height and kicked out and up
# into a thin blade
LIP = [(-0.06, 0.958), (0.0, 0.956), (0.03, 0.966), (0.052, 0.988), (0.046, 1.0), (-0.02, 1.008), (-0.07, 1.004)]


def _band_section(y):
    """The band's section on the side at y, matching LIP point for point."""
    zc, w = band_at(y)
    h = w / 2
    return [(-0.03, zc - h), (0.0, zc - h), (0.008, zc - h + 0.004), (0.01, zc), (0.008, zc + h - 0.004),
            (0.0, zc + h), (-0.03, zc + h)]


def _lip_section(y, back):
    """The band stays on its straight line along the quarter; round the
    tail's corners it turns into the blade, which faces back (`back` 0 on
    the sides, 1 across the tail), so the blade's ends fair into the band."""
    u = min(max((back - 0.3) / 0.6, 0.0), 1.0)
    u = u * u * (3 - 2 * u)
    return [(bd + (ld - bd) * u, bz + (lz - bz) * u) for (bd, bz), (ld, lz) in zip(_band_section(y), LIP)]


def _band_rear(M, ref):
    """The band's back end and the lip spoiler as one piece: along each rear
    quarter the band rises, thickens and stands out until, round the tail's
    corners, it is the lip along the boot lid's edge."""
    def hit(o, d):
        ok, loc, _, _ = K.surface_ray(ref, o, d)
        return (loc.x, loc.y) if ok else None

    def z_of(y):
        return band_at(y)[0]

    half = []
    for x in (0.0, 0.15, 0.3, 0.4, 0.48):
        half.append(hit((x, -5.0, LIP_Z), (0, 1, 0)))
    cx, cy = 0.48, -1.82
    for a in range(-80, -5, 8):
        dx, dy = math.cos(math.radians(a)), math.sin(math.radians(a))
        q = hit((cx + 3 * dx, cy + 3 * dy, LIP_Z), (-dx, -dy, 0))
        if q:
            q = hit((cx + 3 * dx, cy + 3 * dy, z_of(q[1])), (-dx, -dy, 0)) or q
            half.append(q)
    y = cy + 0.02
    while y <= BAND_REAR + 0.08 + 1e-6:
        half.append(hit((5.0, y, z_of(y)), (-1, 0, 0)))
        y += 0.025
    half = [q for q in half if q]
    path = [(-x, y) for x, y in reversed(half[1:])] + half
    n, m = len(path), len(LIP)
    v, f = [], []
    for i, (x, y) in enumerate(path):
        xa, ya = path[max(i - 1, 0)]
        xb, yb = path[min(i + 1, n - 1)]
        ln = math.hypot(xb - xa, yb - ya)
        nx, ny = (yb - ya) / ln, -(xb - xa) / ln
        if nx * x + ny * (y + 1.0) < 0:
            nx, ny = -nx, -ny
        for d, z in _lip_section(y, -ny):
            v.append((x + nx * d, y + ny * d, z))
    for i in range(n - 1):
        for j in range(m):
            jj = (j + 1) % m
            f.append((i * m + j, (i + 1) * m + j, (i + 1) * m + jj, i * m + jj))
    f.append(tuple(range(m)))
    f.append(tuple((n - 1) * m + j for j in range(m)))
    return _smoothed(_fix_normals(C.mesh_obj("lip", v, f, M["band"])), 40)


def _band(M, ref):
    p = []
    for sx in (-1, 1):
        fr = K.side_frame(sx)
        p.append(_facing(_ribbon("band", ref, _dense(band_line(), 0.012), fr,
                                 lambda y: float(BAND_W(y)), M["band"], 0.009), (sx, 0, 0)))
    p.append(_band_rear(M, ref))
    return p


# ------------------------------------------------------------------ trim

def _trim(M, ref, body):
    p = []
    top = K.top_frame()
    for sx in (-1, 1):
        fr = K.side_frame(sx)
        # doors: the front door from the A pillar's foot to the B pillar,
        # the rear door from there to its back edge, down round the arch
        arch = [(AXLE_R + dy, TYRE_R + dz) for dy, dz in (arch_pt(a, FLARE_R + 0.012) for a in range(90, 9, -10))
                if AXLE_R + dy >= -1.10]
        lines = [
            [(0.735, ZB(0.735) - 0.004), (0.74, SILL_Z1 + 0.012), (-0.236, SILL_Z1 + 0.012), (-0.236, ZB(-0.236))],
            [(-0.252, ZB(-0.252)), (-0.252, SILL_Z1 + 0.012), (arch[-1][0], SILL_Z1 + 0.012)] + list(reversed(arch))
            + [(-1.10, 0.97)],
        ]
        for ln in lines:
            p.append(_line("shut", ref, ln, fr, 0.006, M["shut"], 0.005))
        # black pull handles at the back of each door, just under the band
        for y in (-0.08, -1.0):
            zc = float(BAND(y)) - 0.05
            p.append(K.project_poly("handle", ref, _round_poly(_box_pts(y - 0.06, y + 0.06, zc - 0.02, zc + 0.02), 0.008, 2),
                                    fr, M["black"], offset=0.008, cuts=1))
        # between the glasses the doors' body-colour frames meet over a thin
        # black gap; the rear door's glass is split by a black bar from its
        # fixed quarter light
        yb_ = 0.5 * (B_FRONT + B_REAR)
        p.append(K.project_poly("bpillar", ref, _box_pts(yb_ - 0.007, yb_ + 0.007, ZB(yb_) + 0.01,
                                                         dlo_top(yb_) + 0.012), fr, M["black"], offset=0.006, cuts=2))
        yd = REAR_DIVIDER
        p.append(K.project_poly("divider", ref, _box_pts(yd - 0.008, yd + 0.008, ZB(yd) + 0.004, dlo_top(yd)), fr,
                                M["black"], offset=0.004, cuts=2))
        # amber repeater on the wing behind the front arch
        p.append(K.project_poly("repeater", ref, _round_poly(_box_pts(0.97, 1.03, 0.595, 0.613), 0.008, 2), fr,
                                M["amber"], offset=0.006, cuts=1))
        # door mirror: a body-coloured pod on a stalk at the glass's front corner
        # (a small, low, rounded pod)
        my, mz = 0.6, 0.93
        xg = MIRROR_X
        x0, x1 = sorted((sx * (xg + 0.02), sx * (xg + 0.125)))
        xo, xi = (x1, x0) if sx > 0 else (x0, x1)
        pod = _smoothed(_prism("mirror", _round_poly([(xi, mz - 0.03), (xo, mz - 0.034), (xo, mz + 0.03),
                                                       (xi, mz + 0.036)], 0.028, 4), "y", my - 0.03, my + 0.045,
                               M["paint"]), 50)
        p.append(pod)
        p.append(bx((min(sx * (xg - 0.01), sx * (xg + 0.03)), my - 0.02, mz - 0.034),
                    (max(sx * (xg - 0.01), sx * (xg + 0.03)), my + 0.06, mz + 0.01), M["black"]))
        p.append(bx((x0 + 0.008, my - 0.034, mz - 0.026), (x1 - 0.008, my - 0.03, mz + 0.026), M["glass"]))
    # fuel flap on the right rear quarter
    p.append(K.project_poly("fuel_flap", ref, [(-1.54 + 0.045 * math.cos(a * math.pi / 8), 0.875 +
                                                0.045 * math.sin(a * math.pi / 8)) for a in range(16)],
                            K.side_frame(1), M["shut"], offset=0.004, cuts=1, border=0.006,
                            border_mat=M["shut"]))
    # bonnet: shut lines along the wing tops and the windscreen's foot
    for sx in (-1, 1):
        p.append(_line("shut", ref, [(sx * (HW - 0.04), 0.83), (sx * (HW - 0.045), 1.4), (sx * (HW - 0.1), Y1 - 0.025)],
                       top, 0.006, M["shut"], 0.004))
        # boot lid edges
        p.append(_line("shut", ref, [(sx * (HW - 0.05), -1.47), (sx * (HW - 0.1), Y0 + 0.02)], top, 0.006,
                       M["shut"], 0.004))
    p.append(_line("shut", ref, [(-(HW - 0.06), -1.47), (HW - 0.06, -1.47)], top, 0.006, M["shut"], 0.004))
    # wipers
    for x0, x1 in ((-0.62, -0.05), (0.08, 0.62)):
        p.append(_line("wiper", ref, [(x0, WS_B - 0.05), (x1, WS_B - 0.035)], top, 0.012, M["black"], 0.012))
    return p


# the side glass's outer face where the door mirror stands on it
MIRROR_X = 0.712


def _line(name, target, pts, frame, width, mat, offset):
    return K.project_line(name, target, _dense(pts), frame, width, mat, offset=offset)


MOUNT_EXHAUST = (-0.40, YR + 0.03, 0.265)


def _exhaust(M):
    """The stock tailpipe out under the back bumper on the left: a plain
    steel pipe, sooty inside. Its end is Mount_Exhaust."""
    x, y, z = MOUNT_EXHAUST
    steel = _m("A75_PipeSteel", "#4a4745", 0.6, 0.5)
    return [cyl(0.024, 0.2, (x, y + 0.1, z), steel, segs=12, axis="Y"),
            cyl(0.02, 0.004, (x, y - 0.001, z), _m("A75_PipeSoot", "#0b0b0b", 1.0), segs=12, axis="Y")]


def _plates(M):
    """Front plate on the bumper's middle, over the band; rear plate in its
    recess."""
    return [bx((-0.186, YF + 0.012, 0.35), (0.186, YF + 0.02, 0.48), M["plate"]),
            bx((-0.186, TAIL_Y - 0.006, PLATE_Z0), (0.186, TAIL_Y + 0.001, PLATE_Z0 + 0.13), M["plate"])]


def _exterior(M):
    body, ref = _shell(M)
    p = [body] + _glass(M, ref, body) + _nose(M, ref) + _bumpers(M) + _band(M, ref) + _trim(M, ref, body)
    p += _flares(M, ref) + _sills(M, ref)
    p += _plates(M) + _exhaust(M)
    heads, hp = _head_lamps(M, ref)
    tails, tp = _tail(M, ref)
    p += hp + tp
    return p, ref, heads + tails


def alfa_shell_preview():
    M = _mats()
    p, ref, lamps = _exterior(M)
    bpy.data.objects.remove(ref, do_unlink=True)
    return [("Alfa75", p, (0, 0, 0), None)] + lamps + _preview_wheels(AP.wheel_stock), {}


def alfa_blockout_preview():
    """The bare body for shape checks: shell, bumpers, band and spoiler forms
    and glass, all one grey, on plain wheels. No lamps, grille or trim."""
    M = _mats()
    body, ref = _shell(M)
    band, drop = [], []
    for o in _band(M, ref):
        (band if o.name.startswith("lip") else drop).append(o)
    for o in drop:
        bpy.data.objects.remove(o, do_unlink=True)
    p = [body] + _glass(M, ref, body, frames=False) + _bumpers(M) + band + _flares(M, ref) + _sills(M, ref)
    bpy.data.objects.remove(ref, do_unlink=True)
    grey = _m("A75_Blockout", "#9a9a98", 0.35, 0.3)
    keep = {M["glass"].name, M["under"].name}
    for o in p:
        for slot in o.material_slots:
            if slot.material and slot.material.name not in keep:
                slot.material = grey
    return [("Alfa75", p, (0, 0, 0), None)] + _preview_wheels(_plain_wheel), {}


def _plain_wheel(sx):
    tyre = C.cylinder("tyre", TYRE_R, 0.195, segs=40, axis="X", material=_m("A75_Tyre", "#18181a", 0.92))
    disc = C.cylinder("disc", 0.175, 0.012, segs=32, axis="X", loc=(sx * 0.092, 0, 0),
                      material=_m("A75_Disc", "#6d6e70", 0.5, 0.4))
    return C.join([tyre, disc], "wheel")


def _preview_wheels(builder):
    out = []
    for y, tag in ((AXLE_F, "F"), (AXLE_R, "R")):
        for sx in (-1, 1):
            loc = (sx * TRACK_X, y, TYRE_R)
            out.append(("Wheel_" + tag + ("R" if sx > 0 else "L"), [_at(builder(sx), loc)], loc, None))
    return out


def alfa_simmons_preview():
    M = _mats()
    p, ref, lamps = _exterior(M)
    bpy.data.objects.remove(ref, do_unlink=True)
    return [("Alfa75", p, (0, 0, 0), None)] + lamps + _preview_wheels(AP.wheel_simmons), {}


def alfa_wheels_preview():
    """The stock wheel and the Simmons side by side, outer faces to +X."""
    a, b = (0, 0.35, TYRE_R), (0, -0.35, TYRE_R)
    return [("Stock", [_at(AP.wheel_stock(1), a)], a, None),
            ("Simmons", [_at(AP.wheel_simmons(1), b)], b, None)], {}


def _at(o, loc):
    o.location = loc
    C.apply_transform(o)
    return o


# ------------------------------------------------------------------ to drive
#
# The car on the cars/ contract (art/models/README.md), for the car yard:
# origin on the ground midway between the axles, the wheels out as their
# own glbs (wheel_a75_l/_r, lib/alfa75_parts.py) with Hub_* empties at
# their centres, the cockpit and opening front doors from
# lib/alfa75_cabin.py, seats, exits and mounts, and the material names the
# game drives (LampHead, LampTail, Glass, Plate).

CAR_PLATE = "6BA-275"   # made up: a late-80s WA plate
AXLE_MID = (AXLE_F + AXLE_R) / 2
WHEEL_STYLE = "a75"


def _car_mats():
    from . import textures as TX
    M = _mats()
    M.update({
        "glass": C.mat("Glass", "#5f7480", rough=0.03, metal=0.35, alpha=0.5),
        "head": _m("LampHead", "#a2acb0", 0.04, 0.5),
        "tail": _m("LampTail", "#a4141a", 0.25),
        "plate": C.mat("Plate", image=TX.plate(CAR_PLATE), rough=0.6),
    })
    return M


def alfa_car():
    """The driveable 75 in build_city's form (items, empties), nose +Y with
    the origin at the footprint centre; `alfa_car_finish` turns the
    cockpit's parts to their axes, adds the contract empties and moves the
    origin between the axles."""
    from . import alfa75_cabin as CAB
    M = _car_mats()
    body, ref = _shell(M)
    p = [body] + _glass(M, ref, body) + _nose(M, ref) + _bumpers(M) + _band(M, ref) + _trim(M, ref, body)
    p += _flares(M, ref) + _sills(M, ref)
    p += _plates(M) + _exhaust(M)
    heads, hp = _head_lamps(M, ref)
    tails, tp = _tail(M, ref)
    p += hp + tp
    cab, items, trims, _tip = CAB.cockpit(M, body)
    bpy.data.objects.remove(ref, do_unlink=True)
    p, doors, door_empties = CAB.split_doors(p + cab, trims)
    for o in p:
        if o.type == "MESH" and o.data.materials and o.data.materials[0] is M["plate"]:
            C.apply_transform(o)
            # read from in front of the car its right is -X, from behind +X
            K.planar_uv(o, 0, 2, flip_u=o.data.vertices[0].co.y > 0)
    return [("Alfa75", p, (0, 0, 0), None)] + doors + items + heads + tails, door_empties


def alfa_car_finish():
    """After build_city's build of `alfa_car`: the cockpit's axes, the
    contract empties, then everything moved so the origin sits midway
    between the axles. Returns every object."""
    from mathutils import Matrix
    from . import alfa75_cabin as CAB
    CAB.orient()

    def em(name, loc, rx=0.0, rz=0.0):
        e = C.empty(name, loc, size=0.08)
        e.rotation_euler = (math.radians(rx), 0, math.radians(rz))
        return e
    em("WheelStyle_" + WHEEL_STYLE, (0, 0, 0))
    for nm, sx, y in (("FL", -1, AXLE_F), ("FR", 1, AXLE_F), ("RL", -1, AXLE_R), ("RR", 1, AXLE_R)):
        em("Hub_" + nm, (sx * TRACK_X, y, TYRE_R))
    em("Cam_Cockpit", tuple(CAB.EYE))
    for nm, sx in (("L", -1), ("R", 1)):
        em("Seat_" + nm, (sx * CAB.HIP[0], CAB.HIP[1], CAB.HIP[2]))
        # beside the front door, facing away from the car (Godot -Z out)
        em("Exit_" + nm, (sx * (HW + 0.5), 0.2, 0.0), rz=90 * -sx)
        em("Mount_MudFlap_" + nm, (sx * TRACK_X, AXLE_R - 0.4, float(_ZBOT(AXLE_R - 0.4))))
    # a fitted wheel: Godot -Z down the column toward the dash, +Y to twelve
    em("Mount_SteeringWheel", tuple(CAB.HUB), rx=-CAB.COL_TILT)
    em("Mount_GearKnob", tuple(bpy.data.objects["GearKnob"].location), rx=14)
    em("Mount_Exhaust", MOUNT_EXHAUST)
    em("Mount_Roof", (0.0, -0.4, ZR))
    em("Mount_Spotlights", (0.0, YF - 0.02, 0.56))
    em("Mount_BumperF", (0.0, YF + 0.01, 0.46))
    em("Mount_BumperR", (0.0, YR - 0.01, 0.50))
    em("Mount_TowBar", (0.0, YR, 0.30))
    em("Mount_Mirror", (0.0, 0.225, 1.2))
    em("Mount_Dash", (-0.3, 0.6, 0.91))
    em("Mount_Shelf", (-0.35, -1.7, 0.97))
    em("Mount_Gear", (0.0, -0.06, 0.52))
    em("Mount_Glovebox", (-0.46, 0.46, 0.735))
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.parent is None:
            o.matrix_world = Matrix.Translation((0, -AXLE_MID, 0)) @ o.matrix_world
    bpy.context.view_layer.update()
    return list(bpy.data.objects)
