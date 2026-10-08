class_name MapView
extends Control
## A window onto the Perth map, drawn like a page of a street directory: the
## ground and roads from MapData, then pins, the player's arrow and suburb
## names on top at a fixed size. The minimap and the full map are both one of
## these; they set `centre`, `metres_per_px` and `turn` and hand it pins.
##
## Screen space: x right, y down. World: x east, z south. With `turn` 0 the
## map is north-up; the minimap sets `turn` so the player's heading points up.

## World x/z at the middle of the view.
var centre := Vector2.ZERO
var metres_per_px := 1.5
## Radians the map is turned (screen = world turned by this).
var turn := 0.0
## 0 day .. 1 night: the page dims a little.
var night := 0.0:
	set(value):
		night = value
		if _ground_material:
			_ground_material.set_shader_parameter("night", value)
## Where the player is (world x/z) and which way they face (world yaw, the
## direction of -Z turned by it: rotation.y).
var player := Vector2.INF
var player_yaw := 0.0
## Drawn over the map. Each: {at: Vector2 (world x/z), icon, accent: Color,
## label (optional), kind ("place", "marker", "target"), rim: bool (keep it
## on the edge of the view when it's off it)}.
var pins: Array = []
## The pin under the cursor (index in pins), -1 for none: drawn bigger.
var hot_pin := -1
## The suggested route (world x/z, from where you are to the end), and the
## straight bits it doesn't cover (pairs of world x/z), drawn dotted.
var route := PackedVector2Array()
var route_ends := PackedVector2Array()
## Suburb names (full map only).
var show_suburbs := false
## A circle (the minimap) instead of the whole rect, for pins kept on the rim.
var is_round := false
## Inset (px) for pins kept on the rim.
var rim_inset := 12.0

const ROAD_FILL := [Color("fbf7ee"), Color("fffdf8"), Color("f6d48a"), Color("e8956a")]
const ROAD_CASE := [Color("d8c8a6"), Color("c4b08c"), Color("b5823a"), Color("9a3122")]
const ROAD_MIN_PX := [0.7, 1.1, 1.9, 2.6]
const ROAD_OUTLINE_PX := [0.55, 0.7, 0.85, 1.0]
const GROUND_SHADER := preload("res://shaders/ui/map_ground.gdshader")
const ROAD_SHADER := preload("res://shaders/ui/map_road.gdshader")

var data: MapData
var _world: Node2D
var _ground: Sprite2D
var _ground_material: ShaderMaterial
var _fills: Array[MeshInstance2D] = []
var _cases: Array[MeshInstance2D] = []
var _overlay: Control
var _icons := {}


func _init() -> void:
	# A default, set here so the full map's own (STOP, for drag, wheel and
	# right-click) isn't undone when it's added.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	clip_contents = true
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	data = MapData.shared()
	if data.is_loaded:
		_build()
	else:
		data.loaded.connect(_build, CONNECT_ONE_SHOT)


func _build() -> void:
	if data.ground:
		_ground = Sprite2D.new()
		_ground.texture = data.ground
		_ground.centered = false
		_ground.position = data.ground_rect.position
		_ground.scale = data.ground_rect.size / Vector2(data.ground.get_size())
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = GROUND_SHADER
		_ground_material.set_shader_parameter("night", night)
		_ground.material = _ground_material
		_world.add_child(_ground)
	# All the casings, then all the fills, so junctions join up.
	for pass_fill in [false, true]:
		for cls in data.road_meshes.size():
			var mi := MeshInstance2D.new()
			mi.mesh = data.road_meshes[cls]
			var m := ShaderMaterial.new()
			m.shader = ROAD_SHADER
			m.set_shader_parameter("color", ROAD_FILL[cls] if pass_fill else ROAD_CASE[cls])
			m.set_shader_parameter("min_px", ROAD_MIN_PX[cls])
			m.set_shader_parameter("outline_px", 0.0 if pass_fill else ROAD_OUTLINE_PX[cls])
			mi.material = m
			_world.add_child(mi)
			(_fills if pass_fill else _cases).append(mi)
	_update_world()


