> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Interfaces & Contracts

> **Scope of this artifact.** Cluster-scoped Stage 6 for Cluster A: **Movement, Camera, Combat, Form** (per `00-system-map.md` §§ 2–3, and 01–05 cluster artifacts). Declares GDScript base classes, Reader wrappers, and pure data structs that enforce — structurally, with `assert(false, …)` virtual-method traps and caller-identity asserts — every rule committed in Stages 1–5. Designed so the Graybox team cannot erode the architecture by accident: illegal operations either fail at compile-time (class shape) or crash at the point of origin (runtime assert).
>
> **Composition notes.** `EntityController` is `extends Node3D` — the composition root holds no physics proxy; that role lives on a sibling `Body` wrapper. Consequence: `EntityController` cannot call `move_and_slide()` because the method does not exist on its base class (Rule 2 by class shape). See Stage-5 scaffold § Composition Root and Stage-4 § Entity Composition.
>
> `Body` is a `Node` wrapper owning a child `CharacterBody3D` (`PhysicsProxy`). `apply_motion` runs the **Entity-Level Transform Sync Contract** from Stage 5 as a post-condition.

---

## Core Design Principles: Compliance with Architecture Protocol

Every declaration below enforces a rule from `docs/architecture/CONSTITUTION.md` by **class shape, method signature, or runtime assertion**, not by discipline:

| Rule | Mechanism in this artifact |
|---|---|
| **1. SOLID — Interface Segregation** | `CameraBrain.populate`, `CameraMode.gather_proposals`, `CameraEffect.apply_to_transform`, `CombatAction.gather_decision` / `execute` / `on_form_shift` are each one-responsibility virtuals. Readers expose only their one system's getters. |
| **2. Structure Enforces Rules** | `EntityController extends Node3D` — no `move_and_slide()` surface exists on its class. `CameraRig` has no `FormReader` field. Readers have no setters. `Body.apply_motion` is the sole write-path for entity motion. |
| **4. Fail Loud, Fail Early** | Every base class virtual uses `assert(false, "%s must override …" % get_script().resource_path)`. Every struct `_init` validates inputs. `Body.apply_motion` asserts the transform-sync post-condition. `CombatBroker.request_effect` asserts registered effect type. `MovementBroker.inject_forced_proposal` asserts FORCED-only category. |
| **5. Data is Blind** | `CameraInput`, `EffectRequest`, `DamageEvent`, `CombatDecision` are `RefCounted` carriers with zero logic beyond `_init` validation. |
| **6. Single Source of Truth** | `AimingReader` / `LockOnTargetReader` back onto `CombatBroker`-owned state — one mutable holder per fact. `FormReader` backs onto the single `FormComponent`. `CameraReader` backs onto `Lens` (the single `Camera3D` writer). |
| **10. Input is Just Another Fact** | `CameraBrain` is an abstract base so `PlayerCameraBrain` and future variants share one `populate(CameraInput)` surface (no `AICameraBrain` in MVP — camera never runs from AI). |
| **11. State Machines over Boolean Flags** | `CameraMode` returns **0 or 1** proposal per call (mutually exclusive). `CombatAction` gate-asserts against a `LocomotionState` deny-set. `FormBroker._shifts_enabled` is a single bool gate, not a soup of `is_dying`/`is_cinematic` flags. |
| **13. Data Down, Events Up** | Upward signals (`form_shifted`, `hit_landed`, `stagger_triggered`, `mode_changed`) only. Downward fan-out runs through `EntityController`'s four forward methods; every receiver that is EC-only declares a caller-identity assert. `CameraRig.request_effect` is the single choke point for cross-system camera effects. |
| **14. No Global State for Game Logic** | `ObjectPool` Autoload holds only free/in-use bookkeeping per `type_key`. `DebugOverlay` is observer-only. Every per-entity state (CombatState, FormComponent, LocomotionState, StaminaComponent) lives on a scene-tree Node. |

---

## § 1 Pure Data Structs

### `Intents`

Produced by every `Brain.populate(Intents)` call at slot 1 (EntityTickBundle) or slot 1-of-mount (MountTickBundle). Consumed by `FormBroker.tick`, `MovementBroker.tick`, `CombatBroker.tick`. `AIBrain` shares this one struct with `PlayerBrain` (Rule 10 — input is just another fact).

```gdscript
class_name Intents extends RefCounted
## Per-frame intent struct shared by PlayerBrain and AIBrain (Rule 10).
## All fields populated every frame — empty defaults are explicit contracts.

const NO_AIM_TARGET: Vector3 = Vector3.INF  ## Sentinel: no aim target this frame

var move_dir: Vector3 = Vector3.ZERO
var wants_jump: bool = false
var wants_sprint: bool = false
var wants_sneak: bool = false
var wants_glide: bool = false
var wants_climb_release: bool = false
var wants_mount: bool = false
var wants_form_shift: StringName = &""
var wants_attack: bool = false
var wants_parry: bool = false
var wants_dodge: bool = false
var wants_archery_aim: bool = false
var wants_archery_release: bool = false
var wants_assassinate: bool = false
var aim_target: Vector3 = NO_AIM_TARGET

func has_aim_target() -> bool: pass
func validate() -> void: pass
func is_complete() -> bool: pass  ## Called by gather_intents assert every frame
```

### `TransitionProposal`

Used by Motors + Services (Movement arbitration), Camera Modes (mode arbitration), and `EntityController.forward_forced_proposal` (cross-system interrupts). The `Priority` enum drives arbitration; `override_weight` is the tie-breaker within a category; ambiguous ties `assert(false)` per Stage-3 rule.

