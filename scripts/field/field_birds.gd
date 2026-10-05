class_name FieldBirds
extends Node3D
## Bird sightings around the player: the field journal's species (see
## data/field/birds.json) turning up in their real places at their hours.
##
## A sighting is one species, one to a handful of birds, perched where that
## species would be: on a lawn, in a tree crown, on the water, on a post in
## the shallows, or circling overhead. From a distance a sighting gives
## itself away (Dredge's bubbles): a few birds lift off and wheel about over
## it now and then, and it calls. Get too close too fast and they flush.
##
## Sightings appear out of view and go when you leave the area or their hour
## passes. Each one only stands for so many photos before the birds move on.

const CHECK := 1.5
const SPAWN_NEAR := 70.0
const SPAWN_FAR := 330.0
const KEEP := 700.0
const MAX_SIGHTINGS := 6
const RARITY_WEIGHT := {1: 10.0, 2: 4.0, 3: 1.4, 4: 0.45}
const GROUND_SURFACES := [&"grass", &"dirt", &"sand"]
## Tree props from the map, and where their crowns are: [trunk height, crown radius].
const TREE_KINDS := {"props_tree_round": [2.4, 2.3], "props_tree_gum": [4.2, 2.6]}

## Live sightings: {id, species, habitat, centre, perch, birds, frames, leaving, cue, call_timer}.
var sightings: Array = []
var stats := {"spawned": 0, "flushed": 0}
## Tests switch the clock-driven spawning off and place sightings by hand.
var auto_spawn := true

var _rng := RandomNumberGenerator.new()
var _timer := 0.5
var _tree_cache := {}  # tile root instance id -> Array of [crown centre, crown radius, transform, twigs]
var _twig_cache := {}  # crown mesh -> its outer points


func _ready() -> void:
	add_to_group(&"field_bird_spawner")
	_rng.randomize()


