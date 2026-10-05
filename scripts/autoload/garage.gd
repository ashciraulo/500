extends Node
## Your cars and everything you spend on them: buying cars, parts, paint,
## fuel and washes (autoload: Garage).
##
## Each car keeps its own parts, tuning, paint, fuel and odometer. The car
## you're driving holds its own state (the CarController); the others wait
## here in `cars`. A part you buy belongs to the car you bought it for, so
## you can swap it back and forth without paying twice.

signal parts_owned_changed
signal car_bought(id: String)
signal car_switched(id: String)
signal resprayed(color: Color)

## Respray colours: [name, colour, price].
const PAINTS := [
	["Gelato white", Color(0.93, 0.92, 0.88), 900],
	["Passion red", Color(0.72, 0.08, 0.1), 900],
	["Cinema black", Color(0.07, 0.07, 0.08), 900],
	["Slate grey", Color(0.42, 0.44, 0.47), 900],
	["Cottesloe blue", Color(0.32, 0.6, 0.82), 1100],
	["Swan River teal", Color(0.12, 0.45, 0.45), 1100],
	["Pastel mint", Color(0.66, 0.86, 0.76), 1100],
	["Pistachio", Color(0.68, 0.76, 0.42), 1100],
	["Rottnest sand", Color(0.85, 0.76, 0.58), 1100],
	["Sunburnt orange", Color(0.9, 0.42, 0.14), 1300],
	["Bubblegum pink", Color(0.95, 0.6, 0.72), 1300],
	["Kings Park olive", Color(0.36, 0.38, 0.2), 1300],
]

## Hours of the day spent in the shed fitting a part, by slot.
const FIT_HOURS := {
	"engine": 4.0, "gearbox": 3.0, "suspension": 2.5, "exhaust": 1.0,
	"intake": 0.5, "brakes": 1.5, "tyres": 1.0, "wheels": 0.5, "weight": 0.5,
	"roof": 0.5, "lights": 1.0,
}
const RESPRAY_HOURS := 6.0
## Jobs on the consumables (CarController.wear), done in your carport:
## item -> [what it's called, price in dollars, hours spent on it].
const SERVICES := {
	"oil": ["Oil and filter change", 60, 1.0],
	"brakes": ["New brake pads", 140, 1.5],
	"tyres": ["Set of four tyres", 320, 2.0],
}

## Unleaded per litre through the week, Monday first. Perth prices run on a
## weekly cycle: cheap early in the week, a jump midweek.
const FUEL_PRICES := [1.79, 1.72, 2.05, 2.01, 1.96, 1.91, 1.85]
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
## Fast charger, per kWh.
const CHARGE_PRICE := 0.55
const WASH_PRICE := 15
const WASH_HOURS := 0.25
const ROADSIDE_PRICE := 85
const ROADSIDE_LITRES := 5.0
const ROADSIDE_HOURS := 0.75

## Parts bought, as "car_id/part_id".
var owned: PackedStringArray = []
## Cars you own, by id. The Pop is yours from the start.
var owned_cars: PackedStringArray = [CarCatalogue.STARTER]
## Saved state of the cars you're not driving (CarController.vehicle_state).
var cars := {}


func _ready() -> void:
	SaveGame.register("garage", self)


## True for stock parts, parts you've bought for this car, and anything
## already on it.
func owns(part: CarPart, car: CarController) -> bool:
	if part.is_stock() or owned.has(_key(car.car_id, part)):
		return true
	if part.found_only and is_found(part):
		return true
	return car.get_part_ids().has(String(part.id))


## Pay for a part for this car. Returns false if you can't afford it, it
## doesn't fit, or it's one you have to find.
func buy(part: CarPart, car: CarController) -> bool:
	if owns(part, car):
		return true
	if part.found_only or not PartsCatalogue.fits(part, car.car_id) or not Wallet.spend(part.price):
		return false
	owned.append(_key(car.car_id, part))
	Progression.add_stat("parts_bought")
	parts_owned_changed.emit()
	return true


## Buy if needed, then fit. Returns false if you can't afford it.
func buy_and_fit(part: CarPart, car: CarController) -> bool:
	if not PartsCatalogue.fits(part, car.car_id):
		return false
	if not owns(part, car) and not buy(part, car):
		return false
	if car.get_part_ids().has(String(part.id)) or (part.is_stock() and not car.parts.has(part.slot)):
		return true
	car.install_part(part)
	# New tyres or brakes come fresh.
	if car.wear.has(String(part.slot)):
		car.wear[String(part.slot)] = 0.0
	car.log_entry("Fitted the %s." % part.display_name)
	GameClock.advance(FIT_HOURS.get(String(part.slot), 1.0))
	return true


## Do a service job (see SERVICES) on the car: pay, spend the time, and the
## item is as good as new. False if it can't be done or afforded.
func service(car: CarController, item: String) -> bool:
	if not SERVICES.has(item) or not car.wear.has(item) or (item == "oil" and car.is_electric):
		return false
	if car.wear[item] < 0.02 or not Wallet.spend(SERVICES[item][1], String(SERVICES[item][0]).to_lower()):
		return false
	car.wear[item] = 0.0
	car.log_entry(String(SERVICES[item][0]) + ".")
	GameClock.advance(SERVICES[item][2])
	Progression.add_stat("services_done")
	return true


