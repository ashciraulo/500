extends Node
## The traffic sandbox: the full game (car, camera, weather, HUD) with the
## Perth map swapped for a small suburb built to exercise traffic. Open
## traffic/sandbox/traffic_sandbox.tscn and press F6 to drive around it.

const MAIN := preload("res://scenes/main.tscn")

## Where the player's car starts: the avenue's eastbound kerb lane.
@export var car_start := Vector3(-140, 0.6, -4.8)
@export var car_yaw_deg := -90.0

var main: Node
var traffic: TrafficManager
var world_root: Node3D


func _ready() -> void:
	main = MAIN.instantiate()
	world_root = main.get_node("LoFi/SubViewport/World")
	# Drop the Perth map (or the old test grid) before it enters the tree.
	for world_name in ["PerthMap", "TestGrid"]:
		var world := world_root.get_node_or_null(world_name)
		if world:
			world_root.remove_child(world)
			world.free()
	traffic = world_root.get_node("Traffic")
	traffic.use_test_grid_fallback = false
	var car := world_root.get_node("Car") as Node3D
	car.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(car_yaw_deg)), car_start)
	var sandbox := TrafficSandboxWorld.new()
	sandbox.name = "SandboxWorld"
	world_root.add_child(sandbox)
	add_child(main)
	traffic.add_network(TrafficTestNetworks.sandbox(), true)
	sandbox.build(traffic.graph)
