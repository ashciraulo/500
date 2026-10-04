extends SceneTree
## Headless traffic test: builds the sandbox network, runs the simulation and
## checks that traffic behaves (drives on the left, stops at red lights and
## for trains, doesn't pile into itself, pools and despawns), then checks the
## main scene gets traffic on the test grid.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/traffic_test.gd

const FPS := 60

var _failures: Array[String] = []
var _step := 0
var _frame := 0
var _root3d: Node3D
var _traffic: Node3D  # TrafficManager
var _focus: Node3D
var _graph  # TrafficGraph
var _mark := {}
var _main: Node


func _process(_delta: float) -> bool:
	if _root3d == null:
		_setup()
		return false
	_frame += 1
	return _run_step()


func _setup() -> void:
	var clock := root.get_node("GameClock")
	clock.set_time(8.0)
	clock.set_locked(true)
	var weather := root.get_node("Weather")
	weather.set_state(0, true)
	weather.set_locked(true)
	_root3d = Node3D.new()
	root.add_child(_root3d)
	_focus = Node3D.new()
	_focus.position = Vector3(-100, 0, 0)
	_root3d.add_child(_focus)
	_traffic = load("res://traffic/scripts/traffic_manager.gd").new()
	_traffic.use_test_grid_fallback = false
	_traffic.random_seed = 500
	_root3d.add_child(_traffic)
	_traffic.focus_path = _traffic.get_path_to(_focus)
	_traffic.add_network(load("res://traffic/scripts/traffic_test_networks.gd").sandbox())
	_graph = _traffic.graph


