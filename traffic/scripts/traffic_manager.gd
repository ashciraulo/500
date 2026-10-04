class_name TrafficManager
extends Node3D
## Traffic and street life around the player: cars, utes, vans and Transperth
## buses driving on the left, traffic lights and give-ways, trains on the rail
## lines with boom gates at level crossings, and people on the footpaths.
##
## Only the area around the player is simulated. Vehicles and people spawn out
## of sight between `min_spawn_radius` and `spawn_radius`, despawn past
## `despawn_radius`, and their nodes are pooled and reused. Density follows
## the time of day (rush hours, quiet nights) and the weather.
##
## Road data: call `add_network(data)` (the map does this per tile, or put a
## node with `get_traffic_data()` in the "traffic_sources" group). With no
## data and a TestGrid next to it, the manager uses a network that matches
## the test grid's streets. Format and hooks: docs/TRAFFIC.md.

signal vehicle_spawned(vehicle: Node3D, type: StringName)
signal vehicle_despawned(vehicle: Node3D)
## A vehicle sounded its horn. Placeholder horns play on the vehicle's
## Audio/Horn player; sound code can mute those and play its own.
signal horn(vehicle: Node3D, duration: float, is_bus: bool)
signal pedestrian_startled(position: Vector3)
signal crossing_changed(position: Vector3, closed: bool)
signal train_spawned(train: Node3D)
signal train_despawned(train: Node3D)
signal signals_changed(position: Vector3)
signal network_changed

## Physics layer 3: traffic. The player's car gets this bit added to its mask.
const TRAFFIC_LAYER := 1 << 2
const HASH_CELL := 16.0
const SPAWN_INTERVAL := 0.25
## Real headlight beams for the closest few vehicles at night.
const HEADLIGHT_BEAMS := 6

@export var focus_path: NodePath
## Fixed seed for repeatable runs (tests); 0 picks a random one.
@export var random_seed := 0
@export var use_test_grid_fallback := true
@export_group("Density")
@export var max_vehicles := 60
@export var max_pedestrians := 70
@export var max_buses := 4
@export var max_trains := 2
## Cars per kilometre of lane at rush hour.
@export var cars_per_lane_km := 10.0
## People per kilometre of footpath at the busiest time.
@export var people_per_km := 45.0
## Player-facing multipliers (e.g. a settings slider).
@export var density_scale := 1.0
@export var pedestrian_scale := 1.0
@export var trains_enabled := true
@export_group("Ranges")
@export var min_spawn_radius := 110.0
@export var spawn_radius := 260.0
@export var despawn_radius := 330.0
@export var ped_spawn_radius := 140.0
@export var ped_despawn_radius := 190.0
@export var train_spawn_min := 450.0
@export var train_spawn_max := 900.0

var graph := TrafficGraph.new()
var vehicles: Array = []
var pedestrians: Array = []
var trains: Array = []
## Rolling average of the simulation cost per physics frame, in ms.
var step_ms := 0.0
## Counters for tests and debugging.
var stats := { "spawned": 0, "despawned": 0, "created": 0, "red_runs": 0, "peds_created": 0, "trains": 0 }

var _rng := RandomNumberGenerator.new()
var _pool := {}
var _ped_pool: Array = []
var _hash := {}
var _next_id := 1
var _spawn_timer := 0.0
var _train_timer := 20.0
var _warm := 2.0
var _time := 0.0
var _focus: Node3D
var _player: RigidBody3D
var _player_proxy := PlayerProxy.new()
var _camera: Camera3D
var _horn_car: AudioStreamWAV
var _horn_bus: AudioStreamWAV
var _signal_props: Array = []
var _crossing_props: Array = []
var _bus_stop_props := {}
var _lane_km_cache := 0.0
var _foot_km_cache := 0.0
var _density_timer := 0.0
var _props_root: Node3D
var _beams: Array = []
var _beam_owners: Array = []
var _beam_timer := 0.0


class PlayerProxy:
	var position := Vector3.ZERO
	var forward := Vector3.FORWARD
	var velocity := Vector3.ZERO
	var speed := 0.0
	var length := 3.6
	var width := 1.7
	var present := false


func _ready() -> void:
	add_to_group(&"traffic")
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	_horn_car = _make_horn(415.0, 523.0, 1.4)
	_horn_bus = _make_horn(247.0, 311.0, 1.6)
	_load_sources.call_deferred()


func _load_sources() -> void:
	var loaded := false
	for source in get_tree().get_nodes_in_group(&"traffic_sources"):
		if source.has_method("get_traffic_data"):
			add_network(source.get_traffic_data())
			loaded = true
	if not loaded and use_test_grid_fallback and graph.roads.is_empty():
		var parent := get_parent()
		if parent and parent.get_node_or_null("TestGrid") != null:
			add_network(TrafficTestNetworks.test_grid())


## Add road data (one map tile, or a whole network). See docs/TRAFFIC.md.
func add_network(data: Dictionary) -> void:
	graph.add_data(data)
	# Junctions where the new roads join were rebuilt: replan from the first
	# move that no longer exists.
	for v in vehicles:
		for i in range(1, v.route.size()):
			if not v.route[i - 1].next.has(v.route[i]):
				v.route.resize(i)
				break
		v.commits = v.commits.filter(func(c): return v.route.has(c))
		if v.commits.is_empty():
			v.cleared = null
		_extend_route(v)
	_build_props()
	_lane_km_cache = 0.0
	network_changed.emit()


## Remove everything currently driving or walking (e.g. before a teleport).
func clear_all() -> void:
	for v in vehicles.duplicate():
		_despawn_vehicle(v)
	for p in pedestrians.duplicate():
		_despawn_ped(p)
	for t in trains.duplicate():
		_despawn_train(t)
	_warm = 2.0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_time += delta
	_update_focus()
	for controller in graph.signal_controllers:
		controller.update(delta)
		if controller.changed_this_frame:
			signals_changed.emit(controller.center)
	_update_trains(delta)
	_update_crossings(delta)
	_rebuild_hash()
	var lights_on := _headlights_wanted()
	for v in vehicles:
		_drive(v, delta)
	for v in vehicles:
		_place(v, delta, lights_on)
	_update_beams(delta, lights_on)
	_update_peds(delta)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_manage_population()
	_warm = maxf(_warm - delta, 0.0)
	_update_props()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	step_ms = lerpf(step_ms, ms, 0.05)


# --- Focus, player and camera -------------------------------------------------

func _update_focus() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player_car") as RigidBody3D
		if _player:
			_player.collision_mask |= TRAFFIC_LAYER
			if _player.has_signal(&"impact"):
				_player.impact.connect(_on_player_impact)
	if focus_path != NodePath() and has_node(focus_path):
		_focus = get_node(focus_path)
	elif _player:
		_focus = _player
	_player_proxy.present = _player != null
	if _player:
		_player_proxy.position = _player.global_position
		_player_proxy.forward = -_player.global_basis.z
		_player_proxy.velocity = _player.linear_velocity
		_player_proxy.speed = _player.linear_velocity.length()
	if _camera == null or not is_instance_valid(_camera) or not _camera.current:
		_camera = get_viewport().get_camera_3d() if get_viewport() else null


func focus_position() -> Vector3:
	if _focus and is_instance_valid(_focus):
		return _focus.global_position
	if _camera:
		return _camera.global_position
	return Vector3.ZERO


func _visible(p: Vector3, margin := 0.0) -> bool:
	if _camera == null:
		return false
	return _camera.is_position_in_frustum(p) or (margin > 0.0 and _camera.global_position.distance_to(p) < margin)


func _headlights_wanted() -> bool:
	return GameClock.daylight() < 0.45 or Weather.rain > 0.5


# --- Density ------------------------------------------------------------------

## Traffic by hour, 0..1 (rush hours at 7-9 and 16-18).
const CAR_CURVE := [0.14, 0.08, 0.05, 0.05, 0.08, 0.25, 0.6, 1.0, 1.0, 0.75, 0.6, 0.65,
	0.7, 0.65, 0.65, 0.8, 1.0, 1.0, 0.8, 0.6, 0.5, 0.45, 0.35, 0.22]
