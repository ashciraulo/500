extends SceneTree
## Finds places the player can walk or drop into on foot but can't walk back
## out of (a yard lower than the footpath, a hole between buildings, a steep
## bank), headless, from the map tiles' colliders and the townhouse:
##
##   godot --headless --path . --script res://tools/stuck_sweep.gd -- out=/tmp/stuck.json [tiles=0_0,-1_0] [step=0.5]
##   godot --headless --path . --script res://tools/stuck_sweep.gd -- around=-8,-1,150   (x, z, radius in metres)
##   ... -- part=0/4 out=/tmp/p0.json resume   (carry on a stopped run from its out= file)
##
## The whole map takes hours at 0.5 m: split it with part=0/4 .. part=3/4 in
## four processes (each with its own out=), or use step=1.
##
## How: a grid of rays straight down finds every floor you could stand on
## (several per column under bridges and in the house, each with headroom for
## the player; not riverbed under water deeper than you wade). Neighbouring floors are joined when the player could walk
## from one to the other: a step up of at most OnFoot.step_height, any drop
## down, and nothing in the way at knee and chest height. Starting from the
## roads, a trap is any floor you can reach but can't get back from. Each trap
## is listed with where it is, how big, how you got in, and how high a step
## would get you out, nearest to home first.
##
## It also lists uneven ground ("rough"), from the same floors:
##   crest, dip   on roads and bridge decks, a change of grade over a car's
##                length sharp enough to throw it: `value` is the speed (km/h)
##                at which a car leaves the ground over it (a crest) or slams
##                into it (a dip). Listed under ROUGH_SPEED.
##   lump, hole   anywhere you walk or drive, more than LUMP (on roads) or
##                LUMP_GROUND above or below what's 2 m either side of it,
##                both ways: `value` in metres
##   step         a sudden step of more than STEP (and not a kerb) between
##                floors that are flat either side, beyond what the slope
##                either side climbs: `value` in metres
##   steep road   asphalt climbing more than STEEP_ROAD degrees over 4 m: `value`
## Each is one spot per patch of touching cells, at its worst cell, with what's
## near it (jetty, bridge, tunnel, map edge), since a fix nearby can be the cause.
## Exits 0; the counts are the result.

