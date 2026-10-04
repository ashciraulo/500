extends Node
## Lo-fi render settings (autoload: RenderSettings).
##
## The 3D world renders into a small SubViewport (about 240 pixels tall) that
## is scaled up with nearest-neighbour filtering, then dithered down to a
## reduced colour depth. World materials (see shaders/ps1_surface.gdshader)
## also snap vertices to the low-res pixel grid and use partly affine texture
## mapping. Everything here can be switched off for comfort or debugging.

signal changed

## Target height of the low-res framebuffer, in pixels.
@export var target_height := 240
## 1.0 snaps vertices to every low-res pixel; lower values exaggerate the wobble.
@export var vertex_snap_scale := 0.5
@export_range(0.0, 1.0) var affine_strength := 0.6
@export var color_levels := 32.0
@export var dither_enabled := true

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
