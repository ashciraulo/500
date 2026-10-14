class_name Street1979
extends LateDrive
## The 1979 street (STORY.md, event 9). After midnight, from act 4, on a
## street of shops: the deck clicks on, the light goes sodium orange, and
## every car on the road is from 1979, Valiants and little 500 Ls in
## mustard and olive and burnt orange, the parked ones too. The shops have
## their old names: a milk bar, a cake shop, a TV and radio repairer, a
## courier firm's sign lit all night. Drive to the end of the street and
## it's now again. Turning off, turning round or getting out lets it go too.
##
## A street of shops is one whose buildings come right up to the footpath,
## found by looking along it: the old signs go on those walls, and on the
## Northbridge venues' fronts (the venue is hidden while it lasts). The cars
## are the traffic's own, dressed by Traffic1979.

## Streets it happens on (OSM kinds; the shops are what decide it).
const KINDS_1979 := ["primary", "secondary", "tertiary", "unclassified", "residential"]
const MIN_KMH := 15.0
const MAX_KMH := 80.0
## The street must carry on this far (m), and have this many shops in the
## first FIRST_LOOK m of it.
const MIN_PATH := 250.0
const FIRST_LOOK := 320.0
const MIN_SHOPS := 3
## Looking for shop walls: every SHOP_STEP m along the street, no more than
## WALL_OUT m out from its middle (across the road and the footpath, and
## not back behind a front garden); signs at least SIGN_GAP m apart on one
## side.
const SHOP_STEP := 9.0
const WALL_OUT := 15.0
const SIGN_GAP := 12.0
const SIGN_WIDTH := 4.6
const SIGN_Y := 3.3
## Shops are looked for this far (m) ahead of the car as it goes.
const SCAN_AHEAD := 260.0
## Venues this close (m) to the street, facing it, are the street's.
const VENUE_NEAR := 19.0
## The traffic turns this long (s) after the deck clicks on.
const TURN_AFTER := 1.2
## The street is kept busy with at least BUSY cars within EXTRA_TO m, new
## ones coming in between EXTRA_FROM and EXTRA_TO m ahead, every BUSY_EVERY s.
const BUSY := 6
const BUSY_EVERY := 1.5
const EXTRA_FROM := 140.0
const EXTRA_TO := 240.0
const EXTRA_TYPES: Array[StringName] = [&"sedan", &"hatch", &"sedan", &"ute", &"sedan"]
const OFF_STREET := 16.0
const END_GAP := 12.0
const TURN_ROUND := 2.0
## A street without shops isn't looked at again for this long (s).
const SKIP_FOR := 30.0

