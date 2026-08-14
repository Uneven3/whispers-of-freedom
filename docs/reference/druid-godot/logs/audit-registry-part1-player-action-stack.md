# Architecture Audit — Decision Registry Part 1
# Source: artifacts 01, 02, 03 — player-action-stack
# Used by: Session 3 (checks A–K)

---

## FROM STAGE 01 — Scope & Boundaries

### 01-A. Named Architectural Layers

Each system has its own strict top-to-bottom chain (no shared cluster-wide stack):

**Movement layers (top→bottom):**
1. Brain (Input Generation) — abstract; PlayerBrain, AIBrain
2. Broker (Orchestrator + Arbiter) — MovementBroker
3. Motors (Execution) — one Motor per locomotion state
4. Services & Body (Foundational) — GroundService, LedgeService, WaterService, MountService; Body

**Camera layers (top→bottom):**
1. CameraBrain (Input Generation) — abstract; PlayerCameraBrain in MVP
2. CameraBroker (Orchestrator + Arbiter)
3. CameraModes & CameraEffects (Execution) — Modes mutually exclusive; Effects stackable
4. CameraServices & Lens (Foundational) — OcclusionService; Lens

**Combat layers (top→bottom):**
1. Brain (shared with Movement) — no separate input layer for Combat
2. CombatBroker (Orchestrator + Arbiter)
3. Combat Actions (Execution, moveset-bound) — TakedownAction, ParryAction+CounterAction, BowAction
4. CombatServices & CombatTargeting (Foundational) — HitDetectionService, LockOnService

**Form layers (top→bottom):**
1. Brain (shared with Movement) — wants_form_shift field on Intents
2. FormBroker (Orchestrator + Arbiter)
3. Form Shape Swap (Execution)
4. FormServices (Foundational — minimal, placeholder)

### 01-B. Cross-System Access Rules (read-only vs. mutable)

| Component | Mutable Owner | Read-Only Consumers |
|-----------|--------------|---------------------|
| Body (full) | MovementBroker, Motors | BodyReader → Camera, Combat, external |
| StaminaComponent (full) | EntityController (lent to Motors AND Combat actions) | StaminaReader → UI, AI perception, Combat (balance) |
| LocomotionState (full) | MovementBroker only (set_state()) | LocomotionStateReader → Camera, Combat, UI, AI perception |
| FormComponent (full) | FormBroker only (set_form()) | FormReader → Combat, Audio, UI, Progression |
| Lens | CameraBroker (via set_target_transform) | CameraReader → PlayerBrain, future Audio/VFX |
| LockOnTargetReader | LockOnService (owns the surface) | Camera LockOnMode, UI reticle, Audio |
| AimingReader | CombatContextStub/CombatBroker | Camera AimMode |

**Declared shared-mutable exception:** StaminaComponent is mutable to both Motors AND Combat actions, lent by EntityController composition root.

### 01-C. Enumerated Sets That Must Remain Consistent Across Artifacts

