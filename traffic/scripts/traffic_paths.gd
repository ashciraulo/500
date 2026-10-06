class_name TrafficPaths
extends Node3D
## Life on the bike paths and shared paths (the map's "cycleways": the river
## foreshore, the freeway principal shared paths, Kings Park), run by
## TrafficManager: people out riding at an easy pace and joggers, most at the
## start and end of the day, a few through the middle, more at weekends, the
## odd jogger at night, nobody much in the rain. Everyone keeps left, swings
## out to pass someone slower, and stops short of the player on foot.

## Riders' and joggers' cruising speeds, m/s.
const RIDER_SPEED := Vector2(4.2, 6.8)
const JOG_SPEED := Vector2(2.3, 3.3)
## Path people per kilometre of path nearby at the busiest times.
const RIDERS_PER_KM := 7.0
const JOGGERS_PER_KM := 5.0

@export var enabled := true
## Tests: ignore the clock, the calendar and the weather.
@export var always_on := false
@export var radius := 230.0
@export var max_riders := 10
@export var max_joggers := 8


class Mover:
	var node: Node3D
	var rider := false
	var active := false
	var edge: TrafficGraph.PedEdge
	var s := 0.0
	var dir := 1
	var cruise := 3.0
	var speed := 0.0
	## Metres left of the path's centre line where they like to be (keep
	## left), and where they are now (out to the right when passing).
	var side := 0.8
	var lean := 0.0
	var passing := false
	var phase := 0.0
	var position := Vector3.ZERO
	var forward := Vector3.FORWARD
	var legs: Array = []
	var arms: Array = []


var movers: Array = []
var stats := { "riders": 0, "joggers": 0, "passes": 0 }

var graph: TrafficGraph
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _pools := { true: [], false: [] }


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph
	if manager.get("random_seed"):
		_rng.seed = hash([manager.random_seed, "paths"])
	else:
		_rng.randomize()


func _clock() -> Node:
	return get_node("/root/GameClock")


## How busy the paths are now, 0 to 1: [riders, joggers].
func busy() -> Vector2:
	if always_on:
		return Vector2.ONE
	var weather := get_node_or_null("/root/Weather")
	var wet: bool = weather != null and weather.rain > 0.3
	var c := _clock()
	var h: float = c.time_of_day
	var weekend: bool = _manager.is_weekend(c.day)
	var riders := 0.0
	var joggers := 0.0
	if h >= 5.5 and h < 9.0:
		riders = 1.0
		joggers = 1.0
	elif h >= 9.0 and h < 16.5:
		riders = 0.85 if weekend else 0.4
		joggers = 0.35
	elif h >= 16.5 and h < 19.5:
		riders = 0.8
		joggers = 1.0
	elif h >= 19.5 and h < 22.0:
		riders = 0.1
		joggers = 0.25
	else:
		joggers = 0.04
	if wet:
		riders *= 0.05
		joggers *= 0.15
	return Vector2(riders, joggers)


