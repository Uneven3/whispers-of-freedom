class_name Stairs
extends Area3D

## Marcador de escalera para StairsService / StairsMotor. El Area3D es SÓLO
## TRIGGER (collision_layer = 0, collision_mask = 2) y tiene que encerrar los
## escalones más un labio arriba y abajo. Los treads reales son hermanos.

## @onready y no @export/NodePath: evita el problema de orden de carga.
@onready var base_marker: Node3D = $BaseMarker
@onready var top_marker: Node3D = $TopMarker

@export var step_count: int = 8
@export var step_depth: float = 0.5  ## Horizontal run of one tread, metres
@export var step_rise: float = 0.25  ## Vertical rise of one riser, metres

func _ready() -> void:
	if base_marker == null or top_marker == null:
		push_error("Stairs '%s' is missing a BaseMarker or TopMarker child — stairs disabled." % name)
		return
	add_to_group("stairs")

func get_slope_horizontal_axis() -> Vector3:
	var d: Vector3 = top_marker.global_position - base_marker.global_position
	return Vector3(d.x, 0.0, d.z).normalized()

## Y de los pies esperada para un cuerpo en esa posición del mundo.
func compute_expected_feet_y(world_pos: Vector3) -> float:
	var slope_axis: Vector3 = get_slope_horizontal_axis()
	var distance_along_slope: float = (world_pos - base_marker.global_position).dot(slope_axis)
	if distance_along_slope <= 0.0:
		return base_marker.global_position.y
	var total_horizontal_run: float = float(step_count) * step_depth
	if distance_along_slope >= total_horizontal_run:
		return base_marker.global_position.y + float(step_count) * step_rise
	var step_index: int = int(floor(distance_along_slope / step_depth))
	return base_marker.global_position.y + float(step_index + 1) * step_rise
