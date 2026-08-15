extends "res://addons/gut/test.gd"

## Regression: the landing-dip camera effect only fired for Fall→Walk and
## Fall→Sprint, missing Fall→Stairs, Fall→Sneak, and Fall→Ladder — equally
## valid ways to leave FALL after landing.

const CameraRigScript = preload("res://scripts/player_action_stack/camera/camera_rig.gd")

func _make_rig() -> Node3D:
	var rig: Node3D = CameraRigScript.new()
	# CameraRig's own hardcoded $Lens / $Lens/Camera3D lookups (pre-existing,
	# unrelated to this fix) need real children present, matching player.tscn's
	# structure, or _ready() errors before this test ever gets to call
	# _on_locomotion_state_changed().
	var lens := SpringArm3D.new()
	lens.name = "Lens"
	rig.add_child(lens)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	lens.add_child(camera)
	add_child_autofree(rig)
	return rig

func test_landing_dip_fires_for_walk():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.FALL, LocomotionState.ID.WALK)
	assert_gt(rig._current_dip, 0.0)

func test_landing_dip_fires_for_sprint():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.FALL, LocomotionState.ID.SPRINT)
	assert_gt(rig._current_dip, 0.0)

func test_landing_dip_fires_for_stairs():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.FALL, LocomotionState.ID.STAIRS)
	assert_gt(rig._current_dip, 0.0, "landing directly onto a staircase should trigger the dip")

func test_landing_dip_fires_for_sneak():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.FALL, LocomotionState.ID.SNEAK)
	assert_gt(rig._current_dip, 0.0, "landing into a sneak crouch should trigger the dip")

func test_landing_dip_fires_for_ladder():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.FALL, LocomotionState.ID.LADDER)
	assert_gt(rig._current_dip, 0.0, "landing at a ladder's base should trigger the dip")

func test_landing_dip_does_not_fire_for_non_landing_transition():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.WALK, LocomotionState.ID.MANTLE)
	assert_eq(rig._current_dip, 0.0, "a non-Fall-origin transition should not trigger the dip")

func test_landing_dip_does_not_fire_leaving_fall_into_active_traversal():
	var rig := _make_rig()
	rig._on_locomotion_state_changed(LocomotionState.ID.FALL, LocomotionState.ID.AUTO_VAULT)
	assert_eq(rig._current_dip, 0.0, "auto-vault is active traversal, not a passive landing")
