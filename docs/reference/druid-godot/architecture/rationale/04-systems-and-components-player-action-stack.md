> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Systems and Components

> **Scope of this artifact.** Cluster-scoped Stage 4 for Cluster A: **Movement, Camera, Combat, Form** (per `00-system-map.md` § 2–3, `01-scope-and-boundaries-player-action-stack.md`, `02-data-flow-player-action-stack.md`, and `03-edge-cases-player-action-stack.md`). Inventories the concrete Godot Nodes, declares SSoT ownership across the four systems, pins the game-specific performance thresholds that downstream stages must respect, and registers the cluster-wide FORCED-proposal **weight table** required by `03-edge-cases-player-action-stack.md` § Weight registry.

---

## Concrete Inventory

*Per-system sub-sections. Strict adjacency within each system; cross-system access goes through `EntityController` or the declared Readers from Stage 1 Shared Contracts. `EntityController` and `CameraRig` are declared once each — the first in the Movement sub-section (where the composition role originates) and the second in the Camera sub-section.*

### Movement

#### 0. Composition Root

- **`EntityController` (`Node3D`, `[script: EntityController.gd]`):** Composition root for every Movement-bearing entity (player, enemy, future NPC). **Not itself a `CharacterBody3D`** — the physical proxy is a sibling child (`Body`, declared in § 5) which owns the `CharacterBody3D` node. This separation is load-bearing per Stage 1: the composition root coordinates siblings and holds no physics state, so it can never be mistaken for a Motor target and can never call `move_and_slide()`. Holds typed references to all sibling children across Movement, Combat, Form (and future Health, Interaction). Four load-bearing roles — no gameplay logic:
  1. **Wires the entity scene tree at `_ready()`.** Instantiates child Brokers in the order required by Stage 2's `EntityTickBundle._init` constraint (Brain + FormBroker + MovementBroker + CombatBroker all non-null at bundle construction). Injects Readers via constructor arguments / typed fields — `BodyReader` to Camera/Combat/Services, `StaminaReader` to UI/AI, `LocomotionStateReader` to Camera/Combat, `FormReader` to Combat/UI/Audio, `AimingReader`+`LockOnTargetReader` (from `CombatContextStub` or real `CombatBroker`) to Camera.
  2. **Signal hub (Rule 13 — events up, data down).** Single subscriber for every upward signal emitted by a sibling: `CombatBroker.stagger_triggered`, `CombatBroker.hit_landed`, `FormBroker.form_shifted`, `HealthComponent.defeated` (LOOSE bridge), `InteractionBroker.cinematic_requested` (LOOSE bridge — future), and `LocomotionState.state_changed` (Stage 3 shift-gate driver). Forwards each event to the correct downward call on a child — never lets siblings talk sideways.
  3. **Sole caller of four cluster-internal surfaces:** `MovementBroker.inject_forced_proposal(proposal)`, `MovementBroker.set_allowed_motors(mask)`, `Body.swap_collision_shape(shape)`, and **`FormBroker.set_shifts_enabled(bool)`** (Stage 3 addition — DEFEAT/CINEMATIC gate). Runtime asserts in Stage 6 enforce caller identity; Stage 4 records the constraint.
  4. **Owns `StaminaComponent`.** Stamina lives at entity level (shared-mutable exception between Movement Motors and Combat Actions) — `EntityController` lends mutable refs to both subsystems explicitly.
  - *Tick authority:* `PROCESS_MODE_INHERIT` and **no `_physics_process` override.** `EntityController` never ticks. `GameOrchestrator` drives every slot via the entity's registered `EntityTickBundle` (Stage 2).

#### 1. Brain Layer (Inputs)

- **`Brain` (abstract Node):** Contract class. `populate(intents: Intents)` — the only public surface. Never subclassed with gameplay logic; subclasses only gather inputs. **Cluster-wide MVP rule:** every concrete Brain populates **every** `Intents` field every frame (combat fields + movement fields + `aim_target` + `wants_form_shift`). Defaults are explicit (`false` / `Vector3.ZERO` / `&""`), not implicit.
- **`PlayerBrain` (Node):** Reads Godot `InputMap` + mouse/gamepad. Populates movement fields, combat fields (`wants_attack`, `wants_parry`, `wants_dodge`, `wants_archery_aim`/`wants_archery_release`, `wants_assassinate`), `wants_form_shift`, and `aim_target` (derived from `CameraReader.get_forward()` projected forward).
- **`AIBrain` (Node):** Reads target perception, distance/LOS, and last-frame Reader state (`BodyReader`, `StaminaReader`, `LocomotionStateReader`, `HealthReader`, `FormReader`, `AimingReader`, `LockOnTargetReader`). Populates the same `Intents` struct — combat fields from day one (Stage 1 Rule 10 lock). `aim_target = target.global_position` when tracking, `Vector3.INF` sentinel otherwise.

#### 2. Broker Layer (Orchestrator)

- **`MovementBroker` (Node):** Arbitrates `TransitionProposal`s for this entity and dispatches the active Motor. Does **not** natively tick — `GameOrchestrator._physics_process` calls `entity_bundle.tick_movement(delta)` → `MovementBroker.tick(intents, delta)` at slot 4. Single choke point for cross-system locomotion interrupts via `inject_forced_proposal(proposal)` (enqueued in `_external_proposals`, drained at the next tick — 1-frame cross-system budget, 0-frame same-frame from slot 3 fan-out).
  - *Per-tick sub-loop (restated from `02-data-flow-player-action-stack.md` slot 4):* drain FORCED queue → Services `update_facts(body_reader)` → gather proposals from Motors + Services → sort (category > weight > stable) → commit winner (`on_exit` / `set_state` / `on_enter`) → `active_motor.on_tick(intents, delta)` → `Body.move_and_slide()`.

