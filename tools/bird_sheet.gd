extends SceneTree
## Close-up renders of every bird model for checking against reference
## photos: for each species a side view, a three-quarter view from the front
## and one in flight, each scaled to fill the frame.
##
##   xvfb-run -a godot --path . --resolution 640x480 --script res://tools/bird_sheet.gd -- --no-save shots=/tmp/birds
##
## only=id,id limits it to some species; models=res://path.gd and
## data=/path/birds.json render another builder or data (for before/after).

const VIEWS := ["side", "front", "flight"]

var _shots := "/tmp/birds"
var _ids: Array = []
var _birds := {}
var _models: Variant = null
var _i := 0
var _view := 0
var _frames := 0
var _stage_root: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var data_path := "res://data/field/birds.json"
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		elif arg.begins_with("only="):
			only = arg.trim_prefix("only=")
		elif arg.begins_with("models="):
			_models = load(arg.trim_prefix("models="))
		elif arg.begins_with("data="):
			data_path = arg.trim_prefix("data=")
	if _models == null:
		_models = BirdModels
	DirAccess.make_dir_recursive_absolute(_shots)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	for b: Dictionary in data.birds:
		_birds[b.id] = b
		if only == "" or b.id in only.split(","):
			_ids.append(b.id)
	_stage_root = Node3D.new()
	root.add_child.call_deferred(_stage_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.84, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.75)
	e.ambient_light_energy = 0.8
	env.environment = e
	_stage_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.1
	_stage_root.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_stage_root.add_child(_cam)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _i >= _ids.size():
		quit()
		return true
	if _frames == 3:
		_pose(_ids[_i], VIEWS[_view])
	elif _frames == 6:
		var path := _shots.path_join("%s_%s.png" % [_ids[_i], VIEWS[_view]])
		root.get_texture().get_image().save_png(path)
		_stage_root.get_node("Bird").free()
		_view += 1
		if _view >= VIEWS.size():
			_view = 0
			_i += 1
			print("saved ", path)
		_frames = 2
	return false


func _pose(id: String, view: String) -> void:
	var b: Dictionary = _birds[id]
	var bird: Node3D = _models.build(b)
	bird.name = "Bird"
	_stage_root.add_child(bird)
	if view == "flight":
		_models.set_flying(bird, true)
		_models.flap(bird, 0.35)
		bird.transform.basis = Basis(Vector3.RIGHT, -0.75) * Basis(Vector3.UP, -2.3)
	elif view == "front":
		bird.rotation.y = PI + 0.75
	else:
		bird.rotation.y = -PI * 0.5
	# Frame the whole bird.
	var box := AABB()
	var first := true
	for m: Node in bird.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var bb := mi.global_transform * mi.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var centre := box.get_center()
	var r := box.size.length() * 0.5
	var dist := r / tan(deg_to_rad(_cam.fov * 0.5)) * 0.95
	_cam.position = centre + Vector3(0, r * 0.15, dist)
	_cam.look_at(centre)
	_cam.near = dist * 0.05
	_cam.far = dist * 4.0
	_cam.current = true
