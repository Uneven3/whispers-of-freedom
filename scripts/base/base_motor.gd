class_name BaseMotor
extends Node

@warning_ignore("unused_private_class_variable")
var _broker: MovementBroker ## Reference to the MovementBroker that ticks this motor.

## Gathers transition proposals for this motor based on current state and intents.
func gather_proposals(_current_mode: int, _intents: Intents, _services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	return []

## Ticks the motor. It is only called if this motor is active.
func tick(_delta: float, _intents: Intents, _body: CharacterBody3D, _stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	assert(false, "Not implemented: tick")

## Shared service locator — avoids duplicating this helper in every concrete motor.
## Returns the first element in services that matches service_type, or null.
func _get_service(services: Array[BaseService], service_type: Variant) -> BaseService:
	assert(services != null, "Services array cannot be null")
	for s in services:
		if is_instance_of(s, service_type):
			return s
	return null

## Body geometry from the entity's CollisionShape3D (SSoT — see BodyReader).
## Falls back to player-capsule defaults when the reader or shape is missing,
## so unit tests that construct bare CharacterBody3D nodes keep working.
func _get_body_half_height() -> float:
	var reader := _get_body_reader()
	return reader.get_body_half_height() if reader else 1.0

func _get_body_radius() -> float:
	var reader := _get_body_reader()
	return reader.get_body_radius() if reader else 0.5

func _get_body_reader() -> BodyReader:
	if _broker and _broker.has_method("get_body_reader"):
		return _broker.get_body_reader()
	return null

## Helper to rotate the body towards movement intent.
func apply_locomotion_rotation(body: CharacterBody3D, intents: Intents, delta: float, speed: float = 15.0) -> void:
	var intended_dir: Vector2 = intents.move_dir
	if intended_dir.length_squared() > 0.01:
		var target_dir: Vector3 = Vector3(intended_dir.x, 0, intended_dir.y).normalized()
		var target_basis: Basis = Basis.looking_at(target_dir, Vector3.UP)
		body.basis = body.basis.slerp(target_basis, speed * delta)

## Shared flat-floor horizontal-velocity handling — WalkMotor, SprintMotor,
## and SneakMotor all accelerate toward move_dir * speed when moving and
## decelerate to zero otherwise, then zero velocity.y (stairs/obstacles are
## delegated to StairsMotor/AutoVaultMotor, never handled here). Kept as a
## shared helper instead of each motor's own copy after the same pattern
## showed up duplicated three times.
func apply_ground_velocity(body: CharacterBody3D, move_dir: Vector3, speed: float, accel: float, decel: float, delta: float) -> void:
	if move_dir != Vector3.ZERO:
		body.velocity.x = move_toward(body.velocity.x, move_dir.x * speed, accel * delta)
		body.velocity.z = move_toward(body.velocity.z, move_dir.z * speed, accel * delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0, decel * delta)
		body.velocity.z = move_toward(body.velocity.z, 0, decel * delta)
	body.velocity.y = 0.0
