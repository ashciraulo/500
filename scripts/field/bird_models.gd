class_name BirdModels
extends RefCounted
## Low-poly birds, one body plan per family, coloured and marked per species
## from data/field/birds.json. Bodies are lofted (a breast that tapers into
## the tail), the wings fold flat along the flanks with the primaries reaching
## back over the tail, and the markings are painted onto the triangles rather
## than stuck on, so the shapes stay slim and the patterns stay crisp. Every
## bird faces -Z with its feet at the origin and has:
##   Trunk         the body, pitched by its posture; Tail and Folds under it
##   Head          neck, head and bill, a pivot for pecking and looking about
##   Legs
##   WingL, WingR  spread wings, shown in flight (the folded ones hide then)
## Sizes are the species' real length (bill to tail), so a fairywren is tiny
## and a pelican is not. Meshes are built once per species and shared.

## Body plans for a bird 1 m long, scaled by the species' size.
## body: [length, half width, half height above, half height below];
## breast: where along the body it's deepest (0 front .. 1 rear); rear: how
## thick the body still is where the tail starts; tilt: body pitch (head up);
## neck: points (forward, up) from the shoulder, neck_r its radius at each end;
## head: radii; bill: [length, depth, width, curve (radians, down), hook
## (radians, at the tip), bluntness 0..1]; tail: [length, root width, tip
## width, cocked up], tail_kind square/round/wedge/point/fork/fan/streamer and
## fork; reach: how far the folded wingtips pass the body; wing: [span of one
## wing, chord], wing_kind round/point/broad/slot; leg: [visible length,
## thickness, toe]; crest: [length] and crest_kind cockatoo/tern/plume;
## swims: sits in the water; front_eyes: an owl's face; eye: eye size.
const PLANS := {
	"songbird": {"body": [0.44, 0.1, 0.095, 0.12], "breast": 0.32, "rear": 0.3, "tilt": 0.35,
		"neck": [Vector2(0.025, 0.05)], "neck_r": [0.065, 0.055], "head": Vector3(0.068, 0.066, 0.078),
		"bill": [0.11, 0.034, 0.032, 0.05, 0.0, 0.0], "tail": [0.27, 0.085, 0.11, 0.0], "tail_kind": "square",
		"reach": 0.14, "wing": [0.85, 0.26], "wing_kind": "round", "leg": [0.13, 0.011, 0.07]},
	"wren": {"body": [0.36, 0.115, 0.11, 0.135], "breast": 0.35, "rear": 0.3, "tilt": 0.25,
		"neck": [Vector2(0.02, 0.05)], "neck_r": [0.08, 0.07], "head": Vector3(0.08, 0.08, 0.085),
		"bill": [0.07, 0.03, 0.028, 0.05, 0.0, 0.0], "tail": [0.40, 0.07, 0.085, 0.85], "tail_kind": "round",
		"reach": 0.05, "wing": [0.7, 0.26], "wing_kind": "round", "leg": [0.17, 0.012, 0.08]},
	"parrot": {"body": [0.38, 0.095, 0.095, 0.115], "breast": 0.35, "rear": 0.3, "tilt": 0.8,
		"neck": [Vector2(0.03, 0.04)], "neck_r": [0.06, 0.06], "head": Vector3(0.075, 0.075, 0.08),
		"bill": [0.065, 0.06, 0.045, 1.1, 0.6, 0.35], "tail": [0.39, 0.08, 0.025, 0.0], "tail_kind": "wedge",
		"reach": 0.14, "wing": [0.85, 0.22], "wing_kind": "point", "leg": [0.05, 0.014, 0.05]},
	"cockatoo": {"body": [0.4, 0.12, 0.115, 0.135], "breast": 0.33, "rear": 0.3, "tilt": 0.75,
		"neck": [Vector2(0.04, 0.04)], "neck_r": [0.07, 0.07], "head": Vector3(0.09, 0.09, 0.095),
		"bill": [0.075, 0.075, 0.06, 1.2, 0.6, 0.35], "tail": [0.31, 0.12, 0.15, 0.0], "tail_kind": "round",
		"reach": 0.12, "wing": [0.95, 0.3], "wing_kind": "broad", "leg": [0.06, 0.016, 0.06],
		"crest": [0.15], "crest_kind": "cockatoo"},
	"dove": {"body": [0.38, 0.1, 0.095, 0.115], "breast": 0.3, "rear": 0.28, "tilt": 0.1,
		"neck": [Vector2(0.05, 0.06)], "neck_r": [0.055, 0.045], "head": Vector3(0.055, 0.056, 0.065),
		"bill": [0.05, 0.02, 0.018, 0.25, 0.0, 0.0], "tail": [0.30, 0.08, 0.11, 0.0], "tail_kind": "round",
		"reach": 0.12, "wing": [0.9, 0.26], "wing_kind": "point", "leg": [0.06, 0.012, 0.055]},
	"kookaburra": {"body": [0.36, 0.11, 0.11, 0.13], "breast": 0.35, "rear": 0.3, "tilt": 0.5,
		"neck": [Vector2(0.02, 0.04)], "neck_r": [0.085, 0.08], "head": Vector3(0.1, 0.095, 0.11),
		"bill": [0.24, 0.065, 0.05, 0.05, 0.15, 0.1], "tail": [0.27, 0.085, 0.1, 0.0], "tail_kind": "square",
		"reach": 0.1, "wing": [0.7, 0.3], "wing_kind": "round", "leg": [0.04, 0.014, 0.05]},
	"wader": {"body": [0.36, 0.09, 0.085, 0.1], "breast": 0.3, "rear": 0.25, "tilt": 0.1,
		"neck": [Vector2(0.04, 0.06), Vector2(0.07, 0.1)], "neck_r": [0.045, 0.035], "head": Vector3(0.05, 0.052, 0.06),
		"bill": [0.24, 0.022, 0.018, 0.0, 0.0, 0.0], "tail": [0.12, 0.08, 0.09, 0.0], "tail_kind": "round",
		"reach": 0.14, "wing": [0.85, 0.22], "wing_kind": "point", "leg": [0.3, 0.01, 0.07]},
	"ibis": {"body": [0.36, 0.1, 0.1, 0.115], "breast": 0.35, "rear": 0.28, "tilt": 0.15,
		"neck": [Vector2(0.03, 0.08), Vector2(0.07, 0.15), Vector2(0.1, 0.17)], "neck_r": [0.04, 0.024], "head": Vector3(0.045, 0.048, 0.058),
		"bill": [0.26, 0.028, 0.022, 0.75, 0.0, 0.15], "tail": [0.12, 0.09, 0.1, 0.0], "tail_kind": "round",
		"reach": 0.08, "wing": [0.82, 0.32], "wing_kind": "broad", "leg": [0.28, 0.012, 0.08]},
	"heron": {"body": [0.3, 0.08, 0.085, 0.095], "breast": 0.35, "rear": 0.25, "tilt": 0.55,
		"neck": [Vector2(0.03, 0.09), Vector2(0.0, 0.17), Vector2(0.04, 0.25), Vector2(0.09, 0.28)], "neck_r": [0.038, 0.022],
		"head": Vector3(0.036, 0.036, 0.05), "bill": [0.17, 0.024, 0.018, 0.0, 0.0, 0.0], "tail": [0.1, 0.07, 0.08, 0.0],
		"tail_kind": "round", "reach": 0.06, "wing": [0.85, 0.32], "wing_kind": "broad", "leg": [0.38, 0.011, 0.08]},
	"night_heron": {"body": [0.4, 0.11, 0.11, 0.12], "breast": 0.35, "rear": 0.28, "tilt": 0.25,
		"neck": [Vector2(0.04, 0.05)], "neck_r": [0.07, 0.062], "head": Vector3(0.07, 0.07, 0.085),
		"bill": [0.13, 0.035, 0.028, 0.08, 0.0, 0.0], "tail": [0.12, 0.08, 0.09, 0.0], "tail_kind": "round",
		"reach": 0.06, "wing": [0.8, 0.32], "wing_kind": "broad", "leg": [0.22, 0.013, 0.08],
		"crest": [0.16], "crest_kind": "plume", "eye": 0.2},
	"rail": {"body": [0.38, 0.1, 0.11, 0.125], "breast": 0.35, "rear": 0.28, "tilt": 0.25,
		"neck": [Vector2(0.04, 0.08)], "neck_r": [0.055, 0.045], "head": Vector3(0.058, 0.06, 0.07),
		"bill": [0.1, 0.05, 0.035, 0.12, 0.0, 0.0], "tail": [0.12, 0.08, 0.05, 0.6], "tail_kind": "point",
		"reach": 0.02, "wing": [0.6, 0.26], "wing_kind": "round", "leg": [0.24, 0.014, 0.12]},
	"duck": {"body": [0.52, 0.13, 0.095, 0.11], "breast": 0.3, "rear": 0.3, "tilt": 0.0, "swims": true,
		"neck": [Vector2(0.03, 0.1)], "neck_r": [0.055, 0.045], "head": Vector3(0.06, 0.065, 0.075),
		"bill": [0.13, 0.022, 0.045, 0.08, 0.15, 0.85], "tail": [0.12, 0.09, 0.04, 0.3], "tail_kind": "point",
		"reach": 0.04, "wing": [0.75, 0.22], "wing_kind": "point", "leg": [0.0, 0.0, 0.0]},
	"coot": {"body": [0.48, 0.12, 0.1, 0.11], "breast": 0.32, "rear": 0.35, "tilt": 0.0, "swims": true,
		"neck": [Vector2(0.04, 0.09)], "neck_r": [0.055, 0.045], "head": Vector3(0.06, 0.062, 0.07),
		"bill": [0.07, 0.04, 0.028, 0.15, 0.0, 0.0], "tail": [0.1, 0.08, 0.05, 0.3], "tail_kind": "round",
		"reach": 0.02, "wing": [0.6, 0.24], "wing_kind": "round", "leg": [0.0, 0.0, 0.0]},
	"musk": {"body": [0.56, 0.13, 0.085, 0.11], "breast": 0.3, "rear": 0.3, "tilt": 0.0, "swims": true,
		"neck": [Vector2(0.03, 0.08)], "neck_r": [0.06, 0.05], "head": Vector3(0.065, 0.065, 0.08),
		"bill": [0.1, 0.04, 0.035, 0.15, 0.0, 0.3], "tail": [0.2, 0.06, 0.13, 0.25], "tail_kind": "fan",
		"reach": 0.0, "wing": [0.55, 0.22], "wing_kind": "point", "leg": [0.0, 0.0, 0.0]},
	"swan": {"body": [0.44, 0.12, 0.09, 0.1], "breast": 0.32, "rear": 0.3, "tilt": 0.0, "swims": true,
		"neck": [Vector2(0.0, 0.1), Vector2(-0.02, 0.22), Vector2(0.02, 0.32), Vector2(0.07, 0.35)], "neck_r": [0.032, 0.022],
		"head": Vector3(0.034, 0.036, 0.048), "bill": [0.1, 0.028, 0.028, 0.2, 0.0, 0.6], "tail": [0.08, 0.09, 0.04, 0.5],
		"tail_kind": "point", "reach": 0.02, "fold_up": 0.5, "wing": [0.72, 0.26], "wing_kind": "point", "leg": [0.0, 0.0, 0.0]},
	"pelican": {"body": [0.46, 0.13, 0.1, 0.11], "breast": 0.32, "rear": 0.3, "tilt": 0.0, "swims": true,
		"neck": [Vector2(0.0, 0.09), Vector2(0.03, 0.15)], "neck_r": [0.05, 0.035], "head": Vector3(0.045, 0.05, 0.06),
		"bill": [0.3, 0.022, 0.032, 0.0, 0.5, 0.75], "pouch": true, "tail": [0.08, 0.09, 0.07, 0.25], "tail_kind": "round",
		"reach": 0.04, "wing": [0.7, 0.26], "wing_kind": "slot", "leg": [0.0, 0.0, 0.0]},
	"cormorant": {"body": [0.38, 0.085, 0.09, 0.095], "breast": 0.35, "rear": 0.25, "tilt": 0.9,
		"neck": [Vector2(0.03, 0.06), Vector2(0.05, 0.12)], "neck_r": [0.045, 0.033], "head": Vector3(0.042, 0.044, 0.058),
		"bill": [0.1, 0.02, 0.016, 0.0, 0.9, 0.0], "tail": [0.26, 0.06, 0.09, 0.0], "tail_kind": "round",
		"reach": 0.04, "wing": [0.75, 0.26], "wing_kind": "broad", "leg": [0.05, 0.014, 0.06]},
	"darter": {"body": [0.34, 0.075, 0.08, 0.085], "breast": 0.35, "rear": 0.25, "tilt": 0.55,
		"neck": [Vector2(0.03, 0.08), Vector2(0.0, 0.17), Vector2(0.05, 0.25), Vector2(0.1, 0.27)], "neck_r": [0.032, 0.02],
		"head": Vector3(0.03, 0.032, 0.045), "bill": [0.13, 0.018, 0.014, 0.0, 0.0, 0.0], "tail": [0.28, 0.06, 0.1, 0.0],
		"tail_kind": "fan", "reach": 0.02, "wing": [0.8, 0.26], "wing_kind": "broad", "leg": [0.05, 0.012, 0.06]},
	"gull": {"body": [0.4, 0.095, 0.095, 0.105], "breast": 0.33, "rear": 0.28, "tilt": 0.08,
		"neck": [Vector2(0.04, 0.06)], "neck_r": [0.055, 0.05], "head": Vector3(0.06, 0.06, 0.07),
		"bill": [0.11, 0.03, 0.018, 0.05, 0.7, 0.0], "tail": [0.16, 0.09, 0.1, 0.0], "tail_kind": "square",
		"reach": 0.16, "wing": [1.4, 0.22], "wing_kind": "point", "leg": [0.1, 0.011, 0.06]},
	"tern": {"body": [0.38, 0.085, 0.085, 0.095], "breast": 0.33, "rear": 0.26, "tilt": 0.08,
		"neck": [Vector2(0.04, 0.06)], "neck_r": [0.05, 0.045], "head": Vector3(0.055, 0.056, 0.068),
		"bill": [0.15, 0.026, 0.018, 0.08, 0.0, 0.0], "tail": [0.2, 0.08, 0.11, 0.0], "tail_kind": "fork", "fork": 0.35,
		"reach": 0.18, "wing": [1.4, 0.2], "wing_kind": "point", "leg": [0.05, 0.01, 0.05], "crest": [0.07], "crest_kind": "tern"},
	"raptor": {"body": [0.38, 0.11, 0.115, 0.13], "breast": 0.35, "rear": 0.3, "tilt": 0.85,
		"neck": [Vector2(0.03, 0.03)], "neck_r": [0.065, 0.06], "head": Vector3(0.075, 0.075, 0.085),
		"bill": [0.075, 0.05, 0.035, 0.25, 1.4, 0.2], "tail": [0.32, 0.09, 0.11, 0.0], "tail_kind": "square",
		"reach": 0.06, "wing": [1.25, 0.34], "wing_kind": "slot", "leg": [0.08, 0.02, 0.07]},
	"owl": {"body": [0.36, 0.15, 0.15, 0.16], "breast": 0.4, "rear": 0.35, "tilt": 1.3,
		"neck": [Vector2(0.0, 0.02)], "neck_r": [0.08, 0.08], "head": Vector3(0.15, 0.13, 0.11), "head_taper": 0.1,
		"bill": [0.045, 0.04, 0.03, 0.4, 1.0, 0.2], "tail": [0.16, 0.1, 0.12, 0.0], "tail_kind": "round",
		"reach": 0.04, "wing": [1.2, 0.36], "wing_kind": "broad", "leg": [0.06, 0.02, 0.06], "front_eyes": true, "eye": 0.24},
	"frogmouth": {"body": [0.4, 0.11, 0.11, 0.12], "breast": 0.35, "rear": 0.3, "tilt": 1.35,
		"neck": [Vector2(0.0, 0.02)], "neck_r": [0.07, 0.07], "head": Vector3(0.13, 0.095, 0.11), "head_taper": 0.05,
		"bill": [0.1, 0.05, 0.12, 0.3, 0.6, 0.7], "tail": [0.34, 0.09, 0.11, 0.0], "tail_kind": "round",
		"reach": 0.04, "wing": [0.9, 0.3], "wing_kind": "round", "leg": [0.03, 0.015, 0.05], "eye": 0.2},
	"swallow": {"body": [0.36, 0.085, 0.08, 0.095], "breast": 0.3, "rear": 0.28, "tilt": 0.15,
		"neck": [Vector2(0.02, 0.03)], "neck_r": [0.065, 0.06], "head": Vector3(0.065, 0.062, 0.068),
		"bill": [0.04, 0.018, 0.035, 0.1, 0.0, 0.4], "tail": [0.42, 0.06, 0.15, 0.0], "tail_kind": "fork", "fork": 0.6,
		"reach": 0.3, "wing": [1.05, 0.19], "wing_kind": "point", "leg": [0.025, 0.01, 0.04]},
}

