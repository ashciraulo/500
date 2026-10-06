class_name SpeciesIcon
## Little field-guide plates for the journal, the catch card and the shops: a
## side-on bird or fish in its own colours with an ink outline, drawn from the
## species' "shape" and "colours" in data/field, so a new species gets one for
## free. Unseen species can be drawn as a pale pencil silhouette.
##
##   button.icon = SpeciesIcon.bird(FieldJournal.bird(id), 32)
##   rect.texture = SpeciesIcon.fish(FieldJournal.fish_species(id), 96, true)  # silhouette

const SILHOUETTE := Color("cfc2a6")
const OUTLINE := Color("2a231e")

## Per bird shape. tilt: body angle (deg, negative = front up). rx/ry: body.
## neck: [length, angle, curl]. head: radius. beak: [kind, length, depth].
## tail: [length, width, angle, kind]. legs: length (0 = none). Flags: swim,
## crest, face (an owl's disc), wing: how far the wing reaches past the body.
const BIRDS := {
	"songbird": {"tilt": -25, "rx": 10.5, "ry": 6.5, "neck": [2.5, -60, 0], "head": 5.0, "beak": ["straight", 5.0, 2.2], "tail": [11, 4.0, 20, "long"], "legs": 6},
	"wader": {"tilt": -12, "rx": 10.5, "ry": 6.0, "neck": [7.0, -60, 0.3], "head": 3.8, "beak": ["straight", 9.0, 1.6], "tail": [6, 4.5, 10, "short"], "legs": 14},
	"parrot": {"tilt": -55, "rx": 9.5, "ry": 6.0, "neck": [1.5, -40, 0], "head": 5.2, "beak": ["hook", 3.6, 3.4], "tail": [14, 3.4, 8, "long"], "legs": 3},
	"dove": {"tilt": -18, "rx": 10.5, "ry": 7.0, "neck": [3.0, -50, 0], "head": 4.2, "beak": ["straight", 3.2, 1.4], "tail": [10, 4.4, 15, "long"], "legs": 4},
	"cockatoo": {"tilt": -55, "rx": 10.5, "ry": 7.2, "neck": [1.5, -40, 0], "head": 6.0, "beak": ["hook", 4.6, 4.6], "tail": [11, 4.4, 8, "long"], "legs": 3, "crest": true},
	"kookaburra": {"tilt": -35, "rx": 9.5, "ry": 7.0, "neck": [1.0, -40, 0], "head": 7.0, "beak": ["straight", 9.0, 3.6], "tail": [10, 4.2, 15, "long"], "legs": 3},
	"swan": {"tilt": 4, "rx": 13.5, "ry": 6.5, "neck": [15.0, -82, -0.55], "head": 3.2, "beak": ["flat", 5.0, 1.8], "tail": [4, 4.0, -25, "short"], "legs": 0, "swim": true},
	"pelican": {"tilt": 0, "rx": 13.5, "ry": 7.5, "neck": [6.0, -70, 0.2], "head": 4.0, "beak": ["pouch", 14.0, 3.6], "tail": [4, 4.0, -15, "short"], "legs": 0, "swim": true},
	"duck": {"tilt": 0, "rx": 11.5, "ry": 6.2, "neck": [4.0, -72, 0], "head": 4.6, "beak": ["flat", 4.8, 2.0], "tail": [4, 3.6, -25, "short"], "legs": 0, "swim": true},
	"rail": {"tilt": -18, "rx": 9.5, "ry": 6.8, "neck": [3.5, -55, 0], "head": 4.2, "beak": ["cone", 4.4, 3.2], "tail": [5, 3.6, -35, "short"], "legs": 9},
	"cormorant": {"tilt": -50, "rx": 11.0, "ry": 5.6, "neck": [6.5, -60, -0.2], "head": 3.6, "beak": ["hook", 6.5, 1.6], "tail": [9, 3.0, 5, "long"], "legs": 3},
	"gull": {"tilt": -8, "rx": 11.5, "ry": 6.6, "neck": [3.0, -55, 0], "head": 4.8, "beak": ["straight", 6.0, 2.0], "tail": [6, 4.4, 5, "short"], "legs": 6, "wing": 7.0},
	"raptor": {"tilt": -62, "rx": 10.5, "ry": 7.2, "neck": [1.5, -40, 0], "head": 5.2, "beak": ["hook", 3.8, 3.0], "tail": [11, 4.8, 5, "long"], "legs": 4},
	"heron": {"tilt": -25, "rx": 9.5, "ry": 5.6, "neck": [12.0, -70, -0.45], "head": 3.6, "beak": ["straight", 9.0, 2.0], "tail": [4, 4.0, 10, "short"], "legs": 14},
	"frogmouth": {"tilt": -78, "rx": 12.5, "ry": 7.8, "neck": [0.5, -20, 0], "head": 6.8, "beak": ["wide", 4.0, 4.6], "tail": [8, 4.8, 5, "long"], "legs": 2},
	"owl": {"tilt": -82, "rx": 11.0, "ry": 8.0, "neck": [0.5, -20, 0], "head": 7.4, "beak": ["hook", 2.2, 2.2], "tail": [5, 4.6, 5, "short"], "legs": 3, "face": true},
	"swallow": {"tilt": -10, "rx": 8.5, "ry": 4.8, "neck": [1.5, -40, 0], "head": 4.2, "beak": ["straight", 3.0, 1.6], "tail": [13, 4.2, 12, "fork"], "legs": 3, "wing": 9.0},
	"wren": {"tilt": -15, "rx": 6.8, "ry": 5.4, "neck": [1.5, -50, 0], "head": 4.4, "beak": ["straight", 3.2, 1.4], "tail": [11, 2.6, -62, "long"], "legs": 5},
}

