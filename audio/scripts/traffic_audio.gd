extends Node
## Sound for the city's traffic (traffic/scripts/traffic_manager.gd): engines
## on the nearest cars, utes, vans and buses, their horns, the bus air brake,
## trains running past, level-crossing bells and the train horn, and the
## pedestrian-crossing beeps at signals.
##
## Engines are pooled: a few EngineAudio voices per kind are handed to the
## nearest vehicles of that kind a few times a second, so a street full of
## traffic costs the same as a handful of cars. Created by Audio.hooks when it
## finds the TrafficManager; see docs/HOOKS.md for the signals.

## Engine voices per kind, and the engine set each uses.
const VOICES := {&"car": 4, &"diesel": 2, &"bus": 2}
const SETS := {&"car": "sedan", &"diesel": "diesel", &"bus": "busdiesel"}
## Vehicle type (TrafficManager) -> engine kind. Unknown types sound like cars.
const KIND := {&"ute": &"diesel", &"van": &"diesel", &"bus": &"bus"}
## Only vehicles this close get an engine voice (m).
const HEAR_RADIUS := 90.0
## Rough gearing for AI engines: km/h at which each gear tops out.
const GEAR_TOPS := [18.0, 34.0, 52.0, 72.0, 200.0]
const CAR_HORNS := ["traffic/traffic_horn_car_01", "traffic/traffic_horn_car_02", "traffic/traffic_horn_car_03"]

var manager: Node
var hear_radius := HEAR_RADIUS

var _voices := {}            # kind -> Array of {"engine": EngineAudio, "v": TrafficVehicle or null}
var _assign_timer := 0.0
var _trains := {}            # train root -> AudioStreamPlayer3D
var _bells := {}             # crossing position (Vector3) -> AudioStreamPlayer3D
var _bus_moving := {}        # vehicle id -> bool


func setup(traffic_manager: Node) -> void:
	manager = traffic_manager
	manager.vehicle_spawned.connect(_on_vehicle_spawned)
	manager.train_spawned.connect(_on_train_spawned)
	if manager.has_signal("train_despawned"):
		manager.train_despawned.connect(_on_train_despawned)
	manager.crossing_changed.connect(_on_crossing_changed)
	manager.signals_changed.connect(_on_signals_changed)
	for kind in VOICES:
		_voices[kind] = []
		for i in VOICES[kind]:
			var e := EngineAudio.new()
			e.engine_set = SETS[kind]
			e.start_on_ready = false
			e.follow_parts = false
			e.unit_size = 6.0 if kind != &"bus" else 9.0
			e.max_distance = HEAR_RADIUS * 1.3
			e.volume_db = -4.0
			e.name = "TrafficEngine_%s_%d" % [kind, i]
			add_child(e)
			e.silence()
			_voices[kind].append({"engine": e, "v": null})
	# Vehicles that spawned before we got here.
	for v in manager.vehicles:
		_dress_vehicle(v.body, v.type)


func _kind(type: StringName) -> StringName:
	return KIND.get(type, &"car")


func _on_vehicle_spawned(body: Node3D, type: StringName) -> void:
	_dress_vehicle(body, type)


## Our horns in place of the placeholder (the manager plays it when it toots).
func _dress_vehicle(body: Node3D, type: StringName) -> void:
	var horn := body.get_node_or_null("Audio/Horn") as AudioStreamPlayer3D
	if horn == null:
		return
	if type == &"bus":
		horn.stream = Audio.stream("traffic/traffic_horn_bus")
	else:
		horn.stream = Audio.stream(CAR_HORNS[hash(body.get_instance_id()) % CAR_HORNS.size()])
	horn.bus = &"Vehicles"


func _process(delta: float) -> void:
	if not is_instance_valid(manager):
		return
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = 0.25
		_assign_voices()
	for kind in _voices:
		for voice in _voices[kind]:
			if voice.v != null:
				_drive_voice(voice, kind)
	_update_trains()


## Hand each kind's voices to the nearest vehicles of that kind.
func _assign_voices() -> void:
	var ear: Node3D = Audio.listener()
	if ear == null:
		return
	var here := ear.global_position
	var near := {}
	for kind in _voices:
		near[kind] = []
	for v in manager.vehicles:
		if not v.active:
			continue
		var d: float = here.distance_to(v.position)
		if d < hear_radius:
			near[_kind(v.type)].append([d, v])
	for kind in _voices:
		var list: Array = near[kind]
		list.sort_custom(func(a, b) -> bool: return a[0] < b[0])
		var wanted := []
		for i in mini(list.size(), _voices[kind].size()):
			wanted.append(list[i][1])
		# Keep voices already on a wanted vehicle; free the rest.
		var free := []
		for voice in _voices[kind]:
			if voice.v != null and wanted.has(voice.v):
				wanted.erase(voice.v)
			else:
				free.append(voice)
		for voice in free:
			if wanted.is_empty():
				if voice.v != null:
					voice.engine.silence()
					voice.engine.reparent(self, false)
					voice.v = null
				continue
			var v = wanted.pop_front()
			voice.v = v
			var e: EngineAudio = voice.engine
			e.silence()
			var holder: Node = v.body.get_node_or_null("Audio")
			e.reparent(holder if holder else v.body, false)
			e.position = Vector3.ZERO
			e.speed_kmh = v.speed * 3.6
			e.rpm = _rpm_for(e, e.speed_kmh)
			e.start_running()


