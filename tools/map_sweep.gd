extends SceneTree
## Checks every map tile for placement bugs, headless, without the game:
##
##   godot --headless --path . --script res://tools/map_sweep.gd -- out=/tmp/sweep.json [tiles=0_0,1_0]
##
## Per tile it builds the colliders and casts rays to find:
## - holes: no ground at all under a point of the tile;
## - props (trees, shrubs, street lights) floating above or sunk into the
##   ground, standing on a road, or inside a building;
## - buildings standing on a road;
## - steps along tile seams: the ground height either side of a shared edge.
## Findings go to `out` as JSON (one list per kind) with world positions, and
## a per-kind count is printed.

const GRID_HOLES := 8.0
const GRID_BUILDINGS := 4.0
const EDGE_STEP := 4.0
const EDGE_INSET := 0.3
const PROP_SLACK := 0.35
const SEAM_STEP := 0.3

var _tiles: Array[String] = []
var _at := 0
var _phase := 0
var _holder: Node3D
var _origin := Vector3.ZERO
var _result: MapTileLoader.TileResult
var _out := "user://map_sweep.json"
var _found := {holes = [], prop_float = [], prop_sunk = [], prop_on_road = [], prop_in_building = [],
	building_on_road = [], seam_step = [], seam_gap = []}
## "i_j" -> {n: [heights], s: [...], e: [...], w: [...]} sampled just inside each edge.
var _edges := {}
var _world: Node3D
var _started := 0
## Bodies the rays look through: the tile's own tree trunks and poles.
var _skip: Array[RID] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
		elif arg.begins_with("tiles="):
			for t in arg.trim_prefix("tiles=").split(","):
				_tiles.append(t)
	if _tiles.is_empty():
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://map/tiles/index.json"))
		for t: String in index.tiles:
			_tiles.append(t)
	_world = Node3D.new()
	root.add_child(_world)
	_started = Time.get_ticks_msec()
	print("SWEEP %d tiles" % _tiles.size())


func _process(_delta: float) -> bool:
	if _at >= _tiles.size():
		_compare_seams()
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string(JSON.stringify(_found))
		for kind: String in _found:
			print("SWEEP %-18s %d" % [kind, _found[kind].size()])
		print("SWEEP done in %.0f s, written to %s" % [(Time.get_ticks_msec() - _started) / 1000.0, _out])
		quit(0)
		return true
	if _phase == 0:
		var key := _tiles[_at]
		_result = MapTileLoader.build("res://map/tiles/%s.p5t" % key, {}, {})
		if _result.error != "":
			print("SWEEP skip ", key, " ", _result.error)
			_at += 1
			return false
		_origin = _result.root.position
		_holder = MapTileLoader.make_collision(_result)
		_holder.position = _origin
		_world.add_child(_holder)
		_phase = 1
		return false
	if _phase < 3:
		_phase += 1  # let the physics server pick the bodies up
		return false
	_check_tile(_tiles[_at])
	_holder.queue_free()
	_result.root.free()
	_phase = 0
	_at += 1
	if _at % 50 == 0:
		print("SWEEP %d / %d" % [_at, _tiles.size()])
	return false


func _space() -> PhysicsDirectSpaceState3D:
	return _world.get_world_3d().direct_space_state


func _down(x: float, z: float, top := 400.0, bottom := -120.0, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z))
	q.exclude = exclude + _skip
	return _space().intersect_ray(q)


func _surface(hit: Dictionary) -> StringName:
	var body := hit.get("collider") as Node
	return body.get_meta("surface", &"") if body else &""


func _is_building(hit: Dictionary) -> bool:
	var body := hit.get("collider") as CollisionObject3D
	return body != null and (body.collision_layer & MapTileLoader.LAYER_BUILDINGS) != 0


func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.01), snappedf(v.z, 0.1)]