## People by hour (lunchtime peak, Northbridge evenings).
const PED_CURVE := [0.3, 0.2, 0.08, 0.04, 0.04, 0.08, 0.25, 0.6, 0.8, 0.65, 0.7, 0.9,
	1.0, 0.95, 0.75, 0.7, 0.8, 0.85, 0.7, 0.6, 0.6, 0.55, 0.5, 0.4]


static func _curve(curve: Array, hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var i := int(h)
	return lerpf(curve[i], curve[(i + 1) % 24], h - i)


func car_density() -> float:
	var weather := 1.0
	match Weather.state:
		Weather.State.LIGHT_RAIN: weather = 1.05
		Weather.State.STORM: weather = 0.75
	return _curve(CAR_CURVE, GameClock.time_of_day) * weather * density_scale


func people_density() -> float:
	var weather := lerpf(1.0, 0.35, clampf(Weather.rain * 1.4, 0.0, 1.0))
	if Weather.state == Weather.State.STORM:
		weather *= 0.4
	return _curve(PED_CURVE, GameClock.time_of_day) * weather * pedestrian_scale


func target_vehicles() -> int:
	return mini(roundi(_lane_km_cache * cars_per_lane_km * car_density()), max_vehicles)


func target_pedestrians() -> int:
	return mini(roundi(_foot_km_cache * people_per_km * people_density()), max_pedestrians)


# --- Spatial hash (vehicles, people, the player) ------------------------------

func _rebuild_hash() -> void:
	_hash.clear()
	for v in vehicles:
		_hash_add(v, v.position)
	for p in pedestrians:
		_hash_add(p, p.position)
	if _player_proxy.present:
		_hash_add(_player_proxy, _player_proxy.position)


func _hash_add(agent: Object, p: Vector3) -> void:
	var key := Vector2i(floori(p.x / HASH_CELL), floori(p.z / HASH_CELL))
	if not _hash.has(key):
		_hash[key] = []
	_hash[key].append(agent)


func _agents_near(p: Vector3, radius: float) -> Array:
	var result: Array = []
	var c0 := Vector2i(floori((p.x - radius) / HASH_CELL), floori((p.z - radius) / HASH_CELL))
	var c1 := Vector2i(floori((p.x + radius) / HASH_CELL), floori((p.z + radius) / HASH_CELL))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var list = _hash.get(Vector2i(x, z))
			if list:
				result.append_array(list)
	return result


# --- Driving ------------------------------------------------------------------

func _drive(v: TrafficVehicle, dt: float) -> void:
	v.lifetime += dt
	_extend_route(v)
	var lane: TrafficGraph.Lane = v.route[0]
	var wet: float = Weather.wetness
	var a_max := 1.1 if v.is_bus else 1.8
	var b_comf := 2.4
	var headway := (1.5 if v.is_bus else 1.3) * (1.0 + 0.4 * wet)
	var v0: float = lane.speed * v.eagerness * (1.0 - 0.15 * wet)

	# Slow down in time for bends and slower roads ahead.
	var ahead: float = lane.length - v.s
	for i in range(1, v.route.size()):
		if ahead > 80.0:
			break
		var l: TrafficGraph.Lane = v.route[i]
		var limit: float = l.speed * (v.eagerness if not l.connector else 1.0)
		v0 = minf(v0, sqrt(limit * limit + 2.0 * 1.6 * maxf(ahead, 0.0)))
		ahead += l.length

	var gap := INF
	var lead_speed := 0.0
	var reason := TrafficVehicle.Reason.NONE
	var who: Object = null

	# 1. The vehicle in front on our lanes.
	var base := -v.s
	for i in v.route.size():
		var l: TrafficGraph.Lane = v.route[i]
		if base > 90.0:
			break
		var best := INF
		var best_o: TrafficVehicle = null
		for o in l.vehicles:
			if o == v:
				continue
			if i == 0 and (o.s < v.s or (o.s == v.s and o.id < v.id)):
				continue
			var d: float = base + o.s
			if d < best:
				best = d
				best_o = o
		if l.connector and i > 0:
			# Someone just ahead taking another way out of the same lane is
			# still in front of us until the paths part.
			for sib in l.in_lane.next:
				if sib == l:
					continue
				for o in sib.vehicles:
					if o.s < 8.0 and base + o.s < best:
						best = base + o.s
						best_o = o
		if l.connector:
			# Someone on another move into the same exit lane, nearer its end:
			# they're in front once the paths join.
			for other in l.conflicts:
				if other.next[0] != l.next[0]:
					continue
				for o in other.vehicles:
					if o == v:
						continue
					# Distances to the end of the junction, where the paths meet.
					var d: float = (base + l.length) - (other.length - o.s)
					if (d > 0.0 or (d == 0.0 and o.id < v.id)) and d < best:
						best = d
						best_o = o
		if best_o:
			var g: float = best - (best_o.length + v.length) * 0.5
			if g < gap:
				gap = g
				lead_speed = best_o.speed
				reason = TrafficVehicle.Reason.LEADER
				who = best_o
			break
		base += l.length

	var leader_gap := gap
	var leader_speed := lead_speed

	# 2. Stop lines: red lights, closed level crossings, bus stops.
	base = -v.s - v.length * 0.5
	var stop_found := false
	for i in v.route.size():
		var l: TrafficGraph.Lane = v.route[i]
		if base > 90.0 or stop_found:
			break
		for st in l.stops:
			var d: float = base + st.s
			if d < -0.3:
				continue
			if d > 90.0:
				break
			var gate: TrafficGraph.Gate = st.gate
			var halt := false
			if gate.buses_only():
				if v.is_bus and not v.served.has(gate):
					halt = true
					if d < 1.5 and v.speed < 0.4:
						v.dwell += dt
						if v.dwell > 9.0:
							v.served[gate] = true
							v.dwell = 0.0
							halt = false
			else:
				var state := gate.state()
				if state == TrafficGraph.Gate.STOP:
					# Already on the line at speed: too late to stop, carry on.
					halt = not (d < 0.6 and v.speed > 3.0)
				elif state == TrafficGraph.Gate.AMBER:
					halt = v.speed * v.speed / (2.0 * maxf(d, 0.1)) < 3.5
				elif gate is TrafficGraph.LevelCrossing and d > 0.5:
					# Never stop on the tracks: wait until there's room past them.
					halt = leader_gap < d + 14.0 + v.length and leader_speed < 3.0
			if halt:
				var g := d + 1.4
				if g < gap:
					gap = g
					lead_speed = 0.0
					reason = TrafficVehicle.Reason.STOP_LINE
					who = gate
				stop_found = true
				break
		base += l.length

	# 3. Junctions: give way, stop signs, and don't enter while someone is
	# crossing our path or there's no room on the far side.
	base = -v.s - v.length * 0.5
	for i in v.route.size():
		var l: TrafficGraph.Lane = v.route[i]
		if base > 45.0:
			break
		if l.connector and i > 0 and l.node.degree() == 2:
			# Just a bend in the road, unless a lane ends here: then merge in
			# turn with the car alongside.
			if not l.conflicts.is_empty() and not v.commits.has(l) and base < 40.0:
				if _merge_turn(l, v, base):
					if base < 10.0:
						v.commits.append(l)
				else:
					var g := base + 1.2
					if g < gap:
						gap = g
						lead_speed = 0.0
						reason = TrafficVehicle.Reason.YIELD
						who = l
			base += l.length
			continue
		if l.connector and i > 0:
			if not v.commits.has(l):
				var d := base
				var ready := true
				if l.full_stop:
					if d < 2.0 and v.speed < 0.3:
						v.stop_sign_wait += dt
					ready = v.stop_sign_wait > 1.0
				# After a long wait at a give-way, edge out anyway (but never
				# into a junction someone is crossing).
				var chain := _junction_chain(v, i)
				var clear := true
				var has_priority := not l.full_stop
				for c in chain:
					clear = clear and (_junction_clear(c, v) or v.yield_wait > 12.0) and _junction_free(c, v)
					has_priority = has_priority and c.yield_to.is_empty()
				# Two lanes joining into one: take turns, even on the through road.
				clear = clear and _merge_turn(l, v, d)
				if clear and ready:
					if d < maxf(8.0, v.speed * v.speed / 4.0 + 4.0):
						v.cleared = l
						v.commits = chain
				elif has_priority and _merge_turn(l, v, d) and v.speed * v.speed / (2.0 * maxf(d, 0.1)) > 4.0:
					pass  # Too late to stop nicely; the path check slows us if needed.
				else:
					var g := d + 1.2
					if g < gap:
						gap = g
						lead_speed = 0.0
						reason = TrafficVehicle.Reason.YIELD
						who = l
					if v.speed < 0.3 and d < 4.0:
						v.yield_wait += dt
			break
		base += l.length

	# 4. Anything physically in our path: the player, people, other traffic
	# (crossing paths at junctions). Refreshed a few times a second.
	v.obstacle_timer -= dt
	if v.obstacle_timer <= 0.0:
		v.obstacle_timer = 0.08 + _rng.randf() * 0.04
		_scan_obstacles(v)
	elif v.obstacle_gap < INF:
		v.obstacle_gap -= (v.speed - v.obstacle_speed) * dt
	if v.obstacle_gap < gap:
		gap = v.obstacle_gap
		lead_speed = v.obstacle_speed
		reason = v.obstacle_reason
		who = v.obstacle_who

	# Intelligent driver model.
	var ratio := v.speed / maxf(v0, 0.5)
	var a := a_max * (1.0 - ratio * ratio * ratio * ratio)
	if gap < INF:
		var dv := v.speed - lead_speed
		var s_star := 2.2 + maxf(0.0, v.speed * headway + v.speed * dv / (2.0 * sqrt(a_max * b_comf)))
		var q := s_star / maxf(gap, 0.2)
		a -= a_max * q * q
	if v.hazard_time > 5.0:
		a = -6.0  # Just got bumped: stop and put the hazards on.
	a = clampf(a, -9.0, a_max)

	v.reason = reason
	v.blocked_by = who if v.speed < 1.0 else null
	if v.speed < 0.2:
		v.stopped_time += dt
	else:
		v.stopped_time = 0.0
	if reason != TrafficVehicle.Reason.YIELD:
		v.yield_wait = 0.0

	v.accel = a
	v.speed = maxf(v.speed + a * dt, 0.0)
	v.s += v.speed * dt
	_advance(v)
	_maybe_change_lane(v, dt, v0, gap, lead_speed)
	_react_to_player(v, dt)


## The connector at route[i], plus any junctions straight after it that are
## joined by a link too short to wait on (dual carriageways, split
## intersections): those are only entered when all of them are clear.
func _junction_chain(v: TrafficVehicle, i: int) -> Array:
	var chain: Array = [v.route[i]]
	var room := 0.0
	for k in range(i + 1, v.route.size()):
		var l: TrafficGraph.Lane = v.route[k]
		if l.connector and l.node.degree() != 2:
			var gate: TrafficGraph.SignalGate = l.in_lane.signal_gate
			var first_gate: TrafficGraph.SignalGate = chain[0].in_lane.signal_gate
			if gate != null and (first_gate == null or gate.controller != first_gate.controller):
				break  # Its own set of lights: stop for those separately.
			chain.append(l)
			room = 0.0
			if chain.size() >= 4:
				break
		else:
			room += l.length
			if room >= v.length + 6.0:
				break
	return chain


## Zip merge where a lane ends: whoever is nearer the merge goes first.
func _merge_turn(c: TrafficGraph.Lane, v: TrafficVehicle, d: float) -> bool:
	for other in c.conflicts:
		if other.next[0] != c.next[0]:
			continue
		for o in other.vehicles:
			if o != v and o.s < o.length + 2.0:
				return false
		for o in other.in_lane.vehicles:
			if o == v:
				continue
			if o.commits.has(other):
				return false
			var rem: float = other.in_lane.length - o.s - o.length * 0.5
			if rem < d - 0.5 or (absf(rem - d) <= 0.5 and o.id < v.id):
				return false
	return true


## Has everyone we must give way to cleared off (or stopped)?
func _junction_clear(c: TrafficGraph.Lane, v: TrafficVehicle) -> bool:
	for l in c.yield_to:
		# Merging into their lane (a slip road or on-ramp) needs a smaller gap
		# than crossing their path.
		var merge := false
		for other in l.next:
			if other.next[0] == c.next[0]:
				merge = true
		var window := 2.5 if merge else 6.0
		for o in l.vehicles:
			if o == v:
				continue
			if o.cleared != null and o.cleared.in_lane == l:
				return false  # Committed to go.
			var rem: float = l.length - o.s
			if rem > 110.0:
				continue
			if o.speed < 0.5 and rem < 14.0:
				continue  # Waiting at the line themselves.
			if rem / maxf(o.speed, 0.1) < window:
				return false
		# Anyone already in the junction from a priority lane.
		for conn in l.next:
			for o in conn.vehicles:
				if o != v:
					return false
	return true


## Nobody on a crossing path inside the junction, and room to get out.
func _junction_free(c: TrafficGraph.Lane, v: TrafficVehicle) -> bool:
	# Someone crawling through the same move: the junction is backed up.
	for o in c.vehicles:
		if o != v and o.speed < 2.0:
			return false
	for other in c.conflicts:
		for o in other.vehicles:
			if o != v:
				return false
		# Just out of the junction but the tail is still in it.
		for o in other.next[0].vehicles:
			if o != v and o.prev_lane == other and o.s < o.length * 0.5 + 1.5:
				return false
		# Someone about to enter that crossing path has already committed.
		for o in other.in_lane.vehicles:
			if o != v and o.commits.has(other):
				return false
	var out: TrafficGraph.Lane = c.next[0]
	for o in out.vehicles:
		if o != v and o.s < (o.length + v.length) * 0.5 + 2.0 and o.speed < 2.0:
			return false
	return true


func _scan_obstacles(v: TrafficVehicle) -> void:
	v.obstacle_gap = INF
	v.obstacle_speed = 0.0
	v.obstacle_reason = TrafficVehicle.Reason.NONE
	v.obstacle_who = null
	var look := clampf(v.speed * 2.6 + 10.0, 12.0, 38.0)
	var candidates := _agents_near(v.position, look + v.length)
	if candidates.size() <= 1:
		return
	var samples: Array = []
	var d := 0.5
	var start: float = v.s + v.length * 0.5
	while d <= look:
		var p := _route_point(v, start + d)
		samples.append([d, p])
		d += 2.0
	for o in candidates:
		if o == v:
			continue
		var rel: Vector3 = o.position - v.position
		var along: float = rel.dot(v.forward)
		if along < 0.0 or rel.length_squared() > (look + 12.0) * (look + 12.0):
			continue
		var is_vehicle: bool = o is TrafficVehicle
		if is_vehicle:
			# Two cars blocking each other: the lower id goes first.
			if o.blocked_by == v and v.id < o.id:
				continue
		var of: Vector3 = o.forward
		var ol := TrafficGraph.left_of(of)
		var hl: float = o.length * 0.5 + 0.4
		var hw: float = o.width * 0.5 + v.width * 0.5 + 0.25
		for smp in samples:
			var lp: Vector3 = smp[1] - o.position
			if absf(lp.y) < 3.0 and absf(lp.dot(of)) < hl and absf(lp.dot(ol)) < hw:
				var gap: float = smp[0] - 1.0
				if gap < v.obstacle_gap:
					v.obstacle_gap = gap
					v.obstacle_who = o
					if o == _player_proxy:
						v.obstacle_speed = _player_proxy.velocity.dot(v.forward)
						v.obstacle_reason = TrafficVehicle.Reason.PLAYER
					elif o is TrafficPedestrian:
						v.obstacle_speed = 0.0
						v.obstacle_reason = TrafficVehicle.Reason.PEDESTRIAN
					else:
						v.obstacle_speed = o.forward.dot(v.forward) * o.speed
						v.obstacle_reason = TrafficVehicle.Reason.OBSTACLE
				break


func _advance(v: TrafficVehicle) -> void:
	while v.s > v.route[0].length:
		if v.route.size() < 2:
			_extend_route(v)
		if v.route.size() < 2:
			# End of the known network: wait here until out of sight.
			v.s = v.route[0].length
			v.speed = 0.0
			v.stopped_time = 999.0
			return
		var old: TrafficGraph.Lane = v.route[0]
		var nxt: TrafficGraph.Lane = v.route[1]
		if old.signal_gate and nxt.connector:
			var gate := old.signal_gate
			if gate.state() == TrafficGraph.Gate.STOP and gate.controller.timer > 1.0 and gate.controller.phase % 3 != 1:
				stats.red_runs += 1
		v.s -= old.length
		_finish_lane_change(v)
		_leave_lane(v, old)
		v.prev_lane = v.route.pop_front()
		_enter_lane(v, v.route[0])
		v.stop_sign_wait = 0.0
		v.yield_wait = 0.0
		if old.connector:
			v.commits.erase(old)
		if not v.route[0].connector:
			v.served.clear()
			if v.commits.is_empty():
				v.cleared = null
		_extend_route(v)


func _extend_route(v: TrafficVehicle) -> void:
	var ahead: float = v.route[0].length - v.s
	for i in range(1, v.route.size()):
		ahead += v.route[i].length
	while ahead < 130.0 and v.route.size() < 14:
		var last: TrafficGraph.Lane = v.route[v.route.size() - 1]
		if last.next.is_empty():
			return
		var nxt := _choose_next(v, last)
		v.route.append(nxt)
		ahead += nxt.length


func _choose_next(v: TrafficVehicle, lane: TrafficGraph.Lane) -> TrafficGraph.Lane:
	if lane.next.size() == 1:
		return lane.next[0]
	var weights: Array = []
	var total := 0.0
	var open_road := false
	for c in lane.next:
		if graph.reach(c) >= TrafficGraph.REACH:
			open_road = true
	for c in lane.next:
		var w := 1.0
		if open_road and graph.reach(c) < TrafficGraph.REACH:
			weights.append(0.0)
			continue  # Don't turn into a dead end when there's another way.
		match c.turn:
			TrafficGraph.Turn.STRAIGHT: w = 4.0
			TrafficGraph.Turn.LEFT: w = 2.0
			TrafficGraph.Turn.RIGHT: w = 1.6
			TrafficGraph.Turn.UTURN: w = 0.05
		var out: TrafficGraph.Lane = c.next[0]
		var rank: int = out.road.rank if out.road else 2
		w *= 1.0 + rank * 0.15
		if v.is_bus:
			w *= 4.0 if rank >= 3 else 0.3
		weights.append(w)
		total += w
	var r := _rng.randf() * total
	for i in lane.next.size():
		r -= weights[i]
		if r <= 0.0:
			return lane.next[i]
	return lane.next[lane.next.size() - 1]


func _enter_lane(v: TrafficVehicle, lane: TrafficGraph.Lane) -> void:
	lane.vehicles.append(v)


func _leave_lane(v: TrafficVehicle, lane: TrafficGraph.Lane) -> void:
	lane.vehicles.erase(v)


## Overtake slow traffic on multi-lane roads (on the right, as in Australia,
## or move left when the right lane is blocked).
func _maybe_change_lane(v: TrafficVehicle, dt: float, v0: float, gap: float, lead_speed: float) -> void:
	if v.change_from:
		v.change_t += dt / 2.4
		if v.change_t >= 1.0:
			_finish_lane_change(v)
		return
	v.change_cooldown -= dt
	if v.change_cooldown > 0.0:
		return
	v.change_cooldown = 1.0 + _rng.randf()
	var lane: TrafficGraph.Lane = v.route[0]
	if lane.connector or (lane.left_lane == null and lane.right_lane == null):
		return
	if v.to_lane_end() < 40.0 or v.is_bus and v.reason != TrafficVehicle.Reason.PLAYER:
		return
	var slow_leader := gap < 30.0 and lead_speed < v0 * 0.6 and v.reason in [
		TrafficVehicle.Reason.LEADER, TrafficVehicle.Reason.PLAYER, TrafficVehicle.Reason.OBSTACLE]
	if not slow_leader:
		return
	for cand in [lane.right_lane, lane.left_lane]:
		if cand == null:
			continue
		var s_new: float = v.s * cand.length / maxf(lane.length, 0.1)
		if not _lane_has_room(cand, s_new, v):
			continue
		v.change_from = lane
		v.change_t = 0.0
		v.indicator = 1 if cand == lane.right_lane else -1
		v.route = [cand]
		v.s = s_new
		_enter_lane(v, cand)
		_extend_route(v)
		return


func _lane_has_room(lane: TrafficGraph.Lane, s: float, v: TrafficVehicle) -> bool:
	for o in lane.vehicles:
		var d: float = o.s - s
		if d > -(10.0 + o.length * 0.5) and d < 14.0 + o.length * 0.5:
			return false
		if d < 0.0 and d > -30.0 and o.speed > v.speed + 3.0:
			return false
	return true


func _finish_lane_change(v: TrafficVehicle) -> void:
	if v.change_from:
		_leave_lane(v, v.change_from)
		v.change_from = null
		v.change_t = 1.0
		v.indicator = 0


func _react_to_player(v: TrafficVehicle, dt: float) -> void:
	v.horn_cooldown -= dt
	v.hazard_time = maxf(v.hazard_time - dt, 0.0)
	v.flash_time = maxf(v.flash_time - dt, 0.0)
	if v.horn_time > 0.0:
		v.horn_time -= dt
		if v.horn_time <= 0.0 and v.horn:
			v.horn.stop()
	v.lateral_target = 0.0
	if not _player_proxy.present:
		v.lateral = move_toward(v.lateral, 0.0, dt)
		return
	var rel := _player_proxy.position - v.position
	var dist := rel.length()
	if dist < 50.0:
		# Head-on: the player is on our side of the road coming at us.
		var along := rel.dot(v.forward)
		var side := rel.dot(TrafficGraph.left_of(v.forward))
		if along > 4.0 and absf(side) < 2.6 and _player_proxy.forward.dot(v.forward) < -0.6 and _player_proxy.speed > 3.0:
			v.lateral_target = 1.1 if side <= 0.3 else -0.6
			if v.horn_cooldown <= 0.0 and along < 40.0:
				v.flash_time = 1.2
				_sound_horn(v, 1.2)
		# Stuck behind (or blocked by) the player.
		elif v.reason == TrafficVehicle.Reason.PLAYER and v.speed < 0.5 and v.stopped_time > 2.5:
			if v.horn_cooldown <= 0.0:
				_sound_horn(v, 0.3 if _rng.randf() < 0.6 else 0.9)
	v.lateral = move_toward(v.lateral, v.lateral_target, dt * 1.4)


func _sound_horn(v: TrafficVehicle, duration: float) -> void:
	v.horn_cooldown = _rng.randf_range(5.0, 9.0)
	v.horn_time = duration
	if v.horn:
		v.horn.play()
	horn.emit(v.body, duration, v.is_bus)


func _on_player_impact(strength: float) -> void:
	if strength < 1.5 or not _player_proxy.present:
		return
	for v in _agents_near(_player_proxy.position, 8.0):
		if v is TrafficVehicle and v.position.distance_to(_player_proxy.position) < (v.length + 4.0) * 0.6:
			v.hazard_time = 9.0
			v.horn_cooldown = 0.0
			_sound_horn(v, 1.3)


# --- Placing vehicles and their lights ----------------------------------------

func _route_point(v: TrafficVehicle, s: float) -> Vector3:
	if s < 0.0:
		if v.prev_lane:
			return v.prev_lane.point(maxf(v.prev_lane.length + s, 0.0))
		var l0: TrafficGraph.Lane = v.route[0]
		return l0.point(0.0) + l0.tangent(0.0) * s
	for l in v.route:
		if s <= l.length:
			return l.point(s)
		s -= l.length
	var last: TrafficGraph.Lane = v.route[v.route.size() - 1]
	return last.point(last.length) + last.tangent(last.length) * s


func _place(v: TrafficVehicle, dt: float, lights_on: bool) -> void:
	var lane: TrafficGraph.Lane = v.route[0]
	var p := lane.point(v.s)
	if v.change_from:
		var old: TrafficGraph.Lane = v.change_from
		var po := old.point(v.s * old.length / maxf(lane.length, 0.1))
		p = po.lerp(p, smoothstep(0.0, 1.0, v.change_t))
	var wb := v.length * 0.3
	var dir := _route_point(v, v.s + wb) - _route_point(v, v.s - wb)
	if dir.length_squared() < 0.0001:
		dir = lane.tangent(v.s)
	dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if flat == Vector3.ZERO:
		flat = v.forward
	p += TrafficGraph.left_of(flat) * v.lateral
	v.position = p
	v.forward = flat
	var basis := Basis.looking_at(dir, Vector3.UP)
	v.body.global_transform = Transform3D(basis, p)

	# Indicators for the next turn.
	if not v.change_from:
		v.indicator = 0
		var base: float = lane.length - v.s
		if lane.connector:
			base = 0.0
			v.indicator = _turn_indicator(lane.turn)
		else:
			for i in range(1, v.route.size()):
				if base > 35.0:
					break
				var l: TrafficGraph.Lane = v.route[i]
				if l.connector:
					v.indicator = _turn_indicator(l.turn)
					break
				base += l.length
	var blink := int(_time * 2.6) % 2 == 0
	var key := 0
	if lights_on or (v.flash_time > 0.0 and blink):
		key |= 1
	if v.is_braking():
		key |= 2
	var hazard := v.hazard_time > 0.0
	if blink and (v.indicator < 0 or hazard):
		key |= 4
	if blink and (v.indicator > 0 or hazard):
		key |= 8
	if key != v.lights_key:
		_apply_lights(v, key)


func _update_beams(dt: float, lights_on: bool) -> void:
	if _beams.is_empty():
		for i in HEADLIGHT_BEAMS:
			var beam := SpotLight3D.new()
			beam.light_color = Color(1.0, 0.93, 0.78)
			beam.light_energy = 3.0
			beam.spot_range = 28.0
			beam.spot_angle = 32.0
			beam.spot_attenuation = 1.2
			beam.shadow_enabled = false
			beam.visible = false
			add_child(beam)
			_beams.append(beam)
			_beam_owners.append(null)
	_beam_timer -= dt
	if _beam_timer <= 0.0:
		_beam_timer = 0.5
		var near: Array = []
		if lights_on and _camera:
			var eye := _camera.global_position
			for v in vehicles:
				var d: float = v.position.distance_squared_to(eye)
				if d < 110.0 * 110.0:
					near.append([d, v])
			near.sort_custom(func(a, b): return a[0] < b[0])
		for i in _beams.size():
			_beam_owners[i] = near[i][1] if i < near.size() else null
	for i in _beams.size():
		var v: TrafficVehicle = _beam_owners[i]
		var beam: SpotLight3D = _beams[i]
		beam.visible = v != null and v.active
		if beam.visible:
			beam.global_transform = v.body.global_transform * Transform3D(Basis(Vector3.RIGHT, -0.14), Vector3(0, 0.8, -v.length * 0.5 - 0.2))


func _turn_indicator(turn: int) -> int:
	match turn:
		TrafficGraph.Turn.LEFT: return -1
		TrafficGraph.Turn.RIGHT, TrafficGraph.Turn.UTURN: return 1
	return 0


func _apply_lights(v: TrafficVehicle, key: int) -> void:
	var changed := key ^ v.lights_key if v.lights_key >= 0 else 0xFF
	v.lights_key = key
	var m := v.mesh
	if changed & 1:
		var on := (key & 1) != 0
		m.set_surface_override_material(TrafficModels.Surf.HEAD, TrafficModels.material(Color(1.0, 0.95, 0.8), 3.0) if on else TrafficModels.material(Color(0.8, 0.8, 0.75)))
	if changed & 3:
		var tail: Material
		if key & 2:
			tail = TrafficModels.material(Color(1.0, 0.1, 0.05), 3.0)
		elif key & 1:
			tail = TrafficModels.material(Color(0.8, 0.05, 0.03), 1.2)
		else:
			tail = TrafficModels.material(Color(0.45, 0.05, 0.04))
		m.set_surface_override_material(TrafficModels.Surf.TAIL, tail)
	var amber_on := TrafficModels.material(Color(1.0, 0.55, 0.05), 3.0)
	var amber_off := TrafficModels.material(Color(0.55, 0.35, 0.1))
	if changed & 4:
		m.set_surface_override_material(TrafficModels.Surf.IND_L, amber_on if key & 4 else amber_off)
	if changed & 8:
		m.set_surface_override_material(TrafficModels.Surf.IND_R, amber_on if key & 8 else amber_off)


# --- Spawning and pooling -----------------------------------------------------

func _manage_population() -> void:
	var focus := focus_position()
	_density_timer -= SPAWN_INTERVAL
	if _density_timer <= 0.0 or _lane_km_cache == 0.0:
		_density_timer = 1.0
		_lane_km_cache = _count_samples(graph.lane_cells(), focus, spawn_radius) * TrafficGraph.SAMPLE_STEP / 1000.0
		_foot_km_cache = _count_samples(graph.ped_cells(), focus, ped_spawn_radius) * 8.0 / 1000.0

	for v in vehicles.duplicate():
		var d: float = v.position.distance_to(focus)
		if d > despawn_radius or (v.stopped_time > 45.0 and d > 60.0 and not _visible(v.position)):
			_despawn_vehicle(v)
	var want := target_vehicles()
	var tries := mini(want - vehicles.size(), 6 if _warm > 0.0 else 3)
	for i in tries:
		_try_spawn_vehicle(focus)

	for p in pedestrians.duplicate():
		if p.position.distance_to(focus) > ped_despawn_radius:
			_despawn_ped(p)
	var want_peds := target_pedestrians()
	tries = mini(want_peds - pedestrians.size(), 8 if _warm > 0.0 else 3)
	for i in tries:
		_try_spawn_ped(focus)

	if trains_enabled and not graph.rail_edges.is_empty():
		_train_timer -= SPAWN_INTERVAL
		if _train_timer <= 0.0:
			_train_timer = _rng.randf_range(45.0, 110.0) / maxf(_curve(CAR_CURVE, GameClock.time_of_day), 0.3)
			var hour := GameClock.time_of_day
			if trains.size() < max_trains and not (hour > 0.5 and hour < 5.0):
				_try_spawn_train(focus)


func _count_samples(cells: Dictionary, focus: Vector3, radius: float) -> int:
	var n := 0
	for list in graph.samples_in_ring(cells, focus, 0.0, radius):
		for entry in list:
			var p: Vector3
			if entry[0] is TrafficGraph.Lane:
				p = entry[0].point(entry[1])
			else:
				p = TrafficGraph.point_at(entry[0].pts, entry[0].cum, entry[1])
			if p.distance_to(focus) <= radius:
				n += 1
	return n


func _pick_sample(cells: Dictionary, focus: Vector3, inner: float, outer: float) -> Array:
	var lists := graph.samples_in_ring(cells, focus, inner, outer)
	if lists.is_empty():
		return []
	var list: Array = lists[_rng.randi() % lists.size()]
	return list[_rng.randi() % list.size()]


func _try_spawn_vehicle(focus: Vector3) -> void:
	var inner := 25.0 if _warm > 0.0 else min_spawn_radius
	var entry := _pick_sample(graph.lane_cells(), focus, inner, spawn_radius)
	if entry.is_empty():
		return
	var lane: TrafficGraph.Lane = entry[0]
	var s: float = entry[1]
	if s > lane.length - minf(30.0, lane.length * 0.5):
		return  # Too close to the next junction.
	if graph.reach(lane) < TrafficGraph.REACH:
		return  # Heading into a dead end.
	var p := lane.point(s)
	var d := p.distance_to(focus)
	if d < inner or d > spawn_radius:
		return
	if _warm <= 0.0 and _visible(p) and d < 240.0:
		return
	var buses := vehicles.filter(func(o): return o.is_bus).size()
	var type: StringName = &"bus" if lane.road.rank >= 3 and buses < max_buses and _rng.randf() < 0.1 else _pick_type()
	var length: float = TrafficModels.TYPES[type].length
	for o in lane.vehicles:
		if absf(o.s - s) < (o.length + length) * 0.5 + 8.0:
			return
	for o in _agents_near(p, 10.0):
		if o.position.distance_to(p) < 8.0:
			return
	if _player_proxy.present and _player_proxy.position.distance_to(p) < 20.0:
		return
	_spawn_vehicle(type, lane, s)


func _pick_type() -> StringName:
	var total := 0.0
	for t in TrafficModels.TYPES:
		total += TrafficModels.TYPES[t].weight
	var r := _rng.randf() * total
	for t in TrafficModels.TYPES:
		r -= TrafficModels.TYPES[t].weight
		if r <= 0.0 and TrafficModels.TYPES[t].weight > 0.0:
			return t
	return &"sedan"


## Put a vehicle of `type` on `lane` at `s`. Returns it (for tests and scripts).
func spawn_vehicle_at(type: StringName, lane: TrafficGraph.Lane, s: float, speed := -1.0) -> TrafficVehicle:
	return _spawn_vehicle(type, lane, s, speed)


func _spawn_vehicle(type: StringName, lane: TrafficGraph.Lane, s: float, speed := -1.0) -> TrafficVehicle:
	var v: TrafficVehicle
	var pool: Array = _pool.get(type, [])
	if not pool.is_empty():
		v = pool.pop_back()
	else:
		v = _create_vehicle(type)
	v.active = true
	v.route = [lane]
	v.prev_lane = null
	v.s = s
	v.eagerness = _rng.randf_range(0.88, 1.1) if type != &"bus" else 0.9
	v.speed = lane.speed * 0.75 * v.eagerness if speed < 0.0 else speed
	v.accel = 0.0
	v.lifetime = 0.0
	v.stopped_time = 0.0
	v.yield_wait = 0.0
	v.stop_sign_wait = 0.0
	v.cleared = null
	v.commits = []
	v.served.clear()
	v.dwell = 0.0
	v.lateral = 0.0
	v.change_from = null
	v.change_t = 1.0
	v.change_cooldown = 2.0
	v.horn_time = 0.0
	v.horn_cooldown = 0.0
	v.hazard_time = 0.0
	v.flash_time = 0.0
	v.obstacle_gap = INF
	v.obstacle_timer = 0.0
	v.lights_key = -1
	v.forward = lane.tangent(s)
	v.position = lane.point(s)
	_paint(v)
	_enter_lane(v, lane)
	_extend_route(v)
	vehicles.append(v)
	v.body.visible = true
	_place(v, 0.0, _headlights_wanted())
	# Only collide once it's in place, or it would sweep through the world.
	v.body.collision_layer = TRAFFIC_LAYER
	stats.spawned += 1
	stats[type] = stats.get(type, 0) + 1
	vehicle_spawned.emit(v.body, type)
	return v


func _paint(v: TrafficVehicle) -> void:
	if v.is_bus:
		var cat := _rng.randf() < 0.3
		var livery: Color = TrafficModels.CAT_COLOURS[_rng.randi() % 4] if cat else TrafficModels.TRANSPERTH_GREEN
		v.mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(Color(0.93, 0.93, 0.92) if cat else TrafficModels.BUS_SILVER))
		v.mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(livery))
	else:
		v.paint = TrafficModels.pick_paint(_rng)
		v.mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(v.paint))


