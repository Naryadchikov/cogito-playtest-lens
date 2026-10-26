extends Node

const QUEST_PATH := "res://addons/cogito/QuestSystem/Quests/QuestA.tres"
const ITEM_NAME := "Key"

var _keypad_heard := false
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not has_node("/root/PlaytestLensLogger") or not has_node("/root/PlaytestLensCogito"):
		print("FAIL: autoload missing")
		get_tree().quit(1)
		return
	_fire_door()
	await _fire_keypad()
	_fire_pickup()
	_fire_quests()
	await get_tree().process_frame
	var logger: Node = get_node("/root/PlaytestLensLogger")
	logger.end_session()
	_check(String(logger.get("log_path")))
	if _failures.is_empty():
		print("PASS path=%s" % logger.get("log_path"))
		get_tree().quit(0)
	else:
		for item in _failures:
			print("FAIL: ", item)
		get_tree().quit(1)


func _fire_door() -> void:
	var door := get_node_or_null("Door") as CogitoDoor
	if door == null:
		_failures.append("door prefab missing")
		return
	var body := Node3D.new()
	door.open_door(body)
	door.close_door(body)
	door.unlock_door()
	door.lock_door()


func _fire_keypad() -> void:
	var keypad := get_node_or_null("Keypad") as CogitoKeypad
	if keypad == null:
		_failures.append("keypad prefab missing")
		return
	_keypad_heard = false
	keypad.correct_code_entered.connect(_on_keypad_heard, CONNECT_ONE_SHOT)
	# unlock_keypad closes the UI through the player. is_closed skips that and still emits.
	keypad.is_closed = true
	keypad.unlock_keypad()
	var start := Time.get_ticks_usec()
	while not _keypad_heard and Time.get_ticks_usec() - start < 3_000_000:
		await get_tree().process_frame
	if not _keypad_heard:
		_failures.append("keypad signal did not fire")


func _on_keypad_heard() -> void:
	_keypad_heard = true


func _fire_pickup() -> void:
	var pickup := get_node_or_null("Pickup")
	if pickup == null:
		_failures.append("pickup prefab missing")
		return
	var component := pickup.get_node_or_null("PickupComponent") as PickupComponent
	if component == null or component.slot_data == null:
		_failures.append("pickup has no slot")
		return
	var player := get_node_or_null("Player")
	if player == null:
		_failures.append("player missing")
		return
	var inventory := player.get("inventory_data") as CogitoInventory
	if inventory == null:
		_failures.append("player inventory missing")
		return
	if not inventory.pick_up_slot_data(component.slot_data):
		_failures.append("pick_up_slot_data returned false")


func _fire_quests() -> void:
	var quest := load(QUEST_PATH) as CogitoQuest
	if quest == null:
		_failures.append("quest resource missing")
		return
	var manager := get_node_or_null("/root/CogitoQuestManager")
	if manager == null:
		_failures.append("CogitoQuestManager missing")
		return
	manager.quest_activated.emit(quest)
	manager.quest_updated.emit(quest)
	manager.quest_completed.emit(quest)
	manager.quest_failed.emit(quest)


func _check(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		_failures.append("log file missing")
		return
	var text := FileAccess.get_file_as_string(path)
	var rows := text.split("\n", false)
	var events: Array[Dictionary] = []
	for row in rows:
		if row.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(row)
		if typeof(parsed) != TYPE_DICTIONARY:
			_failures.append("line is not JSON: %s" % row)
			return
		events.append(parsed)
	_expect_door(events, true)
	_expect_door(events, false)
	_expect_lock(events, false)
	_expect_lock(events, true)
	_expect_keypad(events)
	_expect_pickup(events)
	for step in ["activated", "updated", "completed", "failed"]:
		_expect_quest(events, step)
	for line in events:
		var event_name := String(line.get("event", ""))
		if event_name in ["pickup", "door", "lock", "keypad", "quest"]:
			print(JSON.stringify(line))


func _expect_door(events: Array[Dictionary], is_open: bool) -> void:
	for line in events:
		if String(line.get("event", "")) != "door":
			continue
		if bool(line.get("open", null)) != is_open:
			continue
		if _is_place(String(line.get("path", "")), "Door"):
			return
	_failures.append("missing door open=%s" % is_open)


func _expect_lock(events: Array[Dictionary], is_locked: bool) -> void:
	for line in events:
		if String(line.get("event", "")) != "lock":
			continue
		if bool(line.get("locked", null)) != is_locked:
			continue
		if _is_place(String(line.get("path", "")), "Door"):
			return
	_failures.append("missing lock locked=%s" % is_locked)


func _expect_keypad(events: Array[Dictionary]) -> void:
	for line in events:
		if String(line.get("event", "")) == "keypad" and _is_place(String(line.get("path", "")), "Keypad"):
			return
	_failures.append("missing keypad")


func _expect_pickup(events: Array[Dictionary]) -> void:
	for line in events:
		if String(line.get("event", "")) == "pickup" and String(line.get("item", "")) == ITEM_NAME:
			return
	_failures.append("missing pickup %s" % ITEM_NAME)


func _expect_quest(events: Array[Dictionary], step: String) -> void:
	for line in events:
		if String(line.get("event", "")) != "quest":
			continue
		if String(line.get("step", "")) == step and String(line.get("quest", "")) == "quest_a":
			return
	_failures.append("missing quest %s" % step)


func _is_place(path: String, node_name: String) -> bool:
	return path == node_name or path.ends_with("/" + node_name)
