class_name HouseAbandoned
extends House1979
## The townhouse as if nobody had lived in it since July 1979 (OtherHouse,
## act 3): dust sheets over the sofa, the armchair and the telly, leaves
## blown in under the front door, the chairs up on the table, the round
## fridge standing open and dark, the calendar faded on July, a water stain
## down the stairwell, and the porch light switch by the door taped in the
## on position. Upstairs the beds are stripped and Robyn's little bed is
## under a sheet. No lamps: the moon through the windows and one bare bulb
## in the hall. A cassette lies on the stairs.
##
## With `tidy` (Strange things: Gentle) it's the same house swept and empty:
## no sheets, no leaves, no stain, the boards clean.

const SHEET := Color(0.7, 0.68, 0.62)
const DUST := Color(0.5, 0.47, 0.42)
const LEAF := Color(0.42, 0.3, 0.14)
const LEAF_DRY := Color(0.55, 0.42, 0.2)
const STAIN := Color(0.2, 0.15, 0.09)
const TAPE_YELLOW := Color(0.82, 0.74, 0.46)
const MOON := Color(0.55, 0.65, 0.9)
const BULB := Color(1.0, 0.78, 0.5)
## Where the cassette lies (house frame), on the third step up.
const TAPE_AT := Vector3(0.5, 8.17, 0.725)
const CLUE := "mystery/stairs_tape"

var tidy := false
var took_tape := false
var tape: MeshInstance3D
var _bulb: OmniLight3D


func _ready() -> void:
	name = "HouseAbandoned"
	_hall()
	_lounge_shut()
	_kitchen_shut()
	_dining_shut()
	_stairs()
	_upstairs_shut()


func _process(delta: float) -> void:
	_t += delta
	# The bare bulb on its cord, swaying a little in the draught.
	if _bulb:
		_bulb.light_energy = 0.7 + 0.04 * sin(_t * 1.3)


func _hall() -> void:
	# One bare bulb hanging in the hall, the only light on in the house.
	_box(Vector3(0.01, 0.01, 0.6), Vector3(1.0, 1.2, 2.25), Color(0.1, 0.1, 0.1))
	_box(Vector3(0.07, 0.07, 0.09), Vector3(1.0, 1.2, 1.92), BULB, 2.2)
	_bulb = _light(Vector3(1.0, 1.2, 1.85), BULB, 0.7, 5.5)
	# The porch light switch, an old bakelite one, taped on.
	_switch()
	# The hook by the door, nothing on it.
	_box(Vector3(0.18, 0.03, 0.04), Vector3(0.12, 1.2, 1.5), TEAK.darkened(0.3))
	if tidy:
		return
	# Leaves blown in under the front door, thinning out down the hall.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	for i in 34:
		var y := rng.randf_range(0.05, 1.0) ** 1.6 * 3.2
		var x := rng.randf_range(0.35, 1.5)
		var leaf := _box(Vector3(rng.randf_range(0.06, 0.11), rng.randf_range(0.04, 0.07), 0.005),
			Vector3(x, y + 0.1, 0.165), LEAF if rng.randf() < 0.5 else LEAF_DRY)
		leaf.rotation.y = rng.randf() * TAU
	# Junk mail fanned out behind the door.
	for i in 4:
		var mail := _box(Vector3(0.22, 0.11, 0.004), Vector3(0.85 + i * 0.06, 0.35 + i * 0.05, 0.167), Color(0.82, 0.8, 0.72))
		mail.rotation.y = 0.3 * i - 0.4


func _switch() -> void:
	# On the side wall where today's switch is (PorchSwitch.AT), facing into the hall.
	var at := Vector3(0.012, 1.57, 1.15)
	var plate := _box(Vector3(0.012, 0.09, 0.12), at, Color(0.4, 0.28, 0.18))
	plate.name = "Switch_1979"
	_box(Vector3(0.02, 0.025, 0.04), at + Vector3(0.012, 0, 0.012), Color(0.3, 0.2, 0.12))
	# Two strips of yellowed tape across it, holding it on.
	var strip := _box(Vector3(0.004, 0.16, 0.03), at + Vector3(0.024, 0, 0.0), TAPE_YELLOW)
	strip.rotation.x = 0.35
	var strip2 := _box(Vector3(0.004, 0.15, 0.028), at + Vector3(0.025, 0, 0.005), TAPE_YELLOW.darkened(0.08))
	strip2.rotation.x = -0.4


