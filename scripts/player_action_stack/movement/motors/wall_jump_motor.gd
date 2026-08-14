class_name WallJumpMotor
extends BaseMotor

@export var jump_up_impulse: float = 7.0
@export var jump_away_impulse: float = 6.0
@export var away_push_force: float = 7.0
@export var stamina_cost: float = 15.0
@export var ledge_top_offset: float = 0.33

var _is_jumping: bool = false
var _jump_timer: float = 0.0
var _needs_release: bool = false
const JUMP_DURATION: float = 0.2
const WALL_CONTACT_PUSH: float = 1.0
const AWAY_UP_BLEND: float = 0.4
const AWAY_LEAP_SPEED: float = 3.5
const AWAY_NORMAL_PUSH: float = 4.0
const LATERAL_SPEED_FRACTION: float = 0.8
const LATERAL_VERTICAL_LIFT: float = 0.5
const LATERAL_NORMAL_RETRACTION: float = 0.5
const FORCED_WEIGHT: int = 5

func gather_proposals(current_mode: int, intents: Intents, _services: Array[BaseService], stamina: StaminaComponent) -> Array[TransitionProposal]:
	if not intents.wants_jump:
		_needs_release = false

	if current_mode == LocomotionState.ID.CLIMB and intents.wants_jump and not _needs_release:
		if stamina and not stamina.is_exhausted():
			_needs_release = true
			return [TransitionProposal.new(LocomotionState.ID.WALL_JUMP, TransitionProposal.Priority.FORCED, FORCED_WEIGHT)]

	if current_mode == LocomotionState.ID.WALL_JUMP and _is_jumping:
		return [TransitionProposal.new(LocomotionState.ID.WALL_JUMP, TransitionProposal.Priority.FORCED, FORCED_WEIGHT)]

	return []

func on_activate(_body: CharacterBody3D) -> void:
	_is_jumping = true
	_jump_timer = JUMP_DURATION

func on_deactivate(_body: CharacterBody3D) -> void:
	_is_jumping = false

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, services: Array[BaseService]) -> void:
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	
	# Apply impulse on the first tick of the state
	if _jump_timer == JUMP_DURATION:
		var normal: Vector3 = ledge.get_climb_normal() if ledge else Vector3.ZERO
		
		if normal == Vector3.ZERO:
			normal = -body.get_wall_normal() if body.is_on_wall() else body.basis.z
		
		var right_dir: Vector3 = Vector3.UP.cross(normal).normalized()
		
		if intents.is_climbing_up: # Jumping UP
			body.velocity = Vector3.UP * jump_up_impulse
			body.velocity -= normal * WALL_CONTACT_PUSH # Keep contact
		elif intents.is_climbing_down: # Jumping AWAY (S)
			var away_dir: Vector3 = (normal + Vector3.UP * AWAY_UP_BLEND).normalized()
			body.velocity = away_dir * AWAY_LEAP_SPEED + normal * AWAY_NORMAL_PUSH
		elif intents.is_climbing_left: # Jumping LEFT (A)
			var left_jump_dir: Vector3 = -right_dir
			body.velocity = left_jump_dir * (jump_up_impulse * LATERAL_SPEED_FRACTION)
			body.velocity.y = LATERAL_VERTICAL_LIFT # Minimal vertical
			body.velocity -= normal * LATERAL_NORMAL_RETRACTION
		elif intents.is_climbing_right: # Jumping RIGHT (D)
			var right_jump_dir: Vector3 = right_dir
			body.velocity = right_jump_dir * (jump_up_impulse * LATERAL_SPEED_FRACTION)
			body.velocity.y = LATERAL_VERTICAL_LIFT # Minimal vertical
			body.velocity -= normal * LATERAL_NORMAL_RETRACTION
		else: # Jumping AWAY (Neutral)
			var away_dir: Vector3 = (normal + Vector3.UP * AWAY_UP_BLEND).normalized()
			body.velocity = away_dir * AWAY_LEAP_SPEED + normal * AWAY_NORMAL_PUSH
			
		if stamina:
			stamina.drain(stamina_cost)
	
	_jump_timer -= delta
	
	# Clipping to ledge height
	if ledge:
		var facts: LedgeFacts = ledge.get_ledge_facts()
		if facts.lip_height != -INF and body.velocity.y > 0:
			var feet_y: float = body.global_position.y - _get_body_half_height() # body_half_height
			var ledge_global_y: float = feet_y + facts.lip_height
			var max_y: float = ledge_global_y - ledge_top_offset # ledge_top_offset
			if body.global_position.y >= max_y:
				body.global_position.y = max_y
				body.velocity.y = 0
				_is_jumping = false
				
	body.move_and_slide()
			
	if _jump_timer <= 0:
		_is_jumping = false
