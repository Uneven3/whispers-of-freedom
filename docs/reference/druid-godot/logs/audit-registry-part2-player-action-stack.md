# Architecture Audit — Decision Registry Part 2
# Source: artifacts 04, 05, 06 — player-action-stack
# Used by: Session 3 (checks A–K)

---

## FROM STAGE 04 — Systems and Components

### 04-A. Complete Component Inventory

**Movement system:**
- EntityController (Node3D) — composition root [§0]
- Brain (abstract Node) — base [§1]
- PlayerBrain (Node) [§1]
- AIBrain (Node) [§1]
- MovementBroker (Node) [§2]
- WalkMotor, SprintMotor, SneakMotor, JumpMotor, FallMotor, GlideMotor, ClimbMotor,
  WallJumpMotor, MantleMotor, AutoVaultMotor, SwimMotor, MountMotor,
  CinematicMotor, DeathMotor, StaggerMotor, RagdollMotor (Nodes) [§3]
- GroundService (Node3D + ShapeCast3D), LedgeService (Node3D + ShapeCast3D),
  WaterService (Node3D + Area3D), MountService (Node3D + Area3D) [§4]
- Body (Node wrapper), LocomotionState (Node), StaminaComponent (Node) [§5]
- CombatContextStub (Node) [§6] — **entity-level sibling implementing AimingReader + LockOnTargetReader**

**Camera system:**
- CameraRig (Node3D) — composition root [§0]
- CameraBrain (abstract Node), PlayerCameraBrain (Node) [§1]
- CameraBroker (Node) [§2]
- FollowMode, AimMode, LockOnMode (Nodes — mutually exclusive) [§3]
- DipEffect, ShakeEffect, FOVZoomEffect, FollowEaseInEffect (Nodes — stackable) [§3]
- OcclusionService (Node3D + RayCast3D) [§4]
- CameraReader (lightweight object, NOT a Node) [§4]
- Lens (Node3D) [§4]

**Combat system:**
- CombatBroker (Node) [§2]
- TakedownAction (Node — Panther), ParryAction (Node — Monkey),
  CounterAction (Node — Monkey), BowAction (Node — Avian) [§3]
- HitDetectionService (Node), LockOnService (Node), IncomingAttackBuffer (Node) [§4]
- CombatState (Node) [§5]

**Form system:**
- FormBroker (Node) [§2]
- FormComponent (Node) [§3]
- No Form-specific Services in MVP [§4]

**Autoloads:**
- GameOrchestrator (Autoload, PROCESS_MODE_ALWAYS)
- DebugOverlay (Autoload, PROCESS_MODE_ALWAYS, debug-build-only)
  - MovementContext (F1), CameraContext (F2), CombatContext (F3), FormContext (F4)
- ObjectPool (Autoload, PROCESS_MODE_PAUSABLE) — **newly declared in Stage 4**

**Tick Bundles:**
- EntityTickBundle (4 fields: brain, form_broker, movement_broker, combat_broker)
- MountTickBundle (2 fields: brain, movement_broker) — **Stage 4 resolution for mounts**
- CameraTickBundle (2 fields: brain, broker)

### 04-B. SSoT Ownership Map (from Stage 04)

