class_name TrafficNight
extends Node3D

## The city's night shift, all run by TrafficManager:
## - Street sweepers creep along the city kerbs in the small hours (11pm to
##   5am), brooms spinning and beacons flashing.
## - Bin day (Tuesday): wheelie bins line the residential kerbs from Monday
##   evening, and the bin truck works along them from 5:30 till 10, lifting
##   each one over with its side arm.
## - Food vans park up in Northbridge on Thursday, Friday and Saturday nights
##   (7pm till 2am) in street parking bays, hatches open to the footpath, a
##   few people queuing at each.

signal bin_emptied(position: Vector3)
signal food_van_opened(position: Vector3, food: String)

## Northbridge, north of the railway (x, z), where the food vans go.
const NORTHBRIDGE := Rect2(-120.0, -260.0, 900.0, 720.0)
## [sign, body, trim]
const FOOD := [
	["TACOS", Color(0.95, 0.4, 0.55), Color(0.15, 0.6, 0.55)],
	["WOOD-FIRED PIZZA", Color(0.15, 0.17, 0.2), Color(0.85, 0.25, 0.1)],
	["DUMPLINGS", Color(0.92, 0.85, 0.7), Color(0.75, 0.1, 0.1)],
	["KEBABS", Color(0.95, 0.75, 0.15), Color(0.2, 0.2, 0.22)],
	["GELATO", Color(0.7, 0.88, 0.85), Color(0.95, 0.55, 0.65)],
	["COFFEE", Color(0.35, 0.22, 0.15), Color(0.92, 0.88, 0.8)],
	["BURGERS", Color(0.8, 0.12, 0.1), Color(0.95, 0.95, 0.9)],
]
const SWEEPER_SPEED := 3.5  # About 12 km/h.
const TRUCK_SPEED := 8.5
const BIN_DWELL := 7.0
## Where the bin truck's arm is, back from its front bumper.
const ARM_BACK := 3.0
const BIN_SPACING := 14.0

@export var enabled := true
## Tests: ignore the clock and the calendar.
@export var always_on := false
## Where sweepers work (x, z); defaults to the kerbside module's city.
@export var city := TrafficKerbside.CITY
@export var food_area := NORTHBRIDGE
@export var max_sweepers := 1
@export var sweeper_radius := 600.0
@export var max_bin_trucks := 1
@export var bin_radius := 240.0
@export var max_bins := 70
@export var max_food_vans := 3
@export var food_radius := 450.0
## 0 is Monday.
@export var bin_weekday := 1

var sweepers: Array = []
## { v, stops: [[bin, stop], ...] }
var trucks: Array = []
## { lane, s, node, pos, kerb, emptied, recycling, home (Transform3D) }
var bins: Array = []
## { spot, node, food, queue: [Node3D] }
var food_vans: Array = []
var stats := { "sweepers": 0, "bin_trucks": 0, "bins_out": 0, "bins_emptied": 0, "food_vans": 0 }

var graph: TrafficGraph
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _blink := 0.0
var _version := -1
var _bin_pool: Array = []
var _lit: Material
var _unlit: Material


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph
	if manager.get("random_seed"):
		_rng.seed = hash([manager.random_seed, "night"])
	else:
		_rng.randomize()
	_lit = TrafficModels.beacon_material(true)
	_unlit = TrafficModels.beacon_material(false)


func _sound(sound_name: String, p: Vector3, db: float) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has(sound_name):
		audio.play_at(sound_name, p, db, "SFX")


func _clock() -> Node:
	return get_node("/root/GameClock")


## 0 is Monday (day 1 is a Monday).
func weekday(day: int) -> int:
	return posmod(day - 1, 7)


func sweeper_hours() -> bool:
	if always_on:
		return true
	var h: float = _clock().time_of_day
	return h >= 23.0 or h < 5.0


## Bins go out the evening before bin day and come in the evening after.
func bins_out() -> bool:
	if always_on:
		return true
	var c := _clock()
	var wd := weekday(c.day)
	return (wd == bin_weekday and c.time_of_day < 18.0) or (wd == posmod(bin_weekday - 1, 7) and c.time_of_day >= 18.0)


