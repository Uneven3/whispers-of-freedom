# Mechanic Design: Monkey Melee Combat

**Phase:** mechanic-2
**Status:** Approved
**Started:** 2026-07-12
**Approved:** 2026-07-12

## Feel Contract
- **Mono (Cuerpo a Cuerpo - Shadow of Mordor style):**
  - **Ataques básicos (Strikes) con Snapping Magnético:** Al pulsar atacar, si hay un enemigo en rango, el jugador se desplaza rápidamente hacia él (dash magnético de corto alcance) y ejecuta el ataque, alineándose con el objetivo para garantizar que los golpes impacten sin exigir precisión manual de dirección.
  - **Ritmo de contraataque (Parry & Counter):** Lee los telégrafos de ataque de los enemigos y pulsa el botón de parry en la ventana crítica. El éxito detiene el ataque del enemigo y ejecuta un contraataque de alto impacto con un hitpause extremo que celebra el timing perfecto. Los fallos penalizan al jugador con daño a su salud.

## Level 1: Scope Adherence

**In scope:**
- **Ataque básico (Strike) del Mono:** Ejecutar un combo simple de golpes cuerpo a cuerpo básicos usando el botón `combat_attack` (LMB).
- **Snapping Magnético (Alineación):** Desplazamiento automático rápido (dash magnético) hacia el enemigo más cercano dentro de un rango de ataque ($6.0\text{ m}$) si se pulsa `combat_attack`.
- **Ventana de Contraataque (Parry & Counter):** Ventana temporal de tolerancia de $\pm150\text{ ms}$ cuando un enemigo telegrafía un ataque. Al presionar `combat_parry` (KEY_E) a tiempo, se realiza un contraataque exitoso, infligiendo gran daño e interrumpiendo al enemigo.
- **Hitpause y Desaceleración de Tiempo:** Efecto de detención momentánea del tiempo (hitpause) para simular el peso de los impactos al acertar un contraataque exitoso o un golpe final, solicitado al componente `HitPauseComponent`.
- **Drenaje de Estamina:** Los ataques básicos y los parries fallidos o exitosos pueden drenar estamina del jugador (según configuración).

**Flagged / cut (Fuera de alcance):**
- **Inventario / Cambio de Armas:** No hay armas físicas equipables ni durabilidad en esta fase del prototipo. El Mono ataca directamente con su cuerpo/bastón espiritual.
- **Daños numéricos flotantes en pantalla:** Se delega al sistema de interfaz de usuario (UI/HUD).
- **IA de enemigos completa:** Los enemigos no tienen lógica de navegación compleja en este slice. Solo usan la lógica de `CombatDummy` para telegrafiar y recibir daño.

**Ambiguidades resueltas:**
- **¿Cómo se realiza el desplazamiento magnético sin violar la regla P3 (solo el Motor escribe movimiento)?**
  - *Resolución:* El snapping magnético no modificará la velocidad física de forma directa desde el script de combate. En su lugar, cuando se inicie un Strike magnético, el `CombatBroker` emitirá un evento o propuesta para que un motor de combate o un movimiento especial en el `MovementBroker` tome el control de la posición física del `Body` durante los frames que dure el dash. O, para mantener el prototipo simple dentro del stack actual, se puede inyectar una propuesta temporal de movimiento (`FORCED` o a través de un `StrikeMotor` específico) para controlar la trayectoria hacia el enemigo. Optaremos por proponer un `StrikeMotor` que consuma el objetivo magnético y mueva al jugador de forma limpia e integrada.


## Level 2: Component Assignment

**Existing components used:**
- `MovementBroker` (`res://scripts/player_action_stack/movement/movement_broker.gd`) — arbitrates proposals and ticks the active motor. Needs to register `StrikeMotor` and support state `14` (`STRIKE`).
- `LocomotionState` (`res://scripts/player_action_stack/movement/locomotion_state.gd`) — needs enum extension `STRIKE = 14`.
- `FormBroker` (`res://scripts/player_action_stack/form/form_broker.gd`) — needs to include `&"StrikeMotor"` in `FORM_MONKEY`'s motor mask.
- `CombatBroker` (`res://scripts/player_action_stack/combat/combat_broker.gd`) — ticks combat actions, handles damage and target retrieval.
- `ParryCounterAction` (`res://scripts/player_action_stack/combat/parry_counter_action.gd`) — executes counter logic in response to intents.

**New nodes required:**
- `StrikeAction` (`res://scripts/player_action_stack/combat/strike_action.gd`) — child of `CombatBroker` — handles combat attack input, targets closest dummy, initiates the snapping/dash, and inflicts standard attack damage.
- `StrikeMotor` (`res://scripts/player_action_stack/movement/motors/strike_motor.gd`) — child of `MovementBroker` — handles moving the `Body` towards the snap target during the strike state (`STRIKE`).

**Composition decisions:**
- Snapping motion isolated in `StrikeMotor` because positioning character body requires integration with the physics loop (`move_and_slide()`), separating physics updates from combat logic.

---

## Level 3: Data & State Flow

