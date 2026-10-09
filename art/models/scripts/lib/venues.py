"""Northbridge cafes, bars, pubs and restaurants: a shopfront for each real
place on the front wall of its building, with a made-up name.

`build(entry, look)` makes one venue. `entry` is its line in
data/world/venues.json (tools/places/place_venues.py: how wide the
shopfront is, the footpath out to the kerb and its heights, the street trees
and lights in front, how tall the building's wall is); `look` is its look in
tools/places/venues_src.json (colours, the front, the sign, an awning or a
verandah, the tables outside, festoons, lanterns...). Missing keys take the
kind's defaults (DEFAULTS).

Frame: origin on the footpath at the building's wall, in the middle of the
shopfront; the street toward -Y (Godot +Z), the building toward +Y. Nothing
goes behind the wall: the shopfront is a fit-out standing FIT deep in front
of the building's own facade, its glass recessed into it with the room
behind painted on a card (`VN_Glow_*`, lit by venue.gd while the place is
open). Neon is `VN_Neon_*`, festoon bulbs and lanterns `VN_Bulb*`, lamps
that come on every night `VN_Lamp`. Everything on the footpath stands at
the footpath's own height (`ground`).

Returns (parts, sockets, collision boxes) like lib/city_dressing.py.
"""
import math
import os
import random

import bmesh
import bpy

from . import common as C
from . import furniture as F

bx, cyl = F.bx, F.cyl

FIT = 0.22            # how far the fit-out stands out from the building's wall
GLASS = 0.09          # the painted room, this far out from the wall
HEAD = 2.75           # top of the doors and windows
PX = 32               # room card pixels per metre
UV_PAVE = 2.4         # the footpath texture repeats this often (the map's sidewalk UV scale)
FONTS = {
    "serif": "ui/fonts/DMSerifDisplay-Regular.ttf",
    "sans": "ui/fonts/Jost-SemiBold.ttf",
    "script": "ui/fonts/Caveat-Medium.ttf",
    "pixel": "ui/fonts/VT323-Regular.ttf",
}

DEFAULTS = {
    "cafe": {"wall": "#e9e3d3", "wall2": "#5b6b5a", "trim": "#2b2b2a", "front": "windows", "door": "left",
             "sign": {"font": "sans", "style": "painted", "ink": "#2b2b2a", "board": "#e9e3d3"},
             "awning": {"type": "canvas", "colour": "#3f5f4a"},
             "seating": {"type": "bistro", "rows": 1}, "aframe": True, "planters": True,
             "interior": "cafe", "light": "#ffe2b0"},
    "gelato": {"wall": "#f3efe6", "wall2": "#e7a6a0", "trim": "#f3efe6", "front": "glass", "door": "right",
               "sign": {"font": "script", "style": "letters", "ink": "#d0605a"},
               "awning": {"type": "canvas", "colour": "#e7a6a0", "stripe": "#f6efe4"},
               "seating": {"type": "bistro", "rows": 1}, "interior": "gelato", "light": "#fff6e8"},
    "restaurant": {"wall": "#d9cdb4", "wall2": "#6b3a2a", "trim": "#1f1d1b", "front": "windows", "door": "centre",
                   "sign": {"font": "serif", "style": "letters", "ink": "#f1e7cf"},
                   "awning": {"type": "box", "colour": "#232323"},
                   "seating": {"type": "square", "rows": 1}, "interior": "restaurant", "light": "#ffd9a0"},
    "bar": {"wall": "#2a2a2c", "wall2": "#3b302a", "trim": "#151515", "front": "windows", "door": "right",
            "sign": {"font": "script", "style": "neon", "ink": "#ff5a8a"},
            "awning": {"type": "none"}, "seating": {"type": "high", "rows": 1},
            "interior": "bar", "light": "#ffb46a", "lamps": True},
    "pub": {"wall": "#d8c7a2", "wall2": "#3f5a46", "trim": "#2c3b30", "front": "pub", "door": "double",
            "sign": {"font": "serif", "style": "painted", "ink": "#f0e4c4", "board": "#2c3b30"},
            "awning": {"type": "lace", "colour": "#d7d9d5"}, "seating": {"type": "barrel", "rows": 1},
            "interior": "pub", "light": "#ffc87a", "lamps": True},
}


def _m(name, col, rough=0.8, metal=0.0, **kw):
    return C.mat("VN_" + name, col, rough=rough, metal=metal, **kw)


def _rgb(c):
    return C._hex(c)


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def _merge(base, over):
    out = dict(base)
    for k, v in (over or {}).items():
        out[k] = _merge(base[k], v) if isinstance(v, dict) and isinstance(base.get(k), dict) else v
    return out


# ------------------------------------------------------------------ ground

class Ground:
    """Footpath height above the origin at (x, d): x along the wall, d out
    from it (Blender y = -d), bilinear on venues.json's grid."""

    def __init__(self, entry):
        self.x0, self.nx = entry["ground_x"][0], entry["ground_x"][1]
        self.nz = entry["ground_z"]
        self.h = entry["ground"]

    def __call__(self, x, d):
        fx = min(max((x - self.x0) / 0.5, 0.0), self.nx - 1.001)
        fz = min(max(d / 0.5, 0.0), self.nz - 1.001)
        i, j = int(fx), int(fz)
        tx, tz = fx - i, fz - j
        h = self.h
        a = h[j * self.nx + i] * (1 - tx) + h[j * self.nx + i + 1] * tx
        b = h[(j + 1) * self.nx + i] * (1 - tx) + h[(j + 1) * self.nx + i + 1] * tx
        return a * (1 - tz) + b * tz

    def low(self, x0, x1, d0=0.0, d1=0.6):
        return min(self(x, d) for x in _steps(x0, x1, 0.5) for d in _steps(d0, d1, 0.5))

    def high(self, x0, x1, d0=0.0, d1=0.6):
        return max(self(x, d) for x in _steps(x0, x1, 0.5) for d in _steps(d0, d1, 0.5))


def _steps(a, b, s):
    n = max(1, int(math.ceil((b - a) / s)))
    return [a + (b - a) * i / n for i in range(n + 1)]


# ------------------------------------------------------------------ text

_FONT_CACHE = {}


def _font(kind):
    if kind not in _FONT_CACHE:
        _FONT_CACHE[kind] = bpy.data.fonts.load(os.path.join(C.REPO, FONTS[kind]))
    return _FONT_CACHE[kind]


def text_mesh(text, font, mat, max_w, max_h, centre, depth=0.0, facing=-1, resolution=2):
    """Letters as a flat (or extruded) mesh facing -Y (or +Y), fitted inside
    max_w x max_h and centred on `centre` (x, y, z). Returns the object, or
    None for no text."""
    if not text:
        return None
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = text
    cu.font = _font(font)
    cu.size = 1.0
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.resolution_u = resolution
    cu.extrude = depth / 2 if depth else 0.0
    cu.fill_mode = "BOTH"
    ob = bpy.data.objects.new("txt", cu)
    C.link(ob)
    bpy.context.view_layer.update()
    me = _filled(ob, resolution, cu.extrude)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    if not xs:
        return None
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    s = min(max_w / max(w, 1e-6), max_h / max(h, 1e-6))
    x0, y0, z0 = centre
    for v in me.vertices:
        x, y, z = (v.co.x - cx) * s, (v.co.y - cy) * s, v.co.z
        if facing < 0:
            v.co = (x0 + x, y0 + z, z0 + y)
        else:
            v.co = (x0 - x, y0 - z, z0 + y)
    if facing > 0:
        me.flip_normals()  # turning the letters round flips their winding
    me.materials.append(mat)
    ob = bpy.data.objects.new("txt", me)
    C.link(ob)
    for p in me.polygons:
        p.use_smooth = False
    _face(ob, facing)
    return ob