## A few species the shape table can't tell apart.
const BIRD_TWEAKS := {
	"australian_white_ibis": {"beak": ["curve", 12.0, 1.8]},
	"pied_oystercatcher": {"beak": ["straight", 9.0, 1.8], "legs": 8},
	"black_winged_stilt": {"legs": 18, "beak": ["straight", 8.0, 1.0]},
	"crested_tern": {"crest": true, "beak": ["straight", 8.0, 2.0]},
	"australasian_darter": {"neck": [13.0, -55, 0.6], "beak": ["straight", 7.0, 1.4]},
	"rainbow_bee_eater": {"beak": ["curve", 6.5, 1.4]},
	"purple_swamphen": {"beak": ["cone", 5.0, 4.0], "legs": 11},
	"great_egret": {"neck": [15.0, -72, -0.5]},
	"nankeen_night_heron": {"neck": [4.0, -55, 0]},
	"musk_duck": {"tail": [8, 4.0, -40, "short"]},
}

## Per fish shape. depth: body depth over length. snout: how pointed (0-1).
## tail: "fork", "lunate", "round", "square". fins: dorsal fins.
const FISH := {
	"bream": {"depth": 0.42, "snout": 0.35, "tail": "fork", "fins": "spiny"},
	"torpedo": {"depth": 0.25, "snout": 0.55, "tail": "fork", "fins": "two"},
	"whiting": {"depth": 0.2, "snout": 0.8, "tail": "fork", "fins": "two"},
	"flathead": {"depth": 0.17, "snout": 0.15, "tail": "round", "fins": "two", "flat": true},
	"trevally": {"depth": 0.4, "snout": 0.5, "tail": "lunate", "fins": "two"},
	"garfish": {"depth": 0.1, "snout": 1.0, "tail": "fork", "fins": "back", "beak": true},
	"mulloway": {"depth": 0.27, "snout": 0.4, "tail": "square", "fins": "two"},
	"blowie": {"depth": 0.46, "snout": 0.2, "tail": "round", "fins": "small"},
}

static var _cache := {}


## A bird's plate, px wide and high. silhouette: a pale shape, no colours (unseen).
static func bird(species: Dictionary, px := 32, silhouette := false) -> Texture2D:
	if species.is_empty():
		return UiStyle.icon("bird", px, UiStyle.INK_3, Vector2.ZERO, UiStyle.PAPER_3)
	var key := "b/%s/%d/%s" % [species.get("id", ""), px, silhouette]
	if not _cache.has(key):
		_cache[key] = _render(_bird_svg(species, silhouette), Vector2i(px, px))
	return _cache[key]


## A fish's plate, px wide (a little shorter than wide).
static func fish(species: Dictionary, px := 40, silhouette := false) -> Texture2D:
	if species.is_empty():
		return UiStyle.icon("fish", px, UiStyle.INK_3, Vector2.ZERO, UiStyle.PAPER_3)
	var key := "f/%s/%d/%s" % [species.get("id", ""), px, silhouette]
	if not _cache.has(key):
		_cache[key] = _render(_fish_svg(species, silhouette), Vector2i(px, roundi(px * 0.75)))
	return _cache[key]


