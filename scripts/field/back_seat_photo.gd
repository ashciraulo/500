class_name BackSeatPhoto
extends Node
## The photograph (docs/STORY.md, section 10): once the story sets
## `Story.flag(&"photo_back_seat")`, the next time you're driving a shutter
## clicks behind you, quietly. The lab's next roll comes back with one extra
## frame: you at the wheel, taken from the back seat. Ros offers to keep it.
##
## The shot is rendered from a camera in the back seat into its own little
## viewport, with a figure at the wheel that only that camera sees (you have
## no body in the car). The raw frame is saved straight away; the print look
## (FieldJournal.develop -> `print_look`) is applied at the lab, where a
## hitch can't be felt.

## Car-local: the back seat behind the passenger, looking forward past your
## left shoulder at the wheel, the dash and the road.
const EYE := Vector3(-0.14, 0.80, 1.02)
const LOOK_AT := Vector3(0.3, 0.62, -2.0)
const FOV := 60.0
## The frame is a 35 mm print: 3:2, at the lo-fi resolution.
const SIZE := Vector2i(360, 240)
## A render layer the game cameras never see, so the figure at the wheel is
## only ever in the photograph.
const LAYER := 1 << 19
## Drive this fast for this long before the shutter goes.
const MIN_SPEED := 5.0
const DRIVE_TIME := 4.0
## If you never drove, the lab takes it as it develops the roll, as long as
## the car's this close (so the street round it is loaded).
const LAB_REACH := 150.0
## The date stamp in the corner of the print, in the compact's orange LEDs.
const STAMP := "'79 7 11"
const SODIUM := Color(1.0, 0.7, 0.4)

const HAIR := Color("2e2520")
const SKIN := Color("b58466")
const JACKET := Color("3f4a52")
const SLEEVE := Color("36404a")

var _driving := 0.0
var _busy := false


func _process(delta: float) -> void:
	if _busy or not FieldJournal.back_seat_due():
		_driving = 0.0
		return
	var car := _car()
	if car == null or not _in_car(car) or car.linear_velocity.length() < MIN_SPEED:
		_driving = 0.0
		return
	_driving += delta
	if _driving >= DRIVE_TIME:
		_driving = 0.0
		take(car, true)


## Whether the lab can have it taken now: the car's parked near enough.
func can_take_now() -> bool:
	var car := _car()
	var cam := get_viewport().get_camera_3d()
	return car != null and (cam == null or cam.global_position.distance_to(car.global_position) < LAB_REACH)


## Take the photograph from `car`'s back seat now (the lab calls this if it's
## due and you never drove). `click`: the shutter goes off behind you.
func take(car: Node3D = null, click := false) -> void:
	if car == null:
		car = _car()
	if _busy or car == null or not FieldJournal.back_seat_due():
		return
	_busy = true
	if click and not _gentle():
		var audio := get_node_or_null(^"/root/Audio")
		if audio and audio.has("field/shutter"):
			audio.play_2d("field/shutter", "Cabin" if audio.is_player_driving() else "SFX", -15.0, 0.92)
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		image = await _render(car)
	var file := ""
	if image and not image.is_empty() and is_inside_tree():
		DirAccess.make_dir_recursive_absolute(Activities.PHOTO_DIR)
		file = "%s/day%03d_back_seat_raw.png" % [Activities.PHOTO_DIR, GameClock.day]
		image.save_png(file)
	FieldJournal.took_back_seat(file)
	_busy = false


## Render the back seat's view, with you at the wheel.
func _render(car: Node3D) -> Image:
	var figure := driver_figure()
	car.add_child(figure)
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	car.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.03
	cam.far = 2000.0
	vp.add_child(cam)
	cam.current = true
	# The car moves on between frames: the camera rides along (after physics,
	# before the frame's transforms go to the renderer) until it's drawn.
	var seat := Transform3D(Basis.looking_at(LOOK_AT - EYE), EYE)
	var ride := func() -> void:
		if is_instance_valid(cam) and is_instance_valid(car):
			cam.global_transform = car.global_transform * seat
	ride.call()
	get_tree().process_frame.connect(ride)
	# The game's own camera mustn't catch the figure, even for a frame.
	var main_cam := get_viewport().get_camera_3d()
	var mask := main_cam.cull_mask if main_cam else 0
	if main_cam:
		main_cam.cull_mask = mask & ~LAYER
	for i in 2:
		await RenderingServer.frame_post_draw
	get_tree().process_frame.disconnect(ride)
	var image: Image = vp.get_texture().get_image() if is_instance_valid(vp) else null
	if is_instance_valid(main_cam):
		main_cam.cull_mask = mask
	if is_instance_valid(vp):
		vp.queue_free()
	if is_instance_valid(figure):
		figure.queue_free()
	return image


