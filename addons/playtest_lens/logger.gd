extends Node

## Autoload. Listens and writes. Does not change gameplay, timing, input, or saves.

const _DIR := "user://playtest_lens"
const _POSITION_USEC := 500_000
const _StartFlashScript := preload("res://addons/playtest_lens/start_flash.gd")

var log_path := ""

var _file: FileAccess
var _origin_usec := 0
var _next_position_usec := 0
var _wall := ""
var _logged_scene_id := 0
var _running := false
var _finished := false


func _ready() -> void:
	if Engine.is_editor_hint() or _running:
		return
	_running = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_origin_usec = Time.get_ticks_usec()
	_next_position_usec = _origin_usec + _POSITION_USEC
	_wall = _utc_iso()
	if not _open_log():
		_running = false
		return
	log_event("session_start", {
		"wall_time": _wall,
		"godot_version": String(Engine.get_version_info().get("string", "")),
		"game_name": String(ProjectSettings.get_setting("application/config/name", "")),
		"game_version": String(ProjectSettings.get_setting("application/config/version", "")),
		"log_path": log_path,
	})
	var flash := _StartFlashScript.new()
	flash.name = "StartFlash"
	add_child(flash)


func _process(_delta: float) -> void:
	if not _running or _file == null:
		return
	_log_scene()
	_log_actions()
	var now := Time.get_ticks_usec()
	if now >= _next_position_usec:
		_next_position_usec = now + _POSITION_USEC
		_log_position()


func _log_actions() -> void:
	for action in InputMap.get_actions():
		var action_name := StringName(action)
		if Input.is_action_just_pressed(action_name):
			log_event("input", {"action": String(action_name), "pressed": true})
		if Input.is_action_just_released(action_name):
			log_event("input", {"action": String(action_name), "pressed": false})


func _exit_tree() -> void:
	end_session()


func end_session() -> void:
	if not _running or _finished or _file == null:
		return
	_finished = true
	log_event("session_end", {})
	_file.flush()
	_file.close()
	_file = null


func _open_log() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_DIR))
	# Colons are illegal in Windows file names. wall_time keeps ISO 8601.
	var res_path := "%s/%s.jsonl" % [_DIR, _wall.replace(":", "-")]
	log_path = ProjectSettings.globalize_path(res_path)
	_file = FileAccess.open(res_path, FileAccess.WRITE)
	if _file == null:
		printerr("Playtest Lens could not open the log file %s: %s" % [log_path, error_string(FileAccess.get_open_error())])
		log_path = ""
		return false
	return true


func _log_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var scene_id := scene.get_instance_id()
	if scene_id == _logged_scene_id:
		return
	_logged_scene_id = scene_id
	log_event("scene", {"scene": scene.scene_file_path})


func _log_position() -> void:
	var body := _find_player()
	if body == null:
		return
	var origin := body.global_position
	log_event("position", {
		"x": origin.x,
		"y": origin.y,
		"z": origin.z,
		"yaw": body.global_rotation_degrees.y,
	})


func _find_player() -> Node3D:
	var path := String(ProjectSettings.get_setting("playtest_lens/player_path", ""))
	if path.is_empty():
		return null
	var node: Node = null
	if path.begins_with("/"):
		node = get_tree().root.get_node_or_null(path)
	else:
		var scene := get_tree().current_scene
		if scene == null:
			return null
		node = scene.get_node_or_null(path)
	if node is Node3D:
		return node
	return null


func log_event(event_name: String, fields: Dictionary = {}) -> void:
	if _file == null:
		return
	var line := {"t": _seconds(), "event": event_name}
	for key in fields:
		line[key] = fields[key]
	_file.store_line(JSON.stringify(line))
	_file.flush()



func _seconds() -> float:
	return float(Time.get_ticks_usec() - _origin_usec) / 1_000_000.0


func _utc_iso() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
