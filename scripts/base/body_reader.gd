class_name BodyReader
extends RefCounted

var _body: CharacterBody3D
var _warned_no_capsule: bool = false

func _init(body: CharacterBody3D) -> void:
	assert(body is CharacterBody3D, "BodyReader requires a CharacterBody3D")
	_body = body

func get_body() -> CharacterBody3D:
	return _body

func get_global_position() -> Vector3:
	return _body.global_position

func get_velocity() -> Vector3:
	return _body.velocity

func get_basis() -> Basis:
	return _body.basis

func is_on_floor() -> bool:
	return _body.is_on_floor()

func get_floor_normal() -> Vector3:
	return _body.get_floor_normal()

## Body geometry — single source of truth is the CollisionShape3D on the Body.
## Motors/Services read half-height and radius from here instead of re-declaring
## their own @export geometry, so entities with different capsules (mounts,
## enemies) work without manual per-motor overrides.
##
## The CollisionShape3D may be rotated (e.g. a horizontal capsule for a horse),
## so both extents are computed in world space from the shape's basis.

func get_body_half_height() -> float:
	var capsule := _get_capsule_shape()
	if capsule == null:
		_warn_no_capsule_once()
		return 1.0
	var b := _get_shape_basis()
	# Vertical (Y) half-extent of the rotated capsule: sum of each local
	# half-extent projected onto world Y. Local half-extents are (r, h/2, r).
	var half := capsule.height * 0.5
	var r := capsule.radius
	return absf(b.x.y) * r + absf(b.y.y) * half + absf(b.z.y) * r

func get_body_radius() -> float:
	var capsule := _get_capsule_shape()
	if capsule == null:
		_warn_no_capsule_once()
		return 0.5
	var b := _get_shape_basis()
	# Horizontal half-extent: max of the world X and Z projections of the
	# rotated capsule's local half-extents.
	var half := capsule.height * 0.5
	var r := capsule.radius
	var ext_x := absf(b.x.x) * r + absf(b.y.x) * half + absf(b.z.x) * r
	var ext_z := absf(b.x.z) * r + absf(b.y.z) * half + absf(b.z.z) * r
	return maxf(ext_x, ext_z)

func _warn_no_capsule_once() -> void:
	if _warned_no_capsule:
		return
	_warned_no_capsule = true
	push_warning("Body '%s' has no CapsuleShape3D CollisionShape3D — falling back to default capsule geometry" % _body.name)

func _get_capsule_shape() -> CapsuleShape3D:
	var shape_node := _get_shape_node()
	if shape_node and shape_node.shape is CapsuleShape3D:
		return shape_node.shape as CapsuleShape3D
	return null

func _get_shape_node() -> CollisionShape3D:
	return _body.get_node_or_null("CollisionShape3D") as CollisionShape3D

func _get_shape_basis() -> Basis:
	var shape_node := _get_shape_node()
	return shape_node.global_basis if shape_node else Basis.IDENTITY
