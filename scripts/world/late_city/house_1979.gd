class_name House1979
extends Node3D
## The townhouse as the Dorans had it in July 1979 (OtherHouse, act 2): a
## brown corduroy sofa and an orange armchair, a shag rug, the fire lit, a
## wooden-cabinet telly, Mick's radio on the sideboard playing the midnight
## station, the clock stopped at twenty to three, a mustard kitchen with a
## round cream fridge and a child's drawings on it, the calendar on July,
## the laminex table with a cassette recorder on it, and upstairs two made
## beds and a little girl's room with its night light on.
##
## Built from boxes in the PS1 look, in the house's own frame (the model's
## Blender frame: x across, y back from the street, z up). Add it as a child
## of the HomeBase.

const BROWN := Color(0.4, 0.26, 0.14)
const CORDUROY := Color(0.36, 0.22, 0.11)
const ORANGE := Color(0.78, 0.4, 0.1)
const MUSTARD := Color(0.74, 0.56, 0.16)
const TEAK := Color(0.42, 0.24, 0.12)
const CREAM := Color(0.86, 0.8, 0.64)
const LAMINEX := Color(0.83, 0.79, 0.62)
const SHAG := Color(0.52, 0.34, 0.15)
const CHROME := Color(0.72, 0.72, 0.74)
const VINYL := Color(0.72, 0.36, 0.1)
const LAMP := Color(1.0, 0.62, 0.3)
const DRAWING := "res://art/models/home/shenton/shenton_interior_mystery_drawing.png"
const CASSETTE := "res://art/models/home/shenton/shenton_interior_mystery_cassette_label.png"

## Where the drawing on the fridge is (house frame), for taking it.
const DRAWING_AT := Vector3(2.5, 7.4, 1.2)
## The radio on the sideboard, for its sound.
const RADIO_AT := Vector3(3.6, 4.78, 0.98)

var lights: Array[OmniLight3D] = []
var fire: OmniLight3D
var tv_screen: MeshInstance3D
var drawing: MeshInstance3D
var _t := 0.0
var _screen_mat: ShaderMaterial


func _ready() -> void:
	name = "House1979"
	_lounge()
	_kitchen()
	_dining()
	_upstairs()


func _process(delta: float) -> void:
	_t += delta
	if fire:
		fire.light_energy = 1.1 + 0.25 * sin(_t * 7.3) + 0.15 * sin(_t * 13.1 + 1.0)
	if _screen_mat:
		var flick := 0.8 + 0.2 * sin(_t * 23.0) * sin(_t * 3.1)
		_screen_mat.set_shader_parameter("emission_energy", 0.9 * flick)


