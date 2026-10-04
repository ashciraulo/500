# Hooks for other systems

The car, clock and weather expose read-only values and signals so audio, UI
and the map can react without reaching into their internals.

## Car (`CarController`, `scripts/vehicle/car_controller.gd`)

The player's car is in the `player_car` group:
`var car := get_tree().get_first_node_in_group(&"player_car") as CarController`.

`car.get_telemetry()` returns a Dictionary, refreshed every physics step:

| Key | Type | Meaning |
| --- | --- | --- |
| `rpm` | float | Engine speed. Idle ~850, redline 6200, limiter 6450. |
| `idle_rpm`, `redline_rpm` | float | For normalising rpm. |
| `throttle` | float 0..1 | Throttle reaching the engine (0 during shifts). |
| `brake` | float 0..1 | Brake pedal applied. |
| `clutch` | float 0..1 | 1 = engaged, 0 = in (shifting, neutral, or slipping at pull-away). |
| `engine_load` | float -1..1 | Engine torque as a share of peak; negative = engine braking. Great for the engine's tone. |
| `gear` | int | -1 reverse, 0 neutral, 1..5. |
| `automatic` | bool | Gearbox mode. |
| `is_shifting` | bool | True for the ~0.3 s the clutch is out. |
| `speed_kmh` | float | Road speed. |
| `forward_speed` | float m/s | Signed: negative when rolling backwards. |
| `tire_slip` | float 0..1 | Worst tyre slip. Skids, squeals, gravel spray. |
| `surface` | StringName | Surface under most wheels: asphalt, concrete, brick, gravel, dirt, grass, sand. |
| `grounded_wheels` | int 0..4 | 0 = airborne. |
| `handbrake` | float 0..1 | Handbrake lever. |
| `weather_intensity` | float 0..1 | Rain amount, copied from `Weather`. |
| `wetness` | float 0..1 | How wet the road is (lags behind rain). Tyre hiss on wet roads. |
| `is_player_inside` | bool | Camera is in the cabin: use the muffled interior mix. |

Signals:

- `gear_changed(gear: int)`: a shift finished (clunk).
- `transmission_changed(automatic: bool)`
- `impact(strength: float)`: the body hit something; strength is the change
  in speed in m/s.
- `surface_changed(surface: StringName)`
- `headlights_changed(on: bool)`

Attach car sounds to the car's `Audio` node (at the engine bay). The 3D
listener is the active camera inside `LoFi/SubViewport`
(`audio_listener_enable_3d` is on there).

The car's driver inputs (`throttle_input`, `brake_input`, `steer_input`,
`handbrake_input`) are plain vars; set `player_controlled = false` to drive
it from AI or a replay.

Physics layers: 1 = world (roads, ground), 2 = buildings, 3 = traffic (AI vehicles and trains). The car is on layer 1 and collides with all three (traffic adds layer 3 to its mask).

## Traffic

AI cars, buses, trains and people, and the road data format the map feeds
them, are documented in [TRAFFIC.md](TRAFFIC.md). Sound hooks: the
`TrafficManager` signals `horn`, `crossing_changed`, `pedestrian_startled`,
`vehicle_spawned` and `train_spawned`.

## Clock (autoload `GameClock`)

- `time_of_day` (0..24 hours), `day`, `locked`, `seconds_per_day` (2400 by default).
- `daylight()` 0 night .. 1 day, smooth through dawn/dusk. `is_night()`.
- `sun_direction()` unit vector towards the sun (Perth, early October).
- `time_string()` "HH:MM".
- Signals: `hour_changed(hour)`, `day_started(day)`, `lock_changed(locked)`.
- `set_time(hours)`, `advance(hours)`, `set_locked(bool)`.

## Weather (autoload `Weather`)

- `state`: `Weather.State.CLEAR`, `LIGHT_RAIN` or `STORM`. Read the smoothed
  values below for anything audible or visible, so changes fade in.
- `rain` / `intensity()` 0..1, `cloud_cover` 0..1, `wind` 0..1, `wetness` 0..1.
- Signals: `state_changed(state)`, `lock_changed(locked)`,
  `lightning(strength, distance_m)`: play thunder after `distance_m / 343` s.
- `set_state(state, instant := false)`, `cycle_state()` (also locks),
  `set_locked(bool)`.

## Render settings (autoload `RenderSettings`)

`lofi_enabled`, `target_height` (240), `vertex_snap_scale`, `affine_strength`,
`color_levels`, `dither_enabled`. Call `apply()` after changing them.
Shader globals: `ps1_snap_resolution`, `ps1_affine_strength`, `ps1_wetness`.

## Settings (autoload `Settings`)

