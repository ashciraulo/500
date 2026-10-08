extends SceneTree
## Headless test for the Perth map: the game starts at home on Little Shenton
## Lane, the car lands on the road, and tiles stream in and out as it moves.
##
##   godot --headless --path . --fixed-fps 120 --script res://tools/map_test.gd

const FPS := 120

var _main: Node
var _map: Node3D  # MapStreamer (untyped so this compiles before class names are registered)
var _car: RigidBody3D
var _failures: Array[String] = []
var _step := 0
var _frame := 0
var _park := Vector3.ZERO
var _spawn := Transform3D()


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_map = _main.get_node("LoFi/SubViewport/World/PerthMap")
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		root.get_node("GameClock").set_time(12.0)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		_spawn = _map.get_spawn_transform()
		return false
	_frame += 1
	match _step:
		0:
			_check(not _map.index.is_empty(), "map index loaded")
			_check(_map.loaded_tile_count() >= 1, "home tile loaded before the first frame (%d tiles)" % _map.loaded_tile_count())
			_check(_flat(_car.global_position).distance_to(_flat(_spawn.origin)) < 1.0, "car starts at the spawn point")
			_check(_map.has_collision_at(_spawn.origin), "home tile has colliders")
			var home: Node3D = _map.get_home()
			_check(home != null and home.has_method(&"spawn_transform"), "the townhouse is placed on the map")
			var sites := {}
			for s in _main.get_tree().get_nodes_in_group(&"job_sites"):
				sites[s.site_id] = s
			for id in ["little_shenton_lane", "northbridge_piazza", "kings_park_lookout", "beaufort_st"]:
				_check(sites.has(id), "job site %s is on the map" % id)
			var spots := {}
			for s in _main.get_tree().get_nodes_in_group(&"workshop_spots"):
				spots[s.spot_id] = s
			_check(spots.size() >= 4, "workshop bays are placed (%d)" % spots.size())
			_check(spots.has("scarborough_beach_rd_yard") and spots.scarborough_beach_rd_yard.offers("dealer"), "there is a car yard")
			var badges := _main.get_tree().get_nodes_in_group(&"collectibles").size()
			_check(badges >= 20, "badges are hidden around the map (%d)" % badges)
			_check(spots.has("home_carport") and _flat(spots.home_carport.global_position).distance_to(_flat(_spawn.origin)) < 1.0,
				"the car starts in the carport bay")
			_check(spots.has("fitzgerald_st_servo") and spots.fitzgerald_st_servo.offers("fuel")
				and spots.fitzgerald_st_servo.offers("wash"), "the Fitzgerald St servo sells fuel and washes cars")
			# Servos round the map (data/world/servos.json, Fitzgerald St's too):
			# each a bay that sells fuel, and a fuel pin on every one and nowhere else.
			var servos := _main.get_tree().get_nodes_in_group(&"servos")
			var listed: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/servos.json")).servos
			_check(servos.size() == listed.size() and servos.size() >= 15, "servos are placed round the map (%d)" % servos.size())
			var selling := 0
			for servo in servos:
				var bay = servo.get_node_or_null(^"Bay")
				if bay and bay.offers("fuel"):
					selling += 1
			_check(selling == servos.size(), "every servo sells fuel (%d of %d)" % [selling, servos.size()])
			var fuel_pins := 0
			for pin: Dictionary in load("res://scripts/ui/map_pins.gd").gather(_main.get_tree()):
				if pin.get("icon", "") == "fuel":
					fuel_pins += 1
			_check(fuel_pins == servos.size(), "a fuel pin on each servo, Fitzgerald St's too (%d)" % fuel_pins)
			var fitz = _map.get_node_or_null(^"Servo_fitzgerald_st_servo")
			_check(fitz != null and fitz.get_node_or_null(^"Sign") != null, "the Fitzgerald St servo has a canopy and a price sign")
			var galup: Dictionary = {}
			for lake: Dictionary in _map.get_lakes():
				if lake.name == "Galup":
					galup = lake
			var mid := Vector2.ZERO
			for p: Vector2 in galup.get("outline", PackedVector2Array()):
				mid += p / galup.outline.size()
			_check(not galup.is_empty() and absf(_map.water_level_at(Vector3(mid.x, 0, mid.y)) - galup.level) < 0.01,
				"Lake Monger has a water level (%.2f)" % galup.get("level", NAN))
			_check(is_nan(_map.water_level_at(_spawn.origin)), "no lake at home")
			var overview := _map.get_node_or_null(^"Overview")
			_check(overview != null and overview.lake_water != null, "far-off lakes have water past the streamed tiles")
			_next()
		1:
			# Tiles load on worker threads in real time while frames run as fast
			# as they can, so on a busy runner give them a while to come in.
			if _seconds() >= 3.0 and (_map.loaded_tile_count() >= 6 or _seconds() >= 30.0):
				_check(_car.grounded_wheels == 4, "car lands on all four wheels (%d)" % _car.grounded_wheels)
				_check(absf(_car.global_position.y - _spawn.origin.y) < 1.5, "car rests near spawn height (y=%.2f, spawn %.2f)" % [_car.global_position.y, _spawn.origin.y])
				_check(_car.global_basis.y.dot(Vector3.UP) > 0.95, "car sits level in the carport")
				_check(_map.loaded_tile_count() >= 6, "surrounding tiles stream in (%d)" % _map.loaded_tile_count())
				var traffic = _main.get_node_or_null("LoFi/SubViewport/World/Traffic")
				_check(traffic != null and traffic.graph.roads.size() > 200, "traffic gets the map's roads (%d)" % (traffic.graph.roads.size() if traffic else 0))
				_check(traffic != null and traffic.graph.signal_controllers.size() > 3, "traffic lights at signalled junctions (%d)" % (traffic.graph.signal_controllers.size() if traffic else 0))
				# James Street, round the corner from home.
				var hit := _ray_down(Vector3(-29, 20, 54))
				_check(not hit.is_empty() and hit.collider.get_meta("surface", &"") == &"asphalt", "map roads are asphalt colliders")
				_check_walkers_on_ground(traffic)
				var poles := 0
				for body in _map.find_children("props", "StaticBody3D", true, false):
					poles += body.get_child_count()
				_check(poles > 50, "trees and street lights near the car are solid (%d)" % poles)
				_next()
		2:  # Gentle drive out of the carport.
			Input.action_press("accelerate", 0.4)
			if _seconds() >= 2.0:
				Input.action_release("accelerate")
				_check(_car.speed_kmh() > 5.0, "car drives on the map (%.0f km/h)" % _car.speed_kmh())
				_next()
		3:  # Jump to the Narrows Bridge approach and check streaming follows.
			if _frame == 1:
				_car.freeze = true
				_car.global_position = Vector3(-1250, 40, 2050)
			if _seconds() >= 6.0:
				var key: Vector2i = _map.tile_at(_car.global_position)
				_check(_map.is_tile_loaded(key), "tiles stream around the car's new position")
				_check(not _map.is_tile_loaded(_map.tile_at(_spawn.origin)), "far tiles are unloaded")
				_next()
		4:  # Restore a save somewhere not loaded yet (Kings Park): the ground must be there.
			if _frame == 1:
				_car.freeze = false
				_car.global_position = Vector3(-935.6, 66.0, 1455.6)
				_car.linear_velocity = Vector3.ZERO
			if _seconds() >= 2.0:
				_check(_map.has_collision_at(_car.global_position), "colliders are built where the car is restored")
				_check(absf(_car.global_position.y - 66.0) < 2.0, "restored car stays on the ground (y=%.1f)" % _car.global_position.y)
				_next()
		5:  # Off the end of the built map: back to where it last drove, not home.
			if _frame == 1:
				_park = _car.global_position
				_car.global_position = Vector3(40000.0, 60.0, 0.0)
				_car.linear_velocity = Vector3.ZERO
			if _seconds() >= 2.5:
				_check(_flat(_car.global_position).distance_to(_flat(_park)) < 6.0,
					"a car off the map goes back to where it last drove (%.0f m away)" % _flat(_car.global_position).distance_to(_flat(_park)))
				_next()
		6:  # A save from before the map (test grid height) would leave the car under Perth.
			if _frame == 1:
				_car.global_position = Vector3(0.0, 0.3, 8.0)
				_car.linear_velocity = Vector3.ZERO
			if _seconds() >= 2.0:
				_check(_flat(_car.global_position).distance_to(_flat(_spawn.origin)) < 2.0 and absf(_car.global_position.y - _spawn.origin.y) < 1.5,
					"a car under the ground goes back to the carport (%s)" % _car.global_position)
				_next()
		_:
			Input.action_release("accelerate")
			if _failures.is_empty():
				print("MAP TEST PASSED")
				quit(0)
			else:
				print("MAP TEST FAILED (%d):" % _failures.size())
				for f in _failures:
					print("  - ", f)
				quit(1)
			return true
	return false


