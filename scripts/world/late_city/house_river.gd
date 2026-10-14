class_name HouseRiver
extends House1979
## The house over the river (OtherHouse, act 4, STORY.md event 1): the
## walls, stairs and doors are there, but the downstairs floor is black water
## lit from somewhere underneath, wrong birds sit along the stair rail, and
## the far wall is the river at night with the lights on it.
##
## Built in the house's frame like House1979, without the Dorans' furniture.
## The water and the far wall aren't PS1 surfaces, so OtherHouse shows them
## only once you're inside.

const DEEP := Color(0.1, 0.45, 0.5)
const BIRD := Color(0.06, 0.06, 0.07)
const BIRD_EYE := Color(0.95, 0.7, 0.3)
## The water's surface just above the floor (0.15), and the far wall (house frame).
const WATER_Z := 0.17
const FAR_WALL_Y := 11.95
## Birds on the stair rail: [back, up] along the open side of the stairs.
const RAIL_X := 1.02
const PERCHES := [Vector2(8.4, 1.25), Vector2(7.6, 1.85), Vector2(6.9, 2.4), Vector2(6.1, 3.0), Vector2(5.4, 3.55)]

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 size = vec2(5.4, 12.0);
void fragment() {
	vec2 p = UV * size;
	float a = sin(dot(p, vec2(5.3, 2.1)) + TIME * 0.7) + sin(dot(p, vec2(-3.7, 4.9)) - TIME * 0.5)
		+ sin(dot(p, vec2(1.3, -7.1)) + TIME * 0.9);
	float swell = sin(dot(p, vec2(0.6, 1.1)) - TIME * 0.25) * 0.5 + 0.5;
	float glint = smoothstep(2.1, 2.8, a);
	ALBEDO = vec3(0.005, 0.018, 0.028) + vec3(0.0, 0.012, 0.016) * swell + vec3(0.06, 0.17, 0.19) * glint;
}
"""

var birds: Array[Node3D] = []


func _ready() -> void:
	name = "HouseRiver"
	_water()
	_far_wall()
	# Lit from under the water: dim green-blue, low down.
	for p: Vector3 in [Vector3(3.0, 2.5, -0.2), Vector3(3.0, 7.0, -0.2), Vector3(3.0, 10.5, -0.2), Vector3(0.6, 7.5, -0.2)]:
		lights.append(_light(p, DEEP, 0.9, 4.5))
	lights.append(_light(Vector3(2.7, 11.2, 1.4), Color(0.9, 0.7, 0.45), 0.35, 4.0))
	# Enough on the stair rail to make out the birds.
	lights.append(_light(Vector3(1.9, 7.0, 3.2), Color(0.55, 0.7, 0.75), 0.5, 3.0))
	for i in PERCHES.size():
		_bird(PERCHES[i], i)


func _water() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.4, 12.0)
	mi.mesh = plane
	var m := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = WATER_SHADER
	m.shader = shader
	mi.material_override = m
	mi.position = House1979.at(Vector3(2.7, 6.0, WATER_Z))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The far wall: the river at night from low on the water, the far shore's
## lights and their long reflections.
func _far_wall() -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.3, 2.7)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(river_image())
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = m
	mi.position = House1979.at(Vector3(2.7, FAR_WALL_Y, 1.38))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)  # a quad faces +z, back toward the front door


static func river_image() -> Image:
	var w := 160
	var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var shore := 34
	var skyline := PackedInt32Array()
	var x := 0
	while x < w:
		var bw := rng.randi_range(3, 9)
		var bh := rng.randi_range(2, 14)
		for k in bw:
			if x + k < w:
				skyline.append(shore - bh)
		x += bw
	for py in h:
		for px in w:
			var c: Color
			if py < skyline[px]:
				c = Color(0.02, 0.03, 0.07).lerp(Color(0.1, 0.06, 0.08), py / float(shore))
			elif py < shore:
				c = Color(0.015, 0.015, 0.02)
				if rng.randf() < 0.06:
					c = Color(1.0, 0.75, 0.35)
			else:
				c = Color(0.01, 0.02, 0.03).lerp(Color(0.0, 0.0, 0.01), (py - shore) / float(h - shore))
			img.set_pixel(px, py, c)
	# The lights along the far shore, and each one's reflection, broken up.
	for i in 26:
		var lx := rng.randi_range(2, w - 3)
		var colour := Color(1.0, 0.62, 0.22) if rng.randf() < 0.7 else Color(0.85, 0.9, 1.0)
		img.set_pixel(lx, shore - 1, colour)
		for py in range(shore + 1, mini(h, shore + rng.randi_range(14, 40))):
			if rng.randf() < 0.55:
				var fade := 1.0 - (py - shore) / 40.0
				img.set_pixel(lx + rng.randi_range(-1, 1), py, Color(0, 0, 0).lerp(colour, 0.7 * fade))
	return img


## A still, dark bird on the rail, facing down into the hall. Wrong: too
## still, the eye catching light that isn't there.
func _bird(perch: Vector2, i: int) -> void:
	var root := Node3D.new()
	root.position = House1979.at(Vector3(RAIL_X, perch.x, perch.y))
	root.rotation.y = PI * 0.5 + (0.25 if i % 2 == 0 else -0.2)
	root.scale = Vector3.ONE * 1.5  # crow-sized
	add_child(root)
	# Hunched, crow-shaped: body, breast, head and a heavy beak, a long tail
	# angled down over the rail, legs gripping it.
	_box(Vector3(0.09, 0.17, 0.11), Vector3(0, 0.0, 0.07), BIRD, 0.0, root)
	_box(Vector3(0.075, 0.06, 0.085), Vector3(0, -0.08, 0.05), BIRD, 0.0, root)
	_box(Vector3(0.06, 0.07, 0.065), Vector3(0, -0.1, 0.155), BIRD, 0.0, root)
	_box(Vector3(0.018, 0.065, 0.018), Vector3(0, -0.165, 0.145), Color(0.08, 0.08, 0.09), 0.0, root)
	var tail := _box(Vector3(0.05, 0.17, 0.012), Vector3(0, 0.15, 0.0), BIRD, 0.0, root)
	tail.rotation.x = -0.45
	for s in [-1.0, 1.0]:
		_box(Vector3(0.008, 0.008, 0.05), Vector3(s * 0.022, -0.01, -0.01), Color(0.08, 0.08, 0.09), 0.0, root)
		_box(Vector3(0.006, 0.012, 0.012), Vector3(s * 0.031, -0.12, 0.165), BIRD_EYE, 2.0, root)
	birds.append(root)
