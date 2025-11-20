extends Node2D

@onready var sprite: AnimatedSprite2D = $arrow

@export var life_time: float = 4.5
@export var offset_distance: float = 20.0

# Rotation offset in degrees so you can fix the 90° easily
@export var rotation_offset_deg: float = 90.0

var _age: float = 0.0
var _owner: Node2D
var _target_pos: Vector2

func setup(owner: Node2D, target_global_pos: Vector2) -> void:
	_owner = owner
	_target_pos = target_global_pos
	global_position = _owner.global_position

func _process(delta: float) -> void:
	_age += delta
	if _age >= life_time:
		queue_free()
		return

	if _owner and is_instance_valid(_owner):
		var base_pos := _owner.global_position
		var to_target := _target_pos - base_pos
		if to_target.length() > 0.01:
			var dir := to_target.normalized()
			var offset_rad := deg_to_rad(rotation_offset_deg)
			rotation = dir.angle() + offset_rad
			global_position = base_pos + dir * offset_distance

	# Fade out over time (avoid clamp() issues)
	var t: float = _age / life_time
	if t < 0.0:
		t = 0.0
	elif t > 1.0:
		t = 1.0

	var c := modulate
	c.a = 1.0 - t
	modulate = c
