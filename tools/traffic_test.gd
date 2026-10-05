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
	# A driveway on the avenue, inside the westbound queue for the Station
	# Street lights: nobody may stop across it.
	_graph.add_keep_clear(Vector3(-72, 0, 3.2), 5.0)


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
				_mark.walker.global_position = Vector3(-40, 0, 4.8)
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
				root.get_node("GameClock").set_time(8.0)
				_root3d.queue_free()
				_next()
		12:  # The main scene gets traffic on the Perth map's roads.
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
				_check(traffic.network_ms < 30.0, "map tiles join the road network without stalling a frame (worst %.1f ms, %d pieces that frame; slowest piece %.1f ms: %s)" % [
						traffic.network_ms, traffic.network_frame_pieces, traffic.network_piece_ms, traffic.network_worst])
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
		13:  # Wildlife reacts to the player.
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
		14:  # Boats on the Swan, and the ferry to Mends St.
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
		15:  # Boats sail about and keep off the land.
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


func _next() -> void:
	_step += 1
	_frame = 0
	print("  [t] step %d" % _step)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
