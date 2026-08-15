extends "res://addons/gut/test.gd"

## Regression: Ladder/Stairs used to call add_to_group() before checking for
## their required marker children, so a malformed one still got wired up by
## LadderService/StairsService and crashed later on the null marker instead
## of being disabled as the push_error claimed.

const LadderScript = preload("res://scripts/world/ladder.gd")
const StairsScript = preload("res://scripts/world/stairs.gd")

func test_ladder_missing_markers_does_not_join_group():
	var ladder: Area3D = LadderScript.new()
	add_child_autofree(ladder)
	assert_false(ladder.is_in_group("ladder"), "malformed ladder must not be discoverable by LadderService")
	assert_push_error("is missing a BottomMarker or TopMarker")
	assert_engine_error_count(2, "$BottomMarker/$TopMarker resolution errors from the missing children")

func test_ladder_with_markers_joins_group():
	var ladder: Area3D = LadderScript.new()
	var bottom := Node3D.new()
	bottom.name = "BottomMarker"
	var top := Node3D.new()
	top.name = "TopMarker"
	ladder.add_child(bottom)
	ladder.add_child(top)
	add_child_autofree(ladder)
	assert_true(ladder.is_in_group("ladder"))

func test_stairs_missing_markers_does_not_join_group():
	var stairs: Area3D = StairsScript.new()
	add_child_autofree(stairs)
	assert_false(stairs.is_in_group("stairs"), "malformed stairs must not be discoverable by StairsService")
	assert_push_error("is missing a BaseMarker or TopMarker")
	assert_engine_error_count(2, "$BaseMarker/$TopMarker resolution errors from the missing children")

func test_stairs_with_markers_joins_group():
	var stairs: Area3D = StairsScript.new()
	var base := Node3D.new()
	base.name = "BaseMarker"
	var top := Node3D.new()
	top.name = "TopMarker"
	stairs.add_child(base)
	stairs.add_child(top)
	add_child_autofree(stairs)
	assert_true(stairs.is_in_group("stairs"))
