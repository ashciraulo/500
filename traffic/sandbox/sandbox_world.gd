class_name TrafficSandboxWorld
extends Node3D
## Draws a traffic network so it can be driven and looked at without the real
## map: ground, roads with lane markings, footpaths, rails, a station
## platform, low-poly buildings, trees and street lights. Only for the
## traffic sandbox; the real roads come from the map.

const ROAD_Y := 0.02

var _rng := RandomNumberGenerator.new()


func build(graph: TrafficGraph) -> void:
	_rng.seed = 6000
	var ground := StaticBody3D.new()
	ground.set_meta("surface", &"asphalt")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2400, 1, 2400)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	add_child(ground)
	var grass := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	plane.subdivide_width = 60
	plane.subdivide_depth = 60
	grass.mesh = plane
	grass.material_override = PS1Material.make(Color(0.27, 0.33, 0.2))
	grass.position.y = -0.02
	add_child(grass)

	var asphalt := Builder.new()
	var paint := Builder.new()
	var paths := Builder.new()
	for road in graph.roads:
		asphalt.ribbon(road.pts, -road.half_width, road.half_width, ROAD_Y)
		if road.walk:
			paths.ribbon(road.pts, road.half_width, road.half_width + 3.2, ROAD_Y + 0.06)
			paths.ribbon(road.pts, -road.half_width - 3.2, -road.half_width, ROAD_Y + 0.06)
		_markings(paint, road)
	var ring_points: Array = []
	for node in graph.nodes.values():
		if node.roads.any(func(r): return r.roundabout):
			ring_points.append(node.pos)
			continue
		if node.degree() >= 3:
			asphalt.disc(node.pos + Vector3(0, ROAD_Y + 0.004, 0), node.radius + 0.5, 14)
		elif node.degree() == 2:
			asphalt.disc(node.pos + Vector3(0, ROAD_Y + 0.004, 0), node.roads[0].half_width, 10)
	if not ring_points.is_empty():
		# The roundabout's island.
		var center := Vector3.ZERO
		for p in ring_points:
			center += p
		center /= ring_points.size()
		var island := Builder.new()
		island.disc(center + Vector3(0, 0.15, 0), center.distance_to(ring_points[0]) - 4.0, 16)
		_add_mesh(island.commit(), PS1Material.make(Color(0.3, 0.42, 0.24)))
	for lane in graph.lanes:
		if lane.signal_gate or _yields(lane):
			var end: Vector3 = lane.point(lane.length)
			var dir: Vector3 = lane.tangent(lane.length)
			var left := TrafficGraph.left_of(dir)
			paint.quad_flat(end + left * 1.55 + Vector3(0, 0.012, 0), end - left * 1.55 + Vector3(0, 0.012, 0), dir, 0.35)
	_add_mesh(asphalt.commit(), PS1Material.road())
	_add_mesh(paint.commit(), PS1Material.make(Color(0.88, 0.88, 0.84), 0.7, 0.6))
	_add_mesh(paths.commit(), PS1Material.make(Color(0.4, 0.39, 0.37), 0.9, 0.7))

	# Railway: ballast and two rails per track, a platform at the station.
	var ballast := Builder.new()
	var rails := Builder.new()
	for edge in graph.rail_edges:
		ballast.ribbon(edge.pts, -1.7, 1.7, ROAD_Y + 0.03)
		for x in [-0.72, 0.72]:
			rails.ribbon(edge.pts, x - 0.05, x + 0.05, ROAD_Y + 0.14)
		for st in edge.stations:
			var p := TrafficGraph.point_at(edge.pts, edge.cum, st.s)
			var dir := TrafficGraph.tangent_at(edge.pts, edge.cum, st.s)
			var side := TrafficGraph.left_of(dir)
			# Platform on the outside of each track.
			var probe := p + side * 4.0
			var outside := side if _no_rail_near(graph, probe) else -side
			_platform(p + outside * 3.6, dir)
	_add_mesh(ballast.commit(), PS1Material.make(Color(0.42, 0.38, 0.34)))
	_add_mesh(rails.commit(), PS1Material.make(Color(0.5, 0.5, 0.52), 0.4))

	_buildings(graph)
	_street_lights(graph)


func _yields(lane: TrafficGraph.Lane) -> bool:
	for c in lane.next:
		if not c.yield_to.is_empty() or c.full_stop:
			return c.turn != TrafficGraph.Turn.STRAIGHT or c.node.degree() >= 3
	return false