## A point in the house frame as a local position.
static func at(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


func _lounge() -> void:
	# The rug, the sofa against the far wall, an armchair by the window.
	_box(Vector3(2.0, 2.6, 0.03), Vector3(3.4, 2.9, 0.165), SHAG)
	_sofa(Vector3(4.9, 2.8, 0.15))
	_armchair(Vector3(2.4, 1.1, 0.15))
	# Coffee table: teak, low, an ashtray and a TV guide on it.
	_box(Vector3(0.6, 1.1, 0.06), Vector3(3.4, 2.9, 0.55), TEAK)
	for c: Vector2 in [Vector2(3.15, 2.42), Vector2(3.65, 2.42), Vector2(3.15, 3.38), Vector2(3.65, 3.38)]:
		_box(Vector3(0.05, 0.05, 0.38), Vector3(c.x, c.y, 0.34), TEAK)
	_box(Vector3(0.16, 0.16, 0.04), Vector3(3.3, 2.7, 0.6), Color(0.5, 0.55, 0.5))
	_box(Vector3(0.2, 0.28, 0.01), Vector3(3.5, 3.1, 0.585), Color(0.85, 0.82, 0.7))
	# The telly in its wooden cabinet, on, against the fireplace wall.
	_box(Vector3(0.62, 0.95, 0.75), Vector3(0.45, 4.15, 0.53), TEAK)
	tv_screen = _box(Vector3(0.02, 0.62, 0.45), Vector3(0.77, 4.12, 0.6), Color(0.5, 0.6, 0.66), 0.9)
	_screen_mat = tv_screen.material_override as ShaderMaterial
	_box(Vector3(0.02, 0.18, 0.5), Vector3(0.77, 4.12, 0.25), Color(0.25, 0.18, 0.1))
	# The fire, lit.
	fire = _light(Vector3(0.75, 2.4, 0.45), Color(1.0, 0.5, 0.2), 1.1, 4.5)
	_box(Vector3(0.06, 0.7, 0.4), Vector3(0.42, 2.4, 0.35), Color(1.0, 0.45, 0.12), 2.2)
	_box(Vector3(0.04, 0.85, 0.65), Vector3(0.6, 2.4, 0.48), Color(0.1, 0.1, 0.1))
	# The standard lamp with its orange shade, and the sideboard with the radio.
	_box(Vector3(0.05, 0.05, 1.4), Vector3(4.75, 0.55, 0.85), CHROME)
	_box(Vector3(0.45, 0.45, 0.35), Vector3(4.75, 0.55, 1.65), ORANGE, 0.8)
	lights.append(_light(Vector3(4.75, 0.55, 1.5), LAMP, 1.0, 5.0))
	_box(Vector3(1.5, 0.42, 0.65), Vector3(3.55, 4.72, 0.48), TEAK)
	_box(Vector3(0.36, 0.16, 0.2), RADIO_AT, Color(0.3, 0.2, 0.12))
	_box(Vector3(0.22, 0.01, 0.06), RADIO_AT + Vector3(0, -0.085, 0.03), Color(1.0, 0.75, 0.4), 1.6)
	_clock(Vector3(3.55, 4.93, 1.75))
	# Robyn's school bag at the foot of the stairs.
	_box(Vector3(0.3, 0.14, 0.34), Vector3(0.6, 9.5, 0.32), Color(0.65, 0.12, 0.1))
	# Mick's car keys aren't on the hook by the door.
	_box(Vector3(0.18, 0.03, 0.04), Vector3(0.12, 1.2, 1.5), TEAK)


func _kitchen() -> void:
	# Mustard cupboards with a cream laminex top, and the wall cupboards over.
	_box(Vector3(2.5, 0.6, 0.86), Vector3(4.15, 6.95, 0.58), MUSTARD)
	_box(Vector3(2.52, 0.63, 0.04), Vector3(4.15, 6.95, 1.03), LAMINEX)
	_box(Vector3(2.5, 0.36, 0.7), Vector3(4.15, 6.83, 1.9), MUSTARD)
	for x: float in [3.25, 3.85, 4.45, 5.05]:
		_box(Vector3(0.02, 0.01, 0.05), Vector3(x, 7.26, 0.85), CHROME)
	_box(Vector3(0.6, 1.0, 0.86), Vector3(5.08, 7.75, 0.58), MUSTARD)
	_box(Vector3(0.62, 1.02, 0.04), Vector3(5.08, 7.75, 1.03), LAMINEX)
	# A kettle on the bench, a pot plant on the sill.
	_box(Vector3(0.2, 0.2, 0.22), Vector3(4.8, 6.85, 1.16), CHROME)
	_box(Vector3(0.18, 0.18, 0.16), Vector3(5.1, 7.4, 1.13), Color(0.6, 0.3, 0.15))
	# The fridge: round-shouldered, cream, with a chrome handle.
	_box(Vector3(0.72, 0.7, 1.55), Vector3(2.5, 7.0, 0.93), CREAM)
	_box(Vector3(0.68, 0.66, 0.08), Vector3(2.5, 7.0, 1.74), CREAM)
	_box(Vector3(0.04, 0.03, 0.3), Vector3(2.8, 7.37, 1.15), CHROME)
	# Robyn's drawing on the front, and a couple of others.
	drawing = _picture(DRAWING, Vector3(0.3, 0.42, 0.0), Vector3(2.45, 7.37, 1.2))
	_box(Vector3(0.22, 0.005, 0.28), Vector3(2.32, 7.36, 1.55), Color(0.9, 0.88, 0.78))
	_box(Vector3(0.2, 0.005, 0.24), Vector3(2.66, 7.36, 1.58), Color(0.85, 0.9, 0.8))
	for p: Vector3 in [Vector3(2.45, 7.375, 1.42), Vector3(2.32, 7.375, 1.7), Vector3(2.66, 7.375, 1.71)]:
		_box(Vector3(0.04, 0.01, 0.04), p, ORANGE)
	# The calendar on July 1979 hung on the cupboard door, and the wall phone.
	_calendar(Vector3(3.3, 7.022, 1.9))
	_box(Vector3(0.06, 0.18, 0.26), Vector3(5.36, 8.3, 1.45), Color(0.82, 0.74, 0.58))
	# The tube light over the bench, a little green, the way they were.
	lights.append(_light(Vector3(4.0, 7.3, 2.3), Color(0.92, 1.0, 0.86), 0.7, 4.5))
	_box(Vector3(1.2, 0.08, 0.05), Vector3(4.0, 7.05, 2.32), Color(0.95, 1.0, 0.9), 1.5)


func _dining() -> void:
	# The laminex table on chrome legs, four orange vinyl chairs.
	_box(Vector3(0.85, 1.35, 0.04), Vector3(1.4, 10.6, 0.76), LAMINEX)
	for c: Vector2 in [Vector2(1.05, 10.0), Vector2(1.75, 10.0), Vector2(1.05, 11.2), Vector2(1.75, 11.2)]:
		_box(Vector3(0.04, 0.04, 0.6), Vector3(c.x, c.y, 0.45), CHROME)
	for c: Vector3 in [Vector3(0.75, 10.25, 0.0), Vector3(0.75, 10.95, 0.0), Vector3(2.05, 10.25, PI), Vector3(2.05, 10.95, PI)]:
		_chair(Vector3(c.x, c.y, 0.15), c.z)
	# Mick's cassette recorder on the table, and a cup of tea gone cold.
	_box(Vector3(0.28, 0.18, 0.06), Vector3(1.35, 10.5, 0.81), Color(0.08, 0.08, 0.08))
	_picture(CASSETTE, Vector3(0.1, 0.0, 0.065), Vector3(1.32, 10.5, 0.845), true)
	_box(Vector3(0.08, 0.08, 0.09), Vector3(1.6, 10.9, 0.83), CREAM)
	# A pendant lamp over the table.
	_box(Vector3(0.4, 0.4, 0.22), Vector3(1.4, 10.6, 2.0), ORANGE, 0.9)
	lights.append(_light(Vector3(1.4, 10.6, 1.8), LAMP, 0.9, 4.5))
	# A brown vinyl recliner by the back door.
	_box(Vector3(0.85, 0.85, 0.42), Vector3(4.5, 11.2, 0.36), BROWN)
	_box(Vector3(0.85, 0.2, 0.6), Vector3(4.5, 11.55, 0.85), BROWN)


func _upstairs() -> void:
	var up := 3.16
	# The front bedroom: a double bed with a candlewick spread.
	_box(Vector3(1.6, 2.0, 0.45), Vector3(4.3, 2.05, up + 0.23), Color(0.88, 0.84, 0.72))
	_box(Vector3(1.6, 0.08, 0.9), Vector3(4.3, 1.02, up + 0.45), TEAK)
	_box(Vector3(0.6, 0.55, 1.8), Vector3(0.35, 2.2, up + 0.9), TEAK)
	lights.append(_light(Vector3(3.0, 2.0, up + 2.2), LAMP, 0.35, 3.5))
	# Robyn's room at the back: a single bed with an orange spread, a doll, a
	# night light.
	_box(Vector3(0.9, 1.9, 0.42), Vector3(1.0, 10.6, up + 0.21), ORANGE)
	_box(Vector3(0.9, 0.06, 0.7), Vector3(1.0, 9.62, up + 0.38), Color(0.95, 0.9, 0.8))
	_box(Vector3(0.14, 0.1, 0.26), Vector3(1.0, 10.0, up + 0.55), Color(0.9, 0.7, 0.6))
	_box(Vector3(0.12, 0.08, 0.12), Vector3(2.4, 11.85, up + 0.4), Color(1.0, 0.85, 0.5), 2.0)
	lights.append(_light(Vector3(2.4, 11.6, up + 0.5), Color(1.0, 0.8, 0.5), 0.45, 3.0))
	_box(Vector3(0.9, 0.45, 0.7), Vector3(3.6, 11.7, up + 0.35), Color(0.55, 0.62, 0.8))


func _sofa(base: Vector3) -> void:
	_box(Vector3(0.85, 2.3, 0.42), base + Vector3(-0.1, 0, 0.21), CORDUROY)
	_box(Vector3(0.22, 2.3, 0.85), base + Vector3(0.3, 0, 0.42), CORDUROY)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.85, 0.2, 0.62), base + Vector3(-0.1, s * 1.2, 0.31), CORDUROY)
	for k in 3:
		_box(Vector3(0.6, 0.72, 0.12), base + Vector3(-0.18, -0.76 + k * 0.76, 0.48), Color(0.42, 0.26, 0.13))


