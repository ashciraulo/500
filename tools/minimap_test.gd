extends SceneTree
## Headless check of the minimap and the full map on the real Perth map: the
## road data loads, the minimap knows the street you're in, M opens the full
## map (and pauses), markers go down, save and load, and M closes it again.
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
				return _finish()
	return false


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
