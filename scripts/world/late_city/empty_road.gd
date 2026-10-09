class_name EmptyRoad
extends Node3D
## The empty road (STORY.md, event 2). A story job turns up on the board late
## at night from act 3: a parcel left at your door, addressed to M. Doran, May
## Drive, Kings Park. On the way, under the trees of May Drive:
##
##   1. The deck clicks on and every sound fades except your engine and tyres.
##   2. Everything except the road you're on goes dark and is gone. The road
##      carries on under its own row of sodium lamps, into a blue-black sky.
##   3. A single 1979 house stands by the road with its porch light on. Pull
##      up at the letterbox and the parcel is signed for: M. Doran.
##   4. Drive on and the world fades back in, and the deck clunks off.
##
## It always lets you go: drive off the road, turn round or get out, and the
## world comes back (STORY.md, section 5). It never happens on a normal drive,
## only on its own job. With Strange things on Gentle the world goes into
## thick fog instead of nothing.
##
## The road is our own ribbon down the route's centreline, snapped to the real
## road's colliders, in the map's own asphalt (with `late_keep`, so the PS1
## shader's `late_void` leaves it lit while everything else goes dark).

const EVENT := &"empty_road"
const SITE_ID := "late_may_drive"
## Where the parcel goes: the roadside on May Drive, in the bush of western
## Kings Park, where there has never been a house.
const DROPOFF := Vector3(-3120.6, 25.9, 2212.7)
const STREET := "May Drive"
## Only when the rest of the way there is about this long (m) by road.
const MIN_ROUTE := 450.0
const MAX_ROUTE := 1900.0
## The road as drawn: half its width (m), the lines, the verge beyond it.
const HALF_WIDTH := 3.5
const VERGE := 1.4
const LINE_WIDTH := 0.12
const STEP := 3.0
## Lamps every so often, alternating sides, and how many really light.
const LAMP_GAP := 32.0
const REAL_LAMPS := 6
## Seconds for each stage.
const SOUND_OUT := 2.5
const FADE_OUT := 2.6
const FADE_IN := 2.4
const AFTER_DELIVERY := 3.5
## You've left the road when you're this far (m) past its edge.
const OFF_ROAD := 4.0
## Turned round: driving against the road's direction for this long (s).
const TURN_ROUND := 2.5
const SKY := Color(0.012, 0.016, 0.04)
const VOID_FOG := 0.018
const GENTLE_FOG := 0.06
## When the job may turn up on the board (hours), and from which act.
const OFFER_FROM := 22.0
const OFFER_TO := 3.0
const FROM_ACT := 3

## Tests and the dev panel: ignore the act and the hour.
var force := false

enum Phase { IDLE, SOUND_OUT, FADE_OUT, EMPTY, FADE_IN }
var phase := Phase.IDLE

var _t := 0.0
var _check := 0.0
var _site: JobSite
var _car: CarController
var _route := PackedVector3Array()   # snapped centreline, every STEP m
var _cum := PackedFloat32Array()
var _ribbon: Node3D
var _lamps: Array[Vector3] = []
var _pool: Array[OmniLight3D] = []
var _house: LateHouse
var _hidden: Array[Node3D] = []
var _hidden_roads: Array[Node3D] = []
## How far the world has gone (0 to 1), whatever Gentle makes of it on screen.
var void_amount := 0.0:
	get: return _void
var _void := 0.0
var _car_lit: Array = []
## Why start() last said no (for tests and the dev tools).
var refused := ""
var _env: Environment
var _sky: ProceduralSkyMaterial
var _traffic_scale := [1.0, 1.0]
var _delivered := false
var _since_delivery := 0.0
var _against := 0.0
var _road_mat: ShaderMaterial
var _line_mat: ShaderMaterial
var _verge_mat: ShaderMaterial


func _ready() -> void:
	# After the environment controller, so the void sky has the last word.
	process_priority = 100
	_site = JobSite.new()
	_site.name = "LateMayDrive"
	_site.site_id = SITE_ID
	_site.display_name = "May Drive"
	_site.suburb = "Kings Park"
	_site.kinds = PackedStringArray(["story"])
	_site.discoverable = false
	add_child(_site)
	_site.global_position = DROPOFF
	Jobs.offers_refreshed.connect(_maybe_offer)
	Jobs.job_completed.connect(_on_job_completed)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"late_void", 0.0)


