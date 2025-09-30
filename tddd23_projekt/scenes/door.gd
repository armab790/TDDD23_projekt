extends Area2D

@export var open_time: float = 0.25
@export var prompt_action: String = "Enter"   # create input action "interact"
@export var next_scene: String = ""              # e.g. "res://scenes/Level2.tscn"

@onready var solid: StaticBody2D = $StaticBody2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var exit_point: Marker2D = $ExitPoint

var _player_in_range := false
var _is_open := false

func _ready() -> void:
	anim.play("Closed Door")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(b: Node) -> void:
	if b is CharacterBody2D and b.name == "Player":
		_player_in_range = true

func _on_body_exited(b: Node) -> void:
	if b is CharacterBody2D and b.name == "Player":
		_player_in_range = false

func _process(_dt: float) -> void:
	if _player_in_range and Input.is_action_just_pressed(prompt_action):
		if not _is_open:
			await _open_door()
		else:
			await _go_through()

func _open_door() -> void:
	_is_open = true
	anim.play("door opens")
	await get_tree().create_timer(open_time).timeout
	anim.play("Open Door")
	solid.set_deferred("collision_layer", 0)
	solid.set_deferred("collision_mask", 0)

func _go_through() -> void:
	# Optional: move player to exit point before transition
	var player := get_tree().get_first_node_in_group("player")
	if player and exit_point:
		(player as Node2D).global_position = exit_point.global_position

	# Use your Transition autoload to fade + message + next level
	if next_scene != "":
		# quick text overlay using Transition
		Transition.fade_to_black(0.35)
		await get_tree().create_timer(0.36, false, true).timeout
		# simple text message: you can add a Label to Transition to show text;
		# if you don't have that yet, see helper below.
		get_tree().change_scene_to_file(next_scene)
		Engine.time_scale = 1.0
		await get_tree().process_frame
		await Transition.fade_from_black(0.35)
