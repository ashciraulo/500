class_name MapData
extends RefCounted
## What the minimap and the full map draw, read at run time from the map's
## own generated data in map/tiles, so a rebuilt map shows up on them with no
## extra step:
## - the ground (sea, river, lakes, parks, sand) from the overview's painted
##   texture (overview.p5o),
## - every drivable road from the tiles' traffic data (.p5r), as four road
##   meshes (service lanes, streets, main roads, freeways),
## - street names for "where am I", and suburb names from index.json.
##
## `MapData.shared()` starts loading on a worker thread the first time it's
## asked for; `loaded` fires (on the main thread) when it's ready.

signal loaded

## Road classes, drawn in this order (smallest first).
enum Road { SERVICE, STREET, MAIN, FREEWAY }
const ROAD_CLASS := {
	"service": Road.SERVICE, "track": Road.SERVICE, "living_street": Road.STREET,
	"residential": Road.STREET, "unclassified": Road.STREET, "road": Road.STREET,
	"tertiary": Road.STREET, "tertiary_link": Road.STREET,
	"secondary": Road.MAIN, "secondary_link": Road.MAIN,
	"primary": Road.MAIN, "primary_link": Road.MAIN,
	"trunk": Road.FREEWAY, "trunk_link": Road.FREEWAY,
	"motorway": Road.FREEWAY, "motorway_link": Road.FREEWAY,
}
## Widths (m) for roads the data gives none.
const DEFAULT_WIDTH := [4.0, 7.0, 11.0, 14.0]

## Grid cell (m) for the street-name lookup.
const CELL := 64.0
## How far (m) a road can be and still count as the one you're on.
const STREET_REACH := 32.0

## Places the suburb list lacks (OSM tags them city, not suburb): x, z.
const EXTRA_PLACES := {"Perth": Vector2(622.0, 835.0), "Fremantle": Vector2(-10394.0, 12305.0)}
## Named spots in the suburb list that aren't suburbs.
const NOT_SUBURBS := ["Dutchies", "Peasholm Street Dog Beach", "Prawn Bay", "Perth Cultural Centre", "Stocks Corner"]

static var _shared: MapData

var tiles_dir := "res://map/tiles"
var is_loaded := false
## The overview's painted ground, and the world rect it covers (x, z, w, d).
var ground: Texture2D
var ground_rect := Rect2()
## One mesh per Road class (vertex = centreline, uv = offset * width).
var road_meshes: Array[ArrayMesh] = []
## Everything built: the tiles' extent in world x/z.
var bounds := Rect2()
## index.json, for home, pois, job sites.
var index: Dictionary = {}
## [name, Vector2(x, z)]
var suburbs: Array = []
## Street names to print along the roads: [name, Vector2 middle (x, z),
## angle (radians, kept upright), length (m), Road class], one per OSM way.
var labels: Array = []
var road_count := 0

var _task := -1
var _arrays: Array = []  # per class: [verts, uvs, indices], filled on the worker
var _ground_image: Image
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_name := PackedInt32Array()
var _names := PackedStringArray()
var _grid := {}  # Vector2i -> PackedInt32Array of segment ids


static func shared() -> MapData:
	if _shared == null:
		_shared = MapData.new()
		_shared.start()
	return _shared


func start() -> void:
	if _task != -1 or is_loaded:
		return
	_task = WorkerThreadPool.add_task(_load, false, "Map data")


## Waits for the worker (tests and screenshot tools).
func wait() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish()