func _process(delta: float) -> void:
	for s: Dictionary in sightings:
		for b: Dictionary in s.birds:
			_animate(b, delta)
		_update_cue(s, delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK
	var focus := player_position()
	if focus == Vector3.INF:
		return
	_cull(focus)
	if auto_spawn:
		_try_wrong(focus)
	if auto_spawn and sightings.size() < MAX_SIGHTINGS:
		_try_spawn(focus)


# --- who and where ---------------------------------------------------------------

func _car() -> CarController:
	return get_tree().get_first_node_in_group(&"player_car") as CarController


func _walker() -> Node3D:
	var car := _car()
	if car == null:
		return null
	var p := car.get_parent().get_node_or_null(^"Player") as Node3D
	if p and not p.get("in_car"):
		return p
	return null


## Where the player is (on foot or in the car), or INF.
func player_position() -> Vector3:
	var w := _walker()
	if w:
		return w.global_position
	var car := _car()
	return car.global_position if car else Vector3.INF


func _player_speed() -> float:
	var w := _walker()
	if w:
		return (w as CharacterBody3D).velocity.length() if w is CharacterBody3D else 0.0
	var car := _car()
	return car.linear_velocity.length() if car else 0.0


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _in_view(p: Vector3) -> bool:
	var cam := _camera()
	return cam != null and cam.is_position_in_frustum(p)


func _boats() -> Node:
	var traffic := get_tree().get_first_node_in_group(&"traffic")
	return traffic.get("boats") if traffic else null


func _hour() -> float:
	return GameClock.time_of_day


# --- spawning --------------------------------------------------------------------------

func _try_spawn(focus: Vector3) -> void:
	var near := FieldJournal.habitats_near(focus, SPAWN_FAR)
	if near.is_empty():
		return
	var h: Dictionary = near[_rng.randi() % near.size()]
	var options := FieldJournal.candidates(h, _hour(), Weather.rain)
	if options.is_empty():
		return
	var species := _pick(options)
	# Don't double up a species already showing nearby.
	for s: Dictionary in sightings:
		if s.id == species.id and s.centre.distance_to(focus) < SPAWN_FAR:
			return
	var c := FieldJournal.habitat_centre(h)
	for attempt in 6:
		var ang := _rng.randf() * TAU
		var p := focus + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(SPAWN_NEAR, SPAWN_FAR)
		if Vector2(p.x - c.x, p.z - c.z).length() > float(h.radius):
			continue
		if p.distance_to(focus) < 170.0 and _in_view(p + Vector3.UP * 2.0):
			continue
		if spawn(species, h, p) != {}:
			return


func _pick(options: Array) -> Dictionary:
	var total := 0.0
	for b: Dictionary in options:
		total += RARITY_WEIGHT.get(int(b.rarity), 1.0)
	var r := _rng.randf() * total
	for b: Dictionary in options:
		r -= RARITY_WEIGHT.get(int(b.rarity), 1.0)
		if r <= 0.0:
			return b
	return options.back()


## Put a sighting of `species` near p in habitat h. Returns it, or {} if
## there's nowhere for that bird there. Used by the spawner and by tests.
func spawn(species: Dictionary, h: Dictionary, p: Vector3) -> Dictionary:
	var perch := String(species.get("perch", "ground"))
	var spots := _perches(perch, species, h, p)
	if spots.is_empty():
		return {}
	var flock: Array = species.get("flock", [1, 1])
	var n := mini(_rng.randi_range(int(flock[0]), int(flock[1])), spots.size())
	var s := {"id": String(species.id), "species": species, "habitat": h, "centre": spots[0].pos, "perch": perch,
		"birds": [], "frames": _rng.randi_range(2, 4), "leaving": false, "cue": null,
		"cue_timer": _rng.randf_range(1.0, 6.0), "call_timer": _rng.randf_range(2.0, 8.0), "props": []}
	for spot: Dictionary in spots:
		if spot.has("post"):
			add_child(spot.post)
			s.props.append(spot.post)
	for i in n:
		s.birds.append(_add_bird(s, spots[i]))
	if perch != "air":
		s.cue = _make_cue(species)
		s.cue.position = s.centre + Vector3.UP * (9.0 if perch == "tree" else 6.0)
		add_child(s.cue)
	sightings.append(s)
	stats.spawned += 1
	return s


## Spots for each bird of the flock: [{pos, kind, ...}] with the first as the centre.
func _perches(perch: String, species: Dictionary, h: Dictionary, p: Vector3) -> Array:
	var out := []
	var size := float(species.get("size", 0.3))
	match perch:
		"ground", "shore":
			var g := ground(p)
			if g.is_empty() or not GROUND_SURFACES.has(g.surface):
				return []
			if perch == "shore" and not _near_water(g.pos, 30.0) and not Array(h.get("tags", [])).has("beach"):
				return []
			out.append({"pos": g.pos, "kind": "ground"})
			for i in 7:
				var q := ground(g.pos + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)) * (1.0 + size))
				if not q.is_empty() and GROUND_SURFACES.has(q.surface) and absf(q.pos.y - g.pos.y) < 0.8:
					out.append({"pos": q.pos, "kind": "ground"})
		"water":
			var level := water_level(h, p)
			if level == INF:
				return []
			var at := Vector3(p.x, level, p.z)
			out.append({"pos": at, "kind": "water"})
			for i in 7:
				var q := at + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4)) * (1.0 + size)
				if water_level(h, q) != INF:
					out.append({"pos": q, "kind": "water"})
		"post":
			var level := water_level(h, p)
			if level == INF:
				return _perches("tree", species, h, p)
			var bed := ground(p)
			var base_y: float = bed.pos.y if not bed.is_empty() else level - 2.0
			var post := _make_post(base_y, level + 1.1)
			post.position = Vector3(p.x, 0, p.z)
			out.append({"pos": Vector3(p.x, level + 1.1, p.z), "kind": "post", "post": post})
			# One bird per post; neighbours get posts of their own.
			for i in 2:
				var q := p + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
				if water_level(h, q) != INF:
					var bq := ground(q)
					var other := _make_post(bq.pos.y if not bq.is_empty() else level - 2.0, level + _rng.randf_range(0.8, 1.3))
					other.position = Vector3(q.x, 0, q.z)
					out.append({"pos": Vector3(q.x, other.get_meta("top"), q.z), "kind": "post", "post": other})
		"tree":
			var crowns := trees_near(p, 45.0)
			if crowns.is_empty():
				var g := ground(p)
				if g.is_empty() or not GROUND_SURFACES.has(g.surface):
					return []
				# No tree here: a dead snag does as well (they love a dead branch).
				var snag := _make_snag()
				snag.position = g.pos
				var top: Vector3 = g.pos + Vector3(0, snag.get_meta("top"), 0)
				out.append({"pos": top, "kind": "post", "post": snag})
				for i in 2:
					out.append({"pos": top + Vector3(_rng.randf_range(-0.6, 0.6), -_rng.randf_range(0.3, 1.2), 0), "kind": "post"})
				return out
			var crown: Array = crowns[0]
			for i in 8:
				out.append({"pos": crown_spot(crown, player_position()), "kind": "tree", "crown": crown})
		"air":
			var g := ground(p)
			var base: float
			if not g.is_empty():
				base = g.pos.y
			else:
				base = water_level(h, p)
				if base == INF:
					return []
			var high := 4.0 if species.model == "swallow" else 18.0
			for i in 6:
				out.append({"pos": Vector3(p.x, base + high + _rng.randf_range(0, 6), p.z), "kind": "air", "radius": _rng.randf_range(6, 16) if high < 10 else _rng.randf_range(14, 26)})
	return out


