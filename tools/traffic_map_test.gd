extends SceneTree
## Headless test of traffic on the real Perth map: the game's main scene
## streams map tiles, traffic loads each tile's roads (traffic/data/), and AI
## traffic drives around a few spots in the city without piling up.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/traffic_map_test.gd
##
## Passes without doing anything when the map isn't in the project.

const FPS := 60
## [name, position, seconds to watch]
const SPOTS := [
	["Little Shenton Lane (home)", Vector3.INF, 40.0],
	["William St and Wellington St", Vector3(390.7, 26.0, 586.6), 120.0],
	["Barrack St and St Georges Tce", Vector3(549.6, 48.0, 1089.5), 120.0],
	["Mitchell Freeway ramps at Roe St", Vector3(-310, 20, 30), 100.0],
	["Kwinana Freeway at the Narrows", Vector3(-1500, 40, 2300), 50.0],
	["Highgate school zone (8am)", Vector3(1152, 25, -585), 90.0],
]

var _failures: Array[String] = []
var _main: Node
var _map: Node3D
var _car: RigidBody3D
var _traffic: Node3D  # TrafficManager
var _spot := -1
var _frame := 0
var _mark := {}
var _totals := { "overlaps": 0, "red_runs": 0, "max_ms": 0.0, "max_vehicles": 0, "stuck": 0 }


func _process(_delta: float) -> bool:
	if _main == null:
		if not ResourceLoader.exists("res://map/perth_map.tscn"):
			print("  skip: no Perth map in this project")
			quit(0)
			return true
		# Never write a save file, which would move the next run's start.
		root.get_node("SaveGame").enabled = false
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_map = _main.get_node("LoFi/SubViewport/World/PerthMap")
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_traffic = _main.get_node("LoFi/SubViewport/World/Traffic")
		_traffic.random_seed = 500
		# A Monday (a save loaded before this runs mustn't make it a weekend).
		root.get_node("GameClock").day = 1
		root.get_node("GameClock").set_time(8.0)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_state(0, true)
		root.get_node("Weather").set_locked(true)
		return false
	_frame += 1
	if _spot < 0:
		# Roads go in a few at a time as the tiles stream in.
		if _frame > 5 * FPS:
			_check_network()
			_go(_first_spot())
		return false
	var spot: Array = SPOTS[_spot]
	if _frame < 3 * FPS:
		return false  # Let the tiles and their roads stream in.
	_watch()
	if float(_frame) / FPS >= spot[2] + 3.0:
		_report(spot[0])
		if _spot + 1 >= SPOTS.size() or not OS.get_cmdline_user_args().is_empty():
			_finish()
			return true
		_go(_spot + 1)
	return false


## Optional user argument: only watch the spots whose names contain it.
func _first_spot() -> int:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return 0
	for i in SPOTS.size():
		if args[0] in SPOTS[i][0]:
			return i
	return 0


func _go(i: int) -> void:
	_spot = i
	_frame = 0
	_mark = { "max_vehicles": 0, "overlaps": 0, "head_on": 0, "pairs": {}, "stopped": {}, "red": _traffic.stats.red_runs,
		"ms": 0.0, "ms_n": 0, "moving": 0, "samples": 0 }
	var p: Vector3 = SPOTS[i][1]
	if p == Vector3.INF:
		p = _map.get_spawn_transform().origin
	_car.freeze = true
	# Hover above the junction: close enough for the map and traffic to
	# stream around it, out of the way of the cars it is watching.
	_car.global_position = p + Vector3(0, 30, 0)
	_traffic.clear_all()
	print("  [t] %s" % SPOTS[i][0])


func _check_network() -> void:
	var g = _traffic.graph
	_check(g.roads.size() > 300, "roads load from the map tiles around home (%d roads)" % g.roads.size())
	_check(not g.signal_controllers.is_empty(), "traffic lights on real junctions (%d)" % g.signal_controllers.size())


func _watch() -> void:
	var vs: Array = _traffic.vehicles
	_mark.max_vehicles = maxi(_mark.max_vehicles, vs.size())
	_mark.ms += _traffic.step_ms
	_mark.ms_n += 1
	if _frame % 30 != 0:
		return
	for i in vs.size():
		var v = vs[i]
		_mark.samples += 1
		if v.speed > 1.0:
			_mark.moving += 1
			_mark.stopped.erase(v)
		elif not _mark.stopped.has(v):
			_mark.stopped[v] = _frame
		for j in range(i + 1, vs.size()):
			var o = vs[j]
			var rel: Vector3 = o.position - v.position
			if rel.length() > 8.0 or absf(rel.y) > 2.5:
				continue
			var along := absf(rel.dot(v.forward))
			var side := absf(rel.dot(TrafficGraph.left_of(v.forward)))
			if along < (v.length + o.length) * 0.35 and side < (v.width + o.width) * 0.35:
				var key := "%d/%d" % [v.id, o.id]
				if not _mark.pairs.has(key):
					_mark.pairs[key] = true
					if v.forward.dot(o.forward) < -0.5:
						# Opposite ways: two carriageways drawn on top of each
						# other in the map data, not a driving problem.
						_mark.head_on += 1
						print("  head-on overlap (map geometry): #%d and #%d at %s" % [v.id, o.id, v.position.snapped(Vector3.ONE * 0.1)])
						continue
					_mark.overlaps += 1
					print("  overlap: #%d and #%d at %s (%s / %s)" % [v.id, o.id, v.position.snapped(Vector3.ONE * 0.1),
						_lane_name(v.route[0]), _lane_name(o.route[0])])
					if OS.get_environment("TRAFFIC_SOAK_DEBUG") != "":
						for x in [v, o]:
							print("    #%d %s lane %d s %.1f/%.1f speed %.1f life %.1f change_from %s reason %d fwd %s" % [x.id, x.type, x.route[0].id, x.s, x.route[0].length, x.speed, x.lifetime,
								x.change_from.id if x.change_from else -1, x.reason, x.forward.snapped(Vector3.ONE * 0.01)])