| State | Mutable Owner | Read-Only Consumers |
|-------|--------------|---------------------|
| LocomotionState | MovementBroker (set_state — sole) | Motors, Camera Modes, CombatBroker (gate), EntityController (shift-gate handler) via LocomotionStateReader |
| StaminaComponent | Motors (SprintMotor, ClimbMotor, GlideMotor), CombatActions (CounterAction, future DodgeAction, BowAction) | UI, AI, Combat-balance via StaminaReader |
| Body | Currently active Motor via apply_motion; EntityController for swap_collision_shape | Camera, Combat, Health, Interaction via BodyReader |
| Intents | Brain.populate at slot 1 | FormBroker.tick, MovementBroker.tick, CombatBroker.tick (slots 3-5) |
| FormComponent | FormBroker via set_form | CombatBroker (moveset binding), Audio, UI, Progression via FormReader; Camera has NO access |
| FormBroker._shifts_enabled | EntityController via set_shifts_enabled (sole; runtime-asserted) | FormBroker.tick internal only |
| MovementBroker._allowed_motors | EntityController via set_allowed_motors (sole; runtime-asserted) | MovementBroker.tick internal |
| CombatState | Active CombatAction via CombatBroker | UI (F3), AI perception via CombatStateReader |
| LockOnTarget (_selected_target) | CombatBroker (via LockOnService) | Camera LockOnMode, UI, Audio via LockOnTargetReader |
| Aiming state (_is_aiming) | BowAction via CombatBroker; MVP stub hard-codes false | Camera AimMode via AimingReader |
| Camera3D.global_transform | Lens._process (interpolation), CameraBroker.tick writes via set_target_transform | CameraReader |
| FormBroker catalogs | Populated at _ready() from @export; no runtime mutation | FormBroker.tick internal + EntityController fan-out |
| _external_proposals | MovementBroker.inject_forced_proposal (EC-only, caller-identity-asserted) | MovementBroker.tick internal drain; must be serialized for rollback |

### 04-C. Performance Thresholds and Universal Rules (LAW)

- `_physics_process` disabled by default (GameOrchestrator walks bundles and calls set_physics_process(false))
  - NOTE: `_process` is NOT touched by the walk — Lens._process is self-managed (PROCESS_MODE_PAUSABLE)
- Signal-only cross-node communication; cross-entity via EntityController-to-EntityController edge only
- No group iteration in hot paths (typed arrays, cache at _ready())
- Full static typing required
- No magic numbers (all @export var or const)
- Object pooling threshold: ≥ 10 spawns/sec requires ObjectPool; arrow pool ≥ 30 mandatory
- MultiMeshInstance3D threshold: ≥ 20 identical static meshes
- Jolt physics threading: ENABLED
- Hard cap: 50 active entities in EntityTickBundle
- Per-entity physics-tick budget: ≤ 0.15 ms across slots 1/3/4/5
- Camera slot 6 budget: ≤ 0.5 ms/physics-tick
- Total cluster-A physics budget: ≤ 8.0 ms of the 16.67 ms window
- Render-tick budget: ≤ 0.05 ms (Lens._process only)
- Weight registry must be STRICTLY INJECTIVE; runtime assert on duplicate

### 04-D. FORCED-Proposal Weight Registry (Stage 4 deliverable — 10 entries, all distinct)

| Weight | Source |
|--------|--------|
| 10 | GroundService ground-reattach |
| 20 | WaterService enter-swim |
| 25 | WaterService exit-swim |
| 30 | LedgeService ledge-snap |
| 40 | Combat stagger &"light" |
| 80 | Combat stagger &"heavy" |
| 100 | FormShiftProposal |
| 120 | Combat stagger &"finisher" |
| 150 | Interaction cinematic |
| 200 | Health defeat |

Total: 10 entries; all distinct; injectivity required.

Camera-internal weights (separate registry on CameraBroker):
- FollowMode: DEFAULT, weight 0
- LockOnMode: PLAYER_REQUESTED, weight 50
- AimMode: PLAYER_REQUESTED, weight 60

---

## FROM STAGE 05 — Project Scaffold

### 05-A. Physical Tree / Parent-Child Relationships

**Diagram A — Entity (EntityTickBundle participant):**

