extends "res://addons/gut/test.gd"

const CombatBrokerScript = preload("res://scripts/player_action_stack/combat/combat_broker.gd")
const BowActionScript = preload("res://scripts/player_action_stack/combat/bow_action.gd")
const ParryActionScript = preload("res://scripts/player_action_stack/combat/parry_counter_action.gd")
const TakedownActionScript = preload("res://scripts/player_action_stack/combat/takedown_action.gd")
const StrikeActionScript = preload("res://scripts/player_action_stack/combat/strike_action.gd")
const HitPauseScript = preload("res://scripts/player_action_stack/combat/hit_pause_component.gd")
const CombatDummyScript = preload("res://scripts/world/combat_dummy.gd")
const StrikeMotorScript = preload("res://scripts/player_action_stack/movement/motors/strike_motor.gd")
const MovementBrokerScript = preload("res://scripts/player_action_stack/movement/movement_broker.gd")
const StaminaComponentScript = preload("res://scripts/player_action_stack/movement/stamina_component.gd")

class MockMovementBroker extends MovementBroker:
	var mock_reader: BodyReader
	var active_mode: int = 3 # ID.FALL

	func _ready():
		pass

	func get_body_reader() -> BodyReader:
		return mock_reader

	func get_current_mode() -> int:
		return active_mode

	func inject_forced_proposal(proposal: TransitionProposal) -> void:
		active_mode = proposal.target_state

func _make_broker(stamina: Node = null) -> Array:
	var root := Node3D.new()

	var body := CharacterBody3D.new()
	root.add_child(body)

	var movement_broker := MockMovementBroker.new()
	movement_broker.mock_reader = BodyReader.new(body)
	root.add_child(movement_broker)

	var strike_motor := StrikeMotorScript.new()
	strike_motor.name = "StrikeMotor"
	movement_broker.add_child(strike_motor)
	movement_broker._motors[14] = strike_motor

	var broker: Node = CombatBrokerScript.new()
	broker.name = "CombatBroker"
	root.add_child(broker)

	var bow: Node = BowActionScript.new()
	bow.name = "BowAction"
	broker.add_child(bow)
	var parry: Node = ParryActionScript.new()
	parry.name = "ParryCounterAction"
	broker.add_child(parry)
	var takedown: Node = TakedownActionScript.new()
	takedown.name = "TakedownAction"
	broker.add_child(takedown)
	var strike: Node = StrikeActionScript.new()
	strike.name = "StrikeAction"
	broker.add_child(strike)
	var hit_pause: Node = HitPauseScript.new()
	hit_pause.name = "HitPauseComponent"
	broker.add_child(hit_pause)

	broker.configure(BodyReader.new(body), stamina, root, movement_broker)
	add_child_autofree(root)

	return [root, body, broker, movement_broker, strike_motor]

func test_aim_sets_aiming_state():
	var setup := _make_broker()
	var broker: Node = setup[2]
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_archery_aim = true

	broker.tick(intents, 0.016)

	assert_true(broker.is_aiming())
	assert_eq(broker.get_combat_state(), &"bow_drawn")

func test_aiming_suppresses_strike_on_the_same_frame():
	# Regression: wants_archery_release is partly derived from wants_attack
	# (releasing the bow is "attack while aiming"), so ticking every action
	# unconditionally would also fire a melee strike on a bow release.
	var setup := _make_broker()
	var broker: Node = setup[2]
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_archery_aim = true
	intents.wants_attack = true
	intents.wants_archery_release = true
	intents.aim_direction = Vector3.FORWARD

	broker.tick(intents, 0.016)

	assert_eq(broker.get_combat_state(), &"bow_release", "bow should fire, not a melee strike")

