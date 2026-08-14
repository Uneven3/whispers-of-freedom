class_name Ladder
extends Area3D

## Authored marker for a ladder. Exposes top/bottom anchor points to
## LadderService / LadderMotor.
##
## The Area3D is a TRIGGER ONLY — set collision_layer = 0, collision_mask = 2
## (player Body layer). The actual ladder collider (if any) is a sibling.

@onready var bottom_marker: Node3D = $BottomMarker
@onready var top_marker: Node3D = $TopMarker

func _ready() -> void:
	add_to_group("ladder")
	if bottom_marker == null or top_marker == null:
		push_error("Ladder '%s' is missing a BottomMarker or TopMarker child — ladder disabled." % name)

func get_top_y() -> float:
	return top_marker.global_position.y

func get_bottom_y() -> float:
	return bottom_marker.global_position.y

func get_anchor_xz() -> Vector2:
	var p: Vector3 = bottom_marker.global_position
	return Vector2(p.x, p.z)
