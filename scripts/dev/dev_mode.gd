class_name DevMode
extends CanvasLayer
## Developer mode, for playtesting: get out of spots you're stuck in, fly
## around, jump home or to the car, and note where problems are.
##
## Only in debug builds (running from the Godot editor, or a debug export);
## release exports never add it (main.gd). F3 turns it on and off, and it
## stays on between runs. While it's on, a small panel top right shows where
## you are and the keys:
##
##   U  Unstuck: on foot, back up the last drop you couldn't climb (or back
##      along the way you walked); in the car, back along the road, upright
##   V  Fly (on foot): W/S where you look, A/D sideways, E/Q up and down,
##      Space fast. Walls don't stop you.
##   1  Home: on foot, out the front gate; in the car, back to the carport
##   2  To the car (on foot)
##   3  Car to me (on foot): the car is parked beside you
##   X  Mark this spot: its position goes on the clipboard and into
##      user://dev_marks.txt, for reporting stuck spots
##
## None of these keys are bound to game actions, and they do nothing while
## dev mode is off.

const SETTINGS_PATH := "user://dev_mode.cfg"
const MARKS_PATH := "user://dev_marks.txt"
const TOGGLE_KEY := KEY_F3
## Car breadcrumbs: one every CAR_TRAIL_STEP metres driven upright on the
## ground, the last CAR_TRAIL_SIZE kept.
const CAR_TRAIL_STEP := 4.0
const CAR_TRAIL_SIZE := 40
## Unstuck in the car goes at least this far back along the trail.
const CAR_BACK := 8.0

var enabled := false

var _player: OnFoot
var _car: CarController
var _panel: PanelContainer
var _where: Label
var _keys: Label
var _note: Label
var _note_timer := 0.0
## [Transform3D] where the car has been: on its wheels, facing the way it went.
var _car_trail: Array[Transform3D] = []


## Dev mode exists in editor runs and debug exports, never in release builds.
static func available() -> bool:
	return OS.is_debug_build()


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = bool(cfg.get_value("dev", "enabled", false))
	_panel.visible = enabled


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == TOGGLE_KEY:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()
		return
	if not enabled or get_tree().paused:
		return
	var done := true
	match key.keycode:
		KEY_U:
			unstuck()
		KEY_V:
			toggle_fly()
		KEY_1:
			go_home()
		KEY_2:
			go_to_car()
		KEY_3:
			bring_car()
		KEY_X:
			mark_spot()
		_:
			done = false
	if done:
		get_viewport().set_input_as_handled()


func set_enabled(on: bool) -> void:
	enabled = on
	_panel.visible = on
	if not on and _find() and _player.noclip:
		_player.noclip = false
	var cfg := ConfigFile.new()
	cfg.set_value("dev", "enabled", on)
	cfg.save(SETTINGS_PATH)


func _physics_process(_delta: float) -> void:
	if not _find():
		return
	_track_car()


func _process(delta: float) -> void:
	_note_timer = maxf(_note_timer - delta, 0.0)
	if _note_timer <= 0.0:
		_note.text = ""
	if not enabled or not _find():
		return
	var p := _here()
	var tile := "%d_%d" % [floori(p.x / 500.0), floori(-p.z / 500.0)]
	var state := "in the car" if _player.in_car else ("flying" if _player.noclip
		else ("on the ground" if _player.is_on_floor() else "in the air"))
	_where.text = "%.1f, %.1f, %.1f   tile %s\n%s" % [p.x, p.y, p.z, tile, state]
	_keys.text = "U unstuck   V fly   X mark spot\n1 home   2 to the car   3 car to me" if not _player.in_car \
		else "U unstuck   X mark spot\n1 home (carport)"


# ---------------------------------------------------------------------------
# Actions (also called by tools/dev_mode_test.gd)
# ---------------------------------------------------------------------------

func unstuck() -> void:
	if not _find():
		return
	if _player.in_car:
		_say("Car moved back along the road." if _car_unstuck() else "Nowhere to put the car.")
	elif _player.noclip:
		_say("Flying: press V to land first.")
	else:
		_say("Unstuck." if _player.unstuck() else "Nowhere open nearby. Try 1 (home).")


func toggle_fly() -> void:
	if not _find():
		return
	if _player.in_car:
		_say("Get out of the car to fly.")
		return
	_player.noclip = not _player.noclip
	_say("Flying. E up, Q down, Space fast." if _player.noclip else "Landed.")


func go_home() -> void:
	if not _find():
		return
	var map := _map()
	var home := get_tree().get_first_node_in_group(&"home_base") as HomeBase
	if _player.in_car:
		_place_car(map.get_spawn_transform() if map else _car.global_transform)
		_say("Back in the carport.")
		return
	if home == null:
		_say("No home on this map.")
		return
	var at := home.spawn_transform(&"Spawn_Front")
	_player.noclip = false
	_player.teleport(at.origin + Vector3.UP * 0.1, at.origin + at.basis * Vector3.FORWARD * 4.0 + Vector3.UP * 1.5)
	_say("Home, out the front.")


