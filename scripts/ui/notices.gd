extends CanvasLayer
## Notices (autoload): one card at the top of the screen for anything the
## player should know just happened: a new bird, a place found, a challenge
## done, a job paid, a clue. The event's sound plays as its card appears, so a
## jingle never plays with nothing on screen to say what it was.
##
##   Notices.post("Rainbow bee-eater", "species")
##   Notices.post("Gold. 912 points in 8.2 s.", "medal", "", "Parking: Mends St")
##
## Activities.say() and the HUD's toast() land here too. Without a kind the
## card's look is guessed from how the text starts (PREFIXES), and it stays
## quiet, since whoever said it played their own sound.
##
## Cards queue. Each stays up long enough to read (longer for longer text) and
## steps aside sooner when others are waiting. Nothing shows on the title
## screen, in menus or in photo mode; the queue waits.
##
## Autosaves are silent: a small "Saved" mark shows above the dial.

## [heading, icon, accent, sound, bus, volume_db] for each kind of notice.
## An empty heading shows the text alone.
const KINDS := {
	"info": ["", "note", UiStyle.SUN, "", "", 0.0],
	"place": ["Discovered", "pin", UiStyle.TEAL, "ui/ui_badge_pickup", "UI", -3.0],
	"species": ["New for the journal", "bird", UiStyle.TEAL, "music/mus_field_new_species", "Music", -4.0],
	"fish": ["New for the journal", "fish", UiStyle.TEAL, "", "", 0.0],
	"quiet": ["A quiet place", "eye", UiStyle.TEAL, "field/quiet_place|music/mus_field_new_species", "UI", -4.0],
	"photo": ["Photo spot", "camera", UiStyle.TEAL, "ui/ui_badge_pickup", "UI", -3.0],
	"badge": ["500 badge", "star", UiStyle.RED, "ui/ui_badge_pickup", "UI", -3.0],
	"medal": ["", "star", UiStyle.SUN, "music/mus_sting_complete", "Music", 0.0],
	"result": ["", "flag", UiStyle.TEAL, "ui/ui_checkpoint", "UI", -4.0],
	"career": ["Career challenge done", "star", UiStyle.SUN, "ui/ui_badge_pickup", "UI", 0.0],
	"progress": ["Career", "star", UiStyle.TEAL, "", "", 0.0],
	"tier": ["New tier", "flag", UiStyle.RED, "music/mus_sting_tier_unlock", "Music", 0.0],
	"reward": ["Unlocked", "key", UiStyle.SUN, "ui/ui_badge_pickup", "UI", -3.0],
	"job": ["Job", "flag", UiStyle.RED, "", "", 0.0],
	"paid": ["Job done", "money", UiStyle.GOOD, "music/mus_sting_complete", "Music", 0.0],
	"failed": ["Job", "flag", UiStyle.RED, "music/mus_sting_failed", "Music", 0.0],
	"jobs": ["New jobs", "phone", UiStyle.TEAL, "ui/ui_job_offered", "UI", -8.0],
	"fine": ["Parking fine", "money", UiStyle.RED, "ui/ui_phone_notify", "UI", -3.0],
	"car": ["Your car", "wrench", UiStyle.RED, "", "", 0.0],
	"find": ["Found", "wrench", UiStyle.SUN, "oddity/odd_discovery_sting", "SFX", -8.0],
	"classic": ["Barn find", "car", UiStyle.SUN, "ui/ui_badge_pickup", "UI", -3.0],
	"mystery": ["", "note", UiStyle.BLUE_INK, "oddity/odd_clue", "SFX", 0.0],
	"key": ["", "key", UiStyle.BLUE_INK, "oddity/odd_key_found", "Music", 0.0],
	"odd": ["", "eye", UiStyle.BLUE_INK, "oddity/odd_discovery_sting", "SFX", -6.0],
	"dawn": ["", "sun", UiStyle.SUN, "music/mus_field_dawn", "Music", -4.0],
	"dusk": ["", "moon", UiStyle.SUN, "music/mus_field_dusk", "Music", -4.0],
}

## Text said without a kind: [starts with, kind, icon or "" for the kind's].
const PREFIXES := [
	["Discovered", "place", ""],
	["Challenge done", "career", ""],
	["Tier complete", "tier", ""],
	["Photo spot", "photo", ""],
	["Scenic drive", "result", ""],
	["Fuel", "car", "fuel"],
	["Out of fuel", "car", "fuel"],
	["Found a 500 badge", "badge", ""],
	["Found a ", "classic", ""],
	["New barn-find", "classic", ""],
	["Found:", "find", ""],
	["Tyres", "car", ""],
	["Brakes", "car", ""],
	["Oil", "car", ""],
	["Something's due", "car", ""],
	["Your binoculars", "info", "binoculars"],
	["Binoculars", "info", "binoculars"],
	["Parking fine", "fine", ""],
	["New for the journal", "species", ""],
	["A quiet place", "quiet", ""],
	["A quiet spot", "quiet", "fish"],
	["Fishing spot", "place", "fish"],
	["You beat the train", "medal", ""],
	["Racing the train", "result", ""],
	["The train", "result", ""],
]

