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
- `parked_changed(parked: bool)`: the driver stopped or moved off.

Wear: `car.wear` holds tyres, brakes and oil from 0 (new) to 1 (worn
out), saved with each car. Worn tyres grip less, worn pads stop less hard,
and overdue oil takes a little torque. `service_due(item)` fires at 0.8, and
`services_due()` lists what's due. `Garage.service(car, item)` does the job
at the carport (`Garage.SERVICES`: price and hours), and fitting a tyres or
brakes part also resets that item. Audio could use `wear.brakes` for a pad
squeal and `wear.tyres` for a thinner tyre note.

Dashboard needles: any node under the body named `Needle_<dial>_<full
scale>` (`Needle_Speed_200`, `Needle_Rev_7` in thousands of rpm,
`Needle_Fuel_1` as a share of the tank) is swung by the car, 240 degrees
clockwise from its rest pose at full scale. An `Odometer_<digit height in mm>`
empty gets a six-digit Label3D (`Digits`) showing the car's `odometer_km`.

Bird-watching and fishing from the car:

- `is_parked_for_viewing()`: the driver is in the seat and the car is
  stopped (under 2 km/h), so binoculars and the camera can be raised
  without getting out. `driver_eye()` is the eye point as a world
  `Transform3D` facing forward (-Z).
- `set_field_gear(ids)`, `has_field_gear(id)`, `field_gear`: gear shown in
  and on the car, from `art/models/props/field/<id>.glb`: `fishing_rod`
  (on the roof rack; in the boot, unseen, without one), `esky`,
  `tackle_box`, `binoculars`, `camera` (on the seats; the classics carry
  the esky on the passenger seat). It follows the player to any car and is
  saved with the car they're driving. Call it when gear is bought or sold.

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
- `sun_phase()` `&"night"`, `&"dawn"`, `&"day"` or `&"dusk"` (dawn and dusk
  are the hour or so around sunrise and sunset), `is_golden_hour()`, and the
  `sun_phase_changed(phase)` signal. Birds, fish and challenges use these.
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
`show_help`, `cozy_mode` (no oddities at home). Change values, then call
`apply()`; `save_settings()` writes them.
The pause menu (`scripts/ui/pause_menu.gd`) pauses the tree, so anything that
should keep running while paused needs `process_mode = PROCESS_MODE_ALWAYS`.

## Title screen (`TitleScreen`, `scripts/ui/title_screen.gd`)

`main.gd` adds it on a normal run: the camera drifts round the parked car,
the HUD and car controls are off and `SaveGame.hold` stops autosaves until
you pick Continue or New game (`started` fires). It is skipped under
`--script` (the tests) and with `-- --no-title`. New game with a save on
disk deletes it and restarts the game with `-- --fresh`, so every autoload
starts from its defaults. `TitleScreen.is_showing(tree)` tells other menus to
stand back. Settings opens the pause menu over it (Back instead of Resume).

## Home life and home oddities

On foot, anything in the group `interactables` with `interact_point()`,
`interact_hint()` ("" = nothing to do) and `interact()` gets an F prompt
when you're close and looking at it (`scripts/player/on_foot.gd`). The bed
asks whether to wake in the morning or at dusk (`home.sleep(HomeBase.DUSK_HOUR)`).

`HomeLife` (`scripts/world/home_life.gd`, saved as "home_life"): the cat
(`feed_cat()`, `cat_place()` = "" / "bowl" / "courtyard" / "rug" / "bed",
`pat_cat()`; discovery "home/cat") and the cuttings (`found_cuttings()`,
`stage(id)` 1..3, `water()`, signal `watered(grown)`). Cuttings are found in
the city at `CuttingSpot`s from `data/world/cuttings.json` (discovery
"cutting/<id>").

`HomeOddities` (`scripts/world/home_oddities.gd`) shows the house's
`Oddity_*` props: one odd thing some days (`roll()`, `today`), the intercom
after midnight, tapping on storm nights, headlights across the bedroom
ceiling. Discoveries "oddity/home_<id>". All off in cozy mode, which also
quiets the shed's knocking back and the upstairs toilet light's flicker.

## Parts and upgrades

Parts are data in `data/parts/<id>.tres` (`CarPart`, `scripts/vehicle/car_part.gd`).
Each has a `slot` (engine, intake, exhaust, gearbox, suspension, tyres, wheels,
brakes, weight, roof, lights), a `price` (AUD), stat `modifiers` (keys documented in
`car_part.gd`) and an optional `visual` model id (`exhaust_sport`,
`wheel_alloy15`, ...) for the car body to show. `PartsCatalogue` lists them:
`all()`, `for_slot(slot)`, `get_part(id)`.

