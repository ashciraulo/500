# Traffic

Made by `audio/tools/gen_traffic.py`; played by `audio/scripts/traffic_audio.gd`
on the **Vehicles** bus.

## Engines

Same layout as the Fiat sets (see [engine](engine.md)): `eng_<set>_onload_<rpm>`
and `_offload_<rpm>` loops plus start-up, shut-down and limiter. Stock exhaust
only. The game fakes a gearbox for AI cars from their speed.

| Set | Heard on | Character |
| --- | --- | --- |
| `sedan` | hatches, sedans, SUVs | smooth everyday petrol four |
| `diesel` | utes, vans | clattery turbo-diesel four |
| `busdiesel` | Transperth buses | deep, slow-revving six (600 to 2400 rpm) |

## One-shots and loops (`traffic/`)

| File | Loop | What |
| --- | --- | --- |
| `traffic_horn_car_01` to `_03` | no | car horns (each car keeps one): an Alfa MiTo twin, a Skoda Fabia single, a lower single honked twice (CC0 recordings) |
| `traffic_horn_bus` | no | bus air horn: a recorded deep truck air-horn chord |
| `traffic_bus_air_brake` | no | air brake release when a bus stops |
| `traffic_bus_doors` | no | bus doors folding open |
| `traffic_train_running` | yes | train at speed beside the line; pitched by speed |
| `traffic_train_alongside_loop` | yes (9 s, mono) | racing a train: the train at ~100 km/h from a car keeping pace a few metres off. Inverter whine, motor hum, steel roll, wind buffeting off the carriage, the nearest car's four axles clacking over rail joints, the odd pantograph spark. Pitch it with the train's speed (`pitch_scale = speed / 100 km/h`) and fade with the gap |
| `traffic_train_horn` | no | two-tone warning at level crossings, high then low, from one recorded air horn |
| `traffic_siren_police_loop` | yes (8 s, mono) | police siren close up: a wail, then yelps; swapped onto each police car's `Audio/Siren` by `traffic_audio.gd` |
| `traffic_siren_ambulance_loop` | yes (8 s, mono) | ambulance: a steady wail |
| `traffic_siren_fire_loop` | yes (8 s, mono) | fire truck: a lower, slower wail with a rotary growl under it |
| `traffic_bike_freewheel_loop` | yes (4 s, mono) | a cyclist coasting: freewheel pawls ticking, tyre hum, a little chain rattle; on every bike within 30 m |
| `traffic_roadworks_day_loop` | yes (40 s, mono, -24 LUFS) | roadworks by day: generator, a plate compactor thumping in runs, shovels scraping, the ute reversing with its beeper. Play at the site |
| `traffic_roadworks_night_loop` | yes (20 s, mono, -30 LUFS) | roadworks at night: the generator and the light tower's buzz |
| `traffic_ibis_grunt_01` to `_03` | no | Australian white ibis: hoarse, guttural grunts (synthesised; no CC0 recording found) |
| `traffic_wings_takeoff_01`, `_02` | no | a bird taking off: 01 a magpie's quick wingbeats, 02 an ibis's slower, heavier ones |
| `traffic_roo_thump_01` to `_03` | no | a kangaroo's hop landing on grass: a soft heavy thud and a swish; one per bound |
| `traffic_crowd_small_loop` | yes (20 s, mono, -24 LUFS) | a few people talking as they wait or walk (wordless walla); on a group of pedestrians or a bus stop |
| `traffic_crowd_busy_loop` | yes (30 s, mono, -22 LUFS) | a busy footpath on a Friday night in Northbridge: lots of voices, laughter; on a crowd, several around a strip |
| `traffic_steps_shoes_loop`, `_heels_loop`, `_thongs_loop` | yes (4 s, mono) | one person walking on a concrete footpath at 2 steps a second: rubber soles, heels, and thongs (flip-flops). Pitch with walking speed (`pitch_scale = speed / 1.4 m/s`); only on the few nearest pedestrians |
| `traffic_train_arrive` | no (9 s) | a train pulling into a platform: inverter whine falling, brakes squealing, a clunk and the air hiss |
| `traffic_train_doors` | no (9 s) | door chime, doors sliding open; 4.7 s later the chime again and the doors closing with a thump. Start it as the train stops |
| `traffic_train_depart` | no (9 s) | a train leaving: the inverter whine climbing in steps, rolling away |
| `traffic_ferry_engine_loop` | yes (8 s, mono) | a Transperth ferry under way: diesel thrum, engine, the hull through the chop. Pitch a little with speed |
| `traffic_ferry_idle_loop` | yes (6 s, mono) | the ferry idling at the jetty |
| `traffic_ferry_horn` | no | the ferry's horn: a short and a longer blast, as it leaves the jetty |
| `traffic_ferry_wake_loop` | yes (10 s, mono, -26 LUFS) | the ferry's wake reaching the shore or a jetty: small waves slapping, then settling. Play at the shore for ~10 s after a ferry passes |

Crossing bells and pedestrian beeps come from `amb/` (`amb_crossing_bells_loop`,
`amb_ped_beep`).

## People, stations and ferries in game

`traffic_audio.gd` puts footsteps (shoes, heels or thongs, one per walker)
on the 4 nearest walking pedestrians within 25 m (`manager.pedestrians`),
pitched with their speed, and plays crowd walla at the middle of the people
within 45 m: the busy loop for 8 or more, the small one for 3 to 7. On
`train_arrived` it plays the end of `traffic_train_arrive` and the doors; on
`train_departed`, `traffic_train_depart`; on the ferries' `ferry_departed`,
the wake 6 s later. The traffic code plays the roadworks, wildlife and ferry
engine sounds itself.
