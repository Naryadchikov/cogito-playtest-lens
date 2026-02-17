extends Node3D
class_name CogitoRagdoll

## If you want ragdolls to be saved / loaded, set this to on.
@export var make_persistent : bool = true
@export var save_pose_delay : float = 4.0
@onready var physical_bone_simulator_3d: PhysicalBoneSimulator3D = $Rig/SkeletonRagdoll/PhysicalBoneSimulator3D

var skeleton_bone_root_position : Vector3 = Vector3(0,0,0)
var skeleton_bone_root_rotation : Vector3 = Vector3(0,0,0)

func _ready() -> void:
	if make_persistent:
		self.add_to_group("Persist") #Adding object to group for persistence
	
	await get_tree().create_timer(0.05, false).timeout
	physical_bone_simulator_3d.physical_bones_start_simulation()


func save_bone_root_position() -> void:
	var skeleton = physical_bone_simulator_3d.get_skeleton()
	skeleton_bone_root_position = physical_bone_simulator_3d.get_child(0).global_position
	skeleton_bone_root_rotation = physical_bone_simulator_3d.get_child(0).global_rotation
	print("CogitoRagdoll: saved skeleton_bone_root_position (", skeleton.get_bone_name(0) , ") at " , skeleton_bone_root_position)
	print("CogitoRagdoll: saved skeleton_bone_root_rotation (", skeleton.get_bone_name(0) , ") at " , skeleton_bone_root_rotation)

# Method to set object state when a scene state file is loaded.
func set_state():
	var skeleton = physical_bone_simulator_3d.get_skeleton()
	skeleton.set_bone_pose_position(0, skeleton_bone_root_position)
	#skeleton.set_bone_pose_rotation(0, skeleton_bone_root_rotation)
	print("CogitoRagdoll: loaded skeleton_bone_root_position at " , skeleton_bone_root_position)


func save():
	var node_data = {
		"filename" : get_scene_file_path(),
		"parent" : get_parent().get_path(),
		"pos_x" : position.x,
		"pos_y" : position.y,
		"pos_z" : position.z,
		"rot_x" : rotation.x,
		"rot_y" : rotation.y,
		"rot_z" : rotation.z,
		"skeleton_bone_root_position" : skeleton_bone_root_position,
		"skeleton_bone_root_rotation" : skeleton_bone_root_rotation,
	}
	return node_data
