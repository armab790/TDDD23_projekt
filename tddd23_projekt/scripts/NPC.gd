extends CharacterBody2D

# --- Movement & pathing ---
@export var speed: float = 80.0
@export var wait_time: float = 1.2
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
@export var turn_rate_rad: float = 1.0
@export var turn_accel: float = 0.20
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
var facing_dir: Vector2 = Vector2.DOWN
var _hear_cooldown := 0.0
var _hear_grace := 0.0
var _turning_to_noise := false
var _turn_target: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("enemies")  # ADD THIS LINE
	randomize()
	facing_dir = Vector2.DOWN
	last_dir = facing_dir

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
		print("✅ Reached waypoint ", current_index, " at ", global_position)
		waiting = true
		wait_timer = wait_time
	else:
		var next_pos = agent.get_next_path_position()
		var distance_to_next = global_position.distance_to(next_pos)
		
		# Debug when stuck
		if velocity.length() < 1.0 and distance_to_next > 5.0:
			print("⚠️ Stuck at ", global_position, " trying to reach ", agent.target_position)
			print("   Next path point: ", next_pos, " (dist: ", distance_to_next, ")")
		
		_move_towards(next_pos, delta)


func _next_waypoint() -> void:
	current_index = (current_index + 1) % waypoints.size()
	agent.target_position = waypoints[current_index]


# ----------------------------------------------------------------
# investigation behaviour
# ----------------------------------------------------------------
func _process_investigation(delta: float) -> void:
	if agent.is_navigation_finished():
		investigating = false
		print("👀 Investigation done, returning to patrol")
		if waypoints.size() > 0:
			agent.target_position = waypoints[current_index]
	else:
		_move_towards(agent.get_next_path_position(), delta)


func hear_noise(pos: Vector2) -> void:
	investigating = true
	investigate_pos = pos
	agent.target_position = pos
	_hear_grace = hear_grace_time
	print("🔊 Enemy heard noise at ", pos)


# ----------------------------------------------------------------
# shared movement + animation helpers
# ----------------------------------------------------------------
func _move_towards(target_pos: Vector2, delta: float) -> void:
	var dir = target_pos - global_position
	var distance = dir.length()
	
	if distance > agent.target_desired_distance:
		velocity = dir.normalized() * speed
	else:
		velocity = Vector2.ZERO
	
	# This is the key - move_and_slide() handles collisions
	move_and_slide()
	
	# If stuck (colliding), try to get unstuck
	if get_slide_collision_count() > 0:
		var collision = get_slide_collision(0)
		var slide_dir = velocity.slide(collision.get_normal())
		velocity = slide_dir


func _update_animation() -> void:
	var v := velocity
	if v.length() > 0.01:
		var axis_dir: Vector2
		if abs(v.x) > abs(v.y):
			axis_dir = Vector2(sign(v.x), 0)
		else:
			axis_dir = Vector2(0, sign(v.y))
		last_dir = axis_dir

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
# vision + hearing (same as before)
# ----------------------------------------------------------------
func _can_see_player(p: Node2D) -> bool:
	var to_p: Vector2 = p.global_position - global_position
	if to_p.length() > view_distance:
		return false

	var facing: Vector2 = facing_dir if velocity.length() < 0.001 else velocity.normalized()
	var ang_deg = rad_to_deg(acos(clamp(facing.dot(to_p.normalized()), -1.0, 1.0)))
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
		
