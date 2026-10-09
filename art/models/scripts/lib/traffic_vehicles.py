"""Everyday traffic for traffic/ (traffic_models.gd loads these when
present, in place of its code-built boxes): five cars, a taxi, a Perth-style
low-floor bus, police, ambulance and fire, and a suburban railcar in two
halves (the driving-cab car and a middle car).

Same conventions as lib/city_vehicles.py: authored with the front toward +Y
(Godot -Z), the left/kerb side on -X, origin on the ground at the centre of
the footprint, metres, no wheel nodes, no brand logos. The traffic code
recolours "Paint" (the body) and "Livery" (a stripe, band or trim) per
vehicle; glass is on its own "Glass" material. Lamps are their own meshes:
HeadL/HeadR, TailL/TailR, and IndL/IndR (the amber indicators, front and
back on one mesh per side). The emergency vehicles add LightBar with Red
and Blue meshes under it, and a Siren empty; the bus a "Dest" destination
panel; the railcar DoorsL/DoorsR.

Light on purpose: up to about 60 are on screen at once (about 1.5k
triangles a car, 3k for the bus, the fire truck and each railcar).

Each builder returns (objs, empties) in lib/city_vehicles.py's form.
"""
import math

from . import common as C
from . import furniture as F
from . import city_vehicles as CV

bx, cyl = F.bx, F.cyl
_m = CV._m


def _mats():
    M = CV._common()
    M.update({
        "paint": _m("Paint", "#9aa3a8", 0.4, 0.3),
        "livery": _m("Livery", "#2f3436", 0.5),
        "glass": _m("Glass", "#2b3b46", 0.08, 0.4),
        "ind": _m("CV_Indicator", "#e8961e", 0.3),
        "trim": _m("CV_Trim", "#262829", 0.7),
    })
    return M


def _prism_yz(pts, x0, x1, mat):
    """Extrude a side profile [(y, z), ...] (anticlockwise seen from +X)
    across x0..x1."""
    n = len(pts)
    v = [(x0, y, z) for y, z in pts] + [(x1, y, z) for y, z in pts]
    f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    f += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return C.mesh_obj("prism", v, f, mat)


