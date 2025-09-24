extends CanvasLayer

@onready var shade: ColorRect = $Shade
var busy: bool = false

func _ready() -> void:
	# Make sure it always covers the window
	# Start fully transparent
	var c := shade.modulate
	c.a = 0.0
	shade.modulate = c

func fade_to_black(duration: float = 0.35) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shade, "modulate:a", 1.0, duration)
	await tw.finished

func fade_from_black(duration: float = 0.35) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shade, "modulate:a", 0.0, duration)
	await tw.finished

func slow_time(to_scale: float = 0.15, over: float = 0.25) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(Engine, "time_scale", to_scale, over)
	await tw.finished

func restore_time(over: float = 0.10) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(Engine, "time_scale", 1.0, over)
	await tw.finished

func caught_and_restart() -> void:
	if busy: return
	busy = true

	# 1) slow motion + fade to black (in parallel)
	var tw := create_tween()
	tw.parallel().tween_property(Engine, "time_scale", 0.15, 0.25)
	tw.parallel().tween_property(shade, "modulate:a", 1.0, 0.35)
	await tw.finished

	# Small timer that ignores time scale so we don’t hang if time_scale is tiny
	await get_tree().create_timer(0.05, false, true).timeout

	# 2) restart scene
	get_tree().reload_current_scene()

	# 3) after reload, snap time back to 1 and fade in
	Engine.time_scale = 1.0
	await get_tree().process_frame  # let the new scene settle
	await fade_from_black(0.35)

	busy = false
