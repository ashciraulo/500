extends SceneTree
## The field journal end to end: species and places load, birds turn up in
## their places (on a lawn, in a tree, circling, on the river), the
## binoculars identify one, the focus dial takes its photo, the lab develops
## and sells the roll, the journal and lab screens open, and it all saves.
## After midnight, once the mystery has moved on, the wrong birds turn up.
## Then fishing off the Mends Street jetty: cast, a bite, the fight, a bream
## in the esky, a line snapped by a mulloway, the crab net, and the weigh-in
## at the tackle shop.
##
##   godot --headless --path . --fixed-fps 60 --script res://tools/field_test.gd -- --no-save
##
## With a display (xvfb-run) and shots=<dir> it saves screenshots of each
## stage. Exits with code 1 if any check fails.

const LAWNS := Vector3(-935.6, 66.0, 1455.6)     # Kings Park lookout car park
const BUSH := Vector3(-2189.0, 48.0, 1822.0)     # Lovekin Drive, Kings Park
const RIVER := Vector3(742.0, 3.0, 1533.0)       # Riverside Drive by the quay
const FRASER := Vector3(-911.35, 59.35, 923.83)   # Fraser Avenue's lemon gums
# FieldFishing.State, spelled out: naming the class here would compile it
# before the autoloads it uses exist.
const F_IDLE := 0
const F_READY := 1
const F_CHARGING := 2
const F_WAITING := 3
const F_BITE := 4
const F_FIGHT := 5
const F_LANDED := 6

var _quitting := false
var _main: Node
var _car: RigidBody3D
var _fj: Node
var _field: Node
var _birds: Node
var _bino: Node
var _failures: Array[String] = []
var _stage := 0
var _frames := 0
var _shots := ""
var _target: Dictionary = {}
var _money := 0
var _wait := 0
var _retries := 0
var _seen_before := 0
var _walker: Node3D
var _fishing: Node
var _spot := {}
var _lost: Array[String] = []
var _tries := 0


