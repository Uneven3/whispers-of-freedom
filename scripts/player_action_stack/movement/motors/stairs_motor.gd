class_name StairsMotor
extends BaseMotor

const INPUT_THRESHOLD_SQ := 0.01

## La geometría del cuerpo sale del BodyReader (SSoT), no de un @export.
@export var lookahead_margin: float = 0.1
@export var descend_trail_offset: float = 0.01  ## descend_trail = body_radius - this

@export var ascend_speed: float = 3.5  ## Más lento que walk_speed (5.0)
@export var descend_speed: float = 4.5
@export var sprint_multiplier: float = 1.7
@export var sprint_stamina_cost_per_sec: float = 10.0
@export var lateral_factor: float = 0.6
@export var acceleration: float = 80.0
@export var friction: float = 60.0  ## Alta, o la bajada se siente resbalosa
@export var snap_epsilon: float = 0.08  ## Muy chico (0,02) engancha la esquina al esprintar

@export var ground_tolerance: float = 0.15
## Tiene que ser < step_rise (0,25) o alcanza el escalón anterior y deshace
## el snap-up: esa era la causa del atasco al esprintar.
@export var stairs_floor_snap_length: float = 0.20

var _saved_floor_snap_length: float = 0.0

func on_activate(body: CharacterBody3D) -> void:
	_saved_floor_snap_length = body.floor_snap_length
	body.floor_snap_length = stairs_floor_snap_length

func on_deactivate(body: CharacterBody3D) -> void:
	body.floor_snap_length = _saved_floor_snap_length

func gather_proposals(current_mode: int, _intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var stairs: StairsService = _get_service(services, StairsService) as StairsService
	if stairs == null or not stairs.is_on_stairs():
		return []
	# Pegajoso: is_on_floor() parpadea en false tras un snap-up y sin esto la
	# subida cae a Fall (docs/movimiento.md, "Escaleras").
	if current_mode == LocomotionState.ID.STAIRS:
		return [TransitionProposal.new(LocomotionState.ID.STAIRS, TransitionProposal.Priority.FORCED)]
	# La entrada inicial sí exige estar apoyado, o la gravedad se suprime en el aire.
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	if ground == null or not ground.is_on_floor():
		return []
	return [TransitionProposal.new(LocomotionState.ID.STAIRS, TransitionProposal.Priority.FORCED)]

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, intents, delta)
	var stairs: StairsService = _get_service(services, StairsService) as StairsService
	var stair: Stairs = stairs.get_active_stair() if stairs else null
	if stair == null:
		return

	var slope_axis: Vector3 = stair.get_slope_horizontal_axis()
	var lateral_axis: Vector3 = Vector3.UP.cross(slope_axis).normalized()

	var world_input: Vector3 = Vector3(intents.move_dir.x, 0.0, intents.move_dir.y)
	var input_along_slope: float = world_input.dot(slope_axis)
	var input_across_slope: float = world_input.dot(lateral_axis)

	# SprintMotor se abstiene en escaleras, así que wants_sprint se honra acá.
	var stamina_available: bool = stamina != null and stamina.get_current() > 0.0
	var sprinting: bool = intents.wants_sprint and stamina_available
	var base_speed: float = ascend_speed if input_along_slope >= 0.0 else descend_speed
	var speed: float = base_speed * sprint_multiplier if sprinting else base_speed
	var target_horizontal_velocity: Vector3 = slope_axis * input_along_slope * speed + lateral_axis * input_across_slope * speed * lateral_factor

	var has_directional_input: bool = world_input.length_squared() > INPUT_THRESHOLD_SQ
	var accel_rate: float = acceleration if has_directional_input else friction
	body.velocity.x = move_toward(body.velocity.x, target_horizontal_velocity.x, accel_rate * delta)
	body.velocity.z = move_toward(body.velocity.z, target_horizontal_velocity.z, accel_rate * delta)

	if sprinting and stamina:
		stamina.drain(sprint_stamina_cost_per_sec * delta)

	# El punto de muestreo depende de la dirección, y la distancia está
	# calibrada al radio de la cápsula (docs/movimiento.md, "Escaleras").
	const ASCEND_THRESHOLD := 0.3
	const DESCEND_THRESHOLD := -0.3
	var body_radius: float = _get_body_radius()
	var body_half_height: float = _get_body_half_height()
	var sample_offset: Vector3 = Vector3.ZERO
	if input_along_slope > ASCEND_THRESHOLD:
		sample_offset = slope_axis * (body_radius + lookahead_margin)
	elif input_along_slope < DESCEND_THRESHOLD:
		sample_offset = slope_axis * (body_radius - descend_trail_offset)
	var sample_pos: Vector3 = body.global_position + sample_offset
	var expected_feet_y: float = stair.compute_expected_feet_y(sample_pos)
	var current_feet_y: float = body.global_position.y - body_half_height

	# Cota inferior y gate direccional, los dos hacen falta: sin la primera,
	# caminar contra el COSTADO teletransporta el cuerpo escalones arriba.
	var feet_gap: float = expected_feet_y - current_feet_y
	var max_snap: float = stair.step_rise + ground_tolerance
	if input_along_slope > ASCEND_THRESHOLD and feet_gap > 0.0 and feet_gap <= max_snap:
		body.global_position.y = expected_feet_y + body_half_height + snap_epsilon
		body.velocity.y = 0.0
	elif input_along_slope < DESCEND_THRESHOLD and feet_gap < 0.0 and feet_gap >= -max_snap:
		body.global_position.y = expected_feet_y + body_half_height + snap_epsilon
		body.velocity.y = 0.0
	elif feet_gap < -max_snap:
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		body.velocity.y -= gravity * delta
	else:
		body.velocity.y = 0.0

	body.move_and_slide()