**Input:**
- Attack Trigger: `intents.wants_attack` (mapped to LMB / `combat_attack`) inside `PlayerBrain`.
- Parry Trigger: `intents.wants_parry` (mapped to `E` / `combat_parry`) inside `PlayerBrain`.

**State mutations:**
- `_combat_state: StringName` on `CombatBroker` — set to `&"strike_dash"` when starting attack, `&"strike_hit"` on hit, `&"strike_miss"` on miss, `&"parry_miss"` or `&"counter_hit"` on parries.
- `LocomotionState._mode: ID` on `LocomotionState` — changes to `ID.STRIKE` (14) during attack dash, back to fallback (e.g. `WALK`/`FALL`) on completion.
- `_active: bool` on `StrikeMotor` — tracks whether a physics dash is active.

**Output:**
- Motion: `Body.velocity` is updated toward target position by `StrikeMotor`.
- Damage: `CombatBroker.apply_damage` applied to `CombatDummy`, reducing health.
- FX: `HitPauseComponent` time scaling and combat state signals.

**Flow compliance:**
1. Player presses LMB ➡️ `PlayerBrain` writes `wants_attack = true` in `Intents`.
2. `MovementBroker` ticks, calls `FormBroker` to update form.
3. `MovementBroker` queries motors (including `StrikeMotor`). If `StrikeMotor._active` is true, it forces state `STRIKE`.
4. `MovementBroker` ticks the active motor (`StrikeMotor` or others), calling `Body.move_and_slide()`.
5. `MovementBroker` emits `physics_tick_complete`.
6. `EntityController` catches `physics_tick_complete` and calls `CombatBroker.tick()`.
7. `CombatBroker` delegates to `StrikeAction.tick()` and `ParryCounterAction.tick()`.
8. `StrikeAction` detects attack trigger ➡️ finds closest target ➡️ sets `StrikeMotor` dash target ➡️ injects `FORCED` `STRIKE` proposal to `MovementBroker`.

---

## Level 4: Contract Mapping

### LocomotionState Update (`res://scripts/player_action_stack/movement/locomotion_state.gd`)
```gdscript
# Extension to enum ID:
enum ID {
	# ... (existing states) ...
	EDGE_LEAP = 13,
	STRIKE = 14 # Added for snap strike dashes
}
```

### StrikeMotor (`res://scripts/player_action_stack/movement/motors/strike_motor.gd`)
```gdscript
class_name StrikeMotor
extends BaseMotor

# — Configuration —
@export var dash_speed: float = 25.0              # Speed of the snap dash towards the target
@export var min_distance_to_target: float = 1.5   # Offset to prevent clipping into the target's collider
@export var max_dash_duration: float = 0.25       # Timeout security gate for the dash

# — Internal state —
var _dash_target_position: Vector3 = Vector3.ZERO
var _dash_timer: float = 0.0
var _active: bool = false
var _target_node: Node3D = null

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

## Public initializer called by Combat Action
func start_strike_dash(target_node: Node3D, target_pos: Vector3) -> void:
	_target_node = target_node
	_dash_target_position = target_pos
	_dash_timer = 0.0
	_active = true

func gather_proposals(_current_mode: int, _intents: Intents, _services: Array[BaseService], _stamina: StaminaComponent) -> Array[TransitionProposal]:
	if _active:
		return [TransitionProposal.new(14, TransitionProposal.Priority.FORCED)] # 14 is STRIKE
	return []

func tick(delta: float, _intents: Intents, body: CharacterBody3D, _stamina: StaminaComponent, _services: Array[BaseService]) -> void:
	if not _active:
		return
		
	_dash_timer += delta
	var current_pos := body.global_position
	
	# Keep target position updated if target moves
	if _target_node and is_instance_valid(_target_node):
		var to_enemy := _target_node.global_position - current_pos
		var dist := to_enemy.length()
		if dist > min_distance_to_target:
			_dash_target_position = _target_node.global_position - to_enemy.normalized() * min_distance_to_target
		else:
			_dash_target_position = current_pos
			
	var to_target := _dash_target_position - current_pos
	var distance := to_target.length()
	
	# Stop dash if we are close enough or timer expires
	if distance < 0.25 or _dash_timer >= max_dash_duration:
		body.velocity = Vector3.ZERO
		_active = false
		_target_node = null
		return
		
	body.velocity = to_target.normalized() * dash_speed
	body.move_and_slide()
```