## An empty square, to keep list rows lined up.
static func blank(px := 30) -> Texture2D:
	var key := "blank/%d" % px
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(Image.create(px, px, false, Image.FORMAT_RGBA8))
	return _cache[key]


# --- birds ---------------------------------------------------------------------------------

static func _bird_svg(species: Dictionary, silhouette: bool) -> Array:
	var p: Dictionary = BIRDS.get(String(species.get("model", "songbird")), BIRDS.songbird).duplicate()
	p.merge(BIRD_TWEAKS.get(String(species.get("id", "")), {}), true)
	var c: Dictionary = species.get("colours", {})
	var col := func(k: String, fallback: String) -> String:
		if silhouette:
			return "#" + SILHOUETTE.to_html(false)
		return String(c.get(k, c.get(fallback, "#8a8070")))
	var ink := "#" + (SILHOUETTE.darkened(0.25) if silhouette else OUTLINE).to_html(false)
	var sw := 1.1
	var parts := PackedStringArray()
	var pts := PackedVector2Array()

	var tilt := deg_to_rad(float(p.tilt))
	var rx: float = p.rx
	var ry: float = p.ry
	var centre := Vector2(0, 0)
	var basis := func(v: Vector2) -> Vector2: return centre + v.rotated(tilt)
	# Bounds of the body: a few points round the ellipse.
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(basis.call(Vector2(cos(a) * rx, sin(a) * ry)))

	# Legs first, under everything.
	var legs: float = p.get("legs", 0)
	if legs > 0 and not p.get("swim", false):
		var hip: Vector2 = basis.call(Vector2(rx * 0.05, ry * 0.75))
		var foot := hip + Vector2(0.6, legs)
		var leg_col: String = col.call("legs", "beak")
		parts.append("<path d='M%s L%s M%s l3.2 0 M%s l-2 0' stroke='%s' stroke-width='1.3' stroke-linecap='round' fill='none'/>" % [
			_p(hip), _p(foot), _p(foot), _p(foot), leg_col if not silhouette else ink])
		pts.append(foot + Vector2(3.2, 0))
		pts.append(foot - Vector2(2, 0))

	# Tail from the rump.
	var tail: Array = p.tail
	var t_len: float = tail[0]
	var t_w: float = tail[1]
	var t_ang := deg_to_rad(float(tail[2]))
	var rump: Vector2 = basis.call(Vector2(-rx * 0.8, -ry * 0.1))
	var t_dir := Vector2.LEFT.rotated(tilt + t_ang)
	var t_side := t_dir.orthogonal()
	var t_tip := rump + t_dir * t_len
	var tail_pts: PackedVector2Array
	match String(tail[3]):
		"fork":
			tail_pts = [rump + t_side * t_w * 0.6, t_tip + t_side * t_w * 0.9, rump + t_dir * t_len * 0.55, t_tip - t_side * t_w * 0.5, rump - t_side * t_w * 0.6]
		"short":
			tail_pts = [rump + t_side * t_w * 0.7, t_tip + t_side * t_w * 0.5, t_tip - t_side * t_w * 0.5, rump - t_side * t_w * 0.7]
		_:
			tail_pts = [rump + t_side * t_w * 0.5, t_tip + t_side * t_w * 0.55, t_tip + t_dir * 0.8, t_tip - t_side * t_w * 0.55, rump - t_side * t_w * 0.5]
	parts.append(_poly(tail_pts, col.call("tail", "wing"), ink, sw))
	pts.append_array(tail_pts)

	# Body, then the belly (lower half) over it.
	var deg := rad_to_deg(tilt)
	parts.append("<ellipse cx='0' cy='0' rx='%.2f' ry='%.2f' transform='rotate(%.1f)' fill='%s' stroke='%s' stroke-width='%.2f'/>" % [
		rx, ry, deg, col.call("body", "body"), ink, sw])
	if not silhouette and c.has("belly") and c.belly != c.get("body", ""):
		parts.append("<path d='M%.2f 0 A%.2f %.2f 0 0 0 %.2f 0 Z' transform='rotate(%.1f) translate(0 %.2f)' fill='%s'/>" % [
			-rx * 0.86, rx * 0.86, ry * 0.8, rx * 0.86, deg, ry * 0.12, c.belly])

	# Neck and head.
	var neck: Array = p.neck
	var shoulder: Vector2 = basis.call(Vector2(rx * 0.72, -ry * 0.35))
	var n_dir := Vector2.RIGHT.rotated(deg_to_rad(float(neck[1])))
	var head_at := shoulder + n_dir * float(neck[0])
	var head_r: float = p.head
	var neck_col: String = col.call("neck", "head") if c.has("neck") else col.call("body", "body")
	if float(neck[0]) > 2.0:
		var bend := (head_at - shoulder).orthogonal() * float(neck[2])
		var ctrl := (shoulder + head_at) * 0.5 + bend
		var thick := maxf(head_r * 1.1, 2.4)
		parts.append("<path d='M%s Q%s %s' stroke='%s' stroke-width='%.2f' fill='none' stroke-linecap='round'/>" % [
			_p(shoulder), _p(ctrl), _p(head_at), ink, thick + sw * 2])
		parts.append("<path d='M%s Q%s %s' stroke='%s' stroke-width='%.2f' fill='none' stroke-linecap='round'/>" % [
			_p(shoulder), _p(ctrl), _p(head_at), neck_col, thick])
		pts.append(ctrl)

	# Wing over the body.
	var wing_reach: float = p.get("wing", 2.0)
	var w0: Vector2 = basis.call(Vector2(rx * 0.55, -ry * 0.45))
	var w1: Vector2 = basis.call(Vector2(-rx - wing_reach, -ry * 0.05))
	var w_mid: Vector2 = basis.call(Vector2(-rx * 0.2, ry * 0.55))
	var w_top: Vector2 = basis.call(Vector2(-rx * 0.1, -ry * 0.85))
	parts.append("<path d='M%s Q%s %s Q%s %s Z' fill='%s' stroke='%s' stroke-width='%.2f' stroke-linejoin='round'/>" % [
		_p(w0), _p(w_mid), _p(w1), _p(w_top), _p(w0), col.call("wing", "body"), ink, sw])
	pts.append(w1)

	# Crest behind the head.
	if p.get("crest", false):
		var crest := PackedVector2Array([head_at + Vector2(-head_r * 0.2, -head_r * 0.7), head_at + Vector2(-head_r * 1.9, -head_r * 1.5),
			head_at + Vector2(-head_r * 1.2, -head_r * 0.5), head_at + Vector2(-head_r * 1.7, -head_r * 0.6), head_at + Vector2(-head_r * 0.7, -head_r * 0.1)])
		parts.append(_poly(crest, col.call("accent", "head") if String(species.get("model", "")) == "cockatoo" else col.call("head", "body"), ink, sw))
		pts.append_array(crest)

	parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='%s' stroke='%s' stroke-width='%.2f'/>" % [
		head_at.x, head_at.y, head_r, col.call("head", "body"), ink, sw])
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		pts.append(head_at + Vector2(cos(a), sin(a)) * head_r)
	var face: bool = p.get("face", false)
	if face:
		# An owl looks at you: a pale disc, two eyes and a little hooked beak.
		if not silhouette:
			var disc := String(c.get("belly", c.get("accent", "#e8dcc4")))
			parts.append("<ellipse cx='%.2f' cy='%.2f' rx='%.2f' ry='%.2f' fill='%s' stroke='%s' stroke-width='0.7'/>" % [
				head_at.x, head_at.y + head_r * 0.05, head_r * 0.82, head_r * 0.72, disc, ink])
			for s_x in [-1.0, 1.0]:
				var e := head_at + Vector2(s_x * head_r * 0.36, -head_r * 0.08)
				parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='%s' stroke='%s' stroke-width='0.6'/>" % [e.x, e.y, head_r * 0.24, c.get("eye", "#e8a21e"), ink])
				parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='#2a231e'/>" % [e.x, e.y, head_r * 0.12])
		var nb := PackedVector2Array([head_at + Vector2(-head_r * 0.12, head_r * 0.12), head_at + Vector2(head_r * 0.12, head_r * 0.12), head_at + Vector2(0, head_r * 0.42)])
		parts.append(_poly(nb, col.call("beak", "head"), ink, sw * 0.6))
		pts.append_array(nb)
	else:
		# Beak.
		var beak: Array = p.beak
		var b_len: float = beak[1]
		var b_d: float = beak[2]
		var b_root := head_at + Vector2(head_r * 0.82, head_r * 0.1)
		var beak_col: String = col.call("beak", "head")
		var bp: PackedVector2Array
		match String(beak[0]):
			"hook":
				bp = [b_root + Vector2(0, -b_d * 0.5), b_root + Vector2(b_len * 0.8, -b_d * 0.45), b_root + Vector2(b_len, b_d * 0.3),
					b_root + Vector2(b_len * 0.7, b_d * 0.55), b_root + Vector2(0, b_d * 0.5)]
			"curve":
				bp = [b_root + Vector2(0, -b_d * 0.5), b_root + Vector2(b_len * 0.55, -b_d * 0.2), b_root + Vector2(b_len * 0.95, b_len * 0.42),
					b_root + Vector2(b_len * 0.5, b_d * 0.5), b_root + Vector2(0, b_d * 0.5)]
			"pouch":
				bp = [b_root + Vector2(0, -b_d * 0.5), b_root + Vector2(b_len, -b_d * 0.15), b_root + Vector2(b_len * 0.9, b_d * 0.3),
					b_root + Vector2(b_len * 0.45, b_d * 1.5), b_root + Vector2(0, b_d * 0.6)]
			"flat":
				bp = [b_root + Vector2(0, -b_d * 0.5), b_root + Vector2(b_len, -b_d * 0.1), b_root + Vector2(b_len, b_d * 0.4), b_root + Vector2(0, b_d * 0.5)]
			"wide":
				bp = [b_root + Vector2(-head_r * 0.2, -b_d * 0.3), b_root + Vector2(b_len * 0.6, 0), b_root + Vector2(-head_r * 0.2, b_d * 0.5)]
			_:  # straight, cone
				bp = [b_root + Vector2(0, -b_d * 0.5), b_root + Vector2(b_len, 0), b_root + Vector2(0, b_d * 0.5)]
		parts.append(_poly(bp, beak_col, ink, sw * 0.8))
		pts.append_array(bp)

		# Eye.
		var eye := head_at + Vector2(head_r * 0.3, -head_r * 0.15)
		if not silhouette:
			parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='%s'/>" % [eye.x, eye.y, maxf(head_r * 0.2, 0.9), "#" + OUTLINE.to_html(false)])
			parts.append("<circle cx='%.2f' cy='%.2f' r='0.45' fill='#fff4dd'/>" % [eye.x + 0.3, eye.y - 0.35])

	# Water for the swimmers, over the lower body.
	if p.get("swim", false):
		var y := ry * 0.35
		var x0 := -rx - 6.0
		var x1 := rx + 4.0
		var water := "#" + (SILHOUETTE.lightened(0.2) if silhouette else UiStyle.TEAL_LIGHT).to_html(false)
		parts.append("<path d='M%.2f %.2f q2 -1.4 4 0 t4 0 t4 0 t4 0 t4 0 t4 0 t4 0 t4 0 t4 0 V%.2f H%.2f Z' fill='%s' stroke='%s' stroke-width='%.2f' stroke-linejoin='round'/>" % [
			x0, y, ry + 3.0, x0, water, ink, sw])
		pts.append(Vector2(x0, ry + 3.0))
		pts.append(Vector2(x1, ry + 3.0))
	return [parts, pts]