func _run_step() -> bool:
	match _step:
		0:
			_check_graph()
			_next()
		1:  # Rush hour around the Station Street lights.
			_watch()
			if _seconds() >= 70.0:
				_check(_mark.max_vehicles >= 20, "traffic fills up at rush hour (max %d cars)" % _mark.max_vehicles)
				_check(_traffic.stats.red_runs == 0, "nobody runs a red light (%d did)" % _traffic.stats.red_runs)
				_check(_mark.overlaps <= 2, "cars don't drive through each other (%d overlaps)" % _mark.overlaps)
				_check(_mark.wrong_side == 0, "everyone drives on the left (%d samples on the right)" % _mark.wrong_side)
				_check(_mark.moving_frac > 0.4, "traffic keeps moving (%.0f%% of samples moving)" % (_mark.moving_frac * 100.0))
				_check(_mark.passed_signal > 3, "cars get through the signals (%d crossings)" % _mark.passed_signal)
				_check(_mark.max_peds >= 8, "people walk the footpaths (max %d)" % _mark.max_peds)
				_check(_mark.crossers > 0, "people cross at junctions (%d seen crossing)" % _mark.crossers)
				_check(_mark.buses > 0, "Transperth buses turn up (%d seen)" % _mark.buses)
				_check(_traffic.step_ms < 12.0, "simulation is cheap enough (%.2f ms per frame)" % _traffic.step_ms)
				_check_parking()
				print("  [t] vehicles=%d peds=%d step=%.2fms created=%d spawned=%d" % [
					_traffic.vehicles.size(), _traffic.pedestrians.size(), _traffic.step_ms,
					_traffic.stats.created, _traffic.stats.spawned])
				# Send a train south down the east track towards the crossings.
				var east = null
				for e in _graph.rail_edges:
					if e.pts[0].x > -180.0:
						east = e
				_mark.train = _traffic.spawn_train_at(east, 380.0, true, 3)
				_mark.xing = null
				for x in _graph.crossings:
					if absf(x.pos.z - -200.0) < 1.0 and x.pos.x > -180.0:
						_mark.xing = x
				_mark.closed_seen = false
				_mark.hit_crossing = 0
				_mark.dwelled = false
				_next()
		2:  # The train closes the crossings and stops at the station.
			var train = _mark.train
			var xing = _mark.xing
			if xing.closed:
				_mark.closed_seen = true
				for v in _traffic.vehicles:
					if v.position.distance_to(xing.pos) < 3.0 and _train_near(train, xing.pos, 25.0):
						_mark.hit_crossing += 1
			if train.dwell > 0.0:
				_mark.dwelled = true
			if _seconds() >= 75.0 or (_mark.dwelled and train.front > 1200.0):
				_check(_mark.closed_seen, "the train closes the boom gates")
				_check(_mark.hit_crossing == 0, "cars wait at the closed crossing (%d frames on the tracks)" % _mark.hit_crossing)
				_check(_mark.dwelled, "the train stops at the station")
				_check(train.front > 600.0, "the train moves on (front at %.0f m)" % train.front)
				_mark.created = _traffic.stats.created
				_focus.position = Vector3(5000, 0, 5000)
				_next()
		3:  # Far away from every road: everything despawns into the pools.
			if _seconds() >= 3.0:
				_check(_traffic.vehicles.is_empty(), "cars despawn when the player leaves (%d left)" % _traffic.vehicles.size())
				_check(_traffic.pedestrians.is_empty(), "people despawn too (%d left)" % _traffic.pedestrians.size())
				_focus.position = Vector3(-100, 0, 0)
				_traffic.clear_all()
				_next()
		4:
			if _seconds() >= 10.0:
				var fresh: int = _traffic.stats.created - _mark.created
				_check(_traffic.vehicles.size() > 10, "traffic comes back (%d cars)" % _traffic.vehicles.size())
				_check(fresh < _traffic.vehicles.size(), "pooled cars are reused (%d new nodes for %d cars)" % [fresh, _traffic.vehicles.size()])
				var clock := root.get_node("GameClock")
				var rush: int = _traffic.target_vehicles()
				clock.set_time(3.0)
				var night: int = _traffic.target_vehicles()
				var night_peds: float = _traffic.people_density()
				clock.set_time(12.5)
				var lunch_peds: float = _traffic.people_density()
				root.get_node("Weather").set_state(2, true)
				var storm_peds: float = _traffic.people_density()
				_check(night < rush * 0.3, "3am is quiet (%d cars vs %d at 8am)" % [night, rush])
				_check(night_peds < lunch_peds * 0.2, "few people about at 3am")
				_check(storm_peds < lunch_peds * 0.5, "storms clear the footpaths")
				var tm = _traffic.get_script()
				var cbd := Vector3(470, 0, 850)
				var northbridge := Vector3(230, 0, 200)
				_check(tm.area_factor(cbd, 11.0) > 1.15 and tm.area_factor(cbd, 23.0) < 0.75, "the CBD is busy by day and quiet at night")
				_check(tm.area_factor(northbridge, 22.0, true) > 1.8, "Northbridge fills with people at night")
				_check(is_equal_approx(tm.area_factor(Vector3(-5000, 0, -5000), 11.0), 1.0), "the suburbs are ordinary")
				var busy: float = _mark.kind_cars.get(&"primary", 0.0) / maxf(_mark.kind_km.get(&"primary", 0.0), 0.01)
				var quiet: float = _mark.kind_cars.get(&"residential", 0.0) / maxf(_mark.kind_km.get(&"residential", 0.0), 0.01)
				_check(busy > quiet * 1.3, "the avenue is busier than the back streets (%.1f vs %.1f cars per lane-km)" % [busy, quiet])
				root.get_node("Weather").set_state(0, true)
				clock.set_time(8.0)
				_root3d.queue_free()
				_next()
		5:  # The main scene gets traffic on the Perth map's roads.
			if _main == null:
				_main = load("res://scenes/main.tscn").instantiate()
				root.add_child(_main)
			if _seconds() >= 8.0:
				var traffic = _main.get_node("LoFi/SubViewport/World/Traffic")
				_check(traffic.graph.roads.size() > 80, "main scene loads the map's road network (%d roads)" % traffic.graph.roads.size())
				_check(traffic.vehicles.size() > 3, "main scene has traffic near the start (%d cars)" % traffic.vehicles.size())
				var car = _main.get_node("LoFi/SubViewport/World/Car")
				_check(car.collision_mask & 4 != 0, "the player's car collides with traffic")
				_next()
		_:
			if _failures.is_empty():
				print("TRAFFIC TEST PASSED")
				quit(0)
			else:
				print("TRAFFIC TEST FAILED (%d):" % _failures.size())
				for f in _failures:
					print("  - ", f)
				quit(1)
			return true
	return false


