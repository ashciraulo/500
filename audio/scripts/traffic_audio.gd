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
## Vehicle type (TrafficManager) -> engine kind ("" for none: bicycles).
## Unknown types sound like cars.
const KIND := {&"ute": &"diesel", &"van": &"diesel", &"bus": &"bus", &"ambulance": &"diesel",
	&"fire": &"bus", &"bike": &""}
## Only vehicles this close get an engine voice (m).
const HEAR_RADIUS := 90.0
## Rough gearing for AI engines: km/h at which each gear tops out.
const GEAR_TOPS := [18.0, 34.0, 52.0, 72.0, 200.0]
const CAR_HORNS := ["traffic/traffic_horn_car_01", "traffic/traffic_horn_car_02", "traffic/traffic_horn_car_03"]
## Emergency vehicle type -> its siren loop (police wail and yelp, ambulance
## wail, fire truck's lower wail with a growl).
const SIRENS := {&"police": "traffic/traffic_siren_police_loop",
	&"ambulance": "traffic/traffic_siren_ambulance_loop", &"fire": "traffic/traffic_siren_fire_loop"}

var manager: Node
var hear_radius := HEAR_RADIUS

var _voices := {}            # kind -> Array of {"engine": EngineAudio, "v": TrafficVehicle or null}
var _assign_timer := 0.0
var _trains := {}            # train root -> AudioStreamPlayer3D
var _bells := {}             # crossing position (Vector3) -> AudioStreamPlayer3D
var _bus_moving := {}        # vehicle id -> bool
## Footsteps on the nearest pedestrians, and crowd walla where they gather.
const STEP_VOICES := 4
const STEP_RADIUS := 25.0
const STEP_KINDS := ["traffic/traffic_steps_shoes_loop", "traffic/traffic_steps_heels_loop",
	"traffic/traffic_steps_thongs_loop"]
## People within this of the listener count towards a crowd, and people
## within CROWD_SPREAD of each other make one.
const CROWD_RADIUS := 90.0
const CROWD_SPREAD := 15.0
## Sirens across the city (the manager's distant_siren calls): heard far off.
const FAR_SIREN := "amb/amb_siren_distant"
var _steps: Array = []       # {"player": AudioStreamPlayer3D, "ped": TrafficPedestrian or null}
var _crowd: AudioStreamPlayer3D
## Round home (the quiet lane) a crowd is a street or two over, behind the
## houses: this much further down.
const HOME_CROWD_DB := -12.0
var _crowd_small: AudioStreamPlayer3D
var _far_siren: AudioStreamPlayer3D
var _ped_timer := 0.0


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
			e.bus = &"Vehicles"  # traffic, not your car (the Surroundings slider)
			e.quiet_lift_db = 0.0
			e.name = "TrafficEngine_%s_%d" % [kind, i]
			add_child(e)
			e.silence()
			_voices[kind].append({"engine": e, "v": null})
	# Vehicles that spawned before we got here.
	for v in manager.vehicles:
		_dress_vehicle(v.body, v.type)
	# Trains at stations and ferries leaving the jetty (traffic phase 8 on).
	if manager.has_signal("train_arrived"):
		manager.train_arrived.connect(_on_train_arrived)
	if manager.has_signal("train_departed"):
		manager.train_departed.connect(_on_train_departed)
	if manager.has_signal("distant_siren"):
		manager.distant_siren.connect(_on_distant_siren)
	var boats = manager.get("boats")
	if boats is Object and boats.has_signal("ferry_departed"):
		boats.ferry_departed.connect(_on_ferry_departed)
	# A parking ticket arrives as a fine notice on the phone.
	var kerbside = manager.get("kerbside")
	if kerbside is Object and kerbside.has_signal("parking_ticket"):
		kerbside.parking_ticket.connect(func(_fine = 0, _reason = "", _pos = Vector3.ZERO) -> void:
			get_tree().create_timer(1.5).timeout.connect(func() -> void: Audio.hooks.phone_notify()))
	for i in STEP_VOICES:
		var p := _new_3d("Steps%d" % i, 3.0, STEP_RADIUS * 1.2, -8.0)
		_steps.append({"player": p, "ped": null})
	_crowd = _new_3d("CrowdBusy", 8.0, 120.0, -4.0)
	_crowd.stream = Audio.stream("traffic/traffic_crowd_busy_loop", true)
	_crowd_small = _new_3d("CrowdSmall", 4.0, 60.0, -6.0)
	_crowd_small.stream = Audio.stream("traffic/traffic_crowd_small_loop", true)
	for p in [_crowd, _crowd_small]:
		p.set_meta(&"mix_db", p.volume_db)
	# A siren 350-700 m off: big enough to carry, still falling away with distance.
	_far_siren = _new_3d("FarSiren", 40.0, 900.0, 0.0)
	_far_siren.bus = &"Ambience"
	_far_siren.max_db = 0.0


