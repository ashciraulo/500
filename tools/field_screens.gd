extends SceneTree
## Screenshots of the field journal for review: field-guide plates of every
## bird model, then birds through the binoculars in their real places.
##
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/field_screens.gd -- --no-save shots=/tmp/field
##
## The last plate shows a few in flight. plates=only skips the in-game part,
## plates=skip the plates; plates=fish shoots just the fish plate.

const PER_PLATE := 10
## [species, habitat, where the car stops, hour]
const SCENES := [
	["galah", "kings_park_lawns", Vector3(-935.6, 66.0, 1455.6), 8.5],
	["rainbow_lorikeet", "russell_square", Vector3(150.0, 22.0, 30.0), 10.0],
	["black_swan", "langley_park", Vector3(742.0, 3.0, 1533.0), 9.0],
	["little_pied_cormorant", "langley_park", Vector3(742.0, 3.0, 1533.0), 9.0],
	["australian_pelican", "langley_park", Vector3(742.0, 3.0, 1533.0), 16.0],
	["carnabys_black_cockatoo", "kings_park_bush", Vector3(-2189.0, 48.0, 1822.0), 17.6],
	["laughing_kookaburra", "kings_park_bush", Vector3(-2189.0, 48.0, 1822.0), 6.5],
	["tawny_frogmouth", "russell_square", Vector3(150.0, 22.0, 30.0), 22.5],
	# The wrong birds: no habitat; the car stops by their place (ZERO: home).
	["wrong_frogmouth", "", Vector3.ZERO, 1.0],
	["wrong_cockatoos", "", Vector3(-911.35, 68.4, 923.83), 3.0],
	["wrong_swan", "", Vector3(2173.3, 1.76, 1967.86), 2.0],
]

## The last plate: these in flight.
const FLIGHT_PLATE := ["silver_gull", "black_swan", "australian_pelican", "nankeen_kestrel", "osprey",
	"welcome_swallow", "galah", "carnabys_black_cockatoo", "white_faced_heron", "rainbow_lorikeet"]

var _shots := "/tmp/field"
var _plates_only := false
var _stage := 0
var _frames := 0
var _plate := 0
var _plate_root: Node3D
var _main: Node
var _car: RigidBody3D
var _fj: Node
var _field: Node
var _scene := 0
var _sighting: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		if arg == "plates=only":
			_plates_only = true
		if arg == "plates=skip":
			_stage = 1
		if arg == "plates=fish":
			_stage = 5
	DirAccess.make_dir_recursive_absolute(_shots)


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		0:
			if _frames == 2:
				_fj = root.get_node("FieldJournal")
				_build_plate(_plate)
			elif _frames == 12:
				_save("plate_%d" % (_plate + 1) if _plate * PER_PLATE < _fj.bird_order.size() else "plate_flight")
				_plate += 1
				_plate_root.queue_free()
				if (_plate - 1) * PER_PLATE < _fj.bird_order.size():
					_frames = 0
				else:
					if _plates_only:
						quit()
						return true
					_stage = 1
					_frames = 0
		5:
			if _frames == 2:
				_fj = root.get_node("FieldJournal")
				_build_fish_plate()
			elif _frames == 12:
				_save("plate_fish")
				quit()
				return true
		1:
			if _frames == 1:
				_fj = root.get_node("FieldJournal")
				_main = load("res://scenes/main.tscn").instantiate()
				root.add_child(_main)
				current_scene = _main
				_car = _main.get_node("LoFi/SubViewport/World/Car")
				root.get_node("GameClock").set_locked(true)
				root.get_node("Weather").set_locked(true)
				root.get_node("Weather").set_state(0, true)
				root.get_node("Settings").show_help = false
			elif _frames == 90:
				_field = _main.find_child("Field", true, false)
				_field.birds.auto_spawn = false
				var hud := get_first_node_in_group(&"hud")
				if hud:
					for c in hud.get_children():
						for l in c.get_children():
							if l is Label and l.text.begins_with("W/S"):
								l.visible = false
				_stage = 2
				_frames = 0
		2:
			if _scene >= SCENES.size():
				quit()
				return true
			var sc: Array = SCENES[_scene]
			if _frames == 1:
				root.get_node("GameClock").set_time(sc[3])
				_field.birds.clear()
				_teleport(sc[2])
			elif _frames == 120 and sc[2] == Vector3.ZERO:
				# Home: the car's own spot in the carport.
				var map: Node = _fj.map_node()
				var t: Transform3D = map.get_spawn_transform()
				_teleport(t.origin)
				_car.global_basis = t.basis
			elif _frames == 200 and String(sc[0]).begins_with("wrong_"):
				for clue in ["tape_1", "polaroid", "ticket", "atlas_page", "keyring", "tape_12", "solved"]:
					root.get_node("Discoveries").discover("mystery/" + clue)
				var sp: Dictionary = _fj.bird(sc[0])
				_sighting = _field.birds.spawn_wrong(sp, _field.birds.wrong_place(sp))
				if _sighting.is_empty():
					print("no spot for ", sc[0])
					_next_scene()
					return false
				_car.freeze = false
				_car.set_physics_process(true)
			elif _frames == 200:
				_sighting = _spawn_visible(sc[0], _fj.habitat(sc[1]), sc[2])
				if _sighting.is_empty():
					print("no spot for ", sc[0])
					_next_scene()
					return false
				_car.freeze = false
				_car.set_physics_process(true)
			elif _frames == 260:
				_field.binoculars.open()
			elif _frames == 262:
				_step_to_the_edge(_sighting.birds[0].node)
			elif _frames > 260 and _frames < 420:
				_aim(_sighting.birds[0].node)
				if _frames >= 328 and _frames <= 332:
					# The same view without zooming in, for where it is.
					_field.binoculars._camera.fov = 32.0
				if _frames == 332:
					_save("view_%d_%s_wide" % [_scene + 1, sc[0]])
			elif _frames == 420:
				_report(_sighting.birds[0].node)
				_save("view_%d_%s" % [_scene + 1, sc[0]])
				_field.binoculars.close()
				_next_scene()
	return false


