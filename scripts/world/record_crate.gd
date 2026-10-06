class_name RecordCrate
extends Node
## The record crate and the record player in the lounge. Every song you hear
## on the radio lands in the crate as a record; the two themes are there from
## the start. Play them at home: "Play a record" at the player puts on the
## next one, "Look through the records" at the crate lets you pick. It stops
## when you leave the house.
##
## Uses the townhouse's own RecordPlayer and RecordCrate (spinning a Platter
## and showing Sleeve_1..12 if they have them); stand-ins at PLAYER_AT and
## CRATE_AT if it hasn't. Saved as "records".

signal record_added(id: String, title: String)
signal playing_changed(id: String)

const PLAYER_MODEL := "res://art/models/props/home/record_player.glb"
const CRATE_MODEL := "res://art/models/props/home/record_crate.glb"
const PROGRAMMES := ["cinquecento", "nottefm"]
## Records you have from the start: sound id -> title.
const STARTERS := {"mus_main_theme": "Little Shenton Lane", "mus_home_theme": "Home"}
## Stand-in places (townhouse frame: x across, y back from the street, z up):
## the deck on the lounge's TV unit, the crate on the floor at its end.
const PLAYER_AT := Vector3(0.22, 4.6, 0.6)
const CRATE_AT := Vector3(0.62, 4.88, 0.15)
const LEAVE_RANGE := 14.0

## Records in the crate, in the order you got them: [{id, title, station}].
var records: Array = []
## The record on now ("" for none).
var playing := ""

var _home: Node3D
var _player_node: Node3D
var _crate_node: Node3D
var _speaker: AudioStreamPlayer3D
var _platter: Node3D
var _picker: CanvasLayer
var _check := 0.0
var _titles := {}  # station -> {title: sound id}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the picker pauses the game
	SaveGame.register("records", self)
	for station in PROGRAMMES:
		var path := "res://audio/music/programme_%s.json" % station
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				var by_title := {}
				var titles: Dictionary = parsed.get("titles", {})
				for id: String in titles:
					by_title[titles[id]] = id
				_titles[station] = by_title
	for id: String in STARTERS:
		_add(id, STARTERS[id], "", false)
	_hook_radio.call_deferred()


func _exit_tree() -> void:
	SaveGame.unregister("records")


func save_state() -> Dictionary:
	return {"records": records.duplicate(true)}


func load_state(data: Dictionary) -> void:
	for r: Dictionary in data.get("records", []):
		_add(String(r.get("id", "")), String(r.get("title", "")), String(r.get("station", "")), false)
	_refresh_sleeves()


func has_record(id: String) -> bool:
	return records.any(func(r: Dictionary) -> bool: return r.id == id)


## A song heard on the radio: into the crate, if it's new.
func heard(station: String, title: String) -> void:
	var id: String = _titles.get(station, {}).get(title, "")
	if id != "":
		_add(id, title, station, true)


func _add(id: String, title: String, station: String, tell: bool) -> void:
	if id == "" or has_record(id):
		return
	records.append({"id": id, "title": title, "station": station})
	_refresh_sleeves()
	record_added.emit(id, title)
	if tell:
		Activities.say("\"%s\" is in your record crate now." % title)


func _hook_radio() -> void:
	var audio := get_node_or_null(^"/root/Audio")
	var radio: Object = audio.get("radio") if audio else null
	if radio and radio.has_signal("now_playing"):
		radio.now_playing.connect(func(station: String, title: String, _artist: String) -> void:
			heard(station, title))


# --- Playing -------------------------------------------------------------------------

## Put a record on (the next one after what's playing when `id` is empty).
func play(id := "") -> void:
	if records.is_empty() or _speaker == null:
		return
	if id == "":
		var at := -1
		for i in records.size():
			if records[i].id == playing:
				at = i
		id = records[(at + 1) % records.size()].id
	var audio := get_node_or_null(^"/root/Audio")
	if audio == null or not audio.has("music/" + id):
		return
	playing = id
	_speaker.stream = audio.stream("music/" + id)
	_speaker.play()
	_play_sound("home/home_record_needle")
	playing_changed.emit(id)


