class_name TrafficKerbside
extends Node3D
## The street life that's at work: couriers double-parked in the kerb lane
## with their hazards on while they run a parcel in, taxis queued at the
## train stations (the front one pulls away when a train comes in), and
## parking inspectors walking the city's kerbs, who will ticket the player's
## car too if it's left in a traffic lane or overstays a street bay.
##
## Vans close their bit of lane the same way roadworks do (Lane.closed), so
## traffic merges round them. Everything here only appears or goes away out
## of the player's view.

## A parking fine has been put on the player's car (and taken from the
## Wallet). reason is short and readable: "parked in a traffic lane".
signal parking_ticket(fine: int, reason: String, position: Vector3)
## A taxi has pulled off the rank at a station with a fare.
signal taxi_departed(station: String, position: Vector3)

## Where inspectors work and vans deliver: the CBD, Northbridge, East Perth
## and West Perth (world x, z).
const CITY := Rect2(-450.0, -350.0, 1950.0, 1700.0)
const VAN_LENGTH := 4.9
const RANK_SLOTS := 3
const RANK_GAP := 5.8
const LANE_FINE := 120
const BAY_FINE := 70
## Real seconds the player's car has to be left before it's an offence.
const LANE_GRACE := 60.0
const BAY_GRACE := 300.0
## Real seconds an inspector takes over the ticket.
const WRITE_TIME := 6.0
const SATURDAY := 2
const SUNDAY := 3

@export var enabled := true
@export var max_vans := 2
@export var van_radius := 420.0
@export var max_inspectors := 2
@export var inspector_radius := 320.0
@export var rank_radius := 600.0
## Tests switch the hours and the city limits off.
@export var always_on := false
## The player's own street is never ticketed.
@export var home := Vector3.ZERO
@export var home_clear := 90.0

## { lane, road_key, fwd, k, pos, s, node, courier, time_left, phase, paint }
var vans: Array = []
## { station, pos, lane, s, slots: [node or null], leave_in: [], refill }
var ranks: Array = []
## { node, legs, path, i, wait, target, writing, phase }
var inspectors: Array = []
var stats := { "vans": 0, "taxis_away": 0, "tickets": 0 }
var ticket_note: Node3D

var graph: TrafficGraph
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _version := -1
var _blink := 0.0
var _hazard_on: Material
var _hazard_off: Material
var _van_pool: Array = []
var _taxi_pool: Array = []
var _car_still := 0.0
var _car_spot := Vector3.INF
var _ticketed := false
var _offence := ""


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph
	_rng.randomize()
	_hazard_on = TrafficModels.material(Color(1.0, 0.6, 0.1), 3.0)
	_hazard_off = TrafficModels.material(Color(0.5, 0.3, 0.05))
	if manager.has_signal(&"train_arrived"):
		manager.train_arrived.connect(on_train_arrived)


func _clock() -> Node:
	return get_node("/root/GameClock")


func in_city(p: Vector3) -> bool:
	return always_on or (CITY.has_point(Vector2(p.x, p.z)) and Vector2(p.x - home.x, p.z - home.z).length() > home_clear)


## Couriers about: weekdays 7 till 5:30, Saturday mornings.
func van_hours() -> bool:
	if always_on:
		return true
	var h: float = _clock().time_of_day
	match _day_kind():
		SUNDAY:
			return false
		SATURDAY:
			return h >= 7.0 and h < 12.0
	return h >= 7.0 and h < 17.5


## Inspectors work Monday to Saturday, 8 till 6.
func inspector_hours() -> bool:
	if always_on:
		return true
	var h: float = _clock().time_of_day
	return _day_kind() != SUNDAY and h >= 8.0 and h < 18.0


## TrafficManager.Day for today (by value: this script has to compile before
## the autoloads that TrafficManager uses exist, in the tools).
func _day_kind() -> int:
	return _manager.day_kind(_clock().day)


func update(delta: float, focus: Vector3) -> void:
	if graph == null:
		return
	_blink += delta
	var on := fmod(_blink, 0.8) < 0.4
	for van in vans:
		var mesh: MeshInstance3D = van.node.get_node("Mesh")
		mesh.set_surface_override_material(TrafficModels.Surf.IND_L, _hazard_on if on else _hazard_off)
		mesh.set_surface_override_material(TrafficModels.Surf.IND_R, _hazard_on if on else _hazard_off)
		_update_courier(van, delta)
	for rank in ranks:
		_update_rank(rank, delta)
	for ins in inspectors.duplicate():
		_update_inspector(ins, delta)
	_watch_player_car(delta)
	_timer -= delta
	if _timer > 0.0 or not enabled:
		return
	_timer = 1.5
	if graph.version != _version:
		_version = graph.version
		_relink()
	_manage_vans(focus)
	_manage_ranks(focus)
	_manage_inspectors(focus)