func _create_vehicle(type: StringName) -> TrafficVehicle:
	var info: Dictionary = TrafficModels.TYPES[type]
	var v := TrafficVehicle.new()
	v.id = _next_id
	_next_id += 1
	v.type = type
	v.is_bus = type == &"bus"
	v.length = info.length
	v.width = info.width
	var body := AnimatableBody3D.new()
	body.name = "%s_%d" % [type, v.id]
	body.position = Vector3(0, -500, 0)
	body.sync_to_physics = true
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
	mesh.visibility_range_end = 420.0
	body.add_child(mesh)
	v.mesh = mesh
	mesh.set_surface_override_material(TrafficModels.Surf.GLASS, TrafficModels.material(Color(0.07, 0.08, 0.1)))
	mesh.set_surface_override_material(TrafficModels.Surf.TYRES, TrafficModels.material(Color(0.05, 0.05, 0.05)))
	mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(Color(0.2, 0.2, 0.2)))
	var audio := Node3D.new()
	audio.name = "Audio"
	audio.position = Vector3(0, 0.8, -info.length * 0.35)
	body.add_child(audio)
	var horn_player := AudioStreamPlayer3D.new()
	horn_player.name = "Horn"
	horn_player.stream = _horn_bus if v.is_bus else _horn_car
	horn_player.bus = &"Vehicles"
	horn_player.unit_size = 14.0
	horn_player.max_distance = 180.0
	horn_player.volume_db = -4.0
	audio.add_child(horn_player)
	v.horn = horn_player
	v.body = body
	add_child(body)
	stats.created += 1
	return v


