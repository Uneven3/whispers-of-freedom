class_name CombatBroker
extends Node

signal hit_landed(event: RefCounted)
signal aiming_changed(is_aiming: bool)
signal combat_state_changed(state: StringName)

const DamageEventScript = preload("res://scripts/base/damage_event.gd")

var _body_reader: BodyReader
var _stamina: Node
var _projectile_parent: Node
var _movement_broker: Node
var _is_aiming: bool = false
var _combat_state: StringName = &"idle"
var _last_hit: RefCounted

@onready var _bow_action: Node = get_node_or_null("BowAction")
@onready var _parry_action: Node = get_node_or_null("ParryCounterAction")
@onready var _takedown_action: Node = get_node_or_null("TakedownAction")
@onready var _strike_action: Node = get_node_or_null("StrikeAction")
@onready var _hit_pause: Node = get_node_or_null("HitPauseComponent")

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func configure(
	body_reader: BodyReader,
	stamina: Node,
	projectile_parent: Node,
	movement_broker: Node = null
) -> void:
	_body_reader = body_reader
	_stamina = stamina
	_projectile_parent = projectile_parent
	_movement_broker = movement_broker

## Single character, full moveset — every action is always available, so this
## picks exactly one to run per frame instead of relying on tick order:
## an in-progress strike always resolves first (never interrupted mid-swing),
## then aim/bow, then takedown, then parry, then a fresh strike. Without this,
## e.g. releasing an aimed shot (wants_archery_release) also sets wants_attack
## true the same frame and would double as a melee swing.
func tick(intents: Intents, delta: float) -> void:
	if not intents:
		return
	set_aiming(intents.wants_archery_aim)
	if _strike_action and _strike_action.has_method("is_in_progress") and _strike_action.is_in_progress():
		_strike_action.tick(intents, delta, self)
		return
	if intents.wants_archery_aim or intents.wants_archery_release:
		if _bow_action and _bow_action.has_method("tick"):
			_bow_action.tick(intents, delta, self)
		return
	if intents.wants_assassinate:
		if _takedown_action and _takedown_action.has_method("tick"):
			_takedown_action.tick(intents, delta, self)
		return
	if intents.wants_parry:
		if _parry_action and _parry_action.has_method("tick"):
			_parry_action.tick(intents, delta, self)
		return
	if _strike_action and _strike_action.has_method("tick"):
		_strike_action.tick(intents, delta, self)

func get_body_reader() -> BodyReader:
	return _body_reader

func get_projectile_parent() -> Node:
	return _projectile_parent if _projectile_parent else get_tree().current_scene

func is_aiming() -> bool:
	return _is_aiming

func get_combat_state() -> StringName:
	return _combat_state

func get_last_hit() -> RefCounted:
	return _last_hit

func set_aiming(is_enabled: bool) -> void:
	if _is_aiming == is_enabled:
		return
	_is_aiming = is_enabled
	aiming_changed.emit(_is_aiming)

func set_combat_state(state: StringName) -> void:
	if _combat_state == state:
		return
	_combat_state = state
	combat_state_changed.emit(_combat_state)

func apply_damage(
	target: Node3D,
	amount: float,
	damage_type: StringName,
	stagger_class: StringName,
	hit_position: Vector3 = Vector3.ZERO
) -> RefCounted:
	if not target:
		return null
	var source_node: Node3D = _body_reader._body if _body_reader else target
	var event: RefCounted = DamageEventScript.new(source_node, target, amount, damage_type, stagger_class, hit_position)
	var receiver: Node = target
	if not receiver.has_method("apply_damage") and target.get_parent():
		receiver = target.get_parent()
	if receiver.has_method("apply_damage"):
		receiver.apply_damage(event)
	_last_hit = event
	hit_landed.emit(event)
	return event

func trigger_hit_pause(scale: float, duration: float) -> void:
	if _hit_pause and _hit_pause.has_method("request_hit_pause"):
		_hit_pause.request_hit_pause(scale, duration)

func find_nearest_target(origin: Vector3, max_distance: float) -> Node3D:
	var best_target: Node3D = null
	var best_distance := max_distance
	for target in get_tree().get_nodes_in_group("combat_target"):
		if not target is Node3D:
			continue
		if target.has_method("is_defeated") and target.is_defeated():
			continue
		var distance := origin.distance_to(target.global_position)
		if distance <= best_distance:
			best_distance = distance
			best_target = target
	return best_target