def _cabin(wb, wt, cb, ct, zb, zt, M, pillars=((0.0, 0.07), (0.93, 1.0)), roof=None):
    """The greenhouse: a frustum from the belt line (width wb, y cb[0]..cb[1])
    to the roof (width wt, y ct[0]..ct[1]); glass all round, a painted roof,
    and painted pillars as strips on the side glass (u = 0 rear .. 1 front)."""
    v = [(-wb / 2, cb[0], zb), (wb / 2, cb[0], zb), (wb / 2, cb[1], zb), (-wb / 2, cb[1], zb),
         (-wt / 2, ct[0], zt), (wt / 2, ct[0], zt), (wt / 2, ct[1], zt), (-wt / 2, ct[1], zt)]
    f = [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    out = [C.mesh_obj("cabin", v, f, mats=[roof or M["paint"], M["glass"]], face_mats=[0, 1, 1, 1, 1])]
    for sx in (-1, 1):
        for u0, u1 in pillars:
            def pt(u, top):
                y = (ct[0] + (ct[1] - ct[0]) * u) if top else (cb[0] + (cb[1] - cb[0]) * u)
                x = sx * ((wt if top else wb) / 2 + 0.006)
                return (x, y, zt if top else zb)
            q = [pt(u0, False), pt(u1, False), pt(u1, True), pt(u0, True)]
            if sx < 0:
                q = q[::-1]
            out.append(C.mesh_obj("pillar", q, [(0, 1, 2, 3)], roof or M["paint"]))
    return out


def _lamps(W, yf, yr, zh, zt, M, inset=0.22, hw=(0.26, 0.12), tw=(0.22, 0.14), ind=True):
    """HeadL/R on the front face (y = yf), TailL/R on the back (y = yr),
    IndL/R amber at the corners front and back."""
    out = []
    for name, sx in (("HeadL", -1), ("HeadR", 1)):
        x = sx * (W / 2 - inset)
        out.append((name, [bx((x - hw[0] / 2, yf - 0.02, zh - hw[1] / 2), (x + hw[0] / 2, yf + 0.015, zh + hw[1] / 2),
                              M["head"])], None, None))
    for name, sx in (("TailL", -1), ("TailR", 1)):
        x = sx * (W / 2 - inset + 0.04)
        out.append((name, [bx((x - tw[0] / 2, yr - 0.015, zt - tw[1] / 2), (x + tw[0] / 2, yr + 0.02, zt + tw[1] / 2),
                              M["tail"])], None, None))
    if ind:
        for name, sx in (("IndL", -1), ("IndR", 1)):
            xo = sx * (W / 2 - 0.07)
            out.append((name, [bx((xo - 0.05, yf - 0.02, zh - 0.04), (xo + 0.05, yf + 0.016, zh + 0.04), M["ind"]),
                               bx((xo - 0.05, yr - 0.016, zt - 0.11), (xo + 0.05, yr + 0.02, zt - 0.05), M["ind"])],
                        None, None))
    return out


def _wheels(W, ys, r, M, w=0.2):
    return CV._wheels(W - w - 0.02, ys, r, w, M)


def _plate(y, z, M, facing=1):
    return bx((-0.26, y - (0.0 if facing > 0 else 0.012), z - 0.06), (0.26, y + (0.012 if facing > 0 else 0.0), z + 0.06),
              M["plate"])


def _mirrors(W, y, z, M):
    return [bx((sx * (W / 2 + 0.02) - 0.07, y - 0.05, z - 0.06), (sx * (W / 2 + 0.02) + 0.07, y + 0.05, z + 0.06),
               M["paint"]) for sx in (-1, 1)]


def _car(L, W, H, profile, cab, wheel_ys, r, zh, zt, M, extra=(), cabin_kw=None):
    """A car body: the lower body from a side profile across the full width
    (less a little), the greenhouse, sills, bumpers, wheels and lamps.
    cab = (wb, wt, (cb0, cb1), (ct0, ct1), zb)."""
    yf, yr = L / 2, -L / 2
    p = [_prism_yz(profile, -W / 2 + 0.02, W / 2 - 0.02, M["paint"])]
    wb, wt, cb, ct, zb = cab
    p += _cabin(wb, wt, cb, ct, zb, H, M, **(cabin_kw or {}))
    # sills, bumpers and the side rubbing strip (Livery)
    p.append(bx((-W / 2 + 0.01, yr + 0.5, 0.26), (W / 2 - 0.01, yf - 0.6, 0.36), M["trim"]))
    p.append(bx((-W / 2 + 0.06, yf - 0.12, 0.28), (W / 2 - 0.06, yf + 0.03, 0.5), M["trim"]))
    p.append(bx((-W / 2 + 0.06, yr - 0.03, 0.3), (W / 2 - 0.06, yr + 0.12, 0.52), M["trim"]))
    p.append(bx((-W / 2 + 0.005, yr + 0.4, zb - 0.32), (W / 2 - 0.005, yf - 0.55, zb - 0.27), M["livery"]))
    p.append(_plate(yf + 0.03, 0.4, M))
    p.append(_plate(yr - 0.03, 0.62, M, facing=-1))
    p += _mirrors(W, cab[2][1] - 0.15, zb + 0.08, M)
    p += _wheels(W, wheel_ys, r, M)
    p += list(extra)
    return p, _lamps(W, yf, yr, zh, zt, M)


# ------------------------------------------------------------------ cars

def hatch():
    """A small five-door hatchback, 4.0 x 1.75 x 1.5."""
    M = _mats()
    L, W, H = 4.0, 1.75, 1.5
    yf, yr = L / 2, -L / 2
    prof = [(yr, 0.3), (yf, 0.3), (yf, 0.62), (yf - 0.18, 0.8), (0.75, 0.92), (yr + 0.08, 0.95), (yr, 0.86)]
    cab = (W - 0.1, W - 0.34, (yr + 0.12, 0.75), (yr + 0.32, -0.05), 0.92)
    p, lamps = _car(L, W, H, prof, cab, (1.27, -1.27), 0.31, 0.7, 0.85, M,
                    cabin_kw={"pillars": ((0.0, 0.1), (0.47, 0.52), (0.95, 1.0))})
    return [("Hatch", p, (0, 0, 0), None)] + lamps, {}


def sedan():
    """A mid-size four-door sedan with a boot, 4.7 x 1.82 x 1.45."""
    M = _mats()
    L, W, H = 4.7, 1.82, 1.45
    yf, yr = L / 2, -L / 2
    prof = [(yr, 0.32), (yf, 0.32), (yf, 0.62), (yf - 0.2, 0.78), (0.95, 0.9), (-1.35, 0.92), (yr + 0.05, 0.9),
            (yr, 0.8)]
    cab = (W - 0.1, W - 0.36, (-1.35, 0.95), (-0.85, 0.05), 0.9)
    p, lamps = _car(L, W, H, prof, cab, (1.42, -1.42), 0.32, 0.68, 0.8, M,
                    cabin_kw={"pillars": ((0.0, 0.12), (0.48, 0.53), (0.95, 1.0))})
    return [("Sedan", p, (0, 0, 0), None)] + lamps, {}


def suv():
    """A family SUV, boxy and tall, 4.7 x 1.9 x 1.75, with roof rails."""
    M = _mats()
    L, W, H = 4.7, 1.9, 1.75
    yf, yr = L / 2, -L / 2
    prof = [(yr, 0.42), (yf, 0.42), (yf, 0.78), (yf - 0.22, 0.98), (0.95, 1.08), (yr + 0.06, 1.12), (yr, 1.0)]
    cab = (W - 0.1, W - 0.28, (yr + 0.1, 0.95), (yr + 0.2, 0.2), 1.08)
    rails = [bx((sx * (W / 2 - 0.2) - 0.03, yr + 0.5, H), (sx * (W / 2 - 0.2) + 0.03, 0.0, H + 0.06), M["trim"])
             for sx in (-1, 1)]
    cladding = [bx((-W / 2 - 0.005, yr + 0.15, 0.36), (W / 2 + 0.005, yf - 0.15, 0.5), M["trim"])]
    p, lamps = _car(L, W, H, prof, cab, (1.42, -1.42), 0.37, 0.88, 0.98, M, extra=rails + cladding,
                    cabin_kw={"pillars": ((0.0, 0.1), (0.38, 0.43), (0.66, 0.7), (0.95, 1.0))})
    return [("Suv", p, (0, 0, 0), None)] + lamps, {}


def ute():
    """A dual-cab ute with a tub, 5.3 x 1.9 x 1.82: the Aussie tradie's
    staple, a nudge bar and a ladder rack."""
    M = _mats()
    L, W, H = 5.3, 1.9, 1.82
    yf, yr = L / 2, -L / 2
    cab_back = -0.75
    prof = [(cab_back, 0.45), (yf, 0.45), (yf, 0.82), (yf - 0.25, 1.02), (1.15, 1.1), (cab_back, 1.12)]
    cab = (W - 0.1, W - 0.3, (cab_back, 1.15), (cab_back + 0.05, 0.5), 1.1)
    tub = [bx((-W / 2 + 0.08, yr + 0.05, 0.8), (W / 2 - 0.08, cab_back - 0.05, 0.86), M["paint"])]   # floor
    for sx in (-1, 1):
        tub.append(bx((sx * (W / 2 - 0.03) - 0.05, yr, 0.45), (sx * (W / 2 - 0.03) + 0.05, cab_back - 0.05, 1.12),
                      M["paint"]))
        tub.append(bx((sx * (W / 2 - 0.3) - 0.2, -1.95, 0.8), (sx * (W / 2 - 0.3) + 0.2, -1.15, 1.0), M["paint"]))  # arch
    tub.append(bx((-W / 2 + 0.03, cab_back - 0.1, 0.45), (W / 2 - 0.03, cab_back - 0.05, 1.12), M["paint"]))
    tub.append(bx((-W / 2 + 0.03, yr, 0.45), (W / 2 - 0.03, yr + 0.06, 1.1), M["paint"]))        # tailgate
    tub.append(bx((-W / 2 + 0.08, yr - 0.005, 0.95), (W / 2 - 0.08, yr, 1.0), M["livery"]))
    # chassis under the tub, the nudge bar, the ladder rack over the tub
    tub.append(bx((-0.55, yr + 0.3, 0.32), (0.55, yf - 0.5, 0.45), M["black"]))
    for sx in (-1, 1):
        tub.append(bx((sx * 0.45 - 0.04, yf, 0.45), (sx * 0.45 + 0.04, yf + 0.12, 0.95), M["black"]))
        tub.append(bx((sx * (W / 2 - 0.08) - 0.03, cab_back - 0.1, 1.1), (sx * (W / 2 - 0.08) + 0.03, cab_back - 0.04,
                                                                          H + 0.1), M["black"]))
        tub.append(bx((sx * (W / 2 - 0.08) - 0.03, yr + 0.1, 1.1), (sx * (W / 2 - 0.08) + 0.03, yr + 0.16, H + 0.1),
                      M["black"]))
        tub.append(bx((sx * (W / 2 - 0.08) - 0.025, yr + 0.1, H + 0.06), (sx * (W / 2 - 0.08) + 0.025, cab_back - 0.04,
                                                                          H + 0.1), M["black"]))
    tub.append(bx((-0.45, yf + 0.08, 0.88), (0.45, yf + 0.12, 0.95), M["black"]))
    for y in (cab_back - 0.07, yr + 0.13):
        tub.append(bx((-W / 2 + 0.08, y - 0.03, H + 0.06), (W / 2 - 0.08, y + 0.03, H + 0.1), M["black"]))
    p = [_prism_yz(prof, -W / 2 + 0.02, W / 2 - 0.02, M["paint"])]
    p += _cabin(*cab[:4], cab[4], H, M, pillars=((0.0, 0.08), (0.46, 0.51), (0.94, 1.0)))
    p.append(bx((-W / 2 + 0.01, cab_back + 0.1, 0.38), (W / 2 - 0.01, yf - 0.75, 0.46), M["trim"]))
    p.append(bx((-W / 2 + 0.06, yf - 0.1, 0.38), (W / 2 - 0.06, yf + 0.03, 0.6), M["trim"]))
    p.append(bx((-W / 2 + 0.06, yr - 0.08, 0.36), (W / 2 - 0.06, yr + 0.02, 0.48), M["steel"]))   # step bumper
    p.append(_plate(yf + 0.03, 0.5, M))
    p.append(_plate(yr - 0.08, 0.42, M, facing=-1))
    p += _mirrors(W, 0.95, 1.2, M)
    p += _wheels(W, (1.6, -1.55), 0.38, M, w=0.24)
    p += tub
    lamps = _lamps(W, yf, yr, 0.85, 0.85, M)
    return [("Ute", p, (0, 0, 0), None)] + lamps, {}


def van():
    """A high-roof delivery van, 4.9 x 1.9 x 2.0: a short bonnet, sliding
    side door, a blank box behind the cab for signwriting (Livery band)."""
    M = _mats()
    L, W, H = 4.9, 1.9, 2.0
    yf, yr = L / 2, -L / 2
    cabf = 1.45
    rake = 0.55
    prof = [(yr, 0.35), (yf, 0.35), (yf, 0.75), (yf - 0.2, 0.95), (cabf, 1.05), (cabf - rake, H), (yr + 0.04, H),
            (yr, H - 0.06)]
    p = [_prism_yz(prof, -W / 2 + 0.02, W / 2 - 0.02, M["paint"])]
    ws = [(-W / 2 + 0.1, cabf - 0.03, 1.1), (W / 2 - 0.1, cabf - 0.03, 1.1),
          (W / 2 - 0.12, cabf - rake + 0.05, H - 0.1), (-W / 2 + 0.12, cabf - rake + 0.05, H - 0.1)]
    p.append(C.mesh_obj("windscreen", [(x, y + 0.012, z + 0.008) for x, y, z in ws], [(0, 1, 2, 3)], M["glass"]))
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.02 + 0.006)
        q = [(x, 0.55, 1.12), (x, cabf - 0.08, 1.12), (x, cabf - rake + 0.05, H - 0.15), (x, 0.55, H - 0.15)]
        if sx < 0:
            q = q[::-1]
        p.append(C.mesh_obj("side_glass", q, [(0, 1, 2, 3)], M["glass"]))
    # door lines, the sliding door rail, the livery band down the box
    for x in (-W / 2 + 0.018, W / 2 - 0.018):
        for y in (0.5, -0.45):
            p.append(bx((x - 0.006, y - 0.01, 0.4), (x + 0.006, y + 0.01, H - 0.12), M["trim"]))
        p.append(bx((x - 0.008, -1.6, 1.35), (x + 0.008, 0.5, 1.38), M["trim"]))
    p.append(bx((-W / 2 + 0.015, yr + 0.1, 1.1), (W / 2 - 0.015, 0.45, 1.3), M["livery"]))
    p.append(bx((-0.012, yr - 0.012, 0.45), (0.012, yr, H - 0.12), M["trim"]))                   # barn door split
    p.append(bx((-W / 2 + 0.01, yr + 0.5, 0.26), (W / 2 - 0.01, yf - 0.6, 0.36), M["trim"]))
    p.append(bx((-W / 2 + 0.06, yf - 0.1, 0.3), (W / 2 - 0.06, yf + 0.04, 0.55), M["trim"]))
    p.append(bx((-W / 2 + 0.06, yr - 0.04, 0.3), (W / 2 - 0.06, yr + 0.1, 0.5), M["trim"]))
    p.append(_plate(yf + 0.04, 0.42, M))
    p.append(_plate(yr - 0.04, 0.6, M, facing=-1))
    p += _mirrors(W, 1.05, 1.25, M)
    p += _wheels(W, (1.55, -1.45), 0.34, M, w=0.22)
    lamps = _lamps(W, yf, yr, 0.82, 0.95, M, tw=(0.16, 0.3))
    return [("Van", p, (0, 0, 0), None)] + lamps, {}