func _despawn_vehicle(v: TrafficVehicle) -> void:
	for l in v.route:
		_leave_lane(v, l)
	if v.change_from:
		_leave_lane(v, v.change_from)
		v.change_from = null
	v.route.clear()
	v.active = false
	v.body.visible = false
	v.body.collision_layer = 0
	v.body.global_position = Vector3(0, -500, 0)
	if v.horn:
		v.horn.stop()
	vehicles.erase(v)
	if not _pool.has(v.type):
		_pool[v.type] = []
	_pool[v.type].append(v)
	stats.despawned += 1
	vehicle_despawned.emit(v.body)


# --- People -------------------------------------------------------------------

func _try_spawn_ped(focus: Vector3) -> void:
	var inner := 8.0 if _warm > 0.0 else 35.0
	var entry := _pick_sample(graph.ped_cells(), focus, inner, ped_spawn_radius)
	if entry.is_empty():
		return
	var edge: TrafficGraph.PedEdge = entry[0]
	var s: float = entry[1]
	var p := TrafficGraph.point_at(edge.pts, edge.cum, s)
	var d := p.distance_to(focus)
	if d < inner or d > ped_spawn_radius:
		return
	if _warm <= 0.0 and _visible(p) and d < 110.0:
		return
	var ped: TrafficPedestrian = _ped_pool.pop_back() if not _ped_pool.is_empty() else _create_ped()
	ped.active = true
	ped.edge = edge
	ped.s = s
	ped.dir = 1 if _rng.randf() < 0.5 else -1
	ped.walk_speed = _rng.randf_range(1.1, 1.6)
	ped.speed = ped.walk_speed
	ped.side = _rng.randf_range(-0.7, 0.7)
	ped.dodge = 0.0
	ped.dodge_target = 0.0
	ped.waiting = false
	ped.wait_time = 0.0
	ped.has_umbrella = _rng.randf() < 0.75
	ped.node.visible = true
	pedestrians.append(ped)
	_place_ped(ped, 0.0)


