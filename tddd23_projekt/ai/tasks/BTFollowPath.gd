extends BTAction

func _tick(delta: float) -> BT.Status:
	var finished_val = blackboard.get_var("path_finished")
	if (finished_val is bool) and finished_val:
		return SUCCESS

	var tp = blackboard.get_var("target_position")
	if not (tp is Vector2):
		return FAILURE

	return RUNNING
