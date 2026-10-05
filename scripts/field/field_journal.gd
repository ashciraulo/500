extends Node
## The field journal (autoload: FieldJournal): every bird you've seen and
## photographed, every fish you've caught, the film in the camera, the esky,
## and the gear you carry. Dredge on wheels: the film roll and the esky are
## the hold, the photo lab and the tackle shop are the dock.
##
## Species are data (data/field/birds.json, fish.json), places too
## (data/field/habitats.json, fishing_spots.json). The world side (sightings,
## binoculars, the rod, the lab and the tackle shop, the journal screen) is
## built by FieldWorld when the game scene appears, so the autoload itself
## works headless and in tests.
##
## Progress is saved under "field_journal". Stats for the career:
## species_seen, species_photographed, prints_sold. The wrong birds (after
## midnight, see FieldBirds) don't count as species: seeing one is the
## discovery "field/<id>" and opens M.'s page on it.

signal species_seen(id: String)
## A frame was used: `stars` 1..3.
signal photo_logged(id: String, stars: int, frame: Dictionary)
signal film_changed(left: int, size: int)
## The lab developed the roll: `prints` [{species, name, stars, pay, wrong}], `pay` after the lab's fee.
signal roll_developed(prints: Array, pay: int)
## A fish (or crab, or worse) came up: `fish` {species, cm, kg, legal, ...}.
signal fish_landed(fish: Dictionary)
signal esky_changed(count: int, size: int)
## The tackle shop weighed in the esky: `fish` [{species, name, kg, pay, ...}], `pay` in total.
signal weighed_in(fish: Array, pay: int)

const BIRDS_PATH := "res://data/field/birds.json"
const HABITATS_PATH := "res://data/field/habitats.json"
## Print value by stars (two stars is the species' listed value).
const STAR_PAY := [0.0, 0.5, 1.0, 1.8]
## The first print of a species is worth more: a magazine wants it.
const FIRST_PRINT_BONUS := 1.5
const DEVELOP_PRICE := 15
## Gear by level. Binoculars: how far you can make a bird out, how fast,
## and how far they zoom (narrowest field of view). Cameras: frames per roll
## and how forgiving the focus dial is.
const BINOCULARS := [
	{"name": "Old 8x30s (M.)", "range": 150.0, "identify": 1.4, "fov": 9.0, "night": 0.15, "price": 0},
	{"name": "10x42 roof prisms", "range": 220.0, "identify": 1.0, "fov": 7.0, "night": 0.3, "price": 480},
	{"name": "Stabilised 12x50s", "range": 300.0, "identify": 0.7, "fov": 5.5, "night": 0.5, "price": 1450},
]
const CAMERAS := [
	{"name": "Pawn-shop compact", "frames": 24, "ease": 0.0, "price": 0},
	{"name": "Second-hand 35 mm SLR", "frames": 36, "ease": 0.25, "price": 650},
	{"name": "Pro body, motor drive", "frames": 36, "ease": 0.5, "price": 2200},
]
const RARITY_NAMES := ["", "Common", "Uncommon", "Rare", "Very rare"]

const FISH_PATH := "res://data/field/fish.json"
const SPOTS_PATH := "res://data/field/fishing_spots.json"
## Rods: how much line tension they take before it snaps, and how fast the reel winds.
const RODS := [
	{"name": "Hand-me-down rod", "strength": 1.0, "reel": 1.0, "price": 0},
	{"name": "Graphite spin rod", "strength": 1.25, "reel": 1.2, "price": 380},
	{"name": "Surf rod and Alvey reel", "strength": 1.5, "reel": 1.35, "price": 1100},
]
const ESKIES := [
	{"name": "Little esky", "size": 4, "price": 0},
	{"name": "Family esky", "size": 8, "price": 160},
	{"name": "Big chest esky", "size": 14, "price": 420},
]
const CRAB_NET_PRICE := 45
## A crab net wants this many game hours down before it's worth pulling.
const CRAB_SOAK_HOURS := 0.75
## A bag of ice keeps the esky cold this many game hours.
const ICE_PRICE := 5
const ICE_HOURS := 8.0
## Out of the ice a fish loses value over this many game hours, down to FRESH_FLOOR.
const SPOIL_HOURS := 4.0
const FRESH_FLOOR := 0.4
## The first fish of a species weighed in earns the club's "new to the board" bonus.
const FIRST_FISH_BONUS := 1.5