On the car: `install_part(part)`, `remove_part(slot)`, `parts` (slot -> part),
`get_part_ids()` / `install_part_ids(ids)` for saving, and `get_stats()` for
headline numbers (power_kw, torque_nm, mass_kg, grip, ...). Parts always stack
from the stock values. Signal `parts_changed(slot, part)` fires on every change;
the car body uses `part.visual` to swap wheels and exhausts.

Part models live in `art/models/cars/parts/<visual>.glb` (wheels as
`<visual>_l` / `_r`). Exhaust, roof and lights parts sit at the body's
`Mount_Exhaust`, `Mount_Roof` and `Mount_Spotlights` empties as `Body/Part_<slot>`;
the spotlights add two lamps (group `car_spotlights`) that follow the
headlights. Without a fitted wheels part the car uses its model's own
`WheelStyle_<style>` wheels.

A part model can come in one per body family: the car loads
`<visual>_classic.glb` on classics and `<visual>_modern.glb` on everything
else when it exists, else `<visual>.glb`. Roof racks (`roof_plain_rack`,
`roof_luggage`, `roof_bike`, the found `roof_surf_rack`) carry a `Mount_Rod`
empty where the field fishing rod lies; cars with `"no_roof_rack": true` in
cars.json (the 500C, the Jolly) take no roof parts.

Body and interior slots: `rear_rack` (Mount_RearRack, classics with an engine
lid), `bumpers` (`<visual>_f` at Mount_BumperF and `<visual>_r` at
Mount_BumperR; a part with one model goes on the front only), `towbar`
(Mount_TowBar), `mudflaps` (the same model at Mount_MudFlap_L and _R;
`mudflap_short` on the Giardiniera), `steering_wheel` (Mount_SteeringWheel;
hides `SteeringWheel` and turns with the steering), `gear_knob`
(Mount_GearKnob; hides `GearKnob`) and `seat_covers` (Seat_L, and mirrored at
Seat_R). See `CarController.PART_MOUNTS`, `PART_PLACES` and `PART_HIDES`.
The modifier `dirt_mult` scales how fast the car gets dirty.

`ladders` limits a part to cars whose cars.json `ladder` is listed (empty fits
everything). `found_only` parts can't be bought: each is somewhere in the city
(`data/world/found_parts.json`, `FoundPart` nodes in group `found_parts`), and
picking it up records the discovery `part/<id>`, after which `Garage.owns()` is
true for every car it fits. The phone lists their rumours.

Drivetrain slots: `flywheel` (`flywheel_light`: `free_rev_mult` speeds how the
engine revs, in and out of gear), `diff` (`diff_lsd`: `diff_lock_add`) and
`anti_roll` (`anti_roll_sport`, `anti_roll_adjustable`, which unlocks the
anti-roll tuning slider). The car's `diff_lock` (0 open, 0.5 even split, 1
locked; stock 0.25) decides how much drive the wheel with grip gets when the
other driven wheel can't use its half (`_drive_share`). The LSD also unlocks a
"Diff lock" tuning slider.

Engine kits: `engine_turbo_hybrid` (turbo cars), `engine_carb_kit` and
`engine_big_bore` (classics; both show `sump_finned` at Mount_Exhaust as
`Part_engine`). `lights_fog` shows `foglamps_yellow` at Mount_Spotlights with
wide yellow lamps. `plate` parts swap `art/models/cars/plates/<visual>.png` into
the body's Plate material (`CarBody.set_plate`); `plate_stock` keeps the car's
own.

## Skidpad (`Skidpad`, `scripts/world/skidpad.gd`)