func _add_bird(s: Dictionary, spot: Dictionary) -> Dictionary:
	var node := BirdModels.build(s.species)
	node.add_to_group(&"field_birds")
	node.set_meta("species", s.id)
	add_child(node)
	node.position = spot.pos
	node.rotation.y = _rng.randf() * TAU
	var b := {"node": node, "sighting": s, "state": "perch", "kind": spot.kind, "home": spot.pos,
		"timer": _rng.randf_range(0.5, 3.0), "target": spot.pos, "vel": Vector3.ZERO, "phase": _rng.randf() * TAU,
		"crown": spot.get("crown", []), "radius": spot.get("radius", 10.0), "speed": 0.0}
	node.set_meta("bird", b)
	if spot.kind == "air":
		b.state = "circle"
		b.speed = (6.0 if s.species.model == "swallow" else 3.0) * _rng.randf_range(0.8, 1.2)
		BirdModels.set_flying(node, true)
	elif spot.kind == "tree":
		# Face out from the crown, give or take.
		var out: Vector3 = spot.pos - spot.crown[0]
		node.rotation.y = atan2(-out.x, -out.z) + _rng.randf_range(-1.3, 1.3)
	return b


# --- the world under them ---------------------------------------------------------------

## The ground under p: {pos, surface}, or {}.
func ground(p: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.z), Vector3(p.x, -60.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var surface: StringName = hit.collider.get_meta("surface", &"") if hit.collider else &""
	return {"pos": hit.position, "surface": StringName(surface)}


## The water surface height at p in habitat h, or INF when p isn't on open water.
func water_level(h: Dictionary, p: Vector3) -> float:
	var boats := _boats()
	if boats == null or not boats.has_method("water_at") or not boats.water_at(p, 4.0):
		return INF
	# Lakes sit above the river: their heights come from the map, per 25 m cell
	# (tools/field/water_levels.gd). The river and the sea are at 0.
	var river: bool = Array(h.get("tags", [])).has("river")
	var best := INF
	var best_d := 35.0 * 35.0
	for cell: Array in h.get("water", []):
		var d := Vector2(p.x - float(cell[0]), p.z - float(cell[1])).length_squared()
		if d < best_d:
			best_d = d
			best = float(cell[2])
	if river and (best == INF or best < 0.5):
		return 0.0
	if best == INF and h.has("water"):
		return INF
	return best if best != INF else 0.0


func _near_water(p: Vector3, r: float) -> bool:
	var boats := _boats()
	if boats == null or not boats.has_method("water_at"):
		return false
	for i in 8:
		var a := TAU * i / 8.0
		if boats.water_at(p + Vector3(cos(a), 0, sin(a)) * r):
			return true
	return false


## Tree crowns from the map's props near p: [[centre, radius], ...], nearest first.
func trees_near(p: Vector3, r: float) -> Array:
	var map := FieldJournal.map_node()
	var out := []
	if map == null:
		return out
	for tile in map.get_children():
		if not tile is Node3D:
			continue
		for crown: Array in _tile_trees(tile):
			var d := Vector2(crown[0].x - p.x, crown[0].z - p.z).length()
			if d < r:
				out.append([crown[0], crown[1], d, crown[2], crown[3]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	return out


func _tile_trees(tile: Node3D) -> Array:
	var key := tile.get_instance_id()
	if _tree_cache.has(key):
		return _tree_cache[key]
	var crowns := []
	for kind: String in TREE_KINDS:
		var mmi := tile.get_node_or_null(NodePath(kind)) as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var dims: Array = TREE_KINDS[kind]
		var xf := mmi.global_transform
		for i in mmi.multimesh.instance_count:
			var t := xf * mmi.multimesh.get_instance_transform(i)
			var scale := t.basis.get_scale().y
			crowns.append([t.origin + Vector3(0, (dims[0] + dims[1] * 0.6) * scale, 0), dims[1] * scale, t, _twigs(mmi.multimesh.mesh, dims)])
	_tree_cache[key] = crowns
	if _tree_cache.size() > 64:
		_tree_cache.erase(_tree_cache.keys()[0])
	return crowns


## A place on the outside of a tree's crown: the tip of one of the crown
## mesh's outer points, so the bird sits on the leaves rather than in them.
## `toward`: favour the side of the tree facing this point (the player), so
## the bird isn't hidden behind the leaves.
func crown_spot(crown: Array, toward := Vector3.INF) -> Vector3:
	var twigs: PackedVector3Array = crown[4] if crown.size() > 4 else PackedVector3Array()
	var centre: Vector3 = crown[0]
	var facing := Vector3.ZERO
	if toward != Vector3.INF:
		facing = Vector3(toward.x - centre.x, 0, toward.z - centre.z).normalized()
	if twigs.is_empty():
		var a := _rng.randf() * TAU
		if facing != Vector3.ZERO:
			a = atan2(facing.z, facing.x) + _rng.randf_range(-0.9, 0.9)
		var r: float = crown[1]
		return centre + Vector3(cos(a) * r * 1.1, r * _rng.randf_range(0.1, 0.5), sin(a) * r * 1.1)
	var xf: Transform3D = crown[3]
	var best := Vector3.ZERO
	var best_dot := -INF
	for i in (10 if facing != Vector3.ZERO else 1):
		var p: Vector3 = xf * twigs[_rng.randi() % twigs.size()]
		var d := Vector3(p.x - centre.x, 0, p.z - centre.z).normalized().dot(facing) + _rng.randf_range(0.0, 0.3)
		if d > best_dot:
			best_dot = d
			best = p
	var out: Vector3 = best - centre
	out.y = 0.0
	return best + out.normalized() * 0.12


## The crown mesh's outer, upper points (local), once per mesh. Empty when
## the mesh can't be read (the headless dummy renderer).
func _twigs(mesh: Mesh, dims: Array) -> PackedVector3Array:
	if mesh == null:
		return PackedVector3Array()
	if _twig_cache.has(mesh):
		return _twig_cache[mesh]
	var out := PackedVector3Array()
	var centre_y: float = dims[0] + dims[1] * 0.6
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			# Leaves only (above the trunk), the upper half and the outer edge.
			if v.y > centre_y - dims[1] * 0.1 and Vector2(v.x, v.z).length() > dims[1] * 0.55 and not out.has(v):
				out.append(v)
	_twig_cache[mesh] = out
	return out


# --- leaving ----------------------------------------------------------------------------------

func _cull(focus: Vector3) -> void:
	var hour := _hour()
	for s: Dictionary in sightings.duplicate():
		var d: float = s.centre.distance_to(focus)
		var alive: Array = s.birds.filter(func(b: Dictionary) -> bool: return b.state != "gone")
		if alive.is_empty() or d > KEEP:
			_remove(s)
		elif not s.leaving and not FieldJournal.is_about(s.species, hour, Weather.rain) and not _in_view(s.centre):
			_remove(s)


func _remove(s: Dictionary) -> void:
	sightings.erase(s)
	if s.has("lights_cb"):
		var traffic := get_tree().get_first_node_in_group(&"traffic") if is_inside_tree() else null
		if traffic and traffic.is_connected("signals_changed", s.lights_cb):
			traffic.disconnect("signals_changed", s.lights_cb)
	for b: Dictionary in s.birds:
		if is_instance_valid(b.node):
			b.node.queue_free()
	if s.cue and is_instance_valid(s.cue):
		s.cue.queue_free()
	for prop: Node in s.props:
		if is_instance_valid(prop):
			prop.queue_free()


func clear() -> void:
	for s: Dictionary in sightings.duplicate():
		_remove(s)


## Send a bird (and the rest of its flock) off, away from `from`.
func flush(node: Node3D, from: Vector3) -> void:
	var b: Dictionary = node.get_meta("bird", {})
	if b.is_empty():
		return
	var s: Dictionary = b.sighting
	if s.leaving:
		return
	s.leaving = true
	stats.flushed += 1
	_sound("field/flush", node.global_position, -4.0)
	for other: Dictionary in s.birds:
		_take_off(other, from)


## The lab-worthy shot was taken: one fewer frame before this flock moves on.
func photographed(node: Node3D) -> void:
	var b: Dictionary = node.get_meta("bird", {})
	if b.is_empty():
		return
	var s: Dictionary = b.sighting
	s.frames -= 1
	if s.frames <= 0 and not s.leaving:
		s.leaving = true
		for other: Dictionary in s.birds:
			other.timer = _rng.randf_range(1.5, 4.0)
			other.state = "leave" if other.state != "circle" else "circle_out"


func _take_off(b: Dictionary, from: Vector3) -> void:
	if b.state == "gone" or b.state == "fly":
		return
	var away: Vector3 = b.node.global_position - from
	away.y = 0.0
	away = (away.normalized() if away.length() > 0.1 else Vector3.FORWARD).rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
	b.vel = away * _rng.randf_range(5.0, 8.0) + Vector3.UP * 2.5
	b.state = "fly"
	b.timer = 8.0
	BirdModels.set_flying(b.node, true)
	b.node.rotation = Vector3(0, atan2(-away.x, -away.z), 0)


# --- behaviour ---------------------------------------------------------------------------------

func _threat_distance(b: Dictionary) -> float:
	var shy := float(b.sighting.species.get("shy", 0.3))
	return 4.0 + shy * 16.0 + _player_speed() * 1.1


func _animate(b: Dictionary, delta: float) -> void:
	var node: Node3D = b.node
	if not is_instance_valid(node):
		b.state = "gone"
		return
	b.phase += delta
	if b.sighting.has("wrong") and b.state == "perch":
		_wrong_behaviour(b, delta)
		return
	match b.state:
		"perch", "walk":
			var focus := player_position()
			if focus != Vector3.INF and node.global_position.distance_to(focus) < _threat_distance(b):
				if b.kind == "water" and node.global_position.distance_to(focus) > 4.0:
					# Swimmers paddle off rather than fly.
					var away: Vector3 = node.global_position - focus
					away.y = 0.0
					b.target = node.global_position + away.normalized() * 10.0
					b.state = "walk"
				else:
					flush(node, focus)
					return
			_peck(b, delta)
			if b.state == "walk":
				var to: Vector3 = b.target - node.position
				if b.kind != "tree" and b.kind != "post":
					to.y = 0.0
				var speed := 0.8 if b.kind != "water" else 0.6
				if to.length() < 0.05:
					b.state = "perch"
				else:
					node.position += to.normalized() * minf(speed * delta, to.length())
					node.rotation.y = lerp_angle(node.rotation.y, atan2(-to.x, -to.z), minf(delta * 5.0, 1.0))
			if b.kind == "water":
				node.position.y = b.home.y + sin(b.phase * 1.4) * 0.03
			b.timer -= delta
			if b.timer <= 0.0:
				b.timer = _rng.randf_range(1.5, 5.0)
				_wander(b)
		"leave", "fly":
			if b.state == "leave":
				b.timer -= delta
				if b.timer > 0.0:
					_peck(b, delta)
					return
				var p := player_position()
				_take_off(b, p if p != Vector3.INF else node.global_position + Vector3.FORWARD)
				return
			b.vel.y = minf(b.vel.y + 1.8 * delta, 4.5)
			node.position += b.vel * delta
			BirdModels.flap(node, b.phase * 20.0)
			b.timer -= delta
			if b.timer <= 0.0:
				b.state = "gone"
				node.visible = false
		"circle", "circle_out":
			var centre: Vector3 = b.home
			b.phase += delta * b.speed / maxf(b.radius, 1.0)
			var at := centre + Vector3(cos(b.phase) * b.radius, sin(b.phase * 0.7) * 1.5, sin(b.phase) * b.radius)
			if b.state == "circle_out":
				b.home += Vector3(0, delta * 3.0, 0)
				if b.home.y - b.sighting.centre.y > 60.0:
					b.state = "gone"
					node.visible = false
			var dir := at - node.position
			node.position = at
			if dir.length() > 0.001:
				node.rotation.y = atan2(-dir.x, -dir.z)
			BirdModels.flap(node, b.phase * 30.0, 0.5 + 0.5 * absf(sin(b.phase * 2.0)))
		"gone":
			pass


func _peck(b: Dictionary, delta: float) -> void:
	var head := b.node.get_node_or_null(^"Head") as Node3D
	if head == null:
		return
	var down: bool = b.kind == "ground" and b.state == "perch" and fmod(b.phase, 2.4) < 0.8
	var look := sin(b.phase * 0.9) * 0.5 if b.kind != "ground" else 0.0
	head.rotation.x = lerpf(head.rotation.x, -0.8 if down else 0.0, minf(delta * 8.0, 1.0))
	head.rotation.y = lerpf(head.rotation.y, look, minf(delta * 3.0, 1.0))


## Potter about: a few steps on the ground, along the crown, a slow paddle.
func _wander(b: Dictionary) -> void:
	if _rng.randf() < 0.5:
		return
	var node: Node3D = b.node
	match b.kind:
		"ground":
			var g := ground(node.position + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5)))
			if not g.is_empty() and GROUND_SURFACES.has(g.surface) and absf(g.pos.y - node.position.y) < 0.6:
				b.target = g.pos
				b.state = "walk"
		"water":
			b.target = b.home + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
			if water_level(b.sighting.habitat, b.target) != INF:
				b.state = "walk"
		"tree":
			var crown: Array = b.crown
			if crown.size() >= 2:
				b.target = crown_spot(crown, player_position())
				b.state = "walk"
				b.node.position = b.target  # a short hop through the leaves
				var out: Vector3 = b.target - crown[0]
				b.node.rotation.y = atan2(-out.x, -out.z) + _rng.randf_range(-1.3, 1.3)
				b.state = "perch"


# --- after midnight ---------------------------------------------------------------------------------
# The wrong birds (data/field/birds.json, wrong: true): one more each time the
# mystery moves on, each in its own place, after midnight. They don't flush
# and they don't feed; each does one wrong thing (`behaviour`).

## How near you have to be for one to be there.
const WRONG_RANGE := 300.0
## The frogmouth's pole, from the car's spot in the carport: [across, ahead].
const HOME_POLE := Vector2(2.6, 7.5)

var _photo_spots := {}


## Whether a wrong bird can be out now: the mystery is far enough along and
## it's its hour.
static func wrong_ready(sp: Dictionary, hour: float) -> bool:
	return sp.get("wrong", false) and Discoveries.has(String(sp.get("after", ""))) and FieldJournal.is_about(sp, hour, 0.0)


func _try_wrong(focus: Vector3) -> void:
	var hour := _hour()
	for id: String in FieldJournal.bird_order:
		var sp := FieldJournal.bird(id)
		if not wrong_ready(sp, hour) or sightings.any(func(s: Dictionary) -> bool: return s.id == id):
			continue
		var at := wrong_place(sp)
		if at == Vector3.INF:
			continue
		var d := Vector2(at.x - focus.x, at.z - focus.z).length()
		# Never pop in under your nose.
		if d > WRONG_RANGE or (d < 120.0 and _in_view(at + Vector3.UP)):
			continue
		spawn_wrong(sp, at)


## Where a wrong bird belongs, or INF if that place isn't loaded.
func wrong_place(sp: Dictionary) -> Vector3:
	var spot: Variant = sp.get("spot", "")
	if spot is Array:
		return Vector3(float(spot[0]), 0.0, float(spot[1]))
	match String(spot):
		"home_pole":
			var map := FieldJournal.map_node()
			if map == null or not map.has_method("get_spawn_transform"):
				return Vector3.INF
			var t: Transform3D = map.get_spawn_transform()
			return t.origin + t.basis.x * HOME_POLE.x - t.basis.z * HOME_POLE.y
		"shed_roof":
			var home := get_tree().get_first_node_in_group(&"home_base") as Node3D
			var shed := home.find_child("ShedInterior_Root", true, false) as Node3D if home else null
			# The shed is 2.4 m to the top of its flat roof.
			return shed.global_position + Vector3.UP * 2.42 if shed else Vector3.INF
	var h := FieldJournal.habitat(String(spot))
	if not h.is_empty():
		return FieldJournal.habitat_centre(h)
	if _photo_spots.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/places.json"))
		if parsed is Dictionary:
			for ps: Dictionary in parsed.get("photo_spots", []):
				_photo_spots[ps.id] = Vector3(ps.p[0], ps.p[1], ps.p[2])
	return _photo_spots.get(String(spot), Vector3.INF)


## Put a wrong bird (or thirteen) at its place. Returns the sighting or {}.
func spawn_wrong(sp: Dictionary, at: Vector3) -> Dictionary:
	var spots := []
	var props := []
	var flock: Array = sp.get("flock", [1, 1])
	var n := int(flock[1])
	match String(sp.get("perch", "ground")):
		"post":
			var top := at
			if String(sp.get("spot", "")) == "home_pole":
				var g := ground(at)
				if g.is_empty():
					return {}
				var pole := _make_pole()
				pole.position = g.pos
				props.append(pole)
				top = g.pos + Vector3(0, pole.get_meta("top"), 0)
			spots.append({"pos": top, "kind": "post"})
		"ground":
			var g := ground(at)
			if g.is_empty():
				return {}
			spots.append({"pos": g.pos, "kind": "ground"})
		"water":
			var h := {"tags": ["river"]}
			var boats := _boats()
			for r: float in [20.0, 35.0, 50.0, 70.0]:
				for i in 12:
					var q := at + Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0)) * r
					# Well out on the water, not on the bank the mask blurs into.
					if spots.is_empty() and boats and boats.water_at(q, 10.0) and water_level(h, q) != INF:
						spots.append({"pos": Vector3(q.x, water_level(h, q), q.z), "kind": "water"})
			if spots.is_empty():
				return {}
		"tree":
			var crowns := trees_near(at, 60.0)
			if crowns.is_empty():
				var g := ground(at)
				if g.is_empty():
					return {}
				var snag := _make_snag()
				snag.position = g.pos
				props.append(snag)
				var top: Vector3 = g.pos + Vector3(0, snag.get_meta("top"), 0)
				for i in n:
					spots.append({"pos": top + Vector3(_rng.randf_range(-0.7, 0.7), -_rng.randf_range(0.0, 1.6), _rng.randf_range(-0.3, 0.3)), "kind": "post"})
			else:
				# Spread over the nearest few crowns.
				for i in n:
					var crown: Array = crowns[i % mini(crowns.size(), 3)]
					spots.append({"pos": crown_spot(crown, player_position()), "kind": "tree", "crown": crown})
	if spots.is_empty():
		return {}
	var s := {"id": String(sp.id), "species": sp, "habitat": {}, "centre": spots[0].pos, "perch": String(sp.perch),
		"birds": [], "frames": 999, "leaving": false, "cue": null, "cue_timer": 0.0,
		"call_timer": _rng.randf_range(2.0, 6.0), "props": props, "wrong": true, "lift": 0.0}
	for prop: Node3D in props:
		add_child(prop)
	for i in n:
		var b := _add_bird(s, spots[i % spots.size()])
		s.birds.append(b)
		match String(sp.get("behaviour", "")):
			"still":
				# Facing upstream: east, up the river.
				b.node.rotation.y = -PI * 0.5
			"nest":
				var nest := _make_nest()
				nest.position = b.node.position + Vector3(0, -0.08, 0)
				add_child(nest)
				props.append(nest)
	if String(sp.get("behaviour", "")) == "lights":
		var traffic := get_tree().get_first_node_in_group(&"traffic")
		if traffic and traffic.has_signal("signals_changed"):
			var cb := func(p: Vector3) -> void:
				if p.distance_to(s.centre) < 60.0:
					s.lift = 2.5
			traffic.connect("signals_changed", cb)
			s["lights_cb"] = cb
	sightings.append(s)
	stats.spawned += 1
	return s


