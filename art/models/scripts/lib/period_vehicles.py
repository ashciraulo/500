"""Period cars for the late city (story batch 3 and on): props, not drivable.

  valiant  A mid-70s Australian full-size sedan in the Chrysler Valiant VK's
           shape, 4.94 x 1.88 x 1.39, with no badges or script anywhere:
           long flat bonnet with a centre crease, single round headlamps in a
           full-width dark grille with a chrome surround and a centre peak,
           amber parkers wrapping the front corners, a formal roof in cream
           vinyl, a full-width tail-lamp band (red outer, amber inner, a
           silver panel between) and chrome bumpers with rubber overriders.

Same conventions as lib/traffic_vehicles.py: front toward +Y (Godot -Z), the
kerb side on -X (driver on +X), origin on the ground at the footprint centre,
no wheel nodes. "Paint" is the body colour and "VinylRoof" the roof, both
recolourable. Lamps are their own meshes so code can light them: HeadL/HeadR,
ParkL/ParkR (the amber front parkers, for "parkers on"), TailL/TailR.

Builders return (objs, empties) in lib/city_vehicles.py's form.
"""
from . import common as C
from . import furniture as F
from . import city_vehicles as CV
from . import traffic_vehicles as TV

bx, cyl = F.bx, F.cyl
_m = CV._m


def _mats():
    M = CV._common()
    M.update({
        "paint": _m("Paint", "#8ca23f", 0.45, 0.25),
        "vinyl": _m("VinylRoof", "#e6e0cc", 0.85),
        "glass": _m("Glass", "#26333b", 0.08, 0.4),
        "chrome": _m("PV_Chrome", "#d4d7d8", 0.2, 0.9),
        "grille": _m("PV_Grille", "#17181a", 0.6),
        "rubber": _m("PV_Rubber", "#141415", 0.85),
        "silver": _m("PV_Silver", "#b8bab6", 0.35, 0.6),
        "park": _m("PV_Parker", "#e8961e", 0.3),
    })
    return M


L, W, H = 4.94, 1.88, 1.39
YF, YR = L / 2, -L / 2
WHEELS = (1.42, -1.40)
R = 0.33
BELT = 0.87


def _body(M):
    # side profile (y, z), anticlockwise seen from +X, as traffic_vehicles.sedan
    prof = [(YR, 0.3), (YF, 0.3), (YF, 0.72), (YF - 0.06, 0.79), (0.95, BELT - 0.01),
            (-1.22, BELT + 0.01), (YR + 0.06, BELT - 0.01), (YR, 0.8)]
    body = TV._prism_yz(prof, -W / 2 + 0.02, W / 2 - 0.02, M["paint"])
    sill = bx((-W / 2 + 0.03, YR + 0.55, 0.24), (W / 2 - 0.03, YF - 0.6, 0.32), M["paint"])
    p = CV._arches([body, sill], 0.45, WHEELS, R, M, clear=0.05)
    # the bonnet's centre crease
    crease = [(0.95, BELT - 0.01), (YF - 0.06, 0.79), (YF - 0.06, 0.802), (0.95, BELT + 0.002)]
    p.append(TV._prism_yz(crease, -0.025, 0.025, M["paint"]))
    return p


def _greenhouse(M):
    cab = TV._cabin(W - 0.12, W - 0.42, (-1.22, 0.95), (-0.86, 0.22), BELT, H, M,
                    pillars=((0.0, 0.2), (0.5, 0.55), (0.95, 1.0)), roof=M["vinyl"])
    # the vinyl's edge: a thin chrome strip along each side of the roof
    for sx in (-1, 1):
        x = sx * ((W - 0.42) / 2 + 0.008)
        cab.append(bx((x - 0.006, -0.86, H - 0.025), (x + 0.006, 0.22, H - 0.005), M["chrome"]))
    return cab


