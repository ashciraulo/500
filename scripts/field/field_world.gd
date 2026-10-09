class_name FieldWorld
extends Node3D
## The field journal's world side, added under World by the FieldJournal
## autoload once the player's car exists: bird sightings, the photo lab, and
## the fishing spots and the rod, the tackle shop, the binoculars' hook and
## the feeder at home, the quiet places you find by wandering, and the screens
## (binoculars, the journal, the lab and tackle counters, the fishing view),
## which sit on the main scene at window resolution rather than inside the
## lo-fi viewport.

## The photo lab on Lake Street, Northbridge: [x, z, yaw] of the kerbside bay.
const LAB := [346.3, 78.1, -0.49]
## The bait and tackle shop at the end of Mends Street, South Perth, on the
## jetty forecourt: [x, z, yaw] of the kerbside bay (the shop is behind it).
const TACKLE := [-65.0, 2840.6, 1.149]

var birds: FieldBirds
var lab: BirdLab
var binoculars: Binoculars
var journal: JournalScreen
var lab_screen: LabScreen
var fishing: FieldFishing
var tackle: TackleShop
var tackle_screen: TackleScreen
var fishing_screen: FishingScreen
var home: HomeField
var trophies: HomeTrophies
var quiet: QuietPlaces
var flicker: BirdFlicker

var _ui: Array[Node] = []


func _ready() -> void:
	birds = FieldBirds.new()
	birds.name = "FieldBirds"
	add_child(birds)
	lab = BirdLab.new()
	lab.name = "PhotoLab"
	lab.position = Vector3(LAB[0], 0.0, LAB[1])
	lab.rotation.y = LAB[2]
	add_child(lab)
	fishing = FieldFishing.new()
	fishing.name = "FieldFishing"
	add_child(fishing)
	tackle = TackleShop.new()
	tackle.name = "TackleShop"
	tackle.position = Vector3(TACKLE[0], 0.0, TACKLE[1])
	tackle.rotation.y = TACKLE[2]
	add_child(tackle)
	home = HomeField.new()
	home.name = "HomeField"
	add_child(home)
	trophies = HomeTrophies.new()
	trophies.name = "HomeTrophies"
	add_child(trophies)
	quiet = QuietPlaces.new()
	quiet.name = "QuietPlaces"
	quiet.setup(birds)
	add_child(quiet)
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	binoculars = Binoculars.new()
	binoculars.name = "Binoculars"
	journal = JournalScreen.new()
	journal.name = "FieldJournalScreen"
	lab_screen = LabScreen.new()
	lab_screen.name = "LabScreen"
	lab.screen = lab_screen
	tackle_screen = TackleScreen.new()
	tackle_screen.name = "TackleScreen"
	tackle.screen = tackle_screen
	fishing_screen = FishingScreen.new()
	fishing_screen.name = "FishingScreen"
	fishing_screen.fishing = fishing
	fishing.screen = fishing_screen
	flicker = BirdFlicker.new()
	flicker.name = "BirdFlicker"
	flicker.setup(birds, binoculars)
	add_child(flicker)
	for node: Node in [binoculars, journal, lab_screen, tackle_screen, fishing_screen]:
		host.add_child.call_deferred(node)
		_ui.append(node)
	_show_gear.call_deferred()


## The gear rides in the car (the driving side places it): the rod and esky
## from the start, the binoculars and the camera, and a tackle box once
## you've bought kit at the tackle shop.
func _show_gear() -> void:
	if not FieldJournal.gear_changed.is_connected(_show_gear):
		FieldJournal.gear_changed.connect(_show_gear)
	var car := get_tree().get_first_node_in_group(&"player_car")
	if car == null or not car.has_method("set_field_gear"):
		return
	var gear := PackedStringArray(["fishing_rod", "esky", "binoculars", "camera"])
	if FieldJournal.rod > 0 or FieldJournal.esky_level > 0 or FieldJournal.has_crab_net:
		gear.append("tackle_box")
	car.set_field_gear(gear)


func _exit_tree() -> void:
	for node in _ui:
		if is_instance_valid(node):
			node.queue_free()
	BirdModels.clear_cache()
	FishModels.clear_cache()
