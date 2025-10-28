extends BTAction
@export var ttl: float = 3.0

func _tick(delta: float) -> BT.Status:
	var nt_val = blackboard.get_var("noise_time")
	var nt: float
	if nt_val is float:
		nt = float(nt_val)
	else:
		nt = -1.0

	if nt < 0.0:
		return FAILURE

	var now = Time.get_ticks_msec() / 1000.0
	if (now - nt) <= ttl:
		return SUCCESS
	return FAILURE
