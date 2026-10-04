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

enum Reason { NONE, LEADER, STOP_LINE, YIELD, PLAYER, PEDESTRIAN, OBSTACLE }

var id := 0
var type: StringName
var is_bus := false
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
var dwell := 0.0
var lifetime := 0.0

## Sideways offset from the lane centre (to dodge the player), metres; + = left.
var lateral := 0.0
var lateral_target := 0.0
## Lane change: the lane we're moving out of and progress 0..1.
var change_from: TrafficGraph.Lane
var change_t := 1.0
var change_cooldown := 0.0

var horn_time := 0.0
var horn_cooldown := 0.0
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
