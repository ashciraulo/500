"""Home studio gear for bedroom 2: guitars, amps, pedals, synths, a drum kit
and band posters. Low poly, no maker logos; the posters are original
designs that only carry the band names.

Guitars and posters face -Y with their backs on the wall plane y=0; the
other pieces stand on the floor about their origin."""
import math

import bmesh

from . import common as C
from . import textures as TX
from .furniture import M, bx, cyl


def _mat(name, color, rough=0.5, metal=0.0):
    return C.mat("S_" + name, color, rough=rough, metal=metal)


def _slab(points, y0, y1, mat, name="slab"):
    """Extrude an outline in the XZ plane between y0 and y1."""
    n = len(points)
    verts = [(x, y0, z) for x, z in points] + [(x, y1, z) for x, z in points]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    o = C.mesh_obj(name, verts, faces, mat)
    # outward normals whichever way the outline winds
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def _scaled(points, k, about):
    return [(about[0] + (x - about[0]) * k, about[1] + (z - about[1]) * k) for x, z in points]


# ------------------------------------------------------------------ guitars

# body outlines, neck up, viewed from the front (bass side on -X); the neck
# joins between x = +-0.03 at the top of each outline
TELE = [(-0.11, 0.0), (0.11, 0.0), (0.155, 0.05), (0.16, 0.14), (0.135, 0.21), (0.14, 0.27), (0.12, 0.31),
        (0.06, 0.32), (0.03, 0.33), (0.03, 0.40), (-0.03, 0.40), (-0.07, 0.41), (-0.12, 0.38), (-0.14, 0.31),
        (-0.135, 0.21), (-0.16, 0.14), (-0.155, 0.05)]
OFFSET = [(0.05, 0.0), (0.14, 0.03), (0.18, 0.10), (0.17, 0.18), (0.135, 0.25), (0.15, 0.33), (0.165, 0.40),
          (0.14, 0.44), (0.08, 0.43), (0.03, 0.41), (0.03, 0.47), (-0.03, 0.47), (-0.06, 0.48), (-0.11, 0.50),
          (-0.15, 0.46), (-0.15, 0.38), (-0.12, 0.29), (-0.16, 0.20), (-0.185, 0.11), (-0.16, 0.03), (-0.07, -0.01)]
BASS = [(0.05, 0.0), (0.13, 0.03), (0.165, 0.10), (0.155, 0.18), (0.12, 0.25), (0.13, 0.33), (0.15, 0.42),
        (0.125, 0.46), (0.07, 0.43), (0.03, 0.40), (0.03, 0.47), (-0.03, 0.47), (-0.06, 0.49), (-0.11, 0.53),
        (-0.145, 0.49), (-0.14, 0.40), (-0.11, 0.30), (-0.15, 0.21), (-0.17, 0.11), (-0.15, 0.03), (-0.07, -0.01)]

GUITARS = {
    # Squier 40th Anniversary Telecaster, Gold Edition: gold anodised
    # pickguard and gold hardware, maple neck
    "tele": dict(outline=TELE, body=("#2f5f9e", 0.3, 0.2), guard="#c9a24a", board="#d9b47a", neck_len=0.47,
                 pickups="tele", hardware="gold", tuners=6),
    # Squier J Mascis Jazzmaster: vintage white, gold anodised pickguard
    "jazzmaster": dict(outline=OFFSET, body=("#ece2c6", 0.35, 0.0), guard="#c9a24a", board="#4a2c1e",
                       neck_len=0.48, pickups="soapbar", hardware="chrome", tuners=6),
    # Squier Affinity Jazz Bass in black, white pickguard
    "jbass": dict(outline=BASS, body=("#121212", 0.3, 0.0), guard="#efece4", board="#4a2c1e", neck_len=0.66,
                  pickups="jbass", hardware="chrome", tuners=4),
}


