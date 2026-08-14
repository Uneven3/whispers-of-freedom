class_name ParryCounterAction
extends Node

@export var parry_range: float = 4.0
@export var counter_damage: float = 45.0
@export var hit_pause_scale: float = 0.12
@export var hit_pause_duration: float = 0.12

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func tick(intents: Intents, _delta: float, broker: Node) -> void:
	if not intents.wants_parry or not broker:
		return
	var body_reader: BodyReader = broker.get_body_reader()
	if not body_reader:
		return
	var target: Node3D = broker.find_nearest_target(body_reader.get_global_position(), parry_range)
	if not target:
		broker.set_combat_state(&"parry_miss")
		return
	if not target.has_method("is_parry_vulnerable") or not target.is_parry_vulnerable():
		broker.set_combat_state(&"parry_miss")
		return
	if target.has_method("consume_parry"):
		target.consume_parry()
	broker.apply_damage(target, counter_damage, &"monkey_counter", &"heavy", target.global_position)
	broker.set_combat_state(&"counter_hit")
	broker.trigger_hit_pause(hit_pause_scale, hit_pause_duration)