## Player capsule (OnFoot): what it can step up, how much headroom it needs,
## and how deep it wades.
const STEP_UP := 0.4
const WADE_DEPTH := 0.6
const WET_STEP := 0.65  # out of the water, up the bank
const HEADROOM := 1.75
const MIN_NORMAL_Y := 0.64  # floor_max_angle 50 degrees
## Uneven ground (see the top): car speeds (km/h), metres, degrees.
const ROUGH_SPEED := 50.0
const LUMP := 0.15
const LUMP_GROUND := 0.25  # off the road (where two slopes meet in a crease is about 0.2)
const STEP := 0.12
const STEEP_ROAD := 12.0
## Up to this many floors in one column (street, bridge deck, house floors).
const MAX_LAYERS := 4
## Traps smaller than this (m²) are cracks the capsule can't get into.
const MIN_AREA := 0.5
## Each tile is swept with this much of its neighbours around it. Floors on
## the edge of that window count as joined to the rest of the map both ways
## (a long tunnel or cutting leads out somewhere past it), so only traps that
## close up inside the window are reported.
const MARGIN := 40.0
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
var _rough: Array[Dictionary] = []
## The map's extent (x, z), for "near the map edge".
var _map_rect := Rect2()
var _area := Rect2()  # around=: only this square (x, z)
var _ray := PhysicsRayQueryParameters3D.new()
var _water_ray := PhysicsRayQueryParameters3D.new()
var _home_at := Vector3.ZERO
var _done_before: Array = []  # tiles a stopped run already did (resume)
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
	for t: String in _index.tiles:
		_map_rect = _tile_rect(t) if _map_rect.size == Vector2.ZERO else _map_rect.merge(_tile_rect(t))
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
	if OS.get_cmdline_user_args().has("resume") and FileAccess.file_exists(_out):
		# Carry on from a stopped run: keep what it found, skip the tiles it did.
		var was: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_out))
		var done: Array = was.get("done", [])
		for t: Dictionary in was.traps:
			_traps.append(t)
		for r: Dictionary in was.rough:
			_rough.append(r)
		var left: Array[String] = []
		for t in _tiles:
			if not done.has(t):
				left.append(t)
		_tiles = left
		_done_before = done
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
	_water_ray.collision_mask = MapTileLoader.LAYER_WATER
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
		_save()
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
	var wet := PackedByteArray()  # floors under shallow water
	wet.resize(n * MAX_LAYERS)
	var ny := PackedFloat32Array()  # how flat each floor is (its normal's y)
	ny.resize(n * MAX_LAYERS)
	var grade := PackedVector2Array()  # its rise per metre east and south
	grade.resize(n * MAX_LAYERS)
	var room := PackedFloat32Array()  # the first thing above each floor
	room.resize(n * MAX_LAYERS)
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
			var body := hit.collider as Node
			var depth := _depth(body, x, y, z)
			if (hit.normal as Vector3).y >= MIN_NORMAL_Y and ceiling - y >= HEADROOM and depth <= WADE_DEPTH:
				h[c * MAX_LAYERS + layer] = y
				wet[c * MAX_LAYERS + layer] = 1 if depth > 0.05 else 0
				room[c * MAX_LAYERS + layer] = ceiling
				var normal := hit.normal as Vector3
				ny[c * MAX_LAYERS + layer] = normal.y
				grade[c * MAX_LAYERS + layer] = Vector2(-normal.x, -normal.z) / normal.y
				if body and body.get_meta(&"surface", &"") == &"asphalt" and String(body.name).begins_with("road"):
					road[c * MAX_LAYERS + layer] = 1
				kind[c * MAX_LAYERS + layer] = _kind_of(body)
				layer += 1
			ceiling = y
			from = y - 0.05
	_find_rough(key, rect, nx, nz, h, kind, ny, grade)
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
			var step_up := WET_STEP if wet[c * MAX_LAYERS + la] == 1 else STEP_UP
			for d: Vector2i in dirs:
				var ox := cx + d.x
				var oz := cz + d.y
				if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
					continue
				var o := oz * nx + ox
				# You land on (or step onto) the highest floor there you can reach:
				# a step up, or up a slope you can walk (the grid makes a 30 degree
				# bank look like a 0.6 m step, so allow for how steep both are).
				var lb := -1
				for k in MAX_LAYERS:
					var b := h[o * MAX_LAYERS + k]
					if is_nan(b):
						break
					var tilt := clampf((ny[c * MAX_LAYERS + la] + ny[o * MAX_LAYERS + k]) * 0.5, MIN_NORMAL_Y, 1.0)
					if b <= a + step_up + _step * tan(acos(tilt)):
						lb = k
						break
				if lb < 0:
					continue
				var b := h[o * MAX_LAYERS + lb]
				# Dropping to a floor under something (a tunnel floor under its lid
				# and the bank beside it) needs room to walk in at this height.
				if room[o * MAX_LAYERS + lb] < a + HEADROOM:
					continue
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
	# From the roads and the window's edge (not its roofs): everywhere you can
	# get to, and everywhere you can get back from.
	var seeds := PackedInt32Array()
	for i in nodes:
		var c := i / MAX_LAYERS
		var edge_cell := c % nx == 0 or c / nx == 0 or c % nx == nx - 1 or c / nx == nz - 1
		if road[i] == 1 or (edge_cell and not is_nan(h[i]) and _walk_kind[kind[i]] == 1):
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
		var into := Vector3.INF  # the trap floor you get in at
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
					into = p
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
		_traps.append({tile = key, at = _v(centre), area = snappedf(area, 0.25), entry = _v(entry), into = _v(into), floor = main_kind,
			climb = snappedf(climb, 0.01) if climb != INF else -1.0,
			home_m = snappedf(Vector2(centre.x - _home_at.x, centre.z - _home_at.z).length(), 1.0)})


