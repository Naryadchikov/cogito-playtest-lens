extends StateProcessor

## Reference to the sight detection system so cone detection checks can be done after the first point is reached
@export var sight_detection: SightDetection

## How long does the player need to be in view of the NPC before restarting the chase? 
## NPC has heightened sight range at this point, the only way to not be seen in LOS is being in the dark
@export var reacquire_time: float = 0.5
## Does the NPC turn their head from side when moving?
@export var turn_head_when_pathing: bool = false
## How far does the NPC turn their head from side to side in degrees?
@export var head_target_rotation_angle: float = 15
## Resets both hearing and sight suspicion to zero when the search ends
@export var reset_suspicion_when_search_ends: bool = true
## How long before the NPC gives up searching once reaching the last known player position?
@export var end_search_after_reaching_last_known: float = 3.0
## What does the NPC bark when start searching?
@export var searching_bark: AudioStream
## What does the NPC bark when they end the search?
@export var end_search_bark: AudioStream

## The point where the player's line of sight was broken
var broken_los_point: Vector3
## The point where the player was when the line of sight timer finished
var last_known_player_position: Vector3
var player: CogitoPlayer

var los_point_reached: bool = false
var last_known_point_reached: bool = false

var reacquire_timer: Timer
var wait_timer: Timer
var head: Node3D

func _enter_tree() -> void:
	wait_timer = Timer.new()
	wait_timer.wait_time = end_search_after_reaching_last_known
	wait_timer.one_shot = true
	wait_timer.timeout.connect(end_search)
	add_child(wait_timer)
	
	reacquire_timer = Timer.new()
	reacquire_timer.wait_time = reacquire_time
	reacquire_timer.one_shot = true
	reacquire_timer.timeout.connect(func(): start_chasing())
	add_child(reacquire_timer)


func _on_searching_state_entered() -> void:
	wait_timer.wait_time = end_search_after_reaching_last_known
	reacquire_timer.wait_time = reacquire_time
	bark(searching_bark)
	state_chart.send_event("body_walk")
	npc.move_speed = npc.walk_speed
	los_point_reached = false
	last_known_point_reached = false
	head = npc.head_turner


func _on_searching_state_exited() -> void:
	pass # Replace with function body.


func _on_searching_state_physics_processing(delta: float) -> void:
	if npc.nav_agent.is_target_reached():
		if not los_point_reached:
			los_point_reached = true
			npc.nav_agent.target_position = last_known_player_position
		elif not last_known_point_reached:
			last_known_point_reached = true
			wait_timer.start()
	else:
		npc.move_npc_to_next_position(delta)
		if turn_head_when_pathing:
			turn_head(delta)	
	# Test LOS of the player, start an reacquire timer if they are seen
	if not los_point_reached:
		los_infinite_range_check()
	else:
		sight_detection_check()


## When headed for the first LOS point, the NPC has infinite range and will spot you immediately
func los_infinite_range_check():
	if fire_raycast_at_player():
		start_chasing()


## When headed for the second point, the NPC raycast is now limited to the sight detection cone and will start the reacquire timer if spotted
func sight_detection_check():
	if sight_detection.check_if_player_in_los():
		if reacquire_timer.is_stopped():
			reacquire_timer.start()
	else:
		reacquire_timer.stop()


func start_chasing():
	npc.attention_target = player
	state_chart.send_event("chase")


func end_search():
	bark(end_search_bark)
	if reset_suspicion_when_search_ends:
		if npc.hearing_detection:
			npc.hearing_detection.reset()
		if npc.sight_detection:
			npc.sight_detection.reset()
	state_chart.send_event("ubody_neutral")
	state_chart.send_event("patrol")


## Shoot a raycast at the player, if it hits check against their visibility attribute if applicable
func fire_raycast_at_player() -> bool:
	# Get the space state of the world, construct a ray to fire from the npc to the spotted target
	var space_state = npc.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(npc.head.global_position, player.global_position)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	# If the raycast hits a player, check that they are visible via attribute
	if not result:
		return false
	elif result["collider"] is CogitoPlayer and player.visibility_attribute:
		return player.visibility_attribute.value_current >= npc.sight_detection.minimum_visibility
	elif result["collider"] is CogitoPlayer:
		return true
	return false


func turn_head(delta: float) -> void:
	if head_target_rotation_angle > 0:
		head.rotate_y(deg_to_rad(0.1)*delta)
		if head.rotation_degrees.y >= head_target_rotation_angle:
			head_target_rotation_angle *= -1
	else:
		head.rotate_y(deg_to_rad(-0.1)*delta)
		if head.rotation_degrees.y <= head_target_rotation_angle:
			head_target_rotation_angle *= -1
		
