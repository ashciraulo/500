class_name Mystery
extends Node3D
## The main mystery, a slow burn over the whole career. After midnight the
## unlisted station on the radio (the "midnight station") reads out a place.
## Drive there between midnight and half past three and something has been
## left for you: a tape, a Polaroid, a 1979 parking ticket. The next morning
## it isn't in the car any more; it's on the boxes in the cupboard under the
## stairs, and the cupboard you shut last night is open. The last thing the
## voice sends you to, late in the career, is the key to your locked shed,
## and what's under the sheet in there ties the oddities together.
##
## Knock on the shed late at night and something knocks back.
##
## Clues and their tier gates are in data/progression/mystery.json. Progress
## is saved under "mystery"; each find is also a discovery ("mystery/<id>").

signal clue_heard(id: String)
signal clue_found(id: String)
signal solved

const DATA_PATH := "res://data/progression/mystery.json"
const NIGHT_FROM := 0.0
const NIGHT_TO := 3.5
## The voice repeats itself this often (s) while you stay on the station.
const REPEAT := 75.0
## Build the waiting object when you're this close (m), so the tiles are in.
const SHOW_RADIUS := 220.0
## Pick it up by stopping within this (m) in the car, or walking up to it.
const PICKUP_CAR := 7.0
const PICKUP_FOOT := 2.2
const REVEAL_RADIUS := 1.8
const REWARD := "trinket_night_drive_tape"

var clues: Array = []
var ending: Array = []
var min_days := 2
## Saved progress.
var heard := ""                 # clue the voice has sent you to and you haven't found yet
var found: PackedStringArray = []
var last_found_day := -100
var in_cupboard: PackedStringArray = []   # found things that have turned up at home
var has_key := false
var is_solved := false
var knocks := 0

var _car: Node3D
var _player: Node
var _home: Node3D
var _check := 0.0
var _repeat := 0.0
var _on_station := false
var _waiting: Node3D             # the object at the clue's spot
var _waiting_id := ""
var _shelf: Node3D               # cupboard props
var _shed_props: Node3D
var _bed: AudioStreamPlayer      # the mystery underscore while it plays
var _bed_tween: Tween


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if parsed is Dictionary:
		clues = parsed.get("clues", [])
		ending = parsed.get("ending", [])
		min_days = int(parsed.get("min_days", 2))
	SaveGame.register("mystery", self)
	_setup.call_deferred()


func _exit_tree() -> void:
	SaveGame.unregister("mystery")


func _setup() -> void:
	var radio = _radio()
	if radio and radio.has_signal("station_changed"):
		radio.station_changed.connect(_on_station_changed)
		_on_station = _current_station(radio) == "midnight"


# --- Progress -------------------------------------------------------------------

## The clue the voice will send you to next, or {} if it's not time yet.
func next_clue() -> Dictionary:
	if is_solved or heard != "":
		return {}
	for clue: Dictionary in clues:
		if found.has(clue.id):
			continue
		if Progression.tier_index < int(clue.get("tier", 0)):
			return {}
		if GameClock.day < last_found_day + min_days:
			return {}
		return clue
	return {}


func clue(id: String) -> Dictionary:
	for c: Dictionary in clues:
		if c.id == id:
			return c
	return {}


func is_night() -> bool:
	var h: float = GameClock.time_of_day
	return h >= NIGHT_FROM and h < NIGHT_TO


## What the phone shows: where the voice sent you, and what you've found.
func notes() -> PackedStringArray:
	var lines: PackedStringArray = []
	if is_solved:
		lines.append("The shed is open. The transmitter is off. The station still plays after midnight, but it doesn't say anything new.")
	elif heard != "":
		lines.append("The midnight station said: " + String(clue(heard).get("broadcast", "")))
		lines.append("  Go there between midnight and half past three.")
	elif has_key:
		lines.append("You have the shed key.")
	elif not Discoveries.has("oddity/midnight_station"):
		lines.append("Late at night, try the radio. There's a station between the others after midnight.")
	elif found.is_empty() or not next_clue().is_empty():
		lines.append("The midnight station has something to say tonight.")
	else:
		lines.append("The midnight station is quiet for now. Keep working; keep driving at night.")
	for id in found:
		var c := clue(id)
		if not c.is_empty():
			lines.append("Found " + String(c.get("title", id)) + ".")
	return lines


# --- The voice ------------------------------------------------------------------

func _on_station_changed(id: String, _display: String) -> void:
	_on_station = id == "midnight"
	_repeat = 0.0
	if _on_station:
		_broadcast.call_deferred()


