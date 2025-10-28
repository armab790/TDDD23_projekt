extends BTAction
@export var seconds := 0.6
var _elapsed := 0.0

func _tick(delta: float) -> BT.Status:
	var target_val = blackboard.get_var("wait_at_wp")
	var target: float
	if target_val is float:
		target = float(target_val)
	else:
		target = seconds

	_elapsed += delta
	if _elapsed >= target:
		_elapsed = 0.0
		return SUCCESS
	return RUNNING
