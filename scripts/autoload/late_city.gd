extends Node
## The late city (autoload: LateCity): Perth as it was on the night of 11 July
## 1979, leaking into ours after midnight. Every weird event in the story runs
## through here so they all look and sound the same, and players learn the
## signs early (STORY.md, sections 4 and 5):
##
##   in      a cassette deck clicking on and whirring
##   during  sodium-orange light, the street's sound gone or gone to tape, a
##           little cassette counter turning next to the dash
##   out     the deck clunking off
##
## Events are nodes in the world (scripts/world/late_city/) that ask to begin
## and end here. Other code reads presence(), flicker_level() and the event
## signals (STORY_API.md).
##
##   if LateCity.allowed_now() and LateCity.begin(&"empty_road"):
##       LateCity.fade_mute(1.0, 2.5)
##   ...
##   LateCity.end(&"empty_road")

signal event_started(id: StringName)
signal event_ended(id: StringName)

## Late-city events happen between midnight and this hour, as a rule.
const NIGHT_TO := 4.5
## The 1979 sodium streetlamp colour the light shifts to.
const SODIUM := Color(1.0, 0.7, 0.4)
## How far (m) from a late-city place its presence reaches, from act 3.
const PLACE_RADIUS := 260.0
## Buses that go quiet when an event takes the street's sound away. Engine,
## Tyres and Cabin (your own car) and UI stay.
const MUTE_BUSES := ["Ambience", "Weather", "Vehicles", "SFX", "Music", "Radio"]
## Buses that go to tape (a little flat, wobbling) while the look is on.
const TAPE_BUSES := ["Ambience", "SFX", "Radio"]
const SHIMMER_SHADER := preload("res://shaders/late_city_shimmer.gdshader")
## Recordings dropped in here by the audio thread replace the made-up sounds.
const SOUND_START := "late/late_tape_start"
const SOUND_STOP := "late/late_tape_stop"
const SOUND_FLICKER := "late/late_flicker"
const SOUND_HISS := "late/late_tape_hiss_loop"

## The event running now, or &"".
var event: StringName = &""

var _mute := 0.0
var _look := 0.0
var _mute_tween: Tween
var _look_tween: Tween
var _amps := {}               # bus -> AudioEffectAmplify
var _pitches := {}            # bus -> AudioEffectPitchShift
var _grade_layer: CanvasLayer
var _grade: ColorRect
var _counter: TapeCounter
var _hiss: AudioStreamPlayer
var _sounds := {}             # name -> AudioStream (made up on first use)
var _shimmers := {}           # rounded amount -> ShaderMaterial
var _places: Array[Vector3] = []
var _places_read := false
var _wobble := 0.0


func _ready() -> void:
	# After the environment and everything else, so the look has the last word.
	process_priority = 100
	_grade_layer = CanvasLayer.new()
	_grade_layer.layer = 1
	add_child(_grade_layer)
	_grade = ColorRect.new()
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_grade.material = mul
	_grade.color = Color.WHITE
	_grade.visible = false
	_grade_layer.add_child(_grade)
	var counter_layer := CanvasLayer.new()
	counter_layer.layer = 2
	add_child(counter_layer)
	_counter = TapeCounter.new()
	counter_layer.add_child(_counter)
	_hiss = AudioStreamPlayer.new()
	_hiss.bus = "SFX"
	_hiss.volume_db = -80.0
	add_child(_hiss)
	_add_bus_effects.call_deferred()


func _exit_tree() -> void:
	if _hiss:
		_hiss.stop()
		_hiss.stream = null


func _process(delta: float) -> void:
	_wobble += delta
	_counter.turning = active()
	if _look > 0.001:
		_grade.visible = true
		_grade.color = Color.WHITE.lerp(SODIUM, _look * 0.55)
		# Tape: a little flat, drifting slowly up and down.
		var pitch := 1.0 - 0.035 * _look + 0.012 * _look * sin(_wobble * 1.7)
		for bus in _pitches:
			(_pitches[bus] as AudioEffectPitchShift).pitch_scale = pitch
	else:
		_grade.visible = false


