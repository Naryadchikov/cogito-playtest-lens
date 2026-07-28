extends CogitoWieldable
class_name NpcWieldable

@export_group("NPC Wieldable Settings")
## Range of this NpcWieldable:
@export var npc_weapon_range : float = 15
## Determines delay between shots aka fire rate.
@export var firing_delay : float = 0.2
## Node for the laser origin
@onready var bullet_point: Node3D = %Bullet_Point
## Prefab of laser_ray
@export var ray_prefab : PackedScene
## How long laser rays linger in the air
@export var ray_lifespan : float = 5.0


@export_group("Collisions")
## Spawn hit decal on Collision hit
@export var decal_spawn : bool = true
## Hit decal texture, if blank will be set to default bullet decal texture
@export var decal_texture : Texture2D
## Scene that spawns when a bullet of the weapon collides with anything. Used for impact vfx.
@export var collision_scene : PackedScene

@export_group("Audio")
@export var sound_primary_use : AudioStream
@export var sound_secondary_use : AudioStream
@export var sound_reload : AudioStream

var npc_wielding: bool = false
var spawn_node : Node
var is_firing : bool = false
var firing_cooldown : float
var wielding_rid : RID


func _ready():
	super._ready()
	wieldable_mesh.hide()
	firing_cooldown = 0
	wielding_rid = CogitoSceneManager._current_player_node.get_rid()


func _physics_process(_delta: float) -> void:
	if firing_cooldown > 0:
		firing_cooldown -= _delta
		
	if is_firing and not npc_wielding:
		if firing_cooldown <= 0:
			if animation_player.is_playing():
				return
			# Gettting camera_collision pos from player interaction component:
			var _camera_collision = player_interaction_component.get_camera_collision()
			hit_scan_collision(_camera_collision) #Do the hitscan
		
			animation_player.play(anim_action_primary)
			
			if audio_stream_player_3d and sound_primary_use:
				audio_stream_player_3d.stream = sound_primary_use
				audio_stream_player_3d.play()
			
			firing_cooldown = firing_delay


func can_npc_attack(attacking_npc: CogitoNPC) -> bool:
	if item_reference.wieldable_range <= 0.0:
		return true
	# Check the weapon range is within player distance
	var ref_to_player: CogitoPlayer = attacking_npc.sight_detection.ref_to_player
	if not ref_to_player:
		return false
	if not firing_cooldown > 0 and attacking_npc.global_position.distance_to(ref_to_player.global_position) <= npc_weapon_range:
		return true
	else:
		return false


func npc_do_attack(attacking_npc: CogitoNPC):
	if not can_npc_attack(attacking_npc):
		return
	
	# Set the spawn node point if it hasn't already been set, on player it sets on equip
	if not spawn_node:
		spawn_node = get_tree().get_current_scene()
	# Check that the RID has been re-assigned
	if wielding_rid != attacking_npc.get_rid():
		wielding_rid = attacking_npc.get_rid()
	
	var player_sight_collision_point = attacking_npc.sight_detection.player_sight_collision_point
	if player_sight_collision_point != Vector3.ZERO:	
		hit_scan_collision(player_sight_collision_point)
		animation_player.play(anim_action_primary)
		if audio_stream_player_3d and sound_primary_use:
			audio_stream_player_3d.stream = sound_primary_use
			audio_stream_player_3d.play()
		firing_cooldown = firing_delay


# This gets called by player interaction component when the wieldable is equipped and primary action is pressed
func action_primary(_passed_item_reference : InventoryItemPD, _is_released: bool):
	if _is_released:
		is_firing = false
	else:
		is_firing = true


func action_secondary(is_released:bool):
	pass


func hit_scan_collision(collision_point:Vector3):
	var bullet_direction = (collision_point - bullet_point.get_global_transform().origin).normalized()
	var new_intersection = PhysicsRayQueryParameters3D.create(bullet_point.get_global_transform().origin, collision_point + bullet_direction * 2)
	new_intersection.exclude = [wielding_rid]
	
	var bullet_collision = get_world_3d().direct_space_state.intersect_ray(new_intersection)
	
	# Spawning a laser ray
	var instantiated_ray = ray_prefab.instantiate()
	instantiated_ray.draw_ray(bullet_point.get_global_transform().origin, collision_point)
	spawn_node.add_child(instantiated_ray)
	
	if bullet_collision:
		hit_scan_damage(bullet_collision.collider, bullet_direction, bullet_collision.position)
		
		if collision_scene !=null: # Spawning impact particle effects
			var spawned_impact_scene = collision_scene.instantiate()
			add_child(spawned_impact_scene)
			spawned_impact_scene.global_position = collision_point
		
		if decal_spawn == true:
			var bullet_collider = bullet_collision.collider
			var bullet_collision_position = bullet_collision.position
			var bullet_collision_normal = bullet_collision.normal
			var bullet_global_basis = bullet_point.get_global_transform().basis
			# Spawn bullet decal with collision parameters
			BulletDecalPool.spawn_bullet_decal(bullet_collision_position, bullet_collision_normal, bullet_collider, bullet_global_basis,decal_texture)


func hit_scan_damage(collider, bullet_direction, bullet_position):
	var damage = item_reference.wieldable_damage
	if collider.has_signal("damage_received"):
		collider.damage_received.emit(damage, self, bullet_direction,bullet_position)
	elif collider is CogitoPlayer:
		var player = collider as CogitoPlayer
		player.decrease_attribute("health", damage)
