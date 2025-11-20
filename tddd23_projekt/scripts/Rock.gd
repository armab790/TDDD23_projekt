extends RigidBody2D

@export var throw_speed: float = 250.0
@export var min_land_speed: float = 30.0
@export var noise_radius: float = 150.0      # How far enemies can hear it
@export var noise_loudness: float = 0.9      # How loud (0.0 - 1.0)
@export var noise_priority: int = 2          # Higher priority than footsteps

@export var pickup_hint_radius: float = 26.0 # distance for showing hint (Level 1 mainly)
@export var hint_duration: float = 1.5       # how long the hint is visible

signal noise_emitted(pos: Vector2, radius: float, loudness: float, priority: int)

@onready var sfx: AudioStreamPlayer2D = $SFX
@onready var prompt_label: Node = get_node_or_null("PickupPrompt")  # Label or Sprite2D

var _player: Node2D = null
var _can_be_picked_up: bool = true
var _hint_shown_once: bool = false
var _hint_timer: float = 0.0

# remember original collision for when we throw from inventory
var _initial_collision_layer: int
var _initial_collision_mask: int

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 0.3
	contact_monitor = true
	max_contacts_reported = 4

	add_to_group("rocks")

	_initial_collision_layer = collision_layer
	_initial_collision_mask = collision_mask

	# Rocks placed in the world should start resting and not drift
	sleeping = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	if prompt_label:
		prompt_label.visible = false

func _find_player() -> void:
	if _player and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		_player = players[0]

func throw(dir: Vector2) -> void:
	# Called when player throws a rock from inventory
	_can_be_picked_up = false          # cannot pick up mid-air
	_hint_shown_once = true            # no hint for thrown rocks
	hint_duration = 0.0                # safety

	sleeping = false
	freeze = false                     # let physics move it
	collision_layer = _initial_collision_layer
	collision_mask = _initial_collision_mask

	linear_velocity = dir.normalized() * throw_speed
	angular_velocity = 0.0
	rotation = dir.angle()

func _physics_process(delta: float) -> void:
	# 1) landing: once it slows down enough, we consider it "landed"
	if not sleeping and linear_velocity.length() <= min_land_speed:
		_land()

	# 2) handle hint timer
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0 and prompt_label:
			prompt_label.visible = false

	# 3) pickup hint (only before first pickup, and only on Level 1 if you like)
	_find_player()
	if not _can_be_picked_up or _hint_shown_once:
		return

	if _player and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		var close := dist <= pickup_hint_radius

		if close and not _hint_shown_once:
			_hint_shown_once = true
			_hint_timer = hint_duration
			if prompt_label:
				prompt_label.visible = true
	else:
		if prompt_label:
			prompt_label.visible = false

func _on_Rock_body_entered(_body: Node) -> void:
	# We don't rely on collision to trigger landing, only on speed,
	# so we can ignore this.
	pass

func _land() -> void:
	if sleeping:
		return

	sleeping = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	# >>> KEY PART: stop all physics interactions after landing <<<
	freeze = true
	collision_layer = 0
	collision_mask = 0
	# Now the rock will NOT move anymore, even if NPCs or player bump into it.

	if sfx:
		sfx.play()

	emit_signal("noise_emitted", global_position, noise_radius, noise_loudness, noise_priority)
	# Rock stays on floor as a static pickup

func pickup(by: Node2D) -> void:
	if not _can_be_picked_up:
		return
	if not by or not is_instance_valid(by):
		return

	if by.has_method("pickup_rock"):
		by.pickup_rock()

	if prompt_label:
		prompt_label.visible = false

	queue_free()
