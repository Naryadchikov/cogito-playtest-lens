extends Node

## Autoload. Listens and writes. Does not change gameplay, timing, input, or saves.

const _DIR := "user://playtest_lens"
const _POSITION_USEC := 500_000
const _PERF_USEC := 1_000_000
# Engine.get_frames_per_second() is only whole after its first full second, so no perf line before this age.
const _PERF_WARM_USEC := 2_000_000
const SCHEMA_VERSION := 1
const _SyncFlashScript := preload("res://addons/playtest_lens/sync_flash.gd")
const _VolumeScript := preload("res://addons/playtest_lens/telemetry_volume.gd")

var log_path := ""

var _file: FileAccess
var _origin_usec := 0
var _next_position_usec := 0
var _next_perf_usec := 0
var _was_paused := false
var _wall := ""
var _logged_scene_id := 0
var _running := false
var _finished := false
var _sync: Node
# Volumes the player is inside, oldest first. The last one stamps later lines.
var _inside: Array[Dictionary] = []
var _volume_calls: Dictionary = {}
var _need_overlap := false


func _ready() -> void:
	set_physics_process(false)
	if Engine.is_editor_hint() or _running:
		return
	_running = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_origin_usec = Time.get_ticks_usec()
	_next_position_usec = _origin_usec + _POSITION_USEC
	_next_perf_usec = _origin_usec + _PERF_USEC
	_wall = _utc_iso()
	if not _open_log():
		_running = false
		return
	log_event("session_start", {
		"schema": SCHEMA_VERSION,
		"session_id": "%s-%d" % [_wall.replace(":", "-"), OS.get_process_id()],
		"wall_time": _wall,
		"godot_version": String(Engine.get_version_info().get("string", "")),
		"game_name": String(ProjectSettings.get_setting("application/config/name", "")),
		"game_version": String(ProjectSettings.get_setting("application/config/version", "")),
		"os": OS.get_name(),
		"renderer": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"log_path": log_path,
	})
	_sync = _SyncFlashScript.new()
	_sync.name = "SyncFlash"
	add_child(_sync)


func _process(_delta: float) -> void:
	if not _running or _file == null:
		return
	_log_pause()
	_log_scene()
	_log_actions()
	var now := Time.get_ticks_usec()
	if now >= _next_position_usec:
		_next_position_usec = now + _POSITION_USEC
		_log_position()
	if now >= _next_perf_usec:
		_next_perf_usec = now + _PERF_USEC
		_log_perf(now, _delta)


# A cold frame counter would read as a hitch, so no perf line until it is warm.
func _log_perf(now: int, delta: float) -> void:
	if now - _origin_usec < _PERF_WARM_USEC:
		return
	log_event("perf", {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": snappedf(delta * 1000.0, 0.01),
	})


# This node runs while the tree is paused, so it sees both edges.
func _log_pause() -> void:
	var paused := get_tree().paused
	if paused == _was_paused:
		return
	_was_paused = paused
	log_event("pause" if paused else "resume", {})


# F9 marks a moment for the analyst. Listening only: never handled.
func _input(event: InputEvent) -> void:
	if not _running or _file == null:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F9:
			log_event("marker", {})


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	if not _need_overlap:
		return
	_need_overlap = false
	_catch_overlaps()


func _log_actions() -> void:
	for action in InputMap.get_actions():
		var action_name := StringName(action)
		if Input.is_action_just_pressed(action_name):
			log_event("input", {"action": String(action_name), "pressed": true})
		if Input.is_action_just_released(action_name):
			log_event("input", {"action": String(action_name), "pressed": false})


func _exit_tree() -> void:
	end_session("quit")


func end_session(reason := "quit") -> void:
	if not _running or _finished or _file == null:
		return
	_finished = true
	log_event("session_end", {"reason": reason})
	_file.flush()
	_file.close()
	_file = null


func _open_log() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_DIR))
	# Colons are illegal in Windows file names. wall_time keeps ISO 8601.
	# user:// so the log does not name the account or the machine.
	var res_path := "%s/%s.jsonl" % [_DIR, _wall.replace(":", "-")]
	log_path = res_path
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
	_sync_volumes(scene)
	log_event("scene", {"scene": scene.scene_file_path})
	if _find_player() != null:
		sync_flash("level_load")


func _log_position() -> void:
	var body := _find_player()
	if body == null:
		return
	var origin := body.global_position
	var fields := {
		"x": origin.x,
		"y": origin.y,
		"z": origin.z,
	}
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var look := camera.global_rotation_degrees
		fields["yaw"] = look.y
		fields["pitch"] = look.x
	log_event("position", fields)


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


