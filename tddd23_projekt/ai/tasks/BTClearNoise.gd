extends BTAction

func _tick(delta: float) -> BT.Status:
	blackboard.set_var("noise_pos", null)
	blackboard.set_var("noise_time", -1.0)
	return SUCCESS
