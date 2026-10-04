class_name JobSite
extends Marker3D
## A named place jobs can start or end at: a shop, a café strip, a beach car
## park. The map places these (the test grid has placeholders). Driving close
## to one for the first time also counts as discovering it.

@export var site_id := ""
@export var display_name := ""
@export var suburb := ""
## What can happen here: "pickup", "dropoff", "trial".
@export var kinds := PackedStringArray(["pickup", "dropoff", "trial"])


func _ready() -> void:
	add_to_group(&"job_sites")
	if site_id == "":
		site_id = name.to_snake_case()
	if display_name == "":
		display_name = name.capitalize()


func label() -> String:
	return display_name if suburb == "" else "%s, %s" % [display_name, suburb]
