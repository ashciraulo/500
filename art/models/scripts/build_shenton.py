"""15 Little Shenton Lane, Northbridge: the player's townhouse and its block.

    python3.11 art/models/scripts/build_shenton.py [--render]

Writes art/models/home/shenton/:
  shenton_house.glb     walls, floors, stairs, roof, windows, doors and markers
  shenton_interior.glb  furniture, plants and the little mysteries
  shenton_site.glb      front garden, courtyard, shared carport and sheds,
                        both lanes and the neighbours

Layout (metres, Blender: X across the block, Y from the street at -Y to the
rear lane at +Y, Z up). The house's inside is x 0..5.4, y 0..12, with the
front wall at y = 0 facing Little Shenton Lane. Floor plan per Ash:

  Ground: lounge (front, fireplace on the x=0 wall, front door and French
  doors to the porch); hall between the under-stair storage (door at x=1.0)
  and the laundry (door opposite at x=2.1); laundry -> toilet; U-shaped
  kitchen with breakfast bar; rear living with sliding door to the courtyard.
  Stairs along the x=0 wall rise from y=8.8 toward the front.
  Upstairs: main bedroom at the front (balcony), landing, one bathroom with
  doors from the landing and from the main bedroom, a toilet between the
  bathroom and bedroom 2, bedroom 2 at the back over the courtyard.
  Out back: courtyard, gate, then the SHARED carport. Only one of the sheds
  is the player's, and it stays padlocked (the key turns up late).

Node conventions for Godot (see art/models/README.md):
  "-col" suffix      static trimesh collision on import
  Door_*, Shed_Door  origin on the hinge; swing about local Z (Godot Y)
  Spawn_*, Light_*   empties: spawn points and warm lamp positions
  Bed                walk here to end the day
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from lib import arch as A  # noqa: E402
from lib import common as C  # noqa: E402
from lib import furniture as F  # noqa: E402
from lib import lived as L  # noqa: E402
from lib import mystery as MY  # noqa: E402
from lib import studio as S  # noqa: E402
from lib import textures as TX  # noqa: E402

OUT = "art/models/home/shenton/"
W, D = 5.4, 12.0          # inside width and depth
FZ0 = 0.15                # ground floor level
CZ0 = 2.9                 # ground floor ceiling
FZ1 = 3.16                # upstairs floor level (slab 2.9..3.15 + carpet)
CZ1 = 5.9                 # upstairs ceiling
EAVE = 6.05
EXT = 0.2                 # exterior wall thickness
PARTY = 0.2


# ------------------------------------------------------------------ materials

def mats():
    m = {}
    m["render"] = C.mat("Render", image=A.tex_noise("render", "#e7d9b0", 0.025, 16, 3), rough=0.95)
    m["render_n17"] = C.mat("RenderYellow", image=A.tex_noise("render17", "#ecd58e", 0.025, 16, 4), rough=0.95)
    m["render_n13"] = C.mat("RenderCream", image=A.tex_noise("render13", "#efe6cf", 0.025, 16, 5), rough=0.95)
    m["paint"] = C.mat("WallPaint", image=A.tex_noise("wallpaint", "#dfe2d6", 0.03, 16, 6), rough=0.9)
    m["ceiling"] = C.mat("Ceiling", "#f1efe8", rough=0.95)
    m["trim"] = C.mat("TrimWhite", "#f3f1ea", rough=0.6)
    # polished jarrah: narrow, long boards, dark seams and a glossy finish
    m["boards"] = C.mat("Jarrah", image=A.tex_boards("jarrah", "#5e2617", 48, 192, 4, gap=(0.10, 0.035, 0.025),
                                                     run=1, spread=0.16), rough=0.28)
    m["carpet"] = C.mat("Carpet", image=A.tex_carpet("carpet", "#b7aa98"), rough=1.0)
    m["tiles"] = C.mat("FloorTiles", image=A.tex_tiles("floortiles", "#d9d2c3", "#a59d8f", 4, 4), rough=0.6)
    m["mosaic"] = C.mat("Mosaic", image=A.tex_checker_mosaic(), rough=0.5)
    m["walltile"] = C.mat("WallTiles", image=A.tex_tiles("walltiles", "#efe4c8", "#cfc4aa", 4, 4), rough=0.4)
    m["glass"] = C.mat("WindowGlass", "#9fb4bf", rough=0.05, metal=0.2, alpha=0.35)
    m["glass"].use_backface_culling = False
    m["door"] = C.mat("DoorWhite", "#efede6", rough=0.6)
    m["front_door"] = C.mat("FrontDoor", "#1d2321", rough=0.4)
    m["roof"] = C.mat("RoofTiles", image=A.tex_roof_tiles(base="#4f4a46"), rough=0.9)
    m["pavers"] = C.mat("Pavers", image=A.tex_herringbone(), rough=0.9)
    m["asphalt"] = C.mat("Asphalt", image=A.tex_noise("asphalt", "#3b3b3d", 0.12, 16, 7), rough=1.0)
    m["iron"] = C.mat("Iron", "#151617", rough=0.5, metal=0.6)
    m["pickets"] = C.mat("Pickets", image=A.tex_pickets(), rough=0.8)
    m["lawn"] = C.mat("Lawn", image=A.tex_noise("lawn", "#6f8a46", 0.25, 16, 8), rough=1.0)
    m["mulch"] = C.mat("Mulch", image=A.tex_noise("mulch", "#4a3524", 0.3, 16, 9), rough=1.0)
    m["timber"] = C.mat("Timber", image=A.tex_boards("timber", "#5b3f2a", 32, 32, 4, 5), rough=0.8)
    m["corrugated"] = C.mat("Corrugated", image=A.tex_corrugated("corrugated", "#9da3a6"), rough=0.6, metal=0.5)
    m["firebox"] = C.mat("Firebox", "#141210", rough=1.0)
    m["dark_window"] = C.mat("DarkWindow", "#2b343b", rough=0.12, metal=0.4)
    m["warm_window"] = C.mat("WarmWindow", "#f2c27a", rough=0.6, emit="#f2c27a", emit_strength=0.8)
    m["concrete"] = C.mat("Concrete", image=A.tex_noise("concrete", "#a9a59c", 0.1, 16, 10), rough=1.0)
    m["post"] = C.mat("CarportPost", "#3a2a1e", rough=0.8)
    return m


# ------------------------------------------------------------------ helpers

def frame_opening(axis, at, b0, b1, z0, z1, M, bucket, glass=True, bars=0, transom=None, depth=0.2):
    """White frame and glass in an opening; bars = vertical glazing bars."""
    t = 0.05
    if axis == "x":
        def box(a0, a1, q0, q1, d0, d1, mat, b):
            A.block((a0, at + d0, q0), (a1, at + d1, q1), mat, b)
    else:
        def box(a0, a1, q0, q1, d0, d1, mat, b):
            A.block((at + d0, a0, q0), (at + d1, a1, q1), mat, b)
    h = depth / 2
    box(b0, b0 + t, z0, z1, -h, h, M["trim"], bucket)
    box(b1 - t, b1, z0, z1, -h, h, M["trim"], bucket)
    box(b0 + t, b1 - t, z1 - t, z1, -h, h, M["trim"], bucket)
    box(b0 + t, b1 - t, z0, z0 + t, -h, h, M["trim"], bucket)
    if transom:
        box(b0, b1, transom - t / 2, transom + t / 2, -0.03, 0.03, M["trim"], bucket)
    for i in range(bars):
        x = b0 + (b1 - b0) * (i + 1) / (bars + 1)
        box(x - 0.02, x + 0.02, z0, z1, -0.03, 0.03, M["trim"], bucket)
    if glass:
        box(b0 + t, b1 - t, z0 + t, z1 - t, -0.005, 0.005, M["glass"], "House_Glass")


def ext_wall(axis, at, a0, a1, z0, z1, outward, M, openings=(), outer="render"):
    """Exterior wall: painted inside, rendered outside. outward = +1/-1 along
    the wall normal (the side the street or yard is on)."""
    inner = EXT - 0.03
    A.wall(axis, at, a0, a1, z0, z1, inner, M["paint"], "House-col", openings, side=outward)
    A.wall(axis, at + outward * inner, a0, a1, z0, z1, 0.03, M[outer], "House-col", openings, side=outward)


# Doors that open clockwise seen from above (HomeBase swings every other door
# anticlockwise); keep in step with OPEN_CLOCKWISE in scripts/world/home_base.gd.
OPEN_CLOCKWISE = ("Door_French_R", "Door_Balcony_R", "Shed_Door")


def _french_parts(length, height, M):
    """Glazed French door leaf: white stiles and rails, glass in a grid of
    glazing bars, built along +x from the hinge."""
    t, s, rail = 0.045, 0.07, 0.18
    parts = [C.box_minmax("stile", (0, -t / 2, 0), (s, t / 2, height), M["trim"]),
             C.box_minmax("stile", (length - s, -t / 2, 0), (length, t / 2, height), M["trim"]),
             C.box_minmax("rail", (s, -t / 2, 0), (length - s, t / 2, rail), M["trim"]),
             C.box_minmax("rail", (s, -t / 2, height - s), (length - s, t / 2, height), M["trim"]),
             C.box_minmax("glass", (s, -0.004, rail), (length - s, 0.004, height - s), M["glass"])]
    rows = 5
    for i in range(1, rows):
        z = rail + (height - s - rail) * i / rows
        parts.append(C.box_minmax("bar", (s, -0.012, z - 0.012), (length - s, 0.012, z + 0.012), M["trim"]))
    mid = length / 2
    parts.append(C.box_minmax("bar", (mid - 0.012, -0.012, rail), (mid + 0.012, 0.012, height - s), M["trim"]))
    return parts


def door(name, axis, hinge, length, z0, height, mat, sign=1, knob=True, glass=None, french=None):
    """Door leaf with its origin on the hinge. axis: the wall's run ('x' or
    'y'); the leaf extends `sign` along it from the hinge. french: the house
    materials, to build a glazed French door leaf instead of a plain one."""
    t = 0.04
    if axis == "x":
        lo, hi = (0, -t / 2, 0), (length, t / 2, height)
    else:
        lo, hi = (-t / 2, 0, 0), (t / 2, length, height)
    if french:
        assert axis == "x", "French doors are only built in x walls"
        parts = _french_parts(length, height, french)
        parts[0].name = name
    else:
        parts = [C.box_minmax(name, lo, hi, mat)]
    if glass:
        # two tall, narrow leadlight panes side by side, raised panels below
        g0, g1 = glass
        lead = C.mat("DoorGlass", "#8a6a3e", rough=0.2, emit="#e0a860", emit_strength=0.12)
        for c in (0.31, 0.69):
            lo, hi = (length * c - 0.075, -t / 2 - 0.005, g0), (length * c + 0.075, t / 2 + 0.005, g1)
            if axis == "y":
                lo, hi = (lo[1], lo[0], lo[2]), (hi[1], hi[0], hi[2])
            parts.append(C.box_minmax("g", lo, hi, lead))
            lo, hi = (length * c - 0.11, -t / 2 - 0.008, 0.2), (length * c + 0.11, t / 2 + 0.008, 0.85)
            if axis == "y":
                lo, hi = (lo[1], lo[0], lo[2]), (hi[1], hi[0], hi[2])
            parts.append(C.box_minmax("panel", lo, hi, mat))
    if knob:
        k = length - 0.07
        for s in (-1, 1):
            loc = (k, s * 0.05, 1.0) if axis == "x" else (s * 0.05, k, 1.0)
            parts.append(C.sphere("knob", 0.03, loc, F.M("brass"), segs=6, rings=4))
    o = C.join(parts, name)
    C.apply_transform(o)  # the leaf's mesh is built about the hinge
    if sign < 0:
        o.scale = (-1, 1, 1) if axis == "x" else (1, -1, 1)
        C.apply_transform(o)
        bpy.ops.object.select_all(action="DESELECT")
        for p in o.data.polygons:
            p.flip()
    o.location = (hinge[0], hinge[1], z0)
    C.box_uv(o, 1.0)
    return o


def marker(name, loc, rot_z=0.0):
    e = C.empty(name, loc)
    e.rotation_euler = (0, 0, math.radians(rot_z))
    return e


# ------------------------------------------------------------------ the house

def house(M):
    doors = []
    # floors and ceilings
    A.block((-PARTY, -EXT, 0), (W + PARTY, D + EXT, FZ0), M["boards"], "House-col", uv=1.0)
    A.block((2.1, 5.0, FZ0), (5.4, 6.6, FZ0 + 0.006), M["tiles"], "House-col")   # laundry + toilet
    stair_void = (0.0, 5.0, 1.0, 8.0)
    A.slab(0, 0, W, D, CZ0, FZ1 - 0.01, M["ceiling"], "House", holes=[stair_void])
    for x0, y0, x1, y1 in ((0, 0, W, 3.9), (0, 3.9, 2.1, 5.0), (1.0, 5.0, 2.1, 8.0), (0, 8.0, W, D),
                           (2.1, 6.6, W, 8.0)):
        A.block((x0, y0, FZ1 - 0.01), (x1, y1, FZ1), M["carpet"], "House-col")
    A.block((2.1, 3.9, FZ1 - 0.01), (W, 6.6, FZ1), M["mosaic"], "House-col")     # bathroom
    A.block((0, 0, CZ1), (W, D, CZ1 + 0.1), M["ceiling"], "House")
    # balcony slab over the porch
    A.block((0, -1.6, CZ0), (W, -EXT, FZ1 - 0.01), M["render"], "House-col")
    A.block((0, -1.6, FZ1 - 0.01), (W, -EXT, FZ1), M["tiles"], "House-col")

    # front wall (y = 0, street at -Y)
    # Ground (street side, left to right): the black front door with a leaded
    # sidelight and a three-pane transom over both, then French doors between
    # two narrow fixed sidelights. Upstairs: the balcony French doors on the
    # left over the front door, a wide window on the right.
    front_g = [(0.45, 1.72, FZ0, 2.65), (2.2, 4.9, FZ0, 2.45)]
    front_u = [(0.55, 1.85, FZ1, FZ1 + 2.45), (2.6, 4.6, FZ1 + 0.45, FZ1 + 2.25)]
    ext_wall("x", 0, -PARTY, W + PARTY, 0, EAVE, -1, M, front_g + front_u)
    frame_opening("x", -0.1, 0.45, 1.72, 2.25, 2.65, M, "House", bars=2)                  # transom
    frame_opening("x", -0.1, 1.37, 1.72, FZ0, 2.25, M, "House", transom=FZ0 + 0.95)      # sidelight
    A.block((1.42, -0.13, FZ0), (1.67, -0.07, FZ0 + 0.93), M["trim"], "House-col")       # sidelight panel
    A.block((1.35, -0.2, FZ0), (1.42, 0.0, 2.25), M["trim"], "House-col")                # jamb between
    frame_opening("x", -0.1, 2.2, 2.75, FZ0, 2.45, M, "House", bars=0, transom=1.25)     # fixed sidelights
    frame_opening("x", -0.1, 4.35, 4.9, FZ0, 2.45, M, "House", bars=0, transom=1.25)
    A.block((2.75, -0.2, 2.35), (4.35, 0.0, 2.45), M["trim"], "House-col")                # head over the leaves
    A.block((2.75, -0.2, FZ0), (4.35, 0.0, FZ0 + 0.02), M["trim"], "House-col")           # sill
    doors.append(door("Door_Front", "x", (0.47, -0.1), 0.86, FZ0, 2.08, M["front_door"], glass=(1.0, 1.95)))
    doors.append(door("Door_French_L", "x", (2.77, -0.08), 0.79, FZ0 + 0.02, 2.17, None, french=M))
    doors.append(door("Door_French_R", "x", (4.33, -0.08), 0.79, FZ0 + 0.02, 2.17, None, sign=-1, french=M))
    # balcony doors and the bedroom window
    frame_opening("x", -0.1, 0.55, 1.85, FZ1 + 2.15, FZ1 + 2.45, M, "House", bars=1)      # transom
    A.block((0.55, -0.2, FZ1), (1.85, 0.0, FZ1 + 0.02), M["trim"], "House-col")
    A.block((0.55, -0.2, FZ1 + 2.1), (1.85, 0.0, FZ1 + 2.15), M["trim"], "House-col")
    doors.append(door("Door_Balcony_L", "x", (0.57, -0.08), 0.63, FZ1 + 0.02, 2.08, None, french=M))
    doors.append(door("Door_Balcony_R", "x", (1.83, -0.08), 0.63, FZ1 + 0.02, 2.08, None, sign=-1, french=M))
    frame_opening("x", -0.1, 2.6, 4.6, FZ1 + 0.45, FZ1 + 2.25, M, "House", bars=1, transom=FZ1 + 1.75)

    # rear wall (y = D, courtyard at +Y)
    rear_g = [(0.5, 2.0, FZ0 + 0.9, 2.5), (2.6, 4.8, FZ0, 2.45)]
    rear_u = [(1.5, 3.5, FZ1 + 0.9, FZ1 + 2.1)]
    ext_wall("x", D, -PARTY, W + PARTY, 0, EAVE, 1, M, rear_g + rear_u)
    frame_opening("x", D + 0.1, 0.5, 2.0, FZ0 + 0.9, 2.5, M, "House", bars=1)
    frame_opening("x", D + 0.1, 3.7, 4.8, FZ0, 2.45, M, "House")          # fixed half of the slider
    frame_opening("x", D + 0.1, 1.5, 3.5, FZ1 + 0.9, FZ1 + 2.1, M, "House", bars=1)
    t = 0.05
    slider = C.join([C.box_minmax("Door_Sliding", (0, -0.02, 0), (t, 0.02, 2.3), M["trim"]),
                     C.box_minmax("r", (1.15 - t, -0.02, 0), (1.15, 0.02, 2.3), M["trim"]),
                     C.box_minmax("b", (t, -0.02, 0), (1.15 - t, 0.02, t), M["trim"]),
                     C.box_minmax("t", (t, -0.02, 2.3 - t), (1.15 - t, 0.02, 2.3), M["trim"]),
                     C.box_minmax("pane", (t, -0.005, t), (1.15 - t, 0.005, 2.3 - t), M["glass"])],
                    "Door_Sliding")
    C.apply_transform(slider)
    slider.location = (2.6, D + 0.04, FZ0)
    doors.append(slider)

    # party walls, full height including the gable
    for x, s in ((0, -1), (W, 1)):
        A.wall("y", x, -EXT, D + EXT, 0, EAVE, PARTY, M["paint"], "House-col", side=s)

    # fireplace on the lounge's x=0 wall
    # toward the street end, leaving the wall beside it for the TV
    A.block((0, 1.75, FZ0), (0.35, 3.05, CZ0), M["paint"], "House-col")
    A.block((0.30, 2.05, FZ0), (0.36, 2.75, FZ0 + 0.85), M["firebox"], "House")
    A.block((0.0, 1.65, FZ0 + 1.1), (0.45, 3.15, FZ0 + 1.16), M["trim"], "House-col")  # mantel
    A.block((0.35, 1.9, FZ0), (0.75, 2.9, FZ0 + 0.03), M["tiles"], "House-col")         # hearth

    # ---- ground floor partitions (0.1 thick)
    t = 0.1
    A.wall("x", 5.0, 0, 1.0, FZ0, CZ0, t, M["paint"], "House-col")                    # storage front
    A.wall("x", 5.0, 2.1, W, FZ0, CZ0, t, M["paint"], "House-col")                    # laundry/WC front
    A.wall("y", 1.0, 5.0, 6.6, FZ0, CZ0, t, M["paint"], "House-col", [(5.7, 6.45, FZ0, 2.2)])
    A.wall("y", 2.1, 5.0, 6.6, FZ0, CZ0, t, M["paint"], "House-col", [(5.72, 6.5, FZ0, 2.2)])
    A.wall("y", 3.6, 5.0, 6.6, FZ0, CZ0, t, M["paint"], "House-col", [(5.7, 6.4, FZ0, 2.2)])
    A.wall("x", 6.6, 2.1, W, FZ0, CZ0, t, M["paint"], "House-col")                    # behind the kitchen run
    A.wall("x", 6.6, 0, 1.0, FZ0, 1.9, t, M["paint"], "House-col")                    # storage back (under stair)
    # the storage door opens out into the hall (the cupboard is too small to
    # swing into); the laundry door opposite opens into the laundry
    doors.append(door("Door_Storage", "y", (1.0, 6.44), 0.72, FZ0, 2.04, M["door"], sign=-1))
    doors.append(door("Door_Laundry", "y", (2.1, 6.49), 0.76, FZ0, 2.04, M["door"], sign=-1))
    doors.append(door("Door_Toilet", "y", (3.6, 5.72), 0.66, FZ0, 2.04, M["door"]))

    # stairs: carpeted, rising from y=8.8 (bottom) to y=5.0 (top) along x=0
    stair_mat = C.mat("StairCarpet", image=A.tex_carpet("stair_carpet", "#a99d8b"), rough=1.0)
    A.stairs_straight(0.0, 1.0, 8.8, 5.0, FZ0, FZ1, 16, stair_mat, "House-col", solid_until=lambda y: y > 6.6)
    # handrail and balustrade along the open side
    A.block((0.97, 6.6, FZ0), (1.03, 8.8, FZ0 + 0.9), M["trim"], "House-col")            # stringer wall
    for i in range(8):                        # the last one stops short of bedroom 2
        y = 5.1 + i * 0.4
        A.block((0.98, y, FZ1), (1.02, y + 0.03, FZ1 + 0.95), M["trim"], "House")
    A.block((0.97, 5.0, FZ1 + 0.95), (1.05, 8.0, FZ1 + 1.0), F.M("wood_mid"), "House-col")
    A.block((0.98, 5.0, FZ1), (1.02, 8.0, FZ1 + 0.95), M["glass"], "House_Guard-colonly")          # invisible guard
    A.block((0.0, 8.0, FZ1), (1.0, 8.04, FZ1 + 1.0), M["trim"], "House-col")             # end of the void

    # ---- upstairs partitions
    A.wall("x", 3.9, 0, W, FZ1, CZ1, t, M["paint"], "House-col", [(0.9, 1.72, FZ1, FZ1 + 2.05), (2.4, 3.2, FZ1, FZ1 + 2.05)])
    A.wall("y", 2.1, 3.9, 8.0, FZ1, CZ1, t, M["paint"], "House-col", [(4.05, 4.85, FZ1, FZ1 + 2.05), (7.05, 7.75, FZ1, FZ1 + 2.05)])
    A.wall("x", 6.6, 2.1, W, FZ1, CZ1, t, M["paint"], "House-col")
    A.wall("x", 8.0, 0, W, FZ1, CZ1, t, M["paint"], "House-col", [(1.15, 1.95, FZ1, FZ1 + 2.05)])
    A.wall("y", 1.0, 5.0, 8.0, FZ1 + 1.0, CZ1, t, M["paint"], "House")                   # bulkhead over the void
    # bathroom wall tiles to 1.2 m
    for lo, hi in (((2.15, 3.95, FZ1), (2.17, 6.55, FZ1 + 1.2)), ((5.38, 3.95, FZ1), (5.4, 6.55, FZ1 + 1.2)),
                   ((2.15, 6.53, FZ1), (5.4, 6.55, FZ1 + 1.2))):
        A.block(lo, hi, M["walltile"], "House", uv=0.6)
    doors.append(door("Door_Bed1", "x", (0.92, 3.9), 0.78, FZ1, 2.04, M["door"]))
    doors.append(door("Door_Bath_Bed", "x", (3.18, 3.9), 0.76, FZ1, 2.04, M["door"], sign=-1))
    doors.append(door("Door_Bath_Landing", "y", (2.1, 4.83), 0.76, FZ1, 2.04, M["door"], sign=-1))
    doors.append(door("Door_WC_Up", "y", (2.1, 7.73), 0.66, FZ1, 2.04, M["door"], sign=-1))
    doors.append(door("Door_Bed2", "x", (1.17, 8.0), 0.76, FZ1, 2.04, M["door"]))

    # skirting (dark jarrah downstairs, white up) along the long walls
    for z, mat in ((FZ0, F.M("wood_dark")), (FZ1, M["trim"])):
        A.block((0, 0.0, z), (0.02, D, z + 0.1), mat, "House")
        A.block((W - 0.02, 0.0, z), (W, D, z + 0.1), mat, "House")

    # roof: gable with the ridge along X, party walls carry up as gable ends
    zr = A.gable_roof(-PARTY, W + PARTY, -EXT, D + EXT, EAVE, 22, M["roof"], "House_Roof", overhang=0.35)
    for x in (-PARTY / 2, W + PARTY / 2):
        A.gable_end(x, -EXT, D + EXT, EAVE, zr, PARTY, M["render"], "House_Roof")
    # chimney over the fireplace, poking through the front roof slope
    A.block((-0.1, 1.85, EAVE), (0.55, 2.95, zr + 0.4), M["render"], "House_Roof")
    for y in (2.13, 2.67):
        A.block((0.1, y - 0.12, zr + 0.4), (0.34, y + 0.12, zr + 0.75), F.M("terracotta"), "House_Roof")
    # fascia and gutters
    A.block((-PARTY, -EXT - 0.4, EAVE - 0.15), (W + PARTY, -EXT - 0.3, EAVE + 0.05), M["trim"], "House_Roof")
    A.block((-PARTY, D + EXT + 0.3, EAVE - 0.15), (W + PARTY, D + EXT + 0.4, EAVE + 0.05), M["trim"], "House_Roof")

    # balcony: black iron railing on the front and sides, posts down to the porch
    rail_z0, rail_z1 = FZ1, FZ1 + 1.0
    for x0, y0, x1, y1 in ((0.05, -1.6, W - 0.05, -1.55), (0.05, -1.6, 0.1, -EXT), (W - 0.1, -1.6, W - 0.05, -EXT)):
        A.block((x0, y0, rail_z1 - 0.05), (x1, y1, rail_z1), M["iron"], "House-col")
        A.block((x0, y0, rail_z0), (x1, y1, rail_z0 + 0.05), M["iron"], "House")
        n = int(max(x1 - x0, y1 - y0) / 0.12)
        for i in range(n + 1):
            if x1 - x0 > y1 - y0:
                x = x0 + (x1 - x0) * i / n
                A.block((x - 0.01, y0 + 0.01, rail_z0), (x + 0.01, y1 - 0.01, rail_z1), M["iron"], "House")
            else:
                y = y0 + (y1 - y0) * i / n
                A.block((x0 + 0.01, y - 0.01, rail_z0), (x1 - 0.01, y + 0.01, rail_z1), M["iron"], "House")
        A.block((x0, y0, rail_z0), (x1, y1, rail_z1), M["glass"], "House_Guard-colonly")             # keeps you on
    for x in (0.12, W - 0.12):
        A.block((x - 0.08, -1.58, 0), (x + 0.08, -1.42, CZ0), M["trim"], "House-col")
    A.block((0, -1.6, 0), (W, -EXT, 0.12), M["tiles"], "House-col")                        # porch

    # exterior lights either side of the front door
    for x in (0.25, 1.55):
        it("porch_light", F.wall_light(), (x, -EXT - 0.03, 2.1), 0)

    # markers
    marker("Spawn_Player", (2.3, 2.0, FZ1), 180)          # beside the bed, facing the room
    marker("Spawn_Front", (0.9, -2.2, 0.05), 0)
    marker("Spawn_Courtyard", (3.0, 13.2, 0.05), 180)
    marker("Bed", (3.15, 2.05, FZ1), -90)                   # walk here to sleep
    lights = {
        "Light_Lounge": (2.6, 2.6, CZ0 - 0.7), "Light_Lounge_Lamp": (4.75, 0.5, FZ0 + 1.55),
        "Light_Kitchen": (3.8, 7.6, CZ0 - 0.3), "Light_Bar": (3.7, 8.5, CZ0 - 0.75),
        "Light_Living": (2.7, 10.4, CZ0 - 0.3), "Light_Laundry": (2.85, 5.8, CZ0 - 0.2),
        "Light_WC": (4.5, 5.8, CZ0 - 0.2), "Light_Storage": (0.5, 5.8, 1.6),
        "Light_Stairs": (1.5, 6.5, CZ1 - 0.3), "Light_Bed1": (2.7, 1.9, CZ1 - 0.3),
        "Light_Bed1_Lamp": (W - 0.3, 1.0, FZ1 + 0.75), "Light_Bath": (3.7, 5.2, CZ1 - 0.2),
        "Light_WC_Up": (3.7, 7.3, CZ1 - 0.2), "Light_Bed2": (2.7, 10.0, CZ1 - 0.3),
        "Light_Bed2_Desk": (2.4, 11.5, FZ1 + 1.1), "Light_Porch": (0.9, -0.6, 2.2),
        "Light_Courtyard": (2.7, 14.5, 2.3),
    }
    for name, loc in lights.items():
        marker(name, loc)
    return doors


# ------------------------------------------------------------------ inside

_USED = {}


def uniq(name):
    """Unique object names that keep a trailing -col suffix intact."""
    base, col = (name[:-4], "-col") if name.endswith("-col") else (name, "")
    n = _USED.get(base, 0)
    _USED[base] = n + 1
    return (base if n == 0 else "%s_%d" % (base, n)) + col


def it(name, parts, pos, rot=0):
    return F.item(uniq(name), parts, pos, rot)


def prop(name, parts, pos, rot=0):
    """Like it(), but the object's origin sits at pos, so the game can find,
    turn or slide it (clues, oddities, the shed key)."""
    o = F.item(uniq(name), parts, pos, rot)
    C.set_origin(o, pos)
    o.rotation_euler = (0, 0, 0)
    return o


def interior(M):
    out = []
    z0, z1 = FZ0, FZ1
    # lounge
    # fireplace and a 65" TV on the x=0 wall; a big L-shaped couch runs along
    # the opposite wall from the back wall and turns across the room level
    # with the fireplace. The walk from the front door to the hall stays
    # clear along the TV side, and the French doors open onto the floor
    # in front of the couch's back.
    out.append(it("Sofa-col", F.sectional(4.05, 2.05), (W, 0.9, z0)))
    out.append(it("TV_Unit-col", F.tv_unit(1.6), (0.21, 4.1, z0), 90))
    out.append(it("TV_Screen", F.tv(65), (0.0, 4.1, z0 + 0.72), 90))
    out.append(it("CoffeeTable", F.coffee_table(1.0, 0.55), (3.4, 3.05, z0), 90))
    out.append(it("Rug_Lounge", F.rug(2.6, 1.8, "rug_red"), (3.4, 2.95, z0), 90))
    out.append(it("FloorLamp", F.floor_lamp(), (4.75, 0.5, z0)))
    out.append(it("Bookshelf-col", F.bookshelf(0.8, 1.9, 0.32, 1), (5.22, 0.46, z0), -90))
    out.append(it("RecordPlayer", F.record_player_unit(), (3.3, 4.72, z0)))
    out.append(it("RecordCrate", F.record_crate(), (4.1, 4.74, z0)))
    out.append(it("Gallery", F.photo_frames(7, 3, 1.6, 0.9), (3.5, 4.94, z0 + 1.05)))
    out.append(it("Plant_Fiddle", F.plant("fiddle", 2), (2.45, 4.6, z0)))
    out.append(it("Plant_Snake", F.plant("snake", 3), (1.95, 0.3, z0)))
    out.append(it("Plant_Hanging", F.hanging_plant(0.7, 4), (4.55, 0.7, CZ0)))
    out.append(it("Coats", F.shoe_rack_and_coats(), (0.18, 1.1, z0), 90))
    out.append(it("Pendant_Lounge", F.pendant(0.6), (2.6, 2.6, CZ0)))
    out.append(it("Curtains_Lounge", F.curtains(2.7, 2.45), (3.55, 0.08, z0)))
    # candles and an old photo on the mantel; one frame lies face down
    for i, y in enumerate((1.8, 1.95, 2.95)):
        out.append(it("candle", [F.cyl(0.03, 0.12 + i * 0.04, (0, 0, 0.06 + i * 0.02), F.M("cream"), 6)],
                      (0.22, y, z0 + 1.16)))
    out.append(it("Photo_FaceDown", [F.bx((-0.1, -0.13, 0), (0.1, 0.13, 0.015), F.M("frame"))], (3.5, 3.12, z0 + 0.42)))
    out.append(it("Throw_Basket", [F.cyl(0.22, 0.35, (0, 0, 0.175), F.M("wood_light"), 10),
                                   C.sphere("f", 0.2, (0, 0, 0.33), F.M("throw"), segs=8, rings=4, scale=(1, 1, 0.5))],
                  (4.2, 2.0, z0)))

    # kitchen: U shape, fridge by the hall, bar facing the rear living
    out.append(it("Kitchen_Back-col", F.kitchen_run(2.5, top=M["granite"], with_cooktop=True, oven=True, upper=True),
                  (W, 6.95, z0), 180))
    out.append(it("Kitchen_Side-col", F.kitchen_run(1.0, top=M["granite"], with_sink=True), (5.1, 8.25, z0), -90))
    out.append(it("Kitchen_Bar-col", F.kitchen_run(2.2, top=M["granite"]), (2.6, 8.5, z0)))
    out.append(it("Bar_Top", [F.bx((0, -0.1, 1.05), (2.2, 0.35, 1.09), M["granite"]),
                              F.bx((0, 0.25, 0.9), (2.2, 0.31, 1.05), F.M("white"))], (2.6, 8.5, z0)))
    out.append(it("Fridge-col", F.fridge(), (2.5, 7.0, z0), 180))
    # fridge magnets the player collects; the fridge is turned to face +Y
    for i, (mx, mz) in enumerate(F.FRIDGE_MAGNETS):
        marker("Magnet_%d" % (i + 1), (2.5 - mx, 7.0 + 0.35, z0 + mz), 180)
    out.append(it("CoffeeMachine", F.coffee_machine(), (3.4, 6.85, z0 + 0.91), 180))
    out.append(it("Kettle", F.kettle(), (4.9, 6.85, z0 + 0.91)))
    out.append(it("Herbs", F.plant("herb", 5), (5.15, 7.6, z0 + 0.91)))
    out.append(it("Succulent", F.plant("succulent", 6), (3.0, 8.5, z0 + 1.09)))
    for i, x in enumerate((3.0, 3.7, 4.4)):
        out.append(it("Stool", F.bar_stool(), (x, 9.15, z0), 0))
    out.append(it("Cat_Bowl", F.cat_bowl(), (2.35, 8.35, z0)))          # there is no cat
    for i, x in enumerate((3.3, 3.75, 4.2)):
        out.append(it("Pendant_Bar", F.pendant(0.75), (x, 8.55, CZ0)))
    # laundry, toilet, storage
    out.append(it("Washer-col", F.washing_machine(), (2.5, 5.35, z0), 180))
    out.append(it("Trough-col", F.laundry_trough(), (3.15, 5.35, z0), 180))
    out.append(it("Toilet_Down-col", F.toilet(), (5.1, 5.8, z0), -90))
    out.append(it("Storage_Boxes", F.boxes(2, 4), (0.3, 5.28, z0)))
    out.append(it("Storage_Boxes2", F.boxes(7, 2), (0.3, 6.2, z0)))
    out.append(it("Vacuum", F.vacuum(), (0.82, 5.25, z0)))
    # something small and old at the back of the storage: a biscuit tin
    out.append(it("Storage_Tin", [F.cyl(0.11, 0.09, (0, 0, 0.045), F.M("teal"), 10),
                                  F.cyl(0.115, 0.015, (0, 0, 0.095), F.M("brass"), 10)], (0.22, 5.85, z0)))
    # rear living
    # dining table under the kitchen window, leaving a clear run from the
    # hall and the bar to the sliding door
    out.append(it("Dining-col", F.dining_table(1.4, 0.8), (1.4, 10.6, z0), 90))
    for (x, y, r) in ((0.72, 10.25, 90), (0.72, 10.95, 90), (2.08, 10.25, -90), (2.08, 10.95, -90)):
        out.append(it("Chair", F.chair(), (x, y, z0), r))
    out.append(it("Armchair2-col", F.armchair("teal"), (4.55, 11.3, z0), -45))
    out.append(it("Rug_Living", F.rug(2.0, 1.4, "rug_blue"), (1.4, 10.6, z0), 90))
    out.append(it("AC_Living", F.split_ac(), (W - 0.01, 10.5, 2.5), -90))
    out.append(it("Intercom", F.intercom(), (W - 0.01, 11.6, z0 + 1.35), -90))
    out.append(it("Bookshelf2-col", F.bookshelf(0.8, 1.2, 0.3, 9), (5.23, 10.2, z0), -90))
    out.append(it("TableLamp", F.table_lamp(), (5.23, 9.95, z0 + 1.2)))

    # main bedroom (front)
    # bed against the x=W wall, a full-length built-in robe on the x=0 wall
    # (it starts clear of the balcony door's swing)
    out.append(it("Bed-col", F.bed(1.53, 2.03), (W - 1.06, 2.05, z1), -90))
    for y in (1.0, 3.1):
        out.append(it("Bedside-col", F.bedside_table(), (W - 0.25, y, z1), -90))
    out.append(it("BedLamp", F.table_lamp(), (W - 0.25, 1.0, z1 + 0.55)))
    out.append(it("Books_Bedside", [F.bx((-0.1, -0.08, 0), (0.1, 0.08, 0.05), F.M("book1")),
                                    F.bx((-0.09, -0.07, 0.05), (0.08, 0.07, 0.09), F.M("book3"))], (W - 0.25, 3.1, z1 + 0.55)))
    out.append(it("Robes-col", F.robe_doors(3.1, CZ1 - FZ1 - 0.04, 0.62), (0.31, 0.72, z1), 90))
    out.append(it("Plant_Fiddle2", F.plant("fiddle", 11), (2.25, 0.4, z1)))
    out.append(it("Curtains_Bed1", F.curtains(2.0, 2.4), (3.6, 0.08, z1)))
    out.append(it("Rug_Bed1", F.rug(2.0, 1.6, "rug_cream", "rug_red"), (3.2, 2.05, z1)))
    # Decorate spots for things bought from props/home/decor/ (origin at the
    # base, or the middle of a poster on the wall); when a spot is filled the
    # game hides the stock piece it replaces, named in the comment
    marker("Decor_Rug_Lounge", (3.4, 2.95, z0), 90)            # Rug_Lounge
    marker("Decor_Rug_Bedroom", (3.2, 2.05, z1), 0)            # Rug_Bed1
    marker("Decor_Lamp_Lounge", (4.75, 0.5, z0), 180)          # FloorLamp
    marker("Decor_Lamp_Bedroom", (W - 0.3, 3.6, z1), -90)
    marker("Decor_Poster_1", (W - 0.01, 1.6, z0 + 1.6), -90)   # over the couch
    marker("Decor_Poster_2", (4.3, 3.82, z1 + 1.55), 0)        # bedroom back wall
    marker("Decor_Poster_3", (0.02, 6.5, z1 + 1.55), 90)       # landing
    marker("Decor_Poster_4", (W - 0.01, 11.05, z0 + 1.55), -90)  # rear living
    marker("Decor_Plant_1", (1.95, 0.3, z0), 180)              # Plant_Snake
    marker("Decor_Plant_2", (0.35, 11.7, z0), 90)
    marker("Decor_Plant_3", (2.25, 0.4, z1), 180)              # Plant_Fiddle2
    marker("Decor_Chair", (1.75, 1.4, z0), -153)
    # balcony plants
    out.append(it("Balcony_Pot1", F.plant("succulent", 12, 2.0), (2.3, -1.3, z1)))
    out.append(it("Balcony_Pot2", F.plant("palm", 13, 0.8), (5.0, -1.3, z1)))

    # bathroom, toilet
    out.append(it("Bath-col", F.bath(1.65, 0.75), (4.45, 6.17, z1)))
    out.append(it("ShowerScreen", [F.bx((-0.01, -0.37, 0.55), (0.01, 0.37, 2.0),
                                        C.mat("ShowerGlass", "#cfdde0", rough=0.05, alpha=0.3))], (3.6, 6.17, z1)))
    out.append(it("Vanity-col", F.vanity(0.9), (5.15, 4.6, z1), -90))
    out.append(it("TowelRail", F.towel_rail(), (2.2, 5.6, z1 + 1.4), 90))
    out.append(it("Plant_Bath", F.plant("pothos", 14), (5.15, 5.4, z1 + 0.84)))
    out.append(it("Toilet_Up-col", F.toilet(), (5.1, 7.3, z1), -90))
    # bedroom 2: a home studio, and someone's been mapping something
    out.append(it("Desk-col", F.desk(1.2, 0.6), (2.5, 11.6, z1), 180))
    out.append(it("Desk_Chair", F.chair("black"), (2.5, 11.05, z1), 180))
    out.append(it("Synth_Mono", S.mono_synth(), (2.27, 11.65, z1 + 0.75)))
    keys = S.keyboard_stand()
    for p in S.poly_synth():
        p.location.z += 0.75
        keys.append(p)
    out.append(it("KeyboardStand-col", keys, (0.48, 10.2, z1), 90))
    out.append(it("DrumKit-col", S.drum_kit(), (4.4, 11.15, z1)))
    for kind, y in (("tele", 8.45), ("jazzmaster", 9.2), ("jbass", 9.95), ("dove", 10.62)):
        out.append(it("Guitar_" + kind, S.guitar(kind), (W, y, z1 + 2.1 - S.guitar_height(kind)), -90))
    out.append(it("Amp_Guitar-col", S.guitar_combo(), (W - 0.15, 8.5, z1), -90))
    out.append(it("Amp_Bass-col", S.bass_rig(), (W - 0.22, 9.35, z1), -90))
    out.append(it("Pedalboard", S.pedalboard(), (4.75, 8.9, z1), -90))
    for kind, x in (("dinosaur", 2.55), ("lanegan", 3.25), ("qotsa", 3.95)):
        out.append(it("Poster_" + kind, S.poster(kind), (x, 8.05, z1 + 1.2), 180))
    out.append(it("LPs", S.lp_row(3), (4.7, D, z1 + 1.55)))
    out.append(it("Laptop", F.laptop(), (2.88, 11.6, z1 + 0.75), 180))
    out.append(it("Corkboard", F.corkboard(1.4, 0.9), (0.02, 10.2, z1 + 1.0), 90))
    out.append(it("Boxes_Bed2", F.boxes(11, 3), (0.45, 8.5, z1)))
    out.append(it("Plant_Bed2", F.plant("monstera", 15, 0.7), (0.62, 11.38, z1)))
    out.append(it("Curtains_Bed2", F.curtains(2.0, 2.2), (2.5, D - 0.08, z1), 180))
    out.append(it("DeskLamp", F.table_lamp(), (W - 0.22, 9.55, z1 + 0.8)))     # on the bass amp
    out += deco_slots(z0)
    out += mystery_house(z0)
    out += lived_in(z0, z1)
    return out


def lived_in(z0, z1):
    """What's left lying about: things on the benches and bedside tables,
    the bathroom's bits, the studio's floor, plus switches, power points and
    smoke alarms. Purely set dressing (no collision); the layout audit
    treats Dress_* as sitting on furniture or flat on the floor."""
    out = []
    bench, bar, side = z0 + 0.91, z0 + 1.09, z1 + 0.55
    # kitchen: the back bench from the fridge end, then the sink run and the bar
    out.append(it("Dress_Toaster", L.toaster(), (3.07, 6.85, bench)))
    out.append(it("Dress_UtensilCrock", L.utensil_crock(), (3.68, 6.8, bench)))
    out.append(it("Dress_KnifeBlock", L.knife_block(), (4.66, 6.8, bench)))
    out.append(it("Dress_Canisters", L.canisters(), (5.2, 6.8, bench)))
    out.append(it("Dress_DishSoap", L.dish_soap(), (5.2, 7.35, bench), 90))
    out.append(it("Dress_TeaTowel", L.tea_towel(), (4.18, 7.28, z0 + 0.78), 180))
    out.append(it("Dress_FruitBowl", L.fruit_bowl(), (3.62, 8.55, bar)))
    out.append(it("Dress_ChoppingBoard", [F.bx((-0.18, -0.21, 0), (0.18, 0.21, 0.018), F.M("wood_light"))],
                  (4.05, 8.56, bar), 90))
    out.append(it("Dress_PowerPoint_Kitchen", L.power_point(), (5.05, 6.65, z0 + 1.2), 180))
    # lounge
    out.append(it("Dress_TVRemote", L.tv_remote(), (3.22, 2.72, z0 + 0.51), 20))
    out.append(it("Dress_Mug_Lounge", L.mug("#2f6f6c"), (3.55, 2.7, z0 + 0.51)))
    out.append(it("Dress_PowerPoint_Lounge", L.power_point(), (0.0, 3.12, z0 + 0.3), 90))
    out.append(it("Dress_Switch_Front", L.switch_plate(2), (0.25, 0.0, z0 + 1.15), 180))
    out.append(it("Dress_SmokeAlarm_Down", L.smoke_alarm(), (1.5, 6.0, CZ0)))
    # main bedroom: prints over the bed, the bedside tables, the floor
    out.append(it("Dress_Print_Bed_L", L.art_print(0.5, 0.65, ("#2f5f7a", "#d8c08a", "#9fc0c8"), 1), (W, 1.72, z1 + 1.5), -90))
    out.append(it("Dress_Print_Bed_R", L.art_print(0.5, 0.65, ("#3c6e5a", "#c88a4a", "#e9d7a8"), 2), (W, 2.38, z1 + 1.5), -90))
    out.append(it("Dress_AlarmClock", L.alarm_clock(), (5.12, 1.19, side)))
    out.append(it("Dress_WaterGlass", L.water_glass(), (5.25, 2.95, side)))
    out.append(it("Dress_Phone", L.phone(), (5.13, 3.25, side), 90))
    out.append(it("Dress_Slippers", L.slippers(), (3.72, 3.1, z1)))
    out.append(it("LaundryBasket", L.laundry_basket(), (2.85, 0.35, z1)))
    out.append(it("Chair_Clothes", L.chair_with_clothes(), (2.1, 3.56, z1)))
    out.append(it("Dress_PowerPoint_Bed", L.power_point(), (W, 0.6, z1 + 0.3), -90))
    out.append(it("Dress_Switch_Bed1", L.switch_plate(), (1.82, 3.82, z1 + 1.15)))
    out.append(it("Dress_SmokeAlarm_Up", L.smoke_alarm(), (1.5, 5.6, CZ1)))
    # bathroom
    out.append(it("Dress_ToothbrushCup", L.toothbrush_cup(), (5.27, 4.3, z1 + 0.84)))
    out.append(it("Dress_SoapPump", L.soap_pump(), (5.27, 4.92, z1 + 0.84), -90))
    out.append(it("Dress_BathMat", L.bath_mat(), (4.3, 5.5, z1)))
    out.append(it("Dress_BathBottles", L.bath_bottles(), (5.23, 6.22, z1 + 0.55), 90))
    out.append(it("Dress_BathScale", L.bathroom_scale(), (4.55, 4.45, z1), -90))
    # studio
    out.append(it("Rug_Studio", F.rug(2.2, 1.5, "rug_blue", "rug_cream"), (2.75, 9.75, z1)))
    out.append(it("Beanbag", L.beanbag(), (1.7, 9.55, z1)))
    out.append(it("MicStand", L.mic_stand(), (3.4, 10.75, z1), 180))
    out.append(it("Dress_Headphones", L.headphones(), (5.24, 8.5, z1 + 0.53), 90))
    out.append(it("Dress_Cable_Pedals", L.cable([(4.9, 8.75), (5.0, 8.62), (5.09, 8.55)]), (0, 0, z1)))
    out.append(it("Dress_PowerPoint_Studio", L.power_point(), (W, 10.3, z1 + 0.3), -90))
    out.append(it("Dress_Switch_Bed2", L.switch_plate(), (2.08, 8.05, z1 + 1.15), 180))
    # laundry and toilets
    out.append(it("Dress_Detergent", L.detergent(), (2.62, 5.4, z0 + 0.85), 180))
    out.append(it("Dress_PegBasket", L.peg_basket(), (2.36, 5.25, z0 + 0.85)))
    out.append(it("Dress_LooRoll_Down", L.toilet_roll_holder(), (W, 6.2, z0 + 0.7), -90))
    out.append(it("Dress_LooRoll_Up", L.toilet_roll_holder(), (W, 7.62, z1 + 0.7), -90))
    # by the back door, on the strip of wall past the slider: M.'s binoculars hung here
    out.append(it("Dress_BackDoor_Hooks", L.back_door_hook(), (5.12, D, z0 + 1.6)))
    # where the field journal hangs the binoculars until you take them down
    marker("Binoculars_Hook", (4.97, D - 0.08, z0 + 1.63))
    return out


def mystery_house(z0):
    """The mystery's props in the house. Each is its own node with its
    origin on the prop, for the game to show, hide, turn or slide. (The clues
    themselves are scripts/world/mystery.gd's: it stacks them on
    Storage_Boxes in the under-stair cupboard as they turn up.)

      Oddity_Photo / Oddity_Photo_Figure  the stair photo, without and with
                          someone at the gate (the figure one sits behind)
      Oddity_Plant        leans toward the sliding door; turn it 180 degrees
                          to face the front door
      Oddity_LooseBrick   proud of the bricked-up fireplace
      Oddity_Footprints   small muddy footprints in from the sliding door
      Oddity_Drawing      a child's drawing on the fridge
    """
    out = []
    # the old fireplace, bricked up, with one brick sitting proud
    fx, fy, fw, fh = 0.36, 2.4, 0.7, 0.85
    out.append(it("Fireplace_Bricks", MY.bricked_fireplace(fw, fh), (fx, fy, z0), 90))
    brick_x, brick_z = _loose_brick_centre(fw)
    out.append(prop("Oddity_LooseBrick", MY.loose_brick(), (fx, fy + brick_x, z0 + brick_z), 90))
    # the stair photo: the same courtyard, once without and once with someone
    # at the gate; the figure print sits a hair behind the plain one
    py, pz = 8.86, z0 + 1.95
    out.append(it("Oddity_Photo_Frame", [F.bx((-0.17, -0.025, -0.13), (0.17, 0.0, 0.13), F.M("frame")),
                                         F.bx((-0.145, -0.027, -0.105), (0.145, -0.025, 0.105), F.M("cream"))],
                  (0.02, py, pz), 90))
    for name, kind, y in (("Oddity_Photo", "courtyard", -0.0285), ("Oddity_Photo_Figure", "courtyard_figure", -0.0278)):
        out.append(prop(name, [MY._picture_centered("photo_" + kind, MY._img_photo(kind, 32, 24), 0.26, 0.18, y)],
                        (0.02, py, pz), 90))
    # on the breakfast bar, leaning toward the sliding door (+Y)
    out.append(prop("Oddity_Plant", MY.leaning_plant(), (4.55, 8.62, z0 + 1.09), 180))
    # muddy little footprints in from the sliding door toward the stairs
    out.append(prop("Oddity_Footprints", MY.wet_footprints(8, 0.62), (2.95, 11.7, z0 + 0.003), 0))
    # the fridge faces +Y; the drawing goes under the magnets, left of the handle
    out.append(prop("Oddity_Drawing", MY.crayon_drawing(), (2.6, 7.35, z0 + 0.74), 180))
    return out


def _loose_brick_centre(w):
    """Across and up the infill to the gap bricked_fireplace leaves."""
    bw, bh, gap = 0.115, 0.055, 0.008
    z = 0.004 + MY.LOOSE_ROW * (bh + gap)
    off = 0 if MY.LOOSE_ROW % 2 else bw / 2
    x = -w / 2 - off
    while x < w / 2:
        x0, x1 = max(x + 0.004, -w / 2), min(x + bw, w / 2)
        if abs((x0 + x1) / 2 - MY.LOOSE_X) < 0.03:
            return (x0 + x1) / 2, z + bh / 2
        x += bw + gap
    raise ValueError("no loose brick")


def _blank_frame(w, h, mat="cream", depth=0.025):
    """Picture frame facing -Y with a blank mat, origin at its centre."""
    return [F.bx((-w / 2, -depth, -h / 2), (w / 2, 0, h / 2), F.M("frame")),
            F.bx((-w / 2 + 0.03, -depth - 0.004, -h / 2 + 0.03), (w / 2 - 0.03, -depth, h / 2 - 0.03), F.M(mat))]


def deco_slots(z0):
    """Blank props and empties the game fills in as you play (scripts in the
    driving thread spawn their own meshes at the Deco_*, Corkboard_Pin_* and
    Photo_Frame_* empties). Empties face like the furniture: local -Y points
    out of the wall into the room (Godot +Z)."""
    out = []
    # rear living, x=0 wall beside the dining table: a blank corkboard for
    # rumour and secret cards, and a frame waiting for a street directory map
    cw, ch, cz = 1.2, 0.8, z0 + 1.15
    out.append(it("Corkboard_Blank", [F.bx((-cw / 2, -0.02, 0), (cw / 2, 0.0, ch), F.M("frame")),
                                       F.bx((-cw / 2 + 0.04, -0.03, 0.04), (cw / 2 - 0.04, -0.02, ch - 0.04),
                                            F.M("cork"))], (0.02, 10.0, cz), 90))
    for i in range(12):
        col, row = i % 4, i // 4
        y = 10.0 - (cw / 2 - 0.2) + col * (cw - 0.4) / 3
        marker("Corkboard_Pin_%d" % (i + 1), (0.055, y, cz + ch - 0.18 - row * (ch - 0.36) / 2), 90)
    out.append(it("RoadMap_Frame", _blank_frame(0.9, 0.62, "paper"), (0.02, 11.35, z0 + 1.55), 90))
    marker("Deco_RoadMap", (0.05, 11.35, z0 + 1.55), 90)
    # lounge: two floating shelves over the couch for trophies, four slots each
    for k, z in enumerate((z0 + 1.45, z0 + 1.85)):
        out.append(it("TrophyShelf", [F.bx((-0.9, -0.22, -0.03), (0.9, 0.0, 0.0), F.M("wood_mid"))],
                      (W - 0.01, 3.35, z), -90))
        for j in range(4):
            marker("Deco_Shelf_%d" % (k * 4 + j + 1), (W - 0.12, 3.35 - 0.675 + j * 0.45, z), -90)
    # up the stairs: six blank frames for album photos, following the flight
    for i in range(6):
        y = 8.25 - i * 0.55
        stair_z = FZ0 + (9.053 - y) * (FZ1 - FZ0) / (9.053 - 5.0)
        z = stair_z + (1.45 if i % 2 == 0 else 1.75)
        out.append(it("PhotoFrame_Blank", _blank_frame(0.3, 0.24), (0.02, y, z), 90))
        marker("Photo_Frame_%d" % (i + 1), (0.05, y, z), 90)
    return out


# ------------------------------------------------------------------ outside

def neighbour(x0, x1, M, render, seed):
    """A simplified townhouse in the row: shell, openings as dark or lit panels."""
    rnd = random.Random(seed)
    b = "Site-col"
    A.block((x0, -EXT, 0), (x1, D + EXT, EAVE), render, b)
    zr = A.gable_roof(x0, x1, -EXT, D + EXT, EAVE, 22, M["roof"], "Site", overhang=0.35)
    for y, face in ((-EXT - 0.01, -1), (D + EXT + 0.01, 1)):
        for (a0, a1, q0, q1) in ((x0 + 0.5, x0 + 1.4, 0.15, 2.4), (x0 + 2.2, x1 - 0.5, 0.15, 2.4),
                                 (x0 + 0.6, x0 + 1.6, 3.9, 5.3), (x0 + 2.2, x1 - 0.5, 3.16, 5.4)):
            lit = rnd.random() < 0.35
            A.block((a0, y - 0.01 * face, q0), (a1, y, q1), M["warm_window"] if lit else M["dark_window"], "Site")
            # white frame, a mullion every metre or so and a transom bar on
            # the tall openings, like the row's own French doors and sashes
            t, fy0, fy1 = 0.06, min(y, y + 0.025 * face), max(y, y + 0.025 * face)
            for lo, hi in (((a0 - t, q0), (a0, q1)), ((a1, q0), (a1 + t, q1)), ((a0 - t, q0 - t), (a1 + t, q0)),
                           ((a0 - t, q1 - 0.01), (a1 + t, q1))):
                A.block((lo[0], fy0, lo[1]), (hi[0], fy1, hi[1]), M["trim"], "Site")
            n = max(1, round((a1 - a0) / 0.8))
            for k in range(1, n):
                xm = a0 + (a1 - a0) * k / n
                A.block((xm - 0.025, fy0, q0), (xm + 0.025, fy1, q1), M["trim"], "Site")
            if q1 - q0 > 1.8:
                A.block((a0, fy0, q1 - 0.45), (a1, fy1, q1 - 0.4), M["trim"], "Site")
            A.block((a0 - 0.06, y - 0.03 * face if face < 0 else y, q1), (a1 + 0.06, y if face < 0 else y + 0.03, q1 + 0.08),
                    M["trim"], "Site")
    # front balcony with iron railing
    A.block((x0, -1.6, CZ0), (x1, -EXT, FZ1), render, b)
    A.block((x0 + 0.05, -1.6, FZ1 + 0.95), (x1 - 0.05, -1.55, FZ1 + 1.0), M["iron"], "Site")
    for i in range(int((x1 - x0) / 0.12)):
        x = x0 + 0.08 + i * 0.12
        A.block((x - 0.01, -1.6, FZ1), (x + 0.01, -1.56, FZ1 + 0.95), M["iron"], "Site")
    for x in (x0 + 0.12, x1 - 0.12):
        A.block((x - 0.08, -1.58, 0), (x + 0.08, -1.42, CZ0), M["trim"], b)
    return zr


def front_fence(x0, x1, gate_x, M, number=None, ends=(True, True)):
    """ends: whether to put a pillar at each end (a neighbour's fence shares
    the boundary pillar with ours)."""
    b = "Site-col"
    A.block((x0, -3.25, 0), (x1, -3.05, 0.45), M["render"], b)
    A.block((x0, -3.2, 0.45), (gate_x - 0.05, -3.1, 1.15), M["pickets"], b, uv=1.0)
    A.block((gate_x + 0.95, -3.2, 0.45), (x1, -3.1, 1.15), M["pickets"], b, uv=1.0)
    pillars = [gate_x - 0.21 - 0.05, gate_x + 0.95 + 0.21]
    if ends[0] and pillars[0] - (x0 + 0.21) > 0.42:
        pillars.append(x0 + 0.21)
    if ends[1] and (x1 - 0.21) - pillars[1] > 0.42:
        pillars.append(x1 - 0.21)
    for x in pillars:
        A.add(F.item("pillar", F.ball_pillar(1.35, 0.42), (x, -3.15, 0)), b)
    if number:
        # letterbox slot and house number plaque on the gate pillar
        A.block((gate_x - 0.36, -3.37, 0.95), (gate_x - 0.16, -3.36, 1.15), M["trim"], "Site")
    gate = C.box_minmax("g", (0, -0.03, 0), (0.9, 0.03, 1.1), M["pickets"])
    C.apply_transform(gate)
    C.box_uv(gate, 1.0)
    return gate


def site(M):
    b = "Site-col"
    # Little Shenton Lane out front: herringbone brick, shared
    A.block((-12, -9.0, -0.05), (24, -3.25, 0.0), M["pavers"], b, uv=1.6)
    # front gardens
    A.block((0, -3.05, -0.02), (W, -1.6, 0.02), M["mulch"], b)
    A.block((0.55, -3.05, 0.0), (1.35, -1.6, 0.03), M["pavers"], b, uv=1.6)          # path to the door
    it("PencilPine", F.pencil_pine(6.5, 1), (4.2, -2.4, 0))
    it("Shrub_Front", F.shrub(0.45, 2), (2.6, -2.5, 0))
    it("Shrub_Front2", F.shrub(0.35, 3), (5.0, -2.8, 0))
    gate15 = front_fence(-PARTY, W + PARTY, 0.5, M, number=15)
    gate15.name = "Gate_Front"
    gate15.location = (0.5, -3.15, 0.45)
    for x0, x1, s in ((-5.8, -PARTY, 13), (W + PARTY, 11.2, 17)):
        A.block((x0, -3.05, -0.02), (x1, -1.6, 0.02), M["mulch"], b)
        gate = front_fence(x0, x1, x0 + 0.6, M, ends=(s != 17, s != 13))
        gate.name = "Site_Gate_%d" % s      # neighbours' gates stay shut
        gate.location = (x0 + 0.6, -3.15, 0.45)
        it("Shrub", F.shrub(0.5, s), ((x0 + x1) / 2 + 1, -2.4, 0))
    # street trees on the lane
    it("StreetTree1", F.street_tree(6.5, 2, bare=True), (-3.0, -6.5, 0))
    it("StreetTree2", F.street_tree(6.0, 5), (8.0, -6.8, 0))

    # neighbours: #13 on the -X side, #17 (pale yellow) on +X, then a flat-roofed block
    neighbour(-5.8, -PARTY, M, M["render_n13"], 13)
    neighbour(W + PARTY, 11.2, M, M["render_n17"], 17)
    A.block((11.2, -3.3, 0), (19.0, 18.0, 6.6), M["concrete"], b)
    A.block((11.0, -3.5, 6.6), (19.2, 18.2, 6.9), M["trim"], "Site")

    # courtyard: brick paving, rendered side walls, gate to the carport
    y0, y1 = D + EXT, 17.0
    A.block((-PARTY, y0, -0.02), (W + PARTY, y1, 0.02), M["pavers"], b, uv=1.6)
    for x, s in ((-PARTY, 1), (W + PARTY, -1)):
        A.wall("y", x, y0, y1, 0, 1.9, 0.18, M["render"], b, side=s)
    A.wall("x", y1, -PARTY, W + PARTY, 0, 1.9, 0.18, M["render"], b, [(2.4, 3.4, 0, 1.9)], side=1)
    for x in (2.36, 3.44):
        A.block((x - 0.05, y1, 0), (x + 0.05, y1 + 0.18, 2.0), M["post"], b)
    gate = C.box_minmax("Door_Gate", (0, -0.03, 0), (0.98, 0.03, 1.8), M["timber"])
    C.apply_transform(gate)
    C.box_uv(gate, 1.0)
    gate.location = (2.41, y1 + 0.09, 0.02)
    it("HotWater", F.hot_water_unit(), (W - 0.25, 13.6, 0), -90)
    it("AC_Outdoor", F.ac_outdoor(), (0.4, 12.55, 0), 180)
    it("Court_Palm", F.plant("palm", 21, 1.2), (4.9, 16.5, 0))
    it("Court_Fern", F.plant("fern", 22, 1.2), (0.45, 16.5, 0))
    it("Court_Monstera", F.plant("monstera", 23, 1.1), (0.45, 13.4, 0))
    it("Court_Shrub", F.shrub(0.5, 24), (5.0, 15.2, 0))
    A.add(F.item("Court_Table", F.dining_table(0.9, 0.6), (2.0, 14.6, 0)), b)
    # clear ground by the side wall, in view of the rear living window, where
    # the field journal puts the bird feeder once you've seen 30 species
    marker("Feeder_Spot", (0.9, 15.6, 0.02))
    for x, r in ((1.55, 90), (2.45, -90)):
        it("Court_Chair", F.chair("teal"), (x, 14.6, 0), r)
    # festoon lights strung across the courtyard
    glow = F.emissive("Festoon_Glow", "#ffcf87", 2.0)
    bulbs = []
    for i in range(13):
        t = i / 12
        bulbs.append(C.sphere("bulb", 0.04, (0.1 + t * 5.2, 13.0 + t * 3.6, 2.35 - math.sin(t * math.pi) * 0.35),
                              glow, segs=5, rings=3))
    C.join(bulbs, "Festoon")
    it("Clothes_Line", [F.cyl(0.02, 1.7, (0, 0, 0.85), F.M("metal"), 5),
                            F.bx((-0.7, -0.01, 1.7), (0.7, 0.01, 1.72), F.M("metal"))], (4.4, 13.0, 0), 90)

    # shared carport: skillion roof on timber posts, open to the rear lane.
    # The posts stand back under the roof (a steel beam carries the front
    # edge) so a car can swing out into the narrow lane as soon as it rolls
    # forward, left or right, without clipping a post.
    cy0, cy1 = y1 + 0.18, 23.0
    post_y = 19.7
    # the slab runs on behind #13 too, so nothing catches a wheel swinging left
    A.block((-5.8, cy0, -0.05), (11.2, cy1, 0.0), M["concrete"], b, uv=2.0)
    A.block((-PARTY, cy0, 2.55), (11.2, cy1, 2.65), M["timber"], "Site")
    A.block((-PARTY - 0.05, cy0 - 0.05, 2.65), (11.25, cy1 + 0.1, 2.7), M["corrugated"], "Site")
    A.block((-PARTY, cy1 - 0.12, 2.37), (11.2, cy1, 2.55), F.M("pot_dark"), "Site")         # front beam
    A.block((-PARTY, post_y - 0.08, 2.43), (11.2, post_y + 0.08, 2.55), M["timber"], "Site")  # post beam
    for x in (-0.1, 3.7, 7.5, 11.1):
        A.block((x - 0.06, post_y - 0.06, 0), (x + 0.06, post_y + 0.06, 2.43), M["post"], b)
    # sheds along the courtyard wall, doors facing the carport
    sheds = [(-0.1, 2.2, True), (3.6, 5.5, False), (5.7, 7.5, False), (9.1, 11.0, False)]
    shed_door = None
    for x0, x1, mine in sheds:
        door_x0 = (x0 + x1) / 2 - 0.42
        if mine:
            # the player's shed: hollow (walls, floor and roof), white door,
            # padlocked hasp
            t = 0.08
            A.block((x0, cy0, 0), (x1, cy0 + t, 2.4), M["render"], b)
            A.block((x0, cy0, 0), (x0 + t, cy0 + 1.6, 2.4), M["render"], b)
            A.block((x1 - t, cy0, 0), (x1, cy0 + 1.6, 2.4), M["render"], b)
            A.wall("x", cy0 + 1.6, x0 + t, x1 - t, 0, 2.4, t, M["render"], b,
                   [(door_x0, door_x0 + 0.84, 0, 2.02)], side=-1)
            A.block((x0, cy0, 2.32), (x1, cy0 + 1.6, 2.4), M["render"], b)
            A.block((x0 + t, cy0 + t, 0.0), (x1 - t, cy0 + 1.6 - t, 0.02), M["concrete"], b, uv=2.0)
            # the door sits flush in the opening and swings in, so it clears
            # a car parked in front of it
            shed_door = door("Shed_Door", "x", (door_x0, cy0 + 1.58), 0.84, 0.02, 2.0, M["door"], knob=False)
            lock = it("Padlock", F.padlock(), (door_x0 + 0.78, cy0 + 1.628, 1.05), 180)
            hasp = C.box_minmax("hasp", (door_x0 + 0.70, cy0 + 1.6, 1.03), (door_x0 + 0.92, cy0 + 1.612, 1.09),
                                F.M("steel"))
            A.add(hasp, "Site")
            lock.name = "Padlock"
            # a blank backing board for the neon "500" over the player's bay
            neon_x, neon_z = (door_x0 + 0.84 + x1) / 2, 1.85
            A.add(C.box_minmax("NeonSign_Backing", (neon_x - 0.3, cy0 + 1.6, neon_z - 0.16),
                               (neon_x + 0.3, cy0 + 1.625, neon_z + 0.16), F.M("black")), "Site")
            marker("Deco_NeonSign", (neon_x, cy0 + 1.63, neon_z), 180)
            shed_interior(x0 + 0.08, x1 - 0.08, cy0 + 0.08, cy0 + 1.52, door_x0)
        else:
            A.block((x0, cy0, 0), (x1, cy0 + 1.6, 2.4), M["render"], b)
            A.block((door_x0, cy0 + 1.6, 0.02), (door_x0 + 0.84, cy0 + 1.62, 2.02), M["door"], "Site")
    # nose toward the rear lane, with room to stand at the shed door behind it
    marker("Spawn_Car", (1.3, 21.3, 0.05), 0)
    marker("Light_Carport", (1.3, 20.4, 2.45))

    # rear lane
    A.block((-12, cy1, -0.05), (24, cy1 + 5.0, 0.0), M["asphalt"], b, uv=3.0)
    # no wall across the far side: the lane opens onto the street behind, so
    # the car can drive straight out of the carport
    return gate, shed_door


def _wall_mount(parts, axis_rot):
    """Turn a flat-lying prop (face up) to face -Y, back at y=0."""
    for p in parts:
        C.apply_transform(p)
        p.rotation_euler = (math.radians(axis_rot), 0, 0)
        C.apply_transform(p)
    hi = max(v.co.y for p in parts for v in p.data.vertices)
    for p in parts:
        for v in p.data.vertices:
            v.co.y -= hi
    return parts


def shed_interior(x0, x1, y0, y1, door_x0):
    """What's inside the player's shed, under ShedInterior_Root. The inside
    is x0..x1, y0 (back wall, toward the courtyard) .. y1 (door wall), floor
    at 0, ceiling at 2.32.

    Shed_Sheeted is the dust sheet over a card table against the back wall.
    scripts/world/mystery.gd hides it on the reveal and builds the table,
    deck, transmitter, tapes and map from its bounding box, so its size is
    the table's: 1.0 wide, 0.55 deep (the door's inward swing reaches 0.6
    from the back wall), 0.78 high."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    root = marker("ShedInterior_Root", (cx, cy, 0.0))
    kids = []
    table_x, table_d = x0 + 0.95, 0.55
    kids.append(prop("Shed_Sheeted", F.sheet_covered(1.0, table_d, 0.78),
                     (table_x, y0 + 0.01 + table_d / 2, 0.02), 0))
    kids.append(prop("Shed_KeyBoard", MY.key_board(), (x0, y0 + 0.95, 1.5), 90))
    kids.append(prop("Shed_OldPlate", MY.old_plate(), (x0, y0 + 0.5, 1.78), 90))
    kids.append(prop("Shed_Hubcap", _wall_mount(MY.hubcap(), 90), (x0, y0 + 0.5, 1.28), 90))
    # the chair and the tea chest on the right, past the door's reach; a
    # valve radio on the chest, facing into the shed
    kids.append(prop("Shed_Chair", MY.folding_chair(), (x1 - 0.28, y0 + 0.74, 0.02), 0))
    kids.append(prop("Shed_TeaChest-col", MY.tea_chest(), (x1 - 0.24, y1 - 0.22, 0.02), 0))
    kids.append(prop("Shed_Radio", MY.valve_radio(), (x1 - 0.24, y1 - 0.24, 0.5), 0))
    kids.append(prop("Shed_Bulb", MY.bare_bulb(0.32), (cx, cy, 2.32)))
    kids.append(marker("ShedInterior_Light", (cx, cy, 1.85)))
    # the ending: stand in front of the table, facing it
    kids.append(marker("Shed_Ending", (table_x, y0 + 0.95, 0.02), 0))
    # where the knocking comes from: just inside the door
    kids.append(marker("Shed_Knock", (door_x0 + 0.42, y1 - 0.05, 1.2), 180))
    for k in kids:
        k.parent = root
        k.matrix_parent_inverse = root.matrix_world.inverted()
    return root