## You at the wheel, from behind: hair, collar, shoulders, two arms to the
## wheel at ten to two. Car-local, around the DriverSeat eye (0.36, 0.72, 0.22).
static func driver_figure() -> Node3D:
	var root := Node3D.new()
	root.name = "BackSeatDriver"
	var x := 0.36
	_part(root, _sphere(0.105, 0.25), Vector3(x, 0.735, 0.27), HAIR)
	_part(root, _sphere(0.085, 0.17), Vector3(x, 0.70, 0.22), SKIN)  # the face side, mostly hidden
	_part(root, _cylinder(0.055, 0.12), Vector3(x, 0.60, 0.29), SKIN)
	var torso := _part(root, _box(Vector3(0.40, 0.50, 0.22)), Vector3(x, 0.32, 0.36), JACKET)
	torso.rotation.x = -0.12
	var shoulders := _part(root, _capsule(0.085, 0.46), Vector3(x, 0.53, 0.34), JACKET)
	shoulders.rotation.z = PI / 2.0
	_part(root, _cylinder(0.075, 0.06), Vector3(x, 0.575, 0.31), JACKET)  # the collar
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector3(x + side * 0.2, 0.52, 0.33)
		var elbow := Vector3(x + side * 0.24, 0.36, 0.06)
		var hand := Vector3(x + side * 0.16, 0.56, -0.34)
		_limb(root, shoulder, elbow, 0.06, SLEEVE)
		_limb(root, elbow, hand, 0.05, SLEEVE)
		_part(root, _sphere(0.038, 0.07), hand, SKIN)
	return root


static func _part(root: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = PS1Material.make(color, 1.0)
	m.layers = LAYER
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = at
	root.add_child(m)
	return m


static func _limb(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var m := _part(root, _capsule(radius, a.distance_to(b) + radius * 2.0), (a + b) / 2.0, color)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	m.basis = Basis(side, up, side.cross(up))


static func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 10
	s.rings = 6
	return s


static func _cylinder(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 8
	c.rings = 2
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## The print: faded blacks, the sodium-orange grade (the late city's look),
## grain, a dark edge, and the date stamp in the corner. `seed` keeps the
## grain the same if it's printed again.
static func print_look(src: Image, seed := 0) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var centre := Vector2(w, h) / 2.0
	var reach := centre.length()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var lum := c.get_luminance()
			# Half toward the street lights' orange, then the blacks lifted.
			c = c.lerp(SODIUM * (lum * 1.25), 0.45)
			c = c * 0.88 + Color(0.08, 0.06, 0.05)
			var edge := clampf((Vector2(x, y).distance_to(centre) / reach - 0.55) / 0.45, 0.0, 1.0)
			c = c.darkened(edge * edge * 0.55)
			var grain := rng.randf_range(-0.045, 0.045)
			img.set_pixel(x, y, Color(c.r + grain, c.g + grain, c.b + grain).clamp())
	_stamp(img, STAMP, Vector2i(w - 8, h - 8))
	return img


## 3 x 5 LED digits, two pixels a dot, right-aligned to `corner`.
const _GLYPHS := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
	"4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001010010010",
	"8": "111101111101111", "9": "111101111001111", "'": "010010000000000", " ": "000000000000000",
}


static func _stamp(img: Image, text: String, corner: Vector2i) -> void:
	var dot := 2
	var advance := 4 * dot
	var left := corner.x - text.length() * advance
	var top := corner.y - 5 * dot
	var core := Color(1.0, 0.55, 0.12)
	for i in text.length():
		var glyph: String = _GLYPHS.get(text[i], _GLYPHS[" "])
		for gy in 5:
			for gx in 3:
				if glyph[gy * 3 + gx] != "1":
					continue
				for py in dot:
					for px in dot:
						var p := Vector2i(left + i * advance + gx * dot + px, top + gy * dot + py)
						# A soft glow round each lit dot, then the dot.
						for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
							_blend(img, p + o, core, 0.35)
						_blend(img, p, core, 0.95)


static func _blend(img: Image, p: Vector2i, c: Color, amount: float) -> void:
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return
	img.set_pixelv(p, img.get_pixelv(p).lerp(c, amount))


func _car() -> RigidBody3D:
	return get_tree().get_first_node_in_group(&"player_car") as RigidBody3D


func _in_car(car: Node) -> bool:
	var p := car.get_parent().get_node_or_null(^"Player")
	return p == null or bool(p.get("in_car"))


func _gentle() -> bool:
	var story := get_node_or_null(^"/root/Story")
	return story != null and bool(story.call("gentle"))