```
Entity (Node3D) [EntityController.gd]
├── Body (Node)
│   └── PhysicsProxy (CharacterBody3D)
│       └── CollisionShape3D
├── VisualsPivot (Node3D)
│   ├── Mesh (Node3D)
│   └── AnimationTree
├── Brain (Node) [PlayerBrain | AIBrain]
├── StaminaComponent (Node)
├── FormComponent (Node)
├── FormBroker (Node)
├── MovementBroker (Node)
│   └── LocomotionState (Node)
├── CombatBroker (Node)
│   ├── CombatState (Node)
│   └── IncomingAttackBuffer (Node)
├── Services (Node)
│   ├── Movement (Node)
│   │   ├── GroundService (Node3D) + GroundProbe (ShapeCast3D)
│   │   ├── LedgeService (Node3D) + WallProbe + MantleClearanceProbe (ShapeCast3D)
│   │   ├── WaterService (Node3D) + SurfaceDetector (Area3D)
│   │   └── MountService (Node3D) + MountDetector (Area3D)
│   └── Combat (Node)
│       ├── HitDetectionService (Node)
│       └── LockOnService (Node)
├── Motors (Node) [MovementBroker caches at _ready()]
│   ├── WalkMotor, SprintMotor, SneakMotor, JumpMotor, FallMotor, GlideMotor,
│   │   ClimbMotor, WallJumpMotor, MantleMotor, AutoVaultMotor, SwimMotor,
│   │   MountMotor, CinematicMotor, DeathMotor, StaggerMotor, RagdollMotor
└── CombatActions (Node) [CombatBroker caches at _ready()]
    ├── TakedownAction, ParryAction, CounterAction, BowAction
```

NOTE: **No CombatContextStub** in the scaffold — Stage 05 note (line 7) says:
"No CombatContextStub. The cluster ships real CombatBroker + CombatState + IncomingAttackBuffer..."

**Diagram B — Mount Entity (MountTickBundle participant):**
- MountEntityController.gd
- Body + PhysicsProxy + CollisionShape3D
- VisualsPivot + Mesh
- Brain (AIBrain)
- MovementBroker + LocomotionState
- Services: GroundService + WaterService
- Motors: WalkMotor, GallopMotor, JumpMotor, FallMotor, SwimMotor, MountedRestMotor

**Diagram C — CameraRig (CameraTickBundle participant):**
- CameraRig.gd
- CameraBrain (PlayerCameraBrain)
- CameraBroker
- Modes: FollowMode, AimMode, LockOnMode
- Effects: DipEffect, ShakeEffect, FOVZoomEffect, FollowEaseInEffect
- Services: OcclusionService + OcclusionRay (RayCast3D)
- Lens (Node3D, PROCESS_MODE_PAUSABLE, sole _process in cluster)
  └── SpringArm3D
      └── Camera3D (only Camera3D in project)

### 05-B. Special Placements (Autoloads)

```
GameOrchestrator — PROCESS_MODE_ALWAYS; _physics_process sole owner
  Registration API:
    register_entity_bundle(bundle: EntityTickBundle)
    register_mount_bundle(bundle: MountTickBundle)
    register_camera_bundle(bundle: CameraTickBundle)
    deregister_entity_bundle(bundle: EntityTickBundle)
    deregister_mount_bundle(bundle: MountTickBundle)

DebugOverlay — PROCESS_MODE_ALWAYS; debug-build-only
  push(context_key: int, snapshot: DebugSnapshot) -> void
  Children: MovementContext(F1), CameraContext(F2), CombatContext(F3), FormContext(F4)

ObjectPool — PROCESS_MODE_PAUSABLE
  register_type(type_key: StringName, scene: PackedScene, initial_count: int)
  acquire(type_key: StringName) -> Node3D
  release(node: Node3D) -> void
  MVP registered pool: &"arrow" (≥30)
```

### 05-C. Transform Sync Contract

Body.apply_motion post-condition (from Stage 05 § Entity-Level Transform Sync Contract):
1. _proxy.velocity = velocity
2. _proxy.move_and_slide()
3. root.global_transform = _proxy.global_transform
4. _proxy.transform = Transform3D.IDENTITY
5. VisualsPivot inherits Entity root via scene graph

---

## FROM STAGE 06 — Interfaces and Contracts

### 06-A. Complete Data Struct Inventory