# --- Events -------------------------------------------------------------------

func active() -> bool:
	return event != &""


## Start an event: the deck clicks on and the counter appears. False if one is
## already running.
func begin(id: StringName) -> bool:
	if active():
		return false
	event = id
	_play_2d(SOUND_START, -4.0)
	_counter.show_counter(true)
	event_started.emit(id)
	return true


## End the event: the deck clunks off, the look and the sound come back.
func end(id: StringName) -> void:
	if event != id:
		return
	event = &""
	_play_2d(SOUND_STOP, -4.0)
	_counter.show_counter(false)
	fade_mute(0.0, 1.5)
	fade_look(0.0, 1.5)
	set_hiss(false)
	event_ended.emit(id)


## Take the street's sound away (1) or give it back (0), over `seconds`.
func fade_mute(to: float, seconds: float) -> void:
	if _mute_tween:
		_mute_tween.kill()
	_mute_tween = create_tween()
	_mute_tween.tween_method(_set_mute, _mute, to, maxf(seconds, 0.01))


## The sodium light and the tape sound, 0..1, over `seconds`.
func fade_look(to: float, seconds: float) -> void:
	if _look_tween:
		_look_tween.kill()
	_look_tween = create_tween()
	_look_tween.tween_method(_set_look, _look, to, maxf(seconds, 0.01))


func mute_amount() -> float:
	return _mute


func look_amount() -> float:
	return _look


## The soft tape hiss under everything (not with the empty road: only the
## engine is left there).
func set_hiss(on: bool) -> void:
	if on:
		if not _hiss.playing:
			_hiss.stream = _sound(SOUND_HISS)
			_hiss.play()
		var tw := create_tween()
		tw.tween_property(_hiss, "volume_db", -16.0, 1.5)
	elif _hiss.playing:
		var tw := create_tween()
		tw.tween_property(_hiss, "volume_db", -80.0, 1.2)
		tw.tween_callback(_hiss.stop)


## The section-5 rules: it's late enough (between midnight and NIGHT_TO, or
## any time after dark with after_midnight off), the map has finished
## loading round you, no ordinary job is running, the game isn't paused and
## nothing else is happening.
func allowed_now(after_midnight := true) -> bool:
	if active() or get_tree().paused:
		return false
	var h := GameClock.time_of_day
	if after_midnight and not (h >= 0.0 and h < NIGHT_TO):
		return false
	if not after_midnight and not GameClock.is_night():
		return false
	if not Jobs.active.is_empty() and not Jobs.active.has("story"):
		return false
	return map_idle()


## Nothing streaming in round the player (so a hitch can't be mistaken for an
## event, or an event for a hitch).
static func map_idle() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var map := tree.get_first_node_in_group(&"perth_map") if tree else null
	if map == null:
		return true
	var pending: Variant = map.get("_pending")
	var building: Variant = map.get("_collision_pending")
	return (pending == null or (pending as Dictionary).is_empty()) \
		and (building == null or (building as Dictionary).is_empty())


# --- Presence and the birds -----------------------------------------------------

## 0..1: how strongly the late city is round the player now.
func presence() -> float:
	if active():
		return 1.0
	var at := _player_position()
	return presence_at(at) if at != Vector3.INF else 0.0


## 0..1 at a world position: 1 while an event runs; near the late city's
## places at night from act 3 (the river lights, the end of the lane, Fraser
## Avenue); otherwise 0.
func presence_at(pos: Vector3) -> float:
	if active():
		return 1.0
	var h := GameClock.time_of_day
	if Story.act() < 3 or not (h >= 0.0 and h < NIGHT_TO):
		return 0.0
	var best := 0.0
	for p in _late_places():
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		best = maxf(best, 1.0 - d / PLACE_RADIUS)
	return clampf(best, 0.0, 1.0)