func _next_scene() -> void:
	_scene += 1
	_frames = 0


func _teleport(p: Vector3) -> void:
	_car.freeze = true
	_car.set_physics_process(false)
	_car.global_transform = Transform3D(Basis(), p + Vector3.UP * 0.8)
	_car.linear_velocity = Vector3.ZERO


func _spawn_visible(id: String, h: Dictionary, at: Vector3) -> Dictionary:
	var birds: Node = _field.birds
	for dist in [18.0, 25.0, 35.0, 50.0]:
		for i in 16:
			var a := TAU * i / 16.0
			var s: Dictionary = birds.spawn(_fj.bird(id), h, at + Vector3(cos(a), 0, sin(a)) * dist)
			if s.is_empty():
				continue
			var eye := _car.global_position + Vector3.UP * 1.2
			var q := PhysicsRayQueryParameters3D.create(eye, s.birds[0].node.global_position + Vector3.UP * 0.2, 1 | 2)
			q.exclude = [_car.get_rid()]
			if _car.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				return s
			birds._remove(s)
	return {}


func _aim(node: Node3D) -> void:
	var b: Node = _field.binoculars
	if not is_instance_valid(node) or b._camera == null:
		return
	var size: float = _fj.bird(String(node.get_meta("species"))).get("size", 0.3)
	var to: Vector3 = node.global_position + Vector3.UP * size * 0.3 - b._camera.global_position
	b._yaw = atan2(-to.x, -to.z)
	b._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	# Zoom so the bird fills a fair bit of the view.
	b._camera.fov = clampf(rad_to_deg(size / to.length()) * 4.0, _fj.gear_binoculars().fov, 32.0)


## Water birds sit below the bank: if it's in the way, look from the top of
## the bank instead, the way you would on foot.
func _step_to_the_edge(node: Node3D) -> void:
	var cam: Camera3D = _field.binoculars._camera
	if not is_instance_valid(node) or cam == null:
		return
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, node.global_position + Vector3.UP * 0.15, 1 | 2)
	q.exclude = [_car.get_rid()]
	var hit := _car.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var at: Vector3 = hit.position
	var toward := (node.global_position - at) * Vector3(1, 0, 1)
	cam.global_position = at + toward.normalized() * 1.0 + Vector3.UP * 1.6
	cam.near = 0.3


