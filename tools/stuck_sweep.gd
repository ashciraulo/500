extends SceneTree
## Finds places the player can walk or drop into on foot but can't walk back
## out of (a yard lower than the footpath, a hole between buildings, a steep
## bank), headless, from the map tiles' colliders and the townhouse:
##
##   godot --headless --path . --script res://tools/stuck_sweep.gd -- out=/tmp/stuck.json [tiles=0_0,-1_0] [step=0.5]
##   godot --headless --path . --script res://tools/stuck_sweep.gd -- around=-8,-1,150   (x, z, radius in metres)
##
## The whole map takes hours at 0.5 m: split it with part=0/4 .. part=3/4 in
## four processes (each with its own out=), or use step=1.
##
## How: a grid of rays straight down finds every floor you could stand on
## (several per column under bridges and in the house, each with headroom for
## the player). Neighbouring floors are joined when the player could walk
## from one to the other: a step up of at most OnFoot.step_height, any drop
## down, and nothing in the way at knee and chest height. Starting from the
## roads, a trap is any floor you can reach but can't get back from. Each trap
## is listed with where it is, how big, how you got in, and how high a step
## would get you out, nearest to home first. Exits 0; the counts are the
## result.

## Player capsule (OnFoot): what it can step up, how much headroom it needs.
const STEP_UP := 0.32
const HEADROOM := 1.75
const MIN_NORMAL_Y := 0.64  # floor_max_angle 50 degrees
## Up to this many floors in one column (street, bridge deck, house floors).
const MAX_LAYERS := 4
## Traps smaller than this (m²) are cracks the capsule can't get into.
const MIN_AREA := 0.5
const MARGIN := 6.0
const TILE := 500.0

var _out := "user://stuck_sweep.json"
var _step := 0.5
var _tiles: Array[String] = []
var _index: Dictionary
var _world: Node3D
var _home: Node3D
var _loaded := {}  # "i_j" -> collision holder
var _at := 0
var _phase := 0
var _started := 0
var _traps: Array[Dictionary] = []
var _area := Rect2()  # around=: only this square (x, z)
var _ray := PhysicsRayQueryParameters3D.new()
var _home_at := Vector3.ZERO
var _part := [0, 1]  # part=k/n: every n-th tile from the k-th, to split a run across processes


