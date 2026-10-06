class_name Skidpad
extends Node3D
## The skidpad behind the garage: a painted circle on a fenced concrete pad
## where you try a tuning setup. The workshop's tuning tab sends the car here
## (`start`); drive laps of the ring and each one shows its time and how hard
## the car held on (average sideways g). The best per car is kept. Stop and
## press F (`finish`) to go back to the carport.
##
## It sits off the edge of the map, so nothing else is around.

signal lap_done(seconds: float, g: float)

const ORIGIN := Vector3(30000.0, 40.0, 0.0)
## The painted ring you drive around: lines at these radii, metres.
const INNER := 14.0
const OUTER := 20.0
const PAD := 70.0
const GRASS := 600.0
## A lap only counts while the car stays this close to the ring.
const BAND := Vector2(11.0, 24.0)

## car id -> {"g": best sideways g, "lap": best lap seconds}
var best := {}
var active := false
var last_lap := 0.0
var last_g := 0.0

var _car: CarController
var _back: Transform3D
var _angle := 0.0          # radians travelled around the centre this lap
var _last_heading := 0.0
var _lap_time := 0.0
var _g_sum := 0.0
var _in_band := false
var _label: Label
var _chip: PanelContainer
var _layer: CanvasLayer


func _ready() -> void:
	SaveGame.register("skidpad", self)
	position = ORIGIN
	_build()
	var layer := CanvasLayer.new()
	layer.layer = 4
	_layer = layer
	get_tree().root.add_child.call_deferred(layer)  # on the window, not in the lo-fi world view
	_chip = PanelContainer.new()
	_chip.theme_type_variation = &"ChipPanel"
	_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chip.position.y = 24.0
	_chip.visible = false
	layer.add_child(_chip)
	_label = UiStyle.label(_chip, "", "")
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF


func _exit_tree() -> void:
	SaveGame.unregister("skidpad")
	if is_instance_valid(_layer):
		_layer.queue_free()


func save_state() -> Dictionary:
	return {"best": best.duplicate(true)}


func load_state(data: Dictionary) -> void:
	best = data.get("best", {})


## Take the car out to the skidpad, lined up on the ring.
func start(car: CarController) -> void:
	if active or car == null:
		return
	_car = car
	_back = car.global_transform
	active = true
	SaveGame.hold = true  # don't save the car out here
	var at := global_position + Vector3(0.0, 0.6, -(INNER + OUTER) * 0.5)
	car.global_transform = Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), at)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	_reset_lap()
	_chip.visible = true
	_show("Drive laps of the ring. Stop and press F to leave.")


## Back to the carport.
func finish() -> void:
	if not active:
		return
	active = false
	SaveGame.hold = false
	_chip.visible = false
	if _car and is_instance_valid(_car):
		_car.global_transform = _back
		_car.linear_velocity = Vector3.ZERO
		_car.angular_velocity = Vector3.ZERO
	_car = null


func best_for(car_id: String) -> Dictionary:
	return best.get(car_id, {})


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("interact") and _car and _car.linear_velocity.length() < 2.0:
		finish()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not active or _car == null or not is_instance_valid(_car):
		return
	var flat := _car.global_position - global_position
	flat.y = 0.0
	var r := flat.length()
	if r > PAD * 0.5 + 15.0 or _car.global_position.y < global_position.y - 5.0:
		finish()  # drove off into the paddock: call it a day
		return
	var inside := r > BAND.x and r < BAND.y and _car.linear_velocity.length() > 3.0
	var heading := atan2(flat.x, flat.z)
	if not inside:
		if _in_band:
			_reset_lap()
		_in_band = false
		return
	if not _in_band:
		_in_band = true
		_last_heading = heading
		return
	_angle += wrapf(heading - _last_heading, -PI, PI)
	_last_heading = heading
	_lap_time += delta
	var v := _car.linear_velocity
	v.y = 0.0
	_g_sum += v.length_squared() / r / 9.81 * delta
	if absf(_angle) >= TAU:
		lap(_lap_time, _g_sum / _lap_time)
		_reset_lap()
		_in_band = true
		_last_heading = heading


