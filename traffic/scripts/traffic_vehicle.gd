class_name TrafficVehicle
extends RefCounted
## One AI vehicle: where it is on the lane graph, how fast it's going, and the
## node that shows it. TrafficManager drives every vehicle in one loop (no
## per-vehicle _process), and pools them: a despawned vehicle is hidden and
## reused for the next spawn of the same type.
##
## Node layout (built by TrafficManager): an AnimatableBody3D on physics layer
## 3 ("traffic") with a box collider, a MeshInstance3D named Mesh using
## TrafficModels' surface layout, and a Node3D named Audio at the front with a
## Horn AudioStreamPlayer3D. Sound code can add players under Audio when the
## manager emits `vehicle_spawned`.

enum Reason { NONE, LEADER, STOP_LINE, YIELD, PLAYER, PEDESTRIAN, OBSTACLE, EMERGENCY }

var id := 0
var type: StringName
var is_bus := false
## Someone on a bicycle: rides near the kerb, cars pass them.
var is_bike := false
## In a lane coned off for roadworks ahead: looking to merge out.
var works_merge := false
## Seconds left passing a cyclist (swung out to the right).
var pass_bike := 0.0
## Police, ambulance or fire truck on a call (lights and siren).
var emergency := false
var siren: AudioStreamPlayer3D
## Seconds since this call began, and the closest it has come to the player.
var call_time := 0.0
var call_closest := INF
var light_bar: Node3D
## A modelled body (art/models/...) shown instead of `mesh`, or null.
var model: Node3D
var length := 4.5
var width := 1.8
var paint := Color.WHITE

var body: AnimatableBody3D
var mesh: MeshInstance3D
var horn: AudioStreamPlayer3D
var active := false

## route[0] is the lane we're on; the rest is the plan ahead.
var route: Array = []
var prev_lane: TrafficGraph.Lane
var s := 0.0
var speed := 0.0
var accel := 0.0
## Personal taste: multiplies the speed limit.
var eagerness := 1.0
var position := Vector3.ZERO
var forward := Vector3.FORWARD
var yaw_basis := Basis.IDENTITY

## Why we're slowing down right now, and who for.
var reason := Reason.NONE
var blocked_by: Object
## The car we're stopped for, and how firmly (see TrafficManager._break_jams):
## 0 giving way, 1 taking turns at a merge, 2 something across our path,
## 3 queued behind them.
var wait_on: TrafficVehicle
var wait_rank := 0
## Going ahead of this car to break a jam, for `unjam_time` more seconds.
var unjam: TrafficVehicle
var unjam_time := 0.0
var stopped_time := 0.0
var yield_wait := 0.0
var stop_sign_wait := 0.0
## Connector we've been cleared to enter (no more yielding for it).
var cleared: TrafficGraph.Lane
## Every connector that clearance covers: back-to-back junctions joined by a
## link too short to wait on are crossed in one go.
var commits: Array = []
## Bus stops already served on the current lane.
var served := {}
## The bus route this bus is running ("" for none: it roams the big roads).
var bus_route := ""
var dwell := 0.0
## Working vehicles (sweepers, bin trucks): a top speed of their own (0 for
## none), stay in their lane, and stops to make on the way:
## { lane, s, dwell } dictionaries, each marked "done" once served.
var max_speed := 0.0
var keep_lane := false
var service_stops: Array = []
## Riding in a bunch (its number, 0 for none): the rider just ahead (whose turns we take and whose
## wheel we sit on), which side of the bunch we ride (metres out from the
## kerb line), and the roads the bunch keeps to (road names, set on all).
var follow: TrafficVehicle
var follow_serial := -1
## Counts up with every spawn (pooled vehicles keep their id).
var serial := 0
var bunch := 0
var bunch_side := 0.0
var ride_roads := {}
## In a bunch: the lanes this rider has ridden lately, oldest first, so the
## rider behind can follow the same way even after a red light splits them.
var trail: Array = []
var lifetime := 0.0

## Sideways offset from the lane centre (to dodge the player), metres; + = left.
var lateral := 0.0
var lateral_target := 0.0
## Seconds left pulled over for an emergency vehicle coming up behind.
var pull_over := 0.0
## Where the vehicle sits across its lane when nothing else says otherwise:
## left when pulled over, right when an emergency vehicle is passing.
var lateral_base := 0.0
## Lane change: the lane we're moving out of and progress 0..1.
var change_from: TrafficGraph.Lane
var change_t := 1.0
var change_cooldown := 0.0

var horn_time := 0.0
var horn_cooldown := 0.0
## Going round the player's stopped car (seconds left of trying).
var round_player := 0.0
var hazard_time := 0.0
var flash_time := 0.0
var indicator := 0
var lights_key := -1

## Cached obstacle check (refreshed a few times a second).
var obstacle_gap := INF
var obstacle_speed := 0.0
var obstacle_reason := Reason.NONE
var obstacle_who: Object
var obstacle_timer := 0.0


func lane() -> TrafficGraph.Lane:
	return route[0] if not route.is_empty() else null


## Distance from our centre to the end of the current lane.
func to_lane_end() -> float:
	return route[0].length - s


func is_braking() -> bool:
	return accel < -0.6 or (speed < 0.3 and active)