var birds := {}
var bird_order: PackedStringArray = []
var habitats: Array = []
## id -> {seen: day, where: place name, photos: n, best: stars, best_file, sold: n}
var entries := {}
## Frames on the roll in the camera: [{species, stars, file, day, time, where, wrong}].
var roll: Array = []
var binoculars := 0
var camera := 0
var prints_sold := 0
var money_from_prints := 0

var fish := {}
var fish_order: PackedStringArray = []
var spots: Array = []
## id -> {caught: n, kept: n, released: n, biggest_cm, biggest_kg, first_day, time, where, best_file, weighed: n}
var catches := {}
## What's in the esky: [{species, cm, kg, caught_at (game minutes), where}].
var esky: Array = []
var rod := 0
var esky_level := 0
var has_crab_net := false
## Crab nets down: spot id -> game minute it went in.
var crab_nets := {}
## Game minute the ice runs out.
var ice_until := 0.0
var fish_weighed := 0
var money_from_fish := 0

var _world: Node


func _ready() -> void:
	_load_data()
	SaveGame.register("field_journal", self)


func _process(_delta: float) -> void:
	# Build the world side once the game scene (with the player's car) is up.
	if _world != null and is_instance_valid(_world):
		return
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	if car == null or not car.is_inside_tree() or car.get_parent() == null:
		return
	_world = FieldWorld.new()
	_world.name = "Field"
	car.get_parent().add_child(_world)


func _load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BIRDS_PATH))
	if parsed is Dictionary:
		for b: Dictionary in parsed.get("birds", []):
			birds[b.id] = b
			bird_order.append(b.id)
	parsed = JSON.parse_string(FileAccess.get_file_as_string(HABITATS_PATH))
	if parsed is Dictionary:
		habitats = parsed.get("habitats", [])
	parsed = JSON.parse_string(FileAccess.get_file_as_string(FISH_PATH))
	if parsed is Dictionary:
		for f: Dictionary in parsed.get("fish", []):
			fish[f.id] = f
			fish_order.append(f.id)
	parsed = JSON.parse_string(FileAccess.get_file_as_string(SPOTS_PATH))
	if parsed is Dictionary:
		# Only spots placed in the map (tools/field/place_spots.gd).
		spots = parsed.get("spots", []).filter(func(sp: Dictionary) -> bool: return sp.has("stand"))


# --- species and places ---------------------------------------------------------

func bird(id: String) -> Dictionary:
	return birds.get(id, {})


func habitat(id: String) -> Dictionary:
	for h: Dictionary in habitats:
		if h.id == id:
			return h
	return {}


static func habitat_centre(h: Dictionary) -> Vector3:
	return Vector3(float(h.get("x", 0.0)), 0.0, float(h.get("z", 0.0)))


## Habitats whose circle comes within `extra` metres of p.
func habitats_near(p: Vector3, extra := 0.0) -> Array:
	var out := []
	for h: Dictionary in habitats:
		var c := habitat_centre(h)
		if Vector2(p.x - c.x, p.z - c.z).length() < float(h.radius) + extra:
			out.append(h)
	return out


## The name of the place p is in, for the journal ("Kings Park bushland").
func place_name(p: Vector3) -> String:
	var best := ""
	var best_d := INF
	for h: Dictionary in habitats_near(p):
		var c := habitat_centre(h)
		var d := Vector2(p.x - c.x, p.z - c.z).length() / float(h.radius)
		if d < best_d:
			best_d = d
			best = h.name
	if best != "":
		return best
	var map := map_node()
	if map and map.has_method("get_landmarks"):
		var marks: Dictionary = map.get_landmarks()
		for name: String in marks:
			var m: Variant = marks[name]
			var at := m as Vector2 if m is Vector2 else Vector2(float(m[0]), float(m[1]))
			var d := Vector2(p.x - at.x, p.z - at.y).length()
			if d < best_d:
				best_d = d
				best = name
	return best if best != "" else "Perth"


