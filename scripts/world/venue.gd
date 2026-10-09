class_name Venue
extends Node3D
## A cafe, bar, pub or restaurant in Northbridge: the shopfront of a real
## place on the front wall of its building, with a made-up name. MapStreamer
## adds one per entry in data/world/venues.json (tools/places/place_venues.py)
## under the tile it stands on, so it comes and goes with the tile.
##
## The model (art/models/scripts/build_venues.py) carries everything you see;
## this lights it by the clock and the venue's hours (the room behind the
## glass when it's open, neon and signs after dark, festoon bulbs over the
## tables at night) and gives it its sound in the place ambience while it's
## open. The frame: origin on the footpath at the wall, +z out to the street.

## Sound per kind, a place type in the ambience (place_<type>_loop).
const SOUNDS := {"cafe": "cafe", "gelato": "cafe", "restaurant": "restaurant", "bar": "bar", "pub": "pub"}
## Opening hours per kind, [[open, close], ...] in clock hours (close may run
## past midnight: 26 is 2 am).
const HOURS := {
	"cafe": [[6.5, 15.5]],
	"gelato": [[12.0, 23.0]],
	"restaurant": [[11.5, 14.5], [17.0, 22.5]],
	"bar": [[16.0, 26.0]],
	"pub": [[11.0, 24.5]],
}
## The sound carries this far round the door.
const SOUND_RADIUS := 22.0
## Lamps, bulbs and signs stop drawing past this.
const DETAIL_RANGE := 260.0
## Only this many venues nearest the player light the footpath for real.
const LIT_NEAREST := 4
const LIGHT_REACH := 90.0
const DATA_PATH := "res://data/world/venues.json"

@export var venue_id := ""
@export var display_name := ""
@export var kind := "cafe"
@export var street := ""
@export var scene_path := ""
## Overrides HOURS for this one ([[open, close], ...]).
@export var hours: Array = []

var is_open := false
var _night := false
var _glow: Array[ShaderMaterial] = []   # the room, lightboxes: on while open
var _neon: Array[ShaderMaterial] = []   # neon: on while open, bright after dark
var _bulbs: Array[ShaderMaterial] = []  # festoons and lamps: after dark while open
var _lamps: Array[ShaderMaterial] = []  # the porch lamp: every night
var _light: OmniLight3D
var _timer := 0.0

static var _all: Array[Venue] = []
static var _entries: Array = []
static var _entries_read := false


## Every venue in data/world/venues.json, loaded or not (for the maps).
static func entries() -> Array:
	if not _entries_read:
		_entries_read = true
		if FileAccess.file_exists(DATA_PATH):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if data is Dictionary:
				_entries = data.get("venues", [])
	return _entries


## A Venue for one venues.json entry, placed in world space.
static func from_entry(entry: Dictionary) -> Venue:
	var v := Venue.new()
	v.name = "Venue_" + str(entry.id)
	v.venue_id = entry.id
	v.display_name = entry.get("name", "")
	v.kind = entry.get("kind", "cafe")
	v.street = entry.get("street", "")
	v.scene_path = entry.get("scene", "")
	v.hours = entry.get("hours", [])
	var p: Array = entry.position
	v.transform = Transform3D(Basis(Vector3.UP, float(entry.get("yaw", 0.0))), Vector3(p[0], p[1], p[2]))
	return v


func _ready() -> void:
	add_to_group(&"venues")
	add_to_group(&"poi")
	set_meta("radius", SOUND_RADIUS)
	set_meta("poi_type", "")
	_all.append(self)
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var model := (load(scene_path) as PackedScene).instantiate() as Node3D
		model.name = "Model"
		add_child(model)
		_take_materials(PS1Model.apply(model))
		for mesh in _meshes(model):
			if mesh.get_aabb().size.length() < 2.5:
				mesh.visibility_range_end = DETAIL_RANGE
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0, 2.6, 1.6)
	_light.omni_range = 7.0
	_light.light_color = Color(1.0, 0.82, 0.6)
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)
	_update(true)


func _exit_tree() -> void:
	_all.erase(self)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_update(false)


## Open at this clock time (hours, 0..24)?
func open_at(time: float) -> bool:
	for span: Array in (hours if not hours.is_empty() else HOURS.get(kind, [[9.0, 17.0]])):
		var a := float(span[0])
		var b := float(span[1])
		if (time >= a and time < b) or (time + 24.0 >= a and time + 24.0 < b):
			return true
	return false


func _update(force: bool) -> void:
	var clock := get_node_or_null(^"/root/GameClock")
	var time: float = clock.get("time_of_day") if clock else 12.0
	var night: bool = clock.call("is_night") if clock else false
	var open := open_at(time)
	if force or open != is_open or night != _night:
		is_open = open
		_night = night
		set_meta("poi_type", SOUNDS.get(kind, "") if open else "")
		for m in _glow:
			m.set_shader_parameter("emission_energy", (1.5 if night else 0.55) if open else 0.0)
		for m in _neon:
			m.set_shader_parameter("emission_energy", (2.6 if night else 0.9) if open else 0.0)
		for m in _bulbs:
			m.set_shader_parameter("emission_energy", 2.4 if open and night else 0.0)
		for m in _lamps:
			m.set_shader_parameter("emission_energy", 1.8 if night else 0.0)
	_update_light(open and night)


## A real light over the footpath, for the few lit venues nearest the player.
func _update_light(want: bool) -> void:
	var lit := false
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if want and cam:
		var d := global_position.distance_to(cam.global_position)
		if d < LIGHT_REACH:
			var closer := 0
			for other in _all:
				if other != self and other.is_open and other._night \
						and other.global_position.distance_to(cam.global_position) < d:
					closer += 1
			lit = closer < LIT_NEAREST
	_light.visible = lit
	_light.light_energy = 1.3 if lit else 0.0


## Sorts the model's glowing materials by name (lib/venues.py): VN_Glow*,
## VN_Neon*, VN_Bulb*, VN_Lamp*. A glowing picture (the room behind the
## glass) glows as its texture, not a flat colour.
func _take_materials(by_name: Dictionary) -> void:
	for n: String in by_name:
		var m := by_name[n] as ShaderMaterial
		if m == null:
			continue
		if n.begins_with("VN_Glow"):
			var tex: Variant = m.get_shader_parameter("albedo_texture")
			if tex is Texture2D:
				m.set_shader_parameter("emission_texture", tex)
				m.set_shader_parameter("emission_color", Color.WHITE)
			_glow.append(m)
		elif n.begins_with("VN_Neon"):
			_neon.append(m)
		elif n.begins_with("VN_Bulb"):
			_bulbs.append(m)
		elif n.begins_with("VN_Lamp"):
			_lamps.append(m)


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