def taxi():
    """A taxi: a long sedan, 4.8 x 1.82 x 1.62 with its roof sign. The
    body colour comes in on Paint; the roof sign is lit."""
    M = _mats()
    L, W, H = 4.8, 1.82, 1.47
    yf, yr = L / 2, -L / 2
    prof = [(yr, 0.32), (yf, 0.32), (yf, 0.62), (yf - 0.2, 0.78), (0.95, 0.9), (-1.4, 0.92), (yr + 0.05, 0.9),
            (yr, 0.8)]
    cab = (W - 0.1, W - 0.36, (-1.4, 0.95), (-0.9, 0.05), 0.9)
    sign_img = C.make_image("taxi_sign", 32, 8, _taxi_text())
    sign = C.mat("CV_TaxiSign", "#ffffff", rough=0.4, image=sign_img, emit="#fff4d0", emit_strength=0.6)
    extra = [bx((-0.32, -0.55, H), (0.32, -0.2, H + 0.04), M["black"])]
    v = [(-0.3, -0.52, H + 0.04), (0.3, -0.52, H + 0.04), (0.3, -0.23, H + 0.04), (-0.3, -0.23, H + 0.04),
         (-0.28, -0.42, H + 0.15), (0.28, -0.42, H + 0.15), (0.28, -0.33, H + 0.15), (-0.28, -0.33, H + 0.15)]
    o = C.mesh_obj("taxi_sign", v, [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], sign)
    uv = o.data.uv_layers.new(name="UVMap")
    for poly in o.data.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            x, y, z = v[vi]
            uv.data[li].uv = ((x + 0.3) / 0.6 if abs(poly.normal.y) > 0.5 else (y + 0.52) / 0.29,
                              (z - H - 0.04) / 0.11)
    extra.append(o)
    # the checker band on the doors (Livery), and the number on the back door
    p, lamps = _car(L, W, H, prof, cab, (1.45, -1.45), 0.32, 0.68, 0.8, M, extra=extra,
                    cabin_kw={"pillars": ((0.0, 0.12), (0.48, 0.53), (0.95, 1.0))})
    return [("Taxi", p, (0, 0, 0), None)] + lamps, {}