func clear() -> void:
	for van in vans.duplicate():
		remove_van(van)
	for rank in ranks.duplicate():
		_remove_rank(rank)
	for ins in inspectors.duplicate():
		_remove_inspector(ins)
	_remove_ticket_note()


# --- Couriers -----------------------------------------------------------------

## Whether a van could double-park on `lane` at `s`: the kerb lane of a road
## with another lane alongside to get round it, clear of junctions, stops,
## keep-clear boxes and anything else closing the lane.
func van_fits(lane: TrafficGraph.Lane, s: float) -> bool:
	if lane.connector or lane.road == null or lane.road.roundabout or not lane.closed.is_empty():
		return false
	if lane.k != lane.count - 1 or (lane.left_lane == null and lane.right_lane == null):
		return false
	if s < 35.0 or s > lane.length - 30.0:
		return false
	for stop in lane.stops:
		if absf(stop.s - s) < 25.0:
			return false
	for kc in lane.keep_clear:
		if s > kc[0] - 15.0 and s < kc[1] + 15.0:
			return false
	for v in lane.vehicles:
		if v.s > s - 35.0 and v.s < s + 12.0:
			return false
	return true


## Double-park a van on `lane` at `s` (the middle of the van). Returns it, or
## {} if it doesn't fit there.
func add_van(lane: TrafficGraph.Lane, s: float, minutes := -1.0) -> Dictionary:
	if not van_fits(lane, s):
		return {}
	var node: StaticBody3D = _van_pool.pop_back() if not _van_pool.is_empty() else _make_body(&"van")
	if node.get_parent() == null:
		add_child(node)
	var paint := Color(0.94, 0.94, 0.92) if _rng.randf() < 0.65 else TrafficModels.pick_paint(_rng)
	var mesh: MeshInstance3D = node.get_node("Mesh")
	mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(paint))
	var van := { "lane": lane, "road_key": lane.road.key, "fwd": lane.from_node == lane.road.a, "k": lane.k,
		"s": s, "node": node, "paint": paint, "phase": 0.0, "courier_t": 0.0, "courier_dir": 1, "courier_wait": 2.0,
		"time_left": (minutes * 60.0) if minutes > 0.0 else _rng.randf_range(80.0, 200.0) }
	_place_van(van)
	node.visible = true
	node.collision_layer = _manager.TRAFFIC_LAYER
	if van.get("courier") == null:
		van.courier = _make_courier()
		add_child(van.courier)
	_hazard_ticks(node)
	vans.append(van)
	stats.vans += 1
	return van


## Take the van away (it doesn't drive off: see _manage_vans for that).
func remove_van(van: Dictionary) -> void:
	vans.erase(van)
	var lane: TrafficGraph.Lane = van.lane
	if lane and not lane.closed.is_empty() and lane.closed[0] <= van.s and lane.closed[1] >= van.s:
		lane.closed = []
	_release_body(van.node, _van_pool)
	if van.courier:
		van.courier.queue_free()


## The van's done: shut the doors and drive off into the traffic. Returns the
## moving van, or null when there's no room to pull out yet.
func van_drive_off(van: Dictionary) -> TrafficVehicle:
	var lane: TrafficGraph.Lane = van.lane
	for v in lane.vehicles:
		if v.s > van.s - 16.0 and v.s < van.s + 8.0:
			return null
	var paint: Color = van.paint
	var s: float = van.s
	remove_van(van)
	var moving: TrafficVehicle = _manager.spawn_vehicle_at(&"van", lane, s, 0.0)
	if moving:
		moving.paint = paint
		moving.mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(paint))
		moving.indicator = 1
	return moving


func _place_van(van: Dictionary) -> void:
	var lane: TrafficGraph.Lane = van.lane
	var s: float = van.s
	var dir := lane.tangent(s)
	var kerb := TrafficGraph.left_of(dir)
	# Tucked in towards the kerb as far as it'll go.
	van.pos = lane.point(s) + kerb * 0.55
	van.node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), van.pos)
	van.kerb = kerb
	van.dir = dir
	# Traffic stops short and merges out, like for roadworks.
	lane.closed = [maxf(s - VAN_LENGTH * 0.5 - 12.0, 0.0), s + VAN_LENGTH * 0.5 + 1.0]