func _create_ped() -> TrafficPedestrian:
	var ped := TrafficPedestrian.new()
	ped.node = TrafficModels.person(_rng)
	ped.node.name = "Person_%d" % _next_id
	_next_id += 1
	var body := ped.node.get_node("Body")
	ped.legs = [body.get_node("LegL"), body.get_node("LegR")]
	ped.arms = [body.get_node("ArmL"), body.get_node("ArmR")]
	ped.umbrella = body.get_node("Umbrella")
	add_child(ped.node)
	stats.peds_created += 1
	return ped


func _despawn_ped(ped: TrafficPedestrian) -> void:
	ped.active = false
	ped.node.visible = false
	pedestrians.erase(ped)
	_ped_pool.append(ped)


func _update_peds(dt: float) -> void:
	var raining := Weather.rain > 0.25
	for ped in pedestrians:
		_walk(ped, dt)
		_place_ped(ped, dt)
		ped.umbrella.visible = raining and ped.has_umbrella


func _walk(ped: TrafficPedestrian, dt: float) -> void:
	ped.startle_cooldown -= dt
	if ped.waiting:
		ped.speed = 0.0
		ped.wait_time += dt
		if _crossing_safe(ped.edge):
			ped.waiting = false
		elif ped.wait_time > 30.0:
			# Give up and walk back the other way.
			ped.waiting = false
			ped.dir = -ped.dir
		else:
			return
	ped.speed = move_toward(ped.speed, ped.walk_speed * (1.4 if ped.edge.crossing else 1.0) + absf(ped.dodge_target) * 0.6, dt * 2.0)
	ped.s += ped.dir * ped.speed * dt
	var edge := ped.edge
	if ped.s > edge.length or ped.s < 0.0:
		var at_node: TrafficGraph.PedNode = edge.b if ped.s > edge.length else edge.a
		var options: Array = at_node.edges.filter(func(e): return e != edge)
		if options.is_empty():
			options = [edge]
		var weights: Array = options.map(func(e): return 1.0 if e.crossing else 2.5)
		var total := 0.0
		for w in weights:
			total += w
		var r := _rng.randf() * total
		var nxt: TrafficGraph.PedEdge = options[options.size() - 1]
		for i in options.size():
			r -= weights[i]
			if r <= 0.0:
				nxt = options[i]
				break
		ped.edge = nxt
		if nxt.a == at_node:
			ped.dir = 1
			ped.s = 0.0
		else:
			ped.dir = -1
			ped.s = nxt.length
		if nxt.crossing:
			ped.waiting = true
			ped.wait_time = 0.0
			ped.side = 0.0

	# Jump out of the way of a fast car heading for us.
	ped.dodge_target = move_toward(ped.dodge_target, 0.0, dt * 0.5)
	if _player_proxy.present and _player_proxy.speed > 4.0:
		var rel := ped.position - _player_proxy.position
		var ahead := rel.dot(_player_proxy.forward)
		var side := rel.dot(TrafficGraph.left_of(_player_proxy.forward))
		if ahead > 0.0 and ahead < 4.0 + _player_proxy.speed * 1.2 and absf(side) < 2.4:
			var away := TrafficGraph.left_of(ped.forward).dot(TrafficGraph.left_of(_player_proxy.forward) * signf(side if side != 0.0 else 1.0))
			ped.dodge_target = 2.4 * (1.0 if away >= 0.0 else -1.0)
			if ped.startle_cooldown <= 0.0:
				ped.startle_cooldown = 5.0
				pedestrian_startled.emit(ped.position)
	ped.dodge = move_toward(ped.dodge, ped.dodge_target, dt * 4.0)


