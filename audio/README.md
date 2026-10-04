# Audio

Everything you hear in the game: engines, tyres, crashes, car foley, weather,
Perth ambiences, the home, UI, music, and the car radio with its **My Music**
station. This first pass is made by Claude: synthesised in code, plus a few
CC0/CC-BY field recordings (see [CREDITS.md](CREDITS.md)). Any of it can be
replaced by your own recordings, one file at a time.

## Replacing a sound with your own

1. Find the file in the tables in [docs/](docs/) (or by browsing the folders).
2. Save your recording with **the same name** in the same folder, as `.ogg`,
   `.wav` or `.mp3`. You can delete the generated `.ogg` or leave it: a `.wav`
   or `.mp3` of the same name always wins.
3. Open the project in Godot once so it imports the file. That's it.

What makes a replacement fit (from the plan's delivery specs):

- 48 kHz, 24-bit WAV masters are ideal; OGG q6+ is fine for the game.
- **Mono** for anything at a point in the world (engines, tyres, impacts,
  horns, doors, birds). **Stereo** for music, ambience beds and UI.
- **Loops** (marked "yes" in the docs tables) must loop seamlessly: trimmed
  to the loop point, no fades. The game turns looping on itself.
- Levels: one-shots peak around -1 dBTP; ambience beds about -24 LUFS; music
  about -16 LUFS. The mixer balances the rest.
- **Variants** are numbered `_01`, `_02`, ... The game picks one at random and
  never the same twice in a row. Add or remove variants freely.
- Design from **outside the car**. The game makes the inside version by
  filtering (except rain on the roof, which has its own inside files).

### Engines

An engine set is a folder in `engine/`, e.g. `engine/fire12/` for the 2013
Pop's 1.2. It holds steady loops at a handful of RPM points:

    eng_fire12_onload_2500.ogg     accelerating, under load, at 2500 rpm
    eng_fire12_offload_2500.ogg    lifting off / engine braking at 2500 rpm
    eng_fire12_startup.ogg  eng_fire12_shutdown.ogg  eng_fire12_limiter.ogg

The game reads the RPM straight from the file names, crossfades the two loops
either side of the current revs and pitch-shifts them, and blends on-load and
off-load by throttle. So you can record your own car at whatever RPM points
you like (2 to 4 seconds each, held steady), name them this way, and the game
uses them. For electric sets the number is km/h instead of RPM.
`python3 audio/tools/preview_drive.py fire12` renders a short drive from a
set exactly as the game mixes it, so you can hear a set without Godot.

Exhaust upgrades are their own sets: `fire12sport`, `fire12straight`.

## What's here

| Folder | What | Docs |
| --- | --- | --- |
| `engine/` | 9 engine families (Fire 1.2, 1.4 16v, TwinAir, T-Jet, classic twin, Giardiniera flat twin, classic Abarth, electric, Abarth 500e generator), each petrol one with sport and straight-through exhausts (the classics also with the Abarth megaphone), plus extras (gear clunks, turbo, blow-off, backfires, gearbox whine, carb gulp) | [engine](docs/engine.md) |
| `engine/sedan`, `diesel`, `busdiesel`, `traffic/` | Other traffic: car, ute/van and bus engines, horns, bus air brake, trains | [traffic](docs/traffic.md) |
| `car/` | Doors, horns, indicators, wipers, radio clicks, windows, roof, cargo... | [car](docs/car.md) |
| `tyre/`, `impact/` | Rolling on each surface, skids, splashes, road features, crashes, street objects | [tyre](docs/tyre.md), [impact](docs/impact.md) |
| `weather/` | Rain outside and on the roof, thunder, wind, cicadas, drips | [weather](docs/weather.md) |
| `amb/` | Perth ambience beds by zone (day, night, rain, late night and dawn), place layers for points of interest (beach, lookout, bush, Elizabeth Quay, river bank, car park; day and night) and wildlife one-shots | [amb](docs/amb.md) |
| `oddity/` | Night oddities: the midnight station, static whispers, river lights | [oddity](docs/oddity.md) |
| `home/`, `garage/` | The townhouse and garage/servo/car-wash activities | [home](docs/home.md), [garage](docs/garage.md) |
| `ui/` | Menu, jobs, checkpoints, stingers | [ui](docs/ui.md) |
| `music/` | Main theme, Radio Cinquecento, Notte FM, mission and time-trial loops, stingers | [music](docs/music.md) |
| `scripts/` | The game code (below) | |
| `tools/` | Python generators that make every file here | |
| `tests/` | Headless tests and a scripted demo drive | |

## Regenerating

Everything generated is reproducible (fixed random seeds):

    python3 audio/tools/gen_engines.py        # or: gen_engines.py fire12 tjet
    python3 audio/tools/gen_car.py            # car foley
    python3 audio/tools/gen_tyres.py          # tyres, surfaces, impacts
    python3 audio/tools/gen_traffic.py        # traffic engines, horns, trains
    python3 audio/tools/gen_weather.py
    python3 audio/tools/gen_ui.py
    python3 audio/tools/gen_home.py
    python3 audio/tools/gen_steps.py          # tile, concrete, mulch, gravel steps
    python3 audio/tools/gen_garage.py
    python3 audio/tools/fetch_sources.py && python3 audio/tools/gen_amb.py
    python3 audio/tools/gen_music.py

The horns, the cat and the midnight voices are cut from CC0 recordings, so
run `fetch_sources.py` before regenerating them; without the downloads the
horn generators keep the committed horns.

Needs Python 3 with numpy, scipy, soundfile and pyloudnorm, plus ffmpeg (and
fluidsynth with the FluidR3_GM soundfont for music). Set `AUDIO_MASTERS=1` to
also write 24-bit WAV masters to `build/audio_masters/`. **Re-running a
generator overwrites its files**, including any you replaced, so after you
start swapping in your own recordings, regenerate only what you need.

## Game code (`scripts/`)

- **`Audio` autoload** (`audio_manager.gd`): finds sounds by name,
  `Audio.play_at("impact/impact_heavy", pos)`, `Audio.ui("ui_menu_move")`,
  `Audio.play_music("mus_main_theme")`, `Audio.start_mission_music()` and
  `Audio.set_mission_intensity(0..1)`, `Audio.sting("complete")`,
  `Audio.set_bus_volume("Music", 0.8)` for the settings menu. It also sets up
  the buses and muffles the world when the camera is inside the car.
  Quit with `Audio.quit_game()`, not `get_tree().quit()`: it stops every
  player, drops every stream and gives the mixer a moment to let go of the
  playbacks first (an Ogg playback still in the mixer at exit can crash on
  quit). SaveGame.quit_cleanly() calls it as its last step.
- **`EngineAudio`**, **`TyreAudio`**, **`CarSounds`**: nodes under the car's
  `Audio` node. They read `get_telemetry()` and the car's signals
  (docs/HOOKS.md). The engine set follows the fitted parts: a sport or twin
  exhaust gives `<family>sport`, the Abarth quad gives `<family>straight`, the
  classics' found Abarth megaphone gives `<family>megaphone`, and
  the 1.4 and T-Jet swaps change the family (`ENGINE_PARTS` and
  `EXHAUST_PARTS` in `engine_audio.gd`). The engine cuts out when the tank
  runs dry and starts again after fuel goes in. CarSounds has door,
  seatbelt and key sounds per car family (docs/car.md); getting in and out
  on foot plays them.
- **`Audio.hooks`** (`game_hooks.gd`): the event sounds, driven by the other
  autoloads' signals so their code has no audio calls. Job accepted,
  pick-up, checkpoints, delivery and trial finishes, new best time, money,
  challenges and tier unlocks, discoveries, saving; cargo sliding or
  clinking in the back when you hit something mid-delivery; the low-fuel
  chime; fuel going in and the car wash; the impact wrench when a part is
  fitted; workshop room tone; menu clicks on every button. Deliveries keep
  the radio until the last 30% of the par time, then the mission tension
  loop fades in and builds; time trials play the time-trial loop with
  countdown ticks before each medal time. The radio dips under both.
- **The map and the townhouse**: on the Perth map the ambience bed follows
  the camera through Northbridge, the CBD, Kings Park, the river and the
  suburbs (rough areas in `ZONE_AREAS` in `ambience_manager.gd`, until the map
  carries real zones). Near one of the map's points of interest (a beach,
  a lookout, the quay, the river bank, a quiet car park, a servo at night)
  its place layer fades in over the bed. The townhouse's doors, going to bed (with the "day
  ends" sting) and the shed being unlocked have their sounds.
