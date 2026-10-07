extends SceneTree
## How the Pop drives: holding a corner at full keyboard lock at town and
## open-road speeds, stopping from 80, riding a lumpy road and a row of bumps
## at 60, and reversing out of a spin with the brake key. Each case runs on
## its own flat world with the gearbox in automatic, like most players drive.
##
##   godot --headless --path . --fixed-fps 120 --script res://tools/handling_test.gd -- --no-save
##
## Add car=<id> to drive another car, report to only print the numbers, and
## jitter=<n> to start every case from start n (see _build), for sweeps.
## Exits with code 1 if any check fails.

## The profile road sits this high over the ground, after a flat run-up from
## the start to PROFILE_START (-Z), long enough to get up to speed.
const PROFILE_Y := 5.0
const PROFILE_START := -150.0
## Pearson St, Churchlands, coming off Alumni Terrace (the map's road as it was
## in October 2026): its height every half metre for 150 m, in cm. Downhill,
## with humps every few metres, two of them 30 cm or more. It also had a lump
## 70 cm high and 4 m long near (-5603, -2360) that throws anything at
## speed; that's a fault in the map, smoothed out here.
## Pearson St at 55-75: two of its humps lift a car off the road whatever
## its suspension, so at most that many moments clean off it, this long in
## all, landing no harder than this change in rise speed (m/s), never more
## than PITCH_OK nose or tail up, and losing no more than SPEED_LOSS_OK
## km/h. Over 64 starts a little off the line the worst was 0.84 s off the
## road, a 3.6 m/s landing, 34 degrees (once, at 75) and 18 km/h (once, at
## 75: it bottoms out in the second dip). What these catch is far beyond
## that: before the bump stops and road hug the Pop flipped at 55 and spun
## at 75, and before the rounded underside, from some starts its floor
## caught the road at 66 and stopped it dead or spun it.
const HOPS_OK := 2
const FLYING_OK := 1.2
const JOLT_OK := 5.0
const PITCH_OK := 45.0
const SPEED_LOSS_OK := 25.0
## The bend road (see _bend_road): run-up, radius of its middle, half width.
const BEND_RUN_UP := 150.0
const BEND_RADIUS := 10.0
const BEND_HALF_WIDTH := 3.5
## Each Pearson St case runs from this many starts; see _initialize.
const PROFILE_STARTS := 4
const PEARSON_ST_CM: Array[int] = [
	0, -1, -1, -2, -3, -4, -5, -5, -6, -8, -9, -11, -12, -12, -7, -5, -9, -13, -18, -22,
	-25, -26, -27, -29, -30, -29, -28, -28, -27, -27, -27, -30, -32, -35, -38, -41, -41, -42, -45, -49,
	-52, -56, -58, -60, -61, -63, -64, -63, -62, -61, -60, -60, -59, -61, -64, -67, -70, -73, -74, -75,
	-78, -83, -88, -92, -94, -96, -98, -100, -101, -102, -100, -98, -96, -95, -93, -96, -100, -103, -107, -111,
	-115, -118, -121, -122, -123, -123, -124, -124, -125, -126, -129, -131, -133, -133, -133, -132, -133, -136, -140, -144,
	-149, -153, -157, -159, -161, -163, -165, -167, -169, -171, -173, -174, -176, -177, -178, -180, -178, -171, -168, -174,
	-179, -184, -185, -186, -187, -187, -189, -191, -190, -188, -186, -184, -181, -184, -188, -192, -196, -200, -205, -208,
	-210, -211, -211, -210, -209, -209, -208, -208, -209, -212, -215, -216, -215, -214, -214, -218, -222, -227, -232, -238,
	-242, -243, -245, -243, -239, -236, -232, -229, -225, -224, -229, -233, -237, -241, -245, -244, -243, -249, -255, -260,
	-260, -261, -261, -261, -263, -265, -266, -262, -258, -255, -251, -252, -258, -263, -268, -273, -277, -282, -284, -283,
	-280, -277, -274, -270, -267, -265, -269, -272, -275, -278, -277, -274, -272, -276, -282, -289, -296, -303, -308, -309,
	-310, -310, -303, -297, -290, -284, -277, -272, -278, -284, -290, -295, -301, -302, -299, -307, -317, -327, -327, -327,
	-328, -328, -329, -329, -330, -331, -331, -332, -333, -334, -334, -335, -336, -336, -337, -338, -338, -339, -334, -329,
	-325, -320, -315, -311, -312, -317, -321, -325, -326, -325, -323, -325, -333, -341, -348, -355, -359, -360, -360, -360,
	-356, -350, -343, -337, -330, -324, -329, -335, -341, -346, -352, -358, -359, -363, -367, -365, -363, -362, -360, -358,
	-356,
]