## The Perth map (MapStreamer), or null on the test grid.
func map_node() -> Node:
	if not is_inside_tree():
		return null
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map == null and _world and is_instance_valid(_world):
		map = _world.get_parent().get_node_or_null(^"PerthMap")
	return map


## Whether a species is about at this hour and in this weather.
static func is_about(b: Dictionary, hour: float, rain: float) -> bool:
	match String(b.get("weather", "any")):
		"dry":
			if rain > 0.45:
				return false
		"wet":
			if rain < 0.2:
				return false
	for span: Array in b.get("hours", []):
		var from := float(span[0])
		var to := float(span[1])
		if (from <= to and hour >= from and hour < to) or (from > to and (hour >= from or hour < to)):
			return true
	return false


## Species that could turn up in this habitat now (not traffic's own birds).
func candidates(h: Dictionary, hour: float, rain: float) -> Array:
	var out := []
	var tags: Array = h.get("tags", [])
	for id in bird_order:
		var b: Dictionary = birds[id]
		if b.get("source", "") != "" or b.get("wrong", false):
			continue
		var places: Array = b.get("places", [])
		if not places.is_empty() and not places.has(h.id):
			continue
		if places.is_empty() and not Array(b.get("habitats", [])).any(func(t: String) -> bool: return tags.has(t)):
			continue
		if is_about(b, hour, rain):
			out.append(b)
	return out


# --- the journal --------------------------------------------------------------------

func is_seen(id: String) -> bool:
	return entries.has(id)


func is_photographed(id: String) -> bool:
	return int(entries.get(id, {}).get("photos", 0)) > 0


func entry(id: String) -> Dictionary:
	return entries.get(id, {})


## Note a species as seen. True the first time.
func see(id: String, where := "") -> bool:
	if not birds.has(id) or entries.has(id):
		return false
	entries[id] = {"seen": GameClock.day, "time": GameClock.time_string(), "where": where, "photos": 0, "best": 0, "best_file": "", "sold": 0}
	if birds[id].get("wrong", false):
		# Not a species for the career; a page already written for the mystery.
		Discoveries.discover("field/" + id)
	else:
		Progression.add_stat("species_seen")
	species_seen.emit(id)
	return true


## How many real species there are to find (the wrong birds aren't counted).
func species_total() -> int:
	var n := 0
	for id in bird_order:
		if not birds[id].get("wrong", false):
			n += 1
	return n


func seen_count() -> int:
	var n := 0
	for id: String in entries:
		if not bird(id).get("wrong", false):
			n += 1
	return n


func photographed_count() -> int:
	var n := 0
	for id: String in entries:
		if is_photographed(id) and not bird(id).get("wrong", false):
			n += 1
	return n


func gear_binoculars() -> Dictionary:
	return BINOCULARS[clampi(binoculars, 0, BINOCULARS.size() - 1)]


func gear_camera() -> Dictionary:
	return CAMERAS[clampi(camera, 0, CAMERAS.size() - 1)]


func roll_size() -> int:
	return int(gear_camera().frames)


func film_left() -> int:
	return maxi(roll_size() - roll.size(), 0)


## Put a photo on the roll. `file` is the album image.
func log_photo(id: String, stars: int, file: String, where: String) -> Dictionary:
	stars = clampi(stars, 1, 3)
	see(id, where)
	var b := bird(id)
	var frame := {"species": id, "stars": stars, "file": file, "day": GameClock.day, "time": GameClock.time_string(),
		"where": where, "wrong": bool(b.get("wrong", false))}
	roll.append(frame)
	var e: Dictionary = entries[id]
	if int(e.photos) == 0 and not b.get("wrong", false):
		Progression.add_stat("species_photographed")
	e.photos = int(e.photos) + 1
	if stars > int(e.best) or e.best_file == "":
		e.best = maxi(stars, int(e.best))
		e.best_file = file
	photo_logged.emit(id, stars, frame)
	film_changed.emit(film_left(), roll_size())
	return frame


