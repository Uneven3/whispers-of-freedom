> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Edge Case Examples

This artifact contains the narrative traces and examples extracted from the core `03-edge-cases-player-action-stack.md` artifact to prevent prose bloat in the main architectural contract.

## Intra-System Conflict Examples

### Movement
Link is clinging to a cliff with zero stamina, `ClimbMotor` stops proposing CLIMB-continue, `FallMotor` proposes FALL (DEFAULT, 10), and an exploding barrel's Combat/Health bridge injects a FORCED RAGDOLL (weight 100). The Broker arbitrates under the shared rule — category `FORCED > DEFAULT` wins outright, `RagdollMotor` activates. No weight tie-break is exercised; the category break won.

**Cluster-A-specific angle:** slot 3's Form fan-out enqueues a FORCED `FormShiftProposal(weight 100)` into the entity's `MovementBroker._external_proposals` on the same frame a previous-frame cross-system stagger has also landed in the queue (e.g., `stagger_class=&"heavy"`, weight=80 in the registry). Both are FORCED. Arbitration: form-shift (100) > stagger (80) — shift wins. If the registry were miswired to weight 100 = 100, the assert fires. The rule forces the designer to make the weight registry injective.

### Camera
`AimMode` and `LockOnMode` can both propose PLAYER_REQUESTED on the same frame: `AimingReader.is_aiming()` flips true (player drew the bow this tick) while `LockOnTargetReader.has_target()` also flips true (a target walked into lock-on range this tick). **Resolution:** `AimMode` declares a higher `override_weight` than `LockOnMode`. Rationale: archery aim already frames a specific target via camera-forward; overlaying lock-on recomposition would snap the frame mid-draw. Equal-weight tie fires the assert.

### Combat
Only one moveset is active per entity at a time (keyed off `FormReader`). Intra-moveset conflict surface: within a moveset, two actions can flag themselves ready on the same frame.
- **Monkey:** `ParryAction` window is open AND `CounterAction` trigger fires AND `wants_dodge` is true. Three actions ready; only one can fire per tick. **Resolution:** each moveset declares an intra-moveset priority list.
- **Panther:** takedown proximity met AND `wants_dodge` true. Takedown is the higher-priority action; dodge fires only if takedown's proximity check fails.
- **Avian:** bow drawn (`wants_archery_aim` sustained) AND `wants_archery_release` on the same frame. Canonical release-this-frame semantics: release wins.

### Form
- **`wants_form_shift == current_form`.** No-op. Early return. No `set_form`, no `form_shifted` emission, no fan-out. Silent because requesting a shift to the current form is legal idle-state behavior.
- **`wants_form_shift` re-populated mid-slot-3.** Impossible under the Stage 1 / Stage 2 contract. If observed, `assert(false, "Intents mutated outside slot 1")` fires.

---

## Narrative Traces (Cross-System)

Four scenarios exercising the cross-system paths at increasing complexity.

### Trace 1 — Intra-Movement conflict: exploding barrel during cliff climb
The baseline — single-entity, single-Broker arbitration as the reader's mental-model entry point.

Link is clinging to a cliff, stamina at 0. Frame N slot 4: `ClimbMotor.gather_proposals` sees `StaminaReader.is_exhausted() == true` and stops proposing CLIMB continuation. `FallMotor.gather_proposals` proposes FALL (DEFAULT, weight 10). Same frame, an exploding barrel's Combat/Health bridge injects a FORCED RAGDOLL proposal (weight 100) into `_external_proposals` via `EC.on_proximity_explosion` → `MovementBroker.inject_forced_proposal`.

MovementBroker arbitration: FORCED (RAGDOLL) > DEFAULT (FALL). RAGDOLL wins. `ClimbMotor.on_exit()` → `LocomotionState.set_state(RAGDOLL)` → `RagdollMotor.on_enter(body, stamina)`. Link ragdolls off the cliff instead of a plain fall.

### Trace 2 — Cross-system conflict: form-shift into stagger
The load-bearing cluster-only trace. Player-side form-shift colliding with an incoming enemy attack, both resolving on the same frame without corrupting each other.

**Pre-tick state.** Player Monkey form, `IDLE` locomotion, parry window open from a prior slot 5. One enemy mid-`ATTACK_SWING`, about to land a hit on the player.

**Frame N slot 1.** `PlayerBrain.populate` writes `wants_form_shift=&"avian", wants_parry=true, ...`. Enemy `AIBrain.populate` writes `wants_attack=true`.

**Slot 3 — Form fan-out.** Player FormBroker reads `wants_form_shift=&"avian"`, validates, calls `FormComponent.set_form`, emits `form_shifted(&"avian")` upward. EC's handler fires synchronously:
- `MovementBroker.set_allowed_motors(motor_mask_for("avian"))`
- `MovementBroker.inject_forced_proposal(FormShiftProposal(target=FALL, weight=100))`
- `Body.swap_collision_shape(shape_for("avian"))`

