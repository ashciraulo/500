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
| `traffic_horn_car_01` to `_03` | no | car horns (each car keeps one) |
| `traffic_horn_bus` | no | bus air horn |
| `traffic_bus_air_brake` | no | air brake release when a bus stops |
| `traffic_bus_doors` | no | bus doors folding open |
| `traffic_train_running` | yes | train at speed beside the line; pitched by speed |
| `traffic_train_horn` | no | two-tone warning at level crossings |

Crossing bells and pedestrian beeps come from `amb/` (`amb_crossing_bells_loop`,
`amb_ped_beep`).
