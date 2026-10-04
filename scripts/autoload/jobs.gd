extends Node
## The job board (autoload: Jobs): deliveries and time trials between JobSites.
##
## A handful of offers refresh every few in-game hours. Taking one puts a
## beacon in the world; the HUD shows where to go. Deliveries pay by distance,
## with a bonus for being quick and a penalty for knocking fragile cargo about.
## Time trials run through checkpoints against bronze/silver/gold times; your
## best time per trial is kept, and medals count towards tier challenges.

signal offers_changed
signal job_started(job: Dictionary)
signal job_stage_changed(job: Dictionary)
## `pay` is what was earned (0 for a trial that missed every medal).
signal job_completed(job: Dictionary, pay: int, summary: String)
signal job_abandoned(job: Dictionary)
signal place_discovered(site: JobSite)

const DELIVERY_OFFERS := 4
const TRIAL_OFFERS := 1
## In-game hours between board refreshes.
const REFRESH_HOURS := 3.0
## Straight-line distance is shorter than the road; pay and par times allow for it.
const ROAD_FACTOR := 1.35
## Deliveries count only once the car has pulled up (km/h).
const STOP_SPEED_KMH := 15.0
const DISCOVER_RADIUS := 30.0
const MEDALS := ["gold", "silver", "bronze"]
## Average speeds (km/h, over road distance) for each medal.
const MEDAL_SPEEDS := {"gold": 62.0, "silver": 52.0, "bronze": 42.0}
const MEDAL_REWARDS := {"gold": 220, "silver": 120, "bronze": 60}

const CARGO := [
	["a crate of Margaret River wine", true],
	["flowers for a wedding", true],
	["a birthday cake", true],
	["a box of old vinyl records", false],
	["spare parts for a Vespa", false],
	["a second-hand surfboard", false],
	["a tray of sourdough loaves", false],
	["a box of vintage glassware", true],
	["a stack of zines for the record shop", false],
	["a sleepy cat in a carrier", true],
	["a crate of mangoes from Carnarvon", false],
	["a rolled-up Persian rug", false],
	["a ceramic lamp", true],
	["coffee beans for a café", false],
	["a guitar amp", false],
	["somebody's forgotten esky", false],
]

var offers: Array = []
var active := {}
## Trial id -> {"best": seconds, "medal": "gold"/"silver"/"bronze"/""}.
var trial_records := {}

var _hours_until_refresh := 0.0
var _beacon: Beacon
var _rng := RandomNumberGenerator.new()
var _car: CarController
var _discover_timer := 0.0
var _next_id := 1


func _ready() -> void:
	_rng.randomize()
	SaveGame.register("jobs", self)


func _process(delta: float) -> void:
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		if _car == null:
			return
		_car.impact.connect(_on_car_impact)
		_place_beacon()
	if not GameClock.locked:
		_hours_until_refresh -= delta * 24.0 / GameClock.seconds_per_day
	if _hours_until_refresh <= 0.0 or (offers.is_empty() and not sites().is_empty()):
		refresh_offers()

	_discover_timer += delta
	if _discover_timer > 0.5:
		_discover_timer = 0.0
		_check_discoveries()

	if not active.is_empty():
		active.elapsed = active.get("elapsed", 0.0) + delta
		_update_active()


func sites() -> Array[JobSite]:
	var result: Array[JobSite] = []
	for node in get_tree().get_nodes_in_group(&"job_sites"):
		result.append(node)
	return result


func site(id: String) -> JobSite:
	for s in sites():
		if s.site_id == id:
			return s
	return null


func refresh_offers() -> void:
	_hours_until_refresh = REFRESH_HOURS
	var all_sites := sites()
	if all_sites.size() < 2:
		return
	offers.clear()
	for i in DELIVERY_OFFERS:
		var job := _make_delivery(all_sites)
		if not job.is_empty():
			offers.append(job)
	for i in TRIAL_OFFERS:
		var trial := _make_trial(all_sites)
		if not trial.is_empty():
			offers.append(trial)
	offers_changed.emit()


func accept(job: Dictionary) -> void:
	if not active.is_empty():
		abandon()
	offers.erase(job)
	active = job
	active.elapsed = 0.0
	active.damage = 0.0
	active.stage = "to_pickup" if job.type == "delivery" else "to_start"
	active.checkpoint = 0
	_place_beacon()
	offers_changed.emit()
	job_started.emit(active)


func abandon() -> void:
	if active.is_empty():
		return
	var job := active
	active = {}
	_place_beacon()
	job_abandoned.emit(job)