def _filled(ob, resolution, extrude):
    """The text object's letters as one mesh. Blender fills a glyph's
    outlines even-odd, so letters drawn as overlapping strokes (Jost's R, E
    and A, Caveat's B) come out with holes where the strokes cross. Fill
    each outer outline on its own, with the counters inside it, and merge."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    crv = ev.to_curve(dg)
    outlines = []
    for sp in crv.splines:
        pts = [(b.co.x, b.co.y) for b in sp.bezier_points]
        if len(pts) < 2:
            continue
        area = 0.5 * sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts)))
        outlines.append((sp, pts, area))
    if not outlines:
        ev.to_curve_clear()
        return bpy.data.meshes.new_from_object(ev)
    sign = 1 if max(outlines, key=lambda o: abs(o[2]))[2] > 0 else -1
    outers = [o for o in outlines if o[2] * sign > 0]
    groups = {id(o[0]): [o] for o in outers}
    for o in outlines:
        if o[2] * sign > 0:
            continue
        inside = [q for q in outers if _inside(o[1][0], q[1])]
        if inside:
            groups[id(min(inside, key=lambda q: abs(q[2]))[0])].append(o)
    bm = bmesh.new()
    for group in groups.values():
        nc = bpy.data.curves.new("glyph", "CURVE")
        nc.dimensions = "2D"
        nc.fill_mode = "BOTH"
        nc.resolution_u = resolution
        nc.extrude = extrude
        for sp, _pts, _a in group:
            ns = nc.splines.new("BEZIER")
            ns.bezier_points.add(len(sp.bezier_points) - 1)
            for a, b in zip(sp.bezier_points, ns.bezier_points):
                b.co = a.co
                b.handle_left_type, b.handle_right_type = "FREE", "FREE"
                b.handle_left, b.handle_right = a.handle_left, a.handle_right
            ns.use_cyclic_u = True
            ns.resolution_u = resolution
        go = bpy.data.objects.new("glyph", nc)
        C.link(go)
        bpy.context.view_layer.update()
        gm = bpy.data.meshes.new_from_object(go.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bm.from_mesh(gm)
        bpy.data.objects.remove(go)
        bpy.data.curves.remove(nc)
        bpy.data.meshes.remove(gm)
    ev.to_curve_clear()
    me = bpy.data.meshes.new("txt")
    bm.to_mesh(me)
    bm.free()
    return me


def _inside(pt, poly):
    x, y = pt
    hit = False
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i - 1], poly[i]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def _face(ob, facing):
    """Make every polygon of a flat sign face its side (-Y or +Y)."""
    me = ob.data
    me.update()
    flip = False
    for p in me.polygons:
        if abs(p.normal.y) > 0.9:
            flip = (p.normal.y > 0) != (facing > 0)
            break
    if flip:
        me.flip_normals()


# ------------------------------------------------------------------ the room card

def _room_image(name, look, w_m, h_m, seed):
    """The room behind the glass, painted at PX per metre: back wall,
    counter, shelves, lamps and people by the venue's interior, with a sheen
    of reflection over the glass. y=0 is the floor line."""
    kind = look.get("interior", "cafe")
    W, H = max(16, int(w_m * PX)), max(16, int(h_m * PX))
    rnd = random.Random(seed)
    light = _rgb(look.get("light", "#ffe2b0"))
    wall = _rgb(look.get("room", {"cafe": "#d8c6a6", "bar": "#3a2a20", "pub": "#4a3020", "restaurant": "#b89a78",
                                  "asian": "#e8dcc6", "gelato": "#f4eee6", "tiki": "#2c4a3e",
                                  "club": "#20142a", "brewery": "#4a4440", "diner": "#f0e8d8"}.get(kind, "#c8b49a")))
    dark = _mix(wall, (0, 0, 0), 0.55)
    px = [[wall for _ in range(W)] for _ in range(H)]

    def rect(x0, y0, x1, y1, col):
        for y in range(max(0, int(y0)), min(H, int(y1))):
            row = px[y]
            for x in range(max(0, int(x0)), min(W, int(x1))):
                row[x] = col

    def blob(cx, cy, rx, ry, col):
        for y in range(max(0, int(cy - ry)), min(H, int(cy + ry) + 1)):
            for x in range(max(0, int(cx - rx)), min(W, int(cx + rx) + 1)):
                if ((x - cx) / max(rx, 0.5)) ** 2 + ((y - cy) / max(ry, 0.5)) ** 2 <= 1.0:
                    px[y][x] = col

    def m(v):
        return int(v * PX)

    # back wall shading: darker toward the floor and the ceiling
    for y in range(H):
        t = y / max(H - 1, 1)
        shade = 0.72 + 0.28 * math.sin(math.pi * min(1.0, t * 1.1))
        for x in range(W):
            px[y][x] = _mix(dark, wall, shade)
    rect(0, 0, W, m(0.12), _mix(dark, (0, 0, 0), 0.4))                     # floor
    rect(0, H - m(0.18), W, H, _mix(dark, (0, 0, 0), 0.35))                # ceiling
    # what's in the room
    counter_col = _rgb(look.get("counter", {"bar": "#5a3622", "pub": "#4a2c1a", "cafe": "#8a6a4a",
                                            "gelato": "#ffffff", "asian": "#c8302a"}.get(kind, "#6a4a32")))
    if kind in ("cafe", "gelato", "asian"):
        cx0, cx1 = W * 0.25, W * 0.85
        rect(cx0, m(0.12), cx1, m(1.0), counter_col)
        rect(cx0, m(1.0), cx1, m(1.06), _mix(counter_col, (1, 1, 1), 0.4))
        if kind == "cafe":
            ex = cx0 + (cx1 - cx0) * 0.6
            rect(ex, m(1.06), ex + m(0.7), m(1.5), (0.78, 0.8, 0.82))          # espresso machine
            rect(ex + m(0.08), m(1.25), ex + m(0.62), m(1.3), (0.6, 0.15, 0.12))
            rect(cx0 + m(0.2), m(1.06), cx0 + m(1.0), m(1.35), _mix(light, (1, 1, 1), 0.3))  # cake cabinet
            for i in range(int((cx1 - cx0) / m(0.25))):                          # cups on a shelf
                rect(cx0 + i * m(0.25), m(1.85), cx0 + i * m(0.25) + m(0.12), m(1.95), (0.95, 0.94, 0.9))
            rect(cx0, m(1.8), cx1, m(1.84), _mix(counter_col, (0, 0, 0), 0.3))
            rect(W * 0.05, m(1.5), W * 0.05 + m(1.0), m(2.2), (0.12, 0.12, 0.11))   # menu board
            for i in range(5):
                rect(W * 0.05 + m(0.1), m(1.6) + i * m(0.11), W * 0.05 + m(rnd.uniform(0.5, 0.9)), m(1.63) + i * m(0.11),
                     (0.85, 0.85, 0.8))
        elif kind == "gelato":
            tubs = [(0.95, 0.75, 0.8), (0.75, 0.9, 0.7), (0.98, 0.92, 0.6), (0.6, 0.4, 0.3), (0.95, 0.95, 0.9),
                    (0.7, 0.8, 0.95), (0.9, 0.5, 0.4)]
            rect(cx0, m(0.95), cx1, m(1.25), (0.8, 0.9, 0.95))
            for i in range(int((cx1 - cx0) / m(0.18))):
                rect(cx0 + i * m(0.18) + 1, m(0.98), cx0 + i * m(0.18) + m(0.15), m(1.12), rnd.choice(tubs))
        else:
            for i in range(int(W / m(0.5))):                                      # menu photos over the counter
                rect(i * m(0.5) + 2, m(1.9), i * m(0.5) + m(0.42), m(2.25),
                     rnd.choice([(0.85, 0.5, 0.2), (0.9, 0.8, 0.5), (0.5, 0.7, 0.3), (0.8, 0.3, 0.2)]))
    if kind in ("bar", "pub", "club", "tiki"):
        # backlit shelves of bottles behind the bar
        sx0, sx1 = W * 0.15, W * 0.9
        rect(sx0, m(1.15), sx1, m(2.3), _mix(light, wall, 0.25))
        for row in range(3):
            y0 = m(1.2) + row * m(0.36)
            rect(sx0, y0 - 2, sx1, y0, _mix(counter_col, (0, 0, 0), 0.4))
            x = sx0 + 2
            while x < sx1 - 3:
                bw = rnd.choice([2, 2, 3])
                rect(x, y0, x + bw, y0 + m(rnd.uniform(0.18, 0.3)),
                     rnd.choice([(0.35, 0.18, 0.08), (0.2, 0.35, 0.18), (0.75, 0.6, 0.3), (0.85, 0.85, 0.8),
                                 (0.5, 0.1, 0.1), (0.15, 0.15, 0.2)]))
                x += bw + rnd.choice([1, 1, 2])
        rect(sx0 - m(0.2), m(0.12), sx1 + m(0.2), m(1.1), counter_col)           # the bar
        rect(sx0 - m(0.25), m(1.06), sx1 + m(0.25), m(1.13), _mix(counter_col, (1, 1, 1), 0.25))
        if kind == "pub":
            for i in range(4):                                                    # beer taps
                tx = W * 0.4 + i * m(0.18)
                rect(tx, m(1.13), tx + 2, m(1.35), (0.85, 0.7, 0.35))
            rect(W * 0.04, m(1.6), W * 0.04 + m(1.1), m(2.2), (0.25, 0.45, 0.75))   # the footy on telly
        if kind == "tiki":
            for i in range(int(W / m(0.4))):
                blob(i * m(0.4) + m(0.2), H - m(0.3), m(0.2), m(0.12), (0.2, 0.5, 0.25))
        for i in range(int((sx1 - sx0) / m(0.7))):                                # stools
            sx = sx0 + m(0.3) + i * m(0.7)
            rect(sx, m(0.12), sx + 2, m(0.7), (0.1, 0.08, 0.07))
            rect(sx - m(0.12), m(0.7), sx + m(0.14), m(0.76), (0.15, 0.1, 0.08))
    if kind == "brewery":
        # the brewhouse behind the glass: copper kettles and steel fermenters
        for i in range(int(W / m(1.6))):
            tx = m(0.5) + i * m(1.6)
            col = (0.72, 0.42, 0.22) if i % 2 == 0 else (0.75, 0.77, 0.78)
            rect(tx, m(0.3), tx + m(1.1), m(2.0), col)
            blob(tx + m(0.55), m(2.0), m(0.55), m(0.25), col)
            rect(tx + m(0.1), m(0.3), tx + m(0.18), m(2.0), _mix(col, (1, 1, 1), 0.4))
            rect(tx + m(0.5), m(2.2), tx + m(0.6), H - m(0.18), (0.6, 0.62, 0.62))
        rect(0, m(0.12), W, m(0.3), (0.2, 0.2, 0.2))
    if kind == "diner":
        # checkerboard floor, red booths, a chrome counter with stools
        for y in range(m(0.12), m(0.45)):
            for x in range(W):
                px[y][x] = (0.95, 0.95, 0.92) if ((x // 4) + (y // 4)) % 2 == 0 else (0.1, 0.1, 0.1)
        for i in range(int(W / m(1.8))):
            bx0 = m(0.3) + i * m(1.8)
            rect(bx0, m(0.45), bx0 + m(0.25), m(1.3), (0.78, 0.12, 0.12))
            rect(bx0 + m(1.1), m(0.45), bx0 + m(1.35), m(1.3), (0.78, 0.12, 0.12))
            rect(bx0 + m(0.3), m(0.72), bx0 + m(1.05), m(0.78), (0.85, 0.85, 0.82))
        rect(0, m(1.7), W, m(1.78), (0.8, 0.82, 0.84))
        for i in range(int(W / m(0.9))):
            rect(m(0.3) + i * m(0.9), m(1.85), m(0.3) + i * m(0.9) + m(0.6), m(2.2),
                 rnd.choice([(0.95, 0.8, 0.3), (0.3, 0.75, 0.8), (0.9, 0.3, 0.3)]))
    if kind in ("restaurant", "asian"):
        for i in range(int(W / m(1.3))):                                          # tables with cloths
            tx = m(0.4) + i * m(1.3)
            rect(tx, m(0.7), tx + m(0.8), m(0.76), (0.95, 0.94, 0.9) if kind == "restaurant" else (0.85, 0.75, 0.55))
            rect(tx + m(0.05), m(0.3), tx + m(0.75), m(0.7), (0.92, 0.9, 0.86) if kind == "restaurant" else dark)
            for sx in (-0.18, 0.86):
                rect(tx + m(sx), m(0.12), tx + m(sx) + m(0.12), m(0.95), _mix(counter_col, (0, 0, 0), 0.3))
        for i in range(int(W / m(1.6))):                                          # pictures on the wall
            px0 = m(0.6) + i * m(1.6)
            rect(px0, m(1.5), px0 + m(0.6), m(2.0), _mix(wall, (0.2, 0.25, 0.3), 0.5))
    # lamps: pendants with a pool of light under each
    lamp_col = _mix(light, (1, 1, 1), 0.35)
    for i in range(max(1, int(W / m(1.4)))):
        lx = m(0.7) + i * m(1.4) + rnd.randint(-3, 3)
        if kind in ("asian",) or look.get("lanterns"):
            blob(lx, H - m(0.55), m(0.16), m(0.2), (0.85, 0.2, 0.15))
        else:
            rect(lx, H - m(0.5), lx + 1, H - m(0.18), (0.1, 0.1, 0.1))
            blob(lx, H - m(0.55), m(0.09), m(0.06), lamp_col)
        for y in range(m(1.2), H - m(0.6)):
            spread = (H - m(0.6) - y) * 0.35
            for x in range(int(lx - spread), int(lx + spread) + 1):
                if 0 <= x < W:
                    px[y][x] = _mix(px[y][x], light, 0.12)
    # people: a few heads and shoulders in silhouette
    for i in range(rnd.randint(2, 3 + int(W / m(2.5)))):
        hx = rnd.uniform(m(0.4), W - m(0.4))
        seated = rnd.random() < 0.6
        top = m(1.25 if seated else 1.7)
        body = _mix(rnd.choice([(0.15, 0.18, 0.25), (0.45, 0.2, 0.18), (0.25, 0.3, 0.25), (0.6, 0.55, 0.5),
                                (0.12, 0.12, 0.12)]), dark, 0.35)
        rect(hx - m(0.2), m(0.12) if not seated else m(0.6), hx + m(0.2), top - m(0.18), body)
        blob(hx, top - m(0.06), m(0.1), m(0.12), _mix((0.55, 0.4, 0.3), dark, 0.4))
    # the glass: a darker edge and a few pale streaks of reflection
    for y in range(H):
        for x in range(W):
            r, g, b = px[y][x]
            t = 0.88
            if ((x + y * 0.8) % (W * 0.55)) < 6 or ((x + y * 0.8 + 9) % (W * 0.55)) < 2:
                t = 1.0
                r, g, b = _mix((r, g, b), (0.85, 0.9, 0.95), 0.25)
            px[y][x] = (r * t, g * t, b * t)
    return C.make_image(name, W, H, lambda x, y: px[y][x])


def _card(img, x0, x1, z0, z1, room, y, mat):
    """A quad of the room card facing -Y between x0..x1, z0..z1, UVs from
    the room's rect (rx0, rx1, rz0, rz1)."""
    rx0, rx1, rz0, rz1 = room
    v = [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
    o = C.mesh_obj("card", v, [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (x, z) in zip(o.data.polygons[0].loop_indices, ((x0, z0), (x1, z0), (x1, z1), (x0, z1))):
        uv.data[li].uv = ((x - rx0) / (rx1 - rx0), (z - rz0) / (rz1 - rz0))
    _face(o, -1)
    return o


# ------------------------------------------------------------------ outdoor furniture

def _bistro_set(M, chair_col, table_col, x, d, g, rot=0.0):
    """A small round table and two aluminium chairs facing each other along x."""
    z = g(x, d)
    p = [cyl(0.3, 0.03, (x, -d, z + 0.72), table_col, 12),
         cyl(0.025, 0.7, (x, -d, z + 0.36), M["steel"], 6),
         cyl(0.2, 0.02, (x, -d, z + 0.01), M["steel"], 8)]
    for sx in (-1, 1):
        cx = x + sx * 0.5
        cz = g(cx, d)
        p += _chair(M, chair_col, cx, d, cz, face=-sx)
    return p


def _chair(M, col, x, d, z, face=1):
    """A cafe chair facing +x (face=1) or -x: seat, back on the far side, four legs."""
    y = -d
    back = x - face * 0.19
    p = [bx((x - 0.19, y - 0.19, z + 0.44), (x + 0.19, y + 0.19, z + 0.47), col),
         bx((back - 0.02, y - 0.19, z + 0.47), (back + 0.02, y + 0.19, z + 0.84), col)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(bx((x + sx * 0.16 - 0.015, y + sy * 0.16 - 0.015, z), (x + sx * 0.16 + 0.015, y + sy * 0.16 + 0.015, z + 0.44),
                        M["steel"]))
    return p


def _square_set(M, chair_col, table_col, x, d, g):
    """A 0.8 m square table with four chairs."""
    z = g(x, d)
    p = [bx((x - 0.4, -d - 0.4, z + 0.71), (x + 0.4, -d + 0.4, z + 0.75), table_col)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(bx((x + sx * 0.34 - 0.02, -d + sy * 0.34 - 0.02, z), (x + sx * 0.34 + 0.02, -d + sy * 0.34 + 0.02, z + 0.71),
                        M["steel"]))
    for sx in (-1, 1):
        cx = x + sx * 0.62
        p += _chair(M, chair_col, cx, d, g(cx, d), face=-sx)
    return p


def _high_set(M, table_col, x, d, g, stools=2):
    """A high bar table (leaner) with stools."""
    z = g(x, d)
    p = [bx((x - 0.35, -d - 0.3, z + 1.04), (x + 0.35, -d + 0.3, z + 1.08), table_col),
         bx((x - 0.04, -d - 0.04, z), (x + 0.04, -d + 0.04, z + 1.04), M["black"]),
         bx((x - 0.25, -d - 0.2, z), (x + 0.25, -d + 0.2, z + 0.03), M["black"])]
    for i, sx in enumerate((-1, 1)[:stools]):
        sxp = x + sx * 0.55
        sz = g(sxp, d)
        p += [cyl(0.17, 0.05, (sxp, -d, sz + 0.76), table_col, 10),
              cyl(0.02, 0.74, (sxp, -d, sz + 0.37), M["black"], 5),
              cyl(0.18, 0.02, (sxp, -d, sz + 0.01), M["black"], 8),
              cyl(0.13, 0.01, (sxp, -d, sz + 0.3), M["black"], 8)]
    return p


def _barrel_set(M, x, d, g):
    """A beer barrel as a table, two stools."""
    z = g(x, d)
    p = [cyl(0.3, 1.0, (x, -d, z + 0.5), M["oak"], 10, r_top=0.27),
         cyl(0.31, 0.04, (x, -d, z + 0.25), M["black"], 10),
         cyl(0.3, 0.04, (x, -d, z + 0.78), M["black"], 10),
         cyl(0.29, 0.02, (x, -d, z + 1.0), M["oak_top"], 10)]
    for sx in (-1, 1):
        sxp = x + sx * 0.55
        sz = g(sxp, d)
        p += [cyl(0.16, 0.05, (sxp, -d, sz + 0.72), M["oak"], 10),
              cyl(0.02, 0.7, (sxp, -d, sz + 0.35), M["black"], 5),
              cyl(0.16, 0.02, (sxp, -d, sz + 0.01), M["black"], 8)]
    return p


def _bench_set(M, table_col, x0, x1, d, g):
    """A long bench against the wall with small tables in front."""
    p = []
    zb = g((x0 + x1) / 2, d)
    p.append(bx((x0, -d - 0.2, zb + 0.42), (x1, -d + 0.2, zb + 0.47), table_col))
    for x in (x0 + 0.1, (x0 + x1) / 2, x1 - 0.1):
        p.append(bx((x - 0.03, -d - 0.15, g(x, d)), (x + 0.03, -d + 0.15, zb + 0.42), M["black"]))
    n = max(1, int((x1 - x0) / 1.4))
    for i in range(n):
        tx = x0 + (x1 - x0) * (i + 0.5) / n
        td = d + 0.55
        tz = g(tx, td)
        p += [bx((tx - 0.3, -td - 0.25, tz + 0.7), (tx + 0.3, -td + 0.25, tz + 0.73), table_col),
              cyl(0.025, 0.7, (tx, -td, tz + 0.35), M["steel"], 6),
              cyl(0.18, 0.02, (tx, -td, tz + 0.01), M["steel"], 8)]
    return p


def _picnic_set(M, x, d, g):
    """A timber beer-garden setting: table and two bench seats along x."""
    z = g(x, d)
    wood = M["oak"]
    p = [bx((x - 0.9, -d - 0.38, z + 0.72), (x + 0.9, -d + 0.38, z + 0.76), wood)]
    for sy in (-1, 1):
        p.append(bx((x - 0.9, -d + sy * 0.62 - 0.14, z + 0.42), (x + 0.9, -d + sy * 0.62 + 0.14, z + 0.46), wood))
    for sx in (-0.7, 0.7):
        p.append(bx((x + sx - 0.04, -d - 0.75, z), (x + sx + 0.04, -d + 0.75, z + 0.06), wood))
        p.append(bx((x + sx - 0.04, -d - 0.05, z), (x + sx + 0.04, -d + 0.05, z + 0.72), wood))
    return p


def _umbrella(M, col, x, d, g, r=1.25):
    z = g(x, d)
    p = [cyl(0.025, 2.35, (x, -d, z + 1.175), M["oak"], 6),
         cyl(0.25, 0.08, (x, -d, z + 0.04), M["black"], 8)]
    # an 8-sided canopy: a shallow cone
    segs = 8
    top = (x, -d, z + 2.45)
    v = [top] + [(x + math.cos(2 * math.pi * i / segs) * r, -d + math.sin(2 * math.pi * i / segs) * r, z + 2.05)
                 for i in range(segs)]
    f = [(0, 1 + (i + 1) % segs, 1 + i) for i in range(segs)]
    f.append(tuple(range(segs, 0, -1)))
    p.append(C.mesh_obj("umb", v, f, col))
    for i in range(segs):                                                         # valance
        a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
        q = [(x + math.cos(a0) * r, -d + math.sin(a0) * r, z + 2.05), (x + math.cos(a1) * r, -d + math.sin(a1) * r, z + 2.05),
             (x + math.cos(a1) * r, -d + math.sin(a1) * r, z + 1.93), (x + math.cos(a0) * r, -d + math.sin(a0) * r, z + 1.93)]
        p.append(C.mesh_obj("val", q, [(0, 1, 2, 3), (3, 2, 1, 0)], col))
    return p


def _planter(M, x, d, g, w=0.9, seed=0):
    z = g(x, d)
    rnd = random.Random(seed)
    p = [bx((x - w / 2, -d - 0.22, z), (x + w / 2, -d + 0.22, z + 0.5), M["planter"]),
         bx((x - w / 2 + 0.03, -d - 0.19, z + 0.47), (x + w / 2 - 0.03, -d + 0.19, z + 0.5), M["soil"])]
    for i in range(int(w / 0.18)):
        p.append(C.sphere("leaf", rnd.uniform(0.14, 0.22), (x - w / 2 + 0.12 + i * 0.18, -d + rnd.uniform(-0.08, 0.08),
                                                             z + 0.6 + rnd.uniform(0, 0.15)),
                          rnd.choice([M["leaf"], M["leaf_dark"]]), segs=6, rings=4))
    return p


def _aframe(M, x, d, g, lines, seed=0):
    """A chalkboard sandwich board: two leaves meeting at the top, the
    chalk face toward the street (-y)."""
    z = g(x, d)
    p = []
    foot, h = 0.22, 0.95
    for sy in (-1, 1):
        v = [(x - 0.3, -d + foot * sy, z), (x + 0.3, -d + foot * sy, z), (x + 0.3, -d + 0.02 * sy, z + h),
             (x - 0.3, -d + 0.02 * sy, z + h)]
        p.append(C.mesh_obj("af", v, [(0, 1, 2, 3), (3, 2, 1, 0)], M["timber"]))

    def out(zz):   # the front leaf's face at this height, just proud of it
        t = (zz - z) / h
        return -d - (foot + (0.02 - foot) * t) - 0.012

    img = _chalk_image("chalk_%d" % seed, lines, seed)
    mat = C.mat("VN_Chalk_%d" % seed, "#ffffff", rough=0.95, image=img)
    z0, z1 = z + 0.08, z + 0.88
    v = [(x - 0.25, out(z0), z0), (x + 0.25, out(z0), z0), (x + 0.25, out(z1), z1), (x - 0.25, out(z1), z1)]
    o = C.mesh_obj("chalk", v, [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, vv) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, vv)
    _face(o, -1)
    p.append(o)
    return p


def _chalk_image(name, lines, seed):
    from . import textures as TX
    W, H = 24, 36
    rnd = random.Random(seed)
    rows = []
    for i, line in enumerate(lines[:5]):
        rows.append((line[:6], H - 4 - i * 7))

    def fn(x, y):
        base = (0.1, 0.11, 0.1)
        for line, y0 in rows:
            gy = y0 - y
            if 0 <= gy < 5:
                x0 = (W - 4 * len(line) + 1) // 2
                gx = x - x0
                if 0 <= gx < 4 * len(line):
                    ch = line[gx // 4]
                    lx = gx % 4
                    if lx < 3 and TX.FONT.get(ch, TX.FONT[" "])[gy * 3 + lx] == "1":
                        return (0.92, 0.9, 0.82)
        return base
    return C.make_image(name, W, H, fn)


# ------------------------------------------------------------------ the shopfront

def _mats(look):
    return {
        "wall": _m("Wall", look["wall"], 0.9),
        "wall2": _m("Wall2", look["wall2"], 0.7),
        "trim": _m("Trim", look["trim"], 0.5),
        "steel": _m("Steel", "#9ea2a3", 0.4, 0.6),
        "black": _m("Black", "#18181a", 0.6),
        "oak": _m("Oak", "#8a6440", 0.75),
        "oak_top": _m("OakTop", "#a07a50", 0.7),
        "timber": _m("Timber", "#6a4a30", 0.8),
        "brass": _m("Brass", "#b8913f", 0.35, 0.8),
        "planter": _m("Planter", look.get("planter", "#2d2d2b"), 0.8),
        "soil": _m("Soil", "#3a2a1e", 1.0),
        "leaf": _m("Leaf", "#3f6b35", 0.8),
        "leaf_dark": _m("LeafDark", "#2c4f2a", 0.8),
        "roof": _m("Roof", "#c9ccc8", 0.5, 0.4),
        "step": _m("Step", "#8f8a80", 0.95),
        "tile": _m("Tile", look.get("tile", look["wall2"]), 0.3),
    }


def _bays(look, x0, x1):
    """Split x0..x1 into doors and windows: [(kind, a, b)]."""
    door = look.get("door", "left")
    front = look.get("front", "windows")
    dw = 1.7 if door == "double" else 1.05
    span = x1 - x0
    if front == "bifold":
        return [("open", x0, x1)]
    if span < dw + 0.8:
        return [("door", x0 + (span - dw) / 2, x0 + (span + dw) / 2)]
    if door in ("centre", "double"):
        a = x0 + (span - dw) / 2
        return [("window", x0, a - 0.08), ("door", a, a + dw), ("window", a + dw + 0.08, x1)]
    if door == "right":
        return [("window", x0, x1 - dw - 0.08), ("door", x1 - dw, x1)]
    if door == "both":
        return [("door", x0, x0 + dw), ("window", x0 + dw + 0.08, x1 - dw - 0.08), ("door", x1 - dw, x1)]
    return [("door", x0, x0 + dw), ("window", x0 + dw + 0.08, x1)]


def build(entry, look_in):
    kind = entry.get("kind", "cafe")
    look = _merge(DEFAULTS.get(kind, DEFAULTS["cafe"]), look_in)
    vid = entry["id"]
    W = float(entry["width"])
    depth = float(entry.get("depth", 3.0))
    g = Ground(entry)
    M = _mats(look)
    seed = sum(ord(c) for c in vid)
    rnd = random.Random(seed)
    p, col = [], []
    hw = W / 2
    wall_top = float(entry.get("wall_top", 6.0))
    aw_type = look.get("awning", {}).get("type", "none")
    # a box awning or a verandah covers the band over the windows from the
    # footpath, so the sign goes on a taller band above it where the wall
    # allows (the old pubs' names are up on the parapet anyway)
    lift = {"box": 0.36, "verandah": 0.67, "lace": 0.67}.get(aw_type, 0.14 if aw_type == "canvas" else 0.0)
    raise_top = {"box": 0.36, "verandah": 1.9, "lace": 1.9}.get(aw_type, 0.0)
    # never lower than the shopfront: on a low building it stands up past
    # the roof as a parapet, as plenty of Northbridge's single-storey shops do
    # (a box awning's sign band always gets its extra height, parapet or not)
    floor_top = look.get("height", 3.55) + (raise_top if aw_type == "box" else 0.0)
    top = max(floor_top, min(look.get("height", 3.55) + raise_top, wall_top - 0.1))
    head = min(HEAD, top - 0.45)
    if aw_type in ("verandah", "lace"):
        # from across the street the verandah's roof hides the wall for about
        # a metre over it: go clear of that where the wall is tall enough
        lift = max(lift, min(1.3, top - head - 0.8))
    pil = 0.28 if W > 3.5 else 0.18
    base_lo = g.low(-hw, hw, 0.0, 0.5) - 0.15
    front = look.get("front", "windows")
    sill = {"glass": 0.12, "bifold": 0.08, "pub": 0.85, "arched": 0.7}.get(front, 0.48)
    if front == "door":
        return _plain_door(p, col, M, entry, look, g, W, vid)
    # pilasters, fascia band and the cornice
    for sx in (-1, 1):
        a, b = (-hw, -hw + pil) if sx < 0 else (hw - pil, hw)
        p.append(bx((a, -FIT, base_lo), (b, 0.0, top), M["wall"]))
        if front == "pub":
            p.append(bx((a - 0.03, -FIT - 0.05, base_lo), (b + 0.03, -FIT + 0.01, g.high(a, b) + 0.9), M["tile"]))
            p.append(bx((a - 0.04, -FIT - 0.06, head - 0.12), (b + 0.04, -FIT + 0.01, head), M["wall2"]))  # capital
    p.append(bx((-hw, -FIT, head), (hw, 0.0, top), M["wall"]))
    if look.get("cornice", front == "pub"):
        p.append(bx((-hw - 0.05, -FIT - 0.12, top - 0.14), (hw + 0.05, 0.0, top), M["wall"]))
        p.append(bx((-hw - 0.02, -FIT - 0.06, top - 0.24), (hw + 0.02, 0.0, top - 0.14), M["wall2"]))
    col.append(((-hw, -FIT, base_lo), (hw, 0.0, top)))
    # the room card covers every opening; one picture across the shopfront
    room = (-hw + pil, hw - pil, 0.0, head)
    img = _room_image("room_" + vid, look, room[1] - room[0], room[3] - room[2], seed)
    glow = C.mat("VN_Glow_" + vid, "#ffffff", rough=0.3, image=img, emit="#ffffff", emit_strength=1.0, emit_image=True)
    bays = _bays(look, -hw + pil, hw - pil)
    door_x = []
    for kind_b, a, b in bays:
        lo = g.low(a, b, 0.0, 0.4)
        if kind_b == "window":
            s_top = lo + sill
            p.append(bx((a, -FIT, base_lo), (b, 0.0, s_top), M["wall2"] if front != "pub" else M["tile"]))
            p.append(bx((a - 0.02, -FIT - 0.03, s_top - 0.04), (b + 0.02, -FIT + 0.02, s_top), M["trim"]))   # sill
            # panes: mullions every 1.8 m at most, a transom for a highlight
            n = max(1, int(math.ceil((b - a) / (1.8 if front != "glass" else 2.6))))
            for i in range(n + 1):
                x = a + (b - a) * i / n
                p.append(bx((x - 0.04, -FIT - 0.01, s_top), (x + 0.04, -GLASS + 0.02, head), M["trim"]))
            p.append(bx((a, -FIT - 0.01, head - 0.06), (b, -GLASS + 0.02, head), M["trim"]))
            if look.get("transom", front in ("windows", "pub")) and head - s_top > 1.9:
                p.append(bx((a, -FIT - 0.01, head - 0.5), (b, -GLASS + 0.02, head - 0.44), M["trim"]))
            p.append(_card(img, a, b, s_top, head, room, -GLASS, glow))
            if front == "arched":
                # arch heads: fill the corners over each pane
                for i in range(n):
                    xa, xb = a + (b - a) * i / n, a + (b - a) * (i + 1) / n
                    r = (xb - xa) / 2
                    for k in range(4):
                        t0, t1 = k / 4 * math.pi / 2, (k + 1) / 4 * math.pi / 2
                        for side in (-1, 1):
                            cx = (xa + xb) / 2
                            xin = cx + side * r * math.sin(t1)
                            p.append(bx((min(xin, cx + side * r), -FIT - 0.005, head - r * (1 - math.cos(t0)) + 0.0),
                                        (max(xin, cx + side * r), -GLASS + 0.01, head), M["wall"]))
        elif kind_b in ("door", "open"):
            door_x.append((a + b) / 2)
            p.append(bx((a, -FIT, base_lo), (b, -0.0, lo + 0.02), M["step"]))            # threshold
            p.append(bx((a - 0.02, -FIT - 0.01, head - 0.07), (b + 0.02, -GLASS + 0.02, head), M["trim"]))
            if kind_b == "open":
                # bifolds pushed right back: a stack of folded leaves each end
                for x, sx in ((a, 1), (b, -1)):
                    for k in range(3):
                        lx = x + sx * (0.06 + k * 0.07)
                        p.append(bx((lx - 0.03, -FIT + 0.02, lo + 0.02), (lx + 0.03, -GLASS + 0.03, head - 0.07), M["trim"]))
                p.append(_card(img, a, b, lo + 0.02, head - 0.07, room, -GLASS + 0.04, glow))
                continue
            leaves = 2 if b - a > 1.3 else 1
            for k in range(leaves):
                la = a + (b - a) * k / leaves
                lb = a + (b - a) * (k + 1) / leaves
                fy0, fy1 = -GLASS - 0.06, -GLASS + 0.02
                p.append(bx((la, fy0, lo + 0.02), (lb, fy1, lo + 0.25), M["trim"]))           # kick rail
                p.append(bx((la, fy0, head - 0.12), (lb, fy1, head - 0.07), M["trim"]))
                for x in (la, lb):
                    p.append(bx((x - 0.035, fy0, lo + 0.02), (x + 0.035, fy1, head - 0.07), M["trim"]))
                p.append(_card(img, la + 0.035, lb - 0.035, lo + 0.25, head - 0.12, room, -GLASS - 0.005, glow))
                hx = lb - 0.12 if k == 0 else la + 0.12
                p.append(bx((hx - 0.015, fy0 - 0.05, lo + 0.9), (hx + 0.015, fy0, lo + 1.3), M["brass"]))
            # side reveals of the recess
            for x in (a, b):
                p.append(bx((x - 0.02, -FIT, lo), (x + 0.02, -GLASS, head), M["wall"]))
    # sign over the shopfront
    sign = look.get("sign", {})
    if top - (head + lift) > 0.3:
        _sign(p, M, sign, entry, look, W, head + lift, top, vid)
    # awning or verandah
    aw = look.get("awning", {"type": "none"})
    trees = [o for o in entry.get("obstacles", []) if o[0] != "street_light"]
    poles = entry.get("obstacles", [])
    reach = depth - 0.55
    for o in trees:
        if abs(o[1]) < hw + 1.2:
            reach = min(reach, o[2] - 1.1)
    awd = min(aw.get("depth", 2.2), max(0.0, reach))
    post_lines = []
    if aw["type"] == "canvas" and awd > 0.6:
        _canvas(p, M, aw, hw, head, awd)
    elif aw["type"] == "box" and awd > 0.6:
        awd = min(awd, 1.6)
        bm = _m("Box", aw.get("colour", "#232323"), 0.5, 0.3)
        p.append(bx((-hw - 0.05, -awd, head + 0.08), (hw + 0.05, -FIT, head + 0.32), bm))
        lamp = C.mat("VN_Lamp_" + vid, "#fff2d0", rough=0.4, emit="#ffe2a8", emit_strength=1.0)
        for i in range(max(1, int(W / 1.6))):
            lx = -hw + W * (i + 0.5) / max(1, int(W / 1.6))
            p.append(bx((lx - 0.08, -awd * 0.55 - 0.08, head + 0.07), (lx + 0.08, -awd * 0.55 + 0.08, head + 0.08), lamp))
    elif aw["type"] in ("verandah", "lace") and reach > 1.6:
        vd = min(aw.get("depth", 3.2), reach)
        post_lines = _verandah(p, col, M, aw, entry, look, g, hw, head, top, vd, poles, vid)
        awd = vd
    _apron(p, entry, g)
    # outside: tables, umbrellas, barriers, planters, the board
    seat = look.get("seating", {"type": "none"})
    blocked = [(o[1], o[2]) for o in poles] + [(x, d) for x, d in post_lines]
    _seating(p, col, M, seat, look, entry, g, hw, depth, door_x, blocked, rnd, vid)
    if look.get("festoon"):
        _festoon(p, M, look, entry, g, hw, head, depth, awd, post_lines, vid)
    if look.get("lanterns"):
        _lanterns(p, M, look, hw, head, max(awd, 0.6), vid)
    if look.get("lamps"):
        lamp = C.mat("VN_Lamp_" + vid, "#fff2d0", rough=0.4, emit="#ffe2a8", emit_strength=1.0)
        for x in (-hw + 0.5, hw - 0.5) if W > 4 else (0.0,):
            p.append(bx((x - 0.01, -FIT - 0.35, top - 0.02), (x + 0.01, -FIT, top + 0.02), M["black"]))
            p.append(cyl(0.11, 0.07, (x, -FIT - 0.38, top - 0.04), M["black"], 8, r_top=0.03))
            p.append(cyl(0.09, 0.01, (x, -FIT - 0.38, top - 0.08), lamp, 8))
    if look.get("aframe") and door_x:
        dx = door_x[0] + (0.9 if door_x[0] < hw - 1.2 else -0.9)
        dd = min(1.1, depth - 0.8)
        if dd > 0.6 and not any(math.hypot(dx - bx_, dd - bd) < 0.9 for bx_, bd in blocked):
            p += _aframe(M, dx, dd, g, look.get("board", ["COFFEE", "TODAY"]), seed)
    sockets = {"Door": ((door_x[0] if door_x else 0.0), -0.8, 0.0)}
    return p, sockets, col


def _apron(p, entry, g):
    """Pave the strip of urban verge some tiles leave between the wall and
    the footpath (venues.json's `pave`, how far out each ground column is
    still unpaved) with the footpath's own paving, just above the ground, so
    the tables stand on a forecourt not grass."""
    pave = entry.get("pave")
    if not pave:
        return
    x0 = float(entry["ground_x"][0])
    img = bpy.data.images.load(os.path.join(C.REPO, "map/textures/sidewalk.png"), check_existing=True)
    img.pack()
    mat = C.mat("VN_Pave", "#ffffff", rough=0.95, image=img)
    verts, faces, uvs = [], [], []
    for c in range(len(pave) - 1):
        d1 = max(pave[c], pave[c + 1])
        if d1 <= 0.0:
            continue
        xa, xb = x0 + c * 0.5, x0 + (c + 1) * 0.5
        ds = _steps(0.0, d1, 0.5)
        base = len(verts)
        for d in ds:
            for x in (xa, xb):
                verts.append((x, -d, g(x, d) + 0.025))
                uvs.append((x / UV_PAVE, d / UV_PAVE))
        for i in range(len(ds) - 1):
            a = base + 2 * i
            faces.append((a, a + 2, a + 3, a + 1))
    if not faces:
        return
    o = C.mesh_obj("apron", verts, faces, mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[o.data.loops[li].vertex_index]
    o.data.update()
    for poly in o.data.polygons:
        if poly.normal.z < 0:
            o.data.flip_normals()
        break
    p.append(o)


def _sign(p, M, sign, entry, look, W, head, top, vid):
    text = sign.get("text", entry["name"].upper())
    style = sign.get("style", "painted")
    font = sign.get("font", "sans")
    band = top - head
    if look.get("cornice", look.get("front") == "pub"):
        band -= 0.24
    max_w = min(W - 0.7, sign.get("width", 6.0))
    cz = head + band / 2
    y = -FIT - 0.012
    if style == "painted" or style == "lightbox":
        board = sign.get("board")
        if board or style == "lightbox":
            bm = C.mat("VN_Glow_box_" + vid, board or "#f4efe2", rough=0.5, emit=board or "#f4efe2",
                       emit_strength=1.0) if style == "lightbox" else _m("Board_" + vid, board, 0.7)
            p.append(bx((-max_w / 2 - 0.15, y - 0.03, head + 0.07), (max_w / 2 + 0.15, -FIT, head + band - 0.07), bm))
            y -= 0.035
        ink = _m("Ink_" + vid, sign.get("ink", "#222222"), 0.7)
        p.append(text_mesh(text, font, ink, max_w, band * 0.55, (0, y, cz)))
    elif style == "letters":
        ink = _m("Letters_" + vid, sign.get("ink", "#f1e7cf"), 0.5, 0.2)
        p.append(text_mesh(text, font, ink, max_w, band * 0.55, (0, y - 0.03, cz), depth=0.05))
    elif style == "neon":
        col = sign.get("ink", "#ff5a8a")
        neon = C.mat("VN_Neon_" + vid, col, rough=0.3, emit=col, emit_strength=1.0)
        if sign.get("board"):
            p.append(bx((-max_w / 2 - 0.2, y - 0.02, head + 0.06), (max_w / 2 + 0.2, -FIT, head + band - 0.06),
                        _m("Board_" + vid, sign["board"], 0.7)))
            y -= 0.025
        p.append(text_mesh(text, font, neon, max_w, band * 0.6, (0, y - 0.02, cz), depth=0.03))
    blade = look.get("blade")
    if blade:
        _blade(p, M, blade, W, head, top, vid)


def _blade(p, M, blade, W, head, top, vid):
    """A sign standing out from the wall at one end, read from up and down the street."""
    x = (W / 2 - 0.45) * (1 if blade.get("side", "right") == "right" else -1)
    z0 = head + 0.15
    h = min(1.3, blade.get("height", 1.1))
    out = 1.0
    style = blade.get("style", "lightbox")
    col = blade.get("ink", "#ff5a5a")
    board = blade.get("board", "#1c1c1c")
    if style == "lightbox":
        bm = C.mat("VN_Glow_blade_" + vid, board, rough=0.5, emit=board, emit_strength=1.0)
    else:
        bm = _m("Blade_" + vid, board, 0.7)
    p.append(bx((x - 0.03, -FIT - 0.3, z0 + h * 0.15), (x + 0.03, -FIT, z0 + h * 0.2), M["black"]))
    p.append(bx((x - 0.03, -FIT - 0.3, z0 + h * 0.8), (x + 0.03, -FIT, z0 + h * 0.85), M["black"]))
    p.append(bx((x - 0.06, -FIT - 0.3 - out, z0), (x + 0.06, -FIT - 0.3, z0 + h), bm))
    # a lightbox's letters are film on the lit panel: they glow their own colour
    ink = (C.mat("VN_Neon_blade_" + vid, col, rough=0.3, emit=col, emit_strength=1.0) if style == "neon"
           else C.mat("VN_Glow_bladeink_" + vid, col, rough=0.6, emit=col, emit_strength=1.0) if style == "lightbox"
           else _m("BladeInk_" + vid, col, 0.6))
    text = blade.get("text", "BAR")
    vertical = "\n".join(text) if blade.get("vertical", len(text) <= 5) else text
    for side in (-1, 1):
        o = text_mesh(vertical, blade.get("font", "sans"), ink, out * 0.75, h * 0.85, (0, 0, 0), depth=0.0)
        if o is None:
            continue
        # turn to face ±x: the letters were made facing -y about the origin
        me = o.data
        for v in me.vertices:
            vx, vy, vz = v.co
            # well clear of the panel (0.06 each side), or the wobbling
            # low-res vertices let the panel through the letters
            v.co = (x + side * 0.1, -FIT - 0.3 - out / 2 + (vx if side > 0 else -vx),
                    z0 + h / 2 + vz)
        me.update()
        _face_x(o, side)
        p.append(o)


def _face_x(ob, side):
    me = ob.data
    me.update()
    for poly in me.polygons:
        if abs(poly.normal.x) > 0.9:
            if (poly.normal.x > 0) != (side > 0):
                me.flip_normals()
            break


def _canvas(p, M, aw, hw, head, d):
    """A sloping canvas awning on two arms, striped or plain, with a valance."""
    c1 = _m("Canvas", aw.get("colour", "#3f5f4a"), 0.95)
    c2 = _m("Canvas2", aw["stripe"], 0.95) if aw.get("stripe") else c1
    z_wall, z_out = head + 0.1, head - 0.36   # tucked under the sign band
    stripe = 0.3
    n = max(1, int(round(2 * hw / stripe)))
    for i in range(n):
        x0, x1 = -hw + 2 * hw * i / n, -hw + 2 * hw * (i + 1) / n
        mat = c1 if i % 2 == 0 else c2
        v = [(x0, -FIT, z_wall), (x1, -FIT, z_wall), (x1, -d, z_out), (x0, -d, z_out)]
        p.append(C.mesh_obj("cv", v, [(0, 3, 2, 1), (0, 1, 2, 3)], mat))
        v = [(x0, -d, z_out), (x1, -d, z_out), (x1, -d, z_out - 0.25), (x0, -d, z_out - 0.25)]
        p.append(C.mesh_obj("vl", v, [(0, 1, 2, 3), (3, 2, 1, 0)], mat))
    for sx in (-1, 1):
        x = sx * (hw - 0.15)
        arm = C.cylinder("arm", 0.015, math.hypot(d - FIT, z_wall - 0.9 - z_out), segs=4, material=M["steel"])
        ang = math.atan2(z_wall - 0.9 - z_out, d - FIT)
        arm.rotation_euler = (math.pi / 2 - ang, 0, 0)
        arm.location = (x, -(d + FIT) / 2, (z_wall - 0.9 + z_out) / 2)
        p.append(arm)


def _verandah(p, col, M, aw, entry, look, g, hw, head, top, vd, poles, vid):
    """A flat-ish verandah over the footpath on posts near the kerb, with a
    fascia board (its sign) and, for the old pubs, cast-iron lace between the
    posts. Returns the posts' (x, d)."""
    roof = _m("Verandah", aw.get("colour", "#d7d9d5"), 0.5, 0.4)
    post = _m("Post", aw.get("post", look["trim"]), 0.6)
    zr = min(top + 0.05, head + 0.55)
    z_out = zr - 0.25
    p.append(bx((-hw, -vd, z_out), (hw, -FIT, z_out + 0.06), roof))
    # corrugations: a few ribs
    for i in range(int(2 * hw / 0.25)):
        x = -hw + 0.12 + i * 0.25
        p.append(bx((x - 0.02, -vd, z_out + 0.06), (x + 0.02, -FIT, z_out + 0.085), roof))
    p.append(bx((-hw - 0.03, -vd - 0.06, z_out - 0.28), (hw + 0.03, -vd + 0.02, z_out + 0.1), post))   # beam / fascia
    n = max(2, int(math.ceil(2 * hw / 3.4)) + 1)
    xs = [-hw + 0.15 + (2 * hw - 0.3) * i / (n - 1) for i in range(n)]
    out = []
    for x in xs:
        # step a post off a tree or pole in its way
        for o in poles:
            if abs(o[2] - (vd - 0.12)) < 0.9 and abs(o[1] - x) < 0.7:
                x = o[1] + (0.75 if x > o[1] else -0.75)
        x = max(-hw + 0.1, min(hw - 0.1, x))
        d = vd - 0.12
        z = g(x, d)
        p.append(bx((x - 0.06, -d - 0.06, z - 0.2), (x + 0.06, -d + 0.06, z_out - 0.28), post))
        p.append(bx((x - 0.1, -d - 0.1, z - 0.05), (x + 0.1, -d + 0.1, z + 0.12), post))
        col.append(((x - 0.06, -d - 0.06, z - 0.2), (x + 0.06, -d + 0.06, z_out)))
        out.append((x, d))
    if aw["type"] == "lace":
        # cast-iron lace frieze under the beam and brackets at each post
        for i in range(len(out) - 1):
            x0, x1 = out[i][0] + 0.08, out[i + 1][0] - 0.08
            k = int((x1 - x0) / 0.2)
            for j in range(k):
                xa = x0 + (x1 - x0) * j / k
                p.append(bx((xa, -vd + 0.03, z_out - 0.55), (xa + 0.025, -vd + 0.06, z_out - 0.28), post))
            p.append(bx((x0, -vd + 0.03, z_out - 0.57), (x1, -vd + 0.06, z_out - 0.53), post))
        for x, d in out:
            for sx in (-1, 1):
                for k in range(3):
                    p.append(bx((x + sx * (0.06 + k * 0.08) - 0.02, -d - 0.03, z_out - 0.3 - (2 - k) * 0.12),
                                (x + sx * (0.06 + k * 0.08) + 0.02, -d + 0.03, z_out - 0.28), post))
    # the name on the verandah's fascia, both faces
    vs = aw.get("sign")
    if vs:
        ink = _m("VerInk_" + vid, vs.get("ink", "#f0e4c4"), 0.6)
        o = text_mesh(vs.get("text", entry["name"].upper()), vs.get("font", "serif"), ink,
                      min(2 * hw - 0.6, 7.0), 0.24, (0, -vd - 0.065, z_out - 0.09))
        p.append(o)
    return out


def _seating(p, col, M, seat, look, entry, g, hw, depth, door_x, blocked, rnd, vid):
    kind = seat.get("type", "none")
    if kind == "none" or depth < 2.0:
        return
    chair = _m("Chair_" + vid, seat.get("chair", "#9ea2a3"), 0.5, 0.5 if seat.get("chair") is None else 0.0)
    table = _m("Table_" + vid, seat.get("table", "#e9e5dc"), 0.5)
    rows = []
    d_wall = 0.75 if kind not in ("bench",) else 0.45
    if kind in ("picnic",):
        d_wall = 1.0
    if depth >= 3.0:
        rows.append(d_wall)
    if seat.get("rows", 1) >= 2 and depth >= 5.5:
        rows.append(depth - 1.25)
    if not rows:
        return
    span = {"bistro": 1.7, "square": 1.9, "high": 1.75, "barrel": 1.6, "picnic": 2.6, "bench": 3.0}[kind]
    um = _m("Umbrella_" + vid, seat["umbrella"], 0.95) if seat.get("umbrella") else None
    for ri, d in enumerate(rows):
        n = int((2 * hw - 0.4) / span)
        xs = [-hw + 0.2 + span * (i + 0.5) + ((2 * hw - 0.4) - n * span) / 2 for i in range(n)]
        if kind == "bench" and ri == 0:
            segs = []
            lo = -hw + 0.3
            for dx in sorted(door_x):
                if dx - 0.75 - lo > 1.2:
                    segs.append((lo, dx - 0.75))
                lo = dx + 0.75
            if hw - 0.3 - lo > 1.2:
                segs.append((lo, hw - 0.3))
            for a, b in segs:
                p += _bench_set(M, table, a, b, d, g)
            continue
        placed = []
        for x in xs:
            half = span / 2 - 0.1
            if ri == 0 and any(abs(x - dx) < half + 0.55 for dx in door_x):
                continue
            if any(abs(x - bx_) < half + 0.35 and abs(d - bd) < 1.1 for bx_, bd in blocked):
                continue
            k = kind if not (kind == "bench" and ri > 0) else "bistro"
            if k == "bistro":
                p += _bistro_set(M, chair, table, x, d, g)
            elif k == "square":
                p += _square_set(M, chair, table, x, d, g)
            elif k == "high":
                p += _high_set(M, table, x, d, g)
            elif k == "barrel":
                p += _barrel_set(M, x, d, g)
            elif k == "picnic":
                p += _picnic_set(M, x, d, g)
            z = g(x, d)
            col.append(((x - 0.35, -d - 0.35, z), (x + 0.35, -d + 0.35, z + 0.75)))
            placed.append(x)
        if um is not None and (ri == len(rows) - 1):
            for x in placed[::1 if kind in ("square", "picnic") else 2]:
                if not any(math.hypot(x - bx_, d - bd) < 1.6 and bd > d - 0.5 for bx_, bd in blocked
                           if (bx_, bd) in [(o[1], o[2]) for o in entry.get("obstacles", []) if o[0] != "street_light"]):
                    p += _umbrella(M, um, x, d, g)
    # barriers along the outer edge of the seating
    if seat.get("barrier") and rows:
        bm = _m("Barrier_" + vid, seat["barrier"], 0.95)
        d = rows[-1] + (0.85 if kind != "picnic" else 1.1)
        if d < depth - 0.4:
            x0, x1 = -hw + 0.2, hw - 0.2
            gaps = [dx for dx in door_x] if len(rows) == 1 else []
            cuts = sorted([(dx - 0.7, dx + 0.7) for dx in gaps])
            segs, lo = [], x0
            for a, b in cuts:
                if a - lo > 0.8:
                    segs.append((lo, a))
                lo = max(lo, b)
            if x1 - lo > 0.8:
                segs.append((lo, x1))
            for a, b in segs:
                for x in _steps(a, b, 1.6):
                    z = g(x, d)
                    p.append(cyl(0.02, 0.95, (x, -d, z + 0.475), M["steel"], 5))
                    p.append(cyl(0.12, 0.02, (x, -d, z + 0.01), M["steel"], 6))
                xs_ = _steps(a, b, 1.6)
                for xa, xb in zip(xs_, xs_[1:]):
                    za, zb = g(xa, d), g(xb, d)
                    zc = min(za, zb)
                    p.append(bx((xa + 0.02, -d - 0.005, zc + 0.2), (xb - 0.02, -d + 0.005, zc + 0.85), bm))
                col.append(((a, -d - 0.05, g(a, d)), (b, -d + 0.05, g(a, d) + 0.9)))
    if look.get("planters") and rows:
        d = rows[0]
        for x in (-hw + 0.55, hw - 0.55):
            if any(abs(x - dx) < 1.0 for dx in door_x):
                continue
            if any(math.hypot(x - bx_, d - bd) < 0.8 for bx_, bd in blocked):
                continue
            p += _planter(M, x, 0.3, g, 0.7, seed=int(abs(x) * 10))


def _festoon(p, M, look, entry, g, hw, head, depth, awd, post_lines, vid):
    """Strings of bulbs over the tables: from the fascia to poles at the kerb
    edge (or along a verandah's beam), sagging between hooks."""
    bulb = C.mat("VN_Bulb_" + vid, "#fff0c8", rough=0.4, emit="#ffd890", emit_strength=1.0)
    wire = M["black"]
    runs = []
    if post_lines:
        pts = [(x, d, head + 0.25) for x, d in post_lines]
        runs.append(pts)
    else:
        # hooked under the sign (or on a canvas awning's front edge, so the
        # bulbs never cross the lettering), rising out to poles at the kerb
        canvas = look.get("awning", {}).get("type") == "canvas" and awd > 0.6
        d_in, z_in = (awd, head - 0.3) if canvas else (FIT + 0.05, head + 0.05)
        d_out = min(depth - 0.7, max(3.4, d_in + 1.6))
        if d_out < max(1.5, d_in + 0.9):
            return
        z_top = head + 0.1
        pole_xs = [-hw + 0.3, hw - 0.3]
        pole_pts = []
        for x in pole_xs:
            z = g(x, d_out)
            p.append(cyl(0.035, z_top + 0.2 - z, (x, -d_out, (z_top + 0.2 + z) / 2), M["black"], 6))
            pole_pts.append((x, d_out, z_top))
        # zigzag: wall, pole, wall, pole...
        n = max(2, int(2 * hw / 1.5))
        zig = []
        for i in range(n + 1):
            x = -hw + 0.3 + (2 * hw - 0.6) * i / n
            zig.append((x, d_in, z_in) if i % 2 == 0 else (x, d_out, z_top - 0.05))
        runs.append(zig)
        runs.append(pole_pts)
    for pts in runs:
        for (x0, d0, z0), (x1, d1, z1) in zip(pts, pts[1:]):
            L = math.hypot(x1 - x0, d1 - d0)
            k = max(2, int(L / 0.45))
            sag = min(0.45, 0.08 * L)
            prev = None
            for j in range(k + 1):
                t = j / k
                x, d = x0 + (x1 - x0) * t, d0 + (d1 - d0) * t
                z = z0 + (z1 - z0) * t - sag * 4 * t * (1 - t)
                if prev is not None:
                    seg = (x - prev[0], -(d - prev[1]), z - prev[2])
                    ln = math.sqrt(sum(c * c for c in seg))
                    if ln > 1e-3:
                        p.append(bx((min(x, prev[0]) - 0.006, -max(d, prev[1]) - 0.006, min(z, prev[2]) - 0.006),
                                    (max(x, prev[0]) + 0.006, -min(d, prev[1]) + 0.006, max(z, prev[2]) + 0.006), wire)
                                 if ln < 0.02 else _wire(prev, (x, d, z), wire))
                if 0 < j < k:
                    p.append(C.sphere("bulb", 0.045, (x, -d, z - 0.06), bulb, segs=5, rings=3))
                prev = (x, d, z)


def _wire(a, b, mat):
    (x0, d0, z0), (x1, d1, z1) = a, b
    ln = math.sqrt((x1 - x0) ** 2 + (d1 - d0) ** 2 + (z1 - z0) ** 2)
    o = C.cylinder("wire", 0.006, ln, segs=3, material=mat)
    from mathutils import Vector
    direction = Vector((x1 - x0, -(d1 - d0), z1 - z0)).normalized()
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = direction.to_track_quat("Z", "Y")
    o.location = ((x0 + x1) / 2, -(d0 + d1) / 2, (z0 + z1) / 2)
    return o


def _lanterns(p, M, look, hw, head, d, vid):
    """Red paper lanterns along the front, hung under the awning's edge."""
    col = look.get("lanterns") if isinstance(look.get("lanterns"), str) else "#c8302a"
    lm = C.mat("VN_Bulb_lantern_" + vid, col, rough=0.8, emit=col, emit_strength=1.0)
    gold = M["brass"]
    n = max(2, int(2 * hw / 1.2))
    dd = min(d, 1.0) - 0.15
    for i in range(n):
        x = -hw + 2 * hw * (i + 0.5) / n
        z = head - 0.3
        p.append(cyl(0.006, 0.35, (x, -dd, z + 0.4), M["black"], 3))
        p.append(C.sphere("lantern", 0.2, (x, -dd, z), lm, segs=8, rings=5, scale=(1, 1, 1.15)))
        p.append(cyl(0.09, 0.04, (x, -dd, z + 0.22), gold, 8))
        p.append(cyl(0.09, 0.04, (x, -dd, z - 0.22), gold, 8))
        p.append(cyl(0.01, 0.18, (x, -dd, z - 0.33), lm, 4))


def _plain_door(p, col, M, entry, look, g, W, vid):
    """No sign, no window: a steel door in a painted frame off a lane, a
    bulkhead lamp over it and a step worn in front. You'd walk past it."""
    hw = W / 2
    lo = g.low(-hw, hw, 0.0, 0.5)
    steel = _m("DoorSteel", look.get("door_colour", "#3c3f3e"), 0.55, 0.5)
    dw, dh = 0.95, 2.15
    p.append(bx((-hw, -0.12, lo - 0.2), (hw, 0.0, lo + dh + 0.35), M["wall"]))
    p.append(bx((-dw / 2 - 0.06, -0.16, lo), (dw / 2 + 0.06, -0.11, lo + dh + 0.06), M["trim"]))
    p.append(bx((-dw / 2, -0.15, lo + 0.01), (dw / 2, -0.13, lo + dh), steel))
    for z in (0.5, 1.6):
        p.append(bx((-dw / 2 + 0.06, -0.155, lo + z), (dw / 2 - 0.06, -0.15, lo + z + 0.02), M["trim"]))
    p.append(bx((dw / 2 - 0.16, -0.19, lo + 1.0), (dw / 2 - 0.1, -0.15, lo + 1.12), M["steel"]))   # pull handle
    p.append(bx((-0.12, -0.155, lo + 1.5), (0.12, -0.15, lo + 1.58), M["black"]))                   # peephole slot
    p.append(bx((-dw / 2 - 0.1, -0.45, lo - 0.2), (dw / 2 + 0.1, -0.11, lo + 0.06), M["step"]))
    lamp = C.mat("VN_Lamp_" + vid, "#fff2d0", rough=0.4, emit="#ffd890", emit_strength=1.0)
    p.append(bx((-0.12, -0.3, lo + dh + 0.18), (0.12, -0.12, lo + dh + 0.32), M["black"]))
    p.append(bx((-0.09, -0.31, lo + dh + 0.2), (0.09, -0.29, lo + dh + 0.3), lamp))
    col.append(((-hw, -0.16, lo - 0.2), (hw, 0.0, lo + dh + 0.35)))
    return p, {"Door": (0.0, -0.8, 0.0)}, col