const CASES := [
	{"name": "corner_40", "kind": "corner", "kmh": 40.0},
	{"name": "corner_60", "kind": "corner", "kmh": 60.0},
	{"name": "corner_80", "kind": "corner", "kmh": 80.0},
	{"name": "lane_change_80", "kind": "swerve", "kmh": 80.0},
	{"name": "brake_80", "kind": "brake", "kmh": 80.0},
	{"name": "brake_in_corner_70", "kind": "brake_corner", "kmh": 70.0},
	{"name": "lumpy_60", "kind": "lumpy", "kmh": 60.0},
	{"name": "bumps_60", "kind": "bumps", "kmh": 60.0},
	{"name": "rough_60", "kind": "rough", "kmh": 60.0},
	{"name": "rough_corner_50", "kind": "rough_corner", "kmh": 50.0},
	{"name": "pearson_st_55", "kind": "profile", "kmh": 55.0},
	{"name": "pearson_st_66", "kind": "profile", "kmh": 66.0},
	{"name": "pearson_st_75", "kind": "profile", "kmh": 75.0},
	{"name": "wide_onto_grass_55", "kind": "bend", "kmh": 55.0},
	{"name": "wide_onto_grass_60", "kind": "bend", "kmh": 60.0},
	{"name": "wide_onto_grass_65", "kind": "bend", "kmh": 65.0},
	{"name": "rolling_back", "kind": "rollback", "kmh": 0.0},
	{"name": "rolling_back_manual", "kind": "rollback", "kmh": 0.0, "manual": true},
	{"name": "stopped_reverse", "kind": "stopped", "kmh": 0.0},
]

var _world: Node3D
var _car  # CarController (untyped: a tool script compiles before the autoloads)
var _case := -1
var _time := 0.0
var _phase := 0
var _phase_time := 0.0
var _failures: Array[String] = []
var _report := false
var _m := {}  # measurements for this case
var _flight := 0.0
var _landed := -1.0
var _land_vy := 0.0
var _cases: Array[Dictionary] = []
var _bend_s := 0.0
var _jitter := 0


func _initialize() -> void:
	_report = OS.get_cmdline_user_args().has("report")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("jitter="):
			_jitter = int(arg.trim_prefix("jitter="))
	for c: Dictionary in CASES:
		_cases.append(c)
		# Pearson St again from a few starts a little off the line: the
		# same car on another computer rounds its sums a hair differently,
		# and a car that only gets down the street from one exact start
		# would pass here and spin there.
		if c.kind == "profile":
			for start in range(1, PROFILE_STARTS):
				var again := c.duplicate()
				again.name = "%s_from_%d" % [c.name, start + 1]
				again.start = start
				_cases.append(again)
	# Drive and measure once per physics tick, not per frame, so the result
	# doesn't depend on --fixed-fps.
	physics_frame.connect(_tick)


func _process(_delta: float) -> bool:
	if _case < 0:
		# Dry roads all the way through: the weather picks its spells at
		# random, and a shower partway through would change every case after it.
		var weather := root.get_node("Weather")
		weather.set_state(0, true)
		weather.set_locked(true)
		weather.wetness = 0.0
	if _world == null:
		_case += 1
		if _case >= _cases.size():
			return _finish()
		var only := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("only="):
				only = arg.trim_prefix("only=")
		if only != "" and not String(_cases[_case].name).begins_with(only):
			return false
		_build(_cases[_case])
	return false


func _tick() -> void:
	if _world == null:
		return
	var delta := 1.0 / Engine.physics_ticks_per_second
	_time += delta
	_phase_time += delta
	if _time < 0.8:
		return  # settle
	var c: Dictionary = _cases[_case]
	if _step(c, delta):
		_judge(c)
		_world.queue_free()
		_world = null