## Respray the car. Returns false if you can't afford it.
func respray(car: CarController, index: int) -> bool:
	var paint: Array = PAINTS[index]
	if not Wallet.spend(paint[2]):
		return false
	car.set_paint(paint[1])
	car.log_entry("Resprayed in %s." % paint[0])
	GameClock.advance(RESPRAY_HOURS)
	Progression.add_stat("resprays")
	resprayed.emit(paint[1])
	return true


## Day 1 is a Monday.
func weekday() -> String:
	return WEEKDAYS[(GameClock.day - 1) % 7]


## Price per litre today, or per kWh at a charger for an electric car.
func fuel_price(car: CarController = null) -> float:
	if car and car.is_electric:
		return CHARGE_PRICE
	return FUEL_PRICES[(GameClock.day - 1) % 7]


## Cost to put `litres` (kWh for an EV) in, rounded up to whole dollars
## (there are no coins in the game).
func fuel_cost(litres: float, car: CarController = null) -> int:
	return ceili(litres * fuel_price(car))


## Buy fuel: `litres` or as much as fits. Returns the litres added (0 if
## you couldn't afford any).
func buy_fuel(car: CarController, litres := INF) -> float:
	var want := minf(litres, car.tank_litres - car.fuel_litres)
	var affordable := floorf(Wallet.balance / fuel_price(car) * 10.0) / 10.0
	want = minf(want, affordable)
	if want <= 0.05:
		return 0.0
	if not Wallet.spend(fuel_cost(want, car), "fuel"):
		return 0.0
	Progression.add_stat("litres_bought", want)
	return car.refuel(want)


func wash(car: CarController) -> bool:
	if not Wallet.spend(WASH_PRICE, "car wash"):
		return false
	car.dirt = 0.0
	GameClock.advance(WASH_HOURS)
	Progression.add_stat("washes")
	return true


## Out of fuel somewhere: someone drives out with a jerry can. Free if you're
## broke, because being stranded isn't fun.
func roadside_assist(car: CarController) -> void:
	if not Wallet.spend(ROADSIDE_PRICE, "roadside assist"):
		Wallet.spend(Wallet.balance)
	car.refuel(ROADSIDE_LITRES)
	GameClock.advance(ROADSIDE_HOURS)


# --- Cars ---------------------------------------------------------------------

func owns_car(id: String) -> bool:
	return owned_cars.has(id)


## Why a car can't be bought right now, or "" if it can.
func car_blocker(id: String) -> String:
	var car := CarCatalogue.get_car(id)
	if car.is_empty():
		return "unknown car"
	if owns_car(id):
		return "already yours"
	match car.unlock:
		"barn_find":
			return "found, not bought"
		"secret":
			return "a secret"
	if Progression.tier_index < int(car.tier):
		return "unlocks at tier %d" % (int(car.tier) + 1)
	if not CarCatalogue.is_drivable(car):
		return "not ready yet"
	if not Wallet.can_afford(int(car.price)):
		return "can't afford it yet"
	return ""


## Buy a car and drive away in it. Your old car goes home to the carport.
func buy_car(id: String, car: CarController) -> bool:
	if car_blocker(id) != "":
		return false
	Wallet.spend(int(CarCatalogue.get_car(id).price), "car")
	owned_cars.append(id)
	Progression.add_stat("cars_bought")
	car_bought.emit(id)
	switch_car(id, car)
	return true


## Give a car you own to the player (barn finds, secrets).
func add_car(id: String) -> void:
	if not owns_car(id) and not CarCatalogue.get_car(id).is_empty():
		owned_cars.append(id)
		car_bought.emit(id)


## Put the current car away and take another one you own.
func switch_car(id: String, car: CarController) -> bool:
	if not owns_car(id) or not CarCatalogue.is_drivable(CarCatalogue.get_car(id)) or not Classics.can_drive(id):
		return false
	if id == car.car_id:
		return true
	cars[car.car_id] = car.vehicle_state()
	car.load_vehicle_state(cars.get(id, {"car_id": id}))
	cars.erase(id)
	car_switched.emit(id)
	return true


## Kilometres driven across every car you own.
func lifetime_km(car: CarController) -> float:
	var km := car.odometer_km if car else 0.0
	for id in cars:
		if car == null or id != car.car_id:
			km += float(cars[id].get("odometer_km", 0.0))
	return km


## Most kilometres driven in any one car of the given tier.
func km_in_tier(tier: int, car: CarController) -> float:
	var best := 0.0
	for id in owned_cars:
		var info := CarCatalogue.get_car(id)
		if info.is_empty() or int(info.tier) != tier or info.ladder == "classic":
			continue
		var km: float = car.odometer_km if car and car.car_id == id else float(cars.get(id, {}).get("odometer_km", 0.0))
		best = maxf(best, km)
	return best


## Found-only parts (CarPart.found_only) are yours once found in the city.
func is_found(part: CarPart) -> bool:
	return Discoveries.has("part/" + String(part.id))


func _key(car_id: String, part: CarPart) -> String:
	return "%s/%s" % [car_id, part.id]


func save_state() -> Dictionary:
	return {"owned": Array(owned), "owned_cars": Array(owned_cars), "cars": cars}


func load_state(data: Dictionary) -> void:
	owned = PackedStringArray(data.get("owned", []))
	owned_cars = PackedStringArray(data.get("owned_cars", [CarCatalogue.STARTER]))
	cars = data.get("cars", {})
	parts_owned_changed.emit()
