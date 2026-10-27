extends Node

## Autoload. Subscribes to COGITO signals and writes them through PlaytestLensLogger.
## Does not change gameplay, timing, input, or saves.

var _watched: Dictionary = {}
var _inventories: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	_connect_quests()
	_scan(tree.root)


func _on_node_added(node: Node) -> void:
	_watch(node)


func _scan(node: Node) -> void:
	_watch(node)
	for child in node.get_children():
		_scan(child)


func _watch(node: Node) -> void:
	var id := node.get_instance_id()
	if _watched.has(id):
		return
	var cared := false
	if node is CogitoDoor:
		cared = true
		node.door_state_changed.connect(_on_door_state.bind(node))
		node.lock_state_changed.connect(_on_lock_state.bind(node))
	elif node is CogitoKeypad:
		cared = true
		node.correct_code_entered.connect(_on_keypad.bind(node))
	if _is_player(node):
		cared = true
		_attach_inventory(node)
		if not node.is_node_ready():
			node.ready.connect(_on_player_ready.bind(node), CONNECT_ONE_SHOT)
	if _is_new_game_button(node):
		cared = true
		var button := node as BaseButton
		if not button.pressed.is_connected(_on_new_game_pressed):
			button.pressed.connect(_on_new_game_pressed)
	if not cared:
		return
	_watched[id] = true
	node.tree_exited.connect(_on_node_exit.bind(id), CONNECT_ONE_SHOT)


func _on_node_exit(id: int) -> void:
	_watched.erase(id)


func _on_player_ready(node: Node) -> void:
	_attach_inventory(node)


func _connect_quests() -> void:
	var manager := get_node_or_null("/root/CogitoQuestManager")
	if manager == null:
		return
	manager.quest_activated.connect(_on_quest.bind("activated"))
	manager.quest_updated.connect(_on_quest.bind("updated"))
	manager.quest_completed.connect(_on_quest.bind("completed"))
	manager.quest_failed.connect(_on_quest.bind("failed"))


func _is_new_game_button(node: Node) -> bool:
	if not node is BaseButton or node.name != "NewGame":
		return false
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is CogitoMainMenuController:
			return true
		ancestor = ancestor.get_parent()
	return false


func _on_new_game_pressed() -> void:
	var logger := get_node_or_null("/root/PlaytestLensLogger")
	if logger != null and logger.has_method("sync_flash"):
		logger.sync_flash("new_game")


func _is_player(node: Node) -> bool:
	if node.is_in_group("Player"):
		return true
	var path := String(ProjectSettings.get_setting("playtest_lens/player_path", ""))
	if path.is_empty():
		return false
	if path.begins_with("/"):
		return String(node.get_path()) == path
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return scene.get_node_or_null(path) == node


func _attach_inventory(node: Node) -> void:
	var inventory := node.get("inventory_data") as CogitoInventory
	if inventory == null:
		return
	var id := inventory.get_instance_id()
	if _inventories.has(id):
		return
	if not inventory.picked_up_new_inventory_item.is_connected(_on_pickup):
		inventory.picked_up_new_inventory_item.connect(_on_pickup)
	_inventories[id] = true


func _on_pickup(slot_data: InventorySlotPD) -> void:
	var item_name := ""
	if slot_data != null and slot_data.inventory_item != null:
		item_name = slot_data.inventory_item.name
	_log("pickup", {"item": item_name})


func _on_door_state(is_open: bool, door: Node) -> void:
	_log("door", {"path": _place(door), "open": is_open})


func _on_lock_state(is_locked: bool, door: Node) -> void:
	_log("lock", {"path": _place(door), "locked": is_locked})


func _on_keypad(keypad: Node) -> void:
	_log("keypad", {"path": _place(keypad)})


func _on_quest(quest: CogitoQuest, step: String) -> void:
	_log("quest", {"quest": _quest_label(quest), "step": step})


func _quest_label(quest: CogitoQuest) -> String:
	if quest == null:
		return ""
	var ident: Variant = quest.get("id")
	if ident != null and String(ident) != "":
		return String(ident)
	if quest.quest_name != "":
		return quest.quest_name
	return quest.quest_title


func _place(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	var scene := get_tree().current_scene
	if scene != null and (node == scene or scene.is_ancestor_of(node)):
		return String(scene.get_path_to(node))
	return String(node.get_path())


func _log(event_name: String, fields: Dictionary) -> void:
	var logger := get_node_or_null("/root/PlaytestLensLogger")
	if logger == null or not logger.has_method("log_event"):
		return
	logger.log_event(event_name, fields)
