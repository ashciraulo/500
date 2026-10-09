class_name BirdFlicker
extends Node
## The late city's birds that flicker (docs/STORY.md, event 3): a bird blinks
## out with the tape shimmer and a soft warble, and comes back a moment later,
## up to a metre away. How much flickers follows LateCity.flicker_level():
##
##   0  nothing
##   1  the wrong frogmouth, and only through the binoculars
##   2  every wrong bird (the shot's focus dial jumps when its bird blinks)
##   3  as 2, plus ordinary birds where the late city is strong, now and then
##   4  as 3, plus the thirteen black cockatoos fly alongside the car on
##      Fraser Avenue after 2 am, flickering in step
##
## Gentle "strange things" keeps the shimmer and the warble but not the jump.
## A bird that's blinked out has meta "flicker" true (the binoculars read it).

## How long a bird is gone for, and how long the shimmer stays after.
const GONE := Vector2(0.2, 0.6)
const AFTERGLOW := 1.2
## The wrong frogmouth's steady shimmer through the binoculars (act 2).
const FROGMOUTH_GLOW := 0.6
## The thirteen keep a faint shimmer the whole way along Fraser Avenue, so
## black birds read against the night sky.
const ALONG_GLOW := 0.7
## Seconds between flickers: wrong birds, ordinary ones.
const WRONG_EVERY := Vector2(3.0, 9.0)
const ORDINARY_EVERY := Vector2(12.0, 35.0)
## Ordinary birds only flicker where the late city is at least this strong.
const PRESENCE := 0.3
## Fraser Avenue: how near the cockatoos' place, how fast, and for how long.
const ALONGSIDE_NEAR := 700.0
const ALONGSIDE_SPEED := 6.0
const ALONGSIDE_TIME := 26.0

## Tests set this to force a level (-1: ask LateCity).
var level_override := -1

var _birds: FieldBirds
var _bino: Binoculars
var _rng := RandomNumberGenerator.new()
var _frogmouth_glow: Node3D
var _along := {}
var _along_day := -1


func setup(birds: FieldBirds, binoculars: Binoculars) -> void:
	_birds = birds
	_bino = binoculars
	_rng.randomize()


func level() -> int:
	if level_override >= 0:
		return level_override
	var lc := _late_city()
	return int(lc.call("flicker_level")) if lc else 0


func _late_city() -> Node:
	return get_node_or_null(^"/root/LateCity") if is_inside_tree() else null


func _gentle() -> bool:
	var story := get_node_or_null(^"/root/Story") if is_inside_tree() else null
	return story != null and bool(story.call("gentle"))


func _binoculars_up() -> bool:
	return is_instance_valid(_bino) and _bino.state != Binoculars.State.CLOSED


func _process(delta: float) -> void:
	if _birds == null:
		return
	var lvl := level()
	var bino := _binoculars_up()
	_frogmouth_shimmer(lvl == 1 and bino)
	for s: Dictionary in _birds.sightings:
		for b: Dictionary in s.birds:
			_update(b, lvl, bino, delta)
	_alongside(lvl, delta)


## Whether this bird flickers at this level.
func can_flicker(b: Dictionary, lvl: int, bino: bool) -> bool:
	if b.state == "gone" or not is_instance_valid(b.node):
		return false
	var s: Dictionary = b.sighting
	if s.has("wrong"):
		if lvl >= 2:
			return true
		return lvl == 1 and bino and s.id == "wrong_frogmouth"
	if lvl < 3 or b.state == "fly" or b.state == "leave":
		return false
	var lc := _late_city()
	return lc != null and float(lc.call("presence_at", (b.node as Node3D).global_position)) > PRESENCE


