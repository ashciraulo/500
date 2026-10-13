class_name FindableMarker
extends Node3D
## What every findable has over it, so it reads from the road: a lilac
## sparkle hanging just above it and a soft lilac light and pool on the
## ground round it, all breathing slowly. Lilac and slow, so it can't be
## taken for a sodium street light, a lit window or a photo spot sign; the
## same on a mystery clue, a found part, a cutting and a barn find, so you
## learn it once.
##
## Add one as a child of the thing, at its origin; `height` is where the
## sparkle hangs above that.

const COLOUR := Color(0.72, 0.5, 1.0)
const SHADER := preload("res://shaders/findable_sparkle.gdshader")
const POOL_SHADER := preload("res://shaders/findable_pool.gdshader")
## Breaths per second (the light and the sparkle together).
const SPEED := 0.5

## Where the sparkle hangs (m above the origin).
@export var height := 1.1
## The light's reach, and the width of the pool it throws on the ground (m).
@export var reach := 7.0
## Light energy at the bottom and top of a breath, at night.
@export var energy := Vector2(2.0, 5.0)
## How far off the sparkle still shows (m).
@export var far := 160.0

var _light: OmniLight3D
var _sparkle: MeshInstance3D
var _pool: ShaderMaterial
var _sparkle_material: ShaderMaterial


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = COLOUR
	_light.omni_range = reach
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.position.y = height * 0.6
	add_child(_light)
	_sparkle = MeshInstance3D.new()
	_sparkle.name = "Sparkle"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_sparkle.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"colour", COLOUR)
	material.set_shader_parameter(&"far", far)
	material.set_shader_parameter(&"speed", SPEED)
	_sparkle.material_override = material
	_sparkle_material = material
	_sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader grows it with distance; don't let the quad's own box cull it.
	_sparkle.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_sparkle.position.y = height
	add_child(_sparkle)
	# The light alone can lose out to the street lights' share of a big
	# ground mesh (the Compatibility renderer's per-object light limit), so it
	# also throws a pool, drawn like the street lamps' pools.
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * reach
	_pool = ShaderMaterial.new()
	_pool.shader = POOL_SHADER
	_pool.set_shader_parameter(&"colour", COLOUR)
	_pool.set_shader_parameter(&"speed", SPEED)
	plane.material = _pool
	pool.mesh = plane
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position.y = 0.06
	add_child(pool)


func _process(_delta: float) -> void:
	# In step with the sparkle (the shader's TIME runs from start-up too).
	var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * SPEED * TAU)
	var dark := clampf(1.0 - GameClock.daylight() * 1.5, 0.0, 1.0)
	_light.visible = dark > 0.01
	_light.light_energy = lerpf(energy.x, energy.y, breath) * dark
	_pool.set_shader_parameter(&"energy", 1.1 * dark)
	_sparkle_material.set_shader_parameter(&"day", 1.0 - dark)