func _process(_delta: float) -> void:
	_update_world()
	_overlay.queue_redraw()


func _update_world() -> void:
	_world.transform = Transform2D(turn, Vector2.ONE / metres_per_px, 0.0, size * 0.5) * Transform2D(0.0, -centre)
	# Zoomed out, lanes and then streets fade so the main roads read.
	for cls in _fills.size():
		var fade := 1.0
		match cls:
			MapData.Road.SERVICE:
				fade = 1.0 - smoothstep(2.5, 4.0, metres_per_px)
			MapData.Road.STREET:
				fade = 1.0 - smoothstep(14.0, 30.0, metres_per_px) * 0.75
		_fills[cls].visible = fade > 0.01
		_cases[cls].visible = fade > 0.01
		_fills[cls].self_modulate.a = fade
		_cases[cls].self_modulate.a = fade
	if _ground_material:
		_ground_material.set_shader_parameter("built_amount", smoothstep(2.0, 6.0, metres_per_px))


## Screen position (in this control) of a world x/z.
func to_screen(world: Vector2) -> Vector2:
	return (world - centre).rotated(turn) / metres_per_px + size * 0.5


## World x/z under a screen position in this control.
func to_world(local: Vector2) -> Vector2:
	return ((local - size * 0.5) * metres_per_px).rotated(-turn) + centre


## Index of the pin drawn at a screen position, or -1.
func pin_at(local: Vector2, reach := 14.0) -> int:
	var best := -1
	var best_d := reach * reach
	for i in pins.size():
		var d := to_screen(pins[i].at).distance_squared_to(local)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- drawing -----------------------------------------------------------------

func _draw_overlay() -> void:
	if show_suburbs and data and data.is_loaded:
		_draw_streets()
		_draw_suburbs()
	_draw_route()
	var half := size * 0.5
	var radius := minf(half.x, half.y) - rim_inset
	# Places first, then targets and the player's markers on top.
	for layer in ["place", "marker", "target"]:
		for i in pins.size():
			var pin: Dictionary = pins[i]
			if String(pin.get("kind", "place")) != layer:
				continue
			var at := to_screen(pin.at)
			var on_rim := false
			if is_round:
				var off := at - half
				if off.length() > radius:
					if not pin.get("rim", false):
						continue
					at = half + off.normalized() * radius
					on_rim = true
			else:
				var box := Rect2(Vector2.ZERO, size).grow(-rim_inset)
				if not box.has_point(at):
					if not pin.get("rim", false):
						if not Rect2(Vector2.ZERO, size).grow(16.0).has_point(at):
							continue
					else:
						at = at.clamp(box.position, box.end)
						on_rim = true
			_draw_pin(at, pin, i == hot_pin, on_rim)
	if player != Vector2.INF:
		_draw_player(to_screen(player))


## The route: a red line with an ink edge along the roads, like a pen line
## on a street directory, dotted where it leaves the roads.
func _draw_route() -> void:
	if route.size() < 2 and route_ends.is_empty():
		return
	var view := Rect2(Vector2.ZERO, size).grow(20.0)
	var runs: Array[PackedVector2Array] = []
	var line := PackedVector2Array()
	# Only the stretches on screen (a long route runs off it), thinned to a
	# point every couple of pixels.
	var prev := to_screen(route[0]) if route.size() > 0 else Vector2.ZERO
	for i in range(1, route.size()):
		var at := to_screen(route[i])
		if view.intersects(Rect2(prev, Vector2.ZERO).expand(at)):
			if line.is_empty():
				line.append(prev)
			if at.distance_squared_to(line[line.size() - 1]) > 4.0 or i == route.size() - 1:
				line.append(at)
		elif not line.is_empty():
			if line[line.size() - 1] != prev:
				line.append(prev)
			if line.size() >= 2:
				runs.append(line)
			line = PackedVector2Array()
		prev = at
	if line.size() >= 2:
		runs.append(line)
	for run in runs:
		_overlay.draw_polyline(run, UiStyle.INK, 6.5, true)
	for run in runs:
		_overlay.draw_polyline(run, UiStyle.RED, 3.5, true)
	for i in range(0, route_ends.size() - 1, 2):
		var a := to_screen(route_ends[i])
		var b := to_screen(route_ends[i + 1])
		var n := int(a.distance_to(b) / 7.0)
		for k in n + 1:
			var p := a.lerp(b, float(k) / maxf(n, 1))
			_overlay.draw_circle(p, 2.6, UiStyle.INK)
			_overlay.draw_circle(p, 1.6, UiStyle.RED)


