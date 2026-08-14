class_name SprintMotor
extends BaseMotor

@export var sprint_speed: float = 10.0
@export var sprint_acceleration: float = 25.0
@export var sprint_deceleration: float = 35.0
@export var stamina_cost_per_sec: float = 10.0
@export var sprint_recharge_threshold: float = 20.0

var _stamina_locked: bool = false

func gather_proposals(_current_mode: int, intents: Intents, services: Array[BaseService], stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	if stamina:
		var cur: float = stamina.get_current()
		if cur <= 0.0:
			_stamina_locked = true
		elif cur >= sprint_recharge_threshold:
			_stamina_locked = false
	## Abstain on stairs — StairsMotor handles the climb (incl. sprint speed) so the
	## per-step Y-snap fires; otherwise SprintMotor's flat-floor velocity.y=0 leaves
	## the body wedged against each riser.
	var stairs: StairsService = _get_service(services, StairsService) as StairsService
	if stairs != null and stairs.is_on_stairs():
		return []
	## Abstain on climbable wall — ClimbMotor wins arbitration when the player is facing a
	## climbable surface and has climb toggled on.  SprintMotor's flat-floor velocity would
	## fight the wall-stick and prevent CLIMB from ever winning PLAYER_REQUESTED arbitration.
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	if ledge != null and ledge.can_climb() and intents.wants_climb:
		return []
	if ground != null and ground.is_on_floor() and intents.wants_sprint and not _stamina_locked:
		return [TransitionProposal.new(LocomotionState.ID.SPRINT, 2)]
	return []

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, intents, delta)
	var move_dir: Vector3 = Vector3(intents.move_dir.x, 0, intents.move_dir.y).normalized()
	if move_dir != Vector3.ZERO:
		body.velocity.x = move_toward(body.velocity.x, move_dir.x * sprint_speed, sprint_acceleration * delta)
		body.velocity.z = move_toward(body.velocity.z, move_dir.z * sprint_speed, sprint_acceleration * delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0, sprint_deceleration * delta)
		body.velocity.z = move_toward(body.velocity.z, 0, sprint_deceleration * delta)

	# Vertical handling — same contract as WalkMotor. Stairs delegated to StairsMotor;
	# obstacles to AutoVaultMotor. SprintMotor is strictly flat-floor.
	body.velocity.y = 0.0

	if stamina:
		stamina.drain(stamina_cost_per_sec * delta)

	body.move_and_slide()