func _initialize() -> void:
	_index = JSON.parse_string(FileAccess.get_file_as_string("res://map/tiles/index.json"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
		elif arg.begins_with("step="):
			_step = float(arg.trim_prefix("step="))
		elif arg.begins_with("tiles="):
			for t in arg.trim_prefix("tiles=").split(","):
				_tiles.append(t)
		elif arg.begins_with("part="):
			var v := arg.trim_prefix("part=").split("/")
			_part = [int(v[0]), int(v[1])]
		elif arg.begins_with("around="):
			var v := arg.trim_prefix("around=").split(",")
			var r := float(v[2])
			_area = Rect2(float(v[0]) - r, float(v[1]) - r, r * 2.0, r * 2.0)
	if _tiles.is_empty():
		for t: String in _index.tiles:
			if _area.size == Vector2.ZERO or _tile_rect(t).intersects(_area):
				_tiles.append(t)
	_tiles.sort_custom(func(a: String, b: String) -> bool:
		var pa := a.split("_")
		var pb := b.split("_")
		return [int(pa[1]), int(pa[0])] < [int(pb[1]), int(pb[0])])
	if _part[1] > 1:
		# Runs of neighbouring tiles, so each process reuses its loaded neighbours.
		var mine: Array[String] = []
		for i in _tiles.size():
			if (i / 8) % _part[1] == _part[0]:
				mine.append(_tiles[i])
		_tiles = mine
	_world = Node3D.new()
	root.add_child(_world)
	var home: Dictionary = _index.get("home", {})
	if home.has("scene"):
		_home = (load(home.scene) as PackedScene).instantiate()
		var p: Array = home.position
		_home_at = Vector3(p[0], p[1], p[2])
		_home.transform = Transform3D(Basis(Vector3.UP, float(home.get("yaw", 0.0))), _home_at)
		_world.add_child(_home)
	_ray.collision_mask = 1 | 2
	_started = Time.get_ticks_msec()
	print("STUCK SWEEP %d tiles, %.2f m grid" % [_tiles.size(), _step])


func _process(_delta: float) -> bool:
	if _at >= _tiles.size():
		_finish()
		return true
	if _phase == 0:
		_load_around(_tiles[_at])
		_phase = 1
		return false
	if _phase < 3:
		_phase += 1  # let the physics server pick the new bodies up
		return false
	_sweep_tile(_tiles[_at])
	_phase = 0
	_at += 1
	if _at % 10 == 0:
		print("STUCK SWEEP %d / %d tiles, %d traps, %.0f s" % [_at, _tiles.size(), _traps.size(),
			(Time.get_ticks_msec() - _started) / 1000.0])
	return false


func _tile_rect(key: String) -> Rect2:
	var p := key.split("_")
	var i := int(p[0])
	var j := int(p[1])
	# x east, z south: tile i_j covers x i*500.., z -(j+1)*500..-j*500.
	return Rect2(i * TILE, -(j + 1) * TILE, TILE, TILE)


## Colliders for the tile and its neighbours (rays near the edge look across).
func _load_around(key: String) -> void:
	var p := key.split("_")
	var want := {}
	for di in [-1, 0, 1]:
		for dj in [-1, 0, 1]:
			var k := "%d_%d" % [int(p[0]) + di, int(p[1]) + dj]
			if _index.tiles.has(k):
				want[k] = true
	for k: String in _loaded.keys():
		if not want.has(k):
			_loaded[k].queue_free()
			_loaded.erase(k)
	for k: String in want:
		if _loaded.has(k):
			continue
		var result := MapTileLoader.build("res://map/tiles/%s" % _index.tiles[k].file, {}, {})
		if result.error != "":
			print("STUCK SWEEP skip ", k, " ", result.error)
			continue
		var holder := MapTileLoader.make_collision(result)
		holder.position = result.root.position
		result.root.free()
		_world.add_child(holder)
		_loaded[k] = holder


func _space() -> PhysicsDirectSpaceState3D:
	return _world.get_world_3d().direct_space_state


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return _space().intersect_ray(_ray)


func _sweep_tile(key: String) -> void:
	var rect := _tile_rect(key).grow(MARGIN)
	if _area.size != Vector2.ZERO:
		rect = rect.intersection(_area)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
	var info: Dictionary = _index.tiles[key]
	var top := float(info.get("hmax", 50.0)) + 260.0
	var bottom := float(info.get("hmin", -10.0)) - 5.0
	var nx := int(rect.size.x / _step)
	var nz := int(rect.size.y / _step)
	var n := nx * nz
	# Floors: height per (cell, layer), NAN where none; surface kind per floor.
	var h := PackedFloat32Array()
	h.resize(n * MAX_LAYERS)
	h.fill(NAN)
	var road := PackedByteArray()
	road.resize(n * MAX_LAYERS)
	var kind := PackedByteArray()
	kind.resize(n * MAX_LAYERS)
	for c in n:
		var x := rect.position.x + (c % nx + 0.5) * _step
		var z := rect.position.y + (c / nx + 0.5) * _step
		var ceiling := INF
		var from := top
		var layer := 0
		while layer < MAX_LAYERS:
			var hit := _cast(Vector3(x, from, z), Vector3(x, bottom, z))
			if hit.is_empty():
				break
			var y: float = (hit.position as Vector3).y
			if (hit.normal as Vector3).y >= MIN_NORMAL_Y and ceiling - y >= HEADROOM:
				h[c * MAX_LAYERS + layer] = y
				var body := hit.collider as Node
				if body and body.get_meta(&"surface", &"") == &"asphalt" and String(body.name).begins_with("road"):
					road[c * MAX_LAYERS + layer] = 1
				kind[c * MAX_LAYERS + layer] = _kind_of(body)
				layer += 1
			ceiling = y
			from = y - 0.05
	# Walks between neighbouring floors.
	var nodes := n * MAX_LAYERS
	var out_edges: Array[PackedInt32Array] = []
	out_edges.resize(nodes)
	var in_edges: Array[PackedInt32Array] = []
	in_edges.resize(nodes)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Wall tests are the same both ways across a cell edge: remember the last
	# one per edge (edges east and south of each cell), [height tested, blocked].
	var memo_y := PackedFloat32Array()
	memo_y.resize(n * 2)
	memo_y.fill(NAN)
	var memo_blocked := PackedByteArray()
	memo_blocked.resize(n * 2)
	for c in n:
		var cx := c % nx
		var cz := c / nx
		for la in MAX_LAYERS:
			var a := h[c * MAX_LAYERS + la]
			if is_nan(a):
				break
			for d: Vector2i in dirs:
				var ox := cx + d.x
				var oz := cz + d.y
				if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
					continue
				var o := oz * nx + ox
				# You land on (or step onto) the highest floor there you can reach.
				var lb := -1
				for k in MAX_LAYERS:
					var b := h[o * MAX_LAYERS + k]
					if is_nan(b):
						break
					if b <= a + STEP_UP:
						lb = k
						break
				if lb < 0:
					continue
				var b := h[o * MAX_LAYERS + lb]
				var top_y := maxf(a, b)
				var edge := (mini(c, o)) * 2 + (0 if d.y == 0 else 1)
				var blocked := false
				if memo_y[edge] == top_y:
					blocked = memo_blocked[edge] == 1
				else:
					var p0 := Vector3(rect.position.x + (cx + 0.5) * _step, 0.0, rect.position.y + (cz + 0.5) * _step)
					var p1 := p0 + Vector3(d.x, 0.0, d.y) * _step
					# Both ways: the map's walls are one-sided meshes, and a ray
					# only sees a face from the front.
					for lift: float in [STEP_UP + 0.1, 1.2]:
						var y := top_y + lift
						if not _cast(Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z)).is_empty() \
								or not _cast(Vector3(p1.x, y, p1.z), Vector3(p0.x, y, p0.z)).is_empty():
							blocked = true
							break
					memo_y[edge] = top_y
					memo_blocked[edge] = 1 if blocked else 0
				if blocked:
					continue
				var ia := c * MAX_LAYERS + la
				var ib := o * MAX_LAYERS + lb
				out_edges[ia].append(ib)
				in_edges[ib].append(ia)
	# From the roads: everywhere you can get to, and everywhere you can get back from.
	var seeds := PackedInt32Array()
	for i in nodes:
		if road[i] == 1:
			seeds.append(i)
	var reach := _flood(seeds, out_edges, nodes)
	var back := _flood(seeds, in_edges, nodes)
	# Traps: reachable, no way back. Group touching trap floors into one spot each.
	var seen := PackedByteArray()
	seen.resize(nodes)
	var tile_rect := _tile_rect(key)
	for i in nodes:
		if reach[i] == 0 or back[i] == 1 or seen[i] == 1:
			continue
		var group := _group(i, reach, back, seen, out_edges, in_edges)
		var area := group.size() * _step * _step
		if area < MIN_AREA:
			continue
		var sum := Vector3.ZERO
		var kinds := {}
		var entry := Vector3.INF
		var climb := INF
		for g: int in group:
			var c := g / MAX_LAYERS
			var p := Vector3(rect.position.x + (c % nx + 0.5) * _step, h[g], rect.position.y + (c / nx + 0.5) * _step)
			sum += p
			var kn := _kind_names[kind[g]]
			kinds[kn] = int(kinds.get(kn, 0)) + 1
			for src: int in in_edges[g]:
				if back[src] == 1 and reach[src] == 1 and entry == Vector3.INF:
					var sc := src / MAX_LAYERS
					entry = Vector3(rect.position.x + (sc % nx + 0.5) * _step, h[src], rect.position.y + (sc / nx + 0.5) * _step)
			# The smallest step up to a floor that does lead back.
			var cx := c % nx
			var cz := c / nx
			for d: Vector2i in dirs:
				var ox := cx + d.x
				var oz := cz + d.y
				if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
					continue
				for k in MAX_LAYERS:
					var j := (oz * nx + ox) * MAX_LAYERS + k
					if is_nan(h[j]):
						break
					if back[j] == 1 and h[j] > h[g]:
						climb = minf(climb, h[j] - h[g])
		var centre := sum / group.size()
		# Only traps centred in this tile (the margin overlaps the neighbours').
		if not tile_rect.has_point(Vector2(centre.x, centre.z)):
			continue
		if _area.size != Vector2.ZERO and not _area.has_point(Vector2(centre.x, centre.z)):
			continue
		var main_kind := ""
		for k: String in kinds:
			if main_kind == "" or kinds[k] > kinds[main_kind]:
				main_kind = k
		_traps.append({tile = key, at = _v(centre), area = snappedf(area, 0.25), entry = _v(entry), floor = main_kind,
			climb = snappedf(climb, 0.01) if climb != INF else -1.0,
			home_m = snappedf(Vector2(centre.x - _home_at.x, centre.z - _home_at.z).length(), 1.0)})


## What each floor is: the collider's name ("ground_grass", "roads_asphalt",
## "props", or "home" for the townhouse), numbered as first seen.
var _kind_names: Array[String] = []
var _kind_ids := {}


func _kind_of(body: Node) -> int:
	var n := "none"
	if body:
		n = "home" if _home and _home.is_ancestor_of(body) else String(body.name)
	if not _kind_ids.has(n):
		_kind_ids[n] = _kind_names.size()
		_kind_names.append(n)
	return mini(int(_kind_ids[n]), 255)


func _flood(seeds: PackedInt32Array, edges: Array[PackedInt32Array], nodes: int) -> PackedByteArray:
	var mark := PackedByteArray()
	mark.resize(nodes)
	var stack := seeds.duplicate()
	for s in seeds:
		mark[s] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		for j in edges[i]:
			if mark[j] == 0:
				mark[j] = 1
				stack.append(j)
	return mark


## Trap floors joined to `start` by walking either way.
func _group(start: int, reach: PackedByteArray, back: PackedByteArray, seen: PackedByteArray,
		out_edges: Array[PackedInt32Array], in_edges: Array[PackedInt32Array]) -> PackedInt32Array:
	var group := PackedInt32Array()
	var stack := PackedInt32Array([start])
	seen[start] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		group.append(i)
		for list: PackedInt32Array in [out_edges[i], in_edges[i]]:
			for j in list:
				if seen[j] == 0 and reach[j] == 1 and back[j] == 0:
					seen[j] = 1
					stack.append(j)
	return group


func _v(p: Vector3) -> Array:
	if p == Vector3.INF:
		return []
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.01), snappedf(p.z, 0.1)]


func _finish() -> void:
	_traps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.home_m < b.home_m)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify({step = _step, tiles = _tiles.size(), traps = _traps}, "  "))
	f.close()
	var big := _traps.filter(func(t: Dictionary) -> bool: return t.area >= 4.0)
	print("STUCK SWEEP %d traps (%d of 4 m² or more) in %d tiles, %.0f s, written to %s" % [_traps.size(), big.size(),
		_tiles.size(), (Time.get_ticks_msec() - _started) / 1000.0, _out])
	for t: Dictionary in _traps.slice(0, 15):
		print("  %s  %5.1f m²  %-16s climb %.2f m  %4d m from home  in from %s" % [t.at, t.area, t.floor, t.climb, t.home_m, t.entry])
	quit(0)
