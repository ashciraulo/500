class_name LateSounds
extends RefCounted
## Stand-in sounds for the late city, made up in code: the cassette deck
## starting and stopping, the warble of something blinking out, tape hiss,
## and for the story at home the answering machine's beep (machine_beep) and
## the porch light's switch (light_switch).
## A recording with the same name in audio/late/ (late_tape_start,
## late_tape_stop, late_flicker, late_tape_hiss_loop) replaces each one.

const RATE := 22050


static func make(sound: String) -> AudioStreamWAV:
	match sound:
		"late_tape_start":
			return _wav(_tape_start(), false)
		"late_tape_stop":
			return _wav(_tape_stop(), false)
		"late_flicker":
			return _wav(_flicker(), false)
		"late_tape_hiss_loop":
			return _wav(_hiss(), true)
		"machine_beep":
			return _wav(_beep(), false)
		"light_switch":
			return _wav(_switch(), false)
	return _wav(PackedFloat32Array([0.0]), false)


## The answering machine's beep before its messages: one clean tone.
static func _beep() -> PackedFloat32Array:
	var n := int(RATE * 0.42)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := clampf(t / 0.01, 0.0, 1.0) * clampf((0.42 - t) / 0.03, 0.0, 1.0)
		out[i] = (sin(TAU * 1020.0 * t) * 0.8 + sin(TAU * 2040.0 * t) * 0.1) * 0.35 * env
	return out


## An old rocker switch: a dull snap, the plate ringing a little.
static func _switch() -> PackedFloat32Array:
	var n := int(RATE * 0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var snap := lp * exp(-t * 260.0) * 1.4
		var ring := sin(TAU * 1850.0 * t) * exp(-t * 90.0) * 0.18
		out[i] = (snap + ring) * 0.6
	return out


## Play pressed: a hard click, then the motor and the capstan whirring up.
static func _tape_start() -> PackedFloat32Array:
	var n := int(RATE * 0.62)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		# The key going down: two clicks, the latch and the head.
		for at: float in [0.0, 0.045]:
			var ct := t - at
			if ct >= 0.0 and ct < 0.012:
				s += rng.randf_range(-1.0, 1.0) * exp(-ct * 420.0) * 0.8
		# The motor: a low hum that comes up to speed, and filtered noise.
		var up := clampf((t - 0.05) / 0.3, 0.0, 1.0)
		if t > 0.05:
			var f := lerpf(60.0, 118.0, up)
			s += sin(TAU * f * t) * 0.16 * up + sin(TAU * f * 2.0 * t) * 0.05 * up
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
			s += lp * 0.5 * up
		var fade := clampf((0.62 - t) / 0.18, 0.0, 1.0)
		out[i] = s * fade
	return out


## Stop: the key clunking up and the reels running down.
static func _tape_stop() -> PackedFloat32Array:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1980
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		# The thud of the mechanism.
		s += sin(TAU * 72.0 * t) * exp(-t * 26.0) * 0.75
		s += sin(TAU * 143.0 * t) * exp(-t * 40.0) * 0.25
		if t < 0.015:
			s += rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.9
		# The motor winding down.
		var down := clampf(1.0 - t / 0.42, 0.0, 1.0)
		var f := lerpf(40.0, 118.0, down)
		s += sin(TAU * f * t) * 0.12 * down
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.06
		s += lp * 0.35 * down
		out[i] = s
	return out


## Something blinking out: a soft falling tone with a wobble, like a tape
## slowing for a moment.
static func _flicker() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(880.0, 520.0, t / 0.45) + sin(TAU * 9.0 * t) * 28.0
		phase += TAU * f / RATE
		var env := sin(PI * t / 0.45)
		out[i] = (sin(phase) * 0.35 + sin(phase * 0.5) * 0.15 + rng.randf_range(-1.0, 1.0) * 0.04) * env * env
	return out


## Tape hiss: soft, bright noise. Four seconds that loop without a seam.
static func _hiss() -> PackedFloat32Array:
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 79
	var prev := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		# A first difference tilts it bright, like hiss off a cassette.
		out[i] = (w - prev * 0.85) * 0.18
		prev = w
	return out


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