# --- fish ----------------------------------------------------------------------------------

static func _fish_svg(species: Dictionary, silhouette: bool) -> Array:
	var c: Dictionary = species.get("colours", {})
	var col := func(k: String, fallback: String) -> String:
		if silhouette:
			return "#" + SILHOUETTE.to_html(false)
		return String(c.get(k, c.get(fallback, "#8a8070")))
	var ink := "#" + (SILHOUETTE.darkened(0.25) if silhouette else OUTLINE).to_html(false)
	var shape := String(species.get("model", "bream"))
	match shape:
		"squid":
			return _squid(col, ink, silhouette)
		"crab":
			return _crab(col, ink, silhouette)
		"hubcap":
			return _hubcap(col, ink, silhouette)
	var p: Dictionary = FISH.get(shape, FISH.bream)
	var parts := PackedStringArray()
	var pts := PackedVector2Array()
	var L := 40.0
	var d: float = L * float(p.depth)
	var x0 := 0.0  # snout
	var x1 := L * 0.8  # tail root
	var mid := L * 0.32  # deepest point
	var top := -d * 0.5
	var bot := d * 0.5
	var snout_y := d * 0.05
	var sharp: float = p.snout
	var peduncle := maxf(d * 0.14, 1.2)
	var sw := 1.1

	# Tail.
	var tail_h := maxf(d * 0.75, 6.0)
	var tx := x1 + L * 0.2
	var tail_pts: PackedVector2Array
	match String(p.tail):
		"fork":
			tail_pts = [Vector2(x1 - 1, -peduncle), Vector2(tx, -tail_h * 0.6), Vector2(tx - L * 0.07, 0), Vector2(tx, tail_h * 0.6), Vector2(x1 - 1, peduncle)]
		"lunate":
			tail_pts = [Vector2(x1 - 1, -peduncle), Vector2(tx + 1, -tail_h * 0.7), Vector2(tx - L * 0.1, 0), Vector2(tx + 1, tail_h * 0.7), Vector2(x1 - 1, peduncle)]
		"square":
			tail_pts = [Vector2(x1 - 1, -peduncle), Vector2(tx, -tail_h * 0.5), Vector2(tx + 0.5, 0), Vector2(tx, tail_h * 0.5), Vector2(x1 - 1, peduncle)]
		_:  # round
			tail_pts = [Vector2(x1 - 1, -peduncle), Vector2(tx - 2, -tail_h * 0.45), Vector2(tx, 0), Vector2(tx - 2, tail_h * 0.45), Vector2(x1 - 1, peduncle)]
	parts.append(_poly(tail_pts, col.call("fin", "back"), ink, sw))
	pts.append_array(tail_pts)

	# Dorsal fins.
	match String(p.fins):
		"spiny":
			var f := PackedVector2Array([Vector2(mid - 6, top + 0.8), Vector2(mid - 3, top - d * 0.32), Vector2(mid + 5, top - d * 0.28), Vector2(mid + 12, top - d * 0.12), Vector2(mid + 14, top + 2.2)])
			parts.append(_poly(f, col.call("fin", "back"), ink, sw))
			pts.append_array(f)
		"two":
			var f1 := PackedVector2Array([Vector2(mid - 4, top + 0.6), Vector2(mid - 1, top - d * 0.38 - 1.5), Vector2(mid + 4, top + 0.6)])
			var f2 := PackedVector2Array([Vector2(mid + 7, top + 1.0), Vector2(mid + 10, top - d * 0.3 - 1.0), Vector2(mid + 16, top + 2.4)])
			parts.append(_poly(f1, col.call("fin", "back"), ink, sw))
			parts.append(_poly(f2, col.call("fin", "back"), ink, sw))
			pts.append_array(f1)
			pts.append_array(f2)
		"back":
			var f := PackedVector2Array([Vector2(x1 - 9, top + 1.4), Vector2(x1 - 5, top - 2.2), Vector2(x1 - 2, -peduncle)])
			parts.append(_poly(f, col.call("fin", "back"), ink, sw))
			pts.append_array(f)
		_:
			var f := PackedVector2Array([Vector2(mid + 6, top + 1.5), Vector2(mid + 9, top - 2.5), Vector2(mid + 12, top + 3.0)])
			parts.append(_poly(f, col.call("fin", "back"), ink, sw))
	# Anal fin.
	var af := PackedVector2Array([Vector2(mid + 8, bot - 0.8), Vector2(mid + 12, bot + d * 0.22 + 1.0), Vector2(mid + 15, bot - 2.4)])
	parts.append(_poly(af, col.call("fin", "back"), ink, sw))
	pts.append_array(af)

	# Body: snout to tail root along the back, back again along the belly.
	var nose := Vector2(x0, snout_y)
	var body := "M%s C%.2f %.2f %.2f %.2f %.2f %.2f C%.2f %.2f %.2f %.2f %.2f %.2f L%.2f %.2f C%.2f %.2f %.2f %.2f %.2f %.2f C%.2f %.2f %.2f %.2f %s Z" % [
		_p(nose),
		x0 + L * 0.04 * (1.0 - sharp), top * (1.0 - sharp * 0.7), mid - 8, top, mid, top,
		mid + 8, top, x1 - 4, -peduncle * 1.6, x1, -peduncle,
		x1, peduncle,
		x1 - 4, peduncle * 1.6, mid + 8, bot, mid, bot,
		mid - 8, bot, x0 + L * 0.04 * (1.0 - sharp), bot * (1.0 - sharp * 0.6), _p(nose)]
	var gid := "g%d" % (hash(String(species.get("id", ""))) & 0xffff)
	if not silhouette:
		parts.append("<defs><linearGradient id='%s' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='%s'/><stop offset='0.48' stop-color='%s'/><stop offset='0.62' stop-color='%s'/><stop offset='1' stop-color='%s'/></linearGradient></defs>" % [
			gid, col.call("back", "body"), col.call("back", "body"), col.call("belly", "back"), col.call("belly", "back")])
	parts.append("<path d='%s' fill='%s' stroke='%s' stroke-width='%.2f' stroke-linejoin='round'/>" % [
		body, ("url(#%s)" % gid) if not silhouette else col.call("back", "body"), ink, sw])
	pts.append_array([Vector2(x0, top), Vector2(x0, bot), Vector2(x1, top), Vector2(x1, bot)])
	if p.get("beak", false):
		var bk := PackedVector2Array([Vector2(x0 + 1, snout_y + 0.2), Vector2(x0 - 7, snout_y + 0.9), Vector2(x0 + 1, snout_y + 1.4)])
		parts.append(_poly(bk, col.call("mark", "back"), ink, sw * 0.7))
		pts.append_array(bk)

	if not silhouette:
		# Gill line, a lateral line or bars, the eye and the pectoral fin.
		var gx := L * 0.17
		parts.append("<path d='M%.2f %.2f Q%.2f 0 %.2f %.2f' stroke='%s' stroke-width='0.8' fill='none' opacity='0.7'/>" % [gx, top * 0.7, gx + 2.2, gx, bot * 0.7, ink])
		if shape in ["torpedo", "trevally", "mulloway", "whiting", "garfish"]:
			parts.append("<path d='M%.2f %.2f Q%.2f %.2f %.2f 0' stroke='%s' stroke-width='0.8' fill='none' opacity='0.6'/>" % [gx + 2, top * 0.25, mid + 6, top * 0.3, x1, col.call("mark", "back")])
		elif shape == "bream" or shape == "blowie" or shape == "flathead":
			for i in 4:
				var bx := mid - 4 + i * 5.5
				parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='%s' opacity='0.55'/>" % [bx, top * 0.35, maxf(d * 0.06, 0.8), col.call("mark", "back")])
		var ex := L * 0.08 + (2.0 if sharp > 0.7 else 0.0)
		var er := maxf(d * 0.09, 1.3)
		parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='#fff4dd' stroke='%s' stroke-width='0.6'/>" % [ex, top * 0.3, er, ink])
		parts.append("<circle cx='%.2f' cy='%.2f' r='%.2f' fill='#2a231e'/>" % [ex + 0.2, top * 0.3, er * 0.55])
		var pf := PackedVector2Array([Vector2(gx + 2, bot * 0.25), Vector2(gx + 8, bot * 0.55), Vector2(gx + 2.5, bot * 0.6)])
		parts.append(_poly(pf, col.call("fin", "back"), ink, 0.8))
	return [parts, pts]


