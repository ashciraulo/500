# osm_import

Turns OpenStreetMap data for Perth into the game's map tiles (`map/tiles/`).
It's a repeatable script: change a rule, rebuild, and the whole city updates.

## Setup

Python 3.11+:

```sh
cd tools/osm_import
pip install -r requirements.txt
```

The first run downloads the BBBike Perth extract (~40 MB) and elevation tiles
into `cache/` (git-ignored).

## Build

```sh
python -m osm_import.build --list              # regions and tile counts
python -m osm_import.build --region first_slice
python -m osm_import.build --stage 2           # every stage-2 region
python -m osm_import.build --tiles 0_-1 1_-1   # just a few tiles
python -m osm_import.build --region first_slice --only 0_0 0_-1
                                               # rebuild a few tiles of a region (and the index)
python -m osm_import.build --region first_slice --traffic-only
                                               # just the traffic road data (traffic.py)
python -m osm_import.build --refresh ...       # re-download the OSM extract
```

Then in Godot, or headless: `godot --headless --path . --import` and run the
game. `tools/map_test.gd` checks the spawn and streaming; `tools/map_screenshot.gd`
renders a few views (needs a display or `xvfb-run`).

## How it works

1. **extract.py** reads roads, paths, rail, buildings, land use and water from
   the `.pbf` (pyosmium) and projects them to metres around the origin
   (Transverse Mercator at Little Shenton Lane).
2. **terrain.py** resamples the elevation tiles onto a 5 m grid, filtering out
   buildings and trees left in the surface model.
3. **heights.py** gives every road/rail/path node a height: terrain-following,
   lifted for bridges, sunk for tunnels and cuttings, with ramps spread along
   connected ways at a maximum grade.
4. **build.py** sculpts the terrain to fit roads (flat cross-sections,
   embankments, cuttings, riverbeds), then for each 500 m tile builds: land
   cover ground, road and footpath surfaces (clipped to the grid so they hug
   the terrain), kerbs, lane markings (left-hand traffic), bridge decks with
   parapets and piers, tunnel boxes, rail, extruded buildings with facade
   bands and roofs, trees and street lights.
5. **tilewriter.py** quantises and writes each tile as a brotli-compressed
   Godot Variant (`.p5t`, magic `P5TB`) that `map/scripts/tile_loader.gd`
   decodes natively. Tiles built before stage 4 are zlib (`P5TZ`) and are
   still read; they aren't rewritten, since every rewrite adds a full copy of
   the tile to git history.
6. **traffic.py** writes each tile's road network for the traffic system
   (`.p5r`, docs/TRAFFIC.md): junction-split roads, signals, rail, stations,
   bus stops and, from **parking.py**, car parks, kerbside parking and bays.
   Opposing one-way carriageways of one street are pushed apart where OSM
   draws them closer than their lanes need.
7. **overview.py** paints the far backdrop and adds every building 24 m or
   taller as a plain block, so the skyline shows from across the city (lit
   windows at night); **textures.py** generates the placeholder textures and
   PS1 materials.

`config.json` also places the player's townhouse (its block is levelled and
OSM's buildings, roads and trees on it are dropped), the job sites and the
workshop bays (**places.py**; lat/lon entries snap onto the nearest road).
Tile names starting with a minus need `--only=-1_0` or `--tiles=-1_0`.

Style knobs live in `styles.py` (road widths, land cover, building heights and
facades) and `textures.py` (colours, patterns).

## Regions

`config.json` lists the build regions from the plan: stage 1 is the first
slice; stage 2 adds Leederville/Subiaco, East Perth and Victoria Park; stage 3
adds the Stirling Highway, Canning Highway and coast road corridors (tiles
within a buffer of the named roads); stage 4 adds Mount Lawley, Osborne Park
(reached up Oxford St and Scarborough Beach Rd, which runs on to the coast)
and the Guildford Rd corridor to the Guildford antique shops.

## Tests

```sh
python -m pytest -q tests
```
