class_name RouteGuide
extends Node
## Suggested routes: the way by road to where the job you're on wants you
## next (or to a marker you've picked on the full map), keeping to one-ways
## and finding a new way when you leave it. The minimap and the full map draw
## it as a red line; with the setting on "Map and road" an amber band with
## arrowheads is painted on the road ahead as well.
##
## The HUD adds one of these; the maps find it with RouteGuide.of(tree).
## Settings.route_guide: 0 off, 1 the maps only, 2 the maps and the road.

## How far (m) off the route counts as having left it, and for how long.
const OFF_ROUTE := 22.0
const OFF_TIME := 1.0
## Heading back the way the route came for this long (s) finds a new way.
const WRONG_WAY_TIME := 3.5
## Least time (s) between two searches, and between tries when there was
## no way at all (nowhere near a road).
const MIN_GAP := 1.5
const NO_WAY_RETRY := 5.0
## How close (m) to a marker counts as there, which ends its route.
const MARKER_REACHED := 25.0
## On the road: a band down your side of it with an arrowhead every so
## often. The band's width is what reads from a low chase camera (a mark
## lying flat shrinks to a sliver lengthways, not sideways). How far ahead it
## starts and stops (m), the spacing of the band's points and arrowheads,
## and their sizes.
const ARROWS_FROM := 4.0
const ARROWS_TO := 130.0
const BAND_STEP := 2.5
const BAND_HALF_WIDTH := 0.7
const ARROW_STEP := 15.0
const ARROW_HALF_WIDTH := 1.7
const ARROW_LENGTH := 3.0
const ARROW_LIFT := 0.15
const ARROW_COLOUR := Color(1.0, 0.7, 0.16)

## Down the middle of each road on the way, from where the search started.
var points := PackedVector3Array()
## Down the middle of your side of the road (the arrows go on this).
var lane := PackedVector3Array()
var length := 0.0
## Where it's going (world), INF for nowhere.
var target := Vector3.INF
## How far along `points` the player is now (m).
var progress := 0.0

var _cum := PackedFloat32Array()
var _lane_cum := PackedFloat32Array()
var _task := -1
var _result: Dictionary = {}
var _asked_for := Vector3.INF
var _again := false
var _since_search := 99.0
var _off_time := 0.0
var _wrong_time := 0.0
var _lead_in := 0.0
var _ahead := PackedVector2Array()
var _ahead_at := -1.0
var _arrows: MeshInstance3D
var _arrows_at := -1.0
var _arrows_shown := false
var _heights := {}  # arrow number -> [position, normal]


static func of(tree: SceneTree) -> RouteGuide:
	return tree.get_first_node_in_group(&"route_guide") as RouteGuide if tree else null


func _ready() -> void:
	add_to_group(&"route_guide")
	# Keeps going under the full map (which pauses), so "Go here" shows up.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## True while there's a route to draw.
func has_route() -> bool:
	return points.size() >= 2 and Settings.route_guide > 0


## The rest of the route from where the player is (world x/z), for the maps,
## or the next `reach` metres of it.
func ahead(reach := INF) -> PackedVector2Array:
	if not has_route():
		return PackedVector2Array()
	if reach == INF:
		return _ahead
	var run := 0.0
	for i in range(1, _ahead.size()):
		run += _ahead[i - 1].distance_to(_ahead[i])
		if run > reach:
			return _ahead.slice(0, i + 1)
	return _ahead


## Straight bits the roads don't cover, as pairs of world x/z: from the
## player to the route while they're not on it yet, and from the route's end
## to the place itself (a car park, a lane the map has no road for).
func loose_ends() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not has_route():
		return out
	var p := MapPins.player_position(get_tree())
	if p != Vector3.INF and progress < 1.0 and _ahead.size() > 0:
		var start := _ahead[0]
		if start.distance_to(Vector2(p.x, p.z)) > 8.0:
			out.append_array([Vector2(p.x, p.z), start])
	var end := points[points.size() - 1]
	if target != Vector3.INF and Vector2(end.x, end.z).distance_to(Vector2(target.x, target.z)) > 8.0:
		out.append_array([Vector2(end.x, end.z), Vector2(target.x, target.z)])
	return out


## Metres of road left to go.
func left_to_go() -> float:
	return maxf(length - progress, 0.0) if has_route() else 0.0


## Where to go: the job's next stop, else the marker you picked to go to.
func _destination() -> Vector3:
	var site := Jobs.target_site() if Jobs.has_method("target_site") else null
	if site and site.is_inside_tree():
		return site.global_position
	var m := MapPins.route_marker
	if m >= 0 and m < MapPins.markers.size():
		var at: Vector2 = MapPins.markers[m].at
		return Vector3(at.x, 0.0, at.y)
	return Vector3.INF


