extends Sprite2D

@export var view_distance: float = 100.0
@export var fov_deg: float = 50.0
@export var follow_parent_rotation: bool = true

func _process(_delta: float) -> void:
	if not follow_parent_rotation:
		return

	var parent := get_parent()
	if not parent or not parent is CharacterBody2D:
		return

	var dir := Vector2.RIGHT
	if parent.velocity.length() > 0.01:
		dir = parent.velocity.normalized()

	rotation = dir.angle()
	scale.x = view_distance / 100.0
	scale.y = fov_deg / 50.0
