class_name TrainRace
extends Node
## Racing the trains: run alongside a Transperth train and get your nose past
## the front carriage before it pulls away. Nobody sets it up; it starts
## whenever you're driving beside a moving train in the same direction.
## Listens to the traffic manager's train_spawned / train_despawned.

## How close (m) to the line counts as alongside.
const ALONGSIDE := 45.0
## The train must be doing at least this (m/s) for it to count as a race.
const MIN_TRAIN_SPEED := 9.0
## Get this far (m) past the front carriage to win.
const WIN_LEAD := 12.0
## Lose when the front carriage is this far (m) ahead of you, or you drift off.
const LOSE_GAP := 90.0

var _trains: Array[Node3D] = []
var _last := {}  # train -> middle of the train at the last check
var _racing: Node3D
var _alongside: AudioStreamPlayer3D
var _car: CarController
var _check := 0.0


var _lead := 0.0  # metres your nose is past the front carriage (negative: behind)


func _ready() -> void:
	add_to_group(&"challenges")
	_connect.call_deferred()


## For the challenge card (top right) while you're racing a train.
func challenge_card() -> Dictionary:
	if _racing == null or not is_instance_valid(_racing):
		return {}
	var gap := "%d m behind the front" % roundi(-_lead) if _lead < 0.0 else "%d m ahead. Keep going!" % roundi(_lead)
	return {"tag": "Train race", "icon": "flag", "title": "Transperth",
		"line": "Get your nose %d m past the front carriage." % roundi(WIN_LEAD), "detail": gap}


func _connect() -> void:
	var traffic := get_tree().get_first_node_in_group(&"traffic")
	if traffic == null or not traffic.has_signal(&"train_spawned"):
		return
	traffic.train_spawned.connect(func(train: Node3D) -> void:
		if not _trains.has(train):
			_trains.append(train))
	traffic.train_despawned.connect(func(train: Node3D) -> void:
		_trains.erase(train)
		_last.erase(train)
		if train == _racing:
			_racing = null
			_stop_sound())


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	var step := 0.25 - _check
	_check = 0.25
	if _car == null or not is_instance_valid(_car):
		_car = get_tree().get_first_node_in_group(&"player_car") as CarController
		return
	for train in _trains:
		if not is_instance_valid(train) or not train.visible or train.get_child_count() == 0:
			continue
		var positions: Array[Vector3] = []
		var centre := Vector3.ZERO
		for carriage in train.get_children():
			if carriage is Node3D:
				positions.append((carriage as Node3D).global_position)
				centre += positions[-1]
		if positions.is_empty():
			continue
		centre /= positions.size()
		var velocity := Vector3.ZERO
		if _last.has(train):
			velocity = (centre - _last[train]) / step
		_last[train] = centre
		# The front carriage is the one furthest along the direction of travel.
		var front := positions[0]
		for p in positions:
			if (p - front).dot(velocity) > 0.0:
				front = p
		_judge(train, front, velocity)


func _judge(train: Node3D, front: Vector3, velocity: Vector3) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	var dir := flat / speed if speed > 0.01 else Vector3.ZERO
	var to_car := _car.global_position - front
	var along := to_car.dot(dir)
	var side := (to_car - dir * along)
	side.y = 0.0
	var car_vel := Vector3(_car.linear_velocity.x, 0.0, _car.linear_velocity.z)
	var parallel := car_vel.length() > 5.0 and dir != Vector3.ZERO and car_vel.normalized().dot(dir) > 0.8
	if _racing == null:
		# Start when you're beside or just behind the train, matching it.
		if speed > MIN_TRAIN_SPEED and parallel and side.length() < ALONGSIDE and along < 0.0 and along > -60.0:
			_racing = train
			_lead = along
			_start_sound(train)
			if _alongside:
				_alongside.global_position = front
			Progression.add_stat("trains_raced")
		return
	if train != _racing:
		return
	_lead = along
	if _alongside and is_instance_valid(_alongside):
		_alongside.global_position = front
		_alongside.pitch_scale = clampf(speed * 3.6 / 100.0, 0.3, 2.0)
	if along > WIN_LEAD and side.length() < ALONGSIDE * 1.5:
		_racing = null
		Progression.add_stat("trains_beaten")
		_stop_sound()
		Notices.post("Your nose got past the front carriage.", "medal", "music/mus_sting_race_win", "You beat the train")
	elif along < -LOSE_GAP or side.length() > ALONGSIDE * 2.0 or speed < 2.0:
		_racing = null
		_stop_sound()
		Notices.post("It got away." if speed >= 2.0 else "It's stopping. Call it a draw.", "result", "-", "Train race")


## The train's roar while you race it (plays nothing until the audio thread
## adds traffic/traffic_train_alongside_loop). Pitch follows its speed.
func _start_sound(_train: Node3D) -> void:
	_stop_sound()
	var audio := get_node_or_null("/root/Audio")
	if audio == null or not audio.has("traffic/traffic_train_alongside_loop"):
		return
	_alongside = AudioStreamPlayer3D.new()
	_alongside.bus = &"SFX"
	_alongside.unit_size = 25.0
	_alongside.stream = audio.stream("traffic/traffic_train_alongside_loop", true)
	_alongside.autoplay = true
	# Ours, not the train's: traffic treats the train's children as carriages.
	add_child(_alongside)


func _stop_sound() -> void:
	if _alongside and is_instance_valid(_alongside):
		_alongside.queue_free()
	_alongside = null