## Where the player should drive next, or null.
func target_site() -> JobSite:
	if active.is_empty():
		return null
	match active.stage:
		"to_pickup":
			return site(active.pickup)
		"to_dropoff":
			return site(active.dropoff)
		"to_start", "racing":
			return site(active.route[active.checkpoint])
	return null


## One line for the HUD describing what to do next.
func objective_text() -> String:
	if active.is_empty():
		return ""
	var target := target_site()
	var where := target.label() if target else "?"
	var distance := ""
	if target and _car:
		distance = "  %.1f km" % (_car.global_position.distance_to(target.global_position) / 1000.0)
	match active.stage:
		"to_pickup":
			return "Pick up %s at %s%s" % [active.cargo, where, distance]
		"to_dropoff":
			var damage := "  (cargo %d%% damaged)" % roundi(active.damage) if active.damage > 0.5 else ""
			return "Deliver to %s%s  %s%s" % [where, distance, _clock(active.elapsed), damage]
		"to_start":
			return "Drive to the start of %s at %s%s" % [active.title, where, distance]
		"racing":
			return "Checkpoint %d/%d  %s   gold %s" % [
				active.checkpoint, active.route.size() - 1, _clock(active.elapsed), _clock(active.medal_times.gold)]
	return ""


func describe(job: Dictionary) -> String:
	if job.type == "delivery":
		var fragile := " Fragile." if job.fragile else ""
		return "%s: %s to %s. %.1f km, $%d.%s" % [
			site(job.pickup).label() if site(job.pickup) else job.pickup, job.cargo,
			site(job.dropoff).label() if site(job.dropoff) else job.dropoff, job.km, job.pay, fragile]
	var record: Dictionary = trial_records.get(job.trial_id, {})
	var best := "  Best %s (%s)" % [_clock(record.best), record.medal] if record.has("best") else ""
	return "%s: %d checkpoints, %.1f km. Gold %s, silver %s, bronze %s.%s" % [
		job.title, job.route.size() - 1, job.km, _clock(job.medal_times.gold),
		_clock(job.medal_times.silver), _clock(job.medal_times.bronze), best]


func _update_active() -> void:
	var target := target_site()
	if target == null or _car == null:
		return
	if not _beacon.contains(_car.global_position):
		return
	match active.stage:
		"to_pickup":
			if _car.speed_kmh() < STOP_SPEED_KMH:
				active.stage = "to_dropoff"
				active.elapsed = 0.0
				_stage_changed()
		"to_dropoff":
			if _car.speed_kmh() < STOP_SPEED_KMH:
				_finish_delivery()
		"to_start":
			active.stage = "racing"
			active.checkpoint = 1
			active.elapsed = 0.0
			_stage_changed()
		"racing":
			active.checkpoint += 1
			if active.checkpoint >= active.route.size():
				_finish_trial()
			else:
				_stage_changed()


func _stage_changed() -> void:
	_place_beacon()
	job_stage_changed.emit(active)


func _finish_delivery() -> void:
	var job := active
	active = {}
	_place_beacon()
	var pay := float(job.pay) * (1.0 - clampf(job.damage, 0.0, 100.0) / 100.0)
	var quick: bool = job.elapsed <= job.par_seconds
	var bonus := roundi(job.pay * 0.25) if quick else 0
	var total := roundi(pay) + bonus
	Wallet.earn(total, "delivery")
	Progression.add_stat("deliveries")
	if GameClock.is_night():
		Progression.add_stat("night_deliveries")
	if Weather.state != Weather.State.CLEAR:
		Progression.add_stat("rain_deliveries")
	if Weather.state == Weather.State.STORM:
		Progression.add_stat("storm_deliveries")
	if job.fragile and job.damage < 0.5:
		Progression.add_stat("fragile_perfect")
	var summary := "Delivered %s in %s. $%d" % [job.cargo, _clock(job.elapsed), total]
	if bonus > 0:
		summary += " (includes $%d for being quick)" % bonus
	if job.damage >= 0.5:
		summary += ", %d%% off for damage" % roundi(job.damage)
	job_completed.emit(job, total, summary + ".")


