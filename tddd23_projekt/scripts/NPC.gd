extends CharacterBody2D

# --- Movement & pathing ---
@export var speed: float = 40.0
@export var chase_speed: float = 50.0
@export var wait_time: float = 0.0
@export var investigation_wait_time: float = 2.0
@export var chase_timeout: float = 5.0
@export var waypoints_path: NodePath
@onready var agent: NavigationAgent2D = $NavigationAgent2D

# --- Vision ---
@export var view_distance: float = 100.0
@export var fov_deg: float = 50.0
@export var catch_distance: float = 22.0   # must be within this distance AND in sight to catch

# --- Hearing (probabilistic with distance) ---
@export var hear_radius_fallback: float = 100.0
@export var prob_at_edge: float = 0.10     # reaction probability at max radius
@export var prob_at_center: float = 0.85   # reaction probability at source
@export var react_cooldown: float = 0.30
@export var hear_grace_time: float = 0.40

# --- Turning / animation ---
@export var turn_speed: float = 1.0
@export var move_threshold: float = 5.0
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var player: CharacterBody2D = get_node_or_null("../Player")

# --- State ---
var waypoints: Array[Vector2] = []
var current_index := 0
var waiting := false
var wait_timer := 0.0

var investigating := false
var investigating_player := false
var investigate_pos := Vector2.ZERO
var investigation_timer := 0.0

var chasing_player := false
var last_saw_player_timer := 0.0
var last_player_pos := Vector2.ZERO

# Track latest noise so “latest wins”
var _last_noise_stamp: int = 0

# --- Heartbeat (investigate/pursue only for player) ---
@export_file("*.mp3") var heartbeat_path := "res://audios/SFX/Heartbeat.mp3"
@export var heartbeat_bus: String = "Master"
@export var heartbeat_max_db: float = -8.0
@export var heartbeat_min_db: float = -40.0
@export var heartbeat_fade_in: float = 0.6
@export var heartbeat_fade_out: float = 0.8

@onready var heartbeat: AudioStreamPlayer2D = $Heartbeat
var _hb_on := false
var _hb_tw: Tween

var last_dir: Vector2 = Vector2.DOWN
var facing_angle: float = PI / 2
var _hear_cooldown := 0.0
var _hear_grace := 0.0

# Cached ScreenFX
var _fx_cached: Node = null
func _get_screen_fx() -> Node:
	if _fx_cached and is_instance_valid(_fx_cached):
		return _fx_cached
	_fx_cached = get_tree().get_first_node_in_group("screen_fx")
	return _fx_cached

# -----------------------------
# Heartbeat & pulse
# -----------------------------
func _update_heartbeat(active: bool) -> void:
	if heartbeat == null:
		return
	if _hb_on == active:
		return
	_hb_on = active

	if _hb_tw:
		_hb_tw.kill()
	_hb_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var fx := _get_screen_fx()

	if active:
		if not heartbeat.playing:
			heartbeat.play()
		_hb_tw.tween_property(heartbeat, "volume_db", heartbeat_max_db, heartbeat_fade_in)
		if fx and fx.has_method("start_pulse"):
			fx.start_pulse(1.1, 0.36)
	else:
		_hb_tw.tween_property(heartbeat, "volume_db", heartbeat_min_db, heartbeat_fade_out)
		_hb_tw.tween_callback(Callable(heartbeat, "stop"))
		if fx and fx.has_method("stop_pulse"):
			fx.stop_pulse()

# -----------------------------
# Ready
# -----------------------------
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

	# connect PLAYER noise to a dedicated handler
	if player and player.has_signal("noise_emitted"):
		player.connect("noise_emitted", Callable(self, "_on_player_noise"))

# -----------------------------
# Physics
# -----------------------------
func _physics_process(delta: float) -> void:
	_hear_cooldown = max(0.0, _hear_cooldown - delta)
	_hear_grace = max(0.0, _hear_grace - delta)

	var can_see := player and _can_see_player(player)
	var dist_ok := false
	if player:
		dist_ok = global_position.distance_to(player.global_position) <= catch_distance

	if can_see:
		# Lock onto player but only catch if close enough
		chasing_player = true
		last_saw_player_timer = 0.0
		last_player_pos = player.global_position

		# Catch only when within distance AND grace expired
		if dist_ok and _hear_grace <= 0.0:
			Transition.caught_and_restart()
			return
	else:
		if chasing_player:
			last_saw_player_timer += delta

	if investigating:
		_process_investigation(delta)
	else:
		_process_patrol(delta)

	# Heartbeat/pulse ONLY for the player (chase or player-investigation)
	var pursuing := chasing_player or (investigating and investigating_player)
	_update_heartbeat(pursuing)

	_update_animation()

# -----------------------------
# Patrol
# -----------------------------
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