## What the lab will pay for a frame (0 for the ones that won't print).
func print_value(frame: Dictionary, first := false) -> int:
	if frame.get("wrong", false):
		return 0
	var b := bird(String(frame.species))
	var pay: float = float(b.get("value", 5)) * STAR_PAY[clampi(int(frame.stars), 1, 3)]
	if first:
		pay *= FIRST_PRINT_BONUS
	return roundi(pay)


## Develop the roll at the lab and sell the prints. Returns {prints, pay, fee}.
func develop() -> Dictionary:
	var prints := []
	var total := 0
	var sold_now := {}
	for frame: Dictionary in roll:
		var id := String(frame.species)
		var first := int(entries.get(id, {}).get("sold", 0)) == 0 and not sold_now.has(id)
		var pay := print_value(frame, first)
		if pay > 0:
			sold_now[id] = true
			entries[id].sold = int(entries[id].get("sold", 0)) + 1
			prints_sold += 1
			Progression.add_stat("prints_sold")
		total += pay
		prints.append({"species": id, "name": bird(id).get("name", id), "stars": frame.stars, "pay": pay,
			"wrong": frame.get("wrong", false), "first": first and pay > 0, "file": frame.file})
	var fee := DEVELOP_PRICE if not roll.is_empty() else 0
	var net := total - fee
	if net > 0:
		Wallet.earn(net)
	elif net < 0:
		Wallet.spend(mini(-net, Wallet.balance))
	money_from_prints += maxi(net, 0)
	roll.clear()
	film_changed.emit(film_left(), roll_size())
	roll_developed.emit(prints, net)
	return {"prints": prints, "pay": net, "fee": fee, "gross": total}


## Buy the next binoculars or camera at the lab. Returns false if you can't.
func upgrade(kind: String) -> bool:
	var list := BINOCULARS if kind == "binoculars" else CAMERAS
	var level := binoculars if kind == "binoculars" else camera
	if level + 1 >= list.size():
		return false
	var price := int(list[level + 1].price)
	if not Wallet.spend(price):
		return false
	if kind == "binoculars":
		binoculars += 1
	else:
		camera += 1
		film_changed.emit(film_left(), roll_size())
	return true


# --- fishing ------------------------------------------------------------------------

func fish_species(id: String) -> Dictionary:
	return fish.get(id, {})


func spot(id: String) -> Dictionary:
	for sp: Dictionary in spots:
		if sp.id == id:
			return sp
	return {}


static func spot_stand(sp: Dictionary) -> Vector3:
	var a: Array = sp.get("stand", [0, 0, 0])
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## What might bite at this spot now, by line or by crab net.
func fish_candidates(sp: Dictionary, hour: float, method := "line") -> Array:
	var out := []
	var tags: Array = sp.get("tags", [])
	for id in fish_order:
		var f: Dictionary = fish[id]
		if String(f.get("method", "line")) != method:
			continue
		if not Array(f.get("water", [])).has(sp.get("water", "river")):
			continue
		if not is_about(f, hour, 0.0):
			continue
		# A few want a particular kind of spot.
		match id:
			"fiat_hubcap":
				if not tags.has("hubcap"):
					continue
			"squid":
				if not (tags.has("lights") or tags.has("jetty")):
					continue
			"mulloway":
				if not tags.has("deep"):
					continue
			"yellowfin_whiting", "flathead":
				if not (tags.has("flats") or sp.get("water", "") == "estuary"):
					continue
			"black_bream":
				if not (tags.has("jetty") or tags.has("snags")):
					continue
			"king_george_whiting":
				if not (tags.has("beach") or tags.has("rocks")):
					continue
		out.append(f)
	return out


