extends CharacterBody2D

@export var speed: float = 50.0

# --- Detection settings ---
@export var view_distance: float = 100.0
@export var fov_deg: float = 50.0

@onready var player: CharacterBody2D = get_node_or_null("../Player")
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# Where the NPC faces when idle (cardinal)
var last_dir: Vector2 = Vector2.DOWN

# --- NEW: hearing + reaction tuning ---
@export var hear_radius_fallback: float = 120.0  # used if player sends 0
@export var prob_at_edge: float = 0.15           # chance to react at edge of radius
@export var prob_at_center: float = 0.85         # chance to react when very close
@export var turn_only_threshold: float = 0.35    # below this, just turn/lean; above, move toward
@export var react_cooldown: float = 0.30         # seconds; avoid reacting to every step
var _hear_cooldown: float = 0.0

func _ready() -> void:
	randomize()
	velocity = Vector2.RIGHT.rotated(randf() * TAU) * speed
	# listen to player footsteps (noise_emitted)
	if player and player.has_signal("noise_emitted"):
		player.connect("noise_emitted", Callable(self, "_on_noise_emitted"))

func _physics_process(delta: float) -> void:
	# cooldown tick for hearing reactions
	_hear_cooldown = max(0.0, _hear_cooldown - delta)

	# --- Move & bounce (unchanged) ---
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal())

	# --- Animate based on velocity (unchanged) ---
	_update_animation()

	# --- Spot player? (unchanged) ---
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

# --- NEW: react to footsteps / noises ---
func _on_noise_emitted(pos: Vector2, radius: float, loudness: float, priority: int) -> void:
	if _hear_cooldown > 0.0:
		return

	var r: float
	if radius > 0.0:
		r = radius
	else:
		r = hear_radius_fallback
	var d: float = global_position.distance_to(pos)
	if d > r:
		return  # out of range

	# Strength 0..1: 1 at the sound source, 0 at radius edge
	var strength: float = 1.0 - (d / r)

	# Weight from loudness (0..1) and priority (e.g., 1 footsteps, 2 doors)
	var weight: float = clamp(loudness, 0.0, 1.0) * clamp(float(priority), 0.5, 3.0)

	# Probability increases toward the center and with weight
	var base_prob: float = lerp(prob_at_edge, prob_at_center, strength)
	var react_prob: float = clamp(base_prob * (0.6 + 0.4 * weight), 0.0, 1.0)

	if randf() <= react_prob:
		var dir: Vector2 = (pos - global_position).normalized()
		if strength < turn_only_threshold:
			# subtle: lean/turn toward sound without fully committing
			velocity = velocity.lerp(dir * speed, 0.35)
		else:
			# commit: head toward the sound
			velocity = dir * speed

		_hear_cooldown = react_cooldown
