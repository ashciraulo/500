class_name TrafficEvents
extends Node3D
## Game days at Optus Stadium. Most weekends (and some Thursday and Friday
## nights) there's footy on, now and then a concert: for a couple of hours
## before the bounce, fans in their team's colours stream in from Perth
## Stadium station, across the Matagarup Bridge and from the car parks, extra
## trains and event buses run, and the roads round Burswood and the Graham
## Farmer Freeway fill up. You hear the crowd from across the river while the
## game's on, then it all goes the other way at the final siren.
##
## Fans are ordinary TrafficPedestrians with a route (TrafficManager
## .spawn_walker); the extra traffic comes from car_factor(), which the
## manager multiplies into its target.

## An event's phase has changed (for the HUD, radio and audio).
signal event_changed(event_name: String, phase: int)

enum Phase { NONE, ARRIVING, ON, LEAVING }

## Hours before the start the crowd builds over, and how long it lasts.
const ARRIVE_HOURS := 2.5
const FOOTY_HOURS := 2.9
const CONCERT_HOURS := 3.2
const LEAVE_HOURS := 1.2
## West Coast Eagles, Fremantle Dockers: [jumper, trim].
const TEAMS := {
	"Eagles": [Color(0.02, 0.18, 0.55), Color(0.98, 0.76, 0.08)],
	"Dockers": [Color(0.3, 0.1, 0.5), Color(0.95, 0.95, 0.95)],
}
const AWAY := ["Collingwood", "Richmond", "Sydney", "Geelong", "Carlton", "Brisbane", "Adelaide", "Port Adelaide",
	"Essendon", "Hawthorn", "Melbourne", "St Kilda", "North Melbourne", "Gold Coast", "GWS", "Western Bulldogs"]
const CONCERT_COLOURS := [Color(0.1, 0.1, 0.1), Color(0.9, 0.9, 0.9), Color(0.85, 0.2, 0.5), Color(0.2, 0.2, 0.25)]

@export var enabled := true
## The stadium (Optus Stadium on the Perth map) and how far out its gates are.
@export var stadium := Vector3(3324.0, 6.0, 567.0)
@export var gate_radius := 150.0
## The station the event trains run to.
@export var station_name := "Perth Stadium"
## How near the player has to be for the crowds (the traffic reaches further).
@export var crowd_radius := 1300.0
@export var traffic_radius := 2200.0
@export var max_fans := 70
## Tests: an event today regardless of the fixture list.
@export var force_event := false
@export var force_start := 19.0

var stats := { "fans": 0, "arrived": 0, "buses": 0 }
var phase := Phase.NONE
var today: Dictionary = {}
## Fans sent on their way by this module and still walking.
var fans: Array = []

var graph: TrafficGraph
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _bus_timer := 5.0
var _version := -1
var _rebuild_wait := 0.0
## [{ gate: PedNode, edge }]: footways into the stadium.
var _gates: Array = []
## PedNodes fans come from (and go back to).
var _origins: Array = []
var _station_node: TrafficGraph.PedNode
## { [from, to]: route } so the walks are only worked out once.
var _routes := {}
var _roar: AudioStreamPlayer3D
var _cheer_timer := 20.0
var _day := -1


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph
	_rng.randomize()
	# Only on the real map, unless a test puts a stadium somewhere.
	var world := manager.get_parent()
	if world == null or not world.has_node("PerthMap"):
		enabled = false
	if manager.has_signal(&"train_arrived"):
		manager.train_arrived.connect(_on_train_arrived)
	if manager.has_signal(&"walker_arrived"):
		manager.walker_arrived.connect(_on_walker_arrived)


func _clock() -> Node:
	return get_node("/root/GameClock")


