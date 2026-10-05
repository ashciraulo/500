class_name Trinkets
extends RefCounted
## Small things in the cabin, built in code: fluffy dice, a nodding dog, a
## hula girl... (data/progression/cosmetics.json says which slot each goes
## in). `build()` returns a node whose origin sits where it hangs or stands;
## parts that swing with the car are children named "Swing" (hanging, pivot
## at the top) or "Bob" (standing on a spring, pivot at the bottom), and
## car_body.gd moves them.
##
## Slots: the model may mark them with Mount_Mirror, Mount_Dash, Mount_Shelf
## and Mount_Gear nodes; otherwise `SLOT_FALLBACK` (measured on the Pop).

const SLOT_FALLBACK := {
	"mirror": Vector3(0.0, 1.29, -0.31),
	"dash": Vector3(-0.18, 0.99, -0.77),
	"shelf": Vector3(-0.32, 0.95, 1.38),
	"gear": Vector3(0.0, 0.64, -0.46),
	"glovebox": Vector3(-0.36, 0.76, -0.552),
}
## Where the classics differ (their glovebox is a parcel tray under a painted
## metal dash), measured on the Nuova: [position, tilt about X].
const SLOT_CLASSIC := {
	"glovebox": [Vector3(-0.27, 0.80, -0.508), 0.52],
}


static func build(item: Dictionary) -> Node3D:
	var color := Color.html(item.get("color", "#cccccc"))
	var root := Node3D.new()
	root.name = item.get("id", "Trinket")
	match String(item.get("id", "")):
		"trinket_fluffy_dice":
			var swing := _swing(root)
			_box(swing, Vector3(0.003, 0.09, 0.003), Vector3(0, -0.045, 0), Color(0.1, 0.1, 0.1))
			_box(swing, Vector3(0.045, 0.045, 0.045), Vector3(-0.025, -0.11, 0), color, Vector3(0.3, 0.4, 0.2))
			_box(swing, Vector3(0.045, 0.045, 0.045), Vector3(0.028, -0.125, 0.01), color, Vector3(-0.2, 0.9, 0.3))
		"trinket_air_freshener":
			var swing := _swing(root)
			_box(swing, Vector3(0.002, 0.07, 0.002), Vector3(0, -0.035, 0), Color(0.9, 0.9, 0.9))
			var tree := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.06, 0.08, 0.004)
			tree.mesh = prism
			tree.position = Vector3(0, -0.11, 0)
			tree.material_override = PS1Material.make(color)
			swing.add_child(tree)
		"trinket_nodding_dog":  # Faces out of the back window.
			_box(root, Vector3(0.06, 0.07, 0.12), Vector3(0, 0.035, 0), color)
			var swing := _swing(root, Vector3(0, 0.08, 0.05), true)
			_box(swing, Vector3(0.06, 0.06, 0.07), Vector3(0, 0.02, 0.02), color)
			_box(swing, Vector3(0.012, 0.04, 0.03), Vector3(-0.034, 0.0, 0.02), color.darkened(0.4))
			_box(swing, Vector3(0.012, 0.04, 0.03), Vector3(0.034, 0.0, 0.02), color.darkened(0.4))
		"trinket_hula_girl":
			_cylinder(root, 0.03, 0.03, 0.012, Vector3(0, 0.006, 0), Color(0.2, 0.5, 0.3))
			var swing := _swing(root, Vector3(0, 0.012, 0), true)
			_cylinder(swing, 0.006, 0.03, 0.035, Vector3(0, 0.03, 0), Color(0.3, 0.7, 0.35))
			_cylinder(swing, 0.012, 0.014, 0.04, Vector3(0, 0.067, 0), color)
			_sphere(swing, 0.014, Vector3(0, 0.1, 0), color)
			_sphere(swing, 0.015, Vector3(0, 0.106, 0.004), Color(0.1, 0.07, 0.05))
		"trinket_bobblehead":
			_cylinder(root, 0.02, 0.025, 0.05, Vector3(0, 0.025, 0), color)
			var swing := _swing(root, Vector3(0, 0.05, 0), true)
			_box(swing, Vector3(0.004, 0.02, 0.004), Vector3(0, 0.01, 0), Color(0.6, 0.6, 0.6))
			_sphere(swing, 0.032, Vector3(0, 0.045, 0), color)
			_sphere(swing, 0.012, Vector3(-0.022, 0.07, 0), color.darkened(0.2))
			_sphere(swing, 0.012, Vector3(0.022, 0.07, 0), color.darkened(0.2))
			_sphere(swing, 0.006, Vector3(0, 0.04, -0.03), Color(0.05, 0.05, 0.05))
		"interior_wooden_knob":
			_sphere(root, 0.042, Vector3(0, 0.015, 0), color)
		"trinket_night_drive_tape":  # From the shed, at the end of the mystery.
			var tape := MysteryProps.build("cassette")
			tape.rotation.y = 0.3
			root.add_child(tape)
		"trinket_meet_plaque":
			_box(root, Vector3(0.11, 0.045, 0.005), Vector3(0, 0.022, 0), color, Vector3(-0.5, 0, 0))
			var label := Label3D.new()
			label.text = "ROE ST MEET"
			label.font_size = 18
			label.pixel_size = 0.0015
			label.modulate = Color(0.15, 0.15, 0.15)
			label.position = Vector3(0, 0.023, 0.004)
			label.rotation.x = -0.5
			root.add_child(label)
		"trinket_dash_wagtail":  # The field journal's 10-species reward.
			if ResourceLoader.exists(DASH_BIRD):
				var bird := (load(DASH_BIRD) as PackedScene).instantiate() as Node3D
				bird.rotation.y = PI  # Facing back into the cabin, watching you.
				root.add_child(bird)
				var head := bird.find_child("Head", true, false) as Node3D
				if head:
					# Nod from the neck: the head rides on a "Bob" at its origin.
					var neck := _swing(head.get_parent() as Node3D, head.position, true)
					head.get_parent().remove_child(head)
					head.owner = null
					head.position = Vector3.ZERO
					neck.add_child(head)
				PS1Model.apply(bird)
			else:
				_box(root, Vector3(0.03, 0.05, 0.06), Vector3(0, 0.025, 0), color)
		"trinket_naturalist_sticker":  # 20 species: stuck on the glovebox lid.
			var sticker := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.07, 0.07)
			sticker.mesh = quad
			sticker.material_override = PS1Material.textured(_sticker_texture(color))
			root.add_child(sticker)
		_:
			_box(root, Vector3(0.04, 0.04, 0.04), Vector3(0, 0.02, 0), color)
	return root


