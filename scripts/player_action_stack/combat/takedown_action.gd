class_name TakedownAction
extends Node

@export var takedown_range: float = 2.4
@export var takedown_damage: float = 999.0
@export var hit_pause_scale: float = 0.10
@export var hit_pause_duration: float = 0.16

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func tick(intents: Intents, _delta: float, broker: Node) -> void:
	if not intents.wants_assassinate or not broker:
		return
	var body_reader: BodyReader = broker.get_body_reader()
	if not body_reader:
		return
	var target: Node3D = broker.find_nearest_target(body_reader.get_global_position(), takedown_range)
	if not target:
		broker.set_combat_state(&"takedown_miss")
		return
	if target.has_method("can_be_takedown") and not target.can_be_takedown(body_reader.get_global_position()):
		broker.set_combat_state(&"takedown_miss")
		return
	broker.apply_damage(target, takedown_damage, &"takedown", &"finisher", target.global_position)
	broker.set_combat_state(&"takedown_hit")
	broker.trigger_hit_pause(hit_pause_scale, hit_pause_duration)