func truck_hours() -> bool:
	if always_on:
		return true
	var c := _clock()
	return weekday(c.day) == bin_weekday and c.time_of_day >= 5.5 and c.time_of_day < 10.0


## Thursday to Saturday nights, 7pm till 2am.
func food_hours() -> bool:
	if always_on:
		return true
	var c := _clock()
	var wd := weekday(c.day)
	var h: float = c.time_of_day
	return (h >= 19.0 and wd >= 3 and wd <= 5) or (h < 2.0 and wd >= 4 and wd <= 6)


func update(delta: float, focus: Vector3) -> void:
	if graph == null:
		return
	_blink += delta
	var phase := fmod(_blink, 0.7) < 0.35
	for v in sweepers:
		_animate_sweeper(v, delta, phase)
	for t in trucks:
		_animate_truck(t, phase)
	for van in food_vans:
		_animate_queue(van)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	if graph.version != _version:
		_version = graph.version
		# Lanes may have been rebuilt: put the bins out again where they belong.
		for bin in bins.duplicate():
			if not bin.lane.road.lanes.has(bin.lane):
				_remove_bin(bin)
	for v in sweepers:
		if not v.active or v.type != &"sweeper":
			_hum(v, false)
	sweepers = sweepers.filter(func(v): return v.active and v.type == &"sweeper")
	trucks = trucks.filter(func(t): return t.v.active and t.v.type == &"bin_truck")
	if not enabled:
		return
	_manage_sweepers(focus)
	_manage_bins(focus)
	_manage_trucks(focus)
	_manage_food(focus)


func clear() -> void:
	for v in sweepers:
		_hum(v, false)
	sweepers.clear()
	trucks.clear()
	for bin in bins.duplicate():
		_remove_bin(bin)
	for van in food_vans.duplicate():
		_remove_food_van(van)


# --- Sweepers -----------------------------------------------------------------

func in_city(p: Vector3) -> bool:
	return always_on or city.has_point(Vector2(p.x, p.z))


## A kerb lane out of sight near `focus` for a working vehicle: [lane, s] or [].
func _kerb_spot(focus: Vector3, radius: float, test: Callable) -> Array:
	# Inside the traffic's own range, or it'd be despawned at once.
	radius = minf(radius, _manager.spawn_radius)
	var samples: Array = graph.samples_near(focus, radius)
	for attempt in 12:
		if samples.is_empty():
			return []
		var entry: Array = samples[_rng.randi() % samples.size()]
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null or lane.k != lane.count - 1 or lane.length < 50.0:
			continue
		if not test.call(lane):
			continue
		var s := _rng.randf_range(15.0, lane.length - 25.0)
		var p := lane.point(s)
		var d := p.distance_to(focus)
		if d < _manager.min_spawn_radius * 0.7 or d > radius or _manager._visible(p, 20.0):
			continue
		if graph.reach(lane) < TrafficGraph.REACH:
			continue
		var clear := true
		for o in lane.vehicles:
			if absf(o.s - s) < 25.0:
				clear = false
		if clear:
			return [lane, s]
	return []


func _manage_sweepers(focus: Vector3) -> void:
	if not sweeper_hours() or sweepers.size() >= max_sweepers:
		return
	var spot := _kerb_spot(focus, sweeper_radius, func(l): return l.road.kind != &"motorway" and l.road.kind != &"trunk" and in_city(l.point(l.length * 0.5)))
	if spot.is_empty():
		return
	add_sweeper(spot[0], spot[1])


## Put a sweeper to work on `lane` at `s`. Returns it.
func add_sweeper(lane: TrafficGraph.Lane, s: float) -> TrafficVehicle:
	var v: TrafficVehicle = _manager.spawn_vehicle_at(&"sweeper", lane, s, SWEEPER_SPEED * 0.5)
	if v == null:
		return null
	v.max_speed = SWEEPER_SPEED
	v.keep_lane = true
	_dress(v, TrafficModels.SWEEPER_PAINT)
	if v.model == null and not v.body.has_node("Brooms"):
		v.body.add_child(TrafficModels.sweeper_brushes())
	_hum(v, true)
	sweepers.append(v)
	stats.sweepers += 1
	return v


