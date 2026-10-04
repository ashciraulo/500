class_name TrafficWildlife
extends Node3D
## Birds and the odd kangaroo: magpies on any patch of grass in the daytime,
## ibis picking around the river foreshore and the city parks, and now and
## then a kangaroo grazing in Kings Park at dusk or dawn.
##
## They only appear on the ground the map says is grass (or sand/dirt), out
## of the player's view, and they clear off when the player gets close:
## birds fly away, a kangaroo bounds off into the bush. No physics; each
## animal is a handful of boxes moved by hand, so they cost next to nothing.

enum Kind { MAGPIE, IBIS, ROO }

## Where ibis hang about, [centre, radius] in world metres (origin at Little
## Shenton Lane; centres are rough).
const IBIS_SPOTS := [
	[Vector3(160, 0, 66), 90.0],      # Russell Square
	[Vector3(812, 0, -827), 220.0],   # Hyde Park and its lakes
	[Vector3(434, 0, 1280), 280.0],   # Supreme Court Gardens, Elizabeth Quay
	[Vector3(1048, 0, 1500), 380.0],  # Langley Park, Riverside Drive
	[Vector3(1850, 0, 835), 250.0],   # Claisebrook Cove
	[Vector3(2560, 0, 2000), 400.0],  # Heirisson Island
	[Vector3(198, 0, 2555), 600.0],   # South Perth foreshore
	[Vector3(-1600, 0, -1940), 400.0],  # Lake Monger
	[Vector3(-4810, 0, -2550), 800.0],  # Herdsman Lake
]
## Kangaroo country: Kings Park and Bold Park's edge of it.
const ROO_SPOTS := [
	[Vector3(-1800, 0, 1600), 1000.0],
]
const GROUND := {
	Kind.MAGPIE: [&"grass"],
	Kind.IBIS: [&"grass", &"sand"],
	Kind.ROO: [&"grass", &"dirt"],
}

@export var enabled := true
@export var max_magpies := 6
@export var max_ibis := 7
## Chance per check (every 1.5 s) of a kangaroo at dusk in Kings Park.
@export var roo_chance := 0.05

## Live animals: { kind, node, state, timer, target, vel, phase, seen }.
var animals: Array = []
var stats := { "spawned": 0, "fled": 0 }
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _pool := {}
var _timer := 0.0
var _call_timer := 4.0
var _roo_cooldown := 0.0


func setup(manager: Node) -> void:
	_manager = manager
	_rng.randomize()


