extends CharacterBody2D

@export var speed: float = 50.0

# --- Detection settings ---
@export var view_distance: float = 100.0
@export var fov_deg: float = 50.0

@onready var player: Node2D = get_node_or_null("../Player")
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# Where the NPC faces when idle (cardinal)
var last_dir: Vector2 = Vector2.DOWN

func _ready() -> void:
	randomize()
	velocity = Vector2.RIGHT.rotated(randf() * TAU) * speed

func _physics_process(delta: float) -> void:
	# --- Move & bounce ---
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal())

	# --- Animate based on velocity ---
	_update_animation()

	# --- Spot player? ---
	if player and _can_see_player(player):
		Transition.caught_and_restart()

func _update_animation() -> void:
	var v: Vector2 = velocity
	if v.length() > 0.01:
		# choose dominant axis (so diagonals pick a side)
		var axis_dir: Vector2
		if abs(v.x) > abs(v.y):
			axis_dir = Vector2(sign(v.x), 0)
		else:
			axis_dir = Vector2(0, sign(v.y))

		if axis_dir != last_dir:
			last_dir = axis_dir

		# play walk clips
		match axis_dir:
			Vector2.RIGHT: anim.play("walkRight")
			Vector2.LEFT:  anim.play("walkLeft")
			Vector2.UP:    anim.play("walkBack")   # up = back (facing away)
			_:             anim.play("walkFront")  # down = front
	else:
		# idle clips based on last_dir
		match last_dir:
			Vector2.RIGHT: anim.play("rightStill")
			Vector2.LEFT:  anim.play("leftStill")
			Vector2.UP:    anim.play("backStill")
			_:             anim.play("frontStill")

func _can_see_player(p: Node2D) -> bool:
	# 1) Distance
	var to_p: Vector2 = p.global_position - global_position
	if to_p.length() > view_distance:
		return false

	# 2) FOV angle (use velocity if moving; otherwise face last_dir)
	var facing: Vector2
	if velocity.length() > 0.001:
		facing = velocity.normalized()
	else:
		facing = _dir_to_vector(last_dir)
	var ang_deg: float = rad_to_deg(acos(clamp(facing.dot(to_p.normalized()), -1.0, 1.0)))
	if ang_deg > fov_deg * 0.5:
		return false

	# 3) Line of sight
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == p

func _dir_to_vector(d: Vector2) -> Vector2:
	# ensures we get a unit vector even if last_dir is cardinal
	if d == Vector2.ZERO:
		return Vector2.RIGHT
	return d.normalized()
