class_name CarCatalogue
extends RefCounted
## Every car in the game, from data/cars/cars.json, loaded on first use.
## Each entry: id, name, years, ladder (modern / electric / classic), tier,
## unlock (starter / tier / barn_find / secret), price, power_kw, blurb and a
## `spec` of CarController values. See that file's comment.

const PATH := "res://data/cars/cars.json"
const STARTER := "pop_12"

static var _cars: Array = []
static var _by_id := {}


static func all() -> Array:
	_ensure_loaded()
	return _cars


static func get_car(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})


static func ladder(name: String) -> Array:
	return all().filter(func(c: Dictionary) -> bool: return c.ladder == name)


## Cars a dealer sells (bought with money once their tier is reached).
static func for_sale() -> Array:
	return all().filter(func(c: Dictionary) -> bool: return c.unlock == "tier")


## True when a car has its own numbers yet. Classics come with the barn
## finds and can't be driven until then.
static func is_drivable(car: Dictionary) -> bool:
	return car.id == STARTER or not car.get("spec", {}).is_empty()


static func _ensure_loaded() -> void:
	if not _cars.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_cars = parsed.get("cars", [])
	for car in _cars:
		_by_id[car.id] = car
