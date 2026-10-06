# Traffic and city life

Everything that moves around the player: cars, utes, vans and Transperth
buses driving on the left, traffic lights, give-ways, stop signs and
roundabouts, Transperth trains with boom gates at level crossings, and people
walking the footpaths, and parked cars. The code lives in `traffic/`.

| File | What it does |
| --- | --- |
| `traffic/scripts/traffic_graph.gd` | `TrafficGraph`: turns road data into lanes, junction connectors, signal controllers, footpaths and rail. |
| `traffic/scripts/traffic_manager.gd` | `TrafficManager` node: spawns, drives, pools and despawns everything near the player. |
| `traffic/scripts/traffic_parking.gd` | `TrafficParking`: parked cars on the map's parking spots, filled by time of day. |
| `traffic/scripts/traffic_models.gd` | Low-poly vehicle, train, people and street furniture meshes, built in code. |
| `traffic/scripts/traffic_vehicle.gd`, `traffic_pedestrian.gd`, `traffic_train.gd` | Per-agent state. |
| `traffic/scripts/traffic_test_networks.gd` | Test road networks: one matching the test grid, one sandbox suburb. |
| `traffic/sandbox/` | `traffic_sandbox.tscn`: the full game on the sandbox suburb. Open it and press F6. |
| `tools/traffic_test.gd` | Headless test (CI runs it). |
| `tools/traffic_screens.gd` | Screenshots of the sandbox (needs xvfb). A second argument renders only the shots whose names contain it. |
| `tools/traffic_map_test.gd` | Soak test on the Perth map: a few minutes of rush hour at home, two CBD junctions and both freeways. Too slow for CI; run it after changing driving rules. |
| `tools/traffic_map_screens.gd` | Screenshots of traffic on the Perth map (needs xvfb), with the same shot filter. |

`scenes/main.tscn` has a `Traffic` node (a `TrafficManager`) under `World`.
The Perth map hands it each tile's roads as the tile streams in. Scenes with
the old test grid get a network matching the grid's streets instead.

## How it works

- **Only near the player.** Vehicles spawn out of sight between 110 m and
  260 m away and despawn past 330 m; people between 35 m and 140 m
  (despawn 190 m); trains 450 to 900 m away. Despawned nodes are hidden and
  reused. Everything runs in one `_physics_process` loop (about 1.5 ms per
  frame for 50 cars and 40 people).
- **Density** is cars per kilometre of lane within the spawn radius, scaled
  by an hourly curve (peaks 7-9 am and 4-6 pm, nearly empty at 3 am) and the
  weather (storms thin it out). People follow their own curve (lunchtime
  peak, Northbridge evenings) and mostly stay in when it rains.
  `density_scale` and `pedestrian_scale` on the manager are there for a
  settings slider. Arterials get more of the cars than back streets
  (`KIND_SHARE`: a residential street carries about a third of what a
  primary road does per lane), and parts of town have their own rhythm
  (`AREAS`): the CBD is busy in working hours and quiet at night, and
  Northbridge fills with people in the evening.
- **The week** (day 1 is a Monday, as in `Garage.weekday()`). Weekends have
  no rush hours and a busy late morning to mid afternoon; Sundays are a bit
  quieter than Saturdays, and the office crowd stays out of the CBD. Friday
  and Saturday nights (6 pm to 4 am, so 1 am Saturday is still Friday night)
  bring out more cars and a lot more people, Northbridge most of all; the
  people cap rises by `night_out_people_cap` for them. Office car parks are
  half empty at the weekend and fill up again on a night out.
  `TrafficManager.hour_density(day, hour, people)`, `is_weekend(day)` and
  `is_night_out(day, hour)` are static, for anything else that wants the same
  rhythm.
- **Parked cars** fill the parking spots the map hands over. Car parks fill
  up in working hours and empty out overnight; street spots are fullest
  overnight. Which spots are taken is redrawn every two game hours, and a
  spot only changes while the camera isn't on it. Parked cars are solid to
  the player, and spots within 3 m of a lane are ignored.
- **Keep-clear boxes.** Queues stop short of a keep-clear box rather than
  across it, and nobody parks in one. The end of Little Shenton Lane on
  James St, where the player drives out, has one (`keep_clear_spots` on the
  manager); the map can add more with `keep_clear` in the road data.
