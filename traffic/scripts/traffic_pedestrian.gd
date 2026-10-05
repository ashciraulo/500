class_name TrafficPedestrian
extends RefCounted
## One person walking the footpaths. Like vehicles, people are plain data
## driven by TrafficManager in one loop and pooled when they despawn.

var node: Node3D
var legs: Array = []
var arms: Array = []
var umbrella: Node3D
var has_umbrella := false
var active := false

var edge: TrafficGraph.PedEdge
var s := 0.0
## +1 walking from edge.a to edge.b, -1 the other way.
var dir := 1
var walk_speed := 1.3
var speed := 0.0
## Personal spot on the footpath (metres to the left of the edge line).
var side := 0.0
var dodge := 0.0
var dodge_target := 0.0
var waiting := false
var wait_time := 0.0
var phase := 0.0
var startle_cooldown := 0.0
## Somewhere to be (fans walking to the footy): the PedEdges still to walk,
## in order; empty to wander as usual.
var route: Array = []
## When the route runs out: 0 wander on, 1 go once nobody's looking (onto
## the train), 2 go anyway (in through the stadium gates).
var leave_at_end := 0
var arrived := false

## Fields shared with vehicles for the obstacle checks.
var position := Vector3.ZERO
var forward := Vector3.FORWARD
var length := 0.5
var width := 0.5
