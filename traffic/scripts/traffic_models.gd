class_name TrafficModels
extends RefCounted
## Low-poly meshes for traffic, built in code so they stay tiny and match the
## PS1 look: cars, utes, vans, Transperth buses, train carriages, people and
## street furniture (traffic lights, boom gates).
##
## Every vehicle mesh has the same surface layout, so the traffic manager can
## repaint and light any of them by swapping surface materials:
##   0 paint, 1 glass and trim, 2 tyres, 3 headlights, 4 tail lights,
##   5 left indicators, 6 right indicators, 7 livery (second colour).
## Vehicles face -Z (Godot's forward) with the ground at y = 0.
##
## To swap in Blender models later, give a type a `scene` in TYPES with the
## same node contract (see docs/TRAFFIC.md).

enum Surf { PAINT, GLASS, TYRES, HEAD, TAIL, IND_L, IND_R, LIVERY }
const SURFACE_COUNT := 8

## Vehicle types. weight: how common; length/width for spacing and collision.
const TYPES := {
	&"hatch": { "weight": 26.0, "length": 4.0, "width": 1.75, "height": 1.5 },
	&"sedan": { "weight": 28.0, "length": 4.7, "width": 1.82, "height": 1.45 },
	&"suv": { "weight": 18.0, "length": 4.7, "width": 1.9, "height": 1.75 },
	&"ute": { "weight": 14.0, "length": 5.3, "width": 1.9, "height": 1.82 },
	&"van": { "weight": 7.0, "length": 4.9, "width": 1.9, "height": 2.0 },
	&"bus": { "weight": 0.0, "length": 12.5, "width": 2.5, "height": 3.15 },
	# Emergency services (never picked at random; see TrafficManager.EMERGENCY).
	&"police": { "weight": 0.0, "length": 4.9, "width": 1.85, "height": 1.55 },
	&"ambulance": { "weight": 0.0, "length": 6.2, "width": 2.05, "height": 2.7 },
	&"fire": { "weight": 0.0, "length": 8.4, "width": 2.5, "height": 3.2 },
	# Someone on a bike, riding near the kerb (see TrafficManager.bike_share).
	&"bike": { "weight": 0.0, "length": 1.8, "width": 0.65, "height": 1.75 },
}

## Jerseys for cyclists (the LIVERY surface).
const JERSEYS := [Color(0.9, 0.2, 0.15), Color(0.1, 0.3, 0.75), Color(0.95, 0.8, 0.1), Color(0.15, 0.15, 0.17),
	Color(0.95, 0.95, 0.93), Color(0.2, 0.6, 0.3), Color(0.95, 0.45, 0.1), Color(0.55, 0.25, 0.6)]

## Emergency liveries: [body paint, livery band].
const EMERGENCY_PAINT := {
	&"police": [Color(0.94, 0.94, 0.93), Color(0.08, 0.16, 0.55)],
	&"ambulance": [Color(0.95, 0.95, 0.93), Color(0.95, 0.8, 0.05)],
	&"fire": [Color(0.75, 0.06, 0.04), Color(0.92, 0.92, 0.88)],
}

## Perth's car park: lots of white and silver, a few bold ones.
const PAINTS := [
	[Color(0.92, 0.92, 0.9), 22.0], [Color(0.7, 0.72, 0.74), 16.0], [Color(0.42, 0.43, 0.45), 13.0],
	[Color(0.08, 0.08, 0.09), 12.0], [Color(0.13, 0.2, 0.38), 8.0], [Color(0.6, 0.08, 0.07), 7.0],
	[Color(0.75, 0.72, 0.62), 4.0], [Color(0.18, 0.3, 0.2), 3.0], [Color(0.82, 0.5, 0.12), 2.0],
	[Color(0.3, 0.55, 0.78), 3.0], [Color(0.55, 0.15, 0.3), 2.0], [Color(0.85, 0.78, 0.2), 1.0],
]

const BUS_SILVER := Color(0.78, 0.8, 0.82)
const TRANSPERTH_GREEN := Color(0.0, 0.42, 0.3)
## Free CAT buses in the city, each route with its own colour.
const CAT_COLOURS := [Color(0.1, 0.35, 0.8), Color(0.82, 0.12, 0.1), Color(0.95, 0.75, 0.05), Color(0.1, 0.6, 0.25)]

static var _meshes := {}
static var _materials := {}


static func material(color: Color, glow := 0.0) -> ShaderMaterial:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if not _materials.has(key):
		_materials[key] = PS1Material.glowing(color, glow) if glow > 0.0 else PS1Material.make(color, 0.55)
	return _materials[key]


static func pick_paint(rng: RandomNumberGenerator) -> Color:
	var total := 0.0
	for p in PAINTS:
		total += p[1]
	var r := rng.randf() * total
	for p in PAINTS:
		r -= p[1]
		if r <= 0.0:
			return p[0]
	return PAINTS[0][0]


static func vehicle_mesh(type: StringName) -> ArrayMesh:
	if not _meshes.has(type):
		_meshes[type] = _build_vehicle(type)
	return _meshes[type]


static func carriage_mesh(cab_front: bool, cab_rear: bool) -> ArrayMesh:
	var key := "carriage/%s/%s" % [cab_front, cab_rear]
	if not _meshes.has(key):
		_meshes[key] = _build_carriage(cab_front, cab_rear)
	return _meshes[key]


