class_name PartsCatalogue
extends RefCounted
## Every part in data/parts/, loaded on first use.

const DIR := "res://data/parts/"
const SLOTS: Array[StringName] = [
	&"engine", &"intake", &"exhaust", &"gearbox", &"suspension",
	&"tyres", &"wheels", &"brakes", &"weight", &"roof", &"lights",
	&"rear_rack", &"bumpers", &"towbar", &"mudflaps",
	&"steering_wheel", &"gear_knob", &"seat_covers",
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


## Slots an electric car can't take parts in.
const COMBUSTION_SLOTS: Array[StringName] = [&"engine", &"intake", &"exhaust", &"gearbox"]


## True when a part can go on a car.
static func fits(part: CarPart, car_id: String) -> bool:
	if not part.fits.is_empty():
		return part.fits.has(car_id)
	var car := CarCatalogue.get_car(car_id)
	if not part.ladders.is_empty() and not part.ladders.has(String(car.get("ladder", "modern"))):
		return false
	# Open-topped cars (the 500C, the Jolly) have nothing to bolt a rack to.
	if part.slot == &"roof" and car.get("no_roof_rack", false):
		return part.is_stock()
	if car.get("electric", false) and COMBUSTION_SLOTS.has(part.slot):
		return part.is_stock()
	return true


## Parts for one slot that fit a car, cheapest first.
static func for_car(slot: StringName, car_id: String) -> Array[CarPart]:
	var result: Array[CarPart] = []
	for part in for_slot(slot):
		if fits(part, car_id):
			result.append(part)
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
