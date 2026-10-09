extends SceneTree
## Drives across each road where the map's old southern edge (z 10500, above
## Bibra Lake) now carries on into the stage 7 tiles: no end-of-map barriers
## left across them. Headless:
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/edge_cross_test.gd -- --no-save
##
## Each run starts 45 m one side of the edge on the road and steers along it
## to 45 m the other side. Exits with code 1 if the car doesn't get there.

## [name, from, to] (y is found on the ground).
const CROSSINGS := [
	["North Lake Rd southbound", Vector3(-3604.4, 0, 10455.0), Vector3(-3603.3, 0, 10545.0)],
	["North Lake Rd northbound", Vector3(-3613.3, 0, 10545.0), Vector3(-3614.3, 0, 10455.0)],
	["Love St", Vector3(-3909.9, 0, 10455.0), Vector3(-3909.5, 0, 10545.0)],
	["Aiken St", Vector3(-3797.2, 0, 10455.0), Vector3(-3795.5, 0, 10545.0)],
	["Prosser Way", Vector3(-3501.3, 0, 10455.0), Vector3(-3500.7, 0, 10545.0)],
	["Choules Pl", Vector3(-3399.7, 0, 10455.0), Vector3(-3399.1, 0, 10545.0)],
	["Spargo St", Vector3(-3298.2, 0, 10455.0), Vector3(-3297.6, 0, 10545.0)],
	["Malland St", Vector3(-3166.4, 0, 10455.0), Vector3(-3165.3, 0, 10545.0)],
]
const TIME_LIMIT := 25.0
const ARRIVE := 6.0

var _main: Node
var _car: RigidBody3D
var _map: Node
var _failures: Array[String] = []
var _k := -1
var _phase := 0
var _t := 0.0
var _quitting := false


func _process(delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_map = _main.get_node("LoFi/SubViewport/World/PerthMap")
		_next_crossing()
		return false
	_t += delta
	var c: Array = CROSSINGS[_k]
	var from: Vector3 = c[1]
	var to: Vector3 = c[2]
	match _phase:
		0:  # Wait for the ground at both ends.
			if _map.has_collision_at(from) and _map.has_collision_at(to) and _t > 1.0:
				var y := _ground(from)
				var dir := (to - from) * Vector3(1, 0, 1)
				var t := Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), Vector3(from.x, y + 0.6, from.z))
				_car.freeze = false
				_car.teleport(t)
				_phase = 1
				_t = 0.0
			elif _t > 30.0:
				_fail("%s: tiles didn't load" % c[0])
		1:  # Settle.
			if _t > 1.0:
				_phase = 2
				_t = 0.0
		2:  # Drive along the road to the far side.
			var flat := Vector3(_car.global_position.x, 0, _car.global_position.z)
			var to_go := Vector3(to.x, 0, to.z) - flat
			var fwd := -_car.global_basis.z
			fwd.y = 0
			var side := fwd.normalized().cross(to_go.normalized()).y
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			if side > 0.02:
				Input.action_press("steer_left", clampf(side * 3.0, 0.0, 1.0))
			elif side < -0.02:
				Input.action_press("steer_right", clampf(-side * 3.0, 0.0, 1.0))
			Input.action_press("accelerate", 0.6 if _car.speed_kmh() < 35.0 else 0.0)
			if to_go.length() < ARRIVE or to_go.dot(to - from) < 0.0:
				print("  ok   %s (%.1f s)" % [c[0], _t])
				_next_crossing()
			elif _t > TIME_LIMIT:
				_fail("%s: stuck %.0f m short at %s (%.0f km/h)" % [c[0], to_go.length(), _car.global_position, _car.speed_kmh()])
	return false


func _fail(msg: String) -> void:
	print("  FAIL %s" % msg)
	_failures.append(msg)
	_next_crossing()


func _next_crossing() -> void:
	for a in ["accelerate", "steer_left", "steer_right"]:
		Input.action_release(a)
	_k += 1
	_phase = 0
	_t = 0.0
	if _k >= CROSSINGS.size():
		_finish()
		return
	var from: Vector3 = CROSSINGS[_k][1]
	_car.freeze = true
	_car.global_position = Vector3(from.x, 60.0, from.z)


func _ground(p: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200, p.z), Vector3(p.x, -50, p.z))
	q.exclude = [_car.get_rid()]
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else 20.0


func _finish() -> void:
	_quitting = true
	if _failures.is_empty():
		print("EDGE CROSS TEST PASSED")
		quit(0)
	else:
		print("EDGE CROSS TEST FAILED (%d)" % _failures.size())
		quit(1)