static func _squid(col: Callable, ink: String, silhouette: bool) -> Array:
	var parts := PackedStringArray()
	var mantle := PackedVector2Array([Vector2(34, 0), Vector2(26, -4.5), Vector2(10, -4.0), Vector2(9, 4.0), Vector2(26, 4.5)])
	var fin := PackedVector2Array([Vector2(36, 0), Vector2(29, -7.5), Vector2(25, 0), Vector2(29, 7.5)])
	parts.append(_poly(fin, col.call("fin", "back"), ink, 1.1))
	for i in 5:
		var y := -3.0 + i * 1.5
		parts.append("<path d='M9 %.2f Q3 %.2f -%.2f %.2f' stroke='%s' stroke-width='1.6' fill='none' stroke-linecap='round'/>" % [y, y * 1.4, 2.0 + (i % 2) * 3.0, y * 1.9, col.call("mark", "back")])
	parts.append("<path d='M%s Q%s %s Q%s %s Z' fill='%s' stroke='%s' stroke-width='1.1'/>" % [
		_p(mantle[0]), _p(Vector2(22, -6.5)), _p(mantle[2]), _p(Vector2(22, 6.5)), _p(mantle[0]), col.call("back", "body"), ink])
	parts.append("<ellipse cx='10.5' cy='0' rx='3' ry='3.6' fill='%s' stroke='%s' stroke-width='1.1'/>" % [col.call("belly", "back"), ink])
	if not silhouette:
		parts.append("<circle cx='10' cy='-0.6' r='1.4' fill='#2a231e'/>")
	return [parts, PackedVector2Array([Vector2(-5, -8), Vector2(36, 8)])]


