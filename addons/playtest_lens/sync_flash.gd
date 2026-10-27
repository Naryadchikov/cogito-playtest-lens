extends Node

## White flash and beep on request, both for 0.25 s.
## The log line is written when that white is drawn, on the logger's clock.
## A request while one is still showing is ignored and not logged.

const DURATION_S := 0.25
const DURATION_USEC := 250_000
const BEEP_HZ := 1000
const _MIX_RATE := 44100
const _AMPLITUDE := 0.5

var _queued := false
var _queued_reason := ""
var _queued_extra: Dictionary = {}
var _showing := false
var _waiting_draw := false
var _stamped := false
var _reason := ""
var _extra: Dictionary = {}
var _remove_usec := 0
var _layer: CanvasLayer
var _player: AudioStreamPlayer
var _beep: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_beep = _make_beep()


func trigger(reason: String, extra: Dictionary = {}) -> bool:
	if _showing and _stamped and Time.get_ticks_usec() >= _remove_usec:
		_clear()
	if _showing or _queued:
		return false
	_queued = true
	_queued_reason = reason
	_queued_extra = extra.duplicate()
	return true


func _process(_delta: float) -> void:
	if _queued:
		_queued = false
		_arm()
		# Same process must not stamp: the draw (or the lack of one) comes after this.
		return
	# frame_post_draw runs before the next process when a frame is drawn.
	# Headless play does not draw, so stamp on that next process instead.
	if _waiting_draw:
		_stamp()
	if _showing and _stamped and Time.get_ticks_usec() >= _remove_usec:
		_clear()


func _arm() -> void:
	_showing = true
	_stamped = false
	_waiting_draw = true
	_reason = _queued_reason
	_extra = _queued_extra
	_show_flash()
	_play_beep()
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _on_frame_post_draw() -> void:
	_stamp()


func _stamp() -> void:
	if _stamped or not _showing:
		return
	_stamped = true
	_waiting_draw = false
	_disconnect_draw()
	var logger := get_parent()
	if logger != null and logger.has_method("log_event"):
		var fields := {
			"reason": _reason,
			"duration_s": DURATION_S,
			"beep_hz": BEEP_HZ,
		}
		for key in _extra:
			fields[key] = _extra[key]
		logger.log_event("sync_flash", fields)
	_remove_usec = Time.get_ticks_usec() + DURATION_USEC


func _disconnect_draw() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _show_flash() -> void:
	if _layer == null:
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
	_layer.visible = true


func _play_beep() -> void:
	if _player == null:
		var player := AudioStreamPlayer.new()
		player.name = "Beep"
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = "Master"
		player.stream = _beep
		add_child(player)
		_player = player
	_player.stop()
	_player.play()


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
	_showing = false
	_stamped = false
	_waiting_draw = false
	_disconnect_draw()
	if _layer != null:
		_layer.visible = false
	if _player != null:
		_player.stop()
