class_name StairsMotor
extends BaseMotor

const INPUT_THRESHOLD_SQ := 0.01  ## Minimum length-squared of world input to count as intentional movement

## Body geometry is read from the entity's CollisionShape3D via the BodyReader
## (SSoT) — no per-motor @export. lookahead_margin / descend_trail tune how far
## the per-step sample trails the body front and are body-agnostic offsets.
@export var lookahead_margin: float = 0.1
@export var descend_trail_offset: float = 0.01  ## descend_trail = body_radius - this

@export var ascend_speed: float = 3.5    ## Slower than walk_speed (5.0) — feels deliberate
@export var descend_speed: float = 4.5
@export var sprint_multiplier: float = 1.7  ## Speed boost when wants_sprint and stamina > 0
@export var sprint_stamina_cost_per_sec: float = 10.0
@export var lateral_factor: float = 0.6  ## Strafe across stairs at 60% of slope speed
@export var acceleration: float = 80.0   ## Ramp-up — high so landing on a step recovers velocity in a few frames
@export var friction: float = 60.0       ## Stop — high so descent doesn't feel slippery
@export var snap_epsilon: float = 0.08   ## Lift body above tread to clear the upper corner — too small (e.g., 0.02) lets sprint-speed ascents catch on the corner

@export var ground_tolerance: float = 0.15  ## Max distance above expected tread to count as grounded on stairs
@export var stairs_floor_snap_length: float = 0.20  ## Floor snap while on stairs — must be < step_rise (0.25) so it pins the current tread (0.08 m below) without yanking back to the previous tread (0.33 m below) after a snap-up

var _saved_floor_snap_length: float = 0.0

## Shrink Godot's floor snap on stairs. Default 0.4 reaches back to the previous tread
## (0.33 m below) and undoes the per-tick snap-up — the sprint-stall cause. 0.20 still
## pins the body to the current tread (only 0.08 m below) so is_on_floor() stays true
## and walking is uninterrupted.
func on_activate(body: CharacterBody3D) -> void:
	_saved_floor_snap_length = body.floor_snap_length
	body.floor_snap_length = stairs_floor_snap_length

func on_deactivate(body: CharacterBody3D) -> void:
	body.floor_snap_length = _saved_floor_snap_length

