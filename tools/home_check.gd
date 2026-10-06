extends SceneTree
## Headless check of the player's townhouse (scenes/home/shenton.tscn):
##
##   godot --headless --path . --script res://tools/home_check.gd
##
## Exits with code 1 if anything the game relies on is missing.

const DOORS := [&"Door_Front", &"Door_French_L", &"Door_French_R", &"Door_Balcony_L", &"Door_Balcony_R",
	&"Door_Sliding", &"Door_Storage", &"Door_Laundry", &"Door_Toilet",
	&"Door_Bed1", &"Door_Bath_Bed", &"Door_Bath_Landing", &"Door_WC_Up", &"Door_Bed2",
	&"Door_Gate", &"Door_Front_Gate", &"Shed_Door"]
const MARKERS := [&"Spawn_Player", &"Spawn_Front", &"Spawn_Courtyard", &"Spawn_Car"]

var _home: Node3D
var _frame := 0
var _waited := 0.0
var _failures: Array[String] = []


func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_home = load("res://scenes/home/shenton.tscn").instantiate()
		root.add_child(_home)
		return false
	if _frame == 2:
		_check_static()
		_check(_home.toggle_door(&"Door_Front"), "front door opens")
		for d in [&"Door_French_L", &"Door_French_R", &"Door_Balcony_L", &"Door_Balcony_R"]:
			_home.toggle_door(d)
		_check(not _home.toggle_door(&"Shed_Door"), "shed is locked until the key is found")
		return false
	_waited += delta
	if _waited < 1.0:  # let the door tweens (0.6 s) finish
		return false
	_check(_home.is_door_open(&"Door_Front"), "front door reports open")
	var leaf: Node3D = _home.find_child("Door_Front", true, false)
	_check(absf(leaf.rotation.y) > 1.0, "front door leaf swung (%.2f rad)" % leaf.rotation.y)
	for d in [&"Door_Front", &"Door_French_L", &"Door_French_R", &"Door_Balcony_L", &"Door_Balcony_R"]:
		_check(_opens_inward(d), "%s opens into the house" % d)
	_home.unlock_shed()
	_check(_home.toggle_door(&"Shed_Door"), "shed opens once unlocked")
	var lock: Node3D = _home.find_child("Padlock", true, false)
	_check(lock == null or not lock.visible, "padlock is gone")
	var car: Vector3 = _home.spawn_transform(&"Spawn_Car").origin
	_check(car.z < -15.0, "car spawns in the carport behind the house (z=%.1f)" % car.z)
	for f in _failures:
		printerr("FAIL: ", f)
	print("HOME CHECK ", "PASSED" if _failures.is_empty() else "FAILED")
	quit(1 if _failures.size() else 0)
	return true


func _check_static() -> void:
	var names: Array = _home.door_names()
	for d in DOORS:
		_check(d in names, "door %s exists" % d)
	for m in MARKERS:
		_check(_home.has_marker(m), "marker %s exists" % m)
	_check(_home.has_marker(&"Bed"), "bed marker exists")
	var bodies := _home.find_children("*", "StaticBody3D", true, false)
	_check(bodies.size() > 20, "walls and furniture have collision (%d bodies)" % bodies.size())
	var lamps := _home.find_children("*", "OmniLight3D", true, false)
	_check(lamps.size() >= 15, "lamps at the light markers (%d)" % lamps.size())


## The street is at +Z, so an open front-wall leaf's middle should sit at -Z
## of its hinge.
func _opens_inward(door_name: StringName) -> bool:
	var leaf: Node3D = _home.find_child(String(door_name), true, false)
	var mesh: MeshInstance3D = leaf if leaf is MeshInstance3D else leaf.find_children("*", "MeshInstance3D")[0]
	var mid := mesh.global_transform * mesh.get_aabb().get_center()
	return mid.z < leaf.global_position.z - 0.2


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
