class_name Oddities
extends Node3D
## Night oddities: small, quiet, unexplained things after midnight. No
## combat and nothing jumps out; each one counts as a discovery
## ("oddity/<id>") the first time you notice it.
##
##   midnight_station  an unlisted frequency on the radio (the radio itself
##                     is audio/scripts/radio.gd; this just notices you found it)
##   kings_park_car    headlights that follow you through Kings Park, keeping
##                     their distance, and are gone when you turn round
##   lane_idle         a classic 500 idling at the end of Little Shenton Lane;
##                     the sound stops before you get there
##   river_lights      soft lights hanging over the river by Riverside Drive

const NIGHT_FROM := 0.0
const NIGHT_TO := 3.5
## How close to the Kings Park lookout counts as being in the park.
const PARK_RADIUS := 1100.0
## The follower keeps about this far behind you.
const FOLLOW_GAP := 38.0
const FOLLOW_MAX_TIME := 75.0
## How far down the lane (m, from the carport, the way you drive out) the
## classic idles at night. Past about 60 m the lane meets buildings.
const LANE_END_DISTANCE := 45.0
const MODEL := preload("res://art/models/cars/pop/pop.glb")

var _car: CarController
var _check := 0.0
var _park_centre := Vector3.INF
var _lane_end := Vector3.INF
var _river := Vector3.INF
var _trail: Array[Vector3] = []
var _follower: Node3D
var _follow_time := 0.0
var _followed_tonight := -1
var _idle: AudioStreamPlayer3D  # the lane idle loop while it plays
var _idle_tonight := -1
var _lights: Node3D


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	for site in get_tree().get_nodes_in_group(&"job_sites"):
		if site.get("site_id") == "kings_park_lookout":
			_park_centre = (site as Node3D).global_position
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map == null:
		map = get_parent().get_parent().get_node_or_null("PerthMap")
	if map and map.has_method("get_spawn_transform"):
		var spawn: Transform3D = map.get_spawn_transform()
		# The far end of the lane, the way you drive out of the carport.
		_lane_end = spawn.origin - spawn.basis.z * LANE_END_DISTANCE
	var places: Dictionary = get_parent().get("places") if get_parent() else {}
	for spot: Dictionary in places.get("photo_spots", []):
		if spot.id == "riverside_east":
			# The river is south of Riverside Drive (+Z); hang the lights out over it.
			_river = Vector3(spot.p[0], spot.p[1], spot.p[2] + 70.0)
	var radio = _radio()
	if radio and radio.has_signal("station_changed"):
		radio.station_changed.connect(func(id: String, _name: String) -> void:
			if id == "midnight":
				_notice("midnight_station", "There's something on that frequency that isn't on the dial."))


func _radio() -> Object:
	var audio := get_node_or_null("/root/Audio")
	return audio.get("radio") if audio else null