func _update(b: Dictionary, lvl: int, bino: bool, delta: float) -> void:
	var node: Node3D = b.node
	if not is_instance_valid(node):
		return
	if b.get("blink", 0.0) > 0.0:
		b.blink -= delta
		if b.blink <= 0.0:
			_back(b)
		return
	if b.get("glow", 0.0) > 0.0:
		b.glow -= delta
		if b.glow <= 0.0:
			_unshimmer(node, b)
	if b.state == "along":
		return  # the Fraser Avenue flock flickers together (_alongside)
	if not can_flicker(b, lvl, bino):
		b.erase("flick_in")
		return
	if not b.has("flick_in"):
		b.flick_in = _next(b)
	b.flick_in -= delta
	if b.flick_in <= 0.0:
		b.flick_in = _next(b)
		blink(b)


func _next(b: Dictionary) -> float:
	var every: Vector2 = WRONG_EVERY if b.sighting.has("wrong") else ORDINARY_EVERY
	return _rng.randf_range(every.x, every.y)


## Blink this bird out (it comes back by itself).
func blink(b: Dictionary) -> void:
	var node: Node3D = b.node
	if not is_instance_valid(node) or not node.visible:
		return
	var lc := _late_city()
	if lc:
		lc.call("play_flicker", node.global_position)
		lc.call("add_shimmer", node, 1.0)
	node.visible = false
	node.set_meta("flicker", true)
	b.blink = _rng.randf_range(GONE.x, GONE.y)
	b.glow = 0.0


func _back(b: Dictionary) -> void:
	var node: Node3D = b.node
	b.blink = 0.0
	b.glow = AFTERGLOW
	node.set_meta("flicker", false)
	if b.state != "gone":
		node.visible = true
	if _gentle() or b.state == "along":
		return
	match String(b.kind):
		"ground", "water":
			var a := _rng.randf() * TAU
			var to := node.position + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.4, 1.0)
			if b.kind == "ground":
				var g := _birds.ground(to)
				if g.is_empty() or absf(g.pos.y - node.position.y) > 0.6:
					return
				to = g.pos
			node.position = to
			b.target = to
			if b.kind == "water":
				b.home = Vector3(to.x, b.home.y, to.z)
		_:
			# On a branch or a post: the same spot, facing somewhere else.
			node.rotation.y += _rng.randf_range(-2.0, 2.0)


func _unshimmer(node: Node3D, b := {}) -> void:
	var lc := _late_city()
	if lc == null or not is_instance_valid(node):
		return
	# Back to a steady shimmer, for the birds that keep one.
	if node == _frogmouth_glow:
		lc.call("add_shimmer", node, FROGMOUTH_GLOW)
	elif b.get("state", "") == "along":
		lc.call("add_shimmer", node, ALONG_GLOW)
	else:
		lc.call("remove_shimmer", node)


## Act 2: the wrong frogmouth shimmers whenever you've got the glasses up.
func _frogmouth_shimmer(on: bool) -> void:
	var node: Node3D = null
	if on:
		for s: Dictionary in _birds.sightings:
			if s.id == "wrong_frogmouth" and not s.birds.is_empty():
				node = s.birds[0].node
	if node == _frogmouth_glow:
		return
	var lc := _late_city()
	if lc and is_instance_valid(_frogmouth_glow):
		lc.call("remove_shimmer", _frogmouth_glow)
	_frogmouth_glow = node
	if lc and node:
		lc.call("add_shimmer", node, FROGMOUTH_GLOW)


# --- the thirteen on Fraser Avenue ------------------------------------------------------

## Whether the thirteen are flying beside the car now.
func alongside() -> bool:
	return not _along.is_empty()


func _alongside(lvl: int, delta: float) -> void:
	if not _along.is_empty():
		_fly_alongside(delta)
		return
	if lvl < 4 or _along_day == GameClock.day:
		return
	var hour := GameClock.time_of_day
	if hour < 2.0 or hour > 5.0:
		return
	var car := _birds._car()
	if car == null or _birds._walker() != null or car.linear_velocity.length() < ALONGSIDE_SPEED:
		return
	var sp := FieldJournal.bird("wrong_cockatoos")
	var at := _birds.wrong_place(sp)
	if at == Vector3.INF or Vector2(at.x - car.global_position.x, at.z - car.global_position.z).length() > ALONGSIDE_NEAR:
		return
	start_alongside()