# --- The job ------------------------------------------------------------------

## Put the parcel on the board if it's time (also called by tests).
func _maybe_offer() -> void:
	if Story.flag(&"empty_road_done"):
		return
	if not force:
		var h := GameClock.time_of_day
		if Story.act() < FROM_ACT or not (h >= OFFER_FROM or h < OFFER_TO):
			return
	for job: Dictionary in Jobs.offers:
		if job.get("story", "") == String(EVENT):
			return
	if Jobs.active.get("story", "") == String(EVENT):
		return
	var job := make_job()
	if job.is_empty():
		return
	Jobs.offers.push_front(job)
	Jobs.offers_changed.emit()


## The story job: from the pickup nearest home to May Drive.
func make_job() -> Dictionary:
	var home := get_tree().get_first_node_in_group(&"home_base") as Node3D
	var from: JobSite = null
	var best := INF
	for s in Jobs.sites():
		if not s.kinds.has("pickup"):
			continue
		var d := s.global_position.distance_to(home.global_position) if home else 0.0
		if d < best:
			best = d
			from = s
	if from == null:
		return {}
	var km := from.global_position.distance_to(DROPOFF) * Jobs.ROAD_FACTOR / 1000.0
	return {
		"id": 90000 + GameClock.day, "type": "delivery", "story": String(EVENT),
		"title": "A parcel left at your door", "cargo": "a parcel for M. Doran",
		"fragile": false, "pickup": from.site_id, "dropoff": SITE_ID,
		"km": km, "pay": roundi((Jobs.DELIVERY_BASE_PAY + km * Jobs.DELIVERY_PAY_PER_KM) * Progression.pay_multiplier() / 5.0) * 5,
		"par_seconds": 3.0 * 3600.0,
	}


func _on_job_completed(job: Dictionary, _pay: int, _summary: String) -> void:
	if job.get("story", "") != String(EVENT):
		return
	Story.set_flag(&"empty_road_done")
	if phase == Phase.IDLE:
		# It never happened (Gentle off-road, or the city didn't let go of you):
		# the parcel goes on a post by the road.
		Notices.post("Nobody's there. You leave the parcel on a post by the road.", "odd")
		return
	_delivered = true
	_since_delivery = 0.0
	Notices.post("Signed for in pencil: M. Doran. The porch light stays on.", "odd")
	Discoveries.discover("oddity/empty_road")
	Story.log_night(&"empty_road",
		"Took a parcel to May Drive. Everything went except the road, and there was one house with its porch light on. M. Doran signed for it.")


# --- Running it ------------------------------------------------------------------

func _process(delta: float) -> void:
	match phase:
		Phase.IDLE:
			_check -= delta
			if _check <= 0.0:
				_check = 1.0
				_try_start()
		Phase.SOUND_OUT:
			_t += delta
			if _t >= SOUND_OUT:
				_begin_fade()
		Phase.FADE_OUT:
			_t += delta
			_set_void(clampf(_t / FADE_OUT, 0.0, 1.0))
			if _t >= FADE_OUT:
				_go_empty()
		Phase.EMPTY:
			_update_lamps()
			_check_leave(delta)
		Phase.FADE_IN:
			_t += delta
			_set_void(1.0 - clampf(_t / FADE_IN, 0.0, 1.0))
			if _t >= FADE_IN:
				_finish()
	if phase != Phase.IDLE:
		_apply_sky()


func _try_start() -> void:
	if Jobs.active.get("story", "") != String(EVENT) or Jobs.active.get("stage", "") != "to_dropoff":
		return
	_car = get_tree().get_first_node_in_group(&"player_car") as CarController
	if _car == null or not _car.player_controlled or _car.speed_kmh() < 15.0:
		return
	if not force and Story.act() < FROM_ACT:
		return
	if not LateCity.allowed_now(false) or Weather.rain > 0.05:
		return
	if _car.global_position.distance_to(DROPOFF) > MAX_ROUTE:
		return
	# Only on the back road itself, in the bush, never on the way there.
	if MapData.shared().street_at(_car.global_position, 12.0) != STREET:
		return
	if not start():
		return


