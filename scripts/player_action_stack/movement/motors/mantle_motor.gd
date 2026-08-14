class_name MantleMotor
extends BaseMotor

const MANTLE_PRIORITY_WEIGHT: int = 10
const MIN_MANTLE_SPEED: float = 0.01
const MIN_MANTLE_DURATION: float = 0.08

@export var min_mantle_height: float = 1.4
@export var mantle_vertical_speed: float = 4.0
@export var mantle_forward_speed: float = 3.0
@export var mantle_arc_height: float = 0.25

enum Phase { INACTIVE, ACTIVATING, RUNNING }
var _phase: Phase = Phase.INACTIVE
var _needs_mantle_release: bool = false
var _elapsed: float = 0.0
var _duration: float = MIN_MANTLE_DURATION
var _start_position: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	if not intents.wants_mantle:
		_needs_mantle_release = false

	# Sticky state: if we are already mantling, we MUST continue until tick() finishes.
	# The ACTIVATING phase ensures we hold the state during the one-frame window
	# before RUNNING is set in the first tick().
	if current_mode == LocomotionState.ID.MANTLE and (_phase == Phase.RUNNING or _phase == Phase.ACTIVATING):
		return [TransitionProposal.new(LocomotionState.ID.MANTLE, TransitionProposal.Priority.FORCED, MANTLE_PRIORITY_WEIGHT)]

	if _needs_mantle_release:
		return []

	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	if ledge != null:
		var is_climbing: bool = current_mode == LocomotionState.ID.CLIMB
		var is_wall_jumping: bool = current_mode == LocomotionState.ID.WALL_JUMP
		
		# Context restriction: Mantle only from climb or while wall jumping
		if not (is_climbing or is_wall_jumping):
			return []
			
		var facts: LedgeFacts = ledge.get_ledge_facts()
		var at_edge: bool = facts.is_at_mantle_edge
		# Re-introduce height threshold with tolerance for climb ceiling clip (1.33m).
		# This prevents mantling lower walls.
		var tall_enough: bool = facts.lip_height >= 1.2
		
		if at_edge and tall_enough:
			var requesting: bool = intents.wants_mantle
			if requesting or (is_wall_jumping and intents.is_climbing_up):
				# FORCED (3) weight 10 beats:
				# - Climb sticky state (OPPORTUNISTIC 2)
				# - WallJump sticky state (FORCED 3, weight 5)
				return [TransitionProposal.new(LocomotionState.ID.MANTLE, TransitionProposal.Priority.FORCED, MANTLE_PRIORITY_WEIGHT)]
	return []

func tick(delta: float, _intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, services: Array[BaseService]) -> void:
	if _phase == Phase.ACTIVATING:
		_phase = Phase.INACTIVE
		
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	if _phase != Phase.RUNNING and not _begin_mantle(body, ledge):
		body.velocity = Vector3.ZERO
		body.move_and_slide()
		return

	_elapsed = minf(_elapsed + delta, _duration)
	var raw_progress: float = _elapsed / _duration
	var eased_progress: float = smoothstep(0.0, 1.0, raw_progress)
	var next_position: Vector3 = _start_position.lerp(_target_position, eased_progress)
	next_position.y += sin(raw_progress * PI) * mantle_arc_height

	body.global_position = next_position
	body.velocity = Vector3.ZERO
	body.move_and_slide()

	if raw_progress >= 1.0:
		body.global_position = _target_position
		_phase = Phase.INACTIVE

func on_activate(_body: CharacterBody3D) -> void:
	_phase = Phase.ACTIVATING
	_needs_mantle_release = true # Lock input now that we successfully started
	_elapsed = 0.0

func on_deactivate(_body: CharacterBody3D) -> void:
	_phase = Phase.INACTIVE
	_elapsed = 0.0

func _begin_mantle(body: CharacterBody3D, ledge: LedgeService) -> bool:
	if ledge == null:
		return false
	
	var facts: LedgeFacts = ledge.get_ledge_facts()
	if facts.target_position == Vector3.ZERO:
		return false

	_start_position = body.global_position
	_target_position = facts.target_position

	var vertical_distance: float = absf(_target_position.y - _start_position.y)
	var horizontal_start: Vector2 = Vector2(_start_position.x, _start_position.z)
	var horizontal_target: Vector2 = Vector2(_target_position.x, _target_position.z)
	var horizontal_distance: float = horizontal_start.distance_to(horizontal_target)
	var vertical_duration: float = vertical_distance / maxf(mantle_vertical_speed, MIN_MANTLE_SPEED)
	var horizontal_duration: float = horizontal_distance / maxf(mantle_forward_speed, MIN_MANTLE_SPEED)

	_duration = maxf(maxf(vertical_duration, horizontal_duration), MIN_MANTLE_DURATION)
	_elapsed = 0.0
	_phase = Phase.RUNNING
	return true
