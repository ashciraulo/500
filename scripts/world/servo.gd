class_name Servo
extends Node3D
## A servo on the map: a pump bay under a canopy, a pump island and a price
## sign by the road. Pull into the bay, stop, and press F / A to fill up (a
## WorkshopSpot that sells fuel). Plain and unbranded. MapStreamer places one
## for each entry in data/world/servos.json (tools/places/place_servos.py
## picks the spots, and needs this layout's footprint kept in step).
##
## The frame: the bay runs along z, centred on the origin; the island and the
## canopy's posts are on its +x side.

const BAY := Vector2(5.0, 7.0)
const ISLAND := Rect2(2.9, -2.5, 1.2, 5.0)  # x, z, width, length
const ISLAND_HEIGHT := 0.15
const ROOF := Rect2(-3.5, -5.0, 9.5, 10.0)  # x, z, width, length
const ROOF_UNDERSIDE := 4.6
const ROOF_DEPTH := 0.7
const POSTS := [Vector2(3.5, -2.0), Vector2(3.5, 2.0)]
const SIGN := Vector2(5.8, 5.8)  # the price sign, at the corner by the road end
## Past this the canopy's light goes out and the small bits stop drawing.
const DETAIL_RANGE := 350.0

@export var spot_id := ""
@export var display_name := "Servo"
## The end of the bay you drive in at: +1 the +z end, -1 the -z end. The
## price sign stands there, by the road.
@export var open_end := 1
## The forecourt's height above this node on a 1 m grid over the footprint
## (GROUND_X by GROUND_Z points from GROUND_FROM, x fastest), from
## servos.json. Empty: flat.
@export var ground := PackedFloat32Array()

const GROUND_FROM := Vector2(-3.5, -6.5)
const GROUND_X := 11
const GROUND_Z := 14
## The slab sits this far over the ground; the bay's lines on top of it.
const SLAB_LIFT := 0.04

static var _materials := {}


func _ready() -> void:
	add_to_group(&"servos")
	var spot := WorkshopSpot.new()
	spot.name = "Bay"
	spot.spot_id = spot_id
	spot.display_name = display_name
	spot.kinds = PackedStringArray(["fuel"])
	spot.size = BAY
	spot.color = Color(0.95, 0.85, 0.4)
	# Lie the bay's lines on the slab: tilted with the ground under it.
	var sx := (_ground_at(BAY.x * 0.5, 0.0) - _ground_at(-BAY.x * 0.5, 0.0)) / BAY.x
	var sz := (_ground_at(0.0, BAY.y * 0.5) - _ground_at(0.0, -BAY.y * 0.5)) / BAY.y
	spot.basis = Basis.from_euler(Vector3(-atan(sz), 0.0, atan(sx)))
	spot.position.y = _ground_at(0.0, 0.0) + SLAB_LIFT
	add_child(spot)
	_build()


func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = MapTileLoader.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta(&"surface", &"concrete")
	add_child(body)
	# The pump island: a low kerb you can't miss, going down into the ground
	# so it never floats where the forecourt dips.
	_slab()
	var base := -INF
	for x in [ISLAND.position.x, ISLAND.end.x]:
		for z in [ISLAND.position.y, ISLAND.end.y]:
			base = maxf(base, _ground_at(x, z))
	var top := base + SLAB_LIFT + ISLAND_HEIGHT
	var island_size := Vector3(ISLAND.size.x, top - _lowest() + 0.3, ISLAND.size.y)
	var island_at := Vector3(ISLAND.position.x + ISLAND.size.x * 0.5, top - island_size.y * 0.5,
		ISLAND.position.y + ISLAND.size.y * 0.5)
	_box(island_size, island_at, &"island", body)
	# Two pumps.
	for z in [-1.2, 1.2]:
		var at := Vector3(ISLAND.position.x + ISLAND.size.x * 0.5, top, z)
		_box(Vector3(0.5, 1.6, 0.75), at + Vector3(0, 0.8, 0), &"pump", body)
		_box(Vector3(0.52, 0.12, 0.77), at + Vector3(0, 1.66, 0), &"stripe")
		for side in [-1.0, 1.0]:
			_box(Vector3(0.02, 0.35, 0.45), at + Vector3(side * 0.26, 1.2, 0), &"screen")
			# The nozzle in its holster and the hose looping down.
			_box(Vector3(0.08, 0.22, 0.08), at + Vector3(side * 0.29, 0.9, 0.22), &"rubber")
			_box(Vector3(0.04, 0.7, 0.04), at + Vector3(side * 0.3, 0.45, 0.3), &"rubber")
	# Posts up from the island, into the roof.
	for p: Vector2 in POSTS:
		var height := ROOF_UNDERSIDE - top + 0.2
		_box(Vector3(0.3, height, 0.3), Vector3(p.x, top + height * 0.5, p.y), &"post", body)
	# The canopy: a flat roof with a coloured band round its edge and a lit
	# underside.
	var roof_at := Vector3(ROOF.position.x + ROOF.size.x * 0.5, ROOF_UNDERSIDE + ROOF_DEPTH * 0.5,
		ROOF.position.y + ROOF.size.y * 0.5)
	_box(Vector3(ROOF.size.x, ROOF_DEPTH, ROOF.size.y), roof_at, &"canopy", body)
	_box(Vector3(ROOF.size.x + 0.04, ROOF_DEPTH * 0.45, ROOF.size.y + 0.04), roof_at, &"band")
	_box(Vector3(ROOF.size.x - 0.6, 0.04, ROOF.size.y - 0.6), Vector3(roof_at.x, ROOF_UNDERSIDE - 0.02, roof_at.z),
		&"glow")
	for side in [-1.0, 1.0]:
		var word := _label("SERVO", 72)
		word.position = Vector3(roof_at.x, roof_at.y, roof_at.z + side * (ROOF.size.y * 0.5 + 0.05))
		word.rotation.y = 0.0 if side > 0.0 else PI
		add_child(word)
	# The price sign, out by the road.
	var sign_z := SIGN.y * signf(open_end)
	var foot := _ground_at(SIGN.x, sign_z) - 0.3
	var pole := 5.0 - foot
	_box(Vector3(0.25, pole, 0.25), Vector3(SIGN.x, foot + pole * 0.5, sign_z), &"post", body)
	var board_at := Vector3(SIGN.x, 4.1, sign_z)
	_box(Vector3(0.3, 1.8, 1.4), board_at, &"band")
	for side in [-1.0, 1.0]:
		var title := _label("SERVO", 40)
		title.position = board_at + Vector3(side * 0.16, 0.5, 0)
		title.rotation.y = side * PI * 0.5
		add_child(title)
		var price := _label("", 48)
		price.name = "Price%d" % (1 if side > 0.0 else 0)
		price.modulate = Color(1.0, 0.75, 0.3)
		price.position = board_at + Vector3(side * 0.16, -0.25, 0)
		price.rotation.y = side * PI * 0.5
		add_child(price)
	_update_price()
	var clock := get_node_or_null(^"/root/GameClock")
	if clock:
		clock.connect(&"day_started", func(_day: int) -> void: _update_price())
	# Light under the canopy at night, only near the player.
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(roof_at.x - 1.5, ROOF_UNDERSIDE - 0.4, 0)
	light.omni_range = 9.0
	light.light_energy = 0.0
	light.light_color = Color(1.0, 0.95, 0.85)
	light.distance_fade_enabled = true
	light.distance_fade_begin = DETAIL_RANGE * 0.4
	light.distance_fade_length = 40.0
	light.add_to_group(&"servo_lights")
	add_child(light)


