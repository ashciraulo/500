extends SceneTree
## Dumps the ground around every servo on the map (index.json pois of kind
## "servo") for tools/places/place_servos.py, headless, from the tiles'
## colliders:
##
##   godot --headless --path . --script res://tools/places/dump_servo_ground.gd   # writes $OUT, default /tmp/servo_ground.json
##
## For each servo: a grid of rays straight down, STEP apart out to RADIUS,
## each giving the height and what it hit (see CLASSES), and the props
## (trees, lights, bins) and parking spots ("parking") near it.

const RADIUS := 50.0
const STEP := 1.0
## What a ray hit: 0 nothing, 1 road, 2 footpath or kerb, 3 paving,
## 4 other ground (grass, dirt, sand), 5 building, 6 water, 7 anything else
## (a prop's collider, a bridge, a landmark).
const CLASSES := {"none": 0, "road": 1, "footpath": 2, "paving": 3, "ground": 4, "building": 5, "water": 6, "other": 7}

var _index: Dictionary
var _world: Node3D
var _loaded := {}  # tile key -> [collision holder, props]
var _pois: Array = []
var _at := 0
var _phase := 0
var _out := []
var _ray := PhysicsRayQueryParameters3D.new()


func _initialize() -> void:
	_index = JSON.parse_string(FileAccess.get_file_as_string("res://map/tiles/index.json"))
	for poi: Dictionary in _index.get("pois", []):
		if poi.get("kind", "") == "servo":
			_pois.append(poi)
	_world = Node3D.new()
	root.add_child(_world)
	_ray.collision_mask = MapTileLoader.LAYER_WORLD | MapTileLoader.LAYER_BUILDINGS | MapTileLoader.LAYER_WATER
	print("SERVO GROUND %d servos" % _pois.size())


func _process(_delta: float) -> bool:
	if _at >= _pois.size():
		var path := OS.get_environment("OUT") if OS.has_environment("OUT") else "/tmp/servo_ground.json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"radius": RADIUS, "step": STEP, "classes": CLASSES, "servos": _out}))
		print("SERVO GROUND wrote ", path)
		return true
	if _phase == 0:
		_load_around(_pois[_at])
		_phase = 1
		return false
	if _phase < 3:
		_phase += 1  # let the physics server pick the new bodies up
		return false
	_out.append(_sample(_pois[_at]))
	_phase = 0
	_at += 1
	return false


func _load_around(poi: Dictionary) -> void:
	var i := floori(float(poi.at[0]) / 500.0)
	var j := floori(-float(poi.at[2]) / 500.0)
	var want := {}
	for di in [-1, 0, 1]:
		for dj in [-1, 0, 1]:
			var k := "%d_%d" % [i + di, j + dj]
			if _index.tiles.has(k):
				want[k] = true
	for k: String in _loaded.keys():
		if not want.has(k):
			_loaded[k][0].queue_free()
			_loaded.erase(k)
	for k: String in want:
		if _loaded.has(k):
			continue
		var path := "res://map/tiles/%s" % _index.tiles[k].file
		var result := MapTileLoader.build(path, {}, {})
		if result.error != "":
			continue
		var holder := MapTileLoader.make_collision(result)
		holder.position = result.root.position
		var props := []
		var instances: Dictionary = MapTileLoader.read(path).get("instances", {})
		for kind: String in instances:
			var values: PackedFloat32Array = instances[kind]
			for n in values.size() / 5:
				var o := n * 5
				var at := result.root.position + Vector3(values[o], values[o + 1], values[o + 2])
				props.append([kind, at.x, at.y, at.z, values[o + 4]])
		var traffic := MapTileLoader.read(path.get_basename() + ".p5r")
		for spot: Dictionary in traffic.get("parking", []):
			var at: Vector3 = _vec(spot.pos)
			props.append(["parking", at.x, at.y, at.z, 1.0])
		result.root.free()
		_world.add_child(holder)
		_loaded[k] = [holder, props]


func _vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	return Vector3(v[0], v[1], v[2])


func _class_of(body: CollisionObject3D) -> int:
	if body == null:
		return CLASSES.other
	if body.collision_layer & MapTileLoader.LAYER_WATER:
		return CLASSES.water
	if body.collision_layer & MapTileLoader.LAYER_BUILDINGS:
		return CLASSES.building
	var name := String(body.name)
	if name.begins_with("roads_asphalt") or name.begins_with("roads_line"):
		return CLASSES.road
	if name.begins_with("roads_"):
		return CLASSES.footpath
	if name.begins_with("ground_paving") or name.begins_with("ground_concrete"):
		return CLASSES.paving
	if name.begins_with("ground_"):
		return CLASSES.ground
	return CLASSES.other


func _sample(poi: Dictionary) -> Dictionary:
	var cx := float(poi.at[0])
	var cz := float(poi.at[2])
	var n := int(RADIUS * 2.0 / STEP) + 1
	var h := []
	var cls := []
	var space := _world.get_world_3d().direct_space_state
	for row in n:
		var z := cz - RADIUS + row * STEP
		for col in n:
			var x := cx - RADIUS + col * STEP
			_ray.from = Vector3(x, 400.0, z)
			_ray.to = Vector3(x, -60.0, z)
			var hit := space.intersect_ray(_ray)
			if hit.is_empty():
				h.append(0.0)
				cls.append(CLASSES.none)
				continue
			h.append(snappedf((hit.position as Vector3).y, 0.01))
			var c := _class_of(hit.collider as CollisionObject3D)
			if c != CLASSES.water and (hit.normal as Vector3).y < 0.9 and c != CLASSES.building:
				c = CLASSES.other if c != CLASSES.road else c  # a bank or a wall, not somewhere to park
			cls.append(c)
	var props := []
	for k: String in _loaded:
		for p: Array in _loaded[k][1]:
			if absf(p[1] - cx) <= RADIUS + 5.0 and absf(p[3] - cz) <= RADIUS + 5.0:
				props.append([p[0], snappedf(p[1], 0.01), snappedf(p[2], 0.01), snappedf(p[3], 0.01), snappedf(p[4], 0.01)])
	return {"id": poi.id, "name": poi.get("name", ""), "suburb": poi.get("suburb", ""), "at": poi.at,
		"origin": [cx - RADIUS, cz - RADIUS], "n": n, "h": h, "cls": cls, "props": props}