func _armchair(base: Vector3) -> void:
	_box(Vector3(0.8, 0.8, 0.4), base + Vector3(0, 0, 0.2), ORANGE)
	_box(Vector3(0.8, 0.18, 0.85), base + Vector3(0, -0.36, 0.42), ORANGE)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.14, 0.8, 0.6), base + Vector3(s * 0.38, 0, 0.3), ORANGE)


func _chair(base: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.position = at(base)
	n.rotation.y = yaw
	add_child(n)
	_box(Vector3(0.42, 0.42, 0.06), Vector3(0, 0, 0.45), VINYL, 0.0, n)
	_box(Vector3(0.06, 0.42, 0.42), Vector3(-0.2, 0, 0.75), VINYL, 0.0, n)
	_box(Vector3(0.03, 0.38, 0.42), Vector3(0.0, 0, 0.22), CHROME, 0.0, n)


func _clock(p: Vector3) -> void:
	# A sunburst wall clock, stopped at twenty to three.
	var face := _box(Vector3(0.34, 0.03, 0.34), p, CREAM)
	face.name = "Clock_1979"
	for k in 12:
		var a := k * TAU / 12.0
		_box(Vector3(0.03, 0.02, 0.06), p + Vector3(sin(a) * 0.14, -0.02, cos(a) * 0.14), Color(0.7, 0.55, 0.2))
	_hand(p, deg_to_rad(80.0), 0.09)     # the hour hand, just short of three
	_hand(p, deg_to_rad(240.0), 0.14)    # the minute hand at eight: forty past


func _hand(p: Vector3, angle: float, length: float) -> void:
	var n := Node3D.new()
	n.position = at(p) + Vector3(0, 0, 0.03)
	add_child(n)
	var hand := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, length, 0.01)
	hand.mesh = box
	hand.material_override = _material(Color(0.1, 0.08, 0.06))
	hand.position = Vector3(0, length * 0.5, 0)
	n.rotation.z = -angle
	n.add_child(hand)


