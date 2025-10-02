extends Node2D

@export var fov_deg: float = 50.0
@export var view_distance: float = 100.0
@export var segments: int = 48
@export var collision_mask: int = 1
@export var fill_color: Color = Color(0.2, 0.8, 1.0, 0.15)
@export var line_color: Color = Color(0.2, 0.8, 1.0, 0.6)

func _process(_dt: float) -> void:
	var cb := get_parent() as CharacterBody2D
	var facing: Vector2 = Vector2.RIGHT

	if cb:
		var vel: Vector2 = cb.velocity
		if vel.length() > 0.001:
			facing = vel.normalized()
		else:
			# fall back to node rotation if not moving
			facing = Vector2.RIGHT.rotated(cb.rotation)

	rotation = facing.angle()
	queue_redraw()

func _draw() -> void:
	var space := get_world_2d().direct_space_state
	var origin: Vector2 = global_position

	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)

	var half: float = deg_to_rad(fov_deg * 0.5)

	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var rel: float = -half + t * (2.0 * half)
		var ang: float = rotation + rel
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var end: Vector2 = origin + dir * view_distance

		var q := PhysicsRayQueryParameters2D.create(origin, end)
		q.exclude = [get_parent()]
		q.collision_mask = collision_mask
		var hit := space.intersect_ray(q)

		var hit_pos: Vector2 = end
		if not hit.is_empty():
			hit_pos = hit["position"] as Vector2

		pts.append(to_local(hit_pos))
	draw_colored_polygon(pts, fill_color)

	var outline: PackedVector2Array = pts.duplicate()
	outline.remove_at(0)
	draw_polyline(outline, line_color, 2.0)
