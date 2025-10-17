extends AudioStreamPlayer

# Autoload this script in Project Settings → Autoload

@export var default_track: AudioStream
@export var default_volume_db: float = -8.0

func _ready() -> void:
	if default_track:
		stream = default_track
		volume_db = default_volume_db
		playing = true  # start automatically
		autoload_playback_settings()

func autoload_playback_settings() -> void:
	# Make sure the track loops forever
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