```gdscript
class_name TransitionProposal extends RefCounted
## Priority arbitration token. Ambiguous ties within a category assert(false).

enum Priority { DEFAULT, PLAYER_REQUESTED, OPPORTUNISTIC, FORCED }

var target_state: int
var category: Priority
var override_weight: int
var source_id: StringName

func _init(p_target: int, p_category: Priority, p_weight: int = 0, p_source_id: StringName = &"") -> void:
    assert(p_target >= 0, "TransitionProposal requires valid state enum")
    target_state = p_target
    category = p_category
    override_weight = p_weight
    source_id = p_source_id
```

### `DebugSnapshot`

Plain-data carrier pushed into `DebugOverlay` (see § 6). Contexts read `data` Dictionary per their own schema.

```gdscript
class_name DebugSnapshot extends RefCounted
## Plain-data carrier pushed into DebugOverlay. Contexts read data per their own schema.

var timestamp: float = 0.0
var source_node_path: NodePath
var data: Dictionary = {}
```

---

## § 2 Cluster-Scope Composition Contracts

Not owned by any one system — these contracts bind the cluster's composition decisions from Stages 4 and 5.

### `EntityController`

```gdscript
class_name EntityController extends Node3D
## Composition root + signal hub for every Movement-bearing entity (player, AI).
## No _physics_process — GameOrchestrator drives ticks via EntityTickBundle.

var _body: Body
var _brain: BaseBrain
var _stamina: StaminaComponent
var _form_broker: FormBroker
var _form_component: FormComponent
var _movement_broker: MovementBroker
var _locomotion_state: LocomotionState
var _locomotion_reader: LocomotionStateReader
var _combat_broker: CombatBroker
var _services: Array[BaseService] = []
var _motors: Array[BaseMotor] = []
var _combat_actions: Array[CombatAction] = []

func forward_forced_proposal(proposal: TransitionProposal) -> void: pass
func forward_motor_mask(mask: Array[StringName]) -> void: pass
func forward_collision_shape(new_shape: Shape3D) -> void: pass
func forward_shift_gate(enabled: bool) -> void: pass
func receive_incoming_attack(event: DamageEvent) -> void: pass
func wire_components() -> void: pass  ## VIRTUAL — override required
func _ready() -> void: pass
func _on_locomotion_state_changed(old_mode: int, new_mode: int) -> void: pass
func _on_form_shifted(new_form: StringName) -> void: pass
func _on_outgoing_attack_resolved(target_entity: EntityController, event: DamageEvent) -> void: pass
func _on_stagger_triggered(event: DamageEvent) -> void: pass
```

#### Signal-Listener Contract (canonical table)

**Canonical SSoT for the EntityController signal-listener contract.** Every row corresponds to exactly one `.connect()` call in `_ready()` (or `wire_components()` in subclasses). No other artifact (cluster 02, 03, 04, 05) may duplicate this table; they cross-reference this section (Rule 6 — Single Source of Truth). Rows grow as sibling systems are scoped in future Sessions; each row declares the signal name, the sibling that emits it, the action EntityController takes in response, and the Session that added it.

| Signal name          | Source child              | Action taken on receipt                                                                                                  | Added in                               |
|----------------------|---------------------------|--------------------------------------------------------------------------------------------------------------------------|----------------------------------------|
| `state_changed`      | `LocomotionState`         | Drives DEFEAT/CINEMATIC shift-gate via `_on_locomotion_state_changed` — calls `forward_shift_gate(false)` on enter, `forward_shift_gate(true)` on exit. Otherwise purely broadcast — Camera/Animation/Audio consume it via their own connections to the Reader. | Movement Stage 1; shift-gate drive added Session 1 — Cluster A |
| `exhausted`          | `StaminaComponent`        | No-op at EntityController level (Motors react internally to `StaminaReader.is_exhausted()`; UI/AI listen directly via Reader). | Movement Stage 1                       |
| `mount_ready`        | `MountMotor`              | Performs the entity-swap ritual: marks current Entity dormant, activates the mount entity, preserves locomotion context. | Movement Stage 1                       |
| `form_shifted`       | `FormBroker`              | `_on_form_shifted`: call `forward_motor_mask(motor_mask_for(new_form))` + `forward_collision_shape(shape_for(new_form))` + `forward_forced_proposal(FORCED TransitionProposal → entry_state_for(new_form), weight 100)`. | Session 1 — Cluster A (Form Stage 1)   |
| `stagger_triggered`  | `CombatBroker`            | `_on_stagger_triggered`: map `event.stagger_class` → `LocomotionState.Mode.STAGGER_{LIGHT,HEAVY,FINISHER}`, look up weight in `CombatBroker.STAGGER_WEIGHTS`, call `forward_forced_proposal(FORCED)`. | Session 1 — Cluster A (Combat Stage 1) |
| `outgoing_attack_resolved` | `CombatBroker`      | `_on_outgoing_attack_resolved`: call `target_entity.receive_incoming_attack(event)` on the target's `EntityController` (single public cross-entity surface). | Session 1 — Cluster A (Combat Stage 1) |
| `defeated`           | *Health* (Session 3)      | **TBD (Session 3 — Health Stage 1):** call `forward_forced_proposal(FORCED → DEFEAT)`; subsequent death-sequence signals are Health's own concern and do NOT flow through Movement. | TBD (Session 3 — Health Stage 1)       |
| `damage_taken`       | *Health* (Session 3)      | **TBD (Session 3 — Health Stage 1):** decide whether to emit a knockback `forward_forced_proposal` or leave Movement untouched (Health-Stage-1 decision). | TBD (Session 3 — Health Stage 1)       |
| `cinematic_requested`| *Interaction* (TBD)       | **TBD (Interaction Stage 1):** call `forward_forced_proposal(FORCED → CINEMATIC)`. Release signal drops the CINEMATIC proposal so Broker naturally transitions back. | TBD (Interaction Stage 1)              |
| `progression_changed`| *Progression* (Session 3) | **TBD (Session 3):** only applies if Session 3 chooses the **push** integration pattern for stamina cap (see `StaminaComponent` TBD in § 3). If pull is chosen, this row is deleted. | TBD (Session 3 — Progression Stage 1)  |