**Intents fields (MVP final list — closes Deferred TODO §6):**
- Movement: `move_dir`, `wants_jump`, `wants_sprint`, `wants_sneak`, `wants_climb_release`, `wants_glide`, `wants_mount`
- Combat: `wants_attack`, `wants_parry`, `wants_dodge`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`
- Form: `wants_form_shift: StringName`
- Aim: `aim_target: Vector3`
- **Total: 15 fields**

**TickSlot enum (must be ordered 1→6 with these exact assignments):**
1. BRAIN_INTENTS
2. CAMERA_BRAIN_INPUT
3. FORM_BROKER
4. MOVEMENT_BROKER
5. COMBAT_BROKER
6. CAMERA_BROKER

**Active form values (StringName):**
- `&"panther"`, `&"monkey"`, `&"avian"`
- Exactly three discrete forms; no blending.

**Damage type StringNames (DamageEvent.damage_type):**
- `&"melee"`, `&"ranged"`, `&"stealth"`

**Stagger class StringNames (DamageEvent.stagger_class):**
- `&"none"`, `&"light"`, `&"heavy"`, `&"finisher"`

**FORCED proposal weight registry (partial at Stage 1, completed at Stage 3/4):**
- FormShiftProposal: weight 100
- Health defeat: weight 200
- Interaction cinematic: weight 150
- Combat stagger: weight keyed by stagger_class (mutually distinct, distinct from 100)

**Proposal priority categories (all four Brokers):**
- `FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT`

**CameraMode inventory:**
- FollowMode, AimMode, LockOnMode (mutually exclusive)

**CameraEffect inventory:**
- DipEffect, ShakeEffect, FOVZoomEffect, FollowEaseInEffect (stackable)

**EffectRequest effect_type StringNames (validated at startup):**
- `&"shake"`, `&"dip"`, `&"fov_zoom"`

**Combat moveset per form:**
- Panther → TakedownAction
- Monkey → ParryAction + CounterAction
- Avian → BowAction

**Debug F-key registry (claimed by this cluster):**
- F1 → Movement
- F2 → Camera
- F3 → Combat
- F4 → Form

**Debug context nodes:**
- MovementContext, CameraContext, CombatContext, FormContext

**Locomotion states that gate combat moveset (no attacks allowed):**
- CLIMB, SWIM, MOUNT, DEFEAT, CINEMATIC (STAGGER states also implied by DeathMotor/CinematicMotor context)

**EntityController downward calls on form_shifted (fan-out — expanded to 4 in Stage 3):**
1. MovementBroker.set_allowed_motors(motor_mask)
2. MovementBroker.inject_forced_proposal(FormShiftProposal)
3. Body.swap_collision_shape(shape)
4. FormBroker.set_shifts_enabled(bool) — added in Stage 3 for DEFEAT/CINEMATIC gate

**EntityController upward-signal-forward routes (Rule 13):**
- CombatBroker.stagger_triggered → MovementBroker.inject_forced_proposal(FORCED)
- HealthComponent.defeated / hp_zeroed → MovementBroker.inject_forced_proposal(RAGDOLL|DEFEAT)
- FormBroker.form_shifted → set_allowed_motors + inject_forced_proposal(FormShiftProposal) + Body.swap_collision_shape
- Future: InteractionBroker.cinematic_requested → MovementBroker.inject_forced_proposal(CINEMATIC)

### 01-D. Entry Points Reserved for Future/External Systems

- `Body.teleport(pos, rot)` — reserved for future FastTravelService (single non-motor position choke point)
- `CameraRig.set_target(BodyReader)` — mandated Stage-1 MVP contract for entity-swap (MountManager, PlayerController)
- `Brain` abstract base — future RemoteBrain fits same contract
- `CameraBrain` abstract base — future RemoteCameraBrain fits same contract
- `MovementBroker.inject_forced_proposal()` — reserved for EntityController only (single choke point for cross-system locomotion interrupts)

### 01-E. OUT OF SCOPE Declarations

**Movement OUT OF SCOPE (must accommodate but not implement):**
- Shapeshifting/Form selection (owned by Form)
- Combat actions (owned by Combat)
- Camera behavior (owned by Camera)
- World interaction (Interaction system — LOOSE bridge)
- Weapon durability/swap
- Cinematic/scripted cameras
- Mounted combat (out of MVP)
- Swimming combat/diving
- Fast travel/teleport (entry point reserved, not implemented)
- Multiplayer/network sync (entry point reserved via RemoteBrain)
- NPCs (non-enemy)

**Camera OUT OF SCOPE (must accommodate but not implement):**
- Cinematic/scripted cameras (future CinematicMode slot)
- Photo mode (future — Lens is the single transform write surface)
- First-person view (future Mode)
- Split-screen/per-player cameras (future)
- Per-form camera reframing — **BANNED BY DESIGN** (not just deferred; composition root has no field to receive Form)
- Hit-pause (owned by future TimeScaleService Autoload)
- Dynamic zone-based fixed framing
- Camera-relative audio/lighting/VFX

**Combat OUT OF SCOPE:**
- Weapon durability/swap
- Mounted combat
- Swimming/diving combat
- Damage numbers/floaty UI
- Hit-pause implementation (Camera only requests; TimeScaleService owns)
- Screen-shake implementation (requests via CameraRig.request_effect only)
- HP ownership (owned by Health)
- Death/respawn logic
- Progression curves

**Form OUT OF SCOPE:**
- Per-form camera reframing (banned — Camera ↔ Form seam is NONE)
- Per-form Movement motor parameters (Movement owns parameter tables; Form declares mask only)
- Unlock/progression gating of forms (Progression — LOOSE bridge)
- Transformation animation/particle burst (Audio + VFX — LOOSE bridges)
- Shapeshift during cutscenes (cinematic scope — CINEMATIC gate covers this)
- Partial/hybrid forms
- Per-form HP pools

### 01-F. EntityController Role (from Entity Composition section)

- Owns StaminaComponent (lives at entity level, lent to Motors and Combat)
- Wires three system Brokers (Movement, Combat, Form) in known order at _ready()
- Forwards upward signals to downward calls (Rule 13 — the ONLY place fan-out happens)
- Does NOT implement gameplay logic
- Publicly exposes: BodyReader, StaminaReader, LocomotionStateReader, FormReader

### 01-G. CameraRig External Dependencies

Inputs consumed by CameraRig:
- target_body_reader: BodyReader (from active Entity — swappable via set_target())
- aiming_reader: AimingReader (from CombatContextStub/real Combat)
- lock_on_reader: LockOnTargetReader (from CombatContextStub/real Combat)

Output exposed by CameraRig:
- CameraReader (consumed by PlayerBrain for aim_target; future Audio/VFX)

### 01-H. Tick Architecture (canonical slot order)

```
Slot 1: Brain.gather_intents()
Slot 2: PlayerCameraBrain.gather_camera_input()
Slot 3: FormBroker.tick(intents, delta)
Slot 4: MovementBroker.tick(intents, delta)
Slot 5: CombatBroker.tick(intents, delta)
Slot 6: CameraBroker.tick(camera_input, delta)
```
Plus: Lens._process() — visual interpolation — the cluster's ONLY _process override.

GameOrchestrator is the sole _physics_process owner. All other nodes have _physics_process disabled.

---

## FROM STAGE 02 — Data Flow

### 02-A. Execution Control Pattern

Single `GameOrchestrator` Autoload (`PROCESS_MODE_ALWAYS`) — the sole owner of `_physics_process` in gameplay code.
- Registration methods walk bundle refs and call `set_physics_process(false)` on every contained Node.
- After registration, no other Node in the cluster has an active `_physics_process`.

### 02-B. Declared Execution Order (6-slot, step-by-step)

**Slot 1 — BRAIN_INTENTS** (`for eb in _entity_bundles: eb.gather_intents()`)
- Per entity, polymorphic. Brain.populate(_intents). Every field populated every frame.
- Fail Early: `assert(_intents.is_complete())` after populate.
- Structural: Brain has no field for Body, Stamina, LocomotionState, MovementBroker.

**Slot 2 — CAMERA_BRAIN_INPUT** (`_camera_bundle.gather_camera_input()`)
- Single-rig. CameraBrain.populate(_input). Writes look_delta, wants_lock_on_toggle, wants_aim.
- Fail Early: gated by `if _camera_bundle:`.
- Structural: CameraBrain has no field for Intents. AI never drives camera.

**Slot 3 — FORM_BROKER** (`for eb in _entity_bundles: eb.tick_form(delta)`)
- Per entity. FormBroker.tick(_intents, delta). Validates wants_form_shift.
- On shift: FormComponent.set_form → form_shifted signal → EC fan-out (3 downward calls on same frame).
- Fail Early: `assert(wants_form_shift in available_forms() or == &"")`.
- Structural: FormBroker does NOT hold MovementBroker reference.

**Slot 4 — MOVEMENT_BROKER** (`for eb in _entity_bundles: eb.tick_movement(delta)`)
- Per entity. MovementBroker.tick(_intents, delta). Internal sub-loop:
  1. Drain FORCED queue (_external_proposals)
  2. Service fact-gathering (update_facts on all Services)
  3. Proposal arbitration (gather_proposals on all Motors and Services, FORCED queue, sort by category+weight, pick winner)
  4. State transition (on_exit → LocomotionState.set_state → state_changed signal → on_enter)
  5. Motor execution (on_tick: motion math, stamina ops, Body.apply_motion)
- Fail Early: `assert(winner.target_state in allowed_motors)`, `assert(active_motor != null)`.
- Structural: MovementBroker sole holder of mutable LocomotionState. Motors hold mutable Body and StaminaComponent.

**Slot 5 — COMBAT_BROKER** (`for eb in _entity_bundles: eb.tick_combat(delta)`)
- Per entity. CombatBroker.tick(_intents, delta). Hit-resolution only (not intent gathering).
- Reads post-motion BodyReader. Dispatches active form's moveset action.
- 1. active_action.gather_decision (side-effect-free)
- 2. active_action.execute → DamageEvent array
- 3. Per DamageEvent: emit hit_landed, optionally stagger_triggered (→ target EC → inject_forced_proposal queued for N+1)
- 4. LockOnService.update_candidates()
- Fail Early: `assert(active_action != null)`, `assert(damage_event.amount >= 0.0)`.
- Structural: CombatBroker does NOT hold MovementBroker reference.

**Slot 6 — CAMERA_BROKER** (`_camera_bundle.tick_camera(delta)`)
- Single-rig. CameraBroker.tick(camera_input, delta).
- 1. Mode arbitration (TransitionProposal from each Mode, pick winner)
- 2. Mode dispatch (base transform, OcclusionService clamp)
- 3. Effect iteration (DipEffect, ShakeEffect, FOVZoomEffect, FollowEaseInEffect)
- 4. Lens write (set_target_transform → Lens stores current/previous for interpolation)
- Fail Early: `assert(target_body_reader != null)`, `assert(active_mode != null)`, `assert(effect_request.effect_type in registered_effect_types)`.
- Structural: CameraBroker holds BodyReader, AimingReader, LockOnTargetReader, LocomotionStateReader — all read-only. NO Form or FormReader field.

**Visual Interpolation — Lens._process():**
- Only node in cluster with _process override.
- `Camera3D.global_transform = previous.interpolate_with(current, Engine.get_physics_interpolation_fraction())`
- Fail Early: asserts both transforms exist before interpolating. Enabled after first physics-tick write.

### 02-C. Structural Rules Mandated for All Components

- Every component's `_physics_process` is disabled by GameOrchestrator registration walk.
- `Lens` is the ONLY node with a `_process` override (documented single exception).
- `CameraRig` has no field of type `Form` or `FormReader` (structurally enforced Camera↔Form NONE coupling).
- Brokers (slots 3–5) treat `Intents` as read-only by contract (Brain mutates in slot 1 only).
- Until GDScript supports `const` parameters, enforced by debug-build hash assertion on `_intents`.
- Registry freezes at first tick (`_registry_frozen = true`); late registration asserts.

### 02-D. Bundle Types and Their Contracts

**EntityTickBundle:**
- Fields: `_intents: Intents`, `_brain: Brain`, `_form_broker: FormBroker`, `_movement_broker: MovementBroker`, `_combat_broker: CombatBroker`
- `_init` asserts all four refs non-null (entity coherence guaranteed at construction)
- Public methods: `gather_intents()`, `tick_form(delta)`, `tick_movement(delta)`, `tick_combat(delta)`

**CameraTickBundle:**
- Fields: `_input: CameraInput`, `_brain: CameraBrain`, `_broker: CameraBroker`
- `_init` asserts both refs non-null
- Public methods: `gather_camera_input()`, `tick_camera(delta)`

**GameOrchestrator:**
- Fields: `_entity_bundles: Array[EntityTickBundle]`, `_camera_bundle: CameraTickBundle`, `_registry_frozen: bool`, `_paused: bool`
- `register_entity_bundle(bundle: EntityTickBundle)` — typed, asserts not frozen, no duplicate
- `register_camera_bundle(bundle: CameraTickBundle)` — typed, asserts not frozen, single-rig MVP

### 02-E. Intents Struct Contract (from Stage 2)

- `_intents` is bundle-private. Brain mutates via parameter; brokers read via parameter.
- `Intents.is_complete()` checks every declared field is non-null (object fields) and `aim_target` is finite.
- Every Brain populates EVERY field EVERY frame; defaults are explicit (false/zero/empty StringName).

---

## FROM STAGE 03 — Edge Cases

### 03-A. Conflict Resolution Rules — Required Struct Fields

**TransitionProposal fields (used by all four Brokers):**
- `from_mode` (current locomotion/camera mode)
- `to_mode` / `target_state` (proposed new mode)
- `category` (FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT)
- `override_weight: int` (tie-break within category)
- source-tagging fields for audit

**Arbitration rule (shared across all four Brokers):**
1. Priority category: FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT
2. override_weight tie-break within category
3. Stable-order final tie-break if category + weight + target_state all match (safe tie, first-wins)
4. Fail-early assert if category + weight match but target_state DIFFERS (hostile ambiguous tie)

### 03-B. Interrupt/Override Mechanisms and Required Interface Surface

**FormBroker.set_shifts_enabled(bool)** [NEW — Stage 3 addendum]:
- Called by EntityController when LocomotionState.state_changed fires
- `new in {DEFEAT, CINEMATIC}` → set_shifts_enabled(false)
- `old in {DEFEAT, CINEMATIC} and new not in {DEFEAT, CINEMATIC}` → set_shifts_enabled(true)
- When false: FormBroker.tick early-returns before set_form, no emission, no fan-out
- Rationale: ragdoll skeleton-swap is physically volatile; cutscene beat integrity

**MovementBroker.inject_forced_proposal(proposal)** — single choke point for cross-system interrupts:
- Called exclusively by EntityController (Rule 13 — audit-time enforcement; runtime assert deferred to graybox phase)
- Queues proposal in _external_proposals; drained at next slot 4

**Registered FORCED weight table (Stage 3 constraint, Stage 4 deliverable):**
- FormShiftProposal: weight 100
- Combat stagger (stagger_class → weight): mutually distinct within table, distinct from 100
  - &"heavy": weight 80 (from Trace 2 / Trace C examples)
  - &"light": weight 40 (from Trace 3 / Trace C examples)
- Health defeat: weight 200
- Interaction cinematic: weight 150
- Constraint: weight registry must be INJECTIVE (no two sources share a weight)
- Runtime: unregistered or duplicate weight fires assert

**CameraRig.request_effect(EffectRequest)** — single choke point for camera effects:
- Called by Combat for screen shake
- Called by CameraRig itself for DipEffect (impact filter), FollowEaseInEffect (set_target rebind)
- Validates effect_type against startup-registered set; unknown type = fail-loud

**EntityController.set_target(BodyReader)** — for mount/entity swap:
- Disconnects from previous BodyReader.impact_detected, connects to new one
- Pushes FollowEaseInEffect (~200 ms)

### 03-C. Data-Layer Invariants (validate-style checks)

**Intents immutability during slots 3–5:**
- `assert(false, "Intents mutated outside slot 1")` if re-mutation detected
- Debug-build: _intents.compute_hash() taken before slot 3, re-checked after slots 3, 4, 5

**Stagger class → weight injectivity:**
- stagger_class → weight mapping must be injective within tiers (Combat Stage 4/6 deliverable)

**Motor mask non-empty:**
- `assert(motor_mask_for(new_form).size() > 0)` — every form must have ≥ 1 valid motor

**DamageEvent amount:**
- `assert(damage_event.amount >= 0.0)` — negative = healing smuggled through wrong contract

**Ambiguous hostile-tie assert:**
- `assert(false, "Ambiguous Transition Tie — [broker_name] [category] weight [N]: targets {A, B}")` when category + weight match but target_state differs

**FORCED proposal target validation:**
- `assert(winner.target_state in allowed_motors)` — FORCED proposal targeting motor not in form mask crashes frame

**_external_proposals serialization requirement (rollback):**
- Queue is NOT empty at end-of-frame (slot 5 injects for slot 4 of N+1)
- Rollback snapshots MUST serialize _external_proposals

### 03-D. External Interruption Handling

**Pause:**
- GameOrchestrator._paused: bool → early-return in _physics_process skips all 6 slots
- Lens.process_mode = PROCESS_MODE_PAUSABLE (required — documented)
- No per-node `if paused` allowed

**Death (DEFEAT):**
- Path: HealthComponent.defeated → EC.on_defeated → inject_forced_proposal(DEFEAT, weight=200) → MovementBroker drains next slot 4 → LocomotionState.set_state(DEFEAT) → state_changed fires → EC.handler calls FormBroker.set_shifts_enabled(false) → DeathMotor.on_enter
- Combat gated during DEFEAT: CombatBroker reads LocomotionStateReader == DEFEAT, moveset gate refuses all actions
- Form gated during DEFEAT: set_shifts_enabled(false) active

**Cutscene (CINEMATIC):**
- Path: Interaction.cinematic_requested → EC.on_cinematic_requested → inject_forced_proposal(CINEMATIC, weight=150) → same path as DEFEAT
- Weight: 150 < 200 — death overrides cutscene if same frame
- Form gated: same set_shifts_enabled(false) mechanism
- Combat gated: same LocomotionStateReader == CINEMATIC gate

**Stage 3 addendum to Stage 1 Form↔Movement fan-out:**
- EC downward calls expand from 3 to 4: adds FormBroker.set_shifts_enabled(bool) on LocomotionState.state_changed

### 03-E. Cross-System Edge Cases (required structural behaviors)

**X1 — Form shift + Combat stagger same frame (different entities):** Independent paths, no shared queue → benign co-occurrence.

**X2 — Fall impact + Form shift same frame:** Slot 3 fan-out first (Avian shape active before slot 4 services update). impact_detected fires AFTER form shift committed. Camera/Health observers read post-transition state.

**X3 — Mount swap:** set_target outside tick loop. Dormant entity's bundle gated by authority flag. Missing FormBroker on mount = silent no-op (structural property, not a data error).

**X4 — Parry-during-climb (canonical "Brain is blind" proof):** Brain populates wants_parry. Slot 4 keeps CLIMB. Slot 5 reads LocomotionStateReader == CLIMB; moveset gate refuses ParryAction. No DamageEvent, no stamina drain.

**X5 — Two staggers same entity same frame:** Both FORCED proposals enqueued. Weight tie-break resolves; assert fires if identical weight + different target_state.

---

## PRECONDITION CHECKS (Rule A / B / C)

### Rule A — Completeness
- [x] All 6 artifacts confirmed present (listed in implementation plan):
  01-scope-and-boundaries-player-action-stack.md (57KB)
  02-data-flow-player-action-stack.md (49KB)
  03-edge-cases-player-action-stack.md (42KB)
  04-systems-and-components-player-action-stack.md (56KB)
  05-project-scaffold-player-action-stack.md (21KB)
  06-interfaces-and-contracts-player-action-stack.md (67KB)

### Rule B — Compatibility-redirect
- [x] Stage 01 is NOT a compatibility-redirect stub. It is the full cluster-scoped Stage 1.
  Evidence: 490 lines, 57KB, begins with "# Player Action Stack (Cluster A) Architecture — Scope & Boundaries"
  No "DEPRECATED — Compatibility Redirect" language present.
  Rule B: not triggered.

### Rule C — No partial-cluster audits
- [x] All stages 2–6 are authored under the `-player-action-stack` cluster suffix.
  No leftover per-system slugs (movement-only, camera-only, etc.) were found in the directory listing.
  The directory contains only: 01/02/03/04/05/06-player-action-stack.md + 00-system-map.md + migration-safety-report-movement.md
  Rule C: not triggered.

**Preconditions PASS — audit may proceed.**

---

## NOTES FOR SESSION 3

- Stage 1 explicitly states Stage 3 addendum: EC fan-out expands from 3 to 4 downward calls (adds set_shifts_enabled). Stage 1 file itself NOT edited; carried into Stage 6. **Check A/E/F**: verify Stage 6 carries this.
- Stage 1 declares stagger weights by stagger_class; Trace examples in 02/03 use: heavy=80, light=40. **Check B**: verify Stage 4/6 weight table matches these.
- Stage 2 TickSlot enum values must be verified in Stage 5 scaffold and Stage 6 contracts. **Check B**.
- Stage 2 documents `_paused: bool` on GameOrchestrator; Stage 3 reinforces. **Check H**: verify Stage 6 has this.
- Camera↔Form NONE coupling: CameraRig must have NO Form/FormReader field. **Check I + Check G**: verify Stage 6 contract has no Form field.
- `CombatContextStub` is declared in Stage 1 entity composition. **Check A**: verify Stage 4/5/6 carry this.
- Lens.process_mode = PROCESS_MODE_PAUSABLE is a Stage 3 runtime enforcement contract. **Check H**: verify Stage 6.
- FormBroker.set_shifts_enabled(bool) is new in Stage 3. **Check E/F**: verify Stage 6 declares this method.
- stagger_class injectivity is a Stage 3 constraint → Stage 4 deliverable. **Check E**: verify Stage 4 weight table.
- `_external_proposals` serialization is a Stage 3 rollback contract. **Check H**: see if Stage 6 documents this.
