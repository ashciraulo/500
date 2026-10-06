extends SceneTree
## Drives the car along a fixed route at a steady speed and records how long
## every frame takes, to find the hitches when map tiles stream in:
##
##   godot --path . --fixed-fps 60 --script res://tools/stream_bench.gd -- route=city out=/tmp/city.csv
##
## Routes: "city" (home, James St, William St, the CBD) and "herdsman" (a loop
## round Herdsman Lake). The car is frozen and moved along the route, so the
## run is the same every time. Works headless too (CPU only, no GPU uploads).
## Writes one line a frame: frame, ms, tiles loaded that frame, x, z. Prints a
## summary: frames over 50 and 100 ms, the worst frame, and the mean.

const ROUTES := {
	city = [Vector2(0, 0), Vector2(-30, 54), Vector2(300, 80), Vector2(350, 600),
		Vector2(420, 1300), Vector2(600, 1450)],
	herdsman = [],  # a circle, filled in below
}
const HERDSMAN_CENTRE := Vector2(-4660, -2940)
const HERDSMAN_RADIUS := 750.0
const SETTLE_FRAMES := 300

var _main: Node
var _map: Node
var _car: RigidBody3D
var _path: Array[Vector2] = []
var _speed := 60.0 / 3.6
var _along := 0.0
var _length := 0.0
var _frame := -1
var _last_usec := 0
var _rows: PackedStringArray = []
var _times: PackedFloat32Array = []
var _loaded_now := 0
var _unloaded_now := 0
var _out := "user://stream_bench.csv"
var _route := "city"
var _y := 25.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("route="):
			_route = arg.trim_prefix("route=")
		elif arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
		elif arg.begins_with("kmh="):
			_speed = float(arg.trim_prefix("kmh=")) / 3.6
	if _route == "herdsman":
		for i in 65:
			var a := TAU * i / 64.0
			_path.append(HERDSMAN_CENTRE + Vector2(cos(a), sin(a)) * HERDSMAN_RADIUS)
	else:
		for p: Vector2 in ROUTES[_route]:
			_path.append(p)
	for i in range(1, _path.size()):
		_length += _path[i - 1].distance_to(_path[i])


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(12.0)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_map = _main.get_node("LoFi/SubViewport/World/PerthMap")
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_map.tile_loaded.connect(func(_key: Vector2i) -> void: _loaded_now += 1)
		_map.tile_unloaded.connect(func(_key: Vector2i) -> void: _unloaded_now += 1)
		return false
	_frame += 1
	if _frame == 1:
		_car.freeze = true
		_place(0.0)
	if _frame < SETTLE_FRAMES:  # let the start of the route stream in
		_last_usec = Time.get_ticks_usec()
		_loaded_now = 0
		_unloaded_now = 0
		return false
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	var at := _place(_along)
	_rows.append("%d,%.2f,%d,%d,%.0f,%.0f,%.1f,%.1f" % [_frame - SETTLE_FRAMES, ms, _loaded_now, _unloaded_now, at.x, at.y,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_times.append(ms)
	_loaded_now = 0
	_unloaded_now = 0
	_along += _speed / 60.0
	if _along >= _length:
		_finish()
		return true
	return false


## Puts the car on the route `d` metres along it, on the ground.
func _place(d: float) -> Vector2:
	var at := _path[-1]
	var heading := Vector2.UP
	for i in range(1, _path.size()):
		var seg := _path[i - 1].distance_to(_path[i])
		if d <= seg:
			at = _path[i - 1].lerp(_path[i], d / seg)
			heading = (_path[i] - _path[i - 1]).normalized()
			break
		d -= seg
	var space := (_car as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400, at.y), Vector3(at.x, -100, at.y), 1, [_car.get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_y = hit.position.y
	_car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-heading.x, -heading.y)), Vector3(at.x, _y + 0.6, at.y))
	_car.linear_velocity = Vector3(heading.x, 0, heading.y) * _speed
	return at


func _finish() -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_line("frame,ms,tiles_loaded,tiles_unloaded,x,z,process_ms,physics_ms")
	for row in _rows:
		f.store_line(row)
	var over50 := 0
	var over100 := 0
	var worst := 0.0
	var total := 0.0
	for t in _times:
		over50 += 1 if t > 50.0 else 0
		over100 += 1 if t > 100.0 else 0
		worst = maxf(worst, t)
		total += t
	print("BENCH %s %.2f km at %.0f km/h: %d frames, mean %.1f ms, worst %.0f ms, %d over 50 ms, %d over 100 ms" % [
		_route, _length / 1000.0, _speed * 3.6, _times.size(), total / _times.size(), worst, over50, over100])
	quit(0)
