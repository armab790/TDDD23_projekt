extends Area2D

@export var action_name := "Enter"
@export var is_on := false
@export var door_group := "doors"
@export var channel: String = ""   # används för att gruppera levrar till samma dörr

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx_pull_player: AudioStreamPlayer2D = $sfx_pull

# Label + partiklar direkt på levern
@onready var progress_label: Label = get_node_or_null("LeverProgressLabel")
@onready var unlock_particles: Node = get_node_or_null("UnlockParticles")

var _player_in_range := false
var _progress_timer: float = 0.0      # hur länge “1/5” ska synas


func _ready() -> void:
	add_to_group("levers")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Fallback: auto-assign stream if empty and file exists
	if sfx_pull_player.stream == null and ResourceLoader.exists("res://audios/SFX/Pull_Lever.mp3"):
		sfx_pull_player.stream = load("res://audios/SFX/Pull_Lever.mp3")

	if progress_label:
		progress_label.visible = false

	# Partiklar: se till att de börjar avstängda och (om GPU) one_shot
	if unlock_particles:
		if unlock_particles is GPUParticles2D:
			unlock_particles.emitting = false
			unlock_particles.one_shot = true
		elif unlock_particles is CPUParticles2D:
			unlock_particles.emitting = false
			unlock_particles.one_shot = true

	_update_visual()


func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		_player_in_range = false


func _process(delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed(action_name):
		if not is_on:
			_toggle_lever(true)

	# räkna ner och göm “1/5”-labeln
	if _progress_timer > 0.0 and progress_label:
		_progress_timer -= delta
		if _progress_timer <= 0.0:
			progress_label.visible = false


func _toggle_lever(state: bool) -> void:
	is_on = state

	# Play lever SFX ONLY when toggling on
	if is_on and is_instance_valid(sfx_pull_player) and sfx_pull_player.stream:
		sfx_pull_player.play()

	_update_visual()
	_show_progress_and_maybe_particles()

	# Notify doors to re-check
	var doors := get_tree().get_nodes_in_group(door_group)
	for d in doors:
		if d.has_method("on_lever_toggled"):
			d.on_lever_toggled()


func _update_visual() -> void:
	if anim == null:
		return
	if is_on:
		anim.play("On")
	else:
		anim.play("Off")


# --------------------------------
# Progress-text + partiklar
# --------------------------------
func _show_progress_and_maybe_particles() -> void:
	# 1) räkna hur många levrar i samma “channel”
	var all_levers: Array = get_tree().get_nodes_in_group("levers")
	var total: int = 0
	var on_count: int = 0

	for l in all_levers:
		if not l is Area2D:
			continue

		# filtrera på channel om denna lever har en satt
		if channel != "":
			if l.has_method("get"):
				if str(l.get("channel")) != channel:
					continue

		total += 1
		if l.has_method("get") and l.get("is_on"):
			on_count += 1

	if total <= 0:
		return

	# 2) visa “x / y” på denna lever
	if progress_label:
		var prog_text: String = "%d / %d" % [on_count, total]
		progress_label.text = prog_text
		progress_label.visible = true
		_progress_timer = 1.0   # hur länge texten ska vara synlig (sekunder)

	# 3) om alla levrar i den här gruppen är ON → spela partiklar
	if on_count == total and unlock_particles:
		if unlock_particles is GPUParticles2D:
			unlock_particles.emitting = false
			unlock_particles.restart()
			unlock_particles.emitting = true
		elif unlock_particles is CPUParticles2D:
			unlock_particles.emitting = false
			unlock_particles.restart()
			unlock_particles.emitting = true
