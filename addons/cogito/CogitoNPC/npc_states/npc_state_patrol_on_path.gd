extends StateProcessor

@export var patrol_point_wait_time : float = 3.0
@export var patrol_point_threshold : float = 0.4

enum TravelStatus{ SUCCESS, FAILURE, RUNNING, WAITING = 3 }
var current_travel_status : TravelStatus = TravelStatus.WAITING

var patrol_wait_timer : Timer
var patrol_point_index : int = 0


func _enter_tree() -> void:
	patrol_wait_timer = Timer.new()
	patrol_wait_timer.wait_time = patrol_point_wait_time
	patrol_wait_timer.one_shot = true
	patrol_wait_timer.timeout.connect(resume_patrolling)
	add_child(patrol_wait_timer)


func set_next_patrol_point_destination():
	if npc.patrol_path:
		var new_destination = npc.patrol_path.patrol_points[patrol_point_index].global_position
		return new_destination
	else:
		return null


func _running(delta: float):
	if not npc.nav_agent.is_target_reachable():
		CogitoGlobals.debug_log(true,"NPC State Patrol on Path", "Patrol point at index " + str(patrol_point_index) + " is not reach able. Going to next one.")
		iterate_patrol_point_index() #Switches to the next patrol point if current one is not reachable.
		npc.nav_agent.target_position = set_next_patrol_point_destination()
	
	if npc.nav_agent.is_navigation_finished():
		wait_at_patrol_point(delta)
		return
	
	npc.move_npc_to_next_position(delta)


func wait_at_patrol_point(_delta: float):
	patrol_wait_timer.start()
	current_travel_status = TravelStatus.WAITING


func resume_patrolling() -> void:
	if npc.patrol_path:
		iterate_patrol_point_index()
		npc.nav_agent.target_position = set_next_patrol_point_destination()
		current_travel_status = TravelStatus.RUNNING


func iterate_patrol_point_index():
	# Checking to see if we've reached the end of the patrol point list.
	if patrol_point_index == npc.patrol_path.patrol_points.size() - 1:
		# If yes, we're starting over:
		patrol_point_index = 0
	else:
		# If no, we're going to the next point:
		patrol_point_index += 1


func _on_patrolling_state_entered() -> void:
	state_chart.send_event("ubody_neutral")
	npc.current_behaviour = CogitoNPC.BehaviourState.Patrolling
	CogitoGlobals.debug_log(true, "npc_state_patrol_on_path.gd", name + " state entered")
	if npc.patrol_path:
		npc.nav_agent.target_position = set_next_patrol_point_destination()
		current_travel_status = TravelStatus.RUNNING
	else:
		CogitoGlobals.debug_log(true, "npc_state_patrol_on_path.gd", "No patrol path assigned to NPC")


func _on_patrolling_state_exited() -> void:
	npc.previous_behaviour = CogitoNPC.BehaviourState.Patrolling


func _on_patrolling_state_physics_processing(delta: float) -> void:
	for i in npc.get_slide_collision_count():
		var collision = npc.get_slide_collision(i)
		if collision is CogitoPlayer and npc.response_to_player == "Hostile":
			npc.attention_target = collision
			state_chart.send_event("chase")
	
	if npc.patrol_path == null:
		return
	
	match current_travel_status:
		TravelStatus.WAITING:
			# Lerping down the velocity
			npc.velocity.x = move_toward(npc.velocity.x, 0, delta * npc.move_speed)
			npc.velocity.z = move_toward(npc.velocity.z, 0, delta * npc.move_speed)
			npc.move_and_slide()
			return
		TravelStatus.RUNNING:
			_running(delta)
		TravelStatus.SUCCESS:
			# This would end patrolling
			pass
		TravelStatus.FAILURE:
			iterate_patrol_point_index() #Switches to the next patrol point if current one is not reachable.
			if npc.patrol_path:
				npc.nav_agent.target_position = set_next_patrol_point_destination()
				current_travel_status = TravelStatus.RUNNING


	var look_ahead := Vector3(npc.global_position.x + npc.velocity.x, npc.global_position.y, npc.global_position.z + npc.velocity.z)
