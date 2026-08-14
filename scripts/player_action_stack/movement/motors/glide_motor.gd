class_name GlideMotor
extends BaseMotor

const MIN_INPUT_LENGTH_SQUARED: float = 0.01
const STAMINA_RECOVERY_FACTOR: float = 0.25

@export var glide_fall_speed: float = 1.5
@export var glide_gravity_multiplier: float = 0.25
@export var max_glide_speed: float = 6.0
@export var glide_acceleration: float = 4.0
@export var stamina_recover_per_sec: float = 8.0

var _previous_wants_glide: bool = false

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	var on_floor: bool = ground != null and ground.is_on_floor()
	if on_floor:
		_previous_wants_glide = intents.wants_glide
		return []

	if current_mode == LocomotionState.ID.GLIDE:
		_previous_wants_glide = intents.wants_glide
		if intents.wants_glide:
			## Downgrade to PLAYER_REQUESTED when the player is also requesting a climb on a
			## climbable wall.  FORCED would outbid ClimbMotor's PLAYER_REQUESTED weight=5,
			## locking the player into GLIDE while glued to a wall.  Downgrading lets
			## ClimbMotor win the weight tiebreak (both are now PLAYER_REQUESTED; ClimbMotor
			## emits override_weight=5 which beats GlideMotor's default weight=0).
			if ledge != null and ledge.can_climb() and intents.wants_climb:
				return [TransitionProposal.new(LocomotionState.ID.GLIDE, TransitionProposal.Priority.PLAYER_REQUESTED)]
			return [TransitionProposal.new(LocomotionState.ID.GLIDE, TransitionProposal.Priority.FORCED)]
		return []

	var fresh_glide_press: bool = intents.wants_glide and not _previous_wants_glide
	_previous_wants_glide = intents.wants_glide
	if current_mode == LocomotionState.ID.FALL and fresh_glide_press:
		return [TransitionProposal.new(LocomotionState.ID.GLIDE, TransitionProposal.Priority.PLAYER_REQUESTED)]
	return []

func on_deactivate(_body: CharacterBody3D) -> void:
	## Reset glide-press memory so the first frame after leaving a wall (or any
	## non-GLIDE exit) does not suppress a legitimate fresh glide press.
	## Without this, `_previous_wants_glide` stays `true` from the last GLIDE frame,
	## causing `fresh_glide_press` to evaluate `false` and blocking re-entry.
	_previous_wants_glide = false

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, intents, delta)
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	body.velocity.y -= gravity * glide_gravity_multiplier * delta
	body.velocity.y = maxf(body.velocity.y, -glide_fall_speed)

	var move_dir: Vector3 = Vector3(intents.move_dir.x, 0.0, intents.move_dir.y).normalized()
	if move_dir.length_squared() > MIN_INPUT_LENGTH_SQUARED:
		body.velocity.x = move_toward(body.velocity.x, move_dir.x * max_glide_speed, glide_acceleration * delta)
		body.velocity.z = move_toward(body.velocity.z, move_dir.z * max_glide_speed, glide_acceleration * delta)

	if stamina != null:
		stamina.recover(stamina_recover_per_sec * STAMINA_RECOVERY_FACTOR * delta)

	body.move_and_slide()
