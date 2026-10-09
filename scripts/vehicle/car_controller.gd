class_name CarController
extends RigidBody3D
## Arcade-leaning raycast car, tuned to feel like a small, heavy-ish hatch.
##
## Each wheel is a ray cast down from its anchor (a Marker3D under `Wheels`).
## The ray gives spring/damper suspension, and the tyre at the contact patch
## pushes the car with a simple grip model: sideways slip is cancelled up to a
## friction limit, and engine/brake forces act along the wheel. It is not a
## simulation, but weight transfer, body roll and wheelspin all fall out of it.
##
## Defaults match a 2013 Fiat 500 Pop: 1.2 FIRE (51 kW, 102 Nm), 5-speed
## manual, front-wheel drive, about 940 kg.
##
## Scene layout this script expects (see scenes/vehicles/fiat_500_pop.tscn):
##   Wheels/WheelFL, WheelFR, WheelRL, WheelRR  (Marker3D suspension anchors)
##     <wheel>/Visual       moved up/down with the suspension, steers
##     <wheel>/Visual/Spin  rolls with the wheel; put wheel meshes in here
##   DriverSeat   (Marker3D, interior camera eye point)
##   Headlights   (Node3D with lights, toggled by `headlights_on`)
##   BrakeLights  (Node3D with lights, shown while braking)
##
## Audio and other systems should read `get_telemetry()` or the public vars
## below, and connect to the signals. See docs/HOOKS.md.

signal gear_changed(gear: int)
signal transmission_changed(automatic: bool)
## Body hit something. `strength` is the impact speed in m/s.
signal impact(strength: float)
signal surface_changed(surface: StringName)
signal headlights_changed(on: bool)
## The driver flashed the headlights (K): high beam for as long as it's held.
signal lights_flashed
## A part was installed (or a slot went back to stock). The car body listens
## to swap visuals such as wheels and exhausts.
signal parts_changed(slot: StringName, part: CarPart)
## apply_car switched this to a different car (models swap bodies on this).
signal car_changed(id: String)
## Fuel dropped below LOW_FUEL_FRACTION of the tank.
signal fuel_low
## The tank ran dry; the engine cuts out until someone brings fuel.
signal fuel_empty
## The driver stopped (true) or moved off (false): binoculars and the camera
## can be raised from the seat while parked. See `is_parked_for_viewing()`.
signal parked_changed(parked: bool)
## A consumable (tyres, brakes, oil) has worn far enough to want doing.
signal service_due(item: String)

enum Transmission { MANUAL, AUTOMATIC }

## Grip and rolling resistance multipliers per surface. Colliders declare
## their surface with metadata, e.g. `collider.set_meta("surface", &"gravel")`.
const SURFACES := {
	&"asphalt": { "grip": 1.0, "rolling": 1.0 },
	&"concrete": { "grip": 0.95, "rolling": 1.0 },
	&"brick": { "grip": 0.9, "rolling": 1.3 },
	&"gravel": { "grip": 0.68, "rolling": 3.0 },
	&"dirt": { "grip": 0.65, "rolling": 2.5 },
	&"grass": { "grip": 0.58, "rolling": 3.5 },
	&"sand": { "grip": 0.5, "rolling": 6.0 },
}
const DEFAULT_SURFACE := &"asphalt"
const RPM_PER_RAD_S := 60.0 / TAU

@export var player_controlled := true
## Which car this is (an id in data/cars/cars.json). `apply_car` changes it.
@export var car_id := "pop_12"
@export var rear_wheel_drive := false
@export var is_electric := false

@export_group("Engine")
@export var idle_rpm := 850.0
@export var redline_rpm := 6200.0
@export var limiter_rpm := 6450.0
## (rpm, Nm) points of the full-throttle torque curve.
@export var torque_curve := PackedVector2Array([
	Vector2(800, 62), Vector2(1500, 80), Vector2(2200, 94), Vector2(3000, 102),
	Vector2(4000, 99), Vector2(5000, 93), Vector2(5500, 88), Vector2(6200, 76),
	Vector2(6600, 60),
])
## Engine braking torque (Nm) per 1000 rpm when off the throttle.
@export var engine_brake_per_krpm := 5.0
## How quickly the engine revs freely (out of gear or clutch in), rpm/s.
@export var free_rev_up := 9000.0
@export var free_rev_down := 3500.0
## How much the differential sends to the wheel with grip when the other one
## can't use its share: 0 open (both get what the weaker wheel can take),
## 0.5 even split, 1 locked. A limited-slip diff raises it.
@export_range(0.0, 1.0) var diff_lock := 0.25

@export_group("Gearbox")
@export var transmission := Transmission.MANUAL
@export var gear_ratios := PackedFloat32Array([3.909, 2.238, 1.520, 1.156, 0.872])
@export var reverse_ratio := 3.909
@export var final_drive := 4.071
@export var drivetrain_efficiency := 0.88
## Seconds the clutch is out during a shift.
@export var shift_time := 0.3
@export var auto_upshift_rpm := 5300.0
@export var auto_downshift_rpm := 1800.0
@export var reverse_limit_kmh := 22.0

@export_group("Suspension")
@export var wheel_radius := 0.29
## Ray length from the anchor to the bottom of the wheel at full droop.
@export var suspension_length := 0.30
## How far ahead of a wheel (in tyre radii) to look for a kerb, furthest first.
const STEP_PROBES: Array[float] = [0.8, 0.55, 0.3]
## Over a crest or a lump a tyre can lift for a moment. It keeps gripping on
## what it remembers of its load for this long (s) while it's within SKIM of
## the road, so one bump doesn't turn the car loose.
const SKIM_TIME := 0.25
const SKIM := 0.12
## Above this suspension speed (m/s) the dampers stiffen no further, so a sharp
## edge at speed doesn't kick the car off the road.
const DAMPER_KNEE := 1.2
## The last part of the suspension's travel (a fraction of it) where a rubber
## bump stop takes over, firming up fast. Without it the spring runs out of
## travel on a dip at speed and the body itself thumps the road and bounces.
const BUMP_STOP := 0.75
const BUMP_STOP_RATE := 8.0
## The lower body (fractions of its height): how far the bumpers' bottoms sit
## above the floor, and the radius of the rounded runners along the sills
## and across the bumpers (a small one there, so a wall still stops it); see
## `_shape_lower_body`.
const BUMPER_RISE := 0.26
const RUNNER_RADIUS := 0.2
const SKID_RADIUS := 0.1
## Stability control (step 6 of _physics_process): the sideways slip (rad)
## where it starts, how much more until it's fully on, and how hard it eases
## an unwanted turn (N m per kg per rad/s).
const ESC_SLIP := 0.1
const ESC_RAMP := 0.2
const ESC_DAMP := 5.0
## How close (m) the underside gets to the road before it's cushioned, and how
## hard: per metre into that gap and per m/s it closes, in g for the whole car.
const CUSHION := 0.08
const CUSHION_SPRING := 300.0
const CUSHION_DAMP := 10.0
## Half the length of road a tyre's suspension averages over; see `_footprint`.
const FOOTPRINT := 0.2
## How much of the drop from the centre of mass to the road the tyres' grip
## acts through (1 = at the road). Grip pushing at road level rolls a tall
## little car onto its door handles in a hard corner and lifts the inside
## wheels; acting higher, it leans and pitches like a car on firm springs.
const GRIP_LEVER := 0.5
## Every car grips and stops harder than its real figures: in a game you judge
## corners from a screen, so the car forgives a bit more than a real one.
const GRIP_ASSIST := 1.2
## See step 5 of _physics_process: extra weight (in g) and pitch/roll damping
## while some wheels are off the road.
const LIGHT_PULL := 1.0
const LIGHT_STEADY := 3.0
## How long after the last wheel leaves the road that still counts as a hop
## (not a jump), and how hard (per second) the car's rise is soaked up then.
const HUG_TIME := 0.5
const HUG_DAMP := 6.0
const BRAKE_ASSIST := 1.45
## The highest step a tyre rides up, in tyre radii (a 13 cm kerb is 0.45; the
## map's kerbs reach 22 cm where streets slope, and 40 cm is still a wall).
const STEP_CLIMB := 0.9
## Fastest you can fold or raise the roof (km/h).
const ROOF_MAX_KMH := 12.0
## Below this the driver counts as stopped for looking out of the window.
const PARKED_MAX_KMH := 2.0
## Consumables wear with use (0 new .. 1 worn out): tyres faster when they
## slide, pads when you brake hard, oil just with distance (petrol cars).
## In-game km: a careful driver changes the oil every few evenings of play,
## tyres and pads every week or two. See Garage.SERVICES.
const WEAR_KM := {"tyres": 450.0, "brakes": 650.0, "oil": 300.0}
## Wear at which the car tells you it's due.
const WEAR_DUE := 0.8
## Field gear the car can carry and show: the rod on a roof rack, the rest on
## the seats. Models are art/models/props/field/<id>.glb.
const FIELD_GEAR_PATH := "res://art/models/props/field/%s.glb"
const FIELD_GEAR := [&"fishing_rod", &"esky", &"tackle_box", &"binoculars", &"camera"]
## Where each piece sits in the modern cars, from the passenger's hip point:
## [offset, yaw, on the driver's side]. Cushions are 11 cm below the hip; the
## back seat is 55 to 85 cm behind it.
const FIELD_GEAR_MODERN := {
	&"esky": [Vector3(0.0, -0.1, 0.68), 0.0],
	&"tackle_box": [Vector3(0.02, -0.11, 0.7), 0.2, true],
	&"binoculars": [Vector3(0.03, -0.1, 0.1), 0.5],
	&"camera": [Vector3(-0.12, -0.11, 0.0), -0.3],
}
## The classics have no room behind the front seats: the esky rides on the
## passenger seat with the binoculars on its lid, the tackle box and camera
## in the footwell.
const FIELD_GEAR_CLASSIC := {
	&"esky": [Vector3(0.0, -0.08, -0.17), 0.0],
	&"binoculars": [Vector3(0.0, 0.33, -0.17), 0.5],
	&"tackle_box": [Vector3(0.0, -0.23, -0.55), 0.0],
	&"camera": [Vector3(0.0, -0.03, -0.55), -0.3],
}
## Soft springs (with a stiff anti-roll bar for the corners) so a wheel keeps
## the road over a dip of 11 cm before it lifts. The Pop's wheel markers in its
## scene are set for this spring's sag; see `_fit_rig` for other bodies.
@export var spring_strength := 20000.0
@export var damper_strength := 2400.0
@export var anti_roll_strength := 6500.0

@export_group("Tyres and brakes")
@export var tire_grip := 1.05
## Share of sideways slide the tyre corrects per physics step (before the grip limit).
@export_range(0.0, 1.0) var lateral_stiffness := 0.7
## Rear grip multiplier while the handbrake is held.
@export var handbrake_grip := 0.3
## Total braking force at full pedal, N.
@export var brake_force := 9000.0
@export var handbrake_force := 3500.0
@export var rolling_resistance := 0.014
@export var drag_coefficient := 0.42