**Slot 4 — player and enemy Movement.**
- Player: MovementBroker drains the FormShiftProposal. Arbitrates with Avian mask — `SprintMotor` out of mask; `GlideMotor` proposes DEFAULT; FormShiftProposal FORCED (100) wins. Transition → FALL.
- Enemy: MovementBroker continues AttackSwingMotor, advances toward player's previous position. Player's new position is ground truth for slot 5.

**Slot 5 — hit resolution.**
- Enemy `CombatBroker.tick` reads post-motion `BodyReader`. Resolves AttackSwingAction — produces `DamageEvent{stagger_class: &"light"}`. Calls `Health.apply_damage(event)`. Emits `stagger_triggered(event)` upward. Player's `EC.on_external_stagger` builds FORCED `TransitionProposal(target=STAGGER_LIGHT, weight=40)`, calls `MovementBroker.inject_forced_proposal`. **Queued for frame N+1 slot 4.**
- Player `CombatBroker.tick` reads `LocomotionStateReader.get_active_mode() == FALL`. **Moveset gated off**. `ParryAction` cannot fire.

**Slot 6.** Camera reads post-motion Body; `FollowMode` reframes around player. Lens interpolates.

**Frame N+1 slot 4.** Player MovementBroker drains STAGGER_LIGHT. Arbitrates against internal proposals. FORCED (40) wins. Transition → STAGGER_LIGHT mid-air. Player staggers while falling.

### Trace 3 — Death during climb
Demonstrates the EC-driven DEFEAT path, the shift-gate activation, and Cluster A's response to a LOOSE-bridge death signal.

**Pre-tick state.** Link climbing a cliff, 20% HP, Panther form. Enemy archer arrow in flight.

**Frame N slot 5.** Enemy archer's `CombatBroker.tick` resolves arrow hit. Produces `DamageEvent`. Calls `Health.apply_damage(event)`. Health emits `defeated` upward on player's `EC` synchronously.
Player `EC.on_defeated` builds FORCED `TransitionProposal(target=DEFEAT, weight=200)` and queues it via `MovementBroker.inject_forced_proposal`.

**Frame N slot 6.** Camera follows normally (player still clinging to cliff).

**Frame N+1 slot 4.** Player MovementBroker drains DEFEAT proposal. Arbitration: FORCED (200) beats ClimbMotor's DEFAULT. DEFEAT wins.
- `ClimbMotor.on_exit()`.
- `LocomotionState.set_state(DEFEAT)`.
- **`state_changed(CLIMB, DEFEAT)` signal fires.** EC's handler calls `FormBroker.set_shifts_enabled(false)` — **the gate closes**.
- `DeathMotor.on_enter(body, stamina)`. Ragdoll physics engage.

**Frame N+1 slot 5.** Player `CombatBroker.tick` reads DEFEAT. Moveset gated off.

**Frame N+1 slot 3 and beyond.** If player presses shapeshift mid-ragdoll, `FormBroker.tick` checks `_shifts_enabled == false` and early-returns. No skeleton swap mid-ragdoll.

### Trace 4 — Cutscene enter mid-attack
Demonstrates weight-ordering among FORCED sources (CINEMATIC 150 vs DEFEAT 200).

**Pre-tick state.** Player Monkey form, `IDLE` locomotion, parry window open. Enemy mid-`ATTACK_SWING`. Interaction system detects proximity to an NPC trigger.

**Frame N — before slot 5.** Interaction emits `cinematic_requested` upward. Player `EC.on_cinematic_requested` builds FORCED `TransitionProposal(target=CINEMATIC, weight=150)` and queues it.

**Frame N slot 5.** Enemy `CombatBroker.tick` runs — attack detected. Player `CombatBroker.tick` reads `IDLE` (CINEMATIC queued for N+1). Moveset active. `ParryAction.gather_decision` succeeds. `CounterAction.execute` fires — produces `DamageEvent{stagger_class: &"heavy", weight: 80}`. Emits `stagger_triggered(event)` upward. Enemy `EC.on_external_stagger` builds FORCED STAGGER_HEAVY, queued for N+1 slot 4.

**Frame N slot 6.** Camera follows player normally.

**Frame N+1 slot 4 — two entities.**
- Player MovementBroker drains CINEMATIC (150). Beats DEFAULT. `LocomotionState.set_state(CINEMATIC)`. **`state_changed(IDLE, CINEMATIC)` fires.** EC calls `FormBroker.set_shifts_enabled(false)`. `CinematicMotor.on_enter`.
- Enemy MovementBroker drains STAGGER_HEAVY (80). Beats DEFAULT. Enemy staggers.

**Frame N+1 slot 5.** Both movesets gated off (`CINEMATIC` for player, `STAGGER_HEAVY` for enemy).