- **Emergency vehicles.** A few times an in-game day (`emergency_interval`,
  in game hours) there's an emergency call. Most are only a siren far off
  across the city (the `distant_siren` signal, 350-700 m away, which the
  sound plays from there); about a third (`emergency_drive_by`) send a
  police car, ambulance or DFES fire truck along a main road towards the
  player from out of sight, lights flashing and siren on. Its call ends
  (siren and lights off) once it has gone past and is heading away, or
  after 75 s; out of sight it just goes. Cars ahead of it
  on its way pull over to the left and stop (never inside a junction), and
  it passes them on the right; it slows right down at red lights and edges
  through when the junction is clear. `spawn_emergency(near, type)` sends
  one on demand; `emergencies` lists those on the road.
- **Cyclists** ride on residential streets, tertiary and secondary roads,
  service lanes and anything the map flags `bike_lane`, about four times as
  often on a bike lane (`bike_share` sets the base share). They keep to the
  kerb, potter along at 15 to 25 km/h, and cars swing out round them. Fewer
  ride at night, more at weekends, nobody in the rain, and never on
  freeways or highways. They come on top of the car count.
- **Roadworks.** Now and then (`roadworks.site_chance`) a long multi-lane
  road has one lane coned off for three days, then the crew moves on. Each
  site has a cone taper, a barrier, a ROADWORK sign 60 m back, a works ute
  with its beacon going and a couple of workers in hi-vis during the day.
  Traffic in the closed lane merges out before the taper (waiting for a gap
  if it has to, and the next lane lets it in), and everyone slows to
  40 km/h past the works. Which roads have works on which day is a pure
  function of the road and the day, so the works are still there when the
  player comes back; sites only appear or go out of sight. The cones are
  light rigid bodies the player can knock flying (with a bonk).
  `roadworks.add_site(road, fwd, k, s0, s1)` closes a lane on demand.
- **Wildlife.** Magpies on any grass in the daytime, ibis around the river
  foreshore, Hyde Park, Russell Square and the lakes, and now and then a
  kangaroo or two grazing in Kings Park at dusk and dawn. They appear out of
  view on grass, peck about and wander, and clear off when the player comes
  close: birds fly, kangaroos bound away. A magpie warbles now and then.
  `wildlife.spawn_group(kind, near, count)` puts some down on demand.
- **The river** (`boats`, TrafficBoats). The Elizabeth Quay to Mends Street
  ferry runs to a timetable on the game clock (`TrafficBoats.ferry_state(hour)`,
  first sailing 6:48, last 21:18), sounds its horn leaving the jetty and has
  lit windows after dark. Yachts and tinnies sail Perth Water, with rowing
  eights early in the morning; plenty on a fine weekend afternoon, hardly any
  at night or in the rain. Boats only go where the overview map is water
  (`boats.water_at(p)`), so they never run aground. Only on the Perth map.
- **Kerbside** (`kerbside`, TrafficKerbside). Couriers double-park in the
  kerb lane of multi-lane city streets (weekdays 7 to 5:30, Saturday
  mornings) with their hazards on while they run a parcel in; traffic merges
  round them like roadworks, and they drive off when done. Taxis queue on a
  rank by each station; when a train comes in, the front one or two take a
  fare and pull out, and the queue shuffles up. Parking inspectors walk the
  city's kerbs (Monday to Saturday, 8 to 6), stopping at parked cars. If the
  player leaves their car in a traffic lane for a minute ($120) or in a
  street bay for five ($70), one walks over and books it: the fine comes out
  of the Wallet, `parking_fines` goes up in Progression, the HUD shows it and
  a ticket sits under the wiper until the player gets back in. Never within
  90 m of home or 35 m of a job site.
- **School zones** (`schools`, TrafficSchools). On school days, 7:30 to 9
  and 2:30 to 4, the streets within about 110 m of each school drop to
  40 km/h (`Lane.zone_speed`; `lane.limit()` is the limit right now), with
  flashing 40 signs on the way in. At the nearest crossing without lights a
  crossing guard waits with the kids, then steps out with the STOP lollipop
  (traffic stops at the line) and sees them across. Parents stop in the kerb
  lane with their hazards on while a kid hops out; on one-lane streets
  traffic queues behind them. Schools come from the road data's `schools`.
  `schools.zone_limit_at(p)` gives the zone limit at a point (0 when
  none), for the HUD or a speeding fine.