@export_group("Steering")
@export var max_steer_deg := 34.0
@export var high_speed_steer_deg := 7.0
## Speed (km/h) at which steering lock is down to `high_speed_steer_deg`.
@export var steer_falloff_kmh := 110.0
## Steering wheel speed, radians of road-wheel angle per second.
@export var steer_rate := 2.2
## How hard full steering input pushes the front tyres at speed: 1.0 caps the
## lock just past the grip limit, so a full keyboard or stick input turns the
## car as tightly as the tyres allow instead of ploughing straight on. 0 turns
## the cap off (pure lock table).
@export_range(0.0, 1.0) var steer_assist := 1.0
## Steering angle past the grip limit that the assist still allows.
@export var steer_assist_margin := 1.4
## Stability control, like the real Pop's ESC: when the car starts to slide
## sideways and turns further than the steering asks, it's eased back
## (0 turns it off). See step 6 of _physics_process.
@export_range(0.0, 1.0) var stability_assist := 1.0

# --- Driver inputs, 0..1 (steer -1..1). Set by the player or by AI. ---
var throttle_input := 0.0
var brake_input := 0.0
var steer_input := 0.0
var handbrake_input := 0.0

# --- Telemetry (read-only for other systems) ---
## Engine speed.
var rpm := 850.0
## -1 reverse, 0 neutral, 1..5 forward.
var gear := 1
## Throttle actually reaching the engine after the shift logic, 0..1.
var throttle := 0.0
## Brake pedal actually applied, 0..1 (after auto-reverse swapping).
var brake := 0.0
## 0 = clutch fully in (disengaged), 1 = fully engaged.
var clutch := 1.0
## Engine torque output as a share of peak, -1..1 (negative = engine braking).
var engine_load := 0.0
## Signed speed along the car's nose, m/s.
var forward_speed := 0.0
## Worst tyre slip this step, 0..1. Good for skid/squeal volume.
var tire_slip := 0.0
## Surface under most of the wheels.
var surface: StringName = DEFAULT_SURFACE
var grounded_wheels := 0
var is_shifting := false
var headlights_on := false
## True while the headlights are flashed (high beam, lights on or not).
var flashing := false
## Front road-wheel angle in radians, positive = left.
var steer_angle := 0.0
## True while the camera is in the cabin (set by CarCameraRig). Audio uses it
## to switch to the muffled interior mix.
var is_player_inside := false
## The folding roof is back (500C, canvas-topped classics). Saved with the car.
var roof_open := false
## Field gear in or on the car (ids from FIELD_GEAR). It's the
## player's, not the car's: it moves to whichever car they drive.
var field_gear: PackedStringArray = []
var _parked := false
## Consumable wear for this car, 0 (new) to 1 (worn out). Saved with the car.
var wear := {"tyres": 0.0, "brakes": 0.0, "oil": 0.0}
## The car's service book: [{day, km, text}], oldest first, saved with it.
var logbook: Array = []
const LOGBOOK_MAX := 60
## Dashboard needles on the body (Needle_<dial>_<full scale>, see
## art/models/README.md): [node, rest basis, dial, full scale, shown value].
var _needles: Array = []
var _needles_body: Node = null
## Odometer readouts on the body: [Label3D, last km shown].
var _odometers: Array = []
## Engine torque multiplier from installed parts.
var torque_multiplier := 1.0
## How much rain hurts grip (1 = stock tyres).
var wet_penalty_multiplier := 1.0
## Installed parts by slot. Empty slots run the stock part.
var parts := {}
## Distance driven, km.
var odometer_km := 0.0
## Fuel tank (the 2013 Pop's is 35 L) and what's in it.
@export var tank_litres := 35.0
var fuel_litres := 35.0
## Gameplay scale on real-world consumption, so servo stops come round
## every few hours of play rather than once a week.
@export var fuel_use_scale := 2.0
## Litres (or kWh, for an EV) used per kWh the engine delivers, and at idle.
@export var fuel_per_kwh := 0.4
@export var fuel_idle_per_hour := 0.8
const LOW_FUEL_FRACTION := 0.12
## How dirty the car is, 0 (fresh from the car wash) to 1 (filthy).
var dirt := 0.35
## How fast dirt builds up (mud flaps keep some off).
var dirt_multiplier := 1.0
## Dirt gained per km by surface; rain on a wet road adds more.
const DIRT_PER_KM := {&"asphalt": 0.004, &"concrete": 0.004, &"gravel": 0.05, &"grass": 0.03, &"dirt": 0.06, &"sand": 0.05}
## Garage tuning values by CarTuning option key.
var tuning := {}
## Saved tuning setups, one per SETUP_NAMES slot (empty dict = nothing saved).
var setups: Array = [{}, {}, {}]
## Names of the saved setup slots in the workshop's Tuning tab.
const SETUP_NAMES := ["Everyday", "Coast road", "Wet day"]
## Respray colour; alpha 0 means the original paint.
var paint_color := Color(0, 0, 0, 0)
## Earned extras fitted to this car: "livery" (a cosmetic id or "") and
## "trinkets" (cosmetic ids, one per slot). See data/progression/cosmetics.json.
var cosmetics := {"livery": "", "trinkets": []}
## The spray shop's own livery, used when cosmetics.livery is "custom":
## {"mode": a CarBody livery mode, "color": "#rrggbb", "number": 1..99}.
var custom_livery := {}
## Clear-coat finish from the spray shop ("" keeps the model's own; see
## Garage.FINISHES).
var finish := ""
const MODEL_PATH := "res://art/models/cars/%s/%s.glb"

## Stock values captured on _ready, so parts always stack from stock.
var _stock := {}
## The scene's own values (the Pop), so switching cars starts clean.
var _scene_defaults := {}
var _peak_torque := 102.0
var _wheelbase := 2.3
## The Pop's rig: wheel anchors, wheel models, collision boxes, tyre radius.
var _rig_defaults := {}
## The body's size (m); the chase camera frames smaller cars closer.
const POP_SIZE := Vector3(1.63, 1.49, 3.55)
var body_size := POP_SIZE
## Each wheel's model from the body (its WheelStyle), before any wheel part.
var _model_wheels := {}
const PART_MODEL_PATH := "res://art/models/cars/parts/%s.glb"
## The yellow glow of lit fog lamp lenses.
const FOG_GLOW := Color(1.0, 0.68, 0.12)
## How much brighter the headlights are while flashed (high beam).
const FLASH_BOOST := 1.8
## Slots whose parts sit on the body, and the empty each sits at.
const PART_MOUNTS := {&"engine": "Mount_Exhaust", &"exhaust": "Mount_Exhaust", &"roof": "Mount_Roof", &"lights": "Mount_Spotlights",
	&"rear_rack": "Mount_RearRack", &"towbar": "Mount_TowBar", &"steering_wheel": "Mount_SteeringWheel",
	&"gear_knob": "Mount_GearKnob"}
## Slots whose part shows at more than one empty: [mount, model suffix, whether
## the plain model may stand in when the suffixed one doesn't exist, mirror
## across the car]. The first one's node is Body/Part_<slot>, the rest
## Part_<slot>_2 and on.
const PART_PLACES := {
	&"bumpers": [["Mount_BumperF", "_f", true, false], ["Mount_BumperR", "_r", false, false]],
	&"mudflaps": [["Mount_MudFlap_L", "", true, false], ["Mount_MudFlap_R", "", true, false]],
	&"seat_covers": [["Seat_L", "", true, false], ["Seat_R", "", true, true]],
}
## Stock model nodes a part replaces, hidden while it's fitted.
const PART_HIDES := {&"steering_wheel": "SteeringWheel", &"gear_knob": "GearKnob"}
## Body-specific stand-ins: model -> {visual: replacement}.
const PART_VISUAL_SWAPS := {"giardiniera": {"mudflap": "mudflap_short"}}
## CarController values a car spec may set (data/cars/cars.json).
const SPEC_KEYS := [
	"mass", "idle_rpm", "redline_rpm", "limiter_rpm", "torque_curve", "gear_ratios",
	"final_drive", "reverse_ratio", "shift_time", "auto_upshift_rpm", "auto_downshift_rpm",
	"engine_brake_per_krpm", "spring_strength", "damper_strength", "anti_roll_strength",
	"brake_force", "handbrake_force", "tire_grip", "suspension_length", "lateral_stiffness",
	"drag_coefficient", "tank_litres", "fuel_per_kwh", "fuel_idle_per_hour", "fuel_use_scale",
	"rear_wheel_drive", "is_electric", "diff_lock",
]
const _TUNABLE := [
	"limiter_rpm", "redline_rpm", "final_drive", "gear_ratios", "shift_time",
	"tire_grip", "lateral_stiffness", "spring_strength", "damper_strength",
	"anti_roll_strength", "suspension_length", "brake_force", "handbrake_force",
	"mass", "drag_coefficient", "diff_lock", "free_rev_up", "free_rev_down",
]

var _wheels: Array[Dictionary] = []
var _shift_timer := 0.0
var _pending_gear := 1
var _reverse_hold := 0.0
var _brake_reverse := false  # reverse was picked with the brake key
var _air_time := 0.0  # since the last wheel touched the road
var _last_slide := 0.0  # sideways slip angle last step, rad (see step 6)
var _cushions: Array[Vector3] = []  # the underside's lowest points; see step 7
var _headlights_manual := false
var _walker: Node = null
var _spawn_transform: Transform3D
## Where teleport() is putting the car, applied in the next physics step.
var _teleport_to: Transform3D
var _teleporting := false
var _ray_query := PhysicsRayQueryParameters3D.new()
var _last_velocity := Vector3.ZERO


func _ready() -> void:
	for key in SPEC_KEYS:
		_scene_defaults[key] = _copy(get(key))
	_capture_stock()
	if player_controlled:
		add_to_group(&"player_car")
		SaveGame.register("car", self)
	_spawn_transform = global_transform
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_ray_query.exclude = [get_rid()]
	_ray_query.collision_mask = ~MapTileLoader.LAYER_WATER  # wheels sit on the riverbed, not the water
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var anchor: Node3D = get_node("Wheels/" + wheel_name)
		_wheels.append({
			"anchor": anchor,
			"visual": anchor.get_node_or_null("Visual"),
			"spin": anchor.get_node_or_null("Visual/Spin"),
			"front": wheel_name.contains("F"),
			"driven": wheel_name.contains("F") != rear_wheel_drive,
			"left": wheel_name.ends_with("L"),
			"compression": 0.0,
			"last_compression": 0.0,
			"grounded": false,
			"hit_distance": suspension_length + wheel_radius,
			"spin_angle": 0.0,
			"spin_speed": 0.0,
			"surface": DEFAULT_SURFACE,
			"cap": INF,  # drive force the tyre had left last step, N
			"grip_load": 0.0,  # the load the tyre grips with, smoothed over bumps, N
			"light": 1.0,  # seconds since this tyre last touched the road
			"skim": false,  # just off the road (within SKIM)
		})
	_capture_rig()
	var lower := get_node_or_null("LowerBodyCollision") as CollisionShape3D
	if lower and lower.shape is BoxShape3D:
		_shape_lower_body(lower, (lower.shape as BoxShape3D).size)
	if physics_material_override == null:
		# A slippery underside: a body that touches a kerb lip slides over it
		# on the wheels' push instead of sticking there.
		physics_material_override = PhysicsMaterial.new()
		physics_material_override.friction = 0.15
	_update_lights()
	_wheelbase = absf(_wheels[0].anchor.position.z - _wheels[2].anchor.position.z)