func test_parry_hits_vulnerable_dummy():
	var setup := _make_broker()
	var root: Node3D = setup[0]
	var body: CharacterBody3D = setup[1]
	var broker: Node = setup[2]
	body.global_position = Vector3.ZERO

	var dummy: StaticBody3D = CombatDummyScript.new()
	dummy.position = Vector3(0, 0, -2)
	root.add_child(dummy)
	await get_tree().process_frame
	dummy._begin_telegraph()

	var intents := Intents.new()
	intents.wants_parry = true
	broker.tick(intents, 0.016)

	assert_eq(broker.get_combat_state(), &"counter_hit")
	assert_lt(dummy.get_current_health(), dummy.max_health)

func test_takedown_finishes_near_dummy():
	var setup := _make_broker()
	var root: Node3D = setup[0]
	var body: CharacterBody3D = setup[1]
	var broker: Node = setup[2]
	body.global_position = Vector3.ZERO

	var dummy: StaticBody3D = CombatDummyScript.new()
	dummy.position = Vector3(0, 0, -1.5)
	root.add_child(dummy)
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_assassinate = true
	broker.tick(intents, 0.016)

	assert_eq(broker.get_combat_state(), &"takedown_hit")
	assert_true(dummy.is_defeated())

func test_strike_air_swing():
	var setup := _make_broker()
	var broker: Node = setup[2]

	var intents := Intents.new()
	intents.wants_attack = true

	# First attack triggers the swing
	broker.tick(intents, 0.016)
	assert_eq(broker.get_combat_state(), &"strike_swing")

	# Subsequent attack during cooldown is ignored
	broker.tick(intents, 0.016)
	assert_eq(broker.get_combat_state(), &"strike_swing")

	# Cooldown ticks down and resets to idle
	intents.wants_attack = false
	for i in range(25):
		broker.tick(intents, 0.016)

	assert_eq(broker.get_combat_state(), &"idle")

func test_strike_snapping_to_target():
	var setup := _make_broker()
	var root: Node3D = setup[0]
	var body: CharacterBody3D = setup[1]
	var broker: Node = setup[2]
	var movement_broker: Node = setup[3]
	var strike_motor: Node = setup[4]

	body.global_position = Vector3.ZERO

	var dummy: StaticBody3D = CombatDummyScript.new()
	dummy.position = Vector3(0, 0, -4.0)
	root.add_child(dummy)
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_attack = true

	broker.tick(intents, 0.016)

	assert_eq(broker.get_combat_state(), &"strike_dash")
	assert_true(strike_motor._active)
	assert_eq(movement_broker.get_current_mode(), 14) # STRIKE ID

	var mock_services: Array[BaseService] = []
	var proposals = strike_motor.gather_proposals(14, intents, mock_services, null)
	assert_eq(proposals.size(), 1)
	assert_eq(proposals[0].target_state, 14)
	assert_eq(proposals[0].override_weight, StrikeMotorScript.STRIKE_PRIORITY_WEIGHT, "must outrank Stairs/Ladder/WallJump's lower weights to avoid losing arbitration mid-dash")

	strike_motor.tick(0.016, intents, body, null, mock_services)
	assert_true(body.velocity.z < 0.0, "Velocity should point towards target (negative Z)")

	body.global_position = Vector3(0, 0, -2.4)
	strike_motor.tick(0.016, intents, body, null, mock_services)
	assert_false(strike_motor._active, "StrikeMotor should deactivate when close enough")

func test_bow_blocked_when_exhausted():
	var stamina := StaminaComponentScript.new()
	add_child_autofree(stamina)
	stamina.current_stamina = 0.0
	var setup := _make_broker(stamina)
	var broker: Node = setup[2]

	var intents := Intents.new()
	intents.wants_archery_release = true
	intents.aim_direction = Vector3.FORWARD
	broker.tick(intents, 0.016)

	assert_ne(broker.get_combat_state(), &"bow_release", "exhausted player should not be able to fire")