func _process(_delta: float) -> bool:
	if _quitting:
		return false
	if _main == null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("shots="):
				_shots = arg.trim_prefix("shots=")
				DirAccess.make_dir_recursive_absolute(_shots)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		current_scene = _main
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_locked(true)
		root.get_node("Weather").set_state(0, true)
		_fj = root.get_node("FieldJournal")
		if _shots != "":
			root.get_node("Settings").show_help = false
		return false
	_frames += 1
	var clock := root.get_node("GameClock")
	match _stage:
		0:
			if _frames == 90:
				_field = _main.find_child("Field", true, false)
				_check(_field != null, "the field journal's world is built")
				if _field == null:
					return _finish()
				_birds = _field.birds
				_bino = _field.binoculars
				_birds.auto_spawn = false
				_check(_fj.bird_order.size() >= 42, "42 species (%d)" % _fj.bird_order.size())
				_check(_fj.habitats.size() >= 20, "real places (%d)" % _fj.habitats.size())
				_check(_bino != null and _bino.is_inside_tree(), "binoculars ready")
				# The binoculars start on the hook by the back door.
				var disc := root.get_node("Discoveries")
				disc._found.erase("field/binoculars")
				_check(String(_bino.blocked_reason()).contains("hook"), "the binoculars start on the hook at home")
				_field.home.take_binoculars()
				_check(disc.has("field/binoculars") and not String(_bino.blocked_reason()).contains("hook"), "taken off the hook")
				# Thirty species puts a feeder up in the courtyard, with visitors by day.
				var saved: Dictionary = _fj.entries.duplicate(true)
				for id: String in _fj.bird_order:
					if not _fj.bird(id).get("wrong", false) and _fj.entries.size() < 30:
						_fj.entries[id] = {"seen": 1, "time": "08:00", "where": "test"}
				clock.set_time(10.0)
				_field.home._update_feeder()
				_field.home._animate_visitors(0.1)
				var feeder: Node3D = _field.home._feeder
				_check(is_instance_valid(feeder) and feeder.is_inside_tree(), "a feeder in the courtyard at 30 species")
				_check(_field.home._visitors.size() >= 1, "birds at the feeder (%d)" % _field.home._visitors.size())
				_field.home._clear_visitors()
				if is_instance_valid(feeder):
					feeder.queue_free()
				_fj.entries = saved
				_check_quiet_places(disc)
				_check(_field.journal.is_inside_tree() and _field.lab_screen.is_inside_tree(), "journal and lab screens ready")
				# Hours wrap past midnight; dry birds skip the rain.
				var frog: Dictionary = _fj.bird("tawny_frogmouth")
				_check(_fj.is_about(frog, 23.0, 0.0) and _fj.is_about(frog, 2.0, 0.0) and not _fj.is_about(frog, 12.0, 0.0), "frogmouths are night birds")
				_check(not _fj.is_about(_fj.bird("new_holland_honeyeater"), 7.0, 0.9), "honeyeaters keep out of the rain")
				var dusk := _ids(_fj.candidates(_fj.habitat("kings_park_bush"), 18.0, 0.0))
				_check(dusk.has("carnabys_black_cockatoo"), "Carnaby's in Kings Park at dusk")
				_check(not dusk.has("black_swan"), "no swans in the bush")
				var night := _ids(_fj.candidates(_fj.habitat("kings_park_bush"), 1.0, 0.0))
				_check(night.has("southern_boobook") and not night.has("rainbow_lorikeet"), "boobooks, not lorikeets, at 1 am")
				var quay := _ids(_fj.candidates(_fj.habitat("claisebrook_cove"), 10.0, 0.0))
				_check(quay.has("australian_pelican"), "pelicans at Claisebrook")
				_check(not _ids(_fj.candidates(_fj.habitat("northbridge"), 10.0, 0.0)).has("australian_magpie"), "magpies are traffic's, not spawned twice")
				clock.set_time(8.0)
				_teleport(LAWNS, 0.0)
				_next()
		1:  # Kings Park lawns: a galah on the grass, a kestrel overhead.
			if _frames == 30:
				var h: Dictionary = _fj.habitat("kings_park_lawns")
				var galah := _spawn_near("galah", h, LAWNS, 45.0)
				_check(not galah.is_empty(), "galahs on the Kings Park lawn")
				if not galah.is_empty():
					_check(galah.birds[0].kind == "ground", "galahs on the ground (%s)" % galah.birds[0].kind)
					_target = galah
				var kestrel := _spawn_near("nankeen_kestrel", h, LAWNS, 60.0)
				_check(not kestrel.is_empty() and kestrel.birds[0].state == "circle", "a kestrel up in the air")
				if galah.is_empty():
					return _finish()
				_check(_bino.open(), "binoculars come up in a stopped car")
				_aim(galah.birds[0].node)
			elif _frames > 30 and _frames < 400:
				# Grazing galahs wander; keep on one you can see over the lawn's rises.
				_aim(_visible_bird(_target))
				if _fj.is_seen("galah"):
					_check(true, "the galah is identified")
					_shot("01_binoculars_galah")
					_next()
			elif _frames == 400:
				_check(false, "the galah was never identified (target %s)" % str(_bino.target))
				_next()
		2:  # The shot: hit every arc.
			# Hold on the bird being focused; before that, one you can see. A
			# grazing galah can still wander behind a rise mid-shot and be
			# lost, so that gets a fresh go at another (a few times at most).
			var focused = _bino.dial.get("node")
			_aim(focused if is_instance_valid(focused) else _visible_bird(_target))
			if _frames == 5:
				_bino._start_shot()
				_check(_bino.state == 2, "the focus dial starts")
			elif _frames == 20:
				_shot("02_focus_dial")
			elif _frames > 20 and _bino.state == 2 and _frames % 10 == 0:
				_bino.dial.needle = _bino.dial.arcs[0]
				_bino._press()
			elif _frames > 20 and _bino.state != 2 and _wait == 0:
				_wait = _frames
			if _wait > 0 and _frames > _wait + 10 and _fj.roll.is_empty() and _retries < 3:
				print("  (lost the galah mid-shot, trying again)")
				_retries += 1
				_wait = 0
				_frames = 0
			elif _wait > 0 and _frames > _wait + 10:
				_check(_fj.roll.size() == 1, "a frame on the roll (%d)" % _fj.roll.size())
				_check(_fj.is_photographed("galah"), "the galah's page has a photo")
				var e: Dictionary = _fj.entry("galah")
				_check(int(e.get("best", 0)) == 3 or _bino.target.get("frame", 0.0) < 0.04, "every sharp press is three stars (got %s)" % e.get("best"))
				_check(FileAccess.file_exists(String(e.get("best_file", ""))) or DisplayServer.get_name() == "headless", "the photo is in the album")
				_shot("03_after_shot")
				_bino.close()
				_check(_car.player_controlled, "the car is back in your hands")
				_wait = 0
				_next()
		3:  # Kings Park bushland: a wattlebird in a tree; scare it off.
			if _frames == 1:
				_teleport(BUSH, 0.0)
			elif _frames == 240:
				var h: Dictionary = _fj.habitat("kings_park_bush")
				# The map's trees are multimesh instances, which the headless renderer doesn't keep.
				if DisplayServer.get_name() != "headless":
					var crowns: Array = _birds.trees_near(BUSH, 120.0)
					_check(not crowns.is_empty(), "trees in Kings Park to perch in (%d)" % crowns.size())
				var wattle := _spawn_near("red_wattlebird", h, BUSH, 40.0)
				_check(not wattle.is_empty(), "a wattlebird in the bush")
				if not wattle.is_empty():
					_check(wattle.birds[0].kind in ["tree", "post"], "up a tree (%s)" % wattle.birds[0].kind)
					var below: Dictionary = _birds.ground(wattle.birds[0].node.global_position)
					_check(not below.is_empty() and wattle.birds[0].node.global_position.y > below.pos.y + 2.0, "up off the ground")
					_target = wattle
				_shot("04_bush_wattlebird")
			elif _frames == 250 and not _target.is_empty():
				var before: int = _birds.stats.flushed
				_birds.flush(_target.birds[0].node, BUSH)
				_check(_birds.stats.flushed == before + 1 and _target.birds[0].state == "fly", "it flushes")
			elif _frames == 800:
				_check(_target.birds[0].state == "gone", "and it's gone (%s)" % _target.birds[0].state)
				_next()
		4:  # The river: a black swan on the water, a cormorant on a post.
			if _frames == 1:
				_teleport(RIVER, 1.2)
				clock.set_time(9.0)
			elif _frames == 60:
				var boats: Node = get_first_node_in_group(&"traffic").get("boats")
				var water := Vector3.INF
				for r in [40.0, 70.0, 100.0, 140.0]:
					for i in 16:
						var p: Vector3 = RIVER + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * r
						if boats.water_at(p, 8.0):
							water = p
							break
					if water != Vector3.INF:
						break
				_check(water != Vector3.INF, "open water off Riverside Drive")
				if water != Vector3.INF:
					var swan: Dictionary = _birds.spawn(_fj.bird("black_swan"), _fj.habitat("langley_park"), water)
					_check(not swan.is_empty() and absf(swan.birds[0].node.global_position.y) < 0.3, "a black swan sitting on the river")
					var shag: Dictionary = _birds.spawn(_fj.bird("little_pied_cormorant"), _fj.habitat("langley_park"), water + Vector3(4, 0, 0))
					_check(not shag.is_empty() and shag.birds[0].kind == "post", "a cormorant on a post")
				_shot("05_river_swan")
				_next()
		5:  # After midnight: the wrong birds, once the mystery has moved on.
			if _frames == 1:
				clock.set_time(2.75)
				_teleport(FRASER, 0.3)
			elif _frames == 60:
				var cockies: Dictionary = _fj.bird("wrong_cockatoos")
				_seen_before = _fj.seen_count()
				_check(not _ids(_fj.candidates(_fj.habitat("kings_park_bush"), 2.75, 0.0)).has("wrong_cockatoos"), "wrong birds aren't ordinary sightings")
				_check(not _birds.wrong_ready(cockies, 2.75), "no thirteen cockatoos before the street directory page")
				var disc := root.get_node("Discoveries")
				for clue in ["tape_1", "polaroid", "ticket", "atlas_page"]:
					disc.discover("mystery/" + clue)
				_check(_birds.wrong_ready(cockies, 2.75) and not _birds.wrong_ready(cockies, 12.0), "after the page, at 3 am, they're out")
				_check(not _birds.wrong_ready(_fj.bird("wrong_ibis"), 2.75), "the ibis waits for the keyring")
				var at: Vector3 = _birds.wrong_place(cockies)
				_check(at.distance_to(FRASER) < 1.0, "the cockatoos' place is Fraser Avenue")
				_check(_birds.wrong_place(_fj.bird("wrong_frogmouth")) != Vector3.INF, "the frogmouth's pole is outside home")
				# Stand off a little, so the snag (headless, no trees) isn't on the car.
				_target = _birds.spawn_wrong(cockies, at + Vector3(18, 0, 0))
				_check(not _target.is_empty() and _target.birds.size() == 13, "thirteen of them (%d)" % (_target.birds.size() if not _target.is_empty() else 0))
				if _target.is_empty():
					return _finish()
				_check(_bino.open(), "binoculars up at night")
				_aim(_target.birds[0].node)
			elif _frames > 60 and _frames < 600:
				_aim(_target.birds[0].node)
				if _fj.is_seen("wrong_cockatoos"):
					_check(root.get_node("Discoveries").has("field/wrong_cockatoos"), "seeing one is a discovery")
					_check(_fj.seen_count() == _seen_before and _fj.species_total() == 42, "they don't count as species (%d of %d)" % [_fj.seen_count(), _fj.species_total()])
					_check(_target.birds.all(func(b: Dictionary) -> bool: return b.state == "perch"), "none of them flush")
					_bino._start_shot()
					_wait = 0
					_frames = 600
			elif _frames > 600 and _bino.state == 2 and _frames % 10 == 0:
				_aim(_target.birds[0].node)
				_bino.dial.needle = _bino.dial.arcs[0]
				_bino._press()
			elif _frames > 600 and _bino.state != 2:
				_check(_fj.roll.size() == 2 and _fj.roll[1].wrong, "a photo of one on the roll")
				_shot("08_wrong_cockatoos")
				_bino.close()
				_field.journal.open()
				_field.journal._selected = "wrong_cockatoos"
				_field.journal.refresh()
				_shot("09_wrong_page")
				_field.journal.close()
				_birds.clear()
				clock.set_time(9.0)
				_next()
			if _frames == 599:
				_check(false, "the cockatoos were never identified (target %s)" % str(_bino.target))
				_bino.close()
				_birds.clear()
				_next()
		6:  # The lab: develop and sell.
			var lab: Node3D = _field.lab
			if _frames == 1:
				_teleport(Vector3(lab.global_position.x, 60.0, lab.global_position.z) + lab.global_basis.x * 6.0, lab.rotation.y)
			elif _frames == 60:
				_check(lab._grounded, "the lab finds the ground on Lake Street (y %.1f)" % lab.global_position.y)
				_teleport(lab.global_position + Vector3.UP * 0.3, lab.rotation.y)
			elif _frames == 70:
				_car.freeze = false
				_car.set_physics_process(true)
			elif _frames == 100:
				_view_shop(lab)
			elif _frames == 110:
				_shot("06_lab_front")
				_view_shop(null)
			elif _frames == 120:
				_check(lab.in_reach(), "parked in the lab's bay (local %s, speed %.1f)" % [lab.to_local(_car.global_position), _car.linear_velocity.length()])
				_money = root.get_node("Wallet").balance
				_field.lab_screen.open()
				_check(_field.lab_screen.is_open() and paused, "the lab counter opens and pauses")
				var result: Dictionary = _fj.develop()
				_field.lab_screen._last_result = result
				_field.lab_screen.refresh()
				_check(result.prints.size() == 2 and _fj.roll.is_empty(), "two prints developed, the roll is empty")
				_check(root.get_node("Wallet").balance == _money + int(result.pay) and int(result.pay) > 0, "the prints pay ($%d)" % result.pay)
				_check(result.prints[0].first, "first print of a species earns the bonus")
				_check(result.prints[1].wrong and int(result.prints[1].pay) == 0, "the cockatoo print comes out blank")
			elif _frames == 130:
				_shot("06_lab")
				_field.lab_screen.close()
				_check(not paused, "closing the counter unpauses")
				_field.journal.open()
				_field.journal._selected = "galah"
				_field.journal.refresh()
				_check(_field.journal.is_open(), "the journal opens")
			elif _frames == 140:
				_shot("07_journal")
				_field.journal.close()
				var state: Dictionary = _fj.save_state()
				var copy: Dictionary = JSON.parse_string(JSON.stringify(state))
				_fj.entries = {}
				_fj.load_state(copy)
				_check(_fj.is_photographed("galah") and _fj.prints_sold == 1, "the journal survives a save and load")
				_check(root.get_node("Progression").get_stat("species_photographed") >= 1.0, "the career counts photographed species")
				_check_lens_and_film(clock)
				_next()
		7:  # Fishing off the Mends Street jetty at dusk.
			_stage_fishing(clock)
		8:  # The tackle shop: ice, the weigh-in, and it all saves.
			var shop: Node3D = _field.tackle
			if _frames == 1:
				# Getting in takes a couple of seconds (door, belt, key).
				_walker.get_in()
			elif _frames == 150:
				_teleport(Vector3(shop.global_position.x, 60.0, shop.global_position.z) + shop.global_basis.x * 6.0, shop.rotation.y)
			elif _frames == 210:
				_check(shop._grounded, "the tackle shop finds the ground on Mends Street (y %.1f)" % shop.global_position.y)
				_teleport(shop.global_position + Vector3.UP * 0.3, shop.rotation.y)
			elif _frames == 220:
				_car.freeze = false
				_car.set_physics_process(true)
			elif _frames == 260:
				_view_shop(shop)
			elif _frames == 270:
				_shot("10_tackle_front")
				_view_shop(null)
			elif _frames == 280:
				_check(shop.in_reach(), "parked in the tackle shop's bay (local %s)" % shop.to_local(_car.global_position))
				var wallet := root.get_node("Wallet")
				_money = wallet.balance
				_field.tackle_screen.open()
				_check(_field.tackle_screen.is_open() and paused, "the tackle counter opens and pauses")
				_check(_fj.buy_ice() and _fj.ice_left_hours() > 7.0, "a bag of ice")
				var kept: int = _fj.esky.size()
				var result: Dictionary = _fj.weigh_in()
				_field.tackle_screen._last_result = result
				_field.tackle_screen.refresh()
				_check(result.fish.size() == kept and kept >= 1 and _fj.esky.is_empty(), "the esky weighed in (%d fish)" % kept)
				_check(int(result.pay) > 0 and wallet.balance == _money - _fj.ICE_PRICE + int(result.pay), "the club pays ($%d)" % result.pay)
				_check(not result.fish.is_empty() and result.fish[0].first, "first of a species on the board earns the bonus")
			elif _frames == 290:
				_shot("10_tackle")
				_field.tackle_screen.close()
				_check(not paused, "closing the tackle counter unpauses")
				_check_walk_in(shop, _field.tackle_screen._last_result)
				# The crab net went on the journal directly back at the jetty.
				_check(_car.field_gear.has("esky") and _car.field_gear.has("fishing_rod"), "the rod and esky ride in the car")
				_fj.gear_changed.emit()
				_check(_car.field_gear.has("tackle_box"), "a tackle box rides in the car once you've bought kit")
				_field.journal.open()
				_field.journal._tab = "fish"
				_field.journal._selected = "black_bream"
				_field.journal.refresh()
			elif _frames == 300:
				_shot("11_journal_fish")
				_field.journal.close()
				var state: Dictionary = _fj.save_state()
				var copy: Dictionary = JSON.parse_string(JSON.stringify(state))
				_fj.catches = {}
				_fj.load_state(copy)
				_check(_fj.is_caught("black_bream") and _fj.fish_weighed >= 1 and _fj.has_crab_net, "the catches survive a save and load")
				_check(root.get_node("Progression").get_stat("fish_species") >= 1.0, "the career counts fish species")
				_check_hubcap(root.get_node("Discoveries"))
				return _finish()
	return false


