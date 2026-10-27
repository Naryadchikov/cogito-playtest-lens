extends Node

const LoggerScript := preload("res://addons/playtest_lens/logger.gd")
const SCENE_A := "res://addons/playtest_lens/tests/test_logger.tscn"
const SCENE_B := "res://addons/playtest_lens/tests/scene_b.tscn"
const POSE_A := Vector3(1.25, 2.5, 3.75)
const YAW_A := 90.0
const PITCH_A := -18.0
const POSE_B := Vector3(-4.5, 0.5, 6.25)
const YAW_B := -35.0
const PITCH_B := 27.0

var _player: Node3D
var _camera: Camera3D
var _failures: PackedStringArray = PackedStringArray()
var _scene_did_change := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_parent().get_node("Player") as Node3D
	_camera = get_parent().get_node("Camera") as Camera3D
	ProjectSettings.set_setting("playtest_lens/player_path", "Player")
	_apply_pose(POSE_A, YAW_A, PITCH_A)
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
	await _fire("jump", true)
	await _fire("jump", false)
	await _fire("interact", true)
	await _fire("interact", false)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, -15)
	Input.parse_input_event(motion)
	await _next_frame()
	await _hold_forward_stick()
	await _wait_sec(0.7)
	_apply_pose(POSE_B, YAW_B, PITCH_B)
	await _wait_sec(0.7)
	get_tree().scene_changed.connect(_on_test_scene_changed)
	var err := get_tree().change_scene_to_file(SCENE_B)
	if err != OK:
		_failures.append("change_scene_to_file returned %s" % error_string(err))
	else:
		var frames := 0
		while not _scene_did_change and frames < 300:
			await get_tree().process_frame
			frames += 1
		if not _scene_did_change:
			_failures.append("scene did not change")
	await _next_frame()
	logger.end_session()
	_check(logger.log_path)
	if _failures.is_empty():
		print("PASS path=%s" % logger.log_path)
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		get_tree().quit(1)


func _on_test_scene_changed() -> void:
	_scene_did_change = true


func _apply_pose(origin: Vector3, yaw: float, pitch: float) -> void:
	_player.global_position = origin
	_player.global_rotation_degrees = Vector3.ZERO
	_camera.global_rotation_degrees = Vector3(pitch, yaw, 0.0)
	_camera.current = true