# ---------------------------------------------------------------------------
# Uneven ground
# ---------------------------------------------------------------------------

## Per kind: 0 not ground you'd walk or drive on (nor the townhouse), 1 ground and paths, 2 roads
## and bridge decks (cars), 3 kerbed footpaths (a kerb's step is meant to be there).
var _rough_kind := PackedByteArray()
## Per kind: what it says about a spot nearby ("jetty", "bridge", "tunnel"), or "".
var _near_tag: Array[String] = []


## The floor in cell `o` that carries on from one at height `a` (the closest
## within a metre), as an index into h, or -1.
func _same_floor(h: PackedFloat32Array, o: int, a: float) -> int:
	var best := -1
	var gap := 1.0
	for k in MAX_LAYERS:
		var b := h[o * MAX_LAYERS + k]
		if is_nan(b):
			break
		if absf(b - a) < gap:
			gap = absf(b - a)
			best = o * MAX_LAYERS + k
	return best


func _find_rough(key: String, rect: Rect2, nx: int, nz: int, h: PackedFloat32Array, kind: PackedByteArray,
		ny: PackedFloat32Array, grade: PackedVector2Array) -> void:
	var n := nx * nz
	# Per floor, what's wrong (1 crest, 2 dip, 3 lump, 4 hole, 5 step, 6 steep road) and how much.
	var what := PackedByteArray()
	what.resize(n * MAX_LAYERS)
	var worst := PackedFloat32Array()
	worst.resize(n * MAX_LAYERS)
	var s := maxi(1, roundi(2.0 / _step))  # cells to 2 m: about a car's wheelbase
	var span := s * _step
	var lift := 9.8 / pow(ROUGH_SPEED / 3.6, 2.0)  # curvature (1/m) that lifts a car at ROUGH_SPEED
	var steep := tan(deg_to_rad(STEEP_ROAD))
	for c in n:
		var cx := c % nx
		var cz := c / nx
		for la in MAX_LAYERS:
			var i := c * MAX_LAYERS + la
			var a := h[i]
			if is_nan(a):
				break
			var rk := _rough_kind[kind[i]]
			if rk == 0:
				continue
			# Grade changes over a car's length, along both axes and both diagonals.
			# Lumps: above (or below) the ground 2 m away on both axes, so the
			# top or foot of a slope isn't one.
			var bump: Array[float] = []
			var best_k := 0.0
			var slope := 0.0  # steepest grade across 4 m (one tilted sliver of mesh isn't a steep road)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
				var ax := cx + d.x * s
				var az := cz + d.y * s
				var bx := cx - d.x * s
				var bz := cz - d.y * s
				if mini(ax, bx) < 0 or mini(az, bz) < 0 or maxi(ax, bx) >= nx or maxi(az, bz) >= nz:
					continue
				var ia := _same_floor(h, az * nx + ax, a)
				var ib := _same_floor(h, bz * nx + bx, a)
				if ia < 0 or ib < 0:
					continue
				# Lumps against the same surface all round (a verge between two
				# footpaths isn't a hole).
				if (d.x == 0 or d.y == 0) and kind[ia] == kind[i] and kind[ib] == kind[i]:
					bump.append(a - (h[ia] + h[ib]) * 0.5)
				if rk == 2 and _rough_kind[kind[ia]] == 2 and _rough_kind[kind[ib]] == 2:
					var dist := span * (1.4142 if d.x != 0 and d.y != 0 else 1.0)
					var k := (h[ia] + h[ib] - 2.0 * a) / (dist * dist)  # < 0: a crest
					if absf(k) > absf(best_k):
						best_k = k
					slope = maxf(slope, absf(h[ia] - h[ib]) / (2.0 * dist))
			if absf(best_k) > lift:
				_mark(what, worst, i, 1 if best_k < 0.0 else 2, sqrt(9.8 / absf(best_k)) * 3.6)
			if bump.size() == 2 and signf(bump[0]) == signf(bump[1]):
				var r := minf(absf(bump[0]), absf(bump[1]))
				if r > (LUMP if rk == 2 else LUMP_GROUND):
					_mark(what, worst, i, 3 if bump[0] > 0.0 else 4, r)
			# A sudden step to the next cell east or south (each edge once), flat
			# both sides: the jump less what the slope either side climbs.
			if ny[i] > 0.97:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var ox := cx + d.x
					var oz := cz + d.y
					if ox >= nx or oz >= nz:
						continue
					var j := _same_floor(h, oz * nx + ox, a)
					if j < 0 or ny[j] <= 0.97 or _rough_kind[kind[j]] == 0:
						continue
					var rise := (grade[i] + grade[j]).dot(Vector2(d)) * 0.5 * _step
					var raw := absf(h[j] - a)
					var jump := absf(h[j] - a - rise)
					var kerb := (rk == 3 or _rough_kind[kind[j]] == 3) and raw < 0.3
					if minf(raw, jump) > STEP and raw <= STEP_UP and not kerb:
						_mark(what, worst, i if h[i] < h[j] else j, 5, jump)
			if slope > steep:
				_mark(what, worst, i, 6, rad_to_deg(atan(slope)))
	# One spot per patch of touching floors with the same finding, at its worst.
	var seen := PackedByteArray()
	seen.resize(n * MAX_LAYERS)
	var tile_rect := _tile_rect(key)
	var names := ["", "crest", "dip", "lump", "hole", "step", "steep road"]
	for i in n * MAX_LAYERS:
		if what[i] == 0 or seen[i] == 1:
			continue
		var wk := what[i]
		var stack := PackedInt32Array([i])
		seen[i] = 1
		var cells := 0
		var top := i
		while not stack.is_empty():
			var g := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cells += 1
			# For speeds the lowest is worst; for the rest, the biggest.
			if (worst[g] < worst[top]) if wk <= 2 else (worst[g] > worst[top]):
				top = g
			var gc := g / MAX_LAYERS
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var ox: int = gc % nx + dx
					var oz: int = gc / nx + dz
					if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
						continue
					var j := _same_floor(h, oz * nx + ox, h[g])
					if j >= 0 and seen[j] == 0 and what[j] == wk:
						seen[j] = 1
						stack.append(j)
		var tc := top / MAX_LAYERS
		var at := Vector3(rect.position.x + (tc % nx + 0.5) * _step, h[top], rect.position.y + (tc / nx + 0.5) * _step)
		if not tile_rect.has_point(Vector2(at.x, at.z)):
			continue
		if _area.size != Vector2.ZERO and not _area.has_point(Vector2(at.x, at.z)):
			continue
		_rough.append({tile = key, kind = names[wk], at = _v(at), value = snappedf(worst[top], 0.01),
			area = snappedf(cells * _step * _step, 0.25), floor = _kind_names[kind[top]],
			near = _near(at, nx, nz, h, kind, top),
			home_m = snappedf(Vector2(at.x - _home_at.x, at.z - _home_at.z).length(), 1.0)})