func _manage_vans(focus: Vector3) -> void:
	for van in vans.duplicate():
		van.time_left -= 1.5
		var far: bool = van.pos.distance_to(focus) > van_radius + 150.0
		if far and not _manager._visible(van.pos, 10.0):
			remove_van(van)
		elif van.time_left <= 0.0 and van.courier_dir > 0 and van.courier_t <= 0.0:
			if not _manager._visible(van.pos, 10.0) and van.pos.distance_to(focus) > 150.0:
				remove_van(van)
			else:
				van_drive_off(van)
	if not van_hours() or vans.size() >= max_vans:
		return
	var samples: Array = graph.samples_near(focus, van_radius)
	for attempt in 6:
		if samples.is_empty():
			return
		var entry: Array = samples[_rng.randi() % samples.size()]
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null:
			continue
		var s := _rng.randf_range(35.0, maxf(lane.length - 30.0, 35.0))
		var p := lane.point(s)
		var d := p.distance_to(focus)
		if d < 120.0 or d > van_radius or not in_city(p) or _manager._visible(p, 10.0):
			continue
		if not add_van(lane, s).is_empty():
			return


func _make_courier() -> Node3D:
	var person := TrafficModels.person(_rng)
	var body: Node3D = person.get_node("Body")
	# Courier polo and a parcel under one arm.
	var polo := TrafficModels.material([Color(0.85, 0.15, 0.1), Color(0.95, 0.75, 0.1), Color(0.2, 0.25, 0.3), Color(0.35, 0.2, 0.55)][_rng.randi() % 4])
	(body.get_child(0) as MeshInstance3D).material_override = polo
	var parcel := TrafficModels._add_part(body, "parcel", Vector3(0.36, 0.28, 0.3), Vector3(0, 1.05, -0.26), Vector3.ZERO, TrafficModels.material(Color(0.62, 0.47, 0.3)))
	parcel.name = "Parcel"
	return person


## The courier goes from the back of the van to a shop door on the footpath
## and back, carrying the parcel one way.
func _update_courier(van: Dictionary, delta: float) -> void:
	var courier: Node3D = van.courier
	if courier == null:
		return
	if van.courier_wait > 0.0:
		van.courier_wait -= delta
		if van.courier_wait <= 0.0 and van.courier_t <= 0.0:
			# Out of the van with the next parcel.
			_sound("traffic/traffic_van_rear_door_open", van.pos - van.dir * VAN_LENGTH * 0.5, -6.0)
	else:
		van.courier_t = clampf(van.courier_t + delta * 1.3 / 7.0 * van.courier_dir, 0.0, 1.0)
		if van.courier_t >= 1.0 or van.courier_t <= 0.0:
			van.courier_dir = -van.courier_dir
			van.courier_wait = _rng.randf_range(4.0, 12.0) if van.courier_t >= 1.0 else 3.0
			if van.courier_t <= 0.0:
				_sound("traffic/traffic_van_rear_door_close", van.pos - van.dir * VAN_LENGTH * 0.5, -6.0)
	var dir: Vector3 = van.dir
	var kerb: Vector3 = van.kerb
	var from: Vector3 = van.pos - dir * (VAN_LENGTH * 0.5 + 0.7)
	var to: Vector3 = van.pos + kerb * 4.6 + dir * 1.0
	var p := from.lerp(to, van.courier_t)
	courier.position = p
	var moving: bool = van.courier_wait <= 0.0
	var heading: Vector3 = (to - from).normalized() * van.courier_dir if moving else -kerb if van.courier_t <= 0.0 else kerb
	if heading.length() > 0.1:
		courier.basis = Basis.looking_at(heading, Vector3.UP)
	van.phase += delta * (7.0 if moving else 0.0)
	_swing(courier.get_node("Body"), sin(van.phase) * 0.5 if moving else 0.0)
	courier.get_node("Body/Parcel").visible = van.courier_dir > 0 and van.courier_t < 1.0 and not (van.courier_wait > 0.0 and van.courier_t >= 1.0)


static func _swing(body: Node3D, swing: float) -> void:
	body.get_node("LegL").rotation.x = swing
	body.get_node("LegR").rotation.x = -swing
	body.get_node("ArmL").rotation.x = -swing * 0.7
	body.get_node("ArmR").rotation.x = swing * 0.7


# --- Taxi ranks ---------------------------------------------------------------

