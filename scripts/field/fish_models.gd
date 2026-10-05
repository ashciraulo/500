class_name FishModels
extends RefCounted
## Low-poly fish (and a crab, a squid and a hubcap) for the end of the line,
## built with the bird models' mesh helpers. Each faces -Z, centred on its
## middle, at its caught length. Colours from data/field/fish.json: back,
## belly, fin, mark.

## Body plans for a fish 1 m long. body: egg radii; taper: how pointed the
## tail end is; tail: [length, height, fork]; dorsal: [length, height] of the
## back fin; snout: lower jaw length (garfish).
const PLANS := {
	"bream": {"body": Vector3(0.09, 0.2, 0.4), "taper": 0.35, "tail": [0.2, 0.26, 0.08], "dorsal": [0.42, 0.1]},
	"torpedo": {"body": Vector3(0.07, 0.11, 0.44), "taper": 0.4, "tail": [0.18, 0.22, 0.09], "dorsal": [0.3, 0.07]},
	"whiting": {"body": Vector3(0.05, 0.075, 0.45), "taper": 0.45, "tail": [0.13, 0.14, 0.03], "dorsal": [0.5, 0.05]},
	"flathead": {"body": Vector3(0.12, 0.05, 0.45), "taper": 0.55, "tail": [0.13, 0.12, 0.0], "dorsal": [0.4, 0.04]},
	"trevally": {"body": Vector3(0.07, 0.19, 0.42), "taper": 0.45, "tail": [0.22, 0.3, 0.12], "dorsal": [0.4, 0.07]},
	"garfish": {"body": Vector3(0.035, 0.05, 0.42), "taper": 0.3, "tail": [0.1, 0.1, 0.04], "dorsal": [0.12, 0.04], "snout": 0.18},
	"mulloway": {"body": Vector3(0.08, 0.13, 0.45), "taper": 0.4, "tail": [0.16, 0.18, 0.0], "dorsal": [0.5, 0.08]},
	"blowie": {"body": Vector3(0.14, 0.13, 0.32), "taper": 0.3, "tail": [0.14, 0.14, 0.0], "dorsal": [0.1, 0.05]},
}

static var _cache := {}


static func build(f: Dictionary) -> Node3D:
	var id := String(f.get("id", "fish"))
	if not _cache.has(id):
		_cache[id] = _make(f)
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var m := MeshInstance3D.new()
	m.name = "Body"
	m.mesh = _cache[id]
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	return root


## Scale a model to a catch's length in cm.
static func sized(f: Dictionary, cm: float) -> Node3D:
	var node := build(f)
	node.scale = Vector3.ONE * (cm / 100.0)
	return node


static func _make(f: Dictionary) -> ArrayMesh:
	var c: Dictionary = f.get("colours", {})
	var back := String(c.get("back", "#6a6a6a"))
	var belly := String(c.get("belly", "#e0e0e0"))
	var fin := String(c.get("fin", back))
	var mark := String(c.get("mark", "#202020"))
	var part := BirdModels.Part.new()
	match String(f.get("model", "torpedo")):
		"crab":
			_crab(part, back, belly, fin, mark)
		"squid":
			_squid(part, back, belly, mark)
		"hubcap":
			_hubcap(part, back, belly, fin, mark)
		var model:
			_fish(part, PLANS.get(model, PLANS["torpedo"]), back, belly, fin, mark)
	return part.mesh()


static func _fish(part: BirdModels.Part, plan: Dictionary, back: String, belly: String, fin: String, mark: String) -> void:
	var r: Vector3 = plan.body
	part.add(back, BirdModels._egg(r, float(plan.taper)))
	# A paler belly bulging out underneath.
	part.add(belly, BirdModels._egg(r * Vector3(0.94, 0.7, 0.86), float(plan.taper)), Transform3D(Basis(), Vector3(0, -r.y * 0.32, -r.z * 0.04)))
	# Tail: a vertical blade off the narrow end, forked or square.
	var t: Array = plan.tail
	var tail_o := PackedVector2Array([Vector2(0, float(t[0]) * 0.4), Vector2(r.y * 0.12, 0), Vector2(float(t[1]) * 0.5, float(t[0])),
		Vector2(0, float(t[0]) - float(t[2])), Vector2(-float(t[1]) * 0.5, float(t[0])), Vector2(-r.y * 0.12, 0)])
	# The blade is drawn flat (XZ); stand it on edge.
	part.add(fin, BirdModels._slab(tail_o, 0.012), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, r.z * 0.86)))
	# Back fin along the top, and a pair of side fins.
	var d: Array = plan.dorsal
	# A sail: rising quickly at the front, sloping away behind.
	var dl := float(d[0])
	var dh := float(d[1])
	var dorsal_o := PackedVector2Array([Vector2(dh * 0.3, dl * 0.45), Vector2(-0.01, 0), Vector2(dh, dl * 0.18), Vector2(dh * 0.8, dl * 0.5),
		Vector2(dh * 0.35, dl * 0.9), Vector2(-0.01, dl)])
	part.add(fin, BirdModels._slab(dorsal_o, 0.01), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, r.y * 0.82, -float(d[0]) * 0.45)))
	for side: float in [-1.0, 1.0]:
		var pec := PackedVector2Array([Vector2(side * 0.03, 0.05), Vector2(0, 0), Vector2(side * 0.07, 0.08), Vector2(0, 0.1)])
		part.add(fin, BirdModels._slab(pec, 0.008, side < 0.0), Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(side * r.x * 0.9, -r.y * 0.3, -r.z * 0.45)))
		# Eyes: a pale ring round a black pupil, on the surface of the head.
		var iris := maxf(r.y * 0.13, 0.014)
		var eye_at := Vector3(side * r.x * 0.6, r.y * 0.22, -r.z * 0.77)
		part.add("#e8dcb0", BirdModels._egg(Vector3(iris * 0.5, iris, iris), 0.0), Transform3D(Basis(), eye_at))
		part.add("#101010", BirdModels._egg(Vector3(iris * 0.4, iris * 0.6, iris * 0.6), 0.0), Transform3D(Basis(), eye_at + Vector3(side * iris * 0.3, 0, 0)))
	if plan.has("snout"):
		var s := float(plan.snout)
		part.add(mark, BirdModels._tube([Vector3(0, -r.y * 0.3, -r.z * 0.9), Vector3(0, -r.y * 0.3, -r.z - s)], [0.01, 0.003], 1.0, 4))