# --- Vehicles -----------------------------------------------------------------

static func _build_vehicle(type: StringName) -> ArrayMesh:
	var b := Builder.new()
	var info: Dictionary = TYPES[type]
	var L: float = info.length
	var W: float = info.width
	match type:
		&"hatch":
			_car(b, L, W, 0.62, 0.62, 2.2, 0.35, 0.9, 0.55)
		&"sedan":
			_car(b, L, W, 0.6, 0.58, 2.4, 0.15, 0.85, 0.55)
		&"suv":
			_car(b, L, W, 0.82, 0.7, 2.7, 0.3, 0.9, 0.7)
		&"ute":
			_ute(b, L, W)
		&"van":
			_van(b, L, W)
		&"bus":
			_bus(b, L, W)
		&"police":
			_car(b, L, W, 0.6, 0.58, 2.4, 0.15, 0.85, 0.55)
			# Chequered band along the doors, done as one blue stripe.
			b.box(Surf.LIVERY, Vector3(0, 0.3 + 0.38, 0.0), Vector3(W + 0.03, 0.2, L * 0.82))
			_light_bar_base(b, W, 0.3 + 0.6 + 0.58 + 0.06, 0.2)
		&"ambulance":
			_ambulance(b, L, W)
		&"fire":
			_fire_truck(b, L, W)
		&"bike":
			_bike(b, L)
	return b.commit()


## A bicycle and its rider: frame and helmet in the paint, jersey in the
## livery, dark lycra and gloves, small front and rear lamps.
static func _bike(b: Builder, L: float) -> void:
	var r := 0.34
	var wb := L * 0.5 - r
	b.wheel(Surf.TYRES, Vector3(0, r, -wb), r, 0.05)
	b.wheel(Surf.TYRES, Vector3(0, r, wb), r, 0.05)
	# Frame: top tube, down tube, seat post, bars.
	b.box(Surf.PAINT, Vector3(0, 0.78, 0.0), Vector3(0.05, 0.05, wb * 1.3))
	b.box(Surf.PAINT, Vector3(0, 0.56, -0.12), Vector3(0.05, 0.42, 0.05))
	b.box(Surf.PAINT, Vector3(0, 0.62, -wb + 0.05), Vector3(0.05, 0.5, 0.05))
	b.box(Surf.GLASS, Vector3(0, 0.98, -wb + 0.1), Vector3(0.44, 0.04, 0.05))
	# Rider: legs down to the pedals, torso leaning over the bars, head.
	for side in [-1.0, 1.0]:
		b.box(Surf.GLASS, Vector3(side * 0.11, 0.62, 0.15), Vector3(0.12, 0.62, 0.14))
		b.box(Surf.GLASS, Vector3(side * 0.17, 1.12, -0.32), Vector3(0.08, 0.42, 0.08))
	b.box(Surf.LIVERY, Vector3(0, 1.24, -0.12), Vector3(0.38, 0.32, 0.62), Vector2(0.85, 0.9))
	b.box(Surf.GLASS, Vector3(0, 1.48, -0.46), Vector3(0.18, 0.2, 0.2))
	b.box(Surf.PAINT, Vector3(0, 1.6, -0.44), Vector3(0.24, 0.1, 0.3))
	b.box(Surf.HEAD, Vector3(0, 0.92, -wb - 0.02), Vector3(0.08, 0.06, 0.04))
	b.box(Surf.TAIL, Vector3(0, 0.8, wb * 0.6), Vector3(0.07, 0.06, 0.04))


## The dark base under a light bar (the lamps themselves are separate
## meshes so they can flash: see light_bar()).
static func _light_bar_base(b: Builder, W: float, y: float, z: float) -> void:
	b.box(Surf.GLASS, Vector3(0, y + 0.04, z), Vector3(W * 0.7, 0.08, 0.3))


## St John-style ambulance: a big white box behind a van cab, yellow band.
static func _ambulance(b: Builder, L: float, W: float) -> void:
	var y0 := 0.4
	var cab := 1.9
	b.box(Surf.PAINT, Vector3(0, y0 + 0.55, -L * 0.5 + cab * 0.5), Vector3(W * 0.95, 1.1, cab), Vector2(0.95, 0.8))
	b.box(Surf.GLASS, Vector3(0, y0 + 1.35, -L * 0.5 + cab * 0.5 + 0.2), Vector3(W * 0.9, 0.55, cab - 0.6), Vector2(0.9, 0.7))
	var box_len := L - cab
	var bz := L * 0.5 - box_len * 0.5
	b.box(Surf.PAINT, Vector3(0, y0 + 1.15, bz), Vector3(W, 2.1, box_len))
	b.box(Surf.LIVERY, Vector3(0, y0 + 0.75, 0.0), Vector3(W + 0.03, 0.3, L - 0.3))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.1, -L * 0.5 - 0.02), Vector3(W * 0.98, 0.22, 0.12))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.1, L * 0.5 + 0.02), Vector3(W * 0.98, 0.22, 0.12))
	_wheels(b, L, W, 0.36, L * 0.5 - 1.0, -L * 0.5 + 1.1)
	_lamps(b, L, W, y0 + 0.55, false)
	_light_bar_base(b, W, y0 + 1.9, -L * 0.5 + cab * 0.5 + 0.1)