## Set up a taxi rank by `lane`'s kerb at `s` (the front of the queue).
func add_rank(station: String, lane: TrafficGraph.Lane, s: float, taxis := RANK_SLOTS) -> Dictionary:
	var rank := { "station": station, "lane": lane, "s": s, "slots": [], "leave_in": [], "pos": lane.point(s),
		"road_key": lane.road.key if lane.road else "", "fwd": lane.road != null and lane.from_node == lane.road.a, "k": lane.k }
	for i in RANK_SLOTS:
		rank.slots.append(null)
	ranks.append(rank)
	for i in mini(taxis, RANK_SLOTS):
		_fill_slot(rank, i, true)
	_reserve_kerb(rank)
	return rank


func rank_slot_transform(rank: Dictionary, i: int) -> Transform3D:
	var lane: TrafficGraph.Lane = rank.lane
	var s: float = maxf(rank.s - i * RANK_GAP, 3.0)
	var dir := lane.tangent(s)
	var p := lane.point(s) + TrafficGraph.left_of(dir) * (TrafficGraph.LANE_WIDTH * 0.5 + 1.05)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), p)


## A train's pulled in: the front taxi or two will have a fare shortly.
func on_train_arrived(position: Vector3) -> void:
	for rank in ranks:
		if rank.pos.distance_to(position) < 320.0:
			rank.leave_in.append(_rng.randf_range(12.0, 22.0))
			if _rng.randf() < 0.5:
				rank.leave_in.append(_rng.randf_range(28.0, 40.0))


func _update_rank(rank: Dictionary, delta: float) -> void:
	for j in rank.leave_in.size():
		rank.leave_in[j] -= delta
	if not rank.leave_in.is_empty() and rank.leave_in[0] <= 0.0:
		if taxi_depart(rank) or rank.leave_in[0] < -20.0:
			rank.leave_in.pop_front()
	# The queue shuffles up.
	for i in RANK_SLOTS:
		var node: Node3D = rank.slots[i]
		if node == null:
			continue
		var want := rank_slot_transform(rank, i)
		node.global_position = node.global_position.move_toward(want.origin, delta * 2.5)
		node.global_basis = want.basis
		if i > 0 and rank.slots[i - 1] == null:
			rank.slots[i - 1] = node
			rank.slots[i] = null


## The front taxi takes a fare and pulls out into the traffic. Returns false
## when there's no taxi or no room to pull out.
func taxi_depart(rank: Dictionary) -> bool:
	var node: StaticBody3D = rank.slots[0]
	if node == null:
		return true
	var lane: TrafficGraph.Lane = rank.lane
	var s := TrafficGraph.closest_s(lane.pts, lane.cum, node.global_position)
	if not lane.closed.is_empty() and s > lane.closed[0] - 5.0 and s < lane.closed[1] + 5.0:
		return false
	for v in lane.vehicles:
		if v.s > s - 20.0 and v.s < s + 10.0:
			return false
	rank.slots[0] = null
	var paint: Array = node.get_meta("paint")
	_sound("traffic/traffic_taxi_door_close", node.global_position, -6.0)
	_release_body(node, _taxi_pool)
	var moving: TrafficVehicle = _manager.spawn_vehicle_at(&"taxi", lane, s, 0.0)
	if moving:
		moving.indicator = 1
		_manager.paint_taxi(moving, paint)
	stats.taxis_away += 1
	taxi_departed.emit(rank.station, rank.pos)
	return true


func _fill_slot(rank: Dictionary, i: int, now := false) -> void:
	var node: StaticBody3D = _taxi_pool.pop_back() if not _taxi_pool.is_empty() else _make_body(&"taxi")
	if node.get_parent() == null:
		add_child(node)
	var paint: Array = TrafficModels.TAXI_PAINT[_rng.randi() % TrafficModels.TAXI_PAINT.size()]
	node.set_meta("paint", paint)
	var mesh: MeshInstance3D = node.get_node("Mesh")
	mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(paint[0]))
	mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(paint[1]))
	# The roof sign's lit while it's free (at night it shows).
	mesh.set_surface_override_material(TrafficModels.Surf.HEAD, TrafficModels.material(Color(1.0, 0.85, 0.4), 2.0))
	var at := rank_slot_transform(rank, i)
	if not now:
		# Rolls up from behind into the queue.
		at.origin += at.basis.z * 12.0
	node.global_transform = at
	node.visible = true
	node.collision_layer = _manager.TRAFFIC_LAYER
	rank.slots[i] = node