func stop() -> void:
	if playing == "":
		return
	playing = ""
	if _speaker:
		_speaker.stop()
	playing_changed.emit("")


func title_of(id: String) -> String:
	for r: Dictionary in records:
		if r.id == id:
			return r.title
	return id


func _process(delta: float) -> void:
	if _platter and playing != "":
		_platter.rotate_y(-delta * TAU * 33.3 / 60.0)
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		if _home:
			_build()
		return
	if playing != "" and _speaker:
		var walker := get_tree().root.find_child("Player", true, false) as Node3D
		var away: bool = walker == null or walker.get("in_car") != false \
			or walker.global_position.distance_to(_speaker.global_position) > LEAVE_RANGE
		if away:
			stop()


func _on_finished() -> void:
	if playing != "":
		play()


# --- The pieces ----------------------------------------------------------------------

func _build() -> void:
	_player_node = _piece(PLAYER_MODEL, "RecordPlayer", PLAYER_AT, true)
	_crate_node = _piece(CRATE_MODEL, "RecordCrate", CRATE_AT, false)
	_platter = _player_node.find_child("Platter", true, false) as Node3D
	var light := _player_node.find_child("Light", true, false) as Node3D
	if light:
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.2)
		glow.light_energy = 0.15
		glow.omni_range = 0.6
		light.add_child(glow)
	_speaker = AudioStreamPlayer3D.new()
	_speaker.name = "RecordSpeaker"
	_speaker.bus = &"Music"
	_speaker.unit_size = 6.0
	_speaker.max_distance = 30.0
	_speaker.position = Vector3.UP * 0.3
	_speaker.finished.connect(_on_finished)
	_player_node.add_child(_speaker)
	_player_node.add_child(_Spot.new(self, "player"))
	_crate_node.add_child(_Spot.new(self, "crate"))
	_refresh_sleeves()


## The townhouse's own piece (a mesh, used where it stands), the model at
## its empty, or a stand-in at `fallback`.
func _piece(path: String, empty: String, fallback: Vector3, is_player: bool) -> Node3D:
	var at := _home.find_child(empty, true, false) as Node3D
	if at is MeshInstance3D:
		var mesh := at as MeshInstance3D
		var top := mesh.global_transform * mesh.get_aabb()
		var anchor := Node3D.new()
		anchor.name = "Records_" + empty
		_home.add_child(anchor)
		anchor.global_position = Vector3(top.get_center().x, top.end.y, top.get_center().z)
		return anchor
	var node: Node3D
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as Node3D
		PS1Model.apply(node)
	else:
		node = _stand_in_player() if is_player else _stand_in_crate()
	node.name = "Records_" + empty
	_home.add_child(node)
	if at:
		node.global_transform = at.global_transform
	else:
		node.position = Vector3(fallback.x, fallback.z, -fallback.y)
		node.rotation.y = PI * 0.5  # face into the lounge, away from the side wall
	return node


## Show a sleeve in the crate for each record you have.
func _refresh_sleeves() -> void:
	if _crate_node == null:
		return
	for i in 12:
		var sleeve := _crate_node.find_child("Sleeve_%d" % (i + 1), true, false) as Node3D
		if sleeve:
			sleeve.visible = i < records.size()


