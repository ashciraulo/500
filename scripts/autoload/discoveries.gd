extends Node
## Places, secrets and oddities the player has found (autoload: Discoveries).
## Anything can mark an id as discovered; ids are free-form strings such as
## "place/kings_park" or "mystery/shed_key".

signal discovered(id: String)

var _found := {}


func _ready() -> void:
	SaveGame.register("discoveries", self)


## Returns true the first time an id is discovered.
func discover(id: String) -> bool:
	if _found.has(id):
		return false
	_found[id] = GameClock.day
	discovered.emit(id)
	return true


func has(id: String) -> bool:
	return _found.has(id)


func all() -> PackedStringArray:
	return PackedStringArray(_found.keys())


func save_state() -> Dictionary:
	return {"found": _found}


func load_state(data: Dictionary) -> void:
	_found = data.get("found", {})
