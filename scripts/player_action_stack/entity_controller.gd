class_name EntityController
extends Node3D

## Motores permitidos para esta entidad. Vacío = todos.
## Este nodo es Node3D y no Node sólo para no romper la cadena de transform
## entre Player y Body; no carga significado (docs/movimiento.md).
@export var default_motor_mask: Array[StringName] = []

@onready var _movement_broker: Node = get_node_or_null("MovementBroker")
@onready var _combat_broker: Node = get_node_or_null("CombatBroker")
@onready var _stamina: Node = get_node_or_null("StaminaComponent")

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _movement_broker:
		_movement_broker.set_allowed_motors(default_motor_mask)
	if _combat_broker and _combat_broker.has_method("configure"):
		_combat_broker.configure(
			_movement_broker.get_body_reader() if _movement_broker and _movement_broker.has_method("get_body_reader") else null,
			_stamina,
			get_tree().current_scene,
			_movement_broker
		)
	if _movement_broker and _movement_broker.has_signal("physics_tick_complete"):
		_movement_broker.connect("physics_tick_complete", _on_movement_physics_tick_complete)

func _on_movement_physics_tick_complete(intents: Intents, _current_mode: int) -> void:
	if _combat_broker and _combat_broker.has_method("tick"):
		_combat_broker.tick(intents, get_physics_process_delta_time())