func _manage_ranks(focus: Vector3) -> void:
	for rank in ranks.duplicate():
		if rank.pos.distance_to(focus) > rank_radius + 150.0 and not _manager._visible(rank.pos, 10.0):
			_remove_rank(rank)
	var h: float = _clock().time_of_day
	var busy := always_on or h >= 5.5 or h < 2.0
	if not busy:
		return
	# Top the ranks up out of sight.
	for rank in ranks:
		var back := rank_slot_transform(rank, RANK_SLOTS - 1).origin
		if rank.slots[RANK_SLOTS - 1] == null and not _manager._visible(back, 8.0) and _rng.randf() < 0.3:
			_fill_slot(rank, RANK_SLOTS - 1)
	for st in graph.stations:
		var p: Vector3 = st.pos
		if p.distance_to(focus) > rank_radius or _manager._visible(p, 30.0):
			continue
		var have := false
		for rank in ranks:
			if rank.station == st.name and rank.pos.distance_to(p) < 150.0:
				have = true
		if have:
			continue
		var spot := _rank_spot(p)
		if spot.is_empty():
			# Nowhere to put one: remember so we don't keep looking.
			ranks.append({ "station": st.name, "pos": p, "slots": [], "leave_in": [], "lane": null, "s": 0.0, "none": true })
			continue
		add_rank(st.name, spot[0], spot[1])


## The kerb lane of a proper street near the station, with room for the queue.
func _rank_spot(p: Vector3) -> Array:
	var best := []
	var best_d := INF
	for entry in graph.samples_near(p, 110.0):
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null or lane.road.roundabout or lane.k != lane.count - 1:
			continue
		if lane.road.kind in [&"motorway", &"motorway_link", &"trunk", &"trunk_link", &"service", &"track"]:
			continue
		var s := TrafficGraph.closest_s(lane.pts, lane.cum, p)
		s = clampf(s, 30.0 + RANK_GAP * RANK_SLOTS, lane.length - 25.0)
		if lane.length < 30.0 + RANK_GAP * RANK_SLOTS + 25.0:
			continue
		var clear := true
		for stop in lane.stops:
			if stop.s > s - RANK_GAP * RANK_SLOTS - 10.0 and stop.s < s + 10.0:
				clear = false
		if not clear:
			continue
		var d := lane.point(s).distance_to(p)
		if d < best_d:
			best_d = d
			best = [lane, s]
	return best


## No parked cars where the taxis queue.
func _reserve_kerb(rank: Dictionary) -> void:
	var parking = _manager.get("parking")
	if parking == null:
		return
	for i in RANK_SLOTS:
		var p := rank_slot_transform(rank, i).origin
		for spot in graph.parking_near(p, 10.0):
			if spot.pos.distance_to(p) < 5.5:
				spot.reserved = true
				if parking.shown.has(spot):
					parking._hide(spot)


func _remove_rank(rank: Dictionary) -> void:
	ranks.erase(rank)
	for i in rank.slots.size():
		if rank.slots[i] != null:
			_release_body(rank.slots[i], _taxi_pool)
	if rank.get("lane") != null:
		for i in RANK_SLOTS:
			var p := rank_slot_transform(rank, i).origin
			for spot in graph.parking_near(p, 10.0):
				spot.erase("reserved")


# --- Parking inspectors ----------------------------------------------------------

func _manage_inspectors(focus: Vector3) -> void:
	for ins in inspectors.duplicate():
		if ins.target == null and ins.node.position.distance_to(focus) > inspector_radius + 120.0 and not _manager._visible(ins.node.position, 2.0):
			_remove_inspector(ins)
	if not inspector_hours() or inspectors.size() >= max_inspectors or not in_city(focus):
		return
	var spots: Array = graph.parking_near(focus, inspector_radius)
	for attempt in 6:
		if spots.is_empty():
			return
		var spot: Dictionary = spots[_rng.randi() % spots.size()]
		if spot.kind != &"street":
			continue
		var d: float = spot.pos.distance_to(focus)
		if d < 70.0 or d > inspector_radius or _manager._visible(spot.pos, 3.0):
			continue
		add_inspector(_kerb_walk(spot))
		return


## Put an inspector on the footpath walking `path` (back and forth).
func add_inspector(path: Array) -> Dictionary:
	if path.is_empty():
		return {}
	var node := _make_inspector()
	add_child(node)
	node.position = path[0].pos
	var ins := { "node": node, "path": path, "i": 0, "step": 1, "wait": 0.0, "target": null, "writing": 0.0, "phase": 0.0 }
	inspectors.append(ins)
	return ins


func _remove_inspector(ins: Dictionary) -> void:
	inspectors.erase(ins)
	ins.node.queue_free()


