class_name TackleShop
extends BirdLab
## The bait and tackle shop at the end of Mends Street, South Perth, on the
## jetty forecourt: the fishing side's dock. Pull into the bay (or walk in to
## the counter) and press F / A to weigh in the esky, buy ice, and look at
## rods, eskies and the crab net.
##
## It stands on its own, down the slope from the bay, on a concrete slab that
## takes up the fall of the ground. Inside: the counter with the scale (the
## last weigh-in's best fish lies on the tray) and the brag board of your
## biggest catches.

## From the bay to the shop's front, across the footpath.
const SET_BACK := 9.0
## The room: 5.6 m wide, 7 m deep behind the front (shop space, -Z inwards).
const ROOM := Vector2(5.6, 7.0)
## Walk up to the counter this close.
const COUNTER_REACH := 2.2
const BRAG_CARDS := 8

var _shop: Node3D
var _counter: Node3D
var _scale_spot: Node3D
var _brag: Node3D
var _on_scale: Node3D
var _cards: Node3D


func _ready() -> void:
	super()
	FieldJournal.weighed_in.connect(_on_weighed_in)
	FieldJournal.fish_landed.connect(_on_fish_landed)


func _group() -> StringName:
	return &"tackle_shops"


func _color() -> Color:
	return Color(0.4, 0.75, 0.95)


func _place_type() -> String:
	return "tackle_shop"


func _shop_model() -> String:
	return "res://art/models/props/field/places/shop_tackle.glb"


func _sign_text() -> String:
	return "BAIT & TACKLE\nweigh-ins  ice\nrods  eskies"


func _prompt_text() -> String:
	return "F / A  Bait and tackle (esky %d of %d)" % [FieldJournal.esky.size(), FieldJournal.esky_size()]


## Free-standing, facing the bay, its floor at the highest ground under it;
## a slab fills in under the low side.
func _place_shop() -> void:
	var path := _shop_model()
	if path == "" or not ResourceLoader.exists(path):
		return
	var space := get_world_3d().direct_space_state
	var side := global_basis.x
	var along := global_basis.z
	var front := global_position + side * SET_BACK
	var high := -INF
	var low := INF
	for d: float in [0.0, 2.0, 4.0, 5.5, ROOM.y]:
		for w: float in [-0.5, 0.0, 0.5]:
			var p := front + side * d + along * w * ROOM.x
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				high = maxf(high, hit.position.y)
				low = minf(low, hit.position.y)
	if high == -INF:
		high = global_position.y
		low = high
	front.y = high
	_shop = (load(path) as PackedScene).instantiate() as Node3D
	_shop.name = "Shopfront"
	add_child(_shop)
	# The model's front is +Z.
	_shop.global_transform = Transform3D(Basis(Vector3.UP, atan2(-side.x, -side.z)), front)
	_add_slab(high - low)
	# The shop's sound is in the room and round the door, not out at the bay.
	remove_from_group(&"poi")
	var sound := Node3D.new()
	sound.name = "Ambience"
	sound.position = Vector3(0, 1.5, -ROOM.y * 0.4)
	sound.add_to_group(&"poi")
	sound.set_meta("poi_type", _place_type())
	sound.set_meta("radius", 10.0)
	_shop.add_child(sound)
	for c in _sign.get_children():
		if not c is Light3D:
			c.visible = false
	_counter = _shop.find_child("Counter", true, false) as Node3D
	_scale_spot = _shop.find_child("Scale", true, false) as Node3D
	_brag = _shop.find_child("BragBoard", true, false) as Node3D
	refresh_brag_board()


## Rendered concrete under the floor, down past the lowest ground.
func _add_slab(fall: float) -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var box := BoxMesh.new()
	var depth := fall + 0.4
	box.size = Vector3(ROOM.x + 0.1, depth, ROOM.y + 0.1)
	slab.mesh = box
	slab.material_override = PS1Material.make(Color(0.72, 0.7, 0.66))
	slab.position = Vector3(0, -depth * 0.5 - 0.005, -ROOM.y * 0.5)
	_shop.add_child(slab)
	# Something to stand on under the slab's top: the model's floor is a
	# mesh, and the map's ground drops away behind the front.
	var body := StaticBody3D.new()
	body.name = "Slab_Col"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", &"concrete")
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	body.add_child(shape)
	body.position = slab.position
	_shop.add_child(body)


## True when the player is parked in the bay or standing at the counter.
func in_reach() -> bool:
	var car := get_tree().get_first_node_in_group(&"player_car") as CarController
	if car == null:
		return false
	var walker := car.get_parent().get_node_or_null(^"Player") as Node3D
	if walker and not walker.get("in_car"):
		return at_counter(walker.global_position)
	return super()