- **Game days** (`events`, TrafficEvents). Most weekends, and some Thursday
  and Friday nights, there's footy (now and then a concert) at Optus
  Stadium: `events.event_on(day)` gives the fixture. For two and a half
  hours before the start, fans in their team's colours walk in from Perth
  Stadium station, the Matagarup Bridge (when the road data has it as a
  footway named "Matagarup Bridge") and the streets round Burswood, through
  footways to the gates, and go in. Six-car trains run more often, event
  buses turn up, and the roads within about 2 km get up to 90% busier. You
  hear the crowd during the game; at the final siren it all goes the other
  way. Fans are ordinary pedestrians with a route
  (`manager.spawn_walker(route, s, dir, leave_at_end)`, with
  `graph.ped_path(from, to)` for the route). Only on the Perth map. Map
  footways are split where they meet each other and their loose ends are
  tied to the nearest footpath, so OSM paths that join mid-way still route.
- **The night shift** (`night`, TrafficNight). From 11pm to 5am a street
  sweeper creeps along the city kerbs at about 12 km/h, brooms turning and
  amber beacons flashing. On bin day (Tuesday) wheelie bins (red lids for
  rubbish, yellow for recycling) line the residential kerbs from Monday
  evening, and from 5:30 to 10 the bin truck works along them, stopping at
  each one to lift it over with its side arm. Thursday to Saturday nights,
  7pm to 2am, food vans park up in Northbridge's street bays, hatches lit,
  with a few people queuing. Working vehicles use `TrafficVehicle.max_speed`,
  `keep_lane` and `service_stops` ({ lane, s, dwell } stops, marked `done`).
- **Bunch rides** (`rides`, TrafficRides). Saturday and Sunday mornings, 6
  to 10 (and one early bunch on weekdays, 5:30 to 7), clubs of road cyclists
  in matching kit ride the river loop: Mounts Bay Road, Riverside Drive, Mill
  Point Road, the South Perth Esplanade, Kings Park Road, Lake Monger Drive.
  Eight to fourteen riders at 31 to 35 km/h, staggered two abreast, each
  sitting a wheel behind the one in front (`TrafficVehicle.follow`) and
  taking the same turns; cars queue behind. None in the rain.
- **Models.** Vehicles use the modelled bodies in
  art/models/vehicles/traffic/<type>.glb (hatch, sedan, suv, ute, van, taxi,
  bus, police, ambulance, fire, carriage_cab, carriage_mid) and the night
  shift's in art/models/props/city/ (sweeper, bin_truck, wheelie_bin,
  food_van), falling back to the code-built ones when a file is missing.
  Traffic recolours their "Paint" and "Livery" materials, lights HeadL/HeadR,
  TailL/TailR and IndL/IndR, and flashes LightBar/Red and Blue (Beacon/A and
  B on the night shift).
- **Bike paths** (`paths`, TrafficPaths). The map's `cycleways` join the
  footpath network as paths marked `cycle` (people walk them too). People
  ride them at an easy pace and joggers run them, most from 5:30 to 9 and
  4:30 to 7:30, fewer midday (more riders at weekends), the odd jogger at
  night, hardly anyone in the rain. They keep left, pull out to pass, and
  stop short of the player on foot.
- **Driving** uses the intelligent driver model: each car keeps a safe gap to
  whatever is ahead (the car in front, a stop line, a person, the player).
  Cars slow for bends, change lanes to pass slow traffic, and drive a little
  slower and further apart in the wet.
- **Junctions.** Left turns come from the kerb lane, right turns from the
  lane by the centre line. The through road has priority; side streets give
  way, roundabout entries give way to circulating traffic, and right turns
  give way to oncoming traffic. Tagged `stop` junctions need a full stop.
  Nobody enters a junction while someone is crossing their path, while the
  same move is backed up, or when there is no room on the far side.
  Junctions joined by a link too short to wait on (dual carriageway
  crossings, split intersections) are crossed in one go, only when all of
  them are clear. Where two lanes become one, cars zip-merge: whoever is
  nearer the merge goes first. On-ramps and slip lanes take smaller gaps
  than crossings. `signals` junctions run fixed-time phases (green, amber,
  all-red) per axis, with Perth-style yellow-backed lights; signal nodes
  joined by short links, even through plain bends, are one set of lights.