## The old names: [name, the line under it]. Made up, the way they were.
const SHOPS := [
	["LUCKY STAR MILK BAR", "ICE CREAM  CIGARETTES  DRINKS"],
	["ACROPOLIS CAKE SHOP", "CONTINENTAL CAKES"],
	["ROMA DELICATESSEN", "IMPORTED FOODS"],
	["SWAN TV & RADIO", "SALES  REPAIRS  RENTALS"],
	["NITE OWL COURIERS", "24 HOURS  ALL SUBURBS"],
	["MODERN FROCKS", "LADIES' WEAR"],
	["GOLDEN DRAGON CAFE", "CHINESE & AUSTRALIAN MEALS"],
	["KING'S RECORD BAR", "LPs  CASSETTES  8-TRACK"],
	["BELLA NAPOLI PIZZA", "TAKE AWAY"],
	["STAR PHOTO SUPPLIES", "DEVELOPING & PRINTING"],
	["VOGUE HAIR STYLISTS", ""],
	["SUNSET TAILORS", "SUITS MADE TO MEASURE"],
	["BRIGHTWAY CHEMIST", ""],
	["TIP TOP SHOE REPAIRS", "KEYS CUT"],
	["WAY '79 SOUVENIRS", "150 YEARS OF W.A."],
	["MARINO'S FISH & CHIPS", "FRESH FISH DAILY"],
	["OLYMPIC SPORTS STORE", ""],
	["CORONET CAMERAS", "FILM  FLASH  PROJECTORS"],
	["NEW AUSTRALIA CAFE", "OPEN LATE"],
	["LUXOR LINO & CARPET", ""],
	["HARBOUR LIGHTS HI-FI", "STEREO  QUAD  TAPE DECKS"],
	["RAINBOW TOYS & HOBBIES", "MODEL KITS"],
	["SKYWAY TRAVEL", "JETS TO EVERYWHERE"],
	["KOOKABURRA COFFEE LOUNGE", ""],
]
## Sign styles: [board, letters, lit]. Painted boards in sodium light, and
## a few lightboxes still on.
const STYLES := [
	[Color(0.86, 0.8, 0.62), Color(0.7, 0.12, 0.08), false],
	[Color(0.12, 0.26, 0.16), Color(0.92, 0.75, 0.3), false],
	[Color(0.92, 0.9, 0.82), Color(0.12, 0.25, 0.6), true],
	[Color(0.78, 0.4, 0.1), Color(0.3, 0.15, 0.06), false],
	[Color(0.08, 0.07, 0.07), Color(1.0, 0.45, 0.65), true],
	[Color(0.62, 0.08, 0.06), Color(0.97, 0.94, 0.86), true],
]
const AWNING := Color(0.24, 0.22, 0.2)
const SHOP_LIGHT := Color(0.95, 0.78, 0.5)
const SHOP_DARK := Color(0.04, 0.05, 0.06)
const DOOR := Color(0.24, 0.15, 0.08)

var street := ""
## Where the shops are: [{at: Transform3D on the footpath at the wall, +z
## out, width, venue}] in the order found.
var shops: Array = []
var turned := false
## Cars put on the street to keep it busy.
var extra := 0

var _path := PackedVector3Array()
var _cum := PackedFloat32Array()
var _at := 0
var _s := 0.0
var _scanned := 0.0
var _last_sign := {1: -100.0, -1: -100.0}
var _t := 0.0
var _busy := 0.0
var _against := 0.0
var _old: Traffic1979
var _root: Node3D
var _venues: Array[Node3D] = []
var _names: Array = []
var _skip_street := ""
var _skip_until := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	event = &"street_1979"
	from_act = 4
	every_days = 3
	chance = 0.5


func _ready_to_start() -> bool:
	# After Night Drive 13 and The Late City every street is 1979 already.
	if not force and Story.ending() in [&"night_drive_13", &"late_city"]:
		return false
	var v := speed_kmh()
	if not force and (v < MIN_KMH or v > MAX_KMH):
		return false
	var found := RepeatStreet.street_ahead(_car.global_position, _heading(), KINDS_1979)
	if found.is_empty() or (not force and found.name == _skip_street and _clock < _skip_until):
		return false
	_path = found.points
	_cum = TrafficGraph.cumulative(_path)
	if _cum[_cum.size() - 1] < MIN_PATH:
		return false
	street = found.name
	_rng.seed = hash(street)
	_names = range(SHOPS.size())
	_shuffle(_names)
	shops.clear()
	_last_sign = {1: -100.0, -1: -100.0}
	_scanned = 0.0
	_find_venues()
	_scan_to(minf(FIRST_LOOK, _cum[_cum.size() - 1]))
	if shops.size() < MIN_SHOPS:
		_skip_street = street
		_skip_until = _clock + SKIP_FOR
		return false
	return true


func _heading() -> Vector2:
	var f := -_car.global_basis.z
	return Vector2(f.x, f.z).normalized()


func _start() -> void:
	_at = 0
	_s = 0.0
	_t = 0.0
	_busy = 0.0
	_against = 0.0
	extra = 0
	turned = false
	LateCity.fade_look(1.0, 2.5)
	LateCity.set_hiss(true)
	_root = Node3D.new()
	_root.name = "Street1979"
	_root.visible = false
	add_child(_root)
	for shop: Dictionary in shops:
		_build_shop(shop)
	_old = Traffic1979.new()
	_old.name = "Traffic1979"
	add_child(_old)