func _physics_process(delta: float) -> void:
	if player_controlled:
		_read_player_input(delta)
	elif flashing:
		flash_lights(false)
	if is_parked_for_viewing() != _parked:
		_parked = not _parked
		parked_changed.emit(_parked)
	_update_transmission_logic(delta)
	if fuel_litres <= 0.0:
		throttle = 0.0
	elif fuel_litres < 0.6 and fmod(Time.get_ticks_msec() / 1000.0, 1.3) < 0.35:
		throttle *= 0.2  # Sputtering on the last of the tank.
	_update_steering(delta)

	var up := global_basis.y
	var total_ray := suspension_length + wheel_radius
	var space := get_world_3d().direct_space_state

	# 1. Suspension rays.
	for wheel in _wheels:
		var origin: Vector3 = wheel.anchor.global_position
		_ray_query.from = origin
		_ray_query.to = origin - up * (total_ray + SKIM)
		var hit := space.intersect_ray(_ray_query)
		wheel.last_compression = wheel.compression
		wheel.skim = false
		if hit.is_empty() or origin.distance_to(hit.position) > total_ray:
			wheel.grounded = false
			wheel.compression = 0.0
			wheel.hit_distance = total_ray
			if not hit.is_empty():
				# Just off the road: close enough to keep a little grip.
				wheel.skim = true
				wheel.contact = hit.position
				wheel.normal = hit.normal
		else:
			wheel.grounded = true
			wheel.hit_distance = _footprint(origin, up, total_ray, origin.distance_to(hit.position), space)
			_climb_step(wheel, origin, up, total_ray, space)
			wheel.compression = clampf(total_ray - wheel.hit_distance, 0.0, suspension_length)
			wheel.contact = hit.position
			wheel.normal = hit.normal
			var collider: Object = hit.collider
			wheel.surface = collider.get_meta("surface", DEFAULT_SURFACE) if collider else DEFAULT_SURFACE

	# 2. Engine torque reaching the driven (front) wheels.
	var drive_torque := _update_engine(delta)

	# 3. Per-wheel forces.
	var corner_mass := mass * 0.25
	var surface_votes := {}
	var worst_slip := 0.0
	grounded_wheels = 0
	var wet_grip := lerpf(1.0, 1.0 - 0.22 * wet_penalty_multiplier, Weather.wetness)
	var wear_grip := tyre_grip_factor()
	var wear_brakes := brake_factor()
	for i in _wheels.size():
		var wheel: Dictionary = _wheels[i]
		var forward := -global_basis.z
		if wheel.front:
			forward = forward.rotated(up, steer_angle)
		var opposite: Dictionary = _wheels[i ^ 1]
		var load := 0.0
		if wheel.grounded:
			wheel.light = 0.0
			grounded_wheels += 1
			surface_votes[wheel.surface] = surface_votes.get(wheel.surface, 0) + 1
			# Spring, damper and anti-roll bar. The dampers are digressive: past
			# DAMPER_KNEE they barely firm up, so a sharp lump doesn't kick.
			var compression_speed: float = (wheel.compression - wheel.last_compression) / delta
			var knee := clampf(compression_speed, -DAMPER_KNEE, DAMPER_KNEE)
			var damping := (knee + (compression_speed - knee) * 0.25) * damper_strength
			load = wheel.compression * spring_strength + damping
			# Bump stop: by how far the road is into the last of the travel,
			# past the end of it too. It only pushes while it's being squashed
			# (a soaked-up thump), not as the car rises off it, so it can't
			# throw the car back up into the air.
			var stop_in: float = total_ray - wheel.hit_distance - suspension_length * BUMP_STOP
			if stop_in > 0.0 and compression_speed > 0.0:
				load += stop_in * stop_in / (suspension_length * (1.0 - BUMP_STOP)) * spring_strength * BUMP_STOP_RATE * 0.5
			load += (wheel.compression - opposite.compression) * anti_roll_strength
			load = maxf(load, 0.0)
			# The tyre grips with a load that follows the spring but rides
			# over the spikes and dips of a bumpy road.
			var static_load := corner_mass * 9.81
			var target := minf(load, static_load * 2.2)
			var rate := 40.0 if target > wheel.grip_load else 12.0
			wheel.grip_load = lerpf(wheel.grip_load, target, 1.0 - exp(-rate * delta))
			apply_force(up * load, wheel.contact - global_position)
		else:
			wheel.light += delta
			if not wheel.skim or wheel.light > SKIM_TIME:
				wheel.grip_load = 0.0
				wheel.spin_speed = lerpf(wheel.spin_speed, 0.0, delta * 0.5)
				wheel.cap = 0.0
				continue
			wheel.grip_load *= exp(-delta / 0.15)
		var contact: Vector3 = wheel.contact
		var normal: Vector3 = wheel.normal
		var offset := contact - global_position

		# Tyre frame on the contact plane.
		forward = (forward - normal * forward.dot(normal)).normalized()
		var right := forward.cross(normal).normalized()
		var point_velocity := linear_velocity + angular_velocity.cross(offset)
		var v_long := point_velocity.dot(forward)
		var v_lat := point_velocity.dot(right)
		var surface_info: Dictionary = SURFACES.get(wheel.surface, SURFACES[DEFAULT_SURFACE])
		var max_force: float = tire_grip * GRIP_ASSIST * wheel.grip_load * surface_info.grip * wet_grip * wear_grip
		var stop_force := absf(v_long) * corner_mass / delta

		var lateral := -v_lat * corner_mass / delta * lateral_stiffness
		var longitudinal := 0.0
		if wheel.driven:
			longitudinal += _drive_share(drive_torque * 0.5 / wheel_radius, wheel, opposite)
		wheel.cap = sqrt(maxf(max_force * max_force - lateral * lateral, 0.0))
		var braking := brake * brake_force * BRAKE_ASSIST * wear_brakes * (0.3 if wheel.front else 0.2)
		if not wheel.front:
			braking += handbrake_input * handbrake_force * 0.5
			if handbrake_input > 0.1:
				max_force *= lerpf(1.0, handbrake_grip, handbrake_input)
		braking += rolling_resistance * surface_info.rolling * wheel.grip_load
		longitudinal -= signf(v_long) * minf(braking, stop_force)

		# Friction circle: the tyre can only push so hard in total.
		var demand := Vector2(lateral, longitudinal)
		var slip := 0.0
		if demand.length() > max_force and max_force > 0.0:
			# How far the tyre is past its limit: sideways by slip angle, and
			# lengthways by how much more drive or braking it was asked for.
			var slip_angle := absf(v_lat) / maxf(absf(v_long), 2.0)
			var over := demand.length() / max_force - 1.0
			slip = clampf(maxf((slip_angle - 0.06) / 0.18, absf(longitudinal) / max_force - 1.0), 0.0, 1.0)
			if absf(v_long) < 2.0:
				slip = maxf(slip, clampf(over * 0.2, 0.0, 1.0))
			demand = demand.normalized() * max_force
		worst_slip = maxf(worst_slip, slip)
		var lever := offset - up * offset.dot(up) * (1.0 - GRIP_LEVER)
		apply_force(right * demand.x + forward * demand.y, lever)

		# Visual wheel spin; driven wheels spin up when they slip.
		var spin_target := v_long / wheel_radius
		if wheel.driven and slip > 0.0 and drive_torque != 0.0:
			spin_target += signf(drive_torque) * slip * 25.0
		if not wheel.front and handbrake_input > 0.5:
			spin_target = 0.0
		wheel.spin_speed = spin_target

	# 4. Air drag.
	apply_central_force(-linear_velocity * linear_velocity.length() * drag_coefficient)

	# 5. Over a crest or a hump, with wheels off the road, pull the car back
	# down onto them, take the spring out of its rise and calm its pitch and
	# roll, so a lump in the road is a lurch rather than a launch. Only for a
	# moment after leaving the road: off a real ramp it flies.
	_air_time = 0.0 if grounded_wheels > 0 else _air_time + delta
	if grounded_wheels < 4 and _air_time < HUG_TIME:
		var missing := float(4 - grounded_wheels) / 4.0
		# Toward the car's own floor, so on a hill it's toward the road.
		var rise := maxf(linear_velocity.dot(up), 0.0)
		apply_central_force(-up * mass * (9.81 * LIGHT_PULL + rise * HUG_DAMP) * missing)
		var tumble := angular_velocity - up * angular_velocity.dot(up)
		apply_torque(-tumble * mass * LIGHT_STEADY * missing)

	# 6. Stability control. With two wheels on grass, a kerb under one side or
	# the throttle down in a slide, the end of the car with the most grip
	# can swing it round: once it's sliding more than ESC_SLIP and the
	# slide is growing, any turn beyond what the steering asks for (at most
	# what the tyres could do) is eased out, so it skids and straightens up
	# instead of spinning. Off with the handbrake, so handbrake turns still work.
	var flat_v := linear_velocity - up * linear_velocity.dot(up)
	var heading := -global_basis.z
	var along := flat_v.dot(heading)
	var slide := 0.0
	if along > 4.0:
		slide = atan2(flat_v.dot(global_basis.x), along)
	if stability_assist > 0.0 and handbrake_input < 0.1 and grounded_wheels >= 2 and along > 4.0:
		var yaw_rate := angular_velocity.dot(up)
		var asked := clampf(along * tan(steer_angle) / _wheelbase, -9.81 * tire_grip / along, 9.81 * tire_grip / along)
		var extra := yaw_rate - asked
		var growing := (slide - _last_slide) * slide > 0.0
		var amount := clampf((absf(slide) - ESC_SLIP) / ESC_RAMP, 0.0, 1.0) * stability_assist
		if growing and amount > 0.0 and extra * yaw_rate > 0.0:
			apply_torque(-up * extra * mass * ESC_DAMP * amount)
	_last_slide = slide

	# 7. Bottoming out: the last few centimetres above the road under the
	# body's lowest points soak up the thump, so a dip that runs the
	# suspension out of travel lifts the car instead of slamming its floor
	# onto the road (which kicked it into the air, or into a spin).
	for point in _cushions:
		var at := global_transform * point
		_ray_query.from = at + up * CUSHION
		_ray_query.to = at - up * CUSHION
		var hit := space.intersect_ray(_ray_query)
		if hit.is_empty():
			continue
		var into: float = CUSHION - (at - (hit.position as Vector3)).dot(up)
		var closing := -(linear_velocity + angular_velocity.cross(at - global_position)).dot(up)
		if into > 0.0 and closing > 0.0:
			apply_force(up * mass * (CUSHION_SPRING * into + CUSHION_DAMP * closing), at - global_position)

	tire_slip = worst_slip
	forward_speed = linear_velocity.dot(-global_basis.z)
	var new_surface: StringName = surface
	var best := 0
	for key in surface_votes:
		if surface_votes[key] > best:
			best = surface_votes[key]
			new_surface = key
	if new_surface != surface:
		surface = new_surface
		surface_changed.emit(surface)
	_last_velocity = linear_velocity
	if grounded_wheels > 0:
		var km := absf(forward_speed) * delta / 1000.0
		odometer_km += km
		var rate: float = DIRT_PER_KM.get(surface, 0.01) + Weather.wetness * 0.02
		dirt = minf(1.0, dirt + km * rate * dirt_multiplier)
		_add_wear("tyres", km * (1.0 + 2.5 * tire_slip))
		_add_wear("brakes", km * (0.3 + 2.0 * brake))
		if not is_electric:
			_add_wear("oil", km)


