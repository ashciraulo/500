extends SceneTree
## How loud each car's engine is idling and pulling away: from rest, foot
## down, in automatic, on the same stretch of Little Shenton Lane. Prints
## the mean of the per-frame Engine and Car bus peaks (dBFS, as the PC
## checks measure them) per car, with the speed, gear and rpm reached.
## Runs in real time so the frames sample the mix as it plays (the dummy
## audio driver mixes too). nocomp switches the Engine bus compressor off.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/engine_loudness.gd \
##       -- --no-save cars=pop_12,valiant_vc frames=200

const SETTLE := 60

var _main: Node
var _world: Node
var _car  # CarController
var _home  # HomeBase
var _H79: GDScript
var _cars: PackedStringArray = ["pop_12", "valiant_vc"]
var _frames := 100
var _nocomp := false
var _i := -1
var _f := -240
var _eng: Array[float] = []
var _bus: Array[float] = []
var _rpm: Array[float] = []
var _idle: Array[float] = []


func _initialize() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("cars="):
			_cars = arg.trim_prefix("cars=").split(",")
		elif arg == "nocomp":
			_nocomp = true
		elif arg.begins_with("frames="):
			_frames = int(arg.trim_prefix("frames="))


func _hold(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func _peak(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))


static func _mean(xs: Array[float]) -> float:
	var s := 0.0
	for x in xs:
		s += x
	return s / maxf(xs.size(), 1.0)


func _start(id: String) -> void:
	_car.apply_car(id)
	_car.set_transmission(1)
	if _nocomp:
		var b := AudioServer.get_bus_index("Engine")
		for k in AudioServer.get_bus_effect_count(b):
			if AudioServer.get_bus_effect(b, k) is AudioEffectCompressor:
				AudioServer.set_bus_effect_enabled(b, k, false)
	var at: Vector3 = _home.to_global(_H79.at(Vector3(15.0, -6.6, 0.0))) + Vector3.UP * 0.8
	_car.teleport(Transform3D(_home.global_basis * Basis(Vector3.UP, PI * 0.5), at))
	_eng.clear()
	_bus.clear()
	_rpm.clear()
	_idle.clear()


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		_H79 = load("res://scripts/world/late_city/house_1979.gd")
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_f += 1
	if _i == -1:
		if _f > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			var first: Node = _main.find_child("FirstDay", true, false)
			if first:
				first.load_state({"step": 4})
			_home = get_first_node_in_group(&"home_base")
			root.get_node("GameClock").set_time(13.0)
			_i = 0
			_f = 0
			_start(_cars[0])
		return false
	if _f > SETTLE - 30 and _f < SETTLE:
		_idle.append(_peak("Engine"))
	if _f == SETTLE:
		_hold(&"accelerate", true)
	elif _f > SETTLE and _f <= SETTLE + _frames:
		_eng.append(_peak("Engine"))
		_bus.append(_peak("Car"))
		_rpm.append(float(_car.rpm))
	elif _f > SETTLE + _frames:
		_hold(&"accelerate", false)
		print("%s: idle %.1f dB, engine %.1f dB (top %.1f), car bus %.1f dB, %.0f km/h, gear %d, rpm %.0f (mean %.0f)" % [_cars[_i],
				_mean(_idle), _mean(_eng), _eng.max(), _mean(_bus), _car.speed_kmh(), _car.gear, _car.rpm, _mean(_rpm)])
		_i += 1
		if _i >= _cars.size():
			quit()
			return true
		_f = 0
		_start(_cars[_i])
	return false
