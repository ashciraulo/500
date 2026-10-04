"""Placeholder lo-fi textures and the Godot materials that use them.

Everything is generated from code (64 px, nearest-neighbour) so the whole look
can be restyled by editing this file and rebuilding. Materials are plain
StandardMaterial3D .tres files: the render pipeline can swap any of them for a
ShaderMaterial without touching the tiles.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from .common import stable_rng

S = 64

# Metres per texture repeat for surfaces with world-space UVs.
UV_SCALE = {
    "ground_urban": 8.0, "grass": 8.0, "bush": 8.0, "turf": 12.0, "sand": 8.0, "wetland": 8.0,
    "paving": 4.0, "dirt": 8.0, "concrete": 6.0, "riverbed": 8.0, "asphalt": 6.0,
    "sidewalk": 2.4, "path": 2.0, "ballast": 3.0,
}


def _noise(rng, scale: int, amp: float = 1.0) -> np.ndarray:
    """Tileable value noise in [-amp, amp]."""
    n = S // scale
    g = rng.uniform(-1, 1, (n, n))
    g = np.kron(g, np.ones((scale, scale)))
    # Wrap-around blur keeps it tileable.
    for axis in (0, 1):
        g = (g + np.roll(g, scale // 2, axis=axis)) / 2
    return g * amp


def _base(rgb, rng, *octaves) -> np.ndarray:
    img = np.zeros((S, S, 3)) + np.array(rgb, dtype=float)
    for scale, amp in octaves:
        img += _noise(rng, scale, amp)[..., None]
    return img


def _speckle(img, rng, prob, rgb, jitter=10):
    m = rng.random((S, S)) < prob
    img[m] = np.array(rgb) + rng.uniform(-jitter, jitter, (m.sum(), 1))
    return img


def _window(img, x0, y0, x1, y1, glass=(52, 62, 74), frame=(225, 222, 210), emit=None, lit=False):
    img[y0:y1, x0:x1] = frame
    img[y0 + 1:y1 - 1, x0 + 1:x1 - 1] = glass
    img[y0 + 1:y0 + 3, x0 + 1:x1 - 1] = np.array(glass) + 25  # sky reflection
    if emit is not None and lit:
        emit[y0 + 1:y1 - 1, x0 + 1:x1 - 1] = (255, 196, 120)


def _bricks(img, rng, rgb, mortar=(170, 160, 150), bh=4, bw=10):
    for y in range(S):
        row = y // bh
        if y % bh == 0:
            img[y, :] = mortar
            continue
        off = (row % 2) * (bw // 2)
        for x in range(S):
            if (x + off) % bw == 0:
                img[y, x] = mortar
            else:
                img[y, x] = np.array(rgb) + rng.normal(0, 6)
    return img


def generate() -> dict[str, tuple[np.ndarray, np.ndarray | None]]:
    """Return {name: (albedo HxWx3, emission HxWx3 or None)}."""
    T: dict[str, tuple[np.ndarray, np.ndarray | None]] = {}
    r = lambda name: stable_rng("tex", name)  # noqa: E731

    rng = r("asphalt")
    T["asphalt"] = (_speckle(_base((62, 62, 64), rng, (16, 6), (4, 5)), rng, 0.05, (90, 90, 92)), None)
    rng = r("sidewalk")
    img = _base((178, 174, 166), rng, (16, 6), (4, 4))
    img[::32, :] -= 35
    img[:, ::32] -= 35
    T["sidewalk"] = (img, None)
    rng = r("path")  # Perth's red brick paving
    T["path"] = (_bricks(np.zeros((S, S, 3)), rng, (150, 72, 58), (120, 96, 86), bh=8, bw=16), None)
    rng = r("kerb")
    img = _base((196, 194, 188), rng, (8, 5))
    img[:6] = (120, 118, 112)
    T["kerb"] = (img, None)
    rng = r("grass")
    T["grass"] = (_speckle(_base((88, 112, 54), rng, (16, 10), (4, 8)), rng, 0.12, (70, 92, 40)), None)
    rng = r("turf")
    img = _base((84, 128, 58), rng, (8, 5))
    img[:, :32] += 10
    T["turf"] = (img, None)
    rng = r("bush")
    img = _base((78, 86, 50), rng, (16, 12), (4, 10))
    img = _speckle(img, rng, 0.10, (110, 92, 60), 15)
    T["bush"] = (_speckle(img, rng, 0.08, (52, 64, 36)), None)
    rng = r("ground_urban")  # patchy dry verge: grass and sand
    g = _base((122, 122, 76), rng, (16, 14), (8, 8), (2, 6))
    T["ground_urban"] = (_speckle(g, rng, 0.08, (150, 136, 100)), None)
    rng = r("sand")
    T["sand"] = (_speckle(_base((214, 198, 156), rng, (16, 6), (2, 6)), rng, 0.05, (190, 172, 132)), None)
    rng = r("wetland")
    T["wetland"] = (_speckle(_base((70, 82, 58), rng, (16, 10), (4, 8)), rng, 0.1, (60, 70, 70)), None)
    rng = r("paving")
    img = _base((150, 148, 142), rng, (16, 6), (4, 5))
    img[::16, :] -= 30
    img[:, ::16] -= 30
    T["paving"] = (img, None)
    rng = r("dirt")
    T["dirt"] = (_speckle(_base((132, 108, 78), rng, (16, 10), (4, 8)), rng, 0.08, (100, 82, 60)), None)
    rng = r("concrete")
    T["concrete"] = (_base((168, 166, 160), rng, (32, 8), (8, 6), (2, 3)), None)
    rng = r("riverbed")
    T["riverbed"] = (_base((86, 82, 66), rng, (16, 8), (4, 6)), None)
    rng = r("water")
    img = _base((34, 64, 78), rng, (16, 6), (4, 4))
    for y in range(0, S, 8):
        img[y, (np.arange(S) + y * 3) % S < 20] += 18
    T["water"] = (img, None)
    T["line_white"] = (np.zeros((S, S, 3)) + (228, 226, 214), None)
    rng = r("ballast")
    img = _speckle(_base((112, 108, 102), rng, (4, 12)), rng, 0.3, (80, 78, 74), 12)
    for y in range(0, S, 13):  # sleepers across the track
        img[y:y + 5, 6:58] = (96, 82, 66)
    T["ballast"] = (img, None)
    T["rail_steel"] = (_base((120, 118, 116), r("rail"), (8, 4)), None)
    rng = r("tunnel")
    img = _base((206, 196, 168), rng, (16, 4))
    img[::16, :] -= 30
    img[40:48] = (60, 70, 80)
    T["tunnel_wall"] = (img, None)

    T.update(_facades(r))
    T.update(_roofs(r))
    T.update(_landmarks(r))
    # Props (trees, street lights) built in Godot use these.
    rng = r("leaves")
    T["tree_leaves"] = (_speckle(_base((64, 92, 46), rng, (8, 14), (2, 10)), rng, 0.15, (40, 62, 30)), None)
    rng = r("gum")
    T["tree_gum"] = (_speckle(_base((96, 110, 78), rng, (8, 14), (2, 10)), rng, 0.15, (70, 84, 60)), None)
    rng = r("bark")
    img = _base((196, 186, 168), rng, (4, 12))  # pale gum bark
    img[:, ::7] -= 30
    T["tree_bark"] = (img, None)
    T["light_pole"] = (_base((110, 112, 114), r("pole"), (8, 4)), None)
    T["light_head"] = (np.zeros((S, S, 3)) + (250, 214, 150), np.zeros((S, S, 3)) + (255, 190, 110))
    return T


def _facades(r):
    T = {}
    # Each facade texture is one 4 m bay by one storey (ground floors: 4 m tall).
    rng = r("brick")
    img = _bricks(np.zeros((S, S, 3)), rng, (150, 84, 62))
    emit = np.zeros((S, S, 3))
    _window(img, 18, 14, 46, 46, emit=emit, lit=True)
    T["facade_brick"] = (img, emit)
    rng = r("render")
    img = _base((224, 218, 202), rng, (16, 5), (4, 3))
    emit = np.zeros((S, S, 3))
    _window(img, 16, 14, 48, 44, frame=(90, 90, 90), emit=emit, lit=True)
    T["facade_render"] = (img, emit)
    rng = r("apartment")
    img = _base((200, 190, 170), rng, (16, 5))
    emit = np.zeros((S, S, 3))
    _window(img, 8, 10, 56, 40, frame=(70, 70, 72), emit=emit, lit=rng.random() < 0.7)
    img[44:52] = (140, 140, 140)  # balcony slab
    img[40:44, 8:56:4] = (60, 60, 60)  # balustrade
    T["facade_apartment"] = (img, emit)
    rng = r("office")
    img = _base((150, 152, 150), rng, (16, 4))
    emit = np.zeros((S, S, 3))
    img[16:44, :] = (58, 72, 84)
    img[16:18, :] = (96, 110, 120)
    img[16:44, ::16] = (130, 132, 130)
    emit[18:44, :] = (220, 230, 255) if rng.random() < 0.6 else 0
    emit[:, ::16] = 0
    T["facade_office"] = (img, emit)
    rng = r("glass")
    img = _base((60, 96, 112), rng, (32, 8), (8, 4))
    img[::16, :] = (150, 160, 160)
    img[:, ::16] = (150, 160, 160)
    emit = np.zeros((S, S, 3))
    emit[2:30, 2:30] = (200, 220, 255)
    emit[34:62, 34:62] = (200, 220, 255)
    T["facade_glass"] = (img, emit)
    rng = r("shopfront")
    img = _base((90, 84, 80), rng, (16, 4))
    emit = np.zeros((S, S, 3))
    img[4:14] = (170, 40, 36)  # awning
    img[8:10] = (210, 200, 190)
    _window(img, 4, 18, 44, 60, glass=(66, 70, 64), frame=(40, 40, 40), emit=emit, lit=True)
    img[24:60, 48:60] = (70, 48, 34)  # door
    img[40, 56] = (220, 200, 120)
    T["facade_shopfront"] = (img, emit)
    rng = r("upper")
    img = _base((214, 196, 160), rng, (16, 5))
    emit = np.zeros((S, S, 3))
    _window(img, 10, 12, 26, 50, glass=(48, 56, 66), frame=(240, 236, 226), emit=emit, lit=True)
    _window(img, 38, 12, 54, 50, glass=(48, 56, 66), frame=(240, 236, 226), emit=emit, lit=False)
    img[0:4] = (180, 160, 128)  # cornice
    T["facade_upper"] = (img, emit)
    rng = r("heritage")
    img = _base((206, 180, 132), rng, (8, 6), (2, 4))
    img[::8, :] -= 18
    emit = np.zeros((S, S, 3))
    _window(img, 22, 18, 42, 54, glass=(40, 44, 52), frame=(232, 220, 196), emit=emit, lit=True)
    for x in range(22, 42):  # arch
        dy = int(6 * (1 - ((x - 32) / 10) ** 2))
        img[18 - dy:18, x] = (232, 220, 196)
    T["facade_heritage"] = (img, emit)
    rng = r("warehouse")
    img = _base((150, 152, 148), rng, (16, 6))
    img[:, ::4] -= 26
    img[:, 1::4] += 10
    T["facade_warehouse"] = (img, None)
    rng = r("shed")
    img = _base((112, 128, 104), rng, (16, 6))
    img[:, ::4] -= 24
    T["facade_shed"] = (img, None)
    rng = r("carpark")
    img = _base((170, 168, 160), rng, (16, 6))
    img[20:52] = (34, 36, 38)
    img[34:38] = (120, 120, 116)
    T["facade_carpark"] = (img, None)
    return T


def _roofs(r):
    T = {}
    rng = r("roof_flat")
    T["roof_flat"] = (_speckle(_base((132, 130, 126), rng, (16, 8), (2, 6)), rng, 0.1, (100, 100, 98)), None)
    rng = r("roof_flat_dark")
    T["roof_flat_dark"] = (_base((86, 86, 88), rng, (16, 8), (2, 6)), None)
    rng = r("roof_tiles")
    img = _base((168, 82, 56), rng, (16, 8))
    img[::8, :] -= 40
    for y in range(0, S, 8):
        img[y:y + 8, ((y // 8) % 2) * 4::8] -= 18
    T["roof_tiles"] = (img, None)
    rng = r("roof_tiles_dark")
    img = _base((72, 70, 72), rng, (16, 6))
    img[::8, :] -= 22
    T["roof_tiles_dark"] = (img, None)
    rng = r("roof_metal")
    img = _base((178, 176, 164), rng, (32, 6))
    img[:, ::6] -= 30
    T["roof_metal"] = (img, None)
    return T


def _landmarks(r):
    """Materials for the hand-built landmarks (landmarks.py)."""
    T = {}
    rng = r("copper")  # the Bell Tower's copper sails
    img = _base((176, 98, 58), rng, (16, 10), (4, 8))
    img[:, ::8] -= 28
    T["copper"] = (_speckle(img, rng, 0.06, (112, 142, 116), 12), None)
    rng = r("limestone")  # Fremantle limestone, the war memorial
    img = _base((214, 198, 160), rng, (16, 8), (4, 8))
    img[::8, :] -= 22
    for y in range(0, S, 8):
        img[y:y + 8, ((y // 8) % 2) * 6::12] -= 14
    T["limestone"] = (img, None)
    rng = r("steel_white")  # bridge arches
    img = _base((226, 228, 228), rng, (32, 4))
    img[::16, :] -= 18
    T["steel_white"] = (img, None)
    rng = r("stadium_bronze")  # Optus Stadium's bronze fins, lit at night
    img = _base((150, 112, 66), rng, (16, 6))
    emit = np.zeros((S, S, 3))
    for x in range(0, S, 8):
        img[:, x:x + 2] = (92, 70, 44)
        emit[:, x + 4:x + 5] = (90, 150, 255)
    T["stadium_bronze"] = (img, emit)
    rng = r("stadium_seats")
    img = _base((52, 60, 92), rng, (8, 6))
    img[::4, :] = (150, 150, 156)
    T["stadium_seats"] = (img, None)
    rng = r("roof_fabric")
    img = _base((236, 236, 230), rng, (32, 5))
    img[:, ::16] -= 26
    T["roof_fabric"] = (img, None)
    return T


# Shader parameters per material (the shared PS1 surface shader).
WET = {"asphalt": 1.0, "line_white": 0.8, "sidewalk": 0.6, "kerb": 0.6, "path": 0.7, "paving": 0.7,
       "concrete": 0.5, "ballast": 0.3, "rail_steel": 0.6}
ROUGH = {"water": 0.15, "rail_steel": 0.5, "facade_glass": 0.4, "asphalt": 0.85, "copper": 0.6,
         "steel_white": 0.6}


def _tres(name: str, has_emit: bool) -> str:
    """A ShaderMaterial using shaders/ps1_surface.gdshader (see CONTRIBUTING.md)."""
    steps = 3 + (1 if has_emit else 0)
    lines = [f'[gd_resource type="ShaderMaterial" load_steps={steps} format=3]', "",
             '[ext_resource type="Shader" path="res://shaders/ps1_surface.gdshader" id="1_shader"]',
             f'[ext_resource type="Texture2D" path="res://map/textures/{name}.png" id="2_albedo"]']
    if has_emit:
        lines.append(f'[ext_resource type="Texture2D" path="res://map/textures/{name}_emit.png" id="3_emit"]')
    lines += ["", "[resource]", f'resource_name = "{name}"', 'shader = ExtResource("1_shader")',
              'shader_parameter/albedo_texture = ExtResource("2_albedo")',
              f"shader_parameter/roughness = {ROUGH.get(name, 0.92)}",
              f"shader_parameter/wet_response = {WET.get(name, 0.25 if name.startswith(('roof', 'facade')) else 0.0)}"]
    if name == "water":
        lines.append("shader_parameter/metallic = 0.3")
    if has_emit:
        energy = 0.0  # MapStreamer.set_night_amount() turns windows and lamps on
        lines += ['shader_parameter/emission_texture = ExtResource("3_emit")',
                  "shader_parameter/emission_color = Color(1, 1, 1, 1)",
                  f"shader_parameter/emission_energy = {energy}"]
    lines.append("")
    return "\n".join(lines)


def write_all(map_dir: Path):
    tex_dir = map_dir / "textures"
    mat_dir = map_dir / "materials"
    tex_dir.mkdir(parents=True, exist_ok=True)
    mat_dir.mkdir(parents=True, exist_ok=True)
    for name, (albedo, emit) in generate().items():
        Image.fromarray(np.clip(albedo, 0, 255).astype(np.uint8)).save(tex_dir / f"{name}.png", optimize=True)
        has_emit = emit is not None and emit.any()
        if has_emit:
            Image.fromarray(np.clip(emit, 0, 255).astype(np.uint8)).save(tex_dir / f"{name}_emit.png", optimize=True)
        (mat_dir / f"{name}.tres").write_text(_tres(name, has_emit))