func _process(delta: float) -> void:
	for wheel in _wheels:
		if wheel.visual:
			wheel.visual.position.y = -(wheel.hit_distance - wheel_radius)
			wheel.visual.rotation.y = steer_angle if wheel.front else 0.0
		if wheel.spin:
			wheel.spin_angle = wrapf(wheel.spin_angle - wheel.spin_speed * delta, -PI, PI)
			wheel.spin.rotation.x = wheel.spin_angle
	_update_needles(delta)
	var brake_lights := get_node_or_null("BrakeLights")
	if brake_lights:
		brake_lights.visible = brake > 0.05
	# Parked with the driver out: the lights go off (and any switch on by
	# hand is forgotten), so a car left in the carport doesn't light the house.
	var parked := _driver_out()
	if parked:
		_headlights_manual = false
	if not _headlights_manual:
		var want := not parked and (GameClock.daylight() < 0.45 or Weather.rain > 0.6)
		if want != headlights_on:
			headlights_on = want
			_update_lights()


## Swing the dashboard needles (the speedo, rev counter and fuel gauge) and
## roll the odometer, on bodies that have them. A needle rests on zero and turns 240 degrees
## clockwise (negative about its local Y) at full scale, with a little lag.
func _update_needles(delta: float) -> void:
	var body := get_node_or_null("Body")
	if body != _needles_body:
		_needles_body = body
		_needles.clear()
		_odometers.clear()
		if body:
			for node: Node3D in body.find_children("Odometer_*", "Node3D", true, false):
				_odometers.append([_odometer_label(node), -1])
			for node: Node3D in body.find_children("Needle_*", "Node3D", true, false):
				var parts := node.name.split("_")
				if parts.size() >= 3 and parts[2].is_valid_float() and float(parts[2]) > 0.0:
					_needles.append([node, node.basis, parts[1], float(parts[2]), 0.0])
	for needle: Array in _needles:
		var value := 0.0
		match needle[2]:
			"Speed":
				value = speed_kmh()
			"Rev":
				value = rpm / 1000.0 if fuel_litres > 0.0 else 0.0
			"Fuel":
				value = fuel_litres / maxf(tank_litres, 0.001)
		value = clampf(value, 0.0, needle[3] * 1.04)
		needle[4] = lerpf(needle[4], value, 1.0 - exp(-10.0 * delta))
		(needle[0] as Node3D).basis = needle[1] * Basis(Vector3.UP, -deg_to_rad(240.0) * needle[4] / needle[3])
	for odo: Array in _odometers:
		var km := int(odometer_km) % 1000000
		if km != odo[1] and is_instance_valid(odo[0]):
			odo[1] = km
			(odo[0] as Label3D).text = "%06d" % km


## The digits in an Odometer_<digit height in mm> window: a Label3D at the
## empty, reading along its +X and facing the driver (+Z).
func _odometer_label(window: Node3D) -> Label3D:
	var existing := window.get_node_or_null(^"Digits") as Label3D
	if existing:
		return existing
	var height_mm := float(String(window.name).get_slice("_", 1))
	var label := Label3D.new()
	label.name = "Digits"
	label.font_size = 32
	label.outline_size = 0
	label.pixel_size = maxf(height_mm, 1.0) / 1000.0 / label.font_size
	label.shaded = false
	label.double_sided = false
	# The modern cars' window is an LCD; the classics' a drum of white digits.
	label.modulate = Color(0.62, 0.9, 1.0) if height_mm >= 6.0 else Color(0.94, 0.92, 0.86)
	label.position = Vector3(0, 0, 0.0005)
	window.add_child(label)
	return label


## Everything audio (or a HUD) needs in one place. See docs/HOOKS.md.
func get_telemetry() -> Dictionary:
	return {
		"rpm": rpm,
		"idle_rpm": idle_rpm,
		"redline_rpm": redline_rpm,
		"throttle": throttle,
		"brake": brake,
		"clutch": clutch,
		"engine_load": engine_load,
		"gear": gear,
		"automatic": transmission == Transmission.AUTOMATIC,
		"is_shifting": is_shifting,
		"speed_kmh": linear_velocity.length() * 3.6,
		"forward_speed": forward_speed,
		"tire_slip": tire_slip,
		"surface": surface,
		"grounded_wheels": grounded_wheels,
		"handbrake": handbrake_input,
		"weather_intensity": Weather.intensity(),
		"wetness": Weather.wetness,
		"is_player_inside": is_player_inside,
		"odometer_km": odometer_km,
		"fuel_litres": fuel_litres,
		"fuel_fraction": fuel_fraction(),
		"engine_running": fuel_litres > 0.0,
		"dirt": dirt,
	}


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func shift_up() -> void:
	if gear < gear_ratios.size():
		_begin_shift(gear + 1)


func shift_down() -> void:
	if gear == 1 and absf(forward_speed) > 2.0:
		_begin_shift(0)  # Refuse reverse while rolling; leave it in neutral.
	elif gear > -1:
		_begin_shift(gear - 1)


func set_transmission(mode: Transmission) -> void:
	transmission = mode
	if mode == Transmission.AUTOMATIC and gear == 0:
		_begin_shift(1)
	transmission_changed.emit(mode == Transmission.AUTOMATIC)


func toggle_transmission() -> void:
	set_transmission(Transmission.MANUAL if transmission == Transmission.AUTOMATIC else Transmission.AUTOMATIC)


## True when the player has got out and walked off (OnFoot isn't in this car).
func _driver_out() -> bool:
	if _walker == null or not is_instance_valid(_walker):
		_walker = get_tree().get_first_node_in_group(&"player_on_foot") if is_inside_tree() else null
		if _walker == null:
			return false
	return not _walker.in_car and _walker.get(&"_car") == self


func toggle_headlights() -> void:
	_headlights_manual = true
	headlights_on = not headlights_on
	_update_lights()


## High beam while `on`, whether the headlights are on or not.
func flash_lights(on: bool) -> void:
	if on == flashing:
		return
	flashing = on
	var lights := get_node_or_null("Headlights")
	if lights:
		lights.visible = headlights_on or on
		for lamp: Light3D in lights.find_children("*", "Light3D", true, false):
			_keep_out_of_rooms(lamp)
			if on:
				lamp.set_meta(&"before_flash", lamp.light_energy)
				lamp.light_energy *= FLASH_BOOST
			elif lamp.has_meta(&"before_flash"):
				lamp.light_energy = lamp.get_meta(&"before_flash")
				lamp.remove_meta(&"before_flash")
	if on:
		lights_flashed.emit()


## Fold the roof back or put it up, on cars with a folding one. Done by
## hand, so not at speed. True when it moved.
func toggle_roof() -> bool:
	if not has_folding_roof():
		return false
	if speed_kmh() > ROOF_MAX_KMH:
		var hud := get_tree().get_first_node_in_group(&"hud") if is_inside_tree() else null
		if hud and hud.has_method("toast"):
			hud.toast("Slow down to fold the roof")
		return false
	roof_open = not roof_open
	_apply_roof()
	return true


func has_folding_roof() -> bool:
	var body := get_node_or_null("Body")
	return body != null and body.has_method("set_roof_open") and body.get_node_or_null(^"Roof_Open") != null


func _apply_roof() -> void:
	var body := get_node_or_null("Body")
	if body == null or not body.has_method("set_roof_open"):
		return
	if body.is_node_ready():
		body.set_roof_open(roof_open)
	elif not body.ready.is_connected(_apply_roof):
		body.ready.connect(_apply_roof, CONNECT_ONE_SHOT)


func _add_wear(item: String, km: float) -> void:
	var before: float = wear[item]
	wear[item] = minf(1.0, before + km / WEAR_KM[item])
	if before < WEAR_DUE and wear[item] >= WEAR_DUE:
		service_due.emit(item)


## Write a line in the service book, stamped with the day and the odometer.
func log_entry(text: String) -> void:
	logbook.append({"day": GameClock.day, "km": roundi(odometer_km), "text": text})
	if logbook.size() > LOGBOOK_MAX:
		logbook.pop_front()


## Grip left in the tyres: bald tyres let go about a fifth sooner.
func tyre_grip_factor() -> float:
	return lerpf(1.0, 0.8, pow(wear.tyres, 1.5))


## Worn pads stop about a quarter less hard.
func brake_factor() -> float:
	return lerpf(1.0, 0.75, pow(wear.brakes, 1.5))


## Old oil takes the edge off the engine once it's well overdue.
func oil_factor() -> float:
	return lerpf(1.0, 0.92, smoothstep(0.7, 1.0, wear.oil))


## Items at or past WEAR_DUE, for the HUD and the workshop.
func services_due() -> PackedStringArray:
	var due := PackedStringArray()
	for item: String in wear:
		if wear[item] >= WEAR_DUE and not (item == "oil" and is_electric):
			due.append(item)
	return due


## The driver is in the seat and the car is stopped: a moment to look out of
## the window (binoculars, the camera) without getting out.
func is_parked_for_viewing() -> bool:
	return player_controlled and speed_kmh() < PARKED_MAX_KMH and grounded_wheels >= 3


## The driver's eye in world space (the interior camera's point), facing
## forward (-Z). Binoculars raised from the seat look out from here.
func driver_eye() -> Transform3D:
	var seat := get_node_or_null("DriverSeat") as Node3D
	if seat:
		return seat.global_transform.orthonormalized()
	return global_transform.translated_local(Vector3(0.36, 0.72, 0.22)).orthonormalized()


## Show this field gear in or on the car (replaces what was shown).
## Unknown ids are skipped.
func set_field_gear(ids: PackedStringArray) -> void:
	field_gear = PackedStringArray()
	for id in ids:
		if FIELD_GEAR.has(StringName(id)) and not field_gear.has(id):
			field_gear.append(id)
	_apply_field_gear()


