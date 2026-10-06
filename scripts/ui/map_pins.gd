class_name MapPins
extends RefCounted
## What goes on the maps: home, shops, servos, workshops, the job you're on,
## challenges, the fishing and birding spots you know about, and your own
## markers. Read fresh from the game each time (gather), so anything that
## moves or gets discovered shows up on its own.
##
## Your markers and the quiet spots you've been to are saved here (the "map"
## save section, through MapScreen).

const MAX_MARKERS := 12
## How close you need to get to a hand-picked quiet spot to put it on the map.
const SPOT_REACH := 60.0

## Your markers: [{at: Vector2 (world x/z), name: String}].
static var markers: Array = []
## Quiet spots (map POI ids) you've been to.
static var seen_spots := {}


## Everything to draw. `mini` leaves out what only clutters a small map, and
## keeps the job you're on and your nearest marker on its rim.
static func gather(tree: SceneTree, mini := false) -> Array:
	var pins: Array = []
	var data := MapData.shared()
	var index := data.index
	var home: Dictionary = index.get("home", {})
	if home.has("position"):
		var hp: Array = home.position
		pins.append(_pin(Vector2(hp[0], hp[2]), "home", UiStyle.RED, "Home"))
	for node in tree.get_nodes_in_group(&"workshop_spots"):
		if node is Node3D and String(node.get("spot_id")) != "home_carport":
			pins.append(_pin(_xz(node), "wrench", UiStyle.TEAL, String(node.get("display_name")) if node.get("display_name") else "Workshop"))
	for node in tree.get_nodes_in_group(&"tackle_shops"):
		pins.append(_pin(_xz(node), "fish", UiStyle.SUN, "Tackle and bait"))
	for node in tree.get_nodes_in_group(&"photo_labs"):
		pins.append(_pin(_xz(node), "camera", UiStyle.SUN, "Photo lab"))
	for poi: Dictionary in index.get("pois", []):
		var kind := String(poi.get("kind", ""))
		var at := _poi_at(poi)
		match kind:
			"servo":
				pins.append(_pin(at, "fuel", UiStyle.SUN, "Servo, %s" % poi.suburb if poi.has("suburb") else "Servo"))
			"quiet_spot":
				if seen_spots.has(String(poi.id)):
					pins.append(_pin(at, "quiet", UiStyle.TEAL, String(poi.get("name", "A quiet spot"))))
			"lookout":
				if not mini:
					pins.append(_pin(at, "eye", UiStyle.TEAL_LIGHT, String(poi.get("name", "Lookout"))))
			"beach":
				if not mini:
					pins.append(_pin(at, "sun", UiStyle.SUN_LIGHT, String(poi.get("name", "Beach"))))
			"birding":
				# Hidden ones are quiet places: only once you've found them.
				if not poi.get("hidden", false):
					pins.append(_pin(at, "bird", UiStyle.GOOD, String(poi.get("name", "Birds"))))
				elif Discoveries.has("places/" + String(poi.id)):
					pins.append(_pin(at, "quiet", UiStyle.GOOD, String(poi.get("name", "A quiet place"))))
	_field_pins(pins)
	_challenge_pins(tree, pins, mini)
	var target := Jobs.target_site() if Jobs.has_method("target_site") else null
	# Job places you've been to (where pickups and drop-offs happen).
	for site: JobSite in Jobs.sites():
		if site != target and (not site.discoverable or Discoveries.has("place/" + site.site_id)):
			pins.append(_pin(_xz(site), "note", UiStyle.SUN, site.label()))
	if target:
		var pin := _pin(_xz(target), "flag", UiStyle.RED, target.label())
		pin.kind = "target"
		pin.rim = true
		pins.append(pin)
	var player := player_position(tree)
	var nearest := nearest_marker(Vector2(player.x, player.z)) if player != Vector3.INF else -1
	for i in markers.size():
		var m: Dictionary = markers[i]
		var pin := _pin(m.at, "pin", UiStyle.TEAL, String(m.get("name", "")))
		pin.kind = "marker"
		pin.marker = i
		pin.rim = mini and i == nearest
		pins.append(pin)
	return pins


static func _field_pins(pins: Array) -> void:
	var journal := FieldJournal
	for sp: Dictionary in journal.spots:
		var id := String(sp.get("id", ""))
		var known: bool = not sp.get("hidden", false) or Discoveries.has("fishing/" + id)
		if not known:
			continue
		var stand: Array = sp.get("stand", sp.get("near", [0, 0, 0]))
		var at := Vector2(float(stand[0]), float(stand[2])) if stand.size() >= 3 else Vector2(float(stand[0]), float(stand[1]))
		pins.append(_pin(at, "fish", UiStyle.TEAL_LIGHT if not sp.get("hidden", false) else UiStyle.TEAL, String(sp.get("name", "Fishing"))))
	# Quiet birding places found by walking into them.
	for h: Dictionary in journal.quiet_places():
		if journal.is_place_found(h) and not h.has("poi"):
			pins.append(_pin(Vector2(float(h.get("x", 0.0)), float(h.get("z", 0.0))), "quiet", UiStyle.GOOD, String(h.get("name", "A quiet place"))))


