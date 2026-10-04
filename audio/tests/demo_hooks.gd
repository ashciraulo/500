extends SceneTree
## A ~40 second tour of the game-event sounds, for hearing them in the real
## game and recording with Godot's movie maker:
##
##   godot --path . --fixed-fps 60 --write-movie build/hooks.avi --script res://audio/tests/demo_hooks.gd
##
## Fuel at the servo, fitting a sport exhaust (the engine changes), a delivery
## with cargo sliding about and the tension music coming in as time runs
## short, a time trial start, its medal countdown and finish, then the car
## wash and the pause menu.

var _main: Node
var _car: Node
var _t := 0.0
var _done := {}


func _process(delta: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		root.get_node("GameClock").set_time(10.0)
		root.get_node("GameClock").set_locked(true)
		root.get_node("Weather").set_state(0, true)
		root.get_node("Weather").set_locked(true)
		root.get_node("Wallet").earn(5000)
		return false
	_t += delta
	var jobs: Node = root.get_node("Jobs")
	var hooks: Node = root.get_node("Audio").hooks
	_at(0.1, func() -> void:
		var hud := _main.get_node_or_null("HUD")
		if hud and hud.get("_help"):
			hud._help.visible = false)
	_at(3.0, func() -> void:
		print("fuel")
		_car.fuel_litres = 8.0)
	_at(3.5, func() -> void: root.get_node("Garage").buy_fuel(_car))
	_at(8.0, func() -> void:
		print("sport exhaust")
		_car.install_part(load("res://data/parts/exhaust_sport.tres")))
	_at(10.0, func() -> void: Input.action_press("accelerate"))
	_at(12.5, func() -> void: Input.action_release("accelerate"))
	# A delivery that's running late: fake the job so the beats land on time.
	_at(14.0, func() -> void:
		print("delivery")
		jobs.active = {"id": 99, "type": "delivery", "stage": "to_pickup", "cargo": "a ceramic lamp",
				"fragile": true, "par_seconds": 10.0, "elapsed": 0.0, "damage": 0.0, "pay": 80, "title": "Delivery",
				"pickup": "demo_a", "dropoff": "demo_b", "km": 2.0}
		jobs.job_started.emit(jobs.active))
	_at(15.5, func() -> void:
		jobs.active.stage = "to_dropoff"
		jobs.active.elapsed = 6.0
		jobs.job_stage_changed.emit(jobs.active))
	_at(17.0, func() -> void: _car.impact.emit(4.0))
	_at(18.5, func() -> void: _car.impact.emit(3.0))
	_at(21.5, func() -> void:
		var job: Dictionary = jobs.active
		jobs.active = {}
		jobs.job_completed.emit(job, 80, "Delivered."))
	_at(25.0, func() -> void:
		print("time trial")
		jobs.active = {"id": 100, "type": "trial", "trial_id": "demo", "stage": "racing", "checkpoint": 1,
				"elapsed": 0.0, "medal_times": {"gold": 6.0, "silver": 9.0, "bronze": 12.0},
				"title": "Demo trial", "route": ["demo_a", "demo_b", "demo_c", "demo_d"], "km": 3.0}
		jobs.job_stage_changed.emit(jobs.active))
	_at(27.0, func() -> void:
		jobs.active.checkpoint = 2
		jobs.job_stage_changed.emit(jobs.active))
	_at(32.5, func() -> void:
		var job: Dictionary = jobs.active
		job.elapsed = 7.5
		jobs.active = {}
		jobs.trial_records["demo"] = {"best": 7.5, "medal": "silver"}
		jobs.job_completed.emit(job, 120, "Silver."))
	_at(36.0, func() -> void:
		print("car wash")
		_car.dirt = 0.6)
	_at(36.5, func() -> void: root.get_node("Garage").wash(_car))
	_at(41.0, func() -> void: _main.get_node("PauseMenu").open())
	_at(43.0, func() -> void:
		root.get_viewport().get_texture().get_image().save_png("res://build/pause_menu.png"))
	_at(44.0, func() -> void:
		_main.get_node("PauseMenu").close()
		quit(0))
	if hooks == null:
		quit(1)
	return false


func _at(time: float, action: Callable) -> void:
	if _t >= time and not _done.has(time):
		_done[time] = true
		action.call()
