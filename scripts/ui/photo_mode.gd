extends CanvasLayer
## Photo mode (P / L3): pauses the game and hands you a free camera near the
## car. Move with W/A/S/D or the left stick, look with the mouse or right
## stick, rise and fall with E/Q, change the filter with T / Y, zoom with the
## mouse wheel, take the shot with Enter / A, leave with P or Esc / B.
##
## Photos go to user://photos and the album (Activities). A photo taken near
## one of the marked photo spots counts that spot.

const MAX_DISTANCE := 25.0
const MOVE_SPEED := 6.0
const LOOK_SPEED := 2.0
const FILTERS := [
	{"name": "Lo-fi", "saturation": 0.92, "contrast": 1.04, "tint": Color(1, 1, 1), "vignette": 0.0},
	{"name": "Faded film", "saturation": 0.65, "contrast": 0.92, "tint": Color(1.06, 0.98, 0.86), "vignette": 0.6},
	{"name": "Black and white", "saturation": 0.0, "contrast": 1.15, "tint": Color(1, 1, 1), "vignette": 0.5},
	{"name": "Warm night", "saturation": 1.05, "contrast": 1.08, "tint": Color(1.1, 0.92, 0.78), "vignette": 0.8},
	{"name": "Cold wet", "saturation": 0.8, "contrast": 1.1, "tint": Color(0.85, 0.95, 1.1), "vignette": 0.7},
	{"name": "Punchy", "saturation": 1.3, "contrast": 1.15, "tint": Color(1, 1, 1), "vignette": 0.2},
]

@export var car_path: NodePath = ^"../LoFi/SubViewport/World/Car"
@export var post_path: NodePath = ^"../LoFi"
@export var hud_path: NodePath = ^"../HUD"

var _car: Node3D
var _camera: Camera3D
var _previous_camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _filter := 0
var _open := false
var _ui: Control
var _info: Label
var _flash: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info.position = Vector2(16, -64)
	_ui.add_child(_info)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	visible = false


func is_open() -> bool:
	return _open


func _input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed("photo_mode") and not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("photo_mode") or event.is_action_pressed("pause") \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		close()
	elif event.is_action_pressed("photo_take"):
		take_photo()
	elif event.is_action_pressed("photo_filter"):
		set_filter((_filter + 1) % FILTERS.size())
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Settings.mouse_sensitivity, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.fov = maxf(_camera.fov - 3.0, 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.fov = minf(_camera.fov + 3.0, 100.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		return
	get_viewport().set_input_as_handled()


func open() -> void:
	_car = get_node_or_null(car_path) as Node3D
	var viewport_camera := (get_node(post_path) as SubViewportContainer).get_child(0).get_camera_3d() as Camera3D
	if _car == null or viewport_camera == null:
		return
	_open = true
	visible = true
	get_tree().paused = true
	_previous_camera = viewport_camera
	_camera = Camera3D.new()
	_camera.far = viewport_camera.far
	_camera.fov = viewport_camera.fov
	_car.get_parent().add_child(_camera)
	_camera.global_transform = viewport_camera.global_transform
	var euler := _camera.global_basis.get_euler()
	_pitch = euler.x
	_yaw = euler.y
	_camera.current = true
	var hud := get_node_or_null(hud_path) as CanvasLayer
	if hud:
		hud.visible = false
	set_filter(_filter)
	_update_info()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	set_filter(0)
	if is_instance_valid(_previous_camera):
		_previous_camera.current = true
	if _camera:
		_camera.queue_free()
		_camera = null
	var hud := get_node_or_null(hud_path) as CanvasLayer
	if hud:
		hud.visible = true
	get_tree().paused = false


func set_filter(index: int) -> void:
	_filter = index
	var f: Dictionary = FILTERS[index]
	var post := (get_node(post_path) as CanvasItem).material as ShaderMaterial
	if post:
		post.set_shader_parameter("saturation", f.saturation)
		post.set_shader_parameter("contrast", f.contrast)
		post.set_shader_parameter("tint", f.tint)
		post.set_shader_parameter("vignette", f.vignette)
	_update_info()


func take_photo() -> void:
	_ui.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_ui.visible = true
	var spot := PhotoSpot.nearest(get_tree(), _camera.global_position if _camera else Vector3.INF)
	var entry := Activities.add_photo(image, spot)
	_flash.color.a = 0.8
	var text := "Saved to the album (%d photos)." % Activities.photos.size()
	if entry.spot != "":
		text = "Photo spot: %s (%d of %d)." % [spot.title, Activities.photo_spots_found(), Activities.PHOTO_SPOTS_TOTAL]
	_update_info(text)


func _process(delta: float) -> void:
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 3.0)
	if not _open or _camera == null:
		return
	var look := Input.get_vector("look_left", "look_right", "look_down", "look_up")
	_yaw -= look.x * LOOK_SPEED * delta
	_pitch = clampf(_pitch + look.y * LOOK_SPEED * delta, -1.4, 1.4)
	_camera.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var move := Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var rise := Input.get_action_strength("shift_up") - Input.get_action_strength("shift_down")
	var dir := _camera.global_basis * Vector3(move.x, 0.0, move.y) + Vector3.UP * rise
	var pos := _camera.global_position + dir * MOVE_SPEED * delta
	# Stay near the car and above the road.
	var offset := pos - _car.global_position
	if offset.length() > MAX_DISTANCE:
		pos = _car.global_position + offset.normalized() * MAX_DISTANCE
	pos.y = maxf(pos.y, _car.global_position.y - 0.2)
	_camera.global_position = pos


func _update_info(extra := "") -> void:
	var spot := PhotoSpot.nearest(get_tree(), _camera.global_position) if _camera else null
	var where := ("Photo spot: %s%s" % [spot.title, " (taken)" if spot.is_taken() else ""]) if spot else ""
	_info.text = "PHOTO MODE   Filter: %s (T / Y)   Enter / A: take   P / Esc: back\n%s%s" % [
		FILTERS[_filter].name, where, ("   " + extra) if extra != "" else ""]
