# Traffic and city life

Everything that moves around the player: cars, utes, vans and Transperth
buses driving on the left, traffic lights, give-ways, stop signs and
roundabouts, Transperth trains with boom gates at level crossings, and people
walking the footpaths. The code lives in `traffic/`.

| File | What it does |
| --- | --- |
| `traffic/scripts/traffic_graph.gd` | `TrafficGraph`: turns road data into lanes, junction connectors, signal controllers, footpaths and rail. |
| `traffic/scripts/traffic_manager.gd` | `TrafficManager` node: spawns, drives, pools and despawns everything near the player. |
| `traffic/scripts/traffic_models.gd` | Low-poly vehicle, train, people and street furniture meshes, built in code. |
| `traffic/scripts/traffic_vehicle.gd`, `traffic_pedestrian.gd`, `traffic_train.gd` | Per-agent state. |
| `traffic/scripts/traffic_test_networks.gd` | Test road networks: one matching the test grid, one sandbox suburb. |
| `traffic/sandbox/` | `traffic_sandbox.tscn`: the full game on the sandbox suburb. Open it and press F6. |
| `tools/traffic_test.gd` | Headless test (CI runs it). |
| `tools/traffic_screens.gd` | Screenshots of the sandbox (needs xvfb). |

`scenes/main.tscn` has a `Traffic` node (a `TrafficManager`) under `World`.
Until the map provides roads it uses a network matching the test grid's
streets, so the prototype already has traffic on the oval and in the town
block.

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
  settings slider.
- **Driving** uses the intelligent driver model: each car keeps a safe gap to
  whatever is ahead (the car in front, a stop line, a person, the player).
  Cars slow for bends, change lanes to pass slow traffic, and drive a little
  slower and further apart in the wet.
- **Junctions.** Left turns come from the kerb lane, right turns from the
  lane by the centre line. The through road has priority; side streets give
  way, roundabout entries give way to circulating traffic, and right turns
  give way to oncoming traffic. Tagged `stop` junctions need a full stop.
  Nobody enters a junction while someone is crossing their path or when there
  is no room on the far side. `signals` junctions run fixed-time phases
  (green, amber, all-red) per axis, with Perth-style yellow-backed lights.
- **Trains** are 3-car sets (6 in rush hour) that run on the left track where
  there are two, stop at stations for about 14 s, and close the boom gates at
  level crossings. Crossings are found wherever rail and road meet at the
  same height.
- **Buses** stick to bigger roads and stop at bus stops. About a third are
  CAT buses in their route colours; the rest are Transperth silver and green.
- **The player.** Cars stuck behind the player toot after a few seconds;
  cars facing the player on the wrong side of the road flash, sound the horn
  and swerve towards the kerb; a car the player hits stops with its hazards
  on and leans on the horn. People leap out of the way of a fast car.

## Road data format

The map gives traffic its roads by calling `add_network(data)` on the
`TrafficManager` (it's in the `traffic` group, so
`get_tree().call_group(&"traffic", &"add_network", data)` works), once per
tile as tiles load. Alternatively a node in the `traffic_sources` group with
a `get_traffic_data()` method is read at startup. Roads join across calls on
shared node ids, so use OSM node ids.

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
			"id": "osm-way-1234/2",             # optional; stops a road being added twice
		},
	],
	"rail": [{ "pts": [[x, y, z], ...] }],             # one entry per track; endpoints within 2 m join up
	"stations": [{ "p": [x, y, z], "name": "Perth" }],   # railway=station/stop positions
	"bus_stops": [{ "p": [x, y, z] }],                   # highway=bus_stop positions
	"footways": [{ "pts": [[x, y, z], ...] }],           # optional extra paths for people
}
```

`give_way` and `stop` tags on a node within 35 m of a junction apply to that
junction's approach on that road, which is how OSM usually tags them.

Traffic draws its own traffic lights, boom gates and bus stop shelters; the
map doesn't need to.

## Hooks

`TrafficManager` signals:

| Signal | When |
| --- | --- |
| `vehicle_spawned(vehicle: Node3D, type: StringName)` | A car/bus appeared (or was reused from the pool). `type`: hatch, sedan, suv, ute, van, bus. |
| `vehicle_despawned(vehicle: Node3D)` | It was hidden and pooled. |
| `horn(vehicle: Node3D, duration: float, is_bus: bool)` | A vehicle sounded its horn. |
| `pedestrian_startled(position: Vector3)` | Someone jumped out of the player's way. |
| `crossing_changed(position: Vector3, closed: bool)` | Boom gates going down (bells start) or up. |
| `train_spawned(train: Node3D)` / `train_despawned(train: Node3D)` | Each carriage is a child of `train`. |
| `signals_changed(position: Vector3)` | A set of lights changed phase. |
| `network_changed` | Road data was added. |

Each vehicle body has a child `Audio` (Node3D at the engine) with a `Horn`
AudioStreamPlayer3D on the Vehicles bus playing a placeholder two-tone horn.
Sound code can swap `Horn.stream`, or add engine players under `Audio` on
`vehicle_spawned`. A vehicle's speed: `manager.vehicles` holds
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
