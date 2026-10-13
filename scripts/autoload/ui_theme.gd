extends Node
## Puts the game's UI style (UiStyle) into Godot's default theme before any
## screen is built, so every Control picks it up, and notes whether the player
## is on a gamepad so prompts can show the right button. Buttons tick when you
## move between them with the keys or a pad, and click when pressed.

## When the player last moved focus with the keys or a pad (ms).
var _nav_at := -10000


func _init() -> void:
	ThemeDB.get_default_theme().merge_with(UiStyle.theme())
	ThemeDB.fallback_font = UiStyle.BODY_FONT
	ThemeDB.fallback_font_size = UiStyle.BODY_SIZE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.focus_entered.connect(func() -> void:
			if Time.get_ticks_msec() - _nav_at < 250:
				UiStyle.click("ui_menu_move", -12.0, UiStyle.CLICK_MOVE))
		button.pressed.connect(func() -> void: UiStyle.click("ui_menu_select", -10.0, UiStyle.CLICK_PRESS))
		# The mouse takes the focus with it, so only one row looks picked.
		button.mouse_entered.connect(_hover_focus.bind(button))


func _hover_focus(button: BaseButton) -> void:
	if button.focus_mode == Control.FOCUS_NONE or button.disabled or not button.is_visible_in_tree():
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return  # mid-drag on a slider
	var focused := button.get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return  # don't pull you out of typing
	button.grab_focus()


func _input(event: InputEvent) -> void:
	for action in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]:
		if event.is_action_pressed(action, true):
			_nav_at = Time.get_ticks_msec()
			break
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		UiStyle.using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		UiStyle.using_pad = false