func sync_flash(reason: String) -> bool:
	if _sync == null or not _sync.has_method("trigger"):
		return false
	var extra := {}
	if reason == "level_load":
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path != "":
			extra["scene"] = scene.scene_file_path
	return bool(_sync.call("trigger", reason, extra))


func log_event(event_name: String, fields: Dictionary = {}) -> void:
	if _file == null:
		return
	var line := {"t": _seconds(), "event": event_name}
	# Active zone first. Caller fields win, so an enter or exit names its own volume.
	if not _inside.is_empty():
		var active: Dictionary = _inside[-1]
		line["zone"] = String(active["zone"])
		line["puzzle"] = String(active["puzzle"])
	for key in fields:
		line[key] = fields[key]
	_file.store_line(JSON.stringify(line))
	_file.flush()


func _sync_volumes(scene: Node) -> void:
	_leave_all_volumes()
	_disconnect_volumes()
	var found := false
	for node in get_tree().get_nodes_in_group(_VolumeScript.GROUP_NAME):
		if not node is Area3D:
			continue
		if node.get_script() != _VolumeScript:
			continue
		if node != scene and not scene.is_ancestor_of(node):
			continue
		_connect_volume(node)
		found = true
	if found:
		_need_overlap = true
		set_physics_process(true)


func _connect_volume(volume: Area3D) -> void:
	var id := volume.get_instance_id()
	if _volume_calls.has(id):
		return
	var entered := _on_volume_body_entered.bind(volume)
	var exited := _on_volume_body_exited.bind(volume)
	volume.body_entered.connect(entered)
	volume.body_exited.connect(exited)
	# The node is not stored. The loading screen frees the old level before
	# the next one is current, and reading that stored node assigns a freed
	# instance, which aborts the scene change.
	_volume_calls[id] = {
		"entered": entered,
		"exited": exited,
	}


func _disconnect_volumes() -> void:
	for id in _volume_calls.keys():
		var row: Dictionary = _volume_calls[id]
		var volume := _volume_by_id(id)
		if volume == null:
			continue
		var entered: Callable = row["entered"]
		var exited: Callable = row["exited"]
		if volume.body_entered.is_connected(entered):
			volume.body_entered.disconnect(entered)
		if volume.body_exited.is_connected(exited):
			volume.body_exited.disconnect(exited)
	_volume_calls.clear()


# Null once the level that owned the volume has been freed.
func _volume_by_id(id: int) -> Area3D:
	var node: Object = instance_from_id(id)
	if node is Area3D and (node as Area3D).is_inside_tree():
		return node as Area3D
	return null


func _catch_overlaps() -> void:
	var player := _find_player()
	if player == null:
		return
	for id in _volume_calls.keys():
		var volume := _volume_by_id(int(id))
		if volume == null:
			continue
		for body in volume.get_overlapping_bodies():
			if body == player:
				_enter_volume(volume)
				break


func _on_volume_body_entered(body: Node3D, volume: Area3D) -> void:
	if body != _find_player():
		return
	_enter_volume(volume)


func _on_volume_body_exited(body: Node3D, volume: Area3D) -> void:
	if body != _find_player():
		return
	_exit_volume(volume)


func _enter_volume(volume: Area3D) -> void:
	if not is_instance_valid(volume):
		return
	var id := volume.get_instance_id()
	for item in _inside:
		if int(item["id"]) == id:
			return
	var names := _volume_names(volume)
	_inside.append({"id": id, "zone": names["zone"], "puzzle": names["puzzle"]})
	log_event("zone_enter", {"zone": names["zone"], "puzzle": names["puzzle"]})


func _exit_volume(volume: Area3D) -> void:
	if not is_instance_valid(volume):
		return
	var id := volume.get_instance_id()
	var zone := ""
	var puzzle := ""
	var found := false
	var next: Array[Dictionary] = []
	for item in _inside:
		if int(item["id"]) == id:
			found = true
			zone = String(item["zone"])
			puzzle = String(item["puzzle"])
		else:
			next.append(item)
	if not found:
		return
	_inside = next
	log_event("zone_exit", {"zone": zone, "puzzle": puzzle})


func _leave_all_volumes() -> void:
	var leaving: Array[Dictionary] = []
	leaving.assign(_inside)
	_inside.clear()
	leaving.reverse()
	for item in leaving:
		log_event("zone_exit", {
			"zone": String(item["zone"]),
			"puzzle": String(item["puzzle"]),
		})


func _volume_names(volume: Object) -> Dictionary:
	return {
		"zone": _string_prop(volume, "zone"),
		"puzzle": _string_prop(volume, "puzzle"),
	}


func _string_prop(node: Object, key: String) -> String:
	var value: Variant = node.get(key)
	if value == null:
		return ""
	return String(value)


func _seconds() -> float:
	return float(Time.get_ticks_usec() - _origin_usec) / 1_000_000.0


func _utc_iso() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