## shape keys that scale a part (the rest set a plan value outright).
const SCALES := ["neck", "bill", "tail", "crest", "head", "body", "leg", "wing", "eye", "reach"]

static var _cache := {}
static var _materials := {}


## Let go of the cached meshes and materials (on quit: static vars outlive
## the renderer otherwise).
static func clear_cache() -> void:
	_cache.clear()
	_materials.clear()


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


## How much the species' shape scales a part.
static func _k(plan: Dictionary, key: String) -> float:
	return float(plan.get(key + "_scale", 1.0))


## The family plan with the species' shape tweaks applied.
static func _plan(species: Dictionary) -> Dictionary:
	var plan: Dictionary = PLANS.get(String(species.get("model", "songbird")), PLANS["songbird"]).duplicate(true)
	var shape: Variant = species.get("shape", {})
	if not shape is Dictionary:
		return plan
	for key: String in shape:
		var v: Variant = shape[key]
		if key in SCALES and (v is float or v is int):
			plan[key + "_scale"] = float(v)
		else:
			plan[key] = v
	return plan


# --- building a species ----------------------------------------------------------------

static func _make(species: Dictionary) -> Dictionary:
	var plan := _plan(species)
	var look := Look.new(species, plan)
	var s := float(species.get("size", 0.3))
	var swims: bool = plan.get("swims", false)
	var tilt := float(plan.tilt)
	var bd: Array = plan.body
	var body := Body.new(float(bd[0]) * s * _k(plan, "body"), float(bd[1]) * s * _k(plan, "body"),
		float(bd[2]) * s * _k(plan, "body"), float(bd[3]) * s * _k(plan, "body"), float(plan.breast), float(plan.rear))

	# Body.
	var trunk := Part.new()
	trunk.paint(body.mesh(), Transform3D.IDENTITY, look.painter("body"))
	var leg_len := float(plan.leg[0]) * s * _k(plan, "leg")
	var hip := Vector3(body.w * 0.38, body.yc(0.55) - body.dn * 0.6, body.z(0.55))
	var tilted := Basis(Vector3.RIGHT, tilt)
	var trunk_y := body.dn * 0.3 if swims else leg_len - (tilted * hip).y
	var trunk_at := Transform3D(Basis(), Vector3(0, trunk_y, 0))

	# Folded wings along the flanks, the primaries reaching back over the tail.
	var folds := Part.new()
	var reach := float(plan.reach) * s * _k(plan, "reach")
	for side: float in [-1.0, 1.0]:
		folds.paint(body.fold(side, reach, float(plan.get("fold_up", 0.0))), Transform3D.IDENTITY, look.painter("fold"))

	# Tail: a feathered plate off the rump.
	var t: Array = plan.tail
	var tail_len := float(t[0]) * s * _k(plan, "tail")
	var tail := Part.new()
	tail.paint(_tail(tail_len, float(t[1]) * s, float(t[2]) * s, String(plan.tail_kind), float(plan.get("fork", 0.0))),
		Transform3D.IDENTITY, look.painter("tail"))
	var tail_at := Transform3D(Basis(Vector3.RIGHT, -float(plan.get("cock", t[3]))), Vector3(0, body.yc(1.0) + body.up * body.rear * 0.2, body.z(1.0) - body.length * 0.06))

	# Neck, head and bill, built around the shoulder pivot.
	var head := Part.new()
	# The shoulders: where the body is furthest up and forward once tilted,
	# drawn in a little.
	var front := body.support(tilted.inverse() * Vector3(0, 0.75, -0.66)) * 0.72
	var hr: Vector3 = plan.head * s * _k(plan, "head")
	var neck_scale: float = _k(plan, "neck")
	var neck_r0 := float(plan.neck_r[0]) * s
	var neck_r1 := float(plan.neck_r[1]) * s * sqrt(_k(plan, "head"))
	var pts: Array[Vector3] = [Vector3(0, -neck_r0 * 1.0, neck_r0 * 0.5)]
	for p: Vector2 in plan.neck:
		pts.append(Vector3(0, p.y, -p.x) * s * neck_scale)
	var hc: Vector3 = pts[-1] + Vector3(0, hr.y * 0.2, -hr.z * 0.3)
	pts.append(hc + Vector3(0, -hr.y * 0.1, hr.z * 0.1))
	if pts.size() > 3:
		pts = _smooth(pts, 3)
	var radii: Array[float] = []
	for i in pts.size():
		radii.append(lerpf(neck_r0, neck_r1, clampf(float(i) / (pts.size() - 2), 0.0, 1.0)))
	head.paint(_sweep(pts, radii, radii, radii, 8), Transform3D.IDENTITY, look.painter("neck"))
	head.paint(_ball(hr, float(plan.get("head_taper", -0.12)), 14, 10), Transform3D(Basis(), hc), look.painter("head"))
	# Eyes, with a pupil when the iris is pale.
	var eye_r := minf(hr.x, hr.y) * float(plan.get("eye", 0.16)) * _k(plan, "eye")
	# The wrong birds' glowing eyes are bigger and have no pupil.
	var glow := look.eye.begins_with("glow:")
	if glow:
		eye_r = maxf(eye_r * 1.6, minf(hr.x, hr.y) * 0.3)
	var taper := float(plan.get("head_taper", -0.12))
	for side: float in [-1.0, 1.0]:
		var dir := look.eye_dir * Vector3(side, 1, 1)
		# On the egg-shaped head, set in a little but standing proud of it.
		var on := _surface(hr, dir)
		on *= Vector3(1.0 - taper * on.z / hr.z, 1.0 - taper * on.z / hr.z, 1.0)
		var out := on.normalized()
		var at := hc + on - out * eye_r * 0.45
		head.add(look.eye, _egg(Vector3.ONE * eye_r, 0.0, 8, 5), Transform3D(Basis(), at))
		if look.ring != "":
			head.add(look.ring, _egg(Vector3.ONE * eye_r * 1.55, 0.0, 8, 5), Transform3D(Basis(), at - out * eye_r * 0.55))
		if look.pale_eye and not glow:
			head.add("#0a0a0a", _egg(Vector3.ONE * eye_r * 0.5, 0.0, 6, 4), Transform3D(Basis(), at + out * eye_r * 0.62))
	# Bill.
	var b: Array = plan.bill
	var bill_len := float(b[0]) * s * _k(plan, "bill")
	var bill_d := float(b[1]) * s * sqrt(_k(plan, "bill"))
	var bill_w := float(b[2]) * s * sqrt(_k(plan, "bill"))
	var curve := float(plan.get("droop", b[3]))
	var hook := float(plan.get("hook", b[4]))
	var blunt := float(b[5])
	var bill_at := hc + Vector3(0, -hr.y * 0.08, -hr.z * 0.7)
	var bill_pts := _bill_curve(bill_at, bill_len, curve, hook)
	var bw: Array[float] = []
	var bu: Array[float] = []
	var bdn: Array[float] = []
	for i in bill_pts.size():
		var u := float(i) / (bill_pts.size() - 1)
		var k := pow(1.0 - u, lerpf(1.0, 0.2, blunt)) * (1.0 - 0.15 * blunt * u * u)
		bw.append(maxf(bill_w * 0.5 * k, bill_w * 0.04 + 0.0004))
		bu.append(maxf(bill_d * 0.5 * pow(1.0 - u, 0.9), 0.0004))
		bdn.append(maxf(bill_d * 0.5 * pow(1.0 - u, 0.9), 0.0004))
	head.paint(_sweep(bill_pts, bw, bu, bdn, 8), Transform3D.IDENTITY, look.painter("bill"))
	if plan.get("pouch", false):
		var pp: Array[Vector3] = []
		var pw: Array[float] = []
		var pup: Array[float] = []
		var pdn: Array[float] = []
		for i in 7:
			var u := float(i) / 6.0
			var on_bill: Vector3 = bill_pts[mini(int(u * 0.85 * (bill_pts.size() - 1) + 0.5), bill_pts.size() - 1)]
			pp.append(on_bill + Vector3(0, -bill_d * 0.4, 0))
			pw.append(bill_w * 0.4 * sin(PI * (0.1 + 0.9 * u)) + 0.0005)
			pup.append(0.0008)
			pdn.append(bill_len * 0.16 * pow(sin(PI * u), 0.7) + 0.0008)
		head.paint(_sweep(pp, pw, pup, pdn, 6), Transform3D.IDENTITY, func(_p: Vector3) -> String: return look.col("pouch", look.col("beak")))
	# Frontal shield, wattles and lobes.
	for m: Array in look.marks:
		match String(m[0]):
			"shield":
				head.add(String(m[1]), _egg(Vector3(bill_w * 0.55, hr.y * 0.5, hr.z * 0.4), 0.0),
					Transform3D(Basis(Vector3.RIGHT, -0.5), hc + Vector3(0, hr.y * 0.32, -hr.z * 0.8)))
			"wattle":
				for side: float in [-1.0, 1.0]:
					head.add(String(m[1]), _egg(Vector3(hr.x * 0.12, hr.y * 0.32, hr.x * 0.14), 0.3),
						Transform3D(Basis(Vector3.RIGHT, -0.3), hc + Vector3(side * hr.x * 0.62, -hr.y * 0.95, hr.z * 0.05)))
			"lobe":
				head.add(String(m[1]), _egg(Vector3(bill_w * 0.28, hr.y * 0.55, hr.z * 0.5), 0.0),
					Transform3D(Basis(), bill_at + Vector3(0, -bill_d * 0.5 - hr.y * 0.5, -bill_len * 0.12)))
	if plan.has("crest"):
		_crest(head, look, String(plan.get("crest_kind", "cockatoo")), float(plan.crest[0]) * s * _k(plan, "crest"), hr, hc)
	if plan.get("hackles", false):
		_crest(head, look, "hackles", hr.y * 1.1, hr, hc)
	var head_at := Transform3D(Basis(), trunk_at.origin + tilted * front)

	# Legs and feet.
	var legs: Part = null
	if not swims and leg_len > 0.0:
		legs = Part.new()
		var lw := maxf(float(plan.leg[1]) * s * 0.5, 0.0022)
		var toe := float(plan.leg[2]) * s
		var hip_at := trunk_at * (tilted * hip)
		for side: float in [-1.0, 1.0]:
			var top := Vector3(side * hip_at.x, hip_at.y + body.dn * 0.3, hip_at.z)
			var foot := Vector3(side * hip_at.x * 0.8, lw, hip_at.z - leg_len * 0.04)
			var heel := Vector3(side * hip_at.x * 0.9, leg_len * 0.5, hip_at.z + leg_len * 0.14)
			legs.add(look.col("legs"), _tube([top, heel, foot], [lw * 1.6, lw, lw * 0.9], 1.0, 5))
			for a: float in [-0.5, 0.0, 0.5]:
				var d := Vector3(sin(a) * side, 0, -cos(a))
				legs.add(look.col("legs"), _tube([foot, foot + d * toe + Vector3(0, -lw * 0.5, 0)], [lw * 0.75, lw * 0.25], 1.0, 4))
			legs.add(look.col("legs"), _tube([foot, foot + Vector3(0, -lw * 0.5, toe * 0.45)], [lw * 0.7, lw * 0.25], 1.0, 4))

	# Spread wings, pinned at the shoulders.
	var w: Array = plan.wing
	var span := float(w[0]) * s * _k(plan, "wing")
	var chord := float(w[1]) * s * sqrt(_k(plan, "wing"))
	var wings := {}
	for side: float in [-1.0, 1.0]:
		var wing := Part.new()
		var geos := _spread_wing(span, chord, String(plan.wing_kind), side)
		for g: Array in geos:
			wing.paint(g, Transform3D.IDENTITY, look.painter("wing"))
		wings["L" if side < 0.0 else "R"] = wing
	var out := {"trunk": trunk.mesh(), "trunk_at": trunk_at, "tilt": tilt, "tail": tail.mesh(), "tail_at": tail_at,
		"folds": folds.mesh(), "head": head.mesh(), "head_at": head_at, "front": front, "legs": legs.mesh() if legs else null,
		"neck_fly": -clampf((hc.y - hr.y * 0.2) / (0.25 * s), 0.0, 1.0) * 1.2}
	for side: String in ["L", "R"]:
		out["wing" + side] = wings[side].mesh()
		out["wing" + side + "_at"] = Transform3D(Basis(), trunk_at.origin + Vector3((-1.0 if side == "L" else 1.0) * body.w * 0.5,
			body.yc(0.4) + body.up * 0.55, body.z(0.3)))
	return out