def _taxi_text():
    from . import mystery as MY
    f = MY._text(["TAXI"], 32, 8, scale=1, top=1)
    return lambda x, y: (0.08, 0.08, 0.08) if f(x, y) else (0.98, 0.95, 0.85)


# ------------------------------------------------------------------ emergency

def _lightbar(W, y, z, M, w=1.2):
    """LightBar (an empty) with Red and Blue under it, side by side."""
    red = _m("CV_LightRed", "#d0261c", 0.3)
    blue = _m("CV_LightBlue", "#2050d8", 0.3)
    base = [bx((-w / 2, y - 0.14, z), (w / 2, y + 0.14, z + 0.04), M["black"])]
    return [("LightBar", [], (0, y, z), None),
            ("LightBase", base, (0, y, z), "LightBar"),
            ("Red", [bx((-w / 2 + 0.02, y - 0.12, z + 0.04), (-0.02, y + 0.12, z + 0.14), red)],
             (-w / 4, y, z + 0.09), "LightBar"),
            ("Blue", [bx((0.02, y - 0.12, z + 0.04), (w / 2 - 0.02, y + 0.12, z + 0.14), blue)],
             (w / 4, y, z + 0.09), "LightBar")]


def police():
    """A police sedan-wagon, 4.9 x 1.85 x 1.55: the light bar, a push bar,
    a chequered band on Livery (the traffic code picks the colours)."""
    M = _mats()
    L, W, H = 4.9, 1.85, 1.42
    yf, yr = L / 2, -L / 2
    prof = [(yr, 0.32), (yf, 0.32), (yf, 0.62), (yf - 0.2, 0.78), (0.95, 0.9), (yr + 0.08, 0.95), (yr, 0.86)]
    cab = (W - 0.1, W - 0.34, (yr + 0.12, 0.95), (yr + 0.3, 0.05), 0.9)
    extra = []
    # the chequered band: alternating squares on Livery along both sides
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.012)
        for k in range(12):
            y0 = yr + 0.3 + k * 0.33
            z0 = 0.52 if k % 2 else 0.64
            extra.append(bx((x - 0.008, y0, z0), (x + 0.008, y0 + 0.33, z0 + 0.12), M["livery"]))
    for sx in (-1, 1):
        extra.append(bx((sx * 0.4 - 0.04, yf, 0.32), (sx * 0.4 + 0.04, yf + 0.14, 0.8), M["black"]))
    extra.append(bx((-0.45, yf + 0.1, 0.55), (0.45, yf + 0.14, 0.62), M["black"]))
    p, lamps = _car(L, W, H, prof, cab, (1.45, -1.45), 0.33, 0.68, 0.82, M, extra=extra,
                    cabin_kw={"pillars": ((0.0, 0.1), (0.44, 0.49), (0.95, 1.0))})
    bar = _lightbar(W, -0.35, H, M)
    return [("Police", p, (0, 0, 0), None)] + lamps + bar, {"Siren": ((0.0, yf - 0.05, 0.5), 0)}


