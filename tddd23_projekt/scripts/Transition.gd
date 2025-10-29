extends CanvasLayer
# Autoload this script as "Transition"

var shade: ColorRect
var message_label: Label
var busy: bool = false

@export var new_scene_stream: AudioStream       # assign in Inspector (optional)
@export var new_scene_min_hold: float = 1.5     # minimum delay before changing scene
@export var new_scene_wait_full_length: bool = false  # wait whole file (>= min_hold)

var _new_scene_player: AudioStreamPlayer

@export_file("*.png") var next_card_path := "res://assets/images/nextlevel.png"
@export_file("*.png") var finish_card_path := "res://assets/images/finish.png"
@export var card_fade_in: float = 0.25
@export var card_fade_out: float = 0.25

@export_file("*.png") var caught_card_path := "res://assets/images/caught.png"
@export_file("*.mp3") var caught_sfx_path := "res://audios/SFX/Tense.mp3"
@export var caught_hold: float = 0.2                    # how long to show the card
@export var caught_fade_in: float = 0.25
@export var caught_fade_out: float = 0.25
@export var caught_sfx: AudioStream                     # optional sound when caught


var _card: TextureRect
var _card_tw: Tween



# -----------------------------
# Helpers
# -----------------------------

func _show_caught_card() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(caught_card_path):
		tex = load(caught_card_path)
	if tex:
		# temporarily override fade times for caught screen
		var old_in := card_fade_in
		var old_out := card_fade_out
		card_fade_in = caught_fade_in
		card_fade_out = caught_fade_out
		await _show_card(tex)
		card_fade_in = old_in
		card_fade_out = old_out


func _play_new_scene_sfx_and_wait() -> void:
	if new_scene_stream == null:
		return

	_new_scene_player.stream = new_scene_stream
	_new_scene_player.play()
	
	

	var wait_time = 1.5

	# If you want to optionally wait the FULL file length (or at least min_hold):
	if new_scene_wait_full_length and new_scene_stream.has_method("get_length"):
		var length := float(new_scene_stream.get_length())
		if length > 0.0:
			wait_time = max(length, new_scene_min_hold)

	# Use a timer that ignores time_scale so slowmo won’t stall it
	await get_tree().create_timer(wait_time, false, true).timeout

func _show_card(tex: Texture2D) -> void:
	if _card_tw: _card_tw.kill()
	_card.texture = tex
	_card.modulate.a = 0.0
	_card.visible = true
	_card_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_tw.tween_property(_card, "modulate:a", 1.0, card_fade_in)
	await _card_tw.finished

func _hide_card() -> void:
	if _card_tw: _card_tw.kill()
	_card_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_card_tw.tween_property(_card, "modulate:a", 0.0, card_fade_out)
	await _card_tw.finished
	_card.visible = false


# Fade → change scene → move Player to group's "spawn_point" → fade in
# Optionally show a message after the fade in. If message is empty,
# we auto-detect "Level X" from the path (if your levels are named Level1.tscn, etc).
func change_scene_with_spawn(path: String, fade: float = 1.0, message: String = "", show_level_if_detected: bool = true) -> void:
	# Fade to black first (keeps the nice curtain effect)
	await fade_to_black(fade)
	_hide_card()
	# --- Show the NEXT LEVEL card ---
	var next_tex: Texture2D = null
	if ResourceLoader.exists(next_card_path):
		next_tex = load(next_card_path)
	if next_tex:
		await _show_card(next_tex)

	# --- Play transition SFX and wait (1.5s or what you set) ---
	await _play_new_scene_sfx_and_wait()

	# Switch scenes
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame

	# Spawn logic (unchanged)
	var player := get_tree().get_first_node_in_group("player")
	var spawn := get_tree().get_first_node_in_group("spawn_point")
	if player == null or spawn == null:
		await get_tree().create_timer(0.05, false, true).timeout
		player = get_tree().get_first_node_in_group("player")
		spawn = get_tree().get_first_node_in_group("spawn_point")
	if player is CharacterBody2D and spawn is Node2D:
		player.global_position = spawn.global_position
	else:
		print("Transition: missing/invalid player or spawn in this scene. player:", player, " spawn:", spawn)

	# Optional message on black (kept for convenience)
	var final_text := message
	if final_text == "" and show_level_if_detected:
		var n := _extract_level_number(path)
		if n > 0:
			final_text = "Level " + str(n)
	if final_text != "":
		await show_message(final_text, 0.35, 1.4, 0.35, true)

	# Hide the card, then fade back in
	if _card.visible:
		await _hide_card()
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

	# Slow-mo + fade to black in parallel (as you had)
	var tw := create_tween()
	tw.parallel().tween_property(Engine, "time_scale", 0.15, 0.25)
	tw.parallel().tween_property(shade, "modulate:a", 1.0, 0.35)
	await tw.finished

	# Show the "caught" card on top of black and (optionally) play SFX
	await _show_caught_card()

	# Hold the card for a moment
	await get_tree().create_timer(caught_hold, false, true).timeout

	# Reload the scene while we (Transition) persist
	get_tree().reload_current_scene()
	Engine.time_scale = 1.0
	await get_tree().process_frame

	# Hide the card and fade back in
	if _card.visible:
		await _hide_card()
	await fade_from_black(0.8)

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
	
	# --- Fullscreen transition card (image) ---
	_card = TextureRect.new()
	_card.name = "Card"
	_card.visible = false   
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.stretch_mode = TextureRect.STRETCH_SCALE    # fill screen
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card.modulate.a = 0.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.z_index = 150   # above shade and label
	add_child(_card)
	
		# --- Transition SFX player (non-positional, survives scene swaps) ---
	_new_scene_player = AudioStreamPlayer.new()
	_new_scene_player.bus = "Master"   # or your SFX bus
	_new_scene_player.autoplay = false
	_new_scene_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_new_scene_player)

	# Optional auto-load if you didn’t assign it in Inspector
	if new_scene_stream == null and ResourceLoader.exists("res://audios/SFX/New_Scene.mp3"):
		new_scene_stream = load("res://audios/SFX/New_Scene.mp3")

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

func return_to_menu(menu_path: String, msg: String = "", fade: float = 0.8) -> void:
	# Fade to black
	await fade_to_black(fade)

	# --- Show FINISH card ---
	var fin_tex: Texture2D = null
	if ResourceLoader.exists(finish_card_path):
		fin_tex = load(finish_card_path)
	if fin_tex:
		await _show_card(fin_tex)

	# Optional message over black (below the card; usually not needed now)
	if msg != "":
		await show_message(msg, 0.30, 1.6, 0.30, true)

	# Give the image a moment and/or play the same transition sound if you want
	await _play_new_scene_sfx_and_wait()

	# Change to menu and fade back in
	get_tree().change_scene_to_file(menu_path)
	await get_tree().process_frame

	if _card.visible:
		await _hide_card()
	await fade_from_black(fade)
