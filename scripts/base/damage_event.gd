class_name DamageEvent
extends RefCounted

var source: Node3D
var target: Node3D
var amount: float
var damage_type: StringName
var stagger_class: StringName
var hit_position: Vector3

func _init(
	p_source: Node3D,
	p_target: Node3D,
	p_amount: float,
	p_damage_type: StringName,
	p_stagger_class: StringName = &"none",
	p_hit_position: Vector3 = Vector3.ZERO
) -> void:
	assert(p_source != null, "DamageEvent.source must not be null")
	assert(p_target != null, "DamageEvent.target must not be null")
	assert(p_amount >= 0.0, "DamageEvent.amount must be >= 0")
	assert(p_damage_type != &"", "DamageEvent.damage_type must be non-empty")
	source = p_source
	target = p_target
	amount = p_amount
	damage_type = p_damage_type
	stagger_class = p_stagger_class
	hit_position = p_hit_position

## El collider golpeado puede ser un hijo y no la entidad con apply_damage():
## sube un nivel. Compartido para que melee y a distancia no se separen.
static func resolve_receiver(target: Node) -> Node:
	if target and not target.has_method("apply_damage") and target.get_parent():
		return target.get_parent()
	return target