## The sweeper's engine and brushes, if the audio side has the loop.
func _hum(v: TrafficVehicle, on: bool) -> void:
	var hum: AudioStreamPlayer3D = v.body.get_node_or_null("Hum")
	if not on:
		if hum:
			hum.stop()
		return
	if hum == null:
		hum = TrafficNight.loop_player(self, "traffic/traffic_sweeper_loop", &"Vehicles", 10.0, 120.0)
		if hum == null:
			return
		hum.name = "Hum"
		hum.position = Vector3(0, 0.8, 0)
		v.body.add_child(hum)
	hum.play()


## A looping 3D sound player for `sound_name`, or null if the audio side
## hasn't got it (yet). Not added to the tree.
static func loop_player(from: Node, sound_name: String, bus: StringName, unit: float, reach: float, db := 0.0) -> AudioStreamPlayer3D:
	var audio := from.get_node_or_null("/root/Audio")
	if audio == null or not audio.has_method("has") or not audio.has(sound_name):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = audio.stream(sound_name, true)
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	p.unit_size = unit
	p.max_distance = reach
	p.volume_db = db
	p.autoplay = true
	return p


func _dress(v: TrafficVehicle, paint: Array) -> void:
	v.paint = paint[0]
	v.mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(paint[0]))
	v.mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(paint[1]))
	# (A modelled one comes in its council colours, beacons and all.)
	if v.model == null and not v.body.has_node("Beacon"):
		v.body.add_child(TrafficModels.beacon(v.type))


func _flash(v: TrafficVehicle, phase: bool) -> void:
	var beacon: Node3D = _part(v, "Beacon")
	if beacon:
		TrafficModels.set_lamp(beacon.get_node("A"), _lit if phase else _unlit)
		TrafficModels.set_lamp(beacon.get_node("B"), _unlit if phase else _lit)


## A named part of a working vehicle, on its model or its code-built body.
func _part(v: TrafficVehicle, part: String) -> Node:
	if v.model:
		return v.model.get_node_or_null(part)
	return v.body.get_node_or_null(part)


func _animate_sweeper(v: TrafficVehicle, delta: float, phase: bool) -> void:
	if not v.active:
		return
	_flash(v, phase)
	var brooms: Node3D = v.model if v.model else v.body.get_node_or_null("Brooms")
	if brooms:
		# The brooms turn into the gutter, whether moving or not.
		brooms.get_node("BroomL").rotate_y(-9.0 * delta)
		brooms.get_node("BroomR").rotate_y(9.0 * delta)


# --- Bin day ------------------------------------------------------------------

func _manage_bins(focus: Vector3) -> void:
	var out := bins_out()
	for bin in bins.duplicate():
		var far: bool = bin.pos.distance_to(focus) > bin_radius + 80.0
		if (far or not out) and not _manager._visible(bin.pos, 25.0) and not bin.get("lifting", false):
			_remove_bin(bin)
	if not out:
		return
	# One bin per house: along residential kerbs, out of sight.
	var samples: Array = graph.samples_near(focus, bin_radius)
	var tries := 0
	while bins.size() < max_bins and tries < 30 and not samples.is_empty():
		tries += 1
		var entry: Array = samples[_rng.randi() % samples.size()]
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null or lane.road.kind != &"residential" or lane.k != lane.count - 1:
			continue
		# Houses along the street: every BIN_SPACING metres (a few skip a week).
		var slot := floori(float(entry[1]) / BIN_SPACING)
		var s := (slot + 0.5) * BIN_SPACING
		if s < 10.0 or s > lane.length - 10.0 or hash([lane.road.key, lane.k, slot]) % 5 == 0:
			continue
		if bins.any(func(b): return b.lane == lane and absf(b.s - s) < 1.0):
			continue
		var p := _kerb_point(lane, s)
		if p.distance_to(focus) > bin_radius or _manager._visible(p, 25.0):
			continue
		add_bin(lane, s, hash([lane.road.key, slot, 3]) % 2 == 0)


