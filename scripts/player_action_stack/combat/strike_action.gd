class_name StrikeAction
extends Node

# — Configuration —
@export var strike_range: float = 6.0             # Max distance to acquire a snapping target
@export var strike_damage: float = 20.0           # Base damage for a standard strike
@export var hit_pause_scale: float = 0.05         # Time scale for the hitpause effect
@export var hit_pause_duration: float = 0.06      # Duration of the hitpause effect
@export var stamina_drain_on_strike: float = 5.0  # Stamina cost per attack
@export var strike_cooldown: float = 0.35         # Cooldown in seconds between attacks

# — Internal state —
var _strike_in_progress: bool = false
var _target_node: Node3D = null
var _strike_cooldown: float = 0.0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

## Lets CombatBroker prioritize other actions on a fresh input without
## interrupting a dash/cooldown that already started (§17 concern: silently
## dropping a swing mid-flight would feel like a bug, not a design choice).
func is_in_progress() -> bool:
	return _strike_in_progress or _strike_cooldown > 0.0

## Sólo durante el dash; is_in_progress() además incluye el enfriamiento.
## Por qué son dos: docs/movimiento.md, "Arbitraje de combate".
func is_active() -> bool:
	return _strike_in_progress

func tick(intents: Intents, delta: float, broker: Node) -> void:
	var cb := broker as CombatBroker
	if not cb:
		return

	# Handle checking if dash completed
	if _strike_in_progress:
		var movement_broker = cb._movement_broker
		if movement_broker and movement_broker.get_current_mode() != LocomotionState.ID.STRIKE:
			_strike_in_progress = false
			if _target_node and is_instance_valid(_target_node):
				var dist: float = cb.get_body_reader().get_global_position().distance_to(_target_node.global_position)
				if dist <= 2.8:
					cb.apply_damage(_target_node, strike_damage, &"strike", &"light", _target_node.global_position)
					cb.trigger_hit_pause(hit_pause_scale, hit_pause_duration)
					cb.set_combat_state(&"strike_hit")
				else:
					cb.set_combat_state(&"strike_miss")
			else:
				cb.set_combat_state(&"strike_miss")
			_target_node = null
			_strike_cooldown = strike_cooldown # Set cooldown after strike finishes
		return

	# Process cooldown
	if _strike_cooldown > 0:
		_strike_cooldown -= delta
		if _strike_cooldown <= 0:
			cb.set_combat_state(&"idle")
		else:
			# Sin esta rama se pierde la pulsación que cae justo en el frame en
			# que el enfriamiento llega a cero: just_pressed es de un disparo.
			if intents.wants_attack:
				return

	if not intents.wants_attack:
		return
		
	var stamina: Node = cb._stamina
	if stamina and stamina.is_exhausted():
		return
		
	var body_reader = cb.get_body_reader()
	if not body_reader:
		return
		
	var target := cb.find_nearest_target(body_reader.get_global_position(), strike_range)
	if target:
		if stamina:
			stamina.drain(stamina_drain_on_strike)
		_target_node = target
		_strike_in_progress = true
		
		# Rotate body to look at target immediately
		var body: CharacterBody3D = body_reader.get_body()
		if body:
			var to_target = (target.global_position - body.global_position)
			to_target.y = 0.0
			if to_target.length_squared() > 0.001:
				body.basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
		
		var movement_broker = cb._movement_broker
		var strike_motor = movement_broker.get_node_or_null("StrikeMotor") if movement_broker else null
		if strike_motor and strike_motor.has_method("start_strike_dash"):
			strike_motor.start_strike_dash(target, target.global_position)
			
		cb.set_combat_state(&"strike_dash")
		var proposal := TransitionProposal.new(LocomotionState.ID.STRIKE, TransitionProposal.Priority.FORCED, StrikeMotor.STRIKE_PRIORITY_WEIGHT)
		if movement_broker:
			movement_broker.inject_forced_proposal(proposal)
	else:
		# Swing in the air if no target
		if stamina:
			stamina.drain(stamina_drain_on_strike)
		cb.set_combat_state(&"strike_swing")
		_strike_cooldown = strike_cooldown
