extends SceneTree
## Screenshots of the notices (one of every kind, cropped into one sheet) and
## of the challenge card, for reviewing them:
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
##     --script res://tools/notice_sheet.gd -- --no-save shots=/tmp/notices
##
## Writes notices_sheet.png plus full-screen shots (scene_*.png).

const SAMPLES := [
	["Rainbow bee-eater", "species", ""],
	["Kings Park lookout", "place", ""],
	["Lake Monger hide. Nobody comes here. It's in the journal.", "quiet", ""],
	["Mends St jetty. It's in the journal.", "place", "Fishing spot"],
	["Jacob's Ladder. A good spot for a photo (P).", "photo", "Discovered"],
	["12 of 40 found", "badge", ""],
	["Odd jobs", "career", ""],
	["Getting your eye in: 6 of 15", "progress", ""],
	["Known around town. Jobs pay better now.", "tier", ""],
	["Fluffy dice. Fit it in any workshop's Extras tab.", "reward", "1,000 km"],
	["Gold. 912 points in 8.2 s. Nobody parks a 500 like you.", "medal", "Parking: Mends St"],
	["No medal. 344 points in 31.0 s, 2 bumps. Try again.", "result", "Parking: Mends St"],
	["Your nose got past the front carriage.", "medal", "You beat the train"],
	["Kings Park at sunset. Nice one.", "result", "Scenic drive done"],
	["Flowers to Subiaco: $84, on time.", "paid", "Job done"],
	["Flowers to Subiaco. Called off.", "failed", ""],
	["Have a look on your phone (Tab / X).", "jobs", ""],
	["$60 (parked in a traffic lane)", "fine", ""],
	["Fuel's low. Find a servo.", "", ""],
	["Finned sump. It's yours to fit in the workshop.", "find", ""],
	["A 1968 500F. It's on the bench at home.", "classic", ""],
	["There's already a page about this in the journal. It isn't in your handwriting.", "mystery", ""],
	["The shed. It's the key to the shed.", "key", ""],
	["The radio finds a station that isn't on the dial.", "odd", ""],
	["First light.", "dawn", ""],
	["The sun's going down.", "dusk", ""],
]

var _shots := "/tmp/notices"
var _main: Node
var _car: RigidBody3D
var _frames := -240
var _i := -1
var _crops: Array[Image] = []
var _scenes: Array = []
var _scene := -1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			_shots = arg.trim_prefix("shots=")
	DirAccess.make_dir_recursive_absolute(_shots)
	_scenes = [
		["scene_notice_driving", func() -> void:
			_notices().post("Rainbow bee-eater", "species"), 40],
		["scene_parking_card", _parking, 50],
		["scene_parking_result", func() -> void:
			_notices().post("Gold. 912 points in 8.2 s. Nobody parks a 500 like you.", "medal", "", "Parking: Mends St"), 40],
		["scene_scenic_card", _scenic, 50],
		["scene_train_card", _train, 50],
		["scene_job_card", _job, 50],
		["scene_notice_with_controls", func() -> void:
			_hud().get("_help").visible = true
			_notices().post("Kings Park lookout", "place"), 40],
		["scene_binoculars", func() -> void:
			_hud().get("_help").visible = false
			root.get_node("Discoveries").discover("field/binoculars")
			var b := _field("Binoculars")
			if b:
				b.open()
			_notices().post("Rainbow bee-eater", "species"), 70],
		["scene_saved", func() -> void:
			var b := _field("Binoculars")
			if b:
				b.close()
			root.get_node("SaveGame").saved.emit("user://test.save"), 20],
	]


func _notices() -> Node:
	return root.get_node("Notices")


func _hud() -> Node:
	return _main.get_node("HUD")


func _field(name: String) -> Node:
	var n := root.get_node_or_null(name)
	return n if n else _main.get_node_or_null(name)


func _process(_delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		root.get_node("GameClock").set_time(10.0)
		root.get_node("Settings").set("show_help", false)
		return false
	_frames += 1
	if _frames == -1:
		_hud().get("_help").visible = false
		_notices().clear()
	if _frames < 0:
		return false
	# One notice of each kind, cropped.
	if _i < SAMPLES.size():
		if _i >= 0 and _frames == 30:
			var card: Control = _notices().get("_card")
			var r := Rect2i(card.get_global_rect().grow(8))
			_crops.append(root.get_texture().get_image().get_region(r))
		if _i == -1 or _frames == 30:
			_i += 1
			_frames = 0
			_notices().clear()
			if _i < SAMPLES.size():
				var s: Array = SAMPLES[_i]
				_notices().post(s[0], s[1], "", s[2])
			else:
				_save_sheet()
		return false
	# Then the full-screen scenes.
	if _scene == -1 or _frames >= int(_scenes[_scene][2]):
		if _scene >= 0:
			root.get_texture().get_image().save_png(_shots.path_join(_scenes[_scene][0] + ".png"))
			print("shot ", _scenes[_scene][0])
		_scene += 1
		_frames = 0
		_notices().clear()
		_end_challenges()
		if _scene >= _scenes.size():
			return true
		(_scenes[_scene][1] as Callable).call()
	return false


func _save_sheet() -> void:
	var cols := 2
	var w := 0
	var h := 0
	for c in _crops:
		w = maxi(w, c.get_width())
		h = maxi(h, c.get_height())
	var rows := ceili(_crops.size() / float(cols))
	var sheet := Image.create(w * cols + 24 * (cols + 1), (h + 16) * rows + 16, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("5b6b62"))
	for i in _crops.size():
		var c: Image = _crops[i]
		c.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(24 + (i % cols) * (w + 24), 16 + (i / cols) * (h + 16))
		sheet.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), at)
	sheet.save_png(_shots.path_join("notices_sheet.png"))
	print("shot notices_sheet (%d kinds)" % _crops.size())


func _parking() -> void:
	var bay: Node3D = get_nodes_in_group(&"parking_bays")[0]
	bay.global_transform = Transform3D(_car.global_basis, _car.global_position + _car.global_basis.z * -9.0 + _car.global_basis.x * 1.5 + Vector3.DOWN * 0.45)
	bay.set("_car", _car)
	bay.set("_active", true)
	bay.set("_time", 7.0)
	bay.set("_bumps", 1)


func _scenic() -> void:
	var drive: Node = get_nodes_in_group(&"scenic_drives")[0]
	drive.set("_car", _car)
	drive.start()
	drive.set("_next", 3)


func _train() -> void:
	for n in get_nodes_in_group(&"challenges"):
		if "_lead" in n:
			var dummy := Node3D.new()
			n.add_child(dummy)
			n.set("_racing", dummy)
			n.set("_lead", -23.0)


func _job() -> void:
	var jobs := root.get_node("Jobs")
	jobs.refresh_offers()
	if not jobs.offers.is_empty():
		jobs.accept(jobs.offers[0])


func _end_challenges() -> void:
	for n in get_nodes_in_group(&"challenges"):
		if "_lead" in n:  # the train race
			n.set("_racing", null)
		elif n.has_method("stop"):  # scenic drives
			n.stop()
		else:
			n.set("_active", false)
	var jobs := root.get_node("Jobs")
	if not jobs.active.is_empty():
		jobs.abandon()