#### 3. Motors Layer (Execution)

*Each Motor owns one LocomotionState cell; mutually exclusive per entity (Rule 11).*

| Motor | Responsibility / Rules |
|---|---|
| **`WalkMotor`** | Grounded base locomotion — idle + walk-speed + slope adjustment math. |
| **`SprintMotor`** | Grounded high-speed — drains stamina. |
| **`SneakMotor`** | Reduced speed + low crouch capsule — Panther-only per motor mask. |
| **`JumpMotor`** | Single-frame vertical impulse; transitions to FALL. |
| **`FallMotor`** | Gravity + terminal velocity; evaluates air-strafe `intents.move_dir`. |
| **`GlideMotor`** | Avian-only — drag-rate gravity + wind vectors + stamina drain. |
| **`ClimbMotor`** | Locks to wall normal; 4-way surface movement; heavy stamina drain. |
| **`WallJumpMotor`** | Single-frame impulse away from wall normal; directional from `intents.move_dir`. |
| **`MantleMotor`** | Short pull-up curve from hang-point to ledge-top; stops proposing after completion so Broker falls back to Walk. |
| **`AutoVaultMotor`** | OPPORTUNISTIC parabolic hop over waist-height obstacles; proposed by `LedgeService`. |
| **`SwimMotor`** | Locks Y to `WaterService` fluid plane; combat gated off by `LocomotionStateReader` consumers. |
| **`MountMotor`** | Thin transition boundary for mount/dismount — drops intents, snaps to mount point, emits `mount_ready`. `EntityController` performs the entity swap on the signal. |
| **`CinematicMotor`** | Ignores `intents` entirely, zero locomotion. Held active while `LocomotionState == CINEMATIC`. |
| **`DeathMotor`** | Active during `LocomotionState == DEFEAT`. Ignores `intents`. MVP: root-motion-only. |
| **`StaggerMotor`** | Active during `STAGGER_LIGHT` / `STAGGER_HEAVY` only. Ignores `intents`; plays stagger reaction keyed by `stagger_class`. |
| **`RagdollMotor`** | Kinematic control disabled; proxy-tracks spawned `RigidBody3D` nodes. Used for DEFEAT and `STAGGER_FINISHER`. |