## Thirteen black cockatoos lift off and keep pace beside the car.
func start_alongside() -> bool:
	var car := _birds._car()
	var sp := FieldJournal.bird("wrong_cockatoos")
	if car == null or sp.is_empty() or _birds.sightings.any(func(s: Dictionary) -> bool: return s.id == "wrong_cockatoos"):
		return false
	_along_day = GameClock.day
	var s := {"id": "wrong_cockatoos", "species": sp, "habitat": {}, "centre": car.global_position, "perch": "air",
		"birds": [], "frames": 999, "leaving": true, "cue": null, "cue_timer": 0.0, "call_timer": 999.0,
		"props": [], "wrong": true}
	_birds.sightings.append(s)
	for i in 13:
		var b := _birds._add_bird(s, {"pos": car.global_position + Vector3.UP * 4.0, "kind": "air"})
		b.state = "along"
		# Two loose lines off the passenger side (the car's left: it's right-hand
		# drive), low over the verge and just ahead, where the chase camera sees them.
		b.home = Vector3(-(5.5 + (i % 2) * 2.5 + _rng.randf_range(-0.6, 0.6)), 2.2 + (i % 3) * 0.8, 1.0 + (i / 2) * 1.8)
		b.node.position = _beside(car, b.home)
		s.birds.append(b)
		var lc := _late_city()
		if lc:
			lc.call("add_shimmer", b.node, ALONG_GLOW)
	_along = {"sighting": s, "time": ALONGSIDE_TIME, "flick": _rng.randf_range(1.0, 2.5), "phase": 0.0}
	return true


func _beside(car: Node3D, off: Vector3) -> Vector3:
	var right := car.global_basis.x
	right.y = 0.0
	var ahead := -car.global_basis.z
	ahead.y = 0.0
	return car.global_position + right.normalized() * off.x + Vector3.UP * off.y + ahead.normalized() * off.z


func _fly_alongside(delta: float) -> void:
	var s: Dictionary = _along.sighting
	var car := _birds._car()
	_along.time -= delta
	_along.phase += delta
	if car == null or _along.time <= 0.0 or not _birds.sightings.has(s):
		_end_alongside()
		return
	s.centre = car.global_position
	var heading := atan2(car.global_basis.z.x, car.global_basis.z.z)
	for b: Dictionary in s.birds:
		var node: Node3D = b.node
		if not is_instance_valid(node):
			continue
		var want := _beside(car, b.home + Vector3(0, sin(_along.phase * 1.3 + b.phase) * 0.6, 0))
		node.position = node.position.lerp(want, minf(delta * 3.0, 1.0))
		node.rotation = Vector3(0, heading + PI, 0)
		BirdModels.flap(node, _along.phase * 9.0 + b.phase)
	# All of them at once, as if they were one thing.
	_along.flick -= delta
	if _along.flick <= 0.0:
		_along.flick = _rng.randf_range(1.5, 3.5)
		var lc := _late_city()
		if lc:
			lc.call("play_flicker", car.global_position - car.global_basis.x * 7.0)
		var gone := _rng.randf_range(GONE.x, GONE.y)
		for b: Dictionary in s.birds:
			if is_instance_valid(b.node) and b.node.visible:
				if lc:
					lc.call("add_shimmer", b.node, 1.0)
				b.node.visible = false
				b.node.set_meta("flicker", true)
				b.blink = gone
				b.glow = 0.0


## The flock peels off upward and is gone.
func _end_alongside() -> void:
	var s: Dictionary = _along.get("sighting", {})
	_along = {}
	if s.is_empty():
		return
	for b: Dictionary in s.birds:
		if is_instance_valid(b.node):
			b.node.visible = true
			b.node.set_meta("flicker", false)
			_unshimmer(b.node)
			b.blink = 0.0
			b.glow = 0.0
		b.state = "fly"
		b.vel = Vector3(_rng.randf_range(-2, 2), 4.0, _rng.randf_range(-2, 2))
		b.timer = 6.0
