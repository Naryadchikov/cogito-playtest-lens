extends Node3D

var inventory_data: CogitoInventory


func _init() -> void:
	add_to_group("Player")
	inventory_data = CogitoInventory.new()
	inventory_data.inventory_size = Vector2i(4, 1)
	inventory_data.grid = false
	inventory_data.inventory_slots.resize(4)
