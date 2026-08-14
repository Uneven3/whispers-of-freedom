class_name FormComponent
extends Node

signal form_changed(old_form: StringName, new_form: StringName)

const FORM_PANTHER: StringName = &"panther"
const FORM_MONKEY: StringName = &"monkey"
const FORM_AVIAN: StringName = &"avian"

@export var default_form: StringName = FORM_PANTHER
@export var allowed_forms: Array[StringName] = [FORM_PANTHER, FORM_MONKEY, FORM_AVIAN]

var _current_form: StringName = FORM_PANTHER

func _ready() -> void:
	if default_form in allowed_forms:
		_current_form = default_form
	else:
		push_error("FormComponent default_form is not in allowed_forms: %s" % default_form)

func get_current_form() -> StringName:
	return _current_form

func get_allowed_forms() -> Array[StringName]:
	return allowed_forms.duplicate()

func can_shift_to(form_id: StringName) -> bool:
	return form_id in allowed_forms

func set_form(form_id: StringName) -> bool:
	if form_id == _current_form:
		return false
	if not can_shift_to(form_id):
		push_error("Invalid form shift requested: %s" % form_id)
		return false
	var old_form: StringName = _current_form
	_current_form = form_id
	form_changed.emit(old_form, _current_form)
	return true
