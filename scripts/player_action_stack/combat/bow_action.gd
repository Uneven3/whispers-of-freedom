class_name BowAction
extends Node

const ArrowProjectileScript = preload("res://scripts/world/arrow_projectile.gd")

@export var damage: float = 35.0
@export var projectile_speed: float = 26.0
@export var projectile_gravity: float = 17.0
@export var max_range: float = 55.0
@export var stamina_cost: float = 8.0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func tick(intents: Intents, _delta: float, broker: Node) -> void:
	if not broker:
		return
	if intents.wants_archery_aim:
		broker.set_combat_state(&"bow_drawn")
	if not intents.wants_archery_release:
		return
	_fire_arrow(intents, broker)

func _fire_arrow(intents: Intents, broker: Node) -> void:
	if intents.aim_direction == Vector3.ZERO:
		return
	var parent: Node = broker.get_projectile_parent()
	if not parent:
		return
	var arrow: Node3D = ArrowProjectileScript.new()
	parent.add_child(arrow)
	var body_reader: BodyReader = broker.get_body_reader()
	var aim_direction := intents.aim_direction.normalized()
	var right := aim_direction.cross(Vector3.UP).normalized()
	if right == Vector3.ZERO:
		right = Vector3.RIGHT
	var muzzle_origin := body_reader.get_global_position() + Vector3.UP * 1.25 + right * 0.42 + aim_direction * 0.45
	arrow.launch(
		body_reader._body,
		muzzle_origin,
		aim_direction,
		projectile_speed,
		max_range,
		damage,
		projectile_gravity
	)
	if broker.has_method("set_combat_state"):
		broker.set_combat_state(&"bow_release")
	if broker.has_method("trigger_hit_pause"):
		broker.trigger_hit_pause(0.65, 0.025)