## DFES fire truck: red, white band, a ladder on the roof.
static func _fire_truck(b: Builder, L: float, W: float) -> void:
	var y0 := 0.5
	var cab := 2.3
	b.box(Surf.PAINT, Vector3(0, y0 + 1.0, -L * 0.5 + cab * 0.5), Vector3(W, 2.0, cab))
	b.box(Surf.GLASS, Vector3(0, y0 + 1.45, -L * 0.5 - 0.01), Vector3(W * 0.9, 0.7, 0.04))
	b.box(Surf.GLASS, Vector3(0, y0 + 1.45, -L * 0.5 + cab * 0.5), Vector3(W + 0.02, 0.6, cab * 0.7))
	var body_len := L - cab - 0.1
	var bz := L * 0.5 - body_len * 0.5
	b.box(Surf.PAINT, Vector3(0, y0 + 1.1, bz), Vector3(W, 2.2, body_len))
	b.box(Surf.LIVERY, Vector3(0, y0 + 0.55, 0.0), Vector3(W + 0.03, 0.22, L - 0.2))
	# Roller doors (dark panels) and the roof ladder.
	for i in 3:
		var z := bz - body_len * 0.5 + body_len * (i + 0.5) / 3.0
		b.box(Surf.GLASS, Vector3(0, y0 + 1.25, z), Vector3(W + 0.04, 1.3, body_len / 3.0 - 0.3))
	for side in [-1.0, 1.0]:
		b.box(Surf.TYRES, Vector3(side * 0.35, y0 + 2.35, bz), Vector3(0.08, 0.1, body_len - 0.3))
	for i in 8:
		b.box(Surf.TYRES, Vector3(0, y0 + 2.35, bz - body_len * 0.45 + i * body_len * 0.9 / 7.0), Vector3(0.7, 0.06, 0.06))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.15, -L * 0.5 - 0.03), Vector3(W * 0.98, 0.3, 0.14))
	_wheels(b, L, W, 0.5, L * 0.5 - 1.5, -L * 0.5 + 1.4)
	_lamps(b, L, W, y0 + 0.6, true)
	_light_bar_base(b, W, y0 + 2.0, -L * 0.5 + cab * 0.5)


## Where each emergency type's light bar sits: [height, z].
const LIGHT_BAR := {
	&"police": [1.58, 0.2],
	&"ambulance": [2.38, -2.0],
	&"fire": [2.58, -3.05],
}


## A red/blue light bar for an emergency vehicle: two lamps named Red and
## Blue, which TrafficManager flashes.
static func light_bar(type: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "LightBar"
	var spot: Array = LIGHT_BAR[type]
	var w: float = TYPES[type].width
	root.position = Vector3(0, spot[0], spot[1])
	var names := ["Red", "Blue"]
	for i in 2:
		var lamp := _add_part(root, "lb_lamp", Vector3(w * 0.32, 0.14, 0.26), Vector3((i * 2 - 1) * w * 0.17, 0, 0), Vector3.ZERO, null)
		lamp.name = names[i]
		lamp.visibility_range_end = 420.0
	return root


const BAR_COLOURS := [Color(1.0, 0.08, 0.05), Color(0.1, 0.25, 1.0)]


static func bar_material(index: int, lit: bool) -> Material:
	var c: Color = BAR_COLOURS[index]
	return material(c, 4.0) if lit else material(c.darkened(0.7))


## A car: lower body, glass cabin with a painted roof, wheels and lamps.
## body_h/cabin_h: heights; cabin_len and cabin_shift (towards the back) place
## the glasshouse; taper narrows its top; clearance is the body's ride height.
static func _car(b: Builder, L: float, W: float, body_h: float, cabin_h: float, cabin_len: float, cabin_shift: float, taper: float, clearance_wheel: float) -> void:
	var y0 := 0.3
	var wheel_r := 0.32 if L < 4.5 else 0.35
	b.box(Surf.PAINT, Vector3(0, y0 + body_h * 0.5, 0), Vector3(W, body_h, L), Vector2(0.97, 0.98))
	# Bonnet slope at the nose.
	b.box(Surf.PAINT, Vector3(0, y0 + body_h * 0.35, -L * 0.5 + 0.12), Vector3(W * 0.96, body_h * 0.7, 0.3), Vector2(0.95, 0.6))
	var cy := y0 + body_h + cabin_h * 0.5
	b.box(Surf.GLASS, Vector3(0, cy, cabin_shift), Vector3(W * 0.92, cabin_h, cabin_len), Vector2(taper, 0.62))
	b.box(Surf.PAINT, Vector3(0, y0 + body_h + cabin_h + 0.03, cabin_shift + 0.05), Vector3(W * 0.92 * taper, 0.06, cabin_len * 0.6))
	# Bumpers.
	b.box(Surf.GLASS, Vector3(0, y0 + 0.12, -L * 0.5 - 0.03), Vector3(W * 0.98, 0.22, 0.12))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.12, L * 0.5 + 0.03), Vector3(W * 0.98, 0.22, 0.12))
	_wheels(b, L, W, wheel_r, L * 0.5 - 0.75)
	_lamps(b, L, W, y0 + body_h * 0.62, false)