func _crossing_safe(edge: TrafficGraph.PedEdge) -> bool:
	var road := edge.road
	var node := edge.node
	if road == null or node == null:
		return true
	var mid := TrafficGraph.point_at(edge.pts, edge.cum, edge.length * 0.5)
	if node.signal_controller:
		for lane in road.lanes_into(node):
			if lane.signal_gate and lane.signal_gate.state() != TrafficGraph.Gate.STOP:
				return false
	else:
		for lane in road.lanes_into(node):
			for o in lane.vehicles:
				var rem: float = lane.length - o.s
				if rem < 35.0 and o.speed > 0.5 and rem / o.speed < 6.0:
					return false
		for lane in road.lanes_from(node):
			for o in lane.vehicles:
				if o.s < 10.0:
					return false
	for o in _agents_near(mid, 12.0):
		if o is TrafficVehicle and o.speed > 0.8 and o.position.distance_to(mid) < 10.0:
			return false
	if _player_proxy.present and _player_proxy.speed > 2.0 and _player_proxy.position.distance_to(mid) < 18.0:
		return false
	return true


func _place_ped(ped: TrafficPedestrian, dt: float) -> void:
	var edge := ped.edge
	var p := TrafficGraph.point_at(edge.pts, edge.cum, ped.s)
	var fwd := TrafficGraph.tangent_at(edge.pts, edge.cum, ped.s) * ped.dir
	if fwd == Vector3.ZERO:
		fwd = ped.forward
	ped.forward = fwd
	p += TrafficGraph.left_of(fwd) * (ped.side + ped.dodge)
	ped.position = p
	ped.node.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
	ped.phase += ped.speed * dt * 4.4
	var swing := sin(ped.phase) * minf(ped.speed, 2.0) * 0.4
	ped.legs[0].rotation.x = swing
	ped.legs[1].rotation.x = -swing
	ped.arms[0].rotation.x = -swing * 0.8
	ped.arms[1].rotation.x = swing * 0.8 if not ped.umbrella.visible else -1.2


