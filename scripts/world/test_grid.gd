extends Node3D
## Throwaway test world for tuning the car: a car park, an oval, a hill, a few
## surfaces, cones, street lights and a block of placeholder buildings, all on
## a big gridded ground plane. Gets replaced by the real Perth map (map/).
##
## Every collider sets `surface` metadata, which is how the car picks grip.

const ROAD_Y := 0.02

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 500
	var ground := PS1Material.blockout(Color(0.42, 0.44, 0.4), 4.0)
	_slab(Vector3(0, -0.5, 0), Vector3(1600, 1, 1600), Vector3.ZERO, &"concrete", ground)

	var asphalt := PS1Material.road()
	var paint := PS1Material.make(Color(0.85, 0.85, 0.8), 0.7, 0.6)

	# Car park around the spawn point, with bays.
	_road(Vector3(0, 0, -20), Vector2(60, 60), 0.0, asphalt)
	for i in 8:
		_line(Vector3(-24.0 + i * 3.0, 0, -44), Vector2(0.12, 5.0), 0.0, paint)
		_line(Vector3(6.0 + i * 3.0, 0, -44), Vector2(0.12, 5.0), 0.0, paint)

	# Road from the car park out to the oval.
	_road(Vector3(65, 0, -40), Vector2(70, 8), 0.0, asphalt)
	_dashes(Vector3(30, 0, -40), Vector3(100, 0, -40), paint)

	# The oval: two straights joined by semicircles.
	var center := Vector3(160, 0, -100)
	for x in [-60.0, 60.0]:
		_road(center + Vector3(x, 0, 0), Vector2(8, 120), 0.0, asphalt)
		_dashes(center + Vector3(x, 0, 60), center + Vector3(x, 0, -60), paint)
	for end in [-1.0, 1.0]:
		var arc_center := center + Vector3(0, 0, 60.0 * end)
		var segments := 16
		for s in segments:
			var a := PI * (float(s) + 0.5) / segments
			var dir := Vector3(-cos(a), 0, sin(a) * end)
			var pos := arc_center + dir * 60.0
			var heading := atan2(dir.x, dir.z) + PI * 0.5
			_road(pos, Vector2(8, 60.0 * PI / segments + 0.6), heading, asphalt)

	# A hill to test weight transfer and engine load.
	var hill := PS1Material.road(Color(0.26, 0.25, 0.25))
	var angle := deg_to_rad(8.0)
	var rise := 40.0 * sin(angle)
	_slab(Vector3(-80, rise - 0.5, -60), Vector3(12, 1, 30), Vector3.ZERO, &"asphalt", hill)
	for side in [1.0, -1.0]:
		var run := 40.0 * cos(angle)
		var top := Vector3(-80, rise * 0.5, -60 + side * (15.0 + run * 0.5))
		var normal := Vector3(0, cos(angle), side * sin(angle))
		_slab(top - normal * 0.5, Vector3(12, 1, 40), Vector3(rad_to_deg(angle) * side, 0, 0), &"asphalt", hill)

	# A small kicker ramp in the car park corner.
	_slab(Vector3(-20, 0.3, -42), Vector3(5, 0.4, 6), Vector3(10, 0, 0), &"concrete", PS1Material.make(Color(0.6, 0.55, 0.45)))

	# Loose surfaces south of the car park.
	_slab(Vector3(-18, -0.48, 32), Vector3(30, 1, 24), Vector3.ZERO, &"gravel", PS1Material.make(Color(0.55, 0.48, 0.38)))
	_slab(Vector3(18, -0.48, 32), Vector3(30, 1, 24), Vector3.ZERO, &"grass", PS1Material.make(Color(0.3, 0.45, 0.22)))

	# Cone slalom.
	for i in 8:
		_cone(Vector3(-12.0 + (i % 2) * 3.0, 0.4, -8.0 - i * 4.0))

	# Street lights.
	for x in range(36, 100, 22):
		_street_light(Vector3(x, 0, -45.5))
	for z in range(-150, -40, 28):
		_street_light(Vector3(center.x - 65.5, 0, z))
		_street_light(Vector3(center.x + 65.5, 0, z))

	# Placeholder job sites with Perth names, until the map supplies real ones.
	var hill_top := Vector3(-80, rise, -60)
	_site("little_shenton_lane", "Little Shenton Lane", "Northbridge", Vector3(0, 0, 8))
	_site("northbridge_piazza", "Northbridge Piazza", "Northbridge", Vector3(20, 0, -45))
	_site("oxford_st", "Oxford Street", "Leederville", Vector3(100, 0, -40))
	_site("subiaco_markets", "Station Street Markets", "Subiaco", Vector3(220, 0, -100))
	_site("kings_park_lookout", "Kings Park lookout", "West Perth", hill_top)
	_site("fremantle_markets", "Fremantle Markets", "Fremantle", Vector3(160, 0, -218))
	_site("cottesloe_surf_club", "Surf club car park", "Cottesloe", Vector3(160, 0, 18))
	_site("beaufort_st", "Beaufort Street", "Mount Lawley", Vector3(-225, 0, -225))
	_site("albany_hwy", "Albany Highway", "Victoria Park", Vector3(-315, 0, -135))
	_site("scarborough_beach", "Scarborough Beach", "Scarborough", Vector3(-18, 0, 32))
	_site("guildford_antiques", "James Street antiques", "Guildford", Vector3(-135, 0, -315))

	# Placeholder workshops: your carport at home, a spray shop and a servo.
	_workshop("home_carport", "Carport", ["parts", "tuning"], Vector3(-7, 0, 4))
	_workshop("spray_shop", "Osborne Park Smash & Spray", ["paint"], Vector3(66, 0, -36), Color(1.0, 0.6, 0.35))
	_workshop("fitzgerald_st_servo", "Fitzgerald St servo", ["fuel", "wash"], Vector3(12, 0, 4), Color(0.95, 0.85, 0.4))

	# Placeholder town block for scale, silhouettes and fog depth.
	var colours := [Color(0.78, 0.72, 0.62), Color(0.6, 0.62, 0.66), Color(0.82, 0.8, 0.76), Color(0.55, 0.45, 0.4)]
	for gx in 6:
		for gz in 6:
			if _rng.randf() < 0.15:
				continue
			var size := Vector3(_rng.randf_range(10, 20), _rng.randf_range(6, 40), _rng.randf_range(10, 20))
			var pos := Vector3(-300 + gx * 30, size.y * 0.5, -300 + gz * 30)
			_slab(pos, size, Vector3.ZERO, &"concrete", PS1Material.make(colours[_rng.randi() % colours.size()], 0.9, 0.3))
	for i in 7:
		_road(Vector3(-315 + i * 30, 0, -225), Vector2(8, 190), 0.0, asphalt)
		_road(Vector3(-225, 0, -315 + i * 30), Vector2(190, 8), 0.0, asphalt)


