extends Node2D

@export var life_time: float = 12.0      # how long total before removal
@export var fade_start: float = 2.0      # start fading after this many seconds
@export var base_alpha: float = 0.6      # initial opacity
@export var base_scale: float = 0.75      # footprint size

var _age: float = 0.0

func _ready() -> void:
	# Smaller + semi-transparent from start (affects whole node, including sprite)
	scale = Vector2.ONE * base_scale

	var c := modulate
	c.a = base_alpha
	modulate = c

	# If you have an AnimatedSprite2D child named "Footsteps", play it
	var sprite := get_node_or_null("Footsteps")
	if sprite and sprite.has_method("play"):
		sprite.play()

func _process(delta: float) -> void:
	_age += delta

	if _age >= life_time:
		queue_free()
		return

	if _age > fade_start:
		var t: float = (_age - fade_start) / (life_time - fade_start)
		if t < 0.0:
			t = 0.0
		elif t > 1.0:
			t = 1.0

		var c := modulate
		c.a = lerpf(base_alpha, 0.0, t)
		modulate = c