- **Routes** avoid dead ends (a one-way street into a laneway traffic
  doesn't use, or the edge of the loaded map) whenever there's another way,
  and cars don't spawn heading into one.
- **Trains** are 3-car sets (6 in rush hour) that run on the left track where
  there are two, stop at stations for about 14 s, and close the boom gates at
  level crossings. Crossings are found wherever rail and road meet at the
  same height.
- **Buses** run the bus routes the map hands over, keep to them, and stop
  only at stops along their route; CAT routes are white with the route's
  colour, the rest Transperth silver and green. Without routes, buses stick
  to bigger roads and stop at every bus stop, and about a third are CATs.
- **The player.** Cars stuck behind the player toot after a few seconds;
  cars facing the player on the wrong side of the road flash, sound the horn
  and swerve towards the kerb; a car the player hits stops with its hazards
  on and leans on the horn. People leap out of the way of a fast car. On
  foot, the player is someone in the road like anyone else: cars stop for
  them (and toot if they stand there), they can't walk through cars, and
  traffic spawns around them instead of the parked car.

## Road data format

The map gives traffic its roads by calling `add_network(data)` on the
`TrafficManager` (it's in the `traffic` group, so
`get_tree().call_group(&"traffic", &"add_network", data)` works), once per
tile as tiles load. The data goes into the road graph a few roads per
physics frame (about `network_budget_ms` each frame), so a new tile never
stalls the game; `add_network(data, true)` or `flush_network()` adds it at
once, and `network_pending()` says whether any is still queued.
Alternatively a node in the `traffic_sources` group with
a `get_traffic_data()` method is read at startup. Roads join across calls on
shared node ids, so use OSM node ids. A tile's roads may arrive before or
after its neighbours': junctions rebuild when new roads reach them (cars
already on them keep going), signal sets join up across tiles without
restarting their cycle, and stations
and bus stops attach to rail and roads that arrive later.

World coordinates in metres, matching the game: -Z north, +X east, +Y up.
`y` is the road surface height.

```gdscript
{
	"nodes": [
		# ctrl: "" | "signals" | "give_way" | "stop" (from OSM highway=*)
		{ "id": 123, "p": [x, y, z], "ctrl": "signals" },
	],
	"roads": [
		{
			"a": 123, "b": 456,                 # node ids at the ends; split ways at every junction
			"pts": [[x, y, z], ...],            # centreline from a to b, including both ends
			"kind": "primary",                  # OSM highway value
			"lanes_fwd": 2, "lanes_back": 2,     # lanes a->b and b->a (oneway: lanes_back ignored)
			"oneway": false,
			"roundabout": false,                # junction=roundabout (implies oneway)
			"speed_kmh": 60,                    # optional; defaults by kind
			"width": 13.6,                      # optional; defaults to lanes x 3.2 m + 0.8 m
			"sidewalks": true,                  # optional; defaults by kind
			"name": "Beaufort Street",          # optional
			"bike_lane": true,                  # optional; cycleway=lane/track on the road
			"id": "osm-way-1234/2",             # optional; stops a road being added twice
		},
	],
	"rail": [{ "pts": [[x, y, z], ...] }],             # one entry per track; endpoints within 2 m join up
	"stations": [{ "p": [x, y, z], "name": "Perth" }],   # railway=station/stop positions
	"bus_stops": [{ "p": [x, y, z] }],                   # highway=bus_stop positions
	"footways": [{ "pts": [[x, y, z], ...], "name": "Matagarup Bridge" }],  # optional extra paths for people (event paths, CBD and Northbridge malls and footpaths; malls have "kind": "mall"); name optional
	"cycleways": [{ "pts": [[x, y, z], ...], "name": "Kwinana Freeway PSP" }],  # optional bike and shared paths; name optional
	"schools": [{ "p": [x, y, z], "name": "Highgate Primary School" }],     # optional; amenity=school, for school zones
	"service_roads": [{ "pts": [[x, y, z], ...], "kind": "alley", "name": "Little Shenton Lane" }],  # optional lanes, driveways, car park aisles ("parking_aisle") and tracks for the maps; traffic doesn't drive them; name optional
	# Optional parking spots, clear of footpaths, street lights and driveways.
	# yaw: the way the nose points, radians about +Y (0 faces -Z).
	"parking": [{ "pos": [x, y, z], "yaw": 1.57, "kind": "street" }],  # kind: "street" | "lot"
	# Optional bus routes (OSM route=bus): the ids of the roads they run along.
	# Pieces with the same ref in different tiles join up.
	"bus_routes": [{ "ref": "950", "name": "950 Morley - UWA", "colour": "#0066b3", "roads": ["osm-way-1234/2", ...] }],
	# Optional keep-clear boxes: where a lane or driveway the player uses
	# meets a road traffic drives. Queues wait before them; no parking in them.
	"keep_clear": [{ "p": [x, y, z], "radius": 6.0 }],
}
```

