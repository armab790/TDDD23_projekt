extends CanvasLayer
# Autoload this script as "Transition"

var shade: ColorRect
var message_label: Label
var busy: bool = false


# -----------------------------
# Public API
# -----------------------------

# Fade → change scene → move Player to group's "spawn_point" → fade in
# Optionally show a message after the fade in. If message is empty,
# we auto-detect "Level X" from the path (if your levels are named Level1.tscn, etc).
func change_scene_with_spawn(path: String, fade: float = 1.0, message: String = "", show_level_if_detected: bool = true) -> void:
	await fade_to_black(fade)
	get_tree().change_scene_to_file(path)

	# Wait a frame so the new scene finishes building
	await get_tree().process_frame

	# Get player & spawn safely
	var player := get_tree().get_first_node_in_group("player")
	var spawn := get_tree().get_first_node_in_group("spawn_point")

	# If still not ready, give it another tiny tick
	if player == null or spawn == null:
		await get_tree().create_timer(0.05).timeout
		player = get_tree().get_first_node_in_group("player")
		spawn = get_tree().get_first_node_in_group("spawn_point")

	if player is CharacterBody2D and spawn is Node2D:
		player.global_position = spawn.global_position
	else:
		print("Transition: missing/invalid player or spawn in this scene. player:", player, " spawn:", spawn)

	# Decide message (on black), then fade in
	var final_text := message
	if final_text == "" and show_level_if_detected:
		var n := _extract_level_number(path)
		if n > 0:
			final_text = "Level " + str(n)

	if final_text != "":
		await show_message(final_text, 0.35, 1.4, 0.35, true)

	await fade_from_black(fade)


# Simple fade-to-black → message on black → fade-from-black (use for chapter cards, endings, etc.)
func show_message_over_black(text: String, fade_in_black: float = 0.35, hold_text: float = 1.6, fade_out_black: float = 0.35) -> void:
	await fade_to_black(fade_in_black)
	await show_message(text, 0.30, hold_text, 0.30, true)
	await fade_from_black(fade_out_black)


# Show a centered message (over the current scene or over black)
# If over_black == true we skip extra background changes (assume you're already black).
func show_message(text: String, fade_in: float = 0.35, hold: float = 1.6, fade_out: float = 0.35, _over_black: bool = false) -> void:
	if message_label == null:
		return
	message_label.text = text
	message_label.visible = true
	message_label.modulate.a = 0.0
	shade.z_index = 0
	message_label.z_index = 1

	var tw_in := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw_in.tween_property(message_label, "modulate:a", 1.0, fade_in)
	await tw_in.finished

	if hold > 0.0:
		await get_tree().create_timer(hold).timeout

	var tw_out := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw_out.tween_property(message_label, "modulate:a", 0.0, fade_out)
	await tw_out.finished

	message_label.visible = false


# Your existing caught→slowmo→fade→restart flow
func caught_and_restart() -> void:
	if busy:
		return
	busy = true

	# Slow-mo + fade to black in parallel
	var tw := create_tween()
	tw.parallel().tween_property(Engine, "time_scale", 0.15, 0.25)
	tw.parallel().tween_property(shade, "modulate:a", 1.0, 0.35)
	await tw.finished

	# Use a timer that ignores time_scale so we don’t stall
	await get_tree().create_timer(0.05, false, true).timeout

	get_tree().reload_current_scene()

	# Reset time and fade back in after reload
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await fade_from_black(3.35)

	busy = false


# -----------------------------
# Fades
# -----------------------------
func fade_to_black(duration: float = 3.35) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shade, "modulate:a", 1.0, duration)
	await tw.finished

func fade_from_black(duration: float = 3.35) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shade, "modulate:a", 0.0, duration)
	await tw.finished


# -----------------------------
# Setup
# -----------------------------
func _ready() -> void:
	# --- Black fullscreen Shade ---
	shade = get_node_or_null("Shade") as ColorRect
	if shade == null:
		shade = ColorRect.new()
		shade.name = "Shade"
		add_child(shade)

	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.offset_left = 0.0
	shade.offset_top = 0.0
	shade.offset_right = 0.0
	shade.offset_bottom = 0.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = 100
	var m := shade.modulate
	m.r = 0.0
	m.g = 0.0
	m.b = 0.0
	m.a = 0.0
	shade.modulate = m

	# Keep full-screen on resize
	get_viewport().size_changed.connect(func ():
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.offset_left = 0.0
		shade.offset_top = 0.0
		shade.offset_right = 0.0
		shade.offset_bottom = 0.0
	)

	# --- Centered message label ---
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	message_label.offset_left = 0
	message_label.offset_top = 0
	message_label.offset_right = 0
	message_label.offset_bottom = 0
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.z_index = 100  # above shade
	message_label.visible = false
	# Style
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.add_theme_font_size_override("font_size", 36)
	add_child(message_label)


# -----------------------------
# Helpers
# -----------------------------
func _extract_level_number(path: String) -> int:
	var base := path.get_file().get_basename()  # e.g. "Level3"
	if base.begins_with("Level"):
		var num_str := base.substr(5)
		if num_str.is_valid_int():
			return int(num_str)
	return -1

func return_to_menu(menu_path: String, msg: String = "You completed the game! Well done!", fade: float = 0.8) -> void:
	# Fade to black first
	await fade_to_black(fade)
	# Optional message on black
	if msg != "":
		await show_message(msg, 0.30, 2.0, 0.30, true)
	# Change to menu and wait a frame while we (the autoload) survive
	get_tree().change_scene_to_file(menu_path)
	await get_tree().process_frame
	# Fade back in
	await fade_from_black(fade)
