class_name MovementBroker
extends Node

signal state_changed(old_mode: int, new_mode: int)
signal physics_tick_complete(intents: Intents, current_mode: int)

@export var motor_map: Dictionary[int, NodePath] = {}
## NodePath to the Brain node relative to this broker. Defaults to the player
## convention; other entities override this to point at their own Brain.
@export var brain_path: NodePath = NodePath("../PlayerBrain")
@onready var _brain: Node = get_node_or_null(brain_path)
@onready var _body: CharacterBody3D = get_node_or_null("%Body")
@onready var _stamina: StaminaComponent = get_node_or_null("%StaminaComponent")
@onready var _ground_service: GroundService = get_node_or_null("%GroundService")
@onready var _ledge_service: LedgeService = get_node_or_null("%LedgeService")
@onready var _stairs_service: StairsService = get_node_or_null("%StairsService")
@onready var _ladder_service: LadderService = get_node_or_null("%LadderService")

var _motors: Dictionary = {}
var _services: Array[BaseService] = []
var _body_reader: BodyReader
var _loco_state: LocomotionState
var _state_reader: LocomotionStateReader
var _allowed_motor_names: Dictionary = {}
var _external_proposals: Array[TransitionProposal] = []

## Public API for state access
func get_current_mode() -> int:
	assert(_loco_state != null, "LocomotionState not initialized")
	return _loco_state.get_active_mode() if _loco_state else LocomotionState.ID.FALL

var _current_mode: int:
	get:
		return get_current_mode()

func get_body_reader() -> BodyReader:
	return _body_reader

func get_state_reader() -> LocomotionStateReader:
	return _state_reader

func set_allowed_motors(mask: Array[StringName]) -> void:
	_allowed_motor_names.clear()
	for motor_name in mask:
		_allowed_motor_names[motor_name] = true

func inject_forced_proposal(proposal: TransitionProposal) -> void:
	if proposal == null:
		return
	if proposal.category != TransitionProposal.Priority.FORCED:
		push_error("MovementBroker only accepts forced external proposals")
		return
	_external_proposals.append(proposal)

func _ready() -> void:
	if _brain == null:
		push_warning("brain_path '%s' does not resolve — entity has no input" % brain_path)
	_body_reader = BodyReader.new(_body)
	_loco_state = LocomotionState.new()
	_state_reader = LocomotionStateReader.new(_loco_state)
	add_child(_loco_state)
	
	var reporter = MovementBrokerDebugReporter.new()
	add_child(reporter)
	
	## Forward LocomotionState.state_changed as MovementBroker.state_changed
	_loco_state.state_changed.connect(func(o: int, n: int) -> void: state_changed.emit(o, n))

	for state_id in motor_map.keys():
		var path: NodePath = motor_map[state_id]
		if has_node(path):
			_motors[state_id] = get_node(path)
	
	if _ground_service: _services.append(_ground_service)
	if _ledge_service: _services.append(_ledge_service)
	if _stairs_service: _services.append(_stairs_service)
	if _ladder_service: _services.append(_ladder_service)
	
	# Auto-populate if map is empty (fallback for graybox ease)
	if _motors.is_empty():
		for child in get_children():
			if child is BaseMotor:
				var state_id: int = _guess_state_id(child.name)
				_motors[state_id] = child
	
	for m in _motors.values():
		if m is BaseMotor:
			m._broker = self

func _guess_state_id(motor_name: String) -> int:
	match motor_name:
		"WalkMotor": return LocomotionState.ID.WALK
		"SprintMotor": return LocomotionState.ID.SPRINT
		"FallMotor": return LocomotionState.ID.FALL
		"JumpMotor": return LocomotionState.ID.JUMP
		"AutoVaultMotor": return LocomotionState.ID.AUTO_VAULT
		"ClimbMotor": return LocomotionState.ID.CLIMB
		"MantleMotor": return LocomotionState.ID.MANTLE
		"StairsMotor": return LocomotionState.ID.STAIRS
		"LadderMotor": return LocomotionState.ID.LADDER
		"GlideMotor": return LocomotionState.ID.GLIDE
		"SneakMotor": return LocomotionState.ID.SNEAK
		"WallJumpMotor": return LocomotionState.ID.WALL_JUMP
		"EdgeLeapMotor": return LocomotionState.ID.EDGE_LEAP
		"StrikeMotor": return LocomotionState.ID.STRIKE
	return LocomotionState.ID.IDLE

func _physics_process(delta: float) -> void:
	var intents: Intents = _brain.get_intents() if _brain and _brain.has_method("get_intents") else Intents.new()

	if _ledge_service:
		_ledge_service.set_current_mode(_current_mode)
	for s in _services:
		if s.has_method("update_facts"):
			s.update_facts(_body_reader)

	var best_proposal: TransitionProposal = null
	for external_proposal in _external_proposals:
		if _proposal_is_allowed(external_proposal):
			best_proposal = _choose_better_proposal(best_proposal, external_proposal)
	_external_proposals.clear()

	for m in _motors.values():
		if not m is BaseMotor:
			continue
		if not _is_motor_allowed(m):
			continue
		var proposals: Array[TransitionProposal] = m.gather_proposals(_current_mode, intents, _services, _stamina)
		for p in proposals:
			if _proposal_is_allowed(p):
				best_proposal = _choose_better_proposal(best_proposal, p)
			
	var new_mode: int = LocomotionState.ID.FALL
	if best_proposal != null:
		new_mode = best_proposal.target_state
		
	if new_mode != _current_mode:
		var old_mode: int = _current_mode
		_loco_state.set_state(new_mode)  ## SSoT write
		if _motors.has(old_mode) and _motors[old_mode].has_method("on_deactivate"):
			_motors[old_mode].on_deactivate(_body)
		if _motors.has(new_mode) and _motors[new_mode].has_method("on_activate"):
			_motors[new_mode].on_activate(_body)
		
	if _motors.has(_current_mode):
		var active_motor = _motors[_current_mode]
		if active_motor is BaseMotor and _is_motor_allowed(active_motor):
			active_motor.tick(delta, intents, _body, _stamina, _services)

	physics_tick_complete.emit(intents, _current_mode)

func _choose_better_proposal(
	current_best: TransitionProposal,
	candidate: TransitionProposal
) -> TransitionProposal:
	if current_best == null:
		return candidate
	if candidate.category > current_best.category:
		return candidate
	if candidate.category == current_best.category and candidate.override_weight > current_best.override_weight:
		return candidate
	return current_best

func _proposal_is_allowed(proposal: TransitionProposal) -> bool:
	if proposal == null:
		return false
	if not _motors.has(proposal.target_state):
		return false
	return _is_motor_allowed(_motors[proposal.target_state])

func _is_motor_allowed(motor: Node) -> bool:
	if _allowed_motor_names.is_empty():
		return true
	return _allowed_motor_names.has(StringName(motor.name))