func _wrong_behaviour(b: Dictionary, delta: float) -> void:
	var s: Dictionary = b.sighting
	var node: Node3D = b.node
	var head := node.get_node_or_null(^"Head") as Node3D
	var focus := player_position()
	var k := minf(delta * 2.0, 1.0)
	match String(s.species.get("behaviour", "")):
		"watch":
			# The body stays put; the head follows the car, all the way round.
			if head and focus != Vector3.INF:
				var to := node.global_transform.affine_inverse() * focus
				var want := atan2(-to.x, -to.z)
				head.rotation.y += wrapf(want - head.rotation.y, -PI, PI) * k
		"silent", "house":
			# All of them turn to look at you (or, the last one, at the house).
			var target := focus
			if s.species.behaviour == "house":
				var home := get_tree().get_first_node_in_group(&"home_base") as Node3D
				target = home.global_position if home else focus
			if target != Vector3.INF:
				var to := target - node.global_position
				node.rotation.y = lerp_angle(node.rotation.y, atan2(-to.x, -to.z), k * 0.3)
		"sing":
			if head:
				head.rotation.x = lerpf(head.rotation.x, 0.5, k)
		"lights":
			# Head down, still; up when the lights change.
			s.lift = maxf(float(s.lift) - delta, 0.0)
			if head:
				head.rotation.x = lerpf(head.rotation.x, 0.45 if s.lift > 0.0 else -0.5, minf(delta * 4.0, 1.0))
		"still":
			pass