func _check_tile(key: String) -> void:
	var x0 := _origin.x
	var z1 := _origin.z  # south edge (tile node sits at the south-west corner)
	var size := 500.0
	var buildings: Array[RID] = []
	_skip.clear()
	var props := _holder.get_node_or_null(^"props") as CollisionObject3D
	if props:
		_skip.append(props.get_rid())
	for body: Node in _holder.get_children():
		if (body as CollisionObject3D).collision_layer & MapTileLoader.LAYER_BUILDINGS:
			buildings.append((body as CollisionObject3D).get_rid())
	# Holes.
	var x := x0 + GRID_HOLES * 0.5
	while x < x0 + size:
		var z := z1 - GRID_HOLES * 0.5
		while z > z1 - size:
			if _down(x, z).is_empty():
				_found.holes.append([snappedf(x, 0.1), snappedf(z, 0.1)])
			z -= GRID_HOLES
		x += GRID_HOLES
	# Buildings over roads (not over tunnels, which run underneath).
	if not buildings.is_empty():
		x = x0 + GRID_BUILDINGS * 0.5
		while x < x0 + size:
			var z := z1 - GRID_BUILDINGS * 0.5
			while z > z1 - size:
				var hit := _down(x, z)
				if not hit.is_empty() and _is_building(hit):
					var under := _down(x, z, hit.position.y - 0.05, -120.0, buildings)
					if not under.is_empty() and _surface(under) == &"asphalt" \
							and not str((under.collider as Node).name).begins_with("tunnels") \
							and hit.position.y - under.position.y > 2.0:
						_found.building_on_road.append(_p(under.position))
				z -= GRID_BUILDINGS
			x += GRID_BUILDINGS
	# Props.
	var data := MapTileLoader.read("res://map/tiles/%s.p5t" % key)
	var instances: Dictionary = data.get("instances", {})
	for kind: String in instances:
		var values: PackedFloat32Array = instances[kind]
		for i in values.size() / 5:
			var base := _origin + Vector3(values[i * 5], values[i * 5 + 1], values[i * 5 + 2])
			var hit := _down(base.x, base.z, base.y + 6.0, base.y - 30.0)
			if hit.is_empty():
				continue
			var entry := [kind] + _p(base)
			if _is_building(hit) and hit.position.y > base.y + 0.5:
				_found.prop_in_building.append(entry)
				continue
			if _is_building(hit):
				hit = _down(base.x, base.z, base.y + 6.0, base.y - 30.0, buildings)
				if hit.is_empty():
					continue
			var dy: float = base.y - hit.position.y
			if dy > PROP_SLACK:
				_found.prop_float.append(entry + [snappedf(dy, 0.01)])
			elif dy < -PROP_SLACK:
				_found.prop_sunk.append(entry + [snappedf(dy, 0.01)])
			if kind != "street_light" and _surface(hit) == &"asphalt":
				_found.prop_on_road.append(entry)
	# Ground heights just inside each edge, for the seam check.
	var edges := {n = [], s = [], e = [], w = []}
	var t := EDGE_STEP * 0.5
	while t < size:
		edges.s.append(_ground(x0 + t, z1 - EDGE_INSET, buildings))
		edges.n.append(_ground(x0 + t, z1 - size + EDGE_INSET, buildings))
		edges.w.append(_ground(x0 + EDGE_INSET, z1 - t, buildings))
		edges.e.append(_ground(x0 + size - EDGE_INSET, z1 - t, buildings))
		t += EDGE_STEP
	_edges[key] = edges


## Height of the first non-building surface, or NAN.
func _ground(x: float, z: float, buildings: Array[RID]) -> float:
	var hit := _down(x, z, 400.0, -120.0, buildings)
	return NAN if hit.is_empty() else float(hit.position.y)


func _compare_seams() -> void:
	for key: String in _edges:
		var ij := key.split("_")
		var i := int(ij[0])
		var j := int(ij[1])
		# East neighbour shares our east edge; north neighbour our north edge.
		for pair in [["%d_%d" % [i + 1, j], "e", "w"], ["%d_%d" % [i, j + 1], "n", "s"]]:
			if not _edges.has(pair[0]):
				continue
			var mine: Array = _edges[key][pair[1]]
			var theirs: Array = _edges[pair[0]][pair[2]]
			for k in mini(mine.size(), theirs.size()):
				var a: float = mine[k]
				var b: float = theirs[k]
				var t := EDGE_STEP * 0.5 + k * EDGE_STEP
				var at: Array
				if pair[1] == "e":
					at = [(i + 1) * 500.0, -(j * 500.0 + t)]
				else:
					at = [i * 500.0 + t, -((j + 1) * 500.0)]
				if is_nan(a) != is_nan(b):
					_found.seam_gap.append(at)
				elif not is_nan(a) and absf(a - b) > SEAM_STEP:
					_found.seam_step.append(at + [snappedf(a - b, 0.01)])
