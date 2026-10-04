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
			_check(spots.size() == 3, "three workshop bays (%d)" % spots.size())
			_check(spots.has("home_carport") and _flat(spots.home_carport.global_position).distance_to(_flat(_spawn.origin)) < 1.0,
				"the car starts in the carport bay")
			_check(spots.has("fitzgerald_st_servo") and spots.fitzgerald_st_servo.offers("fuel"), "the servo sells fuel")
			_next()
		1:
			if _seconds() >= 3.0:
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
				_car.global_position = Vector3(-1500, 40, 2300)
			if _seconds() >= 6.0:
				var key: Vector2i = _map.tile_at(_car.global_position)
				_check(_map.is_tile_loaded(key), "tiles stream around the car's new position")
				_check(not _map.is_tile_loaded(_map.tile_at(_spawn.origin)), "far tiles are unloaded")
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