func _markings(paint: Builder, road: TrafficGraph.Road) -> void:
	if road.length < 6.0:
		return
	var trim_a: float = road.a.radius + 1.0
	var trim_b: float = road.b.radius + 1.0
	if trim_a + trim_b > road.length - 4.0:
		return
	var pts := TrafficGraph.cut_polyline(road.pts, trim_a, trim_b)
	var offsets: Array = []
	if road.lanes_back > 0 and not road.roundabout:
		offsets.append([0.0, road.lanes_fwd + road.lanes_back > 2])
		for k in range(1, road.lanes_fwd):
			offsets.append([k * TrafficGraph.LANE_WIDTH, false])
			offsets.append([-k * TrafficGraph.LANE_WIDTH, false])
	else:
		for k in range(1, road.lanes_fwd):
			offsets.append([(k - road.lanes_fwd * 0.5) * TrafficGraph.LANE_WIDTH, false])
	for o in offsets:
		var line := TrafficGraph.offset_polyline(pts, o[0])
		if o[1]:
			# Double centre line on the big roads.
			paint.ribbon(TrafficGraph.offset_polyline(line, 0.18), -0.07, 0.07, ROAD_Y + 0.01)
			paint.ribbon(TrafficGraph.offset_polyline(line, -0.18), -0.07, 0.07, ROAD_Y + 0.01)
		else:
			paint.dashes(line, 0.07, ROAD_Y + 0.01, 3.0, 6.0)


func _no_rail_near(graph: TrafficGraph, p: Vector3) -> bool:
	for e in graph.rail_edges:
		var s := TrafficGraph.closest_s(e.pts, e.cum, p)
		if TrafficGraph.point_at(e.pts, e.cum, s).distance_to(p) < 1.5:
			return false
	return true


func _platform(center: Vector3, dir: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", &"concrete")
	var size := Vector3(3.6, 1.0, 100.0)
	body.position = center + Vector3(0, 0.5, 0)
	body.basis = Basis.looking_at(dir, Vector3.UP)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_depth = 12
	mesh.mesh = bm
	mesh.material_override = PS1Material.make(Color(0.66, 0.64, 0.6))
	body.add_child(mesh)
	# Shelter and a yellow safety line.
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(3.0, 0.15, 30.0)
	roof.mesh = rm
	roof.position = Vector3(0, 3.3, 0)
	roof.material_override = PS1Material.make(Color(0.3, 0.45, 0.42))
	body.add_child(roof)
	add_child(body)


func _buildings(graph: TrafficGraph) -> void:
	var colours := [Color(0.62, 0.55, 0.45), Color(0.55, 0.48, 0.42), Color(0.68, 0.66, 0.6),
		Color(0.5, 0.33, 0.26), Color(0.52, 0.54, 0.52), Color(0.64, 0.6, 0.5)]
	var roofs := [Color(0.45, 0.2, 0.16), Color(0.28, 0.29, 0.32), Color(0.48, 0.48, 0.46)]
	var walls := {}
	for c in colours:
		walls[c] = Builder.new()
	var roof_builders := {}
	for c in roofs:
		roof_builders[c] = Builder.new()
	var trees := Builder.new()
	var trunks := Builder.new()
	var step := 24.0
	var x := -400.0
	while x <= 400.0:
		var z := -400.0
		while z <= 400.0:
			var p := Vector3(x + _rng.randf_range(-4, 4), 0, z + _rng.randf_range(-4, 4))
			var size := Vector3(_rng.randf_range(9, 16), 0, _rng.randf_range(9, 16))
			var clearance := _clearance(graph, p)
			var radius := size.length() * 0.5
			if clearance > radius + 4.5:
				var near_avenue := absf(p.z) < 60.0
				size.y = _rng.randf_range(8, 22) if near_avenue else _rng.randf_range(3.5, 7.0)
				var wall: Color = colours[_rng.randi() % colours.size()]
				walls[wall].box(p + Vector3(0, size.y * 0.5, 0), size)
				if not near_avenue:
					# Pitched roof for the houses.
					var roof: Color = roofs[_rng.randi() % roofs.size()]
					roof_builders[roof].box(p + Vector3(0, size.y + 1.0, 0), Vector3(size.x + 0.6, 2.0, size.z + 0.6), Vector2(0.15, 1.0))
			elif clearance > 6.5 and clearance < 12.0 and _rng.randf() < 0.5:
				_tree(trees, trunks, p)
			z += step
		x += step
	for c in walls:
		_add_mesh(walls[c].commit(), PS1Material.make(c, 0.9, 0.3), true)
	for c in roof_builders:
		_add_mesh(roof_builders[c].commit(), PS1Material.make(c, 0.8, 0.3), true)
	_add_mesh(trees.commit(), PS1Material.make(Color(0.24, 0.36, 0.2)))
	_add_mesh(trunks.commit(), PS1Material.make(Color(0.36, 0.28, 0.2)))


func _tree(trees: Builder, trunks: Builder, p: Vector3) -> void:
	var h := _rng.randf_range(4.0, 7.0)
	trunks.box(p + Vector3(0, h * 0.3, 0), Vector3(0.35, h * 0.6, 0.35))
	trees.box(p + Vector3(0, h * 0.75, 0), Vector3(h * 0.6, h * 0.55, h * 0.6), Vector2(0.4, 0.4))


## Distance from p to the nearest road edge, rail or platform.
func _clearance(graph: TrafficGraph, p: Vector3) -> float:
	var best := INF
	for road in graph.roads:
		var s := TrafficGraph.closest_s(road.pts, road.cum, p)
		var d: float = TrafficGraph.point_at(road.pts, road.cum, s).distance_to(p) - road.half_width - (3.2 if road.walk else 0.0)
		best = minf(best, d)
	for edge in graph.rail_edges:
		var s := TrafficGraph.closest_s(edge.pts, edge.cum, p)
		best = minf(best, TrafficGraph.point_at(edge.pts, edge.cum, s).distance_to(p) - 8.0)
	return best


func _street_lights(graph: TrafficGraph) -> void:
	var posts := Builder.new()
	var count := 0
	for road in graph.roads:
		if road.rank < 4 or count > 24:
			continue
		var s := 15.0
		while s < road.length - 10.0 and count <= 24:
			var p := TrafficGraph.point_at(road.pts, road.cum, s)
			var dir := TrafficGraph.tangent_at(road.pts, road.cum, s)
			var side: Vector3 = TrafficGraph.left_of(dir) * (road.half_width + 0.6) * (1.0 if count % 2 == 0 else -1.0)
			var base: Vector3 = p + side
			posts.box(base + Vector3(0, 3.6, 0), Vector3(0.16, 7.2, 0.16))
			var lamp := Node3D.new()
			lamp.position = base + Vector3(0, 7.0, 0) - side.normalized() * 1.2
			lamp.add_to_group("night_lights")
			var bulb := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.15, 0.35)
			bulb.mesh = bm
			bulb.material_override = PS1Material.glowing(Color(1.0, 0.75, 0.45), 3.0)
			lamp.add_child(bulb)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.72, 0.42)
			light.light_energy = 2.2
			light.omni_range = 18.0
			light.omni_attenuation = 1.3
			light.position = Vector3(0, -0.4, 0)
			lamp.add_child(light)
			add_child(lamp)
			count += 1
			s += 60.0
	_add_mesh(posts.commit(), PS1Material.make(Color(0.35, 0.36, 0.38), 0.6))


