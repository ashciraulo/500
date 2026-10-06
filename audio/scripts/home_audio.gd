extends Node
## The townhouse's own sound (Audio.hooks adds it once the map has the house).
##
## - Marks the lanes round it as the quiet "home" zone (Audio.ambience.home_at).
## - Indoors on foot, the street, traffic and weather come through the walls
##   (Audio.set_indoors), and the house is heard instead: the fridge humming
##   in the kitchen and the alarm clock ticking by the bed, each a 3D source
##   you only hear close to it.

## Where things are, in house coordinates (Blender: x across, y back from the
## street, z up). Keep in step with build_shenton.py (Fridge-col, Dress_AlarmClock).
const FRIDGE := Vector3(2.5, 7.35, 1.0)
const CLOCK := Vector3(5.12, 1.19, 3.75)
## The house's footprint, the same box home_oddities.gd uses (the courtyard
## and carport behind it are outside).
const HOUSE_MIN := Vector3(0.0, 0.0, -0.5)
const HOUSE_MAX := Vector3(5.4, 12.0, 8.0)

var _home: Node3D
var _hum: Array[AudioStreamPlayer3D] = []
var _check := 0.0


func setup(home: Node3D) -> void:
	_home = home
	Audio.ambience.home_at = home.global_position
	_hum.append(_loop("home/home_fridge_hum", FRIDGE, -16.0, 1.2, 12.0))
	_hum.append(_loop("home/home_clock_tick", CLOCK, -20.0, 0.5, 5.0))


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	if not is_instance_valid(_home):
		Audio.set_indoors(false)
		return
	var ear: Node3D = Audio.listener()
	var indoors: bool = ear != null and not Audio.is_player_inside() and contains(ear.global_position)
	Audio.set_indoors(indoors)
	# The house's hums only play while you could hear them.
	for p in _hum:
		var near := ear != null and ear.global_position.distance_to(p.global_position) < p.max_distance
		if near and not p.playing:
			p.play(randf() * p.stream.get_length())
		elif not near and p.playing:
			p.stop()


func _exit_tree() -> void:
	Audio.set_indoors(false)


## Whether a world position is inside the townhouse.
func contains(world_pos: Vector3) -> bool:
	var p := _home.global_transform.affine_inverse() * world_pos
	var b := Vector3(p.x, -p.z, p.y)  # back to house coordinates
	return b.x >= HOUSE_MIN.x and b.x <= HOUSE_MAX.x and b.y >= HOUSE_MIN.y and b.y <= HOUSE_MAX.y \
			and b.z >= HOUSE_MIN.z and b.z <= HOUSE_MAX.z


func _loop(sound: String, at: Vector3, volume_db: float, unit: float, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = sound.get_file()
	p.stream = Audio.stream(sound, true)
	p.bus = "SFX"
	p.volume_db = volume_db
	p.unit_size = unit
	p.max_distance = reach
	p.max_db = 0.0
	p.attenuation_filter_cutoff_hz = 20500.0
	_home.add_child(p)
	p.position = Vector3(at.x, at.z, -at.y)
	return p