func _build(c: Dictionary) -> void:
	_time = 0.0
	_phase = 0
	_phase_time = 0.0
	_m = {"max_lat_g": 0.0, "max_roll": 0.0, "max_pitch": 0.0, "max_yaw_rate": 0.0, "max_slip": 0.0,
		"airborne": 0.0, "spun": false, "drift": 0.0, "flying": 0.0, "hops": 0, "jolt": 0.0}
	_flight = 0.0
	_landed = -1.0
	_world = Node3D.new()
	root.add_child(_world)
	if c.kind != "bend":
		_box(Vector3(3000, 1, 3000), Vector3(0, -0.5, -1200))
	match String(c.kind):
		"lumpy":
			_lumpy_road()
		"bumps":
			_bump_row()
		"rough", "rough_corner":
			_rough_ground()
		"profile":
			_profile_road(PEARSON_ST_CM)
		"bend":
			_bend_road()
	_car = (load("res://scenes/vehicles/fiat_500_pop.tscn") as PackedScene).instantiate()
	_car.player_controlled = false
	_car.position = Vector3(0, 0.6 + (PROFILE_Y if c.kind == "profile" else 0.0), 0)
	var start: int = _jitter if _jitter else c.get("start", 0)
	if start:
		# Up to 30 cm to one side and a degree askew; the driver lines it up.
		var rng := RandomNumberGenerator.new()
		rng.seed = start
		_car.position.x += rng.randf_range(-0.3, 0.3)
		_car.rotation.y = deg_to_rad(rng.randf_range(-1.0, 1.0))
	_world.add_child(_car)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("car="):
			_car.load_vehicle_state({"car_id": arg.trim_prefix("car=")})
	_car.set_transmission(0 if c.get("manual", false) else 1)