- **Footsteps** (`footsteps.gd`, `FootstepAudio`): add one as a child of
  whatever walks (the player on foot) and it plays a step every stride for
  the floor underfoot: timber, carpet, stairs, tile, brick, concrete, mulch
  or gravel. It reads a collider's `surface` metadata, or for the
  townhouse's imported floors the material of the face it's standing on
  (`MATERIAL_SURFACES`), so new floors need only a material name added there.
- **Traffic** (`traffic_audio.gd`, made by `Audio.hooks` when the city's
  TrafficManager appears): pooled engine voices on the nearest cars (4),
  utes and vans (2) and buses (2), our horns on every vehicle, the bus air
  brake when a bus pulls up, trains rumbling past with their horn at level
  crossings, crossing bells while the booms are down, and pedestrian beeps
  at signals. Everything plays on the Vehicles bus.
- **Changing car**: `EngineAudio.CAR_SETS` maps each car in
  `data/cars/cars.json` to its engine set, and the horn style follows (classic
  meep, Abarth blare, modern).
- **Volume settings**: `Settings.volume_master`, `volume_effects`,
  `volume_music` and `volume_radio` (0..1, sliders in the pause menu's
  Sound section, next to an "Open My Music folder" button).
- **`Audio.radio`** (`radio.gd`): Radio Cinquecento, Notte FM, My Music and
  (after midnight only) an unlisted station. The two built-in stations run
  like real broadcasts: each keeps its place while you listen elsewhere,
  plays the songs its `music/programme_<station>.json` tags for the time of
  day (morning, day, evening, night, late), drops one of its idents
  (`mus_ident_<station>_NN`) after every two songs, and plays the time pips
  before the next song at 6:00, 12:00 and 18:00. Keys: `.` / `,` change station,
  `/` on/off, `M` next track, `N` next playlist.
