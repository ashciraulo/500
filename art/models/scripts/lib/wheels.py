"""Wheels: tyre + rim revolved around X, with a radial pixel texture for the face.

Every wheel is built with its outer face toward +X (left side of the car).
Right-hand wheels are mirrored geometry so all four wheel nodes keep an
identity rotation and spin around local X.
"""
import math

from . import carkit as K
from . import common as C

# style -> rim radius (m), tyre outer radius, width, face painter
STYLES = {}


def style(name, rim_r, tyre_r, width):
    def deco(fn):
        STYLES[name] = (rim_r, tyre_r, width, fn)
        return fn
    return deco


TYRE = (0.07, 0.07, 0.075)
SIDEWALL = (0.12, 0.12, 0.13)


def _tyre(r, rim):
    if r > 0.995:
        return TYRE
    if r > rim:
        return SIDEWALL if r < 0.97 else TYRE
    return None


@style("pop_trim", 0.178, 0.29, 0.175)
def _pop_trim(r, t, rim):
    """Pop 14" steel wheel under a silver plastic cover with a ring of round holes."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr > 0.94:
        return (0.42, 0.43, 0.45)
    if rr < 0.20:
        return (0.10, 0.10, 0.11) if rr < 0.15 else (0.55, 0.56, 0.58)
    # ten round holes on a ring, small dimples on an inner ring
    for ring_r, hole_r, n in ((0.66, 0.11, 10), (0.36, 0.05, 5)):
        ang = 2 * math.pi / n
        a = (t + ang / 2) % ang - ang / 2
        dx = rr * math.cos(a) - ring_r
        dy = rr * math.sin(a)
        if dx * dx + dy * dy < hole_r * hole_r:
            return (0.08, 0.08, 0.09)
    shade = 0.80 if rr > 0.82 else 0.74
    return (shade, shade + 0.01, shade + 0.03)


@style("steel", 0.178, 0.29, 0.175)
def _steel(r, t, rim):
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr < 0.3:
        hole = rr > 0.2 and (math.degrees(t) % 90) < 18
        return (0.05, 0.05, 0.05) if hole or rr < 0.1 else (0.25, 0.25, 0.27)
    vent = 0.55 < rr < 0.7 and (math.degrees(t) % 45) < 14
    return (0.04, 0.04, 0.04) if vent else (0.22, 0.22, 0.24)


@style("alloy15", 0.19, 0.29, 0.185)
def _alloy15(r, t, rim):
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr > 0.9 or rr < 0.25:
        return (0.7, 0.71, 0.74) if rr > 0.12 else (0.12, 0.12, 0.14)
    spoke = (math.degrees(t) % 24) < 9
    return (0.72, 0.73, 0.76) if spoke else (0.08, 0.08, 0.09)


@style("sport16", 0.203, 0.29, 0.195)
def _sport16(r, t, rim):
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr > 0.9 or rr < 0.28:
        return (0.62, 0.63, 0.66) if rr > 0.12 else (0.5, 0.05, 0.05)
    a = math.degrees(t) % 72
    spoke = a < 10 or 16 < a < 26
    return (0.64, 0.65, 0.68) if spoke else (0.05, 0.05, 0.06)


@style("abarth17", 0.216, 0.295, 0.205)
def _abarth17(r, t, rim):
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr > 0.9:
        return (0.15, 0.15, 0.16)
    if rr < 0.25:
        return (0.85, 0.1, 0.1) if rr < 0.12 else (0.15, 0.15, 0.16)
    a = math.degrees(t) % 72
    return (0.16, 0.16, 0.17) if a < 14 else (0.03, 0.03, 0.03)


@style("turbine16", 0.203, 0.30, 0.195)
def _turbine16(r, t, rim):
    """2020 500: many thin swept spokes, machined silver on dark grey."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr > 0.92:
        return (0.70, 0.71, 0.74)
    if rr < 0.24:
        return (0.12, 0.12, 0.13) if rr < 0.17 else (0.66, 0.67, 0.70)
    a = (math.degrees(t) + rr * 14) % 15      # a slight swirl outwards
    return (0.74, 0.75, 0.78) if a < 5 else (0.10, 0.10, 0.11)