func _add_mesh(mesh: ArrayMesh, material: Material, collide := false) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	if not collide:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.set_meta("surface", &"concrete")
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)


## Flat ribbons, discs and boxes merged into one mesh per material.
class Builder:
	var st := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _tri(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		if n.y > 0.0:
			var t := b
			b = c
			c = t
			n = -n
		var normal := -n.normalized()
		for p in [a, b, c]:
			st.set_normal(normal)
			st.set_uv(Vector2(p.x, p.z) * 0.25)
			st.add_vertex(p)
		count += 1

	## Strip between two offsets (left positive) along a polyline, at height y above it.
	func ribbon(pts: PackedVector3Array, off_a: float, off_b: float, y: float) -> void:
		var a := TrafficGraph.offset_polyline(pts, off_a)
		var b := TrafficGraph.offset_polyline(pts, off_b)
		var up := Vector3(0, y, 0)
		for i in pts.size() - 1:
			_tri(a[i] + up, b[i] + up, b[i + 1] + up)
			_tri(a[i] + up, b[i + 1] + up, a[i + 1] + up)

	func dashes(pts: PackedVector3Array, half_width: float, y: float, dash: float, gap: float) -> void:
		var cum := TrafficGraph.cumulative(pts)
		var total := cum[cum.size() - 1]
		var s := gap * 0.5
		while s + dash < total:
			var p0 := TrafficGraph.point_at(pts, cum, s)
			var p1 := TrafficGraph.point_at(pts, cum, s + dash)
			ribbon(PackedVector3Array([p0, p1]), -half_width, half_width, y)
			s += dash + gap

	func quad_flat(a: Vector3, b: Vector3, dir: Vector3, depth: float) -> void:
		var d := dir * depth
		_tri(a - d, b - d, b)
		_tri(a - d, b, a)

	func disc(c: Vector3, r: float, sides: int) -> void:
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			_tri(c, c + Vector3(sin(a0), 0, cos(a0)) * r, c + Vector3(sin(a1), 0, cos(a1)) * r)

	func box(c: Vector3, size: Vector3, top_scale := Vector2.ONE) -> void:
		var h := size * 0.5
		var t := Vector3(h.x * top_scale.x, h.y, h.z * top_scale.y)
		var v := [
			c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
			c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
			c + Vector3(-t.x, t.y, -t.z), c + Vector3(t.x, t.y, -t.z),
			c + Vector3(t.x, t.y, t.z), c + Vector3(-t.x, t.y, t.z),
		]
		for f in [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [2, 6, 7, 3], [1, 5, 6, 2], [3, 7, 4, 0]]:
			_tri_out(v[f[0]], v[f[1]], v[f[2]], c)
			_tri_out(v[f[0]], v[f[2]], v[f[3]], c)


	func _tri_out(a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		if n.dot((a + b + c) / 3.0 - inside) > 0.0:
			var t := b
			b = c
			c = t
			n = -n
		var normal := -n.normalized()
		for p in [a, b, c]:
			st.set_normal(normal)
			st.set_uv(Vector2(p.x + p.z, p.y) * 0.25)
			st.add_vertex(p)
		count += 1

	func commit() -> ArrayMesh:
		if count == 0:
			return null
		return st.commit()