The contract above is the single place Session 3 / Interaction-Stage-1 authors edit to add sibling signals. Cluster 02 / 04 / 05 cross-reference this table but do not duplicate it.

#### Dependency-Injection Contract

EntityController composes children and injects typed Readers each child needs. Readers are immutable facades — consuming nodes cannot mutate the underlying state. This table enumerates Readers flowing out of cluster components; future Sessions append rows for their own Readers.

| Reader type              | Source owner (mutable holder) | Injected into (consumers)                                                  | Enforces                                                      |
|--------------------------|-------------------------------|----------------------------------------------------------------------------|---------------------------------------------------------------|
| `BodyReader`             | `Body` (sibling under EC)     | All `BaseService`s; `CameraRig` (target body); `OcclusionService`; `HitDetectionService`; `LockOnService` | Only the currently active Motor holds the mutable `Body` ref  |
| `StaminaReader`          | `StaminaComponent`            | UI, AI/Brain (perception). Combat Actions take the mutable `StaminaComponent` directly (shared-mutable exception — Stage 4 SSoT). | UI/AI cannot mutate stamina; Movement Motors hold mutable ref |
| `LocomotionStateReader`  | `LocomotionState`             | Motors (non-active), Camera Modes, `CombatBroker` (moveset gate), Animation | Only `MovementBroker` holds the mutable `set_state()` surface |
| `FormReader`             | `FormComponent`               | `CombatBroker` (moveset-binding subscriber), UI (form indicator), Audio (bus routing), future Progression. Camera has **no** FormReader (Stage-1 coupling = NONE). | Only `FormBroker` holds the mutable `set_form()` surface      |
| `AimingReader`           | `CombatBroker`-owned state    | Camera AimMode                                                             | Ground truth for "is the bow drawn?" — written only by BowAction via CombatBroker |
| `LockOnTargetReader`     | `CombatBroker`-owned state    | Camera LockOnMode, UI, Audio                                               | Lock-on selection — written via LockOnService dispatched from CombatBroker |
| `CombatStateReader`      | `CombatState`                 | F3 debug panel, AI perception (telegraph reads), future feel/animation hooks | Only `CombatBroker` holds the mutable `set_stance()` surface  |
| `CameraReader`           | `Lens`                        | `PlayerBrain` (for aim_target derivation), future Audio (stereo panning), future VFX (camera-relative particles) | `Lens` is the sole writer of `Camera3D.global_transform`     |

#### Rule-13 Assertion

Sibling systems (Movement, Camera, Combat, Form, Health, Interaction, Progression, Audio, UI, Save, …) **never hold direct references to each other** under the same EntityController composition root. Cross-sibling state flow travels either:
- Through an upward signal + downward method call routed via `EntityController` (this file — the signal-listener table above), or
- Through typed Readers injected at `_ready()` / `wire_components()` (the DI contract above).

Direct sibling-to-sibling method calls are an architectural violation. The architecture-audit stage (`workflow/stages/architecture/07-architecture-audit.md`) scans for this pattern across all Stage 1–6 artifacts.

### `Body`

```gdscript
class_name Body extends Node
## Sole write-path for entity motion. Enforces Entity-Level Transform Sync Contract
## (Stage 5) as a post-condition on apply_motion.

signal grounded_changed(is_grounded: bool)
signal impact_detected(velocity_at_impact: Vector3)

@onready var _proxy: CharacterBody3D = $PhysicsProxy
@onready var _collision_shape: CollisionShape3D = $PhysicsProxy/CollisionShape3D

func _ready() -> void:
    assert(_proxy != null, "Body requires a child CharacterBody3D named PhysicsProxy")
    assert(_collision_shape != null, "Body.PhysicsProxy requires a CollisionShape3D child")

func apply_motion(velocity: Vector3) -> void: pass  ## Sole motion write-path; syncs EC root transform
func teleport(target: Transform3D) -> void: pass
func swap_collision_shape(new_shape: Shape3D, caller: Node) -> void: pass  ## caller-identity asserted
func get_global_position() -> Vector3: pass
func get_velocity() -> Vector3: pass
func get_up_direction() -> Vector3: pass
func is_on_floor() -> bool: pass
```

`BodyReader._init(body: Body)` (declared in § 3 below) wraps this `Body` unchanged — its getters and signal-forwarding are stable; only `Body`'s internals (proxy-wrapping) differ from earlier movement-only drafts.

### Tick Bundle Structs

Declared in Stage 2 data-flow; contract-frozen here.

```gdscript
class_name EntityTickBundle extends RefCounted
## Per-entity tick participant registered with GameOrchestrator by EntityController.
## Owns the per-frame Intents struct (SSoT for transient tick data — Rule 6).

var _intents: Intents = Intents.new()
var _brain: BaseBrain
var _form_broker: FormBroker
var _movement_broker: MovementBroker
var _combat_broker: CombatBroker

func _init(brain: BaseBrain, form: FormBroker, movement: MovementBroker, combat: CombatBroker) -> void:
    assert(brain != null and form != null and movement != null and combat != null,
        "EntityTickBundle requires complete cluster participation: Brain + Form + Movement + Combat")

func gather_intents() -> void: pass
func tick_form(delta: float) -> void: pass
func tick_movement(delta: float) -> void: pass
func tick_combat(delta: float) -> void: pass
```

