extends Area3D
class_name PlaytestLensTelemetryVolume

## Designer zone for the session log. Place it over a room, set zone and puzzle
## (puzzle may be empty), and size the CollisionShape3D. Nothing else.
##
## The volume only reports overlaps. It does not move, block, or read input.
## At runtime it sits on no physics layer, so nothing collides with it and the
## player's movement stays the same. Monitoring stays on. It is not monitorable,
## not mouse-pickable, and it does not override gravity, damp, or audio.
## The mask includes every layer so the player body is seen on its own layer.
## The logger records only that player.

const GROUP_NAME := "playtest_lens_telemetry_volume"

@export var zone: String = ""
@export var puzzle: String = ""


func _enter_tree() -> void:
	_keep_passive()
	if not is_in_group(GROUP_NAME):
		add_to_group(GROUP_NAME)


func _keep_passive() -> void:
	monitorable = false
	input_ray_pickable = false
	audio_bus_override = false
	reverb_bus_enabled = false
	gravity_space_override = SPACE_OVERRIDE_DISABLED
	linear_damp_space_override = SPACE_OVERRIDE_DISABLED
	angular_damp_space_override = SPACE_OVERRIDE_DISABLED
	collision_layer = 0
	for layer in range(1, 33):
		set_collision_mask_value(layer, true)
	# Toggle so the physics server picks up the mask before the first overlap test.
	monitoring = false
	monitoring = true
