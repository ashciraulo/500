class_name Traffic1979
extends Node
## The traffic as it was in 1979 (STORY.md, act 4 and the Night Drive 13
## ending): while this is on, every car round you, moving or parked, is a
## Valiant or a little 500 L in a seventies colour, and the street lights
## burn a deeper sodium orange. Buses, bikes, the night shift and the
## emergency services stay as they are.
##
## It dresses the traffic's own bodies: their own model and mesh are hidden
## and a period car is put on in their place, so they drive, stop and park
## exactly as before. undress_all() puts everything back.
##
##   var old := Traffic1979.new()
##   add_child(old)
##   old.dress_all()
##   ...
##   old.undress_all()

const VALIANT := "res://art/models/vehicles/period/valiant.glb"
const FIAT := "res://art/models/cars/classic_l/classic_l.glb"
## The kinds of traffic that turn into a period car.
const CARS := [&"hatch", &"sedan", &"suv", &"taxi", &"ute", &"van", &"police"]
## Out of every ten cars that aren't hatches, this many are 500s.
const FIATS_IN_TEN := 3
## Seventies paint: mustard, burnt orange, olive, chocolate, cream, sky blue,
## white, maroon, lime and the Valiant's own olive.
const PAINTS := [Color(0.66, 0.5, 0.16), Color(0.72, 0.3, 0.08), Color(0.4, 0.42, 0.22), Color(0.3, 0.18, 0.1),
	Color(0.86, 0.8, 0.62), Color(0.45, 0.62, 0.75), Color(0.9, 0.9, 0.86), Color(0.42, 0.08, 0.1),
	Color(0.55, 0.65, 0.2), Color(0.396, 0.498, 0.341)]
## The street lights' 1979 sodium, deeper than today's warm white.
const SODIUM := Color(1.0, 0.56, 0.2)
## The lamps' materials on the two cars.
const HEAD_LAMPS := ["VC_HeadLamp", "VC_Parker", "LampHead"]
const TAIL_LAMPS := ["VC_TailLamp", "LampTail"]
const HEAD := Color(1.0, 0.9, 0.68)
const TAIL := Color(0.8, 0.05, 0.03)
const BRAKE := Color(1.0, 0.1, 0.05)
## How often (s) new and braking traffic is looked at.
const TICK := 0.2
const SHIMMER := 0.3

var dressed := false

## body -> [period model, [hidden nodes], TrafficVehicle or null]
var _bodies := {}
var _traffic: TrafficManager
var _lamps: Array = []     # [OmniLight3D, its colour]
var _pool_colour: Variant = null
var _tick := 0.0


func _process(delta: float) -> void:
	if not dressed:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_follow()


## Dress everything now, and anything that turns up until undress_all().
func dress_all() -> void:
	if dressed:
		return
	dressed = true
	_traffic = get_tree().get_first_node_in_group(&"traffic") as TrafficManager
	if _traffic:
		_traffic.vehicle_spawned.connect(_on_spawned)
		_traffic.vehicle_despawned.connect(_on_despawned)
	_follow()
	_sodium(true)


func undress_all() -> void:
	if not dressed:
		return
	dressed = false
	if _traffic and is_instance_valid(_traffic):
		_traffic.vehicle_spawned.disconnect(_on_spawned)
		_traffic.vehicle_despawned.disconnect(_on_despawned)
	for body: Node3D in _bodies.keys():
		undress(body)
	_bodies.clear()
	_sodium(false)


func count() -> int:
	return _bodies.size()


## Every period car on now: [body, model].
func models() -> Array:
	var out := []
	for body: Node3D in _bodies:
		out.append([body, _bodies[body][0]])
	return out


## Look for traffic that's new, gone, parked or braking.
func _follow() -> void:
	if _traffic == null or not is_instance_valid(_traffic):
		return
	var night := GameClock.daylight() < 0.45
	for v: TrafficVehicle in _traffic.vehicles:
		if not v.active or not v.type in CARS:
			continue
		if not _bodies.has(v.body):
			dress(v.body, v.type, v.id, v)
		_brake(v, night)
	if _traffic.parking:
		for body: StaticBody3D in _traffic.parking.shown.values():
			if not _bodies.has(body):
				dress(body, body.get_meta(&"type", &"sedan"), int(body.get_meta(&"pick", body.get_instance_id())), null)
	# Parked cars that have been put away again.
	for body: Node3D in _bodies.keys():
		if not is_instance_valid(body):
			_bodies.erase(body)
		elif _bodies[body][2] == null and not body.visible:
			undress(body)


func _on_spawned(body: Node3D, type: StringName) -> void:
	if not type in CARS:
		return
	for v: TrafficVehicle in _traffic.vehicles:
		if v.body == body:
			dress(body, type, v.id, v)
			return


func _on_despawned(body: Node3D) -> void:
	if _bodies.has(body):
		undress(body)