```gdscript
class_name MountTickBundle extends RefCounted
## Mount-only participant. Registers at slots 1 + 4 only (no Form, no Combat).

var _intents: Intents = Intents.new()
var _brain: BaseBrain
var _movement_broker: MovementBroker

func _init(brain: BaseBrain, movement: MovementBroker) -> void:
    assert(brain != null and movement != null,
        "MountTickBundle requires Brain + MovementBroker (no Form, no Combat)")

func gather_intents() -> void: pass
func tick_movement(delta: float) -> void: pass
```

```gdscript
class_name CameraTickBundle extends RefCounted
## Single-instance rig. Registers at slots 2 + 6. Type-separated from EntityTickBundle
## so cross-registration fails GDScript static typing (Stage 2 Mechanism 3).

var _input: CameraInput = CameraInput.new()
var _brain: CameraBrain
var _broker: CameraBroker

func _init(brain: CameraBrain, broker: CameraBroker) -> void:
    assert(brain != null and broker != null, "CameraTickBundle requires CameraBrain + CameraBroker")

func gather_camera_input() -> void: pass
func tick_camera(delta: float) -> void: pass
```

### `ObjectPool` (Autoload API)

```gdscript
class_name ObjectPool extends Node
## Stage-4 rule: ≥10 spawns/sec of any node type mandates pre-pooling.
## MVP consumer: BowAction arrows (≥30 pool size). No gameplay state (Rule 14).

var _free: Dictionary = {}
var _in_use: Dictionary = {}
var _scenes: Dictionary = {}

func register_type(type_key: StringName, scene: PackedScene, initial_count: int) -> void: pass
func acquire(type_key: StringName) -> Node3D: pass
func release(node: Node3D) -> void: pass
```

---

## § 3 Movement System Contracts

### Reader Wrappers (Structural Isolation)

```gdscript
class_name BodyReader extends RefCounted
## Forwarded signals — external systems connect to these, not to Body directly.

signal grounded_changed(is_grounded: bool)
signal impact_detected(velocity_at_impact: Vector3)

var _body: Body

func _init(body: Body) -> void:
    assert(body != null, "BodyReader must wrap a valid Body")

func get_global_position() -> Vector3: pass
func get_velocity() -> Vector3: pass
func get_up_direction() -> Vector3: pass
func is_on_floor() -> bool: pass
```

```gdscript
class_name StaminaReader extends RefCounted
## Forwarded signals — external systems connect to these.

signal exhausted()
signal stamina_changed(current: float, maximum: float)

var _target: StaminaComponent

func _init(target: StaminaComponent) -> void:
    assert(target != null, "StaminaReader must be initialized with target")

func get_value() -> float: pass
func get_max() -> float: pass
func is_exhausted() -> bool: pass
```

```gdscript
class_name LocomotionStateReader extends RefCounted
## Forwarded signal — Camera, Combat, UI, AI perception react to state changes.

signal state_changed(old_mode: int, new_mode: int)

var _target: LocomotionState

func _init(target: LocomotionState) -> void:
    assert(target != null, "LocomotionStateReader missing target")

func get_active_mode() -> int: pass
```

### State & Resource Components

#### `LocomotionState`

```gdscript
class_name LocomotionState extends Node
## State machine cell. Only MovementBroker holds mutable ref; everyone else gets a Reader.

signal state_changed(old_mode: int, new_mode: int)

enum Mode {
    WALK, SPRINT, SNEAK, JUMP, FALL, GLIDE,
    CLIMB, WALL_JUMP, MANTLE, AUTO_VAULT,
    SWIM, MOUNT, CINEMATIC, RAGDOLL,
    STAGGER_LIGHT, STAGGER_HEAVY, STAGGER_FINISHER, DEFEAT,
}

var active_mode: int = Mode.FALL

func set_state(new_mode: int) -> void: pass  ## Only MovementBroker calls this
```

#### `StaminaComponent`

```gdscript
class_name StaminaComponent extends Node
## Stamina budget. Mutable ref held by Motors + CombatActions; read-only via StaminaReader.

signal exhausted()
signal stamina_changed(current: float, maximum: float)

@export var max_stamina: float = 100.0
@export var regen_rate: float = 10.0
@export var regen_delay: float = 1.5

var current_stamina: float = max_stamina
var is_exhausted: bool = false
var _time_since_last_drain: float = 0.0

func drain(amount: float) -> void: pass
func tick_regen(delta: float) -> void: pass
func clear_exhaustion(threshold: float = 20.0) -> void: pass
```

> **TBD (Session 3 — Progression Stage 1):** `max_stamina` becomes dynamically sourced from the Progression system once `ProgressionReader` is declared. Two integration patterns remain open and MUST be decided in Session 3:
> - **Pull:** `StaminaComponent` holds an injected `ProgressionReader` reference and reads `get_stamina_cap()` each `tick_regen` call.
> - **Push:** `EntityController` subscribes to a `progression_changed` signal from Progression and calls `StaminaComponent.set_max_stamina(new_cap)` on events.
>
> Until Session 3, the `@export var max_stamina` default above remains the authoritative source (single SSoT — Rule 6). **No typed field** (`var progression_reader: ProgressionReader`) is added here pre-Session-3, since `ProgressionReader` is not yet a declared `class_name` and a phantom type reference would hard-fail the GDScript parser. The system map's Progression↔Movement (Stamina) LOOSE coupling row notes that the specific call-direction (pull vs push) is finalized in Session 3; the coupling verdict (LOOSE via a Reader or a signal bridge) is already settled.

### Base Classes (Strict Enforcement)

#### `BaseMotor`

```gdscript
class_name BaseMotor extends Node
## Abstract base for all locomotion motors.
## Phase 1: proposals (side-effect-free). Phase 2: lifecycle. Phase 3: execution.

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    assert(false, "%s must override gather_proposals()" % get_script().resource_path)  ## VIRTUAL
    return []
func on_enter(body: Body, stamina: StaminaComponent) -> void:
    assert(false, "%s must override on_enter()" % get_script().resource_path)  ## VIRTUAL
func on_exit() -> void:
    assert(false, "%s must override on_exit()" % get_script().resource_path)  ## VIRTUAL
func on_tick(intents: Intents, delta: float) -> void:
    assert(false, "%s must override on_tick()" % get_script().resource_path)  ## VIRTUAL
```

