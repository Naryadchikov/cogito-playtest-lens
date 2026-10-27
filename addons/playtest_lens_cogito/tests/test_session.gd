extends Node

const MENU := "res://addons/cogito/DemoScenes/COGITO_0_MainMenu.tscn"
const BUTTON_PATH := "MainMenu/ContentMain/GameMenu/VBoxContainer/MarginContainer2/NewGame"
const LEVEL := "res://addons/cogito/DemoScenes/COGITO_3_Lobby.tscn"
const LEVEL_WAIT_S := 90.0
const MOVE_S := 3.0
const OUT_M := 15.0
const IDLE_S := 41.0
const LOOK_S := 20.0
const YAW_SWEEP_DEG := 50.0
const PITCH_SWEEP_DEG := 25.0
const AFTER_S := 2.0
const AFTER_M := 4.0
const IDLE_MIN_S := 40.0
const BACK_MIN_M := 12.0
const HOME_M := 1.5
const RUN_LIMIT_S := 180.0

var _failures: PackedStringArray = PackedStringArray()
var _deadline_usec := 0
var _health_died := false
var _reported_timeout := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deadline_usec = Time.get_ticks_usec() + int(RUN_LIMIT_S * 1_000_000.0)
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
	print("phase=menu")
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
	button.pressed.emit()
	print("phase=level")
	if not await _wait_for_level(logger, 1):
		_failures.append("new_game then level scene then level_load did not appear")
		_finish(logger)
		return
	var player := _player()
	if player == null:
		_failures.append("player missing after level load")
		_finish(logger)
		return
	_hold(player)
	print("phase=move_out")
	await _slide(player, Vector3(OUT_M, 0.0, 0.0), MOVE_S)
	print("phase=move_back")
	await _slide(player, Vector3(-OUT_M, 0.0, 0.0), MOVE_S)
	print("phase=idle")
	await _look_then_hold(player)
	print("phase=kill")
	if not await _kill(player):
		_failures.append("health damage did not emit death")
		_finish(logger)
		return
	var retry := _death_button(player)
	if retry == null:
		_failures.append("death screen button missing")
		_finish(logger)
		return
	print("phase=retry")
	retry.pressed.emit()
	if not await _wait_for_level(logger, 2):
		_failures.append("retry did not load the level again")
		_finish(logger)
		return
	player = _player()
	if player == null:
		_failures.append("player missing after retry")
		_finish(logger)
		return
	_hold(player)
	print("phase=move_after")
	await _slide(player, Vector3(AFTER_M, 0.0, 0.0), AFTER_S)
	_finish(logger)


func _finish(logger: Node) -> void:
	logger.end_session()
	var path := String(logger.get("log_path"))
	var events := _read_events(path)
	_check_sequence(events)
	if _failures.is_empty():
		var dest := _checks_dir().path_join("15-session.jsonl")
		if not _copy_log(path, dest):
			_failures.append("could not copy log to %s" % dest)
	if _failures.is_empty():
		print("PASS path=%s" % path)
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		print("log=%s" % path)
		get_tree().quit(1)


func _wait_for_button() -> BaseButton:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 5_000_000 and not _timed_out():
		var scene := get_tree().current_scene
		if scene != null:
			var button := scene.get_node_or_null(BUTTON_PATH) as BaseButton
			if button != null and button.is_node_ready():
				return button
		await get_tree().process_frame
	return null


func _wait_for_level(logger: Node, level_loads: int) -> bool:
	var start := Time.get_ticks_usec()
	var limit := int(LEVEL_WAIT_S * 1_000_000.0)
	while Time.get_ticks_usec() - start < limit and not _timed_out():
		await get_tree().process_frame
		var events := _read_events(String(logger.get("log_path")), false)
		if _level_load_count(events) >= level_loads and _opening_ready(events) and _player() != null:
			return true
	return false


func _wait_seconds(seconds: float) -> void:
	var start := Time.get_ticks_usec()
	var limit := int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() - start < limit and not _timed_out():
		await get_tree().process_frame


# Body yaw and head pitch, the same axes COGITO's mouse look uses.
# Two slow sweeps, then the view stays put for the rest of the stand.
func _look_then_hold(player: Node3D) -> void:
	var body := player.get_node_or_null("Body") as Node3D
	var head := player.get_node_or_null("Body/Neck/Head") as Node3D
	if body == null or head == null:
		_failures.append("player body or head missing")
		await _wait_seconds(IDLE_S)
		return
	var yaw0 := body.rotation.y
	var pitch0 := head.rotation.x
	var t0 := Time.get_ticks_usec()
	var look_us := int(LOOK_S * 1_000_000.0)
	var total_us := int(IDLE_S * 1_000_000.0)
	var held_pitch := clampf(pitch0 + deg_to_rad(PITCH_SWEEP_DEG), deg_to_rad(-90.0), deg_to_rad(90.0))
	while not _timed_out():
		var elapsed := Time.get_ticks_usec() - t0
		if elapsed >= look_us:
			body.rotation.y = yaw0
			head.rotation.x = held_pitch
		else:
			var u := float(elapsed) / float(look_us)
			var yaw_wave := sin(u * TAU * 2.0)
			var pitch_wave := sin(u * TAU * 2.0 + PI * 0.5)
			body.rotation.y = yaw0 + deg_to_rad(YAW_SWEEP_DEG * yaw_wave)
			head.rotation.x = clampf(pitch0 + deg_to_rad(PITCH_SWEEP_DEG * pitch_wave), deg_to_rad(-90.0), deg_to_rad(90.0))
		if elapsed >= total_us:
			return
		await get_tree().process_frame