## Where the kerb is beside `lane` at `s` (just onto the verge).
func _kerb_point(lane: TrafficGraph.Lane, s: float) -> Vector3:
	var p := lane.point(s)
	var road: TrafficGraph.Road = lane.road
	var c := TrafficGraph.point_at(road.pts, road.cum, TrafficGraph.closest_s(road.pts, road.cum, p))
	var off := road.half_width - Vector2(p.x - c.x, p.z - c.z).length()
	if off < 0.4 or off > 4.0:
		off = 1.8
	return p + TrafficGraph.left_of(lane.tangent(s)) * (off + 0.45)


## Put a wheelie bin out beside `lane` at `s`. Returns it.
func add_bin(lane: TrafficGraph.Lane, s: float, recycling := false) -> Dictionary:
	var node: Node3D
	for i in _bin_pool.size():
		if _bin_pool[i].get_meta("recycling") == recycling:
			node = _bin_pool.pop_at(i)
			break
	if node == null:
		node = TrafficModels.wheelie_bin(recycling)
		node.set_meta("recycling", recycling)
		add_child(node)
	var dir := lane.tangent(s)
	var kerb := TrafficGraph.left_of(dir)
	var pos := _kerb_point(lane, s)
	# Handle towards the house, lid hinge at the back, a little askew.
	var basis := Basis.looking_at(-kerb, Vector3.UP).rotated(Vector3.UP, _rng.randf_range(-0.25, 0.25))
	var home := Transform3D(basis, pos)
	node.global_transform = home
	node.visible = true
	(node.get_node("Lid") as Node3D).rotation = Vector3.ZERO
	var bin := { "lane": lane, "s": s, "node": node, "pos": pos, "kerb": kerb, "emptied": false,
		"recycling": recycling, "home": home }
	bins.append(bin)
	stats.bins_out += 1
	return bin


func _remove_bin(bin: Dictionary) -> void:
	bins.erase(bin)
	var node: Node3D = bin.node
	node.visible = false
	_bin_pool.append(node)
	for t in trucks:
		for pair in t.stops.duplicate():
			if pair[0] == bin:
				t.v.service_stops.erase(pair[1])
				t.stops.erase(pair)


func _manage_trucks(focus: Vector3) -> void:
	for t in trucks:
		_plan_stops(t)
	if not truck_hours() or trucks.size() >= max_bin_trucks or bins.is_empty():
		return
	var spot := _kerb_spot(focus, bin_radius + 120.0, func(l): return l.road.kind == &"residential" and bins.any(func(b): return b.lane == l and not b.emptied))
	if spot.is_empty():
		return
	add_bin_truck(spot[0], spot[1])


## Send a bin truck along `lane` from `s`. Returns { v, stops }.
func add_bin_truck(lane: TrafficGraph.Lane, s: float) -> Dictionary:
	var v: TrafficVehicle = _manager.spawn_vehicle_at(&"bin_truck", lane, s, 3.0)
	if v == null:
		return {}
	v.max_speed = TRUCK_SPEED
	v.keep_lane = true
	_dress(v, TrafficModels.BIN_TRUCK_PAINT)
	if v.model == null and not v.body.has_node("BinArm"):
		v.body.add_child(TrafficModels.bin_arm())
	var t := { "v": v, "stops": [] }
	trucks.append(t)
	stats.bin_trucks += 1
	_plan_stops(t)
	return t


## A stop at each full bin on the lanes the truck is about to drive.
func _plan_stops(t: Dictionary) -> void:
	var v: TrafficVehicle = t.v
	if not v.active:
		return
	var front: float = v.s + v.length * 0.5
	for i in v.route.size():
		var l: TrafficGraph.Lane = v.route[i]
		if l.connector:
			continue
		for bin in bins:
			if bin.lane != l or bin.emptied or t.stops.any(func(pair): return pair[0] == bin):
				continue
			var at: float = bin.s + ARM_BACK + 0.8
			if i == 0 and at < front + 4.0:
				continue  # Already past it.
			var st := { "lane": l, "s": at, "dwell": BIN_DWELL }
			v.service_stops.append(st)
			t.stops.append([bin, st])


