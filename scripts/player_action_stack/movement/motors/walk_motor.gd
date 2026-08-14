class_name WalkMotor
extends BaseMotor

@export var max_speed: float = 5.0
@export var acceleration: float = 20.0
@export var friction: float = 25.0
@export var stamina_recover_per_sec: float = 15.0

func gather_proposals(_current_mode: int, _intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	if ground != null and ground.is_on_floor():
		return [TransitionProposal.new(LocomotionState.ID.WALK, TransitionProposal.Priority.PLAYER_REQUESTED)] # state WALK
	return []

func tick(_delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, intents, _delta)
	var move_dir: Vector3 = Vector3(intents.move_dir.x, 0, intents.move_dir.y).normalized()
	if move_dir != Vector3.ZERO:
		body.velocity.x = move_toward(body.velocity.x, move_dir.x * max_speed, acceleration * _delta)
		body.velocity.z = move_toward(body.velocity.z, move_dir.z * max_speed, acceleration * _delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0, friction * _delta)
		body.velocity.z = move_toward(body.velocity.z, 0, friction * _delta)

	# Vertical handling — WalkMotor owns velocity.y in walk mode. Stair traversal is
	# delegated to StairsMotor; small obstacles to AutoVaultMotor. WalkMotor itself is
	# strictly flat-floor.
	body.velocity.y = 0.0

	if stamina:
		stamina.recover(stamina_recover_per_sec * _delta)

	body.move_and_slide()
