extends SceneTree
## Drives the Pop at kerbs built like the map's (a trimesh wall up to a
## trimesh footpath, tools/osm_import build.py: 14 cm on the flat, up to
## 22 cm where streets slope), slowly, head on and at angles, and checks it
## rides up onto them; then at a 40 cm wall, which should still stop it.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/kerb_test.gd -- --no-save
##
## Exits with code 1 if any check fails.

const KERB := 0.14
const WALL := 0.4
const CASES := [
	{"name": "a kerb, head on at 8 km/h", "height": KERB, "yaw": 0.0, "kmh": 8.0, "over": true},
	{"name": "a kerb, head on at 3 km/h", "height": KERB, "yaw": 0.0, "kmh": 3.0, "over": true},
	{"name": "a kerb, at 30 degrees at 5 km/h", "height": KERB, "yaw": 0.52, "kmh": 5.0, "over": true},
	{"name": "a kerb, clipped at 60 degrees at 5 km/h", "height": KERB, "yaw": 1.05, "kmh": 5.0, "over": true},
	{"name": "a 20 cm kerb, head on at 5 km/h", "height": 0.2, "yaw": 0.0, "kmh": 5.0, "over": true},
	{"name": "a 20 cm kerb, at 30 degrees at 5 km/h", "height": 0.2, "yaw": 0.52, "kmh": 5.0, "over": true},
	{"name": "a 22 cm kerb, head on at 5 km/h", "height": 0.22, "yaw": 0.0, "kmh": 5.0, "over": true},
	{"name": "a 22 cm kerb, at 30 degrees at 10 km/h", "height": 0.22, "yaw": 0.52, "kmh": 10.0, "over": true},
	{"name": "a 40 cm wall, head on at 8 km/h", "height": WALL, "yaw": 0.0, "kmh": 8.0, "over": false},
]

var _world: Node3D
var _car  # CarController (untyped: a tool script compiles before the autoloads)
var _case := -1
var _time := 0.0  # seconds into this case, so any --fixed-fps works
var _failures: Array[String] = []


func _process(delta: float) -> bool:
	if _world == null or _time > 14.0:
		if _world:
			_judge()
			_world.queue_free()
			_world = null
			return false
		_case += 1
		if _case >= CASES.size():
			return _finish()
		_build(CASES[_case])
		_time = 0.0
		return false
	_time += delta
	if _time > 1.0:
		var target: float = CASES[_case].kmh / 3.6
		var speed: float = _car.linear_velocity.length()
		_car.throttle_input = clampf((target - speed) * 0.6 + 0.15, 0.0, 1.0)
		_car.brake_input = 0.0
	return false


func _build(c: Dictionary) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	# The kerb (or wall) runs across the road 8 m ahead of the car's middle,
	# turned by yaw about that point, with a footpath beyond.
	_kerb(float(c.height), float(c.yaw))
	_car = (load("res://scenes/vehicles/fiat_500_pop.tscn") as PackedScene).instantiate()
	_car.player_controlled = false
	_car.position = Vector3(0, 0.6, 0)
	_world.add_child(_car)


func _judge() -> void:
	var c: Dictionary = CASES[_case]
	# On the footpath means the car's middle is past the kerb line and it sits higher.
	var line := Transform3D(Basis(Vector3.UP, float(c.yaw)), Vector3(0, 0, -8))
	var past: bool = (line.affine_inverse() * _car.global_position).z < -2.5
	var up: bool = _car.global_position.y > 0.45 + float(c.height) * 0.7
	var over: bool = past and up
	print("    at %s, %.1f km/h" % [_car.global_position, _car.linear_velocity.length() * 3.6])
	_check(over == c.over, ("rides up " if c.over else "stopped by ") + c.name)


## One-sided triangles like the map's tiles: a vertical wall facing the car
## and the footpath on top, 40 m wide and 30 m deep.
func _kerb(height: float, yaw: float) -> void:
	var a := Vector3(-20, 0, 0)
	var b := Vector3(20, 0, 0)
	var at := Vector3.UP * height
	var back := Vector3(0, 0, -30)
	var faces := PackedVector3Array([
		a, a + at, b + at, a, b + at, b,
		a + at, a + at + back, b + at + back, a + at, b + at + back, b + at,
	])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = false
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0, 0.0, -8))
	_world.add_child(body)


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = at
	_world.add_child(body)
	return body


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	print("KERBS ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	quit(1 if _failures.size() else 0)
	return true
