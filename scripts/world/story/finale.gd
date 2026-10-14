class_name Finale
extends Node3D
## The night of 11 July (STORY.md: act 5, choice 4 and the five endings).
##
## Once the shed is open (Mystery.solved) the calendar on its wall is turned
## to July 1979 with the 11th coloured in, and the game's calendar comes
## round to it: the night of the 11th is DAYS_TO days after the shed opened,
## from six in the evening to half past three the next morning. Missed, or
## only half lit, it comes round again every AGAIN days (the game's year is a
## short one).
##
## That night:
##   - It's the 11th: a card in the morning, and the messages on the machine
##     the days before (Dee's show, Thea, Robyn if you found her).
##   - Dee talks about Skylab on Notte FM, and at 12:37 it comes down again:
##     lights cross the sky, breaking up, going south-east.
##   - The lights over the river are brighter than ever. (In act 5 the rain
##     over them falls upwards, every night.)
##   - Choice 4. In the shed, look at the microphone, the deck or the
##     transmitter on M.'s table and press interact (twice, to be sure):
##       microphone   "Lights on": City of Light, or Half Light if not enough
##                    of the city is lit (deliveries; more if the thirteen
##                    was sold)
##       deck         record NIGHT DRIVE 13 (only if you answered the porch
##                    light): Night Drive 13
##       transmitter  switch it off: Lights Out
##     Or don't go to the shed: from twenty to three, with the porch light
##     on, the lights come down over Riverside Drive. Drive into them: The
##     Late City.
##
## Story.set_ending() says which ending; the scenes and what each leaves
## behind hang off Story.ending_reached and Story.ending().
##
## Added by GameplayPlaces. Saved under "finale".

signal chosen(choice: StringName, ending: StringName)

## The 11th comes this many days after the shed opens, and again this often.
const DAYS_TO := 7
const AGAIN := 14
## The night: from FROM_H on the 11th to TO_H the next morning (hours).
const FROM_H := 18.0
const TO_H := 3.5
## The morning card, and Skylab at 12:37 am (Perth, 12 July 1979).
const CARD_H := 7.0
const SKYLAB_H := 37.0 / 60.0
## The lights come down over Riverside Drive from twenty to three.
const DRIVE_IN_H := 2.0 + 40.0 / 60.0
const DRIVE_IN_SHOW := 700.0
const DRIVE_IN_RADIUS := 14.0
## Deliveries the city needs for City of Light, more if the thirteen was
## sold, and a little either way for every other wrong-bird print.
const LIT_NEEDED := 120
const LIT_SOLD := 60
const LIT_PER_PRINT := 5
const LIT_PRINTS_MAX := 30
## Dee on Notte FM: a line this often (s) while you're tuned in.
const DEE_EVERY := 90.0
const DEE_LINES := [
	"It's the eleventh of July. Forty-seven years ago tonight Skylab came down over the south-east, and half of Perth stayed up to watch it.",
	"My dad took us up to Kings Park in our pyjamas. We saw it go over, breaking up, like someone had thrown a handful of coals.",
	"There was a man who did a little show at this end of the dial back then. Night Drive. He went out that night and didn't come back.",
	"So if you're out driving tonight, look up. And if you've got a porch light, leave it on.",
	"It's late. This is Notte FM. Keep driving.",
]
## The endings after which there's no next 11 July.
const FINAL := [&"city_of_light", &"night_drive_13", &"lights_out", &"late_city"]
const CALENDAR := "res://art/models/home/mystery/shed_calendar_july.png"
## Skylab's path across the sky, from round the camera (m), and how long.
const SKYLAB_FROM := Vector3(-420.0, 190.0, -260.0)
const SKYLAB_TO := Vector3(430.0, 40.0, 320.0)
const SKYLAB_SECONDS := 11.0
const SKY := Color(1.0, 0.78, 0.5)

## The game day the 11th falls on (its evening), or -1 before the shed opens.
var night_day := -1
var nights_missed := 0
## The night (its night_day) a choice was made on, so it's once a night.
var chose_on := -1
## Tests and screenshots: the drive-in ignores the hour.
var force := false

var _mystery: Mystery
var _people: StoryPeople
var _table: ShedTable
var _calendar_done: Node
var _car: CarController
var _check := 0.0
var _card_day := -1
var _skylab_on := -1
var _dee_on := -1
var _dee_said := 0
var _dee_wait := 0.0
var _radio: Object
var _lit_up: Node   # the river lights made brighter tonight
var _rain: Node     # the lights the rain was put under
var _road_lights: Node3D
var _drive_in := Vector3.INF
var _river := Vector3.INF
var _skylab: Node3D
var _skylab_t := 0.0
## The thing on the table pressed once, and until when a second press counts.
var _armed := &""
var _armed_until := 0.0