# --- Trains -------------------------------------------------------------------

func _try_spawn_train(focus: Vector3) -> void:
	for attempt in 6:
		var entry := _pick_sample(graph.rail_cells(), focus, train_spawn_min, train_spawn_max)
		if entry.is_empty():
			return
		var edge: TrafficGraph.RailEdge = entry[0]
		var s: float = entry[1]
		var p := TrafficGraph.point_at(edge.pts, edge.cum, s)
		var d := p.distance_to(focus)
		if d < train_spawn_min or d > train_spawn_max or _visible(p):
			continue
		if trains.any(func(t): return not is_nan(t.distance_of(edge, s))):
			continue
		var tangent := TrafficGraph.tangent_at(edge.pts, edge.cum, s)
		var fwd := tangent.dot(focus - p) > 0.0
		var dir := tangent if fwd else -tangent
		# Trains run on the left: if there's a parallel track to our left,
		# we're on the wrong one for this direction.
		if _rail_near(p + TrafficGraph.left_of(dir) * 4.0, edge) and not _rail_near(p - TrafficGraph.left_of(dir) * 4.0, edge):
			fwd = not fwd
		_spawn_train(edge, s, fwd)
		return


func _rail_near(p: Vector3, exclude: TrafficGraph.RailEdge) -> bool:
	for entry in graph.rail_samples_near(p, 30.0):
		var e: TrafficGraph.RailEdge = entry[0]
		if e == exclude:
			continue
		var s := TrafficGraph.closest_s(e.pts, e.cum, p)
		if TrafficGraph.point_at(e.pts, e.cum, s).distance_to(p) < 1.8:
			return true
	return false


## Start a train with its rear at `s` on `edge`, heading along the edge if `fwd`.
func spawn_train_at(edge: TrafficGraph.RailEdge, s: float, fwd: bool, cars := 0) -> TrafficTrain:
	return _spawn_train(edge, s, fwd, cars)


func _spawn_train(edge: TrafficGraph.RailEdge, s: float, fwd: bool, cars := 0) -> TrafficTrain:
	var train := TrafficTrain.new()
	var hour := GameClock.time_of_day
	var rush := (hour > 7.0 and hour < 9.5) or (hour > 16.0 and hour < 18.5)
	if cars <= 0:
		cars = 6 if rush else 3
	train.length = cars * TrafficModels.CARRIAGE_LENGTH + (cars - 1) * TrafficTrain.GAP
	var local := s if fwd else edge.length - s
	train.add_seg(edge, fwd, -local)
	train.front = train.length
	train.speed = TrafficTrain.MAX_SPEED * 0.8
	train.extend(400.0)
	train.root = Node3D.new()
	train.root.name = "Train"
	add_child(train.root)
	var white := TrafficModels.material(Color(0.93, 0.93, 0.92))
	var stripe := TrafficModels.material(Color(0.05, 0.3, 0.38))
	for i in cars:
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		body.position = Vector3(0, -500, 0)
		body.collision_layer = 0
		body.collision_mask = 0
		body.set_meta("surface", &"concrete")
		body.set_meta("traffic", &"train")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TrafficModels.CARRIAGE_WIDTH, 3.6, TrafficModels.CARRIAGE_LENGTH)
		shape.shape = box
		shape.position = Vector3(0, 2.2, 0)
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		# A cab at each end of every three-car set.
		mesh.mesh = TrafficModels.carriage_mesh(i % 3 == 0, i % 3 == 2 or i == cars - 1)
		mesh.visibility_range_end = 1200.0
		mesh.set_surface_override_material(TrafficModels.Surf.PAINT, white)
		mesh.set_surface_override_material(TrafficModels.Surf.GLASS, TrafficModels.material(Color(0.06, 0.07, 0.09)))
		mesh.set_surface_override_material(TrafficModels.Surf.TYRES, TrafficModels.material(Color(0.12, 0.12, 0.12)))
		mesh.set_surface_override_material(TrafficModels.Surf.HEAD, TrafficModels.material(Color(1.0, 0.95, 0.8), 3.0))
		mesh.set_surface_override_material(TrafficModels.Surf.TAIL, TrafficModels.material(Color(0.9, 0.08, 0.05), 2.0))
		mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, stripe)
		body.add_child(mesh)
		train.root.add_child(body)
		train.cars.append(body)
	trains.append(train)
	_place_train(train)
	for body in train.cars:
		body.collision_layer = TRAFFIC_LAYER
	stats.trains += 1
	train_spawned.emit(train.root)
	return train


