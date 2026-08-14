class_name GroundService
extends BaseService

## Read-only fact provider for floor state.
## Exposes:
##   is_on_floor()       — delegates to CharacterBody3D.is_on_floor() (previous frame),
##                         filtered by slope angle (see max_slope_angle_deg).
##   get_floor_normal()  — normal of the floor under the player
##
## Stair traversal is no longer this service's concern — see StairsService /
## StairsMotor / scripts/world/stairs.gd. Step-up casts (WallCast, ClearanceCast)
## have been removed; AutoVaultMotor still handles waist-high obstacles.
##
## Per architecture (01-scope-and-boundaries-player-action-stack.md), this
## service NEVER mutates the body — motors are the only writers.

## Surfaces steeper than this angle (measured from Vector3.UP) are not considered
## "floor". Default 60° is large enough to pass stair-riser glance frames (~27° from
## UP on tread contact) while still rejecting walls (90°) and very steep ramps.
## Lower this if the player walks on surfaces they should slide off.
@export var max_slope_angle_deg: float = 60.0

var _is_on_floor: bool      = false
var _floor_normal: Vector3  = Vector3.UP

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func update_facts(body_reader: BodyReader) -> void:
	## Floor detection: CharacterBody3D.is_on_floor() is authoritative — updated each
	## move_and_slide(). Reflects the state from the end of the PREVIOUS physics frame,
	## which is exactly what we need for one-frame-consistent ground decisions.
	var raw_on_floor: bool = body_reader.is_on_floor()
	_floor_normal = body_reader.get_floor_normal()
	## Slope filter: reject surfaces steeper than max_slope_angle_deg.
	## guards against the player "walking" up near-vertical ramps.
	if raw_on_floor and _floor_normal != Vector3.ZERO:
		var slope_deg: float = rad_to_deg(_floor_normal.angle_to(Vector3.UP))
		_is_on_floor = slope_deg <= max_slope_angle_deg
	else:
		_is_on_floor = raw_on_floor

func is_on_floor() -> bool:
	return _is_on_floor

func get_floor_normal() -> Vector3:
	return _floor_normal
