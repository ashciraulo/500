class_name TrafficBoats
extends Node3D
## Life on the Swan River: the Transperth ferry between Elizabeth Quay and
## Mends Street, and yachts, tinnies and the odd rowing eight out on the
## water around the player.
##
## Where the water is comes from the map's overview picture (the river is
## one colour in it), read once in the background at start. Without the map
## (the traffic sandbox) there's no river and so no boats.
##
## The ferry's position is a pure function of the clock, so it's always in
## the same place at the same time. Other boats come and go out of sight,
## like the cars.

signal ferry_departed(position: Vector3)

const RIVER_LEVEL := 0.0
const WATER_COLOR := Color8(40, 72, 88)
const OVERVIEW := "res://map/tiles/overview.p5o"
## Elizabeth Quay to Mends Street, South Perth, in world metres.
const FERRY_ROUTE: Array[Vector3] = [
	Vector3(220, 0, 1350), Vector3(160, 0, 1470), Vector3(120, 0, 1600),
	Vector3(0, 0, 2400), Vector3(-40, 0, 2750),
]
const FERRY_SPEED := 6.0
const FERRY_DWELL := 60.0
## First and last sailings, hours.
const FERRY_HOURS := Vector2(6.8, 21.3)

enum Kind { YACHT, RUNABOUT, ROWING }
const KINDS := {
	Kind.YACHT: { "speed": 3.0, "turn": 0.25 },
	Kind.RUNABOUT: { "speed": 9.0, "turn": 0.6 },
	Kind.ROWING: { "speed": 4.5, "turn": 0.3 },
}

@export var enabled := true
@export var radius := 1100.0
@export var max_boats := 7

## Live boats: { kind, node, target, speed, heading, phase }.
var boats: Array = []
var ferry: Node3D
var stats := { "spawned": 0 }
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _mask: PackedByteArray
var _mask_w := 0
var _mask_h := 0
## World x, z of the mask's top-left corner, and metres per mask pixel.
var _mask_origin := Vector2.ZERO
var _mask_step := 20.0
var _loading := -1
var _timer := 0.0
var _ferry_at_jetty := true
var _pool := {}
var _sails := {}


func setup(manager: Node) -> void:
	_manager = manager
	_rng.randomize()
	# Only on the real map: the sandbox has no river.
	var world := manager.get_parent()
	if world == null or not world.has_node("PerthMap"):
		enabled = false
		return
	if FileAccess.file_exists(OVERVIEW):
		_loading = WorkerThreadPool.add_task(_load_mask)


func _exit_tree() -> void:
	if _loading >= 0:
		WorkerThreadPool.wait_for_task_completion(_loading)
		_loading = -1


## Whether the river map is in yet.
func ready_for_boats() -> bool:
	return _mask_w > 0