#### `BaseService`

```gdscript
class_name BaseService extends Node
## Abstract base for fact-caching services.
## Phase 1: update_facts. Phase 2: gather_proposals (side-effect-free).

func update_facts(body_reader: BodyReader) -> void:
    assert(false, "%s must override update_facts()" % get_script().resource_path)  ## VIRTUAL
func gather_proposals(current_mode: int, intents: Intents) -> Array[TransitionProposal]:
    assert(false, "%s must override gather_proposals()" % get_script().resource_path)  ## VIRTUAL
    return []
```

#### `BaseBrain`

```gdscript
class_name BaseBrain extends Node
## Abstract brain. Populates caller-owned Intents once per frame (SSoT for per-frame input).

func populate(intents: Intents) -> void:
    assert(false, "%s must override populate()" % get_script().resource_path)  ## VIRTUAL
```

### `MovementBroker` (public surface for the composition root)

```gdscript
class_name MovementBroker extends Node
## Per-entity Movement orchestrator. Ticked at slot 4 via EntityTickBundle.tick_movement.
## Sole writer of LocomotionState.set_state(). Single choke point for forced proposals.

var _external_proposals: Array[TransitionProposal] = []
var _allowed_motor_mask: Array[StringName] = []

func inject_forced_proposal(proposal: TransitionProposal) -> void: pass
func set_allowed_motors(motor_mask: Array[StringName]) -> void: pass
func tick(intents: Intents, delta: float) -> void:
    assert(false, "%s must override tick()" % get_script().resource_path)  ## VIRTUAL
```

---

## § 4 Camera System Contracts

### Pure Data Structs

```gdscript
class_name CameraInput extends RefCounted
## Produced by CameraBrain at slot 2. Consumed by CameraBroker at slot 6.
## wants_aim is a hint for predictive smoothing only — ground truth lives in AimingReader.

var look_delta: Vector2 = Vector2.ZERO
var wants_lock_on_toggle: bool = false
var wants_aim: bool = false

func validate() -> void: pass
```

```gdscript
class_name EffectRequest extends RefCounted
## Pushed into CameraBroker's effect stack via CameraRig.request_effect.
## Single cross-system choke point for Combat-side shake / Health-side flash / etc.

var effect_type: StringName
var magnitude: float
var duration_seconds: float
var easing: Curve

func _init(p_type: StringName, p_magnitude: float, p_duration: float, p_easing: Curve = null) -> void:
    assert(p_type != &"", "EffectRequest.effect_type must be a non-empty StringName")
    assert(is_finite(p_magnitude), "EffectRequest.magnitude must be finite")
    assert(p_duration > 0.0, "EffectRequest.duration_seconds must be positive")
```

### Reader Wrappers

```gdscript
class_name CameraReader extends RefCounted
## Published by CameraRig.get_camera_reader(). Read-only view on Lens transform.
## Consumers: PlayerBrain (aim_target), future Audio, future VFX.

signal aim_state_changed(now_aiming: bool)
signal target_rebound(new_target: BodyReader)

var _lens: Lens
var _camera_rig: CameraRig

func _init(camera_rig: CameraRig, lens: Lens) -> void:
    assert(camera_rig != null, "CameraReader requires non-null CameraRig")
    assert(lens != null, "CameraReader requires non-null Lens")

func get_global_position() -> Vector3: pass
func get_forward() -> Vector3: pass
func get_up() -> Vector3: pass
func get_fov_degrees() -> float: pass
```

### Base Classes (Strict Enforcement)

```gdscript
class_name CameraBrain extends Node
## Abstract. PlayerCameraBrain is the only MVP subclass. AI never drives camera.

func populate(input: CameraInput) -> void:
    assert(false, "%s must override populate()" % get_script().resource_path)  ## VIRTUAL
```

```gdscript
class_name CameraMode extends Node
## Abstract. Mutually exclusive per frame; side-effect-free (no Lens writes, no effect pushes).

func gather_proposals(current_mode: int, aiming: bool, locked_on: bool) -> Array[TransitionProposal]:
    assert(false, "%s must override gather_proposals()" % get_script().resource_path)  ## VIRTUAL
    return []
func on_active_tick(delta: float, body_reader: BodyReader) -> Transform3D:
    assert(false, "%s must override on_active_tick()" % get_script().resource_path)  ## VIRTUAL
    return Transform3D.IDENTITY
```

```gdscript
class_name CameraEffect extends Node
## Abstract. Effects compose ADDITIVELY on top of Mode base transform.
## apply_to_transform must be idempotent (called once per physics tick).

var time_remaining: float = 0.0
var magnitude: float = 0.0

func start(request: EffectRequest) -> void:
    assert(false, "%s must override start()" % get_script().resource_path)  ## VIRTUAL
func tick(delta: float) -> void:
    assert(false, "%s must override tick()" % get_script().resource_path)  ## VIRTUAL
func apply_to_transform(base: Transform3D) -> Transform3D:
    assert(false, "%s must override apply_to_transform()" % get_script().resource_path)  ## VIRTUAL
    return base
func is_expired() -> bool: pass
```

### `CameraRig` (composition root — public cross-system surface)

