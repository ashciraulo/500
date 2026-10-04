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

Physics layers: 1 = world (roads, ground), 2 = buildings. The car is on layer 1 and collides with both.

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