func _check_parking() -> void:
	var parking = _traffic.parking
	var lot := 0
	var near_avenue := 0
	for spot in parking.shown:
		if spot.kind == &"lot":
			lot += 1
		if absf(spot.pos.z) < 6.0:
			near_avenue += 1
	_check(lot >= 14 and lot <= 28, "the car park is busy at 8am (%d of 28 bays taken)" % lot)
	_check(near_avenue == 0, "nobody parks in a traffic lane (%d did)" % near_avenue)
	_check(_mark.get("parked_hits", 0) == 0, "traffic and people keep clear of parked cars (%d hits)" % _mark.get("parked_hits", 0))
	_check(parking.occupancy(&"lot", 3.0) < parking.occupancy(&"lot", 11.0) * 0.3, "car parks empty out overnight")
	_check(parking.occupancy(&"street", 3.0) > parking.occupancy(&"street", 11.0), "streets fill up overnight")


func _check_graph() -> void:
	var g = _graph
	_check(g.roads.size() > 25, "sandbox network loads (%d roads)" % g.roads.size())
	_check(g.signal_controllers.size() == 2, "two signal junctions (%d)" % g.signal_controllers.size())
	_check(g.crossings.size() >= 6, "level crossings found where rail meets road (%d)" % g.crossings.size())
	_check(g.bus_stops.size() == 2, "bus stops placed on kerb lanes (%d)" % g.bus_stops.size())
	_check(g.ped_edges.size() > 50, "footpaths built (%d edges)" % g.ped_edges.size())
	_check(g.parking.size() == 38, "parking spots load (%d)" % g.parking.size())
	var dead := 0
	var right_side := 0
	for lane in g.lanes:
		if lane.next.is_empty():
			dead += 1
		var road = lane.road
		if road.lanes_back > 0:
			var mid: Vector3 = lane.point(lane.length * 0.5)
			var s: float = TrafficGraph.closest_s(road.pts, road.cum, mid)
			var center: Vector3 = TrafficGraph.point_at(road.pts, road.cum, s)
			if (mid - center).dot(TrafficGraph.left_of(lane.tangent(lane.length * 0.5))) <= 0.0:
				right_side += 1
	_check(dead == 0, "every lane leads somewhere (%d dead ends)" % dead)
	_check(right_side == 0, "lanes sit on the left of the road (%d on the right)" % right_side)
	# Left turns from the kerb lane, right turns from the inside lane.
	var bad_turns := 0
	for c in g.connectors:
		if c.turn == TrafficGraph.Turn.LEFT and c.in_lane.k != c.in_lane.count - 1:
			bad_turns += 1
		if c.turn == TrafficGraph.Turn.RIGHT and c.in_lane.k != 0:
			bad_turns += 1
	_check(bad_turns == 0, "turns come from the right lanes (%d wrong)" % bad_turns)
	var minor_yields := 0
	var major_free := 0
	for c in g.connectors:
		if c.node.degree() >= 3 and c.node.signal_controller == null:
			if c.in_lane.road.rank == 2 and c.next[0].road.rank >= 5:
				minor_yields += 1 if not c.yield_to.is_empty() else 0
			if c.in_lane.road.rank >= 5 and c.turn == TrafficGraph.Turn.STRAIGHT:
				major_free += 1 if c.yield_to.is_empty() else 0
	_check(minor_yields > 0, "side streets give way to the avenue")
	_check(major_free > 0, "the avenue has right of way")
	var stop_conns: Array = g.connectors.filter(func(c): return c.full_stop)
	_check(not stop_conns.is_empty(), "the stop sign applies at its junction")
	var entering := 0
	var circulating := 0
	for c in g.connectors:
		if c.next[0].road.roundabout and not c.in_lane.road.roundabout:
			entering += 1 if not c.yield_to.is_empty() else 0
		if c.next[0].road.roundabout and c.in_lane.road.roundabout:
			circulating += 1 if c.yield_to.is_empty() else 0
	_check(entering >= 4 and circulating >= 4, "roundabout: entering traffic gives way to circulating (%d/%d)" % [entering, circulating])