| Class | Key fields |
|-------|-----------|
| Intents | move_dir, wants_jump, wants_sprint, wants_sneak, wants_glide, wants_climb_release, wants_mount, wants_form_shift, wants_attack, wants_parry, wants_dodge, wants_archery_aim, wants_archery_release, wants_assassinate, aim_target; + has_aim_target(), validate(), is_complete() |
| TransitionProposal | target_state:int, category:Priority enum {DEFAULT, PLAYER_REQUESTED, OPPORTUNISTIC, FORCED}, override_weight:int |
| DebugSnapshot | timestamp:float, source_node_path:NodePath, data:Dictionary |
| CameraInput | look_delta:Vector2, wants_lock_on_toggle:bool, wants_aim:bool; + validate() |
| EffectRequest | effect_type:StringName, magnitude:float, duration_seconds:float, easing:Curve; _init validates non-empty type, finite magnitude, positive duration |
| DamageEvent | source:Node3D, target:Node3D, amount:float, damage_type:StringName, stagger_class:StringName; VALID_STAGGER_CLASSES = [&"none",&"light",&"heavy",&"finisher"]; _init asserts all |
| CombatDecision | will_execute:bool, payload:Dictionary |

### 06-B. Base Classes / Interfaces and Method Signatures

| Class | Key methods |
|-------|------------|
| BaseBrain (extends Node) | populate(intents: Intents) → void [virtual trap] |
| BaseMotor (extends Node) | gather_proposals(current_mode:int, intents:Intents, services:Array) → Array[TransitionProposal]; on_enter(body:Body, stamina:StaminaComponent) → void; on_exit() → void; on_tick(intents:Intents, delta:float) → void [all virtual traps] |
| BaseService (extends Node) | update_facts(body_reader:BodyReader) → void; gather_proposals(current_mode:int, intents:Intents) → Array[TransitionProposal] [virtual traps] |
| MovementBroker (extends Node) | inject_forced_proposal(proposal:TransitionProposal) → void; set_allowed_motors(mask:Array[StringName]) → void; tick(intents:Intents, delta:float) → void [virtual]; _external_proposals:Array[TransitionProposal]; _allowed_motor_mask:Array[StringName] |
| CameraBrain (extends Node) | populate(input:CameraInput) → void [virtual trap] |
| CameraMode (extends Node) | gather_proposals(current_mode:int, aiming:bool, locked_on:bool) → Array[TransitionProposal]; on_active_tick(delta:float, body_reader:BodyReader) → Transform3D [virtual traps] |
| CameraEffect (extends Node) | time_remaining:float, magnitude:float; start(request:EffectRequest)→void; tick(delta:float)→void; apply_to_transform(base:Transform3D)→Transform3D; is_expired()→bool [virtual traps except is_expired] |
| CombatAction (extends Node) | MIN_DENIED_STATES (const Array[int]); denied_states()→Array[int]; gather_decision(intents, locomotion, body_reader)→CombatDecision; execute(decision, body_reader, stamina)→Array[DamageEvent]; on_form_shift(new_form)→void [virtual traps] |
| BaseDebugContext (extends Node) | get_panel_key()→int; render(container:VBoxContainer)→void [virtual traps] |

### 06-C. Reader/Wrapper Classes

| Class | Backing | Getters | Signals |
|-------|---------|---------|---------|
| BodyReader (extends RefCounted) | Body | get_global_position, get_velocity, get_up_direction, is_on_floor | grounded_changed(bool), impact_detected(Vector3) forwarded |
| StaminaReader (extends RefCounted) | StaminaComponent | get_value, get_max, is_exhausted | exhausted, stamina_changed forwarded |
| LocomotionStateReader (extends RefCounted) | LocomotionState | get_active_mode()→int | state_changed(old,new) forwarded |
| CameraReader (extends RefCounted) | Lens (via CameraRig) | get_global_position, get_forward, get_up, get_fov_degrees | aim_state_changed, target_rebound forwarded from CameraRig |
| AimingReader (extends RefCounted) | CombatBroker._is_aiming | is_aiming()→bool | aim_state_changed forwarded |
| LockOnTargetReader (extends RefCounted) | CombatBroker._selected_target | get_target()→Node3D, has_target()→bool | target_changed forwarded |
| CombatStateReader (extends RefCounted) | CombatState | get_stance()→int | stance_changed(old,new) forwarded |
| FormReader (extends RefCounted) | FormComponent | get_active_form()→StringName | form_shifted forwarded |

