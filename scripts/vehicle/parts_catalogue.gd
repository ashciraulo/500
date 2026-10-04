class_name PartsCatalogue
extends RefCounted
## Every part in data/parts/, loaded on first use.

const DIR := "res://data/parts/"
const SLOTS: Array[StringName] = [
	&"engine", &"intake", &"exhaust", &"gearbox", &"suspension",
	&"tyres", &"wheels", &"brakes", &"weight",
]

static var _parts := {}


static func all() -> Array[CarPart]:
	_ensure_loaded()
	var result: Array[CarPart] = []
	for part in _parts.values():
		result.append(part)
	return result


static func get_part(id: StringName) -> CarPart:
	_ensure_loaded()
	return _parts.get(id)


## Parts for one slot, cheapest first (stock first).
static func for_slot(slot: StringName) -> Array[CarPart]:
	var result: Array[CarPart] = []
	for part in all():
		if part.slot == slot:
			result.append(part)
	result.sort_custom(func(a: CarPart, b: CarPart) -> bool: return a.price < b.price)
	return result


static func _ensure_loaded() -> void:
	if not _parts.is_empty():
		return
	for file in DirAccess.get_files_at(DIR):
		# Exported builds list "x.tres.remap"; load() still wants "x.tres".
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var part := load(DIR + file) as CarPart
		if part:
			_parts[part.id] = part