static func _challenge_pins(tree: SceneTree, pins: Array, mini: bool) -> void:
	for node in tree.get_nodes_in_group(&"parking_bays"):
		pins.append(_pin(_xz(node), "park", UiStyle.TEAL, "Parking: %s" % node.get("title") if node.get("title") else "Parking challenge"))
	for node in tree.get_nodes_in_group(&"scenic_drives"):
		pins.append(_pin(_xz(node), "flag", UiStyle.GOOD, "Scenic drive: %s" % node.get("title") if node.get("title") else "Scenic drive"))
	for node in tree.get_nodes_in_group(&"car_meets"):
		pins.append(_pin(_xz(node), "car", UiStyle.RED, String(node.get("title")) if node.get("title") else "Car meet"))
	for node in tree.get_nodes_in_group(&"photo_spots"):
		if Discoveries.has("spot/" + String(node.get("spot_id"))) and not mini:
			pins.append(_pin(_xz(node), "camera", UiStyle.TEAL_LIGHT, String(node.get("title"))))


static func _pin(at: Vector2, icon: String, accent: Color, label := "") -> Dictionary:
	return {at = at, icon = icon, accent = accent, label = label, kind = "place", rim = false}


static func _xz(node: Node) -> Vector2:
	var p: Vector3 = (node as Node3D).global_position if node is Node3D and node.is_inside_tree() else Vector3.ZERO
	return Vector2(p.x, p.z)


static func _poi_at(poi: Dictionary) -> Vector2:
	var p: Array = poi.get("at", poi.get("p", [0, 0, 0]))
	return Vector2(float(p[0]), float(p[2]))


# --- the player ----------------------------------------------------------------

static func player_car(tree: SceneTree) -> CarController:
	return tree.get_first_node_in_group(&"player_car") as CarController


static func _walker(tree: SceneTree) -> Node3D:
	var car := player_car(tree)
	if car == null:
		return null
	var p := car.get_parent().get_node_or_null(^"Player") as Node3D
	if p and not p.get("in_car"):
		return p
	return null


static func in_car(tree: SceneTree) -> bool:
	return _walker(tree) == null


## Where the player is (on foot or in the car), or INF.
static func player_position(tree: SceneTree) -> Vector3:
	var w := _walker(tree)
	if w:
		return w.global_position
	var car := player_car(tree)
	return car.global_position if car else Vector3.INF


## Which way the player faces: rotation.y (0 = north, -Z).
static func player_yaw(tree: SceneTree) -> float:
	var w := _walker(tree)
	var node: Node3D = w if w else player_car(tree)
	if node == null:
		return 0.0
	var f := -node.global_basis.z
	return atan2(-f.x, -f.z)


# --- markers -----------------------------------------------------------------

static func add_marker(at: Vector2, name := "") -> int:
	if markers.size() >= MAX_MARKERS:
		return -1
	markers.append({at = at, name = name if name != "" else "Marker %d" % (markers.size() + 1)})
	return markers.size() - 1


static func remove_marker(i: int) -> void:
	if i >= 0 and i < markers.size():
		markers.remove_at(i)


static func rename_marker(i: int, name: String) -> void:
	if i >= 0 and i < markers.size() and name.strip_edges() != "":
		markers[i].name = name.strip_edges().left(28)


static func nearest_marker(from: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in markers.size():
		var d: float = from.distance_squared_to(markers[i].at)
		if d < best_d:
			best_d = d
			best = i
	return best


## Notes quiet spots the player is near (called by the minimap now and then).
static func note_spots(p: Vector3) -> void:
	for poi: Dictionary in MapData.shared().index.get("pois", []):
		if poi.get("kind", "") == "quiet_spot" and not seen_spots.has(String(poi.id)):
			if _poi_at(poi).distance_to(Vector2(p.x, p.z)) < SPOT_REACH:
				seen_spots[String(poi.id)] = true


static func save_state() -> Dictionary:
	var out: Array = []
	for m: Dictionary in markers:
		out.append({x = m.at.x, z = m.at.y, name = m.name})
	return {markers = out, spots = seen_spots.keys()}


static func load_state(state: Dictionary) -> void:
	markers.clear()
	for m: Dictionary in state.get("markers", []):
		markers.append({at = Vector2(float(m.get("x", 0.0)), float(m.get("z", 0.0))), name = String(m.get("name", "Marker"))})
	seen_spots.clear()
	for id: Variant in state.get("spots", []):
		seen_spots[String(id)] = true
