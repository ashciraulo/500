extends Node
## Career progress (autoload: Progression): tiers, their challenges, and the
## counters challenges are measured against. Tiers live in
## data/progression/tiers.json. All challenges in a tier must be done to move
## up; reaching a tier lets you buy that tier's cars at a dealer (the `tier`
## of each car in data/cars/cars.json).
##
## Stats a challenge can use:
##   counters kept here (bump with `add_stat`): deliveries, night_deliveries,
##     rain_deliveries, storm_deliveries, fragile_perfect, trials_completed,
##     trials_medalled, trials_silver, trials_gold, parts_bought, cars_bought,
##     washes, resprays, litres_bought
##   read live: earned (Wallet.total_earned), km_driven (every car's odometer),
##     km_tier_car (most km in one car of the current tier), discoveries
##     (Discoveries count), upgrades_fitted (non-stock parts on the car you're
##     driving), suburbs_delivered (different suburbs you've delivered to),
##     cars_owned

signal stat_changed(stat: String, value: float)
signal challenge_completed(tier_index: int, challenge: Dictionary)
signal tier_completed(tier_index: int, tier: Dictionary)

const TIERS_PATH := "res://data/progression/tiers.json"
## Every stat a challenge may name (the smoke test checks tiers.json against it).
const KNOWN_STATS := [
	"deliveries", "night_deliveries", "rain_deliveries", "storm_deliveries", "fragile_perfect",
	"trials_completed", "trials_medalled", "trials_silver", "trials_gold", "parts_bought",
	"cars_bought", "washes", "resprays", "litres_bought", "earned", "km_driven", "km_tier_car",
	"discoveries", "upgrades_fitted", "suburbs_delivered", "cars_owned",
]

var tiers: Array = []
var tier_index := 0
## Suburbs you've delivered to.
var suburbs: PackedStringArray = []

var _stats := {}
var _completed := {}  # challenge id -> day completed
var _check_timer := 0.0


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIERS_PATH))
	if parsed is Dictionary:
		tiers = parsed.get("tiers", [])
	Wallet.changed.connect(func(_b: int, _d: int) -> void: check())
	Discoveries.discovered.connect(func(_id: String) -> void: check())
	SaveGame.register("progression", self)


func _process(delta: float) -> void:
	# Distance and fitted parts change continuously; check now and then.
	_check_timer += delta
	if _check_timer > 2.0:
		_check_timer = 0.0
		check()


func current_tier() -> Dictionary:
	return tiers[tier_index] if tier_index < tiers.size() else {}


func pay_multiplier() -> float:
	if tiers.is_empty():
		return 1.0
	# Past the last tier, keep the last tier's pay.
	return float(tiers[mini(tier_index, tiers.size() - 1)].get("pay_multiplier", 1.0))


func add_stat(stat: String, amount := 1.0) -> void:
	_stats[stat] = _stats.get(stat, 0.0) + amount
	stat_changed.emit(stat, _stats[stat])
	check()


func get_stat(stat: String) -> float:
	match stat:
		"earned":
			return Wallet.total_earned
		"discoveries":
			return Discoveries.all().size()
		"km_driven":
			return Garage.lifetime_km(_car())
		"km_tier_car":
			return Garage.km_in_tier(mini(tier_index, tiers.size() - 1), _car())
		"suburbs_delivered":
			return suburbs.size()
		"cars_owned":
			return Garage.owned_cars.size()
		"upgrades_fitted":
			var car := _car()
			return car.parts.size() if car else 0.0
	return _stats.get(stat, 0.0)


func is_done(challenge: Dictionary) -> bool:
	return _completed.has(challenge.id)


## 0..1 progress towards a challenge.
func progress(challenge: Dictionary) -> float:
	if is_done(challenge):
		return 1.0
	return clampf(get_stat(challenge.stat) / float(challenge.target), 0.0, 1.0)


## Mark finished challenges and advance the tier when all are done.
func check() -> void:
	var tier := current_tier()
	if tier.is_empty():
		return
	var all_done := true
	for challenge in tier.challenges:
		if not is_done(challenge) and get_stat(challenge.stat) >= float(challenge.target):
			_completed[challenge.id] = GameClock.day
			challenge_completed.emit(tier_index, challenge)
		all_done = all_done and is_done(challenge)
	if all_done:
		var finished := tier_index
		tier_index += 1
		tier_completed.emit(finished, tier)


## Note a delivery to a suburb (for "deliver in N suburbs" challenges).
func note_suburb(suburb: String) -> void:
	if suburb != "" and not suburbs.has(suburb):
		suburbs.append(suburb)
		check()


## Cars a dealer will now sell you (by tier reached).
func cars_unlocked_at(index: int) -> Array:
	return CarCatalogue.for_sale().filter(func(c: Dictionary) -> bool: return int(c.tier) == index)


func save_state() -> Dictionary:
	return {
		"tier_index": tier_index,
		"stats": _stats,
		"completed": _completed,
		"suburbs": Array(suburbs),
	}


func load_state(data: Dictionary) -> void:
	tier_index = int(data.get("tier_index", 0))
	_stats = data.get("stats", {})
	_completed = data.get("completed", {})
	suburbs = PackedStringArray(data.get("suburbs", []))


func _car() -> CarController:
	return get_tree().get_first_node_in_group(&"player_car") as CarController