func _ready() -> void:
	name = "Finale"
	SaveGame.register("finale", self)
	_setup.call_deferred()


func _exit_tree() -> void:
	SaveGame.unregister("finale")


func _setup() -> void:
	var places: Dictionary = get_parent().get("places") if get_parent() and get_parent().get("places") is Dictionary else {}
	for spot: Dictionary in places.get("photo_spots", []):
		if spot.id == "riverside_east":
			_drive_in = Vector3(spot.p[0], spot.p[1], spot.p[2])
			# Where Oddities hangs the lights, out over the river.
			_river = _drive_in + Vector3(0.0, 0.0, 70.0)
	_mystery = get_parent().get_node_or_null(^"Mystery") as Mystery
	if _mystery:
		_mystery.solved.connect(_on_shed_opened)
	_people = get_parent().get_node_or_null(^"StoryPeople") as StoryPeople
	var audio := get_node_or_null(^"/root/Audio")
	_radio = audio.get("radio") if audio else null


func _on_shed_opened() -> void:
	if night_day < 0:
		night_day = GameClock.day + DAYS_TO


# --- The calendar --------------------------------------------------------------

## Game hours since day 0.
static func _now() -> float:
	return GameClock.day * 24.0 + GameClock.time_of_day


## Whether it's the night of the 11th now.
func is_night() -> bool:
	if night_day < 0 or done():
		return false
	var t := _now()
	return t >= night_day * 24.0 + FROM_H and t < (night_day + 1) * 24.0 + TO_H


## Days until the 11th (0 on the day itself), or -1.
func days_to() -> int:
	return night_day - GameClock.day if night_day >= 0 and not done() else -1


## An ending there's no coming back from has been reached.
func done() -> bool:
	return Story.ending() in FINAL


func chose_tonight() -> bool:
	return chose_on == night_day


## How much of the city is lit (deliveries over the game), and how much
## City of Light needs.
func lit() -> int:
	return int(Progression.get_stat("deliveries"))


func lit_needed() -> int:
	var need := LIT_NEEDED
	if Story.choice(&"thirteen") == &"buyer":
		need += LIT_SOLD
	need += clampi((Story.prints_to_buyer - Story.prints_to_ros) * LIT_PER_PRINT, -LIT_PRINTS_MAX, LIT_PRINTS_MAX)
	return need


## The phone's line for the shed once it's open (Mystery.notes()).
func notes_line() -> String:
	match Story.ending():
		&"city_of_light":
			return "The city left its lights on, and the lights over the river went up. The transmitter's quiet."
		&"night_drive_13":
			return "NIGHT DRIVE 13 is your voice now. After midnight the city is 1979 again."
		&"lights_out":
			return "The transmitter is off. After midnight the station is only static."
		&"late_city":
			return "You went in after him."
	if is_night():
		return "It's the night of the 11th. The transmitter in the shed is waiting. The lights over the river are brighter than they've ever been."
	var days := days_to()
	if days < 0:
		return "The shed is open. The transmitter's little red light is on."
	var when := "tomorrow" if days == 1 else ("today" if days == 0 else "in %d days" % days)
	if Story.ending() == &"half_light":
		return "Only some of the city lit up, and the lights over the river settled back. The 11th comes round again %s. More of the city needs its lights on." % when
	return "The calendar in the shed is turned to July 1979, the 11th coloured in. The 11th comes round %s." % when


