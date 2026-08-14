class_name ArrowProjectile
extends Node3D

const DamageEventScript = preload("res://scripts/base/damage_event.gd")

var _source: Node3D
var _velocity: Vector3 = Vector3.FORWARD
var _remaining_range: float = 40.0
var _damage: float = 25.0
var _gravity: float = 18.0
var _mesh: MeshInstance3D

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_mesh = MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.08, 0.08, 0.72)
	_mesh.mesh = body
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.90, 0.35)
	material.emission_enabled = true
	material.emission = Color(0.95, 0.65, 0.10)
	_mesh.material_override = material
	add_child(_mesh)

func launch(
	source: Node3D,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	max_range: float,
	damage: float,
	gravity: float = 18.0
) -> void:
	_source = source
	global_position = origin
	_velocity = direction.normalized() * speed
	_remaining_range = max_range
	_damage = damage
	_gravity = gravity
	_face_velocity()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	var start := global_position
	_velocity += Vector3.DOWN * _gravity * delta
	var displacement := _velocity * delta
	var travel := displacement.length()
	var end := start + displacement
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [_source, self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_hit_target(hit)
		return
	global_position = end
	_face_velocity()
	_remaining_range -= travel
	if _remaining_range <= 0.0:
		queue_free()

func _face_velocity() -> void:
	if _velocity.length_squared() <= 0.001:
		return
	look_at(global_position + _velocity.normalized(), Vector3.UP)

func _hit_target(hit: Dictionary) -> void:
	var collider := hit.get("collider") as Node
	var target := collider
	if target and not target.has_method("apply_damage") and target.get_parent():
		target = target.get_parent()
	if target and target.has_method("apply_damage") and target is Node3D:
		var event := DamageEventScript.new(
			_source,
			target,
			_damage,
			&"avian_arrow",
			&"light",
			hit.get("position", global_position)
		)
		target.apply_damage(event)
	queue_free()