func gather_proposals(current_mode: int, _intents: Intents, services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	var stairs: StairsService = _get_service(services, StairsService) as StairsService
	if stairs == null or not stairs.is_on_stairs():
		return []
	## Sticky mode: once active (mode 8), stay active as long as the Area3D reports
	## on-stairs — even if is_on_floor() flickers false for a frame after a snap-up.
	## Without this, the climb drops to Fall whenever the body's center is briefly
	## off the previous tread but not yet over the next, causing sprint stalls.
	if current_mode == LocomotionState.ID.STAIRS:
		return [TransitionProposal.new(LocomotionState.ID.STAIRS, TransitionProposal.Priority.FORCED)]
	## Initial entry requires being grounded — airborne players stay in Fall until
	## they land on a tread, otherwise gravity gets suppressed mid-air.
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

	var horiz_axis: Vector3 = stair.get_slope_horizontal_axis()
	var lateral_axis: Vector3 = Vector3.UP.cross(horiz_axis).normalized()

	## intents.move_dir is already world-space (player_brain.gd:32) — camera yaw applied there.
	var world_input: Vector3 = Vector3(intents.move_dir.x, 0.0, intents.move_dir.y)
	var along: float = world_input.dot(horiz_axis)
	var lateral: float = world_input.dot(lateral_axis)

	## Sprint while climbing if held + stamina available. SprintMotor abstains on stairs,
	## so we honor wants_sprint here directly to keep the climb continuous.
	var stamina_available: bool = stamina != null and stamina.get_current() > 0.0
	var sprinting: bool = intents.wants_sprint and stamina_available
	var base_speed: float = ascend_speed if along >= 0.0 else descend_speed
	var speed: float = base_speed * sprint_multiplier if sprinting else base_speed
	var target_h: Vector3 = horiz_axis * along * speed + lateral_axis * lateral * speed * lateral_factor

	## Higher decel than accel — kills the slippery feel on descent when input releases.
	var has_input: bool = world_input.length_squared() > INPUT_THRESHOLD_SQ
	var rate: float = acceleration if has_input else friction
	body.velocity.x = move_toward(body.velocity.x, target_h.x, rate * delta)
	body.velocity.z = move_toward(body.velocity.z, target_h.z, rate * delta)

	if sprinting and stamina:
		stamina.drain(sprint_stamina_cost_per_sec * delta)

	## Per-step Y-snap. Sample position depends on motion direction:
	##   ascent  → leading edge + margin (lift body over next riser before capsule front hits it)
	##   descent → trailing edge just inside upper tread (drop only when capsule fully clears it,
	##             otherwise the rear half of the capsule embeds into the upper tread's box)
	##   lateral → body center (no snap will fire, but sampling here is harmless)
	const ASCEND_THRESHOLD := 0.3
	const DESCEND_THRESHOLD := -0.3
	var slope_input: float = world_input.dot(horiz_axis)
	var body_radius: float = _get_body_radius()
	var body_half_height: float = _get_body_half_height()
	var look_ahead: Vector3 = Vector3.ZERO
	if slope_input > ASCEND_THRESHOLD:
		look_ahead = horiz_axis * (body_radius + lookahead_margin)
	elif slope_input < DESCEND_THRESHOLD:
		look_ahead = horiz_axis * (body_radius - descend_trail_offset)
	var sample_pos: Vector3 = body.global_position + look_ahead
	## Snap to whichever tread the lookahead point lies on — no per-frame clamp.
	## The lookahead distance is matched to the capsule radius so the sample
	## naturally tracks the front of the body, never overshooting; clamping to
	## one tread/frame caused sprint-speed climbs to leave the leading capsule
	## sphere embedded in the next tread's box, which move_and_slide resolves
	## by killing horizontal velocity (the "clash" while sprinting).
	var expected_feet_y: float = stair.compute_expected_feet_y(sample_pos)
	var current_feet_y: float = body.global_position.y - body_half_height

	## Only snap up (and zero out gravity) when the body is genuinely on the stair geometry —
	## within one step's rise of the expected tread, both above and below. Without the lower
	## bound, walking into the SIDE of the staircase from the floor would teleport the body
	## up to neck-height steps because the Area3D trigger encloses the whole staircase.
	##
	## Snap is gated by clear directional intent (|slope_input| > 0.3). Pure lateral motion
	## along a tread is left to floor_snap_length — without this gate, tiny along-slope
	## drift while strafing crosses tread boundaries and bobs the body up/down by step_rise.
	var feet_gap: float = expected_feet_y - current_feet_y
	var max_snap: float = stair.step_rise + ground_tolerance
	if slope_input > ASCEND_THRESHOLD and feet_gap > 0.0 and feet_gap <= max_snap:
		## Climbing intent + reachable next tread — lift body over the riser.
		body.global_position.y = expected_feet_y + body_half_height + snap_epsilon
		body.velocity.y = 0.0
	elif slope_input < DESCEND_THRESHOLD and feet_gap < 0.0 and feet_gap >= -max_snap:
		## Descending intent + reachable next tread down — drop body to it. Without this,
		## the body floats off the upper tread and only falls under gravity once its center
		## drifts onto the lower tread, producing the parallel-floaty-fall feel.
		body.global_position.y = expected_feet_y + body_half_height + snap_epsilon
		body.velocity.y = 0.0
	elif feet_gap < -max_snap:
		## Body more than one step above the expected tread — too far to snap. Apply gravity
		## (e.g., jumped above the stairs from outside, or stepped off into a void).
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		body.velocity.y -= gravity * delta
	else:
		## Lateral / idle / on-tread / small gap — floor_snap_length holds Y.
		body.velocity.y = 0.0

	body.move_and_slide()
