class_name LadderMotor
extends BaseMotor

@export var climb_speed: float = 2.5
@export var snap_lerp: float = 12.0     ## How fast body locks to ladder X/Z anchor
@export var top_exit_bump: float = 3.0  ## Upward velocity injected when stepping off the top

const MOVE_DIR_THRESHOLD_SQ: float = 0.01
const LADDER_TOP_EXIT_CLEARANCE: float = 0.1

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ladder_svc: LadderService = _get_service(services, LadderService) as LadderService
	if ladder_svc == null or not ladder_svc.is_on_ladder():
		return []
	## Latch on once entered; release only when player jumps or leaves the area.
	if current_mode == LocomotionState.ID.LADDER or intents.move_dir.length_squared() > MOVE_DIR_THRESHOLD_SQ or intents.wants_climb:
		return [TransitionProposal.new(LocomotionState.ID.LADDER, TransitionProposal.Priority.FORCED)]
	return []

func tick(delta: float, intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, services: Array[BaseService]) -> void:
	var ladder_svc: LadderService = _get_service(services, LadderService) as LadderService
	var ladder: Ladder = ladder_svc.get_active_ladder() if ladder_svc else null
	if ladder == null:
		return

	## raw_input.y is +1 when pressing back, -1 when pressing forward (player_brain → Input.get_vector axis convention).
	## Forward press → negative y → body.velocity.y positive (ascending).
	body.velocity.y = -intents.raw_input.y * climb_speed
	body.velocity.x = 0.0
	body.velocity.z = 0.0

	## Smoothly snap X/Z to the ladder's bottom anchor so the body stays on the rail.
	var anchor: Vector2 = ladder.get_anchor_xz()
	body.global_position.x = lerp(body.global_position.x, anchor.x, snap_lerp * delta)
	body.global_position.z = lerp(body.global_position.z, anchor.y, snap_lerp * delta)

	## Auto-exit at top: if player is near the top and still pressing forward, give a small
	## upward bump so they step onto the landing instead of capping at the ladder top.
	if body.global_position.y >= ladder.get_top_y() - LADDER_TOP_EXIT_CLEARANCE and intents.raw_input.y < 0.0:
		body.velocity.y = top_exit_bump
		
	body.move_and_slide()
