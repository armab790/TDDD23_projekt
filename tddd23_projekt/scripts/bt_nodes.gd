extends Resource
class_name BTNode

# Alla noder använder samma enum för status
enum Status {
	SUCCESS,
	FAILURE,
	RUNNING
}

# Bas-API, alla noder ska ha en tick()
func tick(_delta: float, _owner: Node) -> int:
	return Status.FAILURE


# ----------------- Selector (OR) -----------------
class Selector:
	var children: Array

	func _init(p_children: Array = []) -> void:
		children = p_children

	func tick(delta: float, owner: Node) -> int:
		for child in children:
			var result: int = child.tick(delta, owner)
			match result:
				Status.SUCCESS:
					return Status.SUCCESS
				Status.RUNNING:
					return Status.RUNNING
		return Status.FAILURE


# ----------------- Sequence (AND) -----------------
class Sequence:
	var children: Array
	var _current_index: int = 0

	func _init(p_children: Array = []) -> void:
		children = p_children

	func tick(delta: float, owner: Node) -> int:
		while _current_index < children.size():
			var result: int = children[_current_index].tick(delta, owner)
			match result:
				Status.SUCCESS:
					_current_index += 1
				Status.RUNNING:
					return Status.RUNNING
				Status.FAILURE:
					_current_index = 0
					return Status.FAILURE

		# Alla barn lyckades
		_current_index = 0
		return Status.SUCCESS


# ----------------- Condition node -----------------
class Condition:
	var condition: Callable

	func _init(p_condition: Callable) -> void:
		condition = p_condition

	func tick(_delta: float, owner: Node) -> int:
		if not condition.is_valid():
			return Status.FAILURE

		var ok: bool = condition.call(owner)
		return Status.SUCCESS if ok else Status.FAILURE


# ----------------- Action node -----------------
class Action:
	var action: Callable

	func _init(p_action: Callable) -> void:
		action = p_action

	func tick(delta: float, owner: Node) -> int:
		if not action.is_valid():
			return Status.FAILURE

		# Action ska returnera en av Status-värdena (int)
		return action.call(delta, owner)
