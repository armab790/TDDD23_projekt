extends CharacterBody2D

# --- Movement & pathing ---
@export var speed: float = 40.0
@export var chase_speed: float = 40.0
@export var wait_time: float = 0.0
@export var investigation_wait_time: float = 8.0
@export var chase_timeout: float = 15.0
@export var waypoints_path: NodePath
@onready var agent: NavigationAgent2D = $NavigationAgent2D

# --- Vision ---
@export var view_distance: float = 50.0
@export var fov_deg: float = 50.0
@export var catch_distance: float = 20.0   # must be within this distance AND in sight to catch

# --- Hearing (probabilistic with distance) ---
@export var hear_radius_fallback: float = 50.0
@export var prob_at_edge: float = 0.10     # reaction probability at max radius
@export var prob_at_center: float = 0.99   # reaction probability at source
@export var react_cooldown: float = 0.30
@export var hear_grace_time: float = 0.40

# --- Turning / animation ---
@export var turn_speed: float = 1.0
@export var move_threshold: float = 5.0
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var player: CharacterBody2D = get_node_or_null("../Player")

# --- Look-around at waypoints ---
@export var look_around_enabled: bool = true
@export var look_around_angle_deg: float = 35.0    # how far left/right to turn

var _look_around_phase: float = 0.0
var _look_around_base_angle: float = 0.0

# >>> Simple speech/bark settings
@export var bark_cooldown: float = 1.5              # min seconds between barks
@export var patrol_bark_interval: float = 12.0      # seconds between idle patrol barks
@export var speech_visible_time: float = 2.5        # how long a line stays visible
@export var speech_label_path: NodePath

var _bark_cooldown_timer: float = 0.0
var _patrol_bark_timer: float = 0.0
var _speech_timer: float = 0.0
@onready var speech_label: Label = get_node_or_null(speech_label_path)

# Remember last line to avoid immediate repeats
var _last_bark_text: String = ""

# --- Suspicion system (now mostly flavour) ---
@export var suspicion_build_rate: float = 1.2
@export var suspicion_decay_rate: float = 0.3
@export var suspicion_threshold: float = 1.0
@export var suspicion_min_to_investigate: float = 0.4
var _suspicion: float = 0.0

# --- Search pattern after losing player ---
@export var search_radius: float = 32.0
@export var search_points_count: int = 4
@export var max_search_time: float = 17.0

var _search_points: Array[Vector2] = []
var _search_index: int = -1
var _search_time: float = 0.0

# --- Stuck detection ---
@export var stuck_distance_threshold: float = 3.0
@export var stuck_time_threshold: float = 3.0
var _stuck_timer: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

# --- Guard smalltalk ---
@export var guard_chat_distance: float = 26.0
@export var guard_chat_cooldown: float = 9.0
var _guard_chat_timer: float = 0.0

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

func refresh_alert_fx() -> void:
	var pursuing := chasing_player or (investigating and investigating_player)
	_update_heartbeat(pursuing, true)

func _find_player() -> void:
	if player and is_instance_valid(player):
		return
	var p := get_tree().get_first_node_in_group("player")
	if p and p is CharacterBody2D:
		player = p

# -----------------------------
# Heartbeat & pulse
# -----------------------------
func _update_heartbeat(active: bool, force: bool = false) -> void:
	if heartbeat == null:
		return
	if (not force) and (_hb_on == active):
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
# Sound line-of-sight helper
# -----------------------------
func _has_clear_sound_path(pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, pos)
	query.exclude = [self]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true

	var collider = hit["collider"]
	if collider == player:
		return true

	# Anything else in between (walls, props) blocks the sound
	return false

# -----------------------------
# Simple bark / speech helpers
# -----------------------------
func _say_line(text: String) -> void:
	if _bark_cooldown_timer > 0.0:
		return
	_bark_cooldown_timer = bark_cooldown
	_speech_timer = speech_visible_time
	_last_bark_text = text

	if speech_label:
		speech_label.text = text
	else:
		print("[NPC]: ", text)

