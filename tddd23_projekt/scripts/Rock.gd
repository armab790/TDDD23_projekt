extends RigidBody2D

@export var throw_speed: float = 350.0
@export var min_land_speed: float = 50.0
@export var noise_radius: float = 150.0  # How far enemies can hear it
@export var noise_loudness: float = 0.9  # How loud (0.0 - 1.0)
@export var noise_priority: int = 2      # Higher priority than footsteps

signal noise_emitted(pos: Vector2, radius: float, loudness: float, priority: int)

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 3.0
	contact_monitor = true
	max_contacts_reported = 4

func throw(dir: Vector2) -> void:
	linear_velocity = dir.normalized() * throw_speed
	rotation = dir.angle()

func _physics_process(_delta: float) -> void:
	if not sleeping and linear_velocity.length() <= min_land_speed:
		_land()

func _on_Rock_body_entered(_body: Node) -> void:
	_land()

func _land() -> void:
	if sleeping:
		return
	sleeping = true
	linear_velocity = Vector2.ZERO
	$SFX.play()
	
	# Emit noise with all parameters
	emit_signal("noise_emitted", global_position, noise_radius, noise_loudness, noise_priority)
	
	await $SFX.finished
	queue_free()
