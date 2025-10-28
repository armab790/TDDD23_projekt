extends BTAction

func _tick(delta: float) -> BT.Status:
	var wps_val = blackboard.get_var("waypoints")
	if typeof(wps_val) != TYPE_ARRAY:
		return FAILURE

	var wps: Array = wps_val
	if wps.is_empty():
		return FAILURE

	var idx_val = blackboard.get_var("wp_index")
	var idx: int
	if idx_val is int:
		idx = int(idx_val)
	else:
		idx = 0

	if idx < 0:
		idx = 0
	if idx >= wps.size():
		idx = wps.size() - 1

	blackboard.set_var("target_position", wps[idx])
	blackboard.set_var("path_finished", false)
	return SUCCESS
