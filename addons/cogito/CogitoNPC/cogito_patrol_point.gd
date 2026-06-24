## Represents a point on a patrol path that can link to other patrol points
@tool
extends Marker3D
class_name CogitoPatrolPoint

## Will the next patrol point selected be random or follow the sequence?
@export var random_point_selection: bool = false
## A list of possible patrol points that can be selected at random or sequentially if there is more than one
@export var next_patrol_points: Array[CogitoPatrolPoint] = []

## Which point will be selected next? Ignored if random_point_selection is true
var current_point_index: int = 0
## The previous patrol point being travelled from. Used to send the NPC back if next_patrol_points is empty
var previous_patrol_point: CogitoPatrolPoint

var traversed: bool = false
func clear_traversals_bools():
	traversed = false
	if next_patrol_points.is_empty():
		return
	for point in next_patrol_points:
		point.clear_traversals_bools()

func get_return_to_point() -> CogitoPatrolPoint:
	if get_parent() is CogitoPatrolPath:
		var parent = get_parent()
		if parent.starting_point_as_next_on_end:
			return parent.starting_patrol_point
	return previous_patrol_point

## Called once the NPC reached their currently selected patrol point.
## Will return the previous patrol point if this is the end or the starting one
func get_next_point() -> CogitoPatrolPoint:
	if (traversed and current_point_index == 0) or next_patrol_points.is_empty():
		return get_return_to_point()
	var next_patrol_point = next_patrol_points[current_point_index]
	if not traversed:
		traversed = true	
		next_patrol_point.previous_patrol_point = self
	current_point_index = wrapi(current_point_index + 1, 0, len(next_patrol_points)-1)
	return next_patrol_point