static func _crab(part: BirdModels.Part, back: String, belly: String, fin: String, mark: String) -> void:
	# A wide shell with a spine each side, claws out front, legs.
	part.add(back, BirdModels._egg(Vector3(0.36, 0.08, 0.22), 0.0))
	part.add(belly, BirdModels._egg(Vector3(0.32, 0.05, 0.19), 0.0), Transform3D(Basis(), Vector3(0, -0.035, 0)))
	for side: float in [-1.0, 1.0]:
		part.add(back, BirdModels._tube([Vector3(side * 0.3, 0, 0), Vector3(side * 0.5, 0.01, -0.04)], [0.04, 0.0], 1.0, 4))
		var arm := [Vector3(side * 0.18, 0, -0.16), Vector3(side * 0.3, 0.02, -0.34), Vector3(side * 0.16, 0.02, -0.5)]
		part.add(fin, BirdModels._tube(arm, [0.035, 0.03, 0.045], 0.8, 5))
		part.add(mark, BirdModels._egg(Vector3(0.05, 0.035, 0.1), 0.3), Transform3D(Basis(), Vector3(side * 0.12, 0.02, -0.56)))
		for i in 4:
			var z := -0.06 + i * 0.07
			part.add(fin, BirdModels._tube([Vector3(side * 0.28, 0, z), Vector3(side * 0.44, 0.05, z + 0.04), Vector3(side * 0.52, -0.06, z + 0.07)],
				[0.02, 0.016, 0.006], 1.0, 4))


static func _squid(part: BirdModels.Part, back: String, belly: String, mark: String) -> void:
	# Mantle at the back (+Z), head and arms forward.
	part.add(back, BirdModels._egg(Vector3(0.08, 0.08, 0.32), 0.45), Transform3D(Basis(), Vector3(0, 0, 0.12)))
	var fin := PackedVector2Array([Vector2(0, 0.3), Vector2(0, 0.06), Vector2(0.16, 0.3), Vector2(0, 0.42)])
	for side: float in [-1.0, 1.0]:
		var o := PackedVector2Array()
		for p in fin:
			o.append(Vector2(p.x * side, p.y))
		part.add(back, BirdModels._slab(o, 0.01, side < 0.0))
		part.add(mark, BirdModels._egg(Vector3.ONE * 0.025, 0.0), Transform3D(Basis(), Vector3(side * 0.05, 0.02, -0.25)))
	part.add(belly, BirdModels._egg(Vector3(0.06, 0.06, 0.08), 0.0), Transform3D(Basis(), Vector3(0, 0, -0.24)))
	for i in 8:
		var a := TAU * i / 8.0
		var o := Vector3(cos(a) * 0.035, sin(a) * 0.035, -0.3)
		part.add(belly, BirdModels._tube([o, o + Vector3(cos(a) * 0.02, sin(a) * 0.02 - 0.03, -0.12), o + Vector3(cos(a) * 0.03, -0.08, -0.22)],
			[0.012, 0.008, 0.002], 1.0, 4))


static func _hubcap(part: BirdModels.Part, back: String, belly: String, fin: String, mark: String) -> void:
	# A chrome dish: a rim, a low dome, slots round it and the badge in the middle.
	part.add(back, BirdModels._tube([Vector3(0, -0.03, 0), Vector3(0, 0.02, 0)], [0.5, 0.48], 1.0, 14))
	part.add("#d4d4d0", BirdModels._egg(Vector3(0.44, 0.09, 0.44), 0.0))
	part.add(belly, BirdModels._egg(Vector3(0.2, 0.1, 0.2), 0.0), Transform3D(Basis(), Vector3(0, 0.03, 0)))
	part.add(mark, BirdModels._egg(Vector3(0.08, 0.04, 0.08), 0.0), Transform3D(Basis(), Vector3(0, 0.12, 0)))
	for i in 8:
		var a := TAU * i / 8.0
		var slot := PackedVector2Array([Vector2(0, 0.05), Vector2(-0.025, 0), Vector2(0.025, 0), Vector2(0.025, 0.1), Vector2(-0.025, 0.1)])
		part.add(mark, BirdModels._slab(slot, 0.01), Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * 0.24 + Vector3(0, 0.08, 0)))
	# Weed growing on it.
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		part.add("#4a6a3a", BirdModels._egg(Vector3(0.07, 0.025, 0.05), 0.0), Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * 0.42 + Vector3(0, 0.03, 0)))