## Seconds a card stays up: a floor, plus reading time for the words.
const MIN_SECONDS := 3.5
const MAX_SECONDS := 8.0
const CHARS_PER_SECOND := 16.0
## With others waiting, a card can leave after this share of its time.
const HURRY := 0.6
const TOP := 18.0
const WIDTH := 500.0
## No sounds this long after a load, while saved state replays its signals.
const QUIET_AFTER_LOAD_S := 1.5

var _queue: Array[Dictionary] = []
var _current := {}
var _shown_for := 0.0
var _fade := 0.0
var _quiet_until := 0.0
var _saved_for := 0.0
var _phone: Node

var _card: PanelContainer
var _stripe: ColorRect
var _icon: TextureRect
var _heading: Label
var _text: Label
var _saved: PanelContainer


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_quiet_until = _now() + QUIET_AFTER_LOAD_S
	SaveGame.loaded.connect(func(_p) -> void: _quiet_until = _now() + QUIET_AFTER_LOAD_S)
	SaveGame.saved.connect(_on_saved)
	_listen.call_deferred()


## Put a notice up. `kind` picks its heading, icon, colour and sound (KINDS);
## `sound` replaces the kind's ("-" for none, "a|b" for b when a isn't there)
## and `bus` its bus; `heading` replaces its heading; `picture` replaces the
## icon (a bird's field-guide plate, say). The same text twice in a row shows
## once.
func post(text: String, kind := "", sound := "", heading := "", bus := "", picture: Texture2D = null) -> void:
	text = text.strip_edges()
	if text == "":
		return
	var guessed := kind == ""
	var icon := ""
	if guessed:
		kind = "info"
		for p: Array in PREFIXES:
			if text.begins_with(p[0]):
				kind = p[1]
				icon = p[2]
				break
	var k: Array = KINDS.get(kind, KINDS.info)
	if sound == "" and not guessed:
		sound = k[3]
	var n := {
		"text": text, "kind": kind,
		"heading": heading if heading != "" else String(k[0]),
		"icon": icon if icon != "" else String(k[1]), "picture": picture,
		"accent": k[2],
		"sound": "" if sound == "-" else sound,
		"bus": bus if bus != "" else (k[4] if k[4] != "" else "UI"), "db": k[5],
	}
	# Said twice (a say() and a signal for the same thing): keep the first.
	if _current.get("text", "") == text:
		return
	for q in _queue:
		if q.text == text:
			return
	_queue.append(n)


## Every card currently waiting, oldest first (for tests).
func pending() -> Array[Dictionary]:
	return _queue


## The card on screen now, or {}.
func showing() -> Dictionary:
	return _current


## Drop everything waiting and on screen (tests, starting a new game).
func clear() -> void:
	_queue.clear()
	_current = {}
	_fade = 0.0
	_card.visible = false


static func seconds_for(text: String) -> float:
	return clampf(2.0 + text.length() / CHARS_PER_SECOND, MIN_SECONDS, MAX_SECONDS)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Not over the title screen, menus or photo mode; the queue waits.
func _held() -> bool:
	return get_tree().paused or SaveGame.hold


func _process(delta: float) -> void:
	if _jobs_told:
		_check_phone()
	var held := _held()
	visible = not held
	if held:
		return
	_update_saved(delta)
	if _current.is_empty():
		if _queue.is_empty():
			return
		_show(_queue.pop_front())
	_shown_for += delta
	if _shown_for < 0.3:
		_card.reset_size()  # wrapped text settles over the first frames
	var full := seconds_for(_current.text)
	var leave := full * HURRY if not _queue.is_empty() else full
	var fade_in := clampf(_shown_for / 0.25, 0.0, 1.0)
	var fade_out := clampf((leave - _shown_for) / 0.4, 0.0, 1.0)
	_card.modulate.a = minf(fade_in, fade_out)
	_card.position.y = TOP - 16.0 * (1.0 - ease(fade_in, 0.4))
	_place()
	if _shown_for >= leave:
		_current = {}
		_card.visible = false


