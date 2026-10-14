class_name DevPlaces
extends RefCounted
## Where the dev menu's Places tab can take you, read fresh from the game:
## home, the job you're on, workshops, challenges, barn finds, found parts,
## badges, the next mystery clue, venues, and the birding and fishing spots.
## `world` is the 3D world the player is in.


## [[section, [[label, where (Vector3, y NAN when unknown), note, optional
## Callable to run first], ...]], ...]. Empty sections are left out.
static func gather(tree: SceneTree, world: Node) -> Array:
	var out: Array = []
	var home: Array = []
	var house := tree.get_first_node_in_group(&"home_base") as HomeBase
	if house and house.has_marker(&"Spawn_Front"):
		home.append(["Out the front", house.spawn_transform(&"Spawn_Front").origin, "on foot by the gate"])
	var map := tree.get_first_node_in_group(&"perth_map")
	if map and map.has_method(&"get_spawn_transform"):
		home.append(["The carport", (map.get_spawn_transform() as Transform3D).origin, "where the car starts"])
	var target := Jobs.target_site()
	if target:
		home.append(["The job's next stop", target.global_position, target.label()])
	out.append(["Home and the job", home])

	var shops: Array = []
	for node in tree.get_nodes_in_group(&"workshop_spots"):
		if String(node.get("spot_id")) == "home_carport":
			continue
		var kinds: Array[String] = []
		for kind in ["dealer", "parts", "paint", "fuel"]:
			if node.offers(kind):
				kinds.append({"dealer": "car yard", "parts": "parts", "paint": "spray shop", "fuel": "fuel"}[kind])
		shops.append([String(node.get("display_name")), node.global_position, ", ".join(kinds)])
	for node in tree.get_nodes_in_group(&"tackle_shops"):
		shops.append(["Tackle and bait", node.global_position, ""])
	for node in tree.get_nodes_in_group(&"photo_labs"):
		shops.append(["Photo lab", node.global_position, ""])
	out.append(["Workshops, servos and shops", _sorted(shops)])

	var fun: Array = []
	for node in tree.get_nodes_in_group(&"parking_bays"):
		fun.append([String(node.get("title")), node.global_position, "parking challenge"])
	for node in tree.get_nodes_in_group(&"scenic_drives"):
		var points: PackedVector3Array = node.get("points")
		if not points.is_empty():
			fun.append([String(node.get("title")), points[0], "scenic drive, the start"])
	for node in tree.get_nodes_in_group(&"car_meets"):
		fun.append([String(node.get("title")), node.global_position, "car meet"])
	for node in tree.get_nodes_in_group(&"photo_spots"):
		fun.append([String(node.get("title")), node.global_position, "photo spot" + (", taken" if node.is_taken() else "")])
	out.append(["Challenges and photo spots", _sorted(fun)])

	var finds: Array = []
	for node in tree.get_nodes_in_group(&"barn_finds"):
		var id := String(node.get("car_id"))
		var hours: Array = node.get("hours")
		var note := "barn find" + (", already yours" if Classics.is_found(id) else ", hears the rumour")
		if not hours.is_empty():
			note += ", there %d:00 to %d:00" % [int(hours[0]), int(hours[1])]
		finds.append([String(CarCatalogue.get_car(id).get("name", id)), node.global_position, note,
			Classics.hear_rumour.bind(id)])
	for node in tree.get_nodes_in_group(&"found_parts"):
		var id := String(node.get("part_id"))
		var part := PartsCatalogue.get_part(StringName(id))
		var note := "found part"
		if Discoveries.has("part/" + id):
			note += ", already yours"
		elif not FoundPart.turned_up(id):
			note += ", shows once you own a car it fits"
		finds.append([part.display_name if part else id, node.global_position, note])
	var mystery := world.get_node_or_null(^"GameplayPlaces/Mystery") as Mystery
	if mystery:
		var next := ""
		for clue: Dictionary in mystery.clues:
			if not mystery.found.has(clue.id):
				next = clue.id
				break
		var at := mystery.spot_position(next) if next != "" else Vector3.INF
		if at != Vector3.INF:
			finds.append(["The next mystery clue", at, "%s; sets the station on it and the clock to after midnight" % next,
				func() -> void:
					mystery.heard = next
					if not mystery.is_night():
						GameClock.set_time(0.5)])
	out.append(["Finds", finds])

	var badges: Array = []
	for node in tree.get_nodes_in_group(&"collectibles"):
		if not Discoveries.has(node.key()):
			badges.append(["Badge " + String(node.get("badge_id")), node.global_position, ""])
	out.append(["Hidden 500 badges not found yet", badges])

	var venues: Array = []
	for node in tree.get_nodes_in_group(&"venues"):
		venues.append([String(node.get("display_name")), node.global_position, String(node.get("street"))])
	out.append(["Cafes, bars and restaurants", _sorted(venues)])

	var field: Array = []
	for h: Dictionary in FieldJournal.habitats:
		field.append([String(h.get("name", h.id)), Vector3(float(h.get("x", 0.0)), NAN, float(h.get("z", 0.0))),
			"birds" + (", a quiet place" if h.get("hidden", false) else "")])
	for s: Dictionary in FieldJournal.spots:
		var stand: Array = s.get("stand", [])
		if stand.size() == 3:
			field.append([String(s.get("name", s.id)), Vector3(stand[0], stand[1], stand[2]),
				"fishing" + (", a quiet spot" if s.get("hidden", false) else "")])
	out.append(["Birding and fishing", _sorted(field)])
	return out.filter(func(group: Array) -> bool: return not (group[1] as Array).is_empty())




static func _sorted(list: Array) -> Array:
	list.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]).naturalnocasecmp_to(String(b[0])) < 0)
	return list
