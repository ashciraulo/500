extends Node
## Where the game starts (the project's main scene). With the title screen,
## nothing of the game is built behind it: no world, no car, no traffic, and
## the save isn't loaded. Continue or New game, and then the game scene is
## built, as if it had been run on its own. Straight into the game, save
## loaded, with `-- --no-title`.

const GAME := "res://scenes/main.tscn"

## Open on the title screen (tests set it before adding the scene).
var with_title := TitleScreen.wanted()


func _ready() -> void:
	if not with_title:
		_play.call_deferred()
		return
	# The title's Settings button opens the pause menu's settings.
	var settings: CanvasLayer = load("res://scripts/ui/pause_menu.gd").new()
	settings.name = "PauseMenu"
	add_child(settings)
	var title := TitleScreen.new()
	title.name = "TitleScreen"
	add_child(title)
	title.started.connect(func() -> void:
		# A couple of frames for "Loading..." to show: building the game takes
		# a few seconds and nothing draws while it does.
		for i in 2:
			await get_tree().process_frame
		# The title stays over the game's first frames, then fades.
		title.reparent(get_tree().root)
		title.fade_out()
		_play())


func _play() -> void:
	get_tree().change_scene_to_file(GAME)
	if get_tree().current_scene != self:
		queue_free()  # a test's copy, not the scene being changed