## Start now if the way to May Drive is right; true if it started.
func start() -> bool:
	_car = get_tree().get_first_node_in_group(&"player_car") as CarController
	refused = ""
	if _car == null or phase != Phase.IDLE:
		refused = "already running"
		return false
	var fwd := -_car.global_transform.basis.z
	var found := MapData.shared().routes.find(_car.global_position, Vector2(fwd.x, fwd.z), DROPOFF)
	if found.is_empty() or float(found.length) < MIN_ROUTE or float(found.length) > MAX_ROUTE:
		refused = "no way there of the right length (%s)" % str(found.get("length", "none"))
		return false
	if _traffic_near(150.0):
		refused = "traffic about"
		return false
	if not LateCity.begin(EVENT):
		refused = "another event is on"
		return false
	_build_route(found.points)
	phase = Phase.SOUND_OUT
	_t = 0.0
	_delivered = false
	_against = 0.0
	LateCity.fade_mute(1.0, SOUND_OUT)
	return true


func _begin_fade() -> void:
	phase = Phase.FADE_OUT
	_t = 0.0
	_build_ribbon()
	_build_house()
	# Your car stays as it is (it would go dark with the rest).
	_car_lit = LateCity.keep_lit(_car)
	# No more traffic or people for now.
	var traffic := get_tree().get_first_node_in_group(&"traffic_manager")
	if traffic == null:
		traffic = get_tree().root.find_child("Traffic", true, false)
	if traffic and traffic.get("density_scale") != null:
		_traffic_scale = [traffic.density_scale, traffic.pedestrian_scale]
		traffic.density_scale = 0.0
		traffic.pedestrian_scale = 0.0
	# The real roads go now (the ribbon is in their place); the rest fades.
	_hidden_roads.clear()
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map:
		for tile in map.get_children():
			for c in tile.get_children():
				if c is MeshInstance3D and c.visible and (String(c.name).begins_with("road") or String(c.name).begins_with("markings")):
					c.visible = false
					_hidden_roads.append(c)
		if not map.tile_loaded.is_connected(_on_tile_loaded):
			map.tile_loaded.connect(_on_tile_loaded)
	_ribbon.visible = true
	_house.visible = true


func _go_empty() -> void:
	phase = Phase.EMPTY
	_t = 0.0
	_set_void(1.0)
	# Gone for good while it lasts: the world's own nodes hide (lights too),
	# and traffic clears, so nothing unseen can be driven into.
	_hidden.clear()
	var world := _car.get_parent()
	for c in world.get_children():
		if c is Node3D and c.visible and not _keep(c):
			(c as Node3D).visible = false
			_hidden.append(c)
	var traffic := world.get_node_or_null("Traffic")
	if traffic and traffic.has_method("clear_all"):
		traffic.clear_all()
	_update_lamps()


func _check_leave(delta: float) -> void:
	if _car == null or not is_instance_valid(_car):
		_end_void()
		return
	var at := _car.global_position
	var near := _nearest(at)
	var off: float = near[0]
	var s: float = near[1]
	if off > HALF_WIDTH + OFF_ROAD:
		_end_void()
		return
	if not _car.player_controlled:
		_end_void()
		return
	# Turned round: going back the way you came.
	var along := _direction_at(s)
	var v := _car.linear_velocity
	if Vector2(v.x, v.z).dot(Vector2(along.x, along.z)) < -2.0:
		_against += delta
	else:
		_against = 0.0
	if _against > TURN_ROUND:
		_end_void()
		return
	# Past the end of the road, or the parcel is in.
	if s >= _cum[_cum.size() - 1] + 40.0:
		_end_void()
		return
	if _delivered:
		_since_delivery += delta
		if _since_delivery >= AFTER_DELIVERY:
			_end_void()


func _end_void() -> void:
	if phase != Phase.EMPTY and phase != Phase.FADE_OUT:
		return
	phase = Phase.FADE_IN
	_t = 0.0
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for n in _hidden_roads:
		if is_instance_valid(n):
			n.visible = true
	_hidden_roads.clear()
	_ribbon.visible = false
	_house.visible = false
	for l in _pool:
		l.visible = false
	var traffic := get_tree().root.find_child("Traffic", true, false)
	if traffic and traffic.get("density_scale") != null:
		traffic.density_scale = _traffic_scale[0]
		traffic.pedestrian_scale = _traffic_scale[1]
	LateCity.fade_mute(0.0, FADE_IN + 0.5)