func _load() -> void:
	var path := tiles_dir.path_join("index.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if parsed is Dictionary:
		index = parsed
	_read_places()
	_read_ground()
	_read_roads()
	_finish.call_deferred()


func _finish() -> void:
	if is_loaded:
		return
	if _ground_image:
		ground = ImageTexture.create_from_image(_ground_image)
		_ground_image = null
	road_meshes.clear()
	for a: Array in _arrays:
		var mesh := ArrayMesh.new()
		if (a[0] as PackedVector2Array).size() > 0:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = a[0]
			arrays[Mesh.ARRAY_TEX_UV] = a[1]
			arrays[Mesh.ARRAY_INDEX] = a[2]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		road_meshes.append(mesh)
	_arrays.clear()
	is_loaded = true
	_task = -1
	loaded.emit()


# --- places ----------------------------------------------------------------

func _read_places() -> void:
	var marks: Dictionary = index.get("landmarks", {})
	for name: String in marks:
		if name in NOT_SUBURBS:
			continue
		var p: Array = marks[name]
		suburbs.append([name, Vector2(p[0], p[1])])
	for name: String in EXTRA_PLACES:
		if not marks.has(name):
			suburbs.append([name, EXTRA_PLACES[name]])


## The suburb a world position is in (the nearest suburb's name), or "".
func suburb_at(p: Vector3) -> String:
	var at := Vector2(p.x, p.z)
	var best := ""
	var best_d := INF
	for s: Array in suburbs:
		var d := at.distance_squared_to(s[1])
		if d < best_d:
			best_d = d
			best = s[0]
	return best


## The name of the street at a world position, or "" off the named roads.
func street_at(p: Vector3, reach := STREET_REACH) -> String:
	if not is_loaded:
		return ""
	var at := Vector2(p.x, p.z)
	var c := Vector2i(floori(at.x / CELL), floori(at.y / CELL))
	var best := -1
	var best_d := reach * reach
	var span := ceili(reach / CELL)
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			var cell: Variant = _grid.get(c + Vector2i(dx, dy))
			if cell == null:
				continue
			for s: int in cell:
				var q := Geometry2D.get_closest_point_to_segment(at, _seg_a[s], _seg_b[s])
				var d := at.distance_squared_to(q)
				if d < best_d:
					best_d = d
					best = s
	if best >= 0:
		return _names[_seg_name[best]]
	# Lanes and car parks aren't in the road data; the map's named job sites
	# (Little Shenton Lane, by the house) cover the ones that matter.
	for site: Dictionary in index.get("job_sites", []):
		var sp: Array = site.get("position", [])
		if sp.size() >= 3 and at.distance_to(Vector2(sp[0], sp[2])) < reach * 1.5:
			return String(site.get("name", ""))
	return ""


# --- ground ----------------------------------------------------------------

func _read_ground() -> void:
	var data := MapTileLoader.read(tiles_dir.path_join("overview.p5o"))
	if data.is_empty() or not data.has("texture_png"):
		return
	var image := Image.new()
	if image.load_png_from_buffer(data.texture_png as PackedByteArray) != OK:
		return
	_ground_image = image
	var r: Array = data.texture_rect
	ground_rect = Rect2(r[0], r[1], r[2], r[3])


# --- roads -----------------------------------------------------------------

func _read_roads() -> void:
	_arrays.clear()
	for i in 4:
		_arrays.append([PackedVector2Array(), PackedVector2Array(), PackedInt32Array()])
	var seen := {}
	var name_ids := {}
	var ways := {}  # OSM way id -> [name, class, {part: pts}]
	var first := true
	for key: String in index.get("tiles", {}):
		var entry: Dictionary = index.tiles[key]
		var t := Vector2(float(entry.get("i", 0)), float(entry.get("j", 0))) * float(index.get("tile_size", 500.0))
		var tile_box := Rect2(t.x, -t.y - 500.0, 500.0, 500.0)
		bounds = tile_box if first else bounds.merge(tile_box)
		first = false
		if not entry.has("traffic"):
			continue
		var data := MapTileLoader.read(tiles_dir.path_join(entry.traffic))
		for road: Dictionary in data.get("roads", []):
			var id := String(road.get("id", ""))
			if id != "":
				if seen.has(id):
					continue
				seen[id] = true
			var kind := String(road.get("kind", "residential"))
			var cls: int = ROAD_CLASS.get(kind, Road.STREET)
			var pts := _xz(road.pts)
			if pts.size() < 2:
				continue
			var width := float(road.get("width", DEFAULT_WIDTH[cls]))
			_add_strip(_arrays[cls], pts, width)
			road_count += 1
			var name := String(road.get("name", ""))
			if name != "":
				if not name_ids.has(name):
					name_ids[name] = _names.size()
					_names.append(name)
				_add_segments(pts, name_ids[name])
				var parts := id.trim_prefix("w").split("/")
				if parts.size() == 2:
					var way: Array = ways.get(parts[0], [name, cls, {}])
					way[2][int(parts[1])] = pts
					ways[parts[0]] = way
	for way: Array in ways.values():
		_add_label(way[0], way[1], way[2])


## A label at the middle of a whole OSM way (its pieces, in order).
func _add_label(name: String, cls: int, parts: Dictionary) -> void:
	var line := PackedVector2Array()
	var keys := parts.keys()
	keys.sort()
	for k: int in keys:
		var pts: PackedVector2Array = parts[k]
		if not line.is_empty() and line[line.size() - 1].distance_to(pts[0]) > 1.0:
			break  # not joined up (a reversed one-way piece): label what we have
		line.append_array(pts if line.is_empty() else pts.slice(1))
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	if total < 40.0:
		return
	# The middle, and the way the road runs there (over about 30 m).
	var half := total * 0.5
	var run := 0.0
	for i in line.size() - 1:
		var seg := line[i].distance_to(line[i + 1])
		if run + seg >= half:
			var mid := line[i].lerp(line[i + 1], (half - run) / maxf(seg, 0.001))
			var a := _along(line, half - 15.0)
			var b := _along(line, half + 15.0)
			var angle := (b - a).angle()
			if angle > PI * 0.5:
				angle -= PI
			elif angle < -PI * 0.5:
				angle += PI
			labels.append([name, mid, angle, total, cls])
			return
		run += seg


static func _along(line: PackedVector2Array, at: float) -> Vector2:
	var run := 0.0
	for i in line.size() - 1:
		var seg := line[i].distance_to(line[i + 1])
		if run + seg >= at:
			return line[i].lerp(line[i + 1], (at - run) / maxf(seg, 0.001))
		run += seg
	return line[line.size() - 1]


static func _xz(pts: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts is PackedVector3Array:
		for p: Vector3 in pts:
			out.append(Vector2(p.x, p.z))
	elif pts is PackedFloat32Array:
		var f: PackedFloat32Array = pts
		for i in range(0, f.size() - 2, 3):
			out.append(Vector2(f[i], f[i + 2]))
	elif pts is Array:
		for p: Variant in pts:
			if p is Vector3:
				out.append(Vector2(p.x, p.z))
			elif p is Array or p is PackedFloat32Array:
				out.append(Vector2(float(p[0]), float(p[2])))
	# Drop repeated points: they have no direction.
	var clean := PackedVector2Array()
	for p in out:
		if clean.is_empty() or clean[clean.size() - 1].distance_squared_to(p) > 0.01:
			clean.append(p)
	return clean


## A road as a triangle strip: two vertices per point on the centreline, with
## uv the way out to each edge times the road's width (mitred at bends, pushed
## out half a width at the ends so roads meet cleanly). The road shader
## widens or narrows that to suit the zoom.
static func _add_strip(a: Array, pts: PackedVector2Array, width: float) -> void:
	var verts: PackedVector2Array = a[0]
	var uvs: PackedVector2Array = a[1]
	var idx: PackedInt32Array = a[2]
	var base := verts.size()
	var n := pts.size()
	for i in n:
		var d_in := (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var d_out := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else Vector2.ZERO
		var tangent := (d_in + d_out).normalized()
		if tangent == Vector2.ZERO:
			tangent = d_out if d_out != Vector2.ZERO else d_in
		var normal := Vector2(-tangent.y, tangent.x)
		var miter := 1.0
		if i > 0 and i < n - 1:
			miter = 1.0 / maxf(normal.dot(Vector2(-d_in.y, d_in.x)), 0.5)
		var cap := Vector2.ZERO
		if i == 0:
			cap = -tangent
		elif i == n - 1:
			cap = tangent
		verts.append(pts[i])
		verts.append(pts[i])
		uvs.append((normal * miter + cap) * width)
		uvs.append((-normal * miter + cap) * width)
		if i > 0:
			var k := base + (i - 1) * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	a[0] = verts
	a[1] = uvs
	a[2] = idx


func _add_segments(pts: PackedVector2Array, name_id: int) -> void:
	for i in pts.size() - 1:
		var s := _seg_a.size()
		_seg_a.append(pts[i])
		_seg_b.append(pts[i + 1])
		_seg_name.append(name_id)
		var lo := Vector2i(floori(minf(pts[i].x, pts[i + 1].x) / CELL), floori(minf(pts[i].y, pts[i + 1].y) / CELL))
		var hi := Vector2i(floori(maxf(pts[i].x, pts[i + 1].x) / CELL), floori(maxf(pts[i].y, pts[i + 1].y) / CELL))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cy)
				var cell: PackedInt32Array = _grid.get(key, PackedInt32Array())
				cell.append(s)
				_grid[key] = cell