func _draw_pin(at: Vector2, pin: Dictionary, hot: bool, on_rim: bool) -> void:
	var accent: Color = pin.get("accent", UiStyle.RED)
	var kind := String(pin.get("kind", "place"))
	var grow := 1.25 if hot else 1.0
	if kind == "marker":
		# A map pin standing on the spot.
		var tex := _icon("pin", int(26 * grow), accent)
		_overlay.draw_texture(tex, at - Vector2(tex.get_width() * 0.5, tex.get_height() * 0.9))
	else:
		var r := (10.0 if kind == "target" else 8.5) * grow
		_overlay.draw_circle(at + Vector2(1, 2), r + 1.5, UiStyle.SHADOW)
		_overlay.draw_circle(at, r + 1.5, UiStyle.INK)
		_overlay.draw_circle(at, r, accent if kind == "target" else UiStyle.PAPER)
		var ink := UiStyle.CREAM_TEXT if kind == "target" else UiStyle.INK
		var tex := _icon(String(pin.get("icon", "dot")), int(r * 1.5), accent, ink)
		_overlay.draw_texture(tex, at - Vector2(tex.get_size()) * 0.5)
	if (hot or (kind == "marker" and not on_rim and show_suburbs)) and String(pin.get("label", "")) != "":
		_draw_tag(at + Vector2(0, -30 if kind == "marker" else -18), String(pin.label), hot)


## A little cream tag with a name in it, centred above `at`.
func _draw_tag(at: Vector2, text: String, bold: bool) -> void:
	var font := UiStyle.BOLD_FONT if bold else UiStyle.BODY_FONT
	var fs := 13
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(at.x - w * 0.5 - 6, at.y - 17, w + 12, 20)
	_overlay.draw_style_box(UiStyle.box(UiStyle.PAPER, UiStyle.INK, 1, 6, 0), box)
	_overlay.draw_string(font, Vector2(box.position.x + 6, box.position.y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.INK)


func _draw_player(at: Vector2) -> void:
	# The player's yaw points -Z (north at yaw 0); on screen that's up when
	# the map isn't turned.
	var a := -player_yaw + turn
	var pts := PackedVector2Array([Vector2(0, -11), Vector2(8, 8), Vector2(0, 4), Vector2(-8, 8)])
	var out := PackedVector2Array()
	var shadow := PackedVector2Array()
	for p in pts:
		out.append(at + p.rotated(a))
		shadow.append(at + p.rotated(a) * 1.25 + Vector2(1, 2))
	_overlay.draw_colored_polygon(shadow, UiStyle.SHADOW)
	var rim := PackedVector2Array()
	for p in pts:
		rim.append(at + (p * 1.28).rotated(a))
	_overlay.draw_colored_polygon(rim, UiStyle.INK)
	_overlay.draw_colored_polygon(out, UiStyle.RED)
	var closed := out.duplicate()
	closed.append(out[0])
	_overlay.draw_polyline(closed, UiStyle.CREAM_TEXT, 1.2, true)


## Street names along the roads, close in, like a street directory.
func _draw_streets() -> void:
	var alpha := 1.0 - smoothstep(2.4, 3.4, metres_per_px)
	if alpha <= 0.01:
		return
	var view := Rect2(Vector2.ZERO, size).grow(80)
	var placed: Array[Rect2] = []
	var fs := 11
	for l: Array in data.labels:
		var at := to_screen(l[1])
		if not view.has_point(at):
			continue
		var text := String(l[0])
		var font := UiStyle.BOLD_FONT if int(l[4]) >= MapData.Road.MAIN else UiStyle.BODY_FONT
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if float(l[3]) / metres_per_px < w + 16.0:
			continue  # the road's too short on screen for its name
		var box := Rect2(at - Vector2(w, w) * 0.5, Vector2(w, w)).grow(-w * 0.3)
		var clash := false
		for r in placed:
			if r.intersects(box):
				clash = true
				break
		if clash:
			continue
		placed.append(box)
		var angle := float(l[2]) + turn
		_overlay.draw_set_transform(at, angle)
		var p := Vector2(-w * 0.5, 4)
		_overlay.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(UiStyle.PAPER, alpha * 0.9))
		_overlay.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiStyle.INK_2, alpha))
	_overlay.draw_set_transform(Vector2.ZERO)


