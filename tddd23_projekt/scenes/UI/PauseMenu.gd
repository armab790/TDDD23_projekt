extends CanvasLayer

@export var lobby_scene_path: String = "res://scenes/UI/MainMenu.tscn"
@export var dim_alpha: float = 0.55
@export var layer_index: int = 200

@onready var root: Control      = $Root
@onready var dim: ColorRect     = $Root/Dim
@onready var btn_continue: Button = $Root/CenterContainer/Panel/VBoxContainer/ContinueButton
@onready var btn_lobby: Button    = $Root/CenterContainer/Panel/VBoxContainer/LobbyButton

var _gameplay_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = layer_index

	# Defensive init if any child is missing
	if root == null:
		root = Control.new(); root.name = "Root"; add_child(root); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if dim == null:
		dim = ColorRect.new(); dim.name = "Dim"; root.add_child(dim); dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Style + initial state
	var c := dim.color
	dim.color = Color(c.r, c.g, c.b, dim_alpha)
	root.visible = false

	# Wire buttons
	if btn_continue and not btn_continue.pressed.is_connected(_on_continue_pressed):
		btn_continue.pressed.connect(_on_continue_pressed)
	if btn_lobby and not btn_lobby.pressed.is_connected(_on_lobby_pressed):
		btn_lobby.pressed.connect(_on_lobby_pressed)

	# Track scene changes to enable/disable pause
	get_tree().tree_changed.connect(_on_tree_changed) # fires on scene swaps too
	_update_gameplay_active()  # initial evaluation

func _unhandled_input(event: InputEvent) -> void:
	# Ignore Esc if not in gameplay
	if not _gameplay_active:
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	if get_tree().paused:
		_resume()
	else:
		_pause()

func _pause() -> void:
	get_tree().paused = true
	root.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Stop pulse overlay if present
	var fx := _find_screen_fx()
	if fx and fx.has_method("stop_pulse"):
		fx.stop_pulse()

func _resume() -> void:
	get_tree().paused = false
	root.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Re-sync heartbeat/pulse for all enemies after unpausing
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("refresh_alert_fx"):
			e.refresh_alert_fx()

func _on_continue_pressed() -> void:
	_resume()

func _on_lobby_pressed() -> void:
	# 1) Close the pause UI and unpause
	_resume()                                    # sets paused=false, root.visible=false

	# 2) Prevent re-opening or stray input during scene swap
	set_process_unhandled_input(false)

	# 3) Go straight to the lobby (no Transition => no finish card/message)
	get_tree().change_scene_to_file(lobby_scene_path)

	# 4) Re-enable input next frame (so menu can also use Esc if you want)
	await get_tree().process_frame
	set_process_unhandled_input(true)

# ----- Gameplay detection -----
func _on_tree_changed() -> void:
	# This can fire while we’re not in the tree; defer to next frame.
	if not is_inside_tree():
		return
	call_deferred("_update_gameplay_active")

func _update_gameplay_active() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var scn := tree.current_scene
	var was_active := _gameplay_active
	_gameplay_active = _is_gameplay_scene(scn)
	if was_active and not _gameplay_active and tree.paused:
		_resume()

func _is_gameplay_scene(scn: Node) -> bool:
	if scn == null:
		return false
	# Preferred: mark your gameplay scene root with this group in the editor
	if scn.is_in_group("gameplay_root"):
		return true
	# Fallback heuristic: avoid menus by name/path
	var name_ok := scn.name != "MainMenu"
	var path := scn.scene_file_path
	var path_ok := ("/Levels/" in path) or ("/scenes/Levels/" in path)
	return name_ok and path_ok

func _find_screen_fx() -> Node:
	# If you autoload ScreenFX, prefer: return get_node_or_null("/root/ScreenFX")
	var fx := get_tree().get_first_node_in_group("screen_fx")
	return fx
