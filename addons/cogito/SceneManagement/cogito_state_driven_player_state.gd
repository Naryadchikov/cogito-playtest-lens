class_name CogitStateDrivenPlayerState
extends CogitoPlayerState

@export var jump_target_speed: float

@export var swimming_head_shapecast_position: Vector3
@export var is_under_water_effect_visible: bool

@export var state_chart: SerializedStateChart = null


func save_additional_states(player):
	jump_target_speed = player.jump_target_speed
	
	swimming_head_shapecast_position = player.swimming_head_shapecast.global_position
	is_under_water_effect_visible = player.under_water_effect.visible
	
	_save_state_chart(player)


func _save_state_chart(player):
	state_chart = StateChartSerializer.serialize(player.state_chart)


func load_additional_states(player):
	if player.try_crouch:
		player.current_body_posture_state = CogitoPlayerStateDriven.BodyPostureState.Crouching
	else:
		player.current_body_posture_state = CogitoPlayerStateDriven.BodyPostureState.Standing
	
	_load_state_chart(player)
	
	player.jump_target_speed = jump_target_speed
	
	player.swimming_head_shapecast.global_position = swimming_head_shapecast_position
	player.under_water_effect.visible = is_under_water_effect_visible
	
	player.is_movement_paused = true
	player._on_resume_movement()


func _load_state_chart(player):
	StateChartSerializer.deserialize(state_chart, player.state_chart)
