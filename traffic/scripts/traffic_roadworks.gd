class_name TrafficRoadworks
extends Node3D
## Roadworks: one lane of a multi-lane road coned off for a few days, then the
## crew moves on somewhere else. Traffic in the closed lane merges out before
## the cones and everyone slows past the works (TrafficManager reads
## `Lane.closed`). Each site has cones the player can knock flying, a
## barrier, a "ROADWORK" sign up the road, a works ute with its beacon
## going, and a couple of workers in the daytime.
##
## Which roads have works on which days is a pure function of the road and
## the day (site_for), so the same works are there whenever the player comes
## back that day. Sites only appear or clear away out of view.

## Chance an eligible road has works in any given few-day block.
@export var site_chance := 0.06
## Sites are kept up to date within this distance of the player.
@export var radius := 600.0
## How many days a crew stays.
const STAY_DAYS := 3
const CONE_STEP := 4.5
const TAPER := 22.0

var graph: TrafficGraph
## road key -> site Dictionary (see _make_site).
var sites := {}
var _manager: Node
var _timer := 0.0
var _version := -1


func setup(manager: Node, traffic_graph: TrafficGraph) -> void:
	_manager = manager
	graph = traffic_graph


## Whether `road` can take roadworks: a long enough multi-lane road.
static func eligible(road: TrafficGraph.Road) -> bool:
	if road.roundabout or road.length < 140.0 or road.rank < 2:
		return false
	return road.lanes_fwd >= 2 or road.lanes_back >= 2


## The works on `road` on `day`: {} for none, else { fwd, k, s0, s1 }
## (s along the closed lane's direction).
func site_for(road: TrafficGraph.Road, day: int) -> Dictionary:
	if not eligible(road):
		return {}
	var h: int = hash(road.key)
	var block := int(floor(float(day + posmod(h, STAY_DAYS)) / STAY_DAYS))
	var roll := float(hash([road.key, block]) & 0xffff) / 65536.0
	if roll >= site_chance:
		return {}
	var pick: int = hash([road.key, block, 3])
	var fwd := road.lanes_fwd >= 2
	if road.lanes_fwd >= 2 and road.lanes_back >= 2:
		fwd = pick & 1 == 0
	var count: int = road.lanes_fwd if fwd else road.lanes_back
	# Kerb lane mostly, sometimes the one by the centre line.
	var k: int = count - 1 if (pick >> 1) % 3 != 0 else 0
	var len := 45.0 + float((pick >> 3) % 30)
	var s0: float = road.length * (0.35 + float((pick >> 8) % 20) / 100.0)
	return { "fwd": fwd, "k": k, "s0": s0, "s1": minf(s0 + len, road.length - 30.0) }


func update(delta: float, focus: Vector3) -> void:
	_timer -= delta
	_update_beacons()
	if _timer > 0.0 or graph == null:
		return
	_timer = 1.0
	_check_cones()
	# Lanes are rebuilt when map tiles arrive: put the closures back on.
	if graph.version != _version:
		_version = graph.version
		for key in sites:
			_apply(sites[key])
	var seen := {}
	for entry in graph.samples_near(focus, radius):
		var lane: TrafficGraph.Lane = entry[0]
		if lane.connector or lane.road == null or seen.has(lane.road):
			continue
		seen[lane.road] = true
		var road := lane.road
		var want := site_for(road, GameClock.day)
		var have: Dictionary = sites.get(road.key, {})
		if have.get("pinned", false):
			continue
		if want.is_empty() == have.is_empty() and (want.is_empty() or _same(want, have)):
			continue
		var at := _road_point(road, want if not want.is_empty() else have)
		# Never pop in or vanish in front of the player.
		if at.distance_to(focus) < 220.0 or _manager._visible(at, 60.0):
			continue
		if not have.is_empty():
			remove_site(road.key)
		if not want.is_empty():
			add_site(road, want.fwd, want.k, want.s0, want.s1, false)
	# Far away: clear up.
	for key in sites.keys():
		var site: Dictionary = sites[key]
		if not site.pinned and site.pos.distance_to(focus) > radius + 150.0:
			remove_site(key)