The importer pushes the two sides of a divided road apart where OSM draws
them closer than their lanes need, so oncoming cars don't overlap.

`give_way` and `stop` tags on a node within 35 m of a junction apply to that
junction's approach on that road, which is how OSM usually tags them.

Traffic draws its own traffic lights, boom gates and bus stop shelters; the
map doesn't need to.

## Hooks

`TrafficManager` signals:

| Signal | When |
| --- | --- |
| `vehicle_spawned(vehicle: Node3D, type: StringName)` | A car/bus appeared (or was reused from the pool). `type`: hatch, sedan, suv, ute, van, taxi, bus, bike, or police, ambulance, fire (on a call). |
| `vehicle_despawned(vehicle: Node3D)` | It was hidden and pooled. |
| `horn(vehicle: Node3D, duration: float, is_bus: bool)` | A vehicle sounded its horn. |
| `pedestrian_startled(position: Vector3)` | Someone jumped out of the player's way. |
| `crossing_changed(position: Vector3, closed: bool)` | Boom gates going down (bells start) or up. |
| `train_spawned(train: Node3D)` / `train_despawned(train: Node3D)` | Each carriage is a child of `train`. |
| `signals_changed(position: Vector3)` | A set of lights changed phase. |
| `train_arrived(position: Vector3)` / `train_departed(position: Vector3)` | A train stopped at, or is leaving, a station (its front). |
| `network_changed` | Road data was added. |
| `walker_arrived(ped: TrafficPedestrian)` | Someone with a route (a fan) got there and went. |

`boats` signals `ferry_departed(position)` (the ferry also has a `Horn`
AudioStreamPlayer3D). `kerbside` signals `parking_ticket(fine: int, reason:
String, position: Vector3)` and `taxi_departed(station: String, position:
Vector3)`. `schools` signals `zone_changed(active: bool)` and
`guard_out(position: Vector3)`. `events` signals `event_changed(event_name:
String, phase: int)` (TrafficEvents.Phase: NONE, ARRIVING, ON, LEAVING).
`night` signals `bin_emptied(position: Vector3)` and
`food_van_opened(position: Vector3, food: String)`. `rides` signals
`bunch_started(position: Vector3, club: String, riders: int)`.
`vehicle_spawned` types also include `sweeper` and `bin_truck`.

Sounds the traffic plays when the audio thread adds them (all optional):
`traffic/traffic_guard_whistle` (a crossing guard steps out),
`traffic/traffic_crowd_roar_loop` and `traffic/traffic_crowd_cheer` (the
stadium during a game), `traffic/traffic_bin_tip` (the bin truck empties a
bin), `traffic/traffic_sweeper_loop` (a street sweeper's engine and brushes,
looped on the sweeper), `traffic/traffic_food_van_hum_loop` and
`traffic/traffic_food_van_chatter_loop` (on each food van: generator and
fridges, customers), `traffic/traffic_bunch_loop` (freewheels and chatter,
following the middle of a bunch ride).

Each vehicle body has a child `Audio` (Node3D at the engine) with a `Horn`
AudioStreamPlayer3D on the Vehicles bus playing a placeholder two-tone horn.
Sound code can swap `Horn.stream`, or add engine players under `Audio` on
`vehicle_spawned`. Police cars, ambulances and fire trucks also have a
`Siren` player under `Audio` (a placeholder looping wail, playing while
their call lasts) and a `LightBar` with `Red` and `Blue` lamps the
manager flashes. A vehicle's speed: `manager.vehicles` holds
`TrafficVehicle` objects with `body`, `speed` (m/s), `accel` and `type`.

Physics: vehicles and train carriages are `AnimatableBody3D`s on layer 3
(traffic). The manager adds layer 3 to the player car's collision mask.
Bodies carry metadata `traffic` (the type) and `surface`.

## Swapping in modelled vehicles

`TrafficModels.vehicle_mesh(type)` builds each type's mesh with eight
surfaces in a fixed order: paint, glass/trim, tyres, headlights, tail lights,
left indicators, right indicators, livery. The manager repaints and lights a
vehicle by overriding those surface materials, so a Blender model exported
with the same surface order (vehicle facing -Z, wheels on y = 0) can replace
the generated mesh in `vehicle_mesh()`.
