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
##     washes, resprays, litres_bought, services_done
##   read live: earned (Wallet.total_earned), km_driven (every car's odometer),
##     km_tier_car (most km in one car of the current tier), discoveries
##     (Discoveries count), upgrades_fitted (non-stock parts on the car you're
##     driving), suburbs_delivered (different suburbs you've delivered to),
##     cars_owned, badges (hidden 500 badges found)
##   from the field journal (FieldJournal.stat(name), when it's there):
##     species_seen, species_photographed, prints_sold, fish_caught, fish_species

signal stat_changed(stat: String, value: float)
signal challenge_completed(tier_index: int, challenge: Dictionary)
signal tier_completed(tier_index: int, tier: Dictionary)
## A cosmetic reward (trinket, livery...) was earned. `reward` has id, title,
## kind and `why` (what earned it, for the toast).
signal reward_unlocked(reward: Dictionary)

const TIERS_PATH := "res://data/progression/tiers.json"
const MILEAGE_PATH := "res://data/progression/mileage_rewards.json"
const COSMETICS_PATH := "res://data/progression/cosmetics.json"
## Every stat a challenge may name (the smoke test checks tiers.json against it).
const KNOWN_STATS := [
	"deliveries", "night_deliveries", "rain_deliveries", "storm_deliveries", "fragile_perfect",
	"trials_completed", "trials_medalled", "trials_silver", "trials_gold", "parts_bought",
	"cars_bought", "washes", "resprays", "litres_bought", "earned", "km_driven", "km_tier_car",
	"discoveries", "upgrades_fitted", "suburbs_delivered", "cars_owned", "badges",
	"barn_finds", "restoration_stages", "classics_restored", "photos_taken", "photo_spots",
	"parking_done", "parking_gold", "scenic_drives", "meets_attended", "lifts_given",
	"trains_raced", "trains_beaten", "parts_found", "services_done",
	"species_seen", "species_photographed", "prints_sold", "fish_caught", "fish_species",
]
## Stats the field journal keeps (birds and fish); read live from it.
const JOURNAL_STATS := ["species_seen", "species_photographed", "prints_sold", "fish_caught", "fish_species"]

var tiers: Array = []
var tier_index := 0
## Suburbs you've delivered to.
var suburbs: PackedStringArray = []
var mileage_rewards: Array = []
## How each cosmetic looks (data/progression/cosmetics.json), by id.
var cosmetics := {}
## Ids of cosmetic rewards earned (mileage, meets...).
var rewards: PackedStringArray = []

var _stats := {}
var _completed := {}  # challenge id -> day completed
var _check_timer := 0.0


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIERS_PATH))
	if parsed is Dictionary:
		tiers = parsed.get("tiers", [])
	parsed = JSON.parse_string(FileAccess.get_file_as_string(MILEAGE_PATH))
	if parsed is Dictionary:
		mileage_rewards = parsed.get("rewards", [])
	parsed = JSON.parse_string(FileAccess.get_file_as_string(COSMETICS_PATH))
	if parsed is Dictionary:
		cosmetics = parsed.get("items", {})
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
			# Places only: badges, barn finds and photo spots have their own stats.
			return Array(Discoveries.all()).filter(func(id: String) -> bool:
				return not (id.begins_with("badge/") or id.begins_with("barn/") or id.begins_with("photo/"))).size()
		"km_driven":
			return Garage.lifetime_km(_car())
		"km_tier_car":
			return Garage.km_in_tier(mini(tier_index, tiers.size() - 1), _car())
		"suburbs_delivered":
			return suburbs.size()
		"cars_owned":
			return Garage.owned_cars.size()
		"badges":
			return Collectible.found_count()
		"upgrades_fitted":
			var car := _car()
			return car.parts.size() if car else 0.0
	if stat in JOURNAL_STATS:
		var journal := get_node_or_null(^"/root/FieldJournal")
		if journal and journal.has_method("stat"):
			return float(journal.stat(stat))
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
	_check_mileage()
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


func _check_mileage() -> void:
	var km := get_stat("km_driven")
	for reward in mileage_rewards:
		if km >= float(reward.km):
			grant_reward(reward.id, "%d km driven" % int(reward.km))


## Give a cosmetic reward (once). `why` says what earned it.
func grant_reward(id: String, why := "") -> void:
	if rewards.has(id):
		return
	rewards.append(id)
	var reward := cosmetic(id)
	reward["why"] = why
	reward_unlocked.emit(reward)


## Everything known about a cosmetic: its look from cosmetics.json plus its
## title (from the mileage list when it isn't given there).
func cosmetic(id: String) -> Dictionary:
	var item: Dictionary = cosmetics.get(id, {}).duplicate()
	item["id"] = id
	for reward in mileage_rewards:
		if reward.id == id:
			item.merge(reward)
	if not item.has("title"):
		item["title"] = id.capitalize()
	return item


## Cosmetics earned so far of one kind ("trinket", "livery", "garage").
func earned_cosmetics(kind: String) -> Array:
	var out := []
	for id in rewards:
		var item := cosmetic(id)
		if item.get("kind", "") == kind:
			out.append(item)
	return out


## Rewards for a number of nights at the car meet.
func check_meet_rewards(visits: int) -> void:
	for id: String in cosmetics:
		var need := int(cosmetics[id].get("meet", 0))
		if need > 0 and visits >= need:
			grant_reward(id, "%d night%s at the meet" % [need, "" if need == 1 else "s"])


## The next mileage reward still to earn, or {}.
func next_mileage_reward() -> Dictionary:
	for reward in mileage_rewards:
		if not rewards.has(reward.id):
			return reward
	return {}


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
		"rewards": Array(rewards),
	}


func load_state(data: Dictionary) -> void:
	tier_index = int(data.get("tier_index", 0))
	_stats = data.get("stats", {})
	_completed = data.get("completed", {})
	suburbs = PackedStringArray(data.get("suburbs", []))
	rewards = PackedStringArray(data.get("rewards", []))


func _car() -> CarController:
	return get_tree().get_first_node_in_group(&"player_car") as CarController