static func _ute(b: Builder, L: float, W: float) -> void:
	var y0 := 0.42
	var body_h := 0.62
	var cab_len := 2.5
	var cab_z := -L * 0.5 + 0.9 + cab_len * 0.5
	# Nose and cab.
	b.box(Surf.PAINT, Vector3(0, y0 + body_h * 0.5, -L * 0.5 + (cab_len + 0.9) * 0.5), Vector3(W, body_h, cab_len + 0.9))
	b.box(Surf.GLASS, Vector3(0, y0 + body_h + 0.33, cab_z + 0.25), Vector3(W * 0.92, 0.66, cab_len - 0.5), Vector2(0.9, 0.7))
	b.box(Surf.PAINT, Vector3(0, y0 + body_h + 0.69, cab_z + 0.3), Vector3(W * 0.82, 0.06, cab_len * 0.45))
	# Tray with low sides.
	var tray_len := L - cab_len - 0.9
	var tz := L * 0.5 - tray_len * 0.5
	b.box(Surf.GLASS, Vector3(0, y0 + 0.35, tz), Vector3(W, 0.12, tray_len))
	for side in [-1.0, 1.0]:
		b.box(Surf.PAINT, Vector3(side * (W * 0.5 - 0.05), y0 + 0.62, tz), Vector3(0.1, 0.45, tray_len))
	b.box(Surf.PAINT, Vector3(0, y0 + 0.62, L * 0.5 - 0.05), Vector3(W, 0.45, 0.1))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.1, -L * 0.5 - 0.03), Vector3(W * 0.98, 0.25, 0.14))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.1, L * 0.5 + 0.03), Vector3(W * 0.98, 0.2, 0.12))
	# Bull bar, because Perth.
	b.box(Surf.GLASS, Vector3(0, y0 + 0.35, -L * 0.5 - 0.15), Vector3(W * 0.7, 0.55, 0.08))
	_wheels(b, L, W, 0.38, L * 0.5 - 0.95)
	_lamps(b, L, W, y0 + body_h * 0.6, false)


static func _van(b: Builder, L: float, W: float) -> void:
	var y0 := 0.35
	var h := 1.62
	b.box(Surf.PAINT, Vector3(0, y0 + h * 0.5, 0.1), Vector3(W, h, L - 0.2), Vector2(0.96, 0.97))
	b.box(Surf.PAINT, Vector3(0, y0 + 0.4, -L * 0.5 + 0.15), Vector3(W * 0.97, 0.8, 0.35), Vector2(1.0, 0.5))
	# Window band and a raked windscreen.
	b.box(Surf.GLASS, Vector3(0, y0 + h * 0.74, -0.4), Vector3(W + 0.02, h * 0.3, L - 1.6))
	b.box(Surf.GLASS, Vector3(0, y0 + h * 0.72, -L * 0.5 + 0.38), Vector3(W * 0.9, h * 0.38, 0.12))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.1, -L * 0.5 - 0.02), Vector3(W * 0.98, 0.22, 0.12))
	b.box(Surf.GLASS, Vector3(0, y0 + 0.1, L * 0.5 + 0.02), Vector3(W * 0.98, 0.22, 0.12))
	_wheels(b, L, W, 0.33, L * 0.5 - 0.8)
	_lamps(b, L, W, y0 + 0.55, false)


## Transperth bus: silver body, dark window band, green skirt (the livery).
static func _bus(b: Builder, L: float, W: float) -> void:
	var y0 := 0.32
	var h := 2.85
	b.box(Surf.PAINT, Vector3(0, y0 + h * 0.5, 0), Vector3(W, h, L), Vector2(0.98, 0.995))
	b.box(Surf.GLASS, Vector3(0, y0 + h * 0.66, 0.2), Vector3(W + 0.02, h * 0.38, L - 1.2))
	b.box(Surf.GLASS, Vector3(0, y0 + h * 0.6, -L * 0.5 - 0.01), Vector3(W * 0.9, h * 0.6, 0.04))
	b.box(Surf.LIVERY, Vector3(0, y0 + 0.4, 0), Vector3(W + 0.03, 0.55, L + 0.02))
	# Destination sign above the windscreen.
	b.box(Surf.HEAD, Vector3(0, y0 + h - 0.22, -L * 0.5 - 0.02), Vector3(W * 0.7, 0.24, 0.04))
	b.box(Surf.GLASS, Vector3(0, y0 + h + 0.12, 1.0), Vector3(W * 0.6, 0.24, 2.4))
	_wheels(b, L, W, 0.5, L * 0.5 - 2.2, -L * 0.5 + 2.6)
	_lamps(b, L, W, y0 + 0.75, true)


static func _wheels(b: Builder, L: float, W: float, r: float, front_z: float, rear_z := INF) -> void:
	if rear_z == INF:
		rear_z = -front_z
	for side in [-1.0, 1.0]:
		for z in [-front_z, -rear_z]:
			b.wheel(Surf.TYRES, Vector3(side * (W * 0.5 - 0.12), r, z), r, 0.24)