func _stage_fishing(clock: Node) -> void:
	if _frames == 1:
		_walker = _main.get_node("LoFi/SubViewport/World/Player")
		_fishing = _field.fishing
		_fishing.lost.connect(func(why: String) -> void: _lost.append(why))
		_check(_fj.fish_order.size() >= 15, "15 fish (%d)" % _fj.fish_order.size())
		_check(_fj.spots.size() >= 18, "fishing spots placed on the map (%d)" % _fj.spots.size())
		_spot = _fj.spot("mends_st_jetty")
		_check(not _spot.is_empty(), "the Mends Street jetty is a spot")
		var dusk := _ids(_fj.fish_candidates(_spot, 18.5))
		_check(dusk.has("black_bream") and not dusk.has("mulloway") and not dusk.has("king_george_whiting"), "bream at the jetty at dusk, no mulloway or KGs")
		_check(_ids(_fj.fish_candidates(_fj.spot("elizabeth_quay"), 12.0)).has("fiat_hubcap"), "something odd in the river off the quay")
		_check(_ids(_fj.fish_candidates(_fj.spot("fremantle_harbour"), 21.0)).has("squid"), "squid under the harbour lights at night")
		# The wrong bream: Mends St after midnight, once the ticket's found.
		var disc := root.get_node("Discoveries")
		var had_ticket: bool = disc.has("mystery/ticket")
		disc._found.erase("mystery/ticket")
		_check(not _ids(_fj.fish_candidates(_spot, 1.0)).has("wrong_bream"), "no tagged bream before the ticket")
		disc._found["mystery/ticket"] = 1
		_check(_ids(_fj.fish_candidates(_spot, 1.0)).has("wrong_bream"), "a tagged bream at Mends St after midnight")
		_check(not _ids(_fj.fish_candidates(_spot, 13.0)).has("wrong_bream"), "but not by day")
		_check(not _ids(_fj.fish_candidates(_fj.spot("coode_st_jetty"), 1.0)).has("wrong_bream"), "and only at Mends St")
		var total: int = _fj.fish_total()
		var tagged: Dictionary = _fj.land(_fj.fish_size(_fj.fish_species("wrong_bream"), RandomNumberGenerator.new()), "Mends Street jetty")
		_check(tagged.first and _fishing.keep_blocked(tagged) != "" and not _fj.keep(tagged), "it can't go in the esky")
		_check(_fj.fish_total() == total and not _fj.counts(_fj.fish_species("wrong_bream")), "and doesn't count as a species")
		_check(not _ids(_fj.fish_candidates(_spot, 1.0)).has("wrong_bream"), "once caught it's done")
		_fj.catches.erase("wrong_bream")
		if not had_ticket:
			disc._found.erase("mystery/ticket")
		_check_wrong_flathead(disc)
		_check(_ids(_fj.fish_candidates(_spot, 12.0, "net")) == ["blue_swimmer_crab"], "the crab net catches crabs")
		clock.set_time(18.5)
		_teleport(Vector3(-4.0, 9.6, 2873.0), 2.0)
		_hide_help()
	elif _frames == 90:
		_car.freeze = false
		_car.set_physics_process(true)
	elif _frames == 120:
		_walker.get_out()
	elif _frames == 230:
		# Getting out takes a moment: key, door, step.
		_check(not _walker.in_car, "out of the car on the Esplanade")
		var stand: Vector3 = _fj.spot_stand(_spot)
		var yaw := float(_spot.yaw)
		_walker.teleport(stand + Vector3.UP * 0.1, stand + Vector3(-sin(yaw), -0.3, -cos(yaw)) * 10.0)
	elif _frames == 270:
		_check(root.get_node("Discoveries").has("fishing/mends_st_jetty"), "walking up finds the spot")
		_check(_fishing.spot_in_reach().get("id", "") == "mends_st_jetty", "standing at the spot (%s)" % _walker.global_position)
		_check(_fishing.prompt().contains("Fish here"), "the prompt offers to fish (%s)" % _fishing.prompt())
		_fishing.start(_spot)
		_check(_fishing.state == F_READY and _fishing._rod != null, "the rod comes out")
		_check(not _walker.is_physics_processing(), "the walker stands still while fishing")
		_fishing._yaw = float(_spot.yaw)
		_fishing._pitch = -0.25
	elif _frames == 280:
		_fishing._press()
	elif _frames > 280 and _fishing.state == F_CHARGING:
		if _fishing.power > 0.8:
			_fishing._release()
			_check(_fishing.state == F_WAITING, "a long cast lands in the water (%.0f m)" % _fishing.cast_distance)
			_check(absf(_fishing._float.global_position.y) < 0.2, "the float sits on the river (y %.2f)" % _fishing._float.global_position.y)
			_hook_next("black_bream")
	elif _fishing.state == F_WAITING and _tries == 0 and _fishing._nibbles > 0:
		if _frames % 20 == 0:
			_shot("08_fishing_wait")
	elif _fishing.state == F_BITE and _frames > 280:
		_fishing._press()
		_check(_fishing.state == F_FIGHT, "struck in time: fish on")
		if _tries == 0:
			# A legal bream for the esky.
			_fishing.fish_on.cm = 33.0
			_fishing.fish_on.kg = 0.65
			_fishing.fish_on.legal = true
	elif _fishing.state == F_FIGHT:
		if _tries == 0:
			# Play it: ease off when the tip shivers or it runs, reel when it's slack.
			if _fishing.warning or _fishing.surging or _fishing.tension > 0.8:
				_fishing._reeling = false
			elif _fishing.tension < 0.45:
				_fishing._reeling = true
		else:
			_fishing._reeling = true  # hauling on a mulloway: it'll snap
		if _fishing.tension > 0.5 and _frames % 97 == 0:
			_shot("08_fishing_fight")
	elif _fishing.state == F_LANDED and _tries == 0:
		_tries = 1
		_check(_fj.is_caught("black_bream"), "the bream's in the journal")
		_check(_field.fishing_screen.card_open(), "the catch card is up")
		_check(_fishing.keep_blocked(_fishing.caught) == "", "a legal bream can be kept")
		_wait = _frames + 20
	elif _tries == 1 and _frames == _wait:
		_shot("09_fishing_catch")
		_fishing.choose("keep")
		_check(_fj.esky.size() == 1 and _fishing.state == F_READY, "the bream goes in the esky")
		# Now something too big for the old rod.
		_tries = 2
		_fishing.power = 1.0
		_fishing._cast()
		_hook_next("mulloway")
		_fishing._species = _fj.fish_species("mulloway")
	elif _tries == 2 and _lost.size() > 0:
		_check(_lost[-1] == "snapped", "hauling flat out on a mulloway snaps the line (%s)" % _lost[-1])
		_fishing._put_away()
		_check(_fishing.state == F_IDLE and _walker.is_physics_processing(), "the rod goes away")
		# The crab net.
		clock.set_time(20.5)
		_fj.has_crab_net = true
		_fishing.start(_spot)
		_check(_fj.crab_nets.has("mends_st_jetty"), "the crab net goes over the side")
		_fishing._put_away()
		_fj.crab_nets["mends_st_jetty"] = float(_fj.crab_nets["mends_st_jetty"]) - 200.0
		_check(_fishing.prompt().contains("crab net"), "the net's ready to pull (%s)" % _fishing.prompt())
		var esky_before: int = _fj.esky.size()
		var crabs: Array = _fishing.pull_crab_net(_spot)
		_check(crabs.size() >= 2 and _fj.is_caught("blue_swimmer_crab"), "blue mannas in the net (%d)" % crabs.size())
		_check(_fj.crab_nets.is_empty() and _fj.esky.size() >= esky_before, "the net's up, legal crabs kept (%d in the esky)" % _fj.esky.size())
		_next()
	elif _tries == 0 and not _lost.is_empty() and _fishing.state == F_READY:
		print("     (the bream got away: %s; casting again)" % _lost[-1])
		_lost.clear()
		_fishing.power = 1.0
		_fishing._cast()
		_hook_next("black_bream")
	elif _frames > 4000:
		_check(false, "fishing stalled (state %d, tries %d, lost %s)" % [_fishing.state, _tries, str(_lost)])
		_next()


