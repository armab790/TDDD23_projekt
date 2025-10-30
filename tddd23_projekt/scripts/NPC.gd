extends CharacterBody2D

# --- Movement & pathing ---
@export var speed: float = 40.0
@export var chase_speed: float = 80.0  # Faster when chasing player
@export var wait_time: float = 0.0
@export var investigation_wait_time: float = 2.0  # How long to look around at noise location
@export var chase_timeout: float = 5.0  # Give up chasing if no visual contact for this long
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
var investigation_timer := 0.0
var chasing_player := false  # Are we actively chasing?
var last_saw_player_timer := 0.0  # NEW: Time since last visual contact
var last_player_pos := Vector2.ZERO  # NEW: Last known player position

# --- Heartbeat (investigate/pursue) --
@export_file("*.mp3") var heartbeat_path := "res://audios/SFX/Heartbeat.mp3"
@export var heartbeat_bus: String = "Master"
@export var heartbeat_max_db: float = -8.0     # loud when active
@export var heartbeat_min_db: float = -40.0    # effectively silent when inactive
@export var heartbeat_fade_in: float = 0.6
@export var heartbeat_fade_out: float = 0.8

@onready var heartbeat: AudioStreamPlayer2D = $Heartbeat
var _hb_on := false
var _hb_tw: Tween


var last_dir: Vector2 = Vector2.DOWN
var facing_angle: float = PI / 2  # Start facing down (90 degrees)
var _hear_cooldown := 0.0
var _hear_grace := 0.0

func _update_heartbeat(active: bool) -> void:
	if heartbeat == null:
		return
	if _hb_on == active:
		return
	_hb_on = active

	if _hb_tw:
		_hb_tw.kill()
	_hb_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var fx = get_tree().get_first_node_in_group("screen_fx")

	if active:
		if not heartbeat.playing:
			heartbeat.play()
		_hb_tw.tween_property(heartbeat, "volume_db", heartbeat_max_db, heartbeat_fade_in)
		if fx and fx.has_method("start_pulse"):
			fx.start_pulse(1.2, 0.36) # you can lower to 0.04 later
		else:
			print("[NPC] No ScreenFX found (group 'screen_fx').")
	else:
		_hb_tw.tween_property(heartbeat, "volume_db", heartbeat_min_db, heartbeat_fade_out)
		_hb_tw.tween_callback(Callable(heartbeat, "stop"))
		if fx and fx.has_method("stop_pulse"):
			fx.stop_pulse()


func _ready() -> void:
	add_to_group("enemies")
	randomize()
	last_dir = Vector2.DOWN
	facing_angle = last_dir.angle()
	
	# Heartbeat audio (create if missing)
	if heartbeat == null:
		heartbeat = AudioStreamPlayer2D.new()
		heartbeat.name = "Heartbeat"
		add_child(heartbeat)

	heartbeat.bus = heartbeat_bus
	heartbeat.autoplay = false
	heartbeat.volume_db = heartbeat_min_db

	if heartbeat.stream == null and ResourceLoader.exists(heartbeat_path):
		heartbeat.stream = load(heartbeat_path)
	# Try to loop (depends on stream type/import settings)
	if heartbeat.stream and heartbeat.stream.has_method("set_loop"):
		heartbeat.stream.set_loop(true)

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
		print("NPC has no waypoints!")

	# connect to player noise
	if player and player.has_signal("noise_emitted"):
		player.connect("noise_emitted", Callable(self, "_on_noise_emitted"))


func _physics_process(delta: float) -> void:
	_hear_cooldown = max(0.0, _hear_cooldown - delta)
	_hear_grace = max(0.0, _hear_grace - delta)

	# Check if we can see the player (before catching them)
	var can_see = player and _can_see_player(player)
	
	if can_see:
		last_saw_player_timer = 0.0  # Reset timer when we see them
		last_player_pos = player.global_position
		
		# If we see them and grace period is over, catch them
		if _hear_grace <= 0.0:
			Transition.caught_and_restart()
			return
	else:
		# Increment timer when we can't see them
		if chasing_player:
			last_saw_player_timer += delta

	if investigating:
		_process_investigation(delta)
	else:
		_process_patrol(delta)
		
	# Consider "pursuing" when investigating OR briefly after hearing (grace)
	var pursuing := investigating or (_hear_grace > 0.0)
	_update_heartbeat(pursuing)

	_update_animation()


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
		_move_towards_smooth(agent.get_next_path_position(), delta, speed)


func _next_waypoint() -> void:
	current_index = (current_index + 1) % waypoints.size()
	agent.target_position = waypoints[current_index]


# ----------------------------------------------------------------
# investigation behaviour
# ----------------------------------------------------------------
func _process_investigation(delta: float) -> void:
	# If chasing player, continuously update target
	if chasing_player and player:
		# Check if we've lost sight for too long
		if last_saw_player_timer >= chase_timeout:
			print("⏰ Lost sight of player, investigating last known position")
			# Switch to investigating last known position
			chasing_player = false
			agent.target_position = last_player_pos
			investigation_timer = 0.0
			return
		
		# Still chasing - update target to current player position
		agent.target_position = player.global_position
		_move_towards_smooth(agent.get_next_path_position(), delta, chase_speed)
		return
	
	# Otherwise, investigating a static position (rock/footstep/last known position)
	if agent.is_navigation_finished():
		# Reached the noise location, look around for a bit
		investigation_timer += delta
		if investigation_timer >= investigation_wait_time:
			investigating = false
			chasing_player = false
			investigation_timer = 0.0
			last_saw_player_timer = 0.0
			print("👀 Investigation done, returning to patrol")
			if waypoints.size() > 0:
				agent.target_position = waypoints[current_index]
	else:
		_move_towards_smooth(agent.get_next_path_position(), delta, speed)


func hear_noise(pos: Vector2, is_player: bool = false) -> void:
	investigating = true
	investigate_pos = pos
	agent.target_position = pos
	chasing_player = is_player  # Track if this is the player or just a noise
	investigation_timer = 0.0
	last_saw_player_timer = 0.0  # Reset the timer when we start investigating
	_hear_grace = hear_grace_time
	
	if is_player:
		last_player_pos = pos  # Store last known position
		print("🔊 Enemy heard PLAYER at ", pos)
	else:
		print("🔊 Enemy heard noise at ", pos)


# ----------------------------------------------------------------
# SMOOTH MOVEMENT with turning
# ----------------------------------------------------------------
func _move_towards_smooth(target_pos: Vector2, delta: float, current_speed: float) -> void:
	var to_target = target_pos - global_position
	var distance = to_target.length()
	
	if distance < 0.1:
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
		velocity = move_dir * current_speed
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
		# Check if this noise is from the player
		var is_player_noise = false
		if player:
			is_player_noise = player.global_position.distance_to(pos) < 5.0
		
		hear_noise(pos, is_player_noise)
		_hear_cooldown = react_cooldown
