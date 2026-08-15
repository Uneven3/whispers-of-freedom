class_name EntityController
extends Node3D

## Motor mask applied at _ready() for this entity — e.g. a mount only allows
## ground motors. Empty means "all allowed" (the default for a full player).
##
## Node3D, not Node: Godot's Node3D only inherits transform from its
## IMMEDIATE parent cast to Node3D — it does not walk up through a plain
## Node to find a farther Node3D ancestor. As a plain Node, EntityController
## silently broke that chain between Player (the entity's spatial root,
## moved by scenes/SpawnSnap) and Body/VisualsPivot underneath it: moving
## Player never moved the actual capsule, in the editor or in a real Play
## session — confirmed empirically against the engine, not assumed. This
## node still owns no transform of its own (identity, a transparent
## pass-through) — it's spatial now only so the chain isn't broken, not to
## carry meaning itself (§3/§13 of ARCHITECTURE.md, unchanged).
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
