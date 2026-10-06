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
	# A save from playing (it's loaded before this runs) mustn't set the day,
	# and the test mustn't write one: rush hour is a weekday thing.
	root.get_node("SaveGame").enabled = false
	var clock := root.get_node("GameClock")
	clock.day = 1
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
	_traffic.add_network(load("res://traffic/scripts/traffic_test_networks.gd").sandbox(), true)
	_graph = _traffic.graph
	# The crews stay away until the roadworks step, so earlier steps don't
	# depend on which roads happen to have works today.
	_traffic.roadworks.site_chance = 0.0
	# Couriers, taxi ranks and inspectors only when the kerbside step asks.
	_traffic.kerbside.enabled = false
	# No school zone until the schools step.
	_traffic.schools.enabled = false
	# No stadium in the sandbox until the game-day step puts one there.
	_traffic.events.enabled = false
	# Nor the night shift until its step.
	_traffic.night.enabled = false
	_traffic.rides.enabled = false
	_traffic.paths.enabled = false
	# A driveway on the avenue, inside the westbound queue for the Station
	# Street lights: nobody may stop across it.
	_graph.add_keep_clear(Vector3(-72, 0, 3.2), 5.0)


func _run_step() -> bool:
	match _step:
		0:
			_check_graph()
			_next()
			# Developing one step: TRAFFIC_TEST_FROM=12 skips straight to it.
			var from := OS.get_environment("TRAFFIC_TEST_FROM")
			if from.is_valid_int():
				_step = from.to_int()
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
				var on_route: float = float(_mark.get("on_route", 0)) / maxf(_mark.get("route_samples", 0), 1.0)
				_check(_mark.get("route_samples", 0) > 0 and on_route > 0.9, "buses keep to their routes (%.0f%% of samples)" % (on_route * 100.0))
				_check(_traffic.step_ms < 12.0, "simulation is cheap enough (%.2f ms per frame)" % _traffic.step_ms)
				_check_parking()
				_check(_mark.get("in_box", 0) == 0, "nobody stops across a keep-clear driveway (%d samples)" % _mark.get("in_box", 0))
				_check(_mark.get("before_box", 0) > 0, "queues wait before the driveway (%d samples)" % _mark.get("before_box", 0))
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
				# Day 1 is a Monday, so day 5 is a Friday and day 6 a Saturday.
				_check(tm.hour_density(6, 8.0) < tm.hour_density(1, 8.0) * 0.6, "no morning rush on a Saturday")
				_check(tm.hour_density(6, 12.0) > tm.hour_density(1, 12.0), "Saturday middays are busy")
				_check(tm.hour_density(7, 12.0) < tm.hour_density(6, 12.0), "Sundays are quieter than Saturdays")
				_check(tm.hour_density(5, 23.0, true) > tm.hour_density(3, 23.0, true) * 1.8, "Friday night brings people out")
				_check(tm.hour_density(6, 1.0) > tm.hour_density(2, 1.0) * 1.5, "the small hours of Saturday are busy (night out)")
				_check(tm.hour_density(1, 1.0) < tm.hour_density(7, 1.0), "Sunday 1am still counts as Saturday night")
				_check(tm.area_factor(northbridge, 23.0, true, 6) > tm.area_factor(northbridge, 23.0, true, 2) * 1.15, "Northbridge is busiest on a Saturday night")
				_check(tm.area_factor(cbd, 11.0, false, 7) < tm.area_factor(cbd, 11.0, false, 2), "the CBD is quieter at the weekend")
				_check(_traffic.parking.occupancy(&"lot", 11.0, 7) < _traffic.parking.occupancy(&"lot", 11.0, 2) * 0.6, "office car parks are half empty on Sunday")
				# Where new cars start (how busy the roads then look depends on
				# the queues at the lights, too much to test in a minute).
				var picks := {}
				var rng_state: int = _traffic._rng.state  # Leave the traffic's own dice alone.
				for i in 4000:
					var spot: Array = _traffic._pick_spawn_spot(_focus.position, _traffic.min_spawn_radius)
					if not spot.is_empty():
						picks[spot[0].road.kind] = picks.get(spot[0].road.kind, 0.0) + 1.0
				_traffic._rng.state = rng_state
				var km := {}
				for lane in _graph.lanes:
					var d: float = lane.point(lane.length * 0.5).distance_to(_focus.position)
					if d > _traffic.min_spawn_radius and d < _traffic.spawn_radius:
						km[lane.road.kind] = km.get(lane.road.kind, 0.0) + lane.length / 1000.0
				var busy: float = picks.get(&"primary", 0.0) / maxf(km.get(&"primary", 0.0), 0.01)
				var quiet: float = picks.get(&"residential", 0.0) / maxf(km.get(&"residential", 0.0), 0.01)
				_check(busy > quiet * 2.0, "the avenue gets more new cars than the back streets (%.0f vs %.0f per lane-km)" % [busy, quiet])
				root.get_node("Weather").set_state(0, true)
				clock.set_time(8.0)
				# The player gets out and stands in the avenue's westbound kerb lane.
				var script := GDScript.new()
				script.source_code = "extends CharacterBody3D\nvar in_car := false\n"
				script.reload()
				_mark.walker = CharacterBody3D.new()
				_mark.walker.set_script(script)
				_root3d.add_child(_mark.walker)
				# Somewhere no car is already too close to stop for them.
				var wx := -40.0
				while wx > -100.0 and _traffic.vehicles.any(func(v): return absf(v.position.z - 4.8) < 2.5 and v.position.x > wx - 6.0 and v.position.x < wx + 25.0):
					wx -= 8.0
				_mark.walker.global_position = Vector3(wx, 0, 4.8)
				# And a car on its way down that lane towards them (whether one
				# happens along in time otherwise is down to the dice).
				for lane in _graph.lanes:
					if lane.connector or lane.tangent(0.0).x > -0.9 or absf(lane.point(0.0).z - 4.8) > 1.0:
						continue
					var at: float = lane.point(0.0).x - wx
					if at < 30.0 or at > lane.length:
						continue
					var from := maxf(2.0, at - 50.0)
					if lane.vehicles.all(func(o) -> bool: return o.s < from - 10.0 or o.s > at):
						_traffic.spawn_vehicle_at(&"sedan", lane, from)
					break
				_mark.walker_hits = 0
				_mark.waited = 0
				_next()
		5:  # Traffic stops for the player on foot.
			var walker: Node3D = _mark.walker
			for v in _traffic.vehicles:
				if v.position.distance_to(walker.global_position) < (v.length * 0.5 + 0.2) and absf(v.position.y - walker.global_position.y) < 2.0:
					var rel: Vector3 = walker.global_position - v.position
					if absf(rel.dot(TrafficGraph.left_of(v.forward))) < v.width * 0.5 + 0.2:
						_mark.walker_hits += 1
				# Stopping or pulling round into the free lane both count.
				if v.reason == TrafficVehicle.Reason.PLAYER and v.position.distance_to(walker.global_position) < 40.0:
					_mark.waited += 1
			if _seconds() >= 25.0:
				_check(_mark.walker_hits == 0, "nobody drives through the player on foot (%d frames)" % _mark.walker_hits)
				_check(_mark.waited > 0, "cars slow for the player standing in the road")
				_mark.walker.queue_free()
				# An ambulance on a call comes up the avenue's westbound kerb lane.
				var best = null
				for lane in _graph.lanes:
					if lane.connector or lane.road == null or lane.road.rank < 2 or lane.length < 60.0:
						continue
					var mid: Vector3 = lane.point(lane.length * 0.5)
					if lane.tangent(lane.length * 0.5).x < -0.9 and absf(mid.z - 4.8) < 1.0 and lane.point(0.0).x > 100.0 and lane.point(lane.length).x < 100.0:
						best = lane
				_mark.amb = null
				if best != null:
					# A car dawdling ahead of it, so someone has to pull over.
					for o in best.vehicles.duplicate():
						_traffic._despawn_vehicle(o)
					_mark.slow = _traffic.spawn_vehicle_at(&"sedan", best, minf(55.0, best.length - 5.0), 6.0)
					_mark.amb = _traffic.spawn_vehicle_at(&"ambulance", best, 4.0, 12.0)
					_mark.amb_lane = best
					_mark.amb_start = _mark.amb.position
				_mark.pulled = {}
				_mark.amb_hits = 0
				_next()
		6:  # Traffic pulls over for an ambulance on a call.
			var amb = _mark.amb
			if amb == null:
				_check(false, "an ambulance turns up on the avenue")
				_next()
				return false
			if amb.active:
				for v in _traffic.vehicles:
					if v == amb:
						continue
					if v.reason == TrafficVehicle.Reason.EMERGENCY and v.lateral > 0.7:
						_mark.pulled[v.id] = true
					var rel: Vector3 = v.position - amb.position
					if absf(rel.y) < 2.0 and absf(rel.dot(amb.forward)) < (v.length + amb.length) * 0.5 - 0.4 \
							and absf(rel.dot(TrafficGraph.left_of(amb.forward))) < (v.width + amb.width) * 0.5 - 0.25:
						_mark.amb_hits += 1
				_mark.amb_end = amb.position
				var slow = _mark.slow
				if slow.active and _mark.pulled.has(slow.id) and (amb.position - slow.position).dot(slow.forward) > 3.0:
					_mark.overtook = true
			if _seconds() >= 35.0:
				_check(amb.light_bar != null and amb.siren != null, "the ambulance has lights and a siren")
				_check(_mark.pulled.size() > 0, "traffic pulls over for the ambulance (%d cars)" % _mark.pulled.size())
				_check(_mark.amb_hits == 0, "the ambulance doesn't drive through anyone (%d frames)" % _mark.amb_hits)
				var went: float = _mark.amb_start.distance_to(_mark.amb_end)
				_check(went > 150.0, "the ambulance gets through (%.0f m)" % went)
				_check(_mark.get("overtook", false), "the ambulance passes the car that pulled over")
				_check(_traffic.emergencies.has(amb) == amb.active, "the emergency list follows the ambulance")
				_check(_traffic.stats.get("bike", 0) > 0, "people ride bikes on the quieter roads (%d so far)" % _traffic.stats.get("bike", 0))
				# A cyclist on the avenue with a car coming up behind.
				var lane = _mark.get("amb_lane")
				for v in _traffic.vehicles.duplicate():
					_traffic._despawn_vehicle(v)
				_mark.bike = null
				if lane != null:
					_mark.bike = _traffic.spawn_vehicle_at(&"bike", lane, 40.0, 5.0)
					_mark.passer = _traffic.spawn_vehicle_at(&"sedan", lane, 4.0, 11.0)
				_mark.bike_hits = 0
				_mark.passed = false
				_next()
		7:  # Cars pass a cyclist.
			var bike = _mark.bike
			if bike == null:
				_check(false, "a cyclist turns up on the avenue")
				_next()
				return false
			var car = _mark.passer
			if bike.active and car.active:
				var rel: Vector3 = car.position - bike.position
				if absf(rel.dot(bike.forward)) < (car.length + bike.length) * 0.5 - 0.3 \
						and absf(rel.dot(TrafficGraph.left_of(bike.forward))) < (car.width + bike.width) * 0.5 - 0.15:
					_mark.bike_hits += 1
				if rel.dot(bike.forward) > car.length:
					_mark.passed = true
			# Out on the road (not turning through a junction), by the kerb.
			if bike.active and bike.lifetime > 3.0 and not bike.route[0].connector:
				_mark.bike_on_road = _mark.get("bike_on_road", 0) + 1
				if bike.lateral > 0.8:
					_mark.bike_kerb = _mark.get("bike_kerb", 0) + 1
			if _seconds() >= 20.0:
				var kerb: float = float(_mark.get("bike_kerb", 0)) / maxf(_mark.get("bike_on_road", 0), 1.0)
				_check(kerb > 0.8 or _mark.get("bike_on_road", 0) == 0, "the cyclist rides by the kerb (%.0f%% of the time)" % (kerb * 100.0))
				_check(_mark.passed, "a car passes the cyclist")
				_check(_mark.bike_hits == 0, "nobody rides or drives through each other (%d frames)" % _mark.bike_hits)
				# Roadworks close the westbound kerb lane of the avenue.
				var road = null
				for r in _graph.roads:
					# The stretch between the Roundabout Road lights and the next corner.
					var xs := [r.pts[0].x, r.pts[r.pts.size() - 1].x]
					if r.name == "Sandbox Avenue" and xs.min() > 50.0 and xs.max() < 230.0:
						road = r
				_mark.works = null
				if road != null:
					var fwd: bool = road.pts[0].x > road.pts[road.pts.size() - 1].x  # a -> b runs west
					_mark.works = _traffic.roadworks.add_site(road, fwd, 1, road.length * 0.4, road.length * 0.4 + 50.0)
					# A couple of cars coming up the closed lane, and one alongside.
					var cl: TrafficGraph.Lane = _traffic.roadworks._lane_of(_mark.works)
					for s0 in [2.0, 14.0]:
						_traffic.spawn_vehicle_at(&"sedan", cl, s0, 10.0)
					var other: TrafficGraph.Lane = cl.right_lane if cl.right_lane else cl.left_lane
					if other:
						_traffic.spawn_vehicle_at(&"hatch", other, 8.0, 10.0)
				_mark.in_works = 0
				_mark.past_works = {}
				_mark.works_hits = _traffic.stats.get("overlaps", 0)
				_next()
		8:  # Traffic merges out of the closed lane and gets past the works.
			var site = _mark.works
			if site == null:
				_check(false, "roadworks set up on the avenue")
				_next()
				return false
			var closed_lane: TrafficGraph.Lane = _traffic.roadworks._lane_of(site)
			for v in _traffic.vehicles:
				var l: TrafficGraph.Lane = v.route[0]
				if l == closed_lane and v.s > closed_lane.closed[0] + 1.0 and v.s < closed_lane.closed[1] and not v.change_from:
					_mark.in_works += 1
				if l.road == site.road and l != closed_lane and l.from_node == closed_lane.from_node and v.s > closed_lane.closed[1]:
					_mark.past_works[v.id] = true
			if _seconds() >= 60.0:
				_check(not closed_lane.closed.is_empty(), "the roadworks close a lane")
				_check(_mark.in_works == 0, "nobody drives through the cones (%d frames)" % _mark.in_works)
				_check(_mark.past_works.size() >= 2, "traffic gets past the roadworks (%d cars)" % _mark.past_works.size())
				_check(site.nodes.size() > 10, "the works have cones, a barrier, a sign and a ute (%d pieces)" % site.nodes.size())
				var rw = _traffic.roadworks
				rw.site_chance = 0.06
				var days_on := 0
				var moved := false
				for day in 60:
					var a: Dictionary = rw.site_for(site.road, day)
					var b: Dictionary = rw.site_for(site.road, day + 1)
					if not a.is_empty():
						days_on += 1
					if a.is_empty() != b.is_empty():
						moved = true
				var eligible := 0
				var with_works := 0
				for r in _graph.roads:
					if rw.eligible(r):
						eligible += 1
						for day in 30:
							if not rw.site_for(r, day).is_empty():
								with_works += 1
								break
				_check(moved and days_on < 30, "the crews move on every few days (%d of 60 days on the avenue)" % days_on)
				rw.clear()
				_check(closed_lane.closed.is_empty(), "the lane opens again when the works go")
				# Kerbside: a courier double-parks in that lane with cars
				# coming up behind; a taxi rank at the station; an inspector
				# sent to a car left in a traffic lane.
				var kb: TrafficKerbside = _traffic.kerbside
				kb.always_on = true
				_mark.van = {}
				for k in 9:
					if _mark.van.is_empty():
						_mark.van = kb.add_van(closed_lane, closed_lane.length * (0.45 + k * 0.05), 10.0)
				for s0 in [2.0, 14.0]:
					_traffic.spawn_vehicle_at(&"sedan", closed_lane, s0, 10.0)
				_mark.van_lane = closed_lane
				_mark.in_van = 0
				_mark.past_van = {}
				var st: Dictionary = _graph.stations[0]
				var spot: Array = kb._rank_spot(st.pos)
				_mark.rank = kb.add_rank(st.name, spot[0], spot[1]) if not spot.is_empty() else {}
				_mark.taxis_before = kb.stats.taxis_away
				if not _mark.rank.is_empty():
					kb.on_train_arrived(_mark.rank.pos)
				_mark.tickets = []
				kb.parking_ticket.connect(func(fine: int, reason: String, _p: Vector3) -> void: _mark.tickets.append([fine, reason]))
				var car_lane: TrafficGraph.Lane = closed_lane.right_lane if closed_lane.right_lane else closed_lane.left_lane
				_mark.parked = Node3D.new()
				_root3d.add_child(_mark.parked)
				_mark.parked.global_position = car_lane.point(car_lane.length * 0.8)
				_mark.offence = kb.offence_at(_mark.parked.global_position)
				_mark.kerb_offence = kb.offence_at(_mark.parked.global_position + TrafficGraph.left_of(car_lane.tangent(car_lane.length * 0.8)) * 9.0)
				kb._offence = "lane"
				kb.send_inspector(_mark.parked)
				_mark.balance = root.get_node("Wallet").balance
				_next()
		9:  # Traffic gets round the courier; taxis leave; the inspector books the car.
			var kb: TrafficKerbside = _traffic.kerbside
			var lane: TrafficGraph.Lane = _mark.van_lane
			var van: Dictionary = _mark.van
			if not van.is_empty():
				for v in _traffic.vehicles:
					var l: TrafficGraph.Lane = v.route[0]
					if l == lane and absf(v.s - van.s) < 3.0 and not v.change_from:
						_mark.in_van += 1
					if l.road == lane.road and l != lane and l.from_node == lane.from_node and v.s > van.s + 5.0:
						_mark.past_van[v.id] = true
			if _seconds() >= 100.0 or (_seconds() >= 50.0 and not _mark.tickets.is_empty()):
				_check(not van.is_empty() and not lane.closed.is_empty(), "a courier double-parks and closes the kerb lane")
				_check(_mark.in_van == 0, "nobody drives through the van (%d frames)" % _mark.in_van)
				_check(_mark.past_van.size() >= 2, "traffic gets round the double-parked van (%d cars)" % _mark.past_van.size())
				var away: TrafficVehicle = kb.van_drive_off(van) if not van.is_empty() else null
				_check(away != null and lane.closed.is_empty(), "the van drives off and the lane opens")
				_check(not _mark.rank.is_empty() and kb.stats.taxis_away > _mark.taxis_before, "a taxi leaves the station rank when a train comes in (%d)" % (kb.stats.taxis_away - _mark.taxis_before))
				var taxis := 0
				for v in _traffic.vehicles:
					if v.type == &"taxi":
						taxis += 1
				_check(taxis >= 1, "the taxi pulls out into the traffic")
				_check(_mark.offence == "lane" and _mark.kerb_offence == "", "a car in a traffic lane is booked, one off the road isn't")
				var paid: int = _mark.balance - root.get_node("Wallet").balance
				var ins_d := -1.0
				for ins in kb.inspectors:
					ins_d = ins.node.position.distance_to(_mark.parked.global_position)
				_check(_mark.tickets.size() == 1 and paid == TrafficKerbside.LANE_FINE and kb.ticket_note != null,
						"the inspector walks over and books it ($%d paid, %d tickets, inspector %.0f m off)" % [paid, _mark.tickets.size(), ins_d])
				root.get_node("Wallet").earn(paid)
				kb.clear()
				kb.always_on = false
				_next()
		10:  # School zone: 40 km/h, the crossing guard stops traffic, parents double-park.
			var sc: TrafficSchools = _traffic.schools
			if _frame == 1:
				var clock := root.get_node("GameClock")
				clock.set_time(12.0)
				_mark.lunch_zone = sc.zone_hours()
				clock.set_time(8.0)
				sc.always_on = true
				sc.enabled = true
				sc._timer = 0.0
				_mark.school_fast = 0
				_mark.school_hits = 0
				_mark.school_parent = {}
				_mark.parent_hits = 0
				_mark.school_stopped = false
			if _frame == 30:
				var school: Dictionary = sc.schools[0] if not sc.schools.is_empty() else {}
				_mark.school = school
				if not school.is_empty():
					# Cars heading for the guard's crossing, and a parent stopping.
					var edge: TrafficGraph.PedEdge = school.edge
					if edge:
						for lane in edge.road.lanes_into(edge.node):
							for s0 in [5.0, 25.0, 45.0]:
								if s0 < lane.length - 10.0:
									_traffic.spawn_vehicle_at(&"sedan", lane, s0, 11.0)
					for lane in school.lanes:
						if not _mark.school_parent.is_empty():
							break
						if edge and lane.road == edge.road:
							continue
						for f in [0.4, 0.5, 0.6]:
							if _mark.school_parent.is_empty():
								_mark.school_parent = sc.add_parent(lane, lane.length * f, 40.0)
					if not _mark.school_parent.is_empty():
						var pl: TrafficGraph.Lane = _mark.school_parent.lane
						for s0 in [2.0, 12.0]:
							_traffic.spawn_vehicle_at(&"hatch", pl, s0, 10.0)
			if _frame > 30 and not _mark.school.is_empty():
				var school: Dictionary = _mark.school
				_mark.school_stopped = _mark.school_stopped or sc.guard_stopping(school)
				var zone := {}
				for lane in school.lanes:
					zone[lane] = true
				for v in _traffic.vehicles:
					var l: TrafficGraph.Lane = v.route[0]
					if _frame > 180 and not v.emergency and zone.has(l) and v.s > 35.0 and v.speed > TrafficSchools.ZONE_SPEED + 0.6:
						_mark.school_fast += 1
						if _mark.school_fast % 30 == 1:
							print("    over 40: #%d %s %.1f m/s at s=%.0f of %.0f, zone %.1f, reason %d, lead %s" % [v.id, v.type, v.speed, v.s, l.length, l.zone_speed, v.reason, v.lifetime])
					for o in _traffic.obstacles:
						var rel: Vector3 = o.position - v.position
						if absf(rel.dot(v.forward)) < v.length * 0.5 and absf(rel.dot(TrafficGraph.left_of(v.forward))) < v.width * 0.5:
							_mark.school_hits += 1
					var par: Dictionary = _mark.school_parent
					if not par.is_empty() and parents_has(sc, par) and l == par.lane and absf(v.s - par.s) < 3.0 and not v.change_from:
						_mark.parent_hits += 1
			if _seconds() >= 70.0:
				var school: Dictionary = _mark.school
				_check(not _mark.lunch_zone, "no school zone at lunchtime")
				_check(not school.is_empty() and school.lanes.size() >= 4 and school.lanes[0].zone_speed > 11.0 and school.lanes[0].zone_speed < 11.2,
						"the streets round the school drop to 40 (%d lanes)" % (school.lanes.size() if not school.is_empty() else 0))
				_check(not school.is_empty() and school.signs.size() >= 2, "flashing 40 signs on the way in (%d)" % (school.signs.size() if not school.is_empty() else 0))
				_check(_mark.school_fast == 0, "traffic keeps to 40 in the zone (%d frames over)" % _mark.school_fast)
				_check(not school.is_empty() and school.edge != null and not school.guard.is_empty(), "a crossing guard at the school crossing")
				_check(_mark.school_stopped and sc.stats.kids >= 1, "the guard stops the traffic and sees the kids across (%d crossings, %d kids)" % [sc.stats.crossings, sc.stats.kids])
				_check(_mark.school_hits == 0, "nobody drives into the guard or the kids (%d frames)" % _mark.school_hits)
				var par: Dictionary = _mark.school_parent
				_check(not par.is_empty() and _mark.parent_hits == 0, "a parent double-parks and nobody drives through them (%d frames)" % _mark.parent_hits)
				var away: TrafficVehicle = null
				if not par.is_empty() and parents_has(sc, par):
					away = sc.parent_drive_off(par)
				_check(par.is_empty() or away != null or not parents_has(sc, par), "the parent drives off")
				sc.always_on = false
				sc.clear()
				_check(school.is_empty() or school.lanes[0].zone_speed == 0.0, "the zone lifts after school hours")
				_next()
		11:  # Game day: fans walk to the stadium, the roads and trains get busier.
			var ev: TrafficEvents = _traffic.events
			if _frame == 1:
				var days := 0
				var midweek := 0
				var saturdays := 0
				for day in range(1, 57):
					var e: Dictionary = ev.event_on(day)
					if not e.is_empty():
						days += 1
						if posmod(day - 1, 7) < 3:
							midweek += 1
						if posmod(day - 1, 7) == 5:
							saturdays += 1
				_mark.event_days = [days, midweek, saturdays]
				ev.enabled = true
				ev.force_event = true
				ev.force_start = 9.0
				ev.stadium = Vector3(140, 0.02, 160)
				ev.gate_radius = 45.0
				ev.station_name = "Sandbox"
				# Watching from the street by the ground.
				_focus.position = Vector3(140, 0, 230)
				ev._timer = 0.0
				_mark.fan_start = {}
				_mark.fan_closer = 0
				_mark.fan_further = 0
			if _frame == 120:
				_mark.car_factor = ev.car_factor(ev.stadium)
				_mark.train_factor = ev.train_factor(ev.stadium)
				_mark.phase_in = ev.phase
			if _frame % 60 == 0:
				for f in ev.fans:
					# Edges still to walk: fewer as they get on with it.
					var d: float = f.route.size() + (0.0 if f.leave_at_end > 0 else 99.0)
					# People are pooled: the same one can be a new fan later.
					var key := [f, f.get_meta(&"fan", -1)]
					if not _mark.fan_start.has(key):
						_mark.fan_start[key] = [d, _frame]
					elif _frame - _mark.fan_start[key][1] >= 600:
						if d < _mark.fan_start[key][0]:
							_mark.fan_closer += 1
						elif d > _mark.fan_start[key][0]:
							_mark.fan_further += 1
						_mark.fan_start[key] = [d, _frame]
			if _seconds() >= 60.0 and not _mark.has("fans_in"):
				_mark.fans_in = [ev.stats.fans, ev.fans.size(), ev.stats.arrived]
				_mark.dressed = 0
				for f in ev.fans:
					if f.node.get_node_or_null("Body/Scarf") != null:
						_mark.dressed += 1
				# Final siren: everyone out.
				root.get_node("GameClock").set_time(9.0 + TrafficEvents.FOOTY_HOURS + 0.1)
				_mark.leave_from = ev.stats.fans
				_mark.fan_start = {}
			if _seconds() >= 80.0:
				var days: Array = _mark.event_days
				_check(days[0] >= 8 and days[0] <= 30 and days[1] == 0 and days[2] >= 3, "games most weekends, none early in the week (%d days in 8 weeks, %d on Saturdays)" % [days[0], days[2]])
				_check(_mark.phase_in == TrafficEvents.Phase.ARRIVING and _mark.car_factor > 1.4 and _mark.train_factor > 1.0,
						"the roads and trains get busier before the game (cars x%.2f, trains x%.1f)" % [_mark.car_factor, _mark.train_factor])
				var fi: Array = _mark.fans_in
				_check(fi[0] >= 20 and fi[1] >= 10, "fans stream in to the game (%d sent, %d walking)" % [fi[0], fi[1]])
				_check(_mark.dressed >= fi[1] * 0.8, "fans wear their team's colours (%d of %d)" % [_mark.dressed, fi[1]])
				_check(_mark.fan_closer > _mark.fan_further * 3 and fi[2] >= 3, "they head for the gates and go in (%d getting there, %d lost, %d in)" % [_mark.fan_closer, _mark.fan_further, fi[2]])
				_check(ev.phase == TrafficEvents.Phase.LEAVING and ev.stats.fans > _mark.leave_from + 10, "after the siren they pour out again (%d)" % (ev.stats.fans - _mark.leave_from))
				ev.force_event = false
				ev.enabled = false
				ev.clear()
				root.get_node("GameClock").set_time(8.0)
				_next()
		12:  # The night shift: sweepers, bin day and the bin truck, food vans.
			var nt: TrafficNight = _traffic.night
			if _frame == 1:
				# Start from the same streets every run, whatever the earlier
				# steps left behind (how far they got depends on the machine),
				# so the bunch ride meets the same traffic and lights each time.
				_settle()
				var clock := root.get_node("GameClock")
				var hours := []
				for t in [[1, 2.0, "sweep"], [1, 14.0, "sweep"], [1, 19.0, "bins"], [3, 9.0, "bins"], [2, 7.0, "truck"], [2, 13.0, "truck"],
						[5, 21.0, "food"], [2, 21.0, "food"], [6, 1.0, "food"], [7, 20.0, "food"]]:
					clock.day = t[0]
					clock.set_time(t[1])
					hours.append(nt.sweeper_hours() if t[2] == "sweep" else nt.bins_out() if t[2] == "bins" else nt.truck_hours() if t[2] == "truck" else nt.food_hours())
				_mark.night_hours = hours
				clock.day = 1
				clock.set_time(8.0)
				nt.always_on = true
				nt.enabled = true
				nt.bin_radius = 300.0
				# Among the back streets, with the street parking on Station Street.
				_focus.position = Vector3(-160, 0, -120)
				nt._timer = 0.0
				_mark.sweep_fast = 0
				_mark.sweep_seen = 0
				_mark.sweep_moved = 0
				_mark.truck = {}
				_mark.truck_stopped = 0
				_mark.bunch = []
			if _frame == 100:
				# A bunch ride rolls up to a junction it can turn at.
				var best: TrafficGraph.Lane = null
				for entry in _graph.samples_near(_focus.position, 160.0):
					var l: TrafficGraph.Lane = entry[0]
					if l.connector or l.k != l.count - 1 or l.length < 60.0 or l.next.size() < 2:
						continue
					if best == null or l.length > best.length:
						best = l
				if best:
					for o in best.vehicles.duplicate():
						_traffic._despawn_vehicle(o)
					_mark.bunch = _traffic.rides.add_bunch(best, best.length - 6.0, 10)
				_mark.bunch_roads = []
				for v in _mark.bunch:
					_mark.bunch_roads.append({ v.route[0].road: true })
				_mark.bunch_fast = 0.0
				_mark.bunch_gaps = []
			if _frame == 90 and not nt.bins.is_empty():
				# Send the bin truck up a street with bins out.
				# (The street with the most bins on it.)
				var count := {}
				for bin in nt.bins:
					count[bin.lane] = count.get(bin.lane, 0) + 1
				var lanes: Array = count.keys()
				lanes.sort_custom(func(a, b): return count[a] > count[b])
				for bin in nt.bins:
					if bin.lane == lanes[0] and _mark.truck.is_empty():
						_mark.truck = nt.add_bin_truck(bin.lane, maxf(bin.s - 45.0, 5.0))
			if _frame > 90:
				for v in nt.sweepers:
					if v.active:
						_mark.sweep_seen += 1
						if v.speed > TrafficNight.SWEEPER_SPEED + 0.2:
							_mark.sweep_fast += 1
						if v.speed > 1.0:
							_mark.sweep_moved += 1
				var riders: Array = _mark.get("bunch", [])
				for i in riders.size():
					var v: TrafficVehicle = riders[i]
					if not v.active:
						continue
					if not v.route[0].connector:
						_mark.bunch_roads[i][v.route[0].road] = true
					# Pace: the quickest anyone in the bunch gets against the
					# pace the leader sets (the leader can be held up at lights
					# or behind a car the whole time, the riders on its wheel
					# still get going).
					if v.bunch == _mark.bunch[0].bunch:
						_mark.bunch_fast = maxf(_mark.bunch_fast, v.speed / _mark.bunch[0].max_speed)
					if OS.get_environment("TRAFFIC_BUNCH_DEBUG") != "" and _frame % 60 == 0 and i == 0:
						print("  leader speed=%.1f of %.1f reason=%s" % [v.speed, v.max_speed, v.reason])
					if OS.get_environment("TRAFFIC_BUNCH_DEBUG") != "" and _frame % 60 == 0 and i > 0 and i < 4 and _traffic._in_bunch(v):
						print("  rider %d gap=%.1f speed=%.1f lead=%.1f reason=%s obst=%.1f who=%s" % [i, v.follow.position.distance_to(v.position), v.speed, v.follow.speed, v.reason, v.obstacle_gap, v.obstacle_who.type if v.obstacle_who is TrafficVehicle else str(v.obstacle_who)])
					if i > 0 and _traffic._in_bunch(v) and v.follow.route[0] == v.route[0] and v.speed > 6.0:
						_mark.bunch_gaps.append(v.follow.s - v.s)
				var t: Dictionary = _mark.truck
				if not t.is_empty() and t.v.active and t.v.speed < 0.3 and t.v.reason == TrafficVehicle.Reason.STOP_LINE:
					_mark.truck_stopped += 1
			if _seconds() >= 75.0:
				var h: Array = _mark.night_hours
				_check(h == [true, false, true, false, true, false, true, false, true, false],
						"the night shift keeps its hours: sweeping at 2am, bins out Monday night, the truck Tuesday morning, food vans Thursday to Saturday nights (%s)" % [h])
				var v: TrafficVehicle = nt.sweepers[0] if not nt.sweepers.is_empty() else null
				_check(nt.stats.sweepers >= 1 and v != null and nt._part(v, "Beacon") != null and (v.model != null or v.body.has_node("Brooms")), "a street sweeper comes out, beacons and brooms going (%d)" % nt.stats.sweepers)
				_check(_mark.sweep_seen > 0 and _mark.sweep_fast == 0 and _mark.sweep_moved > 0, "it creeps along at sweeping pace (%d of %d frames too fast)" % [_mark.sweep_fast, _mark.sweep_seen])
				var off_road := 0
				for bin in nt.bins:
					var c: Vector3 = bin.lane.point(bin.s)
					if Vector2(bin.pos.x - c.x, bin.pos.z - c.z).length() > 1.4:
						off_road += 1
				_check(nt.bins.size() >= 12 and off_road == nt.bins.size(), "bins out along the residential kerbs, out of the traffic (%d, %d off the road)" % [nt.bins.size(), off_road])
				_check(not _mark.truck.is_empty() and _mark.truck_stopped > 60 and nt.stats.bins_emptied >= 2,
						"the bin truck stops at each bin and empties it (%d emptied)" % nt.stats.bins_emptied)
				var vans: Array = nt.food_vans
				var parked_under := 0
				for van in vans:
					for spot in _traffic.parking.shown.keys():
						if spot.pos.distance_to(van.spot.pos) < 2.0:
							parked_under += 1
				_check(vans.size() >= 1 and vans[0].queue.size() >= 2 and parked_under == 0,
						"food vans park up in the street bays with a queue at the hatch (%d vans, %d cars under them)" % [vans.size(), parked_under])
				var riders: Array = _mark.get("bunch", [])
				var strays := 0
				for i in range(1, riders.size()):
					for road in _mark.bunch_roads[i]:
						if not _mark.bunch_roads[i - 1].has(road):
							strays += 1
				var club := 0
				for r in riders:
					if r.active and r.mesh.get_surface_override_material(TrafficModels.Surf.LIVERY) == riders[0].mesh.get_surface_override_material(TrafficModels.Surf.LIVERY):
						club += 1
				# Most of the time (they string out after a red light, then close up).
				var gaps: Array = _mark.get("bunch_gaps", [])
				gaps.sort()
				var gap: float = gaps[gaps.size() / 2] if not gaps.is_empty() else INF
				if not gaps.is_empty():
					print("  bunch gaps: quartiles %.1f %.1f %.1f, worst %.1f" % [gaps[gaps.size() / 4], gap, gaps[gaps.size() * 3 / 4], gaps[-1]])
				_check(riders.size() >= 8 and _mark.bunch_fast > 0.85, "a bunch ride comes through at pace (%d riders, %.0f%% of its pace)" % [riders.size(), _mark.bunch_fast * 100.0])
				_check(gaps.size() > 100 and gap < 4.5, "they ride on each other's wheels (%.1f m apart)" % gap)
				_check(strays == 0, "and stick together through the junctions (%d strays)" % strays)
				var ride_hours := []
				var cl := root.get_node("GameClock")
				for dh in [[6, 7.5], [7, 9.0], [6, 13.0], [2, 6.0], [2, 9.0]]:
					cl.day = dh[0]
					cl.set_time(dh[1])
					ride_hours.append(_traffic.rides.bunches_wanted() > 0)
				_check(ride_hours == [true, true, false, true, false], "bunches ride weekend mornings and early weekdays (%s)" % [ride_hours])
				cl.day = 1
				cl.set_time(8.0)
				nt.always_on = false
				nt.clear()
				_check(nt.bins.is_empty() and nt.food_vans.is_empty(), "the night shift packs up")
				_next()
		13:  # Riders and joggers out on a riverside bike path.
			var pt: TrafficPaths = _traffic.paths
			if _frame == 1:
				# A shared path along the "river" south of the suburb, with a
				# branch off it that joins partway along.
				_graph._add_footways([
					{ "pts": [[-400, 0.02, 470], [0, 0.02, 480], [400, 0.02, 470]], "name": "Sandbox Foreshore Path" },
					{ "pts": [[0, 0.02, 480], [30, 0.02, 560], [150, 0.02, 600]] },
				], true)
				_focus.position = Vector3(0, 0, 470)
				pt.always_on = true
				pt.enabled = true
				pt._timer = 0.0
				_mark.path_off = 0
				_mark.path_close = 0
				_mark.path_samples = 0
				_mark.rider_speed = 0.0
				_mark.jog_speed = 0.0
				_mark.path_ids = {}
			if _frame > 60:
				for m in pt.movers:
					_mark.path_samples += 1
					if not m.edge.cycle:
						_mark.path_off += 1
					if m.rider:
						_mark.rider_speed = maxf(_mark.rider_speed, m.speed)
					else:
						_mark.jog_speed = maxf(_mark.jog_speed, m.speed)
					for o in pt.movers:
						if o != m and o.position.distance_to(m.position) < 0.5:
							_mark.path_close += 1
			if _seconds() >= 40.0:
				var riders: int = pt.movers.filter(func(m): return m.rider).size()
				var joggers: int = pt.movers.size() - riders
				var cycle_edges: int = _graph.ped_edges.filter(func(e): return e.cycle).size()
				_check(cycle_edges >= 3, "bike paths join the network, split where they meet (%d path pieces)" % cycle_edges)
				_check(riders >= 2 and joggers >= 2, "people ride and jog on the bike path (%d riders, %d joggers)" % [riders, joggers])
				_check(_mark.path_samples > 0 and _mark.path_off == 0, "they keep to the bike paths (%d samples off)" % _mark.path_off)
				_check(_mark.rider_speed > _mark.jog_speed and _mark.jog_speed > 2.0, "riders go faster than joggers (%.1f vs %.1f m/s)" % [_mark.rider_speed, _mark.jog_speed])
				_check(_mark.path_close < 30 and pt.stats.passes > 0, "they pass each other rather than through each other (%d close frames, %d passes)" % [_mark.path_close / 2, pt.stats.passes])
				var cl := root.get_node("GameClock")
				var busy := []
				pt.always_on = false
				for dh in [[2, 7.0], [2, 12.0], [6, 12.0], [2, 2.0]]:
					cl.day = dh[0]
					cl.set_time(dh[1])
					busy.append(pt.busy())
				_check(busy[0].x > busy[1].x and busy[2].x > busy[1].x and busy[3].x == 0.0 and busy[3].y < 0.1,
						"the paths are busiest early and at weekends, near empty at 2am (%s)" % [busy])
				cl.day = 1
				cl.set_time(8.0)
				pt.clear()
				_check(pt.movers.is_empty(), "the path people go home")
				_root3d.queue_free()
				_next()
		14:  # The main scene gets traffic on the Perth map's roads.
			if _main == null:
				_main = load("res://scenes/main.tscn").instantiate()
				root.add_child(_main)
			if _seconds() >= 8.0:
				var traffic = _main.get_node("LoFi/SubViewport/World/Traffic")
				_check(traffic.graph.roads.size() > 80, "main scene loads the map's road network (%d roads)" % traffic.graph.roads.size())
				_check(traffic.vehicles.size() > 3, "main scene has traffic near the start (%d cars)" % traffic.vehicles.size())
				var boxed := 0
				for entry in traffic.graph.samples_near(traffic.keep_clear_spots[0], 15.0):
					if not traffic.graph.keep_clear_on(entry[0]).is_empty():
						boxed += 1
				_check(boxed >= 2, "James St keeps Little Shenton Lane clear (%d lane samples boxed)" % boxed)
				var frames: Array = Array(traffic.network_frames)
				frames.sort()
				var p95: float = frames[int(frames.size() * 0.95)] if not frames.is_empty() else 0.0
				# Most frames well inside budget, and no real stall; a single
				# slow frame on a loaded machine is the machine.
				_check(p95 < 30.0 and traffic.network_ms < 120.0, "map tiles join the road network without stalling a frame (95%% of %d frames under %.1f ms, worst %.1f ms, %d pieces that frame; slowest piece %.1f ms: %s)" % [
						frames.size(), p95, traffic.network_ms, traffic.network_frame_pieces, traffic.network_piece_ms, traffic.network_worst])
				var car = _main.get_node("LoFi/SubViewport/World/Car")
				_check(car.collision_mask & 4 != 0, "the player's car collides with traffic")
				# Wildlife: birds right by the player take off, ones further
				# away carry on pecking; a kangaroo close by bounds off.
				var wild: TrafficWildlife = traffic.wildlife
				wild.clear()
				wild.enabled = false
				var cp: Vector3 = car.global_position
				_mark.near_birds = wild.spawn_group(TrafficWildlife.Kind.MAGPIE, cp + Vector3(2.0, 0, 0), 1, false) \
						+ wild.spawn_group(TrafficWildlife.Kind.MAGPIE, cp + Vector3(0, 0, -2.0), 1, false)
				_mark.far_birds = wild.spawn_group(TrafficWildlife.Kind.IBIS, cp + Vector3(0, 0, 45), 3, false)
				_mark.roo = wild.spawn_group(TrafficWildlife.Kind.ROO, cp + Vector3(-9, 0, 0), 1, false)
				_mark.roo_start = cp + Vector3(-9, 0, 0)
				_next()
		15:  # Wildlife reacts to the player.
			if _seconds() >= 3.0:
				var traffic = _main.get_node("LoFi/SubViewport/World/Traffic")
				var wild: TrafficWildlife = traffic.wildlife
				_check(_mark.near_birds == 2 and _mark.far_birds == 3 and _mark.roo == 1, "wildlife appears where it's put (%d magpies, %d ibis, %d roo)" % [_mark.near_birds, _mark.far_birds, _mark.roo])
				var flying := 0
				var pecking := 0
				var hopped := 0.0
				for a in wild.animals:
					if a.kind == TrafficWildlife.Kind.MAGPIE and a.state == &"fly":
						flying += 1
					if a.kind == TrafficWildlife.Kind.IBIS and (a.state == &"idle" or a.state == &"walk"):
						pecking += 1
					if a.kind == TrafficWildlife.Kind.ROO:
						hopped = Vector2(a.node.position.x - _mark.roo_start.x, a.node.position.z - _mark.roo_start.z).length()
				_check(flying == 2, "magpies by the player fly off (%d of 2)" % flying)
				_check(pecking == 3, "birds further away carry on (%d of 3)" % pecking)
				_check(hopped > 10.0, "the kangaroo bounds away (%.0f m)" % hopped)
				wild.enabled = true
				_next()
		16:  # Boats on the Swan, and the ferry to Mends St.
			var traffic = _main.get_node("LoFi/SubViewport/World/Traffic")
			var boats: TrafficBoats = traffic.boats
			if not boats.ready_for_boats() and _seconds() < 30.0:
				return false
			_check(boats.ready_for_boats(), "the river map loads for the boats")
			_check(boats.water_at(Vector3(1000, 0, 1750)) and not boats.water_at(Vector3.ZERO), "Perth Water is water and Little Shenton Lane isn't")
			var dry := 0
			var docked_at_3am: bool = TrafficBoats.ferry_state(3.0)[2]
			var crossing := false
			for k in 2400:
				var st: Array = TrafficBoats.ferry_state(k / 100.0)
				if not boats.water_at(st[0]):
					dry += 1
				if not st[2]:
					crossing = true
			_check(dry == 0 and crossing and docked_at_3am, "the ferry stays on the river, crosses by day and ties up at night (%d dry spots)" % dry)
			boats.clear()
			boats.enabled = false
			_mark.boats = []
			for i in 3:
				var b: Dictionary = boats.spawn_boat(i, Vector3(1000 + i * 60, 0, 1750))
				if not b.is_empty():
					_mark.boats.append(b)
			_mark.dry_boat = boats.spawn_boat(TrafficBoats.Kind.YACHT, Vector3.ZERO).is_empty()
			_mark.boat_start = Vector3(1000, 0, 1750)
			_mark.boat_dry_frames = 0
			_next()
		17:  # Boats sail about and keep off the land.
			var traffic = _main.get_node("LoFi/SubViewport/World/Traffic")
			var boats: TrafficBoats = traffic.boats
			for b in _mark.boats:
				b.node.position.y = 0.0
				boats._sail(b, 1.0 / 60.0)
				if not boats.water_at(b.node.position):
					_mark.boat_dry_frames += 1
			if _seconds() >= 20.0:
				var moved := 0.0
				for b in _mark.boats:
					moved = maxf(moved, Vector2(b.node.position.x - _mark.boat_start.x, b.node.position.z - _mark.boat_start.z).length())
				_check(_mark.boats.size() == 3 and _mark.dry_boat, "boats go on the water and not on the land (%d of 3)" % _mark.boats.size())
				_check(moved > 30.0 and _mark.boat_dry_frames == 0, "boats sail about without running aground (%.0f m, %d dry frames)" % [moved, _mark.boat_dry_frames])
				boats.clear()
				boats.enabled = true
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


