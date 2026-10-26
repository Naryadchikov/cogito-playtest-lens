extends Node

const LoggerScript := preload("res://addons/playtest_lens/logger.gd")
const _WAIT_USEC := 2_000_000
const _CAPTURE_USEC := 4_000_000
const _PEAK_MIN := 1000
const _LOUD_MIN := 100

var _failures: PackedStringArray = PackedStringArray()
var _phase := 0
var _last_center := ""
var _flash_path := ""
var _after_path := ""
var _record: AudioEffectRecord
var _record_bus := -1


func _ready() -> void:
	if _windowed():
		Engine.max_fps = 30
		RenderingServer.set_default_clear_color(Color(0.12, 0.18, 0.28, 1))
		var checks := _checks_dir()
		_flash_path = checks.path_join("08-flash.png")
		_after_path = checks.path_join("08-after.png")
		# Deferred so the flash can stamp t on this draw before the viewport readback.
		RenderingServer.frame_post_draw.connect(_on_post_draw, CONNECT_DEFERRED)
	call_deferred("_run")


func _windowed() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("headless")


func _run() -> void:
	if not has_node("/root/PlaytestLensLogger"):
		print("FAIL: PlaytestLensLogger autoload is missing")
		get_tree().quit(1)
		return
	var logger: LoggerScript = get_node("/root/PlaytestLensLogger")
	print("display=%s headless_feature=%s" % [DisplayServer.get_name(), OS.has_feature("headless")])
	var windowed := _windowed()
	if windowed:
		_begin_recording()
		var start := Time.get_ticks_usec()
		while _phase < 2 and Time.get_ticks_usec() - start < _CAPTURE_USEC:
			await get_tree().process_frame
		if _phase < 2:
			_failures.append("screenshot timeout phase=%d center=%s" % [_phase, _last_center])
		_check_recording()
	else:
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - start < _WAIT_USEC:
			await get_tree().process_frame
	await get_tree().process_frame
	logger.end_session()
	_check(logger.log_path)
	if _failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		get_tree().quit(1)


func _on_post_draw() -> void:
	if _phase >= 2 or _flash_path.is_empty():
		return
	var showing := _flash_visible()
	if _phase == 0 and not showing:
		return
	if _phase == 1 and showing:
		return
	var viewport := get_tree().root.get_viewport()
	var texture := viewport.get_texture()
	if texture == null:
		return
	var img := texture.get_image()
	if img == null or img.is_empty():
		_last_center = "empty"
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_last_center = _center_text(img)
	if _phase == 0 and showing and _is_white(img):
		var err := img.save_png(_flash_path)
		if err != OK:
			_failures.append("save flash png %s" % error_string(err))
			_phase = 3
			return
		print("saved flash %s center=%s" % [_flash_path, _last_center])
		_phase = 1
	elif _phase == 1 and not showing and not _is_white(img):
		var err := img.save_png(_after_path)
		if err != OK:
			_failures.append("save after png %s" % error_string(err))
			_phase = 3
			return
		print("saved after %s center=%s" % [_after_path, _last_center])
		_phase = 2


func _flash_visible() -> bool:
	var rect := get_node_or_null("/root/PlaytestLensLogger/StartFlash/FlashLayer/White") as ColorRect
	return rect != null and rect.visible and rect.color.a > 0.9


func _is_white(img: Image) -> bool:
	var points: Array[Vector2i] = [
		Vector2i(img.get_width() / 2, img.get_height() / 2),
		Vector2i(4, 4),
		Vector2i(maxi(img.get_width() - 5, 0), maxi(img.get_height() - 5, 0)),
	]
	for point in points:
		var color := img.get_pixel(point.x, point.y)
		if color.r < 0.95 or color.g < 0.95 or color.b < 0.95:
			return false
	return true


func _center_text(img: Image) -> String:
	var color := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	return "%.3f,%.3f,%.3f" % [color.r, color.g, color.b]


func _checks_dir() -> String:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	return game_dir.get_base_dir().path_join("runs/checks")


