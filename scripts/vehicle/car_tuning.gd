class_name CarTuning
extends RefCounted
## Garage tuning settings: small adjustments on top of the fitted parts.
##
## Each option maps to a part modifier key (see CarPart) and is only
## available when one of its `needs` parts is fitted; tyre pressure is
## always available. Values the car can't use right now are ignored, not
## lost, so refitting the part brings the setup back.

const OPTIONS := [
	{"key": "tyre_pressure", "label": "Tyre pressure", "min": -1.0, "max": 1.0, "step": 0.25,
		"default": 0.0, "low": "soft, grippy", "high": "hard, sharp", "needs": []},
	{"key": "ride_height_add", "label": "Ride height", "min": -0.03, "max": 0.02, "step": 0.005,
		"default": 0.0, "low": "slammed", "high": "lifted", "needs": ["suspension_coilovers"]},
	{"key": "spring_mult", "label": "Spring stiffness", "min": 0.8, "max": 1.25, "step": 0.05,
		"default": 1.0, "low": "soft", "high": "stiff", "needs": ["suspension_coilovers"]},
	{"key": "damper_mult", "label": "Damping", "min": 0.8, "max": 1.25, "step": 0.05,
		"default": 1.0, "low": "floaty", "high": "tight", "needs": ["suspension_coilovers"]},
	{"key": "anti_roll_mult", "label": "Anti-roll bars", "min": 0.6, "max": 1.4, "step": 0.1,
		"default": 1.0, "low": "rolls", "high": "flat", "needs": ["suspension_coilovers"]},
	{"key": "final_drive_mult", "label": "Final drive", "min": 0.9, "max": 1.12, "step": 0.02,
		"default": 1.0, "low": "long legs", "high": "punchy", "needs": ["gearbox_close_ratio", "gearbox_short_final"]},
]


static func option(key: String) -> Dictionary:
	for o in OPTIONS:
		if o.key == key:
			return o
	return {}


## True when the car has a part that unlocks this option.
static func is_available(o: Dictionary, part_ids: PackedStringArray) -> bool:
	if o.needs.is_empty():
		return true
	for id in o.needs:
		if part_ids.has(id):
			return true
	return false


## Turn tuning values into part-style modifiers, skipping unavailable ones.
static func to_modifiers(tuning: Dictionary, part_ids: PackedStringArray) -> Dictionary:
	var m := {}
	for o in OPTIONS:
		if not tuning.has(o.key) or not is_available(o, part_ids):
			continue
		var value := clampf(float(tuning[o.key]), o.min, o.max)
		if o.key == "tyre_pressure":
			# Softer tyres grip a little more but feel vaguer; harder the opposite.
			m["grip_mult"] = 1.0 - value * 0.03
			m["lateral_stiffness_add"] = value * 0.06
		else:
			m[o.key] = value
	return m
