extends Node

## White flash and beep, once, about a second after the logger starts.
## The log line is written when that white is drawn, on the logger's clock.

const DELAY_USEC := 1_000_000
const DURATION_S := 0.25
const DURATION_USEC := 250_000
const BEEP_HZ := 1000
const _MIX_RATE := 44100
const _AMPLITUDE := 0.5

var _ready_usec := 0
var _armed := false
var _waiting_draw := false
var _stamped := false
var _remove_usec := 0
var _cleared := false
var _layer: CanvasLayer
var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_ready_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if not _armed:
		if Time.get_ticks_usec() - _ready_usec < DELAY_USEC:
			return
		_arm()
		return
	# frame_post_draw runs before the next process when a frame is drawn.
	# Headless play does not draw, so stamp on that next process instead.
	if _waiting_draw:
		_stamp()
	if _stamped and not _cleared and Time.get_ticks_usec() >= _remove_usec:
		_clear()


func _arm() -> void:
	_armed = true
	_show_flash()
	_play_beep()
	_waiting_draw = true
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)


func _on_frame_post_draw() -> void:
	_stamp()


func _stamp() -> void:
	if _stamped:
		return
	_stamped = true
	_waiting_draw = false
	var logger := get_parent()
	if logger != null and logger.has_method("log_event"):
		logger.log_event("start_flash", {
			"duration_s": DURATION_S,
			"beep_hz": BEEP_HZ,
		})
	_remove_usec = Time.get_ticks_usec() + DURATION_USEC


func _show_flash() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlashLayer"
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.name = "White"
	rect.color = Color(1, 1, 1, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer = layer


func _play_beep() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "Beep"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = "Master"
	player.stream = _make_beep()
	add_child(player)
	player.play()
	_player = player


func _make_beep() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _MIX_RATE
	stream.stereo = false
	var frames := int(float(_MIX_RATE) * DURATION_S)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var theta := TAU * float(BEEP_HZ) * float(i) / float(_MIX_RATE)
		var sample := clampi(int(round(sin(theta) * 32767.0 * _AMPLITUDE)), -32767, 32767)
		data.encode_s16(i * 2, sample)
	stream.data = data
	return stream


func _clear() -> void:
	_cleared = true
	set_process(false)
	if _layer != null:
		_layer.visible = false
		_layer.queue_free()
		_layer = null
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