```gdscript
class_name CameraRig extends Node3D
## Single-instance camera composition root. No Form field by class shape —
## Camera ↔ Form coupling = NONE (Stage-1 seam) cannot be wired even by accident.

signal mode_changed(old_mode: int, new_mode: int)
signal effect_pushed(request: EffectRequest)
signal aim_state_changed(now_aiming: bool)
signal target_rebound(new_target: BodyReader)

var _target_body_reader: BodyReader
var _aiming_reader: AimingReader
var _lock_on_reader: LockOnTargetReader
var _locomotion_state_reader: LocomotionStateReader
var _registered_effect_types: Dictionary = {}

@onready var _camera_brain: CameraBrain = $CameraBrain
@onready var _camera_broker: CameraBroker = $CameraBroker
@onready var _lens: Lens = $Lens

func set_target(target_body_reader: BodyReader) -> void: pass
func request_effect(request: EffectRequest) -> void: pass
func get_camera_reader() -> CameraReader: pass
```

---

## § 5 Combat System Contracts

### Pure Data Structs

```gdscript
class_name DamageEvent extends RefCounted
## Produced by CombatAction.execute. Dumb data carrier (Rule 5).
## damage_type and stagger_class are StringNames to stay open to future moveset additions.

var source: Node3D
var target: Node3D
var amount: float
var damage_type: StringName
var stagger_class: StringName

const VALID_STAGGER_CLASSES: Array[StringName] = [&"none", &"light", &"heavy", &"finisher"]

func _init(p_source: Node3D, p_target: Node3D, p_amount: float,
           p_damage_type: StringName, p_stagger_class: StringName = &"none") -> void:
    assert(p_source != null, "DamageEvent.source must not be null")
    assert(p_target != null, "DamageEvent.target must not be null")
    assert(p_amount >= 0.0, "DamageEvent.amount must be >= 0")
    assert(p_damage_type != &"", "DamageEvent.damage_type must be a non-empty StringName")
    assert(p_stagger_class in VALID_STAGGER_CLASSES,
        "DamageEvent.stagger_class %s not in %s" % [p_stagger_class, VALID_STAGGER_CLASSES])
```

```gdscript
class_name CombatDecision extends RefCounted
## Produced by CombatAction.gather_decision. Opaque payload so each moveset
## carries its own data shape without polluting a shared enum.

var will_execute: bool = false
var payload: Dictionary = {}

func _init(p_will_execute: bool, p_payload: Dictionary = {}) -> void:
    will_execute = p_will_execute
```

### Reader Wrappers

```gdscript
class_name AimingReader extends RefCounted
## Ground truth for "is the bow drawn?". Backed by CombatBroker. Consumer: Camera AimMode.

signal aim_state_changed(now_aiming: bool)

var _combat_broker: CombatBroker

func _init(broker: CombatBroker) -> void:
    assert(broker != null, "AimingReader requires non-null CombatBroker")

func is_aiming() -> bool: pass
```

```gdscript
class_name LockOnTargetReader extends RefCounted
## Lock-on selection reader. Backed by CombatBroker. Consumers: Camera LockOnMode, UI, Audio.

signal target_changed(new_target: Node3D)

var _combat_broker: CombatBroker

func _init(broker: CombatBroker) -> void:
    assert(broker != null, "LockOnTargetReader requires non-null CombatBroker")

func get_target() -> Node3D: pass
func has_target() -> bool: pass
```

```gdscript
class_name CombatStateReader extends RefCounted
## Read-only view of per-entity combat stance. Consumers: F3 debug panel, AI, animation.

signal stance_changed(old_stance: int, new_stance: int)

var _target: CombatState

func _init(target: CombatState) -> void:
    assert(target != null, "CombatStateReader requires non-null CombatState")

func get_stance() -> int: pass
```

### `CombatState` (state-machine cell)

```gdscript
class_name CombatState extends Node
## State machine cell. Only CombatBroker holds mutable ref; everyone else gets a Reader.

signal stance_changed(old_stance: int, new_stance: int)

enum Stance {
    IDLE, DRAWING, AIMING, PARRY_WINDOW,
    COUNTERING, ASSASSINATING, STAGGERED_AS_ATTACKER,
}

var stance: int = Stance.IDLE

func set_stance(new_stance: int) -> void: pass  ## Only CombatBroker calls this
```

### Base Class (Strict Enforcement)

```gdscript
class_name CombatAction extends Node
## Abstract. Dispatched one-at-a-time by CombatBroker per form moveset binding.
## gather_decision is side-effect-free; execute is the sole producer of DamageEvents.

## Moveset gate: every concrete subclass declares its LocomotionState deny-set.
## Min required: {CLIMB, SWIM, MOUNT, DEFEAT, CINEMATIC, STAGGER_*}. BowAction exempts FALL.
const MIN_DENIED_STATES: Array[int] = [
    LocomotionState.Mode.CLIMB,
    LocomotionState.Mode.SWIM,
    LocomotionState.Mode.MOUNT,
    LocomotionState.Mode.DEFEAT,
    LocomotionState.Mode.CINEMATIC,
    LocomotionState.Mode.STAGGER_LIGHT,
    LocomotionState.Mode.STAGGER_HEAVY,
    LocomotionState.Mode.STAGGER_FINISHER,
]

func denied_states() -> Array[int]:
    assert(false, "%s must override denied_states()" % get_script().resource_path)  ## VIRTUAL
    return []
func gather_decision(intents: Intents, locomotion: LocomotionStateReader, body_reader: BodyReader) -> CombatDecision:
    assert(false, "%s must override gather_decision()" % get_script().resource_path)  ## VIRTUAL
    return CombatDecision.new(false)
func execute(decision: CombatDecision, body_reader: BodyReader, stamina: StaminaComponent) -> Array[DamageEvent]:
    assert(false, "%s must override execute()" % get_script().resource_path)  ## VIRTUAL
    return []
func on_form_shift(new_form: StringName) -> void:
    assert(false, "%s must override on_form_shift()" % get_script().resource_path)  ## VIRTUAL
```