## Close lane `k` of `road` (forward or back) between s0 and s1. Returns the
## site. Sites added from outside (pinned) stay until removed.
func add_site(road: TrafficGraph.Road, fwd: bool, k: int, s0: float, s1: float, pinned := true) -> Dictionary:
	remove_site(road.key)
	var site := { "road": road, "fwd": fwd, "k": k, "s0": s0, "s1": s1, "nodes": [], "cones": [], "beacons": [], "pinned": pinned }
	site.pos = _road_point(road, site)
	sites[road.key] = site
	_apply(site)
	_build(site)
	return site


func remove_site(key: String) -> void:
	var site: Dictionary = sites.get(key, {})
	if site.is_empty():
		return
	sites.erase(key)
	var lane := _lane_of(site)
	if lane:
		lane.closed = []
	for n in site.nodes:
		n.queue_free()


func clear() -> void:
	for key in sites.keys():
		remove_site(key)


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.fwd == b.fwd and a.k == b.k and is_equal_approx(a.s0, b.s0)


func _lane_of(site: Dictionary) -> TrafficGraph.Lane:
	var road: TrafficGraph.Road = site.road
	for lane in road.lanes:
		if (lane.from_node == road.a) == site.fwd and lane.k == site.k:
			return lane
	return null


func _road_point(road: TrafficGraph.Road, site: Dictionary) -> Vector3:
	var s: float = (site.s0 + site.s1) * 0.5
	return TrafficGraph.point_at(road.pts, road.cum, s if site.fwd else road.length - s)


## Mark the closed stretch on the lane (lane s runs from its own start, which
## is trimmed back from the road's ends at junctions).
func _apply(site: Dictionary) -> void:
	var lane := _lane_of(site)
	if lane == null:
		return
	var road: TrafficGraph.Road = site.road
	var a := TrafficGraph.point_at(road.pts, road.cum, site.s0 if site.fwd else road.length - site.s0)
	var b := TrafficGraph.point_at(road.pts, road.cum, site.s1 if site.fwd else road.length - site.s1)
	var s0 := TrafficGraph.closest_s(lane.pts, lane.cum, a)
	var s1 := TrafficGraph.closest_s(lane.pts, lane.cum, b)
	# The closure starts where the cone taper does, so nobody drives into it.
	lane.closed = [maxf(minf(s0, s1) - TAPER, 0.0), maxf(s0, s1)]


