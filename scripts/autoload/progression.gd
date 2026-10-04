extends Node
## Career progress (autoload: Progression): tiers, their challenges, and the
## counters challenges are measured against. Tiers live in
## data/progression/tiers.json. All challenges in a tier must be done to move
## up; finishing a tier unlocks the next one and possibly a new car.
##
## Stats a challenge can use:
##   counters kept here (bump with `add_stat`): deliveries, night_deliveries,
##     rain_deliveries, storm_deliveries, fragile_perfect, trials_completed,
##     trials_medalled, trials_silver, trials_gold
##   read live: earned (Wallet.total_earned), km_driven (car odometer),
##     discoveries (Discoveries count), upgrades_fitted (non-stock parts on the car)

signal stat_changed(stat: String, value: float)
signal challenge_completed(tier_index: int, challenge: Dictionary)
signal tier_completed(tier_index: int, tier: Dictionary)

const TIERS_PATH := "res://data/progression/tiers.json"

var tiers: Array = []
var tier_index := 0
var unlocked_cars: PackedStringArray = ["pop_12"]

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
			var car := _car()
			return car.odometer_km if car else 0.0
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
		if tier.get("unlocks_car", "") != "" and not unlocked_cars.has(tier.unlocks_car):
			unlocked_cars.append(tier.unlocks_car)
		tier_index += 1
		tier_completed.emit(finished, tier)


func save_state() -> Dictionary:
	return {
		"tier_index": tier_index,
		"stats": _stats,
		"completed": _completed,
		"unlocked_cars": Array(unlocked_cars),
	}


func load_state(data: Dictionary) -> void:
	tier_index = int(data.get("tier_index", 0))
	_stats = data.get("stats", {})
	_completed = data.get("completed", {})
	unlocked_cars = PackedStringArray(data.get("unlocked_cars", ["pop_12"]))


func _car() -> CarController:
	return get_tree().get_first_node_in_group(&"player_car") as CarController
