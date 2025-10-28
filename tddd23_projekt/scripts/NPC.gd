extends CharacterBody2D

@export var speed: float = 50.0

# --- Vision settings ---
@export var view_distance: float = 100.0
@export var fov_deg: float = 50.0

# --- Hearing settings ---
@export var hear_radius_fallback: float = 120.0
@export var prob_at_edge: float = 0.15
@export var prob_at_center: float = 0.85
@export var react_cooldown: float = 0.30

# --- Smooth turning reaction ---
@export var turn_rate_rad: float = 1.0       # radians per second
@export var turn_accel: float = 0.20         # how fast velocity blends toward facing
@export var hear_grace_time: float = 0.40    # seconds grace after hearing noise

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var player: CharacterBody2D = get_node_or_null("../Player")

# --- State ---
var last_dir: Vector2 = Vector2.DOWN
var facing_dir: Vector2 = Vector2.DOWN
var _hear_cooldown: float = 0.0
var _hear_grace: float = 0.0
var _turning_to_noise: bool = false
var _turn_target: Vector2 = Vector2.ZERO


# ----------------------------------------------------
# Ready
# ----------------------------------------------------
func _ready() -> void:
	randomize()
	facing_dir = Vector2.DOWN
	last_dir = facing_dir
	velocity = Vector2.RIGHT.rotated(randf() * TAU) * speed

	# Listen to player noise signal
	if player and player.has_signal("noise_emitted"):
		player.connect("noise_emitted", Callable(self, "_on_noise_emitted"))


# ----------------------------------------------------
# Physics
# ----------------------------------------------------
func _physics_process(delta: float) -> void:
	_hear_cooldown = max(0.0, _hear_cooldown - delta)
	_hear_grace = max(0.0, _hear_grace - delta)

	# --- Smooth turn toward noise if reacting ---
	if _turning_to_noise:
		var current_angle := facing_dir.angle()
		var target_angle := _turn_target.angle()
		var diff := wrapf(target_angle - current_angle, -PI, PI)
		var max_step := turn_rate_rad * delta
		var step := clampf(diff, -max_step, max_step)

		# Rotate facing gradually
		var new_angle := current_angle + step
		facing_dir = Vector2(cos(new_angle), sin(new_angle)).normalized()
		last_dir = facing_dir

		# Steer softly in facing direction
		velocity = velocity.lerp(facing_dir * speed * 0.6, turn_accel)

		# Stop turning when close enough
		if abs(diff) < 0.03:
			_turning_to_noise = false

	# --- Movement + bounce ---
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal())

	# --- Animation ---
	_update_animation()

	# --- Catch player only if not in grace period ---
	if _hear_grace <= 0.0 and player and _can_see_player(player):
		Transition.caught_and_restart()


# ----------------------------------------------------
# Animation
# ----------------------------------------------------
func _update_animation() -> void:
	var v := velocity
	if v.length() > 0.01 and not _turning_to_noise:
		var axis_dir: Vector2
		if abs(v.x) > abs(v.y):
			axis_dir = Vector2(sign(v.x), 0)
		else:
			axis_dir = Vector2(0, sign(v.y))
		if axis_dir != last_dir:
			last_dir = axis_dir

	if v.length() > 0.01:
		match last_dir:
			Vector2.RIGHT: anim.play("walkRight")
			Vector2.LEFT:  anim.play("walkLeft")
			Vector2.UP:    anim.play("walkBack")
			_:             anim.play("walkFront")
	else:
		match last_dir:
			Vector2.RIGHT: anim.play("rightStill")
			Vector2.LEFT:  anim.play("leftStill")
			Vector2.UP:    anim.play("backStill")
			_:             anim.play("frontStill")


# ----------------------------------------------------
# Vision
# ----------------------------------------------------
func _can_see_player(p: Node2D) -> bool:
	var to_p: Vector2 = p.global_position - global_position
	if to_p.length() > view_distance:
		return false

	var facing: Vector2
	if velocity.length() > 0.001:
		facing = velocity.normalized()
	else:
		facing = facing_dir

	var ang_deg: float = rad_to_deg(acos(clamp(facing.dot(to_p.normalized()), -1.0, 1.0)))
	if ang_deg > fov_deg * 0.5:
		return false

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == p


# ----------------------------------------------------
# Hearing
# ----------------------------------------------------
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
		return

	var strength: float = 1.0 - (d / r)
	var weight: float = clamp(loudness, 0.0, 1.0) * clamp(float(priority), 0.5, 3.0)
	var base_prob: float = lerp(prob_at_edge, prob_at_center, strength)
	var react_prob: float = clamp(base_prob * (0.6 + 0.4 * weight), 0.0, 1.0)

	if randf() <= react_prob:
		var dir: Vector2 = (pos - global_position).normalized()
		_turn_target = dir
		_turning_to_noise = true
		_hear_grace = hear_grace_time
		velocity = velocity.lerp(dir * (speed * 0.3), 0.15)
		_hear_cooldown = react_cooldown



# ----------------------------------------------------
# Helpers
# ----------------------------------------------------
func _dir_to_vector(d: Vector2) -> Vector2:
	if d == Vector2.ZERO:
		return Vector2.RIGHT
	return d.normalized()