*(Note: Mount-entity registration strategy and Mount-entity Motor set are detailed in Stage 5 deliverables. They run on a `MountTickBundle` [slots 1+4 only] while the player's bundle is deregistered).*

#### 4. Services Layer

- **`GroundService` (`Node3D` with `ShapeCast3D`):** Ground contact + slope normal + surface material tag. `update_facts(body_reader)` fires `force_shapecast_update()`; `gather_proposals` may emit FORCED ground-reattach on transitions from airborne.
- **`LedgeService` (`Node3D` with `ShapeCast3D`):** Wall-climb flags + mantle-clearance endpoints + auto-vault candidates. Emits OPPORTUNISTIC proposals (mantle, auto-vault) and FORCED proposals (ledge snap to prevent floating).
- **`WaterService` (`Area3D` listener):** Subscribes to world water volumes; reports depth + surface height. Emits FORCED enter-swim on submersion, FORCED exit-swim on emersion.
- **`MountService` (`Node3D` with `Area3D`):** Proximity scan for mountable entities; caches closest valid target. Emits PLAYER_REQUESTED mount/dismount proposals when `intents.wants_mount` is true and a target is resolvable.

#### 5. Body & State Layer (SSoT Foundation)

- **`Body` (Node wrapper owning a `CharacterBody3D` child):** Physical proxy. `Body` itself is a thin `Node` that owns the `CharacterBody3D` — this is the **only** node in the entity scene tree that *is* a `CharacterBody3D` (the composition root `EntityController` is a plain `Node3D`). Public write surface on the wrapper: `apply_motion(velocity)` (active Motor only — forwards to the internal `CharacterBody3D.move_and_slide()`), `teleport(pos, rot)` (Motor-exempt choke point for future FastTravel), **`swap_collision_shape(shape: Shape3D)` (called only by `EntityController` on `form_shifted` — Stage 1 Form seam)**. Emits `grounded_changed(is_on_floor: bool)` and `impact_detected(velocity: Vector3)` signals upward (Rule 12 — past events).
- **`LocomotionState` (Node):** State-machine cell. Holds one enum value. `set_state(new_mode)` callable by `MovementBroker` only. Emits `state_changed(old, new)` upward — **Stage 3 subscriber: `EntityController` drives the `FormBroker.set_shifts_enabled` gate on DEFEAT/CINEMATIC entry and exit.**
- **`StaminaComponent` (Node):** Mutable stamina owner. `drain(amount)`, `regen(delta)`, `set_max_stamina(value)`. Lives on `EntityController` because both Movement Motors and Combat Actions hold mutable refs (declared shared-mutable exception — enforced by the composition root lending the ref to exactly these two subsystems).

#### 6. Cross-System Stubs

> **Superseded before Stage 5.** `CombatContextStub` was originally planned as an entity-level sibling implementing `AimingReader` and `LockOnTargetReader` while real `CombatBroker` shipped incrementally. After Stage 4 completed the full Combat inventory (§ 2–5 above), it was determined that the cluster ships real `CombatBroker` from graybox-1 — there is no incremental stub phase. `CombatContextStub` does **not** appear in Stage 5 Diagram A or Stage 6 class declarations. `AimingReader` and `LockOnTargetReader` back directly onto `CombatBroker`-owned state from day one.

---

### Camera

#### 0. Composition Root

- **`CameraRig` (`Node3D`, `[script: CameraRig.gd]`):** Single-instance composition root for the MVP camera (per Stage 1: not per-entity in MVP; split-screen is a future structural change of the composition root, not of `CameraRig`). Holds the `CameraBrain`, `CameraBroker`, Modes/Effects/Services folders, and `Lens`. Pure wiring — no gameplay logic.
  - **Consumer bindings set at construction (top-level scene or `MountManager` on entity swap):**
    - `target_body_reader: BodyReader` — active entity's body; swappable via `set_target()`.
    - `aiming_reader: AimingReader` — from `CombatContextStub` (MVP) or real `CombatBroker` (later).
    - `lock_on_reader: LockOnTargetReader` — same source as `AimingReader`.
    - `locomotion_state_reader: LocomotionStateReader` — for Mode gating (no aim during SWIM, no lock-on during DEFEAT, etc. — Mode-side gating, not Rig concern).
  - **`set_target(target_body_reader: BodyReader)`:** Single choke point for active-entity swap. Disconnects from previous `impact_detected`, connects to new, pushes `FollowEaseInEffect(~200ms)` to soften the transition. Caller is `MountManager` (future) or top-level scene wiring (MVP).
  - **`request_effect(request: EffectRequest)`:** Single choke point for cross-system pushed effects (screen shake from Combat, future damage-flash from Health). Validates `effect_type ∈ registered_effect_types` and pushes onto `CameraBroker`'s effect stack.
  - **No `Form` field.** The class literally has no typed slot for a `Form`, `FormReader`, or `FormComponent` reference — structural enforcement of Stage 1 Camera ↔ Form coupling NONE.

#### 1. Brain Layer (Inputs)

- **`CameraBrain` (abstract Node):** Contract class. `populate(input: CameraInput)`.
- **`PlayerCameraBrain` (Node):** Reads mouse/gamepad look axis + lock-on-toggle key. Populates `CameraInput { look_delta, wants_lock_on_toggle, wants_aim }`. AI never drives the camera (no `AICameraBrain` exists — mixing camera input into `Intents` would force `AIBrain` to compute fields it has no reason to produce).

#### 2. Broker Layer (Orchestrator)

- **`CameraBroker` (Node):** Arbitrates `TransitionProposal`s among Modes, iterates active Effects, writes composited transform to `Lens`. Ticked at slot 6 by `GameOrchestrator._physics_process` → `camera_bundle.tick_camera(delta)` → `CameraBroker.tick(camera_input, delta)`. Holds the active effect stack (push-on-request, pop-on-expiry).

#### 3. Modes & Effects (Execution — sibling depths)

*Modes are mutually exclusive (one base transform per frame — Rule 11). Effects stack (multiple per frame compose additively on top of the base transform).*

| Component | Type | Responsibility / Rules |
|---|---|---|
| **`FollowMode`** | Mode | Default third-person orbit-behind camera. Proposes DEFAULT continuation. |
| **`AimMode`** | Mode | Over-the-shoulder aim framing. Proposes PLAYER_REQUESTED when `aiming_reader.is_aiming() == true` (ground truth from Combat). |
| **`LockOnMode`** | Mode | Dual-target framing when `lock_on_reader.has_target() == true`. Proposes PLAYER_REQUESTED. |
| **`DipEffect`** | Effect | Vertical transform kick driven by `impact_detected` > `min_impact_velocity` (Camera-side filter). |
| **`ShakeEffect`** | Effect | Noise-driven rotation offset. Pushed by Combat on hit via `request_effect`. |
| **`FOVZoomEffect`** | Effect | FOV delta with easing curve. Pushed on demand (e.g., sprint punch). |
| **`FollowEaseInEffect`** | Effect | Soft-interpolate camera from previous follow position to new one after swap. |

#### 4. Services, Lens & Reader (Foundation)

- **`OcclusionService` (`Node3D` with `RayCast3D`):** Casts from the candidate camera position back toward the target; returns max unobstructed distance. Modes clamp their distance against this value. Consumes `BodyReader` only (read-only per Rule 2).
- **`CameraReader` (lightweight object — not a Node):** Read-only wrapper published by `CameraRig` per Stage 1 Shared Contracts. Exposes `get_global_position() -> Vector3`, `get_forward() -> Vector3`, `get_up() -> Vector3`, `get_fov_degrees() -> float`. Constructed with a private reference to `Lens` (the SSoT for the applied `Camera3D.global_transform`); every getter reads live from `Lens`'s interpolated camera. No setter surface — Rule 2 by class shape. Consumers: `PlayerBrain` (for `aim_target` ray derivation from camera forward), future Audio (stereo panning), future VFX (camera-relative particle orientations). `CameraRig` exposes exactly one instance via `get_camera_reader() -> CameraReader`.
- **`Lens` (`Node3D`):** Sole writer of `Camera3D.global_transform`. Owns `SpringArm3D` + `Camera3D` as children. Receives composited transforms from `CameraBroker.tick` via `set_target_transform(transform)`; stores `previous_transform` and `current_transform` for visual interpolation.
  - **The cluster's only `_process` override:** `Lens._process` runs at render rate and interpolates `_camera_3d.global_transform = previous.interpolate_with(current, Engine.get_physics_interpolation_fraction())` — the single documented exception to "`GameOrchestrator` owns all ticks" (see Stage 2 § Visual Interpolation). `process_mode = PROCESS_MODE_PAUSABLE` so the interpolation freezes correctly on pause (Stage 3).

---

### Combat

#### 1. Brain Layer (Inputs)

Combat does not add a Brain layer. Combat fields on `Intents` (`wants_attack`, `wants_parry`, `wants_dodge`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`) are populated by the shared `Brain` → `PlayerBrain` | `AIBrain` (see Movement § 1). Combat **reads** `Intents` downstream; it does not produce them.

#### 2. Broker Layer (Orchestrator)

- **`CombatBroker` (Node):** Per-entity orchestrator. Ticked at slot 5 by `GameOrchestrator._physics_process` → `entity_bundle.tick_combat(delta)` → `CombatBroker.tick(intents, delta)`. Responsibilities:
  - **Moveset binding** — subscribes to `FormReader.form_shifted` at `_ready()` and pre-binds the active `CombatAction` for the new form. On tick, dispatches only the active-form action (Panther → `TakedownAction`, Monkey → `ParryAction`+`CounterAction`, Avian → `BowAction`).
  - **Moveset gate** — consults `LocomotionStateReader.get_active_mode()` before dispatching; refuses every action in `{CLIMB, SWIM, MOUNT, FALL, DEFEAT, CINEMATIC, STAGGER_*}` (Stage 3 Case X4 canonical gate — "Brain is blind" enforcement). **FALL exemption for ranged archery:** while `active_mode == FALL`, the gate still dispatches `BowAction` for the Avian form only (core-fantasy mid-air archery per Stage 1). Implementation: gate consults `FormReader.get_active_form()` — if `&"avian"` **and** the action is `BowAction`, pass-through; all other FALL actions refused. The exemption is pinned here so Stage 6 contracts freeze it before code.
  - **Hit resolution** — runs the selected `CombatAction.gather_decision` + `execute`; produces `Array[DamageEvent]`; emits `hit_landed(event)` upward and, when the event targets another entity, emits **`outgoing_attack_resolved(target_entity: EntityController, event: DamageEvent)`** upward. The attacker's own `EntityController` receives this signal and forwards the event to the **target `EntityController`**'s public `receive_incoming_attack(event: DamageEvent)` method — which in turn pushes into the target's `CombatBroker.IncomingAttackBuffer` and (when `stagger_class != &"none"`) injects the FORCED stagger proposal into the target's `MovementBroker`. `CombatBroker` never calls `MovementBroker.inject_forced_proposal` itself — by class shape, does not hold the reference (Rule 13).
  - **Incoming-attack buffer drain** — per-entity `IncomingAttackBuffer` receives `DamageEvent`s landed on this entity in the same frame's earlier slot-5 resolutions. Routing is **signal-up / call-down** across entities: attacker `CombatBroker` → attacker `EntityController` (upward signal) → target `EntityController.receive_incoming_attack` (downward call) → target `CombatBroker.IncomingAttackBuffer.push` (downward call). Drained at the top of this entity's `tick` so parry/dodge windows resolve same-frame against same-frame attacks.
  - **Lock-on target ownership** — invokes `LockOnService.update_candidates()`; writes the selected target to `LockOnTargetReader`'s backing state (owned here, not on a separate Component).

#### 3. Combat Actions (Execution — moveset-bound)

*Moveset binding swaps which Action `CombatBroker` dispatches each tick. Exactly one Action active per entity per tick (Rule 11). Intra-moveset conflict resolution declared in Stage 3 § Combat intra-system.*

| Action | Form | Responsibility / Rules |
|---|---|---|
| **`TakedownAction`** | Panther | Proximity + stealth-gated instant kill (`awareness_level == UNAWARE`). Produces `stagger_class: &"finisher"`. |
| **`ParryAction`** | Monkey | Opens parry window. Consumes incoming `DamageEvent`s (no damage) and marks pending counter. |
| **`CounterAction`** | Monkey | Fires on parry-success flag. Produces heavy stagger counter-attack. Drains stamina. |
| **`BowAction`** | Avian | State machine (`DRAW` → `AIM` → `RELEASE`). Writes `AimingReader.is_aiming()`. Produces ranged `DamageEvent`. |

#### 4. Services (Foundation)

- **`HitDetectionService` (Node):** Ray casts / overlap queries from `BodyReader.get_global_position` + action-specific offsets. Side-effect-free — returns `Array[HitCandidate]` to the calling Action.
- **`LockOnService` (Node):** Candidate-target scanning in a sphere around `BodyReader`; scores candidates by angle-to-aim + distance + LOS; selects highest-scoring. Owns the current target selection; mutates only Combat-owned state.
- **`IncomingAttackBuffer` (Node):** Per-entity ring buffer of `DamageEvent`s that landed on this entity earlier in the same frame's slot 5. **Write access is intra-entity only** — the sole caller of `IncomingAttackBuffer.push(event)` is this entity's own `CombatBroker` (forwarded from its parent `EntityController.receive_incoming_attack` handler). Drained by this entity's `CombatBroker.tick` at top-of-tick.
  - *Cross-entity routing (Rule 13 strict form):* cross-entity attack delivery does **not** use direct sideways calls. The attacker's `CombatBroker` emits `outgoing_attack_resolved` upward to its own `EntityController`; that `EntityController` calls `target_entity.receive_incoming_attack(event)` — a public method on the target `EntityController`; the target `EntityController` calls its own `CombatBroker.push_incoming_attack(event)`, which writes into the buffer. Every edge is **signal-up to my own EntityController** or **downward call from my EntityController to my child**. Same-frame resolution is preserved because slot 5 iterates all entities in bundle-registration order and the signal → handler → call chain is synchronous within a single slot-5 step.
  - *Why this works within-tick:* the signal emission, the attacker-EntityController handler, and the target-EntityController forward are all synchronous call-stack frames inside slot 5. The target's `IncomingAttackBuffer` is therefore populated before the target's own `CombatBroker.tick` runs (assuming registration order places the attacker earlier) — or, if the target ticked earlier in slot 5, the buffer holds the event for the **next** frame's parry/dodge window (Stage 2 Trace C 1-frame stagger — documented behavior, not a bug).

#### 5. Combat State

- **`CombatState` (Node):** State-machine cell tracking per-entity combat stance: `IDLE`, `DRAWING`, `AIMING`, `PARRY_WINDOW`, `COUNTERING`, `ASSASSINATING`, `STAGGERED_AS_ATTACKER`. Mutually exclusive per entity (Rule 11). Mutated only by the active `CombatAction` through `CombatBroker`. Read by `F3` debug panel and by AI perception (`CombatStateReader` — declared in Stage 6).

---

### Form

#### 1. Brain Layer (Inputs)

No dedicated Form Brain. `wants_form_shift: StringName` populated on `Intents` by the shared `Brain` (see Movement § 1). Form reads `Intents` downstream.

#### 2. Broker Layer (Orchestrator)

- **`FormBroker` (Node):** Per-entity orchestrator. Ticked at slot 3 by `GameOrchestrator._physics_process` → `entity_bundle.tick_form(delta)` → `FormBroker.tick(intents, delta)`. Responsibilities:
  - **Shift validation.** `intents.wants_form_shift ∈ {&"", active_form} → no-op early-return` (Stage 3 intra-system cases). `wants_form_shift ∈ available_forms()` → proceed. Invalid value fires the Stage 2 slot 3 assert.
  - **Shift-gate check (Stage 3 addition).** If `_shifts_enabled == false` (set by `EntityController` on DEFEAT/CINEMATIC entry), `tick` early-returns before mutating state — no `set_form`, no signal, no fan-out, no FORCED proposal. **Gate is the only Form-side DEFEAT/CINEMATIC awareness — `FormBroker` still holds no `LocomotionStateReader`; the gate state is written from the outside.**
  - **Shift commit.** `FormComponent.set_form(new_form)` → emit `form_shifted(new_form)` upward. The upward signal is the only egress point; the rest of the fan-out happens on `EntityController` (Stage 1 seam, Stage 2 slot 3 fan-out path).
  - **Public downward surface:** `set_shifts_enabled(enabled: bool)` — called only by `EntityController` on `LocomotionState.state_changed` handler. Runtime-asserted on caller identity (Stage 6).
- **Shape catalog (held on `FormBroker`):** `Dictionary[StringName, Shape3D]` mapping `&"panther" / &"monkey" / &"avian" → CollisionShape3D.shape`. `FormBroker` publishes shapes to `EntityController`'s fan-out; it does **not** call `Body.swap_collision_shape` itself (Rule 13).
- **Motor mask catalog (held on `FormBroker`):** `Dictionary[StringName, Array[StringName]]` mapping `&"panther" / &"monkey" / &"avian" → Array` of allowed Motor names (`SneakMotor` → Panther, `GlideMotor` → Avian, core Motors in all forms). Published to `EntityController`'s fan-out on shift.

#### 3. Form State

- **`FormComponent` (Node):** State-machine cell holding the active form (`&"panther" | &"monkey" | &"avian"`). `set_form(new_form)` callable by `FormBroker` only. Lives on `EntityController`. Exposed externally via `FormReader` (read-only getter + `form_shifted` signal forwarding).

#### 4. Services (Foundation)

No Form-specific Services in MVP. Future slot: a `FormAvailabilityService` that reads zone gating (e.g., "no Avian underground") — deferred until Progression or Zone State ships. Stage 1 declared the slot as a placeholder; this stage confirms no MVP Node.

---

## SSoT Ownership and Access Mapping

*Cluster-wide — cross-system consumers listed per state. The closed set in the "Mutable access" column is load-bearing: Reader variants cannot mutate (no setter on the Reader class — Rule 2 by class shape).*

| State | Owning Component | Mutable Access | Read-Only Access (via Reader) |
|---|---|---|---|
| **Locomotion Mode** | `LocomotionState` (Movement) | `MovementBroker` | Motors, `AimMode`/`LockOnMode`, `CombatBroker` (gate), `EntityController` (gate), UI, AI |
| **Stamina** | `StaminaComponent` (Movement) | Motors, Combat Actions | UI, AI, Combat (balance), Progression |
| **Body Transform/Vel** | `Body` (Movement) | Active Motor | `CameraBroker`, `FollowMode`, `OcclusionService`, `CombatBroker`, Services, Health, UI, AI |
| **Intents (struct)** | `EntityTickBundle` | Active `Brain` (Slot 1) | `FormBroker`, `MovementBroker`, `CombatBroker` (Slots 3, 4, 5) |
| **Form** | `FormComponent` (Form) | `FormBroker` | `CombatBroker`, Audio, UI, Progression. *(Camera has NO access)* |
| **Shift-gate flag** | `FormBroker` (Form) | `EntityController` | `FormBroker.tick` (internal) |
| **Motor mask** | `MovementBroker` (Movement)| `EntityController` | `MovementBroker.tick` (internal) |
| **Combat State** | `CombatState` (Combat) | Active `CombatAction` | UI (F3), AI perception, Feel/Animation hooks |
| **Lock-On Target** | `CombatBroker` (Combat) | `LockOnService.update_candidates` | `LockOnMode`, UI reticle, Audio |
| **Aiming state** | `CombatBroker` (Combat) | `BowAction` | `AimMode` |
| **Camera Transform** | `Lens` (Camera) | `Lens._process`, `CameraBroker.tick`| `PlayerBrain`, Audio, VFX |
| **Form catalogs** | `FormBroker` (Form) | None (populated at `_ready()`) | `FormBroker.tick`, `EntityController` |
| **`_external_proposals`** | `MovementBroker` (Movement)| `MovementBroker.inject_forced_proposal` | `MovementBroker.tick` (internal drain; serialized with entity state) |

---

## Performance Constraints

### Universal Rules

All components in this cluster are bound by the rules from the stage template, reasserted here so Stage 4 is a self-contained contract for the Graybox Rule Enforcer and Auditor:

| Rule | Applied to all components | Override allowed? |
|------|---------------------------|-------------------|
| `_physics_process` disabled by default | **Yes** — `GameOrchestrator` calls `set_physics_process(false)` at registration. | **No**, except `Lens._process` for visual interpolation. |
| Signal-only cross-node communication | **Yes** — Intra-entity edges go Signal-up → `EntityController` → downward-call. Cross-entity edges use target's `EntityController` public methods. | **No**. |
| No group iteration in hot paths | **Yes** — `GameOrchestrator` uses typed array iterations; Brokers cache children. | **No**. |
| Full static typing | **Yes** — every var, param, return type explicitly annotated using base classes. | **No**. |
| No magic numbers | **Yes** — weight registry is `const Dictionary`, gameplay thresholds are `@export`. | **No**. |

### Game-Specific Thresholds

These are the cluster's binding numbers. Downstream stages (Stage 5 scaffold, Stage 6 contracts, graybox phase, asset phase) must respect them — any relaxation is a Stage 4 revision, not an implementation choice.

- **Object pooling threshold:** **≥ 10 spawns/sec** of any one node type requires `ObjectPool` pre-pooling. Applies to arrow projectiles, hit-VFX spawns, dust/step VFX, ragdoll spawn shards (future). MVP-relevant: arrow pool size **≥ 30** (accounts for Avian rapid-fire + in-flight arrows from multiple enemies).
- **`MultiMeshInstance3D` threshold:** **≥ 20 identical static meshes** in a single scene chunk → must use `MultiMeshInstance3D`. Applies to future environment assets (grass, rocks) — not to any per-entity cluster-A component. Documented for asset-phase consumption.
- **Physics threading (Jolt):** **Enabled** (Godot 4.6 default; verify in Project Settings at Stage 5 scaffold). Necessary because each entity's `GroundService` + `LedgeService` fire multiple `ShapeCast3D` queries per tick; at 50 simultaneous entities the cast volume exceeds a single-threaded budget.
- **Large population limit:** **Hard cap of 50 active entities** running the full Brain → Form → Movement → Combat stack simultaneously (i.e., 50 registered `EntityTickBundle`s). Entities beyond 50 must fall back to procedural / animation-only LODs (future AI-LOD stage). This cap drives the `_entity_bundles` iteration cost budget at slots 1/3/4/5 (4 iterations × 50 entities × per-slot work).
- **Budgets (physics tick vs render tick, explicitly separated):**
  - **Physics-tick budget (60 Hz, `_physics_process`, 16.67 ms window):** **≤ 0.15 ms CPU per entity** across slots 1/3/4/5 combined. At the 50-entity cap: 50 × 0.15 ms = **7.5 ms for all entity slots**. Slot 6 (Camera, single-instance) is budgeted separately at **≤ 0.5 ms per physics tick**. Total cluster-A physics-tick budget: **≤ 8.0 ms** out of the 16.67 ms window, leaving ≥ 8.67 ms for physics engine, collisions, and other systems' physics work.
  - **Render-tick budget (variable Hz, `_process`, part of the per-rendered-frame budget):** the cluster contributes only `Lens._process` (a single `Transform3D.interpolate_with` call) at **≤ 0.05 ms per rendered frame**. No other component in the cluster runs at render rate. Debug overlay panels (visible-only) are excluded from cluster-A render budget — tracked under `DebugOverlay`.
  - **No conflation:** the 0.15 ms/entity figure applies **only** to physics ticks; it is not amortized over render frames. Render rate may be higher than physics rate; the `Lens._process` interpolation cost is fixed per render frame regardless of physics-tick count.
- **Weight registry injectivity:** the FORCED-proposal weight table (below) must be **strictly injective within each class tier**. Runtime assert fires on duplicate-weight hostile ties (Stage 3 assert discipline).

### FORCED-Proposal Weight Registry

*Declared here as the Stage 4 deliverable required by `03-edge-cases-player-action-stack.md` § Weight registry. Every cluster-internal and cross-cluster FORCED proposal reaching `MovementBroker._external_proposals` carries a weight from this table. Registry is a `const Dictionary` on `MovementBroker` (or a sibling singleton per Stage 5); lookup failure / duplicate registration crashes at `_ready()`.*

| Source | Proposal | Weight | Notes |
|---|---|---|---|
| Movement — GroundService | ground-reattach on airborne→grounded | **10** | Snap-to-floor correction to prevent 1-frame float after Motor transitions. Intra-system FORCED — lowest band. |
| Movement — WaterService | enter-swim (submerge) | **20** | Emitted on water-volume entry. |
| Movement — WaterService | exit-swim (emerge) | **25** | Emitted on water-volume exit. Distinct from enter to keep injectivity. |
| Movement — LedgeService | ledge-snap | **30** | Prevents floating when a mantle-height ledge is detected mid-air between motors. |
| Combat | stagger `&"light"` | **40** | `ParryAction`/`CounterAction` light-stagger, small melee hits. |
| Combat | stagger `&"heavy"` | **80** | Counter-attack, heavy-weapon stagger. |
| Form | `FormShiftProposal` | **100** | Single weight — one form-shift per frame per entity by construction. |
| Combat | stagger `&"finisher"` | **120** | Panther takedown, archery headshot-equivalent; overrides form-shift to allow death-on-shift-frame. Routes `LocomotionState → STAGGER_FINISHER` which dispatches **`RagdollMotor`** (not `StaggerMotor`). |
| Interaction | cinematic | **150** | Scripted cutscene entry (LOOSE bridge — Interaction system, out-of-cluster). |
| Health | defeat | **200** | HP ≤ 0 (LOOSE bridge — Health system, out-of-cluster). Highest weight — death subsumes every other FORCED source. |

**Invariant:** all ten values are distinct. Any future FORCED producer (e.g., future Environment damage, future Trap push-out) must claim an unused weight in this table, not squat on an existing one. The weight-registry singleton asserts `registered_sources.size() == unique_weight_count` at `_ready()`.

**Rationale for the intra-Movement band (10–30):** Service-emitted corrections must win over DEFAULT Motor proposals (they *are* FORCED) but must lose to any Combat/Form/cluster-external FORCED event. Keeping them strictly below stagger-light (40) guarantees the ordering by construction — no cross-band tie is possible.

**Rationale for finisher > form-shift (120 > 100):** a stealth takedown landing on the same frame as an attempted shapeshift should kill the victim, not be gazumped by a panicked shift. The finisher-class weight is specifically tuned to sit between regular stagger (80) and cutscene (150).

**Camera intra-system weights (separate registry on `CameraBroker`):** Camera Mode proposals do not enter `MovementBroker`'s queue — they arbitrate among Modes only. Per Stage 3 Camera intra-system resolution:

| Source | Proposal | Category | Weight | Notes |
|---|---|---|---|---|
| Camera | `FollowMode` continuation | DEFAULT | **0** | Baseline — ticks when no other Mode proposes. |
| Camera | `LockOnMode` | PLAYER_REQUESTED | **50** | Active while `lock_on_reader.has_target()`. |
| Camera | `AimMode` | PLAYER_REQUESTED | **60** | Active while `aiming_reader.is_aiming()`. **Wins against LockOnMode** when both conditions hold simultaneously (bow drawn while locked-on — Avian core combo). |

Same injectivity assert applies at `CameraBroker._ready()`.

### Per-Component Performance Notes

*Which thresholds apply and why. Components not listed are trivial cost — no cluster-internal budget impact.*

- **`MovementBroker`:** CPU hotspot (slot 4). Must cache Motor and Service arrays at `_ready()` to avoid tree searches in `tick`. `_external_proposals: Array[TransitionProposal]` — bounded in practice but serialization-critical for rollback (Stage 3).
- **`CombatBroker`:** CPU hotspot (slot 5). `IncomingAttackBuffer` is a ring buffer — fixed capacity (MVP: 8 attacks/frame/entity — exceeded only by implausible combat storms; overflow asserts loud). `LockOnService.update_candidates` runs an area scan + scoring — cached candidate list with 0.1s invalidation rather than per-tick rescan.
- **`FormBroker`:** Trivial cost — a tick is a Dictionary lookup + 0 or 1 signal emit. Not a budget concern. The load-bearing work happens in `EntityController`'s fan-out handler, which is also trivial (three method calls).
- **`GroundService` / `LedgeService`:** Each runs `force_shapecast_update()` once per tick via `update_facts(body_reader)`. At 50 entities × 2 services × ~1-2 rays → ~150-200 ShapeCast queries per physics tick. Jolt multi-threading (universal threshold) absorbs this. Not a hotspot individually; the 50-entity cap is tuned to keep the aggregate in budget.
- **`OcclusionService`:** One `RayCast3D` per frame (single-instance camera). Trivial cost — slot 6.
- **`HitDetectionService`:** Ray casts / overlaps per active Action's `execute` call. Upper bound: 50 entities × 1 active action = 50 calls/tick. Each call is small (≤ 4 rays typical). Not a hotspot at the 50-entity cap.
- **`Lens`:** Only `_process`-ticking node in the cluster. A single `Transform3D.interpolate_with` call per render frame. Trivial cost.
- **`CombatContextStub`:** Zero-cost stub. Hardcoded Reader returns.
- **Motors / Modes / Effects / Actions:** Dispatched-one-at-a-time by their respective Brokers. Inactive components cost nothing (they only exist as tree nodes with `_process`/`_physics_process` disabled). Active component cost is per-tick-per-entity, already accounted for in the per-entity 0.15 ms budget.
- **Object-pooling requirement (derived):** `BowAction` arrow spawn rate per entity ≤ 2/sec at MVP, but a crowd of 10 Avian enemies drawing simultaneously can exceed the 10-spawn/sec cluster threshold — **arrow pool mandatory from day one, via `ObjectPool` Autoload (to be declared in Stage 5 scaffold)**.

### Autoloads

*One context sub-component per system-in-cluster, claiming the F-key assigned in Stage 1 Debug Overlay Contexts. The union with other groups' artifacts yields the full `DebugOverlay` child list project-wide — this artifact does not redeclare F-keys owned by other groups.*

- **`GameOrchestrator` (Autoload, `PROCESS_MODE_ALWAYS`):** Project-wide tick driver. See `02-data-flow-player-action-stack.md` Mechanism 4 for the 6-slot iteration contract and `05-project-scaffold-player-action-stack.md` § Autoloads for the full registration API. Not a DebugOverlay child. No gameplay state.
- **`DebugOverlay` (Autoload, `PROCESS_MODE_ALWAYS`, debug-build-only via `OS.is_debug_build()`):** Project-wide debug panel host. Read-only observer. Never holds game state. No-op in release. Panel render runs only when the panel is visible. May use `_process` for UI refresh in debug builds only.
  - **Context sub-components:**
    - **`MovementContext` (F1):** Single Movement panel — active `LocomotionState.Mode`, Motor dispatch trace, Service facts (ground/ledge/water/mount), stamina drain + regen, FORCED queue contents, last `TransitionProposal` arbitration result.
    - **`CameraContext` (F2):** Single Camera panel — active mode + last transition reason, effect stack (class + magnitude + time remaining per active effect), occlusion state (ray-hit distance vs desired), lock-on target identity + distance, Lens state (current FOV, base vs composited transform), `CameraInput` values, active `target_body_reader` identity, tick + `_process` interpolation timing.
    - **`CombatContext` (F3):** Single Combat panel — active moveset binding (keyed to current form), current action state (idle/drawing/aiming/parry-window/countering/assassinating/staggered), last `DamageEvent` (source, target, amount, damage_type, stagger_class), active hit-detection state (ray casts this frame, hits/misses), lock-on candidate list + scores + selection, last upward signal (stagger_triggered/hit_landed/target_changed) + whether `EntityController` forwarded a FORCED proposal, Combat stamina drains this frame, combat fields on `Intents` (`wants_attack`/`wants_parry`/etc.), `IncomingAttackBuffer` contents.
    - **`FormContext` (F4):** Single Form panel — active form, previous form + time-in-form + last shift reason (PlayerBrain / AIBrain / forced), motor mask currently sent to `MovementBroker` (array of allowed Motor `StringName`s), collision shape currently active on `Body` (shape resource name), form shift history (last N shifts, timestamp, triggering Brain), moveset currently bound via `FormReader` → Combat, pending `FormShiftProposal` status (queued / arbitrated this frame), `available_forms()` snapshot + `ProgressionReader` source (pre-Progression MVP: all three), **`_shifts_enabled` gate state + last flip source + last flip `LocomotionState.state_changed` event**.
  - **Performance rules for `DebugOverlay` (Stage 4 universal):** panel render runs only when that panel is visible (push is a no-op when hidden); data flows strictly game → DebugOverlay (nothing reads from it); no-op in release (`OS.is_debug_build()` guard); may use `_process` for UI refresh in debug builds only.

- **`ObjectPool` (Autoload, `PROCESS_MODE_PAUSABLE`):** Pre-pool utility for spawn-rate-bound node types per the cluster pooling threshold (≥ 10 spawns/sec). MVP consumer: `BowAction` arrow spawns. API: `acquire(type_key: StringName) -> Node3D`, `release(node: Node3D) -> void`. No gameplay state (Rule 14) — only bookkeeping of free/in-use lists per type.

---

## Exit Criteria

- [x] Exhaustive list of concrete components required to fulfill the MVP scope — per-system sub-sections for Movement, Camera, Combat, Form, including the Composition Root Node per system (`EntityController` for the entity stack; `CameraRig` for the single-instance rig).
- [x] Each component has strict Single Responsibility boundaries defined — one-sentence responsibility per Node; multi-verb entries split into two Nodes.
- [x] SSoT Ownership explicitly mapped showing who has mutable vs read-only access — cross-system consumers listed per state (LocomotionState, Stamina, Body, Intents, Form, CombatState, LockOnTarget, AimingState, CameraTransform, plus bookkeeping flags).
- [x] Narrative examples accompany structural components — examples given for `EntityController` fan-out, `PlayerBrain` / `AIBrain` input production, `MovementBroker` weight-registry arbitration, `BowAction` archery flow.
- [x] Universal performance rules confirmed for all components — Universal Rules table with the declared exception (`Lens._process`) and the cross-entity signal-routing contract for `IncomingAttackBuffer` (signal-up → `EntityController.receive_incoming_attack` → downward-call into the target's own buffer, no sideways `CombatBroker` calls).
- [x] Game-specific thresholds decided — pooling (10/sec, arrow pool ≥ 30 mandatory), MultiMesh (20), physics threading (Jolt enabled), population limit (50 entities), per-entity budget (0.15 ms/entity/physics-frame), Camera budget (0.5 ms/frame).
- [x] Per-component performance notes written — hotspots identified (`MovementBroker`, `CombatBroker`, Services aggregate), trivial-cost components named, derived object-pooling requirement (arrows) captured.
- [x] `DebugOverlay` Autoload mentioned, with one context sub-component per system-in-cluster that claimed an F-key in Stage 1 — `MovementContext` (F1), `CameraContext` (F2), `CombatContext` (F3), `FormContext` (F4).

**Cluster-A-specific additions beyond the stage template:**

- [x] FORCED-proposal **weight registry** pinned as a Stage 4 deliverable (required by `03-edge-cases-player-action-stack.md`). Six weights declared, all distinct, rationale given for finisher > form-shift.
- [x] Per-system sub-sections use the "Motors execute / Services provide facts / Modes compose base transforms / Effects stack / Actions resolve hits" structural naming — same pattern across all four systems under different names (Movement's Motors+Services, Camera's Modes+Effects+Services, Combat's Actions+Services, Form's Broker-only minimum).
- [x] Cross-entity attack-delivery pattern declared under strict Rule 13 form — signal-up through attacker `EntityController`, single cross-entity edge via public `EntityController.receive_incoming_attack`, signal-up / downward-call into target's `IncomingAttackBuffer`. No sideways `CombatBroker`-to-`CombatBroker` call anywhere in the cluster.
- [x] `ObjectPool` autoload newly declared as a derived requirement (arrows exceed the 10-spawn/sec threshold under crowd conditions). Stage 5 scaffold must instantiate it.
- [x] Stage 3 shift-gate wired through SSoT mapping: `FormBroker._shifts_enabled` listed with `EntityController` as sole mutator; `LocomotionState.state_changed` listed with `EntityController` as the new subscriber that drives the gate.