## Inside the shop and close enough to lean on the counter.
func at_counter(p: Vector3) -> bool:
	if _shop == null or _counter == null:
		return false
	if not is_inside(p):
		return false
	var local := _shop.to_local(p)
	var c := _shop.to_local(_counter.global_position)
	return Vector2(local.x - c.x, local.z - c.z).length() < COUNTER_REACH


## True when p is inside the room (tests, ambience).
func is_inside(p: Vector3) -> bool:
	if _shop == null:
		return false
	var local := _shop.to_local(p)
	return absf(local.x) < ROOM.x * 0.5 and local.z < 0.0 and local.z > -ROOM.y and local.y > -0.5 and local.y < 3.5


# --- the scale and the brag board ------------------------------------------------------------

## The best fish of a weigh-in lies on the scale's tray until the next one.
func _on_weighed_in(fish: Array, _pay: int) -> void:
	var best := {}
	for f: Dictionary in fish:
		if best.is_empty() or float(f.kg) > float(best.kg):
			best = f
	if not best.is_empty():
		put_on_scale(String(best.species), float(best.cm))
	refresh_brag_board()


func _on_fish_landed(_fish: Dictionary) -> void:
	refresh_brag_board()


func put_on_scale(species: String, cm: float) -> void:
	if is_instance_valid(_on_scale):
		_on_scale.queue_free()
	_on_scale = null
	if _scale_spot == null:
		return
	var f := FieldJournal.fish_species(species)
	if f.is_empty():
		return
	_on_scale = FishModels.sized(f, cm)
	_on_scale.name = "OnTheScale"
	_scale_spot.add_child(_on_scale)
	# On its side on the tray, the tail hanging over a big one.
	_on_scale.rotation = Vector3(0, PI * 0.5, PI * 0.5)
	_on_scale.position = Vector3.UP * (0.01 + 0.07 * cm / 100.0)


## What's on the tray now (tests): the fish node, or null.
func on_scale() -> Node3D:
	return _on_scale if is_instance_valid(_on_scale) else null


## Your biggest of each species pinned to the board: the photo if you took
## one, otherwise the fish itself on a card, with the weight underneath.
func refresh_brag_board() -> void:
	if _brag == null:
		return
	if is_instance_valid(_cards):
		_cards.free()
	_cards = Node3D.new()
	_cards.name = "Cards"
	_brag.add_child(_cards)
	var best := brag_list()
	var card_mat := PS1Material.make(Color(0.93, 0.91, 0.86))
	for i in best.size():
		var e: Dictionary = best[i]
		var card := Node3D.new()
		card.name = "Card%d" % i
		# Two rows of four across the cork, a little crooked.
		card.position = Vector3(-0.69 + (i % 4) * 0.46, 0.2 - (i / 4) * 0.4, 0.035)
		card.rotation.z = sin(i * 2.3) * 0.06
		_cards.add_child(card)
		var back := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.3, 0.34)
		back.mesh = quad
		back.material_override = card_mat
		card.add_child(back)
		var f := FieldJournal.fish_species(String(e.id))
		var tex := FieldUI.photo_texture(String(e.get("best_file", "")))
		if tex:
			var photo := MeshInstance3D.new()
			var pq := QuadMesh.new()
			pq.size = Vector2(0.27, 0.2)
			photo.mesh = pq
			var m := StandardMaterial3D.new()
			m.albedo_texture = tex
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			photo.material_override = m
			photo.position = Vector3(0, 0.06, 0.002)
			card.add_child(photo)
		else:
			# Sized to the card, flank out.
			var fish := FishModels.build(f)
			fish.scale = Vector3.ONE * 0.24
			fish.rotation.y = PI * 0.5
			fish.position = Vector3(0, 0.07, 0.02)
			card.add_child(fish)
		var label := Label3D.new()
		var kg := float(e.kg)
		label.text = "%s\n%s kg" % [String(f.get("name", e.id)), ("%.1f" % kg) if kg >= 1.0 else ("%.2f" % kg)]
		label.font_size = 18
		label.pixel_size = 0.0022
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = 0.28 / label.pixel_size
		label.modulate = Color(0.12, 0.12, 0.14)
		label.outline_size = 0
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.position = Vector3(0, -0.005, 0.003)
		card.add_child(label)


## [{id, kg, cm, best_file}], heaviest first: real fish you've landed.
func brag_list() -> Array:
	var out := []
	for id: String in FieldJournal.catches:
		var f := FieldJournal.fish_species(id)
		if f.is_empty() or not FieldJournal.counts(f):
			continue
		var e: Dictionary = FieldJournal.catches[id]
		if float(e.get("biggest_kg", 0.0)) <= 0.0:
			continue
		out.append({"id": id, "kg": float(e.biggest_kg), "cm": float(e.biggest_cm), "best_file": String(e.get("best_file", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.kg > b.kg)
	return out.slice(0, BRAG_CARDS)
