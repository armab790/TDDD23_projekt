extends Control

@export var map_scale: float = 3.0              # fler = mer zoom-out (world-units per pixel)
@export var reveal_radius: float = 40.0         # hur nära dörr/spak för att “upptäcka” den

@export var trail_sample_dist: float = 8.0      # minsta distans innan vi lägger till en ny punkt i stigen
@export var trail_sample_time: float = 0.1      # sampelfrekvens i sekunder

@export var bg_color: Color = Color(0, 0, 0, 0.6)
@export var path_color: Color = Color(0.8, 0.8, 0.8, 0.7)
@export var player_color: Color = Color(0.2, 1.0, 0.2, 0.9)

@export var door_icon_size: float = 8.0
@export var lever_icon_size: float = 8.0
@export var rock_icon_size: float = 10.0

@export var door_tint: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var lever_tint: Color = Color(1.0, 0.95, 0.7, 1.0)
@export var rock_tint: Color = Color(1.0, 0.8, 0.8, 1.0)

var _player: Node2D = null

var _path_points: PackedVector2Array = PackedVector2Array()
var _last_sample_pos: Vector2 = Vector2.ZERO
var _sample_timer: float = 0.0

var _doors: Array[Node2D] = []
var _levers: Array[Node2D] = []
var _discovered_doors: Array[bool] = []
var _discovered_levers: Array[bool] = []


func _ready() -> void:
	add_to_group("minimap")
	_find_player()
	_init_objects()
	# säkra så att storleken används som "ruta"
	queue_redraw()


func _find_player() -> void:
	if _player and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		_player = players[0]


func _init_objects() -> void:
	_doors.clear()
	_levers.clear()
	_discovered_doors.clear()
	_discovered_levers.clear()

	for d in get_tree().get_nodes_in_group("doors"):
		if d is Node2D:
			_doors.append(d)
			_discovered_doors.append(false)

	for l in get_tree().get_nodes_in_group("levers"):
		if l is Node2D:
			_levers.append(l)
			_discovered_levers.append(false)


func _process(delta: float) -> void:
	# Dölj när Transition-överlägg är aktiv (caught/fade/next level etc)
	if _transition_overlay_active():
		visible = false
		return
	else:
		visible = true

	if not _player or not is_instance_valid(_player):
		_find_player()
		if not _player:
			return

	# 1) Spara spelarens stig (rörelseminne)
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer = trail_sample_time
		var pos: Vector2 = _player.global_position
		if _path_points.is_empty() or pos.distance_to(_last_sample_pos) >= trail_sample_dist:
			_path_points.append(pos)
			_last_sample_pos = pos

	# 2) “Upptäck” dörrar/spakar när man kommer nära
	for i in _doors.size():
		if not _discovered_doors[i] and is_instance_valid(_doors[i]):
			if _player.global_position.distance_to(_doors[i].global_position) <= reveal_radius:
				_discovered_doors[i] = true

	for i in _levers.size():
		if not _discovered_levers[i] and is_instance_valid(_levers[i]):
			if _player.global_position.distance_to(_levers[i].global_position) <= reveal_radius:
				_discovered_levers[i] = true

	queue_redraw()


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	# Centerar minimapen runt spelaren
	var center: Vector2 = size / 2.0
	var relative: Vector2 = (world_pos - _player.global_position) / map_scale
	return center + relative


# ---------------------------
# Icon helpers
# ---------------------------
func _get_animated_sprite_texture(node: Node) -> Texture2D:
	var s: AnimatedSprite2D = node.get_node_or_null("AnimatedSprite2D")
	if not s:
		return null
	var frames := s.sprite_frames
	if not frames:
		return null
	var tex: Texture2D = null

	if frames.has_method("get_frame_texture"):
		tex = frames.get_frame_texture(s.animation, s.frame)
	elif frames.has_method("get_frame"):
		tex = frames.get_frame(s.animation, s.frame)

	return tex


func _get_rock_texture(rock: Node) -> Texture2D:
	var spr: Sprite2D = rock.get_node_or_null("Sprite2D")
	if spr and spr.texture:
		return spr.texture
	return null


# Bevara aspect ratio, men klipp till max_size_px som största sida
func _draw_icon(tex: Texture2D, world_pos: Vector2, max_size_px: float, tint: Color) -> void:
	if not tex:
		return

	var p: Vector2 = _world_to_minimap(world_pos)
	var clip_rect := Rect2(Vector2.ZERO, size)
	if not clip_rect.has_point(p):
		return

	var tex_size: Vector2 = tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	var largest_side := maxf(tex_size.x, tex_size.y)
	var scale := max_size_px / largest_side
	var draw_size := tex_size * scale
	var draw_pos := p - draw_size * 0.5

	var rect := Rect2(draw_pos, draw_size)
	draw_texture_rect(tex, rect, false, tint)


func _draw() -> void:
	if not _player or not is_instance_valid(_player):
		return

	var clip_rect := Rect2(Vector2.ZERO, size)

	# Bakgrund
	draw_rect(clip_rect, bg_color, true)

	# Stig (spelarens rörelse) – bara punkter inne i rutan
	if _path_points.size() >= 2:
		var screen_points := PackedVector2Array()
		for p in _path_points:
			var sp := _world_to_minimap(p)
			if clip_rect.has_point(sp):
				screen_points.append(sp)

		if screen_points.size() >= 2:
			draw_polyline(screen_points, path_color, 1.5)

	# Dörrar (endast de som "upptäckts")
	for i in _doors.size():
		if _discovered_doors[i] and is_instance_valid(_doors[i]):
			var tex: Texture2D = _get_animated_sprite_texture(_doors[i])
			_draw_icon(tex, _doors[i].global_position, door_icon_size, door_tint)

	# Spakar (endast de som "upptäckts")
	for i in _levers.size():
		if _discovered_levers[i] and is_instance_valid(_levers[i]):
			var tex: Texture2D = _get_animated_sprite_texture(_levers[i])
			_draw_icon(tex, _levers[i].global_position, lever_icon_size, lever_tint)

	# Stenar på marken (alla syns så länge de finns)
	for rock in get_tree().get_nodes_in_group("rocks"):
		if rock is Node2D:
			var rtex: Texture2D = _get_rock_texture(rock)
			_draw_icon(rtex, rock.global_position, rock_icon_size, rock_tint)

	# Spelare (alltid i mitten av minimapen)
	var player_pos: Vector2 = size / 2.0
	if clip_rect.has_point(player_pos):
		draw_circle(player_pos, 1.5, player_color)


func _transition_overlay_active() -> bool:
	if Engine.is_editor_hint():
		return false
	# Om Transition är en autoload-singleton
	if typeof(Transition) == TYPE_NIL:
		return false
	if not Transition.has_method("is_overlay_active"):
		return false
	return Transition.is_overlay_active()