func _run(delta: float) -> void:
	if _cum.size() < 2:
		finish()
		return
	if not driving():
		_let_go("out")
		return
	_follow()
	_t += delta
	if not turned and _t >= TURN_AFTER:
		_turn()
	var total := _cum[_cum.size() - 1]
	var p := _car.global_position
	var on := TrafficGraph.point_at(_path, _cum, _s)
	if Vector2(p.x - on.x, p.z - on.z).length() > OFF_STREET:
		_let_go("turned")
		return
	if _s > total - END_GAP:
		_let_go("end")
		return
	var t := TrafficGraph.tangent_at(_path, _cum, _s)
	_against = _against + delta if Vector2(t.x, t.z).dot(_heading()) < -0.3 else 0.0
	if _against > TURN_ROUND:
		_let_go("turned")
		return
	_busy -= delta
	if turned and _busy <= 0.0:
		_busy = BUSY_EVERY
		_keep_busy()
	# The shops further along, a little at a time.
	var want := minf(_s + SCAN_AHEAD, total)
	if _scanned < want:
		var before := shops.size()
		_scan_to(minf(_scanned + SHOP_STEP * 3.0, want))
		for i in range(before, shops.size()):
			_build_shop(shops[i])


## The street turns: the old cars, the old names, the sodium lamps.
func _turn() -> void:
	turned = true
	_root.visible = true
	for venue: Node3D in _venues:
		venue.visible = false
	_old.dress_all()
	LateCity.play_flicker(_car.global_position + Vector3.UP * 2.0)


func _on_flash() -> void:
	pass  # no getting out of this one but the end of the street


func _let_go(how: String) -> void:
	var was := turned
	finish()
	if not was:
		return
	Discoveries.discover("oddity/street_1979")
	var out: String = {"end": " At the end of the street it was now again.",
		"turned": " I turned off and it was now again.", "out": " I got out and it was now again."}.get(how, "")
	Story.log_night(StringName("street_1979_%d" % GameClock.day),
		"On %s after midnight every car was from 1979, Valiants and little 500s under sodium lamps, and the shops had their old names.%s" % [street, out])


func _stop() -> void:
	if turned and _car and is_instance_valid(_car):
		LateCity.play_flicker(_car.global_position + Vector3.UP * 2.0)
	turned = false
	if _old:
		_old.undress_all()
		_old.queue_free()
		_old = null
	if _root:
		_root.queue_free()
		_root = null
	for venue: Node3D in _venues:
		if is_instance_valid(venue):
			venue.visible = true
	_venues.clear()