## Pedestrians walk the traffic graph's footpaths and footways at the heights
## the map's traffic data gives them, so those must be the ground's heights:
## paths that kept their own height profile had walkers metres in the air
## over James Street Mall and the Herdsman Lake trail.
func _check_walkers_on_ground(traffic) -> void:
	if traffic == null:
		return
	var space := (_main.get_node("LoFi/SubViewport/World") as Node3D).get_world_3d().direct_space_state
	var n := 0
	var off: Array = []
	for edge in traffic.graph.ped_edges:
		var pts: PackedVector3Array = edge.pts
		for i in pts.size():
			var p := pts[i]
			if _flat(p).distance_to(_flat(_spawn.origin)) > 400.0 or not _map.has_collision_at(p):
				continue
			n += 1
			# The first ground under the walker's head: above them if they're sunk, below if floating.
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p - Vector3(0, 12, 0), 1, [_car.get_rid()])
			var hit := space.intersect_ray(q)
			var gap: float = p.y - (hit.position.y if not hit.is_empty() else p.y - 15.0)
			if absf(gap) > 1.0:
				off.append("%+.1f m at (%.0f, %.0f)" % [gap, p.x, p.z])
	_check(n > 500 and off.size() <= n / 100, "walkers stand on the ground (%d of %d path points more than 1 m off%s)"
		% [off.size(), n, (": " + ", ".join(off.slice(0, 4))) if not off.is_empty() else ""])


func _ray_down(p: Vector3) -> Dictionary:
	var space := (_main.get_node("LoFi/SubViewport/World") as Node3D).get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 50, 0), p - Vector3(0, 50, 0), 1, [_car.get_rid()]))


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _seconds() -> float:
	return float(_frame) / FPS


func _next() -> void:
	_step += 1
	_frame = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
