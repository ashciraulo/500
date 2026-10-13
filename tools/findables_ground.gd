extends SceneTree
## A map in text of the ground round every mystery clue, found part and
## cutting, from the tiles' colliders (the classes dump_servo_ground.gd uses),
## so you can check each sits on a footpath or verge and not in the road:
##
##   godot --headless --path . --script res://tools/findables_ground.gd -- --no-save [frangipani tape_1 ...]
##
## North is up, 0.5 m a character: # road, = footpath or kerb, + paving,
## . grass or dirt, B building, ~ water, o anything else (a bridge, a prop),
## L a street lamp, @ the findable. Bridges count as "o", so check those
## from above with findables_screens.gd's `top`.

const R := 16.0
const STEP := 0.5
const CH := ["?", "#", "=", "+", ".", "B", "~", "o"]

var _main: Node
var _frames := -240
var _todo: Array = []
var _world: Node3D
var _index: Dictionary
var _loaded := {}
var _lights: Array = []
var _phase := 0
var _ray := PhysicsRayQueryParameters3D.new()


func _process(_d: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames < 0:
		return false
	if _frames == 0:
		MapData.shared().wait()
		_collect()
		_index = JSON.parse_string(FileAccess.get_file_as_string("res://map/tiles/index.json"))
		_world = Node3D.new()
		root.add_child(_world)
		_ray.collision_mask = 1 | 2 | (1 << 9)
		return false
	if _todo.is_empty():
		quit(0)
		return true
	var item: Array = _todo[0]
	if _phase == 0:
		_load_around(item[1])
		_phase = 1
		return false
	if _phase < 4:
		_phase += 1
		return false
	_phase = 0
	_todo.pop_front()
	_dump(item[0], item[1])
	return false


func _collect() -> void:
	for c in ["classic_500l", "classic_abarth_595"]:
		if not root.get_node("Garage").owned_cars.has(c):
			root.get_node("Garage").owned_cars.append(c)
	var m := _main.find_child("Mystery", true, false)
	for c: Dictionary in m.clues:
		_todo.append(["clue " + String(c.id), m.spot_position(String(c.id))])
	for p: Node3D in get_nodes_in_group(&"found_parts"):
		_todo.append(["part " + String(p.get("part_id")), p.global_position])
	for s in _scripted(_main, "CuttingSpot"):
		_todo.append(["cutting " + String(s.get("cutting_id")), s.global_position])
	var ids := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if not ids.is_empty():
		_todo = _todo.filter(func(t: Array) -> bool:
			for id in ids:
				if String(t[0]).ends_with(" " + id):
					return true
			return false)


func _scripted(node: Node, name: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in node.get_children():
		var script := child.get_script() as Script
		if script and script.get_global_name() == name:
			out.append(child as Node3D)
		out.append_array(_scripted(child, name))
	return out


func _load_around(at: Vector3) -> void:
	var i := floori(at.x / 500.0)
	var j := floori(-at.z / 500.0)
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
		var result = MapTileLoader.build(path, {}, {})
		if result.error != "":
			continue
		var holder := MapTileLoader.make_collision(result)
		holder.position = result.root.position
		var lights := []
		var instances: Dictionary = MapTileLoader.read(path).get("instances", {})
		var values: PackedFloat32Array = instances.get("street_light", PackedFloat32Array())
		for n in values.size() / 5:
			var o := n * 5
			var base: Vector3 = result.root.position + Vector3(values[o], values[o + 1], values[o + 2])
			lights.append(base + Basis(Vector3.UP, values[o + 3]) * Vector3(0, 6.6, 1.8))
		result.root.free()
		_world.add_child(holder)
		_loaded[k] = [holder, lights]


func _cls(body: CollisionObject3D) -> int:
	if body == null:
		return 7
	if body.collision_layer & (1 << 9):
		return 6
	if body.collision_layer & 2:
		return 5
	var name := String(body.name)
	if name.begins_with("roads_asphalt") or name.begins_with("roads_line"):
		return 1
	if name.begins_with("roads_"):
		return 2
	if name.begins_with("ground_paving") or name.begins_with("ground_concrete"):
		return 3
	if name.begins_with("ground_"):
		return 4
	return 7


func _dump(label: String, at: Vector3) -> void:
	var space := _world.get_world_3d().direct_space_state
	var names := {}
	var lines := PackedStringArray()
	var n := int(R * 2.0 / STEP) + 1
	var lamps := []
	for k: String in _loaded:
		for l: Vector3 in _loaded[k][1]:
			if Vector2(l.x - at.x, l.z - at.z).length() < R:
				lamps.append(l)
	for row in n:
		var z := at.z - R + row * STEP
		var line := ""
		for col in n:
			var x := at.x - R + col * STEP
			if absf(x - at.x) < STEP * 0.5 and absf(z - at.z) < STEP * 0.5:
				line += "@"
				continue
			var lamp := false
			for l: Vector3 in lamps:
				if absf(l.x - x) < STEP * 0.5 and absf(l.z - z) < STEP * 0.5:
					lamp = true
			if lamp:
				line += "L"
				continue
			_ray.from = Vector3(x, 400.0, z)
			_ray.to = Vector3(x, -60.0, z)
			var hit := space.intersect_ray(_ray)
			if hit.is_empty():
				line += " "
				continue
			var c := _cls(hit.collider)
			if hit.collider:
				names[String(hit.collider.name).get_slice("@", 0)] = true
			line += CH[c]
		lines.append(line)
	_ray.from = at + Vector3.UP * 30.0
	_ray.to = at + Vector3.DOWN * 5.0
	var hit := space.intersect_ray(_ray)
	print("=== %s at %s (on %s, y %.2f; N up, E right, %.1f m/char, # road = path/kerb + paving . ground B building L lamp)" % [
		label, at, String(hit.collider.name) if not hit.is_empty() else "nothing", (hit.position as Vector3).y if not hit.is_empty() else 0.0, STEP])
	print("\n".join(lines))