# -----------------------------
# Investigation / Chase
# -----------------------------
func _process_investigation(delta: float) -> void:
	# Chasing player live
	if chasing_player and player:
		if last_saw_player_timer >= chase_timeout:
			print("Lost sight of player, go to last known position")
			chasing_player = false
			investigating = true
			investigating_player = true
			agent.target_position = last_player_pos
			investigation_timer = 0.0
			return

		agent.target_position = player.global_position
		_move_towards_smooth(agent.get_next_path_position(), delta, chase_speed)
		return

	# Investigating a static spot (noise / last known)
	if agent.is_navigation_finished():
		investigation_timer += delta
		if investigation_timer >= investigation_wait_time:
			investigating = false
			investigating_player = false
			chasing_player = false
			investigation_timer = 0.0
			last_saw_player_timer = 0.0
			print("Investigation done, back to patrol")
			if waypoints.size() > 0:
				agent.target_position = waypoints[current_index]
	else:
		_move_towards_smooth(agent.get_next_path_position(), delta, speed)

# -----------------------------
# Latest-sound-wins helper
# -----------------------------
func _hear_noise_latest(pos: Vector2, is_player: bool) -> void:
	var stamp := Time.get_ticks_msec()
	if stamp <= _last_noise_stamp:
		return  # ignore older (or same) reports
	_last_noise_stamp = stamp

	investigating = true
	investigating_player = is_player
	investigate_pos = pos
	agent.target_position = pos
	investigation_timer = 0.0
	last_saw_player_timer = 0.0
	_hear_grace = hear_grace_time

	if is_player:
		chasing_player = true
		last_player_pos = pos
	else:
		chasing_player = false  # rock overrides chase

	_update_heartbeat(chasing_player or (investigating and investigating_player))

# Called by external sources:
func hear_noise(pos: Vector2, is_player: bool = false) -> void:
	_hear_noise_latest(pos, is_player)

# -----------------------------
# Noise handlers (probabilistic)
# -----------------------------
func _on_player_noise(pos: Vector2, radius: float, loudness: float, priority: int) -> void:
	if _hear_cooldown > 0.0:
		return
	if _should_react_to_noise(pos, radius, loudness, priority):
		_hear_noise_latest(pos, true)
		_hear_cooldown = react_cooldown

func _on_noise_emitted(pos: Vector2, radius: float, loudness: float, priority: int) -> void:
	if _hear_cooldown > 0.0:
		return
	if _should_react_to_noise(pos, radius, loudness, priority):
		_hear_noise_latest(pos, false)
		_hear_cooldown = react_cooldown

# Distance-aware probability. Farther = lower chance to react.
func _should_react_to_noise(pos: Vector2, radius: float, loudness: float, priority: int) -> bool:
	var r: float = radius if radius > 0.0 else hear_radius_fallback
	var d: float = global_position.distance_to(pos)
	if d > r:
		return false

	# 0..1 proximity (1 near, 0 at edge) with quicker falloff
	var proximity: float = clampf(1.0 - (d / r), 0.0, 1.0)
	var proximity_boost: float = proximity * proximity

	# Base probability blended by proximity
	var base_prob: float = lerpf(prob_at_edge, prob_at_center, proximity_boost)

	# Loudness/priority weighting
	var pr: float = clampf(float(priority), 0.5, 3.0)
	var weight: float = clampf(loudness, 0.0, 1.5) * (0.7 + 0.3 * pr)

	var p: float = clampf(base_prob * weight, 0.0, 1.0)
	return randf() < p


# -----------------------------
# Movement + Animation
# -----------------------------
func _move_towards_smooth(target_pos: Vector2, delta: float, current_speed: float) -> void:
	var to_target: Vector2 = target_pos - global_position
	var distance: float = to_target.length()

	if distance < 0.1:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target_angle: float = to_target.angle()

	# Smooth turn towards target (normalize angle diff to [-PI, PI])
	var angle_diff: float = target_angle - facing_angle
	while angle_diff > PI:
		angle_diff -= TAU
	while angle_diff < -PI:
		angle_diff += TAU

	var turn_amount: float = signf(angle_diff) * minf(absf(angle_diff), turn_speed * delta)
	facing_angle += turn_amount

	# Only move if mostly facing the target
	var facing_alignment: float = absf(angle_diff)
	if facing_alignment < deg_to_rad(move_threshold):
		var move_dir: Vector2 = Vector2.from_angle(facing_angle)
		velocity = move_dir * current_speed
	else:
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)

	move_and_slide()


func _angle_difference(from: float, to: float) -> float:
	var diff := to - from
	while diff > PI:  diff -= TAU
	while diff < -PI: diff += TAU
	return diff

func _update_animation() -> void:
	var facing_dir := Vector2.from_angle(facing_angle)

	var axis_dir: Vector2
	if abs(facing_dir.x) > abs(facing_dir.y):
		axis_dir = Vector2(signf(facing_dir.x), 0.0)
	else:
		axis_dir = Vector2(0.0, signf(facing_dir.y))

	last_dir = axis_dir

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

# -----------------------------
# Vision
# -----------------------------
func _can_see_player(p: Node2D) -> bool:
	var to_p: Vector2 = p.global_position - global_position
	if to_p.length() > view_distance:
		return false

	var facing_dir := Vector2.from_angle(facing_angle)
	var ang_deg := rad_to_deg(acos(clamp(facing_dir.dot(to_p.normalized()), -1.0, 1.0)))
	if ang_deg > fov_deg * 0.5:
		return false

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == p
