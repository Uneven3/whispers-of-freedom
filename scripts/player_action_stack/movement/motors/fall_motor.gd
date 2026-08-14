class_name FallMotor
extends BaseMotor

@export var max_air_speed: float = 5.0
@export var air_acceleration: float = 5.0
@export var rise_gravity_multiplier: float = 1.3
@export var fall_gravity_multiplier: float = 2.5
@export var jump_cut_velocity: float = 2.0
@export var stamina_recover_per_sec: float = 15.0

const FALL_STAMINA_RECOVER_FRACTION: float = 0.25

func gather_proposals(_current_mode: int, _intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	if ground != null and not ground.is_on_floor():
		return [TransitionProposal.new(LocomotionState.ID.FALL, 0)] # state FALL, FALLBACK priority
	return []

func tick(delta: float, intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, intents, delta)
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

	# Jump cut: tapping jump gives a short hop, holding gives full height
	if not intents.wants_jump and body.velocity.y > jump_cut_velocity:
		body.velocity.y = jump_cut_velocity

	# Asymmetric gravity: snappier rise, heavier fall
	if body.velocity.y < 0.0:
		body.velocity.y -= gravity * fall_gravity_multiplier * delta
	else:
		body.velocity.y -= gravity * rise_gravity_multiplier * delta

	var move_dir: Vector3 = Vector3(intents.move_dir.x, 0, intents.move_dir.y).normalized()
	if move_dir != Vector3.ZERO:
		body.velocity.x = move_toward(body.velocity.x, move_dir.x * max_air_speed, air_acceleration * delta)
		body.velocity.z = move_toward(body.velocity.z, move_dir.z * max_air_speed, air_acceleration * delta)
	if _stamina:
		_stamina.recover(stamina_recover_per_sec * FALL_STAMINA_RECOVER_FRACTION * delta)

	body.move_and_slide()