func _finish() -> void:
	phase = Phase.IDLE
	_set_void(0.0)
	LateCity.release_lit(_car_lit)
	_car_lit = []
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map and map.tile_loaded.is_connected(_on_tile_loaded):
		map.tile_loaded.disconnect(_on_tile_loaded)
	if _ribbon:
		_ribbon.queue_free()
		_ribbon = null
	if _house:
		_house.queue_free()
		_house = null
	for l in _pool:
		l.queue_free()
	_pool.clear()
	LateCity.end(EVENT)
	if not _delivered:
		Story.log_night(&"empty_road_left",
			"On May Drive the city went, and there was only the road. I left it, and the city came back.")


## Tiles that load while the road is empty come in hidden too.
func _on_tile_loaded(key: Vector2i) -> void:
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map == null:
		return
	var tile := map.get_node_or_null("Tile_%d_%d" % [key.x, key.y]) as Node3D
	if tile == null:
		return
	for c in tile.get_children():
		if c is MeshInstance3D and (String(c.name).begins_with("road") or String(c.name).begins_with("markings")):
			c.visible = false
			_hidden_roads.append(c)


## The world's own nodes that stay while the road is empty: your car, the
## camera, you, the sky's lights and the job's marker.
func _keep(n: Node) -> bool:
	return n == _car or n == self or n is Camera3D or n is Beacon or n is WorldEnvironment \
		or n is DirectionalLight3D or n.name in [&"CameraRig", &"Player", &"EnvironmentController", &"Car"]


func _traffic_near(r: float) -> bool:
	var traffic := get_tree().root.find_child("Traffic", true, false)
	if traffic == null or traffic.get("vehicles") == null:
		return false
	for v: TrafficVehicle in traffic.vehicles:
		if v.active and v.position.distance_to(_car.global_position) < r:
			return true
	return false


# --- The look ----------------------------------------------------------------------

func _set_void(v: float) -> void:
	_void = v
	RenderingServer.global_shader_parameter_set(&"late_void", 0.0 if Story.gentle() else v)


func _apply_sky() -> void:
	if _env == null:
		var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we == null:
			return
		_env = we.environment
		_sky = _env.sky.sky_material as ProceduralSkyMaterial if _env.sky else null
	var v := _void
	var fog := GENTLE_FOG if Story.gentle() else VOID_FOG
	var fog_colour := Color(0.06, 0.06, 0.07) if Story.gentle() else SKY
	_env.fog_density = lerpf(_env.fog_density, fog, v)
	_env.fog_light_color = _env.fog_light_color.lerp(fog_colour, v)
	if _sky:
		_sky.sky_top_color = _sky.sky_top_color.lerp(SKY, v)
		_sky.sky_horizon_color = _sky.sky_horizon_color.lerp(fog_colour, v)
		_sky.ground_horizon_color = _sky.ground_horizon_color.lerp(fog_colour, v)
		_sky.ground_bottom_color = _sky.ground_bottom_color.lerp(fog_colour, v)


## Real lights on the nearest few lamps; the rest glow and pool on their own.
func _update_lamps() -> void:
	if _car == null or _lamps.is_empty():
		return
	var at := _car.global_position
	var order := range(_lamps.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _lamps[a].distance_squared_to(at) < _lamps[b].distance_squared_to(at))
	while _pool.size() < REAL_LAMPS:
		var l := OmniLight3D.new()
		l.light_color = LateCity.SODIUM
		l.light_energy = 1.6
		l.omni_range = 16.0
		l.omni_attenuation = 1.2
		add_child(l)
		_pool.append(l)
	for i in _pool.size():
		_pool[i].visible = i < order.size()
		if i < order.size():
			_pool[i].global_position = _lamps[order[i]] + Vector3.DOWN * 0.4


# --- Building the road ---------------------------------------------------------------

func _build_route(points: PackedVector3Array) -> void:
	var cum := TrafficGraph.cumulative(points)
	var total := cum[cum.size() - 1]
	_route = PackedVector3Array()
	_cum = PackedFloat32Array()
	var s := 0.0
	while s <= total:
		_route.append(_sample(points, cum, s))
		_cum.append(s)
		s += STEP
	_route.append(points[points.size() - 1])
	_cum.append(total)
	# Snap to the road's own collider where it's loaded.
	var space := get_world_3d().direct_space_state
	for i in _route.size():
		_route[i] = _ground(space, _route[i])


