class_name HomeFurniture
extends Node
## Decorating the townhouse: rugs, lamps, armchairs, posters and plants
## ordered with job money from the catalogue on the coffee table. Orders
## arrive the next morning and go where you ordered them for; things you own
## can be moved between spots of their kind for free.
##
## Spots and items are in data/home/furniture.json. Each spot is a townhouse
## empty (Decor_*) with a stand-in place until the model has it; each item is
## art/models/props/home/decor/<id>.glb with a stand-in box until it exists.
## Saved as "furniture".

signal changed

const DATA_PATH := "res://data/home/furniture.json"
const MODEL_DIR := "res://art/models/props/home/decor/"
## The catalogue's stand-in place: on the lounge coffee table.
const CATALOGUE_AT := Vector3(3.25, 3.3, 0.66)

var spots := {}             # spot id -> {kind, name, at, yaw, replaces}
var items := {}             # item id -> {kind, name, price, colour}
## Item ids you own.
var owned: Array = []
## spot id -> item id, for what's out.
var placed := {}
## spot id -> item id, ordered and arriving tomorrow.
var orders := {}

var _home: Node3D
var _nodes := {}            # spot id -> Node3D shown there
var _panel: CanvasLayer
var _check := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the catalogue pauses the game
	SaveGame.register("furniture", self)
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			spots = parsed.get("spots", {})
			for item: Dictionary in parsed.get("items", []):
				items[item.id] = item


func _exit_tree() -> void:
	SaveGame.unregister("furniture")


func save_state() -> Dictionary:
	return {"owned": owned.duplicate(), "placed": placed.duplicate(), "orders": orders.duplicate()}


func load_state(data: Dictionary) -> void:
	owned = data.get("owned", [])
	placed = data.get("placed", {})
	orders = data.get("orders", {})
	refresh()


## Spots there's somewhere to put things: the townhouse has the empty, or
## there's a stand-in place for it.
func open_spots() -> Array:
	return spots.keys().filter(func(id: String) -> bool:
		return spots[id].has("at") or (_home != null and _home.find_child(id, true, false) != null))


func items_for(kind: String) -> Array:
	return items.values().filter(func(i: Dictionary) -> bool: return i.kind == kind)


## Order an item for a spot: paid now, here tomorrow morning.
func order(item_id: String, spot_id: String) -> bool:
	var item: Dictionary = items.get(item_id, {})
	if item.is_empty() or not open_spots().has(spot_id) or spots[spot_id].kind != item.kind:
		return false
	if owned.has(item_id) or orders.values().has(item_id):
		return false
	if not Wallet.spend(int(item.price), "furniture"):
		return false
	orders[spot_id] = item_id
	changed.emit()
	return true


## Put something you own in a spot ("" clears it). It moves from wherever it was.
func place(item_id: String, spot_id: String) -> bool:
	if not spots.has(spot_id):
		return false
	if item_id == "":
		placed.erase(spot_id)
	else:
		if not owned.has(item_id) or items.get(item_id, {}).get("kind", "") != spots[spot_id].kind:
			return false
		for other: String in placed.keys():
			if placed[other] == item_id:
				placed.erase(other)
		placed[spot_id] = item_id
	refresh()
	changed.emit()
	return true


## The morning's delivery.
func deliver() -> PackedStringArray:
	var arrived := PackedStringArray()
	for spot_id: String in orders:
		var item_id: String = orders[spot_id]
		if not owned.has(item_id):
			owned.append(item_id)
		arrived.append(String(items.get(item_id, {}).get("name", item_id)))
		if not placed.values().has(item_id):
			placed[spot_id] = item_id
	orders.clear()
	if not arrived.is_empty():
		Activities.say("Delivered this morning: %s." % ", ".join(arrived))
		Discoveries.discover("home/decorated")
	refresh()
	changed.emit()
	return arrived


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _home == null or not is_instance_valid(_home):
		_home = get_tree().get_first_node_in_group(&"home_base") as Node3D
		if _home:
			_nodes.clear()
			if _home.has_signal("slept"):
				_home.slept.connect(func(_day: int) -> void: deliver())
			_catalogue()
			refresh()


# --- Showing it ----------------------------------------------------------------------

func refresh() -> void:
	if _home == null:
		return
	for spot_id: String in spots:
		var want: String = placed.get(spot_id, "")
		var node: Node3D = _nodes.get(spot_id)
		if node and node.get_meta("item", "") != want:
			node.queue_free()
			_nodes.erase(spot_id)
			node = null
		var spot: Dictionary = spots[spot_id]
		var old := _home.find_child(String(spot.get("replaces", "-")), true, false) as Node3D
		if old:
			old.visible = want == ""
		if want == "" or node:
			continue
		node = _model(want)
		node.set_meta("item", want)
		node.name = "Furniture_" + spot_id
		_home.add_child(node)
		var empty := _home.find_child(spot_id, true, false) as Node3D
		if empty:
			node.global_transform = empty.global_transform
		elif spot.has("at"):
			var at: Array = spot.at
			node.position = Vector3(at[0], at[2], -at[1])
			node.rotation.y = float(spot.get("yaw", 0.0))
		_nodes[spot_id] = node


func _model(item_id: String) -> Node3D:
	var path := MODEL_DIR + item_id + ".glb"
	var node: Node3D
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as Node3D
		PS1Model.apply(node)
	else:
		node = _stand_in(items.get(item_id, {}))
	var bulb := node.find_child("Light", true, false) as Node3D
	if bulb:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.78, 0.5)
		light.light_energy = 0.6
		light.omni_range = 3.5
		bulb.add_child(light)
	return node


