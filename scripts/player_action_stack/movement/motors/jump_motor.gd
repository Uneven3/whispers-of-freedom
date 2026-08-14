class_name JumpMotor
extends BaseMotor

@export var jump_impulse: float = 5.5
@export var horizontal_speed_boost: float = 2.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _prev_wants_jump: bool = false
var _needs_release: bool = false  # prevents auto-repeat while jump is held

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	## Treat stair mode as grounded. StairsMotor performs its own per-frame Y-snap and
	## suspends Godot's floor_snap, so CharacterBody3D.is_on_floor() flickers off between
	## snap frames — gating the jump on raw is_on_floor() makes jumping from stairs unreliable.
	var on_floor: bool = (ground != null and ground.is_on_floor()) or current_mode == LocomotionState.ID.STAIRS
	var delta: float = get_physics_process_delta_time()

	# Clear the lock as soon as the key is released
	if not intents.wants_jump:
		_needs_release = false

	# Coyote time: start window only when walking off a ledge, not after a jump
	if _was_on_floor and not on_floor and current_mode != LocomotionState.ID.JUMP:
		_coyote_timer = coyote_time
	elif not on_floor:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_was_on_floor = on_floor

	# Jump buffer: detect rising edge of wants_jump and hold intent briefly
	if intents.wants_jump and not _prev_wants_jump:
		_jump_buffer_timer = jump_buffer_time
	elif _jump_buffer_timer > 0.0:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_prev_wants_jump = intents.wants_jump

	var can_jump: bool = on_floor or _coyote_timer > 0.0
	var wants: bool = (intents.wants_jump or _jump_buffer_timer > 0.0) and not _needs_release

	if can_jump and wants:
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		_needs_release = true
		return [TransitionProposal.new(LocomotionState.ID.JUMP, 3)] # state JUMP, priority 3
	return []

func tick(_delta: float, _intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, _intents, _delta)
	body.velocity.y = jump_impulse
	body.move_and_slide()