func has_field_gear(id: String) -> bool:
	return field_gear.has(id)


## Put the gear models where they go on this body: the rod on the roof rack
## (when one's fitted), the rest on the seats (see FIELD_GEAR_MODERN and
## FIELD_GEAR_CLASSIC).
func _apply_field_gear() -> void:
	var body := get_node_or_null("Body") as Node3D
	if body == null:
		return
	for old in body.get_children():
		if old.name.begins_with("Gear_"):
			body.remove_child(old)
			old.queue_free()
	for id in field_gear:
		var path := FIELD_GEAR_PATH % id
		if not ResourceLoader.exists(path):
			continue
		var spot: Variant = _field_gear_spot(body, StringName(id))
		if spot == null:
			continue
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.name = "Gear_" + id
		model.transform = spot
		body.add_child(model)
		PS1Model.apply(model)


func _field_gear_spot(body: Node3D, id: StringName) -> Variant:
	if id == &"fishing_rod":
		# Only on a rack: a 2.1 m rod is longer than a 500's roof. Without one
		# it travels in the boot, out of sight.
		var rack := body.get_node_or_null(^"Part_roof") as Node3D
		var mount := body.find_child(PART_MOUNTS[&"roof"], true, false) as Node3D
		if mount == null or rack == null:
			return null
		# Racks mark where the rod lies: Mount_Rod at the butt, the blank
		# running forward along its -Z (the rod model runs along +Z).
		var rod_spot := rack.find_child("Mount_Rod", true, false) as Node3D
		if rod_spot:
			return _in_body_space(body, rod_spot) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		# Butt forward along +Z, the blank resting on the rack's bars beside
		# the board, the reel hanging just ahead of the front bar.
		return Transform3D(Basis.IDENTITY, _in_body_space(body, mount).origin + Vector3(-0.43, -0.03, -1.05))
	# Everything else sits on the seats or the floor, placed from the
	# passenger's hip point (Seat_L): measured off the cushions of each body
	# family so nothing floats or sinks in.
	var seat := body.find_child("Seat_L", true, false) as Node3D
	var hip := _in_body_space(body, seat).origin if seat else Vector3(-0.36, 0.55, 0.25)
	var spots: Dictionary = FIELD_GEAR_CLASSIC if CarCatalogue.get_car(car_id).get("ladder", "") == "classic" else FIELD_GEAR_MODERN
	if not spots.has(id):
		return null
	var spot: Array = spots[id]
	var offset: Vector3 = spot[0]
	if spot.size() > 2 and spot[2]:
		offset.x -= hip.x * 2.0  # The driver's side.
	return Transform3D(Basis(Vector3.UP, spot[1]), hip + offset)


## Put the car back on its wheels a little above where it is now.
func reset_upright() -> void:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	teleport(Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), global_position + Vector3.UP * 1.0))


func reset_to_spawn() -> void:
	teleport(_spawn_transform)
	_begin_shift(1)


## Moves the car to `t`, stopped. Safe from anywhere: a transform set while
## input is being handled (a key, a menu button) can be put straight back by
## the next physics step, so the physics step sets it again.
func teleport(t: Transform3D) -> void:
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_teleport_to = t
	_teleporting = true
	sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _teleporting:
		_teleporting = false
		state.transform = _teleport_to
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO


## Install a part in its slot (replacing whatever was there).
func install_part(part: CarPart) -> void:
	if part.is_stock():
		parts.erase(part.slot)
	else:
		parts[part.slot] = part
	_rebuild_stats()
	_apply_part_visuals()
	parts_changed.emit(part.slot, part)


## Put a slot back to the stock part.
func remove_part(slot: StringName) -> void:
	if not parts.has(slot):
		return
	parts.erase(slot)
	_rebuild_stats()
	_apply_part_visuals()
	parts_changed.emit(slot, PartsCatalogue.get_part(StringName(String(slot) + "_stock")))


## Installed part ids, for saving.
func get_part_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for part in parts.values():
		ids.append(part.id)
	return ids


## Restore a saved set of parts. Unknown ids are skipped.
func install_part_ids(ids: PackedStringArray) -> void:
	for id in ids:
		var part := PartsCatalogue.get_part(id)
		if part:
			install_part(part)


## Apply garage tuning (CarTuning option key -> value). Replaces the old setup.
func set_tuning(values: Dictionary) -> void:
	tuning = values.duplicate()
	_rebuild_stats()


## Keep the current tuning in setup slot `slot` (0..SETUP_NAMES.size()-1).
func save_setup(slot: int) -> void:
	if slot < 0 or slot >= SETUP_NAMES.size():
		return
	setups[slot] = tuning.duplicate()


## Switch to the tuning saved in setup slot `slot`. Returns false when empty.
func load_setup(slot: int) -> bool:
	if slot < 0 or slot >= setups.size() or (setups[slot] as Dictionary).is_empty():
		return false
	set_tuning(setups[slot])
	return true


func has_setup(slot: int) -> bool:
	return slot >= 0 and slot < setups.size() and not (setups[slot] as Dictionary).is_empty()


## Re-apply the body paint and stats after something outside the car changed
## them (a restoration stage, a restomod).
func apply_paint_refresh() -> void:
	_apply_paint()
	_rebuild_stats()


## Respray the body. The paint is kept with the car and saved.
func set_paint(color: Color) -> void:
	paint_color = Color(color, 1.0)
	_apply_paint()


func has_custom_paint() -> bool:
	return paint_color.a > 0.0


## Become a different car: its numbers from data/cars/cars.json, stock parts,
## default tuning. Use `load_vehicle_state` afterwards to restore one you own.
func apply_car(id: String) -> void:
	var car := CarCatalogue.get_car(id)
	if car.is_empty():
		push_warning("Unknown car '%s'" % id)
		return
	car_id = id
	for item: String in wear:
		wear[item] = 0.0  # Another car, its own wear (load_vehicle_state restores it).
	logbook = []
	# Take the old car's parts off first, while its stock values still apply.
	for slot in parts.keys():
		remove_part(slot)
	for key in SPEC_KEYS:
		set(key, _copy(_scene_defaults[key]))
	is_electric = car.get("electric", false)
	rear_wheel_drive = car.get("rear_engine", false)
	var spec: Dictionary = car.get("spec", {})
	for key in spec:
		if not key in SPEC_KEYS:
			push_warning("Car '%s' sets unknown spec key '%s'" % [id, key])
			continue
		var value: Variant = spec[key]
		match key:
			"torque_curve":
				var curve := PackedVector2Array()
				for point in value:
					curve.append(Vector2(point[0], point[1]))
				value = curve
			"gear_ratios":
				value = PackedFloat32Array(value)
		set(key, value)
	for wheel in _wheels:
		wheel.driven = wheel.front != rear_wheel_drive
	tuning = {}
	setups = [{}, {}, {}]
	paint_color = Color(0, 0, 0, 0)
	cosmetics = {"livery": "", "trinkets": []}
	custom_livery = {}
	finish = ""
	_swap_model(car.get("model", "pop"))
	_apply_paint()
	_capture_stock()
	gear = mini(gear, gear_ratios.size())
	fuel_litres = minf(fuel_litres, tank_litres)
	car_changed.emit(car_id)


## Everything about this car that isn't where it's parked.
func vehicle_state() -> Dictionary:
	return {
		"car_id": car_id,
		"parts": Array(get_part_ids()),
		"odometer_km": odometer_km,
		"automatic": transmission == Transmission.AUTOMATIC,
		"tuning": tuning,
		"setups": setups.duplicate(true),
		"fuel_litres": fuel_litres,
		"dirt": dirt,
		"paint": paint_color.to_html() if has_custom_paint() else "",
		"cosmetics": cosmetics.duplicate(true),
		"custom_livery": custom_livery.duplicate(),
		"finish": finish,
		"roof_open": roof_open,
		"wear": wear.duplicate(),
		"logbook": logbook.duplicate(true),
	}


func load_vehicle_state(data: Dictionary) -> void:
	var id: String = data.get("car_id", car_id)
	if id != car_id:
		apply_car(id)
	for slot in parts.keys():
		remove_part(slot)
	install_part_ids(PackedStringArray(data.get("parts", [])))
	odometer_km = float(data.get("odometer_km", 0.0))
	set_tuning(data.get("tuning", {}))
	setups = [{}, {}, {}]
	var saved_setups: Array = data.get("setups", [])
	for i in mini(saved_setups.size(), setups.size()):
		if saved_setups[i] is Dictionary:
			setups[i] = (saved_setups[i] as Dictionary).duplicate()
	fuel_litres = clampf(float(data.get("fuel_litres", tank_litres)), 0.0, tank_litres)
	dirt = clampf(float(data.get("dirt", dirt)), 0.0, 1.0)
	paint_color = Color(0, 0, 0, 0)
	var saved: Dictionary = data.get("cosmetics", {})
	cosmetics = {"livery": String(saved.get("livery", "")), "trinkets": Array(saved.get("trinkets", []))}
	custom_livery = Dictionary(data.get("custom_livery", {})).duplicate()
	if cosmetics.livery == "custom" and custom_livery.is_empty():
		cosmetics.livery = ""
	finish = String(data.get("finish", ""))
	var paint: String = data.get("paint", "")
	if paint != "":
		set_paint(Color.html(paint))
	else:
		_apply_paint()
	roof_open = bool(data.get("roof_open", false))
	_apply_roof()
	var saved_wear: Dictionary = data.get("wear", {})
	for item: String in wear:
		wear[item] = clampf(float(saved_wear.get(item, 0.0)), 0.0, 1.0)
	logbook = Array(data.get("logbook", [])).duplicate(true)


func save_state() -> Dictionary:
	var state := vehicle_state()
	state["field_gear"] = Array(field_gear)
	state["position"] = SaveGame.vec3_to_array(global_position)
	state["yaw"] = global_rotation.y
	return state


func load_state(data: Dictionary) -> void:
	if data.has("position"):
		# Lift slightly so the wheels settle onto the ground rather than in it.
		var pos := SaveGame.array_to_vec3(data.position) + Vector3.UP * 0.3
		global_transform = Transform3D(Basis(Vector3.UP, float(data.get("yaw", 0.0))), pos)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	load_vehicle_state(data)
	set_field_gear(PackedStringArray(data.get("field_gear", [])))


## Headline numbers for menus and the garage.
func get_stats() -> Dictionary:
	var peak_torque := 0.0
	var peak_power_kw := 0.0
	var at_rpm := idle_rpm
	while at_rpm <= limiter_rpm:
		var torque := _torque_at(at_rpm)
		peak_torque = maxf(peak_torque, torque)
		peak_power_kw = maxf(peak_power_kw, torque * at_rpm * TAU / 60.0 / 1000.0)
		at_rpm += 50.0
	return {
		"power_kw": peak_power_kw,
		"torque_nm": peak_torque,
		"mass_kg": mass,
		"grip": tire_grip,
		"brake_force": brake_force,
		"limiter_rpm": limiter_rpm,
		"final_drive": final_drive,
	}