func _drive_voice(voice: Dictionary, kind: StringName) -> void:
	var v = voice.v
	var e: EngineAudio = voice.engine
	if not v.active or not is_instance_valid(v.body):
		e.silence()
		e.reparent(self, false)
		voice.v = null
		return
	var kmh: float = v.speed * 3.6
	e.speed_kmh = kmh
	e.rpm = _rpm_for(e, kmh)
	e.throttle = clampf(0.25 + v.accel / 1.5, 0.0, 1.0)
	if kind == &"bus":
		var moving := kmh > 6.0
		if _bus_moving.get(v.id, true) and not moving and kmh < 1.0:
			_bus_moving[v.id] = false
			Audio.play_at("traffic/traffic_bus_air_brake", v.position, -4.0, "Vehicles")
		elif moving:
			_bus_moving[v.id] = true


## Pick a gear for the speed and put the revs in that gear's range: each
## upshift drops the revs to about 55% of the shift point.
func _rpm_for(e: EngineAudio, kmh: float) -> float:
	var idle: float = e._idle
	var shift: float = e._redline * 0.6
	var lo := 0.0
	for i in GEAR_TOPS.size():
		var hi: float = GEAR_TOPS[i]
		if kmh <= hi or i == GEAR_TOPS.size() - 1:
			var f := clampf((kmh - lo) / (hi - lo), 0.0, 1.0)
			return lerpf(idle if i == 0 else maxf(idle, shift * 0.55), shift, f)
		lo = hi
	return shift


# ---------------------------------------------------------------------------
# Trains and crossings
# ---------------------------------------------------------------------------

func _on_train_spawned(root_node: Node3D) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = Audio.stream("traffic/traffic_train_running", true)
	p.bus = "Vehicles"
	p.unit_size = 16.0
	p.max_distance = 400.0
	p.volume_db = -80.0
	root_node.add_child(p)
	p.play(randf() * 3.0)
	_trains[root_node] = p


func _on_train_despawned(root_node: Node3D) -> void:
	var p: AudioStreamPlayer3D = _trains.get(root_node)
	if p and is_instance_valid(p):
		p.queue_free()
	_trains.erase(root_node)


func _update_trains() -> void:
	for train in manager.trains:
		var p: AudioStreamPlayer3D = _trains.get(train.root)
		if p == null or not is_instance_valid(p):
			continue
		var r: float = clampf(train.speed / maxf(TrafficTrain.MAX_SPEED, 1.0), 0.0, 1.2)
		p.volume_db = linear_to_db(maxf(r, 0.001)) if r > 0.02 else -80.0
		p.pitch_scale = 0.6 + 0.5 * r
		# Follow the middle of the train, not just its front car.
		if train.cars.size() > 1:
			var mid: Node3D = train.cars[train.cars.size() / 2]
			if is_instance_valid(mid):
				p.global_position = mid.global_position


func _on_crossing_changed(pos: Vector3, closed: bool) -> void:
	var key := pos.snapped(Vector3.ONE)
	if closed:
		if not _bells.has(key):
			var p := AudioStreamPlayer3D.new()
			p.stream = Audio.stream("amb/amb_crossing_bells_loop", true)
			p.bus = "Vehicles"
			p.unit_size = 10.0
			p.max_distance = 260.0
			add_child(p)
			p.global_position = pos + Vector3(0, 2.5, 0)
			p.play()
			_bells[key] = p
		# The driver sounds the horn approaching the crossing.
		var train = _nearest_train(pos)
		if train:
			Audio.play_at("traffic/traffic_train_horn", train.root.global_position, 0.0, "Vehicles")
	elif _bells.has(key):
		var p: AudioStreamPlayer3D = _bells[key]
		_bells.erase(key)
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -40.0, 1.0)
		tw.tween_callback(p.queue_free)


func _nearest_train(pos: Vector3):
	var best = null
	var best_d := 600.0
	for train in manager.trains:
		if train.root and is_instance_valid(train.root):
			var d: float = train.root.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = train
	return best


## Signals changing: the pedestrian crossing beeps for the walk phase.
func _on_signals_changed(pos: Vector3) -> void:
	var ear: Node3D = Audio.listener()
	if ear and ear.global_position.distance_to(pos) < 70.0:
		Audio.play_at("amb/amb_ped_beep", pos + Vector3(0, 1.2, 0), -6.0, "Ambience")