func test_takedown_blocked_when_exhausted():
	var stamina := StaminaComponentScript.new()
	add_child_autofree(stamina)
	stamina.current_stamina = 0.0
	var setup := _make_broker(stamina)
	var root: Node3D = setup[0]
	var body: CharacterBody3D = setup[1]
	var broker: Node = setup[2]
	body.global_position = Vector3.ZERO

	var dummy: StaticBody3D = CombatDummyScript.new()
	dummy.position = Vector3(0, 0, -1.5)
	root.add_child(dummy)
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_assassinate = true
	broker.tick(intents, 0.016)

	assert_ne(broker.get_combat_state(), &"takedown_hit", "exhausted player should not be able to execute a takedown")
	assert_false(dummy.is_defeated())

func test_parry_blocked_when_exhausted():
	var stamina := StaminaComponentScript.new()
	add_child_autofree(stamina)
	stamina.current_stamina = 0.0
	var setup := _make_broker(stamina)
	var root: Node3D = setup[0]
	var body: CharacterBody3D = setup[1]
	var broker: Node = setup[2]
	body.global_position = Vector3.ZERO

	var dummy: StaticBody3D = CombatDummyScript.new()
	dummy.position = Vector3(0, 0, -2)
	root.add_child(dummy)
	await get_tree().process_frame
	dummy._begin_telegraph()

	var intents := Intents.new()
	intents.wants_parry = true
	broker.tick(intents, 0.016)

	assert_ne(broker.get_combat_state(), &"counter_hit", "exhausted player should not land a parry counter")

func test_strike_drains_real_stamina_component():
	# Regression: strike_action.gd's exhaustion gate/drain had only ever run
	# with stamina=null in this test file — proving it parses, not that
	# StaminaComponent.is_exhausted()/drain() actually work at runtime.
	var stamina := StaminaComponentScript.new()
	add_child_autofree(stamina)
	var setup := _make_broker(stamina)
	var broker: Node = setup[2]

	var intents := Intents.new()
	intents.wants_attack = true
	broker.tick(intents, 0.016)

	assert_lt(stamina.get_current(), stamina.get_max(), "a real StaminaComponent should actually be drained")

func test_bow_drains_real_stamina_component():
	var stamina := StaminaComponentScript.new()
	add_child_autofree(stamina)
	var setup := _make_broker(stamina)
	var broker: Node = setup[2]

	var intents := Intents.new()
	intents.wants_archery_release = true
	intents.aim_direction = Vector3.FORWARD
	broker.tick(intents, 0.016)

	assert_lt(stamina.get_current(), stamina.get_max(), "firing an arrow should drain real stamina")

func test_attack_press_not_dropped_on_cooldown_expiry_frame():
	var setup := _make_broker()
	var broker: Node = setup[2]
	var sa: Node = broker.get_node("StrikeAction")

	var intents := Intents.new()
	intents.wants_attack = true
	broker.tick(intents, 0.016)
	assert_eq(broker.get_combat_state(), &"strike_swing")

	intents.wants_attack = false
	var step: float = 0.016
	while sa._strike_cooldown > step:
		broker.tick(intents, step)

	# This tick crosses the cooldown to <= 0 — simulate a press landing on
	# exactly this frame, the case that used to be silently dropped.
	intents.wants_attack = true
	broker.tick(intents, step)

	assert_eq(broker.get_combat_state(), &"strike_swing", "a press landing exactly as cooldown clears must not be dropped")

func test_bow_release_not_dropped_during_strike_cooldown():
	var setup := _make_broker()
	var broker: Node = setup[2]
	var sa: Node = broker.get_node("StrikeAction")

	var intents := Intents.new()
	intents.wants_attack = true
	broker.tick(intents, 0.016)
	assert_eq(broker.get_combat_state(), &"strike_swing")
	assert_false(sa.is_active(), "an air-swing (no target) never enters _strike_in_progress")

	# Now on cooldown, not mid-dash. A same-frame archery release must still
	# reach BowAction instead of being swallowed by the old is_in_progress()
	# routing gate (which included the cooldown window).
	intents.wants_attack = false
	intents.wants_archery_release = true
	intents.aim_direction = Vector3.FORWARD
	broker.tick(intents, 0.016)

	assert_eq(broker.get_combat_state(), &"bow_release", "archery release during strike cooldown (not mid-dash) must not be dropped")
