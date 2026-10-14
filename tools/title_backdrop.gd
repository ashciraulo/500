extends SceneTree
## Renders the picture behind the title screen: the Pop in the carport at
## dusk, through the lo-fi filter, no HUD. The title screen shows this still
## (the game itself isn't built until you choose Continue or New game), so
## re-run it when the house or the Pop change:
##
##   xvfb-run godot --path . --fixed-fps 60 --resolution 1920x1080 --script res://tools/title_backdrop.gd -- --no-save
##
## Writes art/ui/title_backdrop.png (and a copy to shots=<dir> if given).

const OUT := "res://art/ui/title_backdrop.png"
## Where the camera sits round the car, as the old live title had it.
const ORBIT_TURN := PI * 0.75 + 0.35
const ORBIT_RADIUS := 5.2
const ORBIT_HEIGHT := 1.5
## Frames for the map round the house to stream in and the lights to settle.
const SETTLE_FRAMES := 300

var _main: Node
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("GameClock").set_time(18.4)
		root.get_node("GameClock").set("locked", true)
		root.get_node("Weather").set("locked", true)
		return false
	_frames += 1
	if _frames == 2:
		var rig := _main.find_child("CameraRig", true, false)
		rig.set_process(false)
		rig.set_physics_process(false)
		get_first_node_in_group(&"player_car").set("player_controlled", false)
		for spot: Node in get_nodes_in_group(&"workshop_spots"):
			(spot as Node3D).visible = false  # the painted bay is a game marker
	if _frames >= 2:
		# Nothing but the picture: no HUD, hints or cards (some show themselves
		# a moment in, so every frame).
		for layer: Node in root.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
		_place_camera()
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	image.save_png(OUT)
	print("wrote ", OUT, " ", image.get_size())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			image.save_png(a.trim_prefix("shots=").path_join("title_backdrop.png"))
	_done = true
	root.get_node("SaveGame").quit_cleanly()
	return false


func _place_camera() -> void:
	var car := get_first_node_in_group(&"player_car") as Node3D
	var camera := _main.find_child("CameraRig", true, false).get_node("Camera3D") as Camera3D
	var centre := car.global_position + Vector3.UP * 0.5
	var turn := car.global_rotation.y + ORBIT_TURN
	var eye := centre + Vector3(sin(turn), 0.0, cos(turn)) * ORBIT_RADIUS + Vector3.UP * ORBIT_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(centre, eye, 1)
	query.exclude = [(car as CollisionObject3D).get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		eye = centre.lerp(hit.position, 0.85)
	camera.current = true
	camera.global_transform = Transform3D(Basis(), eye).looking_at(centre, Vector3.UP)