func _say_random(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	if lines.size() == 1:
		_say_line(lines[0])
		return

	var chosen: String = lines[randi() % lines.size()]
	var attempts := 0
	while chosen == _last_bark_text and attempts < 4:
		chosen = lines[randi() % lines.size()]
		attempts += 1

	_say_line(chosen)

# -----------------------------
# LLM-integrerad bark helper (2 argument)
# -----------------------------
func _say_with_llm(context: String, fallback_lines: Array[String]) -> void:
	# Respektera cooldown
	if _bark_cooldown_timer > 0.0:
		return

	# Om LLMDialogue inte finns eller saknar metoden → fallback
	if typeof(LLMDialogue) == TYPE_NIL or not LLMDialogue.has_method("request_guard_line"):
		_say_random(fallback_lines)
		return

	# Anropa LLMDialogue med (context, callback)
	var cb := Callable(self, "_apply_llm_line").bind(fallback_lines)
	LLMDialogue.request_guard_line(context, cb)

func _apply_llm_line(text: String, fallback_lines: Array[String]) -> void:
	var final_text := String(text).strip_edges()
	if final_text == "" or final_text == "...":
		_say_random(fallback_lines)
	else:
		_say_line(final_text)

# -----------------------------
# Ready
# -----------------------------
func _ready() -> void:
	add_to_group("enemies")
	randomize()
	last_dir = Vector2.DOWN
	facing_angle = last_dir.angle()
	_last_pos = global_position

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

	_find_player()
	_init_waypoints()

	# connect PLAYER noise to a dedicated handler
	if player and player.has_signal("noise_emitted"):
		if not player.is_connected("noise_emitted", Callable(self, "_on_player_noise")):
			player.connect("noise_emitted", Callable(self, "_on_player_noise"))

	# Resolve speech label (either via path or by name)
	if speech_label_path != NodePath():
		speech_label = get_node_or_null(speech_label_path)
	else:
		speech_label = get_node_or_null("SpeechLabel")

	if speech_label:
		speech_label.text = ""

	_patrol_bark_timer = patrol_bark_interval

# -----------------------------
# Waypoint init (robust)
# -----------------------------
func _init_waypoints() -> void:
	waypoints.clear()
	var container: Node = null

	if waypoints_path != NodePath():
		container = get_node_or_null(waypoints_path)
	else:
		if get_parent():
			container = get_parent().get_node_or_null("Waypoints")
		if container == null:
			container = get_node_or_null("Waypoints")

	if container:
		for c in container.get_children():
			if c is Node2D:
				waypoints.append(c.global_position)

	if waypoints.size() > 0:
		current_index = 0
		agent.target_position = waypoints[0]
	else:
		push_warning("%s has no waypoints (set 'waypoints_path' or add 'Waypoints' node)" % name)

# -----------------------------
# Behavior Tree helpers
# -----------------------------
func _reset_to_patrol() -> void:
	investigating = false
	investigating_player = false
	chasing_player = false
	investigation_timer = 0.0
	last_saw_player_timer = 0.0
	_suspicion = 0.0
	_search_points.clear()
	_search_index = -1
	_search_time = 0.0
	_stuck_timer = 0.0

	if waypoints.size() > 0:
		agent.target_position = waypoints[current_index]

	refresh_alert_fx()

# -----------------------------
# Guard alert broadcast
# -----------------------------
func _broadcast_alert(pos: Vector2) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self:
			continue
		if e.has_method("on_alert_from_guard"):
			e.on_alert_from_guard(pos)

func on_alert_from_guard(pos: Vector2) -> void:
	if chasing_player:
		return

	investigating = true
	investigating_player = true
	investigate_pos = pos
	agent.target_position = pos
	investigation_timer = 0.0

	_say_with_llm(
		"another guard has spotted something suspicious and calls for help",
		[
			"What's going on over there?",
			"He found something!",
			"I'm on my way.",
			"Trouble? Moving to assist."
		]
	)

# -----------------------------
# STUCK DETECTION
# -----------------------------
func _update_stuck(delta: float) -> void:
	if agent == null:
		_last_pos = global_position
		_stuck_timer = 0.0
		return

	var moved := global_position.distance_to(_last_pos)
	var dist_to_target := global_position.distance_to(agent.target_position)

	var intentionally_idle := waiting \
		or (investigating and (agent.is_navigation_finished() or dist_to_target <= 4.0))

	if intentionally_idle:
		_stuck_timer = 0.0
		_last_pos = global_position
		return

	var should_be_moving := chasing_player or (investigating and dist_to_target > 4.0)

	if should_be_moving and moved < stuck_distance_threshold:
		_stuck_timer += delta
		if _stuck_timer >= stuck_time_threshold:
			print("NPC stuck, resetting to patrol")
			_reset_to_patrol()
	else:
		_stuck_timer = 0.0

	_last_pos = global_position

# -----------------------------
# Guard smalltalk
# -----------------------------
func _update_guard_smalltalk() -> void:
	if _guard_chat_timer > 0.0:
		return
	if chasing_player or investigating:
		return

	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self:
			continue
		if not (e is Node2D):
			continue

		var dist := global_position.distance_to(e.global_position)
		if dist <= guard_chat_distance:
			_say_with_llm(
				"two tired guards briefly pass each other on patrol and exchange a short remark",
				[
					"You see anything?",
					"All quiet on your side?",
					"Same patrol, different night.",
					"Stay sharp, they could be anywhere.",
					"I'm freezing. You?",
					"If you see something, shout.",
					"Don't fall asleep on me.",
					"Switch with me later?",
					"Nothing on this side.",
					"Keep your eyes open."
				]
			)
			_guard_chat_timer = guard_chat_cooldown
			break

# -----------------------------
# Physics
# -----------------------------
func _physics_process(delta: float) -> void:
	_find_player()

	_hear_cooldown = maxf(0.0, _hear_cooldown - delta)
	_hear_grace = maxf(0.0, _hear_grace - delta)
	_bark_cooldown_timer = maxf(0.0, _bark_cooldown_timer - delta)
	_patrol_bark_timer = maxf(0.0, _patrol_bark_timer - delta)
	_guard_chat_timer = maxf(0.0, _guard_chat_timer - delta)

	_suspicion = maxf(0.0, _suspicion - suspicion_decay_rate * delta)

	if _speech_timer > 0.0:
		_speech_timer -= delta
		if _speech_timer <= 0.0 and speech_label:
			speech_label.text = ""

	_run_behavior_tree(delta)
	_update_stuck(delta)

	# Patrol muttering
	if not chasing_player and not investigating and _patrol_bark_timer <= 0.0:
		_say_with_llm(
			"a guard is walking alone on patrol in an underground facility, thinking quietly to themselves",
			[
				"Hmm… quiet.",
				"Another boring patrol.",
				"…Did I hear something?",
				"Stay sharp.",
				"Same route, same shadows.",
				"Nothing ever happens down here.",
				"If they catch me slacking, I'm done.",
				"I hate this shift.",
				"Feels like someone's watching me.",
				"Why is it always so cold here?",
				"Focus… just keep moving.",
				"One more round and I'm done."
			]
		)
		_patrol_bark_timer = patrol_bark_interval + randf_range(-4.0, 4.0)

	if not chasing_player and not investigating:
		_update_guard_smalltalk()

	var pursuing := chasing_player or (investigating and investigating_player)
	_update_heartbeat(pursuing)
	_update_animation()

# -----------------------------
# Root: Chase -> Investigate -> Patrol
# -----------------------------
func _run_behavior_tree(delta: float) -> void:
	if _bt_chase(delta):
		return
	if _bt_investigate(delta):
		return
	_bt_patrol(delta)

# -----------------------------
# BT: Chase
# -----------------------------
func _bt_chase(delta: float) -> bool:
	_find_player()
	if not player or not is_instance_valid(player):
		chasing_player = false
		return false

	var can_see := _can_see_player(player)
	var dist_to_player: float = global_position.distance_to(player.global_position)
	var dist_ok := dist_to_player <= catch_distance

	if can_see:
		last_player_pos = player.global_position
		last_saw_player_timer = 0.0
		_suspicion = suspicion_threshold

		if not chasing_player:
			chasing_player = true
			investigating = false
			investigating_player = true
			investigation_timer = 0.0

			_broadcast_alert(player.global_position)

			_say_with_llm(
				"a guard suddenly spots an intruder and starts chasing them",
				[
					"There you are!",
					"I see you!",
					"Got you now!",
					"Hey! Stop right there!",
					"You really thought you could sneak past me?",
					"Got eyes on the target!",
					"Found you!",
					"You shouldn't be here!",
					"There! Over there!",
					"I knew it!"
				]
			)

		if dist_ok and _hear_grace <= 0.0:
			Transition.caught_and_restart()
			return true

		agent.target_position = player.global_position
		_move_towards_smooth(agent.get_next_path_position(), delta, chase_speed)
		return true

	if chasing_player:
		last_saw_player_timer += delta

		if last_saw_player_timer < chase_timeout:
			agent.target_position = last_player_pos
			_move_towards_smooth(agent.get_next_path_position(), delta, chase_speed)
			return true
		else:
			print("Lost sight of player, starting search around last known position")
			chasing_player = false
			last_saw_player_timer = 0.0

			investigating = true
			investigating_player = true
			investigate_pos = last_player_pos
			investigation_timer = 0.0

			_search_points.clear()
			_search_index = -1
			_search_time = 0.0

			if search_points_count > 0 and search_radius > 4.0:
				for i in search_points_count:
					var angle := TAU * float(i) / float(search_points_count)
					var offset := Vector2.RIGHT.rotated(angle) * search_radius
					_search_points.append(last_player_pos + offset)

			agent.target_position = last_player_pos

			_say_with_llm(
				"a guard lost sight of the intruder and is frustrated, searching the area",
				[
					"Where did you go?",
					"You can't hide forever.",
					"I know you're here somewhere…",
					"Come out, I know you're close.",
					"Tch… slippery.",
					"You won't get far.",
					"Keep looking…",
					"They were just here…",
					"How did they vanish that fast?",
					"Stay alert, they’re still around."
				]
			)

			return false

	return false

# -----------------------------
# BT: Investigate
# -----------------------------
func _bt_investigate(delta: float) -> bool:
	if not investigating:
		return false

	_search_time += delta
	if _search_time >= max_search_time:
		_say_with_llm(
			"a guard gives up searching after not finding anything suspicious",
			[
				"Guess it was nothing.",
				"Hmm… must've been the wind.",
				"Back to patrol, I guess.",
				"False alarm…",
				"Wasting my time.",
				"Nothing here after all.",
				"Thought I had something.",
				"All clear… for now.",
				"I'll let it slide… this time.",
				"Back to the usual route."
			]
		)
		_reset_to_patrol()
		return false

	if not _search_points.is_empty():
		var close_enough := global_position.distance_to(agent.target_position) <= 4.0

		if agent.is_navigation_finished() or close_enough:
			_search_index += 1
			if _search_index >= _search_points.size():
				_say_with_llm(
					"a guard stops searching after checking a few spots and finding nothing",
					[
						"Guess it was nothing.",
						"Hmm… must've been the wind.",
						"Back to patrol, I guess.",
						"False alarm…",
						"Wasting my time.",
						"Nothing here after all.",
						"Thought I had something.",
						"All clear… for now.",
						"I'll let it slide… this time.",
						"Back to the usual route."
					]
				)
				_search_points.clear()
				_search_index = -1
				_reset_to_patrol()
				return false
			else:
				agent.target_position = _search_points[_search_index]
		else:
			_move_towards_smooth(agent.get_next_path_position(), delta, speed)

		return true

	var close_enough_simple := global_position.distance_to(agent.target_position) <= 4.0

	if agent.is_navigation_finished() or close_enough_simple:
		investigation_timer += delta
		if investigation_timer >= investigation_wait_time:
			print("Investigation done, back to patrol")

			_say_with_llm(
				"a guard waits a moment at the suspicious spot, then decides it was nothing",
				[
					"Guess it was nothing.",
					"Hmm… must've been the wind.",
					"Back to patrol, I guess.",
					"False alarm…",
					"Wasting my time.",
					"Nothing here after all.",
					"Thought I had something.",
					"All clear… for now.",
					"I'll let it slide… this time.",
					"Back to the usual route."
				]
			)

			_reset_to_patrol()
			return false
	else:
		_move_towards_smooth(agent.get_next_path_position(), delta, speed)

	return true

# -----------------------------
# BT: Patrol between waypoints
# -----------------------------
func _bt_patrol(_delta: float) -> void:
	if waypoints.is_empty():
		return

	if waiting:
		wait_timer -= _delta

		if look_around_enabled and wait_time > 0.1:
			var t := 1.0 - maxf(wait_timer, 0.0) / maxf(wait_time, 0.0001)
			var offset := sin(t * PI) * deg_to_rad(look_around_angle_deg)
			facing_angle = _look_around_base_angle + offset

		if wait_timer <= 0.0:
			waiting = false
			_next_waypoint()
		return

	var close_enough := global_position.distance_to(agent.target_position) <= 4.0

	if agent.is_navigation_finished() or close_enough:
		waiting = true
		wait_timer = wait_time

		if look_around_enabled and wait_time > 0.1:
			_look_around_phase = 0.0
			_look_around_base_angle = facing_angle
	else:
		_move_towards_smooth(agent.get_next_path_position(), _delta, speed)

func _next_waypoint() -> void:
	current_index = (current_index + 1) % waypoints.size()
	agent.target_position = waypoints[current_index]

# -----------------------------
# Latest-sound-wins helper
# -----------------------------
func _hear_noise_latest(pos: Vector2, is_player: bool) -> void:
	var stamp := Time.get_ticks_msec()
	if stamp <= _last_noise_stamp:
		return
	_last_noise_stamp = stamp

	investigating = true
	investigating_player = is_player
	investigate_pos = pos
	agent.target_position = pos
	investigation_timer = 0.0
	last_saw_player_timer = 0.0
	_hear_grace = hear_grace_time

	_search_points.clear()
	_search_index = -1
	_search_time = 0.0

	if is_player:
		chasing_player = false
		last_player_pos = pos

		_suspicion = minf(
			_suspicion + suspicion_min_to_investigate * 0.3,
			suspicion_min_to_investigate * 0.9
		)

		_say_with_llm(
			"a guard hears clear human footsteps nearby in the dark",
			[
				"I heard that.",
				"Those were footsteps…",
				"You're not as quiet as you think.",
				"Someone's there.",
				"That came from over there.",
				"You can't hide that sound.",
				"I definitely heard something.",
				"Those steps again…",
				"There—move!",
				"Keep making noise, see what happens."
			]
		)
	else:
		chasing_player = false
		_say_with_llm(
			"a guard hears a vague non-human noise, like a rock or the pipes, and decides to check it",
			[
				"Huh? What was that?",
				"Thought I heard something…",
				"A noise? Better check it out.",
				"That didn't sound right.",
				"Something moved.",
				"Was that the pipes…?",
				"That came from over there.",
				"Could be nothing… but I should check.",
				"I don't like that sound.",
				"Better not ignore that."
			]
		)

	_update_heartbeat(chasing_player or (investigating and investigating_player))

func hear_noise(pos: Vector2, is_player: bool = false) -> void:
	_hear_noise_latest(pos, is_player)

# -----------------------------
# Noise handlers (probabilistic + LOS)
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

func _should_react_to_noise(pos: Vector2, radius: float, loudness: float, priority: int) -> bool:
	if not _has_clear_sound_path(pos):
		return false

	var r: float = radius if radius > 0.0 else hear_radius_fallback
	var d: float = global_position.distance_to(pos)
	if d > r:
		return false

	var proximity: float = clampf(1.0 - (d / r), 0.0, 1.0)
	var proximity_boost: float = proximity * proximity
	var base_prob: float = lerpf(prob_at_edge, prob_at_center, proximity_boost)

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

	if distance < 0.001:
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
		move_and_slide()
		return

	var target_angle: float = to_target.angle()

	var angle_diff: float = target_angle - facing_angle
	while angle_diff > PI:
		angle_diff -= TAU
	while angle_diff < -PI:
		angle_diff += TAU

	var turn_amount: float = signf(angle_diff) * minf(absf(angle_diff), turn_speed * delta)
	facing_angle += turn_amount

	if distance < 0.1:
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
		move_and_slide()
		return

	var new_diff: float = target_angle - facing_angle
	while new_diff > PI:
		new_diff -= TAU
	while new_diff < -PI:
		new_diff += TAU

	var facing_alignment: float = absf(new_diff)
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