## A walk along the kerb: street bays one after another, each with the
## footpath point beside it. [{pos, spot}]
func _kerb_walk(start: Dictionary) -> Array:
	var path := []
	var at := start
	var seen := {}
	for n in 14:
		seen[at] = true
		path.append({ "pos": _footpath_by(at.pos), "spot": at })
		var next = null
		var next_d := 16.0
		for spot in graph.parking_near(at.pos, 20.0):
			if seen.has(spot) or spot.kind != &"street":
				continue
			var d: float = spot.pos.distance_to(at.pos)
			if d < next_d:
				next_d = d
				next = spot
		if next == null:
			break
		at = next
	return path


## The footpath beside something parked at the kerb at p.
func _footpath_by(p: Vector3) -> Vector3:
	var out := Vector3.ZERO
	var best := INF
	for entry in graph.samples_near(p, 12.0):
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector:
			continue
		var q := lane.point(TrafficGraph.closest_s(lane.pts, lane.cum, p))
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < best:
			best = d
			out = Vector3(p.x - q.x, 0, p.z - q.z).normalized()
	return p + out * 2.0


func _update_inspector(ins: Dictionary, delta: float) -> void:
	var node: Node3D = ins.node
	var body: Node3D = node.get_node("Body")
	var to: Vector3
	if ins.target != null:
		var car: Node3D = ins.target
		if not is_instance_valid(car) or _offence == "" or _ticketed:
			ins.target = null
			ins.writing = 0.0
			return
		to = car.global_position + car.global_basis.x * -1.6
		to.y = car.global_position.y - 0.4
	else:
		to = ins.path[ins.i].pos
	var flat := Vector3(to.x - node.position.x, 0, to.z - node.position.z)
	if flat.length() > 0.4 and ins.wait <= 0.0:
		var step := minf(flat.length(), (1.5 if ins.target != null else 1.2) * delta)
		node.position += flat.normalized() * step
		node.position.y = lerpf(node.position.y, to.y, minf(delta * 3.0, 1.0))
		node.basis = Basis.looking_at(flat.normalized(), Vector3.UP)
		ins.phase += delta * 6.5
		_swing(body, sin(ins.phase) * 0.45)
		body.get_node("Device").visible = false
		return
	_swing(body, 0.0)
	if ins.target != null:
		# Writing the player up.
		body.get_node("Device").visible = true
		var car: Node3D = ins.target
		var look := Vector3(car.global_position.x - node.position.x, 0, car.global_position.z - node.position.z)
		if look.length() > 0.1:
			node.basis = Basis.looking_at(look.normalized(), Vector3.UP)
		if ins.writing == 0.0:
			_sound("traffic/traffic_ticket_printer", node.global_position + Vector3(0, 1.1, 0), -8.0)
		ins.writing += delta
		if ins.writing >= WRITE_TIME:
			_issue_ticket(car)
			ins.target = null
			ins.writing = 0.0
		return
	if ins.wait > 0.0:
		ins.wait -= delta
		body.get_node("Device").visible = ins.wait > 0.5
		return
	# At a bay: a look at whatever's parked there.
	var spot: Dictionary = ins.path[ins.i].spot
	if _manager.parking.shown.has(spot) and ins.get("last") != ins.i:
		ins.last = ins.i
		ins.wait = _rng.randf_range(2.0, 4.5)
		var car: Node3D = _manager.parking.shown[spot]
		var look := Vector3(car.global_position.x - node.position.x, 0, car.global_position.z - node.position.z)
		if look.length() > 0.1:
			node.basis = Basis.looking_at(look.normalized(), Vector3.UP)
		return
	ins.last = -1
	if ins.i + ins.step < 0 or ins.i + ins.step >= ins.path.size():
		ins.step = -ins.step
	ins.i = clampi(ins.i + ins.step, 0, ins.path.size() - 1)


func _make_inspector() -> Node3D:
	var person := TrafficModels.person(_rng)
	var body: Node3D = person.get_node("Body")
	var navy := TrafficModels.material(Color(0.1, 0.13, 0.25))
	(body.get_child(0) as MeshInstance3D).material_override = navy
	for arm in ["ArmL", "ArmR"]:
		(body.get_node(arm).get_child(0) as MeshInstance3D).material_override = navy
	for leg in ["LegL", "LegR"]:
		(body.get_node(leg).get_child(0) as MeshInstance3D).material_override = TrafficModels.material(Color(0.08, 0.09, 0.14))
	var vis := TrafficModels.material(Color(0.85, 0.95, 0.15), 0.3)
	TrafficModels._add_part(body, "vest", Vector3(0.44, 0.4, 0.26), Vector3(0, 1.24, 0), Vector3.ZERO, vis)
	TrafficModels._add_part(body, "cap", Vector3(0.25, 0.08, 0.27), Vector3(0, 1.79, 0.0), Vector3.ZERO, navy)
	TrafficModels._add_part(body, "cap_peak", Vector3(0.22, 0.03, 0.12), Vector3(0, 1.76, -0.17), Vector3.ZERO, navy)
	var device := TrafficModels._add_part(body, "device", Vector3(0.12, 0.18, 0.04), Vector3(0.05, 1.12, -0.3), Vector3(-0.6, 0, 0), TrafficModels.material(Color(0.15, 0.15, 0.15)))
	device.name = "Device"
	device.visible = false
	return person


