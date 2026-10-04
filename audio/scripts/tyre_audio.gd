class_name TyreAudio
extends Node3D
## Tyres, road surfaces and crashes for one car. Add as a child of the
## vehicle (or set vehicle_path).
##
## The vehicle is vehicle_path or the nearest ancestor with get_telemetry()
## (CarController): speed_kmh, surface, tire_slip, wetness, grounded_wheels,
## and its impact(strength) signal for crashes. Other nodes can provide
## speed_kmh, surface, wheel_slip, wet and a collided(impulse) signal instead.
## Or call the one-shot methods from gameplay code: splash(), kerb(),
## pothole(), speed_bump(), expansion_joint(), cats_eye(), metal_plate(),
## impact(impulse, material), and set scraping / rumble_strip while they last.

@export var vehicle_path: NodePath
@export var volume_db := 0.0

var speed_kmh := 0.0
var surface: StringName = &"asphalt"
var wheel_slip := 0.0
var wet := false
var scraping := 0.0      # 0..1 while grinding along a wall
var rumble_strip := false

## Roll loop per surface, and the road speed (km/h) each loop was made at.
const ROLL := {
	"asphalt": [["tyre/tyre_roll_dry_slow", 20.0], ["tyre/tyre_roll_dry_mid", 55.0], ["tyre/tyre_roll_dry_fast", 100.0]],
	"brick": [["tyre/tyre_surface_brick", 30.0]],
	"gravel": [["tyre/tyre_surface_gravel", 30.0]],
	"grass": [["tyre/tyre_surface_grass", 30.0]],
	"sand": [["tyre/tyre_surface_sand", 25.0]],
	"wet": [["tyre/tyre_roll_wet", 50.0]],
}

## Game surfaces that share a sound.
const SURFACE_ALIAS := {&"concrete": &"asphalt", &"dirt": &"gravel"}

var _vehicle: Node
var _roll := {}          # sound name -> AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _skid_wet: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _rumble: AudioStreamPlayer3D
var _last_slip := 0.0
var _last_plate_t := 0.0


func _ready() -> void:
	_vehicle = EngineAudio.find_vehicle(self, vehicle_path)
	for sig in ["impact", "collided"]:
		if _vehicle and _vehicle.has_signal(sig):
			_vehicle.connect(sig, func(impulse: float) -> void: impact(impulse))
			break
	for layers in ROLL.values():
		for l in layers:
			if Audio.has(l[0]) and not _roll.has(l[0]):
				_roll[l[0]] = _loop(l[0])
	_skid = _loop("tyre/tyre_skid_dry")
	_skid_wet = _loop("tyre/tyre_skid_wet")
	_scrape = _loop("impact/impact_metal_scrape")
	_rumble = _loop("tyre/tyre_rumble_strip")