func update(delta: float, focus: Vector3) -> void:
	if graph == null:
		return
	for m in movers:
		_move(m, delta)
		_place(m, delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	_manage(focus)


func clear() -> void:
	for m in movers.duplicate():
		_despawn(m)


# --- Population ---------------------------------------------------------------

func _manage(focus: Vector3) -> void:
	for m in movers.duplicate():
		if m.position.distance_to(focus) > radius + 80.0 and not _manager._visible(m.position, 10.0):
			_despawn(m)
	if not enabled:
		return
	var samples := _path_samples(focus)
	if samples.is_empty():
		return
	var km := samples.size() * 8.0 / 1000.0
	var b := busy()
	var want_riders := mini(max_riders, int(round(km * RIDERS_PER_KM * b.x)))
	var want_joggers := mini(max_joggers, int(round(km * JOGGERS_PER_KM * b.y)))
	var riders := 0
	for m in movers:
		if m.rider:
			riders += 1
	var joggers := movers.size() - riders
	for attempt in 3:
		if riders < want_riders:
			if _try_spawn(samples, focus, true):
				riders += 1
		elif joggers < want_joggers:
			if _try_spawn(samples, focus, false):
				joggers += 1


## Bike path samples (PedEdge, s) within the radius.
func _path_samples(focus: Vector3) -> Array:
	var out: Array = []
	var cells: Dictionary = graph.ped_cells()
	var c := TrafficGraph.cell_of(focus)
	var n := int(ceil(radius / TrafficGraph.CELL))
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for entry in cells.get(c + Vector2i(dx, dz), []):
				if entry[0].cycle:
					out.append(entry)
	return out


func _try_spawn(samples: Array, focus: Vector3, rider: bool) -> bool:
	var entry: Array = samples[_rng.randi() % samples.size()]
	var edge: TrafficGraph.PedEdge = entry[0]
	var s: float = entry[1]
	var p := TrafficGraph.point_at(edge.pts, edge.cum, s)
	var d := p.distance_to(focus)
	if d > radius or (d < 40.0 and not always_on) or _manager._visible(p, 4.0):
		return false
	for m in movers:
		if m.position.distance_to(p) < 6.0:
			return false
	spawn(edge, s, 1 if _rng.randf() < 0.5 else -1, rider)
	return true


## Put someone on `edge` at `s`, heading `dir`. Returns them.
func spawn(edge: TrafficGraph.PedEdge, s: float, dir: int, rider: bool) -> Mover:
	var pool: Array = _pools[rider]
	var m: Mover = pool.pop_back() if not pool.is_empty() else _create(rider)
	m.active = true
	m.edge = edge
	m.s = s
	m.dir = dir
	m.cruise = _rng.randf_range(RIDER_SPEED.x, RIDER_SPEED.y) if rider else _rng.randf_range(JOG_SPEED.x, JOG_SPEED.y)
	m.speed = m.cruise
	m.side = _rng.randf_range(0.6, 1.0)
	m.lean = m.side
	m.passing = false
	m.node.visible = true
	if rider:
		var mesh: MeshInstance3D = m.node.get_node("Mesh")
		mesh.set_surface_override_material(TrafficModels.Surf.PAINT, TrafficModels.material(TrafficModels.pick_paint(_rng)))
		mesh.set_surface_override_material(TrafficModels.Surf.LIVERY, TrafficModels.material(TrafficModels.JERSEYS[_rng.randi() % TrafficModels.JERSEYS.size()]))
		stats.riders += 1
	else:
		stats.joggers += 1
	movers.append(m)
	_place(m, 0.0)
	return m


func _create(rider: bool) -> Mover:
	var m := Mover.new()
	m.rider = rider
	if rider:
		m.node = Node3D.new()
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = TrafficModels.vehicle_mesh(&"bike")
		mesh.visibility_range_end = 300.0
		m.node.add_child(mesh)
	else:
		m.node = TrafficModels.person(_rng)
		var body := m.node.get_node("Body")
		m.legs = [body.get_node("LegL"), body.get_node("LegR")]
		m.arms = [body.get_node("ArmL"), body.get_node("ArmR")]
		(body.get_node("Umbrella") as Node3D).visible = false
	m.node.name = ("PathRider" if rider else "Jogger")
	add_child(m.node)
	return m


func _despawn(m: Mover) -> void:
	m.active = false
	m.node.visible = false
	movers.erase(m)
	_pools[m.rider].append(m)


# --- Moving -------------------------------------------------------------------

func _move(m: Mover, dt: float) -> void:
	var want := m.cruise
	var passing := false
	# Someone slower ahead going our way: pull out and pass. Someone we
	# can't get round (the player standing on the path): stop short.
	for o in movers:
		if o == m:
			continue
		var rel: Vector3 = o.position - m.position
		var ahead := rel.dot(m.forward)
		if ahead < -2.5 or ahead > 9.0:
			continue
		var across := rel.dot(TrafficGraph.left_of(m.forward))
		var same_way: bool = o.forward.dot(m.forward) > 0.3
		# Where they are across the path, from its centre line.
		var their_line := across + m.lean
		if same_way and o.speed < m.cruise - 0.3 and absf(their_line - m.side) < 1.1:
			# In our line and slower: out and past, and stay out until
			# we're clear of them.
			passing = true
			if ahead > 0.0 and ahead < 2.5 and absf(across) < 0.8:
				want = minf(want, o.speed)  # Not out yet: sit behind.
		elif ahead > 0.0 and ahead < 3.0 and absf(across) < 0.8:
			want = minf(want, o.speed if same_way else 0.0)
	for proxy in [_manager._walker_proxy, _manager._player_proxy]:
		if not proxy.present:
			continue
		var rel: Vector3 = proxy.position - m.position
		var ahead := rel.dot(m.forward)
		if ahead > 0.0 and ahead < 7.0 and absf(rel.dot(TrafficGraph.left_of(m.forward))) < 1.3:
			want = 0.0 if ahead < 3.5 else want * 0.4
	if passing and not m.passing:
		stats.passes += 1
	m.passing = passing
	m.lean = move_toward(m.lean, -0.6 if passing else m.side, dt * 1.2)
	m.speed = move_toward(m.speed, want, dt * (2.5 if want < m.speed else 1.0))
	m.s += m.dir * m.speed * dt
	var edge := m.edge
	if m.s > edge.length or m.s < 0.0:
		var at_node: TrafficGraph.PedNode = edge.b if m.s > edge.length else edge.a
		var nxt := _next_edge(m, at_node)
		m.edge = nxt
		if nxt.a == at_node:
			m.dir = 1
			m.s = 0.0
		else:
			m.dir = -1
			m.s = nxt.length


## The way on at `node`: another bike path, mostly the straightest; back the
## way we came at a dead end.
func _next_edge(m: Mover, node: TrafficGraph.PedNode) -> TrafficGraph.PedEdge:
	var options: Array = node.edges.filter(func(e): return e != m.edge and e.cycle and not e.crossing)
	if options.is_empty():
		return m.edge
	var total := 0.0
	var weights: Array = []
	for e in options:
		var away: Vector3 = (e.pts[1] - e.pts[0]) if e.a == node else (e.pts[e.pts.size() - 2] - e.pts[e.pts.size() - 1])
		away.y = 0.0
		var straight := maxf(away.normalized().dot(m.forward), -0.5)
		var w := 0.15 + pow(straight + 0.5, 3.0)
		weights.append(w)
		total += w
	var r := _rng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[options.size() - 1]


func _place(m: Mover, dt: float) -> void:
	var edge := m.edge
	var p := TrafficGraph.point_at(edge.pts, edge.cum, m.s)
	var fwd := TrafficGraph.tangent_at(edge.pts, edge.cum, m.s) * m.dir
	if fwd == Vector3.ZERO:
		fwd = m.forward
	m.forward = fwd
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if flat == Vector3.ZERO:
		flat = Vector3.FORWARD
	p += TrafficGraph.left_of(flat) * m.lean
	m.position = p
	m.node.global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), p)
	if m.rider:
		return
	# Running: quicker, bigger strides, arms bent and pumping.
	m.phase += m.speed * dt * 3.2
	var swing := sin(m.phase) * 0.75 * clampf(m.speed / 2.5, 0.0, 1.0)
	m.legs[0].rotation.x = swing
	m.legs[1].rotation.x = -swing
	m.arms[0].rotation.x = -0.9 - swing * 0.6
	m.arms[1].rotation.x = -0.9 + swing * 0.6