func _broadcast() -> void:
	if not _on_station or is_solved or not is_night():
		return
	_repeat = REPEAT
	if heard == "":
		var next := next_clue()
		if next.is_empty():
			return
		heard = next.id
		clue_heard.emit(heard)
	var c := clue(heard)
	Activities.say("Under the static, a calm voice: " + String(c.get("broadcast", "")))
	_variant(_clue_cue(heard))
	_bed_swell(20.0)


# --- Each frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if _on_station and _repeat > 0.0:
		_repeat -= delta
		if _repeat <= 0.0:
			_broadcast()
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.4
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as Node3D
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false)
	if _home == null or not is_instance_valid(_home):
		_find_home()
	if _car == null:
		return
	_check_waiting()
	_check_shed()


func _focus() -> Vector3:
	if _player and not _player.get("in_car") and _player is Node3D:
		return (_player as Node3D).global_position
	return _car.global_position


func _check_waiting() -> void:
	var want := heard if heard != "" and is_night() else ""
	if want != _waiting_id:
		_clear_waiting()
	if want == "":
		return
	var at := spot_position(want)
	if at == Vector3.INF:
		return
	var focus := _focus()
	var d := focus.distance_to(at)
	if _waiting == null:
		if d < SHOW_RADIUS:
			_place_waiting(want, at)
		return
	d = focus.distance_to(_waiting.global_position)
	var on_foot: bool = _player != null and not _player.get("in_car")
	var picked: bool = d < PICKUP_FOOT if on_foot else (d < PICKUP_CAR and _car.linear_velocity.length() < 2.5)
	if picked:
		_pick_up(want)


## Where a clue waits: its `at` (the kerb by the photo spot), a photo spot (a
## few metres to the side), or the lane end.
func spot_position(id: String) -> Vector3:
	var spot := String(clue(id).get("spot", ""))
	if spot == "lane_end":
		return lane_end()
	var at: Variant = clue(id).get("at")
	if at is Array and at.size() == 3:
		return Vector3(at[0], at[1], at[2])
	var places: Dictionary = get_parent().get("places") if get_parent() and get_parent().get("places") is Dictionary else {}
	for p: Dictionary in places.get("photo_spots", []):
		if p.id == spot:
			var yaw := float(p.get("yaw", 0.0))
			return Vector3(p.p[0], p.p[1], p.p[2]) + Basis(Vector3.UP, yaw) * Vector3(3.0, 0.0, 0.0)
	return Vector3.INF


## The far end of Little Shenton Lane, where the classic idles at night
## (oddities.gd's lane_idle) and where the key turns up.
func lane_end() -> Vector3:
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map == null and get_parent() and get_parent().get_parent():
		map = get_parent().get_parent().get_node_or_null("PerthMap")
	if map == null or not map.has_method("get_spawn_transform"):
		return Vector3.INF
	var spawn: Transform3D = map.get_spawn_transform()
	return spawn.origin - spawn.basis.z * Oddities.LANE_END_DISTANCE


func _place_waiting(id: String, at: Vector3) -> void:
	_waiting_id = id
	_waiting = Node3D.new()
	_waiting.name = "Clue_" + id
	add_child(_waiting)
	_waiting.global_position = _ground(at)
	var kind := String(clue(id).get("cupboard", ""))
	var thing := MysteryProps.for_clue(id, "key" if id == "shed_key" else kind)
	_waiting.add_child(thing)
	# A faint glow so it can be seen from the car at night.
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.85, 0.9, 1.0)
	glow.light_energy = 0.8
	glow.omni_range = 3.5
	glow.position.y = 0.4
	_waiting.add_child(glow)
	var hum := _loop_player("oddity/odd_mystery_bed_loop", 6.0, -10.0)
	_waiting.add_child(hum)


func _clear_waiting() -> void:
	if _waiting:
		_waiting.queue_free()
	_waiting = null
	_waiting_id = ""