func update(delta: float, focus: Vector3) -> void:
	_call_timer -= delta
	_roo_cooldown -= delta
	for a in animals.duplicate():
		_animate(a, delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.5
	for a in animals.duplicate():
		var d: float = a.node.global_position.distance_to(focus)
		if d > 260.0 or (d > 150.0 and not _manager._visible(a.node.global_position)) or (a.state == &"gone"):
			_release(a)
	if not enabled:
		return
	# Autoloads by path: this script is also compiled from tools that run
	# before the autoloads exist.
	var hour: float = get_node("/root/GameClock").time_of_day
	var rain: float = get_node("/root/Weather").rain
	if hour > 6.0 and hour < 19.0 and rain < 0.5 and count(Kind.MAGPIE) < max_magpies:
		_try_spawn(Kind.MAGPIE, focus, mini(_rng.randi_range(1, 3), max_magpies - count(Kind.MAGPIE)))
	if hour > 6.5 and hour < 18.5 and rain < 0.6 and count(Kind.IBIS) < max_ibis and _near(IBIS_SPOTS, focus, 120.0):
		_try_spawn(Kind.IBIS, focus, mini(_rng.randi_range(2, 5), max_ibis - count(Kind.IBIS)))
	var dusk := (hour > 17.4 and hour < 19.8) or (hour > 5.2 and hour < 7.0)
	if dusk and _roo_cooldown <= 0.0 and count(Kind.ROO) == 0 and _near(ROO_SPOTS, focus, 0.0) \
			and _rng.randf() < roo_chance:
		if _try_spawn(Kind.ROO, focus, 1 if _rng.randf() < 0.75 else 2) > 0:
			_roo_cooldown = 90.0


func count(kind: int) -> int:
	var n := 0
	for a in animals:
		if a.kind == kind:
			n += 1
	return n


func clear() -> void:
	for a in animals.duplicate():
		_release(a)


## Put a group of `kind` at a point near `at` (if the ground there suits
## them). Returns how many appeared. Used by the spawner and by tests.
func spawn_group(kind: int, at: Vector3, n: int, check_ground := true) -> int:
	var made := 0
	for i in n:
		var p := at + Vector3(_rng.randf_range(-3.0, 3.0), 0, _rng.randf_range(-3.0, 3.0)) * (1.0 if i > 0 else 0.0)
		var g := _ground(p)
		if g.is_empty() or (check_ground and not GROUND[kind].has(g.surface)):
			continue
		_add(kind, g.pos)
		made += 1
	return made


func _try_spawn(kind: int, focus: Vector3, n: int) -> int:
	var near := 30.0 if kind != Kind.ROO else 45.0
	var far := 95.0 if kind != Kind.ROO else 120.0
	for attempt in 6:
		var ang := _rng.randf() * TAU
		var p := focus + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(near, far)
		if kind == Kind.IBIS and not _near(IBIS_SPOTS, p, 0.0):
			continue
		if kind == Kind.ROO and not _near(ROO_SPOTS, p, 0.0):
			continue
		if _manager._visible(p + Vector3(0, 1, 0), 25.0):
			continue
		var made := spawn_group(kind, p, n)
		if made > 0:
			return made
	return 0


static func _near(spots: Array, p: Vector3, extra: float) -> bool:
	for spot in spots:
		var c: Vector3 = spot[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < spot[1] + extra:
			return true
	return false


## The ground under p: { pos, surface }, or {} for nothing.
func _ground(p: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 80, 0), p - Vector3(0, 120, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var surface: StringName = hit.collider.get_meta("surface", &"") if hit.collider else &""
	return { "pos": hit.position, "surface": StringName(surface) }


func _add(kind: int, p: Vector3) -> void:
	var list: Array = _pool.get(kind, [])
	var node: Node3D = list.pop_back() if not list.is_empty() else _make(kind)
	if node.get_parent() == null:
		add_child(node)
	node.visible = true
	node.position = p
	node.rotation = Vector3(0, _rng.randf() * TAU, 0)
	animals.append({ "kind": kind, "node": node, "state": &"idle", "timer": _rng.randf_range(0.5, 3.0),
		"target": p, "vel": Vector3.ZERO, "phase": _rng.randf() * TAU, "ground": p.y, "hop_t": 0.0 })
	stats.spawned += 1


func _release(a: Dictionary) -> void:
	animals.erase(a)
	a.node.visible = false
	a.node.position = Vector3(0, -500, 0)
	if not _pool.has(a.kind):
		_pool[a.kind] = []
	_pool[a.kind].append(a.node)


## What might spook an animal: [position, speed] of the player in the car
## and on foot.
func _threats() -> Array:
	var out := []
	for proxy in [_manager._player_proxy, _manager._walker_proxy]:
		if proxy.present:
			out.append([proxy.position, proxy.speed])
	return out


func _spooked(a: Dictionary) -> Vector3:
	var p: Vector3 = a.node.global_position
	for t in _threats():
		var d: float = Vector2(p.x - t[0].x, p.z - t[0].z).length()
		var reach: float
		match a.kind:
			Kind.MAGPIE: reach = 4.0 + t[1] * 0.7
			Kind.IBIS: reach = 5.0 + t[1] * 0.6
			_: reach = 16.0 + t[1] * 1.2
		if d < reach:
			var away: Vector3 = p - t[0]
			away.y = 0.0
			return away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	return Vector3.ZERO


func _animate(a: Dictionary, delta: float) -> void:
	var node: Node3D = a.node
	a.phase += delta
	match a.state:
		&"idle", &"walk":
			var away: Vector3 = _spooked(a)
			if away != Vector3.ZERO:
				_flee(a, away)
				return
			if a.state == &"walk":
				var to: Vector3 = a.target - node.position
				to.y = 0.0
				var speed := 0.7 if a.kind != Kind.ROO else 0.9
				if to.length() < 0.1:
					a.state = &"idle"
				else:
					node.position += to.normalized() * minf(speed * delta, to.length())
					node.rotation.y = lerp_angle(node.rotation.y, atan2(-to.x, -to.z), minf(delta * 6.0, 1.0))
			a.timer -= delta
			# Pecking or grazing: head down and up.
			var head: Node3D = node.get_node("Head")
			var down: bool = a.state == &"idle" and fmod(a.phase, 2.2) < 0.9
			head.rotation.x = lerpf(head.rotation.x, -0.9 if down else 0.0, minf(delta * 8.0, 1.0))
			if a.timer <= 0.0:
				a.timer = _rng.randf_range(1.5, 5.0)
				if _rng.randf() < 0.5:
					var step := Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
					var g := _ground(node.position + step)
					if not g.is_empty() and GROUND[a.kind].has(g.surface) and absf(g.pos.y - node.position.y) < 0.6:
						a.target = g.pos
						a.state = &"walk"
				if a.kind == Kind.MAGPIE and _call_timer <= 0.0 and _rng.randf() < 0.3:
					_call_timer = _rng.randf_range(6.0, 14.0)
					_sound("amb/amb_bird_magpie", node.global_position, -4.0)
		&"fly":
			a.vel.y = minf(a.vel.y + 2.5 * delta, 4.0)
			node.position += a.vel * delta
			var flap := sin(a.phase * 22.0) * 0.9
			node.get_node("WingL").rotation.z = flap
			node.get_node("WingR").rotation.z = -flap
			if node.position.y - a.ground > 30.0:
				a.state = &"gone"
		&"hop":
			# Big bounds: up and down with each hop, ground followed loosely.
			a.hop_t += delta
			node.position.x += a.vel.x * delta
			node.position.z += a.vel.z * delta
			if fmod(a.hop_t, 0.5) < delta:
				var g := _ground(node.position)
				if not g.is_empty():
					a.ground = g.pos.y
			node.position.y = a.ground + absf(sin(a.hop_t * TAU)) * 0.7
			node.rotation.x = -0.25 * sin(a.hop_t * TAU)
			if a.hop_t > 14.0:
				a.state = &"gone"


func _flee(a: Dictionary, away: Vector3) -> void:
	var node: Node3D = a.node
	stats.fled += 1
	away = away.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	node.rotation = Vector3(0, atan2(-away.x, -away.z), 0)
	a.ground = node.position.y
	if a.kind == Kind.ROO:
		a.state = &"hop"
		a.hop_t = 0.0
		a.vel = away * _rng.randf_range(7.0, 9.0)
		node.get_node("Head").rotation.x = 0.0
	else:
		a.state = &"fly"
		a.vel = away * _rng.randf_range(4.0, 6.0) + Vector3(0, 2.0, 0)
		node.get_node("Head").rotation.x = 0.0
		node.get_node("WingL").visible = true
		node.get_node("WingR").visible = true
		if a.kind == Kind.MAGPIE and _rng.randf() < 0.35:
			_sound("amb/amb_bird_magpie", node.global_position, -2.0)


func _sound(sound_name: String, p: Vector3, db: float) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play_at"):
		audio.play_at(sound_name, p, db, "SFX")


# --- Models -------------------------------------------------------------------

func _make(kind: int) -> Node3D:
	var root := Node3D.new()
	match kind:
		Kind.MAGPIE:
			_bird(root, 1.0, Color(0.05, 0.05, 0.06), Color(0.92, 0.92, 0.9), Color(0.05, 0.05, 0.06), Color(0.75, 0.75, 0.7), false)
		Kind.IBIS:
			_bird(root, 1.55, Color(0.86, 0.85, 0.8), Color(0.82, 0.8, 0.74), Color(0.06, 0.06, 0.06), Color(0.08, 0.08, 0.08), true)
		Kind.ROO:
			_roo(root)
	root.name = ["Magpie", "Ibis", "Kangaroo"][kind]
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 140.0
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## A bird facing -Z: body, tail, head with beak (on a "Head" pivot so it can
## peck), legs, and wings (hidden until it flies).
func _bird(root: Node3D, s: float, body_c: Color, wing_c: Color, head_c: Color, beak_c: Color, curved: bool) -> void:
	var body := TrafficModels.material(body_c)
	var wing := TrafficModels.material(wing_c)
	var head_m := TrafficModels.material(head_c)
	var beak := TrafficModels.material(beak_c)
	var legs := TrafficModels.material(Color(0.15, 0.13, 0.12))
	var leg_h := 0.09 * s * (1.8 if curved else 1.0)
	TrafficModels._add_part(root, "bird_body_%s" % s, Vector3(0.13, 0.12, 0.26) * s, Vector3(0, leg_h + 0.06 * s, 0), Vector3(0.15, 0, 0), body)
	TrafficModels._add_part(root, "bird_tail_%s" % s, Vector3(0.08, 0.03, 0.12) * s, Vector3(0, leg_h + 0.07 * s, 0.17 * s), Vector3(-0.3, 0, 0), wing)
	# Magpie: white patch on the back of the neck and the wing.
	TrafficModels._add_part(root, "bird_patch_%s" % s, Vector3(0.135, 0.05, 0.1) * s, Vector3(0, leg_h + 0.1 * s, 0.02 * s), Vector3.ZERO, wing)
	for side in [-1.0, 1.0]:
		TrafficModels._add_part(root, "bird_leg_%s" % s, Vector3(0.015, leg_h, 0.015) * Vector3(s, 1, s), Vector3(side * 0.03 * s, leg_h * 0.5, 0), Vector3.ZERO, legs)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, leg_h + 0.1 * s, -0.12 * s)
	root.add_child(head)
	TrafficModels._add_part(head, "bird_neck_%s" % s, Vector3(0.06, 0.1 if curved else 0.05, 0.06) * s, Vector3(0, 0.04 * s, -0.02 * s), Vector3(0.3, 0, 0), head_m if curved else body)
	TrafficModels._add_part(head, "bird_head_%s" % s, Vector3(0.07, 0.07, 0.08) * s, Vector3(0, (0.12 if curved else 0.07) * s, -0.05 * s), Vector3.ZERO, head_m)
	if curved:
		# The ibis' long down-curved bill, in two pieces.
		TrafficModels._add_part(head, "ibis_bill_a", Vector3(0.018, 0.018, 0.09) * s, Vector3(0, 0.11 * s, -0.13 * s), Vector3(0.25, 0, 0), beak)
		TrafficModels._add_part(head, "ibis_bill_b", Vector3(0.016, 0.016, 0.08) * s, Vector3(0, 0.085 * s, -0.2 * s), Vector3(0.7, 0, 0), beak)
	else:
		TrafficModels._add_part(head, "magpie_beak", Vector3(0.025, 0.025, 0.06), Vector3(0, 0.07, -0.11), Vector3(0.1, 0, 0), beak)
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.name = "WingL" if side < 0.0 else "WingR"
		w.position = Vector3(side * 0.06 * s, leg_h + 0.1 * s, 0)
		w.visible = false
		root.add_child(w)
		TrafficModels._add_part(w, "bird_wing_%s" % s, Vector3(0.24, 0.015, 0.14) * s, Vector3(side * 0.12 * s, 0, 0), Vector3.ZERO, wing)


## A grey-brown kangaroo facing -Z, about 1.4 m tall standing.
func _roo(root: Node3D) -> void:
	var fur := TrafficModels.material(Color(0.47, 0.4, 0.33))
	var pale := TrafficModels.material(Color(0.66, 0.6, 0.52))
	var dark := TrafficModels.material(Color(0.12, 0.1, 0.09))
	TrafficModels._add_part(root, "roo_body", Vector3(0.34, 0.6, 0.42), Vector3(0, 0.62, 0.05), Vector3(-0.45, 0, 0), fur)
	TrafficModels._add_part(root, "roo_belly", Vector3(0.26, 0.42, 0.1), Vector3(0, 0.66, -0.16), Vector3(-0.45, 0, 0), pale)
	TrafficModels._add_part(root, "roo_chest", Vector3(0.24, 0.3, 0.26), Vector3(0, 0.98, -0.12), Vector3(-0.2, 0, 0), fur)
	TrafficModels._add_part(root, "roo_tail", Vector3(0.12, 0.1, 0.8), Vector3(0, 0.2, 0.55), Vector3(0.25, 0, 0), fur)
	for side in [-1.0, 1.0]:
		TrafficModels._add_part(root, "roo_thigh", Vector3(0.12, 0.3, 0.32), Vector3(side * 0.15, 0.35, 0.12), Vector3(0.3, 0, 0), fur)
		TrafficModels._add_part(root, "roo_foot", Vector3(0.08, 0.06, 0.34), Vector3(side * 0.15, 0.03, -0.02), Vector3.ZERO, dark)
		TrafficModels._add_part(root, "roo_arm", Vector3(0.05, 0.22, 0.05), Vector3(side * 0.09, 0.84, -0.24), Vector3(-0.5, 0, 0), fur)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.12, -0.18)
	root.add_child(head)
	TrafficModels._add_part(head, "roo_head", Vector3(0.14, 0.14, 0.24), Vector3(0, 0.06, -0.06), Vector3.ZERO, fur)
	TrafficModels._add_part(head, "roo_nose", Vector3(0.07, 0.06, 0.04), Vector3(0, 0.04, -0.19), Vector3.ZERO, dark)
	for side in [-1.0, 1.0]:
		TrafficModels._add_part(head, "roo_ear", Vector3(0.05, 0.14, 0.03), Vector3(side * 0.05, 0.19, 0.03), Vector3(0, 0, side * 0.2), fur)
