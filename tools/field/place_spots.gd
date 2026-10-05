extends SceneTree
## Finds where to stand at each fishing spot in data/field/fishing_spots.json
## and writes it back as `stand` [x, y, z] and `yaw` (facing the water):
## on a pier deck, the end furthest out over the water; on the shore, the
## nearest dry footing to the real place with open water in front.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/field/place_spots.gd
##
## Rerun after a map rebuild. Spots it can't place (off the built map) are
## left without `stand` and don't appear in the game.

const PATH := "res://data/field/fishing_spots.json"
const WAIT := 150

var _main: Node
var _car: RigidBody3D
var _boats: Node
var _doc: Dictionary
var _spots: Array
var _index := -1
var _frames := 0


func _process(_delta: float) -> bool:
	if _main == null:
		_doc = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_spots = _doc.spots
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		_frames = WAIT - 30
		return false
	_frames += 1
	if _frames < WAIT:
		return false
	if _boats == null:
		var traffic := get_first_node_in_group(&"traffic")
		_boats = traffic.get("boats") if traffic else null
	if _index >= 0:
		_place(_spots[_index])
	_index += 1
	if _index >= _spots.size():
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(_doc, "\t", false) + "\n")
		f.close()
		quit()
		return true
	var near: Array = _spots[_index].near
	_car.freeze = true
	_car.set_physics_process(false)
	_car.global_position = Vector3(float(near[0]), 40.0, float(near[1]))
	_frames = 0
	return false


func _place(spot: Dictionary) -> void:
	var near := Vector3(float(spot.near[0]), 0.0, float(spot.near[1]))
	var deck: bool = spot.kind == "deck"
	var best := {}
	var best_score := -INF
	# The map's coast can sit a couple of hundred metres off the real beach.
	var reach := 70.0 if deck else (320.0 if spot.water == "ocean" else 260.0)
	var step := 2.0 if deck else 4.0
	var space := _car.get_world_3d().direct_space_state
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var p := near + Vector3(x, 0, z)
			z += step
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 80.0, p + Vector3.DOWN * 20.0, 1 | 2)
			q.exclude = [_car.get_rid()]
			var hit := space.intersect_ray(q)
			# Beaches run down nearly to the waterline; decks and banks stand clear.
			if hit.is_empty() or hit.position.y < (0.4 if deck else 0.12) or hit.position.y > 6.0:
				continue
			var surface := StringName(hit.collider.get_meta("surface", &""))
			if (hit.collider as CollisionObject3D).collision_layer & 2:
				continue  # a building
			if deck and (surface != &"brick" or _water_round(hit.position) < 3.0):
				continue
			if not deck and (surface == &"asphalt" or _boats.water_at(hit.position, 0.0)):
				continue
			# The way with the most open water in front.
			var face := _open_water(hit.position)
			if face.is_empty():
				continue
			var score: float = face.open * 4.0 - Vector2(x, z).length() * (0.05 if deck else 0.4) - hit.position.y * 2.0
			if deck:
				# Out on the end, water all round.
				score += _water_round(hit.position) * 3.0
			if score > best_score:
				best_score = score
				best = {"stand": hit.position, "yaw": face.yaw, "surface": surface}
		x += step
	if best.is_empty():
		if OS.get_environment("DEBUG_SPOTS") != "":
			var q := PhysicsRayQueryParameters3D.create(near + Vector3.UP * 80.0, near + Vector3.DOWN * 20.0)
			print("  debug: ray at mark ", space.intersect_ray(q), " water_at mark ", _boats.water_at(near, 0.0), " mask ", _boats.get("_mask_w"), " car ", _car.global_position)
		spot.erase("stand")
		spot.erase("yaw")
		print("%-22s  no footing near (%.0f, %.0f)" % [spot.id, near.x, near.z])
		return
	var s: Vector3 = best.stand
	spot.stand = [snappedf(s.x, 0.1), snappedf(s.y, 0.05), snappedf(s.z, 0.1)]
	spot.yaw = snappedf(float(best.yaw), 0.01)
	print("%-22s  stand (%.1f, %.2f, %.1f) yaw %.2f on %s, %.0f m from the mark" % [spot.id, s.x, s.y, s.z, best.yaw, best.surface,
		Vector2(s.x - near.x, s.z - near.z).length()])


## {yaw, open}: the direction with the most water ahead, if there's open
## water close in front (the near ones count for more).
func _open_water(p: Vector3) -> Dictionary:
	var out := {}
	var most := 0.0
	for i in 32:
		var a := TAU * i / 32.0
		var d := Vector3(-sin(a), 0, -cos(a))
		var n := 0.0
		var near := 0
		for r: float in [4.0, 8.0, 14.0, 20.0, 30.0, 45.0, 60.0, 80.0]:
			if _is_water(p + d * r):
				n += 1.0 if r > 20.0 else 1.5
				if r <= 20.0:
					near += 1
		if near >= 3 and n > most:
			most = n
			out = {"yaw": a, "open": n}
	return out


func _water_round(p: Vector3) -> float:
	var n := 0
	for i in 8:
		var a := TAU * i / 8.0
		if _is_water(p + Vector3(cos(a), 0, sin(a)) * 6.0):
			n += 1
	return float(n)


## Water: nothing solid above the waterline (a deck over the river isn't
## water), and the river mask, the sea floor or no ground at all below.
func _is_water(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.z), Vector3(p.x, -15.0, p.z), 1 | 2)
	q.exclude = [_car.get_rid()]
	var hit := _car.get_world_3d().direct_space_state.intersect_ray(q)
	# A jetty deck or a bank over the river mask is still in the way.
	if not hit.is_empty() and hit.position.y > 0.25:
		return false
	return hit.is_empty() or hit.position.y < -0.2 or _boats.water_at(p, 0.0)
