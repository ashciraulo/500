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
python -m osm_import.build --stage 1 --jobs 4  # build four tiles at a time
```

Build every stage in one run (`--stage 1 --stage 2 ...`) when the terrain or
road heights change: each run fits the ground over its own area, so tiles
from separate runs can disagree slightly where they meet.

Then in Godot, or headless: `godot --headless --path . --import` and run the
game. `tools/map_test.gd` checks the spawn and streaming; `tools/map_screenshot.gd`
renders a few views (needs a display or `xvfb-run`).

## How it works

1. **extract.py** reads roads, paths, rail, buildings, land use and water from
   the `.pbf` (pyosmium) and projects them to metres around the origin
   (Transverse Mercator at Little Shenton Lane).
2. **terrain.py** resamples the elevation tiles onto a 5 m grid, filtering out
   buildings and trees left in the surface model.
3. **heights.py** gives every road/rail/path node a height. Ways get extra
   nodes every 5 m, the DEM is sampled along them (among buildings, from a
   "bare earth" copy with building mounds opened out) and smoothed along the
   network over about 30 m of road, measured in metres, so profiles curve
   gently instead of following every lump in the surface model. Bridges are
   lifted, tunnels and cuttings sunk, with ramps at a maximum grade; streets
   under a bridge keep their headroom; the two halves of a divided road and
   roads whose asphalt touches are tied level.
4. **build.py** fits the terrain to the roads: under each road the ground
   takes the road's height (level cross-sections), among buildings the ground
   is interpolated from the roads around it (the DEM there is a surface model
   full of building mounds), open ground and water keep the DEM, and every
   road edge eases back over at least 12 m (embankments and cuttings get
   wider side slopes). Then for each 500 m tile it builds: land
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

`python -m osm_import.roughness [--region R | --tiles ...] [--dir DIR]` walks
every road in built tiles and reports bumps, kinks, crossfall, tile-seam
steps and low bridges, with the worst spots (Godot x, z).
