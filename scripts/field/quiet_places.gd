class_name QuietPlaces
extends Node
## Quiet places: the map's hidden birding spots (habitats.json `hidden`,
## e.g. the Herdsman Lake reedbeds) and hidden fishing spots
## (fishing_spots.json `hidden`). Nothing marks them; walk into one and it
## goes in the journal (discovery places/<map poi id>, which also shows it on
## the map), with a few birds you won't see anywhere else.

## How close you need to get to a quiet birding place.
const FIND := 60.0
const SOUND := "field/quiet_place"

var _check := 0.0
var _birds: FieldBirds


func setup(birds: FieldBirds) -> void:
	_birds = birds


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _birds == null:
		return
	var p := _birds.player_position()
	if p != Vector3.INF:
		find_near(p)


## Finds any quiet place close to p. Returns the names found.
func find_near(p: Vector3) -> Array[String]:
	var found: Array[String] = []
	for h: Dictionary in FieldJournal.quiet_places():
		var c := FieldJournal.habitat_centre(h)
		if Vector2(p.x - c.x, p.z - c.z).length() < FIND and Discoveries.discover(FieldJournal.place_key(h)):
			found.append(String(h.name))
			# The card plays SOUND (or the new-species cue until it's recorded).
			Notices.post("%s. Nobody comes here. It's in the journal." % h.name, "quiet")
	return found