## Drive the case; returns true when it's done.
func _step(c: Dictionary, delta: float) -> bool:
	var v: Vector3 = _car.linear_velocity
	var speed := v.length()
	var fwd: Vector3 = -_car.global_basis.z
	var kind := String(c.kind)
	# Watch the car the whole time.
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() > 3.0:
		var heading := Vector3(fwd.x, 0, fwd.z).normalized()
		var off := absf(heading.signed_angle_to(flat.normalized(), Vector3.UP))
		if _phase >= 1 and absf(_car.forward_speed) > 3.0:
			_m.max_slip = maxf(_m.max_slip, rad_to_deg(minf(off, PI - off) if _car.forward_speed < 0 else off))
			if off > deg_to_rad(40.0) and _car.forward_speed > 0.0:
				_m.spun = true
	var yaw_rate: float = absf(_car.angular_velocity.y)
	if _phase >= 1:
		_m.max_lat_g = maxf(_m.max_lat_g, yaw_rate * speed / 9.81)
		_m.max_yaw_rate = maxf(_m.max_yaw_rate, rad_to_deg(yaw_rate))
		var b: Basis = _car.global_basis
		_m.max_roll = maxf(_m.max_roll, absf(rad_to_deg(asin(clampf(b.x.y, -1, 1)))))
		_m.max_pitch = maxf(_m.max_pitch, absf(rad_to_deg(asin(clampf(b.z.y, -1, 1)))))
		if _car.grounded_wheels < 3:
			_m.airborne += delta
		# Clean off the road: how long, how often for more than a moment, and
		# the jolt (change in rise speed) over the tenth of a second after landing.
		if _car.grounded_wheels == 0:
			_m.flying += delta
			_flight += delta
		elif _flight > 0.0:
			if _flight > 0.12:
				_m.hops += 1
			_flight = 0.0
			_landed = 0.0
			_land_vy = v.y
		if _landed >= 0.0:
			_landed += delta
			if _landed >= 0.1:
				_m.jolt = maxf(_m.jolt, absf(v.y - _land_vy))
				_landed = -1.0
	match kind:
		"corner", "swerve", "brake", "brake_corner", "lumpy", "bumps", "rough", "rough_corner", "profile", "bend":
			if _phase == 0:
				_hold(float(c.kmh), speed)
				_car.steer_input = 0.0
				_steer_straight()
				if speed * 3.6 > float(c.kmh) - 1.0 and _phase_time > 2.0:
					_next()
					_m.start = _car.global_position
					_m.start_yaw = _car.global_rotation.y
				elif _phase_time > 40.0:
					_m.never_reached = true
					return true
				return false
			match kind:
				"corner", "rough_corner":
					_hold(float(c.kmh), speed)
					_car.steer_input = 1.0
					if _phase_time > 6.0:
						_m.end_kmh = speed * 3.6
						return true
				"swerve":
					_hold(float(c.kmh), speed)
					# Left for 0.6 s, right for 1.2 s, left 0.6 s, then straight.
					var t := _phase_time
					_car.steer_input = 1.0 if t < 0.6 else (-1.0 if t < 1.8 else (1.0 if t < 2.4 else 0.0))
					if t > 2.4:
						_steer_straight()
					if t > 6.0:
						_m.end_kmh = speed * 3.6
						return true
				"brake":
					_car.throttle_input = 0.0
					_car.brake_input = 1.0
					_steer_straight()
					if speed < 0.3 or _phase_time > 10.0:
						_m.stop_m = (_car.global_position - _m.start).length()
						_m.stop_s = _phase_time
						_m.yaw_change = rad_to_deg(absf(wrapf(_car.global_rotation.y - _m.start_yaw, -PI, PI)))
						return true
				"brake_corner":
					# Turn in, then brake hard while still turning.
					_car.steer_input = 1.0
					if _phase_time < 1.0:
						_hold(float(c.kmh), speed)
					else:
						_car.throttle_input = 0.0
						_car.brake_input = 1.0
					if speed < 0.5 or _phase_time > 8.0:
						_m.end_kmh = speed * 3.6
						return true
				"bend":
					# Like a player on the keyboard: aim at the road ahead, the
					# key fully down or not at all, at the same speed throughout.
					_hold(float(c.kmh), speed)
					var at := Vector2(_car.global_position.x, _car.global_position.z)
					_bend_s = _bend_closest(at, _bend_s)
					var off := at.distance_to(_bend_centre(_bend_s))
					_m.off_road = maxf(_m.get("off_road", 0.0), off - BEND_HALF_WIDTH)
					var aim := _bend_centre(_bend_s + 5.0) - at
					var heading := Vector2(fwd.x, fwd.z)
					var err := heading.angle_to(aim)  # positive: the road is to the right
					_car.steer_input = -1.0 if err > deg_to_rad(2.0) else (1.0 if err < deg_to_rad(-2.0) else 0.0)
					for w in _car._wheels:
						if w.grounded and w.surface == &"grass":
							_m.on_grass = _m.get("on_grass", 0.0) + delta / 4.0
					if _bend_s > BEND_RUN_UP + PI * 0.5 * BEND_RADIUS + 60.0 or _phase_time > 20.0:
						_m.end_kmh = speed * 3.6
						_m.end_off = maxf(off - BEND_HALF_WIDTH, 0.0)
						return true
				"lumpy", "bumps", "rough", "profile":
					_hold(float(c.kmh), speed)
					_steer_straight()
					var gone: float = (_car.global_position - _m.start).length()
					_m.drift = maxf(_m.drift, absf(_car.global_position.x))
					var past_end: bool = kind == "profile" and _car.global_position.z < PROFILE_START - PEARSON_ST_CM.size() * 0.5
					if past_end or (kind != "profile" and gone > 200.0) or _phase_time > 20.0:
						_m.end_kmh = speed * 3.6
						return true
		"rollback":
			# Rolling backwards at 3 m/s in first (a spin, or a hill), then hold the brake key.
			if _phase == 0:
				_car.linear_velocity = _car.global_basis.z * 3.0
				_car.brake_input = 1.0
				_car.throttle_input = 0.0
				_next()
				return false
			_car.brake_input = 1.0
			if _phase_time > 1.5:
				_m.end_speed = _car.forward_speed
				_m.end_gear = _car.gear
				return true
		"stopped":
			if _phase <= 1:
				_car.brake_input = 1.0
				_car.throttle_input = 0.0
				if _phase == 0:
					_next()
				if _phase_time > 2.0:
					_m.end_speed = _car.forward_speed
					_m.end_gear = _car.gear
					_next()
			else:
				# Then the accelerator: brakes, picks first and drives off.
				_car.brake_input = 0.0
				_car.throttle_input = 1.0
				if _phase_time > 4.0:
					_m.fwd_gear = _car.gear
					_m.fwd_speed = _car.forward_speed
					return true
	return false


