extends SceneTree
## Screenshots of every HUD and menu surface, for reviewing the UI style.
##
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/ui_screens.gd -- --no-save shots=/tmp/ui
##
## only=<name,name> shoots just those (names are the steps below).

var _shots := "/tmp/ui"
var _only := PackedStringArray()
var _main: Node
var _car: RigidBody3D
var _step := -1
var _frames := 0
var _steps: Array = []
var _title_layer: CanvasLayer  # the real title screen while it is shot


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
		elif arg.begins_with("only="):
			_only = arg.trim_prefix("only=").split(",")
	DirAccess.make_dir_recursive_absolute(_shots)
	# [name, setup, frames to wait, teardown]
	_steps = [
		["hud_driving", _hud_driving, 90, Callable()],
		["hud_help", func() -> void: _hud().get("_help").visible = true, 20,
			func() -> void: _hud().get("_help").visible = false],
		["hud_toast", func() -> void:
			_hud().toast("Discovered: Kings Park lookout. A good spot for a photo (P).")
			_set_time(17.6), 40, Callable()],
		["hud_night", func() -> void: _set_time(21.5), 60, Callable()],
		["pause", func() -> void: _node("PauseMenu").open(), 20, func() -> void: _node("PauseMenu").close()],
		["phone_jobs", func() -> void: _node("Phone").toggle(), 20, Callable()],
		["phone_progress", func() -> void: _phone_tab(1), 10, Callable()],
		["phone_leads", func() -> void: _phone_tab(2), 10, Callable()],
		["phone_stats", func() -> void: _phone_tab(3), 10, func() -> void: _node("Phone").toggle()],
		["workshop", _open_workshop, 20, Callable()],
		["workshop_tab2", func() -> void: _workshop_tab(1), 10, Callable()],
		["workshop_tab3", func() -> void: _workshop_tab(2), 10, func() -> void: _node("Workshop").close()],
		["journal_birds", func() -> void: _field("FieldJournalScreen").open(), 20, Callable()],
		["journal_place", func() -> void:
			var j: Node = _field("FieldJournalScreen")
			var fj: Node = root.get_node("FieldJournal")
			var h: Dictionary = fj.quiet_places()[0]
			root.get_node("Discoveries").discover(fj.place_key(h))
			j.set("_selected", "place:" + String(h.id))
			j.refresh(), 10, Callable()],
		["journal_fish", func() -> void:
			var j: Node = _field("FieldJournalScreen")
			j.set("_tab", "fish")
			j.refresh(), 10, func() -> void: _field("FieldJournalScreen").close()],
		["lab", func() -> void: _field("LabScreen").open(), 20, func() -> void: _field("LabScreen").close()],
		["tackle", func() -> void: _field("TackleScreen").open(), 20, func() -> void: _field("TackleScreen").close()],
		["catch_card", func() -> void:
			_set_time(9.0)
			_field("FishingScreen").open_card({"species": "tailor", "cm": 34.5, "kg": 0.52, "legal": true, "first": true}), 20,
			func() -> void: _field("FishingScreen").close_card()],
		["radio", func() -> void:
			var audio := root.get_node_or_null("Audio")
			if audio and audio.get("radio"):
				audio.radio.station_changed.emit("cinquecento", "Radio Cinquecento")
				audio.radio.now_playing.emit("t", "Vespa al Tramonto", "I Lambretti"), 20, Callable()],
		["binoculars", func() -> void:
			root.get_node("Discoveries").discover("field/binoculars")
			_field("Binoculars").open(), 60, func() -> void: _field("Binoculars").close()],
		["photo_mode", func() -> void: _node("PhotoMode").open(), 30, func() -> void: _node("PhotoMode").close()],
		["title", _title, 60, Callable()],
		["title_confirm", func() -> void:
			_title_layer.get("_menu").visible = false
			_title_layer.get("_confirm").visible = true, 10, func() -> void:
			_title_layer.get("_confirm").visible = false
			_title_layer.get("_menu").visible = true],
		["title_settings", func() -> void: _title_layer.call("_settings"), 20, func() -> void:
			_node("PauseMenu").close()
			_title_layer.call("_leave")],
		["on_foot", _get_out, 120, Callable()],
		["wake_card", func() -> void:
			_main.get_node("LoFi/SubViewport/World/Player").call("_ask_when_to_wake"), 20, func() -> void:
			var choice: Control = _main.get_node("LoFi/SubViewport/World/Player").call("wake_choice")
			(choice.get_child(2) as Button).pressed.emit()],
	]


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_frames = -240  # settle: streaming, the field world's screens
		return false
	_frames += 1
	if _step == -1:
		if _frames > 0:
			_next()
		return false
	if _step >= _steps.size():
		return true
	if _frames >= int(_steps[_step][2]):
		var name: String = _steps[_step][0]
		root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))
		print("shot ", name)
		var teardown: Callable = _steps[_step][3]
		if teardown.is_valid():
			teardown.call()
		_next()
	return false


func _next() -> void:
	_step += 1
	while _step < _steps.size() and not _only.is_empty() and not _only.has(_steps[_step][0]):
		_step += 1
	_frames = 0
	if _step < _steps.size():
		(_steps[_step][1] as Callable).call()


func _node(path: String) -> Node:
	return _main.get_node(path)


func _hud() -> Node:
	return _node("HUD")


## The field screens sit on the current scene (the root, under this script).
func _field(name: String) -> Node:
	var n := root.get_node_or_null(name)
	return n if n else _main.get_node_or_null(name)


func _set_time(hours: float) -> void:
	root.get_node("GameClock").set_time(hours)


func _hud_driving() -> void:
	_set_time(10.0)
	root.get_node("Settings").set("show_help", false)
	_hud().get("_help").visible = false
	_car.set("rpm", 3400.0)


func _phone_tab(i: int) -> void:
	(_node("Phone").get("_tabs") as TabContainer).current_tab = i


func _workshop_tab(i: int) -> void:
	var tabs := _node("Workshop").get("_tabs") as TabContainer
	var shown := 0
	for t in tabs.get_tab_count():
		if not tabs.is_tab_hidden(t):
			if shown == i:
				tabs.current_tab = t
				return
			shown += 1


func _open_workshop() -> void:
	var best: Node = null
	for spot in get_nodes_in_group(&"workshop_spots"):
		if best == null or spot.kinds.size() > best.kinds.size():
			best = spot
	if best:
		_node("Workshop").open(best)


func _get_out() -> void:
	var player := _main.get_node_or_null("LoFi/SubViewport/World/Player")
	if player and player.has_method("get_out"):
		player.get_out()


func _title() -> void:
	_set_time(18.4)
	_title_layer = load("res://scripts/ui/title_screen.gd").new()
	_main.add_child(_title_layer)
