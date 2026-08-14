> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Data Flow

> **Scope of this artifact.** Cluster-scoped Stage 2 for Cluster A: **Movement, Camera, Combat, Form** (per `00-system-map.md` § 2–3 and `01-scope-and-boundaries-player-action-stack.md`). Defines the single `GameOrchestrator` autoload, its registration contract, the **tick-slot structural lock**, the per-slot execution order with Fail Early + Structural Enforcement, and cross-system narrative traces.

---

## Core Design Principles: Compliance with Architecture Protocol

This data flow structurally enforces the rules in `docs/architecture/CONSTITUTION.md`:

| Rule | Local Mechanism |
|---|---|
| **2. Structure Enforces Rules** | Orchestrator knows only bundle types. No `.entity` surface exists. |
| **4. Fail Loud, Fail Early** | Per-slot `assert()`s; Bundle `_init` asserts; Registry freeze. |
| **5. Data is Blind** | Brokers receive `Intents` via parameter (read-only by contract/hash-assert). |
| **6. Single Source of Truth** | `Intents` lives exclusively in `EntityTickBundle._intents`. |
| **9. Control the Loop** | Orchestrator is the sole `_physics_process` owner; disables child ticks on register. |
| **10. Input is Just Another Fact** | Slot 1 polymorphic iteration — player/enemy brains share identical `populate()` API. |
| **12. Signals Describe the Past** | Cross-system signals (`stagger_triggered`, etc.) fire after state mutations. |
| **13. Data Down, Events Up** | Slots 3–5 receive downward params. Cross-system interrupts fan-out via `EntityController`. |
| **14. No Global State** | Orchestrator holds bundle arrays only. State lives on entity nodes. |

---

## The Orchestrator

### Class

**Contract Signature:**
- `GameOrchestrator extends Node` (Autoload, `PROCESS_MODE_ALWAYS`)

- **Autoload:** project-wide singleton, instantiated by Stage 5. Runs even during pause (pause is handled via `process_mode` on game-state nodes).
- **Debug-build-agnostic:** Production tick driver. Runs in release builds.
- **Sole `_physics_process` owner:** Disables `_physics_process` on registered bundle children.
- **Out of scope:** Game state. Holds bundle arrays only.

### Registration contract — the four lock mechanisms

The lock is a **typed-bundle + enum + ordered-method-body** contract. The bundle is load-bearing — it solves slot-order, entity-coherence, and Intents-SSoT in a single declared surface so the Orchestrator never reaches through entity internals.

#### Mechanism 1: `TickSlot` enum (value-ordered, exhaustive)

**Contract Signature:**
1. `BRAIN_INTENTS`
2. `CAMERA_BRAIN_INPUT`
3. `FORM_BROKER`
4. `MOVEMENT_BROKER`
5. `COMBAT_BROKER`
6. `CAMERA_BROKER`

Enum **values are ordered and load-bearing.** The order encodes the design invariants from Stage 1's Tick Architecture. (Rationale for this specific order is canonically declared in `01-scope-and-boundaries-player-action-stack.md` and is not re-derived here).

Reordering the enum is a visible diff in one file with mandatory commentary — loud and reviewable, not silent. The enum is the artifact-level contract that downstream stages (Stage 5 scaffold, audit Rule A) cross-check against.

#### Mechanism 2: `EntityTickBundle` — per-entity tick participant

This is the structural answer to three concerns at once: *where do produced Intents live between slot 1 and slots 3–5?*, *how do we guarantee entity E's Brain feeds entity E's brokers?*, and *how does the Orchestrator stay dumb about entity internals?*

**Contract Signature:**
- **State:** `_intents: Intents`
- **Init:** Requires `Brain`, `FormBroker`, `MovementBroker`, `CombatBroker` (Asserts all non-null).
- **Surface:** `gather_intents()`, `tick_form(delta)`, `tick_movement(delta)`, `tick_combat(delta)`.

What this enforces:

| Feature | Rule Enforced |
|---|---|
| **Intents storage owner** | One `Intents` struct per entity, owned by bundle. Closes the slot-1-to-slot-3-5 carrier gap. |
| **Entity coherence** | `_init` asserts all 4 refs non-null. Cannot construct or register without matching brokers. |
| **Orchestrator opacity** | Orchestrator only calls the 4 public methods. No accessors to internals. Structurally prevents spelunking. |
| **Brain mutates, brokers read** | `Brain.populate` writes in slot 1; brokers read via `tick` parameter (Rule 5). Enforced by audit/hash assertion. |

#### Mechanism 3: `CameraTickBundle` — single-instance variant for slots 2 and 6