static func _lamps(b: Builder, L: float, W: float, y: float, big: bool) -> void:
	var lw := 0.34 if big else 0.28
	var lh := 0.2 if big else 0.14
	for side in [-1.0, 1.0]:
		var x: float = side * (W * 0.5 - lw * 0.5 - 0.08)
		b.box(Surf.HEAD, Vector3(x, y, -L * 0.5 - 0.02), Vector3(lw, lh, 0.06))
		b.box(Surf.TAIL, Vector3(x, y + 0.05, L * 0.5 + 0.02), Vector3(lw, lh * 1.2, 0.06))
		var ind: int = Surf.IND_L if side < 0.0 else Surf.IND_R
		var ix: float = side * (W * 0.5 - 0.04)
		b.box(ind, Vector3(ix, y - lh, -L * 0.5 - 0.02), Vector3(0.1, 0.08, 0.06))
		b.box(ind, Vector3(ix, y - lh * 0.4, L * 0.5 + 0.02), Vector3(0.1, 0.08, 0.06))
		b.box(ind, Vector3(side * (W * 0.5 + 0.01), y, -L * 0.5 + 0.7), Vector3(0.03, 0.06, 0.14))


# --- Trains -------------------------------------------------------------------

const CARRIAGE_LENGTH := 23.0
const CARRIAGE_WIDTH := 3.0

## Transperth B-series style carriage: white body, black window band, cab
## ends with a sloped nose, pantograph on top.
static func _build_carriage(cab_front: bool, cab_rear: bool) -> ArrayMesh:
	var b := Builder.new()
	var L := CARRIAGE_LENGTH
	var W := CARRIAGE_WIDTH
	var y0 := 1.05
	var h := 2.85
	var body_len := L - (1.2 if cab_front else 0.0) - (1.2 if cab_rear else 0.0)
	var body_z := (1.2 if cab_front else 0.0) * 0.5 - (1.2 if cab_rear else 0.0) * 0.5
	b.box(Surf.PAINT, Vector3(0, y0 + h * 0.5, body_z), Vector3(W, h, body_len), Vector2(0.94, 1.0))
	b.box(Surf.GLASS, Vector3(0, y0 + h * 0.62, body_z), Vector3(W + 0.02, h * 0.34, body_len - 1.0))
	b.box(Surf.LIVERY, Vector3(0, y0 + 0.35, body_z), Vector3(W + 0.03, 0.22, body_len - 0.4))
	# Doors: dark slots along both sides.
	for i in 4:
		var z := -L * 0.5 + 3.0 + i * (L - 6.0) / 3.0
		b.box(Surf.GLASS, Vector3(0, y0 + h * 0.45, z), Vector3(W + 0.04, h * 0.75, 1.3))
	for end in [[cab_front, -1.0], [cab_rear, 1.0]]:
		if not end[0]:
			continue
		var s: float = end[1]
		var z: float = s * (L * 0.5 - 0.6)
		b.box(Surf.PAINT, Vector3(0, y0 + h * 0.35, z), Vector3(W * 0.96, h * 0.7, 1.2), Vector2(0.9, 0.95))
		b.box(Surf.GLASS, Vector3(0, y0 + h * 0.78, z - s * 0.1), Vector3(W * 0.86, h * 0.36, 1.0), Vector2(0.85, 0.4))
		var lamp: int = Surf.HEAD if s < 0.0 else Surf.TAIL
		for side in [-1.0, 1.0]:
			b.box(lamp, Vector3(side * W * 0.32, y0 + h * 0.3, s * (L * 0.5 + 0.01)), Vector3(0.35, 0.18, 0.05))
	# Bogies and pantograph.
	for z in [-L * 0.5 + 3.2, L * 0.5 - 3.2]:
		b.box(Surf.TYRES, Vector3(0, 0.55, z), Vector3(W * 0.8, 0.8, 2.8))
	b.box(Surf.TYRES, Vector3(0, y0 + h + 0.15, -L * 0.25), Vector3(1.6, 0.25, 2.4))
	b.box(Surf.GLASS, Vector3(0, y0 + h + 0.7, -L * 0.25), Vector3(1.8, 0.06, 0.25), Vector2(1.0, 1.0))
	b.box(Surf.GLASS, Vector3(0, y0 + h + 0.45, -L * 0.25 + 0.3), Vector3(0.08, 0.6, 0.08))
	return b.commit()


# --- People -------------------------------------------------------------------

const SKIN := [Color(0.94, 0.78, 0.66), Color(0.86, 0.66, 0.5), Color(0.66, 0.46, 0.32), Color(0.45, 0.3, 0.2), Color(0.3, 0.2, 0.14)]
const HAIR := [Color(0.08, 0.06, 0.05), Color(0.3, 0.2, 0.1), Color(0.6, 0.45, 0.25), Color(0.8, 0.7, 0.45), Color(0.6, 0.6, 0.6)]
const SHIRTS := [Color(0.9, 0.9, 0.88), Color(0.15, 0.15, 0.17), Color(0.25, 0.35, 0.6), Color(0.7, 0.2, 0.2),
	Color(0.85, 0.7, 0.3), Color(0.35, 0.55, 0.4), Color(0.55, 0.4, 0.6), Color(0.95, 0.55, 0.45), Color(0.4, 0.6, 0.75)]
