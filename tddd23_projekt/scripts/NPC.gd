extends CharacterBody2D

# --- Movement & pathing ---
@export var speed: float = 40.0
@export var wait_time: float = 0.0
@export var waypoints_path: NodePath
@onready var agent: NavigationAgent2D = $NavigationAgent2D

# --- Vision ---
@export var view_distance: float = 100.0
@export var fov_deg: float = 50.0

# --- Hearing ---
@export var hear_radius_fallback: float = 120.0
@export var prob_at_edge: float = 0.15
@export var prob_at_center: float = 0.85
@export var react_cooldown: float = 0.30
@export var hear_grace_time: float = 0.40

# --- Turning / animation ---
@export var turn_speed: float = 1.0  # How fast to turn (radians per second)
@export var move_threshold: float = 5.0  # Don't move until mostly facing target
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var player: CharacterBody2D = get_node_or_null("../Player")

# --- State ---
var waypoints: Array[Vector2] = []
var current_index := 0
var waiting := false
var wait_timer := 0.0
var investigating := false
var investigate_pos := Vector2.ZERO

var last_dir: Vector2 = Vector2.DOWN
var facing_angle: float = PI / 2  # Start facing down (90 degrees)
var _hear_cooldown := 0.0
var _hear_grace := 0.0


func _ready() -> void:
	add_to_group("enemies")
	randomize()
	last_dir = Vector2.DOWN
	facing_angle = last_dir.angle()

	# collect waypoints
	if waypoints_path != NodePath():
		var container = get_node_or_null(waypoints_path)
		if container:
			for c in container.get_children():
				if c is Node2D:
					waypoints.append(c.global_position)

	if waypoints.size() > 0:
		current_index = 0
		agent.target_position = waypoints[0]
	else:
		print("⚠️ NPC has no waypoints!")

	# connect to player noise
	if player and player.has_signal("noise_emitted"):
		player.connect("noise_emitted", Callable(self, "_on_noise_emitted"))


func _physics_process(delta: float) -> void:
	_hear_cooldown = max(0.0, _hear_cooldown - delta)
	_hear_grace = max(0.0, _hear_grace - delta)

	if investigating:
		_process_investigation(delta)
	else:
		_process_patrol(delta)

	_update_animation()

	if _hear_grace <= 0.0 and player and _can_see_player(player):
		Transition.caught_and_restart()


# ----------------------------------------------------------------
# patrol behaviour
# ----------------------------------------------------------------
func _process_patrol(delta: float) -> void:
	if waypoints.is_empty():
		return

	if waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			waiting = false
			_next_waypoint()
		return

	if agent.is_navigation_finished():
		waiting = true
		wait_timer = wait_time
	else:
		_move_towards_smooth(agent.get_next_path_position(), delta)


func _next_waypoint() -> void:
	current_index = (current_index + 1) % waypoints.size()
	agent.target_position = waypoints[current_index]


# ----------------------------------------------------------------
# investigation behaviour
# ----------------------------------------------------------------
func _process_investigation(delta: float) -> void:
	# Update target if chasing player
	if player and investigating:
		agent.target_position = player.global_position
	
	if agent.is_navigation_finished():
		investigating = false
		print("👀 Investigation done, returning to patrol")
		if waypoints.size() > 0:
			agent.target_position = waypoints[current_index]
	else:
		_move_towards_smooth(agent.get_next_path_position(), delta)


func hear_noise(pos: Vector2) -> void:
	investigating = true
	investigate_pos = pos
	agent.target_position = pos
	_hear_grace = hear_grace_time
	print("🔊 Enemy heard noise at ", pos)


# ----------------------------------------------------------------
# SMOOTH MOVEMENT with turning
# ----------------------------------------------------------------
func _move_towards_smooth(target_pos: Vector2, delta: float) -> void:
	var to_target = target_pos - global_position
	var distance = to_target.length()
	
	if distance < 1.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	var target_angle = to_target.angle()
	
	# Smooth turn towards target
	var angle_diff = _angle_difference(facing_angle, target_angle)
	var turn_amount = sign(angle_diff) * min(abs(angle_diff), turn_speed * delta)
	facing_angle += turn_amount
	
	# Only move if mostly facing the target
	var facing_alignment = abs(angle_diff)
	if facing_alignment < deg_to_rad(move_threshold):
		# Move forward in facing direction
		var move_dir = Vector2.from_angle(facing_angle)
		velocity = move_dir * speed
	else:
		# Still turning, slow down or stop
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
	
	move_and_slide()


# Get shortest angle difference (handles wrapping)
func _angle_difference(from: float, to: float) -> float:
	var diff = to - from
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	return diff


# ----------------------------------------------------------------
# ANIMATION based on facing direction
# ----------------------------------------------------------------
func _update_animation() -> void:
	# Convert facing angle to cardinal direction
	var facing_dir = Vector2.from_angle(facing_angle)
	
	var axis_dir: Vector2
	if abs(facing_dir.x) > abs(facing_dir.y):
		axis_dir = Vector2(sign(facing_dir.x), 0)
	else:
		axis_dir = Vector2(0, sign(facing_dir.y))
	
	last_dir = axis_dir
	
	# Play animation based on movement
	if velocity.length() > 0.5:
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


# ----------------------------------------------------------------
# vision + hearing
# ----------------------------------------------------------------
func _can_see_player(p: Node2D) -> bool:
	var to_p: Vector2 = p.global_position - global_position
	if to_p.length() > view_distance:
		return false

	var facing_dir = Vector2.from_angle(facing_angle)
	var ang_deg = rad_to_deg(acos(clamp(facing_dir.dot(to_p.normalized()), -1.0, 1.0)))
	if ang_deg > fov_deg * 0.5:
		return false

	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.exclude = [self]
	var hit = space.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == p


func _on_noise_emitted(pos: Vector2, radius: float, loudness: float, priority: int) -> void:
	if _hear_cooldown > 0.0:
		return

	var r = radius if radius > 0.0 else hear_radius_fallback
	var d = global_position.distance_to(pos)
	if d > r:
		return

	var strength = 1.0 - (d / r)
	var weight = clamp(loudness, 0.0, 1.0) * clamp(float(priority), 0.5, 3.0)
	var base_prob = lerp(prob_at_edge, prob_at_center, strength)
	var react_prob = clamp(base_prob * (0.6 + 0.4 * weight), 0.0, 1.0)

	if randf() <= react_prob:
		hear_noise(pos)
		_hear_cooldown = react_cooldown
