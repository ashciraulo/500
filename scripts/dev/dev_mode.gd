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
##      along the way you walked); in the car, back along the way you drove,
##      upright (press again to go further back), or with no way back, onto
##      the nearest road or open ground
##   V  Fly (on foot): W/S where you look, A/D sideways, E/Q (or Space) up
##      and down, Shift fast. Walls don't stop you.
##   1  Home: on foot, out the front gate; in the car, back to the carport
##      (it says so if the car is already there)
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
## With no trail to go back along, unstuck looks this far (m) for a road,
## then for open level ground about as high as the car (not a roof), then for
## a road further off, to put the car on.
const ROAD_REACH := 30.0
const ROAD_REACH_FAR := 160.0
const OPEN_RINGS: Array[float] = [6.0, 9.0, 12.0, 16.0, 20.0, 25.0, 30.0, 40.0]
const OPEN_RISE := 1.5
## Home (1) in the car within this far (m) of the carport says it's already there.
const AT_CARPORT := 4.0

var enabled := false
## Where the on/off setting and marked spots go (tests point these elsewhere).
var settings_path := SETTINGS_PATH
var marks_path := MARKS_PATH

var _player: OnFoot
var _car: CarController
var _panel: PanelContainer
var _where: Label
var _keys: Label
var _note: Label
var _note_timer := 0.0
## [Transform3D] where the car has been: on its wheels, facing the way it went.
var _car_trail: Array[Transform3D] = []
## Keys pressed since the last physics step, done in the next one: a car moved
## while input is being handled can be put straight back by the physics step.
var _queued: Array[Key] = []


## Dev mode exists in editor runs and debug exports, never in release builds.
static func available() -> bool:
	return OS.is_debug_build()


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
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
	if key.keycode in [KEY_U, KEY_V, KEY_1, KEY_2, KEY_3, KEY_X]:
		_queued.append(key.keycode)
		get_viewport().set_input_as_handled()


func set_enabled(on: bool) -> void:
	enabled = on
	_panel.visible = on
	if not on and _find() and _player.noclip:
		_player.noclip = false
	var cfg := ConfigFile.new()
	cfg.set_value("dev", "enabled", on)
	cfg.save(settings_path)


func _physics_process(_delta: float) -> void:
	if not _find():
		return
	while not _queued.is_empty():
		match _queued.pop_front():
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
	_track_car()


func _process(delta: float) -> void:
	_note_timer = maxf(_note_timer - delta, 0.0)
	if _note_timer <= 0.0:
		_note.text = ""
	# Out of the way of the pause menu and title screen (it sits above them).
	_panel.visible = enabled and not get_tree().paused and not TitleScreen.is_showing(get_tree())
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
# Actions, done in the physics step (call them from _physics_process, or
# press the keys)
# ---------------------------------------------------------------------------

func unstuck() -> void:
	if not _find():
		return
	if _player.in_car:
		var from := _car.global_position
		var how := _car_unstuck()
		_log("U", from, how)
		match how:
			&"trail": _say("Car moved back along the way you came.")
			&"road": _say("Car moved onto the nearest road.")
			&"open": _say("Car moved onto open ground nearby.")
			_: _say("Nowhere open nearby: car put upright. Try 1 (carport).")
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
	_say("Flying. E up, Q down, Shift fast." if _player.noclip else "Landed.")


func go_home() -> void:
	if not _find():
		return
	var map := _map()
	var home := get_tree().get_first_node_in_group(&"home_base") as HomeBase
	if _player.in_car:
		var from := _car.global_position
		var spot: Transform3D = map.get_spawn_transform() if map else _car.global_transform
		_place_car(spot)
		_log("1", from, &"carport")
		_say("Already at the carport: car set straight." if from.distance_to(spot.origin) < AT_CARPORT
			else "Back in the carport.")
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
		if at != Vector3.INF and _car_fits(at, Basis(Vector3.UP, yaw)):
			var from := _car.global_position
			_place_car(Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.6))
			_log("3", from, &"beside you")
			# Turn round to it if it had to go beside or behind you.
			_player.face(_car.global_position + Vector3.UP * 0.5)
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
	var file := FileAccess.open(marks_path, FileAccess.READ_WRITE if FileAccess.file_exists(marks_path) else FileAccess.WRITE)
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


## Gets the car out: back along the trail it drove (keeping the rest of the
## trail, so pressing again goes further back), else onto the nearest road,
## else onto open level ground nearby, else just upright where it is.
## Returns which: &"trail", &"road", &"open" or &"" (upright in place).
func _car_unstuck() -> StringName:
	var here := _car.global_position
	while not _car_trail.is_empty():
		var t: Transform3D = _car_trail.pop_back()
		if t.origin.distance_to(here) < CAR_BACK:
			continue
		var at := _ground(t.origin + Vector3.UP * 1.5, 4.0)
		if at != Vector3.INF and _car_fits(at, t.basis):
			_move_car(Transform3D(t.basis, at + Vector3.UP * 0.6))
			return &"trail"
	var spot := _road_spot(here, ROAD_REACH)
	if spot != Transform3D.IDENTITY:
		_place_car(spot)
		return &"road"
	spot = _open_spot(here)
	if spot != Transform3D.IDENTITY:
		_place_car(spot)
		return &"open"
	spot = _road_spot(here, ROAD_REACH_FAR)
	if spot != Transform3D.IDENTITY:
		_place_car(spot)
		return &"road"
	_car.reset_upright()
	return &""