func _lounge_shut() -> void:
	var cloth := DUST if tidy else SHEET
	if tidy:
		# Swept and empty: just the coffee table left behind.
		_box(Vector3(0.6, 1.1, 0.06), Vector3(3.4, 2.9, 0.55), TEAK)
	else:
		# The sofa under a sheet: its shape, and the cloth falling to the floor.
		_box(Vector3(1.0, 2.5, 0.5), Vector3(4.85, 2.8, 0.4), SHEET)
		_box(Vector3(0.3, 2.5, 0.9), Vector3(5.2, 2.8, 0.6), SHEET)
		_box(Vector3(1.06, 2.56, 0.05), Vector3(4.85, 2.8, 0.66), SHEET.darkened(0.06))
		# The armchair and the telly, sheeted.
		_box(Vector3(0.92, 0.92, 0.5), Vector3(2.4, 1.1, 0.4), cloth)
		_box(Vector3(0.92, 0.25, 0.95), Vector3(2.4, 0.74, 0.62), cloth)
		_box(Vector3(0.72, 1.05, 0.9), Vector3(0.45, 4.15, 0.6), cloth)
		_box(Vector3(1.6, 0.5, 0.75), Vector3(3.55, 4.72, 0.52), cloth)
		# The coffee table, bare, a ring where a cup was, and the lamp on its side.
		_box(Vector3(0.6, 1.1, 0.06), Vector3(3.4, 2.9, 0.55), TEAK.darkened(0.25))
		_box(Vector3(0.09, 0.09, 0.004), Vector3(3.5, 3.1, 0.582), DUST.darkened(0.3))
		var pole := _box(Vector3(0.05, 1.4, 0.05), Vector3(4.4, 0.8, 0.19), CHROME.darkened(0.3))
		pole.rotation.y = 0.5
		# A drift of dust and plaster under the window.
		_box(Vector3(1.6, 0.25, 0.01), Vector3(3.3, 0.2, 0.17), DUST)
	# The clock still up, stopped at twenty to three, gone grey.
	_clock(Vector3(3.55, 4.93, 1.75))
	# The moon through the front window.
	_light(Vector3(3.2, 1.0, 2.0), MOON, 0.45, 6.0)
	# The fire long out: soot in the grate.
	_box(Vector3(0.04, 0.85, 0.65), Vector3(0.6, 2.4, 0.48), Color(0.06, 0.06, 0.06))


func _kitchen_shut() -> void:
	var tone := DUST if not tidy else MUSTARD.darkened(0.25)
	_box(Vector3(2.5, 0.6, 0.86), Vector3(4.15, 6.95, 0.58), MUSTARD.lerp(tone, 0.5))
	_box(Vector3(2.52, 0.63, 0.04), Vector3(4.15, 6.95, 1.03), LAMINEX.darkened(0.25))
	_box(Vector3(2.5, 0.36, 0.7), Vector3(4.15, 6.83, 1.9), MUSTARD.lerp(tone, 0.5))
	_box(Vector3(0.6, 1.0, 0.86), Vector3(5.08, 7.75, 0.58), MUSTARD.lerp(tone, 0.5))
	_box(Vector3(0.62, 1.02, 0.04), Vector3(5.08, 7.75, 1.03), LAMINEX.darkened(0.25))
	if not tidy:
		# One wall cupboard door hanging open.
		var cupboard := _box(Vector3(0.6, 0.02, 0.66), Vector3(3.3, 6.47, 1.9), MUSTARD.lerp(tone, 0.6))
		cupboard.rotation.y = -0.6
	# The fridge, switched off and propped open, dark inside.
	_box(Vector3(0.72, 0.7, 1.55), Vector3(2.5, 7.0, 0.93), CREAM.darkened(0.25))
	_box(Vector3(0.6, 0.02, 1.4), Vector3(2.5, 7.36, 0.95), Color(0.05, 0.05, 0.05))
	_box(Vector3(0.05, 0.7, 1.5), Vector3(2.88, 7.6, 0.93), CREAM.darkened(0.3))
	# The calendar, faded, still on July 1979.
	_faded_calendar(Vector3(3.3, 7.022, 1.9))
	# The moon over the bench.
	_light(Vector3(4.0, 7.6, 2.0), MOON, 0.35, 4.5)