func _build_fish_plate() -> void:
	_plate_root = Node3D.new()
	root.add_child(_plate_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.84, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.75)
	e.ambient_light_energy = 0.8
	env.environment = e
	_plate_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.1
	_plate_root.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.0, 6.4)
	cam.fov = 50.0
	_plate_root.add_child(cam)
	cam.current = true
	var ids: Array = Array(_fj.fish_order)
	for i in ids.size():
		var f: Dictionary = _fj.fish_species(ids[i])
		var fish := FishModels.build(f)
		fish.scale = Vector3.ONE * 1.4
		var col := i % 5
		var row := i / 5
		fish.position = Vector3(-3.6 + col * 1.8, 1.5 - row * 1.75, 0)
		match String(f.get("model", "")):
			"crab":
				fish.rotation = Vector3(1.0, 0, 0)
			"hubcap":
				fish.rotation = Vector3(1.3, 0, 0)
				fish.scale = Vector3.ONE * 1.6
			_:
				fish.rotation.y = PI * 0.5
		_plate_root.add_child(fish)
		var label := Label3D.new()
		label.text = "%s\n%d-%d cm" % [f.name, int(f.length[0]), int(f.length[1])]
		label.font_size = 26
		label.pixel_size = 0.0035
		label.modulate = Color(0.15, 0.13, 0.12)
		label.outline_size = 0
		label.position = fish.position + Vector3(0, -0.45, 0.6)
		_plate_root.add_child(label)


func _report(node: Node3D) -> void:
	var cam: Camera3D = _field.binoculars._camera
	if not is_instance_valid(node) or cam == null:
		print("  bird gone")
		return
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, node.global_position + Vector3.UP * 0.15, 1 | 2)
	q.exclude = [_car.get_rid()]
	var hit := _car.get_world_3d().direct_space_state.intersect_ray(q)
	print("  bird %s at %s, camera %s, %.1f m, fov %.1f, car moved %.1f m, blocked %s" % [node.name, node.global_position,
		cam.global_position, cam.global_position.distance_to(node.global_position), cam.fov,
		_car.global_position.distance_to(SCENES[_scene][2]), hit.get("position", "no")])


func _save(name: String) -> void:
	root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
	print("saved ", name)


## A field-guide plate: each bird on a grey card with its name, all scaled to
## about the same height so the models can be checked.
func _build_plate(index: int) -> void:
	_plate_root = Node3D.new()
	root.add_child(_plate_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.84, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.75)
	e.ambient_light_energy = 0.8
	env.environment = e
	_plate_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.1
	_plate_root.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.3, 6.2)
	cam.rotation.x = -0.08
	cam.fov = 50.0
	_plate_root.add_child(cam)
	cam.current = true
	var flying: bool = index * PER_PLATE >= _fj.bird_order.size()
	var ids: Array = FLIGHT_PLATE if flying else Array(_fj.bird_order).slice(index * PER_PLATE, (index + 1) * PER_PLATE)
	for i in ids.size():
		var b: Dictionary = _fj.bird(ids[i])
		var bird := BirdModels.build(b)
		var s := 1.25 / maxf(float(b.size), 0.1)
		bird.scale = Vector3.ONE * s
		var col := i % 5
		var row := i / 5
		bird.position = Vector3(-3.6 + col * 1.8, 0.75 - row * 2.1, 0)
		bird.rotation.y = -1.95
		_plate_root.add_child(bird)
		if flying:
			BirdModels.set_flying(bird, true)
			BirdModels.flap(bird, 0.5 + i * 0.4)
			bird.rotation = Vector3(0.5, -2.3, 0.0)
		var label := Label3D.new()
		label.text = "%s\n%.2f m" % [b.name, float(b.size)]
		label.font_size = 26
		label.pixel_size = 0.0035
		label.modulate = Color(0.15, 0.13, 0.12)
		label.outline_size = 0
		label.position = bird.position + Vector3(0, -0.2, 0.6)
		_plate_root.add_child(label)
