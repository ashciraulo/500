"""Fridge magnets: little souvenirs from places around Perth, one for each
spot the player drives to, collected on the townhouse fridge.

Each is a 12 x 12 pixel picture cut out round its outline and 6 mm thick, as
the cheap souvenir-shop kind are: rows of pixels become boxes, the front
shows the picture and the edges take the colour of the pixel beside them.
About 6 cm across. Faces -Y in Blender (+Z in Godot), origin at the middle
of the back, which sits on the fridge door. All original art; no brands.
"""
from . import common as C

PX = 0.005          # metres per pixel
DEPTH = 0.006
N = 12

PALETTE = {
    "k": "#1c1b1d", "w": "#f2efe6", "r": "#c3302a", "g": "#5f8f3c", "G": "#2f5a2c",
    "b": "#2f78b8", "B": "#1f3a66", "y": "#f0c33a", "o": "#e47a2a", "n": "#7a5232",
    "c": "#efe0b8", "s": "#9fd2e6", "e": "#9aa2a8", "p": "#e98aa6",
}

# 12 x 12, top row first; "." is cut away
ART = {
    # Fremantle: the north mole's red lighthouse on its base
    "lighthouse": [
        ".....kk.....",
        "....kyyk....",
        "....kwwk....",
        "...kkkkkk...",
        "....krrk....",
        "....krrk....",
        "....kwwk....",
        "....krrk....",
        "...krrrrk...",
        "...krrrrk...",
        ".bbccccccbb.",
        "bbbbbbbbbbbb",
    ],
    # the river: a black swan with its red beak
    "swan": [
        "............",
        "..kk........",
        ".kkr........",
        ".kk.........",
        ".kk.........",
        "..kk....kk..",
        "..kkkkkkkkk.",
        ".kkkkkkkkkk.",
        ".kkkkkkkkk..",
        "bbbbbbbbbbbb",
        ".bbbbbbbbbb.",
        "............",
    ],
    # Pelican Point
    "pelican": [
        "............",
        "...www......",
        "..wwwwk.....",
        "..wwwyyyyy..",
        "...ww.yyy...",
        "...ww.......",
        "..wwwww.....",
        ".wwwwwwwe...",
        ".wwwwwwee...",
        "..wwwwee....",
        "...y..y.....",
        "..yy.yy.....",
    ],
    # Trigg: a striped board on a wave
    "surfboard": [
        ".........yy.",
        "........yyy.",
        ".......yry..",
        "......yry...",
        ".....yry....",
        "....yry.....",
        "...yry......",
        "..yyy.......",
        ".bbbb..bbb..",
        "bbwwbbbbwbbb",
        "bbbbbbbbbbbb",
        ".bbbbbbbbbb.",
    ],
    # Kings Park: a gum on the grass
    "gum_tree": [
        "....GGG.....",
        "..GGgGGGG...",
        ".GgggGGgGG..",
        ".GGgGGGgGG..",
        "..GGGnGGG...",
        ".....n......",
        "....nn......",
        "....n.n.....",
        "....n.......",
        "...nn.......",
        ".gggggggggg.",
        "..gggggggg..",
    ],
    # the city: a glass spire with copper wings
    "bell_tower": [
        ".....s......",
        ".....s......",
        "....sss.....",
        "....sss.....",
        "...osssso...",
        "..oo.ss.oo..",
        ".oo..ss..oo.",
        ".o...ss...o.",
        "....ssss....",
        "...ssssss...",
        "..eeeeeeee..",
        "..eeeeeeee..",
    ],
    # Fishing Boat Harbour: chips in a paper cone
    "fish_chips": [
        "..yy.y.yy...",
        ".yyyyyyyyy..",
        ".ycyyyycyy..",
        "..wwwwwwww..",
        "..wwwbwwww..",
        "...wwwwww...",
        "...wwbwww...",
        "....wwww....",
        "....wwww....",
        ".....ww.....",
        ".....ww.....",
        "............",
    ],
    # Herdsman Lake: a cockatoo on a branch
    "cockatoo": [
        "...yy.......",
        "..yyy.......",
        "..www.......",
        ".wwkww......",
        ".wwwwk......",
        "..wwwwww....",
        "..wwwwwww...",
        "...wwwwwww..",
        "....wwwwww..",
        ".....www.ww.",
        "...nnnnnnnn.",
        "............",
    ],
    # the car meet: a little round cream car
    "little_car": [
        "............",
        "............",
        "............",
        "....ccc.....",
        "...csssc....",
        "..cccccccc..",
        ".cccccccccc.",
        ".cwccccccwc.",
        ".kkcccccckk.",
        ".kk......kk.",
        "............",
        "............",
    ],
    # Mends St jetty: a bream
    "bream": [
        "............",
        "............",
        "............",
        "....eee.....",
        "..eeeeee..e.",
        ".eweeeeee.ee",
        ".eeeeeeeeeee",
        "..eeeeeee.ee",
        "...ey.ey..e.",
        "............",
        "............",
        "............",
    ],
    # the river ferry
    "ferry": [
        "............",
        "............",
        ".....e......",
        "....www.....",
        "..wwBwBww...",
        ".wwwwwwwww..",
        ".BBBBBBBBBB.",
        "..wwwwwwww..",
        "bbbbbbbbbbbb",
        "bbsbbbbbbsbb",
        "............",
        "............",
    ],
    # Scarborough: the sun going into the sea
    "sunset": [
        "............",
        "............",
        "oooooooooooo",
        "oooyyyyyoooo",
        "ooyyyyyyyooo",
        "rryyyyyyyyrr",
        "rrryyyyyyrrr",
        "bbbbbbbbbbbb",
        "bbwwbbbbbwwb",
        "bbbbbbbbbbbb",
        "............",
        "............",
    ],
    # a kangaroo paw in flower
    "kangaroo_paw": [
        "..r...rr....",
        ".rrr.rrr....",
        ".rr..rr.....",
        "..g..rg..r..",
        "..g..g..rrr.",
        "..g.g...rg..",
        "...gg..g.g..",
        "...g..g..g..",
        "...g.g...g..",
        "...gg...g...",
        "....ggggg...",
        "....GGGG....",
    ],
}
NAMES = tuple(ART)