func _update_trains(dt: float) -> void:
	var focus := focus_position()
	for train in trains.duplicate():
		var target: float = train.top_speed
		var stop_at: float = train.next_station_stop()
		var room: float = stop_at - train.front
		if room < INF:
			target = minf(target, sqrt(2.0 * TrafficTrain.BRAKE * maxf(room, 0.0)))
		if train.dead_end:
			target = minf(target, sqrt(2.0 * TrafficTrain.BRAKE * maxf(train.path_end() - train.front - 5.0, 0.0)))
		if train.dwell > 0.0:
			train.dwell -= dt
			target = 0.0
			if train.dwell <= 0.0:
				train.mark_served_near(train.front)
		elif room < 1.0 and train.speed < 0.5:
			train.dwell = TrafficTrain.DWELL
			train.speed = 0.0
		if train.speed < target:
			train.speed = minf(train.speed + TrafficTrain.ACCEL * dt, target)
		else:
			train.speed = maxf(train.speed - TrafficTrain.BRAKE * 2.0 * dt, target)
		train.front += train.speed * dt
		train.extend(400.0)
		train.trim()
		_place_train(train)
		var head: Vector3 = train.cars[0].global_position
		var tail: Vector3 = train.cars[train.cars.size() - 1].global_position
		var far := minf(head.distance_to(focus), tail.distance_to(focus)) > train_spawn_max + 250.0
		if far or (train.dead_end and train.speed < 0.1 and not _visible(head)):
			_despawn_train(train)


func _place_train(train: TrafficTrain) -> void:
	for i in train.cars.size():
		var center := train.front - TrafficModels.CARRIAGE_LENGTH * 0.5 - i * (TrafficModels.CARRIAGE_LENGTH + TrafficTrain.GAP)
		var a := train.point(center + 8.0)
		var b := train.point(center - 8.0)
		var dir := a - b
		if dir.length_squared() < 0.01:
			continue
		train.cars[i].global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (a + b) * 0.5)


func _despawn_train(train: TrafficTrain) -> void:
	trains.erase(train)
	train_despawned.emit(train.root)
	train.root.queue_free()


func _update_crossings(dt: float) -> void:
	for xing in graph.crossings:
		var closed := false
		for train in trains:
			var d: float = train.distance_of(xing.rail_edge, xing.rail_s)
			if not is_nan(d) and d > train.rear() - 12.0 and d < train.front + 260.0:
				closed = true
				break
		if closed != xing.closed:
			xing.closed = closed
			crossing_changed.emit(xing.pos, closed)
		xing.boom = move_toward(xing.boom, 1.0 if closed else 0.0, dt * 0.45)


# --- Street furniture ---------------------------------------------------------

func _build_props() -> void:
	for controller in graph.signal_controllers:
		if _signal_props.any(func(sp): return sp.controller == controller):
			continue
		var heads: Array = []
		for ap in controller.approaches:
			var lane: TrafficGraph.Lane = ap.lane
			if lane.k != lane.count - 1:
				continue  # One post per approach, on the kerb side.
			var end := lane.point(lane.length)
			var dir := lane.tangent(lane.length)
			var light := TrafficModels.traffic_light()
			light.position = end + TrafficGraph.left_of(dir) * (TrafficGraph.LANE_WIDTH * 0.5 + 1.0) + dir * 0.5
			light.basis = Basis(Vector3.UP.cross(dir), Vector3.UP, dir)
			_props_root.add_child(light)
			heads.append({ "node": light, "group": ap.group, "state": -1 })
		_signal_props.append({ "controller": controller, "heads": heads })

	for xing in graph.crossings:
		if _crossing_props.any(func(cp): return cp.crossing == xing):
			continue
		var gates: Array = []
		for road in xing.roads:
			var into: Dictionary = {}
			for lane in road.lanes:
				var s := TrafficGraph.closest_s(lane.pts, lane.cum, xing.pos) - 6.0
				if lane.k == lane.count - 1:
					into[lane] = s
			for lane in into.keys():
				var s: float = into[lane]
				var p: Vector3 = lane.point(maxf(s, 0.0))
				var dir: Vector3 = lane.tangent(maxf(s, 0.0))
				var right := -TrafficGraph.left_of(dir)
				var gate := TrafficModels.boom_gate(lane.count * TrafficGraph.LANE_WIDTH + 0.3)
				gate.position = p - right * (TrafficGraph.LANE_WIDTH * 0.5 + 0.7) + Vector3(0, 0, 0)
				gate.basis = Basis(right, Vector3.UP, right.cross(Vector3.UP))
				_props_root.add_child(gate)
				gates.append(gate)
		_crossing_props.append({ "crossing": xing, "gates": gates })

	for stop in graph.bus_stops:
		if _bus_stop_props.has(stop):
			continue
		var lane: TrafficGraph.Lane = stop.lane
		var dir := lane.tangent(stop.s)
		var sign := TrafficModels.bus_stop_sign()
		sign.position = lane.point(stop.s) + TrafficGraph.left_of(dir) * (TrafficGraph.LANE_WIDTH * 0.5 + 1.6) + dir * 4.0
		sign.basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).rotated(Vector3.UP, PI)
		_props_root.add_child(sign)
		_bus_stop_props[stop] = sign


func _update_props() -> void:
	for sp in _signal_props:
		var controller: TrafficGraph.SignalController = sp.controller
		for head in sp.heads:
			var state := controller.state_for(head.group)
			if state == head.state:
				continue
			head.state = state
			var node: Node3D = head.node
			var lit := [state == TrafficGraph.Gate.STOP, state == TrafficGraph.Gate.AMBER, state == TrafficGraph.Gate.GO]
			var names := ["Red", "Amber", "Green"]
			for i in 3:
				(node.get_node(names[i]) as MeshInstance3D).material_override = TrafficModels.lamp_material(i, lit[i])
	var flash := int(_time * 2.0) % 2
	for cp in _crossing_props:
		var xing: TrafficGraph.LevelCrossing = cp.crossing
		for gate in cp.gates:
			gate.get_node("Arm").rotation.z = lerpf(PI * 0.5, 0.0, smoothstep(0.0, 1.0, xing.boom))
			var on := xing.closed or xing.boom > 0.01
			(gate.get_node("LampL") as MeshInstance3D).material_override = TrafficModels.lamp_material(0, on and flash == 0)
			(gate.get_node("LampR") as MeshInstance3D).material_override = TrafficModels.lamp_material(0, on and flash == 1)


# --- Placeholder horn ---------------------------------------------------------

## A two-tone car horn, synthesised once. Sound can replace it per vehicle.
static func _make_horn(f1: float, f2: float, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(1.0, t / 0.015) * minf(1.0, (seconds - t) / 0.06)
		var x := 0.0
		for f in [f1, f2]:
			var ph: float = TAU * f * t
			x += sin(ph) + 0.33 * sin(3.0 * ph) + 0.18 * sin(5.0 * ph)
		x = clampf(x * 0.24 * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(x * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
