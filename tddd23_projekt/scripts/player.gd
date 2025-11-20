extends CharacterBody2D

signal noise_emitted(pos: Vector2, radius: float, loudness: float, priority: int)

const SPEED := 65.0
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# NEW: footstep audio + cadence
@onready var foot: AudioStreamPlayer2D = $Footsteps
@onready var step_timer: Timer = $StepTimer

var rocks_in_inventory: int = 0

@export var walk_step_interval: float = 0.38          # seconds between steps while moving
@export var footstep_hear_radius_walk: float = 120.0  # how far NPCs can "hear" a step
@export var footstep_pitch_jitter: float = 0.08       # +- pitch variance for variety
@export var footstep_priority: int = 1                # AI weight (doors/explosions could be >1)

var last_dir: Vector2 = Vector2.DOWN  # where we're facing when idle
var _moving_strength := 0.0           # 0..1 how hard we're moving (for cadence)

@onready var noise_ring: Node2D = $NoiseRing

# NEW: Footstep mark FX prefab (change path if different in your project)
const ROCK_SCENE := preload("res://scenes/Rock.tscn")
const FOOTSTEP_MARK_SCENE := preload("res://scenes/FootstepMark.tscn")

@export var throw_cooldown := 0.35
var _can_throw := true


func _ready() -> void:
	add_to_group("player")
	# hook step timer (safe even if already connected)
	if not step_timer.timeout.is_connected(_on_step_timer):
		step_timer.timeout.connect(_on_step_timer)


func _unhandled_input(event: InputEvent) -> void:
	# Face instantly when a key is pressed
	if event.is_action_pressed("ui_right"):
		_set_face(Vector2.RIGHT)
	elif event.is_action_pressed("ui_left"):
		_set_face(Vector2.LEFT)
	elif event.is_action_pressed("ui_down"):
		_set_face(Vector2.DOWN)
	elif event.is_action_pressed("ui_up"):
		_set_face(Vector2.UP)
	elif event.is_action_pressed("throw"):
		_try_throw()


func _physics_process(_delta: float) -> void:
	# Movement input (built-in helper for 2D axes)
	var input_vec: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_vec * SPEED
	move_and_slide()

	# --- footstep cadence control ---
	_moving_strength = input_vec.length()

	noise_ring.set_radius(footstep_hear_radius_walk)
	# noise_ring.visible = _moving_strength > 0.01

	if _moving_strength > 0.01:
		step_timer.wait_time = walk_step_interval
		if step_timer.is_stopped():
			step_timer.start()
	else:
		step_timer.stop()

	# Animation
	if input_vec != Vector2.ZERO:
		var axis_dir: Vector2
		if abs(input_vec.x) > abs(input_vec.y):
			axis_dir = Vector2(sign(input_vec.x), 0)
		else:
			axis_dir = Vector2(0, sign(input_vec.y))

		if axis_dir != last_dir:
			_set_face(axis_dir)

		anim.play("walking_%s" % _vec_to_cardinal(axis_dir))
	else:
		anim.play("idle_%s" % _vec_to_cardinal(last_dir))


func _set_face(v: Vector2) -> void:
	last_dir = v
	# If you only have right-facing art, flip horizontally here:
	# anim.flip_h = (v == Vector2.LEFT)
	# Show idle frame immediately when stopped
	if velocity == Vector2.ZERO:
		anim.play("idle_%s" % _vec_to_cardinal(last_dir))


func _vec_to_cardinal(v: Vector2) -> String:
	if v.y > 0.0:
		return "down"
	elif v.y < 0.0:
		return "up"
	elif v.x < 0.0:
		return "left"
	else:
		return "right"

func _try_throw() -> void:
	# If we already have a rock, throw it
	if rocks_in_inventory > 0:
		if not _can_throw:
			return

		_can_throw = false
		_throw_rock()
		rocks_in_inventory -= 1

		await get_tree().create_timer(throw_cooldown).timeout
		_can_throw = true
		return

	# Otherwise, try to pick up a rock near us
	var pickup_radius := 32.0
	var nearest_rock: Node2D = null
	var best_dist := INF

	for rock in get_tree().get_nodes_in_group("rocks"):
		if rock is Node2D:
			var d := global_position.distance_to(rock.global_position)
			if d < pickup_radius and d < best_dist:
				best_dist = d
				nearest_rock = rock

	if nearest_rock and nearest_rock.has_method("pickup"):
		nearest_rock.pickup(self)

func pickup_rock() -> void:
	rocks_in_inventory += 1
	print("Picked up rock. Rocks: ", rocks_in_inventory)

func _throw_rock() -> void:
	var rock := ROCK_SCENE.instantiate()

	# Ensure we have a valid direction
	var dir := last_dir
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN

	# Add to the tree first so _ready() runs
	get_parent().add_child(rock)

	# Spawn a bit ahead of the player so it doesn't collide immediately
	var spawn_offset := dir.normalized() * 24.0
	rock.global_position = global_position + spawn_offset

	# make sure the rock doesn't collide with the player that threw it
	if rock is RigidBody2D:
		rock.add_collision_exception_with(self)

	# Now actually throw it (after _ready)
	rock.throw(dir)

	# Connect rock noise to all enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("_on_noise_emitted"):
			rock.noise_emitted.connect(enemy._on_noise_emitted)


func _on_rock_noise(pos: Vector2) -> void:
	# Placeholder: later you'll broadcast this to enemies' AI
	print("Rock noise at: ", pos)


# --- footstep "tick" ---
func _on_step_timer() -> void:
	if _moving_strength <= 0.01:
		return

	# audible step for the human player (2D attenuation handled by AudioStreamPlayer2D)
	var jitter = clamp(1.0 + (randf() * 2.0 - 1.0) * footstep_pitch_jitter, 0.75, 1.25)
	foot.pitch_scale = jitter
	foot.play()

	# AI hearing: emit noise signal with radius + loudness (0..1) + priority
	var loudness := 1.0  # walking baseline; make >1.0 for running if you add a run state
	emit_signal("noise_emitted", global_position, footstep_hear_radius_walk, loudness, footstep_priority)

	# NEW: spawn a fading footprint at this step
	_spawn_footstep_mark()


# NEW: spawn visual footprint
func _spawn_footstep_mark() -> void:
	if FOOTSTEP_MARK_SCENE == null:
		return

	var f := FOOTSTEP_MARK_SCENE.instantiate()
	get_parent().add_child(f)

	# Place at feet
	f.global_position = global_position

	# Orient footprint to movement direction, with a 90° correction
	var dir := last_dir
	if dir != Vector2.ZERO and f is Node2D:
		# Try -PI/2 first; if your art is flipped, swap to +PI/2
		f.rotation = dir.angle() + PI / 2.0
