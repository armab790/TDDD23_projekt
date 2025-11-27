extends Node

const OLLAMA_URL := "http://127.0.0.1:11434/api/generate"

@export var model_name: String = "mistral"   # samma som körs i Ollama
@export var timeout_seconds: float = 8.0     # enkel timeout-säkerhet

var _http: HTTPRequest
var _queue: Array = []                      # kö av {payload, callback}
var _is_request_active: bool = false
var _current_callback: Callable = Callable()
var _current_started_time: float = 0.0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "LLMHttp"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _process(_delta: float) -> void:
	# Timeout – om något hänger sig, släpp låset och gå vidare i kön
	if _is_request_active and timeout_seconds > 0.0:
		var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
		if now_sec - _current_started_time > timeout_seconds:
			_is_request_active = false
			if _current_callback.is_valid():
				_current_callback.call("")  # fallback: tom sträng
			_try_send_next()


# Publik funktion som NPC:er använder
# context = kort beskrivning av situation ("patrolling", "spotted intruder" osv)
# callback = Callable som tar en (String) – själva repliken
func request_guard_line(context: String, callback: Callable) -> void:
	var prompt: String = """You are a guard in a top-down 2D stealth game.
You speak short, natural English barks (max 8 words).
Never explain yourself, just say the line.

Situation: %s

Reply with a single guard line.""" % context

	var payload: Dictionary = {
		"model": model_name,
		"prompt": prompt,
		"stream": false
	}

	var entry: Dictionary = {
		"payload": payload,
		"callback": callback
	}
	_queue.push_back(entry)
	_try_send_next()


func _try_send_next() -> void:
	if _is_request_active:
		return
	if _queue.is_empty():
		return

	_is_request_active = true
	_current_started_time = float(Time.get_ticks_msec()) / 1000.0

	var entry: Dictionary = _queue.pop_front()
	_current_callback = entry["callback"]
	var payload: Dictionary = entry["payload"]

	var json_body: String = JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])

	var err := _http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_is_request_active = false
		if _current_callback.is_valid():
			_current_callback.call("")  # signalera fel
		_try_send_next()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_is_request_active = false

	var line: String = ""

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var text: String = body.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("response"):
			line = String(parsed["response"]).strip_edges()

	# Anropa callback (eller fallback om line == "")
	if _current_callback.is_valid():
		_current_callback.call(line)

	# Försök skicka nästa i kön
	_try_send_next()
