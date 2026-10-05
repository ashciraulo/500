class_name HomeLife
extends Node
## Small daily things at home, nothing to do with cars.
##
## The cat: a ginger tabby from down the lane. Put food in the bowl by the
## kitchen bar and it turns up to eat; while you keep feeding it, it stays
## around: loafing in the courtyard sun in the morning, on the lounge rug in
## the afternoon, asleep on the end of your bed at night. Walk up and pat it.
##
## The cuttings: three rare plants to find around the city (a kangaroo paw in
## Kings Park, Geraldton wax at a Fremantle nursery, a frangipani off a
## neglected verge; data/world/cuttings.json). Each one you take home stands
## on the dining table; water them once a day and they grow, from a cutting
## in a jar to a young plant to one in flower.
##
## Saved under "home_life". Models: art/models/props/home/ (README "Home life").

signal cat_fed
signal cat_patted
signal watered(grown: PackedStringArray)

const CAT_MODEL := "res://art/models/props/home/cat.glb"
const BOWL_MODEL := "res://art/models/props/home/cat_bowl.glb"
const CAN_MODEL := "res://art/models/props/home/watering_can.glb"
const PLANT_MODEL := "res://art/models/props/home/%s.glb"
const CUTTINGS_PATH := "res://data/world/cuttings.json"
## The cat turns up this long (in-game hours) after you put food out, and
## the bowl is empty this long after.
const CAT_ARRIVES := 0.3
const CAT_EATS := 1.5
## Days without food before the cat stops coming round.
const CAT_FORGETS := 2
## Watered days to grow from a cutting to a young plant, and to flower.
const STAGE_2_DAYS := 3
const STAGE_3_DAYS := 8

## Places in the townhouse model's frame (build_shenton.py: x across, y back
## from the street, z up; ground floor at 0.15, upstairs at 3.16).
const BOWL := Vector3(2.35, 8.35, 0.15)
const CAT_AT_BOWL := Vector3(2.05, 8.3, 0.15)
const CAT_COURTYARD := Vector3(3.9, 16.0, 0.02)
const CAT_RUG := Vector3(2.9, 2.5, 0.155)
const CAT_BED := Vector3(3.62, 2.05, 3.79)
const TABLE_SPOTS := [Vector3(1.2, 10.15, 0.91), Vector3(1.2, 10.6, 0.91), Vector3(1.2, 11.05, 0.91)]
const CAN_AT := Vector3(0.32, 9.8, 0.15)
## Flowering cuttings are too big for the table; they go out in the courtyard.
const GARDEN_SPOTS := [Vector3(1.4, 16.55, 0.02), Vector3(1.95, 16.6, 0.02), Vector3(3.9, 16.6, 0.02)]

## Saved.
var fed_day := -100
var fed_hour := 0.0
var cat_visits := 0
var pats := 0
## cutting id -> {"days": watered days, "last": day last watered}
var cuttings := {}

var _home: Node3D
var _cat: Node3D
var _cat_pose := ""
var _bowl: Node3D
var _plants := {}  # id -> Node3D
var _can: Node3D
var _check := 0.0
var _arrived_day := -100


## The three cuttings from data/world/cuttings.json: [{id, name, near, offset, rumour}].
static func cutting_entries() -> Array:
	if not FileAccess.file_exists(CUTTINGS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CUTTINGS_PATH))
	return parsed.get("cuttings", []) if parsed is Dictionary else []


func _ready() -> void:
	SaveGame.register("home_life", self)


func _exit_tree() -> void:
	SaveGame.unregister("home_life")


func save_state() -> Dictionary:
	return {"fed_day": fed_day, "fed_hour": fed_hour, "cat_visits": cat_visits, "pats": pats,
		"cuttings": cuttings.duplicate(true)}


func load_state(data: Dictionary) -> void:
	fed_day = int(data.get("fed_day", fed_day))
	fed_hour = float(data.get("fed_hour", fed_hour))
	cat_visits = int(data.get("cat_visits", cat_visits))
	pats = int(data.get("pats", pats))
	cuttings = (data.get("cuttings", {}) as Dictionary).duplicate(true)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		if _home == null:
			return
		_build()
	refresh()


# --- The cat -------------------------------------------------------------------------

## Hours since you last put food out (huge if never).
func hours_since_fed() -> float:
	return (GameClock.day - fed_day) * 24.0 + GameClock.time_of_day - fed_hour


func fed_today() -> bool:
	return fed_day == GameClock.day


func bowl_full() -> bool:
	var since := hours_since_fed()
	return since >= 0.0 and since < CAT_ARRIVES + CAT_EATS


