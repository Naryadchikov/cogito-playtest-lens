extends Node

const ZONE := "Puzzle"
const PUZZLE := "FuseBox"
const OUTSIDE := Vector3(0, 0, 0)
const PLAYER_LAYER := 16

var _player: CharacterBody3D
var _zone := ""
var _puzzle := ""
var _inside_point := Vector3.ZERO
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_parent().get_node("Player") as CharacterBody3D
	var volume := get_parent().get_node("Volume") as Area3D
	_zone = String(volume.get("zone"))
	_puzzle = String(volume.get("puzzle"))
	_inside_point = volume.global_position
	ProjectSettings.set_setting("playtest_lens/player_path", "Player")
	_player.global_position = OUTSIDE
	_check_setup(volume)
	call_deferred("_detach_and_run")


func _check_setup(volume: Area3D) -> void:
	# Layer 16 is not the default. A volume left on mask 1 would miss this body.
	if _player.collision_layer != PLAYER_LAYER:
		_failures.append("player layer %d" % _player.collision_layer)
	if _zone != ZONE or _puzzle != PUZZLE:
		_failures.append("exports zone=%s puzzle=%s" % [_zone, _puzzle])
	if _inside_point.distance_to(OUTSIDE) < 4.0:
		_failures.append("volume is too close to the start")
	if volume.collision_layer != 0:
		_failures.append("volume layer %d" % volume.collision_layer)
	if not volume.monitoring:
		_failures.append("volume is not monitoring")
	if volume.monitorable:
		_failures.append("volume is monitorable")
	if volume.input_ray_pickable:
		_failures.append("volume picks input")
	if volume.gravity_space_override != Area3D.SPACE_OVERRIDE_DISABLED:
		_failures.append("volume overrides gravity")
	if not volume.get_collision_mask_value(5):
		_failures.append("volume mask misses layer 5")


func _detach_and_run() -> void:
	var tree := get_tree()
	var parent := get_parent()
	parent.remove_child(self)
	tree.root.add_child(self)
	_run()


func _run() -> void:
	if not _failures.is_empty():
		_finish(null)
		return
	if not has_node("/root/PlaytestLensLogger"):
		print("FAIL: PlaytestLensLogger autoload is missing")
		get_tree().quit(1)
		return
	var logger: Node = get_node("/root/PlaytestLensLogger")
	await _wait_sec(0.35)
	logger.log_event("marker", {"where": "outside"})
	await _glide(_inside_point)
	if not await _wait_until(_count_event.bind(logger, "zone_enter"), 2.0):
		_failures.append("no zone_enter at %s" % _player.global_position)
	logger.log_event("marker", {"where": "inside"})
	await _wait_sec(0.7)
	await _glide(OUTSIDE)
	if not await _wait_until(_count_event.bind(logger, "zone_exit"), 2.0):
		_failures.append("no zone_exit at %s" % _player.global_position)
	logger.log_event("marker", {"where": "after"})
	await _wait_sec(0.7)
	_finish(logger)


func _count_event(logger: Node, event_name: String) -> bool:
	var count := 0
	for line in _read_events(String(logger.get("log_path")), false):
		if String(line.get("event", "")) == event_name:
			count += 1
	return count >= 1


func _glide(target: Vector3) -> void:
	var guard := 0
	while _player.global_position.distance_to(target) > 0.2 and guard < 180:
		var step := target - _player.global_position
		if step.length() > 0.75:
			step = step.normalized() * 0.75
		_player.global_position += step
		_player.velocity = Vector3.ZERO
		_player.force_update_transform()
		await get_tree().physics_frame
		guard += 1
	_player.global_position = target
	_player.velocity = Vector3.ZERO
	_player.force_update_transform()
	await get_tree().physics_frame


func _finish(logger: Node) -> void:
	var path := ""
	if logger != null and logger.has_method("end_session"):
		logger.end_session()
		path = String(logger.get("log_path"))
		_check(path)
		var dest := _checks_dir().path_join("18-telemetry.jsonl")
		if not _copy_log(path, dest):
			_failures.append("could not copy the log")
		else:
			print("copy=%s" % dest)
	if _failures.is_empty():
		print("PASS path=%s" % path)
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		get_tree().quit(1)


