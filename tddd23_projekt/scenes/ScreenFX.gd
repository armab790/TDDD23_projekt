extends CanvasLayer

@export var pulse_color: Color = Color(0, 0, 0, 1)
@export var max_alpha: float = 0.42           # set high to verify; lower later
@export var rate_hz: float = 0.9
@export var debug_force_on: bool = false       # TEMP: force ON so you can see it

var _on := false
var _t := 0.0
@onready var pulse: ColorRect = $Pulse

func _ready() -> void:
	# Draw above everything and always process, even if game pauses/slows
	layer = 500
	process_mode = Node.PROCESS_MODE_PAUSABLE 

	add_to_group("screen_fx")

	if pulse == null:
		pulse = ColorRect.new()
		pulse.name = "Pulse"
		add_child(pulse)

	pulse.set_anchors_preset(Control.PRESET_FULL_RECT)
	pulse.offset_left = 0
	pulse.offset_top = 0
	pulse.offset_right = 0
	pulse.offset_bottom = 0
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.z_index = 100
	pulse.color = pulse_color
	pulse.visible = true
	pulse.modulate = Color(1, 1, 1, 0.0)      # animate modulate.a

	_on = debug_force_on
	set_process(true)

	print("[ScreenFX] READY  group=", is_in_group("screen_fx"), "  layer=", layer)

func start_pulse(rate: float = -1.0, amp: float = -1.0) -> void:
	if rate > 0.0: rate_hz = rate
	if amp  >= 0.0: max_alpha = amp
	_on = true
	_t = 0.0
	print("[ScreenFX] pulse ON  rate=", rate_hz, " amp=", max_alpha)

func stop_pulse() -> void:
	_on = false
	if is_instance_valid(pulse):
		pulse.modulate.a = 0.0
	print("[ScreenFX] pulse OFF")

func _process(delta: float) -> void:
	var target_a: float = 0.0
	if _on:
		_t += delta * rate_hz
		target_a = (sin(_t * TAU) * 0.5 + 0.5) * max_alpha
	pulse.modulate.a = move_toward(pulse.modulate.a, target_a, delta * 4.0)
