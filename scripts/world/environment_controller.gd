extends Node
## Turns GameClock and Weather into what you see: sun and moon, sky colours,
## fog, ambient light, rain, lightning flashes and street lights.
##
## Anything that should glow at night can join the "night_lights" group. If it
## has a `set_night_amount(amount: float)` method that gets called with 0..1,
## otherwise it is simply shown when it's dark enough.

@export var world_environment_path: NodePath
@export var sun_path: NodePath
@export var moon_path: NodePath
@export var rain_path: NodePath

@export_group("Fog")
## Fog density in clear daylight. Rain and night thicken it.
@export var fog_density_clear := 0.0035
@export var fog_density_rain := 0.012
@export var fog_density_storm := 0.024

# Sky palettes: [top, horizon] for night, twilight and day, plus an overcast tint.
const NIGHT_TOP := Color(0.01, 0.015, 0.04)
const NIGHT_HORIZON := Color(0.1, 0.09, 0.13)
# Night ambient: moonlight plus the city's sodium glow bouncing off the cloud,
# so streets stay readable without headlights.
const NIGHT_FILL := Color(0.3, 0.33, 0.44)
const DUSK_TOP := Color(0.18, 0.2, 0.42)
const DUSK_HORIZON := Color(0.95, 0.5, 0.3)
const DAY_TOP := Color(0.24, 0.48, 0.85)
const DAY_HORIZON := Color(0.7, 0.8, 0.9)
const OVERCAST := Color(0.5, 0.53, 0.57)

var _environment: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _rain: GPUParticles3D
var _flash := 0.0
## -1 until the first update, so lights start in the right state.
var _night_lights_on := -1


func _ready() -> void:
	var world_env := get_node(world_environment_path) as WorldEnvironment
	_environment = world_env.environment
	_sky = _environment.sky.sky_material as ProceduralSkyMaterial
	_sun = get_node(sun_path)
	_moon = get_node(moon_path)
	_rain = get_node_or_null(rain_path)
	Weather.lightning.connect(_on_lightning)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var sun_dir := GameClock.sun_direction()
	var daylight := GameClock.daylight()
	var cloud := Weather.cloud_cover
	var rain := Weather.rain
	# 1 around sunrise/sunset, 0 at noon and midnight.
	var twilight := clampf(1.0 - absf(sun_dir.y) / 0.25, 0.0, 1.0)
	var overcast := clampf((cloud - 0.2) / 0.8, 0.0, 1.0)

	# Sun.
	if sun_dir.y > -0.2:
		_sun.global_basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var sun_color := Color(1.0, 0.55, 0.3).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.0, 0.35, sun_dir.y))
	_sun.light_color = sun_color
	_sun.light_energy = smoothstep(-0.05, 0.12, sun_dir.y) * 1.0 * (1.0 - 0.75 * overcast)
	_sun.visible = _sun.light_energy > 0.01

	# Moon: roughly opposite the sun, never quite below the horizon.
	var moon_dir := Vector3(-sun_dir.x, maxf(0.35, -sun_dir.y), -sun_dir.z + 0.3).normalized()
	_moon.global_basis = Basis.looking_at(-moon_dir, Vector3.UP)
	_moon.light_energy = (1.0 - daylight) * 0.3 * (1.0 - 0.5 * overcast)
	_moon.visible = _moon.light_energy > 0.01

	# Sky.
	var top := NIGHT_TOP.lerp(DUSK_TOP, clampf(daylight * 2.0, 0.0, 1.0)).lerp(DAY_TOP, clampf(daylight * 2.0 - 1.0, 0.0, 1.0))
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight)
	horizon = horizon.lerp(DUSK_HORIZON, twilight * (1.0 - overcast) * 0.85)
	var grey := OVERCAST * lerpf(0.08, 1.0, daylight)
	top = top.lerp(grey * 0.85, overcast * 0.9)
	horizon = horizon.lerp(grey, overcast * 0.9)
	_flash = maxf(0.0, _flash - delta * 6.0)
	var flash_color := Color(0.75, 0.8, 1.0) * _flash
	_sky.sky_top_color = top + flash_color
	_sky.sky_horizon_color = horizon + flash_color
	_sky.sun_angle_max = 30.0
	_sky.sky_energy_multiplier = 1.0 + _flash * 2.0

	# Fog: PS1-style distance fog that also hides the edge of the world.
	var fog_density := lerpf(fog_density_clear, fog_density_rain, clampf(rain / 0.35, 0.0, 1.0))
	fog_density = lerpf(fog_density, fog_density_storm, clampf((rain - 0.35) / 0.65, 0.0, 1.0))
	fog_density *= lerpf(1.4, 1.0, daylight)
	_environment.fog_density = fog_density
	var fog_color := horizon.lerp(Color(0.02, 0.02, 0.04), lerpf(0.6, 0.15, daylight))
	_environment.fog_light_color = fog_color
	# Below the horizon is always fogged-out ground past the camera's far
	# plane, so the sky's ground half takes the fog colour (no grey band).
	_sky.ground_horizon_color = fog_color
	_sky.ground_bottom_color = fog_color
	_environment.fog_sun_scatter = 0.15 * (1.0 - overcast)

	# Flat ambient colour rather than sky radiance: cheap, very PS1, and it
	# follows the time of day instantly.
	var palette := top.lerp(horizon, 0.5)
	_environment.ambient_light_color = palette.lerp(NIGHT_FILL, (1.0 - daylight) * 0.85) + flash_color
	_environment.ambient_light_energy = lerpf(0.6, 0.9, daylight) * lerpf(1.0, 0.8, overcast) + _flash
	_environment.tonemap_exposure = lerpf(1.25, 0.95, daylight)

	# Rain follows whichever camera is active.
	if _rain:
		_rain.emitting = rain > 0.01
		_rain.amount_ratio = rain
		var camera := get_viewport().get_camera_3d()
		if camera:
			_rain.global_position = camera.global_position + Vector3.UP * 8.0

	# Street lights and anything else that glows at night.
	var night_amount := clampf(1.0 - daylight * 1.6 + overcast * 0.3, 0.0, 1.0)
	var lights_on := night_amount > 0.45
	for node in get_tree().get_nodes_in_group("night_lights"):
		if node.has_method("set_night_amount"):
			node.set_night_amount(night_amount)
		elif int(lights_on) != _night_lights_on:
			node.visible = lights_on
	_night_lights_on = int(lights_on)


func _on_lightning(strength: float, distance_m: float) -> void:
	_flash = maxf(_flash, strength * clampf(2000.0 / distance_m, 0.2, 1.0))
