class_name DevTools
extends RefCounted
## What the dev menu (DevMenu, F4 in dev mode) changes in the game: cars,
## parts, field gear, money, the career tier, jobs and the story. Each returns
## a short line saying what it did, for the menu to show.
##
## These change the game as it is, so they go into the save like anything
## else (the menu's Saves tab can keep a run out of the save, and keep
## snapshots to go back to). Moving the car or the player is DevMode's job,
## done in the physics step.

var _dev: DevMode


func _init(dev: DevMode) -> void:
	_dev = dev


# --- cars --------------------------------------------------------------------

## Makes a car yours and puts you in it. Classics come restored and roadworthy.
func give_car(id: String) -> String:
	var car := _dev.car()
	var info := CarCatalogue.get_car(id)
	if car == null or info.is_empty():
		return "No such car."
	_own_car(id, true)
	if not Garage.switch_car(id, car):
		return "The %s can't be driven yet." % info.name
	car.apply_paint_refresh()
	return "You're in the %s." % info.name


## A classic as a barn-find wreck on the restoration bench (not driveable).
func give_wreck(id: String) -> String:
	var info := CarCatalogue.get_car(id)
	if info.get("ladder", "") != "classic":
		return "Only classics come as wrecks."
	if Classics.is_found(id):
		return "The %s is already yours." % info.name
	if not Classics.find_wreck(id):
		Classics.projects[id] = {"stages": [], "finish": ""}
		Garage.add_car(id)
	return "The %s is on the restoration bench." % info.name


## Every car in the game, classics restored.
func give_all_cars() -> String:
	for info: Dictionary in CarCatalogue.all():
		_own_car(String(info.id), true)
	return "Every car is yours (%d)." % Garage.owned_cars.size()


func _own_car(id: String, restored: bool) -> void:
	if CarCatalogue.get_car(id).get("ladder", "") == "classic" and restored:
		var done: Array = []
		for s: Dictionary in Classics.stages():
			done.append(s.id)
		var project: Dictionary = Classics.projects.get(id, {})
		Classics.projects[id] = {"stages": done,
			"finish": project.get("finish", "") if project.get("finish", "") != "" else "original"}
	Garage.add_car(id)


# --- parts -------------------------------------------------------------------

## Owns a part for the car you're in and fits it, with no time or money spent.
func fit_part(part: CarPart) -> String:
	var car := _dev.car()
	if car == null or not PartsCatalogue.fits(part, car.car_id):
		return "The %s doesn't fit this car." % part.display_name
	_own_part(part, car.car_id)
	car.install_part(part)
	if car.wear.has(String(part.slot)):
		car.wear[String(part.slot)] = 0.0
	Garage.parts_owned_changed.emit()
	return "Fitted the %s." % part.display_name


## Every part that fits the car you're in, on its parts shelf.
func own_all_parts() -> String:
	var car := _dev.car()
	if car == null:
		return ""
	var n := 0
	for part in PartsCatalogue.all():
		if not part.is_stock() and PartsCatalogue.fits(part, car.car_id):
			_own_part(part, car.car_id)
			n += 1
	Garage.parts_owned_changed.emit()
	return "%d parts on the shelf for this car." % n


## Every part for every car you own.
func own_parts_every_car() -> String:
	var n := 0
	for id in Garage.owned_cars:
		for part in PartsCatalogue.all():
			if not part.is_stock() and PartsCatalogue.fits(part, id):
				_own_part(part, id)
				n += 1
	Garage.parts_owned_changed.emit()
	return "%d parts for your %d cars." % [n, Garage.owned_cars.size()]


## Back to stock parts all round (the parts stay yours).
func all_stock() -> String:
	var car := _dev.car()
	if car == null:
		return ""
	for slot in car.parts.keys():
		car.remove_part(slot)
	return "Back to stock parts."


func _own_part(part: CarPart, car_id: String) -> void:
	if part.found_only:
		Discoveries.discover("part/" + String(part.id))
	var key := "%s/%s" % [car_id, part.id]
	if not Garage.owned.has(key):
		Garage.owned.append(key)


