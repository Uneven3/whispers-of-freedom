extends "res://addons/gut/test.gd"

## Regression: MovementBrokerDebugReporter and CombatDebugReporter both push
## to this same panel_key=1 context. push_data() used to fully replace the
## label text with only the latest call's keys, so whichever system pushed
## last on a physics frame wiped the other's fields from the F1 debug HUD.

const PlayerActionDebugContextScript = preload("res://scripts/player_action_stack/player_action_debug_context.gd")

func _make_context() -> Node:
	var ctx: Node = PlayerActionDebugContextScript.new()
	add_child_autofree(ctx)
	return ctx

func test_second_push_does_not_erase_first_pushs_keys():
	var ctx := _make_context()
	ctx.push_data({"state": "walk", "speed": 3.2})
	ctx.push_data({"combat": "idle"})

	assert_string_contains(ctx._label.text, "state: walk")
	assert_string_contains(ctx._label.text, "speed: 3.2")
	assert_string_contains(ctx._label.text, "combat: idle")

func test_repushing_same_key_updates_it():
	var ctx := _make_context()
	ctx.push_data({"combat": "idle"})
	ctx.push_data({"combat": "strike_dash"})

	assert_string_contains(ctx._label.text, "combat: strike_dash")
	assert_false(ctx._label.text.contains("combat: idle"), "stale value should be replaced, not duplicated")

func test_clear_resets_accumulated_data():
	var ctx := _make_context()
	ctx.push_data({"state": "walk"})
	ctx.clear()
	ctx.push_data({"combat": "idle"})

	assert_false(ctx._label.text.contains("state: walk"), "clear() should drop previously accumulated fields")
	assert_string_contains(ctx._label.text, "combat: idle")