func _show(n: Dictionary) -> void:
	_current = n
	_shown_for = 0.0
	_heading.text = n.heading
	_heading.visible = n.heading != ""
	_heading.add_theme_color_override("font_color", (n.accent as Color).darkened(0.15))
	_stripe.color = n.accent
	_icon.texture = n.picture if n.picture else UiStyle.icon(n.icon, 34, UiStyle.INK, Vector2.ZERO, n.accent)
	_text.text = n.text
	var width := UiStyle.BODY_FONT.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF if width < WIDTH - 70 else TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 0.0 if width < WIDTH - 70 else WIDTH - 70
	_card.size = Vector2.ZERO  # shrink to the new text
	_card.modulate.a = 0.0
	_card.visible = true
	if n.sound != "" and _now() >= _quiet_until:
		var audio := get_node_or_null(^"/root/Audio")
		if audio and audio.has_method("has"):
			for s in String(n.sound).split("|"):
				if audio.has(s):
					audio.play_2d(s, n.bus, n.db)
					break


## Centred at the top, or beside the controls card while that's up. If that
## would run into the job and challenge card, it drops in under that instead.
func _place() -> void:
	var view := _card.get_parent_area_size()
	var left := (view.x - _card.size.x) * 0.5
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method("help_right") and hud.visible:
		var help_right: float = hud.help_right()
		if help_right > 0.0:
			left = maxf(left, help_right + 16.0)
		var challenge: Rect2 = hud.challenge_rect()
		if challenge.has_area() and left + _card.size.x > challenge.position.x - 12.0:
			left = challenge.end.x - _card.size.x
			_card.position.y += challenge.end.y + 12.0 - TOP
	_card.position.x = left


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.chip(14)
	style.content_margin_left = 0
	_card.add_theme_stylebox_override("panel", style)
	_card.visible = false
	root.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	# A band of the notice's colour down the left edge, like a tab in a notebook.
	_stripe = ColorRect.new()
	_stripe.custom_minimum_size = Vector2(7, 0)
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_stripe)
	_icon = UiStyle.icon_rect("note", 34)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	_heading = UiStyle.label(words, "", "SectionLabel", 13)
	_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text = UiStyle.label(words, "", "", 19)
	# The little "Saved" mark above the dial (the minimap has the bottom left).
	_saved = PanelContainer.new()
	_saved.theme_type_variation = &"ChipPanel"
	_saved.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saved.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_saved.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_saved.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_saved.offset_right = -16
	_saved.offset_left = -16
	_saved.offset_top = -236
	_saved.offset_bottom = -236
	_saved.visible = false
	root.add_child(_saved)
	var saved_row := HBoxContainer.new()
	saved_row.add_theme_constant_override("separation", 6)
	saved_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saved.add_child(saved_row)
	saved_row.add_child(UiStyle.icon_rect("check_on", 16, UiStyle.INK, UiStyle.GOOD))
	UiStyle.label(saved_row, "Saved", "", 14).autowrap_mode = TextServer.AUTOWRAP_OFF


# --- autosaves -------------------------------------------------------------------------------

## A save from the pause menu clicks (the menu says "Saved"); an autosave just
## shows the mark for a moment, with no sound.
func _on_saved(_path: String) -> void:
	if get_tree().paused:
		var audio := get_node_or_null(^"/root/Audio")
		if audio and audio.has_method("ui"):
			audio.ui("ui_save_confirmed")
	elif not SaveGame.hold:
		_saved_for = 2.5


func _update_saved(delta: float) -> void:
	_saved_for = maxf(_saved_for - delta, 0.0)
	_saved.visible = _saved_for > 0.0
	_saved.modulate.a = clampf(_saved_for / 0.5, 0.0, 1.0)


# --- what the game tells you -----------------------------------------------------------------

