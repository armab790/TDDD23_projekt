extends CanvasLayer

@export var pulse_color: Color = Color(0, 0, 0, 1) # pure black; alpha controlled by modulate
@export var max_alpha: float = 0.12                # TEMP high so you can see it; lower later (e.g. 0.05)
@export var rate_hz: float = 1.3                   # pulses per second
@export var debug_force_on: bool = false           # turn on in editor to verify

var _on := false
var _t := 0.0
@onready var pulse: ColorRect = $Pulse

func _ready() -> void:
	# Make sure we render above everything
	layer = 50
	add_to_group("screen_fx")   
	# Build Pulse rect if missing
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
	pulse.z_index = 9999
	pulse.color = pulse_color
	pulse.modulate.a = 0.0
	_on = debug_force_on
	set_process(true)

func start_pulse(rate: float = -1.0, amp: float = -1.0) -> void:
	if rate > 0.0: rate_hz = rate
	if amp >= 0.0: max_alpha = amp
	_on = true
	_t = 0.0
	print("[ScreenFX] pulse ON (rate:", rate_hz, ", amp:", max_alpha, ")")

func stop_pulse() -> void:
	_on = false
	print("[ScreenFX] pulse OFF")

func _process(delta: float) -> void:
	var target_a := 0.0
	if _on:
		_t += delta * rate_hz
		target_a = (sin(_t * TAU) * 0.5 + 0.5) * max_alpha  # 0..max_alpha
	pulse.modulate.a = move_toward(pulse.modulate.a, target_a, delta * 4.0)