## What's on at the stadium on `day` (day 1 is a Monday): { name, kind
## ("footy" or "concert"), start (hour), home, away, colours: [[jumper,
## trim], ...] }, or {} for nothing. The same every time for a given day.
func event_on(day: int) -> Dictionary:
	if force_event:
		return { "name": "Eagles v Dockers", "kind": "footy", "start": force_start, "home": "Eagles", "away": "Dockers",
			"colours": [TEAMS.Eagles, TEAMS.Dockers] }
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day * 7919 + 13)
	var weekday := posmod(day - 1, 7)
	var start := -1.0
	match weekday:
		3:  # Thursday night footy
			if rng.randf() < 0.2:
				start = 19.17
		4:  # Friday night
			if rng.randf() < 0.45:
				start = 19.67
		5:  # Saturday: arvo or twilight
			var r := rng.randf()
			if r < 0.3:
				start = 16.58
			elif r < 0.6:
				start = 19.17
			elif r < 0.68:
				return { "name": "Concert", "kind": "concert", "start": 19.5, "home": "", "away": "",
					"colours": [CONCERT_COLOURS] }
		6:  # Sunday arvo
			if rng.randf() < 0.45:
				start = 15.33 if rng.randf() < 0.6 else 12.67
	if start < 0.0:
		return {}
	var home: String = "Eagles" if rng.randf() < 0.5 else "Dockers"
	var away: String = AWAY[rng.randi() % AWAY.size()]
	var colours: Array = [TEAMS[home], TEAMS[home], TEAMS[home]]
	if rng.randf() < 0.12:
		away = "Dockers" if home == "Eagles" else "Eagles"
	if TEAMS.has(away):
		colours = [TEAMS[home], TEAMS[away]]  # A derby: both sides in force.
	return { "name": "%s v %s" % [home, away], "kind": "footy", "start": start, "home": home, "away": away,
		"colours": colours }


## Where today's event is at `hour`, and how big the crowd on the move is
## (0..1, peaking just before the start and just after the end).
func phase_at(event: Dictionary, hour: float) -> Array:
	if event.is_empty():
		return [Phase.NONE, 0.0]
	var start: float = event.start
	var end: float = start + (CONCERT_HOURS if event.kind == "concert" else FOOTY_HOURS)
	if hour >= start - ARRIVE_HOURS and hour < start:
		# Builds up to a peak half an hour before the start.
		var t := (hour - (start - ARRIVE_HOURS)) / (ARRIVE_HOURS - 0.5)
		return [Phase.ARRIVING, clampf(t, 0.15, 1.0) if hour < start - 0.5 else lerpf(1.0, 0.4, (hour - (start - 0.5)) / 0.5)]
	if hour >= start and hour < end:
		return [Phase.ON, 0.05]
	if hour >= end and hour < end + LEAVE_HOURS:
		# Everyone out at once, thinning over the hour.
		return [Phase.LEAVING, lerpf(1.0, 0.1, (hour - end) / LEAVE_HOURS)]
	return [Phase.NONE, 0.0]


## How much busier the roads around p are because of the event (1 = not at
## all). TrafficManager multiplies this into its traffic target.
func car_factor(p: Vector3) -> float:
	if not enabled or phase == Phase.NONE or phase == Phase.ON:
		return 1.0
	var d := Vector2(p.x - stadium.x, p.z - stadium.z).length()
	var w := clampf((traffic_radius - d) / (traffic_radius * 0.4), 0.0, 1.0)
	return 1.0 + 0.9 * w * _intensity()


## Trains run more often to the stadium around an event (divides the gap).
func train_factor(p: Vector3) -> float:
	if not enabled or phase == Phase.NONE or phase == Phase.ON:
		return 1.0
	var d := Vector2(p.x - stadium.x, p.z - stadium.z).length()
	return 2.5 if d < traffic_radius else 1.0


func _intensity() -> float:
	return phase_at(today, _clock().time_of_day)[1]


func update(delta: float, focus: Vector3) -> void:
	if graph == null or not enabled:
		return
	# Fans who've gone (or been taken back for the ordinary crowd).
	if not fans.is_empty():
		fans = fans.filter(func(f): return f.active and (f.leave_at_end > 0 or not f.route.is_empty()))
	_cheer_timer -= delta
	if phase == Phase.ON and _roar and _cheer_timer <= 0.0:
		_cheer_timer = _rng.randf_range(12.0, 40.0)
		_sound("traffic/traffic_crowd_cheer", stadium + Vector3(0, 20, 0), 6.0)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var clock := _clock()
	if clock.day != _day:
		_day = clock.day
		today = event_on(_day)
	var now: Array = phase_at(today, clock.time_of_day)
	if now[0] != phase:
		phase = now[0]
		event_changed.emit(today.get("name", ""), phase)
		_update_roar()
	# New tiles can replace footpaths: work the walks out again now and then.
	_rebuild_wait -= 1.0
	if graph.version != _version and _rebuild_wait <= 0.0:
		_version = graph.version
		_rebuild_wait = 30.0
		_routes.clear()
		_origins = []
	var near := Vector2(focus.x - stadium.x, focus.z - stadium.z).length() < crowd_radius
	if not near or (phase != Phase.ARRIVING and phase != Phase.LEAVING):
		return
	if _gates.is_empty() or _origins.is_empty():
		_build_walks()
	if _gates.is_empty() or _origins.is_empty():
		return
	var want := roundi(max_fans * now[1])
	for i in mini(want - fans.size(), 4):
		_send_fan(focus)
	_bus_timer -= 1.0
	if _bus_timer <= 0.0:
		_bus_timer = _rng.randf_range(12.0, 25.0)
		_send_bus(focus)