Camera is a single-instance rig (Stage 1). It gets its own bundle type — not a subclass of `EntityTickBundle` — because its inputs and timing differ:

**Contract Signature:**
- **State:** `_input: CameraInput`
- **Init:** Requires `CameraBrain`, `CameraBroker` (Asserts non-null).
- **Surface:** `gather_camera_input()`, `tick_camera(delta)`.

Type separation is deliberate. Passing a `CameraTickBundle` to `register_entity_bundle` (or vice versa) fails GDScript static typing — the bug is caught before the game runs. A future split-screen design that needs per-player rigs would change `_camera_bundle` from a single field to an `Array[CameraTickBundle]`; the bundle's internal contract is unchanged.

#### Mechanism 4: `GameOrchestrator` — bundle-only registration + ordered-method-body loop

**Contract Signature:**
- **State:** `_entity_bundles: Array[EntityTickBundle]`, `_camera_bundle: CameraTickBundle`, `_registry_frozen: bool`
- **Registration:** `register_entity_bundle(bundle)`, `register_camera_bundle(bundle)`. (Asserts `not _registry_frozen`).
- **Loop:** `_physics_process(delta)` Freezes registry, iterates slots 1-6 in strict order over registered bundles.

Properties:

| Feature | Rule Enforced |
|---|---|
| **Restricted Types** | Orchestrator knows only bundle types (no `.entity`). Preserves composition-root pattern. |
| **Visible Slot Order** | Executed in a single method body. Reorders are visible, auditable one-file diffs. |
| **Polymorphic Iteration** | Ticks player and enemy brains via same surface (Rule 10). |
| **Type-correctness** | Cross-bundle registration fails static typing. |
| **Registry freeze** | `_registry_frozen` blocks mid-game churn. Late registration requires an explicit, loud toggle. |

### `EntityController` and `CameraRig` construction contract

Bundle construction is the composition root's job. The Orchestrator never sees an `EntityController` or `CameraRig`.

**Contract Signature:**
- `EntityController._ready()`: Wires children -> Constructs `EntityTickBundle` -> Calls `register_entity_bundle`.
- `CameraRig._ready()`: Wires children -> Constructs `CameraTickBundle` -> Calls `register_camera_bundle`.

A missing system on the entity scene (e.g., scene file forgot to include `CombatBroker`) fails at `EntityTickBundle._init` with a descriptive assert — at scene load, not at first tick. Fail-loud-fail-early at entity construction (Rule 4).

The exact ordering of `_wire_brain_and_brokers()` (which child constructs first, which Readers are lent in which order) is a Stage 5 (project scaffold) concern, not Stage 2.

---

## The 6-Slot Execution Order

For each slot: **What runs**, **Fail Early**, **Structural Enforcement**.

Slot rationale (why Form before Movement, why Combat after Movement, why Camera last) is canonically declared in `01-scope-and-boundaries-player-action-stack.md` § "Tick Architecture → Rationale for slot placement." This artifact does not re-derive it.

### Slot 1 — `BRAIN_INTENTS`

| Aspect | Detail |
|---|---|
| **What Runs** | Polymorphic. `EntityTickBundle.gather_intents()` calls `Brain.populate(_intents)`. `PlayerBrain` and `AIBrain` write to identical `Intents` structs. |
| **Fail Early** | `assert(_intents.is_complete())` ensures no field is implicitly null/unset. |
| **Structure** | `Brain` receives writable `Intents` but no state refs. Private `_intents` is mutated via parameter only. |

### Slot 2 — `CAMERA_BRAIN_INPUT`

| Aspect | Detail |
|---|---|
| **What Runs** | Single-rig. `CameraBrain.populate(_input)` writes player input. Aim intent is for smoothing hint only; ground truth is in Slot 6. |
| **Fail Early** | Rig gated by `if _camera_bundle:`. Postcondition: `assert(_input != null)`. |
| **Structure** | `CameraBrain` has no `Intents` field. AI never drives camera. `CameraInput` is bundle-private. |

### Slot 3 — `FORM_BROKER`

| Aspect | Detail |
|---|---|
| **What Runs** | `FormBroker.tick` reads `wants_form_shift`. On shift, emits `form_shifted` up. `EntityController` synchronously fans out allowed motors, FORCED proposal, and shape swaps downward. |
| **Fail Early** | Invalid form value asserts immediately. Empty motor mask asserts to prevent lock-up. |
| **Structure** | `FormBroker` lacks `MovementBroker` ref (Rule 13). `FormComponent.set_form` is exclusively called by Broker. Shape swaps route through `Body`. |

### Slot 4 — `MOVEMENT_BROKER`