# --- Each frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if _skylab:
		_move_skylab(delta)
	if TitleScreen.is_showing(get_tree()):
		return
	_dee(delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _mystery == null:
		return
	if _mystery.is_solved and night_day < 0 and not done():
		# A game whose shed was open before there was an 11th.
		night_day = GameClock.day + DAYS_TO
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
	_dress_shed()
	_calendar()
	_river_lights()
	_drive_in_lights()


## The 11th comes and goes: the morning card, the flags the messages wait
## for, Skylab, and the next 11th if this one was missed or half lit.
func _calendar() -> void:
	if night_day < 0 or done():
		return
	var t := _now()
	if t >= (night_day + 1) * 24.0 + TO_H:
		if not chose_tonight():
			nights_missed += 1
			Story.log_night(StringName("eleventh_missed_%d" % night_day), "Missed the 11th of July. The red light in the shed stayed on.")
		while t >= (night_day + 1) * 24.0 + TO_H:
			night_day += AGAIN
		return
	if night_day - GameClock.day <= 2:
		Story.set_flag(&"eleventh_soon")
	if GameClock.day == night_day and GameClock.time_of_day >= CARD_H and _card_day != night_day:
		_card_day = night_day
		Notices.post("It's the 11th of July. The day on the calendar in the shed.", "mystery", "", "11 July")
	if is_night():
		Story.set_flag(&"eleventh_night")
	if is_night() and GameClock.day == night_day + 1 and GameClock.time_of_day >= SKYLAB_H \
			and GameClock.time_of_day < SKYLAB_H + 0.5 and _skylab_on != night_day:
		_skylab_on = night_day
		skylab()


# --- The shed: the calendar on the wall and the table -----------------------------

func _dress_shed() -> void:
	var props := _mystery.get(&"_shed_props") as Node3D
	if props == null or not is_instance_valid(props):
		return
	if _calendar_done != props:
		_calendar_done = props
		_turn_calendar(props)
		_table = ShedTable.new()
		_table.finale = self
		props.add_child(_table)
		if Story.ending() == &"lights_out":
			_lights_off(props)


## The model's calendar is a March page; turn it over to July.
func _turn_calendar(props: Node3D) -> void:
	if not ResourceLoader.exists(CALENDAR):
		return
	var page := load(CALENDAR) as Texture2D
	for mi: MeshInstance3D in props.find_children("*", "MeshInstance3D", true, false):
		for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.get_active_material(i) as ShaderMaterial
			if m and m.resource_name.to_lower() == "sr_calendar":
				m.set_shader_parameter("albedo_texture", page)


## The red lights on the deck and the transmitter, and the valve, go out.
func _lights_off(props: Node3D) -> void:
	for socket: String in ["DeckLight", "TxLight", "Valve"]:
		var at := props.find_child(socket, true, false)
		if at:
			for c in at.get_children():
				if c is Light3D:
					(c as Light3D).visible = false
	for mi: MeshInstance3D in props.find_children("*", "MeshInstance3D", true, false):
		for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.get_active_material(i) as ShaderMaterial
			if m and m.resource_name in ["Lamp", "ValveGlow"]:
				m.set_shader_parameter("emission_energy", 0.0)


## What the table's hint says for the thing you're looking at.
func table_hint(thing: StringName) -> String:
	if done():
		return ""
	var hint := ""
	if is_night() and not chose_tonight():
		match thing:
			&"mic":
				hint = "Microphone: ask the city to leave its lights on"
			&"deck":
				hint = "Deck: record NIGHT DRIVE 13" if Story.choice(&"porch_light") == &"on" else "Deck: the record key won't go down"
			&"tx":
				hint = "Transmitter: switch it off for good"
		if thing == _armed and _now_s() < _armed_until:
			hint = "Again to be sure. " + hint
		return hint
	match thing:
		&"mic":
			return "Microphone"
		&"deck":
			return "Deck"
		&"tx":
			return "Transmitter"
	return ""


func use_table(thing: StringName) -> void:
	if done():
		return
	if not is_night() or chose_tonight():
		Activities.say(_not_tonight(thing))
		return
	if thing == &"deck" and Story.choice(&"porch_light") != &"on":
		Activities.say("The record key won't go down. He doesn't know you're here.")
		return
	# Once to choose, twice to be sure.
	if thing != _armed or _now_s() > _armed_until:
		_armed = thing
		_armed_until = _now_s() + 5.0
		return
	_armed = &""
	match thing:
		&"mic":
			choose(&"lights_on")
		&"deck":
			choose(&"tape_13")
		&"tx":
			choose(&"switch_off")


func _not_tonight(thing: StringName) -> String:
	if chose_tonight():
		return "Not again tonight. The 11th comes round again."
	var days := days_to()
	match thing:
		&"mic":
			return "The microphone's cold. Whatever it's for, it isn't for tonight."
		&"deck":
			return "NIGHT DRIVE 13 is in the deck, turning, with nothing on it yet."
	if days > 0:
		return "The little red light is on. It's been on since 1979. The calendar says the 11th: %s." % ("tomorrow" if days == 1 else "%d days away" % days)
	return "The little red light is on. It's been on since 1979."


static func _now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


## Choice 4. Remembered for the night, and the ending it leads to.
func choose(what: StringName) -> void:
	if done() or chose_tonight() or not what in Story.CHOICES[&"eleventh_july"]:
		return
	chose_on = night_day
	Story.make_choice(&"eleventh_july", what)
	var ending := &""
	match what:
		&"lights_on":
			ending = &"city_of_light" if lit() >= lit_needed() else &"half_light"
			Activities.say("You switch the microphone on and lean in close. \"This is Night Drive. If you can hear this, leave your lights on tonight. All of them.\"")
			if ending == &"city_of_light":
				Story.log_night(&"eleventh_lights_on", "On the 11th of July I asked the city to leave its lights on. It did.")
			else:
				Story.log_night(StringName("eleventh_half_light_%d" % night_day), "On the 11th of July I asked the city to leave its lights on. Only some of it did.")
		&"tape_13":
			ending = &"night_drive_13"
			Activities.say("You press record. You read out the streets you've driven at night, in the order you drove them. Then: \"Little Shenton Lane. Home.\"")
			Story.log_night(&"eleventh_tape_13", "On the 11th of July I recorded NIGHT DRIVE 13.")
		&"switch_off":
			ending = &"lights_out"
			Activities.say("You flick the switch. The little red light goes out, after forty-seven years.")
			Story.log_night(&"eleventh_switch_off", "On the 11th of July I switched the transmitter off.")
			if _calendar_done:
				_lights_off(_calendar_done as Node3D)
		&"went_in":
			ending = &"late_city"
			Story.log_night(&"eleventh_went_in", "On the 11th of July, at twenty to three, I drove into the lights over Riverside Drive.")
	Story.set_ending(ending)
	chosen.emit(what, ending)


# --- Dee on Notte FM -----------------------------------------------------------------

func _dee(delta: float) -> void:
	if _radio == null or not is_night() or (_dee_said >= DEE_LINES.size() and _dee_on == night_day):
		return
	if String(_radio.call("current_station_id")) != "nottefm" or not bool(_radio.call("is_on")):
		_dee_wait = minf(_dee_wait, 8.0)
		return
	if _dee_on != night_day:
		_dee_on = night_day
		_dee_said = 0
		_dee_wait = 8.0
	_dee_wait -= delta
	if _dee_wait > 0.0 or _dee_said >= DEE_LINES.size():
		return
	_dee_wait = DEE_EVERY
	Activities.say("On Notte FM, Dee: \"%s\"" % DEE_LINES[_dee_said])
	_dee_said += 1
	if _dee_said == 1:
		Story.log_night(StringName("dee_skylab_%d" % night_day), "Dee did a show about Skylab on Notte FM.")


# --- Skylab ---------------------------------------------------------------------------

## Lights cross the sky, breaking up, going south-east, like 1979. They ride
## with the camera, the way the sky does.
func skylab() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _skylab:
		return
	_skylab = Node3D.new()
	_skylab.name = "Skylab"
	_skylab.top_level = true
	add_child(_skylab)
	_skylab.global_position = cam.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	for i in 11:
		var bit := Node3D.new()
		bit.set_meta(&"lag", i * 0.22 + rng.randf_range(0.0, 0.3))
		bit.set_meta(&"off", Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-12.0, 12.0)))
		var size := 1.0 - i * 0.06
		bit.add_child(_glow_box(Vector3(5.0, 5.0, 5.0) * size, Vector3.ZERO, SKY))
		# A tail back the way it came.
		bit.add_child(_glow_box(Vector3(2.0, 2.0, 46.0) * size, Vector3(0.0, 0.0, 23.0 * size), SKY.darkened(0.35)))
		_skylab.add_child(bit)
	_skylab_t = 0.0
	Notices.post("Lights cross the sky, breaking up as they go. South-east, the way Skylab went.", "odd")
	Discoveries.discover("oddity/skylab")
	Story.log_night(StringName("skylab_%d" % night_day), "At 12:37 on the 12th of July, Skylab came down again over the city.")