func feed_cat() -> void:
	if fed_today() and bowl_full():
		return
	var first := fed_day < 0
	fed_day = GameClock.day
	fed_hour = GameClock.time_of_day
	_play("home/home_cat_food_bowl", _home_point(BOWL), -4.0)
	Activities.say("You tip some biscuits into the bowl. Maybe someone will come." if first and cat_visits == 0
		else "Biscuits in the bowl.")
	cat_fed.emit()
	refresh()


## Where the cat is now: "" (not around), "bowl", "courtyard", "rug" or "bed".
func cat_place() -> String:
	if fed_day < 0:
		return ""
	var since := hours_since_fed()
	if since < CAT_ARRIVES:
		return ""
	if since < CAT_ARRIVES + CAT_EATS:
		return "bowl"
	if GameClock.day - fed_day > CAT_FORGETS:
		return ""
	var hour: float = GameClock.time_of_day
	if hour >= 21.0 or hour < 6.0:
		return "bed"
	if hour < 12.0:
		return "courtyard"
	return "rug"


func pat_cat() -> void:
	pats += 1
	if _cat:
		_play("home/home_cat_purr", _cat.global_position + Vector3.UP * 0.2, -6.0)
	if Discoveries.discover("home/cat"):
		Activities.say("The ginger cat from down the lane. It purrs like a little engine.")
	elif pats % 5 == 0:
		Activities.say("It leans into your hand and shuts its eyes.")
	cat_patted.emit()


# --- The cuttings --------------------------------------------------------------------

## Cuttings you've found and brought home, in the data file's order.
func found_cuttings() -> PackedStringArray:
	var found := PackedStringArray()
	for entry: Dictionary in cutting_entries():
		if Discoveries.has("cutting/" + String(entry.id)):
			found.append(String(entry.id))
	return found


func stage(id: String) -> int:
	var days := int((cuttings.get(id, {}) as Dictionary).get("days", 0))
	return 3 if days >= STAGE_3_DAYS else (2 if days >= STAGE_2_DAYS else 1)


func needs_water() -> PackedStringArray:
	var thirsty := PackedStringArray()
	for id in found_cuttings():
		if int((cuttings.get(id, {}) as Dictionary).get("last", -100)) != GameClock.day:
			thirsty.append(id)
	return thirsty


## Water every cutting that hasn't had any today; returns the ones that grew.
func water() -> PackedStringArray:
	var grown := PackedStringArray()
	for id in needs_water():
		var before := stage(id)
		var state: Dictionary = cuttings.get(id, {"days": 0, "last": -100})
		state.days = int(state.get("days", 0)) + 1
		state.last = GameClock.day
		cuttings[id] = state
		if stage(id) > before:
			grown.append(id)
	_play("home/home_watering_can", _home_point(TABLE_SPOTS[1]), -4.0)
	for id in grown:
		var name := _cutting_name(id)
		Activities.say(("The %s has flowered." if stage(id) == 3 else "The %s has put out new leaves.") % name.to_lower())
	if grown.is_empty():
		Activities.say("You water the cuttings.")
	watered.emit(grown)
	refresh()
	return grown


func _cutting_name(id: String) -> String:
	for entry: Dictionary in cutting_entries():
		if entry.id == id:
			return String(entry.get("name", id))
	return id.capitalize()


# --- Showing it ----------------------------------------------------------------------

## Point in the townhouse's frame (Blender x, y, z) as a world position.
func _home_point(p: Vector3) -> Vector3:
	return _home.global_transform * Vector3(p.x, p.z, -p.y)


func _build() -> void:
	var old_bowl := _home.find_child("Cat_Bowl", true, false) as Node3D
	if old_bowl:
		old_bowl.visible = false  # replaced by the one with food that comes and goes
	_bowl = _model(BOWL_MODEL)
	if _bowl:
		_bowl.name = "HomeLife_Bowl"
		_place(_bowl, BOWL, 0.0)
		_bowl.add_child(_Spot.new(self, "bowl"))
	_cat = _model(CAT_MODEL)
	if _cat:
		_cat.name = "HomeLife_Cat"
		_cat.add_child(_Spot.new(self, "cat"))
	_can = _model(CAN_MODEL)
	if _can:
		_can.name = "HomeLife_WateringCan"
		_place(_can, CAN_AT, 0.4)
	var table := Node3D.new()
	table.name = "HomeLife_Cuttings"
	_home.add_child(table)
	table.position = Vector3(TABLE_SPOTS[1].x, TABLE_SPOTS[1].z, -TABLE_SPOTS[1].y)
	table.add_child(_Spot.new(self, "cuttings"))
	var garden := Node3D.new()
	garden.name = "HomeLife_Garden"
	_home.add_child(garden)
	garden.position = Vector3(GARDEN_SPOTS[1].x, GARDEN_SPOTS[1].z, -GARDEN_SPOTS[1].y)
	garden.add_child(_Spot.new(self, "garden"))
	_plants.clear()
	refresh()