## How the birds flicker, by act (STORY_API.md): 0 nothing, 1 the frogmouth
## through the binoculars, 2 every wrong bird, 3 ordinary birds where the
## late city is strong too, 4 the thirteen fly with the car.
func flicker_level() -> int:
	return clampi(Story.act() - 1, 0, 4)


## Keep everything under `node` lit when the world goes dark (the shader's
## `late_void`): your car on the empty road. Returns what to hand back to
## release_lit() when it's over.
static func keep_lit(node: Node) -> Array:
	var saved: Array = []
	for g in _geometry(node):
		if g.material_override is ShaderMaterial:
			saved.append([g, -1, g.material_override])
			g.material_override = _kept(g.material_override)
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var mi := g as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m is ShaderMaterial:
					saved.append([mi, i, mi.get_surface_override_material(i)])
					mi.set_surface_override_material(i, _kept(m))
	return saved


static func release_lit(saved: Array) -> void:
	for entry: Array in saved:
		var g := entry[0] as GeometryInstance3D
		if not is_instance_valid(g):
			continue
		if int(entry[1]) < 0:
			g.material_override = entry[2]
		else:
			(g as MeshInstance3D).set_surface_override_material(int(entry[1]), entry[2])


static func _kept(m: Material) -> ShaderMaterial:
	var keep := (m as ShaderMaterial).duplicate() as ShaderMaterial
	keep.set_shader_parameter("late_keep", true)
	return keep


## The tape shimmer over everything under `node` (late-city things only:
## nothing from our world ever shimmers).
func add_shimmer(node: Node3D, amount := 1.0) -> void:
	var key := snappedf(clampf(amount, 0.0, 1.0), 0.1)
	if not _shimmers.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHIMMER_SHADER
		m.set_shader_parameter("amount", key)
		_shimmers[key] = m
	for g in _geometry(node):
		if not g.has_meta(&"late_overlay"):
			g.set_meta(&"late_overlay", g.material_overlay)
		g.material_overlay = _shimmers[key]


func remove_shimmer(node: Node3D) -> void:
	for g in _geometry(node):
		if g.has_meta(&"late_overlay"):
			g.material_overlay = g.get_meta(&"late_overlay")
			g.remove_meta(&"late_overlay")


## The soft warble of something blinking out of being.
func play_flicker(pos: Vector3) -> void:
	var world := _world_node()
	if world == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sound(SOUND_FLICKER)
	p.bus = "SFX"
	p.unit_size = 4.0
	p.max_distance = 60.0
	p.volume_db = -6.0
	p.pitch_scale = randf_range(0.92, 1.06)
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# --- Inside ------------------------------------------------------------------------

func _set_mute(v: float) -> void:
	_mute = v
	for bus in _amps:
		# Even in dB, so the fade is heard all the way down, then gone.
		(_amps[bus] as AudioEffectAmplify).volume_db = -80.0 if v >= 0.999 else -48.0 * v


func _set_look(v: float) -> void:
	_look = v
	for bus in _pitches:
		var i := AudioServer.get_bus_index(bus)
		var n := AudioServer.get_bus_effect_count(i)
		for e in n:
			if AudioServer.get_bus_effect(i, e) == _pitches[bus]:
				AudioServer.set_bus_effect_enabled(i, e, v > 0.001)


## One amplify (for muting) and one pitch shift (for the tape) at the end of
## each bus, after the audio manager's own effects, so its indices stay put.
func _add_bus_effects() -> void:
	for bus in MUTE_BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var amp := AudioEffectAmplify.new()
		amp.volume_db = 0.0
		AudioServer.add_bus_effect(i, amp)
		_amps[bus] = amp
	for bus in TAPE_BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var shift := AudioEffectPitchShift.new()
		shift.pitch_scale = 1.0
		AudioServer.add_bus_effect(i, shift)
		AudioServer.set_bus_effect_enabled(i, AudioServer.get_bus_effect_count(i) - 1, false)
		_pitches[bus] = shift


