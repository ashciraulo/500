extends SceneTree
## Headless check that the player always ends up on the ground in the real
## Perth map: a fresh start, a save from before the map (test-grid
## coordinates), and a saved position with no ground under it.
##
##   godot --headless --path . --fixed-fps 120 --script res://tools/spawn_test.gd -- --no-save
##
## Exits with code 1 if any check fails. CI runs this.

const FPS := 120

var _main: Node
var _car: RigidBody3D
var _map: Node
var _failures: Array[String] = []
var _step := 0
var _frame := 0
var _start := Vector3.ZERO
var _quitting := false


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_map = _main.get_node("LoFi/SubViewport/World/PerthMap")
		_start = _map.get_spawn_transform().origin
		return false
	_frame += 1
	match _step:
		0:  # Fresh start: settles in the carport.
			if _seconds() >= 3.0:
				_check_on_ground("fresh start")
				_check(_car.global_position.distance_to(_start) < 2.0, "starts at home (%.1f m from the spawn)" % _car.global_position.distance_to(_start))
				# A save from the test-grid days: its car position must be dropped.
				var save := root.get_node("SaveGame")
				var old: Dictionary = save._migrate({"version": 1, "car": {"position": [12.0, 0.47, 7.0], "yaw": 0.5, "car_id": "pop_12"}})
				_check(not old.car.has("position"), "old saves lose their test-grid car position")
				_check(old.car.get("car_id", "") == "pop_12", "old saves keep the car itself")
				# A bad position anyway (a v2 save pointing into the void).
				_car.load_state({"position": [12.0, 0.47, 7.0], "yaw": 0.5})
				_next()
		1:
			if _seconds() >= 8.0:
				_check_on_ground("save pointing under the map")
				_check(_car.global_position.distance_to(_start) < 2.0, "goes home when there's no ground (%.1f m from the spawn)" % _car.global_position.distance_to(_start))
				return _finish()
	return false


func _check_on_ground(what: String) -> void:
	_check(_car.grounded_wheels == 4, "%s: all four wheels on the ground (%d)" % [what, _car.grounded_wheels])
	_check(_car.linear_velocity.length() < 0.5, "%s: car is at rest (%.1f m/s)" % [what, _car.linear_velocity.length()])
	_check(_car.global_position.y > _start.y - 3.0, "%s: car is at ground height (y=%.1f)" % [what, _car.global_position.y])


func _seconds() -> float:
	return float(_frame) / FPS


func _next() -> void:
	_step += 1
	_frame = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	if _failures.is_empty():
		print("SPAWN TEST PASSED")
	else:
		print("SPAWN TEST FAILED (%d)" % _failures.size())
		for f in _failures:
			print("  - " + f)
	# Takes the game down before quitting (a plain quit() crashed on exit on Windows).
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(0 if _failures.is_empty() else 1)
	return false
