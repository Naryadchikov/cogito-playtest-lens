extends Node

const LoggerScript := preload("res://addons/playtest_lens/logger.gd")
const SCENE_PLAYER := "res://addons/playtest_lens/tests/scene_player.tscn"
const _QUIET_USEC := 2_000_000
const _FLASH_WAIT_USEC := 2_000_000
const _AFTER_USEC := 500_000

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	ProjectSettings.set_setting("playtest_lens/player_path", "Player")
	call_deferred("_detach_and_run")


func _detach_and_run() -> void:
	var tree := get_tree()
	var parent := get_parent()
	parent.remove_child(self)
	tree.root.add_child(self)
	_run()


func _run() -> void:
	if not has_node("/root/PlaytestLensLogger"):
		print("FAIL: PlaytestLensLogger autoload is missing")
		get_tree().quit(1)
		return
	var logger: LoggerScript = get_node("/root/PlaytestLensLogger")
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < _QUIET_USEC:
		await get_tree().process_frame
	var early := _read_events(logger.log_path)
	if early.is_empty() and _failures.is_empty():
		_failures.append("log empty before the scene change")
	var early_flashes := 0
	for line in early:
		if String(line.get("event", "")) == "sync_flash":
			early_flashes += 1
	if early_flashes != 0:
		_failures.append("sync_flash in the first 2s: %d" % early_flashes)
	var err := get_tree().change_scene_to_file(SCENE_PLAYER)
	if err != OK:
		_failures.append("change_scene_to_file returned %s" % error_string(err))
	else:
		var saw := false
		var wait_start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - wait_start < _FLASH_WAIT_USEC:
			await get_tree().process_frame
			if _count_reason(_read_events(logger.log_path, false), "level_load") == 1:
				saw = true
				break
		if not saw:
			_failures.append("level_load flash did not appear")
		else:
			var accepted := logger.sync_flash("level_load")
			print("second sync_flash accepted=%s" % accepted)
			if accepted:
				_failures.append("second sync_flash during the flash was accepted")
	var settle := Time.get_ticks_usec()
	while Time.get_ticks_usec() - settle < _AFTER_USEC:
		await get_tree().process_frame
	logger.end_session()
	_check(logger.log_path)
	if _failures.is_empty():
		print("PASS path=%s" % logger.log_path)
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		get_tree().quit(1)


func _check(path: String) -> void:
	var events := _read_events(path)
	if not _failures.is_empty() and events.is_empty():
		return
	var flashes: Array[Dictionary] = []
	for line in events:
		if String(line.get("event", "")) == "sync_flash":
			flashes.append(line)
			print("sync_flash %s" % JSON.stringify(line))
	if flashes.size() != 1:
		_failures.append("sync_flash count %d" % flashes.size())
		return
	var line := flashes[0]
	if String(line.get("reason", "")) != "level_load":
		_failures.append("reason %s" % line.get("reason", ""))
	if not is_equal_approx(float(line.get("duration_s", -1.0)), 0.25):
		_failures.append("duration_s %s" % line.get("duration_s", ""))
	var hz := line.get("beep_hz", null)
	if (typeof(hz) != TYPE_FLOAT and typeof(hz) != TYPE_INT) or int(hz) != 1000:
		_failures.append("beep_hz %s" % hz)
	if float(line.get("t", -1.0)) < 2.0:
		_failures.append("t %s is inside the first 2s" % line.get("t", ""))
	if String(line.get("scene", "")) != SCENE_PLAYER:
		_failures.append("scene %s" % line.get("scene", ""))


func _count_reason(events: Array[Dictionary], reason: String) -> int:
	var count := 0
	for line in events:
		if String(line.get("event", "")) == "sync_flash" and String(line.get("reason", "")) == reason:
			count += 1
	return count


func _read_events(path: String, strict: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		if strict:
			_failures.append("log file missing")
		return events
	var text := FileAccess.get_file_as_string(path)
	var rows := text.split("\n", false)
	var previous := -1.0
	for i in rows.size():
		var row: String = rows[i]
		if row.is_empty():
			if strict:
				_failures.append("blank line")
			return events
		var parsed: Variant = JSON.parse_string(row)
		if typeof(parsed) != TYPE_DICTIONARY:
			if not strict and i == rows.size() - 1:
				break
			if strict:
				_failures.append("line is not JSON: %s" % row)
			return events
		var line: Dictionary = parsed
		if not line.has("t") or (typeof(line.t) != TYPE_FLOAT and typeof(line.t) != TYPE_INT):
			_failures.append("line missing numeric t: %s" % row)
			return events
		var stamp := float(line.t)
		if stamp < previous:
			if strict:
				_failures.append("t went down: %s then %s" % [previous, stamp])
			return events
		previous = stamp
		events.append(line)
	return events