## A map tile adding a road to a set of lights that's already running must not
## restart its cycle or swap which way is green.
func _check_signal_rebuild() -> void:
	var g := TrafficGraph.new()
	var Y := 0.02
	var minor := { "kind": "residential" }
	g.add_data({ "nodes": [{ "id": 1, "p": [0, Y, 0], "ctrl": "signals" }, { "id": 2, "p": [-120, Y, 0] }, { "id": 3, "p": [0, Y, 120] }],
		"roads": [{ "id": "w", "a": 2, "b": 1, "kind": "residential", "pts": [Vector3(-120, Y, 0), Vector3(0, Y, 0)] },
			{ "id": "s", "a": 3, "b": 1, "kind": "residential", "pts": [Vector3(0, Y, 120), Vector3(0, Y, 0)] }] })
	var ctrl: TrafficGraph.SignalController = g.nodes[1].signal_controller
	for i in 40:
		ctrl.update(0.37)
	var west: TrafficGraph.Lane = g.nodes[1].roads[0].lanes_into(g.nodes[1])[0]
	var before := [ctrl.phase, ctrl.timer, west.signal_gate.state()]
	# The next tile brings the main road in from the east.
	g.add_data({ "nodes": [{ "id": 1, "p": [0, Y, 0], "ctrl": "signals" }, { "id": 4, "p": [150, Y, 0] }],
		"roads": [{ "id": "e", "a": 1, "b": 4, "kind": "primary", "lanes_fwd": 2, "lanes_back": 2, "pts": [Vector3(0, Y, 0), Vector3(150, Y, 0)] }] })
	ctrl = g.nodes[1].signal_controller
	var road_w: TrafficGraph.Road = null
	for r in g.nodes[1].roads:
		if r.other(g.nodes[1]).id == 2:
			road_w = r
	west = road_w.lanes_into(g.nodes[1])[0]
	var after := [ctrl.phase, ctrl.timer, west.signal_gate.state() if west.signal_gate else -1]
	_check(before == after, "lights keep their cycle when a new tile adds a road (%s -> %s)" % [before, after])


