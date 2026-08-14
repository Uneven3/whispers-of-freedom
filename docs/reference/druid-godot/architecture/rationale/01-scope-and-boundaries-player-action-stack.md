> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Scope & Boundaries

> **Scope of this artifact.** This is the canonical Stage 1 for Cluster A (TIGHT cluster per `00-system-map.md` § 2–3): **Movement, Camera, Combat, Form**. Authored as a single file because the four systems share `Intents`, share `StaminaComponent`, share per-entity Brain/Broker composition (Movement + Combat + Form all live under the same `EntityController`), and have mutual tick-order dependencies. See `workflow/stages/architecture/01-scope-and-boundaries.md` for the cluster-scoped authoring rule. Stages 2–6 for this cluster are authored under the `-player-action-stack` suffix and are the sole authoritative home for all cluster contracts.

---

## Systems in this artifact

- **Movement** — locomotion, stamina, collision; Brain/Broker/Motors/Services/Body stack shared by player and enemies.
- **Camera** — follow, aim, lock-on, occlusion, composable reactive effects, visual interpolation; single-instance rig.
- **Combat** — melee (Monkey counter), stealth (Panther takedowns), ranged (Avian archery), enemy AI behavior driving the shared `Intents` struct, hit detection, lock-on target ownership, damage application.
- **Form** — instant shapeshifting between Panther / Monkey / Avian: collision shape swap, motor mask, moveset selection.

---

## Scope

### Movement

**In Scope:**
- Walk, Run, Sprint (Sprint stamina-gated).
- Sneak (Skyrim-style crouch — reduced speed, reduced detection).
- Jump (standing and running).
- Climb on flagged surfaces (stamina-gated, drains while ascending).
- Glide with paraglider (deployable mid-air, drains stamina).
- Mantle (short ledge pull-up).
- Auto-vault (low obstacles crossed without explicit input).
- Wall jump (jump off a climbed surface, directional).
- Swim (stamina-gated, surface-level — no diving combat).
- Mount / Dismount (enter and leave a ridable entity — entity-swap, not Body write-target rebinding).
- Fall damage: `Body` reports `impact_detected(velocity)`; damage application belongs to Health.
- Stamina (**Movement-owned**; read-only to most external systems; mutable access also lent to Combat for dodge/parry costs).
- Locomotion chaining: Climb → WallJump → Glide; Climb → WallJump → Mantle; Glide → land on wall → Climb (BotW parity).

**OUT OF SCOPE (but architecture must not forbid):**
- Shapeshifting / Form selection — owned by **Form** (below). Accommodated structurally by `MovementBroker.set_allowed_motors()` and `inject_forced_proposal()`.
- Combat actions — owned by **Combat**. Shared `Intents` carries combat fields from day one.
- Camera behavior — owned by **Camera**.
- World interaction — Interaction system (out-of-cluster, LOOSE bridge).
- Weapon durability / weapon swap — no weapons in this prototype.
- Cinematic / scripted cameras — out entirely.
- Mounted combat — out of MVP. Mount = entity-swap, not Body write-target rebinding.
- Swimming combat / diving — surface swim only.
- Fast travel / teleport — reserved for `Body.teleport()` entry point.
- Multiplayer / network sync — `RemoteBrain` fits the same abstract contract.
- NPCs (non-enemy) — instantiate the same stack with an `AIBrain`.

### Camera

**In Scope:**
- Default follow camera (BotW / Genshin Impact orbit-behind, third-person).
- Aim camera (Skyrim / Zelda over-the-shoulder shift) — activated when the bow is **actually drawn** (consumed via `AimingReader`, not directly from `Intents.wants_archery_aim`; see Cross-System Seams: Camera ↔ Combat).
- Occlusion handling: when a wall sits between camera and target, push the camera in toward the target along the camera→target ray (no fade, no clipping).
- Lock-on camera mode: frames the locked target alongside the player when Combat reports a target via `LockOnTargetReader`.
- Reactive effects, composable and stackable:
  - **Camera dip on hard fall** — driven by `BodyReader.impact_detected(velocity)`, filtered by a camera-owned `min_impact_velocity` threshold (see Cross-System Seams: Movement ↔ Camera).
  - **Screen shake on hit** — pushed by Combat via the `request_effect()` choke point.
- Visual interpolation between physics frames so the camera stays smooth at any monitor refresh rate (60 / 144 / 240 Hz) while game logic stays at the fixed physics tick (see Tick Architecture).
- Mount / dismount camera target rebind via mandatory `CameraRig.set_target(BodyReader)` contract (Stage-1 requirement).
- **Form-agnostic:** identical anchor, FOV, distance, and behavior across Panther, Monkey, Avian. Form differentiation must be communicated by UI / vignette / post-FX — **not** by Camera. Enforced structurally: the composition root never passes a Form reference to `CameraRig`.

**OUT OF SCOPE (but architecture must not forbid):**
- Cinematic / scripted cameras — future `CinematicMode` slots into the existing mode arbitration loop.
- Photo mode — PhotoMode replaces the base transform without affecting Effects.
- First-person view — another `Mode` in the same loop.
- Split-screen / per-player cameras — moves `CameraRig` from singleton to per-entity.
- **Per-form camera reframing — banned by design.** Structurally prevented (no Form reference).
- Hit-pause — **NOT Camera's responsibility.** Owned by future `TimeScaleService`.
- Dynamic zone-based fixed framing — future `FixedFramingMode`.
- Camera-relative audio / lighting / VFX — exposed as `CameraReader`.
- Multiplayer / network camera authority — `RemoteCameraBrain` fits abstract base.

### Combat

