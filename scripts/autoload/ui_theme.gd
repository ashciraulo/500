extends Node
## Puts the game's UI style (UiStyle) into Godot's default theme before any
## screen is built, so every Control picks it up, and notes whether the player
## is on a gamepad so prompts can show the right button.


func _init() -> void:
	ThemeDB.get_default_theme().merge_with(UiStyle.theme())
	ThemeDB.fallback_font = UiStyle.BODY_FONT
	ThemeDB.fallback_font_size = UiStyle.BODY_SIZE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		UiStyle.using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		UiStyle.using_pad = false
