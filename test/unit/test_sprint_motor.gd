extends "res://addons/gut/test.gd"

## Unit tests for SprintMotor -- also exercises BaseMotor.apply_ground_velocity()
## (see test_walk_motor.gd for the shared-helper rationale).

const SprintMotorScript = preload("res://scripts/player_action_stack/movement/motors/sprint_motor.gd")

var _motor: BaseMotor
var _stamina: StaminaComponent
var _body: CharacterBody3D

func before_each():
	_motor = SprintMotorScript.new()
	add_child_autofree(_motor)
	_stamina = StaminaComponent.new()
	add_child_autofree(_stamina)
	_body = CharacterBody3D.new()
	add_child_autofree(_body)

func test_tick_accelerates_toward_move_dir():
	var intents := Intents.new()
	intents.move_dir = Vector2(0.0, 1.0)
	_motor.tick(0.1, intents, _body, _stamina, [])
	assert_gt(_body.velocity.z, 0.0, "velocity should move toward move_dir")
	assert_eq(_body.velocity.y, 0.0, "SprintMotor is strictly flat-floor")

func test_tick_decelerates_to_zero_with_no_input():
	_body.velocity = Vector3(3.0, 0.0, 0.0)
	var intents := Intents.new()
	_motor.tick(0.1, intents, _body, _stamina, [])
	assert_lt(_body.velocity.x, 3.0, "velocity should decay toward zero with no input")

func test_tick_drains_stamina():
	_stamina.recover(100.0)
	var before := _stamina.get_current()
	var intents := Intents.new()
	_motor.tick(0.1, intents, _body, _stamina, [])
	assert_lt(_stamina.get_current(), before, "sprinting drains stamina")