func _judge(c: Dictionary) -> void:
	var line := "%-20s" % c.name
	for key in ["on_grass", "off_road", "flying", "hops", "jolt", "end_kmh", "max_lat_g", "max_yaw_rate", "max_slip", "max_roll", "max_pitch", "airborne", "drift", "stop_m", "stop_s", "yaw_change", "end_speed", "end_gear"]:
		if _m.has(key):
			var val = _m[key]
			line += "  %s=%s" % [key, ("%.2f" % val) if val is float else str(val)]
	line += "  spun=%s" % _m.spun
	print(line)
	if _m.get("never_reached", false):
		_check(false, "%s: got up to %d km/h" % [c.name, c.kmh])
		return
	match String(c.kind):
		"corner":
			_check(not _m.spun, "%s: holds the corner at full lock without spinning" % c.name)
			_check(_m.max_slip < 25.0, "%s: no big slide (%.0f deg)" % [c.name, _m.max_slip])
			if float(c.kmh) <= 60.0:
				_check(_m.max_lat_g > 0.55, "%s: corners hard enough (%.2f g)" % [c.name, _m.max_lat_g])
			_check(_m.airborne < 0.1, "%s: keeps its wheels down" % c.name)
		"swerve":
			_check(not _m.spun, "%s: a lane change doesn't spin it" % c.name)
			_check(_m.max_slip < 20.0, "%s: settles after the swerve (%.0f deg slide)" % [c.name, _m.max_slip])
		"brake":
			_check(_m.stop_m < 34.0, "%s: stops within 34 m (%.1f m)" % [c.name, _m.stop_m])
			_check(_m.yaw_change < 5.0, "%s: stops straight (%.1f deg)" % [c.name, _m.yaw_change])
		"brake_corner":
			_check(not _m.spun, "%s: braking mid-corner doesn't spin it" % c.name)
		"rough_corner":
			_check(not _m.spun, "%s: rough ground mid-corner doesn't spin it" % c.name)
			_check(_m.max_slip < 25.0, "%s: no big slide on rough ground (%.0f deg)" % [c.name, _m.max_slip])
			_check(_m.airborne < 0.5, "%s: wheels stay down (%.2f s light)" % [c.name, _m.airborne])
		"profile":
			_check(not _m.spun, "%s: humps don't spin it" % c.name)
			_check(_m.drift < 1.5, "%s: stays in its lane (%.2f m)" % [c.name, _m.drift])
			_check(_m.hops <= HOPS_OK, "%s: off the road for more than a moment only at the two big humps (%d times)" % [c.name, _m.hops])
			_check(_m.max_pitch < PITCH_OK, "%s: never noses in or rears up (%.0f deg)" % [c.name, _m.max_pitch])
			_check(_m.end_kmh > float(c.kmh) - SPEED_LOSS_OK, "%s: never hits the road hard enough to stop it (%.0f km/h at the end)" % [c.name, _m.end_kmh])
			_check(_m.flying < FLYING_OK, "%s: little time clean off the road (%.2f s)" % [c.name, _m.flying])
			_check(_m.jolt < JOLT_OK, "%s: lands softly (%.1f m/s jolt)" % [c.name, _m.jolt])
		"lumpy", "bumps", "rough":
			_check(not _m.spun, "%s: bumps don't spin it" % c.name)
			_check(_m.drift < 1.5, "%s: stays in its lane over bumps (%.2f m)" % [c.name, _m.drift])
			# Crests as sharp as the lumpy road's lift a real car too (it was
			# 2.3 s light before the skim grip); what matters is landing straight.
			var light_ok := 2.0 if c.kind == "lumpy" else 0.5
			_check(_m.airborne < light_ok, "%s: wheels stay down (%.2f s light)" % [c.name, _m.airborne])
			_check(_m.max_yaw_rate < 12.0, "%s: bumps barely turn it (%.1f deg/s)" % [c.name, _m.max_yaw_rate])
			_check(_m.end_kmh > float(c.kmh) - 12.0, "%s: keeps its speed (%.0f km/h)" % [c.name, _m.end_kmh])
		"bend":
			_check(_m.get("on_grass", 0.0) > 0.2, "%s: runs wide onto the grass (%.1f s of tyre on grass)" % [c.name, _m.get("on_grass", 0.0)])
			_check(not _m.spun, "%s: running onto the grass and back doesn't spin it (%.0f deg slide)" % [c.name, _m.max_slip])
			_check(_m.end_off < 0.5 and _m.end_kmh > 25.0, "%s: back on the road and away (%.1f m off, %.0f km/h)" % [c.name, _m.end_off, _m.end_kmh])
		"rollback", "stopped":
			_check(_m.end_gear == -1, "%s: the brake key picks reverse (gear %d)" % [c.name, _m.end_gear])
			_check(_m.end_speed < -1.5, "%s: and drives backwards (%.1f m/s)" % [c.name, _m.end_speed])
			if _m.has("fwd_gear"):
				_check(_m.fwd_gear >= 1 and _m.fwd_speed > 1.5, "%s: the accelerator then drives forwards again (gear %d, %.1f m/s)" % [c.name, _m.fwd_gear, _m.fwd_speed])


