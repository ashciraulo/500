class_name BirdLab
extends Node3D
## The photo lab on Lake Street, Northbridge: the field journal's dock. Pull
## into the bay (or walk up to the sign) and press F / A to develop the roll,
## sell the prints and look at better binoculars and cameras.

const SIZE := Vector2(3.2, 7.0)
const COLOR := Color(0.95, 0.55, 0.75)
## Walk up to the sign this close.
const FOOT_REACH := 3.5

## The counter screen it opens (LabScreen, TackleScreen: anything with open()).
var screen: CanvasLayer

var _grounded := false
var _sign: Node3D
var _prompt: Label
var _prompt_layer: CanvasLayer


func _ready() -> void:
	add_to_group(_group())
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _color()
	var w := 0.16
	for line in [
		[Vector3(0, 0, -SIZE.y * 0.5), Vector3(SIZE.x, 0.02, w)],
		[Vector3(0, 0, SIZE.y * 0.5), Vector3(SIZE.x, 0.02, w)],
		[Vector3(-SIZE.x * 0.5, 0, 0), Vector3(w, 0.02, SIZE.y)],
		[Vector3(SIZE.x * 0.5, 0, 0), Vector3(w, 0.02, SIZE.y)],
	]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = line[1]
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = line[0] + Vector3.UP * 0.03
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	# A sandwich board on the footpath side of the bay.
	_sign = Node3D.new()
	_sign.name = "Sign"
	_sign.position = Vector3(SIZE.x * 0.5 + 1.2, 0, -SIZE.y * 0.25)
	add_child(_sign)
	var board_mat := PS1Material.make(Color(0.12, 0.12, 0.14))
	for side in [-1.0, 1.0]:
		var board := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 1.0, 0.65)
		board.mesh = b
		board.position = Vector3(side * 0.16, 0.5, 0)
		board.rotation.z = side * 0.28
		board.material_override = board_mat
		_sign.add_child(board)
	var label := Label3D.new()
	label.text = _sign_text()
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 6
	label.modulate = _color().lerp(Color.WHITE, 0.7)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, 1.45, 0)
	_sign.add_child(label)
	var lamp := OmniLight3D.new()
	lamp.light_color = _color().lerp(Color.WHITE, 0.4)
	lamp.light_energy = 0.8
	lamp.omni_range = 6.0
	lamp.position = Vector3(0, 2.2, 0)
	lamp.add_to_group(&"night_lights")
	_sign.add_child(lamp)

	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 5
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -200.0
	_prompt.offset_right = 200.0
	_prompt.offset_top = -126.0
	_prompt.offset_bottom = -102.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", _color().lerp(Color.WHITE, 0.75))
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 5)
	_prompt_layer.add_child(_prompt)
	get_tree().root.add_child.call_deferred(_prompt_layer)


func _exit_tree() -> void:
	if is_instance_valid(_prompt_layer):
		_prompt_layer.queue_free()


func _process(_delta: float) -> void:
	if not _grounded:
		_snap_to_ground()
	_prompt.text = _prompt_text() if in_reach() and not get_tree().paused else ""


func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(global_position.x, 300.0, global_position.z), Vector3(global_position.x, -50.0, global_position.z), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position.y = hit.position.y
		_grounded = true


# The tackle shop overrides these.
func _group() -> StringName:
	return &"photo_labs"


func _color() -> Color:
	return COLOR


func _sign_text() -> String:
	return "PHOTO LAB\nfilm  prints\nbinoculars"


func _prompt_text() -> String:
	return "F / A  Photo lab (%d of %d frames used)" % [FieldJournal.roll.size(), FieldJournal.roll_size()]


## True when the player is parked in the bay or standing at the sign.
func in_reach() -> bool:
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	if car == null:
		return false
	var walker := car.get_parent().get_node_or_null(^"Player") as Node3D
	if walker and not walker.get("in_car"):
		return walker.global_position.distance_to(_sign.global_position) < FOOT_REACH
	if not car.player_controlled or car.linear_velocity.length() > 1.0:
		return false
	var local := to_local(car.global_position)
	return absf(local.x) <= SIZE.x * 0.5 + 0.6 and absf(local.z) <= SIZE.y * 0.5 + 0.6


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and not get_tree().paused and in_reach() and screen:
		screen.call("open")
		get_viewport().set_input_as_handled()