## Put each model where today says.
func refresh() -> void:
	if _home == null:
		return
	if _bowl:
		var food := _bowl.find_child("Food", true, false) as Node3D
		if food:
			food.visible = bowl_full()
	_refresh_cat()
	_refresh_plants()


func _refresh_cat() -> void:
	if _cat == null:
		return
	var place := cat_place()
	_cat.visible = place != ""
	if place == "":
		return
	var pose := {"bowl": "Pose_Sit", "courtyard": "Pose_Loaf", "rug": "Pose_Loaf", "bed": "Pose_Sleep"}[place] as String
	if pose != _cat_pose:
		_cat_pose = pose
		for child in _cat.get_children():
			if child is Node3D and String(child.name).begins_with("Pose_"):
				(child as Node3D).visible = child.name == pose
	match place:
		"bowl":
			_place(_cat, CAT_AT_BOWL, 0.0, BOWL)
			if _arrived_day != fed_day:
				_arrived_day = fed_day
				cat_visits += 1
				_play("home/home_cat_meow_02", _cat.global_position, -6.0)
				if cat_visits == 1:
					Activities.say("A ginger cat has let itself in through the courtyard. It's eating your biscuits.")
		"courtyard":
			_place(_cat, CAT_COURTYARD, 2.3)
		"rug":
			_place(_cat, CAT_RUG, -0.6)
		"bed":
			_place(_cat, CAT_BED, 1.2)


func _refresh_plants() -> void:
	var found := found_cuttings()
	for id: String in _plants.keys():
		if not found.has(id):
			(_plants[id] as Node3D).queue_free()
			_plants.erase(id)
	for i in found.size():
		var id := found[i]
		if not _plants.has(id):
			var plant := _model(PLANT_MODEL % id)
			if plant == null:
				continue
			plant.name = "HomeLife_" + id
			_plants[id] = plant
		var spots: Array = GARDEN_SPOTS if stage(id) == 3 else TABLE_SPOTS
		_place(_plants[id], spots[i % spots.size()], 0.3 * i)
		var want := "Stage_%d" % stage(id)
		for child in (_plants[id] as Node3D).get_children():
			if child is Node3D and String(child.name).begins_with("Stage_"):
				(child as Node3D).visible = child.name == want


func _model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	PS1Model.apply(model)
	_home.add_child(model)
	return model


## Put `node` at a townhouse point, turned `yaw` (radians), or facing `look_at`.
func _place(node: Node3D, at: Vector3, yaw: float, look_at := Vector3.INF) -> void:
	node.position = Vector3(at.x, at.z, -at.y)
	if look_at != Vector3.INF:
		var to := Vector3(look_at.x - at.x, 0.0, -(look_at.y - at.y))
		yaw = atan2(to.x, to.z)  # the models face +Z
	node.rotation = Vector3(0.0, yaw, 0.0)


func _play(sound: String, at: Vector3, volume_db: float) -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has(sound):
		audio.play_at(sound, at, volume_db)


## What you can do at the bowl, the cat and the cuttings, for OnFoot.
class _Spot extends Node3D:
	var life: HomeLife
	var kind := ""

	func _init(owner_life: HomeLife, what: String) -> void:
		life = owner_life
		kind = what
		name = "Use_" + what

	func _ready() -> void:
		add_to_group(&"interactables")

	func interact_point() -> Vector3:
		return global_position + Vector3.UP * (0.15 if kind == "cuttings" else 0.25)

	func interact_hint() -> String:
		if not is_visible_in_tree():
			return ""
		match kind:
			"bowl":
				return "" if life.bowl_full() or life.fed_today() else "Put some food out for the cat"
			"cat":
				return "Pat the cat"
			"cuttings":
				return "Water the cuttings" if not life.needs_water().is_empty() else ""
			"garden":
				var flowering := false
				for id in life.found_cuttings():
					flowering = flowering or life.stage(id) == 3
				return "Water the plants" if flowering and not life.needs_water().is_empty() else ""
		return ""

	func interact() -> void:
		match kind:
			"bowl":
				life.feed_cat()
			"cat":
				life.pat_cat()
			"cuttings", "garden":
				life.water()
