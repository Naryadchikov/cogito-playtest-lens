extends StateProcessor

## How long should the npc stay unconscious for
@export var stun_duration: float = 3.0
var stun_timer : Timer
var impacted_ground: bool = false

func _on_stunned_state_entered() -> void:
	impacted_ground = false
	stun_timer = Timer.new()
	stun_timer.wait_time = stun_duration
	stun_timer.one_shot = true
	stun_timer.autostart = true
	stun_timer.timeout.connect(recover)
	
func _on_stunned_state_physics_processing(delta: float) -> void:
	if npc.is_on_floor() and !impacted_ground:
		impact_ground()
	else:
		npc.move_and_slide()

func impact_ground():
	impacted_ground = true
	npc.velocity = Vector3.ZERO
	add_child(stun_timer)

func recover():
	state_chart.send_event("body_recover")
	await get_tree().create_timer(3).timeout
	state_chart.send_event(npc.get_previous_event())
