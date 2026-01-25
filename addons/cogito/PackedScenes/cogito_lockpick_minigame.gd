class_name CogitoLockpickGame extends Node3D

signal unlocked # a signal emmited when the lock has been unlocked
signal cancelled # Emitted when the player cancels out by pressing 'menu'
signal lockpick_broke # Emitted when a lockpick breaks.

@export var max_range: float = 10.0 # the range in which the sweet spot can go from
@export var lockpick_move_sensitivity: float = 0.003 # The sensitivity in which the lockpick moves

@export var lockpick_pivot: Node3D
@export var keyhole_pivot: Node3D

@export var lockpick_health_max : float = 5
@export_range(1,10,0.5,"Default = 2.0") var lockpick_damage_per_second_min = 2.0
@export_range(1,10,0.5,"Default = 8.0") var lockpick_damage_per_second_max = 8.0

var lockpick_health : float:
	set(value):
		lockpick_health = maxf(value,0)


@export_subgroup("Audio")
@export var unlock_sound : AudioStream
@export var jiggle_sound : AudioStream
@export var lockpick_break_sound : AudioStream

# Some state bools
var is_unlocked: bool = false
var is_turning_keyhole: bool = false
var is_changing_lockpicks : bool = false
var is_jiggling: bool = false

var lockpick_spot: float = 0.0 # the lockpick postion tanges from MIN_RANGE to max_range
var keyhole_rotation_speed: float = 4.0 # the speed in which the keyhole rotates when pressing D
var sweet_spot: float = 0.0  # The distance to the sweet spot.

@onready var animation_player: AnimationPlayer = $AnimationPlayer


## NOTE: Use this variable to scale difficulity, the closer the number to 0 the harder the lockpicking is
@export var sweet_spot_range: float = 1.0 

const MIN_RANGE: float = 0.0 # i'm not sure why would you change this
const LOCKPICK_SUCCSESS_ZONE: float = -90.0 # the degree in which, the keyhole rotate to considers it has been unlocked


func _ready() -> void:
	lockpick_spot = max_range / 2 	# make the lockpick at the center
	lockpick_health = lockpick_health_max
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # capture the mosue (NOTE: you can remove this)
	place_sweetspot()
	
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# if the keyhole isn't turning and we haven't unlocked it yet
		if not is_turning_keyhole and not is_changing_lockpicks and not is_unlocked:
			# rotate the lockpick along the z axis AND making sure it dosen't go beyong -90 and 90 degrees
			lockpick_pivot.rotate_z(-event.relative.x * lockpick_move_sensitivity)
			lockpick_pivot.rotation.z = clamp(lockpick_pivot.rotation.z, deg_to_rad(-90), deg_to_rad(90))
	
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		cancelled.emit()


func _physics_process(delta: float) -> void:
	# we remap the lockpick spot from -90 and 90 to a value that goes from MIN_RANGE to max_range, then we snap it for easier controls
	lockpick_spot = snappedf(remap(rad_to_deg(lockpick_pivot.rotation.z), -90, 90, MIN_RANGE, max_range), 0.1)
	
	if not is_unlocked:
		_handle_keyhole(delta)


# generating a random number via godot's RandomNumberGenerator class, call this function when you want to reinitialise the sweet spot
func place_sweetspot() -> void:
	var rand_range: RandomNumberGenerator = RandomNumberGenerator.new()
	# snapping the value so the lock for better solvability
	sweet_spot = snappedf(rand_range.randf_range(MIN_RANGE, max_range), 0.1)



func _handle_keyhole(delta: float) -> void:
	if is_jiggling:
		return
	
	# if we're pressing the D button on the keyboard (turning the keyhole) then rotate
	if Input.is_action_pressed("right"):
		keyhole_pivot.rotate_z(-keyhole_rotation_speed * delta)
		is_turning_keyhole = true
		
	else:
		# otherwise go back to normal rotation
		keyhole_pivot.rotation.z = lerp_angle(keyhole_pivot.rotation.z, 0, 4 * delta)
		is_turning_keyhole = false
	
	# gradually block the keyhole rotation depenting on the distance to the sweetspot
	var distance: float = abs(lockpick_spot - sweet_spot) # the distance to the sweet spot acording to the lockpick position
	# we remap that distance to be in the range from 0 to the succes degree, we also snap it for convience
	var grad_lock: float = snappedf(remap(distance, sweet_spot_range, 0, 0, LOCKPICK_SUCCSESS_ZONE), 0.1)
	# clamping the rotation so we don't go beyond LOCKPICK_SUCCSESS_ZONE
	keyhole_pivot.rotation_degrees.z = clamp(keyhole_pivot.rotation_degrees.z, grad_lock, 0)
	
	# Unlock the lock when the keyhole has turned 90 degrees
	if rad_to_deg(keyhole_pivot.rotation.z) <= LOCKPICK_SUCCSESS_ZONE:
		unlock_lock()
	elif is_turning_keyhole :
		if distance <= 1: # Within range where keyhole turns
			if abs(grad_lock - rad_to_deg(keyhole_pivot.rotation.z) ) <= 1: # is within hitting the grad_lock range:
				jiggle_lock(delta, distance)
		else:
			jiggle_lock(delta, distance)


func jiggle_lock(delta: float, distance_to_unlock: float) -> void:
	if is_changing_lockpicks:
		return
	
	is_jiggling = true
	Audio.play_sound(jiggle_sound)

	# Add jiggle animation
	var  lockpick_damage_range : float = lockpick_damage_per_second_max - lockpick_damage_per_second_min
	var lockpick_damage : float = remap(distance_to_unlock, 0, 10, lockpick_damage_per_second_min, lockpick_damage_per_second_max)
	#var lockpick_damage : float = ( distance_to_unlock * lockpick_damage_range) + lockpick_damage_per_second_min
	print("Lockpick Minigame: jiggling the lock. distance_to_unlock=", distance_to_unlock, ". lockpick_damage_range=", lockpick_damage_range, ". lockpick_damage=", lockpick_damage)
	lockpick_health = lockpick_health - ( lockpick_damage * delta )
	
	if lockpick_health == 0:
		GrabNewLockpick()
	else:
		animation_player.play("jiggle_lock")
		await animation_player.animation_finished
	
	is_jiggling = false


func unlock_lock() -> void:
	print("Lockpick Minigame: Unlocked!")
	Audio.play_sound(unlock_sound)
	unlocked.emit()
	is_unlocked = true


func GrabNewLockpick() -> void:
	is_changing_lockpicks = true
	print("!! Lockpick Broke !!")
	
#	Play Lockpick break sound
	Audio.play_sound(unlock_sound)
	
	lockpick_broke.emit()
	
	animation_player.play("grab_new_lockpick")
	await animation_player.animation_finished

	lockpick_health = lockpick_health_max
	is_changing_lockpicks = false
