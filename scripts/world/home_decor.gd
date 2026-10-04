class_name HomeDecor
extends Node
## Things you've collected, shown around the townhouse at the home model's
## empties (art/models/README.md): the framed street directory and the neon
## "500" (garage cosmetics from the mileage rewards), a trophy on the lounge
## shelves for each career tier finished and each classic restored, a card on
## the corkboard for each classic you've found, and your latest album photos
## in the frames up the stairs.
##
## Each empty faces into the room along its local +Z.

const SHELVES := 8
const PINS := 12
const FRAMES := 6

var _home: Node3D
var _props := {}  # empty name -> Node3D we put there
var _neon_light: OmniLight3D
var _dirty := true
var _check := 0.0


func _ready() -> void:
	Progression.reward_unlocked.connect(func(_r: Dictionary) -> void: _dirty = true)
	Progression.tier_completed.connect(func(_i: int, _t: Dictionary) -> void: _dirty = true)
	Activities.photo_taken.connect(func(_e: Dictionary) -> void: _dirty = true)
	Classics.wreck_found.connect(func(_id: String) -> void: _dirty = true)
	Classics.restored.connect(func(_id: String, _f: String) -> void: _dirty = true)


func _process(delta: float) -> void:
	if _neon_light:
		_neon_light.visible = GameClock.daylight() < 0.6
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		_props.clear()
		_dirty = true
	if _home and _dirty:
		_dirty = false
		refresh()


## Rebuild everything from what's been earned.
func refresh() -> void:
	_put("Deco_RoadMap", _road_map() if Progression.rewards.has("garage_road_map") else null)
	_put("Deco_NeonSign", _neon() if Progression.rewards.has("garage_neon_sign") else null)
	# Trophies: gold for each career tier finished, silver for each classic restored.
	var trophies: Array[Color] = []
	for i in mini(Progression.tier_index, Progression.tiers.size()):
		trophies.append(Color(0.85, 0.68, 0.25))
	for car_id: String in Classics.projects:
		if Classics.is_restored(car_id):
			trophies.append(Color(0.78, 0.78, 0.8))
	for i in SHELVES:
		_put("Deco_Shelf_%d" % (i + 1), _trophy(trophies[i]) if i < trophies.size() else null)
	var found: Array = Classics.projects.keys()
	for i in PINS:
		_put("Corkboard_Pin_%d" % (i + 1), _card(String(found[i])) if i < found.size() else null)
	var photos: Array = Activities.photos.slice(-FRAMES)
	photos.reverse()
	for i in FRAMES:
		_put("Photo_Frame_%d" % (i + 1), _photo(String(photos[i].get("file", ""))) if i < photos.size() else null)


func _put(empty_name: String, prop: Node3D) -> void:
	var old: Node3D = _props.get(empty_name)
	if old and is_instance_valid(old):
		old.queue_free()
	_props.erase(empty_name)
	if prop == null:
		return
	var empty := _home.find_child(empty_name, true, false) as Node3D
	if empty == null:
		prop.free()
		return
	prop.name = "Decor"
	empty.add_child(prop)
	_props[empty_name] = prop


# --- Props, built facing +Z ---------------------------------------------------------

func _road_map() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.86, 0.6, 0.025), Vector3(0, 0, 0.012), Color(0.2, 0.14, 0.09))
	_box(root, Vector3(0.78, 0.52, 0.004), Vector3(0, 0, 0.026), Color(0.88, 0.85, 0.74))
	# Roads and the river, roughly.
	_box(root, Vector3(0.78, 0.018, 0.002), Vector3(0, 0.05, 0.029), Color(0.85, 0.55, 0.3))
	_box(root, Vector3(0.018, 0.52, 0.002), Vector3(-0.12, 0, 0.029), Color(0.85, 0.55, 0.3))
	_box(root, Vector3(0.5, 0.06, 0.002), Vector3(0.12, -0.17, 0.029), Color(0.45, 0.62, 0.8))
	_box(root, Vector3(0.14, 0.11, 0.002), Vector3(-0.27, -0.06, 0.029), Color(0.5, 0.68, 0.42))
	return root


func _neon() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.7, 0.32, 0.03), Vector3(0, 0, 0.015), Color(0.08, 0.08, 0.09))
	var label := Label3D.new()
	label.text = "500"
	label.font_size = 96
	label.pixel_size = 0.0028
	label.outline_size = 0
	label.modulate = Color(1.0, 0.35, 0.3)
	label.shaded = false
	label.position = Vector3(0, 0, 0.035)
	root.add_child(label)
	_neon_light = OmniLight3D.new()
	_neon_light.light_color = Color(1.0, 0.35, 0.3)
	_neon_light.light_energy = 1.2
	_neon_light.omni_range = 4.0
	_neon_light.position = Vector3(0, 0, 0.4)
	root.add_child(_neon_light)
	return root


func _trophy(color: Color) -> Node3D:
	var root := Node3D.new()
	_cylinder(root, 0.04, 0.045, 0.03, Vector3(0, 0.015, 0), Color(0.15, 0.12, 0.1))
	_cylinder(root, 0.012, 0.012, 0.06, Vector3(0, 0.06, 0), color)
	_cylinder(root, 0.045, 0.02, 0.07, Vector3(0, 0.125, 0), color)
	return root


func _card(car_id: String) -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.17, 0.12, 0.002), Vector3(0, -0.02, 0.006), Color(0.95, 0.93, 0.86))
	_box(root, Vector3(0.13, 0.06, 0.001), Vector3(0, -0.005, 0.0075), Classics.paint_for(car_id))
	var label := Label3D.new()
	label.text = String(CarCatalogue.get_car(car_id).get("name", car_id))
	label.font_size = 20
	label.pixel_size = 0.0012
	label.modulate = Color(0.15, 0.15, 0.15)
	label.outline_size = 0
	label.position = Vector3(0, -0.06, 0.008)
	root.add_child(label)
	_sphere(root, 0.008, Vector3(0, 0.035, 0.01), Color(0.8, 0.15, 0.12))
	return root


func _photo(file: String) -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.3, 0.22, 0.02), Vector3(0, 0, 0.01), Color(0.12, 0.1, 0.08))
	var picture := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.18)
	picture.mesh = quad
	picture.position = Vector3(0, 0, 0.022)
	var image := Image.load_from_file(file) if file != "" and FileAccess.file_exists(file) else null
	if image:
		image.resize(160, 90, Image.INTERPOLATE_BILINEAR)
		picture.material_override = PS1Material.textured(ImageTexture.create_from_image(image))
	else:
		picture.material_override = PS1Material.make(Color(0.85, 0.83, 0.78))
	picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(picture)
	return root


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_add(parent, box, at, color)


static func _sphere(parent: Node3D, radius: float, at: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	_add(parent, sphere, at, color)


static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, color: Color) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = 8
	cylinder.rings = 1
	_add(parent, cylinder, at, color)


static func _add(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = PS1Material.make(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