### 06-D. Runtime Enforcement Contracts (asserts stated as architectural contracts)

1. BaseBrain.populate: virtual trap assert
2. BaseMotor.*: virtual trap asserts on all 4 methods
3. BaseService.*: virtual trap asserts on both methods
4. MovementBroker.inject_forced_proposal: asserts category == FORCED
5. Body.apply_motion: Entity-Level Transform Sync post-condition assert (_proxy.transform.origin == Vector3.ZERO)
6. Body.swap_collision_shape: caller-identity assert (caller == get_parent())
7. Body._ready: asserts _proxy != null, _collision_shape != null
8. EntityController._ready: asserts all 6 refs non-null after wire_components(); forward_forced_proposal asserts FORCED only
9. EntityController.receive_incoming_attack: asserts event != null AND event.target == self
10. EntityController.forward_collision_shape: asserts new_shape != null
11. FormBroker.set_shifts_enabled: caller-identity assert (caller == get_parent())
12. FormBroker._ready: asserts shape catalog non-null per form, motor mask non-empty per form, entry state present per form
13. FormBroker.tick: assert requested in VALID_FORMS
14. FormComponent.set_form: assert new_form in VALID_FORMS
15. CombatAction.gather_decision: assert NOT (locomotion.get_active_mode() in denied_states())
16. DamageEvent._init: asserts source/target != null, amount >= 0, damage_type != &"", stagger_class in VALID_STAGGER_CLASSES
17. CombatBroker.push_incoming_attack: assert get_parent() is EntityController
18. IncomingAttackBuffer.push: assert event != null; assert size < CAPACITY (8)
19. CameraRig.request_effect: assert request != null; assert effect_type in _registered_effect_types
20. CameraRig.set_target: assert target_body_reader != null
21. EntityTickBundle._init: assert all 4 refs non-null
22. MountTickBundle._init: assert brain + movement != null
23. CameraTickBundle._init: assert brain + broker != null
24. ObjectPool: register_type asserts not already registered, scene != null, initial_count > 0; acquire asserts type registered; release asserts node was acquired
25. EffectRequest._init: assert type != &"", magnitude finite, duration > 0
26. LocomotionState.set_state: assert valid enum range
27. CombatState.set_stance: assert valid enum range
28. StaminaComponent.drain: assert amount >= 0
29. Intents.validate(): asserts move_dir finite + length <= 1.01, sprint/sneak mutually exclusive, aim_target sentinel-or-finite
30. EntityController._on_stagger_triggered: assert stagger_class in {light, heavy, finisher}
31. CombatBroker.STAGGER_WEIGHTS const Dictionary: {&"light": 40, &"heavy": 80, &"finisher": 120}

### 06-E. Stagger Weight Table in Stage 06

CombatBroker.STAGGER_WEIGHTS (const Dictionary):
- &"light": 40
- &"heavy": 80
- &"finisher": 120

