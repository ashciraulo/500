class_name HouseDarkroom
extends House1979
## The house as a darkroom (OtherHouse, act 4, STORY.md event 1): every room
## lit red by safelights like Ros's darkroom at the lab, and lines strung
## through the rooms pegged with prints of your own photos. A few of the
## prints are of places you haven't been yet; those you can take down, and
## they go in your album.
##
## Built in the house's frame like House1979 (whose helpers it uses), without
## the Dorans' furniture.

const SAFELIGHT := Color(1.0, 0.04, 0.02)
const LINE := Color(0.12, 0.1, 0.09)
const PEG := Color(0.62, 0.5, 0.36)
const PAPER := Color(0.9, 0.88, 0.82)
## The lines: [from, to] in the house frame (x across, y back, z up).
const LINES := [
	[Vector3(1.4, 1.6, 1.95), Vector3(5.1, 1.6, 1.95)],
	[Vector3(1.4, 3.4, 1.95), Vector3(5.1, 3.4, 1.95)],
	[Vector3(1.6, 6.7, 1.95), Vector3(5.1, 6.7, 1.95)],
	[Vector3(1.6, 10.2, 1.95), Vector3(5.1, 10.2, 1.95)],
	[Vector3(1.4, 2.4, 3.16 + 1.9), Vector3(5.1, 2.4, 3.16 + 1.9)],
	[Vector3(1.6, 10.0, 3.16 + 1.9), Vector3(4.6, 10.0, 3.16 + 1.9)],
]
## Prints along a line every this many metres, this size (across, up).
const GAP := 0.34
const PRINT := Vector2(0.16, 0.12)
## How many prints are of places you haven't been yet.
const UNSEEN := 3

## Photo files from your album (newest first) to hang.
var photos: Array[String] = []
## Places you haven't been yet: [{id, title}], one print each.
var unseen: Array[Dictionary] = []
## Every print you can take: {node, id, title, image, taken}.
var takeable: Array[Dictionary] = []


func _ready() -> void:
	name = "HouseDarkroom"
	# Safelights: one low red lamp a room, and the stairwell.
	for p: Vector3 in [Vector3(3.2, 2.5, 2.3), Vector3(3.2, 7.2, 2.3), Vector3(3.2, 10.6, 2.3),
			Vector3(0.6, 7.0, 2.6), Vector3(3.2, 2.4, 3.16 + 2.2), Vector3(3.0, 10.4, 3.16 + 2.2)]:
		lights.append(_light(p, SAFELIGHT, 1.3, 5.0))
		_box(Vector3(0.18, 0.18, 0.12), p + Vector3(0, 0, 0.25), SAFELIGHT, 2.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var slots: Array[Array] = []
	for line: Array in LINES:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var length := a.distance_to(b)
		_box(Vector3(length, 0.006, 0.006), (a + b) * 0.5, LINE)
		var n := int(length / GAP)
		for k in n:
			var at := a.lerp(b, (k + 0.5) / n)
			slots.append([at, rng.randf_range(-0.12, 0.12)])
	# The places you haven't been go in spread out among your own.
	var unseen_slots := {}
	for i in mini(unseen.size(), UNSEEN):
		unseen_slots[(i * 7 + 3) % slots.size()] = unseen[i]
	var own := 0
	for i in slots.size():
		var at: Vector3 = slots[i][0]
		var tilt: float = slots[i][1]
		if unseen_slots.has(i):
			var spot: Dictionary = unseen_slots[i]
			var image := _unseen_image(String(spot.id))
			var node := _print(at, tilt, image)
			takeable.append({"node": node, "id": spot.id, "title": spot.title, "image": image, "taken": false})
		else:
			# Your own photos; past the end of your album, half-developed ones.
			var image: Image = null
			if own < photos.size():
				image = _own_image(photos[own])
			if image == null:
				image = _ghost_image(i)
			own += 1
			_print(at, tilt, image)


## A print pegged under the line at `at`, its face to the front of the house.
func _print(at: Vector3, tilt: float, image: Image) -> Node3D:
	var hang := Node3D.new()
	hang.position = House1979.at(at)
	hang.rotation.z = tilt * 0.3
	add_child(hang)
	_box(Vector3(0.02, 0.012, 0.04), Vector3(0, 0, -0.01), PEG, 0.0, hang)
	var paper := _box(Vector3(PRINT.x + 0.02, 0.004, PRINT.y + 0.02), Vector3(0, 0, -0.03 - PRINT.y * 0.5), PAPER, 0.0, hang)
	if image:
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = PRINT
		face.mesh = quad
		face.material_override = PS1Material.textured(ImageTexture.create_from_image(image), Color.WHITE, Vector2.ONE)
		face.position = Vector3(0, -0.03 - PRINT.y * 0.5, 0.003)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hang.add_child(face)
		var back := face.duplicate() as MeshInstance3D
		back.position.z = -0.003
		back.rotation.y = PI
		hang.add_child(back)
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return hang


## One of your own photos, small.
static func _own_image(file: String) -> Image:
	var image := Image.load_from_file(file) if FileAccess.file_exists(file) else null
	if image == null:
		return null
	image.resize(64, 48, Image.INTERPOLATE_BILINEAR)
	return image


## A print of somewhere you haven't been: grainy, a horizon, trees or roofs,
## a pale sky. The same place always prints the same.
static func _unseen_image(id: String) -> Image:
	var w := 64
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var horizon := rng.randi_range(22, 32)
	var ridge := PackedFloat32Array()
	var y := float(horizon)
	for x in w:
		y = clampf(y + rng.randf_range(-1.6, 1.6), horizon - 9, horizon + 3)
		ridge.append(y)
	for py in h:
		for px in w:
			var c: Color
			if py < ridge[px]:
				c = Color(0.82, 0.8, 0.74).darkened(py / float(h) * 0.35)
			else:
				c = Color(0.18, 0.17, 0.15).lightened((py - ridge[px]) / float(h) * 0.5)
			c = c.darkened(rng.randf() * 0.12)
			img.set_pixel(px, py, c)
	return img


## A print that hasn't come up yet: a faint shape on the paper.
static func _ghost_image(i: int) -> Image:
	var img := _unseen_image("ghost%d" % i)
	for py in img.get_height():
		for px in img.get_width():
			img.set_pixel(px, py, img.get_pixel(px, py).lerp(PAPER, 0.75))
	return img


## The untaken print nearest `world_pos`, or {}.
func nearest(world_pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for p: Dictionary in takeable:
		if p.taken:
			continue
		var d := (p.node as Node3D).global_position.distance_to(world_pos)
		if d < best_d:
			best = p
			best_d = d
	return best


## Where a print's face is (world).
static func face_at(p: Dictionary) -> Vector3:
	return (p.node as Node3D).global_transform * Vector3(0, -0.03 - PRINT.y * 0.5, 0.0)