## The map's tiles go into the graph a few roads at a time: the result must
## match adding the whole lot at once.
func _check_pieces() -> void:
	var data: Dictionary = load("res://traffic/scripts/traffic_test_networks.gd").sandbox()
	var pieces: Array = _traffic._split_network(data)
	var g := TrafficGraph.new()
	for piece in pieces:
		g.add_data(piece)
	var sig := func(graph: TrafficGraph) -> Array:
		var yields := 0
		var stops := 0
		for c in graph.connectors:
			yields += c.yield_to.size()
		for l in graph.lanes:
			stops += l.stops.size()
		var approaches := 0
		# Lights where the biggest road gets the longer green.
		var main_green := 0
		for c in graph.signal_controllers:
			approaches += c.approaches.size()
			var best = null
			for ap in c.approaches:
				if best == null or ap.road.rank > best.road.rank:
					best = ap
			if best != null and c.green[best.group] >= c.green[1 - best.group]:
				main_green += 1
		return [graph.roads.size(), graph.lanes.size(), graph.connectors.size(), yields, stops,
			graph.signal_controllers.size(), approaches, main_green, graph.bus_stops.size(), graph.parking.size(), graph.crossings.size()]
	var whole: Array = sig.call(_graph)
	var split: Array = sig.call(g)
	_check(pieces.size() > 3 and whole == split, "road data added in %d pieces builds the same network (%s vs %s)" % [pieces.size(), split, whole])


