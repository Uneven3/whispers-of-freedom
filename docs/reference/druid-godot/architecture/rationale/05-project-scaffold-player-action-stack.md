> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Project Scaffolding

> **Scope of this artifact.** Cluster-scoped Stage 5 for Cluster A: **Movement, Camera, Combat, Form** (per `00-system-map.md` §§ 2–3, `04-systems-and-components-player-action-stack.md`). Translates Stage 4's Concrete Inventory into exact Godot Scene Tree diagrams, pins parent-child relationships so the architectural rules are enforced by tree shape (not developer discipline), and declares the cluster's Autoload footprint.
>
> **Composition notes.**
> 1. **The entity root is a `Node3D` (`EntityController`), not a `CharacterBody3D`.** The sole `CharacterBody3D` in the tree lives inside a `Body` wrapper child. This makes "the composition root never calls `move_and_slide()`" a structural fact (Rule 2 — `Node3D` does not have the method) rather than a discipline rule. Stage 4 § Composition Root mandated this placement.
> 2. **No `CombatContextStub`.** The cluster ships real `CombatBroker` + `CombatState` + `IncomingAttackBuffer`; Camera `AimMode` / `LockOnMode` bind directly to the real `CombatBroker`-backed Readers.

---

## Godot Scene Tree Scaffold

Three hosts exist in this cluster:

- **Entity** — shared host for Movement + Form + Combat (Player and AI both use this scene).
- **Mount Entity** — minimal host for future horse / boat (registers as `MountTickBundle`, not `EntityTickBundle`).
- **CameraRig** — single-instance, not per-entity in MVP.

One diagram per host.

### Diagram A — Entity (Player or AI) — `EntityTickBundle` participant

```text
Entity (Node3D)  [script: EntityController.gd — composition root + signal hub]
│
├── Body (Node)                                  [wrapper; sole writer of physics motion]
│   └── PhysicsProxy (CharacterBody3D)           [the only CharacterBody3D in the tree]
│       └── CollisionShape3D
│
├── VisualsPivot (Node3D)                        [decoupled from collision; inherits Entity transform]
│   ├── Mesh (Node3D)
│   └── AnimationTree (AnimationTree)
│
├── Brain (Node)                                 [PlayerBrain | AIBrain — populates Intents at slot 1]
│
├── StaminaComponent (Node)                      [shared-mutable: lent to Motors + Actions by EntityController]
├── FormComponent (Node)                         [SSoT state cell — set only by FormBroker]
│
├── FormBroker (Node)                            [slot 3 — ticked by GameOrchestrator via EntityTickBundle]
│
├── MovementBroker (Node)                        [slot 4 — ticked by GameOrchestrator via EntityTickBundle]
│   └── LocomotionState (Node)                   [SSoT state cell — set only by MovementBroker]
│
├── CombatBroker (Node)                          [slot 5 — ticked by GameOrchestrator via EntityTickBundle]
│   ├── CombatState (Node)                       [SSoT state cell — mutated only via active CombatAction]
│   └── IncomingAttackBuffer (Node)              [intra-entity ring buffer; fixed capacity 8]
│
├── Services (Node)                              [organizational folder]
│   ├── Movement (Node)
│   │   ├── GroundService (Node3D)
│   │   │   └── GroundProbe (ShapeCast3D)
│   │   ├── LedgeService (Node3D)
│   │   │   ├── WallProbe (ShapeCast3D)
│   │   │   └── MantleClearanceProbe (ShapeCast3D)
│   │   ├── WaterService (Node3D)
│   │   │   └── SurfaceDetector (Area3D)
│   │   └── MountService (Node3D)
│   │       └── MountDetector (Area3D)
│   └── Combat (Node)
│       ├── HitDetectionService (Node)
│       └── LockOnService (Node)
│
├── Motors (Node)                                [MovementBroker caches children at _ready()]
│   ├── WalkMotor (Node)
│   ├── SprintMotor (Node)
│   ├── SneakMotor (Node)
│   ├── JumpMotor (Node)
│   ├── FallMotor (Node)
│   ├── GlideMotor (Node)
│   ├── ClimbMotor (Node)
│   ├── WallJumpMotor (Node)
│   ├── MantleMotor (Node)
│   ├── AutoVaultMotor (Node)
│   ├── SwimMotor (Node)
│   ├── MountMotor (Node)
│   ├── CinematicMotor (Node)
│   ├── DeathMotor (Node)
│   ├── StaggerMotor (Node)                      [serves STAGGER_LIGHT + STAGGER_HEAVY only]
│   └── RagdollMotor (Node)                      [serves DEFEAT + STAGGER_FINISHER]
│
└── CombatActions (Node)                         [CombatBroker caches children at _ready()]
    ├── TakedownAction (Node)                    [Panther moveset]
    ├── ParryAction (Node)                       [Monkey moveset]
    ├── CounterAction (Node)                     [Monkey moveset]
    └── BowAction (Node)                         [Avian moveset]
```