# --- The player's car -----------------------------------------------------------

## What the player's car would be booked for, parked at p: "lane" in a
## traffic lane, "bay" in a street bay, "" nowhere ticketable.
func offence_at(p: Vector3) -> String:
	if not in_city(p):
		return ""
	for entry in graph.samples_near(p, 8.0):
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null:
			continue
		var q := lane.point(TrafficGraph.closest_s(lane.pts, lane.cum, p))
		if absf(q.y - p.y) < 2.0 and Vector2(q.x - p.x, q.z - p.z).length() < 1.9:
			return "lane"
	for spot in graph.parking_near(p, 8.0):
		if spot.kind == &"street" and spot.pos.distance_to(p) < 3.0:
			return "bay"
	return ""


func _watch_player_car(delta: float) -> void:
	var car: RigidBody3D = _manager._player
	if car == null or not is_instance_valid(car):
		return
	var walker: Node = _manager._walker
	var away: bool = walker != null and is_instance_valid(walker) and not walker.in_car and walker.global_position.distance_to(car.global_position) > 12.0
	if walker != null and is_instance_valid(walker) and walker.in_car:
		_remove_ticket_note()
	if not away or car.linear_velocity.length() > 0.3 or car.global_position.distance_to(_car_spot) > 2.0:
		if car.global_position.distance_to(_car_spot) > 2.0 or (walker != null and is_instance_valid(walker) and walker.in_car):
			_ticketed = false
		_car_spot = car.global_position
		_car_still = 0.0
		_offence = ""
		return
	_car_still += delta
	if _ticketed or not enabled or not inspector_hours() or _at_job_site(car.global_position):
		_offence = ""
		return
	var kind := offence_at(car.global_position)
	var grace := LANE_GRACE if kind == "lane" else BAY_GRACE
	if kind == "" or _car_still < grace:
		_offence = ""
		return
	if _offence == "":
		_offence = kind
		send_inspector(car)


## Send the nearest inspector (or a new one from out of sight) to the car.
func send_inspector(car: Node3D) -> void:
	for ins in inspectors:
		if ins.target == car:
			return
	var best = null
	var best_d := 260.0
	for ins in inspectors:
		var d: float = ins.node.position.distance_to(car.global_position)
		if d < best_d:
			best_d = d
			best = ins
	if best == null:
		var from := _out_of_sight_near(car.global_position)
		best = add_inspector([{ "pos": from, "spot": {} }])
		if best.is_empty():
			return
	best.target = car
	best.wait = 0.0


func _out_of_sight_near(p: Vector3) -> Vector3:
	var spots: Array = graph.parking_near(p, 120.0).filter(func(spot): return spot.pos.distance_to(p) > 35.0)
	spots.sort_custom(func(a, b): return a.pos.distance_to(p) < b.pos.distance_to(p))
	for spot in spots:
		if not _manager._visible(spot.pos, 2.0):
			return _footpath_by(spot.pos)
	for attempt in 12:
		var a := _rng.randf() * TAU
		var q := p + Vector3(cos(a), 0, sin(a)) * 50.0
		if not _manager._visible(q, 2.0):
			return q
	return p + Vector3(40, 0, 0)


func _at_job_site(p: Vector3) -> bool:
	var jobs := get_node_or_null("/root/Jobs")
	if jobs == null:
		return false
	for site in jobs.sites():
		if site.global_position.distance_to(p) < 35.0:
			return true
	return false


