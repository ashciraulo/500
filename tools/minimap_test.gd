extends SceneTree
## Headless check of the minimap and the full map on the real Perth map: the
## road data loads, the minimap knows the street you're in, M opens the full
## map (and pauses), markers go down, save and load, and M closes it again.
## Then suggested routes: one-ways kept to, a job's route on the minimap, a
## new one after leaving it, and none with the setting off.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/minimap_test.gd -- --no-save
##
## Exits with code 1 if any check fails. CI runs this.

const FPS := 60

var _main: Node
var _failures: Array[String] = []
var _step := 0
var _frame := 0
var _quitting := false
var _route_start := Vector3.ZERO
## Loaded when used: these read autoloads, which a --script tool can't name.
var _pins: GDScript
var _data: GDScript


func _initialize() -> void:
	_pins = load("res://scripts/ui/map_pins.gd")
	_data = load("res://scripts/ui/map_data.gd")


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frame += 1
	match _step:
		0:
			if _frame >= FPS * 3:
				var data: RefCounted = _data.call("shared")
				data.call("wait")
				_check(data.get("is_loaded"), "map data loaded")
				_check(int(data.get("road_count")) > 1000, "roads read from the tiles (%d)" % data.get("road_count"))
				_check(data.get("ground") != null, "ground read from the overview")
				_check((data.get("labels") as Array).size() > 100, "street names to print (%d)" % (data.get("labels") as Array).size())
				var home := Vector3(-1.37, 22.09, -0.73)
				_check(data.call("street_at", home) == "Little Shenton Lane", "street at home: %s" % data.call("street_at", home))
				_check(data.call("suburb_at", home) == "Northbridge", "suburb at home: %s" % data.call("suburb_at", home))
				print("  lanes and car park aisles drawn: %d" % data.get("lane_count"))
				# Named lanes answer "where am I"; driveways stay off the map.
				var far := Vector3(40000, 0, 40000)
				var lanes := [
					{pts = PackedVector3Array([far, far + Vector3(60, 0, 0)]), kind = "alley", name = "Test Lane"},
					{pts = PackedVector3Array([far + Vector3(0, 0, 200), far + Vector3(60, 0, 200)]), kind = "driveway", name = "Test Drive"},
				]
				var before := int(data.get("lane_count"))
				data.call("add_service_roads", lanes)
				_check(int(data.get("lane_count")) == before + 1, "service roads read, driveways left off")
				_check(data.call("street_at", far + Vector3(30, 0, 3)) == "Test Lane", "named lane: %s" % data.call("street_at", far + Vector3(30, 0, 3)))
				var pins: Array = _pins.call("gather", self, true)
				_check(pins.any(func(p: Dictionary) -> bool: return p.icon == "home"), "home is on the map")
				_next()
		1:
			if _frame >= FPS:
				var mini := _main.find_child("Minimap", true, false)
				_check(mini != null and mini.is_visible_in_tree(), "minimap on the HUD")
				if mini:
					_check(String(mini.get("_street").text) == "Little Shenton Lane", "minimap chip: %s" % mini.get("_street").text)
				_press("map")
				_next()
		2:
			if _frame >= 10:
				var screen := _main.get_node_or_null("MapScreen")
				_check(screen != null and screen.call("is_open"), "M opens the full map")
				_check(paused, "the game pauses under the map")
				if screen:
					var view: Control = screen.get("_view")
					screen.call("_place_or_pick", view.size * 0.5)
					_check((_pins.markers as Array).size() == 1, "a marker goes down")
					var saved: Dictionary = screen.call("save_state")
					_pins.call("remove_marker", 0)
					screen.call("load_state", saved)
					_check((_pins.markers as Array).size() == 1, "markers save and load")
				_press("map")
				_next()
		3:
			if _frame >= 10:
				var screen := _main.get_node_or_null("MapScreen")
				_check(screen != null and not screen.call("is_open"), "M closes it again")
				_check(not paused, "the game carries on")
				_check_route_graph()
				_take_job()
				_next()
		4:
			# Suggested routes: the job's route comes in on its own.
			var guide := root.get_tree().get_first_node_in_group(&"route_guide")
			if _frame >= FPS * 2:
				_check(guide != null, "a route guide on the HUD")
				if guide == null:
					return _finish()
				_check(guide.call("has_route"), "a route to the job (%.0f m)" % float(guide.get("length")))
				var mini := _main.find_child("Minimap", true, false)
				var view: Control = mini.get("_view") if mini else null
				_check(view != null and (view.get("route") as PackedVector2Array).size() >= 2, "the minimap draws it")
				_route_start = (guide.get("points") as PackedVector3Array)[0]
				# Leave it: off down the road somewhere else.
				var car: RigidBody3D = _main.get_node("LoFi/SubViewport/World/Car")
				var off := _route_start + Vector3(250.0, 0.0, 250.0)
				var hit: Array = _data.call("shared").get("routes").call("nearest", Vector2(off.x, off.z))
				if not hit.is_empty():
					var g: RefCounted = _data.call("shared").get("routes")
					var r: int = hit[0][0]
					var p: Vector3 = TrafficGraph.point_at(g.get("road_pts")[r], g.get("road_cum")[r], float(hit[0][1]))
					car.global_transform = Transform3D(Basis.IDENTITY, p + Vector3.UP)
					car.linear_velocity = Vector3.ZERO
				_next()
		5:
			if _frame >= FPS * 4:
				var guide := root.get_tree().get_first_node_in_group(&"route_guide")
				var pts: PackedVector3Array = guide.get("points")
				_check(pts.size() >= 2 and pts[0].distance_to(_route_start) > 100.0, "a new route after leaving it")
				root.get_node("Settings").set("route_guide", 0)
				_next()
		6:
			if _frame >= 10:
				var guide := root.get_tree().get_first_node_in_group(&"route_guide")
				var mini := _main.find_child("Minimap", true, false)
				_check(not guide.call("has_route"), "no route with it turned off")
				_check((mini.get("_view").get("route") as PackedVector2Array).is_empty(), "nothing on the minimap")
				root.get_node("Settings").set("route_guide", 2)
				root.get_node("Jobs").call("abandon")
				return _finish()
	return false