func _loop(sound: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = Audio.stream(sound, true) if Audio.has(sound) else null
	p.bus = "Tyres"
	p.unit_size = 8.0
	p.max_distance = 150.0
	p.volume_db = -80.0
	add_child(p)
	return p


func _set_level(p: AudioStreamPlayer3D, w: float, pitch := 1.0) -> void:
	if p == null or p.stream == null:
		return
	if w < 0.002:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play(randf() * p.stream.get_length())
	p.volume_db = volume_db + linear_to_db(w)
	p.pitch_scale = clampf(pitch, 0.5, 2.0)


var _airborne := false


func _process(_delta: float) -> void:
	if _vehicle and _vehicle.has_method("get_telemetry"):
		var t: Dictionary = _vehicle.get_telemetry()
		speed_kmh = absf(float(t.get("speed_kmh", 0.0)))
		var surf := StringName(t.get("surface", &"asphalt"))
		surface = SURFACE_ALIAS.get(surf, surf)
		wheel_slip = clampf(float(t.get("tire_slip", 0.0)), 0.0, 1.0)
		wet = float(t.get("wetness", 0.0)) > 0.25
		var grounded := int(t.get("grounded_wheels", 4))
		if grounded == 0:
			_airborne = true
		elif _airborne:
			_airborne = false
			speed_bump()  # landing thud
		if grounded == 0:
			speed_kmh = 0.0  # wheels in the air make no road noise
	elif _vehicle:
		if "speed_kmh" in _vehicle:
			speed_kmh = absf(float(_vehicle.speed_kmh))
		if "surface" in _vehicle:
			surface = StringName(_vehicle.surface)
		if "wheel_slip" in _vehicle:
			wheel_slip = clampf(float(_vehicle.wheel_slip), 0.0, 1.0)
		if "wet" in _vehicle:
			wet = bool(_vehicle.wet)
		else:
			wet = Audio.ambience.rain > 0.15
	_mix_roll()
	# Skids: a squeal on dry roads, a hiss on wet. Quick slips just chirp.
	var slip := wheel_slip * clampf(speed_kmh / 15.0, 0.0, 1.0)
	var on_road := surface in [&"asphalt", &"brick", &"metal"]
	_set_level(_skid, slip * (0.0 if wet or not on_road else 1.0), 0.9 + 0.2 * slip)
	_set_level(_skid_wet, slip * (1.0 if wet or not on_road else 0.0), 0.9 + 0.2 * slip)
	if on_road and not wet and slip > 0.35 and _last_slip <= 0.35 and speed_kmh > 10.0:
		Audio.play_at("tyre/tyre_skid_chirp", global_position, volume_db - 4.0, "Tyres")
	_last_slip = slip
	_set_level(_scrape, scraping, 0.8 + clampf(speed_kmh / 80.0, 0.0, 0.6))
	_set_level(_rumble, (1.0 if rumble_strip else 0.0) * clampf(speed_kmh / 20.0, 0.0, 1.0),
			clampf(speed_kmh / 60.0, 0.5, 2.0))
	if surface == &"metal" and speed_kmh > 5.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_plate_t > 0.6:
			_last_plate_t = now
			metal_plate()


func _mix_roll() -> void:
	var key := "wet" if wet and surface == &"asphalt" else String(surface)
	if not ROLL.has(key):
		key = "asphalt"
	var active: Array = ROLL[key]
	var moving := clampf(speed_kmh / 8.0, 0.0, 1.0)
	for sound in _roll.keys():
		var w := 0.0
		var pitch := 1.0
		for i in active.size():
			if active[i][0] != sound:
				continue
			var ref: float = active[i][1]
			pitch = clampf((speed_kmh + 10.0) / (ref + 10.0), 0.5, 1.8)
			if active.size() == 1:
				w = clampf(speed_kmh / ref, 0.0, 1.3)
			else:
				# Crossfade speed layers like the engine does with RPM.
				var lo: float = active[i - 1][1] if i > 0 else -1.0
				var hi: float = active[i + 1][1] if i < active.size() - 1 else 1e9
				if speed_kmh < ref:
					w = 1.0 if lo < 0.0 else sin(clampf((speed_kmh - lo) / (ref - lo), 0.0, 1.0) * PI * 0.5)
				else:
					w = 1.0 if hi > 1e8 else cos(clampf((speed_kmh - ref) / (hi - ref), 0.0, 1.0) * PI * 0.5)
		_set_level(_roll[sound], w * moving, pitch)


# ---------------------------------------------------------------------------
# One-shots
# ---------------------------------------------------------------------------

func splash(big := false) -> void:
	Audio.play_at("tyre/tyre_splash_big" if big else "tyre/tyre_splash_small", global_position, volume_db, "Tyres")


func kerb() -> void:
	Audio.play_at("tyre/tyre_kerb_hit", global_position, volume_db, "Tyres")


func pothole() -> void:
	Audio.play_at("tyre/tyre_pothole", global_position, volume_db, "Tyres")


func speed_bump() -> void:
	Audio.play_at("tyre/tyre_speed_bump", global_position, volume_db, "Tyres")


## The Narrows Bridge "ka-thunk".
func expansion_joint() -> void:
	Audio.play_at("tyre/tyre_expansion_joint", global_position, volume_db, "Tyres")


func cats_eye() -> void:
	Audio.play_at("tyre/tyre_cats_eyes", global_position, volume_db - 6.0, "Tyres")


func metal_plate() -> void:
	Audio.play_at("tyre/tyre_metal_plate", global_position, volume_db - 2.0, "Tyres")


## A collision. impulse is roughly the change in speed in m/s (0..20+).
## material: "metal" (default), "plastic" (bumper tap), "glass".
func impact(impulse: float, material := "metal") -> void:
	if impulse < 0.8:
		return
	var sound := "impact/impact_light"
	if material == "plastic" or (impulse < 2.0 and material == "metal"):
		sound = "impact/impact_plastic_bumper" if material == "plastic" else "impact/impact_light"
	elif impulse < 6.0:
		sound = "impact/impact_medium"
	else:
		sound = "impact/impact_heavy"
	var vol := volume_db + clampf(linear_to_db(impulse / 8.0), -12.0, 0.0)
	Audio.play_at(sound, global_position, vol, "SFX")
	if material == "glass" or impulse > 9.0:
		Audio.play_at("impact/impact_glass_crack", global_position, vol - 3.0, "SFX")


## Street furniture the car knocks over: "wheelie_bin", "traffic_cone",
## "mesh_fence", "signpost", "shopping_trolley".
func hit_object(kind: String, pos := Vector3.INF) -> void:
	Audio.play_at("impact/impact_" + kind, global_position if pos == Vector3.INF else pos, volume_db, "SFX")
