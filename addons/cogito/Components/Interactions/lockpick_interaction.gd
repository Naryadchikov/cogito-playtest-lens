extends InteractionComponent
class_name LockpickInteraction

@onready var parent_node = get_parent() #Grabbing reference to parent

@export var lockpick_minigame : PackedScene
@export var required_lockpick_item : InventoryItemPD
## Hint message if player has no lockpicks. Leave blank to not send one.
@export var lockpick_item_hint : String

@export var door_to_unlock : CogitoDoor

@onready var lockpick_ui: Control = $LockpickUI

var spawned_lockpick_game
var player_interaction_component : PlayerInteractionComponent

@onready var label_amount_lockpicks: Label = $LockpickUI/MarginContainer/PanelContainer/MarginContainer/HBoxContainer/AmountLockpicks


func _ready() -> void:	
	# Precache lockpick minigame:
	spawned_lockpick_game = lockpick_minigame.instantiate()
	lockpick_ui.hide()
	
	#await get_parent().ready
	
	if door_to_unlock:
		door_to_unlock.lock_state_changed.connect(on_door_lock_state_change)


func interact(_player_interaction_component: PlayerInteractionComponent) -> void:
	# Check if player has lockpick item:
	if not check_for_item(_player_interaction_component, required_lockpick_item):
		if lockpick_item_hint:
			_player_interaction_component.send_hint(null, lockpick_item_hint)
		return
	
	player_interaction_component = _player_interaction_component
	player_interaction_component.get_parent().toggled_interface.emit(true)
	
	if !spawned_lockpick_game:
		spawned_lockpick_game = lockpick_minigame.instantiate()
	player_interaction_component.player.head.add_child(spawned_lockpick_game)
	
	spawned_lockpick_game.unlocked.connect(on_lock_picked)
	spawned_lockpick_game.cancelled.connect(on_cancel)
	spawned_lockpick_game.lockpick_broke.connect(discard_lockpick)
	
	# Set the UI to show how many lockpicks the player is carrying:
	label_amount_lockpicks.text = str(get_lockpick_amount_in_inventory(required_lockpick_item.name))
	
	lockpick_ui.show()


func on_lock_picked() -> void:
	print("Lock was picked!")
	lockpick_ui.hide()
	player_interaction_component.get_parent().toggled_interface.emit(false)
	
	if door_to_unlock:
		door_to_unlock.unlock_door()

	spawned_lockpick_game.queue_free()

func on_cancel() -> void:
	print("Cancelled!")
	player_interaction_component.get_parent().toggled_interface.emit(false)
	spawned_lockpick_game.queue_free()
	lockpick_ui.hide()


func check_for_item(interactor, item) -> bool:
	var inventory = interactor.get_parent().inventory_data
	for slot_data in inventory.inventory_slots:
		if slot_data != null and slot_data.inventory_item == item:
			return true
	return false


func discard_lockpick() -> void:
	#	Lockpick Discard Logic, used when a lockpick breaks to remove one from inventory.
	var inventory = player_interaction_component.get_parent().inventory_data
	for slot_data in inventory.inventory_slots:
		if slot_data != null and slot_data.inventory_item == required_lockpick_item:
			player_interaction_component.send_hint(null, tr(required_lockpick_item.name) + " " + tr("HINT_SWITCH_item_used") )
			inventory.remove_item_from_stack(slot_data)
	
	var lockpicks_left : int = get_lockpick_amount_in_inventory(required_lockpick_item.name)
	
	# Refresh the lockpick amount display.
	label_amount_lockpicks.text = str(lockpicks_left)
	
	# Quit the minigame if the player runs out of lockpicks.
	if lockpicks_left <= 0:
		spawned_lockpick_game.cancelled.emit()


func get_lockpick_amount_in_inventory(item_name_to_check_for: String) -> int:
	var item_count : int = 0
	if player_interaction_component.get_parent().inventory_data != null:
		var inventory_to_check = player_interaction_component.get_parent().inventory_data
		for slot in inventory_to_check.inventory_slots:
			if slot != null and slot.inventory_item.name == item_name_to_check_for:
				item_count += slot.quantity
				
	return item_count


func on_door_lock_state_change(is_locked: bool) -> void:
	print("LockpickInteraction: linked door is_locked=", is_locked)
	if is_locked:
		self.is_disabled = false
	else:
		self.is_disabled = true
