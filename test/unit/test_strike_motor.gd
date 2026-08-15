extends "res://addons/gut/test.gd"

## Regression: StrikeMotor._active used to only clear inside tick(), which
## only ever runs once the motor's FORCED proposal actually wins arbitration.
## If a higher-weight FORCED motor (eg AutoVaultMotor, weight 20) wins
## outright instead of tying, tick() never runs, and _active stayed true
## forever — re-proposing every physics frame until it eventually won
## arbitration and snap-dashed toward a stale target with zero player input,
## possibly seconds later. See STRIKE_PRIORITY_WEIGHT / MAX_PENDING_FRAMES
## comments in strike_motor.gd for the full mechanism.

const StrikeMotorScript = preload("res://scripts/player_action_stack/movement/motors/strike_motor.gd")

func test_self_cancels_if_proposal_never_wins_arbitration():
	var strike_motor := StrikeMotorScript.new()
	add_child_autofree(strike_motor)

	var target := Node3D.new()
	add_child_autofree(target)
	strike_motor.start_strike_dash(target, Vector3.ZERO)

	var intents := Intents.new()
	var mock_services: Array[BaseService] = []
	# Simulate losing arbitration every frame (tick() never called, as if a
	# higher-weight FORCED motor kept winning instead) past the watchdog
	# threshold.
	for i in range(StrikeMotorScript.MAX_PENDING_FRAMES + 1):
		strike_motor.gather_proposals(3, intents, mock_services, null)

	assert_false(strike_motor._active, "must self-cancel instead of staying stuck forever")
	assert_eq(strike_motor.gather_proposals(3, intents, mock_services, null).size(), 0, "stops proposing once cancelled")

func test_does_not_self_cancel_while_winning_normally():
	var strike_motor := StrikeMotorScript.new()
	add_child_autofree(strike_motor)

	var target := Node3D.new()
	add_child_autofree(target)
	strike_motor.start_strike_dash(target, Vector3.ZERO)

	var intents := Intents.new()
	var mock_services: Array[BaseService] = []
	var body := CharacterBody3D.new()
	add_child_autofree(body)

	# Normal case: gather_proposals then tick() every frame, well past the
	# watchdog threshold — must not falsely trip.
	for i in range(StrikeMotorScript.MAX_PENDING_FRAMES + 5):
		strike_motor.gather_proposals(14, intents, mock_services, null)
		if not strike_motor._active:
			break
		strike_motor.tick(0.016, intents, body, null, mock_services)

	# Target is at origin and body starts at origin too, so the dash should
	# have already resolved (distance < 0.25) well before the loop ends —
	# this asserts it resolved normally, not via the watchdog.
	assert_false(strike_motor._active, "dash should have completed normally (target reached)")