## A full lap: show it and keep it if it's the car's best.
func lap(seconds: float, g: float) -> void:
	last_lap = seconds
	last_g = g
	var id := String(_car.car_id) if _car else ""
	var mine: Dictionary = best.get(id, {})
	var record := g > float(mine.get("g", 0.0))
	if record:
		best[id] = {"g": g, "lap": seconds}
	_show("Lap %.1f s   %.2f g%s" % [seconds, g, "   best" if record else "   (best %.2f g)" % float(mine.get("g", 0.0))])
	lap_done.emit(seconds, g)


func _reset_lap() -> void:
	_angle = 0.0
	_lap_time = 0.0
	_g_sum = 0.0


func _show(text: String) -> void:
	_label.text = text


# --- The place ----------------------------------------------------------------------

func _build() -> void:
	# Big flat faces are split up so the PS1 vertex wobble can't push one
	# through another.
	_slab(Vector3(GRASS, 1.0, GRASS), Vector3(0, -0.6, 0), Color(0.34, 0.42, 0.22), &"grass", 60)
	_slab(Vector3(PAD, 1.0, PAD), Vector3(0, -0.5, 0), Color(0.52, 0.52, 0.5), &"concrete", 14)
	for radius in [INNER, OUTER]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.12
		torus.outer_radius = radius + 0.12
		torus.rings = 64
		torus.ring_segments = 4
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.05, 1.0)
		ring.position.y = 0.005
		ring.material_override = PS1Material.make(Color(0.92, 0.9, 0.82))
		add_child(ring)
	# Cones around the inside of the ring.
	for i in 16:
		var a := TAU * i / 16.0
		_cone(Vector3(sin(a), 0, cos(a)) * (INNER - 1.2))
	# A low fence round the pad, a corrugated shed and two floodlights.
	var half := PAD * 0.5
	for side in 4:
		var along := Vector3(1, 0, 0) if side % 2 == 0 else Vector3(0, 0, 1)
		var out := Vector3(0, 0, 1) if side % 2 == 0 else Vector3(1, 0, 0)
		var sign := 1.0 if side < 2 else -1.0
		for k in range(-7, 8):
			_box(Vector3(0.08, 1.1, 0.08), out * sign * half + along * k * 5.0 + Vector3.UP * 0.55, Color(0.4, 0.38, 0.35))
		_box(along * PAD + Vector3(0, 0.06, 0) + out * 0.06, out * sign * half + Vector3.UP * 1.0, Color(0.55, 0.55, 0.5))
	_box(Vector3(12, 4.5, 7), Vector3(0, 2.25, half + 5.0), Color(0.62, 0.64, 0.6))
	_box(Vector3(12.6, 0.2, 7.6), Vector3(0, 4.6, half + 5.0), Color(0.45, 0.47, 0.45))
	for x in [-half + 2.0, half - 2.0]:
		_box(Vector3(0.2, 8.0, 0.2), Vector3(x, 4.0, -half + 2.0), Color(0.5, 0.5, 0.5))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.92, 0.75)
		lamp.light_energy = 2.0
		lamp.omni_range = 55.0
		lamp.position = Vector3(x, 8.2, -half + 2.0)
		add_child(lamp)
		var head := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.3, 0.5)
		head.mesh = box
		head.material_override = PS1Material.glowing(Color(1.0, 0.95, 0.8), 1.5)
		head.position = lamp.position
		add_child(head)


func _slab(size: Vector3, at: Vector3, color: Color, surface: StringName, cuts: int) -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", surface)
	body.position = at
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var top := PlaneMesh.new()
	top.size = Vector2(size.x, size.z)
	top.subdivide_width = cuts
	top.subdivide_depth = cuts
	mesh.mesh = top
	mesh.position.y = size.y * 0.5
	mesh.material_override = PS1Material.make(color)
	body.add_child(mesh)


func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = at
	mesh.material_override = PS1Material.make(color)
	add_child(mesh)


func _cone(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.16
	cyl.height = 0.45
	cyl.radial_segments = 8
	mesh.mesh = cyl
	mesh.position = at + Vector3.UP * 0.225
	mesh.material_override = PS1Material.make(Color(0.95, 0.42, 0.1))
	add_child(mesh)