func _timed_out() -> bool:
	if Time.get_ticks_usec() < _deadline_usec:
		return false
	if not _reported_timeout:
		_reported_timeout = true
		_failures.append("run exceeded %ss" % RUN_LIMIT_S)
	return true


func _player() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var node := scene.get_node_or_null("Player")
	if node is Node3D and node.is_node_ready():
		return node
	return null


func _hold(player: Node3D) -> void:
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO


func _slide(player: Node3D, offset: Vector3, seconds: float) -> void:
	var start := player.global_position
	var t0 := Time.get_ticks_usec()
	var duration := maxi(int(seconds * 1_000_000.0), 1)
	while not _timed_out():
		var elapsed := Time.get_ticks_usec() - t0
		var u := 1.0 if elapsed >= duration else float(elapsed) / float(duration)
		player.global_position = start + offset * u
		if elapsed >= duration:
			return
		await get_tree().process_frame


func _kill(player: Node) -> bool:
	var health := player.get_node_or_null("HealthAttribute") as CogitoHealthAttribute
	if health == null:
		_failures.append("health attribute missing")
		return false
	for _i in 8:
		if not health.death.is_connected(_on_health_death):
			health.death.connect(_on_health_death, CONNECT_ONE_SHOT)
		var amount := maxf(health.value_max, health.value_current) + 100.0
		if player.has_method("decrease_attribute"):
			player.call("decrease_attribute", "health", amount)
		else:
			health.subtract(amount)
		if _health_died:
			return true
		await get_tree().process_frame
		if _health_died:
			return true
	return false


func _on_health_death() -> void:
	_health_died = true


func _death_button(player: Node) -> BaseButton:
	var screen := player.find_child("DeathScreen", true, false) as CogitoDeathScreen
	if screen == null or not screen.visible:
		return null
	return screen.load_button


func _opening_ready(events: Array[Dictionary]) -> bool:
	var new_at := _find_event(events, 0, "sync_flash", "new_game")
	return new_at >= 0 and _find_scene(events, new_at + 1) >= 0


func _check_sequence(events: Array[Dictionary]) -> void:
	if events.is_empty():
		_failures.append("log empty")
		return
	var previous := -1.0
	for line in events:
		var t := float(line.get("t", -1.0))
		if t < previous:
			_failures.append("time went backwards")
			return
		previous = t
	var new_at := _find_event(events, 0, "sync_flash", "new_game")
	var scene_at := _find_scene(events, new_at + 1)
	var load_at := _find_event(events, scene_at + 1, "sync_flash", "level_load")
	var death_at := _find_event(events, load_at + 1, "death", "")
	var reload_at := _find_scene(events, death_at + 1)
	var reload_flash := _find_event(events, reload_at + 1, "sync_flash", "level_load")
	var end_at := _find_event(events, reload_flash + 1, "session_end", "")
	if new_at < 0 or scene_at < 0 or load_at < 0 or death_at < 0 or reload_at < 0 or reload_flash < 0 or end_at < 0:
		_failures.append("missing new_game, scene, level_load, death, scene, level_load, session_end")
		return
	if String(events[load_at].get("scene", "")) != LEVEL or String(events[reload_flash].get("scene", "")) != LEVEL:
		_failures.append("level_load scene mismatch")
	var after_flash := _indexes_between(events, load_at + 1, death_at, "position")
	if after_flash.size() < 2:
		_failures.append("fewer than 2 position lines before death")
	# The first position can be written in the same moment as level_load, just before that line.
	var before := _indexes_between(events, scene_at + 1, death_at, "position")
	if before.size() >= 2:
		_check_walk(events, before, death_at)
	if not events[death_at].has("x"):
		_failures.append("death has no position")
	var after := _indexes_between(events, reload_flash + 1, end_at, "position")
	if after.size() < 2:
		_failures.append("fewer than 2 position lines after retry")
	elif _span(events, after) < 2.0:
		_failures.append("move after retry spanned %.2f m" % _span(events, after))
	print("death %s" % JSON.stringify(events[death_at]))


