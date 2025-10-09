extends Area2D

@export var action_name := "Enter"
@export var is_on := false
@export var door_group := "doors"
@export var channel: String = ""   # <-- add this (empty = belongs to all/any)

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
var _player_in_range := false

func _ready() -> void:
	add_to_group("levers")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_visual()

func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = true

func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = false

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed(action_name):
		if not is_on:
			_toggle_lever(true)

func _toggle_lever(state: bool) -> void:
	is_on = state
	_update_visual()
	# Notify doors to re-check
	var doors := get_tree().get_nodes_in_group(door_group)
	for d in doors:
		if d.has_method("on_lever_toggled"):
			d.on_lever_toggled()

func _update_visual() -> void:
	if anim == null:
		return
	if is_on:
		anim.play("On")
	else:
		anim.play("Off")
