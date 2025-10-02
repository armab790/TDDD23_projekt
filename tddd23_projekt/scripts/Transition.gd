extends CanvasLayer

var shade: ColorRect
var busy: bool = false

func _ready() -> void:
	# Create or grab Shade
	shade = get_node_or_null("Shade") as ColorRect
	if shade == null:
		shade = ColorRect.new()
		shade.name = "Shade"
		add_child(shade)

	# Make it cover the whole screen (anchors + zero offsets)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.anchor_left = 0.0
	shade.anchor_top = 0.0
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_left = 0.0
	shade.offset_top = 0.0
	shade.offset_right = 0.0
	shade.offset_bottom = 0.0

	# Don’t block clicks and keep it above everything
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = 9999

	# Start fully transparent (modulate is what we tween!)
	var m := shade.modulate
	m.a = 0.0
	shade.modulate = m

	# Optional: ensure it stays full-screen if window resizes
	get_viewport().size_changed.connect(func ():
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.anchor_left = 0.0
		shade.anchor_top = 0.0
		shade.anchor_right = 1.0
		shade.anchor_bottom = 1.0
		shade.offset_left = 0.0
		shade.offset_top = 0.0
		shade.offset_right = 0.0
		shade.offset_bottom = 0.0
	)


func fade_to_black(duration: float = 0.35) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shade, "modulate:a", 1.0, duration)
	await tw.finished

func fade_from_black(duration: float = 0.35) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shade, "modulate:a", 0.0, duration)
	await tw.finished

func caught_and_restart() -> void:
	if busy:
		return
	busy = true

	# Slow-mo + fade to black in parallel
	var tw := create_tween()
	tw.parallel().tween_property(Engine, "time_scale", 0.15, 0.25)
	tw.parallel().tween_property(shade, "modulate:a", 1.0, 0.35)
	await tw.finished

	# Use a timer that ignores time_scale so we don’t stall
	await get_tree().create_timer(0.05, false, true).timeout

	get_tree().reload_current_scene()

	# Reset time and fade back in after reload
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await fade_from_black(0.35)

	busy = false