func _workshop(id: String, title: String, kinds: PackedStringArray, pos: Vector3, color := Color(0.6, 0.85, 0.8)) -> void:
	var spot := WorkshopSpot.new()
	spot.spot_id = id
	spot.display_name = title
	spot.kinds = kinds
	spot.color = color
	spot.position = pos
	add_child(spot)


func _site(id: String, title: String, suburb: String, pos: Vector3) -> void:
	var site := JobSite.new()
	site.site_id = id
	site.display_name = title
	site.suburb = suburb
	site.position = pos
	add_child(site)


func _slab(pos: Vector3, size: Vector3, rot_deg: Vector3, surface: StringName, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	body.set_meta("surface", surface)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	# Extra subdivisions on big faces so vertex snapping and fog look right.
	box_mesh.subdivide_width = clampi(int(size.x / 8.0), 0, 64)
	box_mesh.subdivide_depth = clampi(int(size.z / 8.0), 0, 64)
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	return body


func _road(pos: Vector3, size: Vector2, heading: float, material: Material) -> void:
	var body := _slab(pos + Vector3(0, ROAD_Y - 0.25, 0), Vector3(size.x, 0.5, size.y), Vector3.ZERO, &"asphalt", material)
	body.rotation.y = heading


func _line(pos: Vector3, size: Vector2, heading: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = material
	mesh.position = pos + Vector3(0, ROAD_Y + 0.01, 0)
	mesh.rotation.y = heading
	add_child(mesh)


func _dashes(from: Vector3, to: Vector3, material: Material) -> void:
	var length := from.distance_to(to)
	var dir := (to - from).normalized()
	var heading := atan2(dir.x, dir.z)
	var d := 1.5
	while d < length:
		_line(from + dir * d, Vector2(0.15, 3.0), heading, material)
		d += 9.0


func _cone(pos: Vector3) -> void:
	var cone := RigidBody3D.new()
	cone.mass = 3.0
	cone.position = pos
	cone.set_meta("surface", &"concrete")
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.18
	cylinder.height = 0.7
	shape.shape = cylinder
	cone.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.03
	cone_mesh.bottom_radius = 0.2
	cone_mesh.height = 0.7
	cone_mesh.radial_segments = 6
	mesh.mesh = cone_mesh
	mesh.material_override = PS1Material.make(Color(1.0, 0.45, 0.1))
	cone.add_child(mesh)
	add_child(cone)


func _street_light(pos: Vector3) -> void:
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.07
	post_mesh.bottom_radius = 0.1
	post_mesh.height = 7.0
	post_mesh.radial_segments = 6
	post.mesh = post_mesh
	post.material_override = PS1Material.make(Color(0.35, 0.36, 0.38), 0.6)
	post.position = pos + Vector3(0, 3.5, 0)
	add_child(post)

	var lamp := Node3D.new()
	lamp.position = pos + Vector3(0, 6.9, 0)
	lamp.add_to_group("night_lights")
	var bulb := MeshInstance3D.new()
	var bulb_mesh := BoxMesh.new()
	bulb_mesh.size = Vector3(0.5, 0.15, 0.3)
	bulb.mesh = bulb_mesh
	bulb.material_override = PS1Material.glowing(Color(1.0, 0.75, 0.45), 3.0)
	lamp.add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.42)
	light.light_energy = 2.5
	light.omni_range = 16.0
	light.omni_attenuation = 1.4
	light.position = Vector3(0, -0.4, 0)
	lamp.add_child(light)
	add_child(lamp)
