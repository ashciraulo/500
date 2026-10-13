extends SceneTree
## Screenshots of every findable from the road, the way you'd come up on it:
## the mystery's clues at 1 am, the found parts, the cuttings and the barn
## finds by day and by night, and a few of the 500 badges. Each is shot from
## the chase camera with the car on the nearest road, heading toward it, FAR
## and NEAR metres away. For checking that things are easy to spot. Needs a
## display (or xvfb):
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/findables_screens.gd -- --no-save shots=/tmp/findables [only=clues,parts,cuttings,barns,badges] [ids=tape_1,...]

const FAR := 40.0
const NEAR := 15.0

var _shots := "/tmp/findables"
var _only := PackedStringArray()
var _ids := PackedStringArray()
var _main: Node
var _world: Node3D
var _car: RigidBody3D
var _m: Node
var _step := -1
var _frames := 0
var _steps: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=").split(",")
		elif arg.begins_with("ids="):
			_ids = arg.trim_prefix("ids=").split(",")
	DirAccess.make_dir_recursive_absolute(_shots)


func _want(what: String, id := "") -> bool:
	return (_only.is_empty() or _only.has(what)) and (_ids.is_empty() or id == "" or _ids.has(id))


func _build_steps() -> void:
	if _want("clues"):
		for c: Dictionary in _m.clues:
			var id := String(c.id)
			if not _want("clues", id):
				continue
			var at: Vector3 = _m.spot_position(id)
			var setup := func() -> void:
				_hour(1.0)
				_m.heard = id
			_approach("clue_%s" % id, at, setup)
	if _want("parts"):
		for c in ["classic_500l", "classic_abarth_595"]:
			if not root.get_node("Garage").owned_cars.has(c):
				root.get_node("Garage").owned_cars.append(c)
		for part: Node3D in get_nodes_in_group(&"found_parts"):
			var id := String(part.get("part_id"))
			if not _want("parts", id):
				continue
			_approach("part_%s_day" % id, part.global_position, func() -> void: _hour(15.0))
			_approach("part_%s_night" % id, part.global_position, func() -> void: _hour(22.0))
	if _want("cuttings"):
		for spot in _scripted(_main, "CuttingSpot"):
			var id := String(spot.get("cutting_id"))
			if not _want("cuttings", id):
				continue
			_approach("cutting_%s_day" % id, spot.global_position, func() -> void: _hour(15.0))
			_approach("cutting_%s_night" % id, spot.global_position, func() -> void: _hour(22.0))
	if _want("barns"):
		for barn: Node3D in get_nodes_in_group(&"barn_finds"):
			var id := String(barn.get("car_id"))
			if not _want("barns", id):
				continue
			root.get_node("Classics").hear_rumour(id)
			_approach("barn_%s_day" % id, barn.global_position, func() -> void: _hour(15.0 if barn.get("hours").is_empty() else 1.0))
			_approach("barn_%s_night" % id, barn.global_position, func() -> void: _hour(1.0))
	if _want("badges"):
		var badges := get_nodes_in_group(&"collectibles")
		for i in mini(badges.size(), 4):
			var badge := badges[i * badges.size() / 4] as Node3D
			_approach("badge_%s_night" % badge.get("badge_id"), badge.global_position, func() -> void: _hour(22.0))


## Nodes under `node` whose script is the class `name` (no typed game classes
## here: this compiles before the autoloads exist).
func _scripted(node: Node, name: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in node.get_children():
		var script := child.get_script() as Script
		if script and script.get_global_name() == name:
			out.append(child as Node3D)
		out.append_array(_scripted(child, name))
	return out


## Shots of `at` from the nearest road: FAR then NEAR metres back along it.
func _approach(name: String, at: Vector3, setup: Callable) -> void:
	for d in [FAR, NEAR]:
		var first: bool = d == FAR
		_steps.append([name + "_%dm" % int(d), func() -> void:
			if first:
				setup.call()
			_place_car(at, d), 150 if first else 50])


func _place_car(at: Vector3, back: float) -> void:
	var g := MapData.shared().routes
	var best_d := INF
	var best_r := -1
	var best_s := 0.0
	var flat := Vector2(at.x, at.z)
	for r in g.road_pts.size():
		var pts: PackedVector3Array = g.road_pts[r]
		var cum: PackedFloat32Array = g.road_cum[r]
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var q := Geometry2D.get_closest_point_to_segment(flat, a, b)
			var d := q.distance_to(flat)
			if d < best_d:
				best_d = d
				best_r = r
				best_s = cum[i - 1] + a.distance_to(q)
	if best_r < 0:
		return
	var pts: PackedVector3Array = g.road_pts[best_r]
	var cum: PackedFloat32Array = g.road_cum[best_r]
	var total := cum[cum.size() - 1]
	# Back along the road whichever way has room, so the car comes up on it.
	var s := best_s - back if best_s - back >= 0.0 else minf(best_s + back, total)
	var p := TrafficGraph.point_at(pts, cum, s)
	# Facing along the road toward it, so it shows beside the road ahead.
	var dir := TrafficGraph.point_at(pts, cum, best_s) - p
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = Vector3.FORWARD
	_car.call("teleport", Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p + Vector3.UP * 0.8))
	print("%s: road %d m off, car at %s" % [name_of_step(), int(best_d), p])


func name_of_step() -> String:
	return String(_steps[_step][0]) if _step >= 0 and _step < _steps.size() else ""


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_world = _main.get_node("LoFi/SubViewport/World")
		_car = _world.get_node("Car")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_frames = -240
		return false
	_frames += 1
	if _step == -1:
		if _frames > 0:
			MapData.shared().wait()
			_main.get_node("HUD").call("hide_help")
			_m = _main.find_child("Mystery", true, false)
			# No act title card over the shots.
			var people := _main.find_child("StoryPeople", true, false)
			if people:
				people.set("card_act", 5)
			_build_steps()
			_next()
		return false
	if _step >= _steps.size():
		quit(0)
		return true
	if _frames >= int(_steps[_step][2]):
		var name: String = _steps[_step][0]
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
		print("shot ", name)
		_next()
	return false


func _next() -> void:
	_step += 1
	_frames = 0
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()


func _hour(h: float) -> void:
	root.get_node("GameClock").set_time(h)
