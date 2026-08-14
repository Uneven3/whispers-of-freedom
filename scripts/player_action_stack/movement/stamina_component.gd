class_name StaminaComponent
extends Node

signal stamina_changed(current: float, max_stamina: float)

@export var max_stamina: float = 100.0
var current_stamina: float = max_stamina

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func drain(amount: float) -> void:
	assert(amount >= 0.0, "Amount must be non-negative")
	current_stamina = clampf(current_stamina - amount, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)

func recover(amount: float) -> void:
	assert(amount >= 0.0, "Amount must be non-negative")
	current_stamina = clampf(current_stamina + amount, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)

func is_exhausted() -> bool:
	return current_stamina <= 0.0

## Reader-only accessors — use these instead of direct field access so callers
## are decoupled from the internal state representation.
func get_current() -> float:
	return current_stamina

func get_max() -> float:
	return max_stamina

func get_normalized() -> float:
	return current_stamina / max_stamina if max_stamina > 0.0 else 0.0
