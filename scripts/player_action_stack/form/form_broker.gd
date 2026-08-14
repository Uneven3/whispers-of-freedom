class_name FormBroker
extends Node

signal form_shifted(new_form: StringName)

const FormReaderScript = preload("res://scripts/player_action_stack/form/form_reader.gd")
const FORM_SHIFT_SOURCE_ID: StringName = &"form_shift"
const FORM_PANTHER: StringName = &"panther"
const FORM_MONKEY: StringName = &"monkey"
const FORM_AVIAN: StringName = &"avian"

@onready var _form_component: Node = $"../FormComponent"

var _reader: RefCounted
var _shifts_enabled: bool = true

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _form_component:
		_reader = FormReaderScript.new(_form_component)
		_form_component.connect("form_changed", _on_form_changed)

func tick(intents: Intents, _delta: float) -> void:
	if not _shifts_enabled or not _form_component or not intents:
		return
	if intents.wants_form_shift == &"":
		return
	_form_component.set_form(intents.wants_form_shift)

func get_form_reader() -> RefCounted:
	return _reader

func set_shifts_enabled(enabled: bool, _caller: Object = null) -> void:
	_shifts_enabled = enabled

func get_current_form() -> StringName:
	return _form_component.get_current_form() if _form_component and _form_component.has_method("get_current_form") else FORM_PANTHER

func motor_mask_for(form_id: StringName) -> Array[StringName]:
	match form_id:
		FORM_PANTHER:
			return [
				&"WalkMotor", &"SprintMotor", &"FallMotor", &"JumpMotor",
				&"AutoVaultMotor", &"MantleMotor", &"StairsMotor", &"LadderMotor",
				&"SneakMotor", &"ClimbMotor", &"WallJumpMotor", &"EdgeLeapMotor"
			]
		FORM_MONKEY:
			return [
				&"WalkMotor", &"SprintMotor", &"FallMotor", &"JumpMotor",
				&"AutoVaultMotor", &"MantleMotor", &"StairsMotor", &"LadderMotor",
				&"ClimbMotor", &"WallJumpMotor", &"EdgeLeapMotor", &"StrikeMotor"
			]
		FORM_AVIAN:
			return [
				&"WalkMotor", &"SprintMotor", &"FallMotor", &"JumpMotor",
				&"AutoVaultMotor", &"MantleMotor", &"StairsMotor", &"LadderMotor",
				&"GlideMotor"
			]
	return []

func visual_color_for(form_id: StringName) -> Color:
	match form_id:
		FORM_PANTHER:
			return Color(0.12, 0.10, 0.16)
		FORM_MONKEY:
			return Color(0.45, 0.30, 0.16)
		FORM_AVIAN:
			return Color(0.18, 0.38, 0.72)
	return Color.WHITE

func visual_scale_for(form_id: StringName) -> Vector3:
	match form_id:
		FORM_PANTHER:
			return Vector3(1.15, 0.85, 1.35)
		FORM_MONKEY:
			return Vector3(0.95, 1.10, 0.95)
		FORM_AVIAN:
			return Vector3(0.80, 0.75, 1.10)
	return Vector3.ONE

func form_shift_proposal_for(_form_id: StringName, current_mode: int) -> TransitionProposal:
	return TransitionProposal.new(
		current_mode,
		TransitionProposal.Priority.FORCED,
		1000.0,
		FORM_SHIFT_SOURCE_ID
	)

func _on_form_changed(_old_form: StringName, new_form: StringName) -> void:
	form_shifted.emit(new_form)
