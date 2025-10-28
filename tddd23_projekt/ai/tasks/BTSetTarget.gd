extends BTAction

func _tick(delta: float) -> BT.Status:
	var pos_val = blackboard.get_var("noise_pos")
	if not (pos_val is Vector2):
		pos_val = blackboard.get_var("target_position")

	if not (pos_val is Vector2):
		return FAILURE

	blackboard.set_var("target_position", pos_val)
	blackboard.set_var("path_finished", false)
	return SUCCESS
