extends SceneTree
## The Valiant's in-car view: the eye sits where the driver's head would be,
## ahead of the bench back (not over it) and well above it, with the stock
## bench and with the sheepskin covers. Fails (exit 1) otherwise. With
## shots=<dir> it photographs each: looking ahead, and looking back over the
## left shoulder at the bench.
##
##   godot --path . --resolution 1280x720 --script res://tools/valiant_eye_test.gd \
##       -- --no-save shots=/tmp/valiant_eye

const ID := "valiant_vc"
## The front bench back, from lib/valiant_cabin.py _seats: its face 0.07 m
## back at 0.95 m (just under the shoulders) and its top 1.066 m up (Blender
## y, z). The glb puts Blender (x, y, z) at (x, z, -y), the mesh 0.237 m back.
const BACK_FACE_Z := 0.07 + 0.237
const BACK_TOP_Y := 1.066
## A head is about this deep behind the eyes.
const HEAD_BEHIND_EYE := 0.06

var _shots := ""
var _main: Node
var _world: Node
var _car  # CarController
var _rig: Node
var _frames := -240
var _stage := 0
var _failed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1


func _measure(label: String) -> void:
	var cam := _rig.get_node("Camera3D") as Camera3D
	var eye: Vector3 = _car.to_local(cam.global_position)
	var cockpit: Vector3 = _car.to_local((_car.find_child("Cam_Cockpit", true, false) as Node3D).global_position)
	var origin_y: float = _car.to_local((_car.get_node("Body") as Node3D).global_position).y
	var ahead: float = BACK_FACE_Z - eye.z
	var above: float = eye.y - (BACK_TOP_Y + origin_y)
	print("%s: eye %s, Cam_Cockpit %s, %.3f m ahead of the bench back, %.3f m above its top" % [label, eye, cockpit, ahead, above])
	_check(eye.distance_to(cockpit) < 0.03, "%s: the eye is at the model's Cam_Cockpit (%.3f m off)" % [label, eye.distance_to(cockpit)])
	_check(ahead > HEAD_BEHIND_EYE, "%s: the head is ahead of the bench back, not in it (%.2f m)" % [label, ahead])
	_check(above > 0.12, "%s: and the eye is well above the bench (%.2f m)" % [label, above])


func _look(yaw: float, pitch: float) -> void:
	_rig.set("_look_yaw", yaw)
	_rig.set("_look_pitch", pitch)
	_rig.set("_look_idle", 0.0)


func _shoot(name: String) -> void:
	if _shots != "":
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
		print("shot ", name)


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		_rig = _world.get_node("CameraRig")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_frames += 1
	if _frames < 0:
		return false
	match _stage:
		0:
			MapData.shared().wait()
			_main.get_node("HUD").visible = false
			root.get_node("GameClock").set_time(11.0)
			_car.load_vehicle_state({"car_id": ID})
			_check(_car.car_id == ID, "in the Valiant")
			if _rig.get("mode") != 1:
				_rig.toggle_mode()
			_stage = 1
			_frames = 0
		1, 3:
			if _frames >= 60:
				_measure("stock bench" if _stage == 1 else "sheepskin covers")
				_shoot("eye_stock" if _stage == 1 else "eye_sheepskin")
				_look(2.0, -0.45)
				_stage += 1
				_frames = 0
		2, 4:
			_look(2.0, -0.45)
			if _frames >= 20:
				_shoot("eye_stock_shoulder" if _stage == 2 else "eye_sheepskin_shoulder")
				_look(0.0, 0.0)
				if _stage == 2:
					_car.install_part(load("res://scripts/vehicle/parts_catalogue.gd").get_part(&"seat_covers_vc_sheepskin"))
					_stage = 3
					_frames = 0
				else:
					_car.remove_part(&"seat_covers")
					_car.load_vehicle_state({"car_id": "pop_12"})
					print("valiant eye: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
					quit(1 if _failed else 0)
					return true
	return false
