class_name StrikeMotor
extends BaseMotor

# — Configuration —
@export var dash_speed: float = 25.0              # Speed of the snap dash towards the target
@export var min_distance_to_target: float = 1.5   # Offset to prevent clipping into the target's collider
@export var max_dash_duration: float = 0.25       # Timeout security gate for the dash

## Le gana a Stairs/Ladder (FORCED 0) y WallJump (5) sin pasar a Mantle/
## EdgeLeap (10) ni AutoVault (20). Por qué ese rango: docs/movimiento.md.
const STRIKE_PRIORITY_WEIGHT: int = 8

## Red de seguridad: si la propuesta pierde el arbitraje de plano, tick()
## nunca corre y _active quedaría true para siempre (docs/movimiento.md).
## En frames y no en tiempo porque gather_proposals() no recibe delta.
const MAX_PENDING_FRAMES: int = 30

# — Internal state —
var _dash_target_position: Vector3 = Vector3.ZERO
var _dash_timer: float = 0.0
var _active: bool = false
var _target_node: Node3D = null
var _pending_frames: int = 0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

## Public initializer called by Combat Action
func start_strike_dash(target_node: Node3D, target_pos: Vector3) -> void:
	_target_node = target_node
	_dash_target_position = target_pos
	_dash_timer = 0.0
	_pending_frames = 0
	_active = true

func gather_proposals(_current_mode: int, _intents: Intents, _services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	if not _active:
		return []
	_pending_frames += 1
	if _pending_frames > MAX_PENDING_FRAMES:
		_active = false
		_target_node = null
		_pending_frames = 0
		return []
	return [TransitionProposal.new(LocomotionState.ID.STRIKE, TransitionProposal.Priority.FORCED, STRIKE_PRIORITY_WEIGHT)]

func tick(delta: float, _intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	if not _active:
		return
	_pending_frames = 0

	_dash_timer += delta
	var current_pos := body.global_position
	
	# Keep target position updated if target moves
	if _target_node and is_instance_valid(_target_node):
		var to_enemy := _target_node.global_position - current_pos
		var dist := to_enemy.length()
		if dist > min_distance_to_target:
			_dash_target_position = _target_node.global_position - to_enemy.normalized() * min_distance_to_target
		else:
			_dash_target_position = current_pos
			
	var to_target := _dash_target_position - current_pos
	var distance := to_target.length()
	
	# Stop dash if we are close enough or timer expires
	if distance < 0.25 or _dash_timer >= max_dash_duration:
		body.velocity = Vector3.ZERO
		_active = false
		_target_node = null
		return
		
	body.velocity = to_target.normalized() * dash_speed
	body.move_and_slide()