Player choices from the pause menu, saved to `user://settings.cfg`:
`automatic_gearbox`, `mouse_sensitivity`, `day_length_minutes`,
`weather_choice` (-1 natural, else a `Weather.State`), `clock_frozen`,
`lofi_enabled`, `lofi_target_height`, `dither_enabled`, `vertex_snap_scale`,
`show_help`. Change values, then call `apply()`; `save_settings()` writes them.
The pause menu (`scripts/ui/pause_menu.gd`) pauses the tree, so anything that
should keep running while paused needs `process_mode = PROCESS_MODE_ALWAYS`.

## Parts and upgrades

Parts are data in `data/parts/<id>.tres` (`CarPart`, `scripts/vehicle/car_part.gd`).
Each has a `slot` (engine, intake, exhaust, gearbox, suspension, tyres, wheels,
brakes, weight), a `price` (AUD), stat `modifiers` (keys documented in
`car_part.gd`) and an optional `visual` model id (`exhaust_sport`,
`wheel_alloy15`, ...) for the car body to show. `PartsCatalogue` lists them:
`all()`, `for_slot(slot)`, `get_part(id)`.

On the car: `install_part(part)`, `remove_part(slot)`, `parts` (slot -> part),
`get_part_ids()` / `install_part_ids(ids)` for saving, and `get_stats()` for
headline numbers (power_kw, torque_nm, mass_kg, grip, ...). Parts always stack
from the stock values. Signal `parts_changed(slot, part)` fires on every change;
the car body uses `part.visual` to swap wheels and exhausts.

## Saving (autoload `SaveGame`)

Register anything that should persist, with a section name and two methods:

```gdscript
func _ready() -> void:
	SaveGame.register("my_system", self)

func save_state() -> Dictionary: return {"thing": thing}
func load_state(data: Dictionary) -> void: thing = data.get("thing", thing)
```

Saved data must be JSON-friendly (numbers, strings, bools, arrays,
dictionaries); use `SaveGame.vec3_to_array()` / `array_to_vec3()` for vectors.
Registering after the save was read applies your section immediately.
`save_game()`, `load_from(path)`, `has_save()`, `delete_save()`; signals
`saved(path)`, `loaded(path)`. Autosaves every 3 minutes of play and on quit.
Run the game with `-- --no-save` to skip saving and loading entirely.

Already saved: `clock` (time, day), `weather` (state, wetness), `car`
(position, heading, parts, tuning, paint, fuel, dirt, odometer), `wallet`, `discoveries`,
`progression` (stats, tier, suburbs), `garage` (your cars, their parts, and the
state of the cars you are not driving), `jobs` (offers, active job, trial
records).

## Money (autoload `Wallet`) and discoveries (autoload `Discoveries`)

- `Wallet.balance` (AUD, starts at 400), `earn(amount)`, `spend(amount) -> bool`,
  `can_afford(amount)`, `total_earned`, signal `changed(balance, delta)`.
- `Discoveries.discover(id) -> bool` (true the first time), `has(id)`, `all()`,
  signal `discovered(id)`. Ids are free-form, e.g. `"place/kings_park"`.

## Jobs (autoload `Jobs`) and career (autoload `Progression`)

- Job sites are `JobSite` markers (group `job_sites`) placed by the map. Each has
  `site_id`, `display_name`, `suburb` and `kinds`. The test grid places 11 of
  them; the real map should place markers with the same ids.
- `Jobs.offers`, `Jobs.active`, `accept(job)`, `abandon()`, `target_site()`,
  `objective_text()`. Signals: `offers_changed`, `job_started`,
  `job_stage_changed`, `job_completed(job, pay, summary)`, `job_abandoned`,
  `place_discovered(site)`. Audio can hook stinger sounds to these.
- `Progression.add_stat(stat, amount)` counts anything (deliveries, medals,
  night drives). Tiers and their challenges live in
  `data/progression/tiers.json`; each challenge names a stat from
  `Progression.KNOWN_STATS` and a target. Reaching a tier lets you buy that
  tier's cars. `python3 tools/pacing_model.py` estimates how many hours each
  tier takes; run it after changing tiers, car prices or delivery pay.
- Deliveries taken in light rain pay 25% more and in a storm 50% more.
  Signals: `stat_changed`, `challenge_completed`, `tier_completed`.
- Time trials are named routes in `data/progression/trials.json` (site ids
  from the job markers). Times are kept per car class, so each trial has a
  separate best for classics and every tier (`Jobs.CLASS_PACE` sets the par).
- Badges are `Collectible` nodes (group `collectibles`) with a `badge_id`.
  The map should scatter `Collectible.TOTAL` (60) of them around Perth; the
  test grid places 8. Found ones count towards the `badges` stat.