## A timber power pole with a crossarm, for the frogmouth outside home.
func _make_pole() -> Node3D:
	var holder := Node3D.new()
	var mat := PS1Material.make(Color(0.3, 0.25, 0.2), 0.95)
	var pole := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.11
	shaft.bottom_radius = 0.14
	shaft.height = 7.2
	shaft.radial_segments = 6
	pole.mesh = shaft
	pole.material_override = mat
	pole.position.y = 3.6
	holder.add_child(pole)
	var arm := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.1, 0.1)
	arm.mesh = box
	arm.material_override = mat
	arm.position.y = 6.6
	holder.add_child(arm)
	holder.set_meta("top", 7.2)
	return holder


## A twiggy nest woven through with shiny brown cassette tape.
func _make_nest() -> Node3D:
	var holder := Node3D.new()
	var twigs := MeshInstance3D.new()
	var bowl := SphereMesh.new()
	bowl.radius = 0.16
	bowl.height = 0.12
	bowl.radial_segments = 7
	bowl.rings = 3
	twigs.mesh = bowl
	twigs.material_override = PS1Material.make(Color(0.32, 0.26, 0.18), 0.95)
	holder.add_child(twigs)
	var tape_mat := PS1Material.make(Color(0.28, 0.17, 0.1), 0.2)
	tape_mat.set_shader_parameter("metallic", 0.6)
	for i in 5:
		var strand := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.36 + i * 0.05, 0.012, 0.025)
		strand.mesh = box
		strand.material_override = tape_mat
		strand.rotation = Vector3(0.2 * sin(i), i * 0.7, 0.25 * cos(i * 1.3))
		strand.position = Vector3(0, 0.03 - 0.02 * (i % 2), 0)
		holder.add_child(strand)
	return holder


