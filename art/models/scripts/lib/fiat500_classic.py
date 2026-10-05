"""The classic Fiat 500 family (Nuova 500, 1957-1975) and its derivatives.

Real proportions (Nuova/D/F/L/R): length 2.97 m, width 1.32 m, height
1.32 m, wheelbase 1.84 m, track 1.12 m front / 1.13 m rear, tyres 125R12.
Giardiniera: length 3.185 m, height 1.35 m, wheelbase 1.94 m. Air-cooled
twin at the back, luggage under the front lid.

Same approach as fiat500_shell.py: every column of KEYS is a curve along
the car (y, metres, front at -Y), interpolated with monotone cubics; each
station's half section is a Catmull-Rom curve through ten control points:

    P0 underside centre  P1 underside edge  P2 sill  P3 lower side
    P4 belt crease (widest)  P4b just above the crease
    P5 window line  P6 roof edge  P7 roof shoulder  P8 roof centre

Over the front lid and the engine lid the window line and roof points
collapse onto the lid surface, so one table draws the whole car.

`build(spec)` returns the exported objects with the same node contract as
fiat500_modern.build() plus Hub_FL/FR/RL/RR empties at the wheel centres
and a `wheels` custom property on Body. Spec keys:
  body          'saloon' | 'estate' (Giardiniera) | 'jolly'
  paint         body colour (hex)
  roof          'fabric_full' (Nuova, to the engine lid) | 'fabric' (D/F/L/R,
                ends over the rear seat) | 'steel' | 'canopy' (Jolly)
  fabric        roof canvas colour
  doors         'suicide' (rear hinged) | 'front' | None (Jolly)
  wheels        wheels.STYLES key
  tail          'small' | 'large' tail lamps
  quarterlight  bool: vent window at the front of the door glass
  nerf          bool: tubular over-riders above the bumpers (500 L)
  dash          'painted' | 'black' (500 L)
  seat          vinyl colour;  seat_piping
  stripe        hex: side stripe along the crease (Sport)
  abarth        None | '595' | '695' (lowered, flares on the 695, lid propped open)
  badge         'nuova' | 'plain' | 'abarth'
  ride          body height offset (negative lowers)
  plate         plate text
"""
import math

import bpy  # noqa: I001  (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector

from . import cabin as CB
from . import carkit as K
from . import common as C
from . import fiat500_shell as S
from . import textures as TX
from . import wheels as W

# ------------------------------------------------------------------ shape

TRACK_F, TRACK_R = 1.12, 1.13

# Saloon key curves. Measured off side/front/rear drawings of the Nuova 500:
# the nose is blunt and round in plan, the front lid domes up from a tall
# front with the lamps on the wings, a steep windscreen, a domed roof, a
# small rear window and the louvred engine lid falling to a round tail.
#        y        w     zb     zcr    zbelt  wbelt  zrs    wrs    zt
SALOON = [
    (-1.440, (0.060, 0.340, 0.440, 0.460, 0.050, 0.470, 0.030, 0.475)),
    (-1.430, (0.170, 0.320, 0.470, 0.530, 0.150, 0.550, 0.100, 0.558)),
    (-1.410, (0.260, 0.300, 0.500, 0.600, 0.225, 0.620, 0.150, 0.630)),
    (-1.375, (0.340, 0.290, 0.525, 0.655, 0.300, 0.675, 0.200, 0.685)),
    (-1.330, (0.410, 0.280, 0.550, 0.695, 0.365, 0.715, 0.250, 0.727)),
    (-1.270, (0.470, 0.275, 0.570, 0.725, 0.420, 0.748, 0.290, 0.760)),
    (-1.190, (0.530, 0.270, 0.590, 0.750, 0.470, 0.775, 0.320, 0.788)),
    (-1.080, (0.585, 0.260, 0.605, 0.772, 0.520, 0.798, 0.350, 0.811)),
    (-0.940, (0.625, 0.220, 0.622, 0.795, 0.555, 0.820, 0.380, 0.833)),
    (-0.790, (0.650, 0.170, 0.640, 0.822, 0.580, 0.843, 0.410, 0.853)),
    (-0.660, (0.660, 0.150, 0.652, 0.852, 0.595, 0.868, 0.450, 0.874)),
    (-0.600, (0.660, 0.150, 0.658, 0.868, 0.598, 0.884, 0.560, 0.890)),
    (-0.520, (0.660, 0.150, 0.660, 0.876, 0.598, 0.985, 0.548, 0.995)),
    (-0.440, (0.660, 0.150, 0.660, 0.878, 0.598, 1.075, 0.535, 1.090)),
    (-0.370, (0.660, 0.150, 0.660, 0.879, 0.598, 1.155, 0.522, 1.178)),
    (-0.310, (0.660, 0.150, 0.660, 0.880, 0.598, 1.215, 0.510, 1.243)),
    (-0.250, (0.660, 0.150, 0.660, 0.881, 0.598, 1.237, 0.505, 1.277)),
    (-0.100, (0.660, 0.150, 0.660, 0.883, 0.598, 1.252, 0.500, 1.306)),
    (0.100, (0.660, 0.150, 0.660, 0.885, 0.598, 1.257, 0.500, 1.319)),
    (0.300, (0.660, 0.150, 0.660, 0.887, 0.598, 1.252, 0.500, 1.320)),
    (0.450, (0.660, 0.150, 0.660, 0.889, 0.597, 1.237, 0.495, 1.305)),
    (0.550, (0.660, 0.150, 0.660, 0.890, 0.596, 1.210, 0.490, 1.280)),
    (0.630, (0.659, 0.150, 0.660, 0.891, 0.595, 1.170, 0.482, 1.236)),
    (0.700, (0.658, 0.152, 0.660, 0.892, 0.594, 1.110, 0.472, 1.172)),
    (0.780, (0.657, 0.160, 0.660, 0.892, 0.592, 1.030, 0.462, 1.090)),
    (0.860, (0.656, 0.175, 0.660, 0.890, 0.590, 0.955, 0.455, 1.008)),
    (0.940, (0.655, 0.195, 0.659, 0.880, 0.585, 0.910, 0.440, 0.940)),
    (1.040, (0.650, 0.220, 0.655, 0.855, 0.570, 0.876, 0.420, 0.893)),
    (1.150, (0.635, 0.240, 0.645, 0.815, 0.550, 0.828, 0.400, 0.838)),
    (1.250, (0.605, 0.250, 0.635, 0.765, 0.520, 0.775, 0.380, 0.782)),
    (1.330, (0.565, 0.260, 0.620, 0.705, 0.480, 0.714, 0.350, 0.720)),
    (1.400, (0.510, 0.270, 0.600, 0.645, 0.430, 0.652, 0.310, 0.658)),
    (1.450, (0.440, 0.280, 0.575, 0.595, 0.370, 0.602, 0.260, 0.606)),
    (1.490, (0.360, 0.290, 0.550, 0.555, 0.300, 0.560, 0.200, 0.563)),
    (1.515, (0.260, 0.305, 0.520, 0.522, 0.210, 0.525, 0.140, 0.527)),
    (1.530, (0.100, 0.330, 0.480, 0.482, 0.080, 0.484, 0.050, 0.485)),
]


def _estate_keys():
    """Giardiniera: the saloon's front and doors 5 cm further forward (the
    wheelbase is 10 cm longer), then a flat roof running back to a square
    tail with the side-hinged rear door."""
    out = [(y - 0.05, v) for y, v in SALOON if y <= 0.10]
    rear = [
        (0.400, (0.660, 0.150, 0.660, 0.889, 0.598, 1.268, 0.500, 1.340)),
        (0.800, (0.660, 0.155, 0.660, 0.892, 0.598, 1.270, 0.500, 1.343)),
        (1.200, (0.660, 0.170, 0.660, 0.895, 0.598, 1.270, 0.500, 1.343)),
        (1.450, (0.656, 0.200, 0.660, 0.897, 0.596, 1.268, 0.499, 1.338)),
        (1.560, (0.648, 0.230, 0.658, 0.898, 0.592, 1.262, 0.496, 1.330)),
        (1.630, (0.632, 0.255, 0.654, 0.896, 0.582, 1.250, 0.488, 1.315)),
        (1.670, (0.608, 0.275, 0.648, 0.892, 0.565, 1.230, 0.474, 1.292)),
        (1.690, (0.578, 0.290, 0.642, 0.886, 0.540, 1.205, 0.455, 1.262)),
        (1.700, (0.540, 0.305, 0.636, 0.878, 0.505, 1.175, 0.430, 1.228)),
    ]
    return out + rear


# Side window outline (y, z) of the saloon: the door glass behind the
# raked A-pillar, the B-pillar band, and the small quarter window whose
# rear edge curves down into the C-pillar.
DLO_SALOON = [
    (-0.540, 0.900), (-0.500, 0.955), (-0.442, 1.035), (-0.385, 1.108), (-0.338, 1.160), (-0.292, 1.190),
    (-0.22, 1.204), (-0.10, 1.214), (0.10, 1.218), (0.30, 1.215), (0.42, 1.200), (0.505, 1.172),
    (0.565, 1.126), (0.605, 1.068), (0.625, 1.000), (0.624, 0.935), (0.605, 0.906), (0.40, 0.903),
    (0.0, 0.899), (-0.40, 0.897),
]
# windscreen seen from above (x, y); rear window seen from behind (x, z)
WINDSCREEN = [
    (-0.475, -0.578), (-0.490, -0.550), (-0.465, -0.452), (-0.432, -0.365), (-0.405, -0.324),
    (-0.365, -0.308), (0.0, -0.300), (0.365, -0.308), (0.405, -0.324), (0.432, -0.365),
    (0.465, -0.452), (0.490, -0.550), (0.475, -0.578), (0.0, -0.588),
]
REAR_WINDOW = [
    (-0.29, 0.995), (-0.335, 1.025), (-0.345, 1.095), (-0.322, 1.142), (-0.27, 1.162),
    (0.27, 1.162), (0.322, 1.142), (0.345, 1.095), (0.335, 1.025), (0.29, 0.995),
]


def _shift(poly, dy):
    return [(y + dy, z) for y, z in poly]


def _estate_dlo():
    """Door glass as the saloon (5 cm forward), then one long rear side
    window to just short of the square tail."""
    top = [(0.30, 1.216), (0.70, 1.220), (1.20, 1.220), (1.42, 1.214), (1.50, 1.199), (1.545, 1.166),
           (1.56, 1.10), (1.56, 0.95), (1.545, 0.912), (1.50, 0.906), (1.00, 0.904), (0.40, 0.902)]
    a = [p for p in _shift(DLO_SALOON, -0.05)[:9]]
    return a + top + [(-0.05, 0.899), (-0.45, 0.897)]