func _build_ribbon() -> void:
	if _ribbon:
		_ribbon.queue_free()
	_road_mat = _keep_material("asphalt", Color(0.2, 0.2, 0.22))
	_line_mat = _keep_material("line_white", Color(0.85, 0.85, 0.8))
	_verge_mat = PS1Material.make(Color(0.09, 0.08, 0.06))
	_verge_mat.set_shader_parameter("late_keep", true)
	_ribbon = Node3D.new()
	_ribbon.name = "EmptyRoadRibbon"
	_ribbon.visible = false
	add_child(_ribbon)
	var space := get_world_3d().direct_space_state
	# Chunks of road so each one has only a few lamps on it.
	var chunk := 12
	var i := 0
	while i < _route.size() - 1:
		var j := mini(i + chunk, _route.size() - 1)
		_ribbon.add_child(_chunk(space, i, j))
		i = j
	# Lamps, alternating sides, each with its pool of light on the road.
	_lamps.clear()
	var pool_mat := _pool_material()
	var post_mat := PS1Material.make(Color(0.18, 0.18, 0.19))
	post_mat.set_shader_parameter("late_keep", true)
	var head_mat := PS1Material.glowing(LateCity.SODIUM, 3.0)
	head_mat.set_shader_parameter("late_keep", true)
	var s := 12.0
	var side := 1.0
	var total := _cum[_cum.size() - 1]
	while s < total:
		var p := _at(s)
		var dir := _direction_at(s)
		var right := dir.cross(Vector3.UP).normalized()
		var base := _ground(space, p + right * side * (HALF_WIDTH + 0.9))
		_ribbon.add_child(_lamp_post(base, -right * side, post_mat, head_mat))
		_lamps.append(base + Vector3.UP * 6.2 - right * side * 1.4)
		var pool := MeshInstance3D.new()
		var quad := PlaneMesh.new()
		quad.size = Vector2(9.0, 9.0)
		pool.mesh = quad
		pool.material_override = pool_mat
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ribbon.add_child(pool)
		pool.global_position = _ground(space, p + right * side * 1.0) + Vector3.UP * 0.05
		s += LAMP_GAP
		side = -side