## Whether p is on open water (with `margin` metres of water all round).
func water_at(p: Vector3, margin := 0.0) -> bool:
	if _mask_w == 0:
		return false
	if margin <= 0.0:
		return _water_px(p.x, p.z)
	for o in [Vector2.ZERO, Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
		if not _water_px(p.x + o.x, p.z + o.y):
			return false
	return true


## Water all the way from a to b?
func water_between(a: Vector3, b: Vector3, margin := 0.0) -> bool:
	var n := int(ceilf(a.distance_to(b) / (_mask_step * 0.5)))
	for i in n + 1:
		if not water_at(a.lerp(b, float(i) / maxf(n, 1)), margin):
			return false
	return true


func _water_px(x: float, z: float) -> bool:
	var i := int((x - _mask_origin.x) / _mask_step)
	var j := int((z - _mask_origin.y) / _mask_step)
	if i < 0 or j < 0 or i >= _mask_w or j >= _mask_h:
		return false
	return _mask[j * _mask_w + i] != 0


func _load_mask() -> void:
	var data := MapTileLoader.read(OVERVIEW)
	if data.is_empty():
		return
	var image := Image.new()
	if image.load_png_from_buffer(data.texture_png as PackedByteArray) != OK:
		return
	image.convert(Image.FORMAT_RGB8)
	var rect: Array = data.texture_rect
	var px := float(rect[2]) / image.get_width()
	# Halve it: 20 m cells are plenty for boats and keep it small.
	var w := image.get_width() / 2
	var h := image.get_height() / 2
	var bytes := image.get_data()
	var mask := PackedByteArray()
	mask.resize(w * h)
	var src_w := image.get_width()
	var r := WATER_COLOR.r8
	var g := WATER_COLOR.g8
	var b := WATER_COLOR.b8
	for j in h:
		for i in w:
			var k := ((j * 2) * src_w + i * 2) * 3
			if absi(bytes[k] - r) < 6 and absi(bytes[k + 1] - g) < 6 and absi(bytes[k + 2] - b) < 6:
				mask[j * w + i] = 1
	call_deferred(&"_mask_loaded", mask, w, h, Vector2(rect[0], rect[1]), px * 2.0)


func _mask_loaded(mask: PackedByteArray, w: int, h: int, origin: Vector2, step: float) -> void:
	if _loading >= 0:
		WorkerThreadPool.wait_for_task_completion(_loading)
		_loading = -1
	_mask = mask
	_mask_origin = origin
	_mask_step = step
	_mask_w = w
	_mask_h = h


func update(delta: float, focus: Vector3) -> void:
	if _mask_w == 0 or not enabled:
		return
	_update_ferry(focus)
	for boat in boats:
		_sail(boat, delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	for boat in boats.duplicate():
		var d: float = boat.node.position.distance_to(focus)
		if d > radius + 300.0 and not _manager._visible(boat.node.position):
			_release(boat)
	if boats.size() < target_boats() and _near_water(focus):
		_try_spawn(focus)


## How many boats should be out now: plenty on a fine weekend afternoon,
## hardly any at night or in the rain.
func target_boats() -> int:
	var hour: float = get_node("/root/GameClock").time_of_day
	var day: int = get_node("/root/GameClock").day
	var rain: float = get_node("/root/Weather").rain
	var f := 0.15
	if hour > 6.0 and hour < 19.0:
		f = 0.6 if hour < 9.0 or hour > 17.0 else 1.0
	if _manager.is_weekend(day):
		f *= 1.5
	f *= lerpf(1.0, 0.15, clampf(rain * 1.5, 0.0, 1.0))
	return clampi(int(round(max_boats * minf(f, 1.0))), 0, max_boats)


func clear() -> void:
	for boat in boats.duplicate():
		_release(boat)


## Put a boat of `kind` on the water at p (heading somewhere sensible).
## Returns it, or {} when p isn't open water.
func spawn_boat(kind: int, p: Vector3) -> Dictionary:
	if not water_at(p, 15.0):
		return {}
	var list: Array = _pool.get(kind, [])
	var node: Node3D = list.pop_back() if not list.is_empty() else _make(kind)
	if node.get_parent() == null:
		add_child(node)
	node.visible = true
	node.position = Vector3(p.x, RIVER_LEVEL, p.z)
	var boat := { "kind": kind, "node": node, "target": node.position, "heading": _rng.randf() * TAU,
		"speed": KINDS[kind].speed * _rng.randf_range(0.8, 1.15), "phase": _rng.randf() * TAU }
	_pick_target(boat)
	boats.append(boat)
	stats.spawned += 1
	return boat


func _near_water(focus: Vector3) -> bool:
	for k in 12:
		var a := TAU * k / 12.0
		if water_at(focus + Vector3(cos(a), 0, sin(a)) * radius * 0.6):
			return true
	return water_at(focus)


func _try_spawn(focus: Vector3) -> void:
	var hour: float = get_node("/root/GameClock").time_of_day
	for attempt in 8:
		var a := _rng.randf() * TAU
		var p := focus + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(250.0, radius)
		if not water_at(p, 30.0):
			continue
		# Out of sight, or far enough off that it doesn't seem to pop in.
		if p.distance_to(focus) < 600.0 and _manager._visible(p + Vector3(0, 2, 0)):
			continue
		var kind := Kind.YACHT
		var roll := _rng.randf()
		if hour > 5.5 and hour < 8.5 and roll < 0.35:
			kind = Kind.ROWING
		elif roll < 0.55:
			kind = Kind.RUNABOUT
		spawn_boat(kind, p)
		return


func _pick_target(boat: Dictionary) -> void:
	var from: Vector3 = boat.node.position
	for attempt in 10:
		var a: float = boat.heading + _rng.randf_range(-1.2, 1.2)
		var d := _rng.randf_range(120.0, 450.0)
		var to := from + Vector3(cos(a), 0, sin(a)) * d
		if water_between(from, to, 25.0):
			boat.target = to
			return
	# Boxed in: turn round.
	boat.heading += PI
	boat.target = from + Vector3(cos(boat.heading), 0, sin(boat.heading)) * 60.0


func _sail(boat: Dictionary, delta: float) -> void:
	var node: Node3D = boat.node
	var to: Vector3 = boat.target - node.position
	to.y = 0.0
	if to.length() < 15.0 or not water_at(node.position + Vector3(cos(boat.heading), 0, sin(boat.heading)) * 25.0, 5.0):
		_pick_target(boat)
		to = boat.target - node.position
		to.y = 0.0
	var want := atan2(to.z, to.x)
	var turn: float = KINDS[boat.kind].turn
	boat.heading = rotate_toward(boat.heading, want, turn * delta)
	var dir := Vector3(cos(boat.heading), 0, sin(boat.heading))
	node.position += dir * boat.speed * delta
	boat.phase += delta
	_float(node, dir, boat.phase, boat.speed)


## Bob on the water, facing `dir` (models face -Z).
func _float(node: Node3D, dir: Vector3, phase: float, speed: float) -> void:
	node.position.y = RIVER_LEVEL + sin(phase * 1.3) * 0.06
	node.basis = Basis.looking_at(dir, Vector3.UP).rotated(dir.cross(Vector3.UP).normalized(), sin(phase * 0.9) * 0.02 + minf(speed, 9.0) * 0.006)


func _release(boat: Dictionary) -> void:
	boats.erase(boat)
	boat.node.visible = false
	if not _pool.has(boat.kind):
		_pool[boat.kind] = []
	_pool[boat.kind].append(boat.node)


# --- The ferry ----------------------------------------------------------------

## Where the ferry is at `hour`: [position, heading, tied up]. It runs on
## the game clock but sails at a real 6 m/s like the traffic, so a day of
## `seconds_per_day` fits a handful of round trips.
static func ferry_state(hour: float, seconds_per_day := 2400.0) -> Array:
	var legs: Array = []
	var total := 0.0
	for i in FERRY_ROUTE.size() - 1:
		var l := FERRY_ROUTE[i].distance_to(FERRY_ROUTE[i + 1])
		legs.append(l)
		total += l
	var crossing := total / FERRY_SPEED + 40.0  # A little slower leaving and arriving.
	var cycle := 2.0 * (crossing + FERRY_DWELL)
	var hours := clampf(hour, FERRY_HOURS.x, FERRY_HOURS.y)
	var t := fposmod((hours - FERRY_HOURS.x) / 24.0 * seconds_per_day, cycle)
	var outbound := t < crossing + FERRY_DWELL
	if not outbound:
		t -= crossing + FERRY_DWELL
	var first: Vector3 = FERRY_ROUTE[0]
	var last: Vector3 = FERRY_ROUTE[FERRY_ROUTE.size() - 1]
	if t < FERRY_DWELL or hour < FERRY_HOURS.x or hour > FERRY_HOURS.y:
		# Tied up: at Elizabeth Quay overnight, else wherever this leg starts.
		var at_eq := outbound or hour < FERRY_HOURS.x or hour > FERRY_HOURS.y
		var p: Vector3 = first if at_eq else last
		var q: Vector3 = FERRY_ROUTE[1] if at_eq else FERRY_ROUTE[FERRY_ROUTE.size() - 2]
		return [p, (q - p).normalized(), true]
	# Ease out of and into the jetties.
	var u := clampf((t - FERRY_DWELL) / crossing, 0.0, 1.0)
	u = smoothstep(0.0, 1.0, u) * 0.3 + u * 0.7
	var s := u * total if outbound else (1.0 - u) * total
	for i in legs.size():
		if s <= legs[i] or i == legs.size() - 1:
			var a: Vector3 = FERRY_ROUTE[i]
			var b: Vector3 = FERRY_ROUTE[i + 1]
			var dir := (b - a).normalized()
			return [a.lerp(b, clampf(s / legs[i], 0.0, 1.0)), dir if outbound else -dir, false]
		s -= legs[i]
	return [last, Vector3.FORWARD, true]


func _update_ferry(focus: Vector3) -> void:
	var near := focus.distance_to(FERRY_ROUTE[2]) < 2500.0
	if not near:
		if ferry:
			ferry.visible = false
		return
	if ferry == null:
		ferry = _make_ferry()
		add_child(ferry)
	ferry.visible = true
	var hour: float = get_node("/root/GameClock").time_of_day
	var state := ferry_state(hour, get_node("/root/GameClock").seconds_per_day)
	if _ferry_at_jetty and not state[2]:
		ferry_departed.emit(state[0])
		var horn := ferry.get_node_or_null("Horn") as AudioStreamPlayer3D
		if horn:
			horn.play()
	if _ferry_at_jetty != state[2] or not ferry.has_meta("engine"):
		_ferry_engine(state[2])
	_ferry_at_jetty = state[2]
	var engine := ferry.get_node_or_null("Engine") as AudioStreamPlayer3D
	if engine and not state[2]:
		engine.pitch_scale = 1.0 + sin(Time.get_ticks_msec() / 3000.0) * 0.03
	ferry.position = state[0]
	_float(ferry, state[1], Time.get_ticks_msec() / 1000.0, 0.0 if state[2] else FERRY_SPEED)
	var lit: bool = get_node("/root/GameClock").daylight() < 0.45
	if ferry.get_meta("lit", false) != lit:
		ferry.set_meta("lit", lit)
		ferry.get_node("Windows").material_override = TrafficModels.material(Color(1.0, 0.85, 0.55), 2.5) if lit else TrafficModels.material(Color(0.15, 0.2, 0.25))


## Engine under way, idling at the jetty (the audio thread's loops, once
## they're in).
func _ferry_engine(at_jetty: bool) -> void:
	ferry.set_meta("engine", true)
	var audio := get_node_or_null("/root/Audio")
	var loop_name := "traffic/traffic_ferry_idle_loop" if at_jetty else "traffic/traffic_ferry_engine_loop"
	if audio == null or not audio.has_method("has") or not audio.has(loop_name):
		return
	var engine := ferry.get_node_or_null("Engine") as AudioStreamPlayer3D
	if engine == null:
		engine = AudioStreamPlayer3D.new()
		engine.name = "Engine"
		engine.bus = &"Vehicles" if AudioServer.get_bus_index(&"Vehicles") >= 0 else &"Master"
		engine.unit_size = 12.0
		engine.max_distance = 250.0
		ferry.add_child(engine)
	engine.stream = audio.stream(loop_name, true)
	engine.play()


# --- Models -------------------------------------------------------------------

func _make(kind: int) -> Node3D:
	var root := Node3D.new()
	var white := TrafficModels.material(Color(0.9, 0.9, 0.88))
	match kind:
		Kind.YACHT:
			root.name = "Yacht"
			var hull := TrafficModels.material([Color(0.92, 0.92, 0.9), Color(0.12, 0.2, 0.35), Color(0.55, 0.12, 0.1)][_rng.randi() % 3])
			TrafficModels._add_part(root, "yacht_hull", Vector3(2.4, 0.9, 8.0), Vector3(0, 0.2, 0), Vector3.ZERO, hull)
			TrafficModels._add_part(root, "yacht_bow", Vector3(1.6, 0.8, 1.6), Vector3(0, 0.25, -4.3), Vector3(0, PI / 4.0, 0), hull)
			TrafficModels._add_part(root, "yacht_cabin", Vector3(1.6, 0.6, 2.6), Vector3(0, 0.9, 0.6), Vector3.ZERO, white)
			TrafficModels._add_part(root, "yacht_mast", Vector3(0.12, 10.0, 0.12), Vector3(0, 5.6, -0.8), Vector3.ZERO, TrafficModels.material(Color(0.7, 0.7, 0.72)))
			# The main aft of the mast and the jib forward of it, both
			# sheeted in a touch to one side.
			var trim := _rng.randf_range(0.12, 0.3) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_add_sail(root, Vector3(3.4, 8.6, 0.05), Vector3(0, 5.6, 0.9), 0.0, -PI / 2.0 + trim, white)
			_add_sail(root, Vector3(2.8, 7.4, 0.05), Vector3(0, 5.0, -2.3), 1.0, -PI / 2.0 + trim * 1.4, white)
		Kind.RUNABOUT:
			root.name = "Runabout"
			var hull := TrafficModels.material([Color(0.85, 0.85, 0.82), Color(0.62, 0.64, 0.66), Color(0.2, 0.35, 0.55)][_rng.randi() % 3])
			TrafficModels._add_part(root, "tinny_hull", Vector3(1.9, 0.7, 4.8), Vector3(0, 0.15, 0), Vector3(-0.04, 0, 0), hull)
			TrafficModels._add_part(root, "tinny_screen", Vector3(1.6, 0.4, 0.1), Vector3(0, 0.7, -0.6), Vector3(-0.4, 0, 0), TrafficModels.material(Color(0.3, 0.4, 0.45)))
			TrafficModels._add_part(root, "tinny_motor", Vector3(0.35, 0.8, 0.4), Vector3(0, 0.5, 2.5), Vector3.ZERO, TrafficModels.material(Color(0.1, 0.1, 0.1)))
			var skipper := TrafficModels.person(_rng)
			skipper.position = Vector3(0.3, -0.45, 0.8)
			skipper.scale = Vector3.ONE * 0.95
			root.add_child(skipper)
		Kind.ROWING:
			root.name = "RowingEight"
			var shell := TrafficModels.material(Color(0.85, 0.82, 0.7))
			TrafficModels._add_part(root, "eight_shell", Vector3(0.55, 0.3, 17.0), Vector3(0, 0.1, 0), Vector3.ZERO, shell)
			var top := TrafficModels.material([Color(0.1, 0.25, 0.55), Color(0.55, 0.1, 0.12), Color(0.1, 0.4, 0.25)][_rng.randi() % 3])
			for i in 9:
				var z := -6.4 + i * 1.5
				TrafficModels._add_part(root, "eight_rower", Vector3(0.38, 0.55, 0.3), Vector3(0, 0.55, z), Vector3(0.2 if i < 8 else 0.0, 0, 0), top)
				if i < 8:
					var side := -1.0 if i % 2 == 0 else 1.0
					TrafficModels._add_part(root, "eight_oar", Vector3(3.6, 0.04, 0.08), Vector3(side * 1.9, 0.35, z), Vector3(0, 0, side * 0.12), shell)
	_nav_lights(root, kind == Kind.ROWING)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 1600.0
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## A triangular sail standing in the boat's fore-and-aft plane: `apex` 0
## puts the peak at the forward edge, 1 at the after edge.
func _add_sail(root: Node3D, size: Vector3, pos: Vector3, apex: float, yaw: float, mat: Material) -> void:
	var key := "%s_%s" % [size, apex]
	if not _sails.has(key):
		var prism := PrismMesh.new()
		prism.size = size
		prism.left_to_right = apex
		_sails[key] = prism
	var sail := MeshInstance3D.new()
	sail.name = "Sail"
	sail.mesh = _sails[key]
	sail.material_override = mat
	sail.position = pos
	sail.rotation = Vector3(0, yaw, 0)
	root.add_child(sail)


## Red to port, green to starboard, white at the stern: always on, they only
## show at dusk anyway.
func _nav_lights(root: Node3D, stern_only: bool) -> void:
	if not stern_only:
		TrafficModels._add_part(root, "nav", Vector3(0.15, 0.15, 0.15), Vector3(-0.8, 0.8, -2.0), Vector3.ZERO, TrafficModels.material(Color(1, 0.1, 0.1), 3.0))
		TrafficModels._add_part(root, "nav", Vector3(0.15, 0.15, 0.15), Vector3(0.8, 0.8, -2.0), Vector3.ZERO, TrafficModels.material(Color(0.1, 1, 0.3), 3.0))
	TrafficModels._add_part(root, "nav", Vector3(0.15, 0.15, 0.15), Vector3(0, 1.0, 2.2), Vector3.ZERO, TrafficModels.material(Color(1, 1, 0.9), 3.0))


## A Transperth river ferry: twin hull, two decks, blue band, facing -Z.
func _make_ferry() -> Node3D:
	var root := Node3D.new()
	root.name = "Ferry"
	var white := TrafficModels.material(Color(0.92, 0.92, 0.9))
	var blue := TrafficModels.material(Color(0.1, 0.3, 0.6))
	var dark := TrafficModels.material(Color(0.15, 0.17, 0.2))
	for side in [-1.0, 1.0]:
		TrafficModels._add_part(root, "ferry_hull", Vector3(2.2, 1.6, 24.0), Vector3(side * 2.6, -0.1, 0), Vector3.ZERO, white)
	TrafficModels._add_part(root, "ferry_deck", Vector3(7.6, 0.4, 24.0), Vector3(0, 0.9, 0), Vector3.ZERO, blue)
	TrafficModels._add_part(root, "ferry_cabin", Vector3(7.0, 2.4, 16.0), Vector3(0, 2.3, 1.0), Vector3.ZERO, white)
	var windows := TrafficModels._add_part(root, "ferry_windows", Vector3(7.1, 0.9, 14.5), Vector3(0, 2.6, 1.0), Vector3.ZERO, dark)
	windows.name = "Windows"
	TrafficModels._add_part(root, "ferry_upper", Vector3(5.0, 0.3, 9.0), Vector3(0, 3.7, 3.0), Vector3.ZERO, white)
	TrafficModels._add_part(root, "ferry_bridge", Vector3(3.2, 1.4, 2.6), Vector3(0, 4.4, -2.6), Vector3.ZERO, white)
	TrafficModels._add_part(root, "ferry_rail", Vector3(5.0, 0.8, 0.08), Vector3(0, 4.25, 7.5), Vector3.ZERO, blue)
	_nav_lights(root, false)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 2500.0
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var horn := AudioStreamPlayer3D.new()
	horn.name = "Horn"
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has("traffic/traffic_ferry_horn"):
		horn.stream = audio.stream("traffic/traffic_ferry_horn")
	else:
		horn.stream = _manager._make_horn(146.0, 184.0, 1.8)
	horn.unit_size = 40.0
	horn.max_distance = 1500.0
	horn.bus = &"Vehicles" if AudioServer.get_bus_index(&"Vehicles") >= 0 else &"Master"
	root.add_child(horn)
	return root
