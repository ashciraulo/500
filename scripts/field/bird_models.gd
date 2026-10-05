class_name BirdModels
extends RefCounted
## Low-poly birds, one body plan per family, coloured and marked per species
## from data/field/birds.json. Built from egg shapes, tapered tubes and flat
## blades so the silhouettes read at a distance. Every bird faces -Z with its
## feet at the origin and has:
##   Trunk         the body, pitched by its posture; Tail and Folds under it
##   Head          neck, head and bill, a pivot for pecking and looking about
##   Legs
##   WingL, WingR  spread wings, shown in flight (the folded ones hide then)
## Sizes are the species' real length (bill to tail), so a fairywren is tiny
## and a pelican is not. Meshes are built once per species and shared.

## Body plans for a bird 1 m long, scaled by the species' size.
## body: egg radii; taper: how pointed the rear is; tilt: body pitch (head up);
## leg: leg length; neck: points (forward, up) from the shoulder, and its
## radius at each end; head: egg radii; bill: [length, depth, droop, width],
## lower: a lower mandible that shows; tail: [length, root width, tip width,
## cocked up, fork]; fold: how far the folded wings reach; wing: [span of one
## wing, chord, broadness of the tip 0..1]; crest: [length, lean back];
## swims: sits in the water; front_eyes: an owl's face.
const PLANS := {
	"songbird": {"body": Vector3(0.15, 0.14, 0.27), "taper": 0.3, "tilt": 0.3, "leg": 0.12,
		"neck": [Vector2(0.04, 0.05)], "neck_r": [0.09, 0.08], "head": Vector3(0.1, 0.095, 0.11),
		"bill": [0.16, 0.05, 0.0, 0.045], "tail": [0.34, 0.07, 0.13, 0.0, 0.0], "fold": 1.0, "wing": [0.55, 0.3, 0.4]},
	"wren": {"body": Vector3(0.19, 0.18, 0.24), "taper": 0.25, "tilt": 0.25, "leg": 0.17,
		"neck": [Vector2(0.03, 0.05)], "neck_r": [0.11, 0.1], "head": Vector3(0.13, 0.13, 0.13),
		"bill": [0.1, 0.04, 0.0, 0.035], "tail": [0.4, 0.06, 0.08, 1.05, 0.0], "fold": 0.9, "wing": [0.45, 0.3, 0.5]},
	"parrot": {"body": Vector3(0.13, 0.14, 0.24), "taper": 0.35, "tilt": 0.65, "leg": 0.06,
		"neck": [Vector2(0.03, 0.05)], "neck_r": [0.09, 0.085], "head": Vector3(0.1, 0.1, 0.1),
		"bill": [0.075, 0.08, 1.0, 0.06], "lower": true, "tail": [0.46, 0.07, 0.025, 0.0, 0.0], "fold": 1.0, "wing": [0.5, 0.24, 0.1]},
	"cockatoo": {"body": Vector3(0.16, 0.16, 0.25), "taper": 0.3, "tilt": 0.6, "leg": 0.07,
		"neck": [Vector2(0.04, 0.05)], "neck_r": [0.11, 0.1], "head": Vector3(0.12, 0.12, 0.12),
		"bill": [0.09, 0.11, 1.1, 0.085], "lower": true, "tail": [0.33, 0.1, 0.15, 0.0, 0.0], "fold": 0.95, "wing": [0.6, 0.3, 0.7],
		"crest": [0.14, 1.1]},
	"dove": {"body": Vector3(0.15, 0.15, 0.26), "taper": 0.3, "tilt": 0.15, "leg": 0.06,
		"neck": [Vector2(0.06, 0.08)], "neck_r": [0.08, 0.06], "head": Vector3(0.08, 0.08, 0.09),
		"bill": [0.06, 0.03, 0.15, 0.03], "tail": [0.36, 0.08, 0.13, 0.0, 0.0], "fold": 1.0, "wing": [0.55, 0.3, 0.3]},
	"kookaburra": {"body": Vector3(0.15, 0.16, 0.23), "taper": 0.25, "tilt": 0.5, "leg": 0.05,
		"neck": [Vector2(0.03, 0.05)], "neck_r": [0.12, 0.11], "head": Vector3(0.13, 0.12, 0.14),
		"bill": [0.24, 0.08, 0.05, 0.065], "lower": true, "tail": [0.33, 0.08, 0.12, 0.0, 0.0], "fold": 0.95, "wing": [0.55, 0.3, 0.5]},
	"wader": {"body": Vector3(0.12, 0.11, 0.21), "taper": 0.35, "tilt": 0.15, "leg": 0.28,
		"neck": [Vector2(0.05, 0.08), Vector2(0.1, 0.15)], "neck_r": [0.06, 0.04], "head": Vector3(0.055, 0.055, 0.065),
		"bill": [0.26, 0.03, 0.35, 0.025], "tail": [0.1, 0.08, 0.1, 0.0, 0.0], "fold": 1.05, "wing": [0.6, 0.28, 0.3]},
	"heron": {"body": Vector3(0.1, 0.12, 0.2), "taper": 0.4, "tilt": 0.45, "leg": 0.36,
		"neck": [Vector2(0.03, 0.12), Vector2(0.0, 0.24), Vector2(0.08, 0.32)], "neck_r": [0.045, 0.032], "head": Vector3(0.045, 0.045, 0.06),
		"bill": [0.18, 0.03, 0.0, 0.022], "tail": [0.1, 0.07, 0.08, 0.0, 0.0], "fold": 1.0, "wing": [0.6, 0.3, 0.6]},
	"rail": {"body": Vector3(0.15, 0.15, 0.22), "taper": 0.3, "tilt": 0.25, "leg": 0.22,
		"neck": [Vector2(0.04, 0.1)], "neck_r": [0.08, 0.06], "head": Vector3(0.07, 0.07, 0.08),
		"bill": [0.1, 0.07, 0.15, 0.05], "tail": [0.12, 0.08, 0.06, 0.6, 0.0], "fold": 0.9, "wing": [0.4, 0.25, 0.4]},
	"duck": {"body": Vector3(0.18, 0.13, 0.3), "taper": 0.3, "tilt": 0.0, "leg": 0.0, "swims": true,
		"neck": [Vector2(0.03, 0.12)], "neck_r": [0.08, 0.06], "head": Vector3(0.075, 0.075, 0.09),
		"bill": [0.12, 0.03, 0.0, 0.065], "tail": [0.1, 0.1, 0.06, 0.3, 0.0], "fold": 0.85, "wing": [0.5, 0.28, 0.2]},
	"swan": {"body": Vector3(0.16, 0.12, 0.28), "taper": 0.35, "tilt": 0.0, "leg": 0.0, "swims": true,
		"neck": [Vector2(0.0, 0.12), Vector2(-0.01, 0.26), Vector2(0.05, 0.36)], "neck_r": [0.05, 0.033], "head": Vector3(0.04, 0.042, 0.06),
		"bill": [0.1, 0.035, 0.15, 0.035], "tail": [0.08, 0.12, 0.06, 0.4, 0.0], "fold": 0.9, "fold_up": 0.25, "wing": [0.6, 0.3, 0.5]},
	"pelican": {"body": Vector3(0.15, 0.13, 0.27), "taper": 0.3, "tilt": 0.0, "leg": 0.0, "swims": true,
		"neck": [Vector2(0.02, 0.1), Vector2(0.05, 0.17)], "neck_r": [0.06, 0.045], "head": Vector3(0.045, 0.05, 0.06),
		"bill": [0.3, 0.028, 0.0, 0.035], "pouch": true, "tail": [0.07, 0.1, 0.08, 0.2, 0.0], "fold": 0.95, "wing": [0.75, 0.25, 0.6]},
	"cormorant": {"body": Vector3(0.11, 0.12, 0.24), "taper": 0.4, "tilt": 1.0, "leg": 0.05,
		"neck": [Vector2(0.05, 0.07), Vector2(0.06, 0.15)], "neck_r": [0.05, 0.04], "head": Vector3(0.05, 0.05, 0.065),
		"bill": [0.1, 0.025, 0.1, 0.02], "tail": [0.25, 0.06, 0.1, 0.0, 0.0], "fold": 0.95, "wing": [0.55, 0.26, 0.4]},
	"gull": {"body": Vector3(0.14, 0.13, 0.25), "taper": 0.35, "tilt": 0.1, "leg": 0.12,
		"neck": [Vector2(0.04, 0.08)], "neck_r": [0.08, 0.07], "head": Vector3(0.08, 0.08, 0.09),
		"bill": [0.12, 0.035, 0.1, 0.025], "tail": [0.18, 0.1, 0.13, 0.0, 0.0], "fold": 1.3, "wing": [0.85, 0.22, 0.0]},
	"raptor": {"body": Vector3(0.15, 0.16, 0.24), "taper": 0.35, "tilt": 0.75, "leg": 0.08,
		"neck": [Vector2(0.03, 0.04)], "neck_r": [0.1, 0.09], "head": Vector3(0.09, 0.09, 0.1),
		"bill": [0.065, 0.06, 1.0, 0.045], "tail": [0.33, 0.1, 0.13, 0.0, 0.0], "fold": 1.0, "wing": [0.9, 0.3, 0.6]},
	"owl": {"body": Vector3(0.2, 0.24, 0.18), "taper": 0.25, "tilt": 1.25, "leg": 0.05,
		"neck": [Vector2(0.0, 0.02)], "neck_r": [0.16, 0.15], "head": Vector3(0.17, 0.15, 0.14),
		"bill": [0.04, 0.045, 1.0, 0.035], "tail": [0.12, 0.12, 0.14, 0.0, 0.0], "fold": 0.95, "wing": [0.7, 0.35, 0.7], "front_eyes": true},
	"frogmouth": {"body": Vector3(0.15, 0.18, 0.2), "taper": 0.3, "tilt": 1.3, "leg": 0.03,
		"neck": [Vector2(0.0, 0.02)], "neck_r": [0.13, 0.13], "head": Vector3(0.14, 0.12, 0.15),
		"bill": [0.1, 0.08, 0.35, 0.13], "tail": [0.35, 0.1, 0.1, 0.0, 0.0], "fold": 1.0, "wing": [0.6, 0.3, 0.6]},
	"swallow": {"body": Vector3(0.12, 0.11, 0.24), "taper": 0.4, "tilt": 0.15, "leg": 0.03,
		"neck": [Vector2(0.02, 0.03)], "neck_r": [0.085, 0.08], "head": Vector3(0.09, 0.085, 0.09),
		"bill": [0.06, 0.03, 0.1, 0.04], "tail": [0.4, 0.06, 0.2, 0.0, 0.25], "fold": 1.25, "wing": [0.7, 0.18, 0.0]},
}