func _rebuild_stats() -> void:
	for key in _TUNABLE:
		set(key, _copy(_stock[key]))
	torque_multiplier = 1.0
	wet_penalty_multiplier = 1.0
	dirt_multiplier = 1.0
	var multipliers := {
		"final_drive_mult": "final_drive", "shift_time_mult": "shift_time",
		"grip_mult": "tire_grip", "spring_mult": "spring_strength",
		"damper_mult": "damper_strength", "anti_roll_mult": "anti_roll_strength",
		"drag_mult": "drag_coefficient", "free_rev_mult": "free_rev_up",
	}
	var modifier_sets: Array[Dictionary] = []
	for part in parts.values():
		modifier_sets.append(part.modifiers)
	modifier_sets.append(CarTuning.to_modifiers(tuning, get_part_ids()))
	modifier_sets.append(Classics.modifiers(car_id))
	for m in modifier_sets:
		torque_multiplier *= m.get("torque_mult", 1.0)
		wet_penalty_multiplier *= m.get("wet_penalty_mult", 1.0)
		dirt_multiplier *= m.get("dirt_mult", 1.0)
		for key in multipliers:
			if m.has(key):
				set(multipliers[key], get(multipliers[key]) * m[key])
		if m.has("brake_mult"):
			brake_force *= m.brake_mult
			handbrake_force *= m.brake_mult
		limiter_rpm += m.get("limiter_add", 0.0)
		redline_rpm += m.get("limiter_add", 0.0)
		suspension_length += m.get("ride_height_add", 0.0)
		mass += m.get("mass_add", 0.0)
		lateral_stiffness = clampf(lateral_stiffness + m.get("lateral_stiffness_add", 0.0), 0.1, 1.0)
		diff_lock = clampf(diff_lock + m.get("diff_lock_add", 0.0), 0.0, 1.0)
		if m.has("free_rev_mult"):
			free_rev_down *= m.free_rev_mult
		if m.has("gear_ratios"):
			gear_ratios = PackedFloat32Array(m.gear_ratios)


func _capture_stock() -> void:
	for key in _TUNABLE:
		_stock[key] = _copy(get(key))
	_peak_torque = 1.0
	for point in torque_curve:
		_peak_torque = maxf(_peak_torque, point.y)
	_rebuild_stats()


static func _copy(value: Variant) -> Variant:
	if value is PackedFloat32Array or value is PackedVector2Array:
		return value.duplicate()
	return value


## Put a livery on (a cosmetic id from Progression.rewards, "custom" for the
## spray shop's one, or "" for none).
func set_livery(id: String) -> void:
	cosmetics.livery = id
	_apply_cosmetics()


## Paint a spray shop livery on: `mode` is a CarBody livery mode, `color` its
## colour and `number` the door number (rally numbers only).
func set_custom_livery(mode: String, color: Color, number := 0) -> void:
	custom_livery = {"mode": mode, "color": "#" + color.to_html(false), "number": clampi(number, 0, 99)}
	set_livery("custom")


## Change the clear coat ("" for the model's own).
func set_finish(id: String) -> void:
	finish = id
	_apply_paint()


func has_trinket(id: String) -> bool:
	return Array(cosmetics.trinkets).has(id)


## Fit a trinket (replacing whatever is in its slot) or take it off.
func toggle_trinket(id: String) -> void:
	var list: Array = cosmetics.trinkets
	if list.has(id):
		list.erase(id)
	else:
		var slot: String = Progression.cosmetic(id).get("slot", "")
		for other: String in list.duplicate():
			if Progression.cosmetic(other).get("slot", "") == slot:
				list.erase(other)
		list.append(id)
	_apply_cosmetics()


## Put this car's own body on (art/models/cars/<model>/<model>.glb, all on
## the Pop's rig). Cars without a model of their own keep the Pop's.
func _swap_model(model: String) -> void:
	var path := MODEL_PATH % [model, model]
	if not ResourceLoader.exists(path):
		path = MODEL_PATH % ["pop", "pop"]
	var old := get_node_or_null("Body") as Node3D
	if old == null or old.scene_file_path == path:
		return
	var body := (load(path) as PackedScene).instantiate() as Node3D
	body.transform = old.transform
	body.set_script(old.get_script())
	var index := old.get_index()
	remove_child(old)
	old.queue_free()
	body.name = "Body"
	add_child(body)
	move_child(body, index)
	_fit_rig(body)
	roof_open = false  # A different car comes with its roof up.


## Fit the wheels and collision to a model that marks its own hubs
## (`Hub_FL`... empties, plus a `WheelStyle_<style>` empty):
## the classic 500s are much smaller than the Pop. Models without hubs get
## the Pop's rig back unchanged.
func _fit_rig(body: Node3D) -> void:
	_capture_rig()
	var hubs: Array[Node3D] = []
	for hub_name in ["Hub_FL", "Hub_FR", "Hub_RL", "Hub_RR"]:
		var hub := body.find_child(hub_name, true, false) as Node3D
		if hub:
			hubs.append(hub)
	var fitted := hubs.size() == 4
	var style := _wheel_style(body) if fitted else ""
	# The model's origin is on the ground, so a hub's height is the tyre radius.
	var ground := body.transform.origin.y
	wheel_radius = _in_car_space(body, hubs[0]).origin.y - ground if fitted else float(_rig_defaults.wheel_radius)
	# Anchor height that puts the model's ground on the road at rest, with
	# this car's own spring sag (each corner carries a quarter of the mass).
	var sag := mass * 9.8 * 0.25 / maxf(spring_strength, 1.0)
	var anchor_y := suspension_length + wheel_radius - sag + ground
	for i in _wheels.size():
		var wheel: Dictionary = _wheels[i]
		var rest: Vector3 = _rig_defaults.anchors[i]
		if fitted:
			var hub_pos := _in_car_space(body, hubs[i]).origin
			wheel.anchor.position = Vector3(hub_pos.x, anchor_y, hub_pos.z)
		else:
			wheel.anchor.position = rest
		wheel.hit_distance = suspension_length + wheel_radius
		var path: String = _rig_defaults.wheels[i]
		if style != "":
			var styled := "res://art/models/cars/parts/wheel_%s_%s.glb" % [style, "l" if wheel.left else "r"]
			if ResourceLoader.exists(styled):
				path = styled
		_model_wheels[i] = path
	_wheelbase = absf(_wheels[0].anchor.position.z - _wheels[2].anchor.position.z)
	_fit_collision(body if fitted else null)
	_apply_part_visuals()


## Remember the Pop's rig (once), so other bodies can be fitted and undone.
func _capture_rig() -> void:
	if _rig_defaults.is_empty() and not _wheels.is_empty():
		_rig_defaults = {"wheel_radius": wheel_radius, "anchors": [], "wheels": [], "shapes": {}}
		for wheel in _wheels:
			_rig_defaults.anchors.append(wheel.anchor.position)
			var spin: Node3D = wheel.spin
			_rig_defaults.wheels.append(spin.get_child(0).scene_file_path if spin and spin.get_child_count() > 0 else "")
		for shape_name in ["LowerBodyCollision", "CabinCollision"]:
			var col := get_node_or_null(shape_name) as CollisionShape3D
			if col and col.shape is BoxShape3D:
				_rig_defaults.shapes[shape_name] = [col.position, (col.shape as BoxShape3D).size]


## The road under a tyre's whole contact patch, not one point: the average
## of the ray at the hub and two either side of it, fore and aft. The map's
## roads are facets half a metre long, and a single ray feels every crease
## between them as a little kick; a tyre rolls over them.
func _footprint(origin: Vector3, up: Vector3, total_ray: float, centre: float, space: PhysicsDirectSpaceState3D) -> float:
	var along := -global_basis.z * FOOTPRINT
	var sum := centre
	var n := 1
	for side: float in [-1.0, 1.0]:
		_ray_query.from = origin + along * side
		_ray_query.to = _ray_query.from - up * (total_ray + SKIM)
		var probe := space.intersect_ray(_ray_query)
		if probe.is_empty():
			continue
		var d: float = _ray_query.from.distance_to(probe.position)
		# A kerb or a wall beside the patch isn't road under it.
		if absf(d - centre) < FOOTPRINT * 0.5:
			sum += d
			n += 1
	return sum / n


## A round tyre rides up a kerb before its centre gets there: probe the
## ground just ahead (in the direction of travel) and, where it's a low step
## up, raise this wheel's contact by however much of the step the tyre's curve
## already touches. Steps higher than STEP_CLIMB of the radius are walls.
func _climb_step(wheel: Dictionary, origin: Vector3, up: Vector3, total_ray: float, space: PhysicsDirectSpaceState3D) -> void:
	var v := linear_velocity - up * linear_velocity.dot(up)
	if v.length() < 0.3:
		return
	var ahead := v.normalized()
	var lift := 0.0
	for f: float in STEP_PROBES:
		var x := wheel_radius * f
		_ray_query.from = origin + ahead * x
		_ray_query.to = _ray_query.from - up * total_ray
		var probe := space.intersect_ray(_ray_query)
		if probe.is_empty():
			continue
		var step: float = wheel.hit_distance - _ray_query.from.distance_to(probe.position)
		if step < 0.01:
			if f == STEP_PROBES[0]:
				return  # Flat ahead: no need to look closer.
			continue
		if step > wheel_radius * STEP_CLIMB:
			return
		lift = maxf(lift, step - (wheel_radius - sqrt(wheel_radius * wheel_radius - x * x)))
	wheel.hit_distance -= lift