- Mileage rewards (`data/progression/mileage_rewards.json`) unlock as
  lifetime km grows; `Progression.rewards` lists the unlocked ids and the
  `reward_unlocked(reward)` signal fires for each new one.

## Night lighting

- `EnvironmentController` keeps nights readable with a moonlit ambient fill
  (`NIGHT_FILL`). Anything that glows at night joins the `night_lights` group.
- The car's `Headlights` node holds both headlight spots and a dim
  `CabinGlow` for the in-car view. `CarBody` lightens the exported `Glass`
  material at runtime (`glass_alpha`, `glass_tint`).

## Cars (data/cars/cars.json, `CarCatalogue`, `Garage`)

- Every car is data: name, years, ladder (modern / electric / classic), tier,
  price, how it unlocks, and a `spec` of CarController values (mass, torque
  curve, gear ratios, springs...). Classics have no spec yet; they arrive with
  the barn finds.
- `car.apply_car(id)` turns the player car into another model and emits
  `car_changed(id)`. Until a car has its own model, every car borrows the
  Pop's body; the models thread can swap bodies on `car_changed`, and audio
  can swap engine sounds on it (`car.is_electric` for the EVs).
- `Garage.owned_cars`, `buy_car(id, car)`, `switch_car(id, car)`,
  `car_blocker(id)` (why it can't be bought yet), `lifetime_km(car)`.
  Each car keeps its own parts, tuning, paint, fuel and odometer; bought
  parts belong to the car (`fits` on a CarPart limits it to certain cars,
  and EVs take no engine, intake, exhaust or gearbox parts).
- WorkshopSpot kinds `cars` (swap between your cars, at home) and `dealer`
  (the car yard, which also sells them).

## Workshops (autoload `Garage`, `WorkshopSpot` markers)

- `WorkshopSpot` (group `workshop_spots`) is a painted bay where the player
  stops and presses F / A. `kinds` says what it offers: `parts`, `tuning`,
  `paint`, `fuel`, `wash`. The map should place one at the townhouse carport (parts and
  tuning) and spray shops for paint; the test grid has placeholders.
- `Garage.owned` is every part bought; refitting an owned part is free.
  `buy_and_fit(part, car)`, `respray(car, index)`, `PAINTS`. Fitting and
  respraying advance the clock (`FIT_HOURS`, `RESPRAY_HOURS`).
- `car.set_tuning({key: value})` applies `CarTuning.OPTIONS` (tyre pressure,
  ride height, springs, dampers, anti-roll, final drive); options need the
  right part fitted and are ignored otherwise. `car.set_paint(color)` calls
  `set_paint` on the car's `Body` node, so any car model with that method
  can be resprayed.

## Fuel and dirt (on the car)

- `car.fuel_litres` / `tank_litres` (35), `fuel_fraction()`, `refuel(litres)`.
  Signals `fuel_low` (under 12%) and `fuel_empty` (engine cuts out). The
  engine sputters on the last half litre; audio can read
  `telemetry.engine_running` and `fuel_fraction`.
- `car.dirt` 0..1 builds up with distance, faster on gravel and grass and in
  the wet. The car body can read it for a dirt overlay (models thread).
  Deliveries in a clean car (dirt under 0.2) earn a small tip.
- `Garage.fuel_price()` follows a weekly Perth-style cycle (day 1 is a
  Monday, Tuesday is cheapest); `buy_fuel(car, litres)`, `wash(car)`,
  `roadside_assist(car)` (also on the phone when the tank is empty).

## Places, classics and side activities

- `data/world/places.json` holds every gameplay marker on the real map: 60
  badges (spawned only to top the map's own badges up to 60), 30 photo spots, 10 parking challenges, the barn finds, scenic
  drives, the car meet and the time-trial checkpoints. It's generated from the
  map's roads (`tools/places/dump_roads.gd`, then `tools/places/gen_places.py`);
  re-run both after the map is regenerated. `GameplayPlaces` (under `World` in
  `scenes/main.tscn`) spawns them. The home carport needs the `cars` and
  `restore` kinds (map/tiles/index.json) for swapping cars and restoration.
- **Points of interest** from the map: `PerthMap.get_pois(kind)` returns
  lookouts, beaches, servos, drive-thrus, quiet spots and landmarks, each
  with a stable `id`, a stop for the car (`p`, `yaw`) and the feature's own
  position (`at`). See map/README.md.
- **Classics** (autoload `Classics`): you hear rumours (one per tier
  completed, one per night at the car meet), and each one makes its `BarnFind`
  wreck appear. Stopping next to the wreck claims it. Restoration stages are in
  `data/cars/restoration.json` and happen at the carport's Restore tab. The car
  can be driven once the mechanical stages are done; the restomod finish adds
  modifiers through `Classics.modifiers(car_id)`. Signals: `rumour_heard`,
  `wreck_found`, `stage_done`, `restored`. Audio could hang the discovery
  sting on `wreck_found`.
- **Activities** (autoload `Activities`) covers the photo album
  (`user://photos`), parking records, scenic drives, the meet and relaxed
  cruising (lighter traffic via `TrafficManager.density_scale`, no jobs).
  Signals: `photo_taken`, `photo_spot_found`, `parking_finished`,
  `scenic_finished`, `meet_visited`, and `message` (HUD toasts).
- **Photo mode** (`PhotoMode`, P / L3) pauses the game and gives you a free
  camera. Its filters drive the post shader's `saturation`, `contrast`,
  `tint` and `vignette`. Audio's shutter sound can hang on
  `Activities.photo_taken`.
- **Lifts** are job-board offers (`job.lift`). Passengers and their lines are
  in `data/progression/lifts.json`.
- **The car meet** runs Friday and Saturday nights, 8 pm to 2 am. Its ambience
  can follow `CarMeet.is_meet_time()` and the `car_meets` group.

## Cosmetics and car bodies

- `data/progression/cosmetics.json` says how each cosmetic reward looks
  (trinket slot, livery mode and colour) and which come from nights at the car
  meet; mileage rewards keep their ids from `mileage_rewards.json`.
  `Progression.grant_reward(id, why)` gives one; `reward_unlocked` fires.
- Trinkets are built in code (`scripts/vehicle/trinkets.gd`). A car model can
  mark where they go with `Mount_Mirror`, `Mount_Dash`, `Mount_Shelf` and
  `Mount_Gear` nodes; without them the Pop's measured spots are used.
- Liveries are drawn by `shaders/ps1_surface.gdshader` in the car's own space
  over the `Body` mesh's bounds (`car_body.gd` `apply_cosmetics()`).
- Garage decorations (`kind: garage`) are earned but not shown yet: the home
  scene can read `Progression.earned_cosmetics("garage")`.
- `data/cars/cars.json` `model` names the body under
  `art/models/cars/<model>/<model>.glb`; `CarController.apply_car()` swaps it
  in. Cars without one borrow the Pop's.

## Train races and night oddities

- `TrainRace` (under `GameplayPlaces`) listens to traffic's `train_spawned`
  and races you against trains you drive beside; stats `trains_raced` and
  `trains_beaten`. Sounds: `traffic/traffic_train_alongside_loop` (pitch =
  train speed / 100 km/h) and `Audio.sting("race_win")`.
- `Oddities` (under `GameplayPlaces`), midnight to 3:30: the Kings Park
  follower (`oddity/odd_follower_engine_loop`), the lane idle
  (`oddity/odd_lane_idle_loop`, then `oddity/odd_lane_idle_cutout` within
  25 m), the river lights (`oddity/odd_river_lights_loop` and
  `oddity/odd_river_lights_shimmer`) and the midnight station
  (`oddity/odd_midnight_station_found` the first time). Each counts once as
  discovery `oddity/<id>`. Missing sounds play nothing.

## The main mystery

- `Mystery` (under `GameplayPlaces`, data in
  `data/progression/mystery.json`). After midnight, tuning to the midnight
  station makes the voice name a place (shown as a message and in the phone's
  Leads tab). Between midnight and 3:30 a small glowing object waits there;
  stop beside it or walk up to it. The next morning it's on the boxes in the
  cupboard under the stairs, and that cupboard is open. Each clue needs a
  career tier and at least `min_days` days after the last; the seventh, the
  shed key, needs the last tier. Finds are discoveries `mystery/<id>`, the
  end is `mystery/solved` and reward `trinket_night_drive_tape`. Saved under
  `mystery`.
- `HomeBase.shed_tried` fires when someone tries the locked shed. The
  mystery unlocks it if you have the key; otherwise, late at night,
  something knocks back (discovery `oddity/shed_knock`).
- Walking up to the sheet in the open shed hides `Shed_Sheeted` and puts the
  card table, cassette deck and transmitter (`MysteryProps.build_shed`) there.
- Sounds (missing ones play nothing): `oddity/odd_clue` (variants) for the
  voice and each find, `oddity/odd_key_found` (Music bus),
  `oddity/odd_shed_interior_loop` (Ambience, in the open shed),
  `oddity/odd_mystery_bed_loop` (fades in on the Music bus during mystery
  moments) and `oddity/odd_shed_knock` (falls back to
  `home/home_odd_wall_tapping`). The shed unlock sound is game_hooks.gd's,
  on `shed_unlocked`.