## An emergency call across the city: a far siren from that direction.
func _on_distant_siren(pos: Vector3, _type: StringName = &"") -> void:
	if not Audio.has(FAR_SIREN):
		return
	_far_siren.stream = Audio.variant(FAR_SIREN)
	_far_siren.global_position = pos + Vector3(0, 10, 0)
	_far_siren.pitch_scale = randf_range(0.96, 1.04)
	_far_siren.play()


func _new_3d(node_name: String, unit: float, max_d: float, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.bus = &"Vehicles"
	p.unit_size = unit
	p.max_distance = max_d
	p.volume_db = db
	add_child(p)
	return p


func _on_train_arrived(pos: Vector3) -> void:
	# The tail of the arrival (brakes, the stop and the air) as it stops,
	# then the doors.
	var a := Audio.play_at("traffic/traffic_train_arrive", pos, -2.0, "SFX", 0.0, 12.0, 300.0)
	if a:
		a.seek(6.0)
	Audio.play_at("traffic/traffic_train_doors", pos, -4.0, "SFX", 0.0)


func _on_train_departed(pos: Vector3) -> void:
	Audio.play_at("traffic/traffic_train_depart", pos, -2.0, "SFX", 0.0, 12.0, 300.0)


func _on_ferry_departed(pos: Vector3) -> void:
	# The wake reaches the shore a little after the ferry pulls away.
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		Audio.play_at("traffic/traffic_ferry_wake_loop", pos, -6.0, "SFX", 0.0))


func _dress_bike(body: Node3D, is_bike: bool) -> void:
	var audio := body.get_node_or_null("Audio") as Node3D
	if audio == null:
		return
	var fw := audio.get_node_or_null("Freewheel") as AudioStreamPlayer3D
	if not is_bike:
		if fw:
			fw.stop()
		return
	if fw == null:
		if not Audio.has("traffic/traffic_bike_freewheel_loop"):
			return
		fw = AudioStreamPlayer3D.new()
		fw.name = "Freewheel"
		fw.stream = Audio.stream("traffic/traffic_bike_freewheel_loop", true)
		fw.bus = &"Vehicles"
		fw.unit_size = 3.0
		fw.max_distance = 30.0
		fw.volume_db = -10.0
		fw.pitch_scale = randf_range(0.85, 1.15)
		audio.add_child(fw)
	fw.play(randf() * fw.stream.get_length())


func _kind(type: StringName) -> StringName:
	return KIND.get(type, &"car")


func _on_vehicle_spawned(body: Node3D, type: StringName) -> void:
	_dress_vehicle(body, type)


## Our horns and sirens in place of the placeholders (the manager plays
## them), and a freewheel ticking on bikes.
func _dress_vehicle(body: Node3D, type: StringName) -> void:
	var siren := body.get_node_or_null("Audio/Siren") as AudioStreamPlayer3D
	if siren and SIRENS.has(type) and Audio.has(SIRENS[type]):
		var was_playing := siren.playing
		siren.stream = Audio.stream(SIRENS[type], true)
		if was_playing:
			siren.play(randf() * siren.stream.get_length())
	_dress_bike(body, type == &"bike")
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
	_ped_timer -= delta
	if _ped_timer <= 0.0:
		_ped_timer = 0.5
		_assign_people(manager.get("pedestrians"))
	_drive_steps()