const PANTS := [Color(0.15, 0.18, 0.3), Color(0.1, 0.1, 0.1), Color(0.55, 0.5, 0.4), Color(0.35, 0.35, 0.38), Color(0.2, 0.3, 0.45)]
const UMBRELLAS := [Color(0.1, 0.1, 0.12), Color(0.6, 0.1, 0.1), Color(0.15, 0.25, 0.55), Color(0.85, 0.75, 0.2), Color(0.3, 0.5, 0.3)]

static func _part_mesh(key: String, size: Vector3, offset: Vector3) -> ArrayMesh:
	if not _meshes.has(key):
		var b := Builder.new(1)
		b.box(0, offset, size)
		_meshes[key] = b.commit()
	return _meshes[key]


## A walking person: torso, head, hair, swinging arms and legs. Returns the
## root; limbs are named LegL/LegR/ArmL/ArmR (pivot at the hip/shoulder).
static func person(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var scale := rng.randf_range(0.9, 1.08)
	var shirt := material(SHIRTS[rng.randi() % SHIRTS.size()])
	var pants := material(PANTS[rng.randi() % PANTS.size()])
	var skin := material(SKIN[rng.randi() % SKIN.size()])
	var hair := material(HAIR[rng.randi() % HAIR.size()])
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * scale
	root.add_child(body)
	_add_part(body, "torso", Vector3(0.42, 0.62, 0.24), Vector3(0, 1.17, 0), Vector3.ZERO, shirt)
	_add_part(body, "head", Vector3(0.22, 0.26, 0.24), Vector3(0, 1.62, 0), Vector3.ZERO, skin)
	var long_hair := rng.randf() < 0.4
	_add_part(body, "hair_long" if long_hair else "hair", Vector3(0.24, 0.32 if long_hair else 0.1, 0.26), Vector3(0, 1.66 if long_hair else 1.76, 0.02), Vector3.ZERO, hair)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		leg.position = Vector3(side * 0.11, 0.86, 0)
		body.add_child(leg)
		_add_part(leg, "leg", Vector3(0.16, 0.86, 0.18), Vector3(0, -0.43, 0), Vector3.ZERO, pants)
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0.0 else "ArmR"
		arm.position = Vector3(side * 0.27, 1.45, 0)
		body.add_child(arm)
		_add_part(arm, "arm", Vector3(0.11, 0.6, 0.12), Vector3(0, -0.3, 0), Vector3.ZERO, shirt)
		_add_part(arm, "hand", Vector3(0.09, 0.1, 0.1), Vector3(0, -0.64, 0), Vector3.ZERO, skin)
	var umbrella := Node3D.new()
	umbrella.name = "Umbrella"
	umbrella.position = Vector3(0.18, 1.45, -0.05)
	umbrella.visible = false
	body.add_child(umbrella)
	_add_part(umbrella, "stick", Vector3(0.03, 0.75, 0.03), Vector3(0, 0.37, 0), Vector3.ZERO, material(Color(0.1, 0.1, 0.1)))
	var canopy := MeshInstance3D.new()
	canopy.mesh = _canopy_mesh()
	canopy.position = Vector3(0, 0.82, 0)
	canopy.material_override = material(UMBRELLAS[rng.randi() % UMBRELLAS.size()])
	umbrella.add_child(canopy)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 180.0
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _canopy_mesh() -> Mesh:
	if not _meshes.has("canopy"):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02
		cone.bottom_radius = 0.55
		cone.height = 0.28
		cone.radial_segments = 8
		cone.rings = 0
		cone.cap_bottom = false
		_meshes["canopy"] = cone
	return _meshes["canopy"]


static func _add_part(parent: Node3D, key: String, size: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _part_mesh(key, size, Vector3.ZERO)
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


# --- Street furniture ---------------------------------------------------------

## A traffic light post facing -Z (towards oncoming traffic when placed with
## look_at). Lamps are MeshInstances named Red, Amber and Green.
static func traffic_light() -> Node3D:
	var root := Node3D.new()
	var pole_mat := material(Color(0.2, 0.22, 0.2))
	_add_part(root, "tl_pole", Vector3(0.14, 3.4, 0.14), Vector3(0, 1.7, 0), Vector3.ZERO, pole_mat)
	_add_part(root, "tl_box", Vector3(0.36, 1.05, 0.3), Vector3(0, 3.0, 0), Vector3.ZERO, material(Color(0.08, 0.08, 0.08)))
	# Yellow backing board, as on Perth signals.
	_add_part(root, "tl_board", Vector3(0.58, 1.25, 0.04), Vector3(0, 3.0, 0.17), Vector3.ZERO, material(Color(0.85, 0.7, 0.1)))
	var names := ["Red", "Amber", "Green"]
	for i in 3:
		var lamp := _add_part(root, "tl_lamp", Vector3(0.22, 0.22, 0.06), Vector3(0, 3.33 - i * 0.33, -0.17), Vector3.ZERO, null)
		lamp.name = names[i]
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 300.0
	return root


const LAMP_COLOURS := [Color(1.0, 0.12, 0.08), Color(1.0, 0.6, 0.05), Color(0.2, 1.0, 0.5)]


static func lamp_material(index: int, lit: bool) -> Material:
	var c: Color = LAMP_COLOURS[index]
	return material(c, 3.0) if lit else material(c.darkened(0.8))


## A boom gate: post with flashing lights, and an arm (named Arm, pivot at the
## post) that swings down from vertical across the road along local +X.
static func boom_gate(arm_length: float) -> Node3D:
	var root := Node3D.new()
	var white := material(Color(0.92, 0.92, 0.9))
	var red := material(Color(0.8, 0.08, 0.06))
	_add_part(root, "bg_post", Vector3(0.18, 2.6, 0.18), Vector3(0, 1.3, 0), Vector3.ZERO, white)
	_add_part(root, "bg_sign", Vector3(1.2, 0.18, 0.04), Vector3(0, 2.75, 0), Vector3(0, 0, 0.6), white)
	_add_part(root, "bg_sign", Vector3(1.2, 0.18, 0.04), Vector3(0, 2.75, 0), Vector3(0, 0, -0.6), white)
	for side in [-1.0, 1.0]:
		var lamp := _add_part(root, "bg_lamp", Vector3(0.22, 0.22, 0.08), Vector3(side * 0.28, 2.15, -0.12), Vector3.ZERO, red)
		lamp.name = "LampL" if side < 0.0 else "LampR"
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0, 1.0, 0)
	root.add_child(arm)
	var stripes := int(ceil(arm_length / 1.0))
	for i in stripes:
		_add_part(arm, "bg_arm", Vector3(1.0, 0.1, 0.08), Vector3(0.5 + i, 0, 0), Vector3.ZERO, red if i % 2 == 0 else white)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 300.0
	return root


static func bus_stop_sign() -> Node3D:
	var root := Node3D.new()
	_add_part(root, "bs_pole", Vector3(0.08, 2.6, 0.08), Vector3(0, 1.3, 0), Vector3.ZERO, material(Color(0.6, 0.6, 0.62)))
	_add_part(root, "bs_sign", Vector3(0.5, 0.6, 0.04), Vector3(0, 2.35, 0), Vector3.ZERO, material(TRANSPERTH_GREEN))
	_add_part(root, "bs_shelter", Vector3(3.0, 0.08, 1.4), Vector3(0, 2.3, 1.2), Vector3.ZERO, material(Color(0.3, 0.32, 0.34)))
	_add_part(root, "bs_back", Vector3(3.0, 2.0, 0.05), Vector3(0, 1.25, 1.85), Vector3.ZERO, material(Color(0.55, 0.62, 0.66)))
	_add_part(root, "bs_bench", Vector3(2.0, 0.08, 0.45), Vector3(0, 0.45, 1.5), Vector3.ZERO, material(Color(0.4, 0.3, 0.2)))
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 250.0
	return root


# --- Roadworks -----------------------------------------------------------------

const WORKS_ORANGE := Color(1.0, 0.45, 0.05)


## A traffic cone the player can knock flying: a light rigid body, asleep
## until something hits it.
static func cone_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = 3.0
	body.sleeping = true
	body.can_sleep = true
	body.collision_mask = 1 | 2 | 4
	body.set_meta("surface", &"plastic")
	body.set_meta("furniture", &"traffic_cone")
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.18
	cyl.height = 0.7
	shape.shape = cyl
	shape.position = Vector3(0, 0.35, 0)
	body.add_child(shape)
	if not _meshes.has("cone"):
		var b := Builder.new(2)
		b.box(0, Vector3(0, 0.03, 0), Vector3(0.42, 0.06, 0.42))
		b.box(0, Vector3(0, 0.33, 0), Vector3(0.3, 0.56, 0.3), Vector2(0.25, 0.25))
		b.box(1, Vector3(0, 0.42, 0), Vector3(0.21, 0.1, 0.21), Vector2(0.85, 0.85))
		_meshes["cone"] = b.commit()
	var mesh := MeshInstance3D.new()
	mesh.mesh = _meshes["cone"]
	mesh.set_surface_override_material(0, material(WORKS_ORANGE))
	mesh.set_surface_override_material(1, material(Color(0.95, 0.95, 0.92), 0.6))
	mesh.visibility_range_end = 220.0
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	return body


## Striped barrier boards across a closed lane, on two legs.
static func works_barrier() -> Node3D:
	var root := Node3D.new()
	var white := material(Color(0.95, 0.95, 0.92))
	var orange := material(WORKS_ORANGE)
	for i in 6:
		_add_part(root, "wb_board", Vector3(0.5, 0.25, 0.04), Vector3(-1.25 + i * 0.5, 0.95, 0), Vector3.ZERO, orange if i % 2 == 0 else white)
	for x in [-1.3, 1.3]:
		_add_part(root, "wb_leg", Vector3(0.06, 1.0, 0.5), Vector3(x, 0.5, 0), Vector3.ZERO, material(Color(0.2, 0.2, 0.2)))
	_add_part(root, "wb_lamp", Vector3(0.14, 0.14, 0.06), Vector3(1.3, 1.2, 0), Vector3.ZERO, material(WORKS_ORANGE, 3.0))
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 260.0
	return root


## A "ROADWORK AHEAD" style sign: an orange diamond on a post (no text at
## this resolution, but you know what it means).
static func works_sign() -> Node3D:
	var root := Node3D.new()
	_add_part(root, "ws_post", Vector3(0.07, 1.6, 0.07), Vector3(0, 0.8, 0), Vector3.ZERO, material(Color(0.6, 0.6, 0.62)))
	_add_part(root, "ws_face", Vector3(0.75, 0.75, 0.03), Vector3(0, 1.75, 0), Vector3(0, 0, PI * 0.25), material(WORKS_ORANGE))
	_add_part(root, "ws_mark", Vector3(0.36, 0.08, 0.035), Vector3(0, 1.75, -0.005), Vector3.ZERO, material(Color(0.08, 0.08, 0.08)))
	_add_part(root, "ws_mark2", Vector3(0.08, 0.3, 0.035), Vector3(0, 1.82, -0.005), Vector3.ZERO, material(Color(0.08, 0.08, 0.08)))
	for child in root.find_children("*", "MeshInstance3D", true, false):
		child.visibility_range_end = 260.0
	return root


## The crew's ute: white with an orange band and an amber beacon (named
## Beacon) on the cab roof.
static func works_ute() -> Node3D:
	var root := Node3D.new()
	var info: Dictionary = TYPES[&"ute"]
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("surface", &"concrete")
	body.set_meta("traffic", &"ute")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(info.width, info.height * 0.85, info.length)
	shape.shape = box
	shape.position = Vector3(0, info.height * 0.5 + 0.1, 0)
	body.add_child(shape)
	root.add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.mesh = vehicle_mesh(&"ute")
	mesh.set_surface_override_material(Surf.PAINT, material(Color(0.94, 0.94, 0.92)))
	mesh.set_surface_override_material(Surf.GLASS, material(Color(0.07, 0.08, 0.1)))
	mesh.set_surface_override_material(Surf.TYRES, material(Color(0.05, 0.05, 0.05)))
	mesh.set_surface_override_material(Surf.LIVERY, material(WORKS_ORANGE))
	mesh.set_surface_override_material(Surf.HEAD, material(Color(0.8, 0.8, 0.75)))
	mesh.set_surface_override_material(Surf.TAIL, material(Color(0.45, 0.05, 0.04)))
	var amber := material(Color(0.5, 0.3, 0.05))
	mesh.set_surface_override_material(Surf.IND_L, amber)
	mesh.set_surface_override_material(Surf.IND_R, amber)
	mesh.visibility_range_end = 300.0
	root.add_child(mesh)
	var beacon := _add_part(root, "beacon", Vector3(0.22, 0.16, 0.22), Vector3(0, 1.98, -0.7), Vector3.ZERO, amber)
	beacon.name = "Beacon"
	# A stripe down the tray side so it reads as a works vehicle.
	_add_part(root, "ute_band", Vector3(info.width + 0.04, 0.12, 2.0), Vector3(0, 0.95, 1.4), Vector3.ZERO, material(WORKS_ORANGE))
	return root


## Collects boxes into per-surface SurfaceTools with flat normals.
class Builder:
	var tools: Array = []

	func _init(count := TrafficModels.SURFACE_COUNT) -> void:
		for i in count:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools.append(st)

	## A box, optionally tapered at the top (top_scale: x and z factors).
	func box(surface: int, c: Vector3, size: Vector3, top_scale := Vector2.ONE) -> void:
		var h := size * 0.5
		var t := Vector3(h.x * top_scale.x, h.y, h.z * top_scale.y)
		var v := [
			c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
			c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
			c + Vector3(-t.x, t.y, -t.z), c + Vector3(t.x, t.y, -t.z),
			c + Vector3(t.x, t.y, t.z), c + Vector3(-t.x, t.y, t.z),
		]
		var faces := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [2, 6, 7, 3], [1, 5, 6, 2], [3, 7, 4, 0]]
		for f in faces:
			quad(surface, v[f[0]], v[f[1]], v[f[2]], v[f[3]], c)

	## A low-poly wheel: hexagonal prism along X.
	func wheel(surface: int, c: Vector3, r: float, w: float) -> void:
		var sides := 6
		var ring_l: Array = []
		var ring_r: Array = []
		for i in sides:
			var a := TAU * (i + 0.5) / sides
			var off := Vector3(0, cos(a) * r, sin(a) * r)
			ring_l.append(c + off + Vector3(-w * 0.5, 0, 0))
			ring_r.append(c + off + Vector3(w * 0.5, 0, 0))
		for i in sides:
			var j := (i + 1) % sides
			quad(surface, ring_l[i], ring_l[j], ring_r[j], ring_r[i], c)
		for i in range(1, sides - 1):
			tri(surface, ring_l[0], ring_l[i], ring_l[i + 1], c)
			tri(surface, ring_r[0], ring_r[i], ring_r[i + 1], c)

	func quad(surface: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
		tri(surface, a, b, c, inside)
		tri(surface, a, c, d, inside)

	## Adds a triangle facing away from `inside` (Godot fronts are clockwise).
	func tri(surface: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		var outward := (a + b + c) / 3.0 - inside
		if n.dot(outward) > 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		var normal := -n.normalized()
		var st: SurfaceTool = tools[surface]
		for p in [a, b, c]:
			st.set_normal(normal)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for st in tools:
			# Empty surfaces still get a degenerate triangle so indices line up.
			var arrays: Array = st.commit_to_arrays()
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if verts == null or verts.is_empty():
				arrays = []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
				arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