## Where each kind of marking sits: [part, direction from the centre, how
## far out (1 = on the surface), size as a fraction of the part's radii].
## Parts: head, body, fold (the folded wings).
const MARKS := {
	"cap": ["head", Vector3(0, 1, -0.1), 0.55, Vector3(0.88, 0.6, 0.88)],
	"nape": ["head", Vector3(0, 0.2, 1), 0.6, Vector3(0.88, 0.75, 0.6)],
	"forehead": ["head", Vector3(0, 0.45, -1), 0.6, Vector3(0.6, 0.45, 0.5)],
	"face": ["head", Vector3(0, 0, -1), 0.55, Vector3(0.98, 0.92, 0.6)],
	"cheek": ["head", Vector3(1, -0.25, -0.1), 0.6, Vector3(0.5, 0.48, 0.55)],
	"mask": ["head", Vector3(0, 0.12, -0.25), 0.0, Vector3(1.04, 0.24, 0.85)],
	"brow": ["head", Vector3(0, 0.42, -0.3), 0.0, Vector3(1.03, 0.14, 0.7)],
	"throat": ["head", Vector3(0, -1, -0.5), 0.55, Vector3(0.7, 0.55, 0.6)],
	"lores": ["head", Vector3(0.6, 0, -1), 0.7, Vector3(0.3, 0.3, 0.3)],
	"tear": ["head", Vector3(1, -0.6, -0.35), 0.7, Vector3(0.18, 0.4, 0.18)],
	"wattle": ["head", Vector3(1, -0.9, 0), 0.85, Vector3(0.2, 0.32, 0.2)],
	"shield": ["head", Vector3(0, 0.3, -1), 0.75, Vector3(0.35, 0.42, 0.35)],
	"lobe": ["head", Vector3(0, -1, -0.9), 0.9, Vector3(0.3, 0.42, 0.35)],
	"breast": ["body", Vector3(0, -0.15, -1), 0.5, Vector3(0.8, 0.65, 0.5)],
	"breast_band": ["body", Vector3(0, 0.1, -1), 0.45, Vector3(0.9, 0.22, 0.55)],
	"belly_patch": ["body", Vector3(0, -1, -0.1), 0.6, Vector3(0.6, 0.45, 0.45)],
	"rump": ["body", Vector3(0, 0.8, 1), 0.6, Vector3(0.6, 0.4, 0.4)],
	"vent": ["body", Vector3(0, -0.6, 1), 0.6, Vector3(0.55, 0.4, 0.4)],
	"shoulder": ["fold", Vector3(0.4, 0.3, -1), 0.55, Vector3(1.1, 0.5, 0.35)],
	"wing_panel": ["fold", Vector3(1, 0, 0.1), 0.45, Vector3(0.75, 0.55, 0.35)],
	"wingbar": ["fold", Vector3(0, 0, -0.15), 0.0, Vector3(1.08, 1.03, 0.1)],
	"wingtip": ["fold", Vector3(0, 0, 1), 0.7, Vector3(1.08, 0.75, 0.4)],
}