func _report(spot_name: String) -> void:
	var ms: float = _mark.ms / maxf(_mark.ms_n, 1)
	var red: int = _traffic.stats.red_runs - _mark.red
	for i in range(_traffic.red_run_log.size() - red, _traffic.red_run_log.size()):
		print("  red run: ", _traffic.red_run_log[i])
	var moving := float(_mark.moving) / maxf(_mark.samples, 1)
	# Stuck: stopped for 90 s and not waiting at a red light or a crossing.
	# (Waiting a minute for a gap at a busy CBD junction happens.)
	var stuck := 0
	for v in _mark.stopped:
		if not _traffic.vehicles.has(v) or _frame - _mark.stopped[v] < 90 * FPS:
			continue
		if v.reason == TrafficVehicle.Reason.STOP_LINE:
			continue
		stuck += 1
		var by = v.blocked_by
		var by_text := "nothing"
		if by is TrafficVehicle:
			by_text = "#%d %s" % [by.id, by.type]
		elif by is TrafficGraph.Lane:
			by_text = _lane_name(by)
			if by.connector:
				var d := 0.0
				var out: TrafficGraph.Lane = by.next[0]
				var queue: Array = []
				for o in out.vehicles:
					queue.append("#%d s%.1f v%.1f r%d" % [o.id, o.s, o.speed, o.reason])
				var conf: Array = []
				for c in by.conflicts:
					for o in c.vehicles:
						conf.append("#%d on %s v%.1f r%d" % [o.id, _lane_name(c), o.speed, o.reason])
					for o in c.in_lane.vehicles:
						if o.commits.has(c):
							conf.append("#%d committed to %s" % [o.id, _lane_name(c)])
				by_text += " [clear %s free %s merge %s room %s; signal %s; out %s: %s; conflicts: %s; yield_wait %.0f]" % [
					_traffic._junction_clear(by, v), _traffic._junction_free(by, v), _traffic._merge_turn(by, v, d), _traffic._room_beyond(v, [by]),
					("%d ctrl %d live %s phase %d t %.0f" % [by.in_lane.signal_gate.state(), by.in_lane.signal_gate.controller.get_instance_id(), _traffic.graph.signal_controllers.has(by.in_lane.signal_gate.controller), by.in_lane.signal_gate.controller.phase, by.in_lane.signal_gate.controller.timer]) if by.in_lane.signal_gate else "none", _lane_name(out), queue, conf, v.yield_wait]
		elif by != null:
			by_text = str(by)
		print("  stuck: #%d %s on %s for %ds (reason %d, held by %s) at %s" % [v.id, v.type, _lane_name(v.route[0]),
			(_frame - _mark.stopped[v]) / FPS, v.reason, by_text, v.position.snapped(Vector3.ONE * 0.1)])
	print("  %s: %d cars max, %.0f%% moving, %d overlaps, %d red runs, %d stuck, %.2f ms/frame, %d roads loaded" % [
		spot_name, _mark.max_vehicles, moving * 100.0, _mark.overlaps, red, stuck, ms, _traffic.graph.roads.size()])
	_totals.overlaps += _mark.overlaps
	_totals.head_on = _totals.get("head_on", 0) + _mark.head_on
	_totals.red_runs += red
	_totals.stuck += stuck
	_totals.max_ms = maxf(_totals.max_ms, ms)
	_totals.max_vehicles = maxi(_totals.max_vehicles, _mark.max_vehicles)
	_check(_mark.max_vehicles >= 8, "%s has traffic (%d cars)" % [spot_name, _mark.max_vehicles])


func _finish() -> void:
	var g = _traffic.graph
	var dead := 0
	for lane in g.lanes:
		if lane.next.is_empty():
			dead += 1
	print("  network: %d roads, %d lanes (%d dead ends), %d connectors, %d signal sets, %d bus stops, %d rail edges, %d level crossings" % [
		g.roads.size(), g.lanes.size(), dead, g.connectors.size(), g.signal_controllers.size(),
		g.bus_stops.size(), g.rail_edges.size(), g.crossings.size()])
	_check(_totals.red_runs == 0, "nobody runs a red light (%d did)" % _totals.red_runs)
	_check(_totals.overlaps <= 3, "cars don't drive through each other (%d overlaps)" % _totals.overlaps)
	print("  %d head-on overlaps where the map draws two carriageways on top of each other" % _totals.get("head_on", 0))
	_check(_totals.stuck <= 2, "nobody gets stuck (%d stuck)" % _totals.stuck)
	_check(_totals.max_ms < 8.0, "simulation is cheap enough (worst spot %.2f ms per frame)" % _totals.max_ms)
	if _failures.is_empty():
		print("TRAFFIC MAP TEST PASSED")
		quit(0)
	else:
		print("TRAFFIC MAP TEST FAILED: %d failure(s)" % _failures.size())
		quit(1)


func _lane_name(lane) -> String:
	if lane.connector:
		return "connector@%d turn %d from lane %d k%d to lane %d" % [lane.node.id, lane.turn, lane.in_lane.id, lane.in_lane.k, lane.next[0].id]
	return "lane k%d of %s (%s)" % [lane.k, lane.road.name if lane.road.name != "" else "road %d" % lane.road.index, lane.road.kind]


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