func _process(delta: float) -> void:
	_since_search += delta
	_collect()
	var mode: int = Settings.route_guide
	var where := _destination() if mode > 0 else Vector3.INF
	var data := MapData.shared()
	if where == Vector3.INF or not data.is_loaded or data.routes.road_count() == 0:
		if target != Vector3.INF or not points.is_empty():
			_clear()
		target = where
		_show_arrows(false)
		return
	var tree := get_tree()
	var p := MapPins.player_position(tree)
	if p == Vector3.INF:
		return
	var car := MapPins.player_car(tree)
	var driving := car != null and MapPins.in_car(tree)
	var heading := _heading()
	if MapPins.route_marker >= 0 and Jobs.target_site() == null \
			and Vector2(p.x, p.z).distance_to(Vector2(where.x, where.z)) < MARKER_REACHED:
		MapPins.route_marker = -1  # there: the route's done its job
		return
	if target == Vector3.INF or Vector2(where.x, where.z).distance_to(Vector2(target.x, target.z)) > 3.0:
		_clear()
		target = where
		_search(p, heading)
	elif points.size() < 2 and _task == -1 and _since_search > NO_WAY_RETRY:
		_search(p, heading)  # no way from where they were: try again from here
	if points.size() >= 2:
		_track(p, heading, driving, car, delta)
	_show_arrows(mode >= 2 and driving and points.size() >= 2)


## Looks for a way from `from` to the target on a worker thread.
func _search(from: Vector3, heading: Vector2) -> void:
	if _task != -1:
		_again = true
		return
	var graph := MapData.shared().routes
	var to := target
	_asked_for = to
	_since_search = 0.0
	_again = false
	_lead_in = 0.0
	_task = WorkerThreadPool.add_task(func() -> void:
		_result = graph.find(from, heading, to), false, "Route")


## Picks up a search that's finished.
func _collect() -> void:
	if _task == -1 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var r := _result
	_result = {}
	if _asked_for != target or _again:
		# Somewhere else by now, or off the route again: look again from here.
		var here := MapPins.player_position(get_tree())
		if here != Vector3.INF and target != Vector3.INF:
			_search(here, _heading())
		return
	if r.is_empty():
		points = PackedVector3Array()
		lane = PackedVector3Array()
		length = 0.0
	else:
		points = r.points
		lane = r.lane
		_cum = TrafficGraph.cumulative(points)
		_lane_cum = TrafficGraph.cumulative(lane)
		length = float(r.length)
	progress = 0.0
	_off_time = 0.0
	_wrong_time = 0.0
	_ahead_at = -1.0
	_arrows_at = -1.0
	_heights.clear()
	var p := MapPins.player_position(get_tree())
	if p != Vector3.INF and points.size() >= 2:
		_lead_in = Vector2(p.x, p.z).distance_to(Vector2(points[0].x, points[0].z))
	_update_ahead()


func _clear() -> void:
	points = PackedVector3Array()
	lane = PackedVector3Array()
	length = 0.0
	progress = 0.0
	_ahead = PackedVector2Array()
	_ahead_at = -1.0
	_heights.clear()
	_asked_for = Vector3.INF


## The way the player faces (world x/z).
func _heading() -> Vector2:
	var yaw := MapPins.player_yaw(get_tree())
	return Vector2(-sin(yaw), -cos(yaw))


## Keeps up with the player along the route, and finds a new one when they
## leave it or turn back.
func _track(p: Vector3, heading: Vector2, driving: bool, car: CarController, delta: float) -> void:
	var at := Vector2(p.x, p.z)
	var lo := progress - 40.0
	var hi := progress + 300.0
	var best_s := progress
	var best_d := INF
	for i in points.size() - 1:
		if _cum[i + 1] < lo:
			continue
		if _cum[i] > hi:
			break
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(at, a, b)
		var d := q.distance_to(at)
		if d < best_d:
			best_d = d
			best_s = _cum[i] + a.distance_to(q)
	progress = best_s
	if absf(progress - _ahead_at) > 0.5:
		_update_ahead()
	if not driving:
		_off_time = 0.0
		_wrong_time = 0.0
		return
	# Not on the route yet (just pulled out of a lane the roads don't cover).
	var reach := OFF_ROUTE if progress > 1.0 else maxf(OFF_ROUTE, _lead_in + 12.0)
	_off_time = _off_time + delta if best_d > reach else 0.0
	var wrong := false
	if car and absf(car.speed_kmh()) > 10.0 and best_d < OFF_ROUTE:
		var t := TrafficGraph.tangent_at(points, _cum, progress)
		wrong = Vector2(t.x, t.z).dot(heading) < -0.5 and car.speed_kmh() > 0.0
	_wrong_time = _wrong_time + delta if wrong else 0.0
	if (_off_time > OFF_TIME or _wrong_time > WRONG_WAY_TIME) and _since_search > MIN_GAP:
		_off_time = 0.0
		_wrong_time = 0.0
		_search(p, heading)


func _update_ahead() -> void:
	_ahead_at = progress
	_ahead = PackedVector2Array()
	if points.size() < 2:
		return
	var first := TrafficGraph.point_at(points, _cum, progress)
	_ahead.append(Vector2(first.x, first.z))
	for i in points.size():
		if _cum[i] > progress + 0.5:
			_ahead.append(Vector2(points[i].x, points[i].z))