func _ground(at: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 6.0, at + Vector3.DOWN * 20.0, ~MapTileLoader.LAYER_WATER)
		if _car is CollisionObject3D:
			query.exclude = [(_car as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		if hit:
			return hit.position
	return at


func _pick_up(id: String) -> void:
	_clear_waiting()
	heard = ""
	found.append(id)
	last_found_day = GameClock.day
	Discoveries.discover("mystery/" + id)
	var c := clue(id)
	# Cards for what you found, each with its sound as it shows (Notices).
	if id == "shed_key":
		has_key = true
		Notices.post(String(c.get("found", "")), "mystery", "-")
		Notices.post("The shed. It's the key to the shed.", "key")
	else:
		Notices.post(String(c.get("found", "")), "mystery")
	_bed_swell(25.0)
	clue_found.emit(id)


# --- Home: the cupboard under the stairs and the shed -------------------------------

func _find_home() -> void:
	_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
	if _home == null:
		return
	if _home.has_signal("slept") and not _home.slept.is_connected(_on_slept):
		_home.slept.connect(_on_slept)
	if _home.has_signal("shed_tried") and not _home.shed_tried.is_connected(_on_shed_tried):
		_home.shed_tried.connect(_on_shed_tried)
	if is_solved:
		_home.unlock_shed()
	_build_shelf()
	if is_solved:
		_reveal(false)


func _on_slept(_day: int) -> void:
	# Whatever you found last night has made its own way into the cupboard.
	var arrived := ""
	for id in found:
		if in_cupboard.has(id) or String(clue(id).get("cupboard", "")) == "":
			continue
		in_cupboard.append(id)
		arrived = id
	if arrived == "":
		return
	_build_shelf()
	if _home and _home.has_method("is_door_open") and not _home.is_door_open(&"Door_Storage"):
		_home.toggle_door(&"Door_Storage")
	Activities.say("The cupboard under the stairs is open. You shut it last night.")
	Activities.say("%s is on the boxes inside. You left it in the car." % String(clue(arrived).get("title", "it")).capitalize())


func _build_shelf() -> void:
	if _home == null:
		return
	if _shelf:
		_shelf.queue_free()
	_shelf = Node3D.new()
	_shelf.name = "CupboardThings"
	add_child(_shelf)
	var boxes := _home.find_child("Storage_Boxes", true, false) as MeshInstance3D
	if boxes == null:
		return
	# Lay things out in the boxes' own frame: `front` faces the cupboard door,
	# `side` runs across. Two rows of three at the front, M.'s journal at the back.
	var aabb := boxes.get_aabb()
	var top := boxes.global_transform * Vector3(aabb.get_center().x, aabb.end.y, aabb.get_center().z)
	var basis := boxes.global_basis.orthonormalized()
	var front := Vector3.FORWARD
	var door := _home.find_child("Door_Storage", true, false) as Node3D
	if door:
		var to := door.global_position - top
		to.y = 0.0
		var best := -INF
		for axis in [basis.x, -basis.x, basis.z, -basis.z]:
			if axis.dot(to) > best:
				best = axis.dot(to)
				front = axis
	var side := Vector3.UP.cross(front)
	for i in in_cupboard.size():
		var thing := MysteryProps.for_clue(in_cupboard[i], String(clue(in_cupboard[i]).get("cupboard", "")))
		_shelf.add_child(thing)
		thing.global_position = top + side * ((i % 3 - 1) * 0.12) + front * (0.17 - (i / 3) * 0.11)
		thing.global_rotation.y = atan2(front.x, front.z) + 0.4 * i
	# M.'s journal turns up with the first of them, at the back, its cover
	# opening along the wall.
	if in_cupboard.size() > 0:
		var journal := MJournal.new()
		_shelf.add_child(journal)
		journal.global_position = top - front * 0.14 + side * 0.08
		journal.global_rotation.y = atan2(side.x, side.z) - PI * 0.5


func _on_shed_tried() -> void:
	if has_key:
		has_key = false
		# The unlock sound plays from audio/scripts/game_hooks.gd on shed_unlocked.
		_home.unlock_shed()
		Activities.say("The key turns, stiff, then all at once.")
		return
	# Nobody's there. Something knocks back anyway (not in cozy mode).
	if is_night() and not Settings.cozy_mode:
		knocks += 1
		var audio := _audio()
		var knock := "oddity/odd_shed_knock" if audio and audio.has("oddity/odd_shed_knock") else "home/home_odd_wall_tapping"
		_play_at(knock, _shed_centre(), -6.0)
		if Discoveries.discover("oddity/shed_knock"):
			Activities.say("You knock. Something inside knocks back.")
		elif knocks % 3 == 0:
			Activities.say("Two knocks from inside. Then nothing.")


func _shed_centre() -> Vector3:
	var sheet := _home.find_child("Shed_Sheeted", true, false) as MeshInstance3D if _home else null
	if sheet:
		return (sheet.global_transform * sheet.get_aabb()).get_center()
	return _home.global_position if _home else Vector3.ZERO


func _check_shed() -> void:
	if is_solved or _home == null or not _home.get("shed_is_unlocked"):
		return
	if _player == null or _player.get("in_car") or not _player is Node3D:
		return
	var centre := _shed_centre()
	var to := (_player as Node3D).global_position - centre
	to.y = 0.0
	if to.length() < REVEAL_RADIUS:
		_reveal(true)


## Under the sheet in the shed. `story` plays the ending; false just rebuilds it
## when loading a solved game.
func _reveal(story: bool) -> void:
	if _shed_props or _home == null:
		return
	var sheet := _home.find_child("Shed_Sheeted", true, false) as MeshInstance3D
	if sheet == null:
		return
	# The sheet's own frame: x along the table, +Z toward the back wall.
	var box := sheet.get_aabb()
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	sheet.visible = false
	_shed_props = MysteryProps.build_shed(box.size * sheet.global_basis.get_scale())
	_shed_props.name = "ShedReveal"
	add_child(_shed_props)
	_shed_props.global_transform = Transform3D(sheet.global_basis.orthonormalized(), sheet.global_transform * base)
	_shed_props.add_child(_loop_player("oddity/odd_shed_interior_loop", 4.0, -6.0, &"Ambience"))
	if not story:
		return
	is_solved = true
	Discoveries.discover("mystery/solved")
	_bed_swell(40.0)
	for line in ending:
		Activities.say(String(line))
	Progression.grant_reward(REWARD, "what was in the shed")
	solved.emit()


# --- Sound hooks (each plays nothing if the sound isn't there yet) --------------------

func _audio() -> Node:
	return get_node_or_null(^"/root/Audio")


func _radio() -> Object:
	var audio := _audio()
	return audio.get("radio") if audio else null


func _current_station(radio: Object) -> String:
	var index: int = radio.get("station_index")
	var list: Array = radio.get("stations")
	if index == list.size():
		return "midnight"  # the unlisted one, after the others on the dial
	return String(list[index].get("id", "")) if index >= 0 and index < list.size() else ""


## The station's cue for a clue: odd_clue_01 to _07 get closer to the
## station as the arc goes on; any odd_clue variant if that one's missing.
func _clue_cue(id: String) -> String:
	var n := 0
	for i in clues.size():
		if clues[i].id == id:
			n = i + 1
	var ordered := "oddity/odd_clue_%02d" % n
	var audio := _audio()
	return ordered if audio and audio.has(ordered) else "oddity/odd_clue"


func _variant(sound: String) -> void:
	var audio := _audio()
	if audio and audio.has(sound):
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		player.stream = audio.variant(sound) if audio.has_method("variant") else audio.stream(sound)
		player.finished.connect(player.queue_free)
		add_child(player)
		player.play()


func _play_at(sound: String, at: Vector3, volume_db := 0.0) -> void:
	var audio := _audio()
	if audio and audio.has(sound):
		audio.play_at(sound, at, volume_db)


func _loop_player(sound: String, unit_size := 8.0, volume_db := -4.0, bus := &"SFX") -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = bus
	player.unit_size = unit_size
	player.max_distance = unit_size * 15.0  # falls silent a sensible way off
	player.volume_db = volume_db
	var audio := _audio()
	if audio and audio.has(sound):
		player.stream = audio.stream(sound, true)
		player.autoplay = true
	return player


## Fade the quiet mystery underscore in, hold it, and fade it out again.
func _bed_swell(hold: float) -> void:
	var audio := _audio()
	if audio == null or not audio.has("oddity/odd_mystery_bed_loop"):
		return
	if _bed == null:
		_bed = AudioStreamPlayer.new()
		_bed.bus = &"Music"
		_bed.stream = audio.stream("oddity/odd_mystery_bed_loop", true)
		_bed.volume_db = -40.0
		add_child(_bed)
	if not _bed.playing:
		_bed.play()
	if _bed_tween:
		_bed_tween.kill()
	_bed_tween = create_tween()
	_bed_tween.tween_property(_bed, "volume_db", -14.0, 4.0)
	_bed_tween.tween_interval(hold)
	_bed_tween.tween_property(_bed, "volume_db", -40.0, 6.0)
	_bed_tween.tween_callback(_bed.stop)


# --- Saving -------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"heard": heard, "found": Array(found), "last_found_day": last_found_day,
		"in_cupboard": Array(in_cupboard), "has_key": has_key, "solved": is_solved, "knocks": knocks}


func load_state(data: Dictionary) -> void:
	heard = String(data.get("heard", ""))
	found = PackedStringArray(data.get("found", []))
	last_found_day = int(data.get("last_found_day", -100))
	in_cupboard = PackedStringArray(data.get("in_cupboard", []))
	has_key = bool(data.get("has_key", false))
	is_solved = bool(data.get("solved", false))
	knocks = int(data.get("knocks", 0))