func _hold(kmh: float, speed: float) -> void:
	var target := kmh / 3.6
	_car.throttle_input = clampf((target - speed) * 0.5 + 0.3, 0.0, 1.0)
	_car.brake_input = clampf((speed - target - 1.5) * 0.3, 0.0, 1.0)


## Keep the car pointed down -Z like a player would.
func _steer_straight() -> void:
	var fwd: Vector3 = -_car.global_basis.z
	var err := atan2(-fwd.x, -fwd.z)  # positive when pointing left of -Z
	var lateral: float = _car.global_position.x
	_car.steer_input = clampf(-err * 3.0 + lateral * 0.08, -1.0, 1.0)  # left is +, so right of the line steers left


func _next() -> void:
	_phase += 1
	_phase_time = 0.0


## A road whose slope changes by up to 7% every metre (like the Pearson St
## crest before the map's smoothing), 400 m long and 8 m wide.
func _lumpy_road() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var faces := PackedVector3Array()
	var h := 0.0
	var slope := 0.0
	var z := -10.0
	var heights: Array[float] = []
	for i in 420:
		heights.append(h)
		slope = clampf(slope + rng.randf_range(-0.07, 0.07), -0.08, 0.08)
		h = clampf(h + slope, -0.6, 0.6)
		if absf(h) >= 0.6:
			slope = -slope * 0.5
	for i in 419:
		var z0 := z - i
		var z1 := z - i - 1
		var a := Vector3(-4, heights[i], z0)
		var b := Vector3(4, heights[i], z0)
		var c := Vector3(-4, heights[i + 1], z1)
		var d := Vector3(4, heights[i + 1], z1)
		faces.append_array([a, c, d, a, d, b])
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)
	body.position.y = 0.6  # above the flat ground
	_world.add_child(body)
	# A ramp up onto it.
	var ramp := PackedVector3Array([Vector3(-4, -0.6, 10), Vector3(-4, 0, -10), Vector3(4, 0, -10),
		Vector3(-4, -0.6, 10), Vector3(4, 0, -10), Vector3(4, -0.6, 10)])
	var rbody := StaticBody3D.new()
	var rcol := CollisionShape3D.new()
	var rshape := ConcavePolygonShape3D.new()
	rshape.set_faces(ramp)
	rcol.shape = rshape
	rbody.add_child(rcol)
	rbody.position.y = 0.6
	_world.add_child(rbody)


## A real road's heights (cm, every half metre) after a flat run-up, 8 m wide.
func _profile_road(cm: Array[int]) -> void:
	var pts: Array[Vector2] = [Vector2(10.0, 0.0)]  # (z, height)
	for i in cm.size():
		pts.append(Vector2(PROFILE_START - i * 0.5, cm[i] * 0.01))
	pts.append(Vector2(pts[-1].x - 40.0, pts[-1].y))
	var faces := PackedVector3Array()
	for i in pts.size() - 1:
		var a := Vector3(-4, pts[i].y, pts[i].x)
		var b := Vector3(4, pts[i].y, pts[i].x)
		var c := Vector3(-4, pts[i + 1].y, pts[i + 1].x)
		var d := Vector3(4, pts[i + 1].y, pts[i + 1].x)
		faces.append_array([a, c, d, a, d, b])
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)
	body.position.y = PROFILE_Y
	_world.add_child(body)