## The events that get a card, wired here so each comes with its sound.
func _listen() -> void:
	Activities.message.connect(post)
	Activities.photo_spot_found.connect(func(_id: String, title: String) -> void:
		post("%s (%d of %d)" % [title, Activities.photo_spots_found(), Activities.PHOTO_SPOTS_TOTAL], "photo"))
	Activities.scenic_finished.connect(func(_id: String, title: String) -> void:
		post("%s. Nice one." % title, "result", "ui/ui_badge_pickup", "Scenic drive done"))
	Jobs.job_started.connect(func(job: Dictionary) -> void: post(String(job.title), "job", "-", "Job started"))
	Jobs.job_completed.connect(func(job: Dictionary, pay: int, summary: String) -> void:
		post(summary, "paid" if pay > 0 else "result", "", "Job done" if job.get("type", "") != "trial" else "Time trial"))
	Jobs.job_abandoned.connect(func(job: Dictionary) -> void:
		post(String(job.get("title", "The job")) + ". Called off.", "failed"))
	Jobs.place_discovered.connect(func(site: JobSite) -> void: post(site.label(), "place"))
	if Jobs.has_signal("offers_refreshed"):
		Jobs.offers_refreshed.connect(_on_offers)
	Progression.challenge_completed.connect(func(_tier: int, challenge: Dictionary) -> void:
		post(String(challenge.title), "career"))
	Progression.tier_completed.connect(func(index: int, tier: Dictionary) -> void:
		var names := PackedStringArray()
		for car in Progression.cars_unlocked_at(index + 1):
			names.append(car.name)
		var cars := " The car yard has the %s for you." % " and ".join(names) if not names.is_empty() else ""
		post("%s. Jobs pay better now.%s" % [tier.title, cars], "tier"))
	Progression.reward_unlocked.connect(func(reward: Dictionary) -> void:
		var extra := ". Fit it in any workshop's Extras tab." if reward.get("kind", "") in ["trinket", "livery"] else ""
		post("%s%s" % [reward.title, extra], "reward", "", String(reward.get("why", "Unlocked")).capitalize()))
	Progression.stat_changed.connect(_on_stat)
	Classics.rumour_heard.connect(func(_car: String, _text: String) -> void:
		post("Check Leads on your phone (Tab / X).", "classic", "", "New barn-find rumour"))
	Classics.wreck_found.connect(func(car_id: String) -> void:
		var car_name := String(CarCatalogue.get_car(car_id).get("name", "classic"))
		# "An Abarth 595 SS", "A Nuova 500" ("A 500 F" reads "a five hundred").
		var article := "An" if car_name.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "A"
		post("%s %s. It's on the bench at home." % [article, car_name], "classic",
				"music/mus_sting_barn_find|ui/ui_badge_pickup", "", "Music"))
	Classics.restored.connect(func(car_id: String, _finish: String) -> void:
		post("The %s is finished. Take it out from the Cars tab at home." % CarCatalogue.get_car(car_id).get("name", "classic"), "classic",
				"music/mus_sting_restored|ui/ui_badge_pickup", "Restored", "Music"))
	Discoveries.discovered.connect(func(id: String) -> void:
		if id.begins_with("spot/"):
			var spot := get_tree().get_root().find_child("Photo_" + id.substr(5), true, false)
			post("%s. A good spot for a photo (P)." % (spot.title if spot else "A photo spot"), "photo", "", "Discovered")
		elif id.begins_with("badge/"):
			post("%d of %d found" % [Collectible.found_count(), Collectible.TOTAL], "badge"))
	Discoveries.discovered.connect(func(_id: String) -> void: _on_stat("discoveries", 0.0))
	GameClock.hour_changed.connect(_on_hour)


## The job board refreshes every few hours. Say so once, then not again
## until the phone has been opened.
var _jobs_told := false


func _on_offers() -> void:
	if Jobs.offers.is_empty() or not Jobs.active.is_empty() or _jobs_told:
		return
	_jobs_told = true
	post("Have a look on your phone (Tab / X).", "jobs")


## Once the phone's been opened, the next fresh board gets a notice again.
func _check_phone() -> void:
	if not is_instance_valid(_phone):
		_phone = get_tree().get_first_node_in_group(&"phone")
	if _phone and _phone.is_open():
		_jobs_told = false


## Counters a career challenge in the current tier is waiting on: a small
## "3 of 10" card as each one ticks over (not for money or distance, which
## tick all the time).
const QUIET_STATS := ["earned", "km_driven", "km_tier_car", "litres_bought"]


func _on_stat(stat: String, value: float) -> void:
	if stat in QUIET_STATS:
		return
	for challenge: Dictionary in Progression.current_tier().get("challenges", []):
		if challenge.stat != stat or Progression.is_done(challenge):
			continue
		var target := float(challenge.target)
		value = Progression.get_stat(stat)
		if value < target and value == floorf(value):
			post("%s: %d of %d" % [challenge.title, int(value), int(target)], "progress")


## Dawn and dusk: the light turning, with the music cue that marks it (the
## way Dredge marks the turn of the day). Only in the quiet (radio off, no
## job on) and only when the clock ran there, not when sleep skipped past.
const DAWN_HOUR := 6
const DUSK_HOUR := 19
var _last_hour := -1


func _on_hour(hour: int) -> void:
	var ran := _last_hour >= 0 and (_last_hour + 1) % 24 == hour
	_last_hour = hour
	if not ran or not Jobs.active.is_empty():
		return
	var radio = Audio.get("radio")
	if radio and radio.has_method("is_on") and radio.is_on():
		return
	match hour:
		DAWN_HOUR:
			post("First light.", "dawn")
		DUSK_HOUR:
			post("The sun's going down.", "dusk")
