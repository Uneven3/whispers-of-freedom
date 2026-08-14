extends "res://addons/gut/test.gd"

const CombatBrokerScript = preload("res://scripts/player_action_stack/combat/combat_broker.gd")
const BowActionScript = preload("res://scripts/player_action_stack/combat/bow_action.gd")
const ParryActionScript = preload("res://scripts/player_action_stack/combat/parry_counter_action.gd")
const TakedownActionScript = preload("res://scripts/player_action_stack/combat/panther_takedown_action.gd")
const StrikeActionScript = preload("res://scripts/player_action_stack/combat/strike_action.gd")
const HitPauseScript = preload("res://scripts/player_action_stack/combat/hit_pause_component.gd")
const CombatDummyScript = preload("res://scripts/world/combat_dummy.gd")
const StrikeMotorScript = preload("res://scripts/player_action_stack/movement/motors/strike_motor.gd")
const MovementBrokerScript = preload("res://scripts/player_action_stack/movement/movement_broker.gd")

class FakeFormReader extends RefCounted:
	var form_id: StringName = &"panther"
	func get_current_form() -> StringName:
		return form_id

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

func _make_broker(form_id: StringName) -> Array:
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
	takedown.name = "PantherTakedownAction"
	broker.add_child(takedown)
	var strike: Node = StrikeActionScript.new()
	strike.name = "StrikeAction"
	broker.add_child(strike)
	var hit_pause: Node = HitPauseScript.new()
	hit_pause.name = "HitPauseComponent"
	broker.add_child(hit_pause)

	var form_reader := FakeFormReader.new()
	form_reader.form_id = form_id
	broker.configure(BodyReader.new(body), form_reader, null, root, movement_broker)
	add_child_autofree(root)

	return [root, body, broker, form_reader, movement_broker, strike_motor]

func test_avian_aim_sets_aiming_state():
	var setup := _make_broker(&"avian")
	var broker: Node = setup[2]
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_archery_aim = true

	broker.tick(intents, 0.016)

	assert_true(broker.is_aiming())
	assert_eq(broker.get_combat_state(), &"bow_drawn")

func test_monkey_parry_hits_vulnerable_dummy():
	var setup := _make_broker(&"monkey")
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

func test_panther_takedown_finishes_near_dummy():
	var setup := _make_broker(&"panther")
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

func test_monkey_strike_air_swing():
	var setup := _make_broker(&"monkey")
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

func test_monkey_strike_snapping_to_target():
	var setup := _make_broker(&"monkey")
	var root: Node3D = setup[0]
	var body: CharacterBody3D = setup[1]
	var broker: Node = setup[2]
	var movement_broker: Node = setup[4]
	var strike_motor: Node = setup[5]

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

	strike_motor.tick(0.016, intents, body, null, mock_services)
	assert_true(body.velocity.z < 0.0, "Velocity should point towards target (negative Z)")
	
	body.global_position = Vector3(0, 0, -2.4)
	strike_motor.tick(0.016, intents, body, null, mock_services)
	assert_false(strike_motor._active, "StrikeMotor should deactivate when close enough")