func _chunk(space: PhysicsDirectSpaceState3D, from: int, to: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	# Road.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(from, to):
		_strip(st, space, k, -HALF_WIDTH, HALF_WIDTH, 0.0)
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(0, _road_mat)
	# Edge lines and the broken centre line.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(from, to):
		for edge in [-1.0, 1.0]:
			var e: float = edge * (HALF_WIDTH - 0.35)
			_strip(st, space, k, e - LINE_WIDTH, e + LINE_WIDTH, 0.015)
		if int(_cum[k] / STEP) % 3 == 0:
			_strip(st, space, k, -LINE_WIDTH * 0.8, LINE_WIDTH * 0.8, 0.015)
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(1, _line_mat)
	# Verges: a little dark ground each side, falling away into nothing.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(from, to):
		_strip(st, space, k, HALF_WIDTH, HALF_WIDTH + VERGE, 0.0, -0.25)
		_strip(st, space, k, -HALF_WIDTH - VERGE, -HALF_WIDTH, 0.0, 0.0, -0.25)
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(2, _verge_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## One quad of road between route points k and k+1, from `a` to `b` metres
## across (negative is left), `lift` above the road; `drop_b`/`drop_a` lower
## that side (for the verges).
func _strip(st: SurfaceTool, _space: PhysicsDirectSpaceState3D, k: int, a: float, b: float,
		lift: float, drop_b := 0.0, drop_a := 0.0) -> void:
	var p0 := _route[k]
	var p1 := _route[k + 1]
	var r0 := _right_at(k)
	var r1 := _right_at(k + 1)
	var up := Vector3.UP * (lift + 0.02)
	var v0a := p0 + r0 * a + up + Vector3.UP * drop_a
	var v0b := p0 + r0 * b + up + Vector3.UP * drop_b
	var v1a := p1 + r1 * a + up + Vector3.UP * drop_a
	var v1b := p1 + r1 * b + up + Vector3.UP * drop_b
	var u0 := _cum[k] / 6.0
	var u1 := _cum[k + 1] / 6.0
	st.set_uv(Vector2(0, u0)); st.add_vertex(v0a)
	st.set_uv(Vector2(1, u1)); st.add_vertex(v1b)
	st.set_uv(Vector2(1, u0)); st.add_vertex(v0b)
	st.set_uv(Vector2(0, u0)); st.add_vertex(v0a)
	st.set_uv(Vector2(0, u1)); st.add_vertex(v1a)
	st.set_uv(Vector2(1, u1)); st.add_vertex(v1b)


func _lamp_post(base: Vector3, toward_road: Vector3, post_mat: Material, head_mat: Material) -> Node3D:
	var lamp := Node3D.new()
	var flat := Vector3(toward_road.x, 0.0, toward_road.z).normalized()
	# -Z (the arm) out over the road. The ribbon sits at the world's origin.
	lamp.transform = Transform3D(Basis.looking_at(flat, Vector3.UP), base)
	var parts := [
		[Vector3(0.14, 6.4, 0.14), Vector3(0, 3.2, 0), post_mat],
		[Vector3(0.08, 0.08, 1.6), Vector3(0, 6.3, -0.8), post_mat],
		[Vector3(0.34, 0.14, 0.6), Vector3(0, 6.2, -1.45), head_mat],
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.material_override = part[2]
		mi.position = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(mi)
	return lamp


func _build_house() -> void:
	if _house:
		_house.queue_free()
	var end := _route[_route.size() - 1]
	var dir := _direction_at(_cum[_cum.size() - 1] - 1.0)
	var right := dir.cross(Vector3.UP).normalized()
	# The side of the road away from the job site's marker line (the left, as
	# you arrive, like a letterbox on your side in Australia).
	var space := get_world_3d().direct_space_state
	var side := -1.0
	_house = LateHouse.new()
	_house.visible = false
	add_child(_house)
	var at := _ground(space, end + right * side * (HALF_WIDTH + 12.0))
	_house.global_position = at
	_house.look_at(at - right * side * 10.0, Vector3.UP)
	_house.place_letterbox(_ground(space, end + right * side * (HALF_WIDTH + 1.2)))


func _keep_material(name: String, fallback: Color) -> ShaderMaterial:
	var path := "res://map/materials/%s.tres" % name
	var m: ShaderMaterial = null
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is ShaderMaterial:
			m = (loaded as ShaderMaterial).duplicate() as ShaderMaterial
	if m == null:
		m = PS1Material.road(fallback)
	m.set_shader_parameter("late_keep", true)
	return m


func _pool_material() -> StandardMaterial3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(LateCity.SODIUM, 0.55))
	grad.set_color(1, Color(LateCity.SODIUM, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


# --- Geometry helpers ------------------------------------------------------------------

func _ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 8.0, MapTileLoader.LAYER_WORLD)
	if _car:
		q.exclude = [_car.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position if hit else p


static func _sample(points: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	for i in range(1, points.size()):
		if cum[i] >= s:
			var seg := cum[i] - cum[i - 1]
			var f := 0.0 if seg <= 0.0 else (s - cum[i - 1]) / seg
			return points[i - 1].lerp(points[i], f)
	return points[points.size() - 1]


func _at(s: float) -> Vector3:
	return _sample(_route, _cum, s)


func _direction_at(s: float) -> Vector3:
	var a := _at(maxf(s - 2.0, 0.0))
	var b := _at(s + 2.0)
	var d := b - a
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _right_at(k: int) -> Vector3:
	var a := _route[maxi(k - 1, 0)]
	var b := _route[mini(k + 1, _route.size() - 1)]
	var d := b - a
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3.RIGHT
	return d.normalized().cross(Vector3.UP).normalized()


## [distance off the centreline (m, flat), distance along it (m)].
func _nearest(p: Vector3) -> Array:
	var best := INF
	var along := 0.0
	var flat := Vector2(p.x, p.z)
	for i in range(1, _route.size()):
		var a := Vector2(_route[i - 1].x, _route[i - 1].z)
		var b := Vector2(_route[i].x, _route[i].z)
		var ab := b - a
		var t := clampf((flat - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := flat.distance_to(a + ab * t)
		if d < best:
			best = d
			along = _cum[i - 1] + (_cum[i] - _cum[i - 1]) * t
	# Past the end of the road you're "along" it by how far past you are.
	var last := Vector2(_route[_route.size() - 1].x, _route[_route.size() - 1].z)
	if along >= _cum[_cum.size() - 1] - 0.01:
		along = _cum[_cum.size() - 1] + flat.distance_to(last)
		best = minf(best, HALF_WIDTH)
	return [best, along]