func _play_2d(sound: String, volume_db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _sound(sound)
	# Your own car's bus when you're at the wheel, so muting the street
	# doesn't take the deck with it.
	p.bus = "Cabin" if Audio.is_player_driving() else "SFX"
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _sound(sound: String) -> AudioStream:
	if Audio.has(sound):
		return Audio.stream(sound, sound == SOUND_HISS)
	if not _sounds.has(sound):
		_sounds[sound] = LateSounds.make(sound.get_file())
	return _sounds[sound]


static func _geometry(node: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if node is GeometryInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_geometry(c))
	return out


func _world_node() -> Node3D:
	var map := get_tree().get_first_node_in_group(&"perth_map")
	if map and map.get_parent() is Node3D:
		return map.get_parent()
	var cam := get_viewport().get_camera_3d()
	return cam.get_parent() as Node3D if cam else null


func _player_position() -> Vector3:
	var cam := _camera()
	return cam.global_position if cam else Vector3.INF


func _camera() -> Camera3D:
	var world := _world_node()
	if world == null:
		return null
	return world.get_viewport().get_camera_3d()


func _late_places() -> Array[Vector3]:
	if _places_read:
		return _places
	_places_read = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/places.json"))
	if parsed is Dictionary:
		for spot: Dictionary in parsed.get("photo_spots", []):
			var p := Vector3(spot.p[0], spot.p[1], spot.p[2])
			match String(spot.id):
				"riverside_east":
					_places.append(p + Vector3(0, 0, 70.0))  # the river lights, out over the water
				"kings_park_fraser":
					_places.append(p)
	var home := get_tree().get_first_node_in_group(&"home_base") as Node3D
	if home:
		_places.append(home.global_position)
	return _places


## The little cassette counter by the dash: three amber digits and two reels
## that turn while the late city is near. The same every time, so it's the
## one sure sign of "this is meant".
class TapeCounter:
	extends Control

	const SIZE := Vector2(112, 44)
	var turning := false
	var _count := 0.0
	var _angle := 0.0
	var _alpha := 0.0
	var _tween: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		custom_minimum_size = SIZE
		size = SIZE
		modulate.a = 0.0
		visible = false

	func show_counter(on: bool) -> void:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		if on:
			visible = true
			_tween.tween_property(self, "modulate:a", 1.0, 0.6)
		else:
			_tween.tween_interval(1.2)
			_tween.tween_property(self, "modulate:a", 0.0, 1.0)
			_tween.tween_callback(func() -> void: visible = false)

	func _process(delta: float) -> void:
		if not visible:
			return
		# Next to the dash when you're driving (the dash is ~238 px wide with
		# its margin); in the corner on foot.
		var shift := 252.0 if Audio.is_player_driving() else 16.0
		var vp := get_viewport_rect().size
		position = Vector2(vp.x - shift - SIZE.x, vp.y - 16.0 - SIZE.y)
		if turning:
			_count = fmod(_count + delta * 1.6, 1000.0)
			_angle += delta * 2.4
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, SIZE)
		draw_rect(r, Color(UiStyle.LCD_BG, 0.92))
		draw_rect(r, Color(UiStyle.LCD_DIM, 0.9), false, 2.0)
		# The two reels.
		for cx: float in [16.0, 40.0]:
			var c := Vector2(cx, SIZE.y * 0.5)
			draw_arc(c, 9.0, 0.0, TAU, 20, UiStyle.LCD, 1.5)
			draw_circle(c, 2.5, UiStyle.LCD)
			for k in 3:
				var a := _angle + k * TAU / 3.0
				draw_line(c + Vector2.from_angle(a) * 3.0, c + Vector2.from_angle(a) * 8.0, UiStyle.LCD, 1.5)
		var text := "%03d" % int(_count)
		draw_string(UiStyle.LCD_FONT, Vector2(56, SIZE.y * 0.5 + 10.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiStyle.LCD)
