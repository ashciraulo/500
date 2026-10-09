class_name AnsweringMachine
extends Node3D
## The answering machine on the breakfast bar at home (STORY.md, the people).
## A little grey seventies-looking box with a cassette window and a red light
## that blinks while there are messages you haven't heard. Interact to play
## them: a beep, then each one on a card ("Thea Kostas, number 11: ..."),
## oldest first. Messages from the late city come with tape hiss and the
## deck's click instead of a beep. Story keeps the messages (leave_message).
##
## Placed by StoryPeople, as a child of the HomeBase, in the house's frame.

## Where it sits (house frame: x across, y back, z up): on the breakfast bar,
## at the kitchen end.
const AT := Vector3(4.4, 8.62, 1.24)
const BODY := Color(0.2, 0.2, 0.21)
const LED := Color(1.0, 0.12, 0.08)

var _led: MeshInstance3D
var _led_mat: ShaderMaterial
var _blink := 0.0
var _beep: AudioStreamPlayer3D
## Messages still to show from this play, and when the next one goes up.
var _playing: Array[Dictionary] = []
var _next := 0.0


func _ready() -> void:
	name = "AnsweringMachine"
	add_to_group(&"interactables")
	position = House1979.at(AT)
	# A wedge-ish box: the body, the lid with its cassette window, the buttons.
	_box(Vector3(0.22, 0.05, 0.15), Vector3(0, 0.025, 0), BODY)
	_box(Vector3(0.2, 0.012, 0.13), Vector3(0, 0.056, 0.005), BODY.lightened(0.08))
	_box(Vector3(0.09, 0.004, 0.05), Vector3(-0.03, 0.063, 0.02), Color(0.05, 0.05, 0.05))
	_box(Vector3(0.06, 0.003, 0.035), Vector3(-0.03, 0.065, 0.02), Color(0.45, 0.32, 0.18))
	for i in 3:
		_box(Vector3(0.022, 0.008, 0.014), Vector3(0.045 + i * 0.026, 0.064, -0.035), Color(0.75, 0.73, 0.68))
	_led = _box(Vector3(0.012, 0.008, 0.012), Vector3(0.08, 0.064, 0.035), LED)
	_led_mat = _led.material_override as ShaderMaterial
	_led_mat.set_shader_parameter("emission_color", LED)
	_beep = AudioStreamPlayer3D.new()
	_beep.bus = "SFX"
	_beep.unit_size = 1.5
	_beep.max_distance = 12.0
	_beep.volume_db = -10.0
	add_child(_beep)


func _process(delta: float) -> void:
	_blink += delta
	var waiting := Story.unheard_messages() > 0
	var on := waiting and fmod(_blink, 1.0) < 0.5
	_led_mat.set_shader_parameter("emission_energy", 2.5 if on else 0.0)
	_led_mat.set_shader_parameter("albedo_color", LED if on else LED.darkened(0.7))
	if not _playing.is_empty():
		_next -= delta
		if _next <= 0.0:
			_show(_playing.pop_front())


# --- Interactables ------------------------------------------------------------

func interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.05


func interact_hint() -> String:
	if not _playing.is_empty():
		return ""
	var n := Story.unheard_messages()
	if n > 0:
		return "Play messages (%d)" % n
	return "Play the last message" if not Story.messages.is_empty() else ""


func interact() -> void:
	if not _playing.is_empty():
		return
	var list := Story.take_unheard()
	if list.is_empty() and not Story.messages.is_empty():
		list = [Story.messages[Story.messages.size() - 1]]
	_playing = list
	_next = 0.6
	_play(LateSounds.make("machine_beep"))


func _show(message: Dictionary) -> void:
	var late: bool = message.get("late", false)
	if late:
		_play(LateSounds.make("late_tape_start"))
		Notices.post(String(message.text), "odd", "-", String(message.from))
	else:
		Notices.post(String(message.text), "info", "-", String(message.from))
	# Give each card its time on screen before the next.
	_next = Notices.seconds_for(String(message.text)) + 0.4
	if _playing.is_empty():
		_next = 0.0


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	_beep.stream = stream
	_beep.play()


func _box(size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	# Baked to an ArrayMesh: the other house goes through its surfaces.
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	mi.mesh = baked
	mi.material_override = PS1Material.make(colour)
	mi.position = at
	add_child(mi)
	return mi
