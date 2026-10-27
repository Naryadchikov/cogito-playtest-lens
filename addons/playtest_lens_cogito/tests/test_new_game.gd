extends Node

const MENU := "res://addons/cogito/DemoScenes/COGITO_0_MainMenu.tscn"
const BUTTON_PATH := "MainMenu/ContentMain/GameMenu/VBoxContainer/MarginContainer2/NewGame"
const LEVEL := "res://addons/cogito/DemoScenes/COGITO_3_Lobby.tscn"
const _LEVEL_WAIT_USEC := 90_000_000
const _PEAK_MIN := 1000
const _LOUD_MIN := 100

var _failures: PackedStringArray = PackedStringArray()
var _phase := 0
var _record: AudioEffectRecord
var _record_bus := -1
var _record_usec := 0
var _new_usec := 0
var _level_usec := 0
var _new_path := ""
var _level_path := ""
var _after_path := ""


func _ready() -> void:
	call_deferred("_detach_and_run")


func _detach_and_run() -> void:
	var tree := get_tree()
	var parent := get_parent()
	parent.remove_child(self)
	tree.root.add_child(self)
	_run()


func _run() -> void:
	if not has_node("/root/PlaytestLensLogger") or not has_node("/root/PlaytestLensCogito"):
		print("FAIL: autoload missing")
		get_tree().quit(1)
		return
	var logger: Node = get_node("/root/PlaytestLensLogger")
	var windowed := _windowed()
	print("display=%s headless_feature=%s" % [DisplayServer.get_name(), OS.has_feature("headless")])
	var err := get_tree().change_scene_to_file(MENU)
	if err != OK:
		_failures.append("change_scene_to_file returned %s" % error_string(err))
		_finish(logger)
		return
	var button := await _wait_for_button()
	if button == null:
		_failures.append("New Game button missing")
		_finish(logger)
		return
	print("new_game_button=%s" % String(button.get_path()))
	if _count_flashes(_read_events(String(logger.get("log_path")))) != 0:
		_failures.append("sync_flash before New Game")
	if windowed:
		Engine.max_fps = 30
		var checks := _checks_dir()
		_new_path = checks.path_join("10-newgame-flash.png")
		_level_path = checks.path_join("10-level-flash.png")
		_after_path = checks.path_join("10-after.png")
		_begin_recording()
		RenderingServer.frame_post_draw.connect(_on_post_draw, CONNECT_DEFERRED)
	button.pressed.emit()
	var start := Time.get_ticks_usec()
	var ready := false
	while Time.get_ticks_usec() - start < _LEVEL_WAIT_USEC:
		await get_tree().process_frame
		if _sequence_ready(_read_events(String(logger.get("log_path")), false)):
			ready = true
			if not windowed or _phase >= 4:
				break
	if not ready:
		_failures.append("new_game then level scene then level_load did not appear")
	if windowed and _phase < 4:
		_failures.append("screenshot timeout phase=%d" % _phase)
	if windowed:
		_check_recording()
	_finish(logger)


func _finish(logger: Node) -> void:
	logger.end_session()
	var events := _read_events(String(logger.get("log_path")))
	_check_sequence(events)
	if _failures.is_empty():
		print("PASS path=%s" % logger.get("log_path"))
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		get_tree().quit(1)


func _wait_for_button() -> BaseButton:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 5_000_000:
		var scene := get_tree().current_scene
		if scene != null:
			var button := scene.get_node_or_null(BUTTON_PATH) as BaseButton
			if button != null and button.is_node_ready():
				return button
		await get_tree().process_frame
	return null


func _windowed() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("headless")


func _sequence_ready(events: Array[Dictionary]) -> bool:
	return _sequence_indexes(events).x >= 0


func _check_sequence(events: Array[Dictionary]) -> void:
	var indexes := _sequence_indexes(events)
	if indexes.x < 0:
		_failures.append("missing sync_flash new_game, level scene, sync_flash level_load")
		return
	var new_line := events[indexes.x]
	var scene_line := events[indexes.y]
	var level_line := events[indexes.z]
	print("sync_flash %s" % JSON.stringify(new_line))
	print("scene %s" % JSON.stringify(scene_line))
	print("sync_flash %s" % JSON.stringify(level_line))
	var gap := float(level_line.get("t", 0.0)) - float(new_line.get("t", 0.0))
	print("flash_gap_s=%.4f" % gap)
	if gap <= 0.25:
		_failures.append("flash gap %.4f is inside the 0.25s flash" % gap)
	if String(level_line.get("scene", "")) != LEVEL:
		_failures.append("level_load scene %s" % level_line.get("scene", ""))


func _sequence_indexes(events: Array[Dictionary]) -> Vector3i:
	var new_at := -1
	var scene_at := -1
	var level_at := -1
	for i in events.size():
		var line := events[i]
		var event_name := String(line.get("event", ""))
		if new_at < 0 and event_name == "sync_flash" and String(line.get("reason", "")) == "new_game":
			new_at = i
		elif new_at >= 0 and scene_at < 0 and event_name == "scene" and String(line.get("scene", "")) == LEVEL:
			scene_at = i
		elif scene_at >= 0 and event_name == "sync_flash" and String(line.get("reason", "")) == "level_load":
			level_at = i
			break
	if new_at < 0 or scene_at < 0 or level_at < 0:
		return Vector3i(-1, -1, -1)
	return Vector3i(new_at, scene_at, level_at)


