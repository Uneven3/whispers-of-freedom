extends "res://addons/gut/test.gd"

## DamageEvent.resolve_receiver() is the shared "walk up to the parent if the
## collider itself doesn't implement apply_damage" rule used by both
## CombatBroker (melee) and ArrowProjectile (ranged) hit resolution.

const DamageEventScript = preload("res://scripts/base/damage_event.gd")
const CombatDummyScript = preload("res://scripts/world/combat_dummy.gd")

func test_returns_target_when_it_implements_apply_damage():
	var receiver: StaticBody3D = CombatDummyScript.new()
	add_child_autofree(receiver)
	assert_eq(DamageEventScript.resolve_receiver(receiver), receiver)

func test_walks_up_to_parent_when_target_lacks_apply_damage():
	var parent: StaticBody3D = CombatDummyScript.new()
	var hitbox := Node3D.new()
	parent.add_child(hitbox)
	add_child_autofree(parent)
	assert_eq(DamageEventScript.resolve_receiver(hitbox), parent)

func test_returns_target_unchanged_when_it_has_no_parent():
	var orphan: Node3D = autofree(Node3D.new())
	assert_eq(DamageEventScript.resolve_receiver(orphan), orphan)

func test_walks_up_exactly_one_level_even_if_parent_also_lacks_apply_damage():
	var grandparent := Node3D.new()
	var parent := Node3D.new()
	var hitbox := Node3D.new()
	grandparent.add_child(parent)
	parent.add_child(hitbox)
	add_child_autofree(grandparent)
	assert_eq(DamageEventScript.resolve_receiver(hitbox), parent)