## Show the fitted parts that have models: wheels (instead of the body's own
## style), and an exhaust, roof rack or spotlights at the body's Mount_* empties.
func _apply_part_visuals() -> void:
	var wheels: CarPart = parts.get(&"wheels")
	for i in _wheels.size():
		var wheel: Dictionary = _wheels[i]
		_capture_rig()
		var path: String = _model_wheels.get(i, _rig_defaults.wheels[i])
		if wheels and wheels.visual != "":
			var fitted := PART_MODEL_PATH % ("%s_%s" % [wheels.visual, "l" if wheel.left else "r"])
			if ResourceLoader.exists(fitted):
				path = fitted
		if path != "":
			_set_wheel_model(wheel.spin, path)
	var body := get_node_or_null("Body") as Node3D
	if body == null:
		return
	for old in body.get_children():
		if old.name.begins_with("Part_"):
			body.remove_child(old)
			old.queue_free()
	for slot: StringName in PART_HIDES:
		var stock := body.find_child(PART_HIDES[slot], true, false) as Node3D
		if stock:
			stock.visible = true
	for slot: StringName in PartsCatalogue.SLOTS:
		var places: Array = PART_PLACES.get(slot, [[PART_MOUNTS.get(slot, ""), "", true, false]])
		if places[0][0] == "":
			continue
		var part: CarPart = parts.get(slot)
		var shown := 0
		for place: Array in places:
			var visual := _part_visual(part, place[1], place[2])
			var mount := body.find_child(place[0], true, false) as Node3D
			if visual == "" or (mount == null and place[0] != PART_MOUNTS.get(slot, "")):
				continue
			var model := (load(PART_MODEL_PATH % visual) as PackedScene).instantiate() as Node3D
			shown += 1
			model.name = "Part_" + String(slot) + ("" if shown == 1 else "_%d" % shown)
			var spot := _in_body_space(body, mount) if mount else Transform3D.IDENTITY
			if place[3]:
				# The other side: mirror across the car's centreline.
				spot.basis = spot.basis * Basis.from_scale(Vector3(-1, 1, 1))
			model.transform = spot
			body.add_child(model)
			var fog := PS1Model.apply(model).get("LampFog") as ShaderMaterial
			if fog:
				model.set_meta("fog_lens", fog)
				fog.set_shader_parameter("emission_color", FOG_GLOW)
				fog.set_shader_parameter("emission_energy", 1.1 if headlights_on else 0.0)
			if slot == &"lights":
				_add_spotlights(model, part.id == &"lights_fog")
			if slot == &"steering_wheel" and body.has_method("turn_with_steering"):
				body.turn_with_steering(model)
		if shown > 0 and PART_HIDES.has(slot):
			var stock := body.find_child(PART_HIDES[slot], true, false) as Node3D
			if stock:
				stock.visible = false
	if body.has_method("set_plate"):
		var plate: CarPart = parts.get(&"plate")
		body.set_plate(plate.visual if plate else "")
	_apply_field_gear()


## The model to show for a part on this car: `<visual>_classic` or
## `<visual>_modern` when the part comes in one per body family, else
## `<visual>`; "" when there's nothing to show.
func _part_visual(part: CarPart, suffix := "", plain_ok := true) -> String:
	if part == null or part.visual == "":
		return ""
	var car := CarCatalogue.get_car(car_id)
	var base: String = PART_VISUAL_SWAPS.get(car.get("model", ""), {}).get(part.visual, part.visual)
	var family := "classic" if car.get("ladder", "") == "classic" else "modern"
	var names := ["%s%s_%s" % [base, suffix, family], base + suffix]
	if suffix != "" and plain_ok:
		names.append_array(["%s_%s" % [base, family], base])
	for name: String in names:
		if ResourceLoader.exists(PART_MODEL_PATH % name):
			return name
	return ""


## Two lamps for the period spotlights (or wide yellow fog lamps), on with
## the headlights.
func _add_spotlights(model: Node3D, fog := false) -> void:
	for x in [-0.28, 0.28]:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(x, 0.1, -0.1)
		lamp.light_color = Color(1.0, 0.82, 0.35) if fog else Color(1.0, 0.9, 0.7)
		lamp.light_energy = 2.2 if fog else 3.0
		lamp.spot_range = 22.0 if fog else 45.0
		lamp.spot_angle = 38.0 if fog else 18.0
		lamp.visible = headlights_on
		lamp.add_to_group(&"car_spotlights")
		model.add_child(lamp)