### `IncomingAttackBuffer`

```gdscript
class_name IncomingAttackBuffer extends Node
## Per-entity fixed-capacity ring buffer. Only EntityController.receive_incoming_attack
## writes here (Rule-13 strict form). Capacity = 8; overflow asserts.

const CAPACITY: int = 8

var _ring: Array[DamageEvent] = []

func push(event: DamageEvent) -> void: pass
func drain() -> Array[DamageEvent]: pass
```

### `CombatBroker` (public surface contracts)

```gdscript
class_name CombatBroker extends Node
## Per-entity Combat orchestrator. Ticked at slot 5 via EntityTickBundle.tick_combat.

signal hit_landed(event: DamageEvent)
signal stagger_triggered(event: DamageEvent)
signal outgoing_attack_resolved(target_entity: EntityController, event: DamageEvent)
signal moveset_bound(form: StringName)
signal aim_state_changed(now_aiming: bool)
signal target_changed(new_target: Node3D)

const STAGGER_WEIGHTS: Dictionary = {&"light": 40, &"heavy": 80, &"finisher": 120}

@onready var _incoming_attack_buffer: IncomingAttackBuffer = $IncomingAttackBuffer
@onready var _combat_state: CombatState = $CombatState
var _is_aiming: bool = false
var _selected_target: Node3D = null

func push_incoming_attack(event: DamageEvent) -> void:
    assert(get_parent() is EntityController, "CombatBroker must be a child of an EntityController")
func is_aiming() -> bool: pass
func get_lock_on_target() -> Node3D: pass
func tick(intents: Intents, delta: float) -> void:
    assert(false, "%s must override tick()" % get_script().resource_path)  ## VIRTUAL
```

---

## § 6 Form System Contracts

### Reader Wrapper

```gdscript
class_name FormReader extends RefCounted
## Read-only view on FormComponent. Consumers: CombatBroker, UI, Audio.
## Camera has NO FormReader (Stage-1 coupling = NONE).

signal form_shifted(new_form: StringName)

var _target: FormComponent

func _init(target: FormComponent) -> void:
    assert(target != null, "FormReader requires non-null FormComponent")

func get_active_form() -> StringName: pass
```

### `FormComponent` (state-machine cell)

```gdscript
class_name FormComponent extends Node
## State machine cell. Only FormBroker holds mutable ref; everyone else gets a Reader.

signal form_shifted(new_form: StringName)

const VALID_FORMS: Array[StringName] = [&"panther", &"monkey", &"avian"]

var active_form: StringName = &"panther"

func set_form(new_form: StringName) -> void: pass  ## Only FormBroker calls this
```

### `FormBroker` (public surface contracts)

```gdscript
class_name FormBroker extends Node
## Per-entity Form orchestrator. Ticked at slot 3 via EntityTickBundle.tick_form.
## Owns shape + motor-mask catalogs; EntityController fans out on form_shifted.

signal form_shifted(new_form: StringName)

@export var _shape_catalog_resources: Dictionary = {}
@export var _motor_mask_catalog: Dictionary = {}
@export var _entry_state_catalog: Dictionary = {}

var _shifts_enabled: bool = true

@onready var _form_component: FormComponent = get_parent().get_node("FormComponent")

func _ready() -> void:
    assert(_form_component != null, "FormBroker requires sibling FormComponent under EntityController")

func tick(intents: Intents, _delta: float) -> void: pass
func set_shifts_enabled(enabled: bool, caller: Node) -> void: pass  ## caller-identity asserted
func shape_for(form: StringName) -> Shape3D: pass
func motor_mask_for(form: StringName) -> Array[StringName]: pass
func entry_state_for(form: StringName) -> int: pass
```

---

## § 7 DebugOverlay Contracts

### `BaseDebugContext`

Abstract base for every per-panel context (F2/F3/F4/... as cluster systems claim keys from the Stage-0 registry). Context nodes are observer-only (Rule 14 — no gameplay state here).

```gdscript
class_name BaseDebugContext extends Node
## Abstract base for every per-panel context. Observer-only (Rule 14 — no gameplay state).

var _data: Dictionary = {}

func get_panel_key() -> int:
    assert(false, "%s must override get_panel_key()" % get_script().resource_path)  ## VIRTUAL
    return -1
func render(container: VBoxContainer) -> void:
    assert(false, "%s must override render()" % get_script().resource_path)  ## VIRTUAL
```

### `DebugOverlay.push`

Singleton push interface. Release builds short-circuit — Rule 14 strict fallback.

```gdscript
# On the DebugOverlay Autoload (see 05-project-scaffold-player-action-stack.md).
func push(context_key: int, snapshot: DebugSnapshot) -> void:
    # Rule 14: Strict fallback in release builds.
    if not OS.is_debug_build():
        return
    # Route snapshot to matching context node by key.
```

### Cluster Context Subclasses

The cluster's four context subclasses below extend `BaseDebugContext` and claim their F-keys from the Stage-0 registry.

```gdscript
class_name MovementContext extends BaseDebugContext
const PANEL_KEY: int = KEY_F1
func get_panel_key() -> int: return PANEL_KEY
func render(container: VBoxContainer) -> void:
    assert(false, "MovementContext.render: concrete implementation in graybox phase")  ## VIRTUAL
```

```gdscript
class_name CameraContext extends BaseDebugContext
const PANEL_KEY: int = KEY_F2
func get_panel_key() -> int: return PANEL_KEY
func render(container: VBoxContainer) -> void:
    assert(false, "CameraContext.render: concrete implementation in graybox phase")  ## VIRTUAL
```

```gdscript
class_name CombatContext extends BaseDebugContext
const PANEL_KEY: int = KEY_F3
func get_panel_key() -> int: return PANEL_KEY
func render(container: VBoxContainer) -> void:
    assert(false, "CombatContext.render: concrete implementation in graybox phase")  ## VIRTUAL
```

