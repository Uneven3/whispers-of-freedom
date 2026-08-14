class_name EdgeLeapMotor
extends BaseMotor

## Motor for leaping away from the edge of a wall while climbing.
## Triggered by pressing a lateral direction + jump at the edge of a wall.

@export var leap_away_impulse: float = 8.0
@export var vertical_boost: float = 2.0
@export var stamina_cost: float = 10.0

var _is_leaping: bool = false
var _leap_timer: float = 0.0
var _needs_release: bool = false
const LEAP_DURATION: float = 0.3
const FORCED_WEIGHT: int = 10
const WALL_PUSH_SPEED: float = 2.0

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], stamina: StaminaComponent) -> Array[TransitionProposal]:
	if not intents.wants_jump:
		_needs_release = false

	# Only propose from CLIMB when at an edge and jumping laterally
	if current_mode == LocomotionState.ID.CLIMB and intents.wants_jump and not _needs_release:
		var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
		if ledge:
			var facts: LedgeFacts = ledge.get_ledge_facts()
			
			var jumping_left: bool = intents.is_climbing_left
			var jumping_right: bool = intents.is_climbing_right
			
			var at_left_edge: bool = jumping_left and not facts.has_wall_left
			var at_right_edge: bool = jumping_right and not facts.has_wall_right
			
			if (at_left_edge or at_right_edge) and (stamina == null or not stamina.is_exhausted()):
				_needs_release = true
				return [TransitionProposal.new(LocomotionState.ID.EDGE_LEAP, TransitionProposal.Priority.FORCED, FORCED_WEIGHT)]

	# Sticky state during the leap animation/movement
	if current_mode == LocomotionState.ID.EDGE_LEAP and _is_leaping:
		return [TransitionProposal.new(LocomotionState.ID.EDGE_LEAP, TransitionProposal.Priority.FORCED, FORCED_WEIGHT)]
		
	return []

func on_activate(_body: CharacterBody3D) -> void:
	_is_leaping = true
	_leap_timer = LEAP_DURATION

func on_deactivate(_body: CharacterBody3D) -> void:
	_is_leaping = false

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, services: Array[BaseService]) -> void:
	# Initial impulse
	if _leap_timer == LEAP_DURATION:
		var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
		var normal: Vector3 = ledge.get_climb_normal() if ledge else -body.get_wall_normal()
		if normal == Vector3.ZERO:
			normal = body.basis.z
			
		var right_dir: Vector3 = Vector3.UP.cross(normal).normalized()
		
		var jump_dir: Vector3 = Vector3.ZERO
		if intents.is_climbing_left:
			jump_dir = -right_dir
		elif intents.is_climbing_right:
			jump_dir = right_dir
		else:
			# Fallback if somehow triggered without lateral intent
			jump_dir = normal
			
		# Impulse: Lateral push + small push away from wall + vertical boost
		body.velocity = (jump_dir * leap_away_impulse) + (normal * WALL_PUSH_SPEED) + (Vector3.UP * vertical_boost)
		
		if stamina:
			stamina.drain(stamina_cost)

	_leap_timer -= delta
	
	# Simple physics during the short leap window
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	body.velocity.y -= gravity * delta
	
	body.move_and_slide()
	
	if _leap_timer <= 0 or body.is_on_floor():
		_is_leaping = false