## Footsteps on the few nearest walking pedestrians; crowd walla from the
## middle of the biggest group of people nearby (busy for 8+, small for 3+).
## The group is found among the people themselves, so the walla stays where
## they are and falls away as you leave, rather than following you.
func _assign_people(peds) -> void:
	var ear: Node3D = Audio.listener()
	if not peds is Array or ear == null:
		return
	var here := ear.global_position
	var near: Array = []
	var around: Array[Vector3] = []
	for ped in peds:
		if not ped is Object:
			continue
		var pos = ped.get("position")
		if not pos is Vector3:
			continue
		var d: float = here.distance_to(pos)
		if d < STEP_RADIUS and float(ped.get("speed") if ped.get("speed") != null else 0.0) > 0.3:
			near.append([d, ped])
		if d < CROWD_RADIUS:
			around.append(pos)
	var group := crowd_at(around)
	var crowd_n: int = group[1]
	var crowd_sum: Vector3 = group[0] * crowd_n
	near.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var wanted: Array = near.slice(0, STEP_VOICES).map(func(e): return e[1])
	for voice in _steps:
		if voice.ped != null and not wanted.has(voice.ped):
			voice.ped = null
			voice.player.stop()
	for ped in wanted:
		var taken := false
		for voice in _steps:
			if voice.ped == ped:
				taken = true
		if taken:
			continue
		for voice in _steps:
			if voice.ped == null:
				voice.ped = ped
				var kind: String = STEP_KINDS[hash(ped.get_instance_id()) % STEP_KINDS.size()]
				voice.player.stream = Audio.stream(kind, true)
				if voice.player.stream:
					voice.player.play(randf() * 4.0)
				break
	_set_crowd(_crowd, crowd_n >= 8, crowd_sum / maxf(crowd_n, 1))
	_set_crowd(_crowd_small, crowd_n >= 3 and crowd_n < 8, crowd_sum / maxf(crowd_n, 1))


## The biggest group among these positions: [its middle, how many], people
## within CROWD_SPREAD of the busiest one.
static func crowd_at(positions: Array[Vector3]) -> Array:
	var best := -1
	var best_n := 0
	for i in positions.size():
		var n := 0
		for q in positions:
			if positions[i].distance_squared_to(q) < CROWD_SPREAD * CROWD_SPREAD:
				n += 1
		if n > best_n:
			best_n = n
			best = i
	if best < 0:
		return [Vector3.ZERO, 0]
	var sum := Vector3.ZERO
	for q in positions:
		if positions[best].distance_squared_to(q) < CROWD_SPREAD * CROWD_SPREAD:
			sum += q
	return [sum / best_n, best_n]


func _set_crowd(p: AudioStreamPlayer3D, on: bool, at: Vector3) -> void:
	if p.stream == null:
		return
	if on:
		var home: bool = Audio.ambience.zone == "home"
		p.volume_db = float(p.get_meta(&"mix_db", p.volume_db)) + (HOME_CROWD_DB if home else 0.0)
		p.global_position = at + Vector3(0, 1.5, 0)
		if not p.playing:
			p.play(randf() * p.stream.get_length())
	elif p.playing:
		p.stop()


func _drive_steps() -> void:
	for voice in _steps:
		var ped = voice.ped
		if ped == null:
			continue
		var pos = ped.get("position")
		if pos is Vector3:
			voice.player.global_position = pos + Vector3(0, 0.1, 0)
		var speed = ped.get("speed")
		voice.player.pitch_scale = clampf(float(speed if speed != null else 1.4) / 1.4, 0.6, 1.6)


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
			var kind := _kind(v.type)
			if near.has(kind):
				near[kind].append([d, v])
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
			Audio.play_at("traffic/traffic_train_horn", train.root.global_position, 0.0, "Vehicles", 0.04, 30.0, 800.0)
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