## A floor keeps its first finding.
func _mark(what: PackedByteArray, worst: PackedFloat32Array, i: int, finding: int, value: float) -> void:
	if what[i] == 0:
		what[i] = finding
		worst[i] = value


## What's within 20 m of a spot that a fix there could have touched.
func _near(at: Vector3, nx: int, nz: int, h: PackedFloat32Array, kind: PackedByteArray, top: int) -> String:
	var tags := {}
	var r := int(20.0 / _step)
	var stride := maxi(1, r / 8)
	var tc := top / MAX_LAYERS
	for dz in range(-r, r + 1, stride):
		for dx in range(-r, r + 1, stride):
			var ox: int = tc % nx + dx
			var oz: int = tc / nx + dz
			if ox < 0 or oz < 0 or ox >= nx or oz >= nz:
				continue
			for k in MAX_LAYERS:
				var j := (oz * nx + ox) * MAX_LAYERS + k
				if is_nan(h[j]):
					break
				var tag := _near_tag[kind[j]]
				if tag != "":
					tags[tag] = true
	if at.x - _map_rect.position.x < 40.0 or _map_rect.end.x - at.x < 40.0 \
			or at.z - _map_rect.position.y < 40.0 or _map_rect.end.y - at.z < 40.0:
		tags["map edge"] = true
	return ", ".join(tags.keys())


