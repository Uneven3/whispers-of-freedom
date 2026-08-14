class_name AutoVaultMotor
extends BaseMotor

const AUTO_VAULT_WEIGHT: int = 20
const MIN_VAULT_SPEED: float = 0.01
const MIN_VAULT_DURATION: float = 0.1

@export var vault_speed: float = 5.0
@export var vault_arc_height: float = 0.4

enum Phase { INACTIVE, ACTIVATING, RUNNING }
var _phase: Phase = Phase.INACTIVE
var _elapsed: float = 0.0
var _duration: float = MIN_VAULT_DURATION
var _start_position: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	# Sticky state: if we are already vaulting, we MUST continue until tick() finishes.
	if current_mode == LocomotionState.ID.AUTO_VAULT and (_phase == Phase.RUNNING or _phase == Phase.ACTIVATING):
		return [TransitionProposal.new(LocomotionState.ID.AUTO_VAULT, TransitionProposal.Priority.FORCED, AUTO_VAULT_WEIGHT)]
	
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	
	if ground != null and ground.is_on_floor() and ledge != null:
		var facts: LedgeFacts = ledge.get_ledge_facts()
		# Auto-vault triggers if we press the vault key while facing a vaultable object
		if facts.is_vaultable and intents.wants_vault:
			return [TransitionProposal.new(LocomotionState.ID.AUTO_VAULT, TransitionProposal.Priority.PLAYER_REQUESTED, AUTO_VAULT_WEIGHT)]
	
	return []

func on_activate(_body: CharacterBody3D) -> void:
	_phase = Phase.ACTIVATING
	_elapsed = 0.0

func on_deactivate(_body: CharacterBody3D) -> void:
	_phase = Phase.INACTIVE
	_elapsed = 0.0

func tick(delta: float, _intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, services: Array[BaseService]) -> void:
	if _phase == Phase.ACTIVATING:
		_phase = Phase.INACTIVE
		
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	
	if _phase != Phase.RUNNING and not _begin_vault(body, ledge):
		# Fallback if vault cannot start
		_phase = Phase.INACTIVE
		return

	_elapsed = minf(_elapsed + delta, _duration)
	var raw_progress: float = _elapsed / _duration
	# Quadratic ease-in-out for smooth movement
	var eased_progress: float = smoothstep(0.0, 1.0, raw_progress)
	
	var next_position: Vector3 = _start_position.lerp(_target_position, eased_progress)
	# Add arc height
	next_position.y += sin(raw_progress * PI) * vault_arc_height

	body.global_position = next_position
	body.velocity = Vector3.ZERO
	# Move and slide handles collisions during the lerp if we hit something unexpected
	body.move_and_slide()

	if raw_progress >= 1.0:
		body.global_position = _target_position
		_phase = Phase.INACTIVE

func _begin_vault(body: CharacterBody3D, ledge: LedgeService) -> bool:
	if ledge == null:
		return false
	
	var facts: LedgeFacts = ledge.get_ledge_facts()
	if facts.vault_target_position == Vector3.ZERO:
		return false

	_start_position = body.global_position
	_target_position = facts.vault_target_position

	var distance: float = _start_position.distance_to(_target_position)
	_duration = maxf(distance / maxf(vault_speed, MIN_VAULT_SPEED), MIN_VAULT_DURATION)
	_elapsed = 0.0
	_phase = Phase.RUNNING
	return true