func _watch() -> void:
	if not _mark.has("max_vehicles"):
		_mark.max_vehicles = 0
		_mark.max_peds = 0
		_mark.overlaps = 0
		_mark.wrong_side = 0
		_mark.moving = 0
		_mark.samples = 0
		_mark.moving_frac = 0.0
		_mark.passed_signal = 0
		_mark.crossers = 0
		_mark.buses = 0
		_mark.signal_lane = {}
		_mark.overlap_pairs = {}
		_mark.kind_cars = {}
		_mark.kind_km = {}
	if _frame % 30 == 0:
		# Lane-km of each kind of road in range, counted on the same frames.
		for lane in _graph.lanes:
			if lane.point(lane.length * 0.5).distance_to(_focus.position) < _traffic.spawn_radius:
				_mark.kind_km[lane.road.kind] = _mark.kind_km.get(lane.road.kind, 0.0) + lane.length / 1000.0
	_mark.max_vehicles = maxi(_mark.max_vehicles, _traffic.vehicles.size())
	_mark.max_peds = maxi(_mark.max_peds, _traffic.pedestrians.size())
	var vs: Array = _traffic.vehicles
	for i in vs.size():
		var v = vs[i]
		if v.is_bus:
			_mark.buses = maxi(_mark.buses, 1)
		var lane = v.route[0]
		var was = _mark.signal_lane.get(v)
		if was != null and was != lane and was.signal_gate != null:
			_mark.passed_signal += 1
		_mark.signal_lane[v] = lane
		if _frame % 30 != 0:
			continue
		_mark.samples += 1
		if not lane.connector:
			_mark.kind_cars[lane.road.kind] = _mark.kind_cars.get(lane.road.kind, 0.0) + 1.0
		if v.speed > 1.0:
			_mark.moving += 1
		if not lane.connector and lane.road.lanes_back > 0 and v.change_from == null and absf(v.lateral) < 0.1:
			var road = lane.road
			var s: float = TrafficGraph.closest_s(road.pts, road.cum, v.position)
			var center: Vector3 = TrafficGraph.point_at(road.pts, road.cum, s)
			if (v.position - center).dot(TrafficGraph.left_of(v.forward)) < 0.5:
				_mark.wrong_side += 1
		for j in range(i + 1, vs.size()):
			var o = vs[j]
			var rel: Vector3 = o.position - v.position
			if rel.length() > 8.0:
				continue
			var along := absf(rel.dot(v.forward))
			var side := absf(rel.dot(TrafficGraph.left_of(v.forward)))
			if along < (v.length + o.length) * 0.35 and side < (v.width + o.width) * 0.35:
				var key := "%d/%d" % [v.id, o.id]
				if not _mark.overlap_pairs.has(key):
					_mark.overlap_pairs[key] = true
					_mark.overlaps += 1
					print("  overlap: %s #%d and %s #%d at %s (%s / %s)" % [v.type, v.id, o.type, o.id, v.position.snapped(Vector3.ONE * 0.1),
						_lane_name(v.route[0]), _lane_name(o.route[0])])
	if _frame % 30 == 0:
		for spot in _traffic.parking.shown:
			for o in _traffic.vehicles:
				if o.position.distance_to(spot.pos) < 2.0:
					_mark.parked_hits = _mark.get("parked_hits", 0) + 1
			for o in _traffic.pedestrians:
				if o.position.distance_to(spot.pos) < 1.2:
					_mark.parked_hits = _mark.get("parked_hits", 0) + 1
	if _frame % 30 == 0 and _mark.samples > 0:
		_mark.moving_frac = float(_mark.moving) / _mark.samples
	for p in _traffic.pedestrians:
		if p.edge.crossing and not p.waiting:
			_mark.crossers += 1


func _lane_name(lane) -> String:
	if lane.connector:
		return "connector@%d turn %d" % [lane.node.id, lane.turn]
	return "lane %d k%d of road %d" % [lane.id, lane.k, lane.road.index]


func _train_near(train, p: Vector3, radius: float) -> bool:
	for car in train.cars:
		if car.global_position.distance_to(p) < radius + 12.0:
			return true
	return false


func _seconds() -> float:
	return float(_frame) / FPS


func _next() -> void:
	_step += 1
	_frame = 0
	print("  [t] step %d" % _step)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