func _animate_truck(t: Dictionary, phase: bool) -> void:
	var v: TrafficVehicle = t.v
	if not v.active:
		return
	_flash(v, phase)
	var rig: Node3D = _part(v, "BinArm")
	if rig == null:
		return
	var grip: Node3D = rig.get_node("Grip")
	if not grip.has_meta("rest"):
		grip.set_meta("rest", grip.position.y)
	var rest: float = grip.get_meta("rest")
	# The bin being lifted: at the truck's side, stopped there.
	var lifting = null
	var front: float = v.s + v.length * 0.5
	for pair in t.stops:
		var bin: Dictionary = pair[0]
		var st: Dictionary = pair[1]
		if st.get("done", false):
			if bin.get("lifting", false):
				_put_back(bin)
			continue
		if st.lane == v.route[0] and absf(st.s - front) < 2.5 and v.speed < 0.5:
			lifting = bin
	if lifting == null:
		grip.position.y = move_toward(grip.position.y, rest, 0.05)
		return
	var bin: Dictionary = lifting
	bin.lifting = true
	var k: float = clampf(v.dwell / BIN_DWELL, 0.0, 1.0)
	var node: Node3D = bin.node
	var lid: Node3D = node.get_node("Lid")
	# Up the side of the truck, tipped over into the hopper, and back down.
	var y := 0.0
	var tip := 0.0
	if k < 0.15:
		y = 0.0
	elif k < 0.4:
		y = smoothstep(0.15, 0.4, k) * 2.55
	elif k < 0.7:
		y = 2.55
		tip = sin((k - 0.4) / 0.3 * PI)
	elif k < 0.85:
		y = (1.0 - smoothstep(0.7, 0.85, k)) * 2.55
	grip.position.y = rest + y
	lid.rotation.x = -1.9 * clampf(tip * 1.5, 0.0, 1.0)
	var held := _held(rig, y, tip)
	if k < 0.15:
		node.global_transform = bin.home.interpolate_with(held, k / 0.15)
	elif k < 0.85:
		node.global_transform = held
	else:
		node.global_transform = held.interpolate_with(bin.home, (k - 0.85) / 0.15)
	if tip > 0.9 and not bin.emptied:
		bin.emptied = true
		stats.bins_emptied += 1
		bin_emptied.emit(bin.pos)
		_sound("traffic/traffic_bin_tip", bin.pos + Vector3(0, 3, 0), -2.0)


## Where the bin is in the gripper: `y` up the rail, `tip` (0..1) of the way
## over into the hopper (about the top of the truck's side).
func _held(rig: Node3D, y: float, tip: float) -> Transform3D:
	# Handle to the truck, lid hinge on that side too.
	var local := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.42, y, 0))
	if tip > 0.0:
		var pivot := Vector3(0.05, y + 1.1, 0)
		var turn := Transform3D(Basis(Vector3(0, 0, 1), -2.3 * tip), Vector3.ZERO)
		local = Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot) * local
	return rig.global_transform * local


func _put_back(bin: Dictionary) -> void:
	bin.lifting = false
	bin.emptied = true
	var node: Node3D = bin.node
	node.global_transform = bin.home
	(node.get_node("Lid") as Node3D).rotation = Vector3.ZERO


# --- Food vans ----------------------------------------------------------------

func in_food_area(p: Vector3) -> bool:
	return always_on or food_area.has_point(Vector2(p.x, p.z))