func _wait_sec(seconds: float) -> void:
	var start := Time.get_ticks_usec()
	var need := int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() - start < need:
		await get_tree().process_frame


func _wait_until(pred: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_usec()
	var need := int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() - start < need:
		if bool(pred.call()):
			return true
		await get_tree().physics_frame
	return bool(pred.call())


func _check(path: String) -> void:
	var events := _read_events(path, true)
	var names: PackedStringArray = PackedStringArray()
	for line in events:
		names.append(String(line.get("event", "")))
	print("events=%s" % " ".join(names))
	if not _failures.is_empty() and events.is_empty():
		return
	var phase := 0
	var enters := 0
	var exits := 0
	var saw_outside := false
	var saw_inside := false
	var saw_after := false
	var saw_position_inside := false
	var saw_position_after := false
	for line in events:
		var event := String(line.get("event", ""))
		if event == "zone_enter":
			enters += 1
			if phase != 0:
				_failures.append("zone_enter in phase %d" % phase)
			_check_named(line)
			phase = 1
			continue
		if event == "zone_exit":
			exits += 1
			if phase != 1:
				_failures.append("zone_exit in phase %d" % phase)
			_check_named(line)
			phase = 2
			continue
		if phase == 1:
			_check_named(line)
			if event == "position":
				saw_position_inside = true
		elif line.has("zone") or line.has("puzzle"):
			_failures.append("%s carries a zone outside" % event)
		elif event == "position" and phase == 2:
			saw_position_after = true
		if event == "marker":
			var where := String(line.get("where", ""))
			if where == "outside" and phase == 0:
				saw_outside = true
			elif where == "inside" and phase == 1:
				saw_inside = true
			elif where == "after" and phase == 2:
				saw_after = true
			else:
				_failures.append("marker %s in phase %d" % [where, phase])
	if enters != 1:
		_failures.append("zone_enter count %d" % enters)
	if exits != 1:
		_failures.append("zone_exit count %d" % exits)
	if not saw_outside or not saw_inside or not saw_after:
		_failures.append("markers outside=%s inside=%s after=%s" % [saw_outside, saw_inside, saw_after])
	if not saw_position_inside:
		_failures.append("no position line while inside")
	if not saw_position_after:
		_failures.append("no position line after exit")


func _check_named(line: Dictionary) -> void:
	if not line.has("zone") or not line.has("puzzle"):
		_failures.append("%s missing zone or puzzle" % line.get("event"))
		return
	if String(line["zone"]) != _zone or String(line["puzzle"]) != _puzzle:
		_failures.append("%s zone=%s puzzle=%s" % [line.get("event"), line["zone"], line["puzzle"]])


func _checks_dir() -> String:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	return game_dir.get_base_dir().path_join("runs/checks")


func _copy_log(src: String, dest: String) -> bool:
	if src.is_empty() or not FileAccess.file_exists(src):
		return false
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var file := FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(FileAccess.get_file_as_string(src))
	file.close()
	return true


func _read_events(path: String, strict: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		if strict:
			_failures.append("log file missing")
		return events
	var text := FileAccess.get_file_as_string(path)
	var rows := text.split("\n", false)
	var previous := -1.0
	for row in rows:
		if row.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(row)
		if typeof(parsed) != TYPE_DICTIONARY:
			if strict:
				_failures.append("line is not JSON: %s" % row)
			return events
		var line: Dictionary = parsed
		if strict:
			if not line.has("t") or (typeof(line.t) != TYPE_FLOAT and typeof(line.t) != TYPE_INT):
				_failures.append("line missing numeric t: %s" % row)
				return events
			var stamp := float(line.t)
			if stamp < previous:
				_failures.append("t went down: %s then %s" % [previous, stamp])
				return events
			previous = stamp
		events.append(line)
	return events