func clear() -> void:
	fans.clear()


# --- Fans ---------------------------------------------------------------------

## Footways from the nearest footpaths in to the gates, and where fans come
## from: the station, the far end of the Matagarup Bridge, and street corners
## out towards the car parks and bus stops.
func _build_walks() -> void:
	if _gates.is_empty():
		var dirs: Array = []
		for k in 6:
			var a := k * TAU / 6.0
			dirs.append(Vector3(sin(a), 0, cos(a)))
		for dir in dirs:
			var gate: Vector3 = stadium + dir * gate_radius
			var near := graph.ped_node_near(gate, gate_radius * 1.6)
			if near == null or Vector2(near.pos.x - stadium.x, near.pos.z - stadium.z).length() < gate_radius * 0.8:
				continue
			gate.y = near.pos.y
			var way := graph.add_footway(PackedVector3Array([near.pos, near.pos.lerp(gate, 0.5), gate]))
			if way:
				way.name = "Stadium gate"
				var gate_node: TrafficGraph.PedNode = way.b if way.b.pos.distance_to(gate) < 1.0 else way.a
				_gates.append({ "node": gate_node, "edge": way })
		# Perth Stadium station: a path from the platform to the nearest gate.
		for st in graph.stations:
			if station_name in str(st.name) and not _gates.is_empty():
				var best: Dictionary = _gates[0]
				for g in _gates:
					if g.node.pos.distance_to(st.pos) < best.node.pos.distance_to(st.pos):
						best = g
				var way := graph.add_footway(PackedVector3Array([st.pos, best.node.pos]))
				if way:
					way.name = "Stadium station path"
					_station_node = way.a if way.a.pos.distance_to(st.pos) < 1.0 else way.b
				break
	_origins = []
	if _station_node:
		_origins.append(_station_node)
	for edge in graph.ped_edges:
		if edge.name == "Matagarup Bridge":
			# The East Perth end.
			_origins.append(edge.a if edge.a.pos.distance_to(stadium) > edge.b.pos.distance_to(stadium) else edge.b)
	# Corners further out: car parks, buses, the walk from East Perth.
	var tries := 0
	while _origins.size() < 8 and tries < 60 and not graph.ped_nodes.is_empty():
		tries += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(gate_radius + 250.0, gate_radius + 800.0)
		var pn := graph.ped_node_near(stadium + Vector3(sin(a) * r, 0, cos(a) * r), 120.0)
		if pn and not _origins.has(pn) and not _route(pn, _gates[0].node).is_empty():
			_origins.append(pn)


func _route(from: TrafficGraph.PedNode, to: TrafficGraph.PedNode) -> Array:
	var key := [from, to]
	if not _routes.has(key):
		_routes[key] = graph.ped_path(from, to, 2500.0)
	return _routes[key]


## A fan on their way: in from an origin to a gate before the game, out from
## a gate to an origin after it. They start somewhere along the walk, out of
## the player's sight.
func _send_fan(focus: Vector3) -> void:
	var gate: Dictionary = _gates[_rng.randi() % _gates.size()]
	var origin: TrafficGraph.PedNode = _origins[_rng.randi() % _origins.size()]
	# Off the trains: half of them come from the station.
	if _station_node and _rng.randf() < 0.4:
		origin = _station_node
	var path := _route(origin, gate.node)
	if path.is_empty():
		return
	var arriving := phase == Phase.ARRIVING
	if not arriving:
		path = path.duplicate()
		path.reverse()
	# Start somewhere along the walk near the player (people further away
	# than that aren't simulated), out of sight.
	var start_node: TrafficGraph.PedNode = origin if arriving else gate.node
	var radius: float = _manager.ped_spawn_radius
	var spots: Array = []
	var from := start_node
	for i in path.size():
		var edge: TrafficGraph.PedEdge = path[i]
		var dir := 1 if edge.a == from else -1
		var along := 0.0
		while along < edge.length:
			var s := along if dir > 0 else edge.length - along
			var p := TrafficGraph.point_at(edge.pts, edge.cum, s)
			var d := p.distance_to(focus)
			if d > 25.0 and d < radius and not (_manager._visible(p) and d < 110.0):
				spots.append([i, s, dir])
			along += 15.0
		from = edge.other(from)
	if spots.is_empty():
		return
	var pick: Array = spots[_rng.randi() % spots.size()]
	var ped: TrafficPedestrian = _manager.spawn_walker(path.slice(pick[0]), pick[1], pick[2], 2 if arriving else 1)
	if ped:
		_dress(ped)
		ped.set_meta(&"fan", stats.fans)
		if not fans.has(ped):
			fans.append(ped)
		stats.fans += 1