def guitar(kind):
    """Wall-hung guitar: back on y=0, facing -Y, bottom of the body at z=0."""
    g = GUITARS[kind]
    col, rough, metal = g["body"]
    t = 0.045
    y0, y1 = -0.008 - t, -0.008                # 8 mm off the wall
    hw = _mat("gold" if g["hardware"] == "gold" else "chrome",
              "#d2ab52" if g["hardware"] == "gold" else "#d6d8da", rough=0.25, metal=0.9)
    parts = [_slab(g["outline"], y0, y1, _mat(kind + "_body", col, rough, metal), "body")]
    top = max(z for _, z in g["outline"])
    # pickguard: the outline shrunk about a point in the upper body
    about = (0.0, top * 0.62)
    parts.append(_slab(_scaled(g["outline"], 0.72, about), y0 - 0.003, y0, _mat(kind + "_guard", g["guard"], 0.4,
                                                                                  0.6 if g["guard"] == "#c9a24a" else 0.0)))
    # neck, fretboard, headstock, tuners
    nl = g["neck_len"]
    zj = top - 0.07
    parts.append(bx((-0.026, y0 + 0.005, zj), (0.026, y1 - 0.01, zj + nl), _mat("maple", "#d9b47a", 0.5)))
    parts.append(bx((-0.027, y0 - 0.006, zj + 0.02), (0.027, y0 + 0.005, zj + nl), _mat(kind + "_board", g["board"], 0.6)))
    for i in range(1, 9):
        z = zj + nl - nl * (1 - 0.5 ** (i / 6.0)) * 1.6
        if zj + 0.05 < z < zj + nl - 0.02:
            parts.append(bx((-0.027, y0 - 0.008, z), (0.027, y0 - 0.006, z + 0.003), hw))
    zh = zj + nl
    hs = 0.2 if kind == "jbass" else 0.17
    parts.append(_slab([(-0.03, zh), (0.03, zh), (0.045, zh + hs * 0.4), (0.04, zh + hs), (-0.035, zh + hs),
                        (-0.05, zh + hs * 0.6)], y0 + 0.012, y1 - 0.012, _mat("maple", "#d9b47a", 0.5), "head"))
    n = g["tuners"]
    for i in range(n):
        z = zh + 0.03 + i * (hs - 0.05) / max(1, n - 1)
        parts.append(cyl(0.008, 0.03, (-0.045 - 0.012, y0 + 0.02, z), hw, 6, axis="X"))
    # pickups and bridge
    pz = {"tele": [(0.08, "bridge"), (0.25, "neck_cover")], "soapbar": [(0.12, "soap"), (0.27, "soap")],
          "jbass": [(0.11, "jb"), (0.24, "jb")]}[g["pickups"]]
    for z, kindp in pz:
        if kindp == "bridge":
            parts.append(bx((-0.05, y0 - 0.008, z - 0.04), (0.05, y0 - 0.003, z + 0.05), hw))
            parts.append(bx((-0.035, y0 - 0.014, z + 0.01), (0.035, y0 - 0.008, z + 0.035), _mat("pickup_black", "#151515")))
        elif kindp == "neck_cover":
            parts.append(bx((-0.035, y0 - 0.012, z - 0.015), (0.035, y0 - 0.003, z + 0.015), hw))
        elif kindp == "soap":
            parts.append(bx((-0.045, y0 - 0.012, z - 0.02), (0.045, y0 - 0.003, z + 0.02), _mat("pickup_cream", "#efe6cc", 0.5)))
        else:
            parts.append(bx((-0.05, y0 - 0.012, z - 0.012), (0.05, y0 - 0.003, z + 0.012), _mat("pickup_black", "#151515")))
    parts.append(bx((-0.045, y0 - 0.01, 0.03), (0.045, y0 - 0.003, 0.06), hw))          # tailpiece/bridge
    for i, (x, z) in enumerate(((0.095, 0.07), (0.11, 0.12), (0.12, 0.17))[: (2 if kind == "tele" else 3)]):
        parts.append(cyl(0.012, 0.018, (x, y0 - 0.012, z), _mat("knob", "#1a1a1a", 0.4), 8, axis="Y"))
    # wall hanger under the headstock
    parts.append(bx((-0.03, -0.01, zh - 0.02), (0.03, 0.0, zh + 0.06), M("wood_dark")))
    parts.append(cyl(0.006, 0.06, (0, y0 + 0.03, zh - 0.01), M("black"), 5, axis="Y"))
    return parts