static var _cache := {}
static var _materials := {}


## A bird for this species entry (from FieldJournal.bird(id)).
static func build(species: Dictionary) -> Node3D:
	var id := String(species.get("id", "bird"))
	if not _cache.has(id):
		_cache[id] = _make(species)
	var made: Dictionary = _cache[id]
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var trunk := _instance(made.trunk, "Trunk", made.trunk_at)
	trunk.rotation.x = made.tilt
	root.add_child(trunk)
	trunk.add_child(_instance(made.tail, "Tail", made.tail_at))
	trunk.add_child(_instance(made.folds, "Folds", Transform3D.IDENTITY))
	root.add_child(_instance(made.head, "Head", made.head_at))
	if made.legs:
		root.add_child(_instance(made.legs, "Legs", Transform3D.IDENTITY))
	for side: String in ["L", "R"]:
		var w := _instance(made["wing" + side], "Wing" + side, made["wing" + side + "_at"])
		w.visible = false
		root.add_child(w)
	root.set_meta("rest", {"tilt": made.tilt, "front": made.front, "neck_fly": made.neck_fly})
	return root


## Flight pose: wings out, folded wings and legs away, body level.
static func set_flying(bird: Node3D, on: bool) -> void:
	for n in [&"WingL", &"WingR"]:
		var w := bird.get_node_or_null(NodePath(n)) as Node3D
		if w:
			w.visible = on
	for n in [&"Trunk/Folds", &"Legs"]:
		var part := bird.get_node_or_null(NodePath(n)) as Node3D
		if part:
			part.visible = not on
	var rest: Dictionary = bird.get_meta("rest", {})
	var trunk := bird.get_node_or_null(^"Trunk") as Node3D
	var head := bird.get_node_or_null(^"Head") as Node3D
	if trunk == null or rest.is_empty():
		return
	var tilt: float = 0.05 if on else float(rest.tilt)
	trunk.rotation.x = tilt
	# Keep the head on the shoulders when the body levels out.
	if head:
		head.position = trunk.position + Basis(Vector3.RIGHT, tilt) * Vector3(rest.front)
		# Long necks stretch out ahead in flight.
		head.rotation.x = float(rest.neck_fly) if on else 0.0