| Aspect | Detail |
|---|---|
| **What Runs** | `MovementBroker.tick` drains `_external_proposals` (EC interrupts), arbitrates motors/services, transitions state, executes motion, and emits `impact_detected` up on landing. |
| **Fail Early** | Target state must exist in `allowed_motors` mask. Broker must have `active_motor` post-transition. |
| **Structure** | Sole owner of mutable `LocomotionState`. Motors hold mutable `Body`/`Stamina`; services read-only. `inject_forced_proposal` is the strict choke point. |

### Slot 5 — `COMBAT_BROKER`

| Aspect | Detail |
|---|---|
| **What Runs** | Post-motion hit resolution. Emits `hit_landed`. Target's EC responds to `stagger_triggered` by injecting a FORCED proposal to target's `MovementBroker` (queued for frame N+1). Updates `LockOnTargetReader`. |
| **Fail Early** | Asserts `active_action` (moveset bound). Negative damage asserts (preventing smuggled healing). |
| **Structure** | Holds read-only `BodyReader`, `FormReader`, `HealthReader`. Lacks `MovementBroker` ref, enforcing 1-frame latency structurally via EC. Data is blind (`DamageEvent` struct). |

### Slot 6 — `CAMERA_BROKER`

| Aspect | Detail |
|---|---|
| **What Runs** | Reads final preceding slots (`AimingReader`, `LockOnTargetReader`, post-motion `BodyReader`). Arbitrates modes, processes pushed effects, writes composited transform to `Lens`. |
| **Fail Early** | Missing follow target at startup asserts. Asserts `active_mode` and validates `EffectRequest` types. |
| **Structure** | Holds only Readers. No game state mutation. `Lens` solely writes to private `Camera3D`. Structurally NONE Form coupling. |

---

## Visual Interpolation — The Single `_process` Slot

`Lens` is the **only** node with a `_process` override. Everything else is disabled by Orchestrator registration.

| Aspect | Detail |
|---|---|
| **Interpolation** | `_process` runs at render-rate, blending `_previous_transform` and `_current_transform`. |
| **Fail Early** | Asserts both transforms exist (disabled via `set_process(false)` until first physics write). |
| **Structure** | Sole writer of `Camera3D.global_transform`. Documented exception to Rule 9 (Orchestrator loop) because it runs at visual Hz. |

---


## Residual Risks (explicit, not hidden)

| Risk | Mitigation |
|---|---|
| **Dev reorders slots in `_physics_process`** | One-file diff with mandatory commentary. Auditor sign-off required. Better than implicit dependency graphs. |
| **Dev expands `EntityTickBundle` public API** | Bundle is intentionally minimal. Expansion is obviously suspicious in code review. |
| **Brokers mutate the `Intents` struct** | GDScript lacks `const` params. Mitigated by debug-build `_intents.compute_hash()` asserts. Audit catch. |
| **Mid-game registration after first tick** | `_registry_frozen` asserts. `_ready()` runs before next tick so spawns are safe. Loud toggle required to override. |

---

## Exit Criteria

Stage-file checklist (`workflow/stages/architecture/02-data-flow.md`):

- [x] A single Orchestrator is defined (`GameOrchestrator` autoload, sole `_physics_process` owner).
- [x] Exact step-by-step execution loop is documented (6-slot order with bundle-driven dispatch).
- [x] Every step includes a 'Fail Early' assert explicitly crashing on bad contract data.
- [x] Every step declares its 'Structural Enforcement' (who has what wrapper / Reader / mutable ref).
- [x] Data flows strictly adjacent layer to adjacent layer (cross-system flow goes through `EntityController` upward-signal-forward — Rule 13).
- [x] At least 2 non-technical trace examples map the data flow to gameplay (4 traces: A baseline, B 0-frame shift, C 1-frame stagger, D LOOSE-bridge fall-damage).

Cluster-A-specific:

- [x] `GameOrchestrator` knows only `EntityTickBundle` and `CameraTickBundle` types; never reaches through `.entity` or `.intents`.
- [x] `TickSlot` enum values are ordered and declared load-bearing; reordering is documented as a loud, reviewable change.
- [x] `EntityTickBundle` declares `Intents` storage ownership (closes the slot-1-to-slot-3-5 carrier gap).
- [x] `EntityTickBundle._init` requires all four refs (Brain + FormBroker + MovementBroker + CombatBroker) non-null — entity coherence guaranteed at construction.
- [x] Registration methods are typed (`register_entity_bundle` vs `register_camera_bundle`); cross-type registration fails GDScript static typing.
- [x] Registry freezes at first tick; mid-game registration asserts.
- [x] Lens visual interpolation is the cluster's only `_process` override; documented as the single exception with rationale.
- [x] Residual risks are explicitly listed, not hidden.