# --- arrows on the road ---------------------------------------------------------

func _show_arrows(show: bool) -> void:
	if not show:
		if _arrows and _arrows_shown:
			_arrows.visible = false
			_arrows_shown = false
		return
	if _arrows == null or not is_instance_valid(_arrows):
		var car := MapPins.player_car(get_tree())
		if car == null or car.get_parent() == null:
			return
		_arrows = MeshInstance3D.new()
		_arrows.name = "RouteArrows"
		_arrows.top_level = true
		_arrows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Bright through mist and dusk, like the job's beacon.
		m.disable_fog = true
		_arrows.material_override = m
		car.get_parent().add_child(_arrows)
		_arrows_at = -1.0
	if not _arrows_shown:
		_arrows.visible = true
		_arrows_shown = true
	if absf(progress - _arrows_at) > 0.4:
		_build_arrows()


## The band and arrowheads along your side of the road ahead, at fixed
## spots on the route so they stay put as you drive over them, fading in
## near the car and out in the distance.
func _build_arrows() -> void:
	_arrows_at = progress
	if lane.size() < 2 or length <= 0.0:
		_arrows.mesh = null
		return
	var lane_len := _lane_cum[_lane_cum.size() - 1]
	var scale := lane_len / length
	var space := _arrows.get_world_3d().direct_space_state if _arrows.is_inside_tree() else null
	var car := MapPins.player_car(get_tree())
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var end := minf(progress + ARROWS_TO, length - 1.0)
	# The band: a strip through points every BAND_STEP metres.
	var prev: Array = []
	for k in range(ceili((progress + ARROWS_FROM) / BAND_STEP), floori(end / BAND_STEP) + 1):
		var spot := _spot(k * BAND_STEP, scale, space, car)
		var c := Color(ARROW_COLOUR, 0.75 * _fade(k * BAND_STEP))
		var l: Vector3 = spot[0] + spot[2] * BAND_HALF_WIDTH
		var r: Vector3 = spot[0] - spot[2] * BAND_HALF_WIDTH
		if not prev.is_empty():
			verts.append_array(PackedVector3Array([prev[0], prev[1], l, l, prev[1], r]))
			colours.append_array(PackedColorArray([prev[2], prev[2], c, c, prev[2], c]))
		prev = [l, r, c]
	# Arrowheads, wider than the band, pointing the way.
	for k in range(ceili((progress + ARROWS_FROM + ARROW_LENGTH) / ARROW_STEP), floori(end / ARROW_STEP) + 1):
		var s := k * ARROW_STEP
		var c := Color(ARROW_COLOUR, _fade(s))
		var tip: Array = _spot(s, scale, space, car)
		var back: Array = _spot(s - ARROW_LENGTH, scale, space, car)
		var lift := Vector3.UP * 0.02  # over the band
		var wing_l: Vector3 = back[0] + back[2] * ARROW_HALF_WIDTH + lift
		var wing_r: Vector3 = back[0] - back[2] * ARROW_HALF_WIDTH + lift
		var notch: Vector3 = (back[0] as Vector3).lerp(tip[0], 0.35) + lift
		verts.append_array(PackedVector3Array([tip[0] + lift, wing_l, notch, tip[0] + lift, notch, wing_r]))
		for i in 6:
			colours.append(c)
	if verts.is_empty():
		_arrows.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_arrows.mesh = mesh


## Fades in just ahead of the car and out in the distance.
func _fade(s: float) -> float:
	var ahead := s - progress
	return smoothstep(ARROWS_FROM - 1.0, ARROWS_FROM + 5.0, ahead) * (1.0 - smoothstep(ARROWS_TO * 0.6, ARROWS_TO, ahead))


## A spot `s` metres along the route on your side of the road, on the road
## surface: [position (lifted), forward, sideways (left)].
func _spot(s: float, scale: float, space: PhysicsDirectSpaceState3D, car: CarController) -> Array:
	var k := roundi(s * 10.0)
	var ground: Array = _ground(k, TrafficGraph.point_at(lane, _lane_cum, s * scale), space, car)
	var up: Vector3 = ground[1]
	var t := TrafficGraph.tangent_at(lane, _lane_cum, s * scale)
	var fwd := (t - up * t.dot(up)).normalized()
	return [ground[0] + up * ARROW_LIFT, fwd, up.cross(fwd).normalized()]


## The road surface at a spot on the route (key: decimetres along it):
## [position, normal], found once per spot.
func _ground(k: int, at: Vector3, space: PhysicsDirectSpaceState3D, car: CarController) -> Array:
	if _heights.has(k):
		return _heights[k]
	var spot := [at, Vector3.UP]
	if space:
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at + Vector3.DOWN * 5.0, MapTileLoader.LAYER_WORLD)
		if car:
			q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			spot = [hit.position, n if n.y > 0.7 else Vector3.UP]
		else:
			return spot  # the tile isn't in yet: look again next time
	_heights[k] = spot
	return spot