def _image(name):
    rows = ART[name]
    assert len(rows) == N and all(len(r) == N for r in rows), name

    def px(x, y):
        ch = rows[N - 1 - y][x]
        return C._hex(PALETTE.get(ch, "#000000"))
    return C.make_image("magnet_" + name, N, N, px)


def magnet(name):
    """The cut-out magnet as one mesh with a nearest-pixel picture."""
    rows = ART[name]
    mat = C.mat("Magnet_" + name, "#ffffff", rough=0.35, image=_image(name))
    verts, faces, uvs = [], [], []

    def quad(corners, uv4):
        i = len(verts)
        verts.extend(corners)
        faces.append((i, i + 1, i + 2, i + 3))
        uvs.extend(uv4)

    # centre the outline's bounding box on the origin
    cells = [(x, N - 1 - r) for r, row in enumerate(rows) for x, ch in enumerate(row) if ch != "."]
    cx = (min(x for x, _ in cells) + max(x for x, _ in cells) + 1) / 2
    cz = (min(z for _, z in cells) + max(z for _, z in cells) + 1) / 2
    X = lambda u: (u - cx) * PX          # noqa: E731
    Z = lambda v: (v - cz) * PX          # noqa: E731
    yf, yb = -DEPTH, 0.0
    for r, row in enumerate(rows):
        z = N - 1 - r
        x = 0
        while x < N:
            if row[x] == ".":
                x += 1
                continue
            a = x
            while x < N and row[x] != ".":
                x += 1
            b = x                                  # run covers pixels a..b-1
            u0, u1, v0, v1 = a / N, b / N, z / N, (z + 1) / N
            vm = (z + 0.5) / N
            # front (-Y) and back
            quad([(X(a), yf, Z(z)), (X(b), yf, Z(z)), (X(b), yf, Z(z + 1)), (X(a), yf, Z(z + 1))],
                 [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
            quad([(X(b), yb, Z(z)), (X(a), yb, Z(z)), (X(a), yb, Z(z + 1)), (X(b), yb, Z(z + 1))],
                 [(u1, v0), (u0, v0), (u0, v1), (u1, v1)])
            # the ends of the run take their end pixels' colour
            ua, ub = (a + 0.5) / N, (b - 0.5) / N
            quad([(X(a), yb, Z(z)), (X(a), yf, Z(z)), (X(a), yf, Z(z + 1)), (X(a), yb, Z(z + 1))], [(ua, vm)] * 4)
            quad([(X(b), yf, Z(z)), (X(b), yb, Z(z)), (X(b), yb, Z(z + 1)), (X(b), yf, Z(z + 1))], [(ub, vm)] * 4)
            # top and bottom edges where the row above/below is cut away
            for k in range(a, b):
                uk = (k + 0.5) / N
                above = r == 0 or rows[r - 1][k] == "."
                below = r == N - 1 or rows[r + 1][k] == "."
                if above:
                    quad([(X(k), yf, Z(z + 1)), (X(k + 1), yf, Z(z + 1)), (X(k + 1), yb, Z(z + 1)), (X(k), yb, Z(z + 1))],
                         [(uk, vm)] * 4)
                if below:
                    quad([(X(k), yb, Z(z)), (X(k + 1), yb, Z(z)), (X(k + 1), yf, Z(z)), (X(k), yf, Z(z))],
                         [(uk, vm)] * 4)
    o = C.mesh_obj("magnet", verts, faces, mat)
    layer = o.data.uv_layers.new(name="UVMap")
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            layer.data[li].uv = uvs[o.data.loops[li].vertex_index]
    return [o]
