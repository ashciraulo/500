class_name WorkshopSpot
extends Marker3D
## A place where you can work on the car: your carport at home, a spray
## shop. Pull up inside the painted box, stop, and press F / A. The map
## places these; the test grid has placeholders.

## What can be done here: "parts", "tuning", "paint".
@export var kinds: PackedStringArray = ["parts", "tuning"]
@export var spot_id := ""
@export var display_name := ""
@export var size := Vector2(5.0, 7.0)
@export var color := Color(0.6, 0.85, 0.8)


func _ready() -> void:
	add_to_group(&"workshop_spots")
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	# Four painted lines on the ground, like a parking bay.
	var w := 0.18
	for line in [
		[Vector3(0, 0, -size.y * 0.5), Vector3(size.x, 0.02, w)],
		[Vector3(0, 0, size.y * 0.5), Vector3(size.x, 0.02, w)],
		[Vector3(-size.x * 0.5, 0, 0), Vector3(w, 0.02, size.y)],
		[Vector3(size.x * 0.5, 0, 0), Vector3(w, 0.02, size.y)],
	]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = line[1]
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = line[0] + Vector3.UP * 0.02
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	# A little sign at the head of the bay.
	var sign := Label3D.new()
	sign.text = display_name
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.fixed_size = false
	sign.pixel_size = 0.01
	sign.font_size = 48
	sign.outline_size = 8
	sign.modulate = color
	sign.position = Vector3(0, 2.6, -size.y * 0.5)
	# Read from the street; up close (parked in the bay) the prompt says it instead.
	sign.visibility_range_begin = 9.0
	sign.visibility_range_begin_margin = 2.0
	sign.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(sign)


## True when `point` is inside the bay (ignoring height).
func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5


func offers(kind: String) -> bool:
	return kinds.has(kind)
