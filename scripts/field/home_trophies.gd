class_name HomeTrophies
extends Node3D
## Things you bring home from the field and put up: the old 500 hubcap out of
## the river goes on the outside of the shed door, chrome out, once you've
## kept it, and M.'s loose journal pages go up by the back door, pinned round
## the hook the binoculars hung on, one for each night bird you've found.

const HUBCAP := "fiat_hubcap"
## Kept when the hubcap comes home (field_fishing).
const HUBCAP_KEPT := "fishing/fiat_hubcap"
## On the door's outside face (its -Z side; the origin is at the hinge),
## middle of the door, about eye height.
const HUBCAP_SPOT := Vector3(0.42, 1.45, -0.033)

## M.'s loose pages: [wrong bird id, the page's model].
const PAGES := [
	["wrong_frogmouth", "m_page_frogmouth"], ["wrong_magpie", "m_page_magpie"],
	["wrong_swan", "m_page_swan"], ["wrong_cockatoos", "m_page_cockatoos"],
	["wrong_ibis", "m_page_ibis"], ["wrong_boobook", "m_page_boobook"],
	["wrong_grey_bird", "m_page_grey_bird"],
]
const PAGE_DIR := "res://art/models/home/mystery/%s.glb"
## The wall behind the hook, along the hook's Z (its board stands off it).
const PAGE_WALL := -0.08
## Where each page goes, in the hook's space (+Z into the room, +Y up, +X
## along the coat-hook board toward the corner): two loose columns on the
## strip of wall above the board, between the slider and the corner.
const PAGE_SPOTS := [
	Vector3(0.03, 0.32, 0.0), Vector3(0.24, 0.36, 0.0), Vector3(0.02, 0.56, 0.0),
	Vector3(0.25, 0.6, 0.0), Vector3(0.04, 0.8, 0.0), Vector3(0.23, 0.83, 0.0),
	Vector3(0.13, 1.03, 0.0),
]

var _home: Node3D
var _door: Node3D
var _hook: Node3D
var _hubcap: Node3D
var _pages := {}
var _check := 0.0


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		_door = _home.find_child("Shed_Door", true, false) as Node3D if _home else null
		_hook = _home.find_child("Binoculars_Hook", true, false) as Node3D if _home else null
	_update_hubcap()
	_update_pages()


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


# --- M.'s pages ------------------------------------------------------------------------------------

func _update_pages() -> void:
	if not is_instance_valid(_hook):
		return
	for i in PAGES.size():
		var id: String = PAGES[i][0]
		if is_instance_valid(_pages.get(id)) or not FieldJournal.is_seen(id):
			continue
		var path: String = PAGE_DIR % PAGES[i][1]
		if not ResourceLoader.exists(path):
			continue
		var page := (load(path) as PackedScene).instantiate() as Node3D
		page.name = "MPage_" + id
		_hook.add_child(page)
		page.position = PAGE_SPOTS[i] + Vector3(0, 0, PAGE_WALL + 0.003 + i * 0.0015)
		# Lying face up in the model: stand it on the wall, facing the room,
		# a little crooked, and a pin through the top.
		page.rotation = Vector3(PI * 0.5, 0, sin(i * 2.7) * 0.12)
		var pin := MeshInstance3D.new()
		var head := SphereMesh.new()
		head.radius = 0.006
		head.height = 0.012
		pin.mesh = head
		pin.material_override = PS1Material.make(Color(0.75, 0.12, 0.1) if id != "wrong_grey_bird" else Color(0.15, 0.25, 0.65))
		pin.position = Vector3(0, 0.002, -0.085)
		page.add_child(pin)
		_pages[id] = page


## The pages pinned up so far (tests): {wrong bird id: node}.
func pages() -> Dictionary:
	var out := {}
	for id: String in _pages:
		if is_instance_valid(_pages[id]):
			out[id] = _pages[id]
	return out
