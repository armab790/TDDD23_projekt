extends Node2D

@export var radius: float = 120.0              # pixels (AI hearing radius)
@export var color: Color = Color(0.2, 0.8, 1.0, 0.5)  # ring color/alpha
@export var softness: float = 0.35             # 0..1 -> ring thickness as a fraction of radius
@export var steps: int = 24                    # gradient smoothness (more = smoother/slower)

func _ready() -> void:
	# draw above tiles/characters
	z_as_relative = false
	z_index = 4000
	# make sure nothing scales/tints this node
	scale = Vector2.ONE
	self_modulate = Color(1,1,1,1)

func set_radius(r: float) -> void:
	radius = max(0.0, r)
	queue_redraw()

func set_tint(c: Color) -> void:
	color = c
	queue_redraw()

func _draw() -> void:
	if radius <= 0.0 or steps <= 0:
		return

	# ring thickness in pixels
	var ring_width: float = max(2.0, radius * softness)
	var start_r: float = radius
	var end_r: float = max(1.0, radius - ring_width)
	var band_count: int = steps

	# Draw multiple thin arcs from outer to inner, fading alpha = gradient
	for i in range(band_count):
		var t: float = float(i) / float(band_count - 1)        # 0..1
		var r: float = lerp(start_r, end_r, t)
		var a: float = color.a * (1.0 - t)                      # fade inward
		var c := Color(color.r, color.g, color.b, a)
		# draw_arc(center, radius, start_angle, end_angle, points, color, width, antialiased)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, c, 2.0, true)