## How deep the water is over a floor. Only the big water's riverbed is
## under any depth (ponds and streams are drawn just over the ground).
func _depth(body: Node, x: float, y: float, z: float) -> float:
	if body == null or not String(body.name).ends_with("riverbed"):
		return 0.0
	_water_ray.from = Vector3(x, y + 30.0, z)
	_water_ray.to = Vector3(x, y, z)
	var hit := _space().intersect_ray(_water_ray)
	return (hit.position as Vector3).y - y if not hit.is_empty() else 0.0


## What each floor is: the collider's name ("ground_grass", "roads_asphalt",
## "props", or "home" for the townhouse), numbered as first seen.
var _kind_names: Array[String] = []
var _kind_ids := {}
## Per kind: 1 for ground you'd walk on, 0 for roofs, props and the house.
var _walk_kind := PackedByteArray()


func _kind_of(body: Node) -> int:
	var n := "none"
	if body:
		n = "home" if _home and _home.is_ancestor_of(body) else String(body.name)
	if not _kind_ids.has(n):
		_kind_ids[n] = _kind_names.size()
		_kind_names.append(n)
		_walk_kind.append(0 if n.begins_with("buildings") or n.begins_with("props") or n.begins_with("landmarks")
			or n == "home" or n == "none" else 1)
		var rough := 0
		if n.ends_with("_asphalt") and (n.begins_with("roads") or n.begins_with("bridges") or n.begins_with("tunnels")):
			rough = 2
		elif n == "roads_sidewalk" or n == "roads_kerb":
			rough = 3
		elif n.begins_with("ground") or n.begins_with("roads") or n.begins_with("bridges") or n.begins_with("tunnels") \
				or n == "props_path" or n == "props_concrete":
			rough = 1  # not the townhouse: its stairs and furniture are meant to be there
		_rough_kind.append(rough)
		_near_tag.append("jetty" if n == "props_path" or n == "props_concrete" else "bridge" if n.begins_with("bridges")
			else "tunnel" if n.begins_with("tunnels") else "")
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


## Everything so far, with the tiles done, so a stopped run can carry on (resume).
func _save() -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify({step = _step, tiles = _done_before.size() + _tiles.size(),
		done = _done_before + _tiles.slice(0, _at),
		traps = _traps, rough = _rough}, "  "))
	f.close()


func _finish() -> void:
	_traps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.home_m < b.home_m)
	_rough.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.home_m < b.home_m)
	_save()
	var big := _traps.filter(func(t: Dictionary) -> bool: return t.area >= 4.0)
	print("STUCK SWEEP %d traps (%d of 4 m² or more) in %d tiles, %.0f s, written to %s" % [_traps.size(), big.size(),
		_tiles.size(), (Time.get_ticks_msec() - _started) / 1000.0, _out])
	for t: Dictionary in _traps.slice(0, 15):
		print("  %s  %5.1f m²  %-16s climb %.2f m  %4d m from home  in from %s" % [t.at, t.area, t.floor, t.climb, t.home_m, t.entry])
	var counts := {}
	for r: Dictionary in _rough:
		counts[r.kind] = int(counts.get(r.kind, 0)) + 1
	print("STUCK SWEEP uneven ground: %s" % [counts])
	for r: Dictionary in _rough.slice(0, 15):
		print("  %s  %-10s %6.2f  %-16s %4d m from home  near %s" % [r.at, r.kind, r.value, r.floor, r.home_m, r.near])
	quit(0)
