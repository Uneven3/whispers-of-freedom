class_name Ladder
extends Area3D

## Marcador de escalera para LadderService / LadderMotor.
## El Area3D es SÓLO TRIGGER: collision_layer = 0, collision_mask = 2. El
## collider real, si lo hay, es un hermano.

@onready var bottom_marker: Node3D = $BottomMarker
@onready var top_marker: Node3D = $TopMarker

func _ready() -> void:
	if bottom_marker == null or top_marker == null:
		push_error("Ladder '%s' is missing a BottomMarker or TopMarker child — ladder disabled." % name)
		return
	add_to_group("ladder")

func get_top_y() -> float:
	return top_marker.global_position.y

func get_bottom_y() -> float:
	return bottom_marker.global_position.y

func get_anchor_xz() -> Vector2:
	var p: Vector3 = bottom_marker.global_position
	return Vector2(p.x, p.z)