## Crest feathers: flat blades fanning off the crown (cockatoos), a shaggy tuft
## at the back (terns), long plumes off the nape (night herons) or hackles
## under the throat (ravens).
static func _crest(head: Part, look: Look, kind: String, length: float, hr: Vector3, hc: Vector3) -> void:
	var blades := []
	match kind:
		"cockatoo":
			for i in 6:
				var k := float(i) / 5.0
				var root := _surface(hr, Vector3(0, lerpf(0.55, 1.0, k), lerpf(-0.85, 0.15, k))) * 0.9
				var dir := Vector3(0, cos(lerpf(0.35, 1.25, k)), sin(lerpf(0.35, 1.25, k)))
				blades.append([root, dir, length * lerpf(0.55, 1.0, sin(k * PI * 0.8 + 0.3)), hr.x * 0.26, 0.6])
		"tern":
			for i in 4:
				var k := float(i) / 3.0
				var root := _surface(hr, Vector3(lerpf(-0.3, 0.3, k), 0.55, 0.75)) * 0.85
				blades.append([root, Vector3(lerpf(-0.25, 0.25, k), -0.15, 1.0).normalized(), length * lerpf(0.8, 1.0, 1.0 - absf(k - 0.5)), hr.x * 0.3, 0.2])
		"plume":
			for i in 2:
				var root := _surface(hr, Vector3((float(i) - 0.5) * 0.2, 0.45, 0.85)) * 0.85
				blades.append([root, Vector3(0, -0.3, 1.0).normalized(), length * (1.0 - 0.15 * i), hr.x * 0.07, 0.15])
		"hackles":
			for i in 3:
				var root := _surface(hr, Vector3((float(i) - 1.0) * 0.4, -0.85, -0.3)) * 0.9
				blades.append([root, Vector3((float(i) - 1.0) * 0.2, -1.0, 0.5).normalized(), length * 0.5, hr.x * 0.22, 0.3])
	for bl: Array in blades:
		var root: Vector3 = hc + bl[0]
		var dir: Vector3 = bl[1]
		var l := float(bl[2])
		var wide := float(bl[3])
		var bend := float(bl[4])
		# Each blade curls back as it goes.
		var mid := root + dir * l * 0.5 + Vector3(0, 0, l * 0.12 * bend)
		var tip := root + dir * l + Vector3(0, -l * 0.15 * bend, l * 0.3 * bend)
		var flat_w: Array[float] = [wide * 0.22, wide * 0.18, 0.0004]
		var flat_h: Array[float] = [wide, wide * 0.8, 0.0004]
		head.paint(_sweep([root, mid, tip], flat_w, flat_h, flat_h, 4), Transform3D.IDENTITY, look.painter("crest"))