func _manage_food(focus: Vector3) -> void:
	var open := food_hours()
	for van in food_vans.duplicate():
		var far: bool = van.spot.pos.distance_to(focus) > food_radius + 100.0
		if (far or not open) and not _manager._visible(van.spot.pos, 30.0):
			_remove_food_van(van)
	if not open or food_vans.size() >= max_food_vans:
		return
	# The same few bays each night, picked by the date: street bays first.
	var spots: Array = graph.parking_near(focus, food_radius).filter(func(sp): return in_food_area(sp.pos) and sp.pos.distance_to(focus) < food_radius)
	if spots.is_empty():
		return
	var day: int = _clock().day
	spots.sort_custom(func(a, b): return _bay_rank(a, day) < _bay_rank(b, day))
	for spot in spots.slice(0, 8):
		if food_vans.size() >= max_food_vans:
			return
		if spot.get("reserved", false) or food_vans.any(func(fv): return fv.spot.pos.distance_to(spot.pos) < 25.0):
			continue
		if _manager._visible(spot.pos, 40.0):
			continue
		add_food_van(spot)


func _bay_rank(spot: Dictionary, day: int) -> int:
	return (0 if spot.kind == &"street" else 1 << 30) + (hash([spot.seed, day]) & 0xfffffff)


## Park a food van in parking `spot`, hatch to the footpath. Returns it.
func add_food_van(spot: Dictionary) -> Dictionary:
	var pick: Array = FOOD[hash([spot.seed, 11]) % FOOD.size()]
	var node := TrafficModels.food_van(pick[0], pick[1], pick[2])
	add_child(node)
	# Parked along the bay; the hatch side (left) faces away from the road.
	var fwd := Vector3(sin(spot.yaw), 0, cos(spot.yaw))
	var lane_p := _nearest_lane_point(spot.pos)
	var away: Vector3 = spot.pos - lane_p
	away.y = 0.0
	if TrafficGraph.left_of(-fwd).dot(away) < 0.0:
		fwd = -fwd
	node.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), spot.pos)
	# (Spots are dictionary keys over in TrafficParking: hide its car first.)
	var parking = _manager.get("parking")
	if parking and parking.shown.has(spot):
		parking._hide(spot)
	spot.reserved = true
	var van := { "spot": spot, "node": node, "food": pick[0], "queue": [] }
	# The generator and fridges, and the customers.
	for sound in [["traffic/traffic_food_van_hum_loop", Vector3(0, 1.0, 1.5), 0.0], ["traffic/traffic_food_van_chatter_loop", Vector3(-2.0, 1.5, 0.0), -3.0]]:
		var player := TrafficNight.loop_player(self, sound[0], &"SFX", 6.0, 60.0, sound[2])
		if player:
			player.position = sound[1]
			node.add_child(player)
	var hatch_dir := TrafficGraph.left_of(-fwd)
	for i in _rng.randi_range(2, 4):
		var person := TrafficModels.person(_rng)
		add_child(person)
		var along := -fwd * (0.6 - i * 0.9) + hatch_dir * (2.2 + i * 0.15 + _rng.randf_range(-0.2, 0.2))
		var p: Vector3 = spot.pos + along
		person.global_position = Vector3(p.x, spot.pos.y, p.z)
		person.look_at(person.global_position - hatch_dir + fwd * 0.2 * i, Vector3.UP)
		person.set_meta("phase", _rng.randf() * TAU)
		van.queue.append(person)
	food_vans.append(van)
	stats.food_vans += 1
	food_van_opened.emit(spot.pos, pick[0])
	return van


func _nearest_lane_point(p: Vector3) -> Vector3:
	var best := p + Vector3(0, 0, 10)
	var best_d := INF
	for entry in graph.samples_near(p, 30.0):
		var lane: TrafficGraph.Lane = entry[0]
		var q := lane.point(TrafficGraph.closest_s(lane.pts, lane.cum, p))
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


func _remove_food_van(van: Dictionary) -> void:
	food_vans.erase(van)
	van.spot.erase("reserved")
	van.node.queue_free()
	for person in van.queue:
		person.queue_free()


func _animate_queue(van: Dictionary) -> void:
	var t := _blink
	for person in van.queue:
		var body: Node3D = person.get_node("Body")
		var ph: float = person.get_meta("phase")
		# Shifting from foot to foot, glancing at a phone.
		body.rotation.z = sin(t * 0.7 + ph) * 0.03
		(body.get_node("ArmR") as Node3D).rotation.x = -0.9 + sin(t * 0.3 + ph) * 0.15
