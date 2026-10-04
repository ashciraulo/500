class_name CarMeet
extends Node3D
## The Friday and Saturday night meet: a car park where other 500 owners
## gather between 8 pm and 2 am. Pull in and stop to hang out: someone always
## has a story, and once a night there's a rumour about a barn find.

const RADIUS := 16.0
const NIGHTS := ["Friday", "Saturday"]
const FROM_HOUR := 20.0
const TO_HOUR := 2.0
const BUILDS := [
	["Pop on steelies, slammed", Color(0.92, 0.9, 0.84)],
	["Abarth with a straight-through exhaust", Color(0.75, 0.1, 0.1)],
	["TwinAir in Bossa Nova white", Color(0.95, 0.95, 0.92)],
	["Lounge with a Gucci stripe", Color(0.12, 0.12, 0.14)],
	["Turismo in matte grey", Color(0.4, 0.42, 0.44)],
	["500e, silent and smug", Color(0.3, 0.6, 0.62)],
	["Competizione on gold wheels", Color(0.95, 0.75, 0.1)],
	["Pop with fluffy dice and a roof box", Color(0.5, 0.75, 0.9)],
]
const CHAT := [
	"Someone's arguing about whether the TwinAir is a real engine.",
	"A kid asks if your 500 is the electric one.",
	"Somebody's selling a set of Abarth wheels out of a boot.",
	"The bloke with the Competizione says the Kings Park loop gold is impossible.",
	"Two owners compare how many badges they've found around town.",
	"Someone swears there's a classic that follows people through Kings Park at night.",
]

@export var meet_id := ""
@export var title := ""

var _cars: Node3D
var _car: CarController
var _visited_day := -1
var _check := 0.0


func _ready() -> void:
	add_to_group(&"car_meets")
	_cars = Node3D.new()
	add_child(_cars)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(meet_id)
	for i in BUILDS.size():
		var row := i % 2
		var slot := i / 2
		var spot := Node3D.new()
		spot.position = Vector3((slot - 1.5) * 2.6, 0.0, (row * 2.0 - 1.0) * 4.2)
		spot.rotation.y = PI if row == 1 else 0.0
		_cars.add_child(spot)
		var model := BarnFind.MODEL.instantiate() as Node3D
		spot.add_child(model)
		var paint := PS1Model.apply(model).get("Paint") as ShaderMaterial
		if paint:
			paint.set_shader_parameter("albedo_color", BUILDS[i][1])
			paint.set_shader_parameter("albedo_texture", null)
		var tag := Label3D.new()
		tag.text = BUILDS[i][0]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.006
		tag.font_size = 28
		tag.outline_size = 6
		tag.position = Vector3(0, 1.9, 0)
		tag.visibility_range_end = 14.0
		spot.add_child(tag)
	_refresh()


static func is_meet_time() -> bool:
	var h := GameClock.time_of_day
	var day := Garage.weekday()
	if h >= FROM_HOUR:
		return NIGHTS.has(day)
	if h < TO_HOUR:
		# Just after midnight it's still Friday or Saturday night.
		var yesterday: String = Garage.WEEKDAYS[(GameClock.day + 5) % 7]
		return NIGHTS.has(yesterday)
	return false


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	_refresh()
	if not _cars.visible:
		return
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		return
	if _visited_day != GameClock.day and _car.global_position.distance_to(global_position) < RADIUS and _car.speed_kmh() < 3.0:
		_visited_day = GameClock.day
		var rumour := Activities.visit_meet()
		var line: String = CHAT[randi() % CHAT.size()]
		if rumour != "":
			Activities.say("%s Then someone leans in: \"%s\"" % [line, Classics.barn_find(rumour).get("rumour", "")])
		else:
			Activities.say("%s No new rumours tonight." % line)


func _refresh() -> void:
	_cars.visible = is_meet_time()
