class_name HomeTrophies
extends Node3D
## Things you bring home from the field and put up: the old 500 hubcap out of
## the river goes on the outside of the shed door, chrome out, once you've
## kept it.

const HUBCAP := "fiat_hubcap"
## Kept when the hubcap comes home (field_fishing).
const HUBCAP_KEPT := "fishing/fiat_hubcap"
## On the door's outside face (its -Z side; the origin is at the hinge),
## middle of the door, about eye height.
const HUBCAP_SPOT := Vector3(0.42, 1.45, -0.033)

var _home: Node3D
var _door: Node3D
var _hubcap: Node3D
var _check := 0.0


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		_door = _home.find_child("Shed_Door", true, false) as Node3D if _home else null
	_update_hubcap()


func _update_hubcap() -> void:
	if is_instance_valid(_hubcap) or not is_instance_valid(_door) or not Discoveries.has(HUBCAP_KEPT):
		return
	var f := FieldJournal.fish_species(HUBCAP)
	if f.is_empty():
		return
	_hubcap = FishModels.sized(f, 30.0)
	_hubcap.name = "Hubcap"
	_door.add_child(_hubcap)
	# The model's dome is +Y: tip it over so the chrome faces out.
	_hubcap.rotation = Vector3(-PI * 0.5, 0, 0)
	_hubcap.position = HUBCAP_SPOT


## The hubcap on the shed door (tests), or null.
func hubcap() -> Node3D:
	return _hubcap if is_instance_valid(_hubcap) else null
