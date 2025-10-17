# MusicPlayer.gd
extends AudioStreamPlayer2D

@export var default_volume_db: float = -8.0

func _ready() -> void:
	# If stream assigned in the scene, just start
	if stream:
		volume_db = default_volume_db
		if has_method("_ensure_loop"):
			_ensure_loop()
		if not playing:
			play()

func _ensure_loop() -> void:
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true

func play_music(track: AudioStream = null) -> void:
	if track and track != stream:
		stream = track
	if not playing:
		play()

func fade_out(duration: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "volume_db", -80.0, duration)
	await tw.finished
	stop()
