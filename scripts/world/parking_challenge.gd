class_name ParkingChallenge
extends Node3D
## A marked gap at the kerb between two parked cars. Squeezing the 500 in is
## the game: drive up, park inside the lines and stop. You're scored on time,
## how straight and close to the kerb you are, and bumps (each one costs).
## Gold, silver or bronze, with the best kept per bay (Activities).
##
## Local -Z runs along the road; +X is towards the middle of the road.

const START_RADIUS := 22.0
const GIVE_UP_RADIUS := 45.0
const SETTLE_SECONDS := 1.0
const MEDAL_SCORES := {"gold": 800, "silver": 600, "bronze": 400}
## The car's footprint, half sizes (a 500 is about 1.63 x 3.55 m).
const CAR_HALF := Vector2(0.78, 1.72)
const PARKED_COLORS := [Color(0.55, 0.57, 0.6), Color(0.2, 0.22, 0.26), Color(0.7, 0.68, 0.62), Color(0.45, 0.1, 0.1), Color(0.15, 0.25, 0.4)]

@export var bay_id := ""
@export var title := ""
## Length of the gap between the parked cars.
@export var gap := 4.6
@export var width := 2.1

var _car: CarController
var _active := false
var _time := 0.0
var _bumps := 0
var _settled := 0.0
var _cooldown := 0.0
var _sign: Label3D


func _ready() -> void:
	add_to_group(&"parking_bays")
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0.95, 0.9, 0.55)
	for line in [
		[Vector3(0, 0, -gap * 0.5), Vector3(width, 0.02, 0.12)],
		[Vector3(0, 0, gap * 0.5), Vector3(width, 0.02, 0.12)],
		[Vector3(width * 0.5, 0, 0), Vector3(0.12, 0.02, gap)],
	]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = line[1]
		mesh.mesh = box
		mesh.material_override = paint
		mesh.position = line[0] + Vector3.UP * 0.03
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bay_id)
	for z in [-1.0, 1.0]:
		_add_parked_car(Vector3(0.0, 0.0, z * (gap * 0.5 + 1.85)), PARKED_COLORS[rng.randi() % PARKED_COLORS.size()])
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.pixel_size = 0.01
	_sign.font_size = 40
	_sign.outline_size = 8
	_sign.modulate = Color(0.95, 0.9, 0.55)
	_sign.position = Vector3(-0.4, 2.4, 0.0)
	add_child(_sign)
	_update_sign()


func _add_parked_car(at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.set_meta(&"surface", &"metal")
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.45, 3.7)
	shape.shape = box
	shape.position.y = 0.75
	body.add_child(shape)
	var model := BarnFind.MODEL.instantiate() as Node3D
	model.position.y = 0.0
	body.add_child(model)
	var materials := PS1Model.apply(model)
	var paint := materials.get("Paint") as ShaderMaterial
	if paint:
		paint.set_shader_parameter("albedo_color", color)
		paint.set_shader_parameter("albedo_texture", null)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		if _car:
			_car.impact.connect(_on_impact)
		return
	var distance := _car.global_position.distance_to(global_position)
	if not _active:
		if distance < START_RADIUS and _cooldown <= 0.0 and Jobs.active.is_empty():
			_active = true
			_time = 0.0
			_bumps = 0
			_settled = 0.0
			Activities.say("Parking challenge: %s. Squeeze into the gap and stop." % title)
		return
	_time += delta
	if distance > GIVE_UP_RADIUS:
		_active = false
		return
	if _inside() and _car.speed_kmh() < 1.0:
		_settled += delta
		if _settled >= SETTLE_SECONDS:
			_finish()
	else:
		_settled = 0.0


## True when all four corners of the car are inside the painted gap.
func _inside() -> bool:
	for corner in [Vector3(-CAR_HALF.x, 0, -CAR_HALF.y), Vector3(CAR_HALF.x, 0, -CAR_HALF.y),
			Vector3(-CAR_HALF.x, 0, CAR_HALF.y), Vector3(CAR_HALF.x, 0, CAR_HALF.y)]:
		var local := to_local(_car.global_transform * corner)
		if absf(local.x) > width * 0.5 + 0.15 or absf(local.z) > gap * 0.5:
			return false
	return true


func score() -> int:
	var local := to_local(_car.global_position)
	var angle := rad_to_deg(absf(angle_difference(global_rotation.y, _car.global_rotation.y)))
	angle = minf(angle, 180.0 - angle)  # Reversing in counts too.
	var points := 1000.0
	points -= maxf(_time - 10.0, 0.0) * 12.0
	points -= angle * 18.0
	# Closer to the kerb (-X) is better.
	points -= maxf(local.x + width * 0.5 - CAR_HALF.x, 0.0) * 300.0
	points -= _bumps * 150.0
	return clampi(roundi(points), 0, 1000)


func _finish() -> void:
	_active = false
	_cooldown = 20.0
	var points := score()
	var medal := ""
	for m in Activities.PARKING_MEDALS:
		if points >= MEDAL_SCORES[m]:
			medal = m
			break
	var result := Activities.record_parking(bay_id, points, medal)
	var text := "Parked in %.1fs: %d points" % [_time, points]
	text += (", %s." % medal) if medal != "" else ". No medal; try again."
	if _bumps > 0:
		text += " (%d bump%s)" % [_bumps, "" if _bumps == 1 else "s"]
	Activities.say(text)
	_update_sign()
	if result.new_medal and medal == "gold":
		Activities.say("Gold at %s. Nobody parks a 500 like you." % title)


func _on_impact(strength: float) -> void:
	if _active and strength > 0.8:
		_bumps += 1


func _update_sign() -> void:
	var record: Dictionary = Activities.parking.get(bay_id, {})
	var medal: String = record.get("medal", "")
	_sign.text = "PARK" + ("  [%s]" % medal.to_upper() if medal != "" else "")