static func _crab(col: Callable, ink: String, silhouette: bool) -> Array:
	var parts := PackedStringArray()
	for s in [-1.0, 1.0]:
		# Legs and a swimming paddle, then the long claws.
		for i in 3:
			parts.append("<path d='M%.2f %.2f l%.2f %.2f l%.2f %.2f' stroke='%s' stroke-width='1.6' fill='none' stroke-linecap='round' stroke-linejoin='round'/>" % [
				s * 4.0, 2.0 + i * 1.5, s * 6.0, 3.0 + i, s * 2.0, 3.5, col.call("fin", "back")])
		parts.append("<ellipse cx='%.2f' cy='9' rx='3' ry='1.8' transform='rotate(%.1f %.2f 9)' fill='%s' stroke='%s' stroke-width='0.9'/>" % [
			s * 12.0, s * 30.0, s * 12.0, col.call("fin", "back"), ink])
		parts.append("<path d='M%.2f -2 l%.2f -5 l%.2f -1' stroke='%s' stroke-width='2.2' fill='none' stroke-linecap='round'/>" % [s * 8.0, s * 5.0, -s * 4.0, col.call("back", "body")])
		parts.append("<path d='M%.2f -8 l%.2f -3 l%.2f 1.2 z' fill='%s' stroke='%s' stroke-width='0.9' stroke-linejoin='round'/>" % [s * 9.0, -s * 6.0, s * 1.0, col.call("mark", "back"), ink])
	parts.append("<path d='M-15 -1 L-6 -4.5 L6 -4.5 L15 -1 L6 4 L-6 4 Z' fill='%s' stroke='%s' stroke-width='1.1' stroke-linejoin='round'/>" % [col.call("back", "body"), ink])
	if not silhouette:
		for x in [-5.0, 0.0, 5.0]:
			parts.append("<circle cx='%.2f' cy='-0.5' r='1' fill='%s' opacity='0.8'/>" % [x, col.call("belly", "back")])
		parts.append("<circle cx='-2' cy='-5' r='0.9' fill='#2a231e'/><circle cx='2' cy='-5' r='0.9' fill='#2a231e'/>")
	return [parts, PackedVector2Array([Vector2(-17, -12), Vector2(17, 13)])]