# --- the giveaway ---------------------------------------------------------------------------------

## A few dark birds wheeling over the spot now and then: the sighting's tell.
func _make_cue(species: Dictionary) -> Node3D:
	var cue := Node3D.new()
	cue.name = "Cue"
	var mat := PS1Material.make(Color(0.08, 0.08, 0.09), 0.9)
	var span := clampf(float(species.get("size", 0.3)) * 1.6, 0.45, 1.6)
	for i in 5:
		var speck := Node3D.new()
		speck.name = "Speck%d" % i
		cue.add_child(speck)
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(span * 0.5, 0.05, span * 0.18)
			w.mesh = box
			w.material_override = mat
			w.position = Vector3(side * span * 0.22, 0, 0)
			w.rotation.z = side * 0.35
			w.name = "W" + ("L" if side < 0 else "R")
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			speck.add_child(w)
	cue.visible = false
	return cue


func _update_cue(s: Dictionary, delta: float) -> void:
	s.call_timer -= delta
	if s.call_timer <= 0.0 and not s.leaving:
		s.call_timer = _rng.randf_range(7.0, 18.0)
		var focus := player_position()
		if focus != Vector3.INF and s.centre.distance_to(focus) < 220.0 and not s.birds.is_empty():
			var caller: Dictionary = s.birds[_rng.randi() % s.birds.size()]
			if caller.state != "gone" and s.species.get("behaviour", "") != "silent":
				_sound(_call_for(s.species), caller.node.global_position, -6.0)
	var cue: Node3D = s.cue
	if cue == null or not is_instance_valid(cue):
		return
	s.cue_timer -= delta
	var focus := player_position()
	var d: float = s.centre.distance_to(focus) if focus != Vector3.INF else INF
	var wanted: bool = not s.leaving and d > 35.0 and d < 260.0 and GameClock.daylight() > 0.25
	if s.cue_timer <= 0.0:
		# On for a few seconds, off for longer: birds lifting and settling.
		cue.visible = wanted and not cue.visible
		s.cue_timer = _rng.randf_range(4.0, 6.0) if cue.visible else _rng.randf_range(5.0, 10.0)
	if not wanted:
		cue.visible = false
	if not cue.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var i := 0
	for speck: Node3D in cue.get_children():
		var a := t * (0.9 + i * 0.13) + i * 1.3
		var r := 3.5 + 2.0 * sin(i * 2.1)
		speck.position = Vector3(cos(a) * r, sin(t * 1.7 + i) * 1.2, sin(a) * r)
		speck.rotation.y = -a
		var flap := sin(t * 14.0 + i * 1.7) * 0.6
		(speck.get_child(0) as Node3D).rotation.z = -0.35 - flap
		(speck.get_child(1) as Node3D).rotation.z = 0.35 + flap
		i += 1


