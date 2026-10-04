extends SceneTree
## A real-time playthrough of the actual game, with whatever save is in
## user:// (or none): load, drive, a fast tour of the whole map to shake out
## streaming hitches, the workshop, a job, switching cars, getting out,
## sleeping, getting back in, and saving. Unlike the smoke test it runs in
## real time (no --fixed-fps) and with saving on, the way a player runs it.
##
##   xvfb-run godot --path . --script res://tools/playthrough.gd
##   godot --headless --path . --script res://tools/playthrough.gd -- tour=off
##
## Options after `--`: tour=off skips the map tour, stops=<n> cuts it short;
## shots=<dir> saves a screenshot at each stage. Prints frame-time stats per stage, the worst
## hitches and where they happened. Exits with 1 if any check fails.

const HITCH_MS := 100.0
## Map tour speed (m/s): about a flat-out Abarth, so streaming sees real driving.
const TOUR_SPEED := 45.0
## The tour visits these job sites in order, then comes home.
const TOUR := ["northbridge_piazza", "kings_park_lookout", "subiaco_markets", "fremantle_markets",
	"cottesloe_surf_club", "scarborough_beach", "oxford_st", "beaufort_st", "albany_hwy", "little_shenton_lane"]

var _main: Node
var _car: RigidBody3D  # CarController (untyped here so it compiles before the autoloads)
var _player: Node
var _map: Node
var _failures: Array[String] = []
var _stage := 0
var _t := 0.0
var _shots := ""
var _tour := true
var _stops := 99
var _top_kmh := 0.0
var _spawn := Vector3.ZERO
var _leg := 0
var _tour_from := Vector3.ZERO
var _tour_points: Array[Vector3] = []
var _day := 0
var _stats := {}       # stage -> [frames, total_ms, worst_ms]
var _hitches: Array = []  # [ms, stage, position]
var _started_ms := 0
var _hopped_ms := -10000  # last time the tour jumped a gap (a teleport, not driving)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
		elif arg == "tour=off":
			_tour = false
		elif arg.begins_with("stops="):
			_stops = int(arg.trim_prefix("stops="))
	_started_ms = Time.get_ticks_msec()
	print("save file: %s (%s)" % [root.get_node("SaveGame").save_path(),
		"found" if root.get_node("SaveGame").has_save() else "none, fresh start"])