## Team colours: the jumper (or a band tee for a concert) and a scarf.
func _dress(ped: TrafficPedestrian) -> void:
	var colours: Array = today.get("colours", [TEAMS.Eagles])
	var team: Array = colours[_rng.randi() % colours.size()]
	var body: Node3D = ped.node.get_node("Body")
	var jumper := TrafficModels.material(team[_rng.randi() % team.size()] if today.get("kind") == "concert" else team[0])
	(body.get_child(0) as MeshInstance3D).material_override = jumper
	for arm in ["ArmL", "ArmR"]:
		(body.get_node(arm).get_child(0) as MeshInstance3D).material_override = jumper
	var scarf: MeshInstance3D = body.get_node_or_null("Scarf")
	if scarf == null:
		scarf = TrafficModels._add_part(body, "scarf", Vector3(0.3, 0.08, 0.27), Vector3(0, 1.47, 0), Vector3.ZERO, jumper)
		scarf.name = "Scarf"
		scarf.visibility_range_end = 180.0
	scarf.material_override = TrafficModels.material(team[1] if team.size() > 1 else team[0])
	scarf.visible = today.get("kind") == "footy" and _rng.randf() < 0.6


func _on_walker_arrived(ped: TrafficPedestrian) -> void:
	if fans.has(ped):
		fans.erase(ped)
		stats.arrived += 1


func _on_train_arrived(position: Vector3) -> void:
	# A trainload off at the stadium: a rush up the path to the gates.
	if not enabled or phase != Phase.ARRIVING or _station_node == null:
		return
	if position.distance_to(_station_node.pos) > 250.0:
		return
	var focus: Vector3 = _manager.focus_position()
	for i in 10:
		if fans.size() < max_fans + 20:
			_send_fan(focus)


# --- Event buses and the crowd ---------------------------------------------------

## An event shuttle bus on a road near the stadium (out of sight).
func _send_bus(focus: Vector3) -> void:
	var samples: Array = graph.samples_near(stadium, 900.0)
	for attempt in 6:
		if samples.is_empty():
			return
		var entry: Array = samples[_rng.randi() % samples.size()]
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null or lane.road.rank < 2 or lane.length < 60.0:
			continue
		var s: float = entry[1]
		var p := lane.point(s)
		var d := p.distance_to(focus)
		if d < 120.0 or d > 600.0 or _manager._visible(p, 20.0):
			continue
		if s < 10.0 or s > lane.length - 20.0:
			continue
		var clear := true
		for o in lane.vehicles:
			if absf(o.s - s) < 20.0:
				clear = false
		if not clear:
			continue
		var bus = _manager.spawn_vehicle_at(&"bus", lane, s, minf(lane.limit() * 0.6, 8.0))
		if bus:
			stats.buses += 1
		return


## The crowd you hear from outside while the game's on.
func _update_roar() -> void:
	var on := phase == Phase.ON
	if not on:
		if _roar:
			_roar.stop()
		return
	var audio := get_node_or_null("/root/Audio")
	if audio == null or not audio.has_method("has") or not audio.has("traffic/traffic_crowd_roar_loop"):
		return
	if _roar == null:
		_roar = AudioStreamPlayer3D.new()
		_roar.name = "Crowd"
		_roar.stream = audio.stream("traffic/traffic_crowd_roar_loop", true)
		_roar.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		_roar.unit_size = 60.0
		_roar.max_distance = 1500.0
		_roar.volume_db = 4.0
		add_child(_roar)
	_roar.global_position = stadium + Vector3(0, 25, 0)
	_roar.play()


func _sound(sound_name: String, p: Vector3, db: float) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has(sound_name):
		audio.play_at(sound_name, p, db, "SFX")
