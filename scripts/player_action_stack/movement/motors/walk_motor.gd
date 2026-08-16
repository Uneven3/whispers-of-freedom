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
	# Stair traversal is delegated to StairsMotor; small obstacles to
	# AutoVaultMotor. WalkMotor itself is strictly flat-floor.
	apply_ground_velocity(body, move_dir, max_speed, acceleration, friction, _delta)

	if stamina:
		stamina.recover(stamina_recover_per_sec * _delta)

	body.move_and_slide()
