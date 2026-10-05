class_name BinocularsOverlay
extends Control
## What you see through the binoculars: the two round eyepieces, a reticle,
## the name of the bird once it's identified, the film counter, and during a
## shot the focus dial (Dredge's fishing ring as a camera lens).

const MASK_SHADER := """
shader_type canvas_item;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float radius = 0.46;
uniform float spread = 0.17;
void fragment() {
	vec2 p = (UV - 0.5) * view_size / view_size.y;
	float a = length(p - vec2(-spread, 0.0));
	float b = length(p - vec2(spread, 0.0));
	float d = min(a, b);
	float edge = smoothstep(radius - 0.025, radius, d);
	COLOR = vec4(0.0, 0.0, 0.0, edge);
}
"""

var owner_binoculars: Binoculars
var flash := 0.0

var _mask: ColorRect
var _font: Font


func _ready() -> void:
	_mask = ColorRect.new()
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = MASK_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_mask.material = mat
	add_child(_mask)
	_font = UiStyle.BODY_FONT


func _process(delta: float) -> void:
	flash = maxf(flash - delta * 2.5, 0.0)
	(_mask.material as ShaderMaterial).set_shader_parameter("view_size", size)


func _draw() -> void:
	var b := owner_binoculars
	if b == null or b.state == Binoculars.State.CLOSED:
		return
	var centre := size * 0.5
	var r_view := size.y * 0.46
	var fov := 30.0
	if b._camera:
		fov = b._camera.fov
	var reticle := size.y * 0.5 * Binoculars.RETICLE
	var ink := Color(0.95, 0.95, 0.88, 0.7)

	# Reticle: a thin ring with ticks.
	draw_arc(centre, reticle, 0.0, TAU, 64, ink, 1.5, true)
	for i in 4:
		var d := Vector2.from_angle(i * PI * 0.5)
		draw_line(centre + d * (reticle - 8.0), centre + d * (reticle + 6.0), ink, 1.5)

	# The bird in view.
	var t: Dictionary = b.target
	var lines := PackedStringArray()
	if not t.is_empty():
		var bird := FieldJournal.bird(t.species)
		if b.is_identified():
			var tag := "" if FieldJournal.is_photographed(t.species) else ("  (no photo yet)" if FieldJournal.is_seen(t.species) else "")
			lines.append("%s%s" % [bird.get("name", t.species), tag])
			var kind: String = "Not in any field guide" if bird.get("wrong", false) else FieldJournal.RARITY_NAMES[clampi(int(bird.get("rarity", 1)), 1, 4)]
			lines.append("%s   %d m" % [kind, roundi(t.dist)])
		elif not t.in_range:
			lines.append("Too far to make out (%d m)" % roundi(t.dist))
		else:
			lines.append("...")
	var y := centre.y + reticle + 40.0
	for i in lines.size():
		# The name in the serif, the rest in the body face.
		var title := i == 0 and b.is_identified()
		_text(lines[i], Vector2(centre.x, y), 30 if title else 18, UiStyle.CREAM_TEXT if title else Color(UiStyle.SUN_LIGHT, 0.95),
			UiStyle.TITLE_FONT if title else _font)
		y += 34.0 if title else 26.0

	# Film and zoom.
	var film := "FILM %d / %d" % [FieldJournal.film_left(), FieldJournal.roll_size()]
	# Like the camera's own little amber counter.
	_text(film, Vector2(centre.x + r_view * 0.95, size.y - 40.0), 24, UiStyle.LCD if FieldJournal.film_left() > 3 else UiStyle.RED.lightened(0.2), UiStyle.LCD_FONT)
	_text("%.0fx" % (72.0 / fov), Vector2(centre.x - r_view * 0.95, size.y - 40.0), 24, UiStyle.LCD, UiStyle.LCD_FONT)

	if b.state == Binoculars.State.FOCUS:
		_draw_dial(centre, r_view * 0.62)
	var msg := b.message()
	if msg != "":
		_text(msg, Vector2(centre.x, size.y * 0.12), 19, Color(1, 0.95, 0.85))
	var hint := "Enter / A  Focus dial: press in the bright arcs" if b.state == Binoculars.State.FOCUS \
		else "Mouse / stick / WASD look    Wheel / E Q zoom    Enter / A photo    B / Esc lower"
	_text(hint, Vector2(centre.x, size.y - 14.0), 13, Color(0.85, 0.85, 0.8, 0.8))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash * 0.8))


func _draw_dial(centre: Vector2, r: float) -> void:
	var d: Dictionary = owner_binoculars.dial
	if d.is_empty():
		return
	var live := owner_binoculars.in_frame()
	var base := Color(0.1, 0.1, 0.1, 0.55)
	draw_arc(centre, r, 0.0, TAU, 96, base, 14.0, true)
	var half: float = d.half
	for a: float in d.arcs:
		var col := Color(0.55, 0.85, 0.55, 0.85) if live else Color(0.5, 0.5, 0.5, 0.5)
		draw_arc(centre, r, a - half, a + half, 24, col, 14.0, true)
		var sharp := Color(0.9, 1.0, 0.7, 0.95) if live else Color(0.65, 0.65, 0.65, 0.6)
		draw_arc(centre, r, a - half * 0.35, a + half * 0.35, 12, sharp, 16.0, true)
	var needle := Vector2.from_angle(d.needle)
	var ncol := Color(1, 0.95, 0.8) if live else Color(0.7, 0.7, 0.7)
	draw_line(centre + needle * (r - 22.0), centre + needle * (r + 22.0), ncol, 3.0, true)
	# Presses still needed, and patience left.
	for i in int(d.need):
		var p := centre + Vector2(-((int(d.need) - 1) * 10.0) + i * 20.0, -r - 30.0)
		draw_circle(p, 6.0, Color(0.6, 0.9, 0.6) if i < int(d.hits) else Color(0.2, 0.2, 0.2, 0.7))
	for i in maxi(int(d.patience), 0):
		var p := centre + Vector2(-((int(d.patience) - 1) * 9.0) + i * 18.0, r + 30.0)
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(0.95, 0.8, 0.5, 0.85))
	if d.flash > 0.0:
		var c := Color(0.7, 1.0, 0.6, d.flash * 0.6) if d.flash_good else Color(1.0, 0.45, 0.35, d.flash * 0.6)
		draw_arc(centre, r, 0.0, TAU, 96, c, 6.0, true)
	if not live:
		_text("Keep it in the middle!", centre + Vector2(0, r + 58.0), 17, Color(1, 0.6, 0.5))
	# How long the bird will wait.
	var wait := clampf(float(d.time) / 15.0, 0.0, 1.0)
	draw_arc(centre, r - 20.0, -PI * 0.5, -PI * 0.5 + TAU * wait, 64, Color(1, 1, 1, 0.25), 2.0, true)


func _text(text: String, at: Vector2, font_size: int, color: Color, font: Font = null) -> void:
	if font == null:
		font = _font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var pos := at - Vector2(w * 0.5, 0)
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
		draw_string(font, pos + o * 1.5, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8 * color.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
