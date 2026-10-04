extends Node
## The classic garage (autoload: Classics): rumours, barn finds and restoration.
##
## Each 1957-75 classic starts as a rumour. Once you've heard it, the wreck
## appears where the rumour says (a `BarnFind` placed from
## data/world/places.json). Finding it puts it in your garage as a project,
## and you restore it stage by stage at the home carport's Restore bench
## (data/cars/restoration.json). It can be driven once the mechanical stages
## are done; finishing picks original spec or a restomod.
##
## Rumours come in slowly: one for every tier you complete and one for each
## night you turn up to the car meet. The doorless Jolly is the last one, and
## only after every other classic has been found.

signal rumour_heard(car_id: String, text: String)
signal wreck_found(car_id: String)
signal stage_done(car_id: String, stage: Dictionary)
signal restored(car_id: String, finish: String)

const RESTORATION_PATH := "res://data/cars/restoration.json"
const PLACES_PATH := "res://data/world/places.json"
const SECRET := "classic_jolly"

## Car ids whose rumour you've heard, in the order heard.
var rumours: PackedStringArray = []
## car id -> {"stages": [ids done], "finish": "" | "original" | "restomod"}
var projects := {}
## Day number of the last car meet that gave a rumour.
var last_meet_day := -1

var _config := {}
var _barn_finds: Array = []


func _ready() -> void:
	_config = _load_json(RESTORATION_PATH)
	_barn_finds = _load_json(PLACES_PATH).get("barn_finds", [])
	SaveGame.register("classics", self)
	Progression.tier_completed.connect(func(_i: int, _t: Dictionary) -> void: hear_next_rumour())


# --- rumours -------------------------------------------------------------------

func barn_finds() -> Array:
	return _barn_finds


func barn_find(car_id: String) -> Dictionary:
	for b: Dictionary in _barn_finds:
		if b.car == car_id:
			return b
	return {}


func has_rumour(car_id: String) -> bool:
	return rumours.has(car_id)


## The next rumour in the fixed order, or "" when there's nothing left to hear.
func next_rumour() -> String:
	for b: Dictionary in _barn_finds:
		if rumours.has(b.car):
			continue
		if b.car == SECRET and found_count() < _barn_finds.size() - 1:
			continue
		return b.car
	return ""


## Learn the next rumour. Returns the car id, or "" if none are left.
func hear_next_rumour() -> String:
	var car_id := next_rumour()
	if car_id != "":
		hear_rumour(car_id)
	return car_id


func hear_rumour(car_id: String) -> void:
	if rumours.has(car_id) or barn_find(car_id).is_empty():
		return
	rumours.append(car_id)
	rumour_heard.emit(car_id, barn_find(car_id).get("rumour", ""))


## Rumours you've heard about cars you haven't found yet.
func open_leads() -> Array:
	var out := []
	for id in rumours:
		if not is_found(id):
			out.append(barn_find(id))
	return out


## The car meet passes on one rumour per night.
func meet_rumour() -> String:
	if last_meet_day == GameClock.day:
		return ""
	var car_id := hear_next_rumour()
	if car_id != "":
		last_meet_day = GameClock.day
	return car_id


# --- finds -------------------------------------------------------------------------

func is_found(car_id: String) -> bool:
	return projects.has(car_id)


func found_count() -> int:
	return projects.size()


func find_wreck(car_id: String) -> bool:
	if is_found(car_id) or barn_find(car_id).is_empty():
		return false
	projects[car_id] = {"stages": [], "finish": ""}
	Discoveries.discover("barn/" + car_id)
	Garage.add_car(car_id)
	Progression.add_stat("barn_finds")
	wreck_found.emit(car_id)
	return true


# --- restoration -------------------------------------------------------------------

func stages() -> Array:
	return _config.get("stages", [])


func finishes() -> Dictionary:
	return _config.get("finish", {})


func cost_scale(car_id: String) -> float:
	return float(_config.get("cost_scale", {}).get(car_id, 1.0))


func stage_price(car_id: String, stage: Dictionary) -> int:
	return roundi(float(stage.price) * cost_scale(car_id) * Progression.pay_multiplier() / 5.0) * 5


func is_stage_done(car_id: String, stage_id: String) -> bool:
	return projects.has(car_id) and projects[car_id].stages.has(stage_id)


## The next stage to do, or {} when only the finish (or nothing) is left.
func next_stage(car_id: String) -> Dictionary:
	for s: Dictionary in stages():
		if not is_stage_done(car_id, s.id):
			return s
	return {}


## Do the next stage. Returns false if it isn't the car's next stage or you can't afford it.
func do_stage(car_id: String, stage_id: String) -> bool:
	var stage := next_stage(car_id)
	if stage.is_empty() or stage.id != stage_id:
		return false
	if not Wallet.spend(stage_price(car_id, stage), "restoration"):
		return false
	projects[car_id].stages.append(stage_id)
	GameClock.advance(float(stage.hours))
	Progression.add_stat("restoration_stages")
	stage_done.emit(car_id, stage)
	return true


func finish(car_id: String) -> String:
	return projects.get(car_id, {}).get("finish", "")


func is_restored(car_id: String) -> bool:
	return finish(car_id) != ""


## Pick original spec or restomod once every stage is done.
func choose_finish(car_id: String, kind: String) -> bool:
	if not projects.has(car_id) or is_restored(car_id) or not next_stage(car_id).is_empty():
		return false
	var f: Dictionary = finishes().get(kind, {})
	if f.is_empty() or not Wallet.spend(roundi(float(f.price) * cost_scale(car_id)), "restoration"):
		return false
	projects[car_id].finish = kind
	GameClock.advance(float(f.hours))
	Progression.add_stat("classics_restored")
	restored.emit(car_id, kind)
	return true


## Classics can't be driven until the mechanical stages are done. Other cars always can.
func can_drive(car_id: String) -> bool:
	if not CarCatalogue.get_car(car_id).get("ladder", "") == "classic":
		return true
	if not projects.has(car_id):
		return false
	for s: Dictionary in stages():
		if s.get("needed_to_drive", false) and not is_stage_done(car_id, s.id):
			return false
	return true


## How restored it looks, 0 (wreck) to 1 (concours).
func condition(car_id: String) -> float:
	if not projects.has(car_id):
		return 0.0
	return float(projects[car_id].stages.size()) / maxf(stages().size(), 1.0)


## The paint a classic wears: rust until it's painted, then its original colour.
func paint_for(car_id: String) -> Color:
	var colors: Dictionary = _config.get("original_colors", {})
	if is_stage_done(car_id, "paint") and colors.has(car_id):
		var c: Array = colors[car_id]
		return Color(c[0], c[1], c[2])
	var r: Array = _config.get("rust_color", [0.45, 0.28, 0.18])
	return Color(r[0], r[1], r[2])


## Extra performance modifiers for a car (the restomod), in CarPart modifier terms.
func modifiers(car_id: String) -> Dictionary:
	if finish(car_id) == "":
		return {}
	return finishes().get(finish(car_id), {}).get("modifiers", {})


func save_state() -> Dictionary:
	return {"rumours": Array(rumours), "projects": projects, "last_meet_day": last_meet_day}


func load_state(data: Dictionary) -> void:
	rumours = PackedStringArray(data.get("rumours", []))
	projects = data.get("projects", {})
	last_meet_day = int(data.get("last_meet_day", -1))


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
