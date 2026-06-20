extends StateProcessor

enum ChaseStatus{ CAUGHT, LOST, CHASING, WAITING = 3 }
var current_chase_status : ChaseStatus
var chase_target : Node3D = null

@export var target_action_distance : float = 1.0
@export var action_when_caught : String = "attack"
## If the NPC navigation agent can't reach the chase target for this amount of time (in sec), they'll return to their previous state.
@export var giveup_chase_time : float = 5.0
## If the NPC can no longer see the player for this duration (in sec), they'll start a search
@export var wait_after_broken_los_time : float = 3.0
@export var face_target_while_waiting : bool = true
## Reference to the searching state processor so the variables can be set (software eng gods please dont strike me down)
@export var searching_state: StateProcessor
@export var chase_start_bark: AudioStream

var los_broken_timer : Timer
var chase_wait_timer : Timer

func _enter_tree() -> void:
	chase_wait_timer = Timer.new()
	chase_wait_timer.wait_time = giveup_chase_time
	chase_wait_timer.one_shot = true
	chase_wait_timer.timeout.connect(stop_chasing)
	add_child(chase_wait_timer)
	
	los_broken_timer = Timer.new()
	los_broken_timer.wait_time = wait_after_broken_los_time
	los_broken_timer.one_shot = true
	los_broken_timer.timeout.connect(start_searching)
	add_child(los_broken_timer)


func _running(delta: float):
	npc.nav_agent.target_position = chase_target.global_position
	var distance_to_target = npc.global_position.distance_to(chase_target.global_position)

	if distance_to_target <= target_action_distance:
		current_chase_status =  ChaseStatus.CAUGHT
		
	if not npc.nav_agent.is_target_reachable():
		start_waiting()
		
	npc.move_npc_to_next_position(delta)

## Abort the chase because the NPC died
func npc_has_died() -> void:
	current_chase_status = ChaseStatus.LOST


## Call this to abort the chase. Switches status to lost target and goes to previous state.
func stop_chasing() -> void:
	#Switch back to walk_speed
	npc.move_speed = npc.walk_speed
	current_chase_status = ChaseStatus.LOST


func start_searching() -> void:
	searching_state.player = chase_target
	searching_state.last_known_player_point = chase_target.global_position
	state_chart.send_event("body_walk")
	state_chart.send_event("search")


## Fire a raycast at the player to see if they're visible to the npc
func check_los_to_player() -> bool:
	# Get the space state of the world, construct a ray to fire from the chaser to the target
	var space_state = npc.get_world_3d().direct_space_state
	# Collision layers 1 (Environment) and 3 (Player) = 4+1 = 5
	var query = PhysicsRayQueryParameters3D.create(npc.global_position, chase_target.global_position, 5)
	query.exclude = [npc.get_rid()]
	var result = space_state.intersect_ray(query)
	# If there is a collision, check that the ray is hitting the player
	if result:
		return result["collider"] is CogitoPlayer
	return false


## Gets called when the line of sight has been broken for long enough
func start_waiting():
	chase_wait_timer.start()
	current_chase_status = ChaseStatus.WAITING


func _on_chasing_state_entered() -> void:
	super.enter_state()
	chase_target = npc.attention_target
	if !chase_target or npc.response_to_player == "Neutral":
		CogitoGlobals.debug_log(true,"npc_state_chase.gd", "Chase target was null. Returning to state patrol")
		state_chart.send_event("search")
		state_chart.send_event("body_walk")
	else:
		# Don't bark if re-entering state from the attacking state
		if barker and chase_start_bark and not npc.in_state([behaviours.Attacking]):
			barker.stream = chase_start_bark
			barker.play()
		state_chart.send_event("ubody_raise_weapon")
		state_chart.send_event("body_run")
		npc.move_speed = npc.sprint_speed
		current_chase_status = ChaseStatus.CHASING
		npc.head_turner.target_node = chase_target.get_path()


func _on_chasing_state_exited() -> void:
	super.exit_state()
	chase_target = null


func _on_chasing_state_physics_processing(delta: float) -> void:
	var can_see_player = check_los_to_player()
	if can_see_player:
		npc.head_turner.active = true
		los_broken_timer.stop()
	else:
		npc.head_turner.active = false
		if los_broken_timer.is_stopped() and chase_wait_timer.is_stopped():
			searching_state.broken_los_point = chase_target.global_position
			los_broken_timer.start()
		
	
	if (chase_target as CogitoPlayer).is_dead:
		stop_chasing()
		
	if npc.is_dead():
		npc_has_died()
	
	match current_chase_status:
		ChaseStatus.WAITING:
			# Lerping down the velocity
			npc.velocity.x = move_toward(npc.velocity.x, 0, delta * npc.move_speed)
			npc.velocity.z = move_toward(npc.velocity.z, 0, delta * npc.move_speed)
			npc.move_and_slide()

			if face_target_while_waiting:
				npc.face_direction(chase_target.global_position)
			
			# The chase
			npc.nav_agent.target_position = chase_target.global_position
			if npc.nav_agent.is_target_reachable() or can_see_player:
				chase_wait_timer.stop() 
				current_chase_status = ChaseStatus.CHASING
				
			return
			
		ChaseStatus.CHASING:
			_running(delta)
			
		ChaseStatus.CAUGHT:
			state_chart.send_event(action_when_caught)
			
		ChaseStatus.LOST: # Ends this state.
			start_searching()
			CogitoGlobals.debug_log(true,"npc_state_chase.gd", "ChaseStatus LOST, going to state = search")


	var look_ahead := Vector3(npc.global_position.x + npc.velocity.x, npc.global_position.y, npc.global_position.z + npc.velocity.z)