func _process(_delta: float) -> void:
	# The canopy lights come on at dusk.
	var clock := get_node_or_null(^"/root/GameClock")
	if clock == null:
		return
	var on: bool = clock.call("is_night")
	var light := get_node_or_null(^"Light") as OmniLight3D
	if light:
		light.light_energy = 1.6 if on else 0.0
	(_material(&"glow") as StandardMaterial3D).emission_energy_multiplier = 1.4 if on else 0.15


## The forecourt: a concrete slab laid over the ground, a little above it.
func _slab() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for j in GROUND_Z:
		for i in GROUND_X:
			var x := GROUND_FROM.x + i
			var z := GROUND_FROM.y + j
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, _ground_at(x, z) + SLAB_LIFT, z))
	for j in GROUND_Z - 1:
		for i in GROUND_X - 1:
			var a := j * GROUND_X + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + GROUND_X)
			st.add_index(a + 1)
			st.add_index(a + GROUND_X + 1)
			st.add_index(a + GROUND_X)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Slab"
	mesh.mesh = st.commit()
	mesh.material_override = _material(&"slab")
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


## The ground's height above this node at local x/z (bilinear on `ground`).
func _ground_at(x: float, z: float) -> float:
	if ground.size() != GROUND_X * GROUND_Z:
		return 0.0
	var fx := clampf(x - GROUND_FROM.x, 0.0, GROUND_X - 1.001)
	var fz := clampf(z - GROUND_FROM.y, 0.0, GROUND_Z - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(ground[j * GROUND_X + i], ground[j * GROUND_X + i + 1], tx)
	var b := lerpf(ground[(j + 1) * GROUND_X + i], ground[(j + 1) * GROUND_X + i + 1], tx)
	return lerpf(a, b, tz)


func _lowest() -> float:
	var low := 0.0
	for v in ground:
		low = minf(low, v)
	return low


func _update_price() -> void:
	var garage := get_node_or_null(^"/root/Garage")
	if garage == null:
		return
	var text := "$%.2f" % float(garage.call("fuel_price"))
	for n in ["Price0", "Price1"]:
		var label := get_node_or_null(NodePath(n)) as Label3D
		if label:
			label.text = text


func _box(size: Vector3, at: Vector3, material: StringName, body: StaticBody3D = null) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(material)
	mesh.position = at
	if size.length() < 3.0:
		mesh.visibility_range_end = DETAIL_RANGE
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	if body:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = at
		body.add_child(shape)


func _label(text: String, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.01
	label.outline_size = 0
	label.modulate = Color(1, 1, 1)
	label.double_sided = false
	label.shaded = false
	label.visibility_range_end = DETAIL_RANGE
	return label


## One material per part, shared by every servo.
static func _material(part: StringName) -> Material:
	if _materials.has(part):
		return _materials[part]
	var colors := {
		&"island": Color(0.72, 0.72, 0.68), &"pump": Color(0.9, 0.9, 0.86), &"stripe": Color(0.18, 0.55, 0.52),
		&"screen": Color(0.08, 0.1, 0.12), &"rubber": Color(0.1, 0.1, 0.1), &"post": Color(0.85, 0.85, 0.82),
		&"canopy": Color(0.92, 0.92, 0.9), &"band": Color(0.18, 0.55, 0.52), &"glow": Color(0.95, 0.95, 0.9),
		&"slab": Color(0.66, 0.66, 0.63),
	}
	var m := StandardMaterial3D.new()
	m.albedo_color = colors.get(part, Color.WHITE)
	m.roughness = 0.9
	if part == &"glow":
		m.emission_enabled = true
		m.emission = Color(1.0, 0.97, 0.88)
		m.emission_energy_multiplier = 0.15
	_materials[part] = m
	return m
