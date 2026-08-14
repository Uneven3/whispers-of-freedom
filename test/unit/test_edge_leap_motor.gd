extends "res://addons/gut/test.gd"

## Unit tests for EdgeLeapMotor.

const EdgeLeapMotorScript = preload("res://scripts/player_action_stack/movement/motors/edge_leap_motor.gd")

var _motor: BaseMotor
var _stamina: StaminaComponent
var _services: Array[BaseService]
var _body: CharacterBody3D

class MockBroker extends MovementBroker:
	var mock_reader: BodyReader
	
	func _ready():
		# Shadow parent _ready to avoid get_node calls
		pass
		
	func get_body_reader() -> BodyReader:
		return mock_reader

class MockLedgeService extends LedgeService:
	var mock_facts: LedgeFacts = LedgeFacts.new()
	var mock_normal: Vector3 = Vector3.BACK
	
	func get_ledge_facts() -> LedgeFacts:
		return mock_facts
	
	func get_climb_normal() -> Vector3:
		return mock_normal

func before_each():
	_motor = EdgeLeapMotorScript.new()
	add_child_autofree(_motor)
	
	_stamina = StaminaComponent.new()
	add_child_autofree(_stamina)
	
	_services = []
	_body = CharacterBody3D.new()
	add_child_autofree(_body)
	
	var broker = MockBroker.new()
	broker.mock_reader = BodyReader.new(_body)
	add_child_autofree(broker)
	
	_motor._broker = broker

func after_each():
	_services.clear()

func test_gather_proposals_triggers_at_left_edge():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	ledge.mock_facts.has_wall_left = false
	_services.append(ledge)
	
	var intents = Intents.new()
	intents.wants_jump = true
	intents.wish_dir = Vector2i(-1, 0) # Climbing left
	
	var proposals = _motor.gather_proposals(LocomotionState.ID.CLIMB, intents, _services, _stamina)
	
	assert_eq(proposals.size(), 1, "Should return one proposal")
	if proposals.size() > 0:
		assert_eq(proposals[0].target_state, LocomotionState.ID.EDGE_LEAP, "Should propose EDGE_LEAP")
		assert_eq(proposals[0].category, TransitionProposal.Priority.FORCED, "Should be FORCED priority")

func test_gather_proposals_does_not_trigger_when_wall_continues():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	ledge.mock_facts.has_wall_left = true # Wall continues
	_services.append(ledge)
	
	var intents = Intents.new()
	intents.wants_jump = true
	intents.wish_dir = Vector2i(-1, 0) # Climbing left
	
	var proposals = _motor.gather_proposals(LocomotionState.ID.CLIMB, intents, _services, _stamina)
	
	assert_eq(proposals.size(), 0, "Should NOT propose anything (let WallJumpMotor handle it)")

func test_tick_applies_impulse_and_drains_stamina():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	_services.append(ledge)
	
	var intents = Intents.new()
	intents.wish_dir = Vector2i(-1, 0) # Climbing left
	
	_stamina.recover(100)
	var initial_stamina = _stamina.get_current()
	
	_motor.on_activate(_body)
	_motor.tick(0.01, intents, _body, _stamina, _services)
	
	assert_true(_body.velocity.length() > 0, "Velocity should be non-zero after impulse")
	assert_true(_stamina.get_current() < initial_stamina, "Stamina should be drained")
	
	assert_no_new_orphans()