const DASH_BIRD := "res://art/models/props/field/dash_bird.glb"
## A wagtail in profile, for the naturalists' club sticker ("#" is ink).
const STICKER_BIRD := [
	"..........##....",
	".........####...",
	"........######..",
	"..#....#######..",
	"..##..########..",
	"...##########...",
	"....#########...",
	".....#######....",
	"......#..#......",
	"......#..#......",
]


## The club's sticker: a green square, a cream border, a wagtail and two
## lines of lettering too small to read.
static func _sticker_texture(green: Color) -> ImageTexture:
	var size := 24
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cream := Color(0.93, 0.9, 0.8)
	image.fill(cream)
	image.fill_rect(Rect2i(2, 2, size - 4, size - 4), green)
	for row in STICKER_BIRD.size():
		var line: String = STICKER_BIRD[row]
		for col in line.length():
			if line[col] == "#":
				image.set_pixel(4 + col, 4 + row, cream)
	image.fill_rect(Rect2i(5, 16, 14, 1), cream)
	image.fill_rect(Rect2i(7, 18, 10, 1), cream)
	return ImageTexture.create_from_image(image)


## Where a slot is on this model, in its own space.
static func slot_position(model: Node3D, slot: String, classic := false) -> Vector3:
	var mount := model.find_child("Mount_" + slot.capitalize(), true, false) as Node3D
	if mount:
		return model.global_transform.affine_inverse() * mount.global_position if mount.is_inside_tree() else mount.position
	if classic and SLOT_CLASSIC.has(slot):
		return SLOT_CLASSIC[slot][0]
	return SLOT_FALLBACK.get(slot, Vector3(0, 1.0, -0.7))


## How far a slot's trinket tilts back about X (the classics' sloped dash).
static func slot_tilt(slot: String, classic := false) -> float:
	return SLOT_CLASSIC[slot][1] if classic and SLOT_CLASSIC.has(slot) else 0.0


static func _swing(parent: Node3D, at := Vector3.ZERO, upright := false) -> Node3D:
	var swing := Node3D.new()
	swing.name = "Bob" if upright else "Swing"
	swing.position = at
	parent.add_child(swing)
	return swing


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var box := BoxMesh.new()
	box.size = size
	_add(parent, box, at, color, rot)


static func _sphere(parent: Node3D, radius: float, at: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_add(parent, sphere, at, color)


static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, color: Color) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = 8
	cylinder.rings = 1
	_add(parent, cylinder, at, color)


static func _add(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rot
	instance.material_override = PS1Material.make(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