func _process(delta: float) -> void:
	if _follower:
		_move_follower(delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		return
	var night := is_night()
	_trail.append(_car.global_position)
	if _trail.size() > 240:
		_trail.pop_front()
	_check_follower(night)
	_check_lane(night)
	_check_river(night)


func is_night() -> bool:
	var h := GameClock.time_of_day
	return h >= NIGHT_FROM and h < NIGHT_TO


func _notice(id: String, text: String) -> void:
	if Discoveries.has("oddity/" + id):
		return
	Discoveries.discover("oddity/" + id)
	# The midnight station has its own cue; the rest share the discovery sting.
	# Notices plays it as the card shows.
	if id == "midnight_station":
		Notices.post(text, "odd", "oddity/odd_midnight_station_found", "", "Music")
	else:
		Notices.post(text, "odd")


## Sound hooks: each plays nothing if the audio thread hasn't added it yet.
func _audio() -> Node:
	return get_node_or_null("/root/Audio")


func _play_at(sound: String, at: Vector3, volume_db := 0.0) -> void:
	var audio := _audio()
	if audio and audio.has(sound):
		audio.play_at(sound, at, volume_db)


func _loop_player(sound: String, unit_size := 8.0, volume_db := -4.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = &"SFX"
	player.unit_size = unit_size
	player.volume_db = volume_db
	var audio := _audio()
	if audio and audio.has(sound):
		player.stream = audio.stream(sound, true)
		player.autoplay = true
	return player


# --- Kings Park follower -------------------------------------------------------

func _check_follower(night: bool) -> void:
	var in_park := _park_centre != Vector3.INF and _car.global_position.distance_to(_park_centre) < PARK_RADIUS
	if _follower == null:
		if night and in_park and _followed_tonight != GameClock.day and _car.speed_kmh() > 25.0 and _trail.size() > 30:
			_followed_tonight = GameClock.day
			_spawn_follower()
		return
	if not night or not in_park or _follow_time > FOLLOW_MAX_TIME:
		_vanish_follower(true)


func _spawn_follower() -> void:
	_follower = Node3D.new()
	_follower.name = "Follower"
	add_child(_follower)
	var model := MODEL.instantiate() as Node3D
	model.position.y = -0.45
	_follower.add_child(model)
	var materials := PS1Model.apply(model)
	var lamps := materials.get("LampHead") as ShaderMaterial
	if lamps:
		lamps.set_shader_parameter("emission_color", Color(1.0, 0.93, 0.75))
		lamps.set_shader_parameter("emission_energy", 3.0)
	var paint := materials.get("Paint") as ShaderMaterial
	if paint:
		paint.set_shader_parameter("albedo_color", Color(0.06, 0.06, 0.07))
		paint.set_shader_parameter("albedo_texture", null)
	for x in [-0.6, 0.6]:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(x, 0.25, -1.75)
		lamp.light_color = Color(1.0, 0.93, 0.75)
		lamp.light_energy = 6.0
		lamp.spot_range = 40.0
		lamp.spot_angle = 30.0
		_follower.add_child(lamp)
	# Appear well back down the road you just drove.
	_follower.global_position = _trail[0]
	for i in range(_trail.size() - 1, -1, -1):
		if _trail[i].distance_to(_car.global_position) >= FOLLOW_GAP + 25.0:
			_follower.global_position = _trail[i]
			break
	_follow_time = 0.0
	# Heard from well behind you (it stays 60-120 m back in the mix).
	_follower.add_child(_loop_player("oddity/odd_follower_engine_loop", 20.0, -2.0))


func _move_follower(delta: float) -> void:
	_follow_time += delta
	# Walk along your path, keeping FOLLOW_GAP behind.
	var target := _follower.global_position
	for i in range(_trail.size() - 1, -1, -1):
		if _trail[i].distance_to(_car.global_position) >= FOLLOW_GAP:
			target = _trail[i]
			break
	var to := target - _follower.global_position
	var step := minf(to.length(), maxf(_car.linear_velocity.length() * 1.15, 4.0) * delta)
	if to.length() > 0.05:
		var dir := to.normalized()
		_follower.global_position += dir * step
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length() > 0.1:
			_follower.global_basis = _follower.global_basis.slerp(Basis.looking_at(flat, Vector3.UP), minf(1.0, delta * 4.0))
	var gap := _follower.global_position.distance_to(_car.global_position)
	var facing_it := (-_car.global_basis.z).dot((_follower.global_position - _car.global_position).normalized()) > 0.5
	# Turn round and drive at it, and it's gone.
	if gap < 18.0 or (facing_it and gap < 30.0):
		_vanish_follower(true)


func _vanish_follower(noticed: bool) -> void:
	if _follower:
		_follower.queue_free()
		_follower = null
	if noticed and _follow_time > 8.0:
		_notice("kings_park_car", "The headlights behind you are gone. There's no side road there.")


# --- The lane -------------------------------------------------------------------

func _check_lane(night: bool) -> void:
	if _lane_end == Vector3.INF:
		return
	var d := _car.global_position.distance_to(_lane_end)
	if _idle == null:
		if night and d < 120.0 and d > 35.0 and _idle_tonight != GameClock.day:
			_idle_tonight = GameClock.day
			_idle = _loop_player("oddity/odd_lane_idle_loop")
			add_child(_idle)
			_idle.global_position = _lane_end
		return
	if d < 25.0 or not night:
		var heard := _idle.playing
		_idle.queue_free()
		_idle = null
		if heard and d < 25.0:
			# It cuts out as you get close.
			_play_at("oddity/odd_lane_idle_cutout", _lane_end, -4.0)
			_notice("lane_idle", "The idling stops. Nobody's at the end of the lane.")


# --- River lights ------------------------------------------------------------

func _check_river(night: bool) -> void:
	if _river == Vector3.INF:
		return
	var d := _car.global_position.distance_to(_river)
	if night and d < 600.0 and _lights == null:
		_lights = _make_lights()
		add_child(_lights)
		_lights.global_position = _river
		_play_at("oddity/odd_river_lights_shimmer", _river + Vector3.UP * 6.0)
		_lights.create_tween().set_loops().tween_property(_lights, "rotation:y", TAU, 90.0).from(0.0)
	elif _lights and (not night or d > 700.0):
		_lights.queue_free()
		_lights = null
	if _lights and d < 160.0:
		_notice("river_lights", "Lights over the river, hanging still. Then they drift off.")


func _make_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "RiverLights"
	var rng := RandomNumberGenerator.new()
	rng.seed = 500
	for i in 5:
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.6
		sphere.height = 1.2
		sphere.radial_segments = 8
		sphere.rings = 4
		orb.mesh = sphere
		orb.material_override = PS1Material.glowing(Color(0.95, 0.8, 0.5), 0.9)
		orb.position = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(3.0, 6.0), rng.randf_range(-30.0, 30.0))
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.85, 0.6)
		glow.light_energy = 2.0
		glow.omni_range = 12.0
		orb.add_child(glow)
		root.add_child(orb)
	var hum := _loop_player("oddity/odd_river_lights_loop", 30.0, 0.0)
	hum.position.y = 6.0
	root.add_child(hum)
	return root