**In Scope:**
- **Melee — Monkey counter:** parry window, counter-attack, stagger application on counter success.
- **Stealth — Panther takedowns:** proximity-gated instant-kill on unaware enemies; detection state read from target's AI perception.
- **Ranged — Avian archery:** bow draw → aim → release; bow draw triggers camera `AimMode` via `AimingReader` (see Cross-System Seams: Camera ↔ Combat).
- **Enemy AI behavior:** `AIBrain` (per enemy) populates the **full** `Intents` struct each physics tick — movement fields AND combat fields (`wants_attack`, `wants_parry`, `wants_dodge`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`). Combat enemies share the Movement Brain/Broker/Motors stack (shared entity composition).
- **Hit detection:** post-motion ray casts / overlap queries; hits produce `DamageEvent` structs sent to target's Health.
- **Lock-on target ownership:** Combat owns the current lock-on target and exposes it through `LockOnTargetReader` (consumed by Camera's `LockOnMode`).
- **Stagger / hit-reaction interrupts to locomotion:** Combat emits `stagger_triggered` upward; `EntityController` catches it and forwards a FORCED `TransitionProposal` to `MovementBroker.inject_forced_proposal()` (per Rule 13 — see Cross-System Seams: Movement ↔ Combat).
- **Stamina drain for dodge / parry:** Combat holds a mutable reference to `StaminaComponent` (lent by `EntityController`) to drain costs on dodge/parry actions. `StaminaComponent` lives at entity level for this reason.
- **Moveset binding per form:** active moveset is determined by current form (Panther = takedowns, Monkey = counters, Avian = archery). See Cross-System Seams: Combat ↔ Form.

**OUT OF SCOPE (but architecture must not forbid):**
- Weapon durability, weapon swap — no weapon inventory.
- Mounted combat — out of MVP.
- Swimming / diving combat — surface swim only.
- Damage numbers / floaty UI — UI concern.
- Hit-pause and screen-shake *implementations* — Combat only *requests* them.
- HP ownership — owned by **Health** (LOOSE bridge).
- Death / respawn logic — Health + scene flow.
- Progression curves — owned by Progression (LOOSE bridge).
- Network combat authority — out of MVP.

### Form

**In Scope:**
- **Three forms:** Panther, Monkey, Avian. Exactly one form active per entity at a time.
- **Instant shapeshift:** no transformation animation; on input, form swaps within 1–2 physics frames.
- **Collision shape swap:** `CharacterBody3D` collision shape changes per form (Panther low-profile, Monkey medium, Avian narrow-tall). Form owns the shape catalog; on swap, `EntityController` receives the `form_shifted(new_form)` signal and calls the shape swap downward on `Body`.
- **Motor mask per form:** `FormBroker` computes the `motor_mask: Array[StringName]` of Movement motors allowed in the new form and calls `MovementBroker.set_allowed_motors(mask)` via the `EntityController` parent-forward pattern.
- **Moveset binding:** emits `form_shifted(new_form)` so Combat can swap active moveset (Panther takedowns / Monkey counters / Avian archery).
- **FORCED locomotion interrupt on swap:** on the shift frame, `EntityController` also calls `MovementBroker.inject_forced_proposal(FormShiftProposal)` so Movement surrenders its current mode for one tick while the collision shape and motor mask settle (prevents mid-air motor conflict).
- **Form-agnostic Camera enforcement:** composition root **must not** pass a Form reference to `CameraRig`. No Form API exists on the Camera side.
- **Form read-only exposure:** owns `FormComponent` (mutable, internal) and `FormReader` (exposes `get_active_form()` + `form_shifted` signal) to UI, Combat, Audio, Progression.

**OUT OF SCOPE (but architecture must not forbid):**
- Form-specific camera reframing — **banned** (see Camera out-of-scope).
- Per-form Movement motor *parameters* — Movement owns parameter tables; Form just declares the mask.
- Unlock / progression gating of forms — owned by Progression (LOOSE bridge).
- Transformation animation / particle burst — owned by Audio + VFX (LOOSE bridges).
- Shapeshift during cutscenes — cinematic scope.
- Partial / hybrid forms — exactly three discrete forms; no blending.
- Per-form HP pools — single shared HP owned by Health.

---

## Shared Contracts (cluster-wide)

Declared **once** across the cluster; every producer/consumer implements the abstract type (Rule 10). For each contract the **owning system** is named; cluster members listed under "Consumers within the cluster" hold the Reader variant unless noted.

### Cross-entity (Movement + Combat share the same stack)

- **`Brain`** *(owner: Movement)* — abstract base class. Produces an `Intents` struct per physics tick. Implementations in MVP: `PlayerBrain` (keyboard / mouse / gamepad), `AIBrain` (behavior tree / FSM for enemies). Future: `RemoteBrain`.
- **`Intents`** *(owner: Movement — struct; populated by Movement and Combat)* — the single cross-entity input contract. Carries movement AND combat fields from day one because the same struct crosses the same Brain → Broker boundary for every entity, player or enemy.
  - **Movement fields:** `move_dir`, `wants_jump`, `wants_sprint`, `wants_sneak`, `wants_climb_release`, `wants_glide`, `wants_mount`.
  - **Combat fields:** `wants_attack`, `wants_parry`, `wants_dodge`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`.
  - **Facing / aim field:** `aim_target: Vector3` (entity facing target — head-look IK, weapon aim direction). Populated by `PlayerBrain` reading `CameraReader.get_forward()`. Not used for camera orientation.
  - **MVP population rule (closes Deferred TODO § 6 of `00-system-map.md`):** every `Brain` populates every field every frame. Combat fields default to `false` / zero when no combat is being intended. `AIBrain` populates combat fields from day one even before Combat ships — Movement motors ignore combat fields, Combat will start consuming them without a struct revision. Unused-per-entity fields staying zero is by construction, not by Brain specialization.
  - Interaction intents are **not** carried in `Intents` (player-only; live in a separate `InteractionIntents` struct owned by Interaction).
- **`Body`** *(owner: Movement)* — abstract mutable container. Owns the `CharacterBody3D`. Public write surface: `apply_motion(velocity)` (Motors only), `teleport(pos, rot)` (single non-motor position choke point). Public read surface: `get_global_position`, `get_velocity`, `get_up_direction`, `is_on_floor`, plus `grounded_changed` and `impact_detected` signals. Also hosts the active collision shape for the current form; `Form` swaps it via `EntityController`-forwarded call.
- **`BodyReader`** *(owner: Movement)* — read-only view of a `Body`. Getters: `get_global_position`, `get_velocity`, `get_up_direction`, `is_on_floor`. Forwarded signals: `grounded_changed`, `impact_detected`. Consumers inside this cluster: Camera (follow + impact-dip + set_target rebind), Combat (hit detection uses post-motion position). Consumers outside the cluster: Health (fall-damage curve via `impact_detected`), Interaction, AI perception, UI. `apply_motion` / `teleport` do not exist on this class.
- **`StaminaComponent`** *(owner: Movement — lives on `EntityController` at entity level)* — mutable stamina owner. Mutators: `drain`, `regen`, `set_max_stamina`. Motors and Combat actions hold mutable refs (declared shared-mutable exception, enforced by the composition root lending refs only to these two systems).
- **`StaminaReader`** *(owner: Movement)* — read-only view. `get_value`, `get_max`, `is_exhausted`; forwarded signals `exhausted`, `stamina_changed`. Consumers: UI, AI perception, Combat (for balance decisions).
- **`LocomotionState`** *(owner: Movement)* — authoritative current locomotion mode. `set_state()` callable by `MovementBroker` only.
- **`LocomotionStateReader`** *(owner: Movement)* — read-only view. `get_active_mode`; forwarded signal `state_changed(old, new)`. Consumers: Camera, Combat (moveset availability gating — e.g., no attacks during `CLIMB`), UI, AI perception.
- **`TransitionProposal`** *(owner: Movement — struct)* — cross-Broker reusable proposal. Fields: `target_state: int`, `category: Priority` (FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT), `override_weight: int` (for deterministic tie-breaking), and `source_id: StringName` (for F1 debug panel tracing). **Reused by Camera** for Mode arbitration and **by Form** for its FORCED interrupt to Movement.

### Camera-owned

- **`CameraInput`** *(owner: Camera — struct, player-only)* — `look_delta: Vector2` (per-frame, NOT cumulative), `wants_lock_on_toggle: bool`, `wants_aim: bool` (hint for predictive smoothing only — ground truth is `AimingReader`).
- **`CameraBrain`** *(owner: Camera)* — abstract. Produces `CameraInput`. Parallel to `Brain`, not shared — AI never drives the camera. Mixing camera input into `Intents` would force `AIBrain` to populate fields it has no reason to compute.
- **`EffectRequest`** *(owner: Camera — struct)* — `effect_type: StringName` (e.g., `&"shake"`, `&"dip"`, `&"fov_zoom"`), `magnitude: float`, `duration_seconds: float`, `easing: Curve` (optional). Validated against a startup-registered effect-class set (Fail Loud on unknown type).
- **`CameraReader`** *(owner: Camera)* — read-only view of live camera transform. Getters: `get_global_position`, `get_forward`, `get_up`, `get_fov_degrees`. Forwarded signals: `aim_state_changed`, `target_rebound(new_target: BodyReader)`. Consumers inside the cluster: `PlayerBrain` (derives `Intents.aim_target` from camera-forward — one-way Read dependency). Consumers outside: future Audio (panning), future VFX (camera-relative particles).

### Combat-owned

- **`DamageEvent`** *(owner: Combat — struct)* — `source: Node3D`, `target: Node3D`, `amount: float`, `damage_type: StringName` (e.g., `&"melee"`, `&"ranged"`, `&"stealth"`), `stagger_class: StringName` (e.g., `&"none"`, `&"light"`, `&"heavy"`, `&"finisher"`). Produced by Combat hit-resolution, consumed by Health (LOOSE bridge).
- **`AimingReader`** *(owner: Combat)* — `is_aiming() -> bool`, signal `aim_state_changed(now_aiming: bool)`. Describes "bow currently drawn," not the input intent. Consumed by Camera's `AimMode`. **MVP stub:** `CombatContextStub` returns `false` until real Combat ships — during MVP, `AimMode` is correctly inert because the bow does not yet exist.
- **`LockOnTargetReader`** *(owner: Combat)* — `get_target() -> Node3D` (or `null`), `has_target() -> bool`, signal `target_changed(new_target: Node3D)`. Consumed by Camera's `LockOnMode`, UI reticle, Audio lock-on stinger. **MVP stub:** `CombatContextStub` returns `null` until real Combat ships.
- **`MovesetBinding`** *(owner: Combat — concept, implementation TBD in Combat Stage 4/6)* — active moveset selection keyed by current form. Subscribes to `FormReader.form_shifted`; on shift, swaps the active `AttackMotor` / equivalent Combat component. Kept as a concept at Stage 1; the concrete class shape is decided in Combat Stage 6.

### Form-owned

- **`FormComponent`** *(owner: Form)* — mutable owner of active form. `set_form(new_form)` callable by `FormBroker` only. Lives on `EntityController`.
- **`FormReader`** *(owner: Form)* — read-only view. `get_active_form() -> StringName` (one of `&"panther"`, `&"monkey"`, `&"avian"`), signal `form_shifted(new_form: StringName)`. Consumers: Combat (moveset swap), Audio (per-form bus routing), UI (form indicator), Progression (usage tracking). Camera does **not** receive this reader.
- **`FormShiftProposal`** *(owner: Form — uses `TransitionProposal` with category = FORCED)* — the one-tick locomotion interrupt injected via `EntityController` into `MovementBroker.inject_forced_proposal()` on shift. Not a new struct; a reuse of `TransitionProposal`.

---

## Architectural Layers

Golden rule: **each layer only talks to the layer next to it. No skipping.** Each system has its own layer stack below — no shared "cluster stack."

### Movement

Strict top-to-bottom:
1. **Brain (Input Generation)** — abstract; `PlayerBrain`, `AIBrain`. Knows nothing about current state, physics, or what the intents will do. Broker accepts `Brain`, not any concrete subclass.
2. **Broker (Orchestrator + Arbiter)** — receives `Intents`, calls `gather_proposals()` on every Motor and Service, picks the winner (FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT; within category, active-exit beats inactive-entry; within a list, stable first-wins), commits the transition, calls `set_state()` on `LocomotionState`, dispatches the per-frame motion step to the Motor owning the new state. **Single choke point for cross-system locomotion interrupts:** `inject_forced_proposal()`. Sibling systems never call this directly — they emit upward signals that `EntityController` forwards down (Rule 13).
3. **Motors (Execution)** — one Motor per locomotion state. Methods:
   - `gather_proposals(current_mode, intents, services) -> Array[TransitionProposal]` — side-effect-free. Intentionally omits `Stamina` and `Body` to structurally forbid mutation during arbitration.
   - `on_enter(body, stamina) -> void`, `on_exit() -> void`, `on_tick(intents, delta) -> void`. Motion math and `body.apply_motion(...)` run only in `on_tick` on the single active Motor.
   - Every Motor and every transition-producing Service declares a const array of `(from_mode, to_mode)` pairs it can ever propose — auditable.
4. **Services & Body (Foundational Layer)** — Services (`GroundService`, `LedgeService`, `WaterService`, `MountService`) are read-only fact providers. Each: `update_facts(body_reader)` every frame, then `gather_proposals(current_mode, intents)` — side-effect-free, may emit FORCED proposals for physics-driven transitions (stair snap, auto-vault, ground reattach). Services receive `BodyReader` only; they cannot mutate. Services never call Motors. Body and Services live side-by-side; Motors speak downward to both.
### Camera

Strict top-to-bottom:
1. **CameraBrain (Input Generation)** — abstract; `PlayerCameraBrain` in MVP. Produces `CameraInput`.
2. **CameraBroker (Orchestrator + Arbiter)** — receives `CameraInput`, gathers Mode proposals (each Mode returns 0 or 1 `TransitionProposal` — reused from Movement), picks winner, dispatches active Mode, iterates the active Effect stack, composes the final transform, writes to `Lens`. Owns `request_effect(EffectRequest)` and `set_target(BodyReader)`.
3. **CameraModes & CameraEffects (Execution, sibling depths)** — Modes are mutually exclusive (one base transform per frame): `FollowMode`, `AimMode`, `LockOnMode`. Effects are stackable (multiple per frame): `DipEffect`, `ShakeEffect`, `FOVZoomEffect`, `FollowEaseInEffect`. Modes and Effects sit at the same depth so Effects can modify any Mode's base transform without being conditional on which Mode is active.
4. **CameraServices & Lens (Foundational Layer)** — `OcclusionService` casts rays from the candidate camera position back toward the target, returns max unobstructed distance; Modes clamp their distance. Services receive `BodyReader` only. `Lens` owns `Camera3D` + `SpringArm3D` + the visual-interpolation step in `_process` (the only `_process` in this cluster). Single `Camera3D` write surface — nothing else sets `Camera3D.global_transform`.
### Combat

Strict top-to-bottom:
1. **Brain (Input Generation — shared with Movement)** — Combat does not add a new input layer. Combat fields on `Intents` are populated by the same `Brain` that populates movement fields. `PlayerBrain` reads input keys for attack / parry / dodge / aim / release. `AIBrain` reads target perception and decides combat intents.
2. **CombatBroker (Orchestrator + Arbiter)** — receives `Intents` post-motion (tick slot 5, see Tick Architecture). Reads `BodyReader` for final positions. Arbitrates which Combat action fires (only one active moveset per entity at a time, chosen by current form via `FormReader`). Performs hit resolution: ray casts / overlaps, produces `DamageEvent` per hit, emits `hit_landed(DamageEvent)` and `stagger_triggered(target)` upward. Maintains lock-on target state.
3. **Combat Actions (Execution, moveset-bound)** — concrete per-form action set, keyed off `FormReader.get_active_form()`:
   - Panther: `TakedownAction` (proximity + stealth-gated instant kill).
   - Monkey: `ParryAction` + `CounterAction` (window, counter, stagger).
   - Avian: `BowAction` (draw → aim → release).
   Each action implements `gather_decision(intents, readers) -> CombatDecision` (side-effect-free) and `execute(decision, body_reader, stamina) -> Array[DamageEvent]`. Actions drain `StaminaComponent` via the lent mutable reference. Moveset availability gated by `LocomotionStateReader` (no attacks during `CLIMB`, `SWIM`, `MOUNT`).
4. **CombatServices & CombatTargeting (Foundational)** — `HitDetectionService` (casts/overlaps, uses `BodyReader` for origin), `LockOnService` (candidate-target scanning, scoring, selection — owns the `LockOnTargetReader` surface). Services are read-only about the world; they mutate only Combat-owned state (lock-on target selection).

### Form

Strict top-to-bottom:
1. **Brain (Input Generation — shared with Movement)** — form-shift intent is a combat/input action like any other. `PlayerBrain` reads the shapeshift key and populates an additional `wants_form_shift: StringName` field on `Intents` (value = requested form, or `&""` for "no change"). `AIBrain` may drive form shifts for shape-shifting enemies (future). **Note:** `wants_form_shift` is a new combat-adjacent `Intents` field added in this artifact; documented in Shared Contracts → `Intents`.
   - *Update to `Intents` closing Deferred TODO § 6:* the final MVP field list is `{move_dir, wants_jump, wants_sprint, wants_sneak, wants_climb_release, wants_glide, wants_mount, wants_attack, wants_parry, wants_dodge, wants_archery_aim, wants_archery_release, wants_assassinate, wants_form_shift, aim_target}`.
2. **FormBroker (Orchestrator + Arbiter)** — receives `Intents.wants_form_shift`, validates against `available_forms()` (reads `ProgressionReader`; pre-Progression MVP returns all three). If valid and different from current: calls `FormComponent.set_form(new_form)`, emits `form_shifted(new_form)`, and constructs a `FormShiftProposal` (FORCED `TransitionProposal`) to be forwarded by `EntityController` into `MovementBroker`.
   - Ticks BEFORE `MovementBroker` (slot 3, see Tick Architecture) so Movement arbitrates with the correct motor mask on the same frame as the shift.
3. **Form Shape Swap (Execution)** — on `set_form`, `FormBroker` emits upward; `EntityController` catches and calls `Body.swap_collision_shape(shape_for_form)`. The shape catalog lives on `FormBroker` (one `Shape3D` resource per form). This is the one-frame transition budget.
4. **FormServices (Foundational — minimal)** — no world queries yet. A placeholder for future form-specific service needs (e.g., form-availability gating based on zone).

---

## Cross-System Seams *(cluster-internal)*

The TIGHT coupling between these four systems lives here. Every seam names the contracts crossing, the tick-order dependency, the structural enforcement, and any latency budget. Seams that are NONE / LOOSE are listed explicitly so future readers see the decision, not just silence.

### Movement ↔ Camera

- **Contracts flowing:** Movement → Camera via `BodyReader` (Camera's follow target), `BodyReader.impact_detected` (landing signal), `LocomotionStateReader` (mode-change reactions). Camera → Movement via `CameraReader.get_forward()` (read by `PlayerBrain` to populate `Intents.aim_target`).
- **Tick-order dependency:** **Camera ticks AFTER Movement** (slot 6, always last). If Camera ticked before Movement, the rig would lag player position by one physics frame — visible during fast motion.
- **Structural enforcement:** Camera holds `BodyReader`, never `Body`. `apply_motion` and `teleport` do not exist on the class Camera holds.
- **Signal filtering contract (`min_impact_velocity`):** `Body` emits `impact_detected` on **every** ground reattach — stairs, pebbles, micro-airtime on bumpy slopes. If Camera applied `DipEffect` on every event, the screen would micro-vibrate. Camera owns a `min_impact_velocity: float` tuning value (camera-feel parameter, not a movement fact). `BodyReader.impact_detected(velocity)` listener on `CameraRig` filters: if `velocity.y > -min_impact_velocity` (sub-threshold) no `DipEffect` is pushed; above-threshold magnitude scales with `abs(velocity.y)`. Movement stays dumb about what counts as a "hard" fall.
- **Mount-swap target rebind:** `CameraRig.set_target(target_reader: BodyReader)` is the **single choke point** for active-entity swap; mandated at Stage 1. On call: Camera disconnects from previous `BodyReader.impact_detected`, connects to new, pushes a `FollowEaseInEffect` (~200 ms) onto the effect stack so the transition is not a hard snap. Caller of `set_target` is `MountManager` (future) or `PlayerController` (MVP) — identity of the caller is a Deferred TODO in `00-system-map.md` Row 2, not closed here.
- **Aim seam (via Combat):** `Intents.wants_archery_aim` is an intent, not a fact. Camera reading it directly would flip `AimMode` whenever the button is pressed even as Panther (no bow). Camera consumes `AimingReader` ("is the bow actually drawn"), owned by Combat. See Camera ↔ Combat below.

### Movement ↔ Combat

- **Contracts flowing:** The cluster's deepest coupling. Combat enemies share the Movement stack — one `EntityController`, one Brain, one MovementBroker, one Body, one StaminaComponent per enemy entity. Shared struct: `Intents` carries combat fields for day-one polymorphism. Shared mutable state: `StaminaComponent` (Motors drain for sprint/climb/glide, Combat actions drain for dodge/parry). Combat reads post-motion `BodyReader` for hit detection.
- **Tick-order dependency:**
  - Slot 1 (`Brain.gather_intents`) populates movement AND combat fields in the single `Intents`.
  - Slot 4 (`MovementBroker.tick`) consumes movement fields only.
  - Slot 5 (`CombatBroker.tick`) consumes combat fields and reads post-motion `BodyReader`.
  - Consequence: Combat sees positions **after** the current frame's motion. Hit detection uses the correct frame-end state.
- **Structural enforcement:** Combat holds `BodyReader` (not `Body`), holds `StaminaComponent` mutably (declared shared-mutable exception lent by `EntityController`). Combat does **not** hold `MovementBroker` — cannot call `inject_forced_proposal` directly.
- **Stagger / forced-interrupt path (Rule 13, upward-signal-forward):**
  1. Combat hit resolution produces a `DamageEvent` with `stagger_class`.
  2. `CombatBroker` emits `stagger_triggered(DamageEvent)` upward on the attacker's or victim's `EntityController`.
  3. `EntityController` catches the signal, builds a FORCED `TransitionProposal` (e.g., `(current, STAGGER)`), calls `MovementBroker.inject_forced_proposal(proposal)`.
  4. The proposal is **queued** and arbitrated on the next `MovementBroker.tick` — **1-frame latency budget** is the documented cost of enforcing the sibling-never-calls-sideways rule.
- **Shared-struct consistency contract:** the cluster-scoped `06-interfaces-and-contracts-player-action-stack.md` is the single authoritative declaration site for `Intents`. Movement and Combat both consume the same struct; there is no second declaration to keep in sync.

### Movement ↔ Form

- **Contracts flowing:** Form → Movement via three downward calls (all routed through `EntityController`): `MovementBroker.set_allowed_motors(mask)`, `MovementBroker.inject_forced_proposal(FormShiftProposal)`, `Body.swap_collision_shape(shape)`. Movement → Form: nothing. Form never reads Movement state directly.
- **Tick-order dependency:** **Form ticks BEFORE Movement** (slot 3, before slot 4). Rationale: the shapeshift changes both the motor mask and the collision shape. If Form ticked after Movement, Movement would arbitrate with the old form's motors for one frame (wrong).
- **Structural enforcement:** Per Rule 13, `FormBroker` does not hold a reference to `MovementBroker`. On shift, `FormBroker` emits `form_shifted(new_form)` upward; `EntityController` catches and fans out three downward calls on the same frame: `MovementBroker.set_allowed_motors(mask)`, `MovementBroker.inject_forced_proposal(FORCED)`, and `Body.swap_collision_shape(shape)`.
- **Latency budget:** the FORCED proposal is queued and consumed by the **next** `MovementBroker.tick`. However, because Form ticks in slot 3 and Movement ticks in slot 4 on the **same** frame, the queued proposal drains on the same frame as the shift — latency = 0 frames for this specific path. This is the only "same-frame forced-interrupt" path in the cluster; it is load-bearing for shapeshift feel and explicitly relies on the tick-order-same-frame guarantee.

### Combat ↔ Form

- **Contracts flowing:** Form → Combat via `FormReader.form_shifted`. Combat subscribes and swaps the active moveset (Panther takedowns / Monkey counters / Avian archery).
- **Tick-order dependency:** Form (slot 3) ticks before Combat (slot 5). On a shift frame, by the time `CombatBroker.tick` runs, `FormReader.get_active_form()` reports the new form; Combat dispatches the new moveset on the same frame as the shift.
- **Structural enforcement:** Combat holds `FormReader`, never `FormComponent`. Combat cannot call `set_form`. `MovesetBinding` is keyed off `FormReader` only.
- **Mid-combat shapeshift state transition:** Combat's per-action state (mid-attack, mid-parry, bow-drawn) is torn down when `form_shifted` fires. Each `CombatAction` implements an `on_form_shift(new_form)` hook that runs cleanup (release bow, cancel parry window). Same `on_enter(new_action)` fires for the incoming moveset. This is the cross-system state-transition contract; details land in Combat Stage 4/6.

### Camera ↔ Combat

- **Contracts flowing:** Combat → Camera via `AimingReader` (bow-drawn state — triggers `AimMode`), `LockOnTargetReader` (who is locked — triggers `LockOnMode`), `CameraRig.request_effect(EffectRequest)` (screen shake on hit). Camera → Combat: nothing. Camera never reads Combat state via mutable handles.
- **Tick-order dependency:** Combat (slot 5) ticks before Camera (slot 6). Camera observes final Combat state on the same frame as hit resolution — screen shake arrives one tick after the hit, but within the same frame's composited render.
- **Structural enforcement:** Camera holds `AimingReader` and `LockOnTargetReader`, never their mutable owners. Camera does **not** hold any handle that could mutate combat state.
- **Coupling verdict remains LOOSE** despite the transitive TIGHT chain (Camera ↔ Movement ↔ Combat): no shared data struct (Camera never touches `Intents` or `StaminaComponent`); no shared entity composition (Camera is a single-instance rig, not per-entity); Camera consumes only Reader stubs — `BodyReader`, `AimingReader`, `LockOnTargetReader`. The LOOSE classification survives cluster membership because the structural isolation is intact.

### Camera ↔ Form

- **Coupling:** **NONE — structurally enforced.**
- **Enforcement:** The composition root **must not** pass a Form reference to `CameraRig`. There is no field on `CameraRig` to receive a Form. Per-form camera reframing is **banned by design**, not just deferred — if a future design wants it, this rule must be revisited with explicit acknowledgement.
- **Rationale:** Camera must stay form-agnostic so gameplay-critical camera behaviors (follow, aim, lock-on, occlusion) never differ by shape. Form differentiation is communicated by UI, vignette, post-FX — never by the camera.

---

## Entity Composition (structural isolation)

### Shared entity (player and every enemy)

One `EntityController` per entity. No gameplay logic lives on it; it is pure wiring and the upward-signal-forward hub (Rule 13).

```text
EntityController (Node3D — composition root, no gameplay logic)
│
├── Movement
│   ├── Brain                  (concrete: PlayerBrain | AIBrain — emits Intents)
│   ├── MovementBroker         (holds refs to Motors, Body full, Stamina full, LocomotionState full)
│   │   └── LocomotionState    (full — set_state() called by MovementBroker only)
│   ├── Motors                 (hold refs to Body full, Stamina full, Services, BodyReader)
│   ├── Services               (hold refs to BodyReader + world)
│   └── Body (full)            (owns CharacterBody3D + active collision shape)
│
├── Combat
│   ├── CombatBroker           (holds refs to BodyReader, StaminaComponent mutable, FormReader, HealthReader)
│   ├── CombatActions          (moveset-bound: TakedownAction | ParryAction+CounterAction | BowAction)
│   ├── CombatServices         (HitDetectionService, LockOnService)
│   └── CombatContextStub      (MVP stub providing AimingReader + LockOnTargetReader — replaced by
│                               real Combat publishers when full Combat ships)
│
├── Form
│   ├── FormBroker             (holds shape catalog, validates shifts against ProgressionReader)
│   └── FormComponent          (full — set_form() called by FormBroker only)
│
├── StaminaComponent (full)    (owned by EntityController — lent mutable to Motors AND Combat actions)
│
├── (Other standalone components wired in later: HealthComponent owned by Health, ProgressionTracker
│    owned by Progression — LOOSE bridges, not this cluster's concern but listed here as placeholders.)
│
│   ═══ Exposed publicly (Reader surface — external systems receive ONLY these) ═══
├── BodyReader
├── StaminaReader
├── LocomotionStateReader
└── FormReader
```

**EntityController role clarity (closes Deferred TODO § 4 of `00-system-map.md`):**
- **Owns:** StaminaComponent (lives at entity level, lent to Motors and Combat).
- **Wires:** constructs the three system Brokers (Movement, Combat, Form) in a known order at `_ready()`, hands each the Readers and mutable refs it is entitled to.
- **Forwards upward signals to downward calls (Rule 13, the only place this fan-out happens):**
  - `CombatBroker.stagger_triggered` → `MovementBroker.inject_forced_proposal(FORCED)`.
  - `HealthComponent.defeated` / `hp_zeroed` → `MovementBroker.inject_forced_proposal(RAGDOLL|DEFEAT)`.
  - `FormBroker.form_shifted` → `MovementBroker.set_allowed_motors(...)` + `MovementBroker.inject_forced_proposal(FormShiftProposal)` + `Body.swap_collision_shape(...)`.
  - Future `InteractionBroker.cinematic_requested` → `MovementBroker.inject_forced_proposal(CINEMATIC)`.
- **Does NOT implement gameplay logic.** No physics, no decisions, no state machines. Every method on `EntityController` is either wiring (`_ready()`) or a signal handler that forwards.
- **Runtime assertion** (tracked as Deferred TODO § 7 in `00-system-map.md`, implementation-phase concern): `MovementBroker.inject_forced_proposal` asserts that the caller is the `EntityController` holding this Broker. Not added to Stage 6 contract file here — this is graybox-phase work.

### Single-instance rig (Camera)

Camera is **not** per-entity in MVP. `CameraRig` sits in the main scene.

```text
CameraRig (Node3D — composition root; no gameplay logic)
│
├── CameraBrain (Node)          (PlayerCameraBrain — produces CameraInput; player-only)
│
├── CameraBroker (Node)         (orchestrator; ticked by GameOrchestrator after MovementBroker and
│                                 CombatBroker; owns Mode arbitration, Effect iteration, set_target)
│
├── Modes (Node)                (organizational folder)
│   ├── FollowMode
│   ├── AimMode
│   └── LockOnMode
│
├── Effects (Node)              (organizational folder; runtime stack lives in Broker)
│   ├── DipEffect, ShakeEffect, FOVZoomEffect, FollowEaseInEffect
│
├── Services (Node)
│   └── OcclusionService (Node3D)
│       └── OcclusionRay (RayCast3D)
│
└── Lens (Node3D — output container; only place that writes to Camera3D)
    ├── SpringArm3D
    └── Camera3D
```

External Reader wiring into `CameraRig` (set by top-level scene wiring or `MountManager` on entity-swap):

```text
CameraRig consumes:
├── target_body_reader: BodyReader           (from active Entity — swappable via set_target())
├── aiming_reader: AimingReader              (from CombatContextStub on Entity; real Combat when it ships)
└── lock_on_reader: LockOnTargetReader       (from CombatContextStub on Entity; real Combat when it ships)

CameraRig exposes:
└── CameraReader                             (consumed by PlayerBrain for aim_target; future Audio/VFX)
```

---

## Tick Architecture (cluster-wide — authoritative)

This section is the cluster-authoritative tick order. It mirrors `00-system-map.md` § 4 (Cluster A tick order skeleton) and is the Stage-1-final canonical slot order with Combat and Form populated.

**`GameOrchestrator` is the sole orchestrator.** Project-wide Autoload (`PROCESS_MODE_ALWAYS`) declared in `05-project-scaffold-player-action-stack.md`. It owns the only `_physics_process` in gameplay code and explicitly disables `_physics_process` on every component it ticks: every Brain, every Broker, every Motor, every Service, every Mode, every Effect.

### Per-physics-tick slot order (`GameOrchestrator._physics_process(delta)`)

| Slot | System & Caller | Key Constraint & Rationale |
|---|---|---|
| **1** | **Movement:** `Brain.gather_intents()` | Polymorphic (Player + AI). Populates FULL `Intents` struct (movement + combat fields) using last-frame state. |
| **2** | **Camera:** `PlayerCameraBrain.gather_camera_input()` | Player-only. AI does not drive the camera. |
| **3** | **Form:** `FormBroker.tick()` | Ticks BEFORE Movement. Resolves shift intents, updates motor mask, triggers collision swap so Movement arbitrates with correct mask same-frame. |
| **4** | **Movement:** `MovementBroker.tick()` | Arbitrates, dispatches Motor, applies motion to Body. Drains FORCED proposals queued by Form (slot 3) or cross-system interrupts (last frame). |
| **5** | **Combat:** `CombatBroker.tick()` | Ticks AFTER Movement. Hit resolution only. Needs post-motion positions to register hits accurately. Enqueues FORCED locomotion interrupts (1-frame latency). |
| **6** | **Camera:** `CameraBroker.tick()` | ALWAYS LAST. Reads final Body + Combat state to compose transform and iterate effects. Must see all systems' final frame state. |


### Visual interpolation (`_process` on `Lens` only — the cluster's single `_process`)

`Lens` keeps the previous and current physics-frame target transforms. In `_process(delta)`:

```
Camera3D.global_transform = previous.interpolate_with(current, Engine.get_physics_interpolation_fraction())
```

At 144 Hz visual / 60 Hz physics, the camera moves smoothly between physics samples instead of stepping. Lens explicitly owns this interpolation (Rule 9 — Control the Loop) rather than relying on `Camera3D.physics_interpolation = true`.

**Why Camera is the only system in `_process`:** game logic (collision, hit detection, state machines, damage application, form shifts) must run at a deterministic rate — the physics tick. Presentation (camera transform interpolation) can run at render rate without affecting game state.

---

## Debug Overlay Contexts

Project-wide rule: one F-key per system. This cluster claims four (F1–F4). The project-wide F-key registry is reconstructed by reading all `01-*.md` artifacts together.

| Key | System | Sub-views shown inside this single panel |
|-----|--------|------------------------------------------|
| F1 | Movement | Locomotion state (current, previous, time-in-state, last transition reason + source + category); Stamina (current/max, drain rate, regen rate, exhausted flag, which Motor drained last frame); Ground & physics (grounded, slope angle, surface tag, velocity, acceleration, fall speed); Ledge & climb (detected ledges, wall normals, mantle target, wall-jump launch vector); Water (submerged, depth, surface height, swim state); Mount (nearby mountables, active entity, swap history); Body (position, orientation, collision flags, teleport history); Brain / Intents (active Brain class, raw inputs if PlayerBrain, produced Intents this frame including combat fields and wants_form_shift); Proposals (all proposals this frame, each source's declared from→to pairs, winner); Motors (active motor, motor params, per-motor update cost, active motor mask); Performance (frame time, physics tick time, Movement system total cost, Motor hotspots); Readers & seams (who holds which Reader + signal subscribers). |
| F2 | Camera | Active mode + last transition reason (mode, source, category); Effect stack (each active effect's class, magnitude, time remaining); Occlusion (ray hit point or "clear", current distance vs. desired); Lock-on (target identity, distance to target, frame interpolation status); Lens (current FOV, position, rotation, base transform vs. composited transform); CameraInput (current look_delta, wants_lock_on_toggle, wants_aim); Active target identity (which BodyReader is wired — confirms set_target swaps); Tick timing (last physics-tick time, last `_process` interpolation time). |
| F3 | Combat | Active moveset (bound to current form); Current action state (mid-attack / mid-parry / bow-drawn / idle, time-in-state); Last `DamageEvent` fired (source, target, amount, damage_type, stagger_class); Hit detection state (active ray casts / overlaps this frame, hits/misses); Lock-on (candidates scanned, candidate scores, selected target, time since selection); Last upward signal (stagger_triggered / hit_landed / target_changed) + whether EntityController forwarded a FORCED proposal; Stamina drains attributed to Combat (dodge/parry costs this frame); Combat fields on Intents (wants_attack, wants_parry, wants_dodge, wants_archery_aim/release, wants_assassinate). |
| F4 | Form | Active form; Previous form + time-in-form + last shift reason (PlayerBrain / AIBrain / forced); Motor mask currently sent to MovementBroker (array of allowed motor StringNames); Collision shape currently active on Body (shape resource name); Form shift history (last N shifts, timestamp, triggering Brain); Moveset currently bound via FormReader → Combat; Pending FormShiftProposal status (queued / arbitrated this frame); available_forms() snapshot + ProgressionReader source (pre-Progression MVP: all three). |

The single Context Node per system (`MovementContext`, `CameraContext`, `CombatContext`, `FormContext` — declared in Stage 4 of this cluster) renders all of the above inside one panel toggled by its F-key. Sub-view cycling within a panel (Tab to step) is an internal concern of the panel implementation, not separate F-keys.

---

## Exit Criteria (cluster-wide)

- [x] Explicit 'Out of Scope' items are documented per system (Movement, Camera, Combat, Form), with architectural accommodations noted.
- [x] Strict layers are defined per system (Brain → Broker → execution → foundation) — no fabricated shared "cluster layer stack."
- [x] DebugOverlay declared as observer, exempt from adjacency; single autoload; one F-key per system-in-cluster (F1 Movement, F2 Camera, F3 Combat, F4 Form) with sub-views internal to each panel.
- [x] Non-technical gameplay examples are included for every layer concept.
- [x] Shared contracts (`Brain`, `Intents`, `Body`/`BodyReader`, `Stamina`/`StaminaReader`, `LocomotionState`/`LocomotionStateReader`, `TransitionProposal`, `CameraInput`/`CameraBrain`/`CameraReader`/`EffectRequest`, `AimingReader`/`LockOnTargetReader`/`DamageEvent`/`MovesetBinding`, `FormComponent`/`FormReader`/`FormShiftProposal`) declared with their owning system named.
- [x] `Intents` field list finalized for MVP, including `wants_form_shift` and `aim_target`; AIBrain populates combat fields day-one (closes Deferred TODO § 6).
- [x] Every cross-system pair within the cluster has a Cross-System Seams block: Movement ↔ Camera, Movement ↔ Combat, Movement ↔ Form, Combat ↔ Form, Camera ↔ Combat (LOOSE), Camera ↔ Form (NONE structurally enforced).
- [x] Read-only vs mutable isolation explicitly mapped (entity composition diagram; Camera single-instance block; Reader-only public surface).
- [x] Rule 13 upward-signal-forward path documented for every cross-system forced interrupt (Combat stagger, Health defeat — LOOSE out-of-cluster, Form shift, future Interaction cinematic).
- [x] Tick architecture section specifies the full 6-slot physics-tick order with rationale for each slot placement, plus the single `_process` slot on `Lens`.
- [x] `CameraRig.set_target(BodyReader)` mandated as Stage-1 MVP contract; `min_impact_velocity` threshold mandated as Stage-1 to prevent micro-dip jitter.
- [x] Form-agnostic Camera behavior structurally enforced (composition root has no field to pass a Form reference — not a discipline rule).
- [x] Hit-pause classified out-of-scope for Camera (owned by future `TimeScaleService`); screen-shake request path documented (`CameraRig.request_effect`).
- [x] EntityController role documented: owns StaminaComponent, wires three Brokers, forwards all upward signals to downward calls, implements no gameplay logic (closes Deferred TODO § 4).