## The lab's lens and film: a long lens makes a far bird a print, fast film
## takes the murk out of a night shot, and both are bought and saved.
func _check_lens_and_film(clock: Node) -> void:
	var wallet := root.get_node("Wallet")
	var was_target: Dictionary = _bino.target
	_bino.target = {"frame": 0.03}
	var bare: float = _bino.photo_frame()
	wallet.earn(2000)
	var money: int = wallet.balance
	_check(_fj.upgrade("lens") and _fj.lens == 1 and wallet.balance == money - int(_fj.LENSES[1].price), "a 200 mm zoom from the lab")
	_check(_bino.photo_frame() > bare * 1.5 and _bino.photo_frame() >= _bino.MIN_FRAME, "a far bird fills a photo with it (%.3f to %.3f)" % [bare, _bino.photo_frame()])
	_bino.target = was_target
	var hour: float = clock.time_of_day
	clock.set_time(23.0)
	var slow: float = _fj.murk()
	_check(slow > 0.5, "slow film can't cope at night (murk %.2f)" % slow)
	_check(_fj.upgrade("film") and _fj.upgrade("film") and _fj.film == 2 and _fj.murk() < 0.05, "ISO 3200 shoots at midnight (murk %.2f)" % _fj.murk())
	clock.set_time(12.0)
	_check(_fj.murk() < 0.05, "and by day there's no murk")
	clock.set_time(hour)
	var copy: Dictionary = JSON.parse_string(JSON.stringify(_fj.save_state()))
	_fj.lens = 0
	_fj.film = 0
	_fj.load_state(copy)
	_check(_fj.lens == 1 and _fj.film == 2, "the lens and film survive a save and load")
	_fj.lens = 0
	_fj.film = 0


