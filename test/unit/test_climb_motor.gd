extends "res://addons/gut/test.gd"

## Unit tests for ClimbMotor.

const ClimbMotorScript = preload("res://scripts/player_action_stack/movement/motors/climb_motor.gd")

var _motor: BaseMotor
var _stamina: StaminaComponent
var _services: Array[BaseService]
var _body: CharacterBody3D

class MockBroker extends MovementBroker:
	var mock_reader: BodyReader
	
	func _ready():
		pass
		
	func get_body_reader() -> BodyReader:
		return mock_reader

class MockLedgeService extends LedgeService:
	var mock_facts: LedgeFacts = LedgeFacts.new()
	var mock_can_climb: bool = false
	var mock_can_continue: bool = false
	var mock_normal: Vector3 = Vector3.BACK
	var mock_wall_point: Vector3 = Vector3.ZERO
	
	func get_ledge_facts() -> LedgeFacts:
		return mock_facts
	
	func can_climb() -> bool:
		return mock_can_climb
		
	func can_continue_climbing() -> bool:
		return mock_can_continue
		
	func get_climb_normal() -> Vector3:
		return mock_normal
		
	func get_wall_point() -> Vector3:
		return mock_wall_point

class MockGroundService extends GroundService:
	var mock_on_floor: bool = false
	func is_on_floor() -> bool:
		return mock_on_floor

func before_each():
	_motor = ClimbMotorScript.new()
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

func test_gather_proposals_climbing_the_air_regression():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	_services.append(ledge)
	
	var ground = MockGroundService.new()
	add_child_autofree(ground)
	_services.append(ground)
	
	var intents = Intents.new()
	intents.wants_climb = true
	
	# SETUP: Player is currently climbing, on floor, has context (just climbed),
	# but NO wall is detected and NOT at mantle edge.
	# This simulates being on flat ground after climbing.
	ground.mock_on_floor = true
	ledge.mock_can_continue = false
	ledge.mock_facts.has_head_hit = false
	ledge.mock_facts.ledge_point = Vector3.ZERO
	
	var proposals = _motor.gather_proposals(LocomotionState.ID.CLIMB, intents, _services, _stamina)
	
	# DESIRED BEHAVIOR: Returns NO proposal because no wall and not at apex.
	assert_eq(proposals.size(), 0, "Should NOT stay in CLIMB on flat ground even with climb context")

func test_gather_proposals_stays_climbing_at_apex_on_floor():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	_services.append(ledge)
	
	var ground = MockGroundService.new()
	add_child_autofree(ground)
	_services.append(ground)
	
	var intents = Intents.new()
	intents.wants_climb = true
	
	# SETUP: Player at apex of rounded surface.
	# is_on_floor() is true, waist cast might miss (mock_can_continue=false),
	# but near_apex conditions are met.
	ground.mock_on_floor = true
	ledge.mock_can_continue = false
	ledge.mock_facts.has_head_hit = false
	ledge.mock_facts.ledge_point = Vector3.FORWARD
	
	var proposals = _motor.gather_proposals(LocomotionState.ID.CLIMB, intents, _services, _stamina)
	
	assert_eq(proposals.size(), 1, "Should stay in CLIMB at apex even if floor-grounded and waist cast misses")

func test_tick_near_apex_logic():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	_services.append(ledge)
	
	var ground = MockGroundService.new()
	add_child_autofree(ground)
	_services.append(ground)
	
	var intents = Intents.new()
	
	# Case 1: On floor but NOT at apex (base of wall - has head hit)
	# Should NOT be near_apex, so should update basis (yaw alignment)
	_body.global_position = Vector3(0, 0, 0)
	ground.mock_on_floor = true
	ledge.mock_can_continue = true
	ledge.mock_facts.has_head_hit = true
	ledge.mock_facts.ledge_point = Vector3.FORWARD
	ledge.mock_normal = Vector3.BACK # Wall facing forward
	
	_body.basis = Basis.from_euler(Vector3(0, PI, 0)) # facing forward (-Z)
	_motor.tick(0.01, intents, _body, _stamina, _services)
	
	# Since it's NOT near_apex, it should align to wall. 
	# face_dir = -climb_normal = -Vector3.BACK = Vector3.FORWARD.
	# Basis.looking_at(Vector3.FORWARD) -> Z axis is Vector3.BACK.
	assert_true(_body.basis.z.distance_to(Vector3.BACK) < 0.01, "Should align to wall when grounded but not at top")

	# Case 2: On floor AND at apex (no head hit)
	# Should be near_apex, so should NOT update basis
	ledge.mock_facts.has_head_hit = false
	ledge.mock_can_continue = false # At apex, waist cast might miss
	_body.basis = Basis.from_euler(Vector3(0, PI, 0)) # reset to facing forward (-Z)
	_motor.tick(0.01, intents, _body, _stamina, _services)
	
	# Since it's near_apex, basis should remain facing forward (Z = Vector3.FORWARD)
	assert_true(_body.basis.z.distance_to(Vector3.FORWARD) < 0.01, "Should NOT align to wall when at apex")

func test_tick_early_returns_when_climb_normal_zero():
	var ledge = MockLedgeService.new()
	add_child_autofree(ledge)
	_services.append(ledge)

	var ground = MockGroundService.new()
	add_child_autofree(ground)
	_services.append(ground)

	var intents = Intents.new()

	# Force get_climb_normal() to return ZERO — motor must return early without writing velocity.
	ledge.mock_normal = Vector3.ZERO
	_body.velocity = Vector3.ZERO

	_motor.tick(0.1, intents, _body, _stamina, _services)

	assert_eq(_body.velocity, Vector3.ZERO, "Motor should return early and leave velocity untouched when climb normal is ZERO")
