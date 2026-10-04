# 500

A slow, lo-fi driving game about a little Fiat 500 in Perth, Western Australia.
Built with **Godot 4** (GDScript) and a PS1-style look.

This is the first playable prototype: a 2013 Fiat 500 Pop (modelled on Ash's
own car) with a 5-speed manual, a test grid to drive around, a day/night
cycle with Perth's sun, three kinds of weather, and the lo-fi render pipeline.

## Run it

1. Install **Godot 4.3 or newer** (standard build, not .NET) from
   <https://godotengine.org/download>.
2. Clone this repo, open Godot, click **Import** and pick `project.godot`.
3. Press **F5** (or the ▶ button, top right) to play.

The first import takes a few seconds while Godot builds its `.godot/` cache.

## Controls

Keyboard or any standard gamepad. Press **F1** in game to show/hide this list.

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle / brake | W / S (or arrows) | Right / left trigger |
| Steer | A / D (or arrows) | Left stick |
| Handbrake | Space | B |
| Gear up / down | E / Q | RB / LB |
| Manual ↔ automatic | G | Select / Back |
| Camera (chase / interior) | C | Y |
| Look around | Click to capture the mouse | Right stick |
| Headlights (auto by default) | L | D-pad up |
| Reset car upright | R | D-pad down |
| Pause and settings | Esc | Start |
| Next weather (and lock it) | F5 | D-pad right |
| Lock / unlock weather | F6 | |
| Skip forward 1 hour | F7 | D-pad left |
| Lock / unlock the clock | F8 | |
| Lo-fi filter on / off | F9 | |

The pause menu lets you pick the weather and time of day (or leave them
natural), freeze the clock, change the day length and gearbox, and tune the
lo-fi look. Settings are saved between sessions.

In **automatic**, hold brake at a standstill to reverse. In **manual**, shift
down past neutral to get reverse (only when nearly stopped). The clutch is
automatic and the engine can't stall.

## Where things live

See [CONTRIBUTING.md](CONTRIBUTING.md) for the folder layout and conventions,
and [docs/HOOKS.md](docs/HOOKS.md) for the values the car, clock and weather
expose to other systems (audio, map, UI).

## Traffic sandbox

Open `traffic/sandbox/traffic_sandbox.tscn` and press **F6** to drive around a
small suburb with traffic lights, a roundabout, a railway with boom gates,
buses and people. See [docs/TRAFFIC.md](docs/TRAFFIC.md).

## Tests

`tools/smoke_test.gd` loads the game headless and drives the car through a
few checks (settles on its wheels, pulls away, shifts, brakes, reverses,
turns). CI runs it on every push; locally:

```sh
godot --headless --path . --import
godot --headless --path . --fixed-fps 120 --script res://tools/smoke_test.gd -- --no-save
godot --headless --path . --fixed-fps 60 --script res://tools/traffic_test.gd
# Optional, a few minutes: traffic soak on the Perth map (not in CI)
godot --headless --path . --fixed-fps 60 --script res://tools/traffic_map_test.gd
```