(Only 3 entries — does NOT include ground-reattach, water, ledge, form-shift, cinematic, defeat weights from Stage 04 — those are in MovementBroker's separate registry)

### 06-F. Notable Stage 06 Structural Observations

1. **CombatContextStub ABSENT** in Stage 06 class list entirely — Stage 05 note explains: cluster ships real CombatBroker. AimingReader and LockOnTargetReader backed directly by CombatBroker.
2. **MountTickBundle present** in Stage 06 (§2) — matches Stage 04 resolution.
3. **GallopMotor** appears in Diagram B (Stage 05 Mount scaffold) but is NOT in Stage 04 Motor inventory (Stage 04 only lists entity Motors, not mount-specific Motors).
4. **MovementContext** debug panel not declared in Stage 06 cluster context subclasses section (§7 only declares CameraContext, CombatContext, FormContext — F2/F3/F4). MovementContext (F1) is referenced in Stage 04 and Stage 05 Autoloads but has no class stub in Stage 06.
5. **Lens** class: not declared as a class_name in Stage 06 § 8 Reuse Summary — CameraReader._init takes a Lens parameter, but Lens is not in the declared class_name list.
6. **LocomotionState.Mode enum** — Stage 06 declares: WALK, SPRINT, SNEAK, JUMP, FALL, GLIDE, CLIMB, WALL_JUMP, MANTLE, AUTO_VAULT, SWIM, MOUNT, CINEMATIC, RAGDOLL, STAGGER_LIGHT, STAGGER_HEAVY, STAGGER_FINISHER, DEFEAT. That is 18 values.
7. **GameOrchestrator.deregister_mount_bundle** appears in Stage 05 Registration API but Stage 05 does NOT list deregister_camera_bundle — only deregister_entity_bundle and deregister_mount_bundle.

---

## CROSS-REGISTRY CONSISTENCY NOTES (for Session 3 checks)

### Stagger weights (Stage 01 vs Stage 03 vs Stage 04 vs Stage 06):
- Stage 01 declared: heavy=80, light=40 (from Trace examples)
- Stage 03 confirmed: heavy=80, light=40; finisher weight not stated in Stage 03 explicitly
- Stage 04 registry: light=40, heavy=80, finisher=120 ✓
- Stage 06 CombatBroker.STAGGER_WEIGHTS: light=40, heavy=80, finisher=120 ✓
- Stage 01/03 did not explicitly give finisher weight — Stage 04 sets it at 120 ✓

### CombatContextStub (Stage 01 vs Stage 04 vs Stage 05 vs Stage 06):
- Stage 01 § entity composition: declares CombatContextStub as an entity-level sibling
- Stage 04 §6: CombatContextStub present as a Node in "Cross-System Stubs (MVP bridges)"
- Stage 05: explicitly notes "No CombatContextStub appears anywhere"
- Stage 06: no CombatContextStub class declared

### TickSlot ordering (Stage 01 vs Stage 02 vs Stage 05):
- Stage 01 canonical tick order: 1=BRAIN, 2=CAMERA_BRAIN, 3=FORM, 4=MOVEMENT, 5=COMBAT, 6=CAMERA ✓
- Stage 02 matches exactly ✓
- Stage 05 Autoloads GameOrchestrator slot order matches ✓

### EC fan-out downward calls — count declared in Stage 01 vs Stage 04 vs Stage 06:
- Stage 01 declared 4 calls: (1) set_allowed_motors, (2) inject_forced_proposal, (3) swap_collision_shape, (4) set_shifts_enabled
- Stage 04 §0 restates all 4 ✓
- Stage 06 EntityController: forward_forced_proposal, forward_motor_mask, forward_collision_shape, forward_shift_gate — matches 4 ✓

### Intents fields (Stage 01 vs Stage 06):
Stage 01 declared 15 fields:
  Movement (7): move_dir, wants_jump, wants_sprint, wants_sneak, wants_climb_release, wants_glide, wants_mount
  Combat (6): wants_attack, wants_parry, wants_dodge, wants_archery_aim, wants_archery_release, wants_assassinate
  Form (1): wants_form_shift
  Aim (1): aim_target
Stage 06 Intents class fields:
  Movement (7): move_dir, wants_jump, wants_sprint, wants_sneak, wants_glide, wants_climb_release, wants_mount ✓
  Form (1): wants_form_shift ✓
  Combat (6): wants_attack, wants_parry, wants_dodge, wants_archery_aim, wants_archery_release, wants_assassinate ✓
  Aim (1): aim_target ✓
  TOTAL: 15 fields ✓ — matches exactly

### LocomotionState modes (Stage 04 Motor listing vs Stage 06 Mode enum):
Stage 04 Motors mapped to states: WALK, SPRINT, SNEAK, JUMP, FALL, GLIDE, CLIMB, WALL_JUMP, MANTLE, AUTO_VAULT, SWIM, MOUNT, CINEMATIC, DEFEAT (DeathMotor), STAGGER_LIGHT/STAGGER_HEAVY (StaggerMotor), STAGGER_FINISHER→RAGDOLL (RagdollMotor)
Stage 06 Mode enum: WALK, SPRINT, SNEAK, JUMP, FALL, GLIDE, CLIMB, WALL_JUMP, MANTLE, AUTO_VAULT, SWIM, MOUNT, CINEMATIC, RAGDOLL, STAGGER_LIGHT, STAGGER_HEAVY, STAGGER_FINISHER, DEFEAT — 18 values ✓

### ObjectPool (Stage 04 vs Stage 05 vs Stage 06):
- Stage 04: newly declares ObjectPool Autoload; API acquire/release/register_type ✓
- Stage 05: instantiates as Autoload with matching API ✓
- Stage 06: frozen implementation with asserts ✓

### FormBroker._shifts_enabled gate:
- Stage 03 (addendum): introduced set_shifts_enabled(bool) method ✓
- Stage 04: SSoT maps it; EntityController sole mutator ✓
- Stage 05: EntityController node rationale confirms ✓
- Stage 06: set_shifts_enabled(enabled:bool, caller:Node) with caller-identity assert ✓

### LocomotionState nested position:
- Stage 01: MovementBroker sole holder of mutable LocomotionState ✓
- Stage 05 Diagram A: LocomotionState nested under MovementBroker ✓
- Stage 06 EntityController _ready: _locomotion_state.state_changed.connect(...)
  BUT Stage 06 EntityController._ready also resolves _locomotion_state as a cached ref — only MovementBroker holds the mutable set_state surface ✓

### Lens._process PROCESS_MODE_PAUSABLE:
- Stage 03 declared: Lens.process_mode = PROCESS_MODE_PAUSABLE ✓
- Stage 04 §Camera §4: "process_mode = PROCESS_MODE_PAUSABLE" ✓
- Stage 05 Diagram C: "Lens (Node3D, PROCESS_MODE_PAUSABLE, sole _process in cluster)" ✓
- Stage 06: no explicit process_mode declaration in Lens code stubs — Lens is referenced but not declared as a class_name in Stage 06 § 8

### _external_proposals serialization:
- Stage 03 declared: must serialize _external_proposals for rollback ✓
- Stage 04: "must be serialized with entity state for networked rollback" ✓
- Stage 06: MovementBroker declares _external_proposals:Array[TransitionProposal] but NO serialization contract or assert — TBD/graybox phase

### GallopMotor in Stage 05 vs Stage 04:
- Stage 04 Motor inventory lists only entity Motors (not mount-specific). Stage 04 § MountMotor describes mount as separate MountTickBundle type, resolved in Stage 5.
- Stage 05 Diagram B lists GallopMotor as a Mount-entity motor — appears only in Stage 05. Not in Stage 04 inventory.
  → This is a STAGE 05 ADDITION not backed by Stage 04 inventory. Flag for Check A.

### MovementContext (F1) debug panel — Stage 04 vs Stage 05 vs Stage 06:
- Stage 04 Autoloads: MovementContext (F1) declared under DebugOverlay ✓
- Stage 05 Autoloads: MovementContext (F1) declared under DebugOverlay ✓
- Stage 06 § 7 DebugOverlay Contracts: only declares CameraContext (F2), CombatContext (F3), FormContext (F4) — MovementContext (F1) HAS NO CLASS STUB in Stage 06.
  → Flag for Check A and Check K.