func _move_skylab(delta: float) -> void:
	_skylab_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam:
		_skylab.global_position = cam.global_position
	var dir := (SKYLAB_TO - SKYLAB_FROM).normalized()
	for bit: Node3D in _skylab.get_children():
		var f := clampf((_skylab_t - float(bit.get_meta(&"lag"))) / SKYLAB_SECONDS, 0.0, 1.0)
		bit.visible = f > 0.0 and f < 1.0
		bit.position = SKYLAB_FROM.lerp(SKYLAB_TO, f) + (bit.get_meta(&"off") as Vector3) * (0.3 + f)
		bit.look_at(_skylab.global_position + bit.position + dir, Vector3.UP)
	if _skylab_t > SKYLAB_SECONDS + 4.0:
		_skylab.queue_free()
		_skylab = null


static func _glow_box(size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.disable_fog = true
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- The river ------------------------------------------------------------------------

## Oddities hangs the lights over the river after midnight. In act 5 the rain
## under them falls upwards; on the 11th they're brighter than ever.
func _river_lights() -> void:
	var odd := get_parent().get_node_or_null(^"Oddities")
	var lights := odd.get(&"_lights") as Node3D if odd else null
	if lights == null or not is_instance_valid(lights):
		return
	if Story.act() >= 5 and _rain != lights:
		_rain = lights
		lights.add_child(rain_up())
	if is_night() and _lit_up != lights:
		_lit_up = lights
		for orb in lights.get_children():
			if orb is MeshInstance3D:
				(orb as MeshInstance3D).scale = Vector3.ONE * 2.2
				for glow in orb.get_children():
					if glow is OmniLight3D:
						(glow as OmniLight3D).light_energy = 5.0
						(glow as OmniLight3D).omni_range = 22.0


## Rain falling up out of the river, in a column round the lights.
static func rain_up() -> CPUParticles3D:
	var rain := CPUParticles3D.new()
	rain.name = "RainUp"
	rain.amount = 420
	rain.lifetime = 3.2
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(34.0, 0.4, 34.0)
	rain.direction = Vector3.UP
	rain.spread = 3.0
	rain.gravity = Vector3(0.0, 1.5, 0.0)
	rain.initial_velocity_min = 5.0
	rain.initial_velocity_max = 8.0
	rain.position.y = -2.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.03, 0.55, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.86, 0.95, 0.5)
	drop.material = m
	rain.mesh = drop
	rain.visibility_aabb = AABB(Vector3(-40.0, -4.0, -40.0), Vector3(80.0, 44.0, 80.0))
	return rain