func _check_walk(events: Array[Dictionary], pos_indexes: Array[int], death_at: int) -> void:
	# Home is where the player stood before dying, not the first sample after the flash.
	var home := _xz(events[pos_indexes[pos_indexes.size() - 1]])
	var far_n := 0
	var far_d := 0.0
	for n in pos_indexes.size():
		var d := home.distance_to(_xz(events[pos_indexes[n]]))
		if d > far_d:
			far_d = d
			far_n = n
	if far_d < BACK_MIN_M:
		_failures.append("walk peaked at %.2f m" % far_d)
		return
	var started := false
	for n in range(0, far_n):
		if home.distance_to(_xz(events[pos_indexes[n]])) <= HOME_M:
			started = true
			break
	if not started:
		_failures.append("did not start near the stand")
		return
	var home_n := -1
	for n in range(far_n, pos_indexes.size()):
		if home.distance_to(_xz(events[pos_indexes[n]])) <= HOME_M:
			home_n = n
			break
	if home_n < 0:
		_failures.append("did not return near the start")
		return
	for n in range(home_n, pos_indexes.size()):
		if home.distance_to(_xz(events[pos_indexes[n]])) > HOME_M:
			_failures.append("moved during the stand")
			return
	var home_at: int = pos_indexes[home_n]
	var stood := float(events[death_at].get("t", 0.0)) - float(events[home_at].get("t", 0.0))
	if stood < IDLE_MIN_S:
		_failures.append("stand was %.2f s" % stood)
	for i in range(home_at, death_at):
		if String(events[i].get("event", "")) == "input":
			_failures.append("input during the stand")
			return
	_check_look(events, home_at, death_at)


func _check_look(events: Array[Dictionary], home_at: int, death_at: int) -> void:
	var t0 := float(events[home_at].get("t", 0.0))
	var t1 := float(events[death_at].get("t", 0.0))
	var early := _look_samples(events, home_at, death_at, t0, t0 + LOOK_S)
	var late := _look_samples(events, home_at, death_at, t1 - LOOK_S, t1)
	if early.size() < 10:
		_failures.append("first 20s has %d position lines" % early.size())
		return
	if late.size() < 10:
		_failures.append("last 20s has %d position lines" % late.size())
		return
	var early_yaw := _angle_span(early, "yaw")
	var early_pitch := _angle_span(early, "pitch")
	var late_yaw := _angle_span(late, "yaw")
	var late_pitch := _angle_span(late, "pitch")
	print("look first20 yaw_span=%.2f pitch_span=%.2f last20 yaw_span=%.2f pitch_span=%.2f" % [early_yaw, early_pitch, late_yaw, late_pitch])
	if early_yaw < 15.0 or early_pitch < 15.0:
		_failures.append("look barely moved in the first 20s")
	if late_yaw > 0.75 or late_pitch > 0.75:
		_failures.append("look still moving in the last 20s")


func _look_samples(events: Array[Dictionary], from_i: int, to_i: int, start: float, end: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for i in range(maxi(from_i, 0), mini(to_i, events.size())):
		var line := events[i]
		if String(line.get("event", "")) != "position":
			continue
		var t := float(line.get("t", 0.0))
		if t < start or t >= end:
			continue
		if not _is_angle(line.get("yaw")) or not _is_angle(line.get("pitch")):
			_failures.append("position missing yaw or pitch at t=%s" % t)
			continue
		found.append(line)
	return found


func _is_angle(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


func _angle_span(lines: Array[Dictionary], key: String) -> float:
	var lo := float(lines[0].get(key, 0.0))
	var hi := lo
	for line in lines:
		var value := float(line.get(key, 0.0))
		lo = minf(lo, value)
		hi = maxf(hi, value)
	return hi - lo


func _span(events: Array[Dictionary], indexes: Array[int]) -> float:
	var origin := _xz(events[indexes[0]])
	var far := 0.0
	for index in indexes:
		far = maxf(far, origin.distance_to(_xz(events[index])))
	return far


func _xz(line: Dictionary) -> Vector2:
	return Vector2(float(line.get("x", 0.0)), float(line.get("z", 0.0)))


func _indexes_between(events: Array[Dictionary], from_i: int, to_i: int, event_name: String) -> Array[int]:
	var found: Array[int] = []
	for i in range(maxi(from_i, 0), mini(to_i, events.size())):
		if String(events[i].get("event", "")) == event_name:
			found.append(i)
	return found


func _find_scene(events: Array[Dictionary], start: int) -> int:
	if start < 0:
		return -1
	for i in range(start, events.size()):
		if String(events[i].get("event", "")) == "scene" and String(events[i].get("scene", "")) == LEVEL:
			return i
	return -1


func _find_event(events: Array[Dictionary], start: int, event_name: String, reason: String) -> int:
	if start < 0:
		return -1
	for i in range(start, events.size()):
		var line := events[i]
		if String(line.get("event", "")) != event_name:
			continue
		if reason != "" and String(line.get("reason", "")) != reason:
			continue
		return i
	return -1


func _level_load_count(events: Array[Dictionary]) -> int:
	var count := 0
	for line in events:
		if String(line.get("event", "")) == "sync_flash" and String(line.get("reason", "")) == "level_load":
			count += 1
	return count


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
