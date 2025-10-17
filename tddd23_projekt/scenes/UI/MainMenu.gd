# res://scenes/UI/MainMenu.gd
extends Control

# set this to your first level file
const FIRST_LEVEL := "res://scenes/Levels/Level1.tscn"

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready() -> void:
	# Connect buttons
	if not play_button.pressed.is_connected(_on_play_pressed):
		play_button.pressed.connect(_on_play_pressed)
	if not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)

	# Optional: keyboard shortcut (Enter starts)
	set_process_unhandled_key_input(true)

	# Optional: start / switch music
	if Engine.has_singleton("MusicPlayer"):
		MusicPlayer.play_music()  # continues ambient if already set

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_play_pressed()

func _on_play_pressed() -> void:
	# Nice fade via Transition (uses your autoload)
	if Engine.has_singleton("Transition"):
		Transition.change_scene_with_spawn(FIRST_LEVEL, 1.0, "Level 1", false)
	else:
		get_tree().change_scene_to_file(FIRST_LEVEL)

func _on_quit_pressed() -> void:
	get_tree().quit()