def guitar_height(kind):
    g = GUITARS[kind]
    top = max(z for _, z in g["outline"])
    return top - 0.07 + g["neck_len"] + (0.2 if kind == "jbass" else 0.17)


# ------------------------------------------------------------------ amps and pedals

def guitar_combo():
    """Blackface style 1x12 combo: black tolex, silver grille, faces -Y."""
    w, d, h = 0.6, 0.26, 0.5
    tolex = _mat("tolex", "#151515", 0.9)
    parts = [bx((-w / 2, -d / 2, 0.03), (w / 2, d / 2, h), tolex),
             bx((-w / 2 + 0.03, -d / 2 - 0.004, 0.06), (w / 2 - 0.03, -d / 2, h - 0.14), _mat("grille_silver", "#b9b6aa", 0.9)),
             bx((-w / 2 + 0.02, -d / 2 - 0.004, h - 0.12), (w / 2 - 0.02, -d / 2, h - 0.02), _mat("panel_black", "#1c1c1c", 0.4)),
             bx((-0.08, -0.02, h), (0.08, 0.02, h + 0.03), tolex)]                       # handle
    for i in range(7):
        parts.append(cyl(0.01, 0.015, (-0.2 + i * 0.055, -d / 2 - 0.008, h - 0.07), _mat("knob_silver", "#cfcfcf", 0.3, 0.8), 8, axis="Y"))
    parts.append(cyl(0.008, 0.004, (0.25, -d / 2 - 0.006, h - 0.07), _mat("jewel", "#d22a1e", 0.3), 6, axis="Y"))
    for sx in (-1, 1):
        parts.append(bx((sx * (w / 2 - 0.05) - 0.03, -d / 2 + 0.02, 0), (sx * (w / 2 - 0.05) + 0.03, d / 2 - 0.02, 0.03), M("black")))
    return parts


