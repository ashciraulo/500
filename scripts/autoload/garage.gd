extends Node
## Parts you own, paint, fuel and washes: everything you spend on the car
## (autoload: Garage).
##
## Buying a part keeps it forever, so you can swap back and forth at a
## workshop without paying twice. What's actually fitted lives on the car
## (CarController.parts); this is the shelf in the shed.

signal parts_owned_changed
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
}
const RESPRAY_HOURS := 6.0

## Unleaded per litre through the week, Monday first. Perth prices run on a
## weekly cycle: cheap early in the week, a jump midweek.
const FUEL_PRICES := [1.79, 1.72, 2.05, 2.01, 1.96, 1.91, 1.85]
const WEEKDAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const WASH_PRICE := 15
const WASH_HOURS := 0.25
const ROADSIDE_PRICE := 85
const ROADSIDE_LITRES := 5.0
const ROADSIDE_HOURS := 0.75

var owned: PackedStringArray = []


func _ready() -> void:
	SaveGame.register("garage", self)


## True for stock parts, parts you've bought, and anything already on the car.
func owns(part: CarPart, car: CarController = null) -> bool:
	if part.is_stock() or owned.has(String(part.id)):
		return true
	return car != null and car.get_part_ids().has(String(part.id))


## Pay for a part. Returns false if you can't afford it.
func buy(part: CarPart) -> bool:
	if owns(part):
		return true
	if not Wallet.spend(part.price):
		return false
	owned.append(String(part.id))
	Progression.add_stat("parts_bought")
	parts_owned_changed.emit()
	return true


## Buy if needed, then fit. Returns false if you can't afford it.
func buy_and_fit(part: CarPart, car: CarController) -> bool:
	if not owns(part, car) and not buy(part):
		return false
	if car.get_part_ids().has(String(part.id)) or (part.is_stock() and not car.parts.has(part.slot)):
		return true
	car.install_part(part)
	GameClock.advance(FIT_HOURS.get(String(part.slot), 1.0))
	return true


## Respray the car. Returns false if you can't afford it.
func respray(car: CarController, index: int) -> bool:
	var paint: Array = PAINTS[index]
	if not Wallet.spend(paint[2]):
		return false
	car.set_paint(paint[1])
	GameClock.advance(RESPRAY_HOURS)
	Progression.add_stat("resprays")
	resprayed.emit(paint[1])
	return true


## Day 1 is a Monday.
func weekday() -> String:
	return WEEKDAYS[(GameClock.day - 1) % 7]


func fuel_price() -> float:
	return FUEL_PRICES[(GameClock.day - 1) % 7]


## Cost to put `litres` in, rounded to the cent and then to whole dollars
## (there are no coins in the game).
func fuel_cost(litres: float) -> int:
	return ceili(litres * fuel_price())


## Buy fuel: `litres` or as much as fits. Returns the litres added (0 if
## you couldn't afford any).
func buy_fuel(car: CarController, litres := INF) -> float:
	var want := minf(litres, car.tank_litres - car.fuel_litres)
	var affordable := floorf(Wallet.balance / fuel_price() * 10.0) / 10.0
	want = minf(want, affordable)
	if want <= 0.05:
		return 0.0
	if not Wallet.spend(fuel_cost(want), "fuel"):
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


func save_state() -> Dictionary:
	return {"owned": Array(owned)}


func load_state(data: Dictionary) -> void:
	owned = PackedStringArray(data.get("owned", []))
	parts_owned_changed.emit()