func _finish_trial() -> void:
	var job := active
	active = {}
	_place_beacon()
	var time: float = job.elapsed
	var medal := ""
	for m in MEDALS:
		if time <= job.medal_times[m]:
			medal = m
			break
	var record: Dictionary = trial_records.get(job.trial_id, {"medal": ""})
	var old_rank := MEDALS.find(record.medal) if record.medal != "" else MEDALS.size()
	var new_rank := MEDALS.find(medal) if medal != "" else MEDALS.size()
	var pay := 0
	Progression.add_stat("trials_completed")
	if new_rank < old_rank:
		# Reward and count each medal level once per trial, so improving
		# bronze to gold pays the difference rather than farming one trial.
		pay = MEDAL_REWARDS[medal] - (MEDAL_REWARDS[record.medal] if record.medal != "" else 0)
		pay = roundi(pay * Progression.pay_multiplier())
		if old_rank == MEDALS.size():
			Progression.add_stat("trials_medalled")
		if new_rank <= 1 and old_rank > 1:
			Progression.add_stat("trials_silver")
		if new_rank == 0:
			Progression.add_stat("trials_gold")
		record.medal = medal
	if not record.has("best") or time < record.best:
		record.best = time
	trial_records[job.trial_id] = record
	if pay > 0:
		Wallet.earn(pay, "time trial")
	var summary := "%s in %s." % [job.title, _clock(time)]
	summary += " %s medal, $%d." % [medal.capitalize(), pay] if medal != "" else " No medal this time."
	job_completed.emit(job, pay, summary)


func _make_delivery(all_sites: Array[JobSite]) -> Dictionary:
	var pickups := all_sites.filter(func(s: JobSite) -> bool: return s.kinds.has("pickup"))
	var dropoffs := all_sites.filter(func(s: JobSite) -> bool: return s.kinds.has("dropoff"))
	if pickups.is_empty() or dropoffs.size() < 2:
		return {}
	var from: JobSite = pickups[_rng.randi() % pickups.size()]
	var to: JobSite = dropoffs[_rng.randi() % dropoffs.size()]
	var tries := 0
	while to == from and tries < 10:
		to = dropoffs[_rng.randi() % dropoffs.size()]
		tries += 1
	if to == from:
		return {}
	var cargo: Array = CARGO[_rng.randi() % CARGO.size()]
	var km := from.global_position.distance_to(to.global_position) * ROAD_FACTOR / 1000.0
	var pay := (18.0 + km * 9.0) * Progression.pay_multiplier() * (1.3 if cargo[1] else 1.0)
	return {
		"id": _new_id(), "type": "delivery",
		"title": "Deliver %s" % cargo[0], "cargo": cargo[0], "fragile": cargo[1],
		"pickup": from.site_id, "dropoff": to.site_id,
		"km": km, "pay": roundi(pay / 5.0) * 5,
		# Par: an easy 40 km/h average plus a minute to load up.
		"par_seconds": km / 40.0 * 3600.0 + 60.0,
	}


func _make_trial(all_sites: Array[JobSite]) -> Dictionary:
	var pool := all_sites.filter(func(s: JobSite) -> bool: return s.kinds.has("trial"))
	if pool.size() < 3:
		return {}
	pool.shuffle()
	var count := mini(pool.size(), _rng.randi_range(4, 6))
	var route: Array = []
	var km := 0.0
	for i in count:
		route.append(pool[i].site_id)
		if i > 0:
			km += pool[i - 1].global_position.distance_to(pool[i].global_position) * ROAD_FACTOR / 1000.0
	var times := {}
	for m in MEDALS:
		times[m] = km / MEDAL_SPEEDS[m] * 3600.0
	return {
		"id": _new_id(), "type": "trial",
		"trial_id": "-".join(route),
		"title": "The %s run" % site(route[0]).display_name,
		"route": route, "km": km, "medal_times": times,
	}


func _place_beacon() -> void:
	var target := target_site()
	if target == null or _car == null:
		if _beacon:
			_beacon.queue_free()
			_beacon = null
		return
	if _beacon == null:
		_beacon = Beacon.new()
		_beacon.color = Color(0.4, 0.9, 1.0) if active.type == "trial" else Color(1.0, 0.8, 0.3)
		_car.get_parent().add_child(_beacon)
	_beacon.global_position = target.global_position


func _check_discoveries() -> void:
	if _car == null:
		return
	for s in sites():
		if _car.global_position.distance_to(s.global_position) < DISCOVER_RADIUS:
			if Discoveries.discover("place/" + s.site_id):
				place_discovered.emit(s)


func _on_car_impact(strength: float) -> void:
	if active.is_empty() or active.type != "delivery" or active.stage != "to_dropoff":
		return
	if active.fragile and strength > 2.0:
		active.damage = minf(100.0, active.damage + strength * 4.0)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func save_state() -> Dictionary:
	return {
		"offers": offers, "active": active, "trial_records": trial_records,
		"hours_until_refresh": _hours_until_refresh, "next_id": _next_id,
	}


func load_state(data: Dictionary) -> void:
	offers = data.get("offers", [])
	active = data.get("active", {})
	trial_records = data.get("trial_records", {})
	_hours_until_refresh = float(data.get("hours_until_refresh", 0.0))
	_next_id = int(data.get("next_id", 1))
	_place_beacon()
	offers_changed.emit()


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
