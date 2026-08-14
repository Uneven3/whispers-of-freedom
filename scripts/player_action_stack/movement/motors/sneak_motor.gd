class_name SneakMotor
extends BaseMotor

@export var max_speed: float = 2.5
@export var acceleration: float = 15.0
@export var friction: float = 20.0

@export var crouch_height: float = 1.2
@export var crouch_y_offset: float = -0.4

var _original_height: float = 2.0
var _original_y_pos: float = 0.0

const MOVE_DIR_THRESHOLD_SQ: float = 0.01
const ROTATION_SLERP_SPEED: float = 10.0
const SNEAK_STAMINA_RECOVER_RATE: float = 5.0

func gather_proposals(_current_mode: int, intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	if ground != null and ground.is_on_floor() and intents.wants_sneak:
		return [TransitionProposal.new(LocomotionState.ID.SNEAK, TransitionProposal.Priority.PLAYER_REQUESTED, 1)] # state SNEAK, override Walk
	return []

func on_activate(body: CharacterBody3D) -> void:
	var shape_node: CollisionShape3D = body.get_node("CollisionShape3D")
	if shape_node and shape_node.shape is CapsuleShape3D:
		# Make the shape unique to this instance to avoid affecting others
		shape_node.shape = shape_node.shape.duplicate()
		_original_height = shape_node.shape.height
		shape_node.shape.height = crouch_height
		_original_y_pos = shape_node.position.y
		shape_node.position.y = crouch_y_offset

func on_deactivate(body: CharacterBody3D) -> void:
	var shape_node: CollisionShape3D = body.get_node("CollisionShape3D")
	if shape_node and shape_node.shape is CapsuleShape3D:
		shape_node.shape.height = _original_height
		shape_node.position.y = _original_y_pos

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	apply_locomotion_rotation(body, intents, delta)
	var move_dir: Vector3 = Vector3(intents.move_dir.x, 0, intents.move_dir.y).normalized()
	
	if move_dir != Vector3.ZERO:
		body.velocity.x = move_toward(body.velocity.x, move_dir.x * max_speed, acceleration * delta)
		body.velocity.z = move_toward(body.velocity.z, move_dir.z * max_speed, acceleration * delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0, friction * delta)
		body.velocity.z = move_toward(body.velocity.z, 0, friction * delta)
		
	body.velocity.y = 0.0 # Stay grounded
	
	# Rotate body to face movement (duplicated from broker but sneak might want custom rotation speed)
	if move_dir.length_squared() > MOVE_DIR_THRESHOLD_SQ:
		var target_basis: Basis = Basis.looking_at(move_dir, Vector3.UP)
		body.basis = body.basis.slerp(target_basis, ROTATION_SLERP_SPEED * delta)

	if stamina:
		stamina.recover(SNEAK_STAMINA_RECOVER_RATE * delta) # Sneaking is restful

	body.move_and_slide()