## Where the car is along the street (it only goes forwards, a little at a time).
func _follow() -> void:
	var p := Vector2(_car.global_position.x, _car.global_position.z)
	var best := INF
	var best_i := _at
	var best_s := _s
	for i in range(maxi(_at - 2, 0), mini(_at + 30, _path.size() - 1)):
		var a := Vector2(_path[i].x, _path[i].z)
		var b := Vector2(_path[i + 1].x, _path[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			best_i = i
			best_s = _cum[i] + a.distance_to(q)
	_at = best_i
	_s = best_s


# --- The shops ----------------------------------------------------------------

## The venues on this street (Northbridge): their fronts get old names.
func _find_venues() -> void:
	_venues.clear()
	var widths := {}
	for entry: Dictionary in Venue.entries():
		widths[str(entry.id)] = float(entry.get("width", 6.0))
	for venue: Node3D in get_tree().get_nodes_in_group(&"venues"):
		var at := venue.global_position
		if _distance_to_path(at) > VENUE_NEAR or venue.global_basis.z.dot(_nearest_on_path(at) - at) <= 0.0:
			continue
		_venues.append(venue)
		var width: float = widths.get(str(venue.get("venue_id")), 6.0)
		var basis := venue.global_basis.orthonormalized()
		shops.append({"at": Transform3D(basis, at), "width": clampf(width - 0.6, 3.0, 9.0), "venue": true})


## Look for shop walls along the street from where it got to up to `to`.
func _scan_to(to: float) -> void:
	var space := _car.get_world_3d().direct_space_state
	var s := _scanned
	while s <= to:
		var p := TrafficGraph.point_at(_path, _cum, s)
		var t := TrafficGraph.tangent_at(_path, _cum, s)
		var along := Vector3(t.x, 0.0, t.z).normalized()
		var left := Vector3(along.z, 0.0, -along.x)
		for side: int in [1, -1]:
			if s - float(_last_sign[side]) < SIGN_GAP:
				continue
			var shop := _shop_wall(space, p, left * side, along)
			if shop.is_empty() or _near_shop(shop.at.origin):
				continue
			_last_sign[side] = s
			shops.append(shop)
		s += SHOP_STEP
	_scanned = s


## A flat wall right on the footpath at `p` out along `out`: {at, width}, or {}.
func _shop_wall(space: PhysicsDirectSpaceState3D, p: Vector3, out: Vector3, along: Vector3) -> Dictionary:
	var road := _ground(space, p).y
	var hit := _wall(space, Vector3(p.x, road + SIGN_Y, p.z) + out * 1.0, out, WALL_OUT - 1.0)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.normal
	normal.y = 0.0
	if normal.length() < 0.9 or normal.normalized().dot(-out) < 0.85:
		return {}
	normal = normal.normalized()
	var at: Vector3 = hit.position
	# Flat for the width of a sign, and down to the street (a shopfront,
	# not an upstairs balcony or a fence).
	for check: Vector3 in [along * SIGN_WIDTH * 0.5, -along * SIGN_WIDTH * 0.5, Vector3.DOWN * 2.0]:
		var other := _wall(space, at + check + normal * 2.5, -normal, 3.5)
		if other.is_empty() or absf((other.position as Vector3 - at - check).dot(normal)) > 0.4:
			return {}
	var foot := _ground(space, at + normal * 0.6)
	var face := Basis(normal.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, normal)
	return {"at": Transform3D(face, Vector3(at.x, foot.y, at.z)), "width": SIGN_WIDTH, "venue": false}


func _wall(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	q.collision_mask = MapTileLoader.LAYER_BUILDINGS
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var what := String((hit.collider as Node).name)
	if not what.begins_with("buildings_facade") or what.contains("shed"):
		return {}
	return hit


func _ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0)
	q.collision_mask = MapTileLoader.LAYER_WORLD
	q.exclude = [_car.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else at


func _near_shop(at: Vector3) -> bool:
	for shop: Dictionary in shops:
		if (shop.at as Transform3D).origin.distance_to(at) < SIGN_GAP:
			return true
	return false


func _distance_to_path(at: Vector3) -> float:
	var on := _nearest_on_path(at)
	return Vector2(on.x - at.x, on.z - at.z).length()


## The nearest point on the street's line to `at` (at `at`'s height).
func _nearest_on_path(at: Vector3) -> Vector3:
	var p := Vector2(at.x, at.z)
	var best := INF
	var best_q := p
	for i in _path.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, Vector2(_path[i].x, _path[i].z), Vector2(_path[i + 1].x, _path[i + 1].z))
		if q.distance_squared_to(p) < best:
			best = q.distance_squared_to(p)
			best_q = q
	return Vector3(best_q.x, at.y, best_q.y)


## A 1979 shopfront on `shop`'s wall: the name on a board over an awning.
## On a venue's front (hidden while this lasts) the window and door too,
## the window lit or dark.
func _build_shop(shop: Dictionary) -> void:
	var i: int = shops.find(shop)
	var name_of: Array = SHOPS[_names[i % _names.size()]]
	var style: Array = STYLES[(i * 5 + _rng.randi() % 2) % STYLES.size()]
	var lit: bool = style[2]
	var w: float = shop.width
	var front := Node3D.new()
	front.name = "Shop_%d" % i
	_root.add_child(front)
	front.global_transform = shop.at
	var board := PS1Material.glowing(style[0], 0.55) if lit else PS1Material.make(style[0])
	RepeatStreet._part(front, Vector3(w, 0.95, 0.14), Vector3(0, SIGN_Y, 0.08), board)
	RepeatStreet._part(front, Vector3(w + 0.3, 0.07, 1.7), Vector3(0, SIGN_Y - 0.58, 0.85), PS1Material.make(AWNING))
	var glow := _rng.randf() < 0.45
	if shop.venue:
		var frame := PS1Material.make(DOOR)
		RepeatStreet._part(front, Vector3(w - 1.1, 2.1, 0.05), Vector3(0.45, 1.35, 0.025), frame)
		var window := PS1Material.glowing(SHOP_LIGHT, 0.35) if glow else PS1Material.make(SHOP_DARK, 0.2)
		RepeatStreet._part(front, Vector3(w - 1.4, 1.8, 0.05), Vector3(0.45, 1.4, 0.04), window)
		RepeatStreet._part(front, Vector3(0.85, 2.1, 0.06), Vector3(-w * 0.5 + 0.55, 1.05, 0.03), frame)
	var letters: Color = style[1]
	if not lit:
		letters = letters.darkened(0.25)
	var title := _label(String(name_of[0]), 72, w * 0.9, 0.0125)
	title.modulate = letters
	title.position = Vector3(0, SIGN_Y + (0.1 if name_of[1] != "" else 0.0), 0.16)
	front.add_child(title)
	if name_of[1] != "":
		var line := _label(String(name_of[1]), 36, w * 0.8, 0.0085)
		line.modulate = letters
		line.position = Vector3(0, SIGN_Y - 0.28, 0.16)
		front.add_child(line)
	if glow and shop.venue:
		var light := OmniLight3D.new()
		light.light_color = SHOP_LIGHT
		light.light_energy = 0.5
		light.omni_range = 4.0
		light.position = Vector3(0, 1.4, 1.2)
		front.add_child(light)


## Painted letters that fit in `width` m (no bigger than `largest` m a pixel).
static func _label(text: String, font_size: int, width: float, largest: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = minf(largest, width / (text.length() * font_size * 0.62))
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.visibility_range_end = 220.0
	return label


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = list[i]
		list[i] = list[j]
		list[j] = swap


# --- The traffic -------------------------------------------------------------

## Keep the street busy with them: while there are fewer than BUSY cars on
## it near you, another one comes, out ahead (alternately coming towards you
## and going your way).
func _keep_busy() -> void:
	var traffic := get_tree().get_first_node_in_group(&"traffic") as TrafficManager
	if traffic == null:
		return
	var near := 0
	for v: TrafficVehicle in traffic.vehicles:
		if v.active and v.lane() and v.lane().road and v.lane().road.name == street \
				and v.position.distance_to(_car.global_position) < EXTRA_TO:
			near += 1
	if near >= BUSY:
		return
	var total := _cum[_cum.size() - 1]
	var oncoming := extra % 2 == 0
	var s := _s + EXTRA_FROM
	while s < minf(_s + EXTRA_TO, total):
		var p := TrafficGraph.point_at(_path, _cum, s)
		var t := TrafficGraph.tangent_at(_path, _cum, s)
		for sample: Array in traffic.graph.samples_near(p, 12.0):
			var lane := sample[0] as TrafficGraph.Lane
			if lane.road == null or lane.road.name != street:
				continue
			var at := TrafficGraph.point_at(lane.pts, lane.cum, sample[1])
			if at.distance_to(p) > 12.0:
				continue
			var lt := TrafficGraph.tangent_at(lane.pts, lane.cum, sample[1])
			if (lt.dot(t) < -0.5) != oncoming or not _clear_of_traffic(traffic, at):
				continue
			if traffic.spawn_vehicle_at(EXTRA_TYPES[extra % EXTRA_TYPES.size()], lane, sample[1]):
				extra += 1
				return
		s += 20.0


static func _clear_of_traffic(traffic: TrafficManager, at: Vector3) -> bool:
	for v: TrafficVehicle in traffic.vehicles:
		if v.position.distance_to(at) < 14.0:
			return false
	return true