- **`Audio.ambience`** (`ambience_manager.gd`): `set_zone("kingspark")` for
  the map; weather and time come from the `Weather` and `GameClock`
  autoloads, with thunder following lightning at the speed of sound.

## My Music

The game makes a `Music` folder next to the save files:

- Windows: `%APPDATA%\Godot\app_userdata\500\Music`
- macOS: `~/Library/Application Support/Godot/app_userdata/500/Music`
- Linux: `~/.local/share/godot/app_userdata/500/Music`

(the pause menu's "Open My Music folder" button opens it.) Drop MP3, OGG or WAV files in. Each
subfolder becomes a playlist; "All music" plays everything. Tune the radio to
My Music: tracks play through the car-stereo filter, shuffle by default, and
carry on faintly when you step out. Track names come from the files' tags, or
from file names like `Artist - Title.mp3`. Spotify was ruled out in the plan, so
the folder is the way.

## Tests

    godot --headless --path . res://audio/tests/test_audio.tscn

checks the buses, every engine set, the engine node, tag reading and the My
Music folder (with real MP3/OGG/WAV fixtures). CI runs it. To hear it all in
the actual game:

    godot --path . --fixed-fps 60 --write-movie build/demo.avi --script res://audio/tests/demo_drive.gd
    godot --path . --fixed-fps 60 --write-movie build/hooks.avi --script res://audio/tests/demo_hooks.gd

(the second is the game-event sounds: fuel, a new exhaust, a delivery, a time
trial, the car wash).