# ------------------------------------------------------------------ main

def export(path, prefixes=None, names=None, lights=False):
    sel = []
    for o in bpy.data.objects:
        if o.name.startswith("Preview") or o.name == "Sun":
            continue
        if (prefixes and o.name.startswith(prefixes)) or (names and o.name in names):
            sel.append(o)
    C.export_glb(path, objects=sel, lights=lights)


def main():
    C.reset()
    C.clear_material_cache()
    A.reset()
    M = mats()
    M["granite"] = C.mat("Granite", image=A.tex_granite(), rough=0.35)

    doors = house(M)
    house_objs = A.finish()
    house_names = set(house_objs) | {d.name for d in doors} | {o.name for o in bpy.data.objects if o.type == "EMPTY"}
    house_names |= {o.name for o in bpy.data.objects if o.name.startswith("porch_light")}

    before = set(bpy.data.objects.keys())
    interior(M)
    interior_names = set(bpy.data.objects.keys()) - before

    before = set(bpy.data.objects.keys())
    site(M)
    site_objs = A.finish()
    site_names = (set(bpy.data.objects.keys()) - before) | set(site_objs)

    tris = C.tri_count([o for o in bpy.data.objects if o.type == "MESH"])
    print("shenton triangles:", tris)
    if "--render" in sys.argv:
        render(sys.argv[sys.argv.index("--render") + 1] if len(sys.argv) > sys.argv.index("--render") + 1
               else "docs/renders/shenton")
    export(OUT + "shenton_house.glb", names=house_names)
    export(OUT + "shenton_interior.glb", names=interior_names)
    export(OUT + "shenton_site.glb", names=site_names)