## A Catmull-Rom curve through `pts`, `steps` points per span.
static func _smooth(pts: Array[Vector3], steps: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for k in steps:
			var t := float(k) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(pts[-1])
	return out


## The bill's centreline: straight out, curving down by `curve` radians over
## its length and `hook` more at the tip.
static func _bill_curve(base: Vector3, length: float, curve: float, hook: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [base]
	var steps := 6
	var p := base
	for i in steps:
		var u := (float(i) + 0.5) / steps
		var a := curve * u + hook * pow(clampf((u - 0.55) / 0.45, 0.0, 1.0), 2.0)
		p += Vector3(0, -sin(a), -cos(a)) * length / steps
		pts.append(p)
	return pts


## A tail: a thin plate `length` long, its trailing edge shaped by `kind`.
## Painting params: (along, across -1..1, face).
static func _tail(length: float, root_w: float, tip_w: float, kind: String, fork: float) -> Array:
	var rows := 6
	var cols := 7
	var top := []
	var bot := []
	for i in rows:
		var t := float(i) / (rows - 1)
		var row_t := []
		var row_b := []
		for j in cols:
			var u := lerpf(-1.0, 1.0, float(j) / (cols - 1))
			var e := 1.0
			match kind:
				"round":
					e = 1.0 - 0.2 * u * u
				"wedge":
					e = 1.0 - 0.55 * absf(u)
				"point":
					e = 1.0 - 0.75 * pow(absf(u), 1.2)
				"fork":
					e = 1.0 - fork * (1.0 - absf(u))
				"fan":
					e = 1.0 - 0.12 * u * u
				"streamer":
					e = 1.0 - 0.15 * u * u + 0.55 * maxf(0.0, 1.0 - absf(u) * 3.5)
			var half := lerpf(root_w, tip_w, t) * 0.5
			if kind == "streamer":
				half = lerpf(root_w, tip_w, minf(t * 1.6, 1.0)) * 0.5
			var x := u * half
			var z := t * e * length
			var th := length * 0.05 * pow(1.0 - t, 1.5) * (1.0 - 0.7 * u * u) + length * 0.006
			# A roof along the middle, so the tail has some depth side on.
			var y := length * 0.07 * (1.0 - absf(u)) * (1.0 - 0.6 * t) - length * 0.035
			row_t.append(Vector3(x, y + th, z))
			row_b.append(Vector3(x, y - th, z))
		top.append(row_t)
		bot.append(row_b)
	var geo := _shell(top, bot)
	# Remap q to -1..1 across.
	var prm: PackedVector3Array = geo[3]
	for i in prm.size():
		prm[i] = Vector3(prm[i].x, prm[i].y * 2.0 - 1.0, prm[i].z)
	return [geo[0], geo[1], geo[2], prm]


## Wing outlines: points [along the span 0..1, leading edge, trailing edge]
## in chords, z back from the shoulder.
const PLANFORMS := {
	"round": [[0.0, -0.3, 0.7], [0.45, -0.36, 0.62], [0.8, -0.24, 0.42], [1.0, -0.04, 0.1]],
	"point": [[0.0, -0.3, 0.7], [0.35, -0.38, 0.6], [0.7, -0.12, 0.38], [1.0, 0.45, 0.52]],
	"broad": [[0.0, -0.3, 0.7], [0.5, -0.34, 0.72], [0.85, -0.22, 0.58], [1.0, 0.0, 0.3]],
	"slot": [[0.0, -0.3, 0.7], [0.6, -0.36, 0.66], [1.0, -0.34, 0.6]],
}


static func _planform(shape: Array, u: float, k: int) -> float:
	for i in range(1, shape.size()):
		var a: Array = shape[i - 1]
		var b: Array = shape[i]
		if u <= float(b[0]):
			var f := (u - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[k]), float(b[k]), f * f * (3.0 - 2.0 * f))
	return float(shape[-1][k])


## A spread wing along +X (or -X), root at the origin; returns geos (a main
## blade and, for slotted wings, the finger primaries). Painting params:
## (along the span, across the chord, face).
static func _spread_wing(span: float, chord: float, kind: String, side: float) -> Array:
	var rows := 10
	var cols := 7
	var inner := 0.7 if kind == "slot" else 1.0
	# Planforms: [along the span, leading edge, trailing edge] in chords, the
	# wrist pushed forward and the hand swept back.
	var shape: Array = PLANFORMS.get(kind, PLANFORMS["round"])
	var top := []
	var bot := []
	for i in rows:
		var u := float(i) / (rows - 1)
		var le := _planform(shape, u, 1) * chord
		var te := _planform(shape, u, 2) * chord
		var x := u * span * inner
		var row_t := []
		var row_b := []
		for j in cols:
			var q := float(j) / (cols - 1)
			var th := chord * 0.07 * (1.0 - 0.75 * u) * (pow(sin(PI * clampf(q, 0.02, 0.98)), 0.6) + 0.08) * (1.0 - 0.6 * q)
			var camber := chord * 0.05 * sin(PI * q) * (1.0 - 0.5 * u) + x * 0.1
			var z := lerpf(le, te, q)
			row_t.append(Vector3(x * side, camber + th * 0.5, z))
			row_b.append(Vector3(x * side, camber - th * 0.5, z))
		top.append(row_t)
		bot.append(row_b)
	var geos := [_shell(top, bot)]
	if kind == "slot":
		# The hand: five fingered primaries splaying out.
		var x0 := span * inner * 0.96
		for k in 5:
			var f := float(k) / 4.0
			var z0 := lerpf(-0.28, 0.55, f) * chord
			var ang := lerpf(-0.08, 0.32, f)
			var l := span * (1.0 - inner) * lerpf(1.0, 0.75, f) + chord * 0.1
			var d := Vector3(cos(ang) * side, 0.0, sin(ang))
			var root := Vector3(x0 * side, x0 * 0.1, z0)
			var fp := [root - d * chord * 0.15, root + d * l * 0.5, root + d * l]
			var fw: Array[float] = [chord * 0.17, chord * 0.13, chord * 0.05]
			var fh: Array[float] = [chord * 0.012, chord * 0.008, 0.0004]
			var g := _sweep(fp, fw, fh, fh, 4, Vector3.UP)
			var prm: PackedVector3Array = g[3]
			for i in prm.size():
				prm[i] = Vector3(0.7 + 0.3 * prm[i].x, 0.5, signf(prm[i].z))
			geos.append([g[0], g[1], g[2], prm])
	return geos


## The body: a loft from the breast (front, -Z) to the rump, with the folded
## wings wrapped over its flanks.
class Body:
	var length: float
	var w: float
	var up: float
	var dn: float
	var breast: float
	var rear: float
	const TS := [0.0, 0.04, 0.1, 0.18, 0.27, 0.37, 0.48, 0.6, 0.72, 0.84, 0.93, 1.0]

	func _init(l: float, half_w: float, half_up: float, half_dn: float, breast_at: float, rear_k: float) -> void:
		length = l
		w = half_w
		up = half_up
		dn = half_dn
		breast = breast_at
		rear = rear_k

	func z(t: float) -> float:
		return -length * 0.5 + t * length

	## Girth 0..1 along the body.
	func girth(t: float) -> float:
		if t < breast:
			var k := (breast - t) / breast
			return sqrt(maxf(1.0 - k * k, 0.0))
		var k := (t - breast) / (1.0 - breast)
		return lerpf(1.0, rear, k * k * (3.0 - 2.0 * k))

	## Centreline height: the rear lifts to meet the tail.
	func yc(t: float) -> float:
		var rise := up * 0.35 * smoothstep(breast, 1.0, t)
		if t < breast:
			rise += dn * 0.12 * (1.0 - t / breast)
		return rise

	func surface(t: float, a: float, k := 1.0) -> Vector3:
		var g := girth(clampf(t, 0.0, 1.0)) * k
		var s := sin(a)
		return Vector3(cos(a) * w * g, yc(clampf(t, 0.0, 1.0)) + s * (up if s > 0.0 else dn) * g, z(t))

	## The point on the body furthest along `dir`.
	func support(dir: Vector3) -> Vector3:
		var best := Vector3.ZERO
		var best_d := -INF
		for t: float in TS:
			for k in 24:
				var p := surface(t, TAU * k / 24.0)
				if p.dot(dir) > best_d:
					best_d = p.dot(dir)
					best = p
		return best

	func mesh() -> Array:
		var pts: Array[Vector3] = []
		var ws: Array[float] = []
		var ups: Array[float] = []
		var dns: Array[float] = []
		for t: float in TS:
			var g := girth(t)
			pts.append(Vector3(0, yc(t), z(t)))
			ws.append(w * g)
			ups.append(up * g)
			dns.append(dn * g)
		return BirdModels._sweep(pts, ws, ups, dns, 12, Vector3.UP, TS)

	## A folded wing on `side`: a shell lying on the flank from the shoulder
	## back past the rump by `reach`. Params: (along, across from the top, face).
	func fold(side: float, reach: float, fold_up: float) -> Array:
		var rows := 12
		var cols := 7
		var t0 := 0.22
		var t1 := 1.0 + reach / length
		var outer := []
		var inner := []
		for i in rows:
			var s := float(i) / (rows - 1)
			var t := lerpf(t0, t1, s)
			var a_hi := deg_to_rad(lerpf(56.0, 48.0, s))
			var prof := 0.45 + 0.55 * s / 0.25 if s < 0.25 else 1.0 - pow((s - 0.25) / 0.75, 1.5) * 0.9
			var arc := deg_to_rad(110.0) * prof
			var past := maxf(t - 1.0, 0.0) / maxf(t1 - 1.0, 0.001)
			var row_o := []
			var row_i := []
			for j in cols:
				var q := float(j) / (cols - 1)
				var a := a_hi - q * arc
				var lift := Vector3(0, fold_up * up * s * s, 0)
				var po := surface(t, a, 1.05 * (1.0 - 0.25 * past))
				var pin := surface(t, a, 0.9 * (1.0 - 0.25 * past) if past > 0.0 else 0.88)
				# Past the body the tips draw in together over the tail.
				po.x *= 1.0 - 0.45 * past
				pin.x *= 1.0 - 0.45 * past
				po.x *= side
				pin.x *= side
				row_o.append(po + lift)
				row_i.append(pin + lift)
			outer.append(row_o)
			inner.append(row_i)
		return BirdModels._shell(outer, inner)


## Colours and markings: which colour each triangle of each part gets.
class Look:
	var c: Dictionary
	var marks: Array
	var eye: String
	var pale_eye: bool
	var eye_dir: Vector3
	var eye_ang: float
	var ring := ""

	func _init(species: Dictionary, plan: Dictionary) -> void:
		c = species.get("colours", {})
		var m: Variant = species.get("marks", [])
		marks = m if m is Array else []
		for mk: Array in marks:
			if String(mk[0]) == "eye_ring":
				ring = String(mk[1])
		var eye_c := col("eye", "#141210")
		pale_eye = Color.html(eye_c).get_luminance() > 0.3
		# The wrong birds' eyes catch the light.
		eye = ("glow:" + eye_c) if species.get("wrong", false) else eye_c
		var front: bool = plan.get("front_eyes", false)
		eye_dir = (Vector3(0.42, 0.14, -0.9) if front else Vector3(0.74, 0.3, -0.6)).normalized()
		eye_ang = float(plan.get("eye", 0.16))

	func col(key: String, fallback := "") -> String:
		match key:
			"body":
				return String(c.get("body", "#555555"))
			"wing":
				return String(c.get("wing", col("body")))
			"head":
				return String(c.get("head", col("body")))
			"belly":
				return String(c.get("belly", col("body")))
			"breast":
				return String(c.get("breast", col("belly")))
			"beak":
				return String(c.get("beak", "#222222"))
			"tail":
				return String(c.get("tail", col("wing")))
			"legs":
				return String(c.get("legs", "#3a3430"))
			"crest":
				return String(c.get("crest", col("head")))
		return String(c.get(key, fallback))

	func painter(part: String) -> Callable:
		return func(p: Vector3) -> String: return paint(part, p)

	func paint(part: String, p: Vector3) -> String:
		var hex := _base(part, p)
		for m: Array in marks:
			if BirdModels._in(part, String(m[0]), p, self):
				hex = String(m[1])
		return hex

	func _base(part: String, p: Vector3) -> String:
		match part:
			"body":
				# p: (along 0 front .. 1 rear, side, up)
				if p.z < 0.1 or (p.x < 0.15 and p.z < 0.5):
					return col("breast") if p.x < 0.42 else col("belly")
				return col("body")
			"fold":
				return col("wing")
			"tail":
				return col("undertail", col("tail")) if p.z < -0.5 else col("tail")
			"wing":
				return col("underwing", col("wing")) if p.z < -0.5 else col("wing")
			"neck":
				# p: (along 0 body .. 1 head, side, dorsal)
				if p.z > -0.2:
					return col("neck", col("head") if p.x > 0.5 else col("body"))
				return col("foreneck", col("neck", col("head") if p.x > 0.55 else col("breast")))
			"bill":
				return col("lower", col("beak")) if p.z < -0.15 else col("beak")
			"crest":
				return col("crest")
		return col("head")


static func _hash(p: Vector3) -> float:
	return fposmod(sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)


## Is this triangle (params `p` on `part`) inside marking `kind`?
static func _in(part: String, kind: String, p: Vector3, look: Look) -> bool:
	match part:
		"body":
			return _in_body(kind, p.x, p.y, p.z, p)
		"fold":
			return _in_fold(kind, p.x, p.y, p)
		"wing":
			return _in_wing(kind, p.x, p.y, p.z, p)
		"tail":
			return _in_tail(kind, p.x, p.y, p)
		"neck":
			return _in_neck(kind, p.x, p.y, p.z, p)
		"bill":
			match kind:
				"bill_tip":
					return p.x > 0.62
				"bill_band":
					return p.x > 0.55 and p.x < 0.74
				"bill_base":
					return p.x < 0.22
		"head":
			return _in_head(kind, p.normalized(), look)
		"crest":
			return kind == "crest_tip" and p.x > 0.6
	return false


static func _in_body(kind: String, t: float, sx: float, s: float, p: Vector3) -> bool:
	match kind:
		"breast":
			return t < 0.42 and s < 0.5
		"breast_band":
			return t > 0.1 and t < 0.3 and s < 0.65
		"breast_spots":
			return t > 0.08 and t < 0.35 and s < 0.6 and _hash(p) < 0.55
		"bib":
			return t < 0.2 and s < 0.6
		"gorget":
			return t < 0.14 and s < 0.4
		"belly_patch":
			return t > 0.42 and t < 0.8 and s < -0.25
		"rump":
			return t > 0.74 and s > 0.0
		"vent":
			return t > 0.68 and s < -0.1
		"mantle":
			return s > 0.4 and t < 0.8
		"flanks":
			return absf(sx) > 0.55 and s > -0.6 and s < 0.35 and t > 0.3
		"underparts":
			return s < 0.15
		"upperparts":
			return s >= 0.15
		"bars_under":
			return s < 0.1 and t > 0.08 and fposmod(t * 10.0, 1.0) < 0.42
		"spots_under":
			return s < 0.2 and _hash(p) < 0.22
		"streaks_under":
			return s < 0.15 and t > 0.08 and fposmod(atan2(s, sx) * 2.2, 1.0) < 0.3
		"scallops":
			return s > 0.0 and _hash(p) < 0.4
		"mottle":
			return _hash(p) < 0.3
		"back_spots":
			return s > 0.35 and _hash(p) < 0.4
	return false


static func _in_fold(kind: String, s: float, q: float, p: Vector3) -> bool:
	match kind:
		"shoulder":
			return s < 0.32 and q < 0.55
		"wing_panel", "coverts":
			return s > 0.12 and s < 0.62 and q < 0.85
		"wingbar":
			return s > 0.38 and s < 0.48
		"wingbars":
			return (s > 0.3 and s < 0.37) or (s > 0.5 and s < 0.57)
		"primaries", "wingtip":
			return s > 0.62
		"flight":
			return s > 0.62 or q > 0.62
		"tertials":
			return s > 0.5 and q < 0.45
		"secondaries", "speculum":
			return q > 0.6 and s > 0.3 and s < 0.62
		"wing_edge":
			return q > 0.55 and s > 0.25 and s < 0.85
		"wing_spots", "back_spots":
			return s < 0.62 and _hash(p) < 0.22
		"scallops":
			return _hash(p) < 0.4
		"mottle":
			return _hash(p) < 0.3
	return false


static func _in_wing(kind: String, s: float, q: float, face: float, p: Vector3) -> bool:
	var top := face > -0.5
	match kind:
		"shoulder":
			return top and s < 0.45 and q < 0.4
		"wing_panel", "coverts":
			return top and s < 0.6 and q > 0.25 and q < 0.6
		"wingbar":
			return top and s < 0.62 and q > 0.38 and q < 0.52
		"wingbars":
			return top and s < 0.62 and ((q > 0.3 and q < 0.38) or (q > 0.5 and q < 0.58))
		"flight_bar":
			return top and s < 0.75 and q > 0.5 and q < 0.65
		"primaries", "wingtip", "flight_tip":
			return s > 0.62
		"tip_spots":
			return s > 0.86 and q > 0.25 and q < 0.6
		"flight", "flight_feathers":
			return s > 0.62 or q > 0.55
		"secondaries", "speculum":
			return top and s < 0.62 and q > 0.6
		"carpal":
			return not top and s > 0.52 and s < 0.68 and q < 0.55
		"wing_spots", "back_spots":
			return top and s < 0.62 and _hash(p) < 0.22
		"wing_edge":
			return top and q > 0.55 and s > 0.2 and s < 0.8
		"mottle":
			return _hash(p) < 0.3
	return false


static func _in_tail(kind: String, t: float, u: float, p: Vector3) -> bool:
	match kind:
		"tail_tip":
			return t > 0.72
		"tail_band":
			return t > 0.35 and t < 0.65
		"tail_base":
			return t < 0.4
		"tail_edge":
			return absf(u) > 0.62
		"tail_corners":
			return absf(u) > 0.55 and t > 0.7
		"tail_panel":
			return t > 0.25 and t < 0.7 and absf(u) > 0.3
		"tail_bars":
			return fposmod(t * 6.0, 1.0) < 0.35
		"tail_spots":
			return t > 0.5 and _hash(p) < 0.35
		"mottle":
			return _hash(p) < 0.3
	return false


static func _in_neck(kind: String, t: float, sx: float, s: float, p: Vector3) -> bool:
	match kind:
		"throat":
			return s < -0.2 and t > 0.45
		"nape":
			return s > -0.2 and t > 0.55
		"hindneck":
			return s > 0.0
		"collar":
			return t > 0.3 and t < 0.65 and s > -0.45
		"collar_spots":
			return t > 0.3 and t < 0.7 and s > -0.45 and _hash(p) < 0.4
		"half_collar":
			return t > 0.35 and t < 0.6 and s > -0.2 and absf(sx) > 0.3
		"foreneck":
			return s < -0.25
		"neck_low":
			return t < 0.35
		"neck_stripe":
			return absf(sx) > 0.6 and t > 0.2
		"gorget":
			return t < 0.45 and s < -0.2
		"bib":
			return s < -0.1
		"hood":
			return t > 0.5
		"mottle":
			return _hash(p) < 0.3
	return false


static func _in_head(kind: String, d: Vector3, look: Look) -> bool:
	var e := look.eye_dir
	var ax := absf(d.x)
	var eye_side := e * Vector3(signf(d.x) if d.x != 0.0 else 1.0, 1, 1)
	var to_eye := d.angle_to(eye_side)
	var eye_line := e.y - 0.15 * (d.z - e.z)
	match kind:
		"cap":
			return d.y > 0.5 and d.z < 0.6
		"crown":
			return d.y > 0.68
		"forehead":
			return d.y > 0.2 and d.z < -0.5
		"nape":
			return d.z > 0.4 and d.y > -0.35
		"face":
			return d.z < -0.3
		"face_disc":
			return d.z < 0.15 and d.y < 0.75
		"disc_rim":
			return d.z >= 0.15 and d.z < 0.35 and d.y < 0.8
		"cheek":
			return ax > 0.45 and d.y < eye_line - 0.12 and d.y > -0.7 and d.z > -0.8 and d.z < 0.45
		"ear":
			return ax > 0.45 and d.y < eye_line + 0.05 and d.y > -0.5 and d.z > -0.15 and d.z < 0.7
		"mask":
			return absf(d.y - eye_line) < 0.16 and d.z < 0.6 and (ax > 0.2 or d.z < -0.75)
		"sub_mask":
			return d.y - eye_line < -0.18 and d.y - eye_line > -0.36 and d.z < 0.55 and ax > 0.25
		"brow":
			return d.y - eye_line > 0.15 and d.y - eye_line < 0.34 and d.z > -0.6 and d.z < 0.4 and ax > 0.3
		"lores":
			return d.z < -0.6 and absf(d.y - e.y) < 0.24 and ax > 0.12
		"throat":
			return d.y < -0.35 and d.z < 0.3
		"chin":
			return d.y < -0.25 and d.z < -0.55
		"tear":
			return ax > 0.45 and absf(d.z - e.z) < 0.17 and d.y < e.y - 0.1 and d.y > -0.85
		"whisker":
			return ax > 0.3 and d.y < e.y - 0.25 and d.y > -0.55 and d.z < -0.35
		"eye_patch":
			return to_eye < look.eye_ang * 2.7
		"spectacles":
			return to_eye > look.eye_ang * 2.3 and to_eye < look.eye_ang * 3.3
		"hood":
			return true
		"mottle":
			return _hash(d) < 0.3
		"streaks":
			return d.y > 0.0 and fposmod(d.x * 9.0, 1.0) < 0.3
	return false


# --- meshes ----------------------------------------------------------------------------
# Generators return [vertices, normals, indices] and, when they can be
# painted, a fourth array of per-vertex params.

## A point on an ellipsoid's surface in direction `dir`.
static func _surface(radii: Vector3, dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var k := sqrt(pow(d.x / radii.x, 2) + pow(d.y / radii.y, 2) + pow(d.z / radii.z, 2))
	return d / k


## A loft through `pts`: at each, a cross-section `w` wide (half) and `up` /
## `dn` above and below. `hint` is the dorsal side (by default the neck's:
## behind when going up, above when going forward). Params: (along, side, dorsal).
static func _sweep(pts: Array, w: Array, up: Array, dn: Array, sides: int, hint := Vector3.ZERO, ts: Array = []) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var prm := PackedVector3Array()
	var count := pts.size()
	for i in count:
		var p: Vector3 = pts[i]
		var tangent: Vector3 = (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var h := hint if hint != Vector3.ZERO else Vector3(0, -tangent.z, tangent.y)
		var dorsal := (h - tangent * h.dot(tangent)).normalized()
		var side := dorsal.cross(tangent).normalized()
		var t := float(ts[i]) if not ts.is_empty() else float(i) / (count - 1)
		var wi := float(w[i])
		for j in sides + 1:
			var a := TAU * j / sides
			var c := cos(a)
			var s := sin(a)
			var hh: float = float(up[i]) if s >= 0.0 else float(dn[i])
			v.append(p + side * c * wi + dorsal * s * hh)
			if wi < 0.0002 and hh < 0.0002:
				n.append(tangent * (-1.0 if i == 0 else 1.0))
			else:
				n.append((side * c / maxf(wi, 0.0001) + dorsal * s / maxf(hh, 0.0001)).normalized())
			prm.append(Vector3(t, c, s))
	for i in count - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	# Caps where the loft doesn't close.
	for end: int in [0, count - 1]:
		if float(w[end]) < 0.0003:
			continue
		var dir: Vector3 = (pts[0] - pts[1]).normalized() if end == 0 else (pts[end] - pts[end - 1]).normalized()
		var centre := v.size()
		v.append(pts[end])
		n.append(dir)
		prm.append(Vector3(float(ts[end]) if not ts.is_empty() else float(end) / (count - 1), 0, 0))
		for j in sides:
			var a := end * (sides + 1) + j
			idx.append_array([centre, a, a + 1])
	return [v, n, idx, prm]


## A closed thin shell between two grids of points (rows along, columns
## across). Params: (along, across, face) with face 1 on top, -1 underneath
## and 0 on the rim.
static func _shell(top: Array, bot: Array) -> Array:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var prm := PackedVector3Array()
	var rows := top.size()
	var cols: int = (top[0] as Array).size()
	for face: int in [0, 1]:
		var grid: Array = top if face == 0 else bot
		for i in rows:
			for j in cols:
				v.append(grid[i][j])
				prm.append(Vector3(float(i) / (rows - 1), float(j) / (cols - 1), 1.0 if face == 0 else -1.0))
		var base := face * rows * cols
		for i in rows - 1:
			for j in cols - 1:
				var a := base + i * cols + j
				idx.append_array([a, a + cols, a + 1, a + 1, a + cols, a + cols + 1])
	# Rim: walk the border and stitch top to bottom.
	var border: Array[Vector2i] = []
	for i in rows:
		border.append(Vector2i(i, 0))
	for j in range(1, cols):
		border.append(Vector2i(rows - 1, j))
	for i in range(rows - 2, -1, -1):
		border.append(Vector2i(i, cols - 1))
	for j in range(cols - 2, 0, -1):
		border.append(Vector2i(0, j))
	var rim0 := v.size()
	for b: Vector2i in border:
		v.append(top[b.x][b.y])
		v.append(bot[b.x][b.y])
		prm.append(Vector3(float(b.x) / (rows - 1), float(b.y) / (cols - 1), 0.0))
		prm.append(Vector3(float(b.x) / (rows - 1), float(b.y) / (cols - 1), 0.0))
	for k in border.size():
		var a := rim0 + k * 2
		var b := rim0 + ((k + 1) % border.size()) * 2
		idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	# Normals: faces summed per vertex; then the top made to face away from
	# the bottom, and the rim outwards from the middle.
	var n := PackedVector3Array()
	n.resize(v.size())
	for k in range(0, idx.size(), 3):
		var fa := (v[idx[k + 1]] - v[idx[k]]).cross(v[idx[k + 2]] - v[idx[k]])
		for m in 3:
			n[idx[k + m]] += fa
	var mid := Vector3.ZERO
	for i in rows * cols:
		mid += v[i]
	mid /= rows * cols
	var sign_top := 0.0
	for i in rows * cols:
		sign_top += n[i].dot(v[i] - v[i + rows * cols])
	for i in rows * cols:
		n[i] = (n[i] * signf(sign_top + 1e-12)).normalized()
		n[i + rows * cols] = -n[i] if n[i + rows * cols].length_squared() < 1e-16 else (n[i + rows * cols] * -signf(sign_top + 1e-12)).normalized()
		if n[i].length_squared() < 0.5:
			n[i] = Vector3.UP
	for k in range(rim0, v.size()):
		var out := v[k] - mid
		n[k] = out.normalized() if out.length_squared() > 1e-12 else Vector3.UP
	return [v, n, idx, prm]


## An ellipsoid with direction params (for painting by where on the head).
static func _ball(r: Vector3, taper: float, segs := 12, rings := 9) -> Array:
	var geo := _egg(r, taper, segs, rings)
	var prm := PackedVector3Array()
	for i in rings + 1:
		var phi := PI * i / rings
		for j in segs + 1:
			var th := TAU * j / segs
			prm.append(Vector3(cos(th) * sin(phi), sin(th) * sin(phi), -cos(phi)))
	return [geo[0], geo[1], geo[2], prm]


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

	func _surface(hex: String) -> Array:
		if not _surfaces.has(hex):
			_surfaces[hex] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		return _surfaces[hex]

	## Add a generator's triangles in one colour, wound to face along its
	## normals (Godot culls the other side).
	func add(hex: String, geo: Array, at := Transform3D.IDENTITY) -> void:
		var s := _surface(hex)
		var v: PackedVector3Array = geo[0]
		var n: PackedVector3Array = geo[1]
		var idx: PackedInt32Array = geo[2]
		var base: int = (s[0] as PackedVector3Array).size()
		for p: Vector3 in v:
			s[0].append(at * p)
		for q: Vector3 in n:
			s[1].append((at.basis * q).normalized())
		var sv: PackedVector3Array = s[0]
		var sn: PackedVector3Array = s[1]
		for k in range(0, idx.size(), 3):
			var a := base + idx[k]
			var b := base + idx[k + 1]
			var c := base + idx[k + 2]
			if (sv[b] - sv[a]).cross(sv[c] - sv[a]).dot(sn[a] + sn[b] + sn[c]) > 0.0:
				s[2].append_array([a, c, b])
			else:
				s[2].append_array([a, b, c])

	## Add a generator's triangles one by one, each in the colour `painter`
	## picks from its params, wound to face along its normals.
	func paint(geo: Array, at: Transform3D, painter: Callable) -> void:
		var v: PackedVector3Array = geo[0]
		var n: PackedVector3Array = geo[1]
		var idx: PackedInt32Array = geo[2]
		var prm: PackedVector3Array = geo[3]
		for k in range(0, idx.size(), 3):
			var a := idx[k]
			var b := idx[k + 1]
			var c := idx[k + 2]
			var face := (v[b] - v[a]).cross(v[c] - v[a])
			if face.length_squared() < 1e-16:
				continue
			if face.dot(n[a] + n[b] + n[c]) > 0.0:
				var swap := b
				b = c
				c = swap
			var s := _surface(String(painter.call((prm[a] + prm[b] + prm[c]) / 3.0)))
			var base: int = (s[0] as PackedVector3Array).size()
			for i: int in [a, b, c]:
				s[0].append(at * v[i])
				s[1].append((at.basis * n[i]).normalized())
			s[2].append_array([base, base + 1, base + 2])

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
