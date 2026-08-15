extends "res://addons/gut/test.gd"

## Regression: register_context() used to silently drop a context whose
## panel_key was left at its -1 default, so a forgotten Inspector value made
## a debug panel look like a data-flow bug elsewhere.

const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const BaseDebugContextScript = preload("res://scripts/base/base_debug_context.gd")

func _make_context(key: int) -> Node:
	var ctx := BaseDebugContextScript.new()
	ctx.panel_key = key
	add_child_autofree(ctx)
	return ctx

func test_negative_panel_key_is_not_registered():
	var overlay := DebugOverlayScript.new()
	add_child_autofree(overlay)
	overlay.register_context(_make_context(-1))
	assert_false(overlay._contexts.has(-1))

func test_valid_panel_key_is_registered():
	var overlay := DebugOverlayScript.new()
	add_child_autofree(overlay)
	var ctx := _make_context(3)
	overlay.register_context(ctx)
	assert_eq(overlay._contexts[3], ctx)
