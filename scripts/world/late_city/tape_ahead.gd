class_name TapeAhead
extends Node
## The tapes run ahead (STORY.md, act 4): late at night there's a cassette in
## the car's deck you didn't put there, and Mick describes a drive you haven't
## done yet: where he picked up, what, where he took it, and a ginger cat on
## the fence at the end. Next morning that exact job is on the board with a
## reel by it. Take it and it goes as he said, down to the cat.
##
##   - the tape: getting into the car between 10 pm and 4 am, from act 4, at
##     most once every EVERY_DAYS days, when no tape job is waiting
##   - the job: offered from 6 am the morning after, top of the board, until
##     it's taken or two days have gone
##   - the cat: on a bit of paling fence by the drop-off once you're close
##
## Added by GameplayPlaces. Saved under "tape_ahead".

const FROM_ACT := 4
const EVERY_DAYS := 4
const TAPE_FROM := 22.0
const TAPE_TO := 4.0
const OFFER_FROM := 6.0
const KEEP_DAYS := 2
const STORY := "tape_ahead"
## The cat turns up once you're this close to the drop-off (m).
const CAT_NEAR := 140.0
const CAT_MODEL := "res://art/models/props/home/cat.glb"
const PALING := Color(0.46, 0.38, 0.28)

## Tests: ignore the act, the hour and the gap.
var force := false
var last_day := -100
## The job he described, waiting to be offered ({} for none), and the day
## (from OFFER_FROM) it goes on the board.
var pending: Dictionary = {}
var due_day := 0
var told := 0

var _was_in_car := true
var _cat: Node3D
var _check := 0.0


func _ready() -> void:
	name = "TapeAhead"
	SaveGame.register("tape_ahead", self)
	Jobs.job_completed.connect(_on_done)
	Jobs.job_abandoned.connect(func(job: Dictionary) -> void:
		if job.get("story", "") == STORY:
			_clear_cat())


func _exit_tree() -> void:
	SaveGame.unregister("tape_ahead")


func _process(delta: float) -> void:
	if get_tree().paused or SaveGame.hold or TitleScreen.is_showing(get_tree()):
		return
	var player := get_tree().get_first_node_in_group(&"player_on_foot")
	var in_car: bool = player != null and player.get("in_car") == true
	if in_car and not _was_in_car:
		maybe_play()
	_was_in_car = in_car
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	_offer()
	_watch_job()


## The tape in the deck, if it's time (also called by tests).
func maybe_play() -> bool:
	if not pending.is_empty() or Jobs.active.get("story", "") == STORY:
		return false
	if not force:
		var h := GameClock.time_of_day
		if Story.act() < FROM_ACT or not (h >= TAPE_FROM or h < TAPE_TO) or GameClock.day < last_day + EVERY_DAYS:
			return false
	var job := make_job()
	if job.is_empty():
		return false
	last_day = GameClock.day
	pending = job
	# The morning after: today's if it's past midnight, else tomorrow's.
	due_day = GameClock.day if GameClock.time_of_day < OFFER_FROM else GameClock.day + 1
	told += 1
	LateCity._play_2d(LateCity.SOUND_START, -6.0)
	Notices.post("There's a cassette in the deck you didn't put there. NIGHT DRIVE, no number.", "odd")
	Notices.post(tape_text(job, due_day), "odd", "-", "NIGHT DRIVE")
	Story.log_night(StringName("tape_ahead_%d" % GameClock.day),
		"A tape in the deck I never put there. Mick, describing a drive: %s to %s. I haven't done that one." % [
			_place(job.pickup), _place(job.dropoff)])
	Discoveries.discover("oddity/tape_ahead")
	return true


## A delivery like any on the board, marked as his.
func make_job() -> Dictionary:
	var job: Dictionary = Jobs._make_delivery(Jobs.sites())
	if job.is_empty():
		return {}
	job.id = 95000 + GameClock.day
	job.story = STORY
	job.icon = "reel"
	return job


## What Mick says on the tape about `job`.
static func tape_text(job: Dictionary, day: int) -> String:
	var weekday: String = Garage.WEEKDAYS[posmod(day - 1, 7)]  # day 1 is a Monday
	return "\"%s. Picked up %s at %s, out to %s. There was a ginger cat on the fence when I got there, watching me the whole time. Paid in cash. Home before the light.\"" % [
		weekday, String(job.cargo), _place(job.pickup), _place(job.dropoff)]