## The glowing flathead: Point Fraser in the small hours, once the atlas page
## is found; it glows, and it goes back.
func _check_wrong_flathead(disc: Node) -> void:
	var point: Dictionary = _fj.spot("point_fraser")
	_check(not point.is_empty(), "Point Fraser is a spot")
	var had: bool = disc.has("mystery/atlas_page")
	disc._found.erase("mystery/atlas_page")
	_check(not _ids(_fj.fish_candidates(point, 2.0)).has("wrong_flathead"), "no glowing flathead before the atlas page")
	disc._found["mystery/atlas_page"] = 1
	_check(_ids(_fj.fish_candidates(point, 2.0)).has("wrong_flathead"), "a glowing flathead at Point Fraser at 2 a.m.")
	_check(not _ids(_fj.fish_candidates(point, 5.0)).has("wrong_flathead"), "but not once it's getting light")
	_check(not _ids(_fj.fish_candidates(_spot, 2.0)).has("wrong_flathead"), "and only at Point Fraser")
	var f: Dictionary = _fj.fish_species("wrong_flathead")
	var model: Node3D = load("res://scripts/field/fish_models.gd").build(f)
	_check(model.find_child("Glow", true, false) is OmniLight3D, "it glows")
	model.free()
	_check(_fishing.keep_blocked(_fj.fish_size(f, RandomNumberGenerator.new())) != "", "it can't be kept")
	if not had:
		disc._found.erase("mystery/atlas_page")