### StrikeAction (`res://scripts/player_action_stack/combat/strike_action.gd`)
```gdscript
class_name StrikeAction
extends Node

# — Configuration —
@export var strike_range: float = 6.0             # Max distance to acquire a snapping target
@export var strike_damage: float = 20.0           # Base damage for a standard Monkey Strike
@export var hit_pause_scale: float = 0.05         # Time scale for the hitpause effect
@export var hit_pause_duration: float = 0.06      # Duration of the hitpause effect
@export var stamina_drain_on_strike: float = 5.0  # Stamina cost per attack

# — Internal state —
var _strike_in_progress: bool = false
var _target_node: Node3D = null

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func tick(intents: Intents, delta: float, broker: Node) -> void:
	# Handle checking if dash completed
	if _strike_in_progress:
		var movement_broker = broker._movement_broker
		if movement_broker and movement_broker.get_current_mode() != 14: # 14 is STRIKE
			_strike_in_progress = false
			if _target_node and is_instance_valid(_target_node):
				var dist: float = broker.get_body_reader().get_global_position().distance_to(_target_node.global_position)
				if dist <= 2.8:
					broker.apply_damage(_target_node, strike_damage, &"monkey_strike", &"light", _target_node.global_position)
					broker.trigger_hit_pause(hit_pause_scale, hit_pause_duration)
					broker.set_combat_state(&"strike_hit")
				else:
					broker.set_combat_state(&"strike_miss")
			else:
				broker.set_combat_state(&"strike_miss")
			_target_node = null
		return

	if not intents.wants_attack or not broker:
		return
		
	var stamina = broker._stamina
	if stamina and stamina.is_exhausted():
		return
		
	var body_reader = broker.get_body_reader()
	if not body_reader:
		return
		
	var target := broker.find_nearest_target(body_reader.get_global_position(), strike_range)
	if target:
		if stamina:
			stamina.drain(stamina_drain_on_strike)
		_target_node = target
		_strike_in_progress = true
		
		# Rotate body to look at target immediately
		var body: CharacterBody3D = body_reader._body
		if body:
			var to_target = (target.global_position - body.global_position)
			to_target.y = 0.0
			if to_target.length_squared() > 0.001:
				body.basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
		
		var strike_motor = broker._movement_broker.get_node_or_null("StrikeMotor")
		if strike_motor and strike_motor.has_method("start_strike_dash"):
			strike_motor.start_strike_dash(target, target.global_position)
			
		broker.set_combat_state(&"strike_dash")
		var proposal := TransitionProposal.new(14, TransitionProposal.Priority.FORCED)
		broker._movement_broker.inject_forced_proposal(proposal)
	else:
		# Swing in the air if no target
		if stamina:
			stamina.drain(stamina_drain_on_strike)
		broker.set_combat_state(&"strike_swing")
```

---

## Level 5: Edge Case Coverage

### System Edge Cases (from 03-edge-cases)

- **Slope Limit Reached:** If snapping into a slope steeper than $45°$, the dash target offset (calculated from the target position) sits on the slope. `StrikeMotor` will move towards the target and stop upon touching the wall/slope geometry.
- **Stamina Exhaustion:** If stamina reaches $0$, `StrikeAction` rejects new attack intents. If stamina is exhausted mid-dash, the current dash finishes (does not interrupt in-progress strikes, preventing jarring stop bugs).
- **Form Shift Mid-Strike:** If the player inputs a form shift (e.g. `Z` to Panther) during a strike dash, the Shift proposal will compete. Form shift has `Priority.FORCED` with weight $1000$ (overriding normal priority). `EntityController` handles updating the allowed motor mask, disabling `StrikeMotor` and canceling the dash.

### Mechanic-Specific Edge Cases

- **Target Defeated Mid-Dash:** If the target is defeated (or deleted) by another source while the player is dashing toward it:
  - *Resolution:* `StrikeMotor.tick` checks `is_instance_valid(_target_node)` and target HP. If dead/invalid, it resets target tracking and stops dash.
- **Wall Occlusion / Snapping through walls:** If a target is behind a wall, snapping to it directly could cause the player to clip or get stuck.
  - *Resolution:* Since the player uses Godot's native physics (`move_and_slide()`) within `StrikeMotor`, collisions with walls will block the player's path normally.
- **Multiple Attack Inputs (Button Mashing):** Rapidly clicking LMB during a dash should not reset or queue multiple dashes.
  - *Resolution:* `StrikeAction.tick` ignores `wants_attack` inputs while `_strike_in_progress` is true.

---

## Implementation Handoff

**Reading order for the implementing `/slice` Builder:**
1. Read this document top to bottom.
2. Extend `LocomotionState.ID` in [locomotion_state.gd](file:///home/francisco/Programming/fbeltran/zelda-druid-godot/graybox-prototype/scripts/player_action_stack/movement/locomotion_state.gd) to include `STRIKE = 14`.
3. Add `StrikeMotor` to [form_broker.gd](file:///home/francisco/Programming/fbeltran/zelda-druid-godot/graybox-prototype/scripts/player_action_stack/form/form_broker.gd) motor mask for `FORM_MONKEY`.
4. Create [strike_motor.gd](file:///home/francisco/Programming/fbeltran/zelda-druid-godot/graybox-prototype/scripts/player_action_stack/movement/motors/strike_motor.gd) and add it to `MovementBroker` in `main.tscn`.
5. Create [strike_action.gd](file:///home/francisco/Programming/fbeltran/zelda-druid-godot/graybox-prototype/scripts/player_action_stack/combat/strike_action.gd) and add it to `CombatBroker` in `main.tscn`.
6. Update `CombatBroker.gd` to load, configure, and tick `StrikeAction` for Monkey Form.
7. Run the GUT unit test suite and add tests covering strikes, snapping, target validation, and stamina drain.

