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

### Build a copy that runs without the editor

`export_presets.cfg` has Windows, Linux and macOS presets. Install the
export templates once (Godot: **Editor > Manage Export Templates >
Download and Install**), then **Project > Export...**, pick a platform and
**Export Project**. Or from a terminal:

```sh
godot --headless --path . --export-release Windows build/windows/500.exe
godot --headless --path . --export-release Linux build/linux/500.x86_64
godot --headless --path . --export-release macOS build/macos/500.zip
```

Keep the `.pck` next to the program. Saves, photos and the My Music folder
live in the user data folder (on Windows `%APPDATA%\Godot\app_userdata\500`).
The macOS build is unsigned, so the first time right-click it and choose
**Open**.

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
| On foot: walk, hurry | W A S D, Shift | Left stick, B |
| On foot: hop up a ledge | Space | Y |
| Pause and settings (and "Get unstuck" if you can't climb out of somewhere) | Esc | Start |
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

### Dev mode (testing)

Running from the Godot editor (or a debug export) adds a developer mode for
playtesting; release exports leave it out. **F3** turns it on or off, and it
stays on between runs. While it's on, a panel top right shows where you are
and these keys work:

| Key | Does |
| --- | --- |
| U | Unstuck: on foot, back on top of the drop you just fell down (or back along where you walked); in the car, back along the road and upright |
| V | Fly on foot, through walls: W/S go where you look, E/Q (or Space) up and down, Shift fast. V again to land |
| 1 | Home: on foot to the front gate, in the car to the carport |
| 2 | To the car (on foot) |
| 3 | Bring the car to you (on foot) |
| X | Mark this spot: its position goes on the clipboard and into `dev_marks.txt` in the user data folder, to report a stuck spot |

To find spots you can get into on foot but not back out of, without
walking them: `tools/stuck_sweep.gd` checks the map tiles' colliders (and the
townhouse) on a grid and lists every trap with where it is, how you got in
and how high a step would get you out; `tools/stuck_shots.gd` takes a
screenshot of each. See the top of each script for how to run them.

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
godot --headless --path . --fixed-fps 60 --script res://tools/mystery_test.gd -- --no-save
godot --headless --path . --fixed-fps 60 --script res://tools/parts_test.gd -- --no-save
godot --headless --path . --fixed-fps 60 --script res://tools/kerb_test.gd -- --no-save
godot --headless --path . --fixed-fps 60 --script res://tools/dev_mode_test.gd -- --no-save
godot --headless --path . --fixed-fps 60 --script res://tools/stuck_test.gd -- --no-save
# A real-time playthrough from whatever save you have (or none): load, drive
# out of the carport, workshop, a job, switching cars, walking, sleeping.
# Without tour=off it also tours the whole map and reports streaming hitches.
godot --headless --path . --script res://tools/playthrough.gd -- tour=off
# Optional, a few minutes: traffic soak on the Perth map (not in CI)
godot --headless --path . --fixed-fps 60 --script res://tools/traffic_map_test.gd
```

## Credits

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors,
available under the Open Database License (ODbL).