GEOM = {
    "saloon": {"keys": SALOON, "wheelbase": 1.84, "door": (-0.565, 0.330), "height": 1.32,
               "dlo": DLO_SALOON, "bpillar": (0.300, 0.360), "screen": WINDSCREEN, "rear": REAR_WINDOW,
               "rear_cut": 0.50, "roof_top": (0.20, 1.320)},
    "jolly": {"keys": SALOON, "wheelbase": 1.84, "door": (-0.565, 0.330), "height": 1.32,
              "dlo": DLO_SALOON, "bpillar": (0.300, 0.360), "screen": WINDSCREEN, "rear": REAR_WINDOW,
              "rear_cut": 0.50, "roof_top": (0.20, 1.320)},
    "estate": {"keys": _estate_keys(), "wheelbase": 1.94, "door": (-0.615, 0.280), "height": 1.343,
               "dlo": _estate_dlo(), "bpillar": (0.250, 0.310), "screen": [(x, y - 0.05) for x, y in WINDSCREEN],
               "rear": [(-0.40, 0.950), (0.40, 0.950), (0.43, 0.98), (0.43, 1.15), (0.40, 1.175), (-0.40, 1.175),
                        (-0.43, 1.15), (-0.43, 0.98)],
               "rear_cut": 1.60, "roof_top": (0.60, 1.343), "pillar2": (0.93, 0.98)},
}

# points per section segment P0-P1, P1-P2, P2-P3, P3-P4, P4-P4b, P4b-P5, P5-P6, P6-P7, P7-P8
COUNTS = [1, 2, 2, 2, 1, 3, 3, 2, 2]

ARCH_R = 0.315
HUB_Z = 0.27


def _curves(keys):
    ys = [k[0] for k in keys]
    cols = list(zip(*[k[1] for k in keys]))
    return ys, [K.pchip(ys, list(c)) for c in cols]


def station_ys(ys, door):
    out = set()
    for i in range(len(ys) - 1):
        a, b = ys[i], ys[i + 1]
        n = max(1, round((b - a) / 0.07))
        for k in range(n):
            out.add(round(a + (b - a) * k / n, 4))
    out.add(ys[-1])
    out.update(door)
    res = []
    for y in sorted(out):
        if res and y - res[-1] < 0.004:
            continue
        res.append(y)
    return res


def section(y, f):
    w, zb, zcr, zbelt, wbelt, zrs, wrs, zt = (c(y) for c in f)
    pts = [
        (0.0, zb), (w * 0.82, zb), (w - 0.05, zb + 0.075), (w - 0.014, (zb + zcr) / 2 + 0.02),
        (w, zcr), (w - 0.009, zcr + 0.022), (wbelt, zbelt), (wrs, zrs),
        (wrs * 0.6, zrs + (zt - zrs) * 0.78), (0.0, zt),
    ]
    sampled, _ = K.catmull(pts, COUNTS)
    return K.Station(y, sampled)


class Geom:
    """Shape and key dimensions of one body style."""

    def __init__(self, body):
        g = GEOM[body]
        self.body = body
        self.keys = g["keys"]
        self.wheelbase = g["wheelbase"]
        self.axle_f, self.axle_r = -self.wheelbase / 2, self.wheelbase / 2
        self.door = g["door"]
        self.height = g["height"]
        self.dlo = g["dlo"]
        self.bpillar = g["bpillar"]
        self.screen = g["screen"]
        self.rear = g["rear"]
        self.rear_cut = g["rear_cut"]
        self.roof_top = g["roof_top"]
        self.pillar2 = g.get("pillar2")
        self.ys, self.f = _curves(self.keys)
        self.nose, self.tail = self.ys[0], self.ys[-1]

    def stations(self):
        return [section(y, self.f) for y in station_ys(self.ys, self.door)]

    def at(self, col, y):
        names = ["w", "zb", "zcr", "zbelt", "wbelt", "zrs", "wrs", "zt"]
        return self.f[names.index(col)](y)


def shell(g):
    st = g.stations()
    verts, faces, tags, uvs = K.loft(st, lambda *a: K.T_PAINT)
    obj = K.shell_object("shell", verts, faces, tags, uvs)
    K.cut_arches(obj, (g.axle_f, g.axle_r), ARCH_R, (0.33, 0.43), HUB_Z)
    return obj, st


# ------------------------------------------------------------------ materials

def _speedo(name="speedo", dark=False):
    """Round period speedometer: cream face, black ticks, chrome bezel."""
    s = 32

    def px(x, y):
        u, v = (x + 0.5) / s * 2 - 1, (y + 0.5) / s * 2 - 1
        r = math.hypot(u, v)
        a = math.degrees(math.atan2(v, u))
        face = (0.12, 0.12, 0.12) if dark else (0.90, 0.87, 0.78)
        ink = (0.9, 0.9, 0.88) if dark else (0.08, 0.08, 0.08)
        if r > 0.92:
            return (0.75, 0.76, 0.78)
        if r > 0.66 and (a % 20) < 6 and not (-130 < a < -50):
            return ink
        if abs(v - u * 0.35) < 0.06 and r < 0.6 and u < 0.05:
            return (0.85, 0.2, 0.05)
        if r < 0.12:
            return ink
        return face
    return C.make_image(name, s, s, px)


