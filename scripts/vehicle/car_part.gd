class_name CarPart
extends Resource
## One upgrade (or the stock part) for a slot on a car.
##
## Parts are data: each lives in data/parts/<id>.tres. Installing one on a
## CarController changes its stats through `modifiers`; the `visual` id tells
## the car body which model to show (wheels, exhausts), if any.
##
## Modifier keys (anything missing is left alone):
##   torque_mult, final_drive_mult, shift_time_mult, grip_mult, spring_mult,
##   damper_mult, anti_roll_mult, brake_mult, drag_mult, wet_penalty_mult
##                               multiply the car's stock value
##   limiter_add (rpm), ride_height_add (m, negative = lower), mass_add (kg),
##   lateral_stiffness_add       add to the stock value
##   gear_ratios (Array of floats) replaces the gearbox ratios

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## engine, intake, exhaust, gearbox, suspension, tyres, wheels, brakes,
## weight, roof, lights
@export var slot: StringName
## Price in Australian dollars. Stock parts are 0.
@export var price := 0
@export var modifiers := {}
## Car ids this part fits. Empty = any car with the slot (electric cars
## have no engine, intake, exhaust or gearbox to swap).
@export var fits: PackedStringArray = []
## Model id for the car body to show, e.g. "exhaust_sport". Empty = none.
## Wheels use art/models/cars/parts/<visual>_l/_r.glb; exhaust, roof and
## lights parts use <visual>.glb at the body's Mount_Exhaust, Mount_Roof or
## Mount_Spotlights.
@export var visual := ""
## Which kinds of car it suits (CarCatalogue "ladder": modern, electric,
## classic). Empty = all. A 17" Abarth wheel won't go on a 1957 Nuova.
@export var ladders: PackedStringArray = []
## Can't be bought: it's somewhere in the city (data/world/found_parts.json).
## Once found (discovery "part/<id>") it's yours for any car it fits.
@export var found_only := false


func is_stock() -> bool:
	return String(id).ends_with("_stock")