## `phase` drives the beat; `amount` 0..1 how deep.
static func flap(bird: Node3D, phase: float, amount := 1.0) -> void:
	var a := sin(phase) * 0.9 * amount
	var l := bird.get_node_or_null(^"WingL") as Node3D
	var r := bird.get_node_or_null(^"WingR") as Node3D
	if l:
		l.rotation.z = -a
	if r:
		r.rotation.z = a


static func _instance(mesh: ArrayMesh, node_name: String, at: Transform3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = mesh
	m.transform = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# --- building a species ----------------------------------------------------------------

static func _make(species: Dictionary) -> Dictionary:
	var plan: Dictionary = PLANS.get(String(species.get("model", "songbird")), PLANS["songbird"])
	var shape: Dictionary = species.get("shape", {})
	var c: Dictionary = species.get("colours", {})
	var col := func(key: String, fallback: String) -> String: return String(c.get(key, fallback))
	var body_c: String = col.call("body", "#555555")
	var wing_c: String = col.call("wing", body_c)
	var head_c: String = col.call("head", body_c)
	var belly_c: String = col.call("belly", body_c)
	var beak_c: String = col.call("beak", "#222222")
	var tail_c: String = col.call("tail", wing_c)
	var legs_c: String = col.call("legs", "#3a3430")
	var eye_c: String = col.call("eye", "#141210")
	# The wrong birds' eyes catch the light.
	if species.get("wrong", false):
		eye_c = "glow:" + eye_c
	var neck_c: String = col.call("neck", head_c if float(plan.neck_r[0]) < 0.07 else body_c)
	var s := float(species.get("size", 0.3))
	var swims: bool = plan.get("swims", false)
	var tilt := float(shape.get("tilt", plan.tilt))
	var r: Vector3 = plan.body * s * float(shape.get("body", 1.0))
	var leg := float(plan.leg) * s * float(shape.get("leg", 1.0))
	var marks: Array = species.get("marks", [])

	# Body: an egg with a paler belly bulging out underneath.
	var trunk := Part.new()
	trunk.add(body_c, _egg(r, float(plan.taper)))
	trunk.add(belly_c, _egg(r * Vector3(0.9, 0.72, 0.72), 0.2), Transform3D(Basis(), Vector3(0, -r.y * 0.3, -r.z * 0.1)))
	var trunk_at := Transform3D(Basis(), Vector3(0, (leg + r.y * 0.75) if not swims else r.y * 0.25, 0))

	# Folded wings along the back, reaching past the rump.
	var folds := Part.new()
	var fr := Vector3(r.x * 0.3, r.y * 0.62, r.z * 0.78 * float(plan.fold))
	var fold_z := r.z * 0.2 + (fr.z - r.z * 0.78) * 0.6
	for side: float in [-1.0, 1.0]:
		var at := Transform3D(Basis(Vector3.RIGHT, -float(plan.get("fold_up", 0.0))).rotated(Vector3.UP, -side * 0.06),
			Vector3(side * r.x * 0.72, r.y * 0.16, fold_z))
		folds.add(wing_c, _egg(fr, 0.55), at)
		for m: Array in marks:
			var def: Array = MARKS.get(String(m[0]), [])
			if not def.is_empty() and def[0] == "fold":
				folds.add(String(m[1]), _mark(fr, def, side), at)
	for m: Array in marks:
		var def: Array = MARKS.get(String(m[0]), [])
		if not def.is_empty() and def[0] == "body":
			trunk.add(String(m[1]), _mark(r, def, 1.0))

	# Tail: a blade off the rump, a band or tip in another colour if marked.
	var t: Array = plan.tail
	var tail_len := float(t[0]) * s * float(shape.get("tail", 1.0))
	var tail := Part.new()
	var outline := _tail_outline(tail_len, float(t[1]) * s, float(t[2]) * s, float(t[4]) * tail_len)
	var thick := maxf(0.02 * s, 0.003)
	tail.add(tail_c, _thinned(_slab(outline, thick * 3.0), tail_len))
	for m: Array in marks:
		var band: Vector2 = {"tail_tip": Vector2(0.72, 1.0), "tail_band": Vector2(0.3, 0.7), "tail_base": Vector2(0.0, 0.45)}.get(String(m[0]), Vector2.ZERO)
		if band != Vector2.ZERO:
			var w0: float = lerpf(float(t[1]), float(t[2]), band.x) * s
			var w1: float = lerpf(float(t[1]), float(t[2]), band.y) * s
			var o := _tail_outline(tail_len * (band.y - band.x), w0 * 1.04, w1 * 1.04, float(t[4]) * tail_len if band.y >= 1.0 else 0.0)
			var band_geo := _moved(_slab(o, thick * 3.6), Vector3(0, 0, tail_len * band.x))
			tail.add(String(m[1]), _thinned(band_geo, tail_len))
	# Rotating +X drops the tail; perched upright, it still hangs a little less than the body.
	var tail_at := Transform3D(Basis(Vector3.RIGHT, -float(t[3]) - tilt * 0.25), Vector3(0, r.y * 0.1, r.z * 0.55))

	# Neck, head and bill, built around the shoulder pivot.
	var head := Part.new()
	var front := Vector3(0, r.y * 0.4, -r.z * 0.72)
	var neck_scale := float(shape.get("neck", 1.0))
	var pts: Array[Vector3] = [Vector3.ZERO]
	for p: Vector2 in plan.neck:
		pts.append(Vector3(0, p.y, -p.x) * s * neck_scale)
	var hr: Vector3 = plan.head * s * float(shape.get("head", 1.0))
	var neck_r0 := float(plan.neck_r[0]) * s
	var neck_r1 := float(plan.neck_r[1]) * s
	# The neck runs from inside the body to the back of the head.
	pts[0] = pts[1] * -0.6 + Vector3(0, -neck_r0 * 0.3, neck_r0 * 0.4)
	var radii: Array[float] = []
	for i in pts.size():
		radii.append(lerpf(neck_r0, neck_r1, float(i) / (pts.size() - 1)))
	head.add(neck_c, _tube(pts, radii, 1.0, 7))
	var hc: Vector3 = pts[-1] + Vector3(0, hr.y * 0.25, -hr.z * 0.35)
	head.add(head_c, _egg(hr, 0.15), Transform3D(Basis(), hc))
	for m: Array in marks:
		var kind := String(m[0])
		if kind == "collar":
			var at: Vector3 = pts[maxi(pts.size() - 2, 0)].lerp(pts[-1], 0.4)
			head.add(String(m[1]), _egg(Vector3(neck_r1, neck_r1, neck_r1) * 1.25, 0.0), Transform3D(Basis(), at))
			continue
		var def: Array = MARKS.get(kind, [])
		if def.is_empty() or def[0] != "head":
			continue
		var paired: bool = absf((def[1] as Vector3).x) > 0.01
		for side: float in ([-1.0, 1.0] if paired else [1.0]):
			head.add(String(m[1]), _mark(hr, def, side), Transform3D(Basis(), hc))
	# Eyes, and a ring around them when marked.
	var front_eyes: bool = plan.get("front_eyes", false)
	var eye_r := hr.x * (0.26 if front_eyes else 0.14)
	var ring_c := ""
	for m: Array in marks:
		if m[0] == "eye_ring":
			ring_c = String(m[1])
	for side: float in [-1.0, 1.0]:
		var dir := Vector3(side * 0.45, 0.2, -1.0) if front_eyes else Vector3(side, 0.3, -0.75)
		var p := hc + _surface(hr, dir) * 0.92
		if ring_c != "":
			head.add(ring_c, _egg(Vector3.ONE * eye_r * 1.7, 0.0), Transform3D(Basis(), p - _surface(hr, dir).normalized() * eye_r * 0.4))
		head.add(eye_c, _egg(Vector3.ONE * eye_r, 0.0), Transform3D(Basis(), p))
	# Bill.
	var b: Array = plan.bill
	var bill_len := float(b[0]) * s * float(shape.get("bill", 1.0))
	var bill_d := float(b[1]) * s
	var bill_w := float(b[3]) * s
	var droop := float(b[2])
	var bill_at := hc + Vector3(0, -hr.y * 0.12, -hr.z * 0.72)
	var bill_pts := _bill_curve(bill_at, bill_len, droop)
	head.add(beak_c, _tube(bill_pts, _taper_radii(bill_pts.size(), bill_w * 0.5, 0.12), bill_d / maxf(bill_w, 0.001), 6))
	for m: Array in marks:
		var range_t: Vector2 = {"bill_tip": Vector2(0.6, 1.0), "bill_band": Vector2(0.55, 0.75)}.get(String(m[0]), Vector2.ZERO)
		if range_t != Vector2.ZERO:
			var sub := _bill_curve(bill_at, bill_len, droop, range_t.x, range_t.y)
			var rr: Array[float] = []
			for i in sub.size():
				var tt := lerpf(range_t.x, range_t.y, float(i) / (sub.size() - 1))
				rr.append(bill_w * 0.5 * lerpf(1.0, 0.12, tt) * 1.12 + 0.0008)
			head.add(String(m[1]), _tube(sub, rr, bill_d / maxf(bill_w, 0.001), 6))
	if plan.get("lower", false):
		var low_at := bill_at + Vector3(0, -bill_d * 0.45, bill_len * 0.05)
		var low := _bill_curve(low_at, bill_len * 0.55, -0.25)
		head.add(col.call("lower", beak_c), _tube(low, _taper_radii(low.size(), bill_w * 0.42, 0.2), 0.8, 6))
	if plan.get("pouch", false):
		var pouch := _bill_curve(bill_at + Vector3(0, -bill_d * 0.6, -bill_len * 0.08), bill_len * 0.82, 0.0)
		var pr: Array[float] = []
		for i in pouch.size():
			pr.append(bill_w * 0.45 * sin(PI * (0.15 + 0.85 * float(i) / (pouch.size() - 1))) + 0.001)
		head.add(col.call("pouch", beak_c), _tube(pouch, pr, 2.2, 6))
	if plan.has("crest"):
		var cl := float(plan.crest[0]) * s * float(shape.get("crest", 1.0))
		var lean := float(plan.crest[1])
		var c0 := hc + Vector3(0, hr.y * 0.75, -hr.z * 0.15)
		var crest_pts: Array[Vector3] = [c0, c0 + Vector3(0, cl * 0.55, cl * 0.12), c0 + Vector3(0, cl * cos(lean), cl * sin(lean) + cl * 0.1)]
		head.add(col.call("crest", head_c), _tube(crest_pts, [hr.x * 0.4, hr.x * 0.25, 0.0], 0.6, 5))
	var head_at := Transform3D(Basis(), trunk_at.origin + Basis(Vector3.RIGHT, tilt) * front)

	# Legs and feet.
	var legs: Part = null
	if not swims and leg > 0.0:
		legs = Part.new()
		var lw := maxf(0.018 * s, 0.003)
		for side: float in [-1.0, 1.0]:
			var x: float = side * r.x * 0.32
			legs.add(legs_c, _tube([Vector3(x, leg + r.y * 0.4, 0.0), Vector3(x, 0.0, 0.0)], [lw, lw * 0.8], 1.0, 4))
			legs.add(legs_c, _tube([Vector3(x, lw * 0.5, lw), Vector3(x, lw * 0.5, -0.07 * s)], [lw * 0.8, lw * 0.4], 0.5, 4))

	# Spread wings, pinned at the shoulders.
	var w: Array = plan.wing
	var span := float(w[0]) * s
	var chord := float(w[1]) * s
	var wings := {}
	for side: float in [-1.0, 1.0]:
		var wing := Part.new()
		var o := _wing_outline(span, chord, float(w[2]), side)
		wing.add(wing_c, _slab(o, maxf(0.012 * s, 0.002), side < 0.0))
		for m: Array in marks:
			if m[0] == "flight_tip":
				var tip := _wing_outline(span * 0.32, chord * 0.75, float(w[2]), side)
				wing.add(String(m[1]), _slab(tip, maxf(0.018 * s, 0.003), side < 0.0), Transform3D(Basis(), Vector3(side * span * 0.68, 0, chord * 0.04)))
		wings["L" if side < 0.0 else "R"] = wing
	var out := {"trunk": trunk.mesh(), "trunk_at": trunk_at, "tilt": tilt, "tail": tail.mesh(), "tail_at": tail_at,
		"folds": folds.mesh(), "head": head.mesh(), "head_at": head_at, "front": front, "legs": legs.mesh() if legs else null,
		"neck_fly": -clampf(pts[-1].y / (0.25 * s), 0.0, 1.0) * 1.2}
	for side: String in ["L", "R"]:
		out["wing" + side] = wings[side].mesh()
		out["wing" + side + "_at"] = Transform3D(Basis(), trunk_at.origin + Vector3((-1.0 if side == "L" else 1.0) * r.x * 0.6, r.y * 0.35, -r.z * 0.1))
	return out


## A point on an ellipsoid's surface in direction `dir`.
static func _surface(radii: Vector3, dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var k := sqrt(pow(d.x / radii.x, 2) + pow(d.y / radii.y, 2) + pow(d.z / radii.z, 2))
	return d / k


## A marking: a smaller egg sunk into the part so only a patch shows.
static func _mark(radii: Vector3, def: Array, side: float) -> Array:
	var dir: Vector3 = def[1]
	dir.x *= side
	# Out 0 means a band through the part, offset by `dir` in radii.
	var centre := _surface(radii, dir) * float(def[2]) if float(def[2]) > 0.0 else dir * radii
	return _moved(_egg(radii * Vector3(def[3]), 0.0), centre)


static func _bill_curve(base: Vector3, length: float, droop: float, from := 0.0, to := 1.0) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var steps := 4
	for i in steps + 1:
		var t := lerpf(from, to, float(i) / steps)
		# Hooked bills curl down harder near the tip.
		pts.append(base + Vector3(0, -droop * length * t * t, -length * t * (1.0 - 0.25 * clampf(droop - 0.5, 0.0, 1.0) * t)))
	return pts


static func _taper_radii(n: int, r0: float, tip: float) -> Array[float]:
	var out: Array[float] = []
	for i in n:
		out.append(r0 * lerpf(1.0, tip, float(i) / (n - 1)) + 0.0005)
	return out


static func _tail_outline(length: float, root_w: float, tip_w: float, fork: float) -> PackedVector2Array:
	# (x, z), z back along the tail; the first point is the fan centre.
	var o := PackedVector2Array([Vector2(0, length * 0.3), Vector2(root_w * 0.5, 0), Vector2(tip_w * 0.5, length)])
	if fork > 0.0:
		o.append(Vector2(0, length - fork))
	o.append_array([Vector2(-tip_w * 0.5, length), Vector2(-root_w * 0.5, 0)])
	return o


static func _wing_outline(span: float, chord: float, broad: float, side: float) -> PackedVector2Array:
	var pts := [
		Vector2(0.25 * span, 0.0),
		Vector2(0.0, -0.5 * chord), Vector2(0.42 * span, -0.55 * chord),
		Vector2(span, lerpf(0.3, -0.35, broad) * chord), Vector2(lerpf(span, 0.95 * span, broad), lerpf(0.3, 0.35, broad) * chord),
		Vector2(0.45 * span, 0.55 * chord), Vector2(0.0, 0.5 * chord)]
	var o := PackedVector2Array()
	for p: Vector2 in pts:
		o.append(Vector2(p.x * side, p.y))
	return o


# --- meshes ----------------------------------------------------------------------------
# Each generator returns [vertices, normals, indices].

## An egg: radii, front at -Z, the rear narrowed by `taper`.
static func _egg(r: Vector3, taper: float, segs := 10, rings := 7) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var phi := PI * i / rings
		var z := -cos(phi)
		var k := sin(phi) * (1.0 - taper * z)
		for j in segs + 1:
			var th := TAU * j / segs
			var p := Vector3(cos(th) * k * r.x, sin(th) * k * r.y, z * r.z)
			v.append(p)
			n.append(Vector3(p.x / (r.x * r.x), p.y / (r.y * r.y), p.z / (r.z * r.z)).normalized() if p != Vector3.ZERO else Vector3(0, 0, z))
	for i in rings:
		for j in segs:
			var a := i * (segs + 1) + j
			var b := a + segs + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	return [v, n, idx]


## A tube through points with a radius at each, squashed vertically by `ry`.
static func _tube(pts: Array, radii: Array, ry: float, sides: int) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var count := pts.size()
	for i in count:
		var p: Vector3 = pts[i]
		var tangent: Vector3 = (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.BACK
		var up := side.cross(tangent).normalized()
		side = tangent.cross(up).normalized()
		for j in sides + 1:
			var a := TAU * j / sides
			var d := side * cos(a) + up * sin(a) * ry
			v.append(p + d * float(radii[i]))
			n.append((side * cos(a) + up * sin(a) / maxf(ry, 0.01)).normalized())
	for i in count - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	# Caps where the tube doesn't come to a point.
	for end: int in [0, count - 1]:
		if float(radii[end]) < 0.002:
			continue
		var dir: Vector3 = (pts[0] - pts[1]).normalized() if end == 0 else (pts[end] - pts[end - 1]).normalized()
		var c := v.size()
		v.append(pts[end])
		n.append(dir)
		for j in sides:
			var a := end * (sides + 1) + j
			if end == 0:
				idx.append_array([c, a + 1, a])
			else:
				idx.append_array([c, a, a + 1])
	return [v, n, idx]


## A flat blade from an outline in the XZ plane (first point is the fan centre).
static func _slab(o: PackedVector2Array, thick: float, flip := false) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var ring := o.size() - 1
	for face: float in [1.0, -1.0]:
		var base := v.size()
		for p: Vector2 in o:
			v.append(Vector3(p.x, face * thick * 0.5, p.y))
			n.append(Vector3(0, face, 0))
		for i in ring:
			var a := base + 1 + i
			var b := base + 1 + (i + 1) % ring
			var up := (face > 0.0) != flip
			if up:
				idx.append_array([base, b, a])
			else:
				idx.append_array([base, a, b])
	# Edges.
	for i in ring:
		var p0 := o[1 + i]
		var p1 := o[1 + (i + 1) % ring]
		var out := Vector3(p1.y - p0.y, 0, -(p1.x - p0.x)).normalized() * (-1.0 if flip else 1.0)
		var base := v.size()
		v.append_array([Vector3(p0.x, thick * 0.5, p0.y), Vector3(p1.x, thick * 0.5, p1.y), Vector3(p1.x, -thick * 0.5, p1.y), Vector3(p0.x, -thick * 0.5, p0.y)])
		n.append_array([out, out, out, out])
		if flip:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return [v, n, idx]


## Thick at the root, thin at the tip (along +Z up to `length`).
static func _thinned(geo: Array, length: float) -> Array:
	var v: PackedVector3Array = (geo[0] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i].y *= lerpf(1.0, 0.3, clampf(v[i].z / maxf(length, 0.001), 0.0, 1.0))
	return [v, geo[1], geo[2]]


static func _moved(geo: Array, offset: Vector3) -> Array:
	var v: PackedVector3Array = (geo[0] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] += offset
	return [v, geo[1], geo[2]]


static func _mat(hex: String) -> Material:
	if not _materials.has(hex):
		if hex.begins_with("glow:"):
			_materials[hex] = PS1Material.glowing(Color.html(hex.trim_prefix("glow:")), 1.2)
		else:
			_materials[hex] = PS1Material.make(Color.html(hex), 0.6)
	return _materials[hex]


## One mesh, a surface per colour, gathered from many pieces.
class Part:
	var _surfaces := {}

	func add(hex: String, geo: Array, at := Transform3D.IDENTITY) -> void:
		if not _surfaces.has(hex):
			_surfaces[hex] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		var s: Array = _surfaces[hex]
		var base: int = (s[0] as PackedVector3Array).size()
		for p: Vector3 in geo[0]:
			s[0].append(at * p)
		for q: Vector3 in geo[1]:
			s[1].append((at.basis * q).normalized())
		for i: int in geo[2]:
			s[2].append(base + i)

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		for hex: String in _surfaces:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = _surfaces[hex][0]
			arrays[Mesh.ARRAY_NORMAL] = _surfaces[hex][1]
			arrays[Mesh.ARRAY_INDEX] = _surfaces[hex][2]
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			m.surface_set_material(m.get_surface_count() - 1, BirdModels._mat(hex))
		return m