## The kept hubcap goes up on the shed door at home.
func _check_hubcap(disc: Node) -> void:
	var trophies: Node = _field.trophies
	var kept := "fishing/fiat_hubcap"
	var door := get_root_home_door()
	if door == null:
		print("     (no shed door in this map; skipping the hubcap)")
		return
	var had: bool = disc.has(kept)
	disc._found.erase(kept)
	trophies._update_hubcap()
	_check(trophies.hubcap() == null, "no hubcap on the shed door until you keep one")
	disc._found[kept] = 1
	trophies._update_hubcap()
	var cap: Node3D = trophies.hubcap()
	_check(cap != null and cap.get_parent() == door, "the kept hubcap hangs on the shed door")
	if cap:
		var out := door.global_basis * Vector3(0, 0, -1)
		var face: Vector3 = cap.global_basis.y.normalized()
		_check(face.dot(out.normalized()) > 0.95, "chrome side out (%.2f)" % face.dot(out.normalized()))
	if not had:
		disc._found.erase(kept)
		if cap:
			cap.free()


func get_root_home_door() -> Node3D:
	var home := get_first_node_in_group(&"home_base") as Node3D
	return home.find_child("Shed_Door", true, false) as Node3D if home else null


var _shop_cam: Camera3D
var _cam_before: Camera3D