def ambulance():
    """An ambulance, 6.2 x 2.05 x 2.7: a van cab on the front of a square
    box body with its Livery band, light bars on the cab and the box."""
    M = _mats()
    L, W, H = 6.2, 2.05, 2.7
    yf, yr = L / 2, -L / 2
    cabf, boxf = 1.75, 0.95
    prof = [(boxf, 0.4), (yf, 0.4), (yf, 0.78), (yf - 0.22, 0.98), (cabf, 1.1), (cabf - 0.1, 2.15), (boxf, 2.15)]
    p = [_prism_yz(prof, -W / 2 + 0.08, W / 2 - 0.08, M["paint"])]
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.08 + 0.006)
        q = [(x, boxf + 0.15, 1.2), (x, cabf - 0.08, 1.2), (x, cabf - 0.16, 2.05), (x, boxf + 0.15, 2.05)]
        if sx < 0:
            q = q[::-1]
        p.append(C.mesh_obj("side_glass", q, [(0, 1, 2, 3)], M["glass"]))
    ws = [(-W / 2 + 0.12, cabf + 0.012, 1.12), (W / 2 - 0.12, cabf + 0.012, 1.12),
          (W / 2 - 0.12, cabf - 0.088, 2.08), (-W / 2 + 0.12, cabf - 0.088, 2.08)]
    p.append(C.mesh_obj("windscreen", ws, [(0, 1, 2, 3)], M["glass"]))
    # the box body, its band and door outlines
    p.append(bx((-W / 2, yr, 0.45), (W / 2, boxf, H), M["paint"]))
    for k in range(2):
        z0 = 1.0 + k * 0.22
        p.append(bx((-W / 2 - 0.006, yr + 0.02, z0), (W / 2 + 0.006, boxf - 0.02, z0 + 0.14), M["livery"]))
    p.append(bx((-W / 2 + 0.08, yf - 0.62, 0.95), (W / 2 - 0.08, yf - 0.6, 1.08), M["livery"]))
    for x in (-W / 2 - 0.008, W / 2 + 0.002):
        p.append(bx((x, -0.3, 0.5), (x + 0.006, -0.28, 2.4), M["trim"]))
    p.append(bx((-0.012, yr - 0.008, 0.5), (0.012, yr, 2.45), M["trim"]))
    p.append(bx((-W / 2 + 0.2, yr - 0.008, 1.9), (W / 2 - 0.2, yr, 2.3), M["glass"]))
    p.append(bx((-0.6, yr - 0.25, 0.42), (0.6, yr, 0.5), M["steel"]))                          # rear step
    p.append(bx((-W / 2 + 0.1, yf - 0.1, 0.36), (W / 2 - 0.1, yf + 0.04, 0.6), M["trim"]))
    p.append(_plate(yf + 0.04, 0.48, M))
    p.append(_plate(yr - 0.01, 0.62, M, facing=-1))
    p += _mirrors(W, cabf - 0.2, 1.45, M)
    p += _wheels(W - 0.1, (2.0, -1.65), 0.36, M, w=0.24)
    lamps = _lamps(W - 0.14, yf, yr, 0.85, 0.9, M, tw=(0.18, 0.34))
    bar = _lightbar(W, cabf - 0.45, 2.15, M, w=1.5)
    # flashers on the box's back corners join Red/Blue
    bar[2] = ("Red", bar[2][1] + [bx((-W / 2 + 0.05, yr - 0.02, H - 0.25), (-W / 2 + 0.3, yr + 0.0, H - 0.1),
                                     _m("CV_LightRed", "#d0261c", 0.3))], bar[2][2], "LightBar")
    bar[3] = ("Blue", bar[3][1] + [bx((W / 2 - 0.3, yr - 0.02, H - 0.25), (W / 2 - 0.05, yr + 0.0, H - 0.1),
                                      _m("CV_LightBlue", "#2050d8", 0.3))], bar[3][2], "LightBar")
    return [("Ambulance", p, (0, 0, 0), None)] + lamps + bar, {"Siren": ((0.0, yf - 0.05, 0.6), 0)}


def fire():
    """A fire appliance, 8.4 x 2.5 x 3.2: a crew cab, roller-shuttered
    lockers down both sides, the ladder on the roof, a white band on
    Livery."""
    M = _mats()
    L, W, H = 8.4, 2.5, 3.2
    yf, yr = L / 2, -L / 2
    cabr = 1.4
    prof = [(cabr, 0.5), (yf, 0.5), (yf, 1.1), (yf - 0.1, 1.3), (yf - 0.25, H - 0.25), (yf - 0.4, H - 0.1),
            (cabr, H - 0.1)]
    p = [_prism_yz(prof, -W / 2, W / 2, M["paint"])]
    # cab glass: windscreen and the crew windows on each side
    ws = [(-W / 2 + 0.1, yf - 0.09, 1.55), (W / 2 - 0.1, yf - 0.09, 1.55),
          (W / 2 - 0.1, yf - 0.24, H - 0.3), (-W / 2 + 0.1, yf - 0.24, H - 0.3)]
    p.append(C.mesh_obj("windscreen", [(x, y + 0.012, z) for x, y, z in ws], [(0, 1, 2, 3)], M["glass"]))
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.006)
        for y0, y1 in ((cabr + 0.15, cabr + 1.15), (cabr + 1.3, yf - 0.5)):
            p.append(bx((x - 0.004, y0, 1.6), (x + 0.004, y1, H - 0.35), M["glass"]))
    # the body: lockers with roller shutters, the pump panel at the back
    p.append(bx((-W / 2, yr + 0.05, 0.5), (W / 2, cabr - 0.05, H - 0.4), M["paint"]))
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.004)
        for k in range(4):
            y0 = yr + 0.25 + k * 1.3
            p.append(bx((x - 0.004, y0, 0.75), (x + 0.004, y0 + 1.15, 2.6), M["steel"]))
            for j in range(6):
                z = 0.95 + j * 0.28
                p.append(bx((x - 0.006, y0, z), (x + 0.006, y0 + 1.15, z + 0.03), M["grey"]))
    for sx in (-1, 1):
        p.append(bx((sx * (W / 2 + 0.008) - 0.004, yr + 0.05, 0.55), (sx * (W / 2 + 0.008) + 0.004, yf - 0.05, 0.72),
                    M["livery"]))
    p.append(bx((-W / 2 + 0.1, yf, 0.75), (W / 2 - 0.1, yf + 0.01, 0.9), M["livery"]))
    p.append(bx((-W / 2 + 0.15, yr - 0.01, 0.8), (W / 2 - 0.15, yr + 0.05, 2.4), M["steel"]))  # pump panel
    p.append(bx((-0.3, yr - 0.03, 1.2), (0.3, yr - 0.01, 1.8), M["grey"]))
    # the ladder on the roof gantry
    for sx in (-1, 1):
        p.append(bx((sx * 0.35 - 0.04, yr + 0.1, H - 0.1), (sx * 0.35 + 0.04, yf - 0.6, H - 0.02), M["steel"]))
    for k in range(14):
        y = yr + 0.3 + k * 0.5
        p.append(bx((-0.35, y - 0.02, H - 0.08), (0.35, y + 0.02, H - 0.04), M["steel"]))
    for y in (yr + 0.3, cabr - 0.3):
        p.append(bx((-0.5, y - 0.05, H - 0.4), (0.5, y + 0.05, H - 0.1), M["black"]))
    p.append(bx((-W / 2 + 0.05, yf - 0.05, 0.5), (W / 2 - 0.05, yf + 0.1, 0.8), M["steel"]))
    p.append(_plate(yf + 0.11, 0.65, M))
    p.append(_plate(yr - 0.02, 0.6, M, facing=-1))
    p += _mirrors(W, yf - 0.6, 2.1, M)
    p += _wheels(W - 0.05, (2.55, -1.6, -2.75), 0.5, M, w=0.32)
    lamps = _lamps(W, yf + 0.1, yr - 0.01, 0.95, 0.75, M, inset=0.3, hw=(0.3, 0.16))
    bar = _lightbar(W, yf - 0.6, H - 0.1, M, w=1.8)
    return [("Fire", p, (0, 0, 0), None)] + lamps + bar, {"Siren": ((0.0, yf + 0.12, 0.65), 0)}