func _faded_calendar(p: Vector3) -> void:
	_box(Vector3(0.36, 0.01, 0.5), p, Color(0.78, 0.74, 0.6))
	_box(Vector3(0.36, 0.012, 0.18), p + Vector3(0, 0, 0.17), Color(0.58, 0.64, 0.66))
	var month := Label3D.new()
	month.text = "JULY 1979"
	month.font_size = 40
	month.pixel_size = 0.0022
	month.modulate = Color(0.6, 0.38, 0.34)
	month.outline_size = 0
	month.shaded = true
	month.position = at(p + Vector3(0, 0.012, 0.03))
	month.rotation.y = PI
	add_child(month)
	# One corner curled down where the pin's gone.
	var curl := _box(Vector3(0.1, 0.012, 0.1), p + Vector3(0.14, 0.02, -0.22), Color(0.7, 0.66, 0.54))
	curl.rotation.y = 0.5


func _dining_shut() -> void:
	_box(Vector3(0.85, 1.35, 0.04), Vector3(1.4, 10.6, 0.76), LAMINEX.darkened(0.2))
	for c: Vector2 in [Vector2(1.05, 10.0), Vector2(1.75, 10.0), Vector2(1.05, 11.2), Vector2(1.75, 11.2)]:
		_box(Vector3(0.04, 0.04, 0.6), Vector3(c.x, c.y, 0.45), CHROME.darkened(0.3))
	if tidy:
		return
	# The chairs up on the table, seats down and legs in the air, the way
	# you leave a room.
	for c: Vector2 in [Vector2(1.2, 10.3), Vector2(1.6, 10.9)]:
		_box(Vector3(0.42, 0.42, 0.05), Vector3(c.x, c.y, 0.805), VINYL.darkened(0.3))
		for l: Vector2 in [Vector2(-0.18, -0.18), Vector2(0.18, -0.18), Vector2(-0.18, 0.18), Vector2(0.18, 0.18)]:
			_box(Vector3(0.025, 0.025, 0.45), Vector3(c.x + l.x, c.y + l.y, 1.05), CHROME.darkened(0.3))
	# Moonlight through the back glass.
	_light(Vector3(2.8, 11.4, 2.0), MOON, 0.4, 5.0)


func _stairs() -> void:
	if not tidy:
		# The water stain down the stairwell wall from the landing, a paler
		# tide line round it, and its drips running down to the steps.
		_box(Vector3(0.006, 1.5, 2.0), Vector3(0.008, 7.2, 2.9), STAIN.lightened(0.25))
		_box(Vector3(0.006, 1.2, 1.8), Vector3(0.011, 7.25, 2.95), STAIN)
		for k in 5:
			var drip := 0.5 + 0.25 * (k % 3)
			_box(Vector3(0.006, 0.05, drip), Vector3(0.011, 6.75 + k * 0.22, 2.05 - drip * 0.5), STAIN)
	# The cassette in its case, on the third step.
	if not took_tape:
		tape = _box(Vector3(0.11, 0.07, 0.016), TAPE_AT, Color(0.42, 0.42, 0.44))
		var label := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.002, 0.035)
		label.mesh = box
		label.material_override = _material(Color(0.94, 0.9, 0.78), 0.4)
		label.position = Vector3(0, 0.009, 0)
		tape.add_child(label)
		tape.rotation.y = 0.4


func _upstairs_shut() -> void:
	var up := 3.16
	# The front bedroom: a bare mattress on the frame, the wardrobe empty.
	_box(Vector3(1.5, 1.9, 0.28), Vector3(4.3, 2.05, up + 0.14), Color(0.62, 0.58, 0.48) if not tidy else DUST)
	_box(Vector3(1.6, 0.08, 0.9), Vector3(4.3, 1.02, up + 0.45), TEAK.darkened(0.3))
	_box(Vector3(0.6, 0.55, 1.8), Vector3(0.35, 2.2, up + 0.9), TEAK.darkened(0.3))
	if not tidy:
		_box(Vector3(0.3, 0.3, 0.004), Vector3(4.6, 2.3, up + 0.285), STAIN.lightened(0.15))
	_light(Vector3(3.0, 1.2, up + 2.0), MOON, 0.35, 5.0)
	# Robyn's room: her little bed under a sheet, and the night light dark.
	_box(Vector3(0.95, 1.95, 0.48), Vector3(1.0, 10.6, up + 0.24), SHEET if not tidy else DUST)
	_box(Vector3(0.12, 0.08, 0.12), Vector3(2.4, 11.85, up + 0.4), Color(0.4, 0.38, 0.32))
	if not tidy:
		# A doll face down on the boards.
		_box(Vector3(0.12, 0.26, 0.07), Vector3(2.0, 10.2, up + 0.04), Color(0.75, 0.6, 0.55))
	_light(Vector3(2.4, 11.2, up + 1.8), MOON, 0.35, 4.5)
