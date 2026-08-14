extends "res://addons/gut/test.gd"

const CombatDummyScript = preload("res://scripts/world/combat_dummy.gd")
const DamageEventScript = preload("res://scripts/base/damage_event.gd")

func test_apply_damage_reduces_health_and_emits_signal():
	var dummy: StaticBody3D = CombatDummyScript.new()
	add_child_autofree(dummy)
	await get_tree().process_frame

	var source := Node3D.new()
	add_child_autofree(source)
	var event: RefCounted = DamageEventScript.new(source, dummy, 25.0, &"test_hit")

	watch_signals(dummy)
	dummy.apply_damage(event)

	assert_eq(dummy.get_current_health(), 125.0)
	assert_signal_emitted(dummy, "damage_received")

func test_consume_parry_closes_parry_window():
	var dummy: StaticBody3D = CombatDummyScript.new()
	add_child_autofree(dummy)
	await get_tree().process_frame

	dummy._begin_telegraph()
	assert_true(dummy.is_parry_vulnerable())
	dummy.consume_parry()

	assert_false(dummy.is_parry_vulnerable())
