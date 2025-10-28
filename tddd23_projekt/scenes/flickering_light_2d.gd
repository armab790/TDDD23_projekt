extends Node2D

@export var base_energy: float = 1.0
@export var flicker_strength: float = 0.25
@export var flicker_speed: float = 4.0
@export var randomize_pattern: bool = true
@export var color_variation: float = 0.0

@onready var light: PointLight2D = $PointLight2D
var _time := 0.0

func _ready() -> void:
	if not light:
		push_warning("No PointLight2D child found!")
		return
	_time = randf() * TAU

func _process(delta: float) -> void:
	if not is_instance_valid(light):
		return

	_time += delta * flicker_speed

	var flicker := sin(_time) * flicker_strength
	if randomize_pattern:
		flicker += randf_range(-flicker_strength, flicker_strength) * 0.25

	light.energy = clamp(base_energy + flicker, 0.0, 8.0)

	if color_variation > 0.0:
		var col := light.color
		var hue_shift := randf_range(-color_variation, color_variation)
		col = Color.from_hsv(fposmod(col.h + hue_shift, 1.0), col.s, col.v)
		light.color = col