## Look at a shop's front from across the road (null puts the camera back).
func _view_shop(bay: Node3D) -> void:
	if bay == null:
		if is_instance_valid(_shop_cam):
			_shop_cam.queue_free()
		if is_instance_valid(_cam_before):
			_cam_before.current = true
		return
	var front := bay.get_node_or_null(^"Shopfront") as Node3D
	_check(front != null, "the %s has its shopfront" % bay.name)
	if front == null:
		return
	_cam_before = _car.get_viewport().get_camera_3d()
	_shop_cam = Camera3D.new()
	_shop_cam.fov = 60.0
	_car.get_parent().add_child(_shop_cam)
	_hide_help()
	# Across the road and off to one side, so a car in the bay doesn't hide it.
	var at := front.global_position + front.global_basis.z * 16.0 + front.global_basis.x * 7.0 + Vector3.UP * 3.5
	_shop_cam.look_at_from_position(at, front.global_position + Vector3.UP * 2.2)
	_shop_cam.current = true


## The driving help overlay gets in the way of the shots.
func _hide_help() -> void:
	var hud := get_first_node_in_group(&"hud")
	if hud == null or _shots == "":
		return
	hud.hide_help()


## Make sure `id` is what bites next, straight away.
func _hook_next(id: String) -> void:
	_fishing._species = _fj.fish_species(id)
	_fishing._wait = 0.5
	_fishing._nibbles = 1


func _ids(list: Array) -> Array:
	return list.map(func(b: Dictionary) -> String: return b.id)


## A sighting of `id` somewhere about `dist` m from `at`, trying a few directions.
func _spawn_near(id: String, h: Dictionary, at: Vector3, dist: float) -> Dictionary:
	for i in 12:
		var a := TAU * i / 12.0
		var s: Dictionary = _birds.spawn(_fj.bird(id), h, at + Vector3(cos(a), 0, sin(a)) * dist)
		if s.is_empty():
			continue
		# Somewhere you can actually see it from the car.
		var eye := _car.global_position + Vector3.UP * 1.2
		var q := PhysicsRayQueryParameters3D.create(eye, s.birds[0].node.global_position + Vector3.UP * 0.2, 1 | 2)
		q.exclude = [_car.get_rid()]
		if _car.get_world_3d().direct_space_state.intersect_ray(q).is_empty() or s.birds[0].kind == "air":
			return s
		_birds._remove(s)
	return {}


## Frozen cars keep adding up their script forces and leap when let go, so
## the car's own processing is off while it's held.
func _teleport(p: Vector3, yaw: float) -> void:
	_car.freeze = true
	_car.set_physics_process(false)
	_car.global_transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 0.8)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO


## Quiet places: hidden until you walk into one, then in the journal, with
## birds you won't see anywhere else.
func _check_quiet_places(disc: Node) -> void:
	var quiet: Array = _fj.quiet_places()
	_check(quiet.size() == 9 and quiet.all(func(h: Dictionary) -> bool: return not disc.has(_fj.place_key(h))), "nine quiet places, none found yet (%d)" % quiet.size())
	var reeds: Dictionary = _fj.habitat("quiet_herdsman_reedbeds")
	var at: Vector3 = _fj.habitat_centre(reeds)
	_check(_fj.place_name(at) != reeds.name, "an unfound quiet place has no name (%s)" % _fj.place_name(at))
	_check(_ids(_fj.candidates(reeds, 7.0, 0.0)).has("australian_reed_warbler")
		and not _ids(_fj.candidates(_fj.habitat("herdsman_lake"), 7.0, 0.0)).has("australian_reed_warbler"), "reed warblers only in the quiet reedbeds")
	_check(_field.quiet.find_near(at + Vector3(80, 0, 0)).is_empty(), "walking past doesn't find it")
	var found: Array = _field.quiet.find_near(at + Vector3(30, 0, 0))
	_check(found.size() == 1 and found[0] == "Herdsman Lake reedbeds", "walking in finds it (%s)" % str(found))
	_check(disc.has("places/birding_herdsman_reedbeds") and _fj.place_name(at) == reeds.name, "it's named once found (%s)" % _fj.place_name(at))
	_field.journal._tab = "birds"
	_field.journal._selected = "place:quiet_herdsman_reedbeds"
	_field.journal.refresh()
	var listed: bool = _field.journal._list.get_children().any(func(n: Node) -> bool: return n is Button and (n as Button).text == "Herdsman Lake reedbeds")
	_check(listed and _fj.places_found() == 1, "the journal lists it under quiet places")
	_field.journal._tab = "fish"
	_field.journal._selected = ""
	_field.journal.refresh()
	var sandbar: bool = _field.journal._list.get_children().any(func(n: Node) -> bool: return n is Button and (n as Button).text == "Point Walter sandbar")
	_check(_fj.spot("point_walter_sandbar").get("hidden", false) and not sandbar, "a quiet fishing spot isn't even a blank until found")
	_field.journal._tab = "birds"
	_field.journal._selected = ""
	disc._found.erase("places/birding_herdsman_reedbeds")


## The first of a flock the binoculars have a clear line to (else the first).
func _visible_bird(s: Dictionary) -> Node3D:
	var size := float(s.species.get("size", 0.3))
	for b: Dictionary in s.birds:
		var n: Node3D = b.node
		if is_instance_valid(n) and _bino._camera and _bino._clear_line(_bino._camera.global_position, n.global_position + Vector3.UP * size * 0.8):
			return n
	return s.birds[0].node


func _aim(node: Node3D) -> void:
	if not is_instance_valid(node) or _bino._camera == null:
		return
	var to: Vector3 = node.global_position + Vector3.UP * 0.15 - _bino._camera.global_position
	_bino._yaw = atan2(-to.x, -to.z)
	_bino._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	_bino._camera.fov = 9.0


func _next() -> void:
	_stage += 1
	_frames = 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failures.append(what)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png(_shots.path_join(name + ".png"))


## The shop is a room you can walk into: clear of the map's buildings, a
## floor to stand on, the counter reachable on foot, the weigh-in on the scale
## and your catches on the brag board.
func _check_walk_in(shop: Node3D, result: Dictionary) -> void:
	var room: Node3D = shop.get_node_or_null("Shopfront")
	_check(room != null, "the tackle shop has its room")
	if room == null:
		return
	var space := _car.get_world_3d().direct_space_state
	var door := room.to_global(Vector3(-0.5, 1.2, 0.6))
	var q := PhysicsRayQueryParameters3D.create(door, room.to_global(Vector3(-0.5, 1.2, -6.6)), 2)
	var wall := space.intersect_ray(q)
	_check(wall.is_empty(), "no map building inside the shop (%s)" % wall.get("collider"))
	q = PhysicsRayQueryParameters3D.create(room.to_global(Vector3(-1.0, 1.0, -2.0)), room.to_global(Vector3(-1.0, -1.0, -2.0)), 1)
	var floor_hit := space.intersect_ray(q)
	_check(not floor_hit.is_empty() and absf(floor_hit.position.y - room.global_position.y) < 0.3, "a floor to stand on inside the shop")
	var counter: Node3D = room.find_child("Counter", true, false)
	_check(shop.at_counter(room.to_global(room.to_local(counter.global_position) + Vector3(-0.9, 0.1, 0.6))), "on foot at the counter is in reach")
	_check(not shop.at_counter(shop.global_position), "the bay isn't the counter on foot")
	var inside := room.to_global(Vector3(0.0, 1.5, -3.5))
	_check(shop.rain_shelters().any(func(box: Transform3D) -> bool:
		var b := box.affine_inverse() * inside
		return absf(b.x) <= 1.0 and absf(b.y) <= 1.0 and absf(b.z) <= 1.0), "no rain inside the shop")
	var heaviest := 0.0
	for f: Dictionary in result.fish:
		heaviest = maxf(heaviest, float(f.kg))
	var on_scale: Node3D = shop.on_scale()
	_check(on_scale != null and on_scale.scale.x > 0.05, "the weigh-in's best fish lies on the scale (%.2f kg)" % heaviest)
	var best: Array = shop.brag_list()
	var cards: Node = room.find_child("Cards", true, false)
	_check(not best.is_empty() and cards != null and cards.get_child_count() == best.size(), "your biggest catches are on the brag board (%d)" % best.size())


func _finish() -> bool:
	print("FIELD ", "PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size())
	for f in _failures:
		print("  - " + f)
	_quitting = true
	root.get_node("SaveGame").quit_cleanly(1 if _failures.size() else 0)
	return false