func _in_body_space(body: Node3D, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var n: Node = node
	while n and n != body:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	return chain


## The model's wheel style, from its `WheelStyle_<style>` empty.
func _wheel_style(body: Node3D) -> String:
	for node in body.get_children():
		if node.name.begins_with("WheelStyle_"):
			return String(node.name).trim_prefix("WheelStyle_")
	return ""


func _set_wheel_model(spin: Node3D, path: String) -> void:
	if spin == null or path == "":
		return
	var current := spin.get_child(0) if spin.get_child_count() > 0 else null
	if current and current.scene_file_path == path:
		return
	if current:
		spin.remove_child(current)
		current.queue_free()
	var wheel := (load(path) as PackedScene).instantiate() as Node3D
	wheel.name = "Wheel"
	spin.add_child(wheel)
	PS1Model.apply(wheel)


## Scale the Pop's two collision boxes to a smaller body's footprint
## (null puts the Pop's back).
func _fit_collision(body: Node3D) -> void:
	var sx := 1.0
	var sz := 1.0
	var sy := 1.0
	body_size = POP_SIZE
	if body:
		var box := _model_bounds(body)
		if box.size.x > 0.1:
			body_size = box.size
		var lower: Array = _rig_defaults.shapes.get("LowerBodyCollision", [])
		if box.size.x > 0.1 and not lower.is_empty():
			sx = box.size.x / 1.63
			sz = box.size.z / 3.55
			sy = box.size.y / 1.49
	for shape_name in _rig_defaults.shapes:
		var col := get_node(shape_name) as CollisionShape3D
		var rest: Array = _rig_defaults.shapes[shape_name]
		var size: Vector3 = rest[1]
		var pos: Vector3 = rest[0]
		var scaled := Vector3(size.x * sx, size.y * sy, size.z * sz)
		col.position = Vector3(pos.x * sx, pos.y * sy, pos.z * sz)
		if shape_name == "LowerBodyCollision":
			_shape_lower_body(col, scaled)
		else:
			var box_shape := BoxShape3D.new()
			box_shape.size = scaled
			col.shape = box_shape


## The lower body: a hull for the bodywork, with its underside made of
## rounded runners, one along each sill and one across the bottom of each
## bumper. A flat-sided shape meeting the road's short facets at speed gets
## shoved back off whichever of its faces is least buried, often a bumper's
## front or an edge of the floor: the car stopped dead from 66 km/h, or
## caught on one side and spun. A runner is only ever pushed out from its
## own middle, so the car rides up and over instead. The runners are
## rounded at the sides and the ends too, so a kerb's lip meets a curve and
## lifts the car. Proportions from the Pop.
func _shape_lower_body(col: CollisionShape3D, size: Vector3) -> void:
	col.shape = _lower_hull(size)
	var d := _underside(size)
	var runners := {
		"NoseSkid": [Vector3(0.0, -d.h + d.rise + d.skid, -d.l + d.skid), d.skid, size.x, Vector3(0.0, 0.0, PI * 0.5)],
		"TailSkid": [Vector3(0.0, -d.h + d.rise + d.skid, d.l - d.skid), d.skid, size.x, Vector3(0.0, 0.0, PI * 0.5)],
		"LeftRunner": [Vector3(-d.w + d.r, -d.h + d.floor_up + d.r, (d.front - d.rear) * 0.5), d.r,
			size.z - d.front - d.rear, Vector3(PI * 0.5, 0.0, 0.0)],
		"RightRunner": [Vector3(d.w - d.r, -d.h + d.floor_up + d.r, (d.front - d.rear) * 0.5), d.r,
			size.z - d.front - d.rear, Vector3(PI * 0.5, 0.0, 0.0)],
	}
	for runner_name: String in runners:
		var spec: Array = runners[runner_name]
		var runner := get_node_or_null(runner_name) as CollisionShape3D
		if runner == null:
			runner = CollisionShape3D.new()
			runner.name = runner_name
			add_child(runner)
		var capsule := CapsuleShape3D.new()
		capsule.radius = spec[1]
		capsule.height = spec[2]
		runner.shape = capsule
		runner.rotation = spec[3]
		runner.position = col.position + spec[0]
	# The runners' lowest points, for the cushions in step 7.
	_cushions.clear()
	for x: float in [-d.w + d.r, d.w - d.r]:
		_cushions.append(col.position + Vector3(x, -d.h + d.floor_up, -d.l + d.front + d.r))
		_cushions.append(col.position + Vector3(x, -d.h + d.floor_up, d.l - d.rear - d.r))
	for end: float in [-1.0, 1.0]:
		_cushions.append(col.position + Vector3(0.0, -d.h + d.rise, end * (d.l - d.skid)))


## The lower body's proportions, from its size.
static func _underside(size: Vector3) -> Dictionary:
	return {
		"w": size.x * 0.5, "h": size.y * 0.5, "l": size.z * 0.5,
		"rise": size.y * BUMPER_RISE,  # bumper bottoms this much higher than the floor
		"front": size.z * 0.13, "rear": size.z * 0.1,  # overhangs, up to the bumpers
		"floor_up": size.y * 0.2,  # the floor between the axles rides over a 22 cm kerb's lip
		"r": size.y * RUNNER_RADIUS,
		"skid": size.y * SKID_RADIUS,
	}


## The bodywork above the runners: a box whose bottom sits along the
## runners' middles, so only they touch the ground.
static func _lower_hull(size: Vector3) -> ConvexPolygonShape3D:
	var d := _underside(size)
	var points := PackedVector3Array()
	for x: float in [-d.w, d.w]:
		for end: float in [-1.0, 1.0]:
			points.append(Vector3(x, d.h, end * d.l))
			points.append(Vector3(x, -d.h + d.rise + d.skid, end * (d.l - 0.01)))
		points.append(Vector3(x, -d.h + d.floor_up + d.r, -d.l + d.front))
		points.append(Vector3(x, -d.h + d.floor_up + d.r, d.l - d.rear))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return hull


## A model node's transform in the car's space (works before entering the tree).
func _in_car_space(body: Node3D, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var n: Node = node
	while n and n != body:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	return body.transform * chain


## Bounding box of a model's meshes in the car's space.
func _model_bounds(body: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_box: AABB = _in_car_space(body, mesh) * mesh.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	return box


func _apply_cosmetics() -> void:
	var body := get_node_or_null("Body")
	if body == null or not body.has_method("apply_cosmetics"):
		return
	var trinkets := []
	for id: String in cosmetics.trinkets:
		trinkets.append(Progression.cosmetic(id))
	var livery: Dictionary = {}
	if cosmetics.livery == "custom":
		livery = custom_livery
	elif cosmetics.livery != "":
		livery = Progression.cosmetic(cosmetics.livery)
	body.apply_cosmetics(livery, trinkets)


func _apply_paint() -> void:
	var body := get_node_or_null("Body")
	if body == null or not body.has_method("set_paint"):
		return
	_apply_cosmetics()
	if has_custom_paint():
		body.set_paint(paint_color)
	elif CarCatalogue.get_car(car_id).get("ladder", "") == "classic":
		# Barn finds wear rust until the paint stage is done.
		body.set_paint(Classics.paint_for(car_id), not Classics.is_stage_done(car_id, "paint"))
	elif body.has_method("reset_paint"):
		body.reset_paint()
	if body.has_method("set_finish"):
		var coat: Array = Garage.FINISHES.get(finish, [])
		body.set_finish(coat[3] if coat else -1.0, coat[4] if coat else -1.0)


func _read_player_input(delta: float) -> void:
	var raw_throttle := Input.get_action_strength("accelerate")
	var raw_brake := Input.get_action_strength("brake")
	# Rate limit so keyboard input feels like a pedal rather than a switch.
	throttle_input = move_toward(throttle_input, raw_throttle, delta * (5.0 if raw_throttle > throttle_input else 8.0))
	brake_input = move_toward(brake_input, raw_brake, delta * (9.0 if raw_brake > brake_input else 10.0))
	steer_input = Input.get_axis("steer_right", "steer_left")
	handbrake_input = Input.get_action_strength("handbrake")
	if Input.is_action_just_pressed("shift_up"):
		shift_up()
	if Input.is_action_just_pressed("shift_down"):
		shift_down()
	if Input.is_action_just_pressed("toggle_transmission"):
		toggle_transmission()
	if Input.is_action_just_pressed("toggle_headlights"):
		toggle_headlights()
	if Input.is_action_just_pressed("flash_lights"):
		flash_lights(true)
	elif flashing and not Input.is_action_pressed("flash_lights"):
		flash_lights(false)
	if Input.is_action_just_pressed("toggle_roof"):
		toggle_roof()
	if Input.is_action_just_pressed("reset_car"):
		reset_upright()


func _update_steering(delta: float) -> void:
	var speed_factor := clampf(speed_kmh() / steer_falloff_kmh, 0.0, 1.0)
	var lock := deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, speed_factor))
	if steer_assist > 0.0:
		# The road-wheel angle that asks for the tyres' full grip at this speed.
		var v := maxf(absf(forward_speed), 1.0)
		var grip_lock := atan(_wheelbase * tire_grip * GRIP_ASSIST * 9.81 / (v * v)) * steer_assist_margin
		# In a slide, hand back the full lock so you can catch it.
		var sideways := absf(linear_velocity.dot(global_basis.x))
		var slide := clampf((atan2(sideways, v) - 0.08) / 0.15, 0.0, 1.0)
		lock = lerpf(lock, minf(lock, grip_lock), steer_assist * (1.0 - slide))
	var target := steer_input * lock
	# Turn in briskly; come back to centre faster still, like a self-centring rack.
	var rate := steer_rate * (1.6 if absf(target) < absf(steer_angle) else 1.0)
	steer_angle = move_toward(steer_angle, target, rate * delta)


func _update_transmission_logic(delta: float) -> void:
	throttle = throttle_input
	brake = brake_input
	# The brake key means "go backwards" once the car is already rolling back
	# (after a spin, say), or in automatic once it's stopped: it picks reverse straight away and
	# drives, rather than braking to a stop first. While reverse was picked
	# this way the pedals swap, so the accelerator brakes, then picks first.
	var stopped := absf(forward_speed) < 1.0
	var rolling_back := forward_speed < -0.5
	var arcade := transmission == Transmission.AUTOMATIC or _brake_reverse
	# In manual a standstill hold stays a brake (you're waiting at the lights
	# in first); only rolling backwards picks reverse.
	var wants_back := rolling_back or (stopped and transmission == Transmission.AUTOMATIC)
	if gear >= 0 and not (is_shifting and _pending_gear == -1) and brake_input > 0.5 and throttle_input < 0.1 and wants_back:
		_reverse_hold += delta
		# A moment's hold at a standstill (so a tap at the lights stays a
		# brake); none at all when it's already rolling backwards.
		if rolling_back or _reverse_hold > 0.2:
			_begin_shift(-1)
			_brake_reverse = true
			arcade = true
	elif gear == -1 and not is_shifting and arcade and throttle_input > 0.5 and brake_input < 0.1 and (stopped or forward_speed > 0.5):
		_reverse_hold += delta
		if forward_speed > 0.5 or _reverse_hold > 0.1:
			_begin_shift(1)
			_brake_reverse = false
	else:
		_reverse_hold = 0.0
	if (gear == -1 or (is_shifting and _pending_gear == -1)) and arcade:
		throttle = brake_input
		brake = throttle_input
	elif is_shifting and _pending_gear == 1 and gear == -1:
		brake = 0.0
	if transmission == Transmission.AUTOMATIC and gear >= 1 and not is_shifting:
		if rpm > auto_upshift_rpm and gear < gear_ratios.size() and throttle > 0.1:
			_begin_shift(gear + 1)
		elif _road_rpm() < auto_downshift_rpm and gear > 1:
			# By road speed, not the engine: at a crawl the clutch slips and
			# the engine sits above idle, but it still wants first.
			_begin_shift(gear - 1)
	if gear == -1:
		# Keep reversing gentle: fade the throttle out above reverse_limit_kmh.
		throttle *= clampf(1.0 - (speed_kmh() - reverse_limit_kmh) / 6.0, 0.0, 1.0)
	if is_shifting:
		_shift_timer -= delta
		throttle = 0.0
		if _shift_timer <= 0.0:
			is_shifting = false
			gear = _pending_gear
			gear_changed.emit(gear)


## The revs the engine would be at in this gear from road speed alone.
func _road_rpm() -> float:
	return absf(forward_speed) / maxf(wheel_radius, 0.01) * absf(_gear_ratio(gear)) * final_drive * RPM_PER_RAD_S


func _begin_shift(target: int) -> void:
	if target == gear and not is_shifting:
		return
	_pending_gear = target
	is_shifting = true
	_shift_timer = shift_time
	_reverse_hold = 0.0


func _gear_ratio(g: int) -> float:
	if g == 0:
		return 0.0
	if g < 0:
		return -reverse_ratio
	return gear_ratios[g - 1]


## One driven wheel's drive force from its half of the torque, `share` (N).
## The wheel with less grip left takes its half (and spins if it can't use
## it); the other gets what the diff passes it: as little as the weaker
## wheel can take when open, its full half at 0.5, more when locked.
func _drive_share(share: float, wheel: Dictionary, other: Dictionary) -> float:
	if not other.driven:
		return share
	var weak := minf(wheel.cap, other.cap)
	var excess := maxf(absf(share) - weak, 0.0)
	if excess <= 0.0 or wheel.cap <= other.cap:
		return share
	return signf(share) * (absf(share) - excess + 2.0 * excess * diff_lock)


## Returns the torque at the driven wheels (both together), Nm.
func _update_engine(delta: float) -> float:
	var ratio := _gear_ratio(gear) * final_drive
	var driven_speed := 0.0
	var driven_count := 0
	for wheel in _wheels:
		if wheel.driven and wheel.grounded:
			driven_speed += linear_velocity.dot(-global_basis.z)
			driven_count += 1
	var wheel_omega := (driven_speed / driven_count) / wheel_radius if driven_count > 0 else 0.0

	var engaged := gear != 0 and not is_shifting
	var torque := 0.0
	if engaged:
		var wheel_rpm := absf(wheel_omega * ratio) * RPM_PER_RAD_S
		# Below idle the clutch slips (auto-clutch, no stalling), letting
		# the engine rev up for a launch.
		var launch_rpm := idle_rpm + throttle * 1800.0
		# An electric motor (idle 0) has no clutch: it's always connected.
		clutch = clampf(wheel_rpm / launch_rpm, 0.0, 1.0) if launch_rpm > 1.0 else 1.0
		var target := maxf(wheel_rpm, launch_rpm)
		# A lighter flywheel (free_rev_up above stock) picks up revs quicker.
		var response := 20.0 * free_rev_up / maxf(float(_stock.get("free_rev_up", free_rev_up)), 1.0)
		rpm = lerpf(rpm, target, 1.0 - exp(-response * delta))
		torque = _torque_at(rpm) * throttle * oil_factor()
		if rpm >= limiter_rpm:
			torque = 0.0
		torque -= engine_brake_per_krpm * rpm / 1000.0 * (1.0 - throttle) * clutch
	else:
		clutch = 0.0
		var free_target := idle_rpm + throttle * (limiter_rpm - idle_rpm)
		var rate := free_rev_up if free_target > rpm else free_rev_down
		rpm = move_toward(rpm, free_target, rate * delta)
	rpm = clampf(rpm, idle_rpm * 0.9, limiter_rpm + 100.0)
	engine_load = clampf(torque / (_peak_torque * torque_multiplier), -1.0, 1.0)
	_burn_fuel(maxf(torque, 0.0) * rpm * TAU / 60.0 / 1000.0, delta)
	if not engaged:
		return 0.0
	return torque * ratio * drivetrain_efficiency


## Roughly 0.8 L/h at idle plus 0.4 L per kWh delivered: about 6-7 L/100 km
## at a steady 60, more when you lean on it.
func _burn_fuel(power_kw: float, delta: float) -> void:
	if fuel_litres <= 0.0:
		return
	var before := fuel_litres
	var per_hour := fuel_idle_per_hour + power_kw * fuel_per_kwh
	fuel_litres = maxf(0.0, fuel_litres - per_hour / 3600.0 * fuel_use_scale * delta)
	var low := tank_litres * LOW_FUEL_FRACTION
	if before >= low and fuel_litres < low:
		fuel_low.emit()
	if fuel_litres <= 0.0:
		fuel_empty.emit()


## Add fuel; returns the litres that actually fit.
func refuel(litres: float) -> float:
	var added := clampf(litres, 0.0, tank_litres - fuel_litres)
	fuel_litres += added
	return added


func fuel_fraction() -> float:
	return fuel_litres / tank_litres


func _torque_at(at_rpm: float) -> float:
	return _stock_torque_at(at_rpm) * torque_multiplier


func _stock_torque_at(at_rpm: float) -> float:
	if at_rpm <= torque_curve[0].x:
		return torque_curve[0].y
	for i in range(1, torque_curve.size()):
		if at_rpm <= torque_curve[i].x:
			var a := torque_curve[i - 1]
			var b := torque_curve[i]
			return lerpf(a.y, b.y, (at_rpm - a.x) / (b.x - a.x))
	return torque_curve[torque_curve.size() - 1].y


func _update_lights() -> void:
	var lights := get_node_or_null("Headlights")
	if lights:
		lights.visible = headlights_on or flashing
		for lamp in lights.find_children("*", "Light3D", true, false):
			_keep_out_of_rooms(lamp)
	for lamp in find_children("*", "SpotLight3D", true, false):
		if lamp.is_in_group(&"car_spotlights"):
			lamp.visible = headlights_on
			_keep_out_of_rooms(lamp)
	var body := get_node_or_null("Body")
	var fog_part := body.get_node_or_null(^"Part_lights") if body else null
	if fog_part and fog_part.has_meta("fog_lens"):
		var lens: ShaderMaterial = fog_part.get_meta("fog_lens")
		lens.set_shader_parameter("emission_color", FOG_GLOW)
		lens.set_shader_parameter("emission_energy", 1.1 if headlights_on else 0.0)
	headlights_changed.emit(headlights_on)


## Lights have no shadows, so without this they'd shine through the
## townhouse walls onto everything inside (HomeBase marks it).
static func _keep_out_of_rooms(lamp: Light3D) -> void:
	lamp.light_cull_mask &= ~(HomeBase.INDOOR_LAYER | OtherHouse.LAYER_1979)


func _on_body_entered(_body: Node) -> void:
	var change := (linear_velocity - _last_velocity).length()
	if change > 1.5:
		impact.emit(change)
