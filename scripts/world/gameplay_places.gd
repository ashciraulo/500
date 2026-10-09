class_name GameplayPlaces
extends Node3D
## Puts the gameplay markers into the world from data/world/places.json
## (generated from the map's roads by tools/places/gen_places.py): photo
## spots, parking challenges, barn finds, scenic drives, the car meet, the
## time-trial checkpoints, and badges topping up the map's own to 60.

## Hidden 500 badges in the whole game (the plan's 60), map and ours together.
const BADGE_TOTAL := 60
const PLACES_PATH := "res://data/world/places.json"

var places := {}


func _ready() -> void:
	if not FileAccess.file_exists(PLACES_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACES_PATH))
	if not parsed is Dictionary:
		return
	places = parsed
	var race := TrainRace.new()
	race.name = "TrainRace"
	add_child(race)
	var odd := Oddities.new()
	odd.name = "Oddities"
	add_child(odd)
	var mystery := Mystery.new()
	mystery.name = "Mystery"
	add_child(mystery)
	var decor := HomeDecor.new()
	decor.name = "HomeDecor"
	add_child(decor)
	var shelf := PartsShelf.new()
	shelf.name = "PartsShelf"
	add_child(shelf)
	var life := HomeLife.new()
	life.name = "HomeLife"
	add_child(life)
	var furniture := HomeFurniture.new()
	furniture.name = "HomeFurniture"
	add_child(furniture)
	var crate := RecordCrate.new()
	crate.name = "Records"
	add_child(crate)
	var pad := Skidpad.new()
	pad.name = "Skidpad"
	add_child(pad)
	var odd_home := HomeOddities.new()
	odd_home.name = "HomeOddities"
	add_child(odd_home)
	# The story's late-city events (scripts/world/late_city/).
	var other := OtherHouse.new()
	other.name = "OtherHouse"
	add_child(other)
	# The story's people: the answering machine, act cards, the porch light.
	var people := StoryPeople.new()
	people.name = "StoryPeople"
	add_child(people)
	# The empty road hides the rest of the world, this node with it, so it
	# lives beside it rather than under it.
	var road := EmptyRoad.new()
	road.name = "EmptyRoad"
	get_parent().add_child.call_deferred(road)
	for p: Dictionary in places.get("photo_spots", []):
		var spot := PhotoSpot.new()
		spot.spot_id = p.id
		spot.title = p.title
		_add(spot, p, "Photo_" + p.id)
	for p: Dictionary in places.get("parking", []):
		var bay := ParkingChallenge.new()
		bay.bay_id = p.id
		bay.title = p.title
		bay.gap = float(p.get("gap", 4.6))
		_add(bay, p, "Parking_" + p.id)
	for p: Dictionary in places.get("barn_finds", []):
		var wreck := BarnFind.new()
		wreck.car_id = p.car
		wreck.hours = p.get("hours", [])
		wreck.tarp = bool(p.get("tarp", false))
		_add(wreck, p, "BarnFind_" + p.car)
	for d: Dictionary in places.get("scenic_drives", []):
		var drive := ScenicDrive.new()
		drive.drive_id = d.id
		drive.title = d.title
		var points := PackedVector3Array()
		for q: Array in d.points:
			points.append(Vector3(q[0], q[1], q[2]))
		drive.points = points
		drive.name = "Scenic_" + d.id
		add_child(drive)
	var meet: Dictionary = places.get("car_meet", {})
	if not meet.is_empty():
		var node := CarMeet.new()
		node.meet_id = meet.id
		node.title = meet.title
		_add(node, meet, "Meet_" + meet.id)
	for c: Dictionary in places.get("checkpoints", []):
		var site := JobSite.new()
		site.site_id = c.id
		site.display_name = "Checkpoint"
		site.kinds = PackedStringArray(["trial"])
		site.discoverable = false
		_add(site, c, c.id)
	# Workshops: wait a frame so the map has placed its own.
	_top_up_badges.call_deferred()
	_place_found_parts.call_deferred()
	_place_cuttings.call_deferred()


func _add(node: Node3D, entry: Dictionary, node_name: String) -> void:
	var p: Array = entry.get("p", [0.0, 0.0, 0.0])
	node.name = node_name
	node.transform = Transform3D(Basis(Vector3.UP, float(entry.get("yaw", 0.0))), Vector3(p[0], p[1], p[2]))
	add_child(node)


## Parts you can't buy (data/world/found_parts.json), placed near a barn
## find, a job site or a photo spot.
func _place_found_parts() -> void:
	for entry: Dictionary in FoundPart.entries():
		var at := _place_ref(String(entry.get("near", "")))
		if at == Vector3.INF:
			push_warning("Found part %s: nowhere called '%s'" % [entry.get("part"), entry.get("near")])
			continue
		var o: Array = entry.get("offset", [0.0, 0.0, 0.0])
		var node := FoundPart.new()
		node.part_id = entry.part
		node.name = "FoundPart_" + String(entry.part)
		node.position = at + Vector3(o[0], o[1], o[2])
		node.rotation.y = float(entry.get("yaw", 0.0))
		node.on_foot = bool(entry.get("on_foot", false))
		add_child(node)


## Rare plants to take cuttings of (data/world/cuttings.json).
func _place_cuttings() -> void:
	for entry: Dictionary in HomeLife.cutting_entries():
		var at := _place_ref(String(entry.get("near", "")))
		if at == Vector3.INF:
			push_warning("Cutting %s: nowhere called '%s'" % [entry.get("id"), entry.get("near")])
			continue
		var o: Array = entry.get("offset", [0.0, 0.0, 0.0])
		var spot := CuttingSpot.new()
		spot.cutting_id = entry.id
		spot.title = entry.get("name", entry.id)
		spot.name = "Cutting_" + String(entry.id)
		spot.position = at + Vector3(o[0], o[1], o[2])
		add_child(spot)


## Where a "barn:<car>", "site:<id>" or "photo:<id>" reference is.
func _place_ref(ref: String) -> Vector3:
	var kind := ref.get_slice(":", 0)
	var id := ref.get_slice(":", 1)
	match kind:
		"barn":
			for p: Dictionary in places.get("barn_finds", []):
				if p.car == id:
					return Vector3(p.p[0], p.p[1], p.p[2])
		"photo":
			for p: Dictionary in places.get("photo_spots", []):
				if p.id == id:
					return Vector3(p.p[0], p.p[1], p.p[2])
		"site":
			for site in get_tree().get_nodes_in_group(&"job_sites"):
				if site.get("site_id") == id:
					return (site as Node3D).global_position
	return Vector3.INF


## The map hides badges of its own; ours top them up to BADGE_TOTAL, skipping
## any that would land near one of the map's.
func _top_up_badges() -> void:
	var existing: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(&"collectibles"):
		existing.append((node as Node3D).global_position)
	var wanted := BADGE_TOTAL - existing.size()
	for b: Dictionary in places.get("badges", []):
		if wanted <= 0:
			break
		var at := Vector3(b.p[0], b.p[1], b.p[2])
		if existing.any(func(p: Vector3) -> bool: return p.distance_to(at) < 120.0):
			continue
		var badge := Collectible.new()
		badge.badge_id = b.id
		_add(badge, b, "Badge_" + b.id)
		existing.append(at)
		wanted -= 1