func go_to_car() -> void:
	if not _find() or _player.in_car:
		return
	var feet := _player.car_side_spot()
	if feet == Vector3.INF:
		feet = _car.global_position + Vector3.UP * 2.0
	_player.noclip = false
	_player.teleport(feet + Vector3.UP * 0.05, _car.global_position + Vector3.UP * 1.0)
	_say("At the car.")


func bring_car() -> void:
	if not _find() or _player.in_car:
		return
	var yaw := _player.rotation.y
	var look := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := Vector3(-look.z, 0.0, look.x)
	# A few metres ahead, pointing the way you're looking.
	for offset: Vector3 in [look * 4.5, look * 4.5 + side * 2.0, look * 4.5 - side * 2.0, -look * 4.5]:
		var at := _ground(_player.global_position + offset + Vector3.UP * 1.5, 6.0)
		if at != Vector3.INF and _car_fits(at):
			_place_car(Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.6))
			_say("Car's here.")
			return
	_say("No room for the car here.")


## Puts where you are on the clipboard and at the end of user://dev_marks.txt.
func mark_spot() -> String:
	if not _find():
		return ""
	var p := _here()
	var line := "%s  %.2f, %.2f, %.2f  tile %d_%d  %s" % [Time.get_datetime_string_from_system(), p.x, p.y, p.z,
		floori(p.x / 500.0), floori(-p.z / 500.0), "car" if _player.in_car else "on foot"]
	var file := FileAccess.open(MARKS_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(MARKS_PATH) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
		file.close()
	DisplayServer.clipboard_set("%.2f, %.2f, %.2f" % [p.x, p.y, p.z])
	_say("Spot marked and copied.")
	return line


# ---------------------------------------------------------------------------

func _find() -> bool:
	if _player and is_instance_valid(_player) and _car and is_instance_valid(_car):
		return true
	var main := get_parent()
	_player = main.find_child("Player", true, false) as OnFoot if main else null
	_car = _player.get_node_or_null(_player.car_path) as CarController if _player else null
	return _player != null and _car != null


func _here() -> Vector3:
	return _car.global_position if _player.in_car else _player.global_position


func _map() -> Node:
	var map := get_tree().get_first_node_in_group(&"perth_map")
	return map if map and map.has_method(&"get_spawn_transform") else null


func _track_car() -> void:
	if not _player.in_car or _car.global_basis.y.dot(Vector3.UP) < 0.9:
		return
	if _ground(_car.global_position + Vector3.UP * 0.5, 2.0) == Vector3.INF:
		return
	var at := _car.global_position
	if not _car_trail.is_empty() and _car_trail.back().origin.distance_to(at) < CAR_TRAIL_STEP:
		return
	var forward := -_car.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		return
	_car_trail.append(Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), at))
	if _car_trail.size() > CAR_TRAIL_SIZE:
		_car_trail.pop_front()


func _car_unstuck() -> bool:
	var here := _car.global_position
	while not _car_trail.is_empty():
		var t: Transform3D = _car_trail.pop_back()
		if t.origin.distance_to(here) < CAR_BACK:
			continue
		var at := _ground(t.origin + Vector3.UP * 1.5, 4.0)
		if at != Vector3.INF and _car_fits(at):
			_place_car(Transform3D(t.basis, at + Vector3.UP * 0.6))
			return true
	# No trail (just spawned, or teleported): upright, a little higher.
	_car.reset_upright()
	return false


func _place_car(t: Transform3D) -> void:
	_car.global_transform = t
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_car_trail.clear()


## The first floor straight down from `from`, within `depth` metres.
func _ground(from: Vector3, depth: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * depth, 1 | 2)
	q.exclude = [_car.get_rid(), _player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
		return Vector3.INF
	return hit.position


## Room for a 500 standing on `ground` (nothing in a car-sized box above it).
func _car_fits(ground: Vector3) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 3.8)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(), ground + Vector3.UP * 0.95)
	q.collision_mask = 1 | 2
	q.exclude = [_car.get_rid(), _player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _say(text: String) -> void:
	_note.text = text
	_note_timer = 3.0


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DevPanel"
	_panel.add_theme_stylebox_override("panel", UiStyle.dark_card(10.0))
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -16.0
	_panel.offset_right = -16.0
	_panel.offset_top = 16.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	UiStyle.label(box, "DEV MODE   F3 hides", "LcdLabel", 20, UiStyle.LCD)
	_where = UiStyle.label(box, "", "LcdLabel", 18, UiStyle.LCD)
	_keys = UiStyle.label(box, "", "LcdLabel", 18, UiStyle.CREAM_TEXT)
	_note = UiStyle.label(box, "", "LcdLabel", 18, UiStyle.SUN)
	for label in box.get_children():
		(label as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
