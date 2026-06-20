extends StateProcessor

var attention_spot: Sprite3D
@export var investigate_bark: AudioStream

func set_attention_point(new_spot: Sprite3D):
	if attention_spot:
		attention_spot.free()
	attention_spot = new_spot
	if npc.current_behaviour == CogitoNPC.BehaviourState.Investigating:
		npc.nav_agent.target_position = attention_spot.global_position


func _on_investigate_state_entered() -> void:
	state_chart.send_event("ubody_raise_weapon")
	if attention_spot:
		npc.nav_agent.target_position = attention_spot.global_position
	npc.current_behaviour = CogitoNPC.BehaviourState.Investigating
	bark(investigate_bark)


func _on_investigate_state_physics_processing(delta: float) -> void:
	npc.move_npc_to_next_position(delta)