func _fire(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	await _next_frame()


func _hold_forward_stick() -> void:
	for _i in 4:
		var stick := InputEventJoypadMotion.new()
		stick.axis = JOY_AXIS_LEFT_Y
		stick.axis_value = -1.0
		Input.parse_input_event(stick)
		await _next_frame()


func _next_frame() -> void:
	var frame := Engine.get_process_frames()
	while Engine.get_process_frames() == frame:
		await get_tree().process_frame


func _wait_sec(seconds: float) -> void:
	var start := Time.get_ticks_usec()
	var need := int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() - start < need:
		await get_tree().process_frame


func _check(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		_failures.append("log file missing")
		return
	var text := FileAccess.get_file_as_string(path)
	var rows := text.split("\n", true)
	if rows.size() > 0 and rows[-1].is_empty():
		rows.remove_at(rows.size() - 1)
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
		if not line.has("event"):
			_failures.append("line missing event: %s" % row)
			return
		var stamp := float(line.t)
		if stamp < previous:
			_failures.append("t went down: %s then %s" % [previous, stamp])
			return
		previous = stamp
		events.append(line)
	if events.is_empty():
		_failures.append("log has no lines")
		return
	if String(events[0].event) != "session_start":
		_failures.append("first event is %s" % events[0].event)
	_check_start(events[0], path)
	if String(events[-1].event) != "session_end":
		_failures.append("last event is %s" % events[-1].event)
	_check_inputs(events)
	_check_scene(events)
	_check_positions(events)


func _check_start(line: Dictionary, path: String) -> void:
	var wall := String(line.get("wall_time", ""))
	var regex := RegEx.new()
	regex.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	if regex.search(wall) == null:
		_failures.append("wall_time is not UTC ISO 8601: %s" % wall)
	var version := String(Engine.get_version_info().get("string", ""))
	if String(line.get("godot_version", "")) != version:
		_failures.append("godot_version %s" % line.get("godot_version", ""))
	var game_name := String(ProjectSettings.get_setting("application/config/name", ""))
	var game_version := String(ProjectSettings.get_setting("application/config/version", ""))
	if String(line.get("game_name", "")) != game_name:
		_failures.append("game_name %s" % line.get("game_name", ""))
	if String(line.get("game_version", "")) != game_version:
		_failures.append("game_version %s" % line.get("game_version", ""))
	var logged := String(line.get("log_path", ""))
	if not logged.begins_with("user://") or logged != path:
		_failures.append("log_path %s" % logged)
	if path.get_file() != wall.replace(":", "-") + ".jsonl":
		_failures.append("log file name %s" % path.get_file())
	if path.get_base_dir().get_file() != "playtest_lens":
		_failures.append("log directory %s" % path.get_base_dir())


func _check_inputs(events: Array[Dictionary]) -> void:
	var expected: Array[Dictionary] = [
		{"action": "jump", "pressed": true},
		{"action": "jump", "pressed": false},
		{"action": "interact", "pressed": true},
		{"action": "interact", "pressed": false},
		{"action": "ui_up", "pressed": true},
		{"action": "forward", "pressed": true},
	]
	var found: Array[Dictionary] = []
	for line in events:
		if String(line.event) != "input":
			continue
		found.append(line)
	if found.size() != expected.size():
		var summary := ""
		for line in found:
			summary += "%s:%s " % [line.get("action", ""), line.get("pressed", "")]
		_failures.append("input count %d (%s)" % [found.size(), summary])
		return
	for i in expected.size():
		if String(found[i].get("action", "")) != String(expected[i].action) or bool(found[i].get("pressed", null)) != bool(expected[i].pressed):
			_failures.append("input %d is %s pressed=%s" % [i, found[i].get("action", ""), found[i].get("pressed", "")])


func _check_scene(events: Array[Dictionary]) -> void:
	var saw_a := false
	var saw_b := false
	for line in events:
		if String(line.event) != "scene":
			continue
		var path := String(line.get("scene", ""))
		if path == SCENE_A:
			saw_a = true
		elif path == SCENE_B and saw_a:
			saw_b = true
		elif path == SCENE_B:
			_failures.append("scene B before the opening scene")
		else:
			_failures.append("unexpected scene %s" % path)
	if not saw_a:
		_failures.append("missing scene %s" % SCENE_A)
	if not saw_b:
		_failures.append("missing scene %s" % SCENE_B)


func _check_positions(events: Array[Dictionary]) -> void:
	var saw_a := false
	var saw_b := false
	for line in events:
		if String(line.event) != "position":
			continue
		if not line.has("yaw") or not line.has("pitch"):
			_failures.append("position missing yaw or pitch")
			continue
		if _pose(line, POSE_A, YAW_A, PITCH_A):
			saw_a = true
		elif _pose(line, POSE_B, YAW_B, PITCH_B):
			if saw_a:
				saw_b = true
			else:
				_failures.append("position B before A")
		else:
			_failures.append("unexpected position x=%s y=%s z=%s yaw=%s pitch=%s" % [line.get("x"), line.get("y"), line.get("z"), line.get("yaw"), line.get("pitch")])
	if not saw_a:
		_failures.append("missing position A")
	if not saw_b:
		_failures.append("missing position B")


func _pose(line: Dictionary, origin: Vector3, yaw: float, pitch: float) -> bool:
	return _near(line.get("x"), origin.x) and _near(line.get("y"), origin.y) and _near(line.get("z"), origin.z) and _near(line.get("yaw"), yaw) and _near(line.get("pitch"), pitch)


func _near(got: Variant, want: float) -> bool:
	if typeof(got) != TYPE_FLOAT and typeof(got) != TYPE_INT:
		return false
	return absf(float(got) - want) <= 0.001
