# Contributing

## Folder layout

| Folder | What goes in it | Owner |
| --- | --- | --- |
| `scenes/` | Godot scenes (`.tscn`). `main.tscn` is the game; `vehicles/`, `world/`, `ui/` hold the rest. | Core |
| `scripts/` | GDScript, mirroring `scenes/`: `vehicle/`, `camera/`, `world/`, `ui/`, `render/`, plus `autoload/` for global singletons. | Core |
| `shaders/` | Shared shaders. `ps1_surface.gdshader` is the world material; `lofi_post.gdshader` is the screen filter. | Core |
| `art/models/` | Blender source (`.blend`), the Python scripts that build them, and exported `.glb` files. | Models |
| `art/textures/`, `art/materials/` | Small, low-res textures (128 px or less is the target) and saved materials. | Models |
| `map/` | OpenStreetMap extracts, the import code that turns them into Godot scenes, and the generated Perth map scenes. | Map |
| `audio/` | Sound effects, ambience, engine synthesis code, music player. | Audio |
| `data/` | Game data as Godot resources, e.g. `data/parts/` for car upgrades. | Core |
| `docs/` | Design notes and interface docs. | Everyone |
| `tools/` | Headless scripts: tests, importers, generators. | Everyone |

Stay inside your folder where you can. If you need a change in someone else's
area, keep it small and say so in your PR.

## Conventions

- **Godot 4.3+, GDScript, Compatibility renderer.** The PS1 look doesn't need
  Forward+, and Compatibility runs on almost anything.
- `snake_case` file names, `PascalCase` node names, static typing in scripts.
- Tabs for indentation in GDScript and shaders (Godot's default).
- **World materials use the PS1 shader**, so everything wobbles and gets wet
  together. In code use `PS1Material.make(colour)` (see
  `scripts/render/ps1_material.gd`); in imported models, set the material to
  a `ShaderMaterial` with `shaders/ps1_surface.gdshader`.
  Set `wet_response = 1` on roads and pavements so they shine in the rain.
- **Colliders declare their surface** with metadata so the car picks grip:
  `body.set_meta("surface", &"asphalt")`. Known surfaces: asphalt, concrete,
  brick, gravel, dirt, grass, sand (see `CarController.SURFACES`).
- Lights that should come on at night join the `night_lights` group.
- Keep polygon counts and textures low; the game renders at about 240 lines.

## Swapping in real assets

- **Car model**: the `Body` node in `scenes/vehicles/fiat_500_pop.tscn` is the
  imported `art/models/cars/pop/pop.glb` with `scripts/vehicle/car_body.gd`
  (PS1 materials, steering wheel, lamps, respray). Wheel glbs sit under
  `Wheels/<Wheel>/Visual/Spin` (axle along X). See `art/models/README.md`.
  Wheel anchors sit 0.05 m above the wheel centre at rest height; if you move
  them, keep the suspension numbers on the car in step.
- **Map**: replace the `TestGrid` node in `scenes/main.tscn` with the map
  scene, and move the `Car` to the spawn point (15 Little Shenton Lane).
- **Audio**: see `audio/README.md`. Sounds are found by file name, so a
  recording dropped in with the same name (any of .ogg/.wav/.mp3) replaces the
  generated one. Buses (`default_bus_layout.tres`): Music, UI, Radio, Cabin,
  and World (muffled when the camera is inside the car) with Engine, Tyres,
  SFX, Ambience and Weather under it.

## Before you push

Run the smoke test (see README). CI runs it too and a red build blocks merging.