func _build(site: Dictionary) -> void:
	var lane := _lane_of(site)
	if lane == null or lane.closed.is_empty():
		return
	var open: TrafficGraph.Lane = lane.right_lane if lane.right_lane else lane.left_lane
	var taper0: float = lane.closed[0]
	var s0: float = minf(taper0 + TAPER, lane.closed[1])
	var s1: float = lane.closed[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(site.road.key)
	# Cones: a taper in from the far edge of the lane, then a line along the
	# edge with the open lane, then back out at the far end.
	var s := taper0
	while s <= s1:
		var p := lane.point(s)
		var dir := lane.tangent(s)
		var to_open := _side_to(lane, open, s, dir)
		var t := clampf((s - taper0) / maxf(s0 - taper0, 0.1), 0.0, 1.0)
		# t = 0: the far edge of the lane; 1: the edge with the open lane.
		var edge := p + to_open * lerpf(-TrafficGraph.LANE_WIDTH * 0.45, TrafficGraph.LANE_WIDTH * 0.45, t)
		_cone(site, edge)
		s += CONE_STEP if t >= 1.0 else CONE_STEP * 0.7
	var end := lane.point(s1)
	_cone(site, end + _side_to(lane, open, s1, lane.tangent(s1)) * -TrafficGraph.LANE_WIDTH * 0.2)
	# Barrier across the closed lane where the taper meets it.
	var bp := lane.point(s0 + 2.0)
	var bdir := lane.tangent(s0 + 2.0)
	var barrier := TrafficModels.works_barrier()
	barrier.position = bp
	barrier.basis = Basis(Vector3.UP.cross(bdir).normalized(), Vector3.UP, bdir)
	_add(site, barrier)
	# Sign at the kerb a way back up the road.
	var sign_s := maxf(taper0 - 60.0, 2.0)
	var sp := lane.point(sign_s)
	var sdir := lane.tangent(sign_s)
	var sign := TrafficModels.works_sign()
	# Out past the kerb lane, on the verge.
	sign.position = sp + TrafficGraph.left_of(sdir) * (TrafficGraph.LANE_WIDTH * float(lane.count - 1 - lane.k) + 2.6)
	sign.basis = Basis(Vector3.UP.cross(sdir).normalized(), Vector3.UP, sdir).rotated(Vector3.UP, PI)
	_add(site, sign)
	# The works ute, parked in the closed lane with its beacon going.
	var us: float = s0 + (s1 - s0) * 0.35
	var ute := TrafficModels.works_ute()
	ute.position = lane.point(us)
	ute.basis = Basis.looking_at(lane.tangent(us), Vector3.UP)
	_add(site, ute)
	site.beacons.append(ute.get_node("Beacon"))
	# A couple of workers in hi-vis during the day (they're lit by the ute's
	# beacon otherwise, which is spooky enough).
	var hour := GameClock.time_of_day
	if hour > 6.5 and hour < 17.5:
		for i in 2:
			var ws: float = s0 + (s1 - s0) * (0.55 + i * 0.2)
			var person := TrafficModels.person(rng)
			var shirt := TrafficModels.material(Color(1.0, 0.45, 0.05))
			for part in person.find_children("*", "MeshInstance3D", true, false):
				if part.get_parent().name.begins_with("Arm") or part.mesh == TrafficModels._part_mesh("torso", Vector3(0.42, 0.62, 0.24), Vector3.ZERO):
					part.material_override = shirt
			person.position = lane.point(ws) + _side_to(lane, open, ws, lane.tangent(ws)) * rng.randf_range(-0.6, 0.4)
			person.rotation.y = rng.randf() * TAU
			_add(site, person)


func _side_to(lane: TrafficGraph.Lane, open: TrafficGraph.Lane, s: float, dir: Vector3) -> Vector3:
	if open != null:
		var d := open.point(s) - lane.point(s)
		d.y = 0.0
		if d.length() > 0.5:
			return d.normalized()
	return -TrafficGraph.left_of(dir)


func _add(site: Dictionary, node: Node3D) -> void:
	add_child(node)
	site.nodes.append(node)


func _cone(site: Dictionary, p: Vector3) -> void:
	var cone := TrafficModels.cone_body()
	cone.position = p
	cone.collision_layer = _manager.TRAFFIC_LAYER
	_add(site, cone)
	site.cones.append(cone)


## A cone the player knocked: a bonk, once.
func _check_cones() -> void:
	for key in sites:
		for cone in sites[key].cones:
			if cone.sleeping or cone.get_meta("hit", false):
				continue
			if cone.linear_velocity.length() > 1.5:
				cone.set_meta("hit", true)
				var audio := get_node_or_null("/root/Audio")
				if audio and audio.has_method("play_at"):
					audio.play_at("impact/impact_traffic_cone", cone.global_position, -2.0, "SFX")


func _update_beacons() -> void:
	if sites.is_empty():
		return
	var on := int(Time.get_ticks_msec() / 300) % 2 == 0
	for key in sites:
		for beacon in sites[key].beacons:
			if not beacon.has_meta("on") or beacon.get_meta("on") != on:
				beacon.set_meta("on", on)
				beacon.material_override = TrafficModels.material(Color(1.0, 0.6, 0.05), 4.0) if on else TrafficModels.material(Color(0.5, 0.3, 0.05))