func _begin_recording() -> void:
	_record_bus = AudioServer.get_bus_index("Master")
	if _record_bus < 0:
		_failures.append("Master bus missing")
		return
	var effect := AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(_record_bus, effect)
	var index := AudioServer.get_bus_effect_count(_record_bus) - 1
	_record = AudioServer.get_bus_effect(_record_bus, index) as AudioEffectRecord
	if _record == null:
		_failures.append("record effect missing")
		return
	_record.set_recording_active(true)


func _check_recording() -> void:
	if _record == null:
		_failures.append("audio record was not started")
		return
	_record.set_recording_active(false)
	var wav := _record.get_recording()
	_remove_record_effect()
	if wav == null or wav.data.is_empty():
		_failures.append("audio recording empty")
		return
	var peak := 0
	var loud := 0
	var data := wav.data
	if wav.format == AudioStreamWAV.FORMAT_16_BITS:
		var i := 0
		while i + 1 < data.size():
			var sample := absi(data.decode_s16(i))
			if sample > peak:
				peak = sample
			if sample >= _PEAK_MIN:
				loud += 1
			i += 2
	elif wav.format == AudioStreamWAV.FORMAT_8_BITS:
		for byte in data:
			var sample := absi(int(byte) - 128)
			if sample > peak:
				peak = sample
			if sample >= 8:
				loud += 1
	else:
		_failures.append("audio format %s" % wav.format)
		return
	print("audio peak=%d loud=%d bytes=%d rate=%d stereo=%s" % [peak, loud, data.size(), wav.mix_rate, wav.stereo])
	var peak_min := _PEAK_MIN if wav.format == AudioStreamWAV.FORMAT_16_BITS else 8
	if peak < peak_min or loud < _LOUD_MIN:
		_failures.append("beep level peak=%d loud=%d" % [peak, loud])


func _remove_record_effect() -> void:
	if _record_bus < 0 or _record == null:
		return
	var count := AudioServer.get_bus_effect_count(_record_bus)
	for index in range(count - 1, -1, -1):
		if AudioServer.get_bus_effect(_record_bus, index) == _record:
			AudioServer.remove_bus_effect(_record_bus, index)
			return


func _check(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		_failures.append("log file missing")
		return
	var text := FileAccess.get_file_as_string(path)
	var rows := text.split("\n", false)
	var events: Array[Dictionary] = []
	var previous := -1.0
	for row in rows:
		if row.is_empty():
			_failures.append("blank line")
			return
		var parsed: Variant = JSON.parse_string(row)
		if typeof(parsed) != TYPE_DICTIONARY:
			_failures.append("line is not JSON: %s" % row)
			return
		var line: Dictionary = parsed
		if not line.has("t") or (typeof(line.t) != TYPE_FLOAT and typeof(line.t) != TYPE_INT):
			_failures.append("line missing numeric t: %s" % row)
			return
		var stamp := float(line.t)
		if stamp < previous:
			_failures.append("t went down: %s then %s" % [previous, stamp])
			return
		previous = stamp
		events.append(line)
	var start_index := -1
	var flashes: Array[int] = []
	for i in events.size():
		var event_name := String(events[i].get("event", ""))
		if event_name == "session_start" and start_index < 0:
			start_index = i
		elif event_name == "start_flash":
			flashes.append(i)
	if start_index < 0:
		_failures.append("missing session_start")
		return
	if flashes.size() != 1:
		_failures.append("start_flash count %d" % flashes.size())
		return
	if flashes[0] <= start_index:
		_failures.append("start_flash before session_start")
		return
	var line := events[flashes[0]]
	print("start_flash %s" % JSON.stringify(line))
	if not is_equal_approx(float(line.get("duration_s", -1.0)), 0.25):
		_failures.append("duration_s %s" % line.get("duration_s", ""))
	var hz := line.get("beep_hz", null)
	if (typeof(hz) != TYPE_FLOAT and typeof(hz) != TYPE_INT) or int(hz) != 1000:
		_failures.append("beep_hz %s" % hz)
	if float(line.t) < 0.9:
		_failures.append("t %s is earlier than the 1s delay" % line.t)