## The road network for routes: one-ways are kept to, and ways are found.
func _check_route_graph() -> void:
	var g: RefCounted = _data.call("shared").get("routes")
	_check(int(g.call("road_count")) > 10000, "roads joined up for routes (%d)" % g.call("road_count"))
	var home := Vector3(-1.37, 22.09, -0.73)
	var subiaco := Vector3(-2900.87, 29.32, 202.66)
	var r: Dictionary = g.call("find", home, Vector2.ZERO, subiaco)
	var straight := home.distance_to(subiaco)
	_check(not r.is_empty() and float(r.length) > straight * 0.9 and float(r.length) < straight * 2.0,
		"a way from home to Subiaco (%.0f m, %.0f m as the crow flies)" % [float(r.get("length", 0.0)), straight])
	# Backwards along a long one-way: never straight down it the wrong way.
	var oneway := -1
	for i in int(g.call("road_count")):
		if g.get("road_oneway")[i] == 1 and g.get("road_len")[i] > 150.0:
			oneway = i
			break
	if oneway < 0:
		_check(false, "a one-way to try")
		return
	var pts: PackedVector3Array = g.get("road_pts")[oneway]
	var cum: PackedFloat32Array = g.get("road_cum")[oneway]
	var length: float = g.get("road_len")[oneway]
	var a := TrafficGraph.point_at(pts, cum, length * 0.8)
	var b := TrafficGraph.point_at(pts, cum, length * 0.2)
	var t := TrafficGraph.tangent_at(pts, cum, length * 0.8)
	var back: Dictionary = g.call("find", a, Vector2(t.x, t.z), b)
	_check(back.is_empty() or float(back.length) > length * 0.6 + 20.0,
		"one-ways only one way (%.0f m round, %.0f m straight back)" % [float(back.get("length", 0.0)), length * 0.6])
	var fwd: Dictionary = g.call("find", b, Vector2(t.x, t.z), a)
	_check(not fwd.is_empty() and absf(float(fwd.length) - length * 0.6) < 15.0, "and straight down it the right way (%.0f m)" % float(fwd.get("length", 0.0)))


func _take_job() -> void:
	var jobs := root.get_node("Jobs")
	jobs.call("refresh_offers")
	for o: Dictionary in jobs.get("offers"):
		if o.get("type", "") == "delivery":
			jobs.call("accept", o)
			return
	_check(false, "a delivery on the job board")


func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _next() -> void:
	_step += 1
	_frame = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	if _failures.is_empty():
		print("MINIMAP TEST PASSED")
	else:
		print("MINIMAP TEST FAILED (%d)" % _failures.size())
		for f in _failures:
			print("  - " + f)
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(0 if _failures.is_empty() else 1)
	return false