A fenced concrete pad with a painted ring, off the edge of the map at
`Skidpad.ORIGIN`. The workshop's tuning tab sends the car there
(`start(car)`; saving is held while it's out there). Each full lap of the ring
emits `lap_done(seconds, g)` with the average sideways g, and the best per car is
kept (`best_for(car_id)`, saved as "skidpad"). Stopping and pressing interact,
or driving off the pad, calls `finish()`, which puts the car back where it was.

## Furniture (`HomeFurniture`, `scripts/world/home_furniture.gd`)

Rugs, lamps, armchairs, posters and plants from the catalogue on the lounge
coffee table (`open_catalogue()`; the townhouse's `Catalogue` empty if it has
one). Spots and items are in `data/home/furniture.json`: each spot is a
townhouse empty (`Decor_Rug_Lounge`, `Decor_Lamp_Bedroom`, `Decor_Poster_1`..4,
`Decor_Plant_1`..3, `Decor_Chair`, ...) with a stand-in place until the model
has it, and can name a model it replaces (`Rug_Lounge`). Items are
`art/models/props/home/decor/<id>.glb` (a `Light` empty gets a lamp) with a
stand-in box until they exist. `order(item, spot)` pays now; `deliver()` runs
on `home.slept` and puts it out. `place(item, spot)` moves something you own
(free). Saved as "furniture".

## Records (`RecordCrate`, `scripts/world/record_crate.gd`)

Every song the radio plays (`Radio.now_playing`, matched to the station
programmes' titles) goes in the record crate once; the main and home themes
are there from the start. At home, the townhouse's `RecordPlayer` plays the
next record and the `RecordCrate` opens a list to pick one (`play(id)`,
`stop()`); it plays through a `RecordSpeaker` on the Music bus and stops when
you leave the house. A `Platter` empty spins and `Sleeve_1..12` show as you
collect, if the models have them. Saved as "records". Sound hook:
`home/home_record_needle`.

## Home decorations (`HomeDecor`, `scripts/world/home_decor.gd`)

Built at the home model's empties, refreshed when rewards, tiers, photos or
classics change: `Deco_RoadMap` and `Deco_NeonSign` (garage cosmetics
`garage_road_map`, `garage_neon_sign`), `Deco_Shelf_1..8` (a gold trophy per
career tier finished, then silver per classic restored), `Corkboard_Pin_1..12`
(a card per classic found) and `Photo_Frame_1..6` (latest album photos). Each
prop is a child named `Decor`.

The carport parts shelf (`PartsShelf`, `scripts/world/parts_shelf.gd`) shows
`Garage.spare_parts(car)` (owned or found, not fitted) at the player's shed
wall under a `CarportShelf` node on the home: small parts on a steel unit,
spare wheels leaning on the wall, racks and bumpers flat-packed. No model
empty needed; if the shed moves in `build_shenton.py`, move `WALL_X`/`WALL_Y`.

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
  `Progression.KNOWN_STATS` and a target. Field journal stats
  (`species_seen`, `species_photographed`, `prints_sold`, `fish_caught`,
  `fish_species`) are read live from `FieldJournal.stat(name)`. Reaching a tier lets you buy that
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
  right part fitted and are ignored otherwise. `car.save_setup(i)`,
  `car.load_setup(i)` and `car.has_setup(i)` keep named setups
  (`CarController.SETUP_NAMES`) saved with the car. `car.set_paint(color)` calls
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
  lookouts, beaches, servos, drive-thrus, quiet spots, fishing spots and
  landmarks, each with a stable `id`, a stop for the car (`p`, `yaw`) and the
  feature's own position (`at`). `PerthMap.water_level_at(pos)` gives the
  surface height of the lake or pond under `pos` (NAN elsewhere; the river
  and sea are at y 0). See map/README.md.
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
- Field journal rewards: cosmetics with `species` are granted at that many
  species seen (`FieldJournal.seen_count()`, checked on `species_seen`): the
  nodding dash wagtail (`dash_bird.glb`, its `Head` on a "Bob") at 10 and the
  naturalists' club sticker (slot `glovebox`) at 20.
- Liveries are drawn by `shaders/ps1_surface.gdshader` in the car's own space
  over the `Body` mesh's bounds (`car_body.gd` `apply_cosmetics()`).
- The spray shop also paints its own liveries (`Garage.LIVERIES`, in one of
  `Garage.LIVERY_COLOURS`): `Garage.paint_livery(car, mode, colour, number)`
  stores them in `car.custom_livery` and sets `cosmetics.livery` to
  `"custom"`. Rally roundels (`rally_numbers`) carry a 1-99 door number drawn
  as seven-segment digits; `centre_stripe` is one wide stripe nose to tail.
- Clear coats (`Garage.FINISHES`: gloss, metallic, satin, matte) set the
  `Paint` material's roughness and metallic; `car.finish` is saved with the
  car, and `""` keeps the model's own.
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
- `MJournal` (`scripts/world/m_journal.gd`): M.'s closed 1979 journal
  (`m_journal.glb`) turns up at the back of the cupboard boxes with the first
  find. Interact opens it (its `Cover` swings to rotation.z +178 degrees);
  the first time is discovery `mystery/m_journal`. Its pages are torn out:
  they're the field journal's M.'s pages.
- Sounds (missing ones play nothing): `oddity/odd_clue` (variants) for the
  voice and each find, `oddity/odd_key_found` (Music bus),
  `oddity/odd_shed_interior_loop` (Ambience, in the open shed),
  `oddity/odd_mystery_bed_loop` (fades in on the Music bus during mystery
  moments) and `oddity/odd_shed_knock` (falls back to
  `home/home_odd_wall_tapping`). The shed unlock sound is game_hooks.gd's,
  on `shed_unlocked`.

## Field journal: birds and fish (autoload `FieldJournal`)

Design: `docs/FIELD_JOURNAL.md`. Species in `data/field/birds.json`, places
in `data/field/habitats.json` (lat/lon of the real place; x/z from
`tools/field/gen_field.py`; lake heights from the map, `MapStreamer.water_level_at`).
Fish in `data/field/fish.json`, spots in `data/field/fishing_spots.json`
(where to stand found in the map by `tools/field/place_spots.gd`; rerun it
after a map rebuild).

- `FieldJournal.species_seen(id)`, `photo_logged(id, stars, frame)`,
  `film_changed(left, size)`, `roll_developed(prints, pay)`.
- `FieldJournal.is_seen(id)`, `is_photographed(id)`, `seen_count()`,
  `photographed_count()`, `entry(id)`; `see(id, where)` notes a species
  (another system can call it, e.g. traffic's magpies).
- Career stats (`Progression`): `species_seen`, `species_photographed`,
  `prints_sold`, `fish_caught`, `fish_species`.
- Fishing: signals `fish_landed(catch)`, `esky_changed(count, size)`,
  `weighed_in(fish, pay)`, `gear_changed`; `is_caught(id)`, `caught_count()`, `catches`,
  `esky`, `rod`, `esky_level`, `has_crab_net`, `crab_nets`;
  `upgrade_fishing("rod" | "esky" | "crab_net")`, `buy_ice()`, `weigh_in()`.
  Discoveries: `fishing/<spot id>` when a spot is found, `fishing/fiat_hubcap`
  when the hubcap goes home.
- Gear: `FieldJournal.binoculars`, `camera`, `lens`, `film` (levels into
  `BINOCULARS`, `CAMERAS`, `LENSES`, `FILMS`); `upgrade(kind)` buys the next
  at the lab. `murk()` is how much the dark spoils a shot on the film loaded
  (0 by day); `Binoculars.photo_frame()` is the target's frame times the lens.
- The world side is `FieldWorld` ("Field", next to the player's car): `birds`
  (`FieldBirds`, group `field_bird_spawner`), `lab` (`BirdLab` on Lake
  Street, group `photo_labs`), `binoculars`, `journal`, `lab_screen`,
  `fishing` (`FieldFishing`, group `fishing`: `is_busy()`, signals
  `landed(catch)`, `lost(why)`), `tackle` (`TackleShop` on the Mends Street
  jetty forecourt, group `tackle_shops`: a walk-in room, `is_inside(p)`,
  `at_counter(p)`, `on_scale()`, `brag_list()`), `tackle_screen`, `fishing_screen`.
- `FishModels.build(fish)` / `sized(fish, cm)` makes a fish, crab, squid or
  hubcap (node `Body`), facing -Z.
  Birds are in group `field_birds` with meta `species`.
- `FieldBirds.spawn(species, habitat, near)` places a sighting by hand (tests
  set `auto_spawn = false`); `flush(node, from)` scares one off.
- `BirdModels.build(species)` makes a bird facing -Z, feet at the origin
  (nodes `Trunk` with `Tail` and `Folds`, `Head`, `Legs`, `WingL`, `WingR`;
  meta `rest`); `set_flying`, `flap`. Looks come from birds.json (`model`,
  `colours`, `marks`, `shape`). `tools/bird_sheet.gd` renders every bird side
  on, from the front and in flight for checking against photos.
- Input: `binoculars` (B, R3), `photo_take` for the shot, `journal` (J),
  `interact` (F / A) to fish, cast, strike and reel.
- Sounds (missing ones play nothing): `field/bird_<id>` calls (magpie and
  ibis use traffic's), `field/binoculars_up`, `field/binoculars_down`,
  `field/shutter`, `field/focus_hit`, `field/focus_miss`, `field/flush`,
  `field/film_full`; fishing: `field/rod_out`, `field/cast`, `field/lure_plop`,
  `field/bite_nibble`, `field/splash_small` (a bite, a release), `field/strike`,
  `field/drag` (a run starts), `field/line_snap`, `field/landed_flop`,
  `field/esky_lid`, `field/reel_in`, `field/splash_big` (crab net in),
  `field/bucket_drop` (crab net up); loops `field/reel_loop` (while you
  wind on a fish, quicker with less weight) and `field/line_tension_loop`
  (louder and higher as the line nears breaking). Saved under `field_journal`.
- `FieldJournal.stat(name)` reads the career stats above live.
- Place ambience (the audio side's `"poi"` group nodes with `poi_type` and
  `radius` meta): fishing spots near the player are `jetty` (decks) or
  `groyne` (rocks), the shops `photo_lab` and `tackle_shop`; a wrong bird
  with a `bed` in birds.json (the cockatoos) carries that place type while
  it's there. Wrong birds call `field/bird_<wrong id>` when it exists, else
  the bird they look like. `field/m_page_found` (or `_yours`) plays when the
  binoculars first find one; `field/m_page_open` and the `field/m_page_room`
  loop while one of M.'s pages is open in the journal.
- Wrong fish (`"wrong": true` in fish.json, like the birds): a `spot`, an
  `after` discovery and `hours`; they bite at that spot only until caught,
  can't be kept, don't count (`FieldJournal.counts(f)`), and show M.'s `page`
  in the Fish tab. `tag` gives the fish model a jaw tag: `bream_tag.glb`
  (node `Tag`, 6.5 cm, hanging from the lower jaw), or a plain one in that
  colour if the model's missing;
  `glow` a colour it glows (an overlay and an `OmniLight3D` "Glow"), and a
  fading patch of that light under the surface when it's let go; `release`
  replaces the line said when it's let go.
- Home (`FieldWorld.home`, `HomeField`): the starter binoculars hang on
  `Binoculars_Hook` until taken (discovery `field/binoculars`; B is blocked
  till then, old saves with journal entries count as taken); at 30 species
  `bird_feeder.glb` goes on `Feeder_Spot` (discovery `field/feeder`) with
  garden birds you've seen (`HomeField.FEEDER_BIRDS`) on its perches by day.
  `FieldWorld.trophies` (`HomeTrophies`) hangs the kept hubcap on the outside
  of `Shed_Door` once `fishing/fiat_hubcap` is discovered (`hubcap()`), and
  pins M.'s `m_page_<bird>.glb` pages above the coat hooks (children of
  `Binoculars_Hook`, named `MPage_<wrong id>`, `pages()`, flat on the wall
  `PAGE_WALL` behind the hook) for each wrong bird in the journal. The wrong
  boobook (`"behaviour": "nest"`) sits on the `Bird` empty of
  `boobook_hollow.glb`, a stump `FieldBirds.find_hollow(sighting)` returns,
  facing out of the hollow. The stump is solid, so it stands on the nearest
  open ground at least 4 m clear of any road or path (`_off_paths`). The dash bird (10
  species) is the car's: `FieldJournal.seen_count()` and `species_seen`.
- Quiet places (`FieldWorld.quiet`, `QuietPlaces`): habitats.json entries
  with `"hidden": true` and fishing_spots.json spots with `"hidden": true`
  name the map POI they come from (`poi`). Walking within 60 m (30 m for a
  fishing spot) discovers `places/<poi id>` (`FieldJournal.place_key(h)`), so
  the map can show a hidden POI once `Discoveries.has("places/" + poi.id)`.
  `FieldJournal.places_found()` / `stat("places_found")` count them;
  `field/quiet_place` plays on finding one (falls back to the new-species
  music).
- Music: `music/mus_field_journal` plays while the journal is open (only if
  no other music is), and `music/mus_field_new_species` on a new bird; both
  are skipped until the audio side ships them.
- Models: the photo lab puts `shop_photo_lab` on the building line beside
  its bay; `shop_tackle` stands on its own 9 m back from its bay on a slab
  (`Slab`, `Slab_Col`) that takes up the slope, with the best weigh-in fish
  on `Scale` and cards on `BragBoard`; the rod in first person is `fishing_rod.glb` (line
  from `Tip`), and `esky.glb` sits beside you while fishing (`Lid` opens as a
  fish goes in).
- Car: binoculars use `CarController.is_parked_for_viewing()` and
  `driver_eye()` when the car has them; the field world calls
  `set_field_gear(["fishing_rod", "esky", "binoculars", "camera"])`, adding
  `"tackle_box"` once a rod, esky or crab net has been bought (`gear_changed`).