**Note:** no `CombatContextStub` appears anywhere — the full `CombatBroker` fills that role.

### Diagram B — Mount Entity — `MountTickBundle` participant

```text
MountEntity (Node3D)  [script: MountEntityController.gd]
│
├── Body (Node)
│   └── PhysicsProxy (CharacterBody3D)
│       └── CollisionShape3D
│
├── VisualsPivot (Node3D)
│   └── Mesh (Node3D)
│
├── Brain (Node)                                 [AIBrain — drives mount locomotion even when player-ridden]
│
├── MovementBroker (Node)                        [slot 4 only — MountTickBundle skips slots 3 and 5]
│   └── LocomotionState (Node)
│
├── Services (Node)
│   ├── GroundService (Node3D)
│   │   └── GroundProbe (ShapeCast3D)
│   └── WaterService (Node3D)
│       └── SurfaceDetector (Area3D)
│
└── Motors (Node)
    ├── WalkMotor (Node)
    ├── GallopMotor (Node)
    ├── JumpMotor (Node)
    ├── FallMotor (Node)
    ├── SwimMotor (Node)
    └── MountedRestMotor (Node)
```

**No `FormBroker`, no `FormComponent`, no `CombatBroker`, no `StaminaComponent`** — a mount is pure locomotion. `EntityTickBundle._init`'s four-non-null assert would fail if one were registered; mounts instead construct a `MountTickBundle { brain, movement_broker }` (Stage 2 Mechanism variant). While the player is mounted, the player's own `EntityTickBundle` is deregistered and re-registered on dismount.

### Diagram C — CameraRig — `CameraTickBundle` participant

```text
CameraRig (Node3D)  [script: CameraRig.gd — composition root for the single-instance MVP rig]
│
├── CameraBrain (Node)                           [PlayerCameraBrain — slot 2]
│
├── CameraBroker (Node)                          [slot 6 — arbitrates Modes, iterates Effects, writes to Lens]
│
├── Modes (Node)                                 [CameraBroker caches children at _ready()]
│   ├── FollowMode (Node)
│   ├── AimMode (Node)
│   └── LockOnMode (Node)
│
├── Effects (Node)                               [push-on-request effect stack; CameraBroker iterates]
│   ├── DipEffect (Node)
│   ├── ShakeEffect (Node)
│   ├── FOVZoomEffect (Node)
│   └── FollowEaseInEffect (Node)
│
├── Services (Node)
│   └── OcclusionService (Node3D)
│       └── OcclusionRay (RayCast3D)
│
└── Lens (Node3D)                                [sole `_process` override in the cluster; PROCESS_MODE_PAUSABLE]
    └── SpringArm3D
        └── Camera3D                             [the only Camera3D in the project]
```

**No Form field anywhere under `CameraRig`** — enforced by class shape per Stage 4 § Camera Composition Root.

---

## Entity-Level Transform Sync Contract

Because `PhysicsProxy` is nested inside `Body` (rather than being the entity root), `CharacterBody3D.move_and_slide()` translates only the `PhysicsProxy` node. Without an explicit sync, the collider would drift away from `Entity` and from its sibling `VisualsPivot`, leaving the mesh standing at the spawn point while the collision capsule walks away.

The sync is a **single, structurally-owned operation** inside `Body.apply_motion(velocity: Vector3) -> void`:

1. Assign `PhysicsProxy.velocity = velocity`.
2. Call `PhysicsProxy.move_and_slide()`.
3. Copy the post-slide transform up to the root: `Entity.global_transform = PhysicsProxy.global_transform`.
4. Zero the proxy's local transform: `PhysicsProxy.transform = Transform3D.IDENTITY`.
5. `VisualsPivot` inherits the new `Entity.global_transform` automatically via the scene graph (it is a plain `Node3D` child).

`Body.apply_motion` is called **only** by the currently active Motor, and no other node in the tree has a surface that translates any part of the entity. The sync therefore cannot be forgotten or bypassed — Rule 2 by ownership: there is exactly one writer of physics motion and the sync is inside that writer.

The contract is restated in Stage 6 as a post-condition of `Body.apply_motion`.

---

## Autoloads (Project Settings → Autoload)

Three project-wide Autoloads are declared here as the single authoritative site for this cluster. All three are referenced by Stage 6 contracts; none duplicate content elsewhere.

```text
GameOrchestrator (Node) — PROCESS_MODE_ALWAYS
    Sole owner of the _physics_process tick for the whole project. Drives the 6-slot tick order by iterating registered bundles. No gameplay state.

DebugOverlay (Node) — PROCESS_MODE_ALWAYS, debug build only
    Observer-only aggregation singleton. Contexts attach as children.
    │
    ├── MovementContext (F1)
    ├── CameraContext (F2)
    ├── CombatContext (F3)
    └── FormContext (F4)

ObjectPool (Node) — PROCESS_MODE_PAUSABLE
    Spawn-rate-driven pooling for nodes (e.g. &"arrow" projectile). Holds no gameplay state.
```

---

## Node Rationale

Only non-obvious, structural decisions are documented here. Trivial parent-child relationships are omitted.

- **Entity (`Node3D`, not `CharacterBody3D`).** `Node3D` does not expose `move_and_slide()`. The composition root therefore cannot accidentally become a physics writer.
- **`Body` (wrapper `Node`) → `PhysicsProxy` (`CharacterBody3D`).** Body is a thin wrapper so the physics node is swappable (future ragdoll split) without reshaping siblings.
- **`VisualsPivot` as sibling of `Body` (not child of `PhysicsProxy`).** Rotating visuals must never rotate collision. The Transform Sync Contract ensures they stay aligned.
- **`StaminaComponent` at entity level.** Declared shared-mutable between Movement Motors and Combat Actions; placed here to avoid cross-adjacency reach.
- **`CameraRig` as its own top-level scene.** Not a child of any Entity. Allows future split-screen by swapping one `CameraRig` for an array without restructuring Entity internals.
- **Mount Entity as a separate scene.** Resolves the null-Form / null-Combat problem by registering as a separate bundle type rather than polluting the Player entity with null stubs.

---

## Exit Criteria

- [x] Complete Godot Scene Tree layout text diagrams — three diagrams (Entity, MountEntity, CameraRig) covering every component in Stage 4's Concrete Inventory.
- [x] Explicit Godot types assigned to all components — `Node3D` / `CharacterBody3D` / `ShapeCast3D` / `Area3D` / `RayCast3D` / `SpringArm3D` / `Camera3D` / `AnimationTree` / `Node` as appropriate.
- [x] DebugOverlay appears in the Autoloads section with one context node per system-in-group that claimed an F-key in Stage 1 — `MovementContext` (F1), `CameraContext` (F2), `CombatContext` (F3), `FormContext` (F4).
- [x] Entity-Level Transform Sync Contract section present; pins `Body.apply_motion` as the sole writer that copies `PhysicsProxy.global_transform` onto `Entity.global_transform` post-`move_and_slide` and zeroes the proxy's local transform.

**Cluster-A-specific additions beyond the stage template:**

- [x] Three diagrams (Entity / MountEntity / CameraRig) rather than one — the cluster has three distinct hosts.
- [x] `ObjectPool` Autoload newly declared as a derived requirement from Stage 4's crowd-archery pooling threshold.
- [x] Transform sync contract pinned structurally to resolve the nested-`CharacterBody3D` drift risk introduced by the new composition-root layout.
