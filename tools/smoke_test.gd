extends SceneTree
## Headless smoke test: loads the main scene and drives the car through a few
## scripted checks. Run it with a fixed frame rate so physics is deterministic:
##
##   godot --headless --path . --fixed-fps 120 --script res://tools/smoke_test.gd -- --no-save
##
## Exits with code 1 if any check fails. CI runs this on every push.

const FPS := 120

var _main: Node
var _car: RigidBody3D  # CarController (untyped so this compiles before autoloads exist)
var _failures: Array[String] = []
var _step := 0
var _frame := 0
var _mark := {}


func _process(_delta: float) -> bool:
	# The scene is loaded on the first frame, once the autoloads exist.
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_car = _main.get_node("LoFi/SubViewport/World/Car")
		var clock := root.get_node("GameClock")
		clock.set_time(12.0)
		clock.set_locked(true)
		root.get_node("Weather").set_locked(true)
		return false
	_frame += 1
	return _run_step()


## Each step returns true when it's finished; the whole test returns true to quit.
func _run_step() -> bool:
	match _step:
		0:  # Settle on the suspension.
			if _seconds() >= 2.0:
				_check(_car.global_position.y > 0.3 and _car.global_position.y < 0.7,
					"car rests on its wheels (y=%.2f)" % _car.global_position.y)
				_check(_car.global_basis.y.dot(Vector3.UP) > 0.98, "car sits level")
				_check(_car.grounded_wheels == 4, "all four wheels touch the ground")
				_check(_car.linear_velocity.length() < 0.2, "car is at rest (%.2f m/s)" % _car.linear_velocity.length())
				_next()
		1:  # Manual gearbox, first gear, full throttle.
			_car.transmission = 0  # MANUAL
			Input.action_press("accelerate")
			if _seconds() >= 2.5:
				_check(_car.gear == 1, "still in first without shifting")
				_check(_car.rpm > 4000.0, "revs climb in first (%d rpm)" % _car.rpm)
				_check(_car.speed_kmh() > 20.0, "car pulls away in first (%.0f km/h)" % _car.speed_kmh())
				_car.shift_up()
				_next()
		2:  # Shift to second.
			if _seconds() >= 1.0:
				_check(_car.gear == 2, "manual upshift to second (gear=%d)" % _car.gear)
				_car.set_transmission(1)  # AUTOMATIC
				_next()
		3:  # Automatic takes over and keeps accelerating.
			if _seconds() >= 14.0:
				_check(_car.gear >= 4, "automatic upshifts (gear=%d)" % _car.gear)
				_check(_car.speed_kmh() > 100.0, "reaches highway speed (%.0f km/h)" % _car.speed_kmh())
				_check(_car.speed_kmh() < 175.0, "top speed is sane (%.0f km/h)" % _car.speed_kmh())
				_check(_car.global_basis.y.dot(Vector3.UP) > 0.95, "still upright at speed")
				_mark.yaw = _car.global_rotation.y
				Input.action_release("accelerate")
				Input.action_press("brake")
				_next()
		4:  # Braking from speed.
			if _car.speed_kmh() < 2.0 or _seconds() >= 10.0:
				_check(_car.speed_kmh() < 2.0, "brakes stop the car (%.0f km/h after %.1fs)" % [_car.speed_kmh(), _seconds()])
				_check(absf(angle_difference(_mark.yaw, _car.global_rotation.y)) < 0.35, "car brakes in a straight line")
				_next()
		5:  # Keep holding brake at a standstill: automatic goes into reverse.
			if _seconds() >= 3.0:
				_check(_car.gear == -1, "automatic engages reverse (gear=%d)" % _car.gear)
				_check(_car.forward_speed < -1.0, "car reverses (%.1f m/s)" % _car.forward_speed)
				_check(_car.speed_kmh() < 30.0, "reverse speed is limited (%.0f km/h)" % _car.speed_kmh())
				Input.action_release("brake")
				_next()
		6:  # Throttle while reversing: automatic brakes, then goes back into first.
			Input.action_press("accelerate")
			if _car.gear == 1 and _car.forward_speed > 0.5:
				_mark.yaw = _car.global_rotation.y
				Input.action_press("accelerate", 0.7)
				Input.action_press("steer_left")
				_next()
			elif _seconds() >= 8.0:
				_check(false, "automatic leaves reverse when the throttle is pressed (gear=%d)" % _car.gear)
				_next()
		7:
			# Accumulate per frame: at full lock the car can go round more than once.
			_mark.turned = _mark.get("turned", 0.0) + angle_difference(_mark.yaw, _car.global_rotation.y)
			_mark.yaw = _car.global_rotation.y
			if _seconds() >= 5.0:
				var turned: float = _mark.turned
				_check(turned > 1.0, "steering left turns the car left (%.2f rad)" % turned)
				_check(_car.global_basis.y.dot(Vector3.UP) > 0.9, "no rollover while turning")
				Input.action_release("accelerate")
				Input.action_release("steer_left")
				_next()
		8:  # Weather and clock respond.
			var weather := root.get_node("Weather")
			weather.set_state(2, true)
			root.get_node("GameClock").set_time(23.0)
			_check(weather.intensity() > 0.9, "storm sets full rain intensity")
			_check(root.get_node("GameClock").is_night(), "23:00 is night")
			var settings := root.get_node("Settings")
			settings.weather_choice = 1  # Light rain, locked
			settings.automatic_gearbox = false
			settings.apply()
			_check(weather.state == 1 and weather.locked, "settings lock the chosen weather")
			_check(_car.transmission == 0, "settings switch the gearbox to manual")
			settings.weather_choice = -1
			settings.apply()
			_check(not weather.locked, "natural weather unlocks it")
			var stock: Dictionary = _car.get_stats()
			_check(absf(stock.power_kw - 51.0) < 4.0, "stock Pop makes about 51 kW (%.1f)" % stock.power_kw)
			var catalogue := load("res://scripts/vehicle/parts_catalogue.gd")
			_check(catalogue.all().size() >= 30, "parts catalogue loads (%d parts)" % catalogue.all().size())
			_car.install_part(catalogue.get_part(&"engine_tjet"))
			_car.install_part(catalogue.get_part(&"tyres_sport"))
			var tuned: Dictionary = _car.get_stats()
			_check(tuned.power_kw > stock.power_kw * 1.8, "turbo engine adds power (%.1f kW)" % tuned.power_kw)
			_check(tuned.grip > stock.grip, "sport tyres add grip")
			_check(Array(_car.get_part_ids()).has("engine_tjet"), "installed parts are listed for saving")
			_car.remove_part(&"engine")
			_car.install_part(catalogue.get_part(&"tyres_stock"))
			var back: Dictionary = _car.get_stats()
			_check(is_equal_approx(back.power_kw, stock.power_kw) and is_equal_approx(back.grip, stock.grip), "going back to stock restores the stock stats")
			# Save round trip, to a scratch file so a real save is never touched.
			var save := root.get_node("SaveGame")
			var wallet := root.get_node("Wallet")
			var clock := root.get_node("GameClock")
			var test_path := "user://smoke_test_save.json"
			wallet.earn(123)
			_car.install_part(catalogue.get_part(&"exhaust_sport"))
			var saved_money: int = wallet.balance
			var saved_pos: Vector3 = _car.global_position
			var saved_time: float = clock.time_of_day
			_check(save.save_to(test_path), "game saves")
			wallet.spend(100)
			clock.set_time(saved_time + 5.0)
			_car.remove_part(&"exhaust")
			_car.global_position += Vector3(50, 0, 50)
			_check(save.load_from(test_path), "game loads")
			_check(wallet.balance == saved_money, "money is restored (%d)" % wallet.balance)
			_check(is_equal_approx(clock.time_of_day, saved_time), "time of day is restored")
			_check(Array(_car.get_part_ids()).has("exhaust_sport"), "installed parts are restored")
			_check(_car.global_position.distance_to(saved_pos) < 1.0, "car position is restored")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
			var telemetry: Dictionary = _car.get_telemetry()
			for key in ["rpm", "throttle", "gear", "speed_kmh", "surface", "weather_intensity"]:
				_check(telemetry.has(key), "telemetry has '%s'" % key)
			_next()
		9:  # Job board: take a delivery and drive it (by teleporting).
			var jobs := root.get_node("Jobs")
			if _frame == 1:
				jobs.refresh_offers()
				_check(jobs.offers.size() >= 4, "job board has offers (%d)" % jobs.offers.size())
				var delivery: Dictionary = {}
				for job in jobs.offers:
					if job.type == "delivery":
						delivery = job
						break
				_check(not delivery.is_empty(), "a delivery is on offer")
				if delivery.is_empty():
					_next()
					return false
				_mark.money = root.get_node("Wallet").balance
				_mark.deliveries = root.get_node("Progression").get_stat("deliveries")
				jobs.accept(delivery)
				_teleport(jobs.target_site().global_position)
			elif _frame == 60:
				_check(jobs.active.get("stage", "") == "to_dropoff", "stopping at the pickup loads the cargo")
				_teleport(jobs.target_site().global_position)
			elif _frame == 120:
				_check(jobs.active.is_empty(), "stopping at the drop-off finishes the delivery")
				_check(root.get_node("Wallet").balance > _mark.money, "the delivery paid ($%d)" % (root.get_node("Wallet").balance - _mark.money))
				_check(root.get_node("Progression").get_stat("deliveries") == _mark.deliveries + 1, "the delivery counts towards challenges")
				_check(root.get_node("Discoveries").all().size() >= 2, "driving past places discovers them")
				_next()
		10:  # Time trial through every checkpoint.
			var jobs := root.get_node("Jobs")
			if _frame == 1:
				var trial: Dictionary = {}
				for job in jobs.offers:
					if job.type == "trial":
						trial = job
				_check(not trial.is_empty(), "a time trial is on offer")
				if trial.is_empty():
					_next()
					return false
				_mark.trial = trial.trial_id
				jobs.accept(trial)
			elif not jobs.active.is_empty() and _frame % 30 == 0:
				_teleport(jobs.target_site().global_position)
			elif jobs.active.is_empty() and _frame > 30:
				_check(jobs.trial_records.has(_mark.trial), "finishing a trial records a best time")
				_check(jobs.trial_records[_mark.trial].medal == "gold", "a teleporting car takes gold (of course)")
				_check(root.get_node("Progression").get_stat("trials_gold") == 1, "gold counts towards challenges")
				_next()
			elif _frame > 2000:
				_check(false, "time trial finished")
				_next()
		_:
			Input.action_release("accelerate")
			Input.action_release("brake")
			if _failures.is_empty():
				print("SMOKE TEST PASSED")
				quit(0)
			else:
				print("SMOKE TEST FAILED (%d):" % _failures.size())
				for failure in _failures:
					print("  - ", failure)
				quit(1)
			return true
	return false


func _teleport(pos: Vector3) -> void:
	_car.global_transform = Transform3D(_car.global_basis, pos + Vector3.UP * 0.5)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO


func _seconds() -> float:
	return float(_frame) / FPS


func _next() -> void:
	_step += 1
	_frame = 0
	print("  [t] step %d  pos=%s  %.0f km/h  gear=%d  rpm=%d" % [
		_step, _car.global_position.snapped(Vector3.ONE * 0.1), _car.speed_kmh(), _car.gear, _car.rpm])


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
