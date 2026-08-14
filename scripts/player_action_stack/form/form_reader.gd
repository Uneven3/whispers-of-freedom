class_name FormReader
extends RefCounted

var _component: Node

func _init(component: Node) -> void:
	_component = component

func get_current_form() -> StringName:
	return _component.get_current_form() if _component and _component.has_method("get_current_form") else &"panther"

func is_form(form_id: StringName) -> bool:
	return get_current_form() == form_id

func get_allowed_forms() -> Array[StringName]:
	return _component.get_allowed_forms() if _component and _component.has_method("get_allowed_forms") else []