@style("pepper15", 0.19, 0.29, 0.185)
def _pepper15(r, t, rim):
    """2013 500e: a smooth silver face pierced by five big round holes."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr < 0.16:
        return (0.12, 0.12, 0.13)
    for ring_r, hole_r, n in ((0.56, 0.23, 5),):
        ang = 2 * math.pi / n
        a = (t + ang / 2) % ang - ang / 2
        dx, dy = rr * math.cos(a) - ring_r, rr * math.sin(a)
        if dx * dx + dy * dy < hole_r * hole_r:
            return (0.07, 0.07, 0.08)
    return (0.78, 0.79, 0.81)


# ------------------------------------------------------------------ classics (12" rims, 125R12 tyres)

def _holes(rr, t, ring_r, hole_r, n, phase=0.0):
    ang = 2 * math.pi / n
    a = (t + phase + ang / 2) % ang - ang / 2
    dx = rr * math.cos(a) - ring_r
    dy = rr * math.sin(a)
    return dx * dx + dy * dy < hole_r * hole_r


@style("classic12", 0.1524, 0.27, 0.125)
def _classic12(r, t, rim):
    """Nuova/D/F/L: steel wheel in silver with a big domed chrome hubcap."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr < 0.66:
        if rr < 0.10:
            return (0.70, 0.71, 0.73)
        return (0.93, 0.93, 0.95) if rr < 0.60 else (0.62, 0.63, 0.66)
    if rr > 0.95:
        return (0.60, 0.60, 0.62)
    if _holes(rr, t, 0.81, 0.055, 8):
        return (0.05, 0.05, 0.05)
    return (0.74, 0.74, 0.73)


@style("classic_steel", 0.1524, 0.27, 0.125)
def _classic_steel(r, t, rim):
    """500 R: plain steel wheel, small chrome centre cap, four nuts."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr < 0.34:
        return (0.85, 0.85, 0.87) if rr < 0.30 else (0.4, 0.4, 0.42)
    if 0.40 < rr < 0.50 and _holes(rr, t, 0.45, 0.04, 4):
        return (0.25, 0.25, 0.26)
    if 0.62 < rr < 0.80 and _holes(rr, t, 0.71, 0.075, 8, 0.2):
        return (0.05, 0.05, 0.05)
    return (0.66, 0.66, 0.64)


@style("abarth_classic", 0.1524, 0.27, 0.145)
def _abarth_classic(r, t, rim):
    """Classic Abarth: wider exposed steel wheel, silver with big round
    lightening holes and a small chrome nut cap."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr < 0.22:
        return (0.88, 0.88, 0.9) if rr < 0.18 else (0.3, 0.3, 0.32)
    if 0.30 < rr < 0.40 and _holes(rr, t, 0.35, 0.03, 4):
        return (0.12, 0.12, 0.13)
    if _holes(rr, t, 0.66, 0.13, 6, 0.3):
        return (0.04, 0.04, 0.04)
    return (0.72, 0.72, 0.72) if rr < 0.95 else (0.5, 0.5, 0.52)


@style("campagnolo", 0.1524, 0.27, 0.14)
def _campagnolo(r, t, rim):
    """Campagnolo-style cast magnesium: five broad spokes in gold-grey,
    a polished lip and a black centre cap."""
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    gold = (0.70, 0.62, 0.42)
    if rr > 0.92:
        return (0.80, 0.80, 0.80)
    if rr < 0.24:
        return (0.10, 0.10, 0.10) if rr < 0.16 else gold
    a = math.degrees(t) % 72
    w = 22 - 8 * (rr - 0.24) / 0.68         # spokes taper toward the rim
    spoke = a < w / 2 or a > 72 - w / 2
    return gold if spoke else (0.05, 0.05, 0.05)


@style("cromodora13", 0.165, 0.265, 0.16)
def _cromodora(r, t, rim):
    c = _tyre(r, rim)
    if c:
        return c
    rr = r / rim
    if rr > 0.9 or rr < 0.2:
        return (0.8, 0.8, 0.8)
    a = math.degrees(t) % 90
    return (0.75, 0.75, 0.76) if a < 30 else (0.06, 0.06, 0.06)


def build(name, style_name, parent=None, loc=(0, 0, 0), right=False, segs=14):
    rim, R, w, fn = STYLES[style_name]
    h = w / 2
    img = None
    key = "wheel_" + style_name
    import bpy
    img = bpy.data.images.get(key)
    if img is None:
        img = K.radial_texture(key, 64, lambda r, t: fn(r, t, rim / R))
    face = C.mat("Wheel_" + style_name, image=img, rough=0.5, metal=0.2)
    tread = C.mat("Tyre", "#141414", rough=0.95)
    profile = [
        (0.0, -h * 0.6),
        (rim * 0.9, -h * 0.6),
        (rim, -h * 0.95),
        (R - 0.025, -h),
        (R, -h * 0.75),
        (R, h * 0.75),
        (R - 0.025, h),
        (rim + 0.006, h * 0.97),
        (rim * 0.98, h * 0.8),
        (rim * 0.6, h * 0.7),
        (rim * 0.2, h * 0.85),
        (0.0, h * 0.9),
    ]
    obj = K.revolve(name, profile, segs, lambda i: tread if i == 4 else face, parent=parent)
    if right:
        for v in obj.data.vertices:
            v.co.x = -v.co.x
        for p in obj.data.polygons:
            p.flip()
    obj.location = loc
    obj["tyre_radius"] = R
    obj["tyre_width"] = w
    return obj


def radius(style_name):
    return STYLES[style_name][1]