## A plain shape in the item's colour, until its model exists.
func _stand_in(item: Dictionary) -> Node3D:
	var root := Node3D.new()
	var colour := Color.html(String(item.get("colour", "#888888")))
	match String(item.get("kind", "")):
		"rug":
			_box(root, Vector3(1.6, 0.012, 2.2), Vector3(0, 0.006, 0), colour)
		"lamp":
			_box(root, Vector3(0.3, 0.03, 0.3), Vector3(0, 0.015, 0), colour.darkened(0.4))
			_box(root, Vector3(0.03, 1.4, 0.03), Vector3(0, 0.7, 0), colour.darkened(0.4))
			_box(root, Vector3(0.36, 0.3, 0.36), Vector3(0, 1.5, 0), colour)
			var light := Node3D.new()
			light.name = "Light"
			light.position = Vector3(0, 1.45, 0)
			root.add_child(light)
		"chair":
			_box(root, Vector3(0.8, 0.4, 0.75), Vector3(0, 0.2, 0), colour)
			_box(root, Vector3(0.8, 0.5, 0.15), Vector3(0, 0.65, -0.3), colour)
		"poster":
			_box(root, Vector3(0.5, 0.7, 0.01), Vector3(0, 0, 0.005), colour)
		"plant":
			_box(root, Vector3(0.32, 0.32, 0.32), Vector3(0, 0.16, 0), Color(0.62, 0.36, 0.24))
			_box(root, Vector3(0.6, 0.9, 0.6), Vector3(0, 0.77, 0), colour)
	return root


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = at
	mesh.material_override = PS1Material.make(color)
	parent.add_child(mesh)


## The catalogue on the coffee table (the townhouse's Catalogue empty, if it has one).
func _catalogue() -> void:
	var book := Node3D.new()
	book.name = "Furniture_Catalogue"
	_home.add_child(book)
	var empty := _home.find_child("Catalogue", true, false) as Node3D
	if empty:
		book.global_transform = empty.global_transform
	else:
		book.position = Vector3(CATALOGUE_AT.x, CATALOGUE_AT.z, -CATALOGUE_AT.y)
		book.rotation.y = 0.3
		_box(book, Vector3(0.21, 0.012, 0.28), Vector3(0, 0.006, 0), Color(0.86, 0.8, 0.66))
		_box(book, Vector3(0.15, 0.002, 0.1), Vector3(0, 0.013, 0.05), Color(0.7, 0.35, 0.25))
	book.add_child(_Spot.new(self))


# --- The catalogue -------------------------------------------------------------------

func open_catalogue(spot_id := "") -> void:
	close_catalogue()
	_panel = CanvasLayer.new()
	_panel.layer = 8
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_panel)  # on the window, not in the lo-fi world view
	var dim := UiStyle.backdrop()
	_panel.add_child(dim)
	var card: Array = UiStyle.centred_card(dim, Vector2(520, 0))
	var box: VBoxContainer = card[1]
	var money := "$%d to spend" % Wallet.balance
	var head: Array = UiStyle.header(box, "Home catalogue" if spot_id == "" else String(spots[spot_id].name),
		"star", money + ". Orders arrive the next morning." if spot_id == "" else money)
	(head[2] as Button).pressed.connect(close_catalogue)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, minf(340.0, get_tree().root.get_visible_rect().size.y * 0.5))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var first: Button
	if spot_id == "":
		for id: String in open_spots():
			var here: String = placed.get(id, "")
			var coming: String = orders.get(id, "")
			var what := "empty"
			if coming != "":
				what = "%s, coming tomorrow" % items[coming].name
			elif here != "":
				what = String(items[here].name)
			var b := _button(list, "%s:  %s" % [spots[id].name, what], open_catalogue.bind(id))
			if first == null:
				first = b
	else:
		var spot: Dictionary = spots[spot_id]
		for item: Dictionary in items_for(spot.kind):
			var id: String = item.id
			var text: String = item.name
			var action: Callable
			if placed.get(spot_id, "") == id:
				text += "  (here)"
			elif owned.has(id):
				text += "  (yours, put it here)"
				action = func() -> void:
					place(id, spot_id)
					open_catalogue(spot_id)
			elif orders.values().has(id):
				text += "  (ordered)"
			else:
				text += "  $%d" % int(item.price)
				if Wallet.can_afford(int(item.price)):
					action = func() -> void:
						order(id, spot_id)
						open_catalogue(spot_id)
			var b := _button(list, text, action)
			b.disabled = not action.is_valid()
			if first == null and not b.disabled:
				first = b
		if placed.has(spot_id):
			_button(list, "Leave it empty", func() -> void:
				place("", spot_id)
				open_catalogue(spot_id))
		var back := Button.new()
		back.text = "Back"
		back.pressed.connect(open_catalogue.bind(""))
		box.add_child(back)
		if first == null:
			first = back
	if first == null:
		first = head[2]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	first.grab_focus.call_deferred()


func close_catalogue() -> void:
	if _panel == null:
		return
	_panel.queue_free()
	_panel = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_browsing() -> bool:
	return _panel != null


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ListButton"
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if action.is_valid():
		b.pressed.connect(action)
	parent.add_child(b)
	return b


func _input(event: InputEvent) -> void:
	if _panel and event.is_action_pressed("pause"):
		close_catalogue()
		get_viewport().set_input_as_handled()


class _Spot extends Node3D:
	var furniture: HomeFurniture

	func _init(owner_furniture: HomeFurniture) -> void:
		furniture = owner_furniture
		name = "Use_catalogue"

	func _ready() -> void:
		add_to_group(&"interactables")

	func interact_point() -> Vector3:
		return global_position

	func interact_hint() -> String:
		return "Browse the home catalogue"

	func interact() -> void:
		furniture.open_catalogue()
