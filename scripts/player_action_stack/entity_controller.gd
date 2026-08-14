class_name EntityController
extends Node

## Static motor mask for entities without a FormBroker (e.g., mounts, enemies).
## Always applied at _ready(); if a FormBroker is present it immediately replaces
## the mask with the active form's mask (composition: base + form = final).
## Empty means "all allowed".
@export var default_motor_mask: Array[StringName] = []

@onready var _form_broker: Node = get_node_or_null("FormBroker")
@onready var _movement_broker: Node = get_node_or_null("MovementBroker")
@onready var _combat_broker: Node = get_node_or_null("CombatBroker")
@onready var _visuals_pivot: Node = get_node_or_null("VisualsPivot")
@onready var _stamina: Node = get_node_or_null("StaminaComponent")

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _movement_broker:
		_movement_broker.set_allowed_motors(default_motor_mask)
	if _form_broker:
		_form_broker.connect("form_shifted", _on_form_shifted)
		_apply_form_outputs(_form_broker.get_current_form(), false)
	if _combat_broker and _combat_broker.has_method("configure"):
		_combat_broker.configure(
			_movement_broker.get_body_reader() if _movement_broker and _movement_broker.has_method("get_body_reader") else null,
			_form_broker.get_form_reader() if _form_broker and _form_broker.has_method("get_form_reader") else null,
			_stamina,
			get_tree().current_scene,
			_movement_broker
		)
	if _movement_broker and _movement_broker.has_signal("physics_tick_complete"):
		_movement_broker.connect("physics_tick_complete", _on_movement_physics_tick_complete)

func _on_form_shifted(new_form: StringName) -> void:
	_apply_form_outputs(new_form, true)

func _apply_form_outputs(form_id: StringName, inject_transition: bool) -> void:
	if not _form_broker:
		return
	if _movement_broker and _movement_broker.has_method("set_allowed_motors"):
		_movement_broker.set_allowed_motors(_form_broker.motor_mask_for(form_id))
	if inject_transition and _movement_broker and _movement_broker.has_method("inject_forced_proposal"):
		_movement_broker.inject_forced_proposal(
			_form_broker.form_shift_proposal_for(form_id, _movement_broker.get_current_mode())
		)
	if _visuals_pivot and _visuals_pivot.has_method("apply_form_visual"):
		_visuals_pivot.apply_form_visual(
			form_id,
			_form_broker.visual_color_for(form_id),
			_form_broker.visual_scale_for(form_id)
		)

func _on_movement_physics_tick_complete(intents: Intents, _current_mode: int) -> void:
	if _combat_broker and _combat_broker.has_method("tick"):
		_combat_broker.tick(intents, get_physics_process_delta_time())
