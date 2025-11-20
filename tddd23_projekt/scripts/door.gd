extends Area2D

@export var action_name := "Enter"
@export var next_scene: String = ""  # leave empty to auto-advance LevelN -> LevelN+1
@export var open_time: float = 0.25
@export var required_levers: int = -1
@export var channel: String = ""        # must match Lever.channel (empty = accept all)
@export var lever_scope: NodePath       # optional: only count levers under this node

@onready var solid: StaticBody2D = $StaticBody2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var exit_point: Marker2D = get_node_or_null("ExitPoint")

# --- SFX nodes by name ---
@onready var sfx_locked_player: AudioStreamPlayer2D = $sfx_locked
@onready var sfx_open_player: AudioStreamPlayer2D = $sfx_open

# Arrow hint scene (adjust path if needed)
const HINT_ARROW_SCENE := preload("res://scenes/DirectionArrow.tscn")

const LEVELS_DIR := "res://scenes/Levels/"
const MAIN_MENU := "res://scenes/UI/MainMenu.tscn"
const LEVEL_PREFIX := "Level"
const LEVEL_EXT := ".tscn"
@export var max_level: int = 8

var _player_in_range := false
var _is_open := false
var _open_sfx_played := false

var _player_ref: Node2D = null


func _ready() -> void:
	add_to_group("doors")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	anim.play("Closed Door")
	_auto_init_required_levers()

	# Fallbacks if streams not set in Inspector
	if is_instance_valid(sfx_locked_player) and sfx_locked_player.stream == null and ResourceLoader.exists("res://audios/SFX/Locked_Door.mp3"):
		sfx_locked_player.stream = load("res://audios/SFX/Locked_Door.mp3")
	if is_instance_valid(sfx_open_player) and sfx_open_player.stream == null and ResourceLoader.exists("res://audios/SFX/Open_Door.mp3"):
		sfx_open_player.stream = load("res://audios/SFX/Open_Door.mp3")


func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = true
		if body is Node2D:
			_player_ref = body


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = false
		_player_ref = null


func _process(_dt: float) -> void:
	if _player_in_range and Input.is_action_just_pressed(action_name):
		if _is_open:
			_enter_next_level()
		else:
			_try_open()

# ---------- Lever helpers ----------

func _get_lever_root() -> Node:
	if lever_scope != NodePath():
		var n := get_node_or_null(lever_scope)
		if n:
			return n
	return get_tree().current_scene


func _matching_levers() -> Array:
	var all := get_tree().get_nodes_in_group("levers")
	var root := _get_lever_root()
	var out: Array = []
	for l in all:
		var in_scope := true
		if root:
			in_scope = root.is_ancestor_of(l)

		var channel_ok := true
		if channel != "":
			# Our lever script exports `channel`, so we can just read it
			if l.has_method("get"):
				channel_ok = str(l.get("channel")) == channel
			else:
				channel_ok = false

		if in_scope and channel_ok:
			out.append(l)
	return out


func _count_on_levers() -> int:
	var cnt := 0
	for l in _matching_levers():
		if l.is_on:
			cnt += 1
	return cnt


func _auto_init_required_levers() -> void:
	if required_levers >= 0:
		return
	var total := _matching_levers().size()
	required_levers = total
	if required_levers == 0:
		await _open_door()

# ---------- Lever hint helpers ----------

# Approximate position of lever cluster, or null if none
# Approximate position of lever cluster: prefer OFF levers
func _get_levers_hint_position():
	var levers := _matching_levers()
	if levers.is_empty():
		return null

	# 1) Try to find the nearest OFF lever
	var best_off: Node2D = null
	var best_dist := INF

	for l in levers:
		if l is Node2D and not l.is_on:
			var d := global_position.distance_to(l.global_position)
			if d < best_dist:
				best_dist = d
				best_off = l

	if best_off:
		return best_off.global_position

	# 2) Fallback: if all are ON (shouldn't really happen when door is locked),
	#    return the nearest lever of any kind.
	var best_any: Node2D = null
	best_dist = INF
	for l in levers:
		if l is Node2D:
			var d := global_position.distance_to(l.global_position)
			if d < best_dist:
				best_dist = d
				best_any = l

	if best_any:
		return best_any.global_position

	return null

# Return progress for the set of levers that belong to THIS door
# for the lever that was toggled.
# Returns {} if this lever is not part of this door's group/scope/channel.
func get_lever_progress_for_lever(lever: Node) -> Dictionary:
	var levers := _matching_levers()
	if levers.is_empty():
		return {}

	if not levers.has(lever):
		return {}

	var total := levers.size()
	if total <= 0:
		return {}

	var on_count := 0
	for l in levers:
		if l.is_on:
			on_count += 1

	return {
		"on": on_count,
		"total": total,
		"complete": on_count >= required_levers
	}


func _spawn_locked_hint_arrow() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if HINT_ARROW_SCENE == null:
		return

	var hint_pos = _get_levers_hint_position()
	if hint_pos == null:
		return

	var arrow := HINT_ARROW_SCENE.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.setup(_player_ref, hint_pos)
	

# ---------- Try open / react to lever toggles ----------

func _try_open() -> void:
	var on_count := _count_on_levers()
	if on_count >= required_levers:
		await _open_door()
	else:
		# PLAY LOCKED SFX on failed attempt
		if is_instance_valid(sfx_locked_player) and sfx_locked_player.stream:
			sfx_locked_player.play()
		print("Door locked — levers ", on_count, "/", required_levers)

		# Show hint arrow toward lever(s)
		_spawn_locked_hint_arrow()


func on_lever_toggled() -> void:
	if _is_open:
		return
	var on_count := _count_on_levers()
	if on_count >= required_levers:
		await _open_door()

# ---------- Door open / level change ----------

func _open_door() -> void:
	if _is_open:
		return
	_is_open = true

	# PLAY OPEN SFX exactly when door unlocks/opens (not on player enter)
	if not _open_sfx_played and is_instance_valid(sfx_open_player) and sfx_open_player.stream:
		sfx_open_player.play()
		_open_sfx_played = true

	anim.play("door opens")
	await get_tree().create_timer(open_time).timeout
	anim.play("Open Door")
	solid.set_deferred("collision_layer", 0)
	solid.set_deferred("collision_mask", 0)
	print("Door opened!")


func _get_current_level_number() -> int:
	var s := get_tree().current_scene
	if s == null:
		return -1
	var path := s.scene_file_path
	if path == "":
		return -1
	var base := path.get_file().get_basename()  # "Level2"
	if base.begins_with(LEVEL_PREFIX):
		var num_str := base.substr(LEVEL_PREFIX.length())
		if num_str.is_valid_int():
			return int(num_str)
	return -1


func _level_path(n: int) -> String:
	return "%s%s%d%s" % [LEVELS_DIR, LEVEL_PREFIX, n, LEVEL_EXT]


func _enter_next_level() -> void:
	var target_path := next_scene

	# Auto-next if empty/auto
	if target_path == "" or target_path == "auto":
		var cur := _get_current_level_number()
		if cur <= 0:
			push_warning("Door: couldn't detect current level number.")
			return

		var next_n := cur + 1

		if max_level > 0 and next_n > max_level:
			Transition.return_to_menu(MAIN_MENU)
			return

		target_path = _level_path(next_n)

	if not ResourceLoader.exists(target_path):
		push_warning("Door: next level not found: " + target_path)
		return

	Transition.change_scene_with_spawn(target_path, 1.0, "", true)