func _check_graph() -> void:
	_check_signal_rebuild()
	_check_pieces()
	var g = _graph
	_check(g.roads.size() > 25, "sandbox network loads (%d roads)" % g.roads.size())
	_check(g.signal_controllers.size() == 2, "two signal junctions (%d)" % g.signal_controllers.size())
	_check(g.crossings.size() >= 6, "level crossings found where rail meets road (%d)" % g.crossings.size())
	_check(g.bus_stops.size() == 2, "bus stops placed on kerb lanes (%d)" % g.bus_stops.size())
	_check(g.ped_edges.size() > 50, "footpaths built (%d edges)" % g.ped_edges.size())
	_check(g.parking.size() == 38, "parking spots load (%d)" % g.parking.size())
	_check(g.bus_routes.size() == 2 and g.bus_routes["950"].roads.size() > 8, "bus routes load (%d)" % g.bus_routes.size())
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
	_mark.max_vehicles = maxi(_mark.max_vehicles, _traffic.vehicles.size())
	_mark.max_peds = maxi(_mark.max_peds, _traffic.pedestrians.size())
	var vs: Array = _traffic.vehicles
	for i in vs.size():
		var v = vs[i]
		if v.is_bus:
			_mark.buses = maxi(_mark.buses, 1)
			if _frame % 30 == 0 and v.bus_route != "" and not v.route[0].connector:
				var on: bool = _graph.bus_routes[v.bus_route].roads.has(v.route[0].road.key)
				_mark.route_samples = _mark.get("route_samples", 0) + 1
				_mark.on_route = _mark.get("on_route", 0) + (1 if on else 0)
		var lane = v.route[0]
		var was = _mark.signal_lane.get(v)
		if was != null and was != lane and was.signal_gate != null:
			_mark.passed_signal += 1
		_mark.signal_lane[v] = lane
		if _frame % 30 != 0:
			continue
		_mark.samples += 1
		if v.speed < 0.3 and absf(v.position.z - 3.2) < 3.5:
			var dx: float = absf(v.position.x - -72.0)
			if dx < 5.0 + v.length * 0.5 - 0.3:
				_mark.in_box = _mark.get("in_box", 0) + 1
			elif dx < 30.0 and v.position.x > -72.0:
				_mark.before_box = _mark.get("before_box", 0) + 1
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