def render(prefix):
    C.render_setup((960, 600), 16, world="#c9d6e0", strength=0.9)
    C.sun(rot=(50, 10, 150), energy=3.5)
    shots = {
        "street": ((1.0, -8.6, 1.7), (2.7, 0, 2.9), 24),
        "front": ((-6.0, -8.0, 2.5), (4.0, -1.0, 2.6), 26),
        "rear": ((4.6, 16.6, 1.6), (2.7, 12.0, 3.2), 22),
        "carport": ((6.5, 26.5, 2.2), (2.0, 18.5, 1.2), 28),
        "aerial": ((-14, -10, 20), (3, 8, 2), 30),
    }
    for k, (loc, tgt, lens) in shots.items():
        C.camera_look(loc, tgt, lens=lens)
        C.render("%s_%s.png" % (prefix, k))
    # interiors: warm lamps at the Light_ markers, roof and site hidden
    for o in [o for o in bpy.data.objects if o.name.startswith("Light_")]:
        lamp = bpy.data.lights.new("Preview_" + o.name, "POINT")
        lamp.energy = 60 if "Lamp" in o.name or "Desk" in o.name else 120
        lamp.color = (1.0, 0.82, 0.6)
        lamp.shadow_soft_size = 0.2
        C.link(bpy.data.objects.new("Preview_" + o.name, lamp)).location = o.location
    hide = [o for o in bpy.data.objects if o.name.startswith(("House_Roof", "Site", "House_Guard"))]
    for o in hide:
        o.hide_render = True
    C.camera_look((4.3, 4.3, 1.5), (0.3, 2.6, 1.0), lens=18)
    C.render("%s_lounge.png" % prefix)
    C.camera_look((1.2, 4.8, 1.6), (4.2, 1.0, 0.7), lens=18)
    C.render("%s_lounge_front.png" % prefix)
    C.camera_look((1.6, 11.6, 1.6), (4.3, 7.2, 1.0), lens=18)
    C.render("%s_kitchen.png" % prefix)
    C.camera_look((3.6, 6.9, 1.6), (2.4, 12.0, 1.1), lens=18)
    C.render("%s_rear_living.png" % prefix)
    C.camera_look((1.0, 3.6, FZ1 + 1.6), (5.0, 1.5, FZ1 + 0.6), lens=18)
    C.render("%s_bedroom.png" % prefix)
    C.camera_look((4.4, 3.6, FZ1 + 1.6), (0.3, 1.4, FZ1 + 1.1), lens=18)
    C.render("%s_bedroom_front.png" % prefix)
    C.camera_look((4.9, 8.4, FZ1 + 1.6), (0.5, 11.0, FZ1 + 0.9), lens=18)
    C.render("%s_study.png" % prefix)
    for o in hide:
        o.hide_render = False


if __name__ == "__main__":
    main()
    C.done()
