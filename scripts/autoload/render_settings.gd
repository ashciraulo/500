extends Node
## Lo-fi render settings (autoload: RenderSettings).
##
## The 3D world renders into a small SubViewport (about 240 pixels tall) that
## is scaled up with nearest-neighbour filtering, then dithered down to a
## reduced colour depth. World materials (see shaders/ps1_surface.gdshader)
## also snap vertices to the low-res pixel grid and use partly affine texture
## mapping. Everything here can be switched off for comfort or debugging.

signal changed

## Filter strengths offered in the pause menu, harshest first. Each sets the
## framebuffer height, colour depth, dither, vertex wobble, affine warp and
## how much the big pixels are softened at their edges.
const PRESETS := [
	{"name": "Strong", "target_height": 240, "color_levels": 32.0, "dither_strength": 1.0,
		"vertex_snap_scale": 0.5, "affine_strength": 0.6, "softness": 0.0},
	{"name": "Medium", "target_height": 300, "color_levels": 48.0, "dither_strength": 0.6,
		"vertex_snap_scale": 0.75, "affine_strength": 0.4, "softness": 0.3},
	{"name": "Soft", "target_height": 360, "color_levels": 64.0, "dither_strength": 0.35,
		"vertex_snap_scale": 1.0, "affine_strength": 0.25, "softness": 0.5},
	{"name": "Light", "target_height": 480, "color_levels": 128.0, "dither_strength": 0.15,
		"vertex_snap_scale": 1.0, "affine_strength": 0.1, "softness": 0.65},
]
const DEFAULT_PRESET := 2

## Target height of the low-res framebuffer, in pixels.
@export var target_height := 360
## 1.0 snaps vertices to every low-res pixel; lower values exaggerate the wobble.
@export var vertex_snap_scale := 1.0
@export_range(0.0, 1.0) var affine_strength := 0.25
@export var color_levels := 64.0
@export var dither_enabled := true
@export_range(0.0, 2.0) var dither_strength := 0.35
## 0 = hard-edged pixels, 1 = fully smoothed between them.
@export_range(0.0, 1.0) var softness := 0.5

var lofi_enabled := true


func _ready() -> void:
	apply()


func toggle_lofi() -> void:
	lofi_enabled = not lofi_enabled
	apply()


## Integer upscale factor for a window of the given height.
func shrink_for(window_height: int) -> int:
	if not lofi_enabled:
		return 1
	return maxi(1, roundi(float(window_height) / float(target_height)))


## Call whenever the low-res framebuffer size changes.
func set_framebuffer_size(size: Vector2i) -> void:
	var snap := Vector2(size) * vertex_snap_scale if lofi_enabled else Vector2(8192, 8192)
	RenderingServer.global_shader_parameter_set("ps1_snap_resolution", snap)


func apply() -> void:
	RenderingServer.global_shader_parameter_set(
		"ps1_affine_strength", affine_strength if lofi_enabled else 0.0)
	changed.emit()