func _stand_in_player() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.44, 0.08, 0.34), Vector3(0, 0.04, 0), Color(0.16, 0.15, 0.14))
	var platter := Node3D.new()
	platter.name = "Platter"
	platter.position = Vector3(-0.04, 0.085, 0)
	root.add_child(platter)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.01
	cyl.radial_segments = 16
	disc.mesh = cyl
	disc.material_override = PS1Material.make(Color(0.05, 0.05, 0.06))
	platter.add_child(disc)
	_box(platter, Vector3(0.1, 0.012, 0.02), Vector3(0, 0.004, 0), Color(0.8, 0.3, 0.2))  # the label
	_box(root, Vector3(0.02, 0.02, 0.2), Vector3(0.15, 0.1, 0.02), Color(0.7, 0.7, 0.68))  # the arm
	var light := Node3D.new()
	light.name = "Light"
	light.position = Vector3(0.17, 0.06, 0.17)
	root.add_child(light)
	return root


func _stand_in_crate() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.38, 0.3, 0.36), Vector3(0, 0.15, 0), Color(0.55, 0.4, 0.24))
	var colours := [Color(0.8, 0.3, 0.2), Color(0.2, 0.4, 0.6), Color(0.9, 0.75, 0.3), Color(0.3, 0.5, 0.3)]
	for i in 12:
		var sleeve := Node3D.new()
		sleeve.name = "Sleeve_%d" % (i + 1)
		sleeve.position = Vector3(0, 0.3, 0.14 - i * 0.025)
		root.add_child(sleeve)
		_box(sleeve, Vector3(0.31, 0.31, 0.006), Vector3(0, 0, 0), colours[i % colours.size()])
	return root


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = at
	mesh.material_override = PS1Material.make(color)
	parent.add_child(mesh)


func _play_sound(sound: String) -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio and audio.has(sound) and _speaker:
		audio.play_at(sound, _speaker.global_position, -6.0)


# --- Picking a record ----------------------------------------------------------------

func open_picker() -> void:
	if _picker:
		return
	_picker = CanvasLayer.new()
	_picker.layer = 8
	_picker.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_picker)  # on the window, not in the lo-fi world view
	var dim := UiStyle.backdrop()
	_picker.add_child(dim)
	var card: Array = UiStyle.centred_card(dim, Vector2(440, 0))
	var box: VBoxContainer = card[1]
	var head: Array = UiStyle.header(box, "Record crate", "music",
		"Playing: " + title_of(playing) if playing != "" else "%d records" % records.size())
	(head[2] as Button).pressed.connect(close_picker)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, minf(330.0, get_tree().root.get_visible_rect().size.y * 0.5))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ButtonGroup.new()
	var first: Button
	for r: Dictionary in records:
		var b := Button.new()
		b.theme_type_variation = &"ListButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = r.id == playing
		b.text = String(r.title)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id: String = r.id
		b.pressed.connect(func() -> void:
			close_picker()
			play(id))
		list.add_child(b)
		if first == null or r.id == playing:
			first = b
	if playing != "":
		var lift := Button.new()
		lift.text = "Lift the needle"
		lift.pressed.connect(func() -> void:
			close_picker()
			stop())
		box.add_child(lift)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	if first:
		first.grab_focus.call_deferred()


func close_picker() -> void:
	if _picker == null:
		return
	_picker.queue_free()
	_picker = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_picking() -> bool:
	return _picker != null


func _input(event: InputEvent) -> void:
	if _picker and event.is_action_pressed("pause"):
		close_picker()
		get_viewport().set_input_as_handled()


## The player and the crate, for OnFoot.
class _Spot extends Node3D:
	var crate: RecordCrate
	var kind := ""

	func _init(owner_crate: RecordCrate, what: String) -> void:
		crate = owner_crate
		kind = what
		name = "Use_" + what
		position = Vector3.UP * 0.1

	func _ready() -> void:
		add_to_group(&"interactables")

	func interact_point() -> Vector3:
		return global_position

	func interact_hint() -> String:
		if kind == "player":
			return "Lift the needle" if crate.playing != "" else "Play a record"
		return "Look through the records (%d)" % crate.records.size()

	func interact() -> void:
		if kind == "player":
			if crate.playing != "":
				crate.stop()
			else:
				crate.play()
		else:
			crate.open_picker()