## Which of `candidates` bites: common ones far more often than rare ones.
static func pick_fish(candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total := 0.0
	var weights: Array[float] = []
	for f: Dictionary in candidates:
		var w: float = [6.0, 6.0, 3.0, 1.2, 0.45][clampi(int(f.get("rarity", 1)), 0, 4)]
		weights.append(w)
		total += w
	var roll_at := rng.randf() * total
	for i in candidates.size():
		roll_at -= weights[i]
		if roll_at <= 0.0:
			return candidates[i]
	return candidates[-1]


## A size for a fish that's just bitten: mostly small ones, the odd big one.
static func fish_size(f: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var range_cm: Array = f.get("length", [10, 20])
	var t := pow(rng.randf(), 2.2)
	var cm := snappedf(lerpf(float(range_cm[0]), float(range_cm[1]), t), 0.5)
	var kg := snappedf(float(f.get("k", 0.01)) * pow(cm / 10.0, 3.0), 0.01)
	var legal := cm >= float(f.get("legal", 0))
	return {"species": String(f.id), "cm": cm, "kg": kg, "legal": legal, "junk": bool(f.get("junk", false))}


func gear_rod() -> Dictionary:
	return RODS[clampi(rod, 0, RODS.size() - 1)]


func gear_esky() -> Dictionary:
	return ESKIES[clampi(esky_level, 0, ESKIES.size() - 1)]


func esky_size() -> int:
	return int(gear_esky().size)


func esky_room() -> int:
	return maxi(esky_size() - esky.size(), 0)


func now_minutes() -> float:
	return GameClock.day * 1440.0 + GameClock.time_of_day * 60.0


func ice_left_hours() -> float:
	return maxf(ice_until - now_minutes(), 0.0) / 60.0


## How fresh a fish in the esky still is (1 on ice, down to FRESH_FLOOR).
func freshness(f: Dictionary) -> float:
	var now := now_minutes()
	# Warm since whichever came later: the catch, or the ice running out.
	var warm_from := maxf(float(f.get("caught_at", now)), ice_until)
	if now <= warm_from:
		return 1.0
	return maxf(1.0 - (now - warm_from) / (SPOIL_HOURS * 60.0) * (1.0 - FRESH_FLOOR), FRESH_FLOOR)


## A catch came up. Notes it in the journal (and the career); undersized
## fish and junk aren't kept. Returns the catch dictionary.
func land(caught: Dictionary, where: String, file := "") -> Dictionary:
	var id := String(caught.species)
	var f := fish_species(id)
	var first := not catches.has(id)
	if first:
		catches[id] = {"caught": 0, "kept": 0, "released": 0, "biggest_cm": 0.0, "biggest_kg": 0.0, "first_day": GameClock.day,
			"time": GameClock.time_string(), "where": where, "best_file": "", "weighed": 0}
		if not f.get("junk", false):
			Progression.add_stat("fish_species")
	var e: Dictionary = catches[id]
	e.caught = int(e.caught) + 1
	if not f.get("junk", false):
		Progression.add_stat("fish_caught")
	if float(caught.cm) > float(e.biggest_cm):
		e.biggest_cm = caught.cm
		e.biggest_kg = caught.kg
		if file != "":
			e.best_file = file
	elif e.best_file == "" and file != "":
		e.best_file = file
	caught["first"] = first
	caught["where"] = where
	fish_landed.emit(caught)
	return caught


## Into the esky (if it's legal and there's room). True if kept.
func keep(caught: Dictionary) -> bool:
	if not caught.get("legal", false) or caught.get("junk", false) or esky_room() <= 0:
		return false
	esky.append({"species": caught.species, "cm": caught.cm, "kg": caught.kg, "caught_at": now_minutes(), "where": caught.get("where", "")})
	var e: Dictionary = catches.get(String(caught.species), {})
	if not e.is_empty():
		e.kept = int(e.kept) + 1
	esky_changed.emit(esky.size(), esky_size())
	return true


func release(caught: Dictionary) -> void:
	var e: Dictionary = catches.get(String(caught.species), {})
	if not e.is_empty():
		e.released = int(e.released) + 1


## The prize money for one fish from the esky now.
func fish_value(f: Dictionary, first := false) -> int:
	var sp := fish_species(String(f.species))
	var pay := float(f.kg) * float(sp.get("pay", 0)) * freshness(f)
	if first:
		pay *= FIRST_FISH_BONUS
	return maxi(roundi(pay), 0)


func is_caught(id: String) -> bool:
	return catches.has(id)


func caught_count() -> int:
	var n := 0
	for id: String in catches:
		if not fish_species(id).get("junk", false):
			n += 1
	return n


func fish_total() -> int:
	var n := 0
	for id in fish_order:
		if not fish[id].get("junk", false):
			n += 1
	return n


## Weigh in the esky at the tackle shop: the anglers' club pays by the kilo.
func weigh_in() -> Dictionary:
	var out := []
	var total := 0
	var done_now := {}
	for f: Dictionary in esky:
		var id := String(f.species)
		var e: Dictionary = catches.get(id, {})
		var first := int(e.get("weighed", 0)) == 0 and not done_now.has(id)
		var pay := fish_value(f, first)
		done_now[id] = true
		if not e.is_empty():
			e.weighed = int(e.get("weighed", 0)) + 1
		fish_weighed += 1
		total += pay
		out.append({"species": id, "name": fish_species(id).get("name", id), "cm": f.cm, "kg": f.kg, "pay": pay,
			"fresh": freshness(f), "first": first})
	if total > 0:
		Wallet.earn(total)
	money_from_fish += total
	esky.clear()
	esky_changed.emit(0, esky_size())
	weighed_in.emit(out, total)
	return {"fish": out, "pay": total}


func buy_ice() -> bool:
	if not Wallet.spend(ICE_PRICE):
		return false
	ice_until = maxf(ice_until, now_minutes()) + ICE_HOURS * 60.0
	# Topping up an esky that's gone warm doesn't unspoil what's in it, but
	# keeps it from getting worse.
	return true


## Buy the next rod or esky, or the crab net, at the tackle shop.
func upgrade_fishing(kind: String) -> bool:
	match kind:
		"crab_net":
			if has_crab_net or not Wallet.spend(CRAB_NET_PRICE):
				return false
			has_crab_net = true
			return true
		"rod", "esky":
			var list := RODS if kind == "rod" else ESKIES
			var level := rod if kind == "rod" else esky_level
			if level + 1 >= list.size() or not Wallet.spend(int(list[level + 1].price)):
				return false
			if kind == "rod":
				rod += 1
			else:
				esky_level += 1
				esky_changed.emit(esky.size(), esky_size())
			return true
	return false


## A career stat read live from the journal (Progression asks for these):
## species_seen, species_photographed, prints_sold, fish_caught, fish_species.
func stat(stat_name: String) -> float:
	match stat_name:
		"species_seen":
			return float(seen_count())
		"species_photographed":
			return float(photographed_count())
		"prints_sold":
			return float(prints_sold)
		"fish_species":
			return float(caught_count())
		"fish_caught":
			var n := 0
			for id: String in catches:
				if not fish_species(id).get("junk", false):
					n += int(catches[id].get("caught", 0))
			return float(n)
	return 0.0


func save_state() -> Dictionary:
	return {"entries": entries, "roll": roll, "binoculars": binoculars, "camera": camera,
		"prints_sold": prints_sold, "money_from_prints": money_from_prints,
		"catches": catches, "esky": esky, "rod": rod, "esky_level": esky_level, "crab_net": has_crab_net,
		"ice_until": ice_until, "fish_weighed": fish_weighed, "money_from_fish": money_from_fish, "crab_nets": crab_nets}


func load_state(data: Dictionary) -> void:
	entries = data.get("entries", {})
	roll = data.get("roll", [])
	binoculars = int(data.get("binoculars", 0))
	camera = int(data.get("camera", 0))
	prints_sold = int(data.get("prints_sold", 0))
	money_from_prints = int(data.get("money_from_prints", 0))
	catches = data.get("catches", {})
	esky = data.get("esky", [])
	rod = int(data.get("rod", 0))
	esky_level = int(data.get("esky_level", 0))
	has_crab_net = bool(data.get("crab_net", false))
	ice_until = float(data.get("ice_until", 0.0))
	fish_weighed = int(data.get("fish_weighed", 0))
	money_from_fish = int(data.get("money_from_fish", 0))
	crab_nets = data.get("crab_nets", {})
	film_changed.emit(film_left(), roll_size())
	esky_changed.emit(esky.size(), esky_size())
