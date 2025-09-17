extends RigidBody2D

@export var throw_speed: float = 350.0
@export var min_land_speed: float = 50.0

signal noise_emitted(world_pos: Vector2)  # enemies can listen to this

func _ready() -> void:
	# No gravity in top-down
	gravity_scale = 0.0
	linear_damp = 3.0
	contact_monitor = true
	max_contacts_reported = 4

func throw(dir: Vector2) -> void:
	linear_velocity = dir.normalized() * throw_speed
	rotation = dir.angle()

func _physics_process(_delta: float) -> void:
	# “Landing” when it slows down naturally
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
	emit_signal("noise_emitted", global_position)
	await $SFX.finished
	queue_free()