func _issue_ticket(car: Node3D) -> void:
	_ticketed = true
	var fine := LANE_FINE if _offence == "lane" else BAY_FINE
	var reason := "parked in a traffic lane" if _offence == "lane" else "overstayed a street bay"
	_offence = ""
	stats.tickets += 1
	var wallet := get_node_or_null("/root/Wallet")
	if wallet:
		wallet.spend(mini(fine, wallet.balance), "parking fine")
	var progression := get_node_or_null("/root/Progression")
	if progression:
		progression.add_stat("parking_fines")
	_remove_ticket_note()
	# A ticket under the wiper.
	ticket_note = Node3D.new()
	ticket_note.name = "ParkingTicket"
	TrafficModels._add_part(ticket_note, "ticket", Vector3(0.14, 0.01, 0.22), Vector3.ZERO, Vector3.ZERO, TrafficModels.material(Color(0.96, 0.95, 0.88)))
	car.add_child(ticket_note)
	ticket_note.position = Vector3(-0.3, 1.02, -0.62)
	ticket_note.rotation.x = -0.5
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_method("toast"):
		hud.toast("Parking fine: $%d (%s)" % [fine, reason])
	parking_ticket.emit(fine, reason, car.global_position)


func _remove_ticket_note() -> void:
	if ticket_note and is_instance_valid(ticket_note):
		ticket_note.queue_free()
	ticket_note = null


# --- Shared ---------------------------------------------------------------------

## Lanes are rebuilt when map tiles arrive: find the vans' and ranks' lanes again.
func _relink() -> void:
	for van in vans.duplicate():
		var lane := _find_lane(van.road_key, van.fwd, van.k)
		if lane == null:
			remove_van(van)
			continue
		van.lane = lane
		van.s = TrafficGraph.closest_s(lane.pts, lane.cum, van.pos)
		_place_van(van)
	for rank in ranks.duplicate():
		if rank.get("none", false):
			continue
		var lane := _find_lane(rank.road_key, rank.fwd, rank.k)
		if lane == null:
			_remove_rank(rank)
			continue
		rank.lane = lane
		rank.s = TrafficGraph.closest_s(lane.pts, lane.cum, rank.pos)


func _find_lane(road_key: String, fwd: bool, k: int) -> TrafficGraph.Lane:
	for road in graph.roads:
		if road.key == road_key:
			for lane in road.lanes:
				if (lane.from_node == road.a) == fwd and lane.k == k:
					return lane
	return null


func _make_body(type: StringName) -> StaticBody3D:
	var info: Dictionary = TrafficModels.TYPES[type]
	var body := StaticBody3D.new()
	body.name = "%s_%d" % [type, get_child_count()]
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_meta("surface", &"concrete")
	body.set_meta("traffic", type)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(info.width, info.height * 0.85, info.length)
	shape.shape = box
	shape.position = Vector3(0, info.height * 0.5 + 0.1, 0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = TrafficModels.vehicle_mesh(type)
	mesh.visibility_range_end = 700.0
	mesh.set_surface_override_material(TrafficModels.Surf.GLASS, TrafficModels.material(Color(0.07, 0.08, 0.1)))
	mesh.set_surface_override_material(TrafficModels.Surf.TYRES, TrafficModels.material(Color(0.05, 0.05, 0.05)))
	mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(Color(0.2, 0.2, 0.2)))
	mesh.set_surface_override_material(TrafficModels.Surf.HEAD, TrafficModels.material(Color(0.8, 0.8, 0.75)))
	mesh.set_surface_override_material(TrafficModels.Surf.TAIL, TrafficModels.material(Color(0.45, 0.05, 0.04)))
	mesh.set_surface_override_material(TrafficModels.Surf.IND_L, _hazard_off)
	mesh.set_surface_override_material(TrafficModels.Surf.IND_R, _hazard_off)
	body.add_child(mesh)
	return body


## The audio thread's sounds, once they're in.
func _sound(sound_name: String, p: Vector3, db: float) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has(sound_name):
		audio.play_at(sound_name, p, db, "SFX")


## A quiet hazard relay ticking on a double-parked van.
func _hazard_ticks(node: Node3D) -> void:
	if node.has_node("Hazards"):
		(node.get_node("Hazards") as AudioStreamPlayer3D).play()
		return
	var audio := get_node_or_null("/root/Audio")
	if audio == null or not audio.has_method("has") or not audio.has("traffic/traffic_hazard_tick_loop"):
		return
	var tick := AudioStreamPlayer3D.new()
	tick.name = "Hazards"
	tick.stream = audio.stream("traffic/traffic_hazard_tick_loop", true)
	tick.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	tick.unit_size = 2.0
	tick.max_distance = 12.0
	tick.position = Vector3(0, 1.0, -1.5)
	node.add_child(tick)
	tick.play()


func _release_body(node: StaticBody3D, pool: Array) -> void:
	if node.has_node("Hazards"):
		(node.get_node("Hazards") as AudioStreamPlayer3D).stop()
	node.visible = false
	node.collision_layer = 0
	node.position = Vector3(0, -500, 0)
	pool.append(node)
