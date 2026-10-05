extends SceneTree
## Checks every fishing spot's stand is on dry footing with water in front,
## and where the map's fishing POIs (`at`) land, so the two agree.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/field/check_spots.gd [-- shots=<dir>]
##
## With shots=, renders each spot from behind the angler (needs a display).

const WAIT := 150

var _main: Node
var _car: RigidBody3D
var _boats: Node
var _items: Array = []
var _index := -1
var _frames := 0
var _bad := 0
var _shots := ""
var _cam: Camera3D


func _process(_delta: float) -> bool:
	if _main == null:
		var only := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("shots="):
				_shots = a.substr(6)
			elif a.begins_with("only="):
				only = a.substr(5)
		var spots: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/field/fishing_spots.json")).spots
		for sp: Dictionary in spots:
			if sp.has("stand"):
				_items.append({"id": "spot " + String(sp.id), "p": Vector3(sp.stand[0], sp.stand[1], sp.stand[2]), "yaw": float(sp.yaw)})
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://map/tiles/index.json"))
		for poi: Dictionary in index.get("pois", []):
			if poi.get("kind", "") == "fishing":
				var at: Array = poi.at
				_items.append({"id": "map  " + String(poi.id), "p": Vector3(at[0], at[1], at[2]), "yaw": INF})
		if only != "":
			_items = _items.filter(func(it: Dictionary) -> bool: return String(it.id).contains(only))
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_frames = WAIT - 30
		return false
	_frames += 1
	if _shots != "" and _index >= 0 and _frames == WAIT - 5:
		_view(_items[_index])
	if _frames < WAIT:
		return false
	if _boats == null:
		var traffic := get_first_node_in_group(&"traffic")
		_boats = traffic.get("boats") if traffic else null
	if _index >= 0:
		_check(_items[_index])
	_index += 1
	if _index >= _items.size():
		print("CHECK SPOTS DONE (%d to look at)" % _bad)
		quit()
		return true
	var p: Vector3 = _items[_index].p
	_car.freeze = true
	_car.set_physics_process(false)
	_car.global_position = p + Vector3(0, 40.0, 30.0)
	_frames = 0
	return false


func _ground(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 3.0, p.z), Vector3(p.x, -15.0, p.z), 1 | 2)
	q.exclude = [_car.get_rid()]
	return _car.get_world_3d().direct_space_state.intersect_ray(q)


func _is_water(p: Vector3) -> bool:
	var hit := _ground(Vector3(p.x, 40.0, p.z))
	if not hit.is_empty() and hit.position.y > 0.25:
		return false  # a deck or bank over the river mask
	return hit.is_empty() or hit.position.y < -0.2 or (_boats != null and _boats.water_at(p, 0.0))


func _check(it: Dictionary) -> void:
	var p: Vector3 = it.p
	var hit := _ground(p)
	var dry: bool = not hit.is_empty() and hit.position.y > -0.2 and absf(hit.position.y - p.y) < 0.6
	var line := "%-40s (%.1f, %.2f, %.1f) " % [it.id, p.x, p.y, p.z]
	line += ("on %s at y %.2f" % [hit.collider.get_meta("surface", "?"), hit.position.y]) if not hit.is_empty() else "NOTHING UNDERFOOT"
	var ok: bool = dry
	if float(it.yaw) != INF:
		var d := Vector3(-sin(it.yaw), 0, -cos(it.yaw))
		var wet := 0
		for r: float in [3.0, 6.0, 10.0, 15.0]:
			if _is_water(p + d * r):
				wet += 1
		line += ", water ahead %d/4" % wet
		ok = ok and wet >= 3
	if not ok:
		_bad += 1
	print(("ok   " if ok else "LOOK ") + line)


## Behind and above the angler, looking the way they face.
func _view(it: Dictionary) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 60.0
		_car.get_parent().add_child(_cam)
		_cam.current = true
		var hud := get_first_node_in_group(&"hud")
		if hud:
			(hud as CanvasItem).visible = false
	var yaw: float = float(it.yaw) if float(it.yaw) != INF else 0.0
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var p: Vector3 = it.p
	_cam.look_at_from_position(p - fwd * 7.0 + Vector3.UP * 3.5, p + fwd * 6.0)
	# A post where the angler stands.
	var post := get_root().get_node_or_null("SpotPost") as MeshInstance3D
	if post == null:
		post = MeshInstance3D.new()
		post.name = "SpotPost"
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 1.8, 0.3)
		post.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.3, 0.1)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		post.material_override = mat
		_car.get_parent().add_child(post)
	post.global_position = p + Vector3.UP * 0.9
	await process_frame
	await process_frame
	var img := _car.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shots, String(it.id).replace(" ", "_")])