func _process(delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_player = _main.get_node_or_null("LoFi/SubViewport/World/Player")
		_map = _main.get_node("LoFi/SubViewport/World/PerthMap")
		_spawn = _map.get_spawn_transform().origin
		print("main scene up after %d ms" % (Time.get_ticks_msec() - _started_ms))
		return false
	_t += delta
	_record(delta)
	match _stage:
		0:  # Load and settle.
			if _t > 6.0:
				_check(_car.global_position.y > _spawn.y - 3.0, "the car is on the map, not under it (y=%.1f)" % _car.global_position.y)
				_check(_car.grounded_wheels == 4, "all four wheels on the ground (%d)" % _car.grounded_wheels)
				_check(_car.linear_velocity.length() < 1.0, "the car is at rest (%.1f m/s)" % _car.linear_velocity.length())
				_check(_player == null or _player.in_car, "starts in the car")
				print("start: %s, %.0f m from home, day %d %s, $%d" % [_car.car_id, _car.global_position.distance_to(_spawn),
					root.get_node("GameClock").day, root.get_node("GameClock").time_string(), root.get_node("Wallet").balance])
				_shot("01_start")
				Input.action_press("accelerate")
				_next()
		1:  # Drive out of the carport for real.
			if _t > 6.0:
				Input.action_release("accelerate")
				var out := Vector2(_car.global_position.x - _spawn.x, _car.global_position.z - _spawn.z).length()
				_check(out > 12.0, "drives out of the carport (%.1f m from the bay after 6 s)" % out)
				_check(_car.global_position.y > _spawn.y - 15.0, "still on the map (y=%.1f)" % _car.global_position.y)
				_next()
		2:  # Then on an open road: speed, no runaway, brakes.
			if _t > 0.1 and _t - delta <= 0.1:
				var site: Node3D = root.get_node("Jobs").site("northbridge_piazza")
				_car.global_transform = Transform3D(site.global_basis, site.global_position + Vector3.UP * 0.6)
				_car.linear_velocity = Vector3.ZERO
				_car.gear = 1
				_hopped_ms = Time.get_ticks_msec()
			if _t > 2.0 and _t - delta <= 2.0:
				Input.action_press("accelerate")
			if _t > 2.0 and _t <= 9.0:
				_top_kmh = maxf(_top_kmh, _car.speed_kmh())
			if _t > 9.0 and _t - delta <= 9.0:
				Input.action_release("accelerate")
				_check(_top_kmh > 30.0, "on the road: gets up to speed (%.0f km/h)" % _top_kmh)
				_check(_car.speed_kmh() < 200.0, "on the road: no runaway speed (%.0f km/h)" % _car.speed_kmh())
				_check(_car.global_position.y > _spawn.y - 30.0, "on the road: still on the map (y=%.1f)" % _car.global_position.y)
				_shot("02_driving")
				Input.action_press("brake")
			if _t > 13.0:
				Input.action_release("brake")
				_check(_car.speed_kmh() < 8.0, "on the road: brakes stop it (%.0f km/h)" % _car.speed_kmh())
				if _tour:
					_start_tour()
				_next()
		3:  # Fast tour of the map: streaming under load.
			if not _tour or _move_tour(delta):
				_next()
		4:  # Home again; let it settle.
			# Move it while it's still frozen from the tour, then let go, so the
			# physics body doesn't wake up wherever the tour left it.
			if _t > 0.1 and _t - delta <= 0.1:
				_car.global_transform = _map.get_spawn_transform().translated(Vector3.UP * 0.4)
				_hopped_ms = Time.get_ticks_msec()
			if _t > 0.4 and _t - delta <= 0.4:
				_car.process_mode = Node.PROCESS_MODE_INHERIT
				_car.freeze = false
				_car.linear_velocity = Vector3.ZERO
				_car.angular_velocity = Vector3.ZERO
			if _t > 5.0:
				_check(_car.grounded_wheels == 4, "home again: on the ground (%d wheels, at %s, %.0f m from home)" % [
					_car.grounded_wheels, _car.global_position, _car.global_position.distance_to(_spawn)])
				_next()
		5:  # Workshop in the carport.
			if _t > 0.2 and _t - delta <= 0.2:
				var shop := _main.find_child("Workshop", true, false)
				var bay: Node = null
				for spot in get_nodes_in_group(&"workshop_spots"):
					if spot.spot_id == "home_carport":
						bay = spot
				_check(bay != null, "the carport bay exists")
				if shop and bay:
					shop.open(bay)
					_check(shop.is_open() and paused, "the workshop opens and pauses the game")
					_shot("03_workshop")
					shop.close()
					_check(not shop.is_open() and not paused, "the workshop closes and unpauses")
			if _t > 1.0:
				_next()
		6:  # A job.
			if _t > 0.2 and _t - delta <= 0.2:
				var jobs := root.get_node("Jobs")
				jobs.refresh_offers()
				_check(not jobs.offers.is_empty(), "the job board has offers (%d)" % jobs.offers.size())
				if not jobs.offers.is_empty():
					jobs.accept(jobs.offers[0])
					_check(not jobs.active.is_empty(), "took a job: %s" % jobs.objective_text())
					_check(jobs.target_site() != null, "the job has somewhere to go")
					jobs.abandon()
					_check(jobs.active.is_empty(), "abandoned it")
			if _t > 1.0:
				_next()
		7:  # Switch cars.
			if _t > 0.2 and _t - delta <= 0.2:
				var garage := root.get_node("Garage")
				var before: String = _car.car_id
				garage.add_car("lounge_14")
				_check(garage.switch_car("lounge_14", _car), "switched to the Lounge")
				_check(_car.get_node("Body").scene_file_path.ends_with("lounge.glb"), "the Lounge has its own body")
				_shot("04_lounge")
				_check(garage.switch_car(before, _car), "switched back to the %s" % before)
			if _t > 3.0:
				_check(_car.grounded_wheels == 4, "after switching: on the ground")
				_next()
		8:  # Get out (hold F).
			if _player == null:
				_next()
			elif _t > 0.1 and _t - delta <= 0.1:
				Input.action_press("interact")
			elif _t > 1.0 and _t - delta <= 1.0:
				Input.action_release("interact")
			elif _t > 2.0:
				_check(not _player.in_car, "got out of the car")
				_check(_player.is_on_floor(), "standing on the ground")
				_shot("05_on_foot")
				_next()
		9:  # Sleep.
			if _t > 0.1 and _t - delta <= 0.1:
				_day = root.get_node("GameClock").day
				_map.get_home().sleep()
			if _t > 6.0:
				_check(root.get_node("GameClock").day == _day + 1, "sleeping ends the day")
				_next()
		10:  # Back in the car.
			if _player == null:
				_next()
			elif _t > 0.1 and _t - delta <= 0.1:
				var side := _car.global_basis * Vector3(1.4, 0, 0.1)
				_player.teleport(_car.global_position + side, _car.global_position + Vector3.UP * 0.8)
			elif _t > 0.8 and _t - delta <= 0.8:
				_player.interact()
			elif _t > 1.5:
				_check(_player.in_car, "got back in the car")
				_next()
		11:  # Save, and report.
			var save := root.get_node("SaveGame")
			_check(not save.enabled or save.save_game(), "the game saves")
			return _finish()
	return false


func _start_tour() -> void:
	var jobs := root.get_node("Jobs")
	for id in TOUR.slice(0, _stops):
		var site: Node3D = jobs.site(id)
		if site:
			_tour_points.append(site.global_position)
	# Frozen and not processing: a frozen body never integrates, so any force
	# the car script applied meanwhile would pile up and fire all at once.
	_car.freeze = true
	_car.process_mode = Node.PROCESS_MODE_DISABLED
	_tour_from = _car.global_position
	print("tour: %d stops" % _tour_points.size())


## Glide the (frozen) car toward the next stop. True when the tour is over.
func _move_tour(delta: float) -> bool:
	if _leg >= _tour_points.size():
		return true
	var target := _tour_points[_leg] + Vector3.UP * 1.5
	var to := target - _car.global_position
	var step := TOUR_SPEED * minf(delta, 0.25)
	if to.length() <= step:
		_car.global_position = target
		print("  reached %s after %.0f s, %d tiles loaded" % [TOUR[_leg], _t, _map.loaded_tile_count()])
		_shot("tour_%02d_%s" % [_leg, TOUR[_leg]])
		_leg += 1
	else:
		var next := _car.global_position + to.normalized() * step
		var tile: Vector2i = _map.tile_at(next)
		if not _map.index.get("tiles", {}).has("%d_%d" % [tile.x, tile.y]):
			# The map has gaps between its corridors (the streamer sends a car
			# that wanders off it home), so hop across them.
			next = target
			_hopped_ms = Time.get_ticks_msec()
		_car.global_position = next
		_car.global_rotation.y = atan2(-to.x, -to.z)
		if int(_t / 10.0) != int((_t - delta) / 10.0):
			print("    %.0f s: %.0f m to %s, %d tiles, %.0f fps" % [_t, to.length(), TOUR[_leg], _map.loaded_tile_count(), Engine.get_frames_per_second()])
	return false


func _record(delta: float) -> void:
	var ms := delta * 1000.0
	var s: Array = _stats.get(_stage, [0, 0.0, 0.0])
	s[0] += 1
	s[1] += ms
	s[2] = maxf(s[2], ms)
	_stats[_stage] = s
	# Teleports (the start of a stage, a hop across a map gap) load tiles all
	# at once on purpose; only count hitches while actually driving.
	if ms > HITCH_MS and _t > 0.5 and Time.get_ticks_msec() - _hopped_ms > 1500:
		_hitches.append([ms, _stage, _car.global_position])


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _next() -> void:
	_stage += 1
	_t = 0.0


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))


func _finish() -> bool:
	const NAMES := ["load", "carport", "road", "tour", "home", "workshop", "job", "cars", "get out", "sleep", "get in", "save"]
	print("frame times by stage (frames, average ms, worst ms):")
	for stage: int in _stats:
		var s: Array = _stats[stage]
		print("  %-9s %6d  %7.1f  %7.1f" % [NAMES[stage], s[0], s[1] / maxf(s[0], 1), s[2]])
	_hitches.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("hitches over %d ms: %d" % [HITCH_MS, _hitches.size()])
	for h in _hitches.slice(0, 8):
		print("  %.0f ms in %s at %s" % [h[0], NAMES[h[1]], h[2]])
	print("PLAYTHROUGH ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	quit(1 if _failures.size() else 0)
	return true