func _count_flashes(events: Array[Dictionary]) -> int:
	var count := 0
	for line in events:
		if String(line.get("event", "")) == "sync_flash":
			count += 1
	return count


func _on_post_draw() -> void:
	if _phase >= 4:
		return
	var showing := _flash_visible()
	var image := _grab()
	if image == null:
		return
	var white := _is_white(image)
	if _phase == 0 and showing and white:
		if _save(image, _new_path):
			_new_usec = Time.get_ticks_usec()
			print("saved new game flash %s" % _new_path)
			_phase = 1
	elif _phase == 1 and not showing:
		_phase = 2
	elif _phase == 2 and showing and white:
		if _save(image, _level_path):
			_level_usec = Time.get_ticks_usec()
			print("saved level flash %s" % _level_path)
			_phase = 3
	elif _phase == 3 and not showing and not white:
		if _save(image, _after_path):
			print("saved after %s" % _after_path)
			_phase = 4


func _flash_visible() -> bool:
	var rect := get_node_or_null("/root/PlaytestLensLogger/SyncFlash/FlashLayer/White") as ColorRect
	return rect != null and rect.visible and rect.color.a > 0.9 and _layer_visible(rect)


func _layer_visible(rect: ColorRect) -> bool:
	var layer := rect.get_parent()
	return layer != null and layer.visible


func _grab() -> Image:
	var viewport := get_tree().root.get_viewport()
	var texture := viewport.get_texture()
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _is_white(image: Image) -> bool:
	var points: Array[Vector2i] = [
		Vector2i(image.get_width() / 2, image.get_height() / 2),
		Vector2i(4, 4),
		Vector2i(maxi(image.get_width() - 5, 0), maxi(image.get_height() - 5, 0)),
	]
	for point in points:
		var color := image.get_pixel(point.x, point.y)
		if color.r < 0.95 or color.g < 0.95 or color.b < 0.95:
			return false
	return true


func _save(image: Image, path: String) -> bool:
	var err := image.save_png(path)
	if err != OK:
		_failures.append("save png %s: %s" % [path, error_string(err)])
		_phase = 4
		return false
	return true


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
	_record_usec = Time.get_ticks_usec()


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
	print("audio bytes=%d rate=%d stereo=%s" % [wav.data.size(), wav.mix_rate, wav.stereo])
	_check_beep(wav, "new_game", _new_usec)
	_check_beep(wav, "level_load", _level_usec)


func _check_beep(wav: AudioStreamWAV, label: String, flash_usec: int) -> void:
	if flash_usec <= 0 or _record_usec <= 0:
		_failures.append("%s audio window missing" % label)
		return
	var center := float(flash_usec - _record_usec) / 1_000_000.0
	var level := _window_level(wav, center - 0.05, center + 0.30)
	print("audio %s peak=%d loud=%d" % [label, level.x, level.y])
	var peak_min := _PEAK_MIN if wav.format == AudioStreamWAV.FORMAT_16_BITS else 8
	if level.x < peak_min or level.y < _LOUD_MIN:
		_failures.append("%s beep level peak=%d loud=%d" % [label, level.x, level.y])


func _window_level(wav: AudioStreamWAV, start_s: float, end_s: float) -> Vector2i:
	var data := wav.data
	var channels := 2 if wav.stereo else 1
	var bytes_per := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var frame := bytes_per * channels
	if frame <= 0 or wav.mix_rate <= 0:
		return Vector2i.ZERO
	var from_frame := maxi(int(start_s * float(wav.mix_rate)), 0)
	var to_frame := mini(int(end_s * float(wav.mix_rate)), data.size() / frame)
	var peak := 0
	var loud := 0
	var loud_at := _PEAK_MIN if wav.format == AudioStreamWAV.FORMAT_16_BITS else 8
	for index in range(from_frame, to_frame):
		var sample := 0
		if wav.format == AudioStreamWAV.FORMAT_16_BITS:
			sample = absi(data.decode_s16(index * frame))
		elif wav.format == AudioStreamWAV.FORMAT_8_BITS:
			sample = absi(int(data[index * frame]) - 128)
		else:
			_failures.append("audio format %s" % wav.format)
			return Vector2i.ZERO
		if sample > peak:
			peak = sample
		if sample >= loud_at:
			loud += 1
	return Vector2i(peak, loud)


func _remove_record_effect() -> void:
	if _record_bus < 0 or _record == null:
		return
	var count := AudioServer.get_bus_effect_count(_record_bus)
	for index in range(count - 1, -1, -1):
		if AudioServer.get_bus_effect(_record_bus, index) == _record:
			AudioServer.remove_bus_effect(_record_bus, index)
			return


func _read_events(path: String, strict: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		return events
	var text := FileAccess.get_file_as_string(path)
	var rows := text.split("\n", false)
	for i in rows.size():
		var row: String = rows[i]
		if row.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(row)
		if typeof(parsed) != TYPE_DICTIONARY:
			if not strict and i == rows.size() - 1:
				break
			if strict:
				_failures.append("line is not JSON: %s" % row)
			return events
		events.append(parsed)
	return events