static func _place(id: String) -> String:
	var site := Jobs.site(id)
	return site.label() if site else id


func _offer() -> void:
	if pending.is_empty():
		return
	if GameClock.day > due_day + KEEP_DAYS:
		pending = {}
		return
	if GameClock.day < due_day or (GameClock.day == due_day and GameClock.time_of_day < OFFER_FROM):
		return
	if Jobs.active.get("id", -1) == pending.id:
		pending = {}  # taken
		return
	for job: Dictionary in Jobs.offers:
		if job.get("story", "") == STORY:
			return
	Jobs.offers.push_front(pending)
	Jobs.offers_changed.emit()


## On the way to the drop-off, the cat's there waiting.
func _watch_job() -> void:
	var job: Dictionary = Jobs.active
	if job.get("story", "") != STORY or job.get("stage", "") != "to_dropoff":
		return
	if _cat:
		return
	var site := Jobs.site(String(job.dropoff))
	var car := get_tree().get_first_node_in_group(&"player_car") as Node3D
	if site == null or car == null or car.global_position.distance_to(site.global_position) > CAT_NEAR:
		return
	_cat = build_cat_fence(site)


## A short paling fence along the footpath by the drop-off, just past the
## kerb, with the ginger cat sitting on top looking at the road.
func build_cat_fence(site: Node3D) -> Node3D:
	var space := site.get_world_3d().direct_space_state
	var base := site.global_position
	var across := site.global_basis.x
	across.y = 0.0
	across = across.normalized() if across.length() > 0.1 else Vector3.RIGHT
	var at := base + across * 6.0
	var out := across
	var found := false
	for side: float in [1.0, -1.0]:
		var was_path := false
		var d := 1.0
		while d < 18.0 and not found:
			var p := base + across * side * d
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 6.0))
			var kind := String((hit.get("collider") as Node).name) if not hit.is_empty() else ""
			if kind.begins_with("roads_sidewalk"):
				was_path = true
			elif was_path and kind.begins_with("ground"):
				at = (hit.position as Vector3) + across * side * 0.4
				out = across * side
				found = true
			elif kind.begins_with("buildings"):
				break
			d += 0.5
		if found:
			break
	if not found:
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 6.0, at + Vector3.DOWN * 6.0))
		if not down.is_empty():
			at.y = (down.position as Vector3).y
	var root := Node3D.new()
	root.name = "TapeAheadCat"
	add_child(root)
	# x along the road, z toward it.
	var toward := -out
	root.global_transform = Transform3D(Basis(Vector3.UP.cross(toward).normalized(), Vector3.UP, toward), at)
	for i in 9:
		var paling := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.13, 1.2 + (0.05 if i % 2 == 0 else 0.0), 0.025)
		paling.mesh = box
		paling.material_override = PS1Material.make(PALING.darkened(0.08 * (i % 3)))
		paling.position = Vector3(-0.72 + i * 0.18, 0.6, 0.0)
		root.add_child(paling)
	for y: float in [0.3, 0.95]:
		var rail := MeshInstance3D.new()
		var r := BoxMesh.new()
		r.size = Vector3(1.7, 0.07, 0.04)
		rail.mesh = r
		rail.material_override = PS1Material.make(PALING.darkened(0.2))
		rail.position = Vector3(0, y, -0.035)
		root.add_child(rail)
	var scene := load(CAT_MODEL) as PackedScene if ResourceLoader.exists(CAT_MODEL) else null
	if scene:
		var cat := scene.instantiate() as Node3D
		cat.name = "Cat"
		cat.position = Vector3(0.1, 1.25, 0.0)
		root.add_child(cat)
	return root


func _on_done(job: Dictionary, _pay: int, _summary: String) -> void:
	if job.get("story", "") != STORY:
		return
	_clear_cat()
	pending = {}
	Notices.post("It went exactly the way he said. The cat watched you all the way back to the car.", "odd")
	Story.log_night(StringName("tape_ahead_done_%d" % GameClock.day),
		"Did the drive from the tape. %s to %s, the ginger cat on the fence. Exactly as he said." % [
			_place(job.pickup), _place(job.dropoff)])


func _clear_cat() -> void:
	if _cat:
		_cat.queue_free()
		_cat = null


func save_state() -> Dictionary:
	return {"last_day": last_day, "pending": pending, "due_day": due_day, "told": told}


func load_state(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -100))
	pending = data.get("pending", {}) as Dictionary
	due_day = int(data.get("due_day", 0))
	told = int(data.get("told", 0))