## Fuel, tyres, brakes and oil as new, and a clean car.
func fix_car() -> String:
	var car := _dev.car()
	if car == null:
		return ""
	car.fuel_litres = car.tank_litres
	for item: String in car.wear:
		car.wear[item] = 0.0
	car.dirt = 0.0
	return "Full tank, fresh tyres, brakes and oil, and a wash."


# --- field gear and the journal ----------------------------------------------

## The best binoculars, camera, lens, film, rod and esky, a crab net, and the
## binoculars off their hook at home.
func best_field_gear() -> String:
	FieldJournal.binoculars = FieldJournal.BINOCULARS.size() - 1
	FieldJournal.camera = FieldJournal.CAMERAS.size() - 1
	FieldJournal.lens = FieldJournal.LENSES.size() - 1
	FieldJournal.film = FieldJournal.FILMS.size() - 1
	FieldJournal.rod = FieldJournal.RODS.size() - 1
	FieldJournal.esky_level = FieldJournal.ESKIES.size() - 1
	FieldJournal.has_crab_net = true
	Discoveries.discover(HomeField.TAKEN)
	FieldJournal.film_changed.emit(FieldJournal.film_left(), FieldJournal.roll_size())
	FieldJournal.gear_changed.emit()
	return "The best field gear, and the binoculars off the hook."


## Every real bird (not the wrong ones) seen and in the journal.
func see_all_birds() -> String:
	var n := 0
	for id: String in FieldJournal.bird_order:
		if not FieldJournal.birds[id].get("wrong", false) and FieldJournal.see(id, "Dev mode"):
			n += 1
	return "%d new birds in the journal." % n


# --- money -------------------------------------------------------------------

## Money that isn't counted as earnings (so it doesn't finish challenges).
func add_money(amount: int) -> String:
	Wallet.balance = maxi(Wallet.balance + amount, 0)
	Wallet.changed.emit(Wallet.balance, amount)
	return "$%s in the bank." % UiStyle.number(Wallet.balance)


# --- career and story --------------------------------------------------------

## Straight to a tier (0-based). The story's act follows it.
func set_tier(index: int) -> String:
	Progression.tier_index = clampi(index, 0, Progression.tiers.size())
	Story.act_override = 0
	Story._check_act()
	return "Tier %d, act %d." % [mini(Progression.tier_index + 1, Progression.tiers.size()), Story.act()]


## Every challenge of this tier done, which moves you up a tier the normal way
## (its rewards, the next act's card and calls).
func finish_tier() -> String:
	var tier := Progression.current_tier()
	if tier.is_empty():
		return "That's the last tier done."
	for challenge: Dictionary in tier.challenges:
		if not Progression.is_done(challenge):
			Progression._completed[challenge.id] = GameClock.day
			Progression.challenge_completed.emit(Progression.tier_index, challenge)
	Progression.check()
	return "Tier finished. Now tier %d, act %d." % [mini(Progression.tier_index + 1, Progression.tiers.size()), Story.act()]


## The job you're on, done as if you'd just pulled up (a trial gets gold).
func finish_job() -> String:
	if Jobs.active.is_empty():
		return "You're not on a job."
	if Jobs.active.type == "delivery":
		Jobs.active.stage = "to_dropoff"
		Jobs._finish_delivery()
	else:
		Jobs.active.elapsed = 0.0
		Jobs._finish_trial()
	return "Job done."


func new_offers() -> String:
	Jobs.refresh_offers()
	return "New jobs on the board."


## A story choice made (or unmade with &"").
func set_choice(id: StringName, value: StringName) -> String:
	if value == &"":
		Story._choices.erase(id)
		return "Choice cleared."
	Story.make_choice(id, value)
	return "Chose %s." % value


## One of the five endings, or none (&"").
func set_ending(id: StringName) -> String:
	if id == &"":
		Story._ending = &""
		Story._ending_day = -1
		return "No ending."
	Story.set_ending(id)
	return "Ending: %s." % String(id).capitalize()