## Whether the lights are down over Riverside Drive now: the 11th, from
## twenty to three, with the porch light on and no choice made yet tonight.
func drive_in_open() -> bool:
	if _drive_in == Vector3.INF or done() or not is_night() or chose_tonight():
		return false
	if _people == null or not _people.porch_light_on:
		return false
	var h := GameClock.time_of_day
	return force or (GameClock.day == night_day + 1 and h >= DRIVE_IN_H and h < TO_H)


func _drive_in_lights() -> void:
	var open := drive_in_open() and _car != null
	var d := _car.global_position.distance_to(_drive_in) if _car else INF
	if open and d < DRIVE_IN_SHOW and _road_lights == null:
		_road_lights = _make_road_lights()
		add_child(_road_lights)
		_road_lights.global_position = _drive_in
		_road_lights.create_tween().set_loops().tween_property(_road_lights, "rotation:y", TAU, 60.0).from(0.0)
	elif _road_lights and (not open or d > DRIVE_IN_SHOW + 100.0):
		_road_lights.queue_free()
		_road_lights = null
	if _road_lights == null:
		return
	var flat := _car.global_position - _drive_in
	flat.y = 0.0
	var walker := get_tree().root.find_child("Player", true, false)
	var in_car: bool = walker == null or walker.get("in_car") != false
	if in_car and flat.length() < DRIVE_IN_RADIUS:
		Notices.post("The lights close round the car. When they open again the street lights are orange, and it's very quiet.", "odd")
		choose(&"went_in")
		_road_lights.queue_free()
		_road_lights = null


## The lights, come down low over the road: thirteen of them, brighter and
## closer than the ones over the water.
func _make_road_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "RoadLights"
	var rng := RandomNumberGenerator.new()
	rng.seed = 711
	for i in 13:
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.3
		sphere.height = 2.6
		sphere.radial_segments = 8
		sphere.rings = 4
		orb.mesh = sphere
		orb.material_override = PS1Material.glowing(Color(0.95, 0.8, 0.5), 1.4)
		var a := TAU * i / 13.0
		orb.position = Vector3(cos(a) * rng.randf_range(4.0, 11.0), rng.randf_range(3.5, 8.0), sin(a) * rng.randf_range(4.0, 11.0))
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.85, 0.6)
		glow.light_energy = 3.5
		glow.omni_range = 16.0
		orb.add_child(glow)
		root.add_child(orb)
	root.add_child(rain_up())
	return root


# --- Saving -----------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"night_day": night_day, "missed": nights_missed, "chose_on": chose_on,
		"card_day": _card_day, "skylab_on": _skylab_on, "dee_on": _dee_on, "dee_said": _dee_said}


func load_state(data: Dictionary) -> void:
	night_day = int(data.get("night_day", -1))
	nights_missed = int(data.get("missed", 0))
	chose_on = int(data.get("chose_on", -1))
	_card_day = int(data.get("card_day", -1))
	_skylab_on = int(data.get("skylab_on", -1))
	_dee_on = int(data.get("dee_on", -1))
	_dee_said = int(data.get("dee_said", 0))
