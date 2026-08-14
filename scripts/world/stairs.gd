class_name Stairs
extends Area3D

## Authored marker for a discrete staircase. Exposes step geometry to
## StairsService / StairsMotor. Place an Area3D shaped to enclose all steps
## plus a small lip at top and bottom (so transitions trigger before the body
## has fully left the stairs).
##
## The Area3D is a TRIGGER ONLY — set collision_layer = 0, collision_mask = 2
## (player Body layer). The actual step CollisionShape3Ds are siblings, kept
## as authored — the body still walks on real treads, the marker only reports
## "you are on the stairs" + step geometry.

## Required children — placed by the scene author. @onready resolves them after
## children are attached, avoiding the Godot 4 @export/NodePath load-order pitfall.
@onready var base_marker: Node3D = $BaseMarker
@onready var top_marker: Node3D = $TopMarker

@export var step_count: int = 8
@export var step_depth: float = 0.5  ## Horizontal run of one tread, metres
@export var step_rise: float = 0.25  ## Vertical rise of one riser, metres

func _ready() -> void:
	add_to_group("stairs")
	if base_marker == null or top_marker == null:
		push_error("Stairs '%s' is missing a BaseMarker or TopMarker child — stairs disabled." % name)

## Unit vector along the stairs in the horizontal plane (Y stripped).
func get_slope_horizontal_axis() -> Vector3:
	var d: Vector3 = top_marker.global_position - base_marker.global_position
	return Vector3(d.x, 0.0, d.z).normalized()

## Returns the expected feet-Y for a body at the given world position, by
## computing how far along the stair axis it has progressed.
##   d <= 0          → at the foot, feet_y = base.y (flat floor below)
##   0 < d < total   → on stair N, feet_y = base.y + (N+1) * step_rise
##   d >= total      → on landing, feet_y = base.y + step_count * step_rise
func compute_expected_feet_y(world_pos: Vector3) -> float:
	var horiz: Vector3 = get_slope_horizontal_axis()
	var d: float = (world_pos - base_marker.global_position).dot(horiz)
	if d <= 0.0:
		return base_marker.global_position.y
	var total_run: float = float(step_count) * step_depth
	if d >= total_run:
		return base_marker.global_position.y + float(step_count) * step_rise
	var idx: int = int(floor(d / step_depth))
	return base_marker.global_position.y + float(idx + 1) * step_rise