func _draw_suburbs() -> void:
	var alpha := smoothstep(3.0, 6.0, metres_per_px) * (1.0 - smoothstep(40.0, 70.0, metres_per_px))
	if alpha <= 0.01:
		return
	var font := UiStyle.spaced_font()
	var fs := 12
	var col := Color(UiStyle.INK_2, alpha * 0.9)
	var outline := Color(UiStyle.PAPER, alpha * 0.85)
	var view := Rect2(Vector2.ZERO, size)
	for s: Array in data.suburbs:
		var at := to_screen(s[1])
		if not view.grow(60).has_point(at):
			continue
		var text := String(s[0]).to_upper()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := at - Vector2(w * 0.5, -4)
		_overlay.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, outline)
		_overlay.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# --- icons -------------------------------------------------------------------

## Map glyphs UiStyle doesn't have, in its inline-SVG style ({c} ink, {a} accent).
const GLYPHS := {
	"home": "<path d='M3.5 11.5L12 4l8.5 7.5' fill='none' stroke='{c}' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/><path d='M6 10v10h12V10' fill='{a}' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><rect x='10' y='14' width='4' height='6' fill='#fff4dd' stroke='{c}' stroke-width='1.4'/>",
	"shop": "<path d='M5 8h14l-1.2 12.5H6.2z' fill='{a}' stroke='{c}' stroke-width='2' stroke-linejoin='round'/><path d='M9 10V7a3 3 0 0 1 6 0v3' fill='none' stroke='{c}' stroke-width='2' stroke-linecap='round'/>",
	"park": "<rect x='3.5' y='3.5' width='17' height='17' rx='3' fill='{a}' stroke='{c}' stroke-width='2'/><path d='M9.5 17V7h3.5a3 3 0 0 1 0 6H9.5' fill='none' stroke='#fff4dd' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/>",
	"quiet": "<path d='M12 3c3 4 5 6.5 5 9.5a5 5 0 0 1-10 0C7 9.5 9 7 12 3z' fill='{a}' stroke='{c}' stroke-width='1.8' stroke-linejoin='round'/><path d='M12 21v-6' stroke='{c}' stroke-width='1.8' stroke-linecap='round'/>",
	"north": "<path d='M12 2.5l5.5 15L12 14l-5.5 3.5z' fill='{a}' stroke='{c}' stroke-width='1.6' stroke-linejoin='round'/>",
}


func _icon(name: String, px: int, accent: Color, ink := UiStyle.INK) -> Texture2D:
	if not GLYPHS.has(name):
		return UiStyle.icon(name, px, ink, Vector2.ZERO, accent)
	return glyph(name, px, ink, accent)


static var _glyphs := {}


static func glyph(name: String, px: int, ink := UiStyle.INK, accent := UiStyle.RED) -> Texture2D:
	var key := "%s/%d/%s/%s" % [name, px, ink.to_html(), accent.to_html()]
	if _glyphs.has(key):
		return _glyphs[key]
	var body := String(GLYPHS.get(name, "")).replace("{c}", "#" + ink.to_html(false)).replace("{a}", "#" + accent.to_html(false))
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 24 24'>%s</svg>" % [px * 4, px * 4, body]
	var image := Image.new()
	var tex: Texture2D
	if image.load_svg_from_string(svg, 1.0) == OK:
		image.resize(px, px, Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(image)
	else:
		tex = ImageTexture.create_from_image(Image.create(maxi(px, 1), maxi(px, 1), false, Image.FORMAT_RGBA8))
	_glyphs[key] = tex
	return tex