## Hide a traffic body's own car and put a period one on. `pick` chooses
## which and its colour, so the same car is always the same old car.
func dress(body: Node3D, type: StringName, pick: int, vehicle: TrafficVehicle) -> void:
	if _bodies.has(body):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = pick * 7919 + 1979
	var fiat := type == &"hatch" or rng.randi() % 10 < FIATS_IN_TEN
	var model := _period(fiat, PAINTS[rng.randi() % PAINTS.size()])
	if model == null:
		return
	var hidden: Array[Node3D] = []
	for n: StringName in [&"Model", &"Mesh"]:
		var own := body.get_node_or_null(NodePath(n)) as Node3D
		if own and own.visible:
			own.visible = false
			hidden.append(own)
	model.name = "Late1979"
	body.add_child(model)
	LateCity.add_shimmer(model, SHIMMER)
	_bodies[body] = [model, hidden, vehicle]
	# Moving traffic has its lamps on after dark; parked cars don't.
	_lamps_on(model, vehicle != null and GameClock.daylight() < 0.45, false)


func undress(body: Node3D) -> void:
	var entry: Array = _bodies.get(body, [])
	_bodies.erase(body)
	if entry.is_empty():
		return
	var model := entry[0] as Node3D
	if is_instance_valid(model):
		model.queue_free()
		if model.get_parent():
			model.get_parent().remove_child(model)
	for own: Node3D in entry[1]:
		if is_instance_valid(own):
			own.visible = true


## A VC Valiant or a 500 L in `paint`, origin on the ground, nose to -z.
func _period(fiat: bool, paint: Color) -> Node3D:
	var path := FIAT if fiat else VALIANT
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	if fiat:
		LateHouse.add_wheels(model)
		# Roof shut, no one's things on the shelf: a car going by at night.
		var open := model.get_node_or_null(^"Roof_Open") as Node3D
		if open:
			open.visible = false
	var mats := PS1Model.apply(model)
	var body_paint := mats.get("Paint") as ShaderMaterial
	if body_paint:
		body_paint.set_shader_parameter("albedo_color", paint)
		body_paint.set_shader_parameter("albedo_texture", null)  # the 500's own red, worn
		body_paint.set_shader_parameter("top_shade", 0.45)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 420.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its own lamp materials (each car has its own), to light.
	var heads: Array[ShaderMaterial] = []
	var tails: Array[ShaderMaterial] = []
	for n: String in HEAD_LAMPS:
		if mats.get(n) is ShaderMaterial:
			heads.append(mats[n])
	for n: String in TAIL_LAMPS:
		if mats.get(n) is ShaderMaterial:
			tails.append(mats[n])
	model.set_meta(&"heads", heads)
	model.set_meta(&"tails", tails)
	return model


## Brake lights on the period car when the traffic under it brakes.
func _brake(v: TrafficVehicle, night: bool) -> void:
	var entry: Array = _bodies.get(v.body, [])
	if entry.is_empty():
		return
	var model := entry[0] as Node3D
	var key := (1 if night else 0) | (2 if v.is_braking() else 0)
	if model.get_meta(&"lamps", -1) == key:
		return
	model.set_meta(&"lamps", key)
	_lamps_on(model, night, v.is_braking())


func _lamps_on(model: Node3D, on: bool, braking: bool) -> void:
	for m: ShaderMaterial in model.get_meta(&"heads", []):
		m.set_shader_parameter("emission_color", HEAD)
		m.set_shader_parameter("emission_energy", 2.5 if on else 0.0)
	for m: ShaderMaterial in model.get_meta(&"tails", []):
		m.set_shader_parameter("emission_color", BRAKE if braking else TAIL)
		m.set_shader_parameter("emission_energy", 3.0 if braking else (1.2 if on else 0.0))


## The map's street lights to 1979 sodium (on), or back (off).
func _sodium(on: bool) -> void:
	var map := get_tree().get_first_node_in_group(&"perth_map") as MapStreamer
	if map == null:
		return
	if on:
		_lamps.clear()
		for c: Node in map.get_children():
			if c is OmniLight3D and String(c.name).begins_with("StreetLight"):
				_lamps.append([c, (c as OmniLight3D).light_color])
				(c as OmniLight3D).light_color = SODIUM
	else:
		for l: Array in _lamps:
			if is_instance_valid(l[0]):
				(l[0] as OmniLight3D).light_color = l[1]
		_lamps.clear()
	# The glow under each lamp: one mesh shared by every tile's pools.
	var pools := get_tree().get_first_node_in_group(&"map_light_pools") as MultiMeshInstance3D
	var pool: Mesh = pools.multimesh.mesh if pools and pools.multimesh else null
	var m := pool.surface_get_material(0) as ShaderMaterial if pool else null
	if m == null:
		return
	if on:
		_pool_colour = m.get_shader_parameter("color")
		m.set_shader_parameter("color", SODIUM)
	elif _pool_colour != null:
		m.set_shader_parameter("color", _pool_colour)
		_pool_colour = null


func _exit_tree() -> void:
	undress_all()