## A species' call; a wrong bird uses its own if the audio has one, or the
## call of the bird it looks like.
func _call_for(species: Dictionary) -> String:
	var own := call_sound(String(species.id))
	var like := String(species.get("like", ""))
	if like == "":
		return own
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("has") and audio.has(own):
		return own
	return call_sound(like)


static func call_sound(id: String) -> String:
	match id:
		"australian_magpie":
			return "amb/amb_bird_magpie"
		"australian_white_ibis":
			return "traffic/traffic_ibis_grunt"
	return "field/bird_" + id


func _sound(sound_name: String, p: Vector3, db: float) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play_at") and (not audio.has_method("has") or audio.has(sound_name)):
		audio.play_at(sound_name, p, db, "SFX")


# --- props ------------------------------------------------------------------------------------------

## A weathered post standing in the shallows, from the bed to `top`.
func _make_post(bed_y: float, top: float) -> Node3D:
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	var h := maxf(top - bed_y, 0.5)
	box.size = Vector3(0.18, h, 0.18)
	post.mesh = box
	post.material_override = PS1Material.make(Color(0.36, 0.3, 0.24), 0.95)
	var holder := Node3D.new()
	holder.add_child(post)
	post.position.y = bed_y + h * 0.5
	holder.set_meta("top", top)
	return holder


## A dead tree: a grey trunk and a couple of bare branches.
func _make_snag() -> Node3D:
	var root := Node3D.new()
	var mat := PS1Material.make(Color(0.55, 0.52, 0.48), 0.95)
	var h := _rng.randf_range(3.5, 5.0)
	for part in [[Vector3(0.22, h, 0.22), Vector3(0, h * 0.5, 0), Vector3.ZERO],
			[Vector3(0.1, 1.6, 0.1), Vector3(0.45, h * 0.75, 0), Vector3(0, 0, -0.7)],
			[Vector3(0.09, 1.3, 0.09), Vector3(-0.35, h * 0.85, 0.1), Vector3(0.2, 0, 0.8)]]:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		m.mesh = box
		m.position = part[1]
		m.rotation = part[2]
		m.material_override = mat
		root.add_child(m)
	root.set_meta("top", h)
	return root