## A road 7 m wide between kerbs 12 cm high, with grass verges beyond (the
## map's colliders carry the same "surface" names), the one on the outside of
## the bend a bank falling away at 1 in 5 like the lake side of Lakeside Rd:
## a straight run-up, then a 90 degree bend to the left a little tighter
## than the case's speed can take, then straight again.
func _bend_road() -> void:
	_bend_s = 0.0
	var ground := _box(Vector3(3000, 1, 3000), Vector3(0, -2.0, -1200))
	ground.set_meta("surface", &"grass")
	var w := BEND_HALF_WIDTH
	# (surface, [from offset, to offset, from height, to height]...) either side.
	var bands := {
		&"asphalt": [[-w, w, 0.02, 0.02]],
		&"concrete": [[w, w, 0.02, 0.14], [w, w + 0.3, 0.14, 0.14], [-w, -w, 0.02, 0.14], [-w, -w - 0.3, 0.14, 0.14]],
		&"grass": [[w + 0.3, w + 8.0, 0.12, 0.12], [w + 8.0, w + 12.0, 0.12, -1.5],
			[-w - 0.3, -w - 1.0, 0.12, 0.12], [-w - 1.0, -w - 9.0, 0.12, -1.5]],
	}
	var length := BEND_RUN_UP + PI * 0.5 * BEND_RADIUS + 120.0
	for surface: StringName in bands:
		var faces := PackedVector3Array()
		var s := -10.0
		while s < length:
			for band: Array in bands[surface]:
				var quad: Array[Vector3] = []
				for at: float in [s, s + 1.0]:
					var p := _bend_centre(at)
					var side := (_bend_centre(at + 0.1) - p).normalized().orthogonal()
					for k in 2:
						var o: float = band[k]
						quad.append(Vector3(p.x + side.x * o, band[2 + k], p.y + side.y * o))
				faces.append_array([quad[0], quad[1], quad[3], quad[0], quad[3], quad[2]])
			s += 1.0
		var body := StaticBody3D.new()
		body.set_meta("surface", surface)
		var col := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		col.shape = shape
		body.add_child(col)
		_world.add_child(body)


## The bend road's middle (x, z), `s` metres along it.
func _bend_centre(s: float) -> Vector2:
	if s <= BEND_RUN_UP:
		return Vector2(0.0, -s)
	var arc := PI * 0.5 * BEND_RADIUS
	if s <= BEND_RUN_UP + arc:
		var a := (s - BEND_RUN_UP) / BEND_RADIUS
		return Vector2(-BEND_RADIUS + BEND_RADIUS * cos(a), -BEND_RUN_UP - BEND_RADIUS * sin(a))
	return Vector2(-BEND_RADIUS - (s - BEND_RUN_UP - arc), -BEND_RUN_UP - BEND_RADIUS)


## How far along the bend road is closest to `at`, searching near `from`.
func _bend_closest(at: Vector2, from: float) -> float:
	var best := from
	var best_d := INF
	var s := from - 5.0
	while s < from + 40.0:
		var d := at.distance_squared_to(_bend_centre(s))
		if d < best_d:
			best_d = d
			best = s
		s += 0.25
	return best


## Rough ground both ways: lumps a few centimetres high whose slope changes
## by several percent every metre, different under each side of the car.
func _rough_ground() -> void:
	var size := 400
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.12
	noise.fractal_octaves = 2
	var data := PackedFloat32Array()
	data.resize(size * size)
	for j in size:
		for i in size:
			data[j * size + i] = noise.get_noise_2d(i, j) * 0.09
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = data
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, 0.12, -size * 0.5 + 20.0)
	_world.add_child(body)


## Speed-bump-like ridges, 6 cm high, under one side of the car then the other.
func _bump_row() -> void:
	for i in 20:
		var x := -0.7 if i % 2 == 0 else 0.7
		_box(Vector3(1.0, 0.12, 0.5), Vector3(x, 0.0, -30.0 - i * 9.0))


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = at
	_world.add_child(body)
	return body


func _check(ok: bool, what: String) -> void:
	if _report:
		return
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> bool:
	print("HANDLING ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	quit(1 if _failures.size() else 0)
	return true