# ------------------------------------------------------------------ bus

def bus():
    """A Perth-style low-floor bus, 12.5 x 2.5 x 3.15: a silver body (Paint)
    with a green skirt and band (Livery), deep windows, two doors on the
    kerb side, the destination panel "Dest" over the windscreen."""
    M = _mats()
    L, W, H = 12.5, 2.5, 3.15
    yf, yr = L / 2, -L / 2
    # the front rakes back a touch above the windscreen's foot, the roof
    # edges are rounded off front and back
    prof = [(yr, 0.3), (yf, 0.3), (yf, 1.0), (yf - 0.1, 2.75), (yf - 0.2, 3.02), (yf - 0.38, H),
            (yr + 0.3, H), (yr + 0.08, 3.02), (yr, 2.8)]
    p = [_prism_yz(prof, -W / 2, W / 2, M["paint"])]
    # the window band down both sides, broken by the doors on the kerb side
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.006)
        p.append(bx((x - 0.004, yr + 0.5, 1.25), (x + 0.004, yf - 0.5, 2.55), M["glass"]))
        for k in range(10):
            y = yr + 1.3 + k * 1.1
            p.append(bx((x - 0.007, y - 0.05, 1.25), (x + 0.007, y + 0.05, 2.55), M["black"]))
        p.append(bx((x - 0.006, yr + 0.05, 0.3), (x + 0.006, yf - 0.05, 0.75), M["livery"]))     # skirt
        p.append(bx((x - 0.006, yr + 0.05, 2.62), (x + 0.006, yf - 0.05, 2.78), M["livery"]))    # roof band
    # kerb-side doors: glazed leaves in a dark frame
    door = _m("CV_BusDoor", "#2a3a44", 0.1, 0.4)
    for yc in (yf - 1.1, 0.4):
        p.append(bx((-W / 2 - 0.012, yc - 0.6, 0.32), (-W / 2 + 0.01, yc + 0.6, 2.6), M["black"]))
        p.append(bx((-W / 2 - 0.016, yc - 0.56, 0.36), (-W / 2 - 0.004, yc - 0.01, 2.55), door))
        p.append(bx((-W / 2 - 0.016, yc + 0.01, 0.36), (-W / 2 - 0.004, yc + 0.56, 2.55), door))
    # the front: a deep windscreen, the destination panel above it, bumper
    # the windscreen follows the rake (y at height z on the front face)
    def fy(z):
        return yf - 0.1 * (z - 1.0) / 1.75 + 0.012
    ws = [(-W / 2 + 0.06, fy(1.0), 1.0), (W / 2 - 0.06, fy(1.0), 1.0),
          (W / 2 - 0.06, fy(2.5), 2.5), (-W / 2 + 0.06, fy(2.5), 2.5)]
    p.append(C.mesh_obj("windscreen", ws, [(0, 1, 2, 3)], M["glass"]))
    p.append(C.mesh_obj("pillar", [(-0.012, fy(1.0) + 0.003, 1.0), (0.012, fy(1.0) + 0.003, 1.0),
                                   (0.012, fy(2.5) + 0.003, 2.5), (-0.012, fy(2.5) + 0.003, 2.5)],
                        [(0, 1, 2, 3)], M["black"]))
    # wipers parked along the foot of the screen
    for x0 in (-1.0, 0.1):
        p.append(bx((x0, yf + 0.016, 1.05), (x0 + 0.85, yf + 0.03, 1.08), M["black"]))
    # the folding bike rack on the front, folded up (Perth buses carry one)
    for sx in (-1, 1):
        p.append(bx((sx * 0.55 - 0.03, yf + 0.06, 0.45), (sx * 0.55 + 0.03, yf + 0.12, 1.05), M["steel"]))
    p.append(bx((-0.58, yf + 0.06, 1.0), (0.58, yf + 0.12, 1.05), M["steel"]))
    p.append(bx((-0.58, yf + 0.06, 0.62), (0.58, yf + 0.12, 0.66), M["steel"]))
    for x in (-0.3, 0.3):
        p.append(bx((x - 0.04, yf + 0.12, 0.66), (x + 0.04, yf + 0.16, 1.0), M["black"]))
    p.append(bx((-W / 2 + 0.05, yf - 0.05, 0.3), (W / 2 - 0.05, yf + 0.06, 0.6), M["trim"]))
    p.append(bx((-W / 2 + 0.05, yf, 0.62), (W / 2 - 0.05, yf + 0.008, 0.8), M["livery"]))
    p.append(bx((-W / 2 + 0.05, yr - 0.06, 0.3), (W / 2 - 0.05, yr + 0.05, 0.6), M["trim"]))
    p.append(bx((-W / 2 + 0.3, yr - 0.008, 1.9), (W / 2 - 0.3, yr, 2.55), M["glass"]))
    p.append(bx((-W / 2 + 0.15, yr - 0.01, 0.9), (W / 2 - 0.15, yr, 1.5), M["grey"]))          # engine grille
    p.append(_plate(yf + 0.07, 0.45, M))
    p.append(_plate(yr - 0.06, 0.7, M, facing=-1))
    # mirrors on long arms, the roof air-con pod
    for sx in (-1, 1):
        p.append(bx((sx * W / 2 - 0.02, yf - 0.05, 2.4), (sx * (W / 2 + 0.25) + 0.02, yf + 0.25, 2.45), M["black"]))
        p.append(bx((sx * (W / 2 + 0.25) - 0.05, yf + 0.2, 1.95), (sx * (W / 2 + 0.25) + 0.05, yf + 0.3, 2.45),
                    M["black"]))
    # the roof air-con pod with sloped ends, and a roof hatch
    p.append(_prism_yz([(-1.0, H), (2.2, H), (2.0, H + 0.25), (-0.8, H + 0.25)], -0.9, 0.9, M["paint"]))
    p.append(bx((-0.4, -3.6, H), (0.4, -2.9, H + 0.06), M["grey"]))
    # engine louvres on the back corner, kerb and road side
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.006)
        for k in range(4):
            z = 0.95 + k * 0.08
            p.append(bx((x - 0.006, yr + 0.3, z), (x + 0.006, yr + 1.4, z + 0.035), M["black"]))
    # wheels in proper arches
    p = CV._arches(p, W / 2 - 0.3 - 0.06, (yf - 2.6, yr + 3.2), 0.5, M)
    p += _wheels(W, (yf - 2.6, yr + 3.2), 0.5, M, w=0.3)
    dest_mat = _m("Dest", "#1a1a12", 0.6, emit="#f2a020", emit_strength=0.4)
    # on the raked face above the windscreen: y of the face at height z
    def face_y(z):
        return yf - 0.1 * (z - 1.0) / 1.75 if z <= 2.75 else yf - 0.1 - 0.1 * (z - 2.75) / 0.27
    dv = [(x, face_y(z) + 0.014, z) for z in (2.6, 2.9) for x in (-W / 2 + 0.25, W / 2 - 0.25)]
    dest = [C.mesh_obj("dest", [dv[0], dv[1], dv[3], dv[2]], [(0, 1, 2, 3)], dest_mat)]
    lamps = _lamps(W, yf + 0.012, yr, 0.72, 0.9, M, inset=0.3, hw=(0.3, 0.14), tw=(0.16, 0.4))
    return [("Bus", p, (0, 0, 0), None), ("Dest", dest, (0, yf - 0.1, 2.75), None)] + lamps, {}