## On the nearest road (the sat-nav's roads) where the car fits, in the left
## lane facing the way the car was going, at least a car's length from where
## it is now. IDENTITY if none within `reach`.
func _road_spot(here: Vector3, reach: float) -> Transform3D:
	var data := MapData.shared()
	if not data.is_loaded:
		return Transform3D.IDENTITY
	var graph := data.routes
	var heading := -_car.global_basis.z
	var tries: Array = []  # [distance, point, tangent]
	for near: Array in graph.nearest(Vector2(here.x, here.z)):
		var r: int = near[0]
		if near[2] > reach:
			continue
		var pts := graph.road_pts[r]
		var cum := graph.road_cum[r]
		for ds: float in [0.0, 6.0, -6.0, 12.0, -12.0, 20.0, -20.0, 30.0, -30.0]:
			var s := clampf(float(near[1]) + ds, 0.0, graph.road_len[r])
			var p := TrafficGraph.point_at(pts, cum, s)
			var tangent := TrafficGraph.tangent_at(pts, cum, s)
			tangent.y = 0.0
			if tangent.length() < 0.1:
				continue
			tangent = tangent.normalized()
			if graph.road_oneway[r] == 0 and tangent.dot(heading) < 0.0:
				tangent = -tangent
			if graph.road_oneway[r] == 0 or graph.road_lanes_fwd[r] > 1:
				# Keep left, half a lane off the middle.
				p += Vector3(tangent.z, 0.0, -tangent.x) * RouteGraph.LANE_WIDTH * 0.5
			tries.append([Vector2(p.x - here.x, p.z - here.z).length(), p, tangent])
	tries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for t: Array in tries:
		if t[0] < 3.0:
			continue
		var p: Vector3 = t[1]
		var at := _ground(Vector3(p.x, p.y + 2.5, p.z), 5.0)
		var facing := Basis.looking_at(t[2], Vector3.UP)
		if at != Vector3.INF and _car_fits(at, facing):
			return Transform3D(facing, at + Vector3.UP * 0.6)
	return Transform3D.IDENTITY


## Open level ground near `here` (rings further and further out) where the
## car fits, nearest first and as near its height as can be, and no more than
## OPEN_RISE above or below it (so not a roof). IDENTITY if none.
func _open_spot(here: Vector3) -> Transform3D:
	var heading := -_car.global_basis.z
	heading.y = 0.0
	if heading.length() < 0.1:
		heading = Vector3.FORWARD
	var facing := Basis.looking_at(heading.normalized(), Vector3.UP)
	for radius in OPEN_RINGS:
		var best := Vector3.INF
		for i in 16:
			var angle := TAU * i / 16.0
			var p := here + Vector3(sin(angle), 0.0, cos(angle)) * radius
			var at := _ground(p + Vector3.UP * 8.0, 20.0, 0.9)
			if at == Vector3.INF or absf(at.y - here.y) > OPEN_RISE or not _car_fits(at, facing):
				continue
			if best == Vector3.INF or absf(at.y - here.y) < absf(best.y - here.y):
				best = at
		if best != Vector3.INF:
			return Transform3D(facing, best + Vector3.UP * 0.6)
	return Transform3D.IDENTITY


## Puts the car somewhere new: the trail behind it no longer leads there.
func _place_car(t: Transform3D) -> void:
	_move_car(t)
	_car_trail.clear()


func _move_car(t: Transform3D) -> void:
	_car.teleport(t)


## A line in the Godot output for each move, for when a key seems to do
## nothing: where the car is a couple of physics steps after it was moved.
func _log(key: String, from: Vector3, how: StringName) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _find():
		return
	var to := _car.global_position
	print("[dev] %s: car %s, (%.1f, %.1f, %.1f) -> (%.1f, %.1f, %.1f), %.1f m" % [key,
		how if how != &"" else &"upright in place", from.x, from.y, from.z, to.x, to.y, to.z, from.distance_to(to)])


## The first floor straight down from `from`, within `depth` metres: not
## under water, not on top of a car, and no steeper than `flat` allows.
func _ground(from: Vector3, depth: float, flat := 0.8) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * depth, 1 | 2 | MapTileLoader.LAYER_WATER)
	q.exclude = [_car.get_rid(), _player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < flat:
		return Vector3.INF
	var body := hit.collider as CollisionObject3D
	if body == null or body is RigidBody3D or body is CharacterBody3D or body.collision_layer & MapTileLoader.LAYER_WATER:
		return Vector3.INF
	return hit.position


## Room for a 500 standing on `ground` facing `facing` (nothing in a
## car-sized box above it).
func _car_fits(ground: Vector3, facing := Basis()) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 3.8)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(facing, ground + Vector3.UP * 0.95)
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
