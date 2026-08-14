class_name ClimbMotor
extends BaseMotor

const MIN_DIR_LENGTH_SQUARED: float = 0.001  ## Minimum squared length to treat a direction as non-zero
const MIN_STICK_LENGTH_SQUARED: float = 0.001  ## Minimum squared length to apply wall-stick velocity

@export var climb_speed: float = 2.5
@export var stamina_cost_per_sec: float = 5.0
@export var wall_approach_speed: float = 0.5
@export var ledge_top_offset: float = 0.33  ## Distance below ledge top to cap climb position

func gather_proposals(current_mode: int, intents: Intents, services: Array[BaseService], stamina: StaminaComponent) -> Array[TransitionProposal]:
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	var exhausted: bool = false
	if stamina:
		exhausted = stamina.is_exhausted()
	if ledge == null or exhausted or not intents.wants_climb:
		return []
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	var on_floor: bool = ground != null and ground.is_on_floor()
	var climbing: bool = current_mode == LocomotionState.ID.CLIMB
	# Sticky-on-floor: at curved apexes (sphere/cylinder top) `is_on_floor()` is
	# true and the waist cast geometry flickers — without this clause, mode would
	# oscillate Climb↔Walk every frame, producing a yaw seizure.
	# We only treat as "near_apex" if on floor AND NOT hitting something at head level
	# (sensor-relative approach). The ledge_point check ensures we are actually
	# at a ledge and not just on flat ground.
	var facts: LedgeFacts = ledge.get_ledge_facts() if ledge else null
	var near_apex: bool = on_floor and facts and not facts.has_head_hit and facts.ledge_point != Vector3.ZERO

	if climbing and (near_apex or ledge.can_continue_climbing()):
		return [TransitionProposal.new(LocomotionState.ID.CLIMB, TransitionProposal.Priority.OPPORTUNISTIC, 5)]
	if not climbing and ledge.can_climb():
		return [TransitionProposal.new(LocomotionState.ID.CLIMB, TransitionProposal.Priority.PLAYER_REQUESTED, 5)]
	return []

func tick(delta: float, intents: Intents, body: CharacterBody3D, stamina: StaminaComponent, services: Array[BaseService]) -> void:
	var ledge: LedgeService = _get_service(services, LedgeService) as LedgeService
	var facts: LedgeFacts = ledge.get_ledge_facts() if ledge else null
	var climb_normal: Vector3 = ledge.get_climb_normal() if ledge else Vector3.ZERO

	if climb_normal == Vector3.ZERO:
		return

	# At the top of a curved surface (sphere/cylinder apex) the physics engine classifies
	# the contact as floor (normal ≈ UP), not wall. is_on_floor() is the authoritative
	# detector for this — it works regardless of which direction the waist cast happens to
	# point, unlike checking climb_normal (which reflects the cast hit point, not the body
	# contact). When near the apex, suppress the yaw snap and wall_stick entirely so the
	# player keeps the last stable orientation and can_continue_climbing() stays consistent.
	# We only treat as "near_apex" if on floor AND NOT hitting something at head level
	# (sensor-relative approach). The ledge_point check ensures we are actually
	# at a ledge and not just on flat ground.
	var ground: GroundService = _get_service(services, GroundService) as GroundService
	var on_floor: bool = ground.is_on_floor() if ground else body.is_on_floor()
	# NOTE: near_apex formula is duplicated in gather_proposals — G2 soft signal; do not extract helper at this scale.
	var near_apex: bool = on_floor and facts and not facts.has_head_hit and facts.ledge_point != Vector3.ZERO

	var touching_wall: bool = ledge.can_continue_climbing() if ledge else body.is_on_wall()

	if not near_apex:
		# Always flatten the facing direction to horizontal. On curved surfaces (sphere/
		# cylinder) the climb normal has a vertical component — feeding it raw to
		# Basis.looking_at tilts the body's Y axis to match the surface normal, which
		# combined with frame-to-frame is_on_wall() flicker at the apex produces the
		# "perpendicular to sphere ↔ perpendicular to floor" seizure.
		var face_dir: Vector3
		if not touching_wall:
			# Approaching: face toward actual wall contact point so subsequent casts keep hitting
			var wall_point: Vector3 = ledge.get_wall_point() if ledge else Vector3.ZERO
			face_dir = wall_point - body.global_position
		else:
			face_dir = -climb_normal
		face_dir.y = 0.0
		if face_dir.length_squared() > MIN_DIR_LENGTH_SQUARED:
			body.basis = Basis.looking_at(face_dir.normalized(), Vector3.UP)

	body.velocity.y = -intents.raw_input.y * climb_speed

	var lateral_input: float = intents.raw_input.x
	if ledge:
		if intents.is_climbing_right and not ledge.has_wall_right():
			lateral_input = 0.0
		elif intents.is_climbing_left and not ledge.has_wall_left():
			lateral_input = 0.0

	var right_dir: Vector3 = Vector3.UP.cross(climb_normal).normalized()
	var lateral_vel: Vector3 = right_dir * lateral_input * climb_speed

	var wall_stick: Vector3 = Vector3.ZERO
	if not near_apex and not touching_wall:
		# Pull toward actual collision point — correct for flat walls and curved cylinders
		var wall_point: Vector3 = ledge.get_wall_point() if ledge else Vector3.ZERO
		var to_wall: Vector3 = wall_point - body.global_position
		to_wall.y = 0.0
		if to_wall.length_squared() > MIN_STICK_LENGTH_SQUARED:
			wall_stick = to_wall.normalized() * wall_approach_speed

	body.velocity.x = lateral_vel.x + wall_stick.x
	body.velocity.z = lateral_vel.z + wall_stick.z

	if ledge:
		# Clipping to ledge height: soft limit at neck height.
		# This prevents climbing over the top and forces a Mantle transition.
		if facts.lip_height != -INF and body.velocity.y > 0:
			var feet_y: float = body.global_position.y - _get_body_half_height() # body_half_height
			var ledge_global_y: float = feet_y + facts.lip_height
			var max_y: float = ledge_global_y - ledge_top_offset
			
			if body.global_position.y >= max_y:
				body.velocity.y = 0.0
				body.global_position.y = max_y # Final micro-correction just in case of float drift
			else:
				var distance_to_top: float = max_y - body.global_position.y
				var max_safe_vel: float = distance_to_top / delta
				if body.velocity.y > max_safe_vel:
					body.velocity.y = max_safe_vel
				
	body.move_and_slide()

	if stamina:
		stamina.drain(stamina_cost_per_sec * delta)
