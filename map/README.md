# Perth map

The drivable city, generated from OpenStreetMap by `tools/osm_import`.

| Path | What it is |
| --- | --- |
| `perth_map.tscn` | Drop-in map node (`MapStreamer`). `scenes/main.tscn` uses it with `target_path` pointing at the car. |
| `scripts/map_streamer.gd` | Streams 500 m tiles around the target, adds colliders near it, runs the night street-light pool. |
| `scripts/tile_loader.gd` | Decodes a `.p5t` tile into meshes, multimeshes and collision data. |
| `scripts/map_overview.gd`, `shaders/overview.gdshader` | The far backdrop: a coarse painted heightfield drawn past ~700 m. |
| `scripts/map_props.gd` | Low-poly trees and street lights (override any with `props/<kind>.tres`). |
| `materials/`, `textures/` | Generated PS1 `ShaderMaterial`s and 64 px textures, one per surface type. Safe to hand-edit, but `osm_import` rewrites them on every build. |
| `tiles/` | Generated: `<i>_<j>.p5t` tiles, `<i>_<j>.p5r` traffic road data, `overview.p5o`, `index.json` (spawn, home, markers, landmarks, tile list). |

## World coordinates

- 1 unit = 1 metre. X = east, Z = south (−Z is north), Y = up.
- Origin: the townhouses on Little Shenton Lane, Northbridge. The player's
  townhouse (`scenes/home/shenton.tscn`) is placed at its real spot and the car
  starts in its carport (`MapStreamer.get_spawn_transform()`, `get_home()`).
- Tile `i_j` covers east `i*500 .. (i+1)*500` and north `j*500 .. (j+1)*500`,
  so its node sits at `(i*500, 0, -j*500)`. `MapStreamer.tile_at(pos)` converts.

## For other systems

- **Colliders** are `StaticBody3D`s on layer 1 (buildings also on layer 2) with
  `surface` metadata: asphalt, concrete, brick (red paving), gravel (rail
  ballast), dirt, grass, sand.
- **Night**: the map is in the `night_lights` group. `set_night_amount()` turns
  on lit windows, street lamp heads, and moves a pool of real lights to the
  street lights nearest the car.
- **Signals**: `map_ready`, `tile_loaded(key)`, `tile_unloaded(key)`.
- **Home, job sites and workshops**: `index.json` lists the townhouse and the
  `JobSite` / `WorkshopSpot` markers from `docs/HOOKS.md`; the streamer adds
  them once at start (they don't stream). Sites outside the built map appear
  when a later region covers them. Positions live in `tools/osm_import/config.json`.
- **Traffic**: each tile has a `.p5r` with its roads, junction controls,
  rail, stations and bus stops in the `docs/TRAFFIC.md` format. The streamer
  hands each one to `add_network` the first time the tile loads.
- **Points of interest**: `get_pois(kind := "")` lists places worth driving
  to, from `index.json` "pois": `lookout` (OSM viewpoints plus hand-picked
  ones), `beach` (stop in its car park), `servo`, `drive_thru`, `quiet_spot`
  (hand-picked places to park and watch the city), `fishing` (hand-picked
  jetties, groynes and foreshores; `at` is the jetty's far end or the water's
  edge), `birding` (reedbeds, lake edges and marshes; `at` is the habitat)
  and `landmark` (the hand-built ones below). Each has a stable `id`,
  `name`, `suburb`, `p` (where to stop the car), `yaw` (facing there) and
  `at` (the feature). Hand-picked stops live in
  `tools/osm_import/config.json` "pois"; ones off the built map appear when a
  region covers them. Spots with `"hidden": true` are for the player to find:
  the field journal keeps them off its map until you are close.
- **Habitats**: `map/tiles/habitats.json` lists OSM wetlands and beaches, one
  per line: `id` (`wetland_<osm id>` or `beach_<osm id>`, stable), `kind`,
  `name` (may be empty), `wetland` (reedbed, marsh, swamp, tidalflat... when
  OSM says), `area` (m²) and `outline` (x/z), for the birds that live there.
- **Lakes**: `water_level_at(pos)` is the water surface height of the lake or
  pond under `pos`, or NAN; `get_lakes()` lists them (name, level, outline in
  x/z). From `map/tiles/lakes.json`, one lake per line. The river and the sea
  are at height 0 and aren't listed. Jetties and groynes
  OSM draws as a line are built as walkable decks like the ones drawn as
  areas.
- **Landmarks**: the Bell Tower, Elizabeth Quay Bridge, Matagarup Bridge,
  Optus Stadium, the State War Memorial, the Round House, the Indiana Tea
  House, Council House, the DNA Tower (its spiral stairs are walkable), RAC
  Arena, Fremantle Markets and Scarborough's Rendezvous tower are low-poly
  models built by `tools/osm_import/osm_import/landmarks.py` on their OSM
  footprints, in the tiles' `landmarks` mesh.
- `get_landmarks()` returns suburb and square names with XZ positions, for a
  map screen or GPS later.

## What's built

Stage 5 adds the places the field journal needs: Herdsman Lake, Bold Park,
Point Walter, Alfred Cove, Trigg and Fremantle's North and South Moles
(106 tiles, 647 in all). The Indian Ocean is built from OSM's coastline, with
a sea floor that shelves away from the sand, and jetties or groynes OSM lacks
can be placed by hand in `tools/osm_import/config.json` "hand_decks" (the
Cottesloe groyne).

Stage 2 adds Leederville, West Leederville, Subiaco, East Perth, Claisebrook,
Optus Stadium, Victoria Park, Burswood and the Causeway (232 tiles in all).
60 badges (`Collectible`) are shared out per region in `config.json`, so
building a new region never moves one already placed.

### The first slice

CBD, Northbridge, Elizabeth Quay, Kings Park, the Narrows Bridge and the South
Perth foreshore (120 tiles, about 6 × 5 km). Roads are draped on real terrain,
bridges are lifted with ramps, the Graham Farmer Freeway tunnel is sunk, and
the river has a bed under the water surface.

Known simplifications: one asphalt look for all roads, flat or gabled roofs
only, building heights guessed from size and zone where OSM has no levels,
no traffic lights or signs yet.

## Regenerating

See `tools/osm_import/README.md`. Tiles are committed so the game runs without
Python; regenerate only when the importer or style changes, because each full
rebuild adds about 37 MB to the repository history.

## Credits

Map data © OpenStreetMap contributors, available under the Open Database
License (ODbL). Elevation: Mapzen/AWS Terrain Tiles (SRTM, Geoscience
Australia and others). Both need to appear in the game's credits.