def _wicker(name="wicker"):
    """Woven cane: diagonal over-under weave in two straw tones."""
    s = 32

    def px(x, y):
        cell = ((x // 4) + (y // 4)) % 2
        k = (x % 4 == 0) or (y % 4 == 0)
        base = (0.80, 0.66, 0.42) if cell else (0.72, 0.57, 0.34)
        return TX.mul(base, 0.75 if k else 1.0)
    return C.make_image(name, s, s, px)


def _stripes(name, a, b, n=8, s=32):
    ca, cb = C._hex(a), C._hex(b)
    return C.make_image(name, s, s, lambda x, y: ca if (x * n // s) % 2 else cb)


def _glass():
    m = C.mat("Glass", "#9fb4bd", rough=0.05, metal=0.2, alpha=0.18)
    m.use_backface_culling = False
    return m


def materials(spec):
    paint = spec.get("paint", "#9fb8c6")
    seat = spec.get("seat", "#b8a888")
    M = {
        "paint": C.mat("Paint", paint, rough=0.35, metal=0.1),
        "glass": _glass(),
        "trim": C.mat("TrimBlack", "#1b1c1e", rough=0.7),
        "seam": C.mat("Seam", "#0b0b0c", rough=1.0),
        "under": C.mat("Underbody", "#151515", rough=0.9),
        "cabin": C.mat("CabinTrim", spec.get("cabin", "#3a3632"), rough=0.85),
        "headliner": C.mat("Headliner", spec.get("headliner", "#d8d0bf"), rough=0.95),
        "chrome": C.mat("Chrome", "#dcdee0", rough=0.15, metal=0.95),
        "head": C.mat("LampHead", "#b4bcc0", rough=0.05, metal=0.5, emit="#fff6dc", emit_strength=0.0),
        "reflector": C.mat("LampReflector", "#8a9094", rough=0.2, metal=0.9),
        "tail": C.mat("LampTail", "#a8121a", rough=0.3, emit="#ff1a10", emit_strength=0.0),
        "amber": C.mat("LampAmber", "#e08a20", rough=0.3),
        "white": C.mat("LampClear", "#e6e6e6", rough=0.2),
        "badge": C.mat("BadgeRed", "#a0101a", rough=0.4),
        "badge_blue": C.mat("BadgeBlue", "#1c3a7a", rough=0.4),
        "dark": C.mat("Grille", "#0c0c0d", rough=0.8),
        "plate": C.mat("Plate", image=TX.plate(spec.get("plate", "1CIN-500")), rough=0.6),
        "fabric": C.mat("RoofFabric", image=TX.fabric("roof_canvas", spec.get("fabric", "#2a2826"), seed=31,
                                                      seams=False), rough=1.0),
        "fabric_rib": C.mat("RoofFabricRib", spec.get("fabric_rib", "#141312"), rough=1.0),
        "dash_black": C.mat("DashBlack", "#161617", rough=0.6),
        "vinyl": C.mat("SeatVinyl", image=TX.fabric("seat_vinyl", seat, seed=41, seams=True), rough=0.55),
        "vinyl_plain": C.mat("SeatVinylPlain", seat, rough=0.55),
        "piping": C.mat("SeatPiping", spec.get("seat_piping", "#e8e2d2"), rough=0.5),
        "wheel": C.mat("SteeringBakelite", spec.get("wheel_color", "#e9e1cc"), rough=0.3),
        "rubber": C.mat("FloorMatRibbed", image=CB.ribbed_mat_tex(), rough=0.9),
        "rubber_pad": C.mat("PedalRubber", image=TX.carpet("pedal_rubber", "#141415", 5, 8), rough=0.95),
        "gauge": C.mat("Gauges", image=_speedo("speedo", spec.get("dash") == "black"), rough=0.4,
                       emit="#302a20", emit_strength=0.15),
        "knob": C.mat("KnobBlack", "#0e0e0f", rough=0.25),
        "ivory": C.mat("KnobIvory", "#e9e1cc", rough=0.3),
        "stripe": C.mat("Stripe", spec.get("stripe") or "#b3121c", rough=0.4),
        "abarth_red": C.mat("AbarthRed", "#b0141c", rough=0.4),
        "abarth_yellow": C.mat("AbarthYellow", "#f0c419", rough=0.4),
        "engine": C.mat("EngineAlloy", "#8d8f90", rough=0.5, metal=0.6),
        "engine_black": C.mat("EngineBlack", "#1e1e1f", rough=0.7),
        "wicker": C.mat("Wicker", image=_wicker(), rough=0.9),
    }
    return M


# ------------------------------------------------------------------ openings

def cut_windows(obj, g):
    """Boolean the window openings: door glass and quarter glass cut
    separately so the B-pillar stays painted; windscreen from above; rear
    window from behind. Cutter faces come out tagged Glass and are dropped."""
    door = S.clip_y(g.dlo, hi=g.bpillar[0])
    quarters = _quarters(g)
    cutters = []
    for poly in [door] + quarters:
        cutters.append(S._prism(poly, lambda u, v, d: (d, u, v), 0.35, 1.5))
        cutters.append(S._prism(poly, lambda u, v, d: (d, u, v), -1.5, -0.35))
    cutters.append(S._prism(g.screen, lambda u, v, d: (u, v, d), 0.90, 2.5))
    cutters.append(S._prism(g.rear, lambda u, v, d: (u, d, v), g.rear_cut, 2.6))
    _apply_cutters(obj, cutters)


def _quarters(g):
    q = S.clip_y(g.dlo, lo=g.bpillar[1])
    if g.pillar2:
        return [S.clip_y(q, hi=g.pillar2[0]), S.clip_y(q, lo=g.pillar2[1])]
    return [q]


def _apply_cutters(obj, cutters):
    for c in cutters:
        mod = obj.modifiers.new("win", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = c
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(c, do_unlink=True)


JOLLY_OPENING = [(-0.50, 0.50), (-0.47, 0.44), (-0.40, 0.41), (0.12, 0.41), (0.20, 0.44), (0.24, 0.50),
                 (0.24, 1.40), (-0.50, 1.40)]
JOLLY_CUT_Z = 0.80


def cut_jolly(obj, g):
    """Ghia Jolly: roof, glass and doors gone, the sides cut down to a low
    open waist, big open door gaps."""
    top = [(-0.585, JOLLY_CUT_Z), (0.93, JOLLY_CUT_Z), (0.93, 2.0), (-0.585, 2.0)]
    cutters = [S._prism(top, lambda u, v, d: (d, u, v), -1.5, 1.5)]
    for sx in (1, -1):
        lo, hi = (0.30, 1.5) if sx > 0 else (-1.5, -0.30)
        cutters.append(S._prism(JOLLY_OPENING, lambda u, v, d: (d, u, v), lo, hi))
    _apply_cutters(obj, cutters)


def door_outline(g):
    """Side outline (y, z) of each door: the panel from the sill to the belt
    between the shut lines, plus the window frame (the glass grown by 3 cm)
    up the A-pillar and over the top to the B-pillar."""
    y0, y1 = g.door
    grown = K.offset_poly(g.dlo, -0.016)
    chain = []
    for i, p in enumerate(grown):
        if p[0] > y1:
            q = grown[i - 1]
            t = (y1 - q[0]) / (p[0] - q[0])
            chain.append((y1, q[1] + (p[1] - q[1]) * t))
            break
        chain.append(p)
    start = [p for p in chain if p[0] < y0]
    chain = [p for p in chain if p[0] >= y0]
    if start:
        q, p = start[-1], chain[0]
        t = (y0 - q[0]) / (p[0] - q[0])
        chain.insert(0, (y0, q[1] + (p[1] - q[1]) * t))
    return [(y0, 0.255), (y1, 0.255)] + list(reversed(chain))


def split_doors(obj, g):
    """Cut each door out of the shell along its exact outline (boolean
    intersect for the door, difference for the body), so the shut lines
    follow the real car instead of the loft rows."""
    outline = door_outline(g)
    pieces = []
    for sx, tag in ((1, K.T_DL), (-1, K.T_DR)):
        d = C.link(bpy.data.objects.new("door_piece", obj.data.copy()))
        lo, hi = (0.35, 1.5) if sx > 0 else (-1.5, -0.35)
        cut = S._prism(outline, lambda u, v, dd: (dd, u, v), lo, hi)
        mod = d.modifiers.new("door", "BOOLEAN")
        mod.operation = "INTERSECT"
        mod.object = cut
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        with bpy.context.temp_override(object=d, active_object=d):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cut, do_unlink=True)
        for p in d.data.polygons:
            if p.material_index == K.T_PAINT:
                p.material_index = tag
        pieces.append(d)
    _apply_cutters(obj, [S._prism(outline, lambda u, v, dd: (dd, u, v), 0.35, 1.5),
                         S._prism(outline, lambda u, v, dd: (dd, u, v), -1.5, -0.35)])
    return pieces, outline


def door_shut_lines(pieces, outline, material, width=0.008):
    """Dark strips along the doors' outer borders (not round the glass)."""
    segs = [(Vector(outline[i - 1]), Vector(outline[i])) for i in range(len(outline))]

    def near(p):
        best = 1e9
        for a, b in segs:
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
            best = min(best, (p - (a + ab * t)).length)
        return best
    verts, faces = [], []
    for d in pieces:
        bm = bmesh.new()
        bm.from_mesh(d.data)
        bm.normal_update()
        for e in bm.edges:
            if len(e.link_faces) != 1 or e.link_faces[0].material_index == K.T_GLASS:
                continue
            v1, v2 = e.verts[0].co, e.verts[1].co
            mid = (v1 + v2) / 2
            if near(Vector((mid.y, mid.z))) > 0.006:
                continue
            n = e.link_faces[0].normal
            side = n.cross(v2 - v1).normalized() * width / 2
            lift = n * 0.002
            i = len(verts)
            verts += [v1 - side + lift, v2 - side + lift, v2 + side + lift, v1 + side + lift]
            faces.append((i, i + 1, i + 2, i + 3))
        bm.free()
    return C.mesh_obj("shut_lines", [tuple(v) for v in verts], faces, material)


def surface_normals(ref, objs):
    """{rounded position: normal} for every vertex of objs, interpolated from
    the smooth vertex normals of the uncut surface `ref` at the nearest
    point. Pieces cut apart by booleans (doors, body round the openings)
    then solidify along identical directions where they meet, so their
    inner skins run side by side instead of crossing."""
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import barycentric_transform
    me = ref.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    out = {}
    for o in objs:
        for v in o.data.vertices:
            loc, nor, idx, _ = tree.find_nearest(v.co)
            if idx is None:
                continue
            f = bm.faces[idx]
            a, b, c = (lp.vert for lp in f.loops)
            w = barycentric_transform(loc, a.co, b.co, c.co, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
            n = a.normal * w.x + b.normal * w.y + c.normal * w.z
            out[K._key(v.co)] = n.normalized() if n.length > 1e-6 else nor
    bm.free()
    return out


def classify(obj, g, doors=True):
    """Underside faces read as the dark floor pan; the rest stays paint."""
    for p in obj.data.polygons:
        if p.material_index in (K.T_UNDER, K.T_GLASS, K.T_DL, K.T_DR):
            continue
        c, n = p.center, p.normal
        p.material_index = K.T_UNDER if (n.z < -0.55 and c.z < 0.30) else K.T_PAINT


# ------------------------------------------------------------------ glass

def _pane(name, ref, poly, frame, M, grow=0.015):
    return K.project_poly(name, ref, K.offset_poly(poly, -grow), frame, M["glass"], offset=-0.012, cuts=3)


def _seal(name, ref, poly, frame, M, border=0.03, mat=None, out=0.018):
    return K.project_poly(name, ref, K.offset_poly(poly, -out), frame, None, offset=0.004, cuts=1,
                          border=border, border_mat=mat or M["trim"])


def windows(ref, g, M, spec):
    body = {"panes": [], "seals": []}
    doors = {}
    door_poly = S.clip_y(g.dlo, hi=g.bpillar[0])
    for sx in (1, -1):
        fr = K.side_frame(sx)
        doors[sx] = {"panes": [_pane("door_glass", ref, door_poly, fr, M, grow=0.007)],
                     "seals": [_seal("door_seal", ref, door_poly, fr, M, border=0.02, out=0.008)]}
        if spec.get("quarterlight"):
            # vent window: a chrome bar up from the belt a hand's width behind the A-pillar
            ya = door_poly[0][0] + 0.29
            doors[sx]["seals"].append(K.project_line("vent_bar", ref, [(ya, 0.905), (ya, 1.19)], fr, 0.014,
                                                     M["chrome"], offset=0.006))
        for q in _quarters(g):
            body["panes"].append(_pane("quarter_glass", ref, q, fr, M))
            body["seals"].append(_seal("quarter_seal", ref, q, fr, M, border=0.024))
    body["panes"].append(_pane("windscreen", ref, g.screen, K.top_frame(), M))
    body["seals"].append(_seal("windscreen_seal", ref, g.screen, K.top_frame(), M, border=0.03))
    body["panes"].append(_pane("rear_window", ref, g.rear, K.rear_frame(), M))
    body["seals"].append(_seal("rear_seal", ref, g.rear, K.rear_frame(), M, border=0.026))
    return body, doors


# ------------------------------------------------------------------ helpers

def _ray_hit(target, origin, direction):
    ok, loc, nor, _ = K.surface_ray(target, origin, direction)
    return (loc, nor) if ok else None


def _wrap_bar(name, ref, z, centre, angles, front, h, d, gap, mat, y_limit):
    """Blade bumper wrapped round the nose (front) or tail at height z:
    rays aim at `centre` (y) in plan from the given angles (deg, 0 = dead
    ahead/behind); the bar keeps `gap` off the skin. Stops at y_limit."""
    sgn = -1 if front else 1
    ring = []
    for a in angles:
        t = math.radians(a)
        dirn = Vector((math.sin(t), sgn * math.cos(t), 0))
        res = _ray_hit(ref, Vector((0, centre, z)) + dirn * 3, -dirn)
        if res is None:
            continue
        loc, nor = res
        if (front and loc.y > y_limit) or (not front and loc.y < y_limit):
            continue
        n = Vector((nor.x, nor.y, 0)).normalized()
        prof = [(gap, h / 2), (gap + d * 0.75, h / 2), (gap + d, h * 0.1), (gap + d * 0.8, -h / 2), (gap, -h / 2)]
        ring.append([loc + n * o + Vector((0, 0, dz)) for o, dz in prof])
    nprof = 5
    verts = [tuple(v) for r in ring for v in r]
    faces = []
    for i in range(len(ring) - 1):
        for k in range(nprof):
            a, b = i * nprof + k, i * nprof + (k + 1) % nprof
            faces.append((a, b, b + nprof, a + nprof))
    faces.append(tuple(range(nprof - 1, -1, -1)))
    last = (len(ring) - 1) * nprof
    faces.append(tuple(last + k for k in range(nprof)))
    o = C.mesh_obj(name, verts, faces, mat)
    _fix_normals(o)
    K.smooth(o, 50)
    return o


def _fix_normals(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


def _tube(name, a, b, r, mat, segs=8):
    """Cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    o = C.cylinder(name, r, (b - a).length, segs=segs, material=mat)
    o.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    o.location = (a + b) / 2
    C.apply_transform(o)
    return o


def _densify(pts, step):
    out = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.dist(a, b) / step + 0.999))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]
    return out + [pts[-1]]


# ------------------------------------------------------------------ front

LAMP_X, LAMP_Z, LAMP_R = 0.445, 0.625, 0.072


def _lid_line(ref, g, M):
    """Front lid shut line: back along the wing tops from the cowl, round
    inside the headlamps and across the nose above the bumper."""
    rays = []
    fr = K.front_frame()
    dy = g.axle_f + 0.92        # 0 for the saloon, -0.05 for the estate
    wing = [(-0.625, 0.505), (-0.75, 0.50), (-0.90, 0.488), (-1.00, 0.468), (-1.10, 0.437), (-1.18, 0.405),
            (-1.25, 0.372)]

    def side(sx, pts):
        for y, x in pts:
            rays.append(((sx * x, y + dy, 3), (0, 0, -1)))

    def nose(sx, pts):
        for x, z in pts:
            rays.append(fr(sx * x, z))
    front = [(0.355, 0.70), (0.348, 0.66), (0.340, 0.60), (0.325, 0.55), (0.29, 0.515), (0.22, 0.497)]
    side(-1, wing)
    nose(-1, front)
    for i in range(1, 10):
        x = -0.20 + i * 0.04
        rays.append(fr(x, 0.493))
    nose(1, list(reversed(front)))
    side(1, list(reversed(wing)))
    return S.ribbon("lid_line", ref, rays, 0.009, M["seam"])


def front_details(ref, g, M, spec):
    out = [_lid_line(ref, g, M)]
    big_ind = spec.get("tail") == "large"
    for sx in (1, -1):
        w = K.on_front(ref, sx * LAMP_X, LAMP_Z)
        out.append(K.stick_disc("head_bezel", ref, w, LAMP_R + 0.012, 0.035, M["chrome"], segs=16, proud=0.0))
        h = K.stick_disc("head", ref, w, LAMP_R, 0.03, M["head"], segs=16, proud=0.008)
        h["lamp"] = "head"
        out.append(h)
        out.append(K.stick_disc("head_reflector", ref, w, 0.03, 0.03, M["reflector"], segs=10, proud=0.012))
        # small round (Nuova/D) or oval (F/L/R) indicators below the lamps
        wi = K.on_front(ref, sx * 0.43, 0.475)
        out.append(K.stick_disc("ind_ring", ref, wi, 0.028, 0.02, M["chrome"], segs=10,
                                sx=1.7 if big_ind else 1.0, proud=0.0))
        out.append(K.stick_disc("ind", ref, wi, 0.022, 0.02, M["amber"], segs=10,
                                sx=1.75 if big_ind else 1.0, proud=0.004))
    # moustache: chrome whiskers sweeping out from the badge
    for sx in (1, -1):
        pts = [(sx * (0.055 + 0.25 * t), 0.548 + 0.035 * t * t) for t in [i / 8 for i in range(9)]]
        out.append(K.project_line("moustache", ref, pts, K.front_frame(), 0.016, M["chrome"], offset=0.004))
        pts2 = [(sx * (0.055 + 0.18 * t), 0.528 + 0.02 * t * t) for t in [i / 6 for i in range(7)]]
        out.append(K.project_line("moustache_lo", ref, pts2, K.front_frame(), 0.010, M["chrome"], offset=0.004))
    badge = spec.get("badge", "nuova")
    if badge == "abarth":
        out += _abarth_badge(ref, K.front_frame(), 0, 0.565, M, 0.9)
    else:
        rect = S.rounded_rect(0.105, 0.045, 0.012, 2)
        rect = [(u, v + 0.545) for u, v in rect]
        out.append(K.project_poly("badge", ref, rect, K.front_frame(),
                                  M["badge_blue"] if badge == "plain" else M["badge"], offset=0.006, cuts=1,
                                  border=0.007, border_mat=M["chrome"]))
    # bumper: slim chrome blade wrapped round the nose
    out.append(_wrap_bar("bumper_f", ref, 0.365, g.nose + 0.62, range(-78, 79, 6), True, 0.05, 0.032, 0.012,
                         M["chrome"], g.axle_f - ARCH_R - 0.035))
    if spec.get("nerf"):
        out += _nerf(ref, g, M, True)
    if spec.get("plate"):
        loc, nor = K.on_front(ref, 0, 0.365)
        p = C.box("plate_f", (0.372, 0.01, 0.134), loc + Vector((0, -0.055, 0.0)), M["plate"])
        K.planar_uv(p, 0, 2)
        out.append(p)
        out.append(C.box("plate_f_bracket", (0.06, 0.03, 0.04), loc + Vector((0, -0.04, -0.03)), M["trim"]))
    # wipers parked across the foot of the windscreen
    for x in (-0.36, 0.08):
        out.append(K.stick_box("wiper", K.on_top(ref, x, g.screen[-1][1] + 0.05), (0.34, 0.016, 0.012),
                               M["chrome"], proud=0.008))
    return out


def _nerf(ref, g, M, front):
    """500 L tubular over-riders: a bar above the bumper blade on two posts."""
    out = []
    z = 0.47
    sgn = -1 if front else 1
    ys = []
    for x in (-0.30, 0.30):
        loc = (K.on_front if front else K.on_rear)(ref, x, 0.365)[0]
        ys.append(loc.y + sgn * 0.06)
    y = min(ys) if front else max(ys)
    out.append(_tube("nerf_bar", (-0.34, y, z), (0.34, y, z), 0.014, M["chrome"]))
    for x in (-0.30, 0.30):
        loc = (K.on_front if front else K.on_rear)(ref, x, 0.365)[0]
        out.append(_tube("nerf_post", (x, loc.y + sgn * 0.035, 0.365), (x, y, z), 0.012, M["chrome"]))
        out.append(_tube("nerf_foot", (x, loc.y + sgn * 0.035, 0.365), (x, y, 0.33), 0.012, M["chrome"]))
    return out


# ------------------------------------------------------------------ rear

LID_SALOON = [(-0.29, 0.905), (0.29, 0.905), (0.355, 0.88), (0.39, 0.80), (0.395, 0.60), (0.37, 0.545),
              (0.33, 0.53), (-0.33, 0.53), (-0.37, 0.545), (-0.395, 0.60), (-0.39, 0.80), (-0.355, 0.88)]

LID_RACK_Z = 0.72  # Mount_RearRack height on the lid (before ride)


def _louvres(ref, M, spec):
    """Horizontal cooling slots in the engine lid: one wide bank on the
    Nuova, two banks either side of the centre on the later cars."""
    out = []
    fr = K.rear_frame()
    if spec.get("louvres", "wide") == "wide":
        banks = [(-0.26, 0.26)]
        rows = [0.66 + i * 0.027 for i in range(8)]
    else:
        banks = [(-0.27, -0.05), (0.05, 0.27)]
        rows = [0.72 + i * 0.026 for i in range(6)]
    for x0, x1 in banks:
        for z in rows:
            slot = [(x0, z), (x1, z), (x1, z + 0.011), (x0, z + 0.011)]
            out.append(K.project_poly("louvre", ref, slot, fr, M["dark"], offset=0.004, cuts=2))
            out.append(K.project_line("louvre_lip", ref, [(x0, z + 0.016), (x1, z + 0.016)], fr, 0.008,
                                      M["paint"], offset=0.008))
    return out


def _tail_lamp(ref, sx, M, large, at=(0.50, 1.41, 0.60)):
    x, y, z = at
    n = Vector((sx * 0.72, 0.694, 0))
    origin = Vector((sx * x, y, z)) + n * 2
    res = _ray_hit(ref, origin, -n)
    loc, nor = res
    out = []
    if large:
        out.append(K.stick_disc("tail_rim", ref, (loc, nor), 0.044, 0.025, M["chrome"], segs=12, sz=1.9,
                                proud=0.0))
        lens = K.stick_disc("tail", ref, (loc - Vector((0, 0, 0.014)), nor), 0.038, 0.02, M["tail"], segs=12,
                            sz=1.45, proud=0.008)
        out.append(K.stick_disc("tail_amber", ref, (loc + Vector((0, 0, 0.058)), nor), 0.034, 0.02, M["amber"],
                                segs=10, sz=0.45, proud=0.006))
    else:
        out.append(K.stick_disc("tail_rim", ref, (loc, nor), 0.036, 0.025, M["chrome"], segs=12, sz=1.45,
                                proud=0.0))
        lens = K.stick_disc("tail", ref, (loc, nor), 0.029, 0.02, M["tail"], segs=12, sz=1.45, proud=0.008)
    lens["lamp"] = "tail"
    out.append(lens)
    return out


def rear_details(ref, g, M, spec, lid_bits):
    out = []
    large = spec.get("tail") == "large"
    estate = g.body == "estate"
    if estate:
        for sx in (1, -1):
            out += _tail_lamp(ref, sx, M, large, at=(0.58, g.tail - 0.06, 0.60))
        # side-hinged rear door: shut line round the tail face, handle, plate
        door = [(-0.47, 0.42), (0.47, 0.42), (0.49, 0.46), (0.49, 1.19), (0.46, 1.215), (-0.46, 1.215),
                (-0.49, 1.19), (-0.49, 0.46)]
        out.append(K.project_line("tailgate_line", ref, _densify(door + door[:1], 0.05), K.rear_frame(), 0.010,
                                  M["seam"]))
        out.append(K.stick_box("tail_handle", K.on_rear(ref, 0.36, 0.86), (0.09, 0.03, 0.02), M["chrome"],
                               proud=0.004))
        pz = 0.56
    else:
        for sx in (1, -1):
            out += _tail_lamp(ref, sx, M, large)
        lid = LID_SALOON
        if not spec.get("abarth"):
            out.append(K.project_line("lid_line", ref, _densify(lid + lid[:1], 0.04), K.rear_frame(), 0.009,
                                      M["seam"]))
        lid_bits += _louvres(ref, M, spec)
        lid_bits.append(K.stick_box("lid_handle", K.on_rear(ref, 0, 0.575), (0.12, 0.03, 0.018), M["chrome"],
                                    proud=0.004))
        for i, x in enumerate((-0.035, 0.0, 0.035)):
            lid_bits.append(K.stick_box("badge_500", K.on_rear(ref, x + 0.20, 0.63), (0.022, 0.035, 0.006),
                                        M["chrome"], proud=0.003))
        if spec.get("badge") == "abarth":
            lid_bits += _abarth_badge(ref, K.rear_frame(), -0.20, 0.64, M, 0.6)
        pz = 0.44
    # rear plate with a chrome plate lamp over it
    w = K.on_rear(ref, 0, pz)
    out.append(K.stick_box("plate_r_back", w, (0.40, 0.15, 0.012), M["trim"], proud=0.006))
    p = K.stick_box("plate_r", w, (0.372, 0.134, 0.01), M["plate"], proud=0.016)
    K.planar_uv(p, 0, 2, flip_u=True)
    out.append(p)
    out.append(K.stick_box("plate_lamp", K.on_rear(ref, 0, pz + 0.09), (0.12, 0.03, 0.03), M["chrome"]))
    out.append(_wrap_bar("bumper_r", ref, 0.36, g.tail - 0.62, range(-78, 79, 6), False, 0.05, 0.03, 0.012,
                         M["chrome"], g.axle_r + ARCH_R + 0.035))
    if spec.get("nerf"):
        out += _nerf(ref, g, M, False)
    if estate:
        # cooling louvres in the rear flanks, ahead of the engine under the floor
        for sx in (1, -1):
            for i in range(6):
                z = 0.50 + i * 0.03
                slot = [(1.32, z), (1.52, z), (1.52, z + 0.012), (1.32, z + 0.012)]
                out.append(K.project_poly("flank_louvre", ref, slot, K.side_frame(sx), M["dark"], offset=0.004,
                                          cuts=2))
    return out


# ------------------------------------------------------------------ sides & roof

def side_details(ref, g, M, spec, door_bits):
    out = []
    y0, y1 = g.door
    jolly = spec.get("body") == "jolly"
    for sx in (1, -1):
        fr = K.side_frame(sx)
        if not jolly:
            hy = y0 + 0.10 if spec.get("doors") == "suicide" else y1 - 0.10
            door_bits[sx].append(K.stick_box("handle", K.on_side(ref, sx, hy, 0.79), (0.11, 0.022, 0.02),
                                             M["chrome"], proud=0.004))
            door_bits[sx].append(K.stick_disc("lock", ref, K.on_side(ref, sx, hy, 0.755), 0.009, 0.01,
                                              M["chrome"], segs=6, proud=0.004))
        if spec.get("tail") == "large":
            out.append(K.stick_disc("side_ind", ref, K.on_side(ref, sx, g.axle_f - 0.08, 0.69), 0.016, 0.015,
                                    M["amber"], segs=8, sx=1.6))
        bands = []
        if spec.get("stripe"):
            bands.append((0.598, 0.632, M["stripe"], "stripe"))
        if spec.get("side_trim"):
            bands.append((0.64, 0.652, M["chrome"], "side_trim"))
        for z0, z1, mat, nm in bands:
            ya, yb = g.nose + 0.20, g.tail - 0.22
            segs = [(ya, y0 - 0.006, out), (y1 + 0.006, yb, out)]
            if jolly:
                segs = [(ya, JOLLY_OPENING[0][0] - 0.01, out), (JOLLY_OPENING[5][0] + 0.01, yb, out)]
            else:
                segs.insert(1, (y0 + 0.006, y1 - 0.006, door_bits[sx]))
            for a, b, dst in segs:
                poly = [(a, z0), (b, z0), (b, z1), (a, z1)]
                dst.append(K.project_poly(nm, ref, poly, fr, mat, offset=0.005, cuts=6))
    # round chrome wing mirror on the driver's side (right-hand drive: -X)
    if not jolly:
        loc, nor = K.on_top(ref, -0.55, g.axle_f + 0.17)
        head = loc + Vector((-0.06, 0.0, 0.11))
        out.append(_tube("mirror_stalk", loc - Vector((0, 0, 0.01)), head, 0.008, M["chrome"]))
        out.append(K.lamp_disc("mirror_head", 0.05, 0.022, head + Vector((0, 0.005, 0)), (0, 1, 0), M["chrome"],
                               segs=10))
        out.append(K.lamp_disc("mirror_glass", 0.042, 0.01, head + Vector((0, 0.017, 0)), (0, 1, 0),
                               M["reflector"], segs=10))
    return out


ROOF_INSET = 0.045         # opening edge inside the canvas outline
FULL_SPLIT = 0.62         # Nuova: the panel with the sewn-in window stays put


def _canvas(g, roof):
    """(outline, header y, rear end, half width) of the canvas roof."""
    hy = g.screen[6][1] + 0.035           # just behind the header rail
    if g.body == "estate":
        end, xw = 1.47, 0.43
    elif roof == "fabric_full":
        end, xw = 0.945, 0.41
    else:
        end, xw = 0.47, 0.40
    if roof == "fabric_full" and g.body != "estate":
        poly = [(-xw + 0.015, hy), (xw - 0.015, hy), (xw, hy + 0.04), (xw + 0.01, 0.50), (xw - 0.01, 0.78),
                (xw - 0.05, end - 0.02), (xw - 0.11, end), (-xw + 0.11, end), (-xw + 0.05, end - 0.02),
                (-xw + 0.01, 0.78), (-xw - 0.01, 0.50), (-xw, hy + 0.04)]
    else:
        poly = [(-xw + 0.02, hy), (xw - 0.02, hy), (xw, hy + 0.04), (xw, end - 0.04), (xw - 0.03, end),
                (-xw + 0.03, end), (-xw, end - 0.04), (-xw, hy + 0.04)]
    return poly, hy, end, xw


def _clip_v(poly, lo=None, hi=None):
    """Clip an (x, y) top-view polygon to lo <= y <= hi."""
    sw = S.clip_y([(v, u) for u, v in poly], lo=lo, hi=hi)
    return [(u, v) for v, u in sw]


def _sliding(g, roof):
    """The part of the canvas that rolls back, and where its rear edge is."""
    poly, hy, end, xw = _canvas(g, roof)
    if roof == "fabric_full" and g.body != "estate":
        return _clip_v(poly, hi=FULL_SPLIT - 0.005), FULL_SPLIT
    return poly, end


def roof_opening(obj, g, spec):
    """Cut the hole the canvas covers, so the roof can be rolled back."""
    roof = spec.get("roof")
    if roof not in ("fabric", "fabric_full"):
        return
    poly, rear = _sliding(g, roof)
    hole = K.offset_poly(poly, ROOF_INSET)
    if rear != _canvas(g, roof)[2]:
        # the fixed rear panel keeps its front rail: stop short of the split
        hole = _clip_v(hole, hi=rear - 0.03)
    _apply_cutters(obj, [S._prism(hole, lambda u, v, d: (u, v, d), 1.05, 2.5)])


def fabric_roof(ref, g, M, spec):
    """Canvas roof. Returns (fixed body bits, closed roof, rolled-back roof):
    the sliding canvas and its bows are one object (Roof_Closed), the canvas
    rolled up at the rear of the opening another (Roof_Open, hidden unless
    the roof is down)."""
    roof = spec.get("roof")
    if roof not in ("fabric", "fabric_full"):
        return [], [], []
    poly, hy, end, xw = _canvas(g, roof)
    slide, rear = _sliding(g, roof)
    fixed = []
    if rear != end:
        # the small plastic rear window is sewn into the canvas behind the split
        back = K.project_poly("roof_canvas_rear", ref, _clip_v(poly, lo=rear), K.top_frame(), M["fabric"],
                              offset=0.008, cuts=5, border=0.022, border_mat=M["trim"])
        K.planar_uv(back, 0, 1)
        cut = S._prism(K.offset_poly(g.rear, -0.012), lambda u, v, d: (u, d, v), g.rear_cut, 2.6)
        _apply_cutters(back, [cut])
        fixed.append(back)
    # the rail round the opening stays on the body; only the canvas moves
    fixed.append(K.project_poly("roof_rail", ref, slide, K.top_frame(), None, offset=0.012, cuts=5,
                                border=0.022, border_mat=M["trim"]))
    fab = K.project_poly("roof_canvas", ref, K.offset_poly(slide, 0.022), K.top_frame(), M["fabric"],
                         offset=0.012, cuts=5)
    K.planar_uv(fab, 0, 1)
    K.solidify(fab, 0.004, M["headliner"])
    closed = [fab]
    n = max(2, int((end - hy) / 0.26))
    for i in range(1, n):
        y = hy + (end - hy) * i / n
        if y > rear - 0.05:
            continue
        closed.append(K.project_line("roof_bow", ref, [(x / 10 * (xw - 0.03), y) for x in range(-10, 11)],
                                     K.top_frame(), 0.014, M["fabric_rib"], offset=0.012))
    return fixed, closed, _rolled_canvas(ref, M, xw, rear)


def _rolled_canvas(ref, M, xw, rear):
    """The canvas rolled up and strapped down at the rear of the opening."""
    r = 0.055
    y = rear - ROOF_INSET - 0.005
    # follow the roof's camber across the car in short rolls
    out = []
    w = 2 * (xw - 0.03)
    segs = 5
    for i in range(segs):
        x0 = -w / 2 + w * i / segs
        x1 = x0 + w / segs
        xc = (x0 + x1) / 2
        zc = max(K.on_top(ref, xc, y + d)[0].z for d in (-r, 0, r))
        out.append(C.cylinder("roof_roll", r, x1 - x0 + 0.004, segs=10, axis="X", loc=(xc, y, zc + r + 0.016),
                              material=M["fabric"]))
    for sx in (-1, 1):
        xs = sx * w * 0.3
        zs = max(K.on_top(ref, xs, y + d)[0].z for d in (-r, 0, r))
        out.append(C.cylinder("roof_strap", r + 0.004, 0.03, segs=10, axis="X", loc=(xs, y, zs + r + 0.016),
                              material=M["fabric_rib"]))
    return out


# ------------------------------------------------------------------ Abarth

def abarth_lid_cut(shell_obj):
    _apply_cutters(shell_obj, [S._prism(LID_SALOON, lambda u, v, d: (u, d, v), 0.95, 2.6)])


def abarth_lid(ref, M, lid_bits, angle=34):
    """The engine lid propped open on a stay (cooling for the hot twin)."""
    panel = K.project_poly("engine_lid", ref, K.offset_poly(LID_SALOON, 0.004), K.rear_frame(), M["paint"],
                           offset=0.0, cuts=4)
    K.solidify(panel, 0.012, M["cabin"])
    lid = C.join([panel] + lid_bits, "engine_lid")
    hinge, _ = K.on_rear(ref, 0, 0.90)
    hinge = hinge + Vector((0, 0.01, 0.0))
    bottom, _ = K.on_rear(ref, 0.22, 0.54)
    C.set_origin(lid, hinge)
    lid.rotation_euler = (math.radians(angle), 0, 0)
    bpy.context.view_layer.update()
    C.apply_transform(lid)
    # stay from the bottom of the lid down to the body below the opening
    rel = bottom - hinge
    a = math.radians(angle)
    tip = hinge + Vector((rel.x, rel.y * math.cos(a) - rel.z * math.sin(a), rel.y * math.sin(a) + rel.z * math.cos(a)))
    foot, _ = K.on_rear(ref, 0.30, 0.50)
    stay = _tube("lid_stay", foot + Vector((0, 0.012, 0)), tip + Vector((0, -0.004, -0.016)), 0.006, M["chrome"],
                 segs=5)
    return [lid, stay]


def abarth_engine(M):
    """Air-cooled twin seen through the propped lid, plus the finned
    Abarth sump hanging under the tail."""
    out = [
        C.box_minmax("engine_block", (-0.17, 1.03, 0.30), (0.12, 1.28, 0.54), M["engine"]),
        C.box_minmax("engine_shroud", (0.10, 1.00, 0.36), (0.26, 1.30, 0.66), M["engine_black"]),
        C.box_minmax("rocker_cover", (-0.15, 1.07, 0.54), (0.08, 1.24, 0.585), M["engine"]),
        C.cylinder("air_filter", 0.10, 0.07, segs=12, loc=(-0.06, 1.14, 0.63), material=M["chrome"]),
        C.cylinder("air_filter_top", 0.06, 0.02, segs=10, loc=(-0.06, 1.14, 0.675), material=M["engine_black"]),
        C.cylinder("distributor", 0.025, 0.08, segs=6, loc=(-0.20, 1.20, 0.52), material=M["engine_black"]),
        C.cylinder("coil", 0.03, 0.10, segs=6, axis="Y", loc=(0.0, 1.32, 0.44), material=M["engine_black"]),
        C.box_minmax("sump", (-0.15, 1.31, 0.175), (0.15, 1.60, 0.252), M["engine"]),
    ]
    for i in range(5):
        x = -0.12 + i * 0.06
        out.append(C.box_minmax("sump_fin", (x - 0.006, 1.33, 0.15), (x + 0.006, 1.58, 0.176), M["engine"]))
    return out


def flares(ref, g, M):
    """695 SS: bolt-on wheel arch flares, a lip proud of each arch."""
    out = []
    R = ARCH_R
    for axle in (g.axle_f, g.axle_r):
        for sx in (1, -1):
            rings = []
            for t in range(-12, 193, 12):
                ang = math.radians(t)
                cy, cz = math.cos(ang), math.sin(ang)

                def surf(r):
                    y, z = axle - cy * r, HUB_Z + cz * r
                    res = _ray_hit(ref, (sx * 3, y, z), (-sx, 0, 0))
                    return (abs(res[0].x) if res else None), y, z
                xo, yo, zo = surf(R + 0.08)
                xi, yi, zi = surf(R + 0.012)
                if xo is None or xi is None:
                    continue
                prof = [(xi - 0.012, R + 0.002), (xi + 0.04, R + 0.004), (xo + 0.035, R + 0.04),
                        (xo + 0.004, R + 0.085), (xo - 0.012, R + 0.085)]
                rings.append([(sx * px, axle - cy * r, HUB_Z + cz * r) for px, r in prof])
            n = 5
            verts = [v for r in rings for v in r]
            faces = []
            for i in range(len(rings) - 1):
                for k in range(n):
                    a, b = i * n + k, i * n + (k + 1) % n
                    faces.append((a, b, b + n, a + n))
            faces.append(tuple(range(n)))
            last = (len(rings) - 1) * n
            faces.append(tuple(last + k for k in range(n - 1, -1, -1)))
            o = C.mesh_obj("flare", verts, faces, M["paint"])
            _fix_normals(o)
            K.smooth(o, 40)
            out.append(o)
    return out


# ------------------------------------------------------------------ Jolly

def jolly_bits(ref, g, M):
    """Low wrap-free windscreen in a chrome frame, and the fringed striped
    canopy on four thin poles."""
    body, glass = [], []
    y0 = g.screen[-1][1] + 0.01
    bl = [K.on_top(ref, sx * 0.47, y0)[0] + Vector((0, 0, 0.004)) for sx in (-1, 1)]
    tl = [p + Vector((0, 0.085, 0.215)) for p in bl]
    corners = [bl[0], bl[1], tl[1], tl[0]]
    pane = C.mesh_obj("jolly_screen", [tuple(c) for c in corners], [(0, 1, 2, 3)], M["glass"])
    glass.append(pane)
    for a, b in zip(corners, corners[1:] + corners[:1]):
        body.append(_tube("screen_frame", a, b, 0.011, M["chrome"], segs=6))
    # canopy
    zt = 1.40
    for sx in (1, -1):
        foot = K.on_top(ref, sx * 0.575, -0.605)[0]
        body.append(_tube("canopy_pole", foot - Vector((0, 0, 0.01)), (sx * 0.575, -0.605, zt), 0.011, M["chrome"],
                          segs=6))
        body.append(_tube("canopy_pole", (sx * 0.575, 0.88, 0.70), (sx * 0.575, 0.88, zt), 0.011, M["chrome"],
                          segs=6))
    canvas = C.mat("CanopyStripes", image=_stripes("canopy_stripes", "#f3efe6", "#3fb5b0", 10), rough=0.95)
    top = C.box_minmax("canopy", (-0.63, -0.66, zt), (0.63, 0.98, zt + 0.015), canvas)
    K.planar_uv(top, 0, 1)
    body.append(top)
    fr_a = C.mat("FringeWhite", "#f3efe6", rough=0.95)
    fr_b = C.mat("FringeTeal", "#3fb5b0", rough=0.95)
    i = 0
    for x in [-0.61 + k * 0.05 for k in range(25)]:
        for y in (-0.655, 0.975):
            body.append(C.box("fringe", (0.03, 0.004, 0.07), (x, y, zt - 0.035), fr_a if i % 2 else fr_b))
            i += 1
    for y in [-0.62 + k * 0.05 for k in range(32)]:
        for x in (-0.625, 0.625):
            body.append(C.box("fringe", (0.004, 0.03, 0.07), (x, y, zt - 0.035), fr_a if i % 2 else fr_b))
            i += 1
    return body, glass


# ------------------------------------------------------------------ interior

DOOR_OPEN_DEG = 60
DRIVER_X = -0.27     # right-hand drive: the driver sits at -X (Godot +X after the export turn)


def _seat_front(x, y, M, wicker=False):
    """Thin period seat: flat cushion, slim upright backrest on a tube frame."""
    cov = M["wicker"] if wicker else M["vinyl"]
    out = []
    cush = C.box_minmax("cushion", (x - 0.20, y - 0.20, 0.25), (x + 0.20, y + 0.22, 0.35), cov)
    out.append(cush)
    back = _leaned_box("back", (0.40, 0.07, 0.52), (y + 0.25, 0.33), 0.27, 14, cov)
    back.location.x += x
    C.apply_transform(back)
    out.append(back)
    for o in (cush, back):
        C.box_uv(o, 0.45)
    if not wicker:
        out.append(C.box_minmax("piping", (x - 0.202, y - 0.205, 0.335), (x + 0.202, y - 0.185, 0.352),
                                M["piping"]))
        # tuck-and-roll: raised ribs running front to back on the cushion
        # and up the backrest, piped round the edge
        for i in range(5):
            rx = x - 0.12 + i * 0.06
            out.append(C.box_minmax("rib", (rx - 0.022, y - 0.17, 0.35), (rx + 0.022, y + 0.20, 0.362), cov))
            rib = _leaned_box("rib_back", (0.044, 0.012, 0.42), (y + 0.25, 0.33), 0.29, 14, cov)
            rib.location.x += rx
            rib.location.y -= 0.039
            C.apply_transform(rib)
            out.append(rib)
        top = _leaned_box("back_piping", (0.404, 0.074, 0.016), (y + 0.25, 0.33), 0.53, 14, M["piping"])
        top.location.x += x
        C.apply_transform(top)
        out.append(top)
    for dx in (-0.17, 0.17):
        for dy in (-0.15, 0.17):
            out.append(C.box_minmax("seat_leg", (x + dx - 0.012, y + dy - 0.012, 0.20), (x + dx + 0.012,
                                    y + dy + 0.012, 0.25), M["chrome"]))
    return out


def interior(M, spec, g, cab):
    """Cabin fitted inside the shell, clear of the wheel tubs (front inner
    walls at x 0.33, rear 0.43), the glass and the doors."""
    dy = g.axle_f + 0.92
    jolly = spec.get("body") == "jolly"
    wicker = jolly
    bits = []
    bits.append(C.box_minmax("floor", (-0.49, -0.59 + dy, 0.18), (0.49, 0.59 + dy, 0.20), M["cabin"]))
    bits.append(C.box_minmax("floor_r", (-0.40, 0.59 + dy, 0.18), (0.40, 0.74 + dy, 0.20), M["cabin"]))
    for x in (DRIVER_X, -DRIVER_X):
        bits.append(C.box_minmax("mat", (x - 0.17, -0.59 + dy, 0.20), (x + 0.17, -0.12 + dy, 0.208), M["rubber"]))
    bits.append(C.box_minmax("tunnel", (-0.065, -0.60 + dy, 0.20), (0.065, 0.44 + dy, 0.26), M["cabin"]))
    bits.append(C.box_minmax("bulkhead_f", (-0.30, -0.64 + dy, 0.20), (0.30, -0.605 + dy, 0.64), M["cabin"]))
    # dashboard: a painted metal shelf under the windscreen (black padded on the 500 L)
    black = spec.get("dash") == "black"
    prof = [(-0.585, 0.872), (-0.53, 0.862), (-0.505, 0.845), (-0.50, 0.80), (-0.52, 0.765), (-0.60, 0.755)]
    prof = [(y + dy, z) for y, z in prof]
    dmat = M["dash_black"] if black else M["paint"]
    dash = _fitted_profile("dash", prof, cab, [dmat, M["cabin"]], [0, 0, 0, 0, 1, 1], margin=0.02, cap=0.60)
    bits.append(dash)
    # open parcel tray under the dash
    hw = min(_half_width(cab, -0.60 + dy, 0.68, 0.03), _half_width(cab, -0.47 + dy, 0.68, 0.03), 0.56)
    bits.append(C.box_minmax("parcel_tray", (-0.17, -0.60 + dy, 0.66), (hw, -0.47 + dy, 0.675), M["cabin"]))
    bits.append(C.box_minmax("parcel_lip", (-0.17, -0.48 + dy, 0.675), (hw, -0.465 + dy, 0.70), M["cabin"]))
    needle_mat = C.mat("Needle", "#c8281a", rough=0.4)
    needles = []
    if black:
        # 500 L: rectangular binnacle in front of the driver, a speedo and a
        # fuel gauge in chrome bezels
        bits.append(C.box_minmax("binnacle", (DRIVER_X - 0.15, -0.53 + dy, 0.79), (DRIVER_X + 0.15, -0.49 + dy, 0.88),
                                 M["dash_black"]))
        dials = ((-0.065, "speedo_l", 140, 20, "KMH", True, "Needle_Speed_140"),
                 (0.065, "fuel_l", 1, 1, "FUEL", False, "Needle_Fuel_1"))
        for dx, tex, vmax, step, units, odo, nname in dials:
            m = CB._frame((DRIVER_X + dx, -0.4885 + dy, 0.835), (-1, 0, 0), (0, 0, 1))
            img = CB.dial_tex(tex, vmax, step, face=(0.05, 0.05, 0.055), ink=(0.9, 0.9, 0.86),
                              tick_step=step / 4, units=units, odo=odo)
            bits.append(CB._disc("gauge", 0.04, m, C.mat("Dial_" + tex, image=img, rough=0.4)))
            bits.append(CB._ring("bezel", 0.039, 0.046, 0.006, m @ Matrix.Translation((0, 0, -0.001)), M["chrome"]))
            needles.append(CB.needle(nname, m, -0.006, 0.036, 0.003, needle_mat, 0.0015))
            if odo:
                needles.append(CB.odometer(m, 0.04, CB.ODO_Y_DIAL, 0.0008))
    else:
        # the single round speedometer in the middle of the dash: cream face,
        # chrome pod and bezel, odometer, a red needle on a black boss
        bits.append(C.cylinder("speedo_pod", 0.068, 0.05, segs=16, axis="Y", loc=(0, -0.495 + dy, 0.815),
                               material=M["chrome"]))
        m = CB._frame((0, -0.469 + dy, 0.815), (-1, 0, 0), (0, 0, 1))
        img = CB.dial_tex("speedo_nuova", 120, 20, face=(0.9, 0.87, 0.78), ink=(0.08, 0.08, 0.08), tick_step=5)
        bits.append(CB._disc("gauge", 0.06, m, C.mat("Dial_speedo_nuova", image=img, rough=0.4)))
        bits.append(CB._ring("bezel", 0.059, 0.068, 0.007, m @ Matrix.Translation((0, 0, -0.001)), M["chrome"]))
        bits.append(CB._place(C.cylinder("needle_boss", 0.008, 0.004, segs=10, loc=(0, 0, 0.003), material=M["knob"]), m))
        needles.append(CB.needle("Needle_Speed_120", m, -0.01, 0.054, 0.0035, needle_mat, 0.0015))
        needles.append(CB.odometer(m, 0.06, CB.ODO_Y_DIAL, 0.0008))
    # ignition key beside the switches
    kx = 0.215 if not black else 0.24
    bits.append(C.cylinder("ign", 0.012, 0.012, segs=10, axis="Y", loc=(kx, -0.494 + dy, 0.79), material=M["chrome"]))
    bits.append(C.box("key", (0.008, 0.03, 0.018), (kx, -0.475 + dy, 0.79), M["chrome"]))
    bits.append(C.box("key_fob", (0.022, 0.006, 0.04), (kx, -0.462 + dy, 0.765), M["knob"]))
    # chrome strip along the front edge of the dash shelf
    hw_s = min(_half_width(cab, -0.503 + dy, 0.85, 0.03), 0.58)
    # it stops either side of the speedo pod (or the 500 L binnacle)
    gx0, gx1 = (DRIVER_X - 0.16, DRIVER_X + 0.16) if black else (-0.075, 0.075)
    for sx0, sx1 in ((-hw_s, gx0), (gx1, hw_s)):
        bits.append(C.box_minmax("dash_strip", (sx0, -0.507 + dy, 0.842), (sx1, -0.501 + dy, 0.852), M["chrome"]))
    # pedals hang just behind the front axle, squeezed inboard by the wheel arch
    for x in (-0.27, -0.19, -0.11):
        bits.append(C.box("pedal", (0.05, 0.015, 0.07), (x, -0.56 + dy, 0.30), M["rubber_pad"]))
        bits.append(C.box_minmax("pedal_arm", (x - 0.006, -0.575 + dy, 0.30), (x + 0.006, -0.562 + dy, 0.45),
                                 M["trim"]))
    # floor gear lever and handbrake between the seats
    knob = Vector((0, -0.12 + dy, 0.53))
    base = Vector((0, -0.22 + dy, 0.26))
    bits.append(_tube("gear_stick", base, knob, 0.008, M["chrome"], segs=6))
    bits.append(C.cylinder("gaiter", 0.035, 0.03, segs=8, loc=tuple(base + Vector((0, 0, 0.012))),
                           material=M["knob"], r_top=0.015))
    # the knob is its own object so a fitted one can replace it
    gear_knob = C.sphere("GearKnob", 0.022, tuple(knob), M["ivory" if not black else "knob"], segs=8, rings=5)
    K.tilted_mount("Mount_GearKnob", knob, -math.atan2((knob - base).y, (knob - base).z), 0.04)
    hb = _tube("handbrake", (0, 0.02 + dy, 0.27), (0, 0.22 + dy, 0.34), 0.012, M["trim"], segs=6)
    bits.append(hb)
    bits.append(_tube("choke", (0.03, -0.05 + dy, 0.26), (0.03, 0.0 + dy, 0.31), 0.005, M["chrome"], segs=5))
    # starter and heater pull levers beside the choke, ahead of the handbrake, with ivory knobs
    for nm, lx, ly in (("starter", -0.03, -0.05), ("heater", 0.0, -0.13)):
        a, b = (lx, ly + dy, 0.26), (lx, ly + 0.045 + dy, 0.305)
        bits.append(_tube(nm, a, b, 0.005, M["chrome"], segs=5))
        bits.append(C.sphere(nm + "_knob", 0.009, b, M["ivory"], segs=6, rings=4))
    bits.append(C.sphere("choke_knob", 0.009, (0.03, 0.0 + dy, 0.31), M["ivory"], segs=6, rings=4))
    # seats
    bits += _seat_front(DRIVER_X, 0.12 + dy, M, wicker)
    bits += _seat_front(-DRIVER_X, 0.12 + dy, M, wicker)
    cov = M["wicker"] if wicker else M["vinyl"]
    rc = C.box_minmax("rear_cushion", (-0.40, 0.45 + dy, 0.20), (0.40, 0.70 + dy, 0.35), cov)
    rb = _leaned_box("rear_back", (0.80, 0.07, 0.40), (0.725 + dy, 0.33), 0.20, 8, cov)
    for o in (rc, rb):
        C.box_uv(o, 0.45)
    bits += [rc, rb]
    if g.body == "estate":
        # flat load floor over the engine, to the rear door
        hw = min(_half_width(cab, 1.0, 0.56), _half_width(cab, 1.60, 0.56), 0.55)
        bits.append(C.box_minmax("load_floor", (-0.40, 0.845 + dy, 0.53), (0.40, 1.62, 0.56), M["rubber"]))
        bits.append(C.box_minmax("load_floor_up", (-hw, 1.25, 0.56), (hw, 1.62, 0.575), M["rubber"]))
        bits.append(C.box_minmax("bulkhead_r", (-0.40, 0.82 + dy, 0.20), (0.40, 0.845 + dy, 0.53), M["cabin"]))
        shelf = (0.0, 1.30, 0.575)
    else:
        sy0, sy1, sz = 0.845, 0.93, 0.72
        hw = min(_half_width(cab, sy0, sz + 0.02), _half_width(cab, sy1, sz + 0.02), 0.56)
        bits.append(C.box_minmax("bulkhead_r", (-0.40, 0.82 + dy, 0.20), (0.40, 0.845 + dy, 0.72), M["cabin"]))
        bits.append(C.box_minmax("parcel_shelf", (-hw, sy0, sz), (hw, sy1, sz + 0.02), M["cabin"]))
        shelf = (0.20, 0.875, sz + 0.02)
    mirror = None
    if not jolly:
        # small rear-view mirror on a stalk from the header rail
        top = _roof_z(cab, 0, -0.25 + dy)
        my, mz = -0.25 + dy, top - 0.075
        bits.append(C.box("rear_mirror", (0.12, 0.02, 0.045), (0, my, mz), M["knob"]))
        bits.append(C.box_minmax("mirror_stem", (-0.01, my - 0.005, mz + 0.025), (0.01, my + 0.005, top - 0.005),
                                 M["chrome"]))
        mirror = (0, my, mz - 0.025)
        for x in (DRIVER_X, -DRIVER_X):
            t = min(_roof_z(cab, x + d, yy + dy) for d in (-0.13, 0, 0.13) for yy in (-0.22, -0.08)) - 0.008
            bits.append(C.box_minmax("visor", (x - 0.13, -0.22 + dy, t - 0.012), (x + 0.13, -0.08 + dy, t),
                                     M["headliner"]))
    interior_obj = C.join(bits, "Interior")
    wheel, column = _steering_wheel(M, dy)
    mounts_needles = needles + [gear_knob]
    interior_obj = C.join([interior_obj, column], "Interior")
    mounts = {
        "Cam_Cockpit": (DRIVER_X, 0.24 + dy, 1.06),
        "Mount_Dash": (0.24, -0.53 + dy, 0.8635),
        "Mount_Shelf": shelf,
        "Mount_Gear": tuple(knob),
    }
    if mirror:
        mounts["Mount_Mirror"] = mirror
    else:
        mounts["Mount_Mirror"] = (0, -0.47 + dy, 1.08)   # Jolly: top rail of the low windscreen
    return interior_obj, wheel, mounts, mounts_needles


def _steering_wheel(M, dy):
    """Big thin two-spoke wheel, nearly upright on a long column."""
    rim_r, tube = 0.19, 0.011
    bits = [CB.torus_rim("rim", rim_r, tube, 32, M["wheel"], ts=6)]
    bits.append(C.cylinder("hub", 0.038, 0.05, segs=10, axis="Y", material=M["wheel"]))
    bits.append(K.lamp_disc("horn", 0.028, 0.01, (0, 0.028, 0), (0, 1, 0), M["chrome"], segs=10))
    for a in (-0.30, math.pi + 0.30):
        sp = C.box("spoke", (rim_r - 0.035, 0.012, 0.022),
                   (math.cos(a) * (rim_r / 2 + 0.017), 0, math.sin(a) * (rim_r / 2 + 0.017)), M["wheel"])
        sp.rotation_euler = (0, -a, 0)
        C.apply_transform(sp)
        bits.append(sp)
    tilt = math.radians(30)
    hub = Vector((DRIVER_X, -0.36 + dy, 0.80))
    axis = Vector((0, math.cos(tilt), math.sin(tilt)))
    sw = C.join(bits, "SteeringWheel")
    sw.rotation_euler = (tilt, 0, 0)
    sw.location = hub
    # a fitted wheel goes here: Godot -Z down the column, +Y to twelve o'clock
    K.tilted_mount("Mount_SteeringWheel", hub, tilt)
    column = C.cylinder("column", 0.018, 0.20, segs=6, axis="Y", loc=hub - axis * 0.125, material=M["knob"])
    column.rotation_euler = (tilt, 0, 0)
    C.apply_transform(column)
    return sw, column


def _door_card(door, sx, M, g):
    """Flat vinyl card, window winder and pull on the inside of the door."""
    y0, y1 = g.door
    ym = (y0 + y1) / 2
    x = sx * 0.605
    xa, xb = sorted((x, x - sx * 0.012))
    out = [C.box_minmax("door_card", (xa, y0 + 0.06, 0.40), (xb, y1 - 0.06, 0.74), M["vinyl_plain"])]
    xi = x - sx * 0.012
    out.append(_tube("winder", (xi, ym + 0.12, 0.62), (xi - sx * 0.03, ym + 0.12, 0.62), 0.008, M["chrome"], segs=6))
    out.append(C.sphere("winder_knob", 0.014, (xi - sx * 0.035, ym + 0.12, 0.58), M["ivory"], segs=6, rings=4))
    out.append(_tube("pull", (xi - sx * 0.02, ym - 0.12, 0.70), (xi - sx * 0.02, ym + 0.02, 0.70), 0.008, M["chrome"],
                     segs=6))
    # pleated panel across the lower half, a chrome strip along the top
    # edge and a little chrome opening lever toward the back
    xp = sorted((xi, xi - sx * 0.006))
    for k in range(4):
        z = 0.43 + k * 0.045
        out.append(C.box_minmax("card_pleat", (xp[0], y0 + 0.09, z), (xp[1], y1 - 0.09, z + 0.03), M["vinyl"]))
    xs = sorted((xi, xi - sx * 0.008))
    out.append(C.box_minmax("card_strip", (xs[0], y0 + 0.07, 0.722), (xs[1], y1 - 0.07, 0.732), M["chrome"]))
    out.append(C.box_minmax("card_piping", (xp[0], y0 + 0.07, 0.405), (xp[1], y1 - 0.07, 0.415), M["piping"]))
    xl = sorted((xi, xi - sx * 0.018))
    out.append(C.box_minmax("door_lever", (xl[0], y1 - 0.20, 0.645), (xl[1], y1 - 0.11, 0.66), M["chrome"]))
    return out


# ------------------------------------------------------------------ shared cabin helpers
# (same as fiat500_modern.py; copied so the classics do not depend on its internals)

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


def _leaned_box(name, size, base, h, lean, mat):
    """Box whose centre sits h up a line leaning back by lean degrees from base (y, z)."""
    a = math.radians(lean)
    o = C.box(name, size, (0, base[0] + h * math.sin(a), base[1] + h * math.cos(a)), mat)
    o.rotation_euler = (-a, 0, 0)
    C.apply_transform(o)
    return o


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


# ------------------------------------------------------------------ build

HINGE_X, HINGE_DY = 0.672, 0.05


def _headliner(body, M):
    me = body.data
    ci = list(me.materials).index(M["cabin"])
    me.materials.append(M["headliner"])
    hi = len(me.materials) - 1
    for p in me.polygons:
        if p.material_index == ci and p.center.z > 0.95:
            p.material_index = hi


def build(spec):
    """Build one classic into the empty scene; returns the exported objects.

    Door hinges: front-hinged doors (F/L/R) have their origin just ahead of
    the front shut line and open like the modern cars (Door_L negative
    angle about local Z/Godot Y). Rear-hinged suicide doors (Nuova, Sport,
    D, Giardiniera, the Abarths) have the origin just behind the rear shut
    line and open the opposite way (Door_L positive). The sign is stored on
    each door as the custom property `open_sign`."""
    C.clear_material_cache()
    style = spec.get("body", "saloon")
    g = Geom(style)
    jolly = style == "jolly"
    doors = None if jolly else spec.get("doors", "suicide")
    abarth = spec.get("abarth")
    ride = spec.get("ride", 0.0)
    shell_obj, st = shell(g)
    M = materials(spec)

    ref = C.link(bpy.data.objects.new("ref", shell_obj.data.copy()))
    if jolly:
        cut_jolly(shell_obj, g)
    else:
        cut_windows(shell_obj, g)
        roof_opening(shell_obj, g, spec)
    if abarth:
        abarth_lid_cut(shell_obj)
    body_bits = []
    if doors:
        pieces, outline = split_doors(shell_obj, g)
        body_bits.append(door_shut_lines(pieces, outline, M["seam"]))
        shell_obj = C.join([shell_obj] + pieces, "shell")
    classify(shell_obj, g)
    nrm = surface_normals(ref, [shell_obj])
    parts = K.split_by_tag(shell_obj, {
        "Body": {"Paint": M["paint"], "Trim": M["trim"], "Under": M["under"]},
        "Door_L": {"DoorL": M["paint"]},
        "Door_R": {"DoorR": M["paint"]},
    }, smooth_angle=40)
    body = parts["Body"]

    if jolly:
        glass, door_glass = {"panes": [], "seals": []}, {}
    else:
        glass, door_glass = windows(ref, g, M, spec)
    body_bits += glass["seals"]
    lid_bits = []
    door_bits = {1: [], -1: []}
    body_bits += front_details(ref, g, M, spec)
    body_bits += rear_details(ref, g, M, spec, lid_bits)
    body_bits += side_details(ref, g, M, spec, door_bits)
    roof_fixed, roof_closed, roof_open = fabric_roof(ref, g, M, spec)
    body_bits += roof_fixed
    if abarth:
        body_bits += abarth_lid(ref, M, lid_bits)
        body_bits += abarth_engine(M)
        if abarth == "695":
            body_bits += flares(ref, g, M)
    else:
        body_bits += lid_bits
    if jolly:
        jb, jg = jolly_bits(ref, g, M)
        body_bits += jb
        glass["panes"] += jg

    K.solidify_along(body, 0.018, M["cabin"], nrm)
    if not jolly:
        _headliner(body, M)
    root = [body, C.join(glass["panes"], "Glass")]

    if doors:
        for side, sx in (("L", 1), ("R", -1)):
            door = parts["Door_" + side]
            card = _door_card(door, sx, M, g)
            K.solidify_along(door, 0.018, M["cabin"], nrm, gap=0.006)
            door = C.join([door] + card + door_glass[sx]["seals"] + door_bits[sx], "Door_" + side)
            if doors == "suicide":
                hy = g.door[1] + HINGE_DY
                door["open_sign"] = sx          # Door_L opens with a positive angle
            else:
                hy = g.door[0] - HINGE_DY
                door["open_sign"] = -sx         # as the modern cars
            door["hinge"] = "rear" if doors == "suicide" else "front"
            C.set_origin(door, (sx * HINGE_X, hy, 0.6))
            gl = C.join(door_glass[sx]["panes"], "Door_%s_Glass" % side)
            gl.parent = door
            gl.matrix_parent_inverse = door.matrix_world.inverted()
            root.append(door)

    lamps_h = [o for o in body_bits if o.get("lamp") == "head"]
    lamps_t = [o for o in body_bits if o.get("lamp") == "tail"]
    rest = [o for o in body_bits if o not in lamps_h and o not in lamps_t]
    body = C.join([body] + rest, "Body")
    root[0] = body
    root.append(C.join(lamps_h, "Lights_Head"))
    root.append(C.join(lamps_t, "Lights_Tail"))
    if roof_closed:
        root.append(C.join(roof_closed, "Roof_Closed"))
        rolled = C.join(roof_open, "Roof_Open")
        rolled["hidden"] = True         # shown when the roof is rolled back
        root.append(rolled)

    cab = _cabin_bvh([o for o in root if o.name != "Roof_Open"])
    inter, wheel_obj, mounts, needles = interior(M, spec, g, cab)
    root += [inter, wheel_obj] + needles

    ws = spec.get("wheels", "classic12")
    body["wheels"] = ws
    # Godot 4.3 drops glTF extras, so the style also rides on an empty's name
    C.empty("WheelStyle_" + ws, (0, 0, 0), size=0.05)
    hub_z = W.radius(ws)
    for nm, x, y, tr in (("FL", 1, g.axle_f, TRACK_F), ("FR", -1, g.axle_f, TRACK_F),
                         ("RL", 1, g.axle_r, TRACK_R), ("RR", -1, g.axle_r, TRACK_R)):
        root.append(W.build("Wheel_" + nm, ws, loc=(x * tr / 2, y, hub_z), right=x < 0))
        C.empty("Hub_" + nm, (x * tr / 2, y, hub_z), size=0.1)

    # roof mount on the roof centre (canopy frame on the Jolly)
    ry = g.roof_top[0]
    if jolly:
        rz = 1.415
    else:
        rz = K.on_top(ref, 0, ry)[0].z + (0.012 if spec.get("roof", "steel").startswith("fabric") else 0.0)
    bumper = K.on_front(ref, 0, 0.365)[0]
    mounts.update({
        "Mount_Exhaust": (0.24, g.tail - 0.07, 0.27),
        "Mount_Roof": (0, ry, rz),
        "Mount_Spotlights": (0, bumper.y - 0.045, 0.39),
    })
    # engine-lid luggage rack: saloons and the Jolly (the Abarths ride with
    # the lid propped, the Giardiniera has its engine under the floor)
    if spec.get("body", "saloon") != "estate" and not spec.get("abarth"):
        mounts["Mount_RearRack"] = tuple(K.on_rear(ref, 0, LID_RACK_Z)[0])
    mounts.update(K.mod_mounts((ref,), 0.365, 0.36, 0.28, g.axle_r, TRACK_R / 2, 0.33))
    for nm, loc in mounts.items():
        C.empty(nm, loc)
    bpy.data.objects.remove(ref, do_unlink=True)
    if ride:
        for o in bpy.data.objects:
            if o.parent is None and not o.name.startswith(("Wheel_", "Hub_")):
                o.location.z += ride
    K.door_markers(DOOR_OPEN_DEG)
    return root


# ------------------------------------------------------------------ parts

def exhaust(style):
    """Classic exhaust tips; origin = Mount_Exhaust, pipe running back (+Y)."""
    chrome = C.mat("Chrome", "#dcdee0", rough=0.15, metal=0.95)
    dark = C.mat("ExhaustDark", "#2a2826", rough=0.6, metal=0.6)
    if style == "abarth_classic":
        # the Abarth megaphone: a long chrome cone flaring out under the tail
        bits = [C.cylinder("pipe", 0.022, 0.20, segs=10, axis="Y", loc=(0, -0.08, 0), material=dark)]
        prof = [(0.0, 0.02), (0.024, 0.02), (0.026, 0.05), (0.036, 0.14), (0.052, 0.25), (0.056, 0.27),
                (0.048, 0.27), (0.034, 0.24), (0.0, 0.24)]
        cone = K.revolve("megaphone", [(r, y) for r, y in prof], 12, lambda i: chrome)
        cone.rotation_euler = (0, 0, math.radians(90))     # revolve runs along X: turn it to Y
        C.apply_transform(cone)
        bits.append(cone)
        return C.join(bits, "Exhaust")
    raise ValueError(style)
