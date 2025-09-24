extends CharacterBody2D

@export var speed: float = 50.0

# --- Detection settings ---
@export var view_distance: float = 100.0     # how far the guard can see
@export var fov_deg: float = 50.0            # cone width (e.g. 90°)

@onready var player: Node2D = get_node_or_null("../Player")

func _ready() -> void:
	randomize()
	velocity = Vector2.RIGHT.rotated(randf() * TAU) * speed

func _physics_process(delta: float) -> void:
	# --- Move & bounce ---
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal())

	# --- Spot player? ---
	if player and _can_see_player(player):
		Transition.caught_and_restart()

func _can_see_player(p: Node2D) -> bool:
	# 1) Distance gate
	var to_p: Vector2 = p.global_position - global_position
	if to_p.length() > view_distance:
		return false

	# 2) FOV cone gate (uses current movement direction as facing)
	var facing: Vector2
	if velocity.length() > 0.001:
		facing = velocity.normalized()
	else:
		facing = Vector2.RIGHT  # or Vector2.RIGHT.rotated(rotation) if you rotate the NPC

	var ang_deg: float = rad_to_deg(acos(clamp(facing.dot(to_p.normalized()), -1.0, 1.0)))
	if ang_deg > fov_deg * 0.5:
		return false

	# 3) Line-of-sight ray (blocked by walls/obstacles)
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.exclude = [self]
	# Optionally: query.collision_mask = <mask that includes walls + player>

	var hit := space.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == p