def _trim(M):
    p = []
    # chrome belt moulding and sill strip down both sides
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (W / 2 - 0.02), sx * (W / 2 - 0.005)))
        p.append(bx((x0, YR + 0.04, BELT - 0.03), (x1, YF - 0.08, BELT - 0.015), M["chrome"]))
        p.append(bx((x0, WHEELS[1] + 0.42, 0.33), (x1, WHEELS[0] - 0.42, 0.35), M["chrome"]))
    # front: dark grille across the full width, a chrome surround and centre peak
    p.append(bx((-0.86, YF - 0.02, 0.5), (0.86, YF + 0.01, 0.71), M["grille"]))
    for z0, z1 in ((0.705, 0.725), (0.49, 0.505)):
        p.append(bx((-0.87, YF - 0.01, z0), (0.87, YF + 0.025, z1), M["chrome"]))
    for x in (-0.87, 0.85):
        p.append(bx((x, YF - 0.01, 0.49), (x + 0.02, YF + 0.025, 0.725), M["chrome"]))
    p.append(bx((-0.02, YF - 0.01, 0.5), (0.02, YF + 0.05, 0.72), M["chrome"]))
    for z in (0.56, 0.64):  # horizontal grille bars
        p.append(bx((-0.4, YF, z), (0.4, YF + 0.015, z + 0.012), M["grey"]))
    # headlamp bezels
    for sx in (-1, 1):
        p.append(cyl(0.105, 0.03, (sx * 0.64, YF + 0.01, 0.605), M["chrome"], segs=16, axis="Y"))
    # bumpers: chrome bars that wrap the corners, black overriders at the back
    p.append(bx((-W / 2 + 0.02, YF - 0.02, 0.3), (W / 2 - 0.02, YF + 0.09, 0.44), M["chrome"]))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (W / 2 - 0.02), sx * (W / 2 + 0.005)))
        p.append(bx((x0, YF - 0.28, 0.3), (x1, YF + 0.05, 0.44), M["chrome"]))
        p.append(bx((x0, YR - 0.05, 0.3), (x1, YR + 0.28, 0.46), M["chrome"]))
    p.append(bx((-W / 2 + 0.02, YR - 0.09, 0.3), (W / 2 - 0.02, YR + 0.02, 0.46), M["chrome"]))
    for sx in (-1, 1):
        x = sx * 0.62
        p.append(bx((x - 0.06, YR - 0.13, 0.31), (x + 0.06, YR - 0.08, 0.45), M["rubber"]))
    # the silver panel between the tail lamps, and the plates (blank)
    p.append(bx((-0.42, YR - 0.02, 0.6), (0.42, YR + 0.01, 0.74), M["silver"]))
    p.append(bx((-0.26, YF + 0.09, 0.32), (0.26, YF + 0.1, 0.42), M["plate"]))
    p.append(bx((-0.26, YR - 0.1, 0.48), (0.26, YR - 0.09, 0.59), M["plate"]))
    # round chrome mirror on the driver's door, aerial on the kerb-side guard
    p.append(cyl(0.012, 0.08, (W / 2 + 0.03, 0.7, BELT + 0.04), M["chrome"], segs=6))
    p.append(cyl(0.055, 0.03, (W / 2 + 0.05, 0.7, BELT + 0.11), M["chrome"], segs=10, axis="X"))
    p.append(cyl(0.004, 0.8, (-W / 2 + 0.12, 1.3, BELT + 0.4), M["chrome"], segs=4))
    # door handles and the shut lines between the doors
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (W / 2 - 0.02), sx * (W / 2 + 0.002)))
        for y in (0.45, -0.45):
            p.append(bx((x0, y - 0.1, BELT - 0.08), (x1, y + 0.03, BELT - 0.06), M["chrome"]))
        for y in (0.98, 0.02, -1.0):
            p.append(bx((x0, y - 0.004, 0.36), (x1, y + 0.004, BELT - 0.035), M["black"]))
    return p


def _wheels(M):
    p = []
    track = W - 0.24
    for y in WHEELS:
        for sx in (-1, 1):
            x = sx * track / 2
            p.append(cyl(R, 0.2, (x, y, R), M["tyre"], segs=14, axis="X"))
            p.append(cyl(R * 0.68, 0.2 + 0.016, (x, y, R), M["chrome"], segs=14, axis="X"))
            p.append(cyl(R * 0.22, 0.2 + 0.03, (x, y, R), M["silver"], segs=10, axis="X"))
    return p


def _lamps(M):
    out = []
    for name, sx in (("HeadL", -1), ("HeadR", 1)):
        out.append((name, [cyl(0.085, 0.03, (sx * 0.64, YF + 0.02, 0.605), M["head"], segs=16, axis="Y")],
                    None, None))
    for name, sx in (("ParkL", -1), ("ParkR", 1)):
        xo = sx * (W / 2 - 0.045)
        s0, s1 = sorted((sx * (W / 2 - 0.01), sx * (W / 2 + 0.006)))
        out.append((name, [bx((xo - 0.045, YF - 0.015, 0.51), (xo + 0.045, YF + 0.015, 0.7), M["park"]),
                           bx((s0, YF - 0.2, 0.51), (s1, YF - 0.01, 0.7), M["park"])], None, None))
    for name, sx in (("TailL", -1), ("TailR", 1)):
        x0, x1 = sorted((sx * 0.43, sx * (W / 2 - 0.05)))
        xa0, xa1 = sorted((sx * 0.43, sx * 0.6))
        out.append((name, [bx((x0, YR - 0.025, 0.6), (x1, YR + 0.01, 0.74), M["tail"]),
                           bx((xa0, YR - 0.03, 0.6), (xa1, YR - 0.02, 0.74), M["amber"])], None, None))
    return out


def valiant():
    M = _mats()
    p = _body(M) + _greenhouse(M) + _trim(M) + _wheels(M)
    return [("Valiant", p, (0, 0, 0), None)] + _lamps(M), {}


VEHICLES = {
    "valiant": valiant,
}