# ------------------------------------------------------------------ train

def _railcar(cab):
    """One car of a suburban electric railcar, 23 x 3.0: a rounded roof,
    the window band, two pairs of sliding doors a side, bogies, a
    pantograph on the cab car, and the driving cab at the front (+Y) when
    `cab`. Origin at rail level in the middle."""
    M = _mats()
    L, W, H = 23.0, 3.0, 4.0
    yf, yr = L / 2, -L / 2
    zf = 1.1                                    # floor
    prof_y = []
    # the body cross-section: vertical sides tumbling home, a rounded roof
    sec = [(-W / 2 + 0.05, 0.75), (W / 2 - 0.05, 0.75), (W / 2, 1.05), (W / 2, 3.1), (W / 2 - 0.25, 3.6),
           (W / 2 - 0.7, 3.8), (-W / 2 + 0.7, 3.8), (-W / 2 + 0.25, 3.6), (-W / 2, 3.1), (-W / 2, 1.05)]
    del prof_y
    y0, y1 = yr, (yf - 1.6 if cab else yf)
    n = len(sec)
    v = [(x, y0, z) for x, z in sec] + [(x, y1, z) for x, z in sec]
    f = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    f += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    p = [C.mesh_obj("shell", v, f, M["paint"])]
    if cab:
        # the nose: the section tapering and raking back to a flat-faced cab
        nose_y = yf
        sec2 = [(x * 0.92, z if z < 3.0 else 3.0 + (z - 3.0) * 0.55) for x, z in sec]
        v2 = [(x, y1, z) for x, z in sec] + [(x, nose_y, z) for x, z in sec2]
        f2 = [tuple(range(2 * n - 1, n - 1, -1))]
        f2 += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
        p.append(C.mesh_obj("nose", v2, f2, M["paint"]))
        # windscreen on the nose face, the livery wrapping round it
        ws = [(-1.1, nose_y + 0.012, 2.0), (1.1, nose_y + 0.012, 2.0), (1.0, nose_y + 0.012, 3.15),
              (-1.0, nose_y + 0.012, 3.15)]
        p.append(C.mesh_obj("windscreen", ws, [(0, 1, 2, 3)], M["glass"]))
        p.append(bx((-0.02, nose_y, 2.0), (0.02, nose_y + 0.02, 3.15), M["black"]))
        p.append(bx((-1.3, nose_y, 1.15), (1.3, nose_y + 0.014, 1.75), M["livery"]))
        p.append(bx((-1.0, nose_y - 0.1, 0.55), (1.0, nose_y + 0.25, 0.9), M["black"]))       # coupler/skirt
        p.append(bx((-0.18, nose_y + 0.2, 0.62), (0.18, nose_y + 0.55, 0.85), M["grey"]))
        dest_mat = _m("Dest", "#1a1a12", 0.6, emit="#f2a020", emit_strength=0.4)
        p.append(bx((-0.7, nose_y, 3.2), (0.7, nose_y + 0.016, 3.45), dest_mat))
    else:
        # the gangway end at the front too
        p.append(bx((-0.55, yf - 0.02, 0.9), (0.55, yf + 0.25, 3.0), M["black"]))
    p.append(bx((-0.55, yr - 0.25, 0.9), (0.55, yr + 0.02, 3.0), M["black"]))                  # gangway bellows
    # the window band and the livery stripes down both sides
    door_ys = (-6.0, 6.0) if not cab else (-6.5, 4.5)
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.006)
        p.append(bx((x - 0.004, yr + 0.6, 2.0), (x + 0.004, y1 - 0.4, 2.9), M["glass"]))
        k = yr + 1.8
        while k < y1 - 0.8:
            if all(abs(k - d) > 1.0 for d in door_ys):
                p.append(bx((x - 0.008, k - 0.08, 2.0), (x + 0.008, k + 0.08, 2.9), M["paint"]))
            k += 1.9
        p.append(bx((x - 0.006, yr + 0.05, 1.35), (x + 0.006, y1, 1.6), M["livery"]))
        p.append(bx((x - 0.006, yr + 0.05, 3.0), (x + 0.006, y1, 3.08), M["livery"]))
    # bogies and the underframe boxes
    # bogies: wheelsets on Perth's narrow gauge, side frames with axle
    # boxes and springs outside them, a bolster across the middle
    wheel = _m("TV_WheelSteel", "#3b3a38", 0.55, 0.4)      # dark, rusty-brown steel, not the shiny trim
    for yb in (yr + 3.8, (yf - 4.2) if cab else yf - 3.8):
        p.append(bx((-0.75, yb - 0.25, 0.55), (0.75, yb + 0.25, 0.72), M["black"]))
        for sx in (-1, 1):
            xf = sx * 0.86
            p.append(bx((xf - 0.07, yb - 1.35, 0.42), (xf + 0.07, yb + 1.35, 0.62), M["black"]))
            p.append(bx((xf - 0.07, yb - 0.35, 0.3), (xf + 0.07, yb + 0.35, 0.42), M["black"]))
            for yy in (yb - 0.95, yb + 0.95):
                p.append(cyl(0.43, 0.1, (sx * 0.6, yy, 0.43), wheel, segs=12, axis="X"))
                p.append(cyl(0.12, 0.16, (xf, yy, 0.43), M["grey"], segs=8, axis="X"))
                p.append(cyl(0.07, 0.18, (xf, yy, 0.68), M["steel"], segs=6))
    # equipment cases under the floor between the bogies
    for y0, y1, x0, x1, col in ((-4.5, -2.2, -1.2, -0.2, "grey"), (-1.8, 0.4, -1.1, 1.1, "black"),
                                (0.8, 3.2, 0.1, 1.2, "grey"), (3.5, 4.6, -1.2, -0.3, "black")):
        p.append(bx((x0, y0, 0.45), (x1, y1, 0.75), M[col]))
    # roof air-conditioning pods
    for yc in ((yr + 5.0, yf - 7.5) if cab else (yr + 5.0, yf - 5.0)):
        p.append(_prism_yz([(yc - 1.3, 3.8), (yc + 1.3, 3.8), (yc + 1.1, 4.05), (yc - 1.1, 4.05)], -0.7, 0.7,
                           M["grey"]))
    if cab:
        # the pantograph on the roof behind the cab
        pg = yf - 5.0
        p.append(bx((-0.6, pg - 0.6, 3.8), (0.6, pg + 0.6, 3.9), M["grey"]))
        p.append(CV._bar((-0.5, pg, 3.9), (0.0, pg + 0.5, 4.35), 0.03, M["steel"]))
        p.append(CV._bar((0.5, pg, 3.9), (0.0, pg + 0.5, 4.35), 0.03, M["steel"]))
        p.append(bx((-0.8, pg + 0.45, 4.35), (0.8, pg + 0.55, 4.4), M["steel"]))
    objs = [("CarriageCab" if cab else "CarriageMid", p, (0, 0, 0), None)]
    # the doors: two double-leaf doors a side, on their own meshes to slide
    door_mat = _m("CV_TrainDoor", "#2a3a44", 0.1, 0.4)
    for name, sx in (("DoorsL", -1), ("DoorsR", 1)):
        x = sx * (W / 2 + 0.012)
        d = []
        for yc in door_ys:
            for s in (-1, 1):
                ya, yb2 = sorted((yc, yc + s * 0.65))
                d.append(bx((x - 0.006, ya + 0.01, zf), (x + 0.006, yb2 - 0.01, 3.0), M["paint"]))
                d.append(bx((x + sx * 0.004 - 0.006, ya + 0.12, 2.0), (x + sx * 0.004 + 0.006, yb2 - 0.12, 2.85),
                            door_mat))
        objs.append((name, d, (x, 0.0, zf), None))
    if cab:
        objs += [("HeadL", [bx((-1.05, yf, 1.25), (-0.75, yf + 0.02, 1.4), M["head"])], None, None),
                 ("HeadR", [bx((0.75, yf, 1.25), (1.05, yf + 0.02, 1.4), M["head"])], None, None),
                 ("TailL", [bx((-1.3, yf, 1.25), (-1.12, yf + 0.02, 1.4), M["tail"])], None, None),
                 ("TailR", [bx((1.12, yf, 1.25), (1.3, yf + 0.02, 1.4), M["tail"])], None, None)]
    return objs, {}


def carriage_cab():
    return _railcar(True)


def carriage_mid():
    return _railcar(False)


VEHICLES = {
    "hatch": hatch,
    "sedan": sedan,
    "suv": suv,
    "ute": ute,
    "van": van,
    "taxi": taxi,
    "bus": bus,
    "police": police,
    "ambulance": ambulance,
    "fire": fire,
    "carriage_cab": carriage_cab,
    "carriage_mid": carriage_mid,
}
