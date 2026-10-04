extends Node
## Side activities that aren't progression (autoload: Activities): the photo
## album, parking challenge records, scenic drives, car meets and lifts. They
## still count a few stats, so tier challenges can nod at them.

signal photo_taken(entry: Dictionary)
signal photo_spot_found(spot_id: String, title: String)
signal parking_finished(bay_id: String, result: Dictionary)
signal scenic_finished(drive_id: String, title: String)
signal meet_visited(rumour_car: String)
signal message(text: String)

const PHOTO_DIR := "user://photos"
const PHOTO_SPOTS_TOTAL := 30
const PARKING_MEDALS := ["gold", "silver", "bronze"]

## [{file, day, time, spot}] newest last.
var photos: Array = []
## bay id -> {"best": score, "medal": "gold"/...}
var parking: Dictionary = {}
## Scenic drive id -> times driven.
var scenic: Dictionary = {}
## Relaxed cruising: lighter traffic and no job offers.
var relaxed := false


func _ready() -> void:
	SaveGame.register("activities", self)


# --- photos ----------------------------------------------------------------------

## Save an image to the album. `spot` is the photo spot it was taken at, if any.
func add_photo(image: Image, spot: Node = null) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var file := "%s/day%03d_%s_%d.png" % [PHOTO_DIR, GameClock.day, GameClock.time_string().replace(":", ""), Time.get_ticks_msec() % 100000]
	if image:
		image.save_png(file)
	var entry := {"file": file, "day": GameClock.day, "time": GameClock.time_string(), "spot": ""}
	Progression.add_stat("photos_taken")
	if spot and Discoveries.discover("photo/" + String(spot.get("spot_id"))):
		entry.spot = spot.get("spot_id")
		Progression.add_stat("photo_spots")
		photo_spot_found.emit(entry.spot, String(spot.get("title")))
	photos.append(entry)
	photo_taken.emit(entry)
	return entry


func photo_spots_found() -> int:
	var count := 0
	for id in Discoveries.all():
		if String(id).begins_with("photo/"):
			count += 1
	return count


# --- parking -----------------------------------------------------------------------

## Record a parking attempt. Returns the record with "new_medal" set if it improved.
func record_parking(bay_id: String, score: int, medal: String) -> Dictionary:
	var record: Dictionary = parking.get(bay_id, {"best": 0, "medal": ""})
	var old_rank := PARKING_MEDALS.find(record.medal) if record.medal != "" else 99
	var new_rank := PARKING_MEDALS.find(medal) if medal != "" else 99
	var result := {"score": score, "medal": medal, "best": maxi(int(record.best), score), "new_medal": false}
	if record.medal == "" and medal != "":
		Progression.add_stat("parking_done")
	if new_rank < old_rank:
		result.new_medal = true
		if medal == "gold":
			Progression.add_stat("parking_gold")
		record.medal = medal
	record.best = result.best
	parking[bay_id] = record
	parking_finished.emit(bay_id, result)
	return result


# --- scenic drives, meets, lifts ------------------------------------------------------

func finish_scenic(drive_id: String, title: String) -> void:
	scenic[drive_id] = int(scenic.get(drive_id, 0)) + 1
	Progression.add_stat("scenic_drives")
	scenic_finished.emit(drive_id, title)


func visit_meet() -> String:
	var rumour := Classics.meet_rumour()
	if rumour != "":
		Progression.add_stat("meets_attended")
		Progression.check_meet_rewards(int(Progression.get_stat("meets_attended")))
	meet_visited.emit(rumour)
	return rumour


func set_relaxed(value: bool) -> void:
	relaxed = value
	var traffic := get_tree().get_first_node_in_group(&"traffic")
	if traffic and "density_scale" in traffic:
		traffic.density_scale = 0.35 if relaxed else 1.0
	message.emit("Relaxed cruising on: lighter traffic, no job offers." if relaxed else "Relaxed cruising off.")


func say(text: String) -> void:
	message.emit(text)


func save_state() -> Dictionary:
	return {"photos": photos, "parking": parking, "scenic": scenic, "relaxed": relaxed}


func load_state(data: Dictionary) -> void:
	photos = data.get("photos", [])
	parking = data.get("parking", {})
	scenic = data.get("scenic", {})
	relaxed = bool(data.get("relaxed", false))