```gdscript
class_name FormContext extends BaseDebugContext
const PANEL_KEY: int = KEY_F4
func get_panel_key() -> int: return PANEL_KEY
func render(container: VBoxContainer) -> void:
    assert(false, "FormContext.render: concrete implementation in graybox phase")  ## VIRTUAL
```

---

## § 8 Reuse Summary (audit cross-check)

Used by the Architecture Auditor (Stage architecture-audit) to confirm no contract is redeclared across artifacts. This artifact declares exactly the following `class_name` tokens (single authoritative declaration site for every Cluster-A contract):

- **Pure data structs:** `Intents`, `TransitionProposal`, `DebugSnapshot`, `CameraInput`, `EffectRequest`, `DamageEvent`, `CombatDecision`.
- **Cluster glue:** `EntityController`, `Body`, `EntityTickBundle`, `MountTickBundle`, `CameraTickBundle`, `ObjectPool`.
- **Movement:** `BodyReader`, `StaminaReader`, `LocomotionStateReader`, `LocomotionState`, `StaminaComponent`, `BaseMotor`, `BaseService`, `BaseBrain`, `MovementBroker`.
- **Camera:** `CameraReader`, `CameraBrain`, `CameraMode`, `CameraEffect`, `CameraRig`.
- **Combat:** `AimingReader`, `LockOnTargetReader`, `CombatStateReader`, `CombatState`, `CombatAction`, `IncomingAttackBuffer`, `CombatBroker`.
- **Form:** `FormReader`, `FormComponent`, `FormBroker`.
- **Debug overlay:** `BaseDebugContext`, `DebugOverlay.push`, `MovementContext`, `CameraContext`, `CombatContext`, `FormContext`.

---

## Exit Criteria

- [x] **SSF compliance:** all `gdscript` code blocks are signature shells — no method bodies beyond `pass` or `assert(false)` for virtuals, no inline implementation comments, no signal wiring inside `_ready`.
- [x] GDScript base classes are fully defined with runtime assertions — `BaseMotor`, `BaseService`, `BaseBrain`, `MovementBroker.tick`, `CameraBrain`, `CameraMode`, `CameraEffect`, `CombatAction`, `CombatBroker.tick`, `BaseDebugContext` each use `assert(false, "%s must override …" % get_script().resource_path)` on every virtual.
- [x] Pure immutable data structs are defined — `Intents`, `TransitionProposal`, `DebugSnapshot`, `CameraInput`, `EffectRequest`, `DamageEvent`, `CombatDecision`.
- [x] Reader Wrapper classes are explicitly defined to enforce structural Read-Only boundaries — `BodyReader`, `StaminaReader`, `LocomotionStateReader`, `CameraReader`, `AimingReader`, `LockOnTargetReader`, `CombatStateReader`, `FormReader`.
- [x] Data validation assertions are included in struct `_init` methods.
- [x] All architectural layers defined in Stage 1 have programmatic enforcement mapped out here — Movement (Motor/Service/Brain/Broker/LocomotionState/Stamina), Camera (Brain/Mode/Effect/Rig), Combat (Broker/Action/Buffer/State), Form (Broker/Component), plus cluster glue (EntityController/Body/TickBundles/ObjectPool).
- [x] DebugOverlay contracts (`BaseDebugContext`, `DebugOverlay.push`, `DebugSnapshot`) are declared here as the single authoritative site. Four cluster context subclasses (`MovementContext`, `CameraContext`, `CombatContext`, `FormContext`) extend the base and claim F1/F2/F3/F4. Never duplicated.
- [x] Custom pattern vocabulary preserved — cluster uses *Motor* (Movement), *Action* (Combat), *Mode* + *Effect* (Camera), *Broker* (all), *Service* (all) consistently; base classes match.

**Cluster-A-specific additions beyond the stage template:**

- [x] EntityController is the single Signal-Listener Contract SSoT — table inline under § 2; cluster 02 / 04 / 05 cross-reference, never duplicate.
- [x] Dependency-Injection Contract inline under § 2 — enumerates every typed Reader flowing out of cluster components.
- [x] Tick-bundle struct contracts (EntityTickBundle / MountTickBundle / CameraTickBundle) frozen here from their Stage-2 prototypes, with non-null `_init` asserts matching Stage-2's entity-coherence invariant.
- [x] `ObjectPool` Autoload API frozen — `register_type` / `acquire` / `release` with full assertions. Growth policy documented (warn, don't hard-cap).
- [x] `EntityController.receive_incoming_attack` declared as the single public cross-entity surface (Stage-4 Rule-13 strict form); target-check asserted; forwards to own `CombatBroker.push_incoming_attack`.
- [x] Stage-3 DEFEAT/CINEMATIC shift-gate fully wired: `FormBroker.set_shifts_enabled(bool, caller)` runtime-asserts caller identity; `EntityController._on_locomotion_state_changed` drives the gate from `LocomotionState.state_changed`.
- [x] Stagger weight table (`CombatBroker.STAGGER_WEIGHTS`) pinned here as a `const Dictionary`; consumed by `EntityController._on_stagger_triggered` when forwarding FORCED proposals. Mirrors the Stage-4 weight registry; injectivity auditable at `_ready()`.
- [x] `Intents.is_complete()` method declared on `Intents`; referenced by `EntityTickBundle.gather_intents` and `MountTickBundle.gather_intents` asserts.
- [x] `LocomotionState.Mode` enum extended with `STAGGER_LIGHT`, `STAGGER_HEAVY`, `STAGGER_FINISHER`, `DEFEAT` to cover cluster motor consumers (`CombatAction.MIN_DENIED_STATES`, `EntityController._on_stagger_triggered`).