func _calendar(p: Vector3) -> void:
	_box(Vector3(0.36, 0.01, 0.5), p, Color(0.93, 0.9, 0.82))
	_box(Vector3(0.36, 0.012, 0.18), p + Vector3(0, 0, 0.17), Color(0.45, 0.6, 0.7))
	var month := Label3D.new()
	month.text = "JULY 1979"
	month.font_size = 40
	month.pixel_size = 0.0022
	month.modulate = Color(0.75, 0.15, 0.1)
	month.outline_size = 0
	month.shaded = true
	month.position = at(p + Vector3(0, 0.012, 0.03))
	month.rotation.y = PI  # the kitchen side of the wall
	add_child(month)
	var days := Label3D.new()
	days.text = "1  2  3  4  5  6  7\n8  9 10 11 12 13 14\n15 16 17 18 19 20 21\n22 23 24 25 26 27 28\n29 30 31"
	days.font_size = 20
	days.pixel_size = 0.0018
	days.modulate = Color(0.15, 0.12, 0.1)
	days.outline_size = 0
	days.shaded = true
	days.position = at(p + Vector3(0, 0.012, -0.11))
	days.rotation.y = PI
	add_child(days)
	# Wednesday the eleventh, ringed in biro.
	_box(Vector3(0.05, 0.004, 0.035), p + Vector3(0.035, 0.014, -0.073), Color(0.1, 0.2, 0.6))


## A flat picture facing +y (the back of the house), or lying flat when `flat`.
func _picture(path: String, size: Vector3, p: Vector3, flat := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.y if not flat else size.z)
	mi.mesh = quad
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var m := PS1Material.textured(tex) if tex else PS1Material.make(Color(0.9, 0.88, 0.8))
	mi.material_override = m
	mi.position = at(p)
	if flat:
		mi.rotation.x = -PI * 0.5
	else:
		mi.rotation.y = PI  # facing back into the house (+y), like the fridge door
	add_child(mi)
	return mi


func _light(p: Vector3, colour: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.position = at(p)
	add_child(l)
	return l


## A box `size` (house frame: across, back, up) centred on `p`.
func _box(size: Vector3, p: Vector3, colour: Color, glow := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.z, size.y)
	mi.mesh = box
	mi.material_override = _material(colour, glow)
	mi.position = at(p) if parent == null else Vector3(p.x, p.z, -p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


static func _material(colour: Color, glow := 0.0) -> ShaderMaterial:
	return PS1Material.glowing(colour, glow) if glow > 0.0 else PS1Material.make(colour)
