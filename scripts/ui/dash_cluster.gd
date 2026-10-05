class_name DashCluster
extends Control
## The driving HUD's instrument: one round dial like the 500's own binnacle.
## Speed on the outer ring with a red needle, revs as an inner arc that turns
## red past the redline, and a small amber dot-matrix screen for the gear,
## the speed in figures and the fuel. With the headlights on it switches to
## its night lighting: dark face, amber markings.

const RADIUS := 104.0
const START := deg_to_rad(135.0)   # 0 km/h, bottom left
const SWEEP := deg_to_rad(270.0)   # clockwise through the top

var speed_kmh := 0.0
var max_kmh := 180.0
var rpm := 0.0
var redline_rpm := 6200.0
var limiter_rpm := 6450.0
var gear_text := "N"
var automatic := false
var fuel := 1.0
var fuel_low := false
var electric := false
## 0 by day, 1 at night (the dash lights): blended so it fades in.
var night := 0.0

var _needle := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 16.0, RADIUS * 2.0 + 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	# The needle has a little weight to it.
	_needle = lerpf(_needle, clampf(speed_kmh / max_kmh, 0.0, 1.04), 1.0 - exp(-delta * 14.0))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var face := UiStyle.PAPER.lerp(UiStyle.NIGHT_2, night)
	var mark := UiStyle.INK.lerp(UiStyle.LCD, night)
	var mark_soft := UiStyle.INK_3.lerp(UiStyle.LCD_DIM, night)
	var bold := UiStyle.BOLD_FONT
	# Shadow, bezel, face.
	draw_circle(c + Vector2(4, 5), RADIUS + 2.0, UiStyle.SHADOW)
	draw_circle(c, RADIUS + 2.0, UiStyle.INK)
	draw_circle(c, RADIUS - 3.0, face)
	draw_arc(c, RADIUS - 6.0, 0.0, TAU, 96, Color(mark, 0.18), 1.5, true)

	# Revs: an inner arc, with the redline marked on its outside.
	var r_rev := RADIUS - 44.0
	var rev_frac := clampf(rpm / limiter_rpm, 0.0, 1.0)
	var red_from := clampf(redline_rpm / limiter_rpm, 0.0, 1.0)
	draw_arc(c, r_rev, START, START + SWEEP, 64, Color(mark_soft, 0.35), 8.0, true)
	if rev_frac > 0.0:
		var hot := rpm > redline_rpm
		var rev_col := UiStyle.RED if hot else UiStyle.TEAL.lerp(UiStyle.LCD, night)
		draw_arc(c, r_rev, START, START + SWEEP * rev_frac, 64, rev_col, 8.0, true)
	draw_arc(c, r_rev + 7.0, START + SWEEP * red_from, START + SWEEP, 24, UiStyle.RED, 3.0, true)
	var thousands := int(floor(limiter_rpm / 1000.0))
	for k in range(0, thousands + 1):
		var frac := k * 1000.0 / limiter_rpm
		var a := START + SWEEP * frac
		var dir := Vector2.from_angle(a)
		draw_line(c + dir * (r_rev - 6.0), c + dir * (r_rev + 6.0), Color(face, 0.9), 2.0, true)
		if k > 0 and frac < 0.9:  # the ends would sit on the screen
			_text_centred(str(k), c + dir * (r_rev - 15.0), bold, 11, mark_soft)

	# Speed: ticks every 10, figures every 20.
	var step := 10.0
	var n := int(max_kmh / step)
	for i in range(0, n + 1):
		var a := START + SWEEP * (i * step / max_kmh)
		var dir := Vector2.from_angle(a)
		var major := i % 2 == 0
		var outer := RADIUS - 8.0
		draw_line(c + dir * (outer - (11.0 if major else 6.0)), c + dir * outer, mark, 2.5 if major else 1.5, true)
		if major:
			_text_centred(str(int(i * step)), c + dir * (outer - 22.0), bold, 13, mark)

	# The amber screen: gear, speed in figures, fuel.
	var lcd := Rect2(c + Vector2(-38, 26), Vector2(76, 44))
	draw_rect(Rect2(lcd.position - Vector2(2, 2), lcd.size + Vector2(4, 4)), UiStyle.INK, true)
	draw_rect(lcd, UiStyle.LCD_BG, true)
	var lcd_font := UiStyle.LCD_FONT
	draw_string(lcd_font, lcd.position + Vector2(4, 25), gear_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiStyle.LCD)
	if automatic:
		draw_string(lcd_font, lcd.position + Vector2(17, 13), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.LCD_DIM)
	draw_string(lcd_font, lcd.position + Vector2(20, 23), "%d" % roundi(speed_kmh), HORIZONTAL_ALIGNMENT_RIGHT, 52, 28, UiStyle.LCD)
	# Fuel: a pump and eight segments, blinking when low.
	var fuel_col := UiStyle.RED if fuel_low else UiStyle.LCD_DIM
	draw_texture_rect(UiStyle.icon("fuel", 12, fuel_col, Vector2.ZERO, fuel_col), Rect2(lcd.position + Vector2(4, 29), Vector2(11, 11)), false)
	var segs := 8
	var lit := ceili(fuel * segs - 0.01)
	var blink := fuel_low and int(Time.get_ticks_msec() / 400) % 2 == 0
	for s in segs:
		var on := s < lit and not (blink and s == lit - 1)
		var col := (UiStyle.RED if fuel_low else UiStyle.LCD) if on else Color(UiStyle.LCD_DIM, 0.45)
		draw_rect(Rect2(lcd.position + Vector2(19 + s * 6.8, 31), Vector2(4.6, 7)), col, true)

	# Needle and hub.
	var na := START + SWEEP * _needle
	var nd := Vector2.from_angle(na)
	var tip := c + nd * (RADIUS - 12.0)
	var tail := c - nd * 16.0
	var side := nd.orthogonal() * 3.2
	var drop := Vector2(2, 3)
	draw_colored_polygon(PackedVector2Array([tail + side + drop, tip + drop, tail - side + drop]), Color(0, 0, 0, 0.22 * (1.0 - night)))
	draw_colored_polygon(PackedVector2Array([tail + side, tip, tail - side]), UiStyle.RED.lightened(0.1 * night))
	draw_circle(c, 10.0, UiStyle.INK)
	draw_circle(c, 4.0, UiStyle.RED)


func _text_centred(text: String, at: Vector2, font: Font, px: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	draw_string(font, at + Vector2(-w.x * 0.5, w.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