def bass_rig():
    """Bass head on a 2x10 cab, faces -Y."""
    tolex = _mat("tolex", "#151515", 0.9)
    parts = [bx((-0.3, -0.2, 0.04), (0.3, 0.2, 0.62), tolex),
             bx((-0.27, -0.204, 0.08), (0.27, -0.2, 0.58), _mat("grille_dark", "#2a2a2a", 1.0)),
             bx((-0.28, -0.13, 0.62), (0.28, 0.13, 0.8), tolex),
             bx((-0.26, -0.134, 0.65), (0.26, -0.13, 0.77), _mat("plate_silver", "#b0b2b4", 0.3, 0.8))]
    for i in range(8):
        parts.append(cyl(0.009, 0.012, (-0.2 + i * 0.055, -0.14, 0.71), M("black"), 8, axis="Y"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(cyl(0.025, 0.04, (sx * 0.24, sy * 0.15, 0.02), M("black"), 6))
    return parts


def big_muff():
    """Silver fuzz box with three knobs and a footswitch, red and black print."""
    parts = [bx((-0.07, -0.09, 0), (0.07, 0.09, 0.055), _mat("muff_silver", "#c8c8c4", 0.35, 0.6)),
             bx((-0.06, -0.02, 0.055), (0.06, 0.07, 0.056), _mat("muff_red", "#c41e1e", 0.6)),
             bx((-0.06, -0.08, 0.055), (0.06, -0.03, 0.056), M("black"))]
    for x in (-0.04, 0, 0.04):
        parts.append(cyl(0.011, 0.018, (x, 0.04, 0.064), M("black"), 8))
    parts.append(cyl(0.01, 0.015, (0, -0.055, 0.064), M("chrome"), 8))
    return parts


def pedalboard():
    """Board with the Big Muff, a tuner and a delay, patch cables between."""
    parts = [bx((-0.3, -0.16, 0), (0.3, 0.16, 0.04), M("black"))]
    for p in big_muff():
        p.location = (p.location[0] + 0.15, p.location[1], p.location[2] + 0.04)
        parts.append(p)
    for x, col in ((-0.05, "#2f6aa8"), (-0.19, "#1e1e1e")):
        parts.append(bx((x - 0.04, -0.065, 0.04), (x + 0.04, 0.065, 0.09), _mat("pedal_" + col[1:], col, 0.4)))
        parts.append(cyl(0.009, 0.012, (x, 0.03, 0.096), M("black"), 8))
        parts.append(cyl(0.009, 0.012, (x, -0.04, 0.096), M("chrome"), 8))
    for x0, x1 in ((-0.15, -0.09), (-0.01, 0.08)):
        parts.append(bx((x0, 0.0, 0.05), (x1, 0.012, 0.062), M("black")))
    return parts


# ------------------------------------------------------------------ synths

def _keys(x0, x1, y0, y1, z, octaves):
    whites = octaves * 7 + 1
    kw = (x1 - x0) / whites
    parts = [bx((x0, y0, z), (x1, y1, z + 0.02), _mat("ivory", "#f1ede2", 0.5))]
    for i in range(1, whites):
        parts.append(bx((x0 + i * kw - 0.0015, y0 - 0.001, z + 0.008), (x0 + i * kw + 0.0015, y1, z + 0.0205), _mat("key_gap", "#8d877a", 0.8)))
    for i in range(whites - 1):
        if i % 7 in (2, 6):
            continue
        cx = x0 + (i + 1) * kw
        parts.append(bx((cx - kw * 0.3, y0 + (y1 - y0) * 0.4, z + 0.02), (cx + kw * 0.3, y1, z + 0.035), _mat("ebony", "#131313", 0.4)))
    return parts


def poly_synth():
    """Silver-panelled 61 key polysynth with coloured sliders, faces -Y."""
    w, d = 0.98, 0.34
    parts = [bx((-w / 2, -d / 2, 0), (w / 2, d / 2, 0.1), _mat("synth_black", "#1b1b1b", 0.5)),
             bx((-w / 2 + 0.03, -0.01, 0.1), (w / 2 - 0.03, d / 2 - 0.02, 0.105), _mat("synth_silver", "#b8b9b6", 0.4, 0.5))]
    parts += _keys(-w / 2 + 0.06, w / 2 - 0.03, -d / 2 + 0.01, -0.02, 0.06, 5)
    cols = ["#d23a2a", "#e6c23a", "#e88a2a", "#3a7bd2", "#efefef"]
    for i in range(26):
        x = -w / 2 + 0.06 + i * 0.034
        parts.append(bx((x, 0.05, 0.105), (x + 0.012, 0.075, 0.125), _mat("slider_%d" % (i // 6), cols[(i // 6) % 5], 0.5)))
    for sx in (-1, 1):
        parts.append(bx((sx * w / 2 - (0.025 if sx > 0 else 0), -d / 2, 0), (sx * w / 2 + (0 if sx > 0 else 0.025), d / 2, 0.11), M("wood_dark")))
    return parts


def mono_synth():
    """Wood-cheeked monosynth with a tilted knob panel, faces -Y."""
    w, d = 0.72, 0.42
    wood = M("wood_mid")
    parts = [bx((-w / 2 + 0.03, -d / 2, 0), (w / 2 - 0.03, d / 2, 0.08), _mat("synth_black", "#1b1b1b", 0.5))]
    parts += _keys(-w / 2 + 0.12, w / 2 - 0.05, -d / 2 + 0.01, -0.02, 0.05, 3)
    panel = bx((-w / 2 + 0.03, -0.0, 0.0), (w / 2 - 0.03, 0.03, 0.22), _mat("synth_black", "#1b1b1b", 0.5))
    panel.rotation_euler = (math.radians(-35), 0, 0)
    panel.location = (0, 0.02, 0.08)
    parts.append(panel)
    for i in range(18):
        x = -w / 2 + 0.08 + (i % 9) * 0.065
        z = 0.12 + (i // 9) * 0.08
        k = cyl(0.014, 0.02, (x, 0.0, 0.0), M("black"), 8, axis="Y")
        k.location = (x, 0.02 + (z - 0.08) * math.tan(math.radians(35)) - 0.012, z)
        parts.append(k)
    for sx in (-1, 1):
        parts.append(_slab([(-d / 2, 0), (d / 2, 0), (d / 2, 0.27), (0.0, 0.12), (-d / 2, 0.1)], -0.015, 0.015, wood, "cheek"))
        c = parts[-1]
        c.rotation_euler = (0, 0, math.radians(90))
        c.location = (sx * (w / 2 - 0.015), 0, 0)
    return parts


def keyboard_stand(w=0.9, h=0.75):
    """Double-braced X stand, keyboard sits at h."""
    parts = []
    for sx in (-1, 1):
        for a in (-1, 1):
            leg = bx((-0.015, -0.015, -0.47), (0.015, 0.015, 0.47), M("black"))
            leg.rotation_euler = (math.radians(a * 38), 0, 0)
            leg.location = (sx * (w / 2 - 0.12), 0, h / 2)
            parts.append(leg)
        parts.append(bx((sx * (w / 2 - 0.12) - 0.02, -0.18, h - 0.02), (sx * (w / 2 - 0.12) + 0.02, 0.18, h), M("black")))
    return parts


# ------------------------------------------------------------------ drums

def drum_kit(shell="#e9e6dc"):
    """Five-piece kit with hi-hat, crash and ride. The drummer sits at +Y,
    the kick faces -Y."""
    sh = _mat("drum_shell", shell, 0.35)
    head = _mat("drum_head", "#f1efe6", 0.7)
    chrome = M("chrome")
    brass = _mat("cymbal", "#c79a3a", 0.3, 0.9)
    parts = []
    # kick on its side
    parts.append(cyl(0.27, 0.42, (0, -0.15, 0.28), sh, 12, axis="Y"))
    parts.append(cyl(0.255, 0.005, (0, -0.363, 0.28), _mat("kick_reso", "#1a1a1a", 0.6), 12, axis="Y"))
    for sx in (-1, 1):
        parts.append(bx((sx * 0.22 - 0.01, -0.33, 0), (sx * 0.22 + 0.01, -0.3, 0.12), chrome))
    # rack tom on the kick, floor tom right, snare left
    parts.append(cyl(0.15, 0.2, (0.05, -0.08, 0.68), sh, 10))
    parts.append(cyl(0.148, 0.005, (0.05, -0.08, 0.782), head, 10))
    parts.append(cyl(0.2, 0.36, (0.45, 0.1, 0.38), sh, 12))
    parts.append(cyl(0.198, 0.005, (0.45, 0.1, 0.562), head, 12))
    for a in range(3):
        ang = a * 2 * math.pi / 3
        parts.append(bx((0.45 + 0.21 * math.cos(ang) - 0.008, 0.1 + 0.21 * math.sin(ang) - 0.008, 0),
                        (0.45 + 0.21 * math.cos(ang) + 0.008, 0.1 + 0.21 * math.sin(ang) + 0.008, 0.25), chrome))
    parts.append(cyl(0.18, 0.14, (-0.32, 0.12, 0.6), _mat("snare", "#d8d8d8", 0.25, 0.7), 12))
    parts.append(cyl(0.178, 0.005, (-0.32, 0.12, 0.672), head, 12))
    parts.append(cyl(0.012, 0.53, (-0.32, 0.12, 0.265), chrome, 6))
    # hi-hat
    parts.append(cyl(0.012, 0.92, (-0.6, -0.05, 0.46), chrome, 6))
    parts.append(cyl(0.18, 0.006, (-0.6, -0.05, 0.9), brass, 12))
    parts.append(cyl(0.18, 0.006, (-0.6, -0.05, 0.92), brass, 12))
    # crash (left) and ride (right) on stands, slightly tilted
    for x, y, z, r in ((-0.4, -0.38, 1.3, 0.2), (0.62, -0.3, 1.15, 0.24)):
        parts.append(cyl(0.012, z, (x, y, z / 2), chrome, 6))
        c = cyl(r, 0.006, (0, 0, 0), brass, 14)
        c.rotation_euler = (math.radians(12), math.radians(-10 if x < 0 else 10), 0)
        c.location = (x, y, z)
        parts.append(c)
        for a in range(3):
            ang = a * 2 * math.pi / 3 + 0.4
            leg = bx((-0.008, -0.008, -0.36), (0.008, 0.008, 0), chrome)
            leg.rotation_euler = (0, math.radians(30), ang)
            leg.location = (x, y, 0.32)
            parts.append(leg)
    # throne
    parts.append(cyl(0.17, 0.08, (0, 0.5, 0.5), M("black"), 10))
    parts.append(cyl(0.02, 0.46, (0, 0.5, 0.23), chrome, 6))
    parts.append(bx((-0.18, 0.49, 0), (0.18, 0.51, 0.02), chrome))
    parts.append(bx((-0.01, 0.32, 0), (0.01, 0.68, 0.02), chrome))
    # sticks on the snare
    for dx in (-0.03, 0.03):
        st = cyl(0.007, 0.4, (0, 0, 0), M("wood_light"), 5, axis="X")
        st.rotation_euler = (0, 0, math.radians(25 + dx * 200))
        st.location = (-0.32 + dx, 0.12, 0.69)
        parts.append(st)
    return parts


# ------------------------------------------------------------------ posters

def _text_rows(lines, w, h, scale, top):
    """Pixel lookups for centred lines of the plate font."""
    cw = 4 * scale
    rows = []
    for i, line in enumerate(lines):
        x0 = (w - cw * len(line) + scale) // 2
        y0 = h - top - (i + 1) * 6 * scale
        rows.append((line, x0, y0))

    def ink(x, y):
        for line, x0, y0 in rows:
            gx, gy = x - x0, y - y0
            if 0 <= gx < cw * len(line) and 0 <= gy < 5 * scale:
                ch = line[gx // cw]
                lx, ly = (gx % cw) // scale, gy // scale
                if lx < 3 and TX.FONT.get(ch, TX.FONT[" "])[(4 - ly) * 3 + lx] == "1":
                    return True
        return False
    return ink


def _poster_image(kind, w=48, h=64):
    if kind == "dinosaur":
        # pastel dusk, a lumpy green creature on a hill, bubbly lettering
        ink = _text_rows(["DINOSAUR", "JR"], w, h, 1, 3)

        def px(x, y):
            if ink(x, y):
                return (0.98, 0.93, 0.35)
            hill = 10 + 4 * math.sin(x / 7.0)
            if y < hill:
                return (0.36, 0.58, 0.32)
            bx_, by_ = (x - 26) / 11.0, (y - hill - 7) / 8.0
            if bx_ * bx_ + by_ * by_ < 1 or (20 <= x <= 23 and hill <= y < hill + 4) or (30 <= x <= 33 and hill <= y < hill + 4):
                return (0.47, 0.72, 0.42) if (x + y) % 7 else (0.3, 0.5, 0.28)
            if (x - 35) ** 2 + (y - hill - 16) ** 2 < 14:
                return (0.47, 0.72, 0.42)
            t = y / h
            return TX.lerp((0.93, 0.6, 0.72), (0.55, 0.45, 0.82), t)
        return C.make_image("poster_dinosaur", w, h, px)
    if kind == "lanegan":
        # stark black and white, a rough-edged moon over dark water
        ink = _text_rows(["MARK", "LANEGAN"], w, h, 1, 3)
        rnd = C.noise_rng(31)

        def px(x, y):
            if ink(x, y):
                return (0.92, 0.9, 0.86)
            if (x - 24) ** 2 + (y - 30) ** 2 < 110 + rnd(25):
                return (0.85, 0.83, 0.78)
            if y < 16:
                return (0.12, 0.12, 0.14) if (x + y * 3) % 9 else (0.6, 0.6, 0.58)
            return (0.05, 0.05, 0.06)
        return C.make_image("poster_lanegan", w, h, px)
    if kind == "qotsa":
        # red and black, a bold ring with a slash through it
        ink = _text_rows(["QUEENS", "OF THE", "STONE", "AGE"], w, h, 1, 2)

        def px(x, y):
            if ink(x, y):
                return (0.07, 0.06, 0.06)
            r = math.hypot(x - 24, y - 15)
            if 7 < r < 11 or (abs((x - 24) - (y - 15)) < 2 and r < 14):
                return (0.07, 0.06, 0.06)
            return (0.78, 0.13, 0.11)
        return C.make_image("poster_qotsa", w, h, px)
    raise ValueError(kind)


def _lp_image(seed):
    """An original sleeve design: blocks and stripes in a few colours."""
    pal = [[(0.85, 0.42, 0.62), (0.98, 0.86, 0.4), (0.3, 0.55, 0.7)],
           [(0.1, 0.1, 0.1), (0.8, 0.78, 0.72), (0.55, 0.12, 0.1)],
           [(0.9, 0.2, 0.15), (0.95, 0.9, 0.85), (0.1, 0.1, 0.1)],
           [(0.45, 0.62, 0.38), (0.96, 0.66, 0.3), (0.2, 0.18, 0.3)]][seed % 4]

    def px(x, y):
        if seed % 2:
            return pal[(x // 6 + y // 11) % 3]
        r = math.hypot(x - 16, y - 16)
        return pal[int(r / 5) % 3]
    return C.make_image("lp_sleeve_%d" % seed, 32, 32, px)


def _picture(img_name, img, w, h, y=-0.012):
    me_mat = C.mat("S_" + img_name, "#ffffff", rough=0.8, image=img)
    o = C.mesh_obj("pic", [(-w / 2, y, 0), (w / 2, y, 0), (w / 2, y, h), (-w / 2, y, h)], [(0, 1, 2, 3)], me_mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    # face -Y: the quad winds anticlockwise seen from -Y
    return o


def poster(kind, w=0.5, h=0.7):
    """Framed poster, back on y=0, facing -Y, origin at the bottom centre."""
    frame = M("frame")
    return [bx((-w / 2 - 0.02, -0.01, -0.02), (w / 2 + 0.02, 0, h + 0.02), frame),
            _picture("poster_" + kind, _poster_image(kind), w, h)]


def lp_row(n=4, gap=0.06):
    """A row of LP sleeves in thin frames, centred, facing -Y."""
    s = 0.31
    parts = []
    width = n * s + (n - 1) * gap
    for i in range(n):
        x = -width / 2 + s / 2 + i * (s + gap)
        parts.append(bx((x - s / 2 - 0.01, -0.01, -0.01), (x + s / 2 + 0.01, 0, s + 0.01), M("frame")))
        pic = _picture("lp_%d" % i, _lp_image(i), s, s)
        pic.location = (x, 0, 0)
        parts.append(pic)
    return parts