static func _hubcap(col: Callable, ink: String, silhouette: bool) -> Array:
	var parts := PackedStringArray()
	parts.append("<circle cx='0' cy='0' r='11' fill='%s' stroke='%s' stroke-width='1.2'/>" % [col.call("back", "body"), ink])
	parts.append("<circle cx='0' cy='0' r='8' fill='none' stroke='%s' stroke-width='0.9'/>" % ink)
	if not silhouette:
		for i in 5:
			var a := TAU * i / 5.0
			parts.append("<path d='M%.2f %.2f L%.2f %.2f' stroke='%s' stroke-width='1.6' stroke-linecap='round'/>" % [cos(a) * 3.0, sin(a) * 3.0, cos(a) * 7.0, sin(a) * 7.0, col.call("mark", "back")])
		parts.append("<circle cx='0' cy='0' r='2.6' fill='%s' stroke='%s' stroke-width='0.9'/>" % [col.call("belly", "back"), ink])
	return [parts, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)])]


# --- drawing -------------------------------------------------------------------------------

## Fit the drawing to the texture with a small margin and rasterise it.
static func _render(drawn: Array, size: Vector2i) -> Texture2D:
	var pts: PackedVector2Array = drawn[1]
	var lo := pts[0]
	var hi := pts[0]
	for v in pts:
		lo = lo.min(v)
		hi = hi.max(v)
	var margin := 1.6
	lo -= Vector2(margin, margin)
	hi += Vector2(margin, margin)
	var span := hi - lo
	var scale := minf(size.x / span.x, size.y / span.y)
	var offset := (Vector2(size) - span * scale) * 0.5 - lo * scale
	var body := "".join(drawn[0])
	var k := 4  # drawn big, then shrunk: smooth edges at small sizes
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'><g transform='translate(%.3f %.3f) scale(%.4f)'>%s</g></svg>" % [
		size.x * k, size.y * k, size.x, size.y, offset.x, offset.y, scale, body]
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK:
		image = Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	else:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


static func _poly(pts: PackedVector2Array, fill: String, ink: String, sw: float) -> String:
	var d := PackedStringArray()
	for v in pts:
		d.append("%.2f,%.2f" % [v.x, v.y])
	return "<polygon points='%s' fill='%s' stroke='%s' stroke-width='%.2f' stroke-linejoin='round'/>" % [" ".join(d), fill, ink, sw]


static func _p(v: Vector2) -> String:
	return "%.2f %.2f" % [v.x, v.y]
