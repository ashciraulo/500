class_name FieldWorld
extends Node3D
## The field journal's world side, added under World by the FieldJournal
## autoload once the player's car exists: bird sightings, the photo lab, and
## the fishing spots and the rod, the tackle shop, and the screens
## (binoculars, the journal, the lab and tackle counters, the fishing view),
## which sit on the main scene at window resolution rather than inside the
## lo-fi viewport.

## The photo lab on Lake Street, Northbridge: [x, z, yaw] of the kerbside bay.
const LAB := [346.3, 78.1, -0.49]
## The bait and tackle shop on Mends Street, South Perth, up from the jetty.
const TACKLE := [-111.0, 2916.4, -0.57]

var birds: FieldBirds
var lab: BirdLab
var binoculars: Binoculars
var journal: JournalScreen
var lab_screen: LabScreen
var fishing: FieldFishing
var tackle: TackleShop
var tackle_screen: TackleScreen
var fishing_screen: FishingScreen

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
	for node: Node in [binoculars, journal, lab_screen, tackle_screen, fishing_screen]:
		host.add_child.call_deferred(node)
		_ui.append(node)


func _exit_tree() -> void:
	for node in _ui:
		if is_instance_valid(node):
			node.queue_free()