func parents_has(sc, par: Dictionary) -> bool:
	return sc.parents.has(par)


func _seconds() -> float:
	return float(_frame) / FPS


## Empty the streets, reseed everyone's dice and restart the lights, so a
## step plays out the same on any machine.
func _settle() -> void:
	_traffic.clear_all()
	# Fresh cars and people, not ones from the pools carrying odd bits of
	# state from earlier steps.
	for pool in _traffic._pool.values():
		for v in pool:
			v.body.queue_free()
	_traffic._pool.clear()
	for p in _traffic._ped_pool:
		p.node.queue_free()
	_traffic._ped_pool.clear()
	# No ambulance on a random call pulling everyone over mid-step.
	_traffic.emergency_interval = Vector2.ZERO
	for module in [_traffic, _traffic.rides, _traffic.night, _traffic.paths, _traffic.kerbside, _traffic.schools, _traffic.events, _traffic.wildlife, _traffic.boats]:
		module._rng.seed = hash([_traffic.random_seed, _step])
	for c in _graph.signal_controllers:
		c.phase = 0
		c.timer = 0.0
	_traffic._spawn_timer = 0.0
	_traffic._train_timer = 20.0
	_traffic._density_timer = 0.0
	_traffic.rides._timer = 0.0
	_traffic.night._timer = 0.0


func _next() -> void:
	_step += 1
	_frame = 0
	print("  [t] step %d" % _step)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
