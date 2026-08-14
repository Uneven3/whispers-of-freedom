> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Migration Safety Report — Movement → Player Action Stack Consolidation

**Date:** 2026-04-19
**Cluster:** A (Player Action Stack = Movement + Camera + Combat + Form)
**Scope:** Consolidate the five authoritative `-movement.md` Stage 2–6 artifacts into their `-player-action-stack` cluster counterparts, then delete the legacy files.
**Decision:** User directive, "Consolidate only, no audit." The Stage 07 architecture-audit is deferred to a follow-up session (`/start-stage architecture-audit player-action-stack`) and runs on the consolidated cluster artifacts.

---

## Classification legend

- **(a) Absorbed** — the cluster-scoped counterpart already contains semantically equivalent content. Safe to drop on deletion of the legacy file.
- **(b) Delegated-to** — the cluster artifact explicitly points to the legacy file as the authoritative home ("declared in …", "live in …", "remains authoritative"). The legacy content is load-bearing for the cluster; **must be inlined** into the cluster before deletion.
- **(c) Orphaned** — content exists only in the legacy file. Inline-into-cluster or drop-as-superseded decision recorded per section.

---

## § 02-data-flow-movement.md → 02-data-flow-player-action-stack.md

| Legacy section | Class | Action |
|---|---|---|
| Core Design Principles (Rules 9, 10, 13, 5 enforcement narrative) | (a) Absorbed | Cluster 02 has its own "Core Design Principles: Compliance with Architecture Protocol" table with richer per-rule mechanisms. Movement-specific narrative redundant. |
| The Orchestrator Loop — **6-step Movement-internal sub-loop** (Brain → Services update_facts → Arbitration → State transition → Motor on_tick → Body apply_motion) | (b) Delegated-to | Cluster 02 line 246 pins this as "remains authoritative in `02-data-flow-movement.md`". **Must inline** into cluster 02 Slot 4 description, replacing the delegating pointer. |
| Narrative Data Trace 1 — Walk off cliff / FALL | (a) Absorbed | Cluster 03 § Narrative Traces Trace 1 carries this case forward with the full FORCED vs DEFAULT arbitration rule statement. |
| Narrative Data Trace 2 — Enemy sprint stamina exhaustion / OPPORTUNISTIC | (c) Orphaned → **drop** | Cluster 02/03 do not trace this case. The OPPORTUNISTIC proposal category rule is stated in cluster 03 § Conflicting Resolutions. Illustrative, not load-bearing. |
| Narrative Data Trace 3 — Glider deploy / PLAYER_REQUESTED | (c) Orphaned → **drop** | Same rationale — PLAYER_REQUESTED category rule stated in cluster 03 § Conflicting Resolutions. Cluster 02 Trace B (0-frame form shift) demonstrates the category differently. |
| Narrative Data Trace 4 — Stagger interrupt (upward signal → EC → inject_forced_proposal) | (a) Absorbed | Cluster 02 Trace C "Counter-parry staggers enemy: the 1-frame-latency cross-system path" is the cluster-equivalent trace, more complete. |

---

## § 03-edge-cases-movement.md → 03-edge-cases-player-action-stack.md

| Legacy section | Class | Action |
|---|---|---|
| Conflicting Resolutions — rule statement (4 categories, `override_weight` tie-break, ambiguous-tie `assert(false)`) | (a) Absorbed | Cluster 03 lines 24–41 state the cluster-wide rule, generalized across all four Brokers. The rule is already inlined. |
| Conflicting Resolutions — example (cliff + zero stamina + exploding barrel → RAGDOLL) | (a) Absorbed | Cluster 03 line 47 "Per-system conflict cases: Movement (intra-system)" already inlines this example. The "see movement-03" back-reference is a stale pointer; the content IS present. Strip the pointer on consolidation. |
| External Interruptions (Pause / Death / Cutscene) — Movement-scoped | (a) Absorbed | Cluster 03 § External Interruptions (lines 126–162) covers Pause via Orchestrator early-return, Death via EC-driven FORCED DEFEAT + ragdoll-safe shift-gate, Cutscene via CINEMATIC + shift-gate. Richer than legacy. |
| Network / God-level Edge Cases — deterministic pipeline, rollback feasibility, RNG rule | (a) Absorbed | Cluster 03 § Network/God-level Edge Cases (lines 165–192) explicitly "extends Movement 03's baseline" and inlines the deterministic pipeline, rollback constraint, and RNG rule ahead of cluster-specific additions (AIBrain authority, lock-on stable-ID, `_external_proposals` serialization). |

---

## § 04-systems-and-components-movement.md → 04-systems-and-components-player-action-stack.md

| Legacy section | Class | Action |
|---|---|---|
| § 0 Composition Root — `EntityController` as `CharacterBody3D` root | (c) Orphaned → **drop** | Explicitly superseded by cluster 04 + cluster 05 + cluster 06: `EntityController extends Node3D`, `Body` wrapper owns a child `PhysicsProxy: CharacterBody3D`. The `CharacterBody3D` root is architecturally obsolete. |
| § 1 Brain Layer (`PlayerBrain`, `AIBrain`) | (a) Absorbed | Cluster 04 enumerates Brains in the per-system Movement sub-section. |
| § 2 Broker Layer (`MovementBroker`) | (a) Absorbed | Cluster 04 covers `MovementBroker`; cluster 06 declares the public surface (`inject_forced_proposal`, `set_allowed_motors`) via delegation + cluster-specific additions. |
| § 3 Motors Layer (14 motors) | (a) Absorbed | Cluster 04 + cluster 05 scaffold list all 14 Motors PLUS `StaggerMotor` + `DeathMotor` (2 cluster-added). Superset coverage. |
| § 4 Services Layer (Ground / Ledge / Water / Mount) | (a) Absorbed | Cluster 04 per-system Services sub-sections enumerate all four. Cluster 05 scaffold places them. |
| § 5 Body & State Layer (`MovementBody`, `StaminaComponent`, `LocomotionState`) | (a) Absorbed | Cluster 04 covers these; `MovementBody` is renamed to `Body` (Node wrapper) per cluster 06 supersession. `StaminaComponent` + `LocomotionState` carry forward unchanged. |
| § 6 Cross-System Stubs — `CombatContextStub` | (c) Orphaned → **drop** | Cluster 05 § "No `CombatContextStub` anywhere" explicitly removes the stub. Real `CombatBroker` + Readers fill the slot. |
| SSoT Ownership and Access Mapping (Locomotion / Stamina / Body / Intents) | (a) Absorbed | Cluster 04 has an extensive SSoT Ownership section covering all cluster states including these four. |
| Performance Constraints — Universal Rules, Game-Specific Thresholds (50-entity cap, Jolt, shapecast pooling), Per-Component Notes | (a) Absorbed | Cluster 04 Performance section inherits and extends these with cluster-wide budget (0.15 ms/entity). |
| Autoloads — `GameOrchestrator` (prior reference) | (a) Absorbed | Cluster 04 line 342 references `GameOrchestrator` as "Declared in movement-04, carried forward". The declaration content is present in cluster 02 Mechanism 4 and cluster 05 Autoloads. Strip the movement-04 pointer on consolidation. |
| Autoloads — `DebugOverlay.MovementContext (F1)` | (b) Delegated-to | Cluster 04 line 349 says "declared in `04-systems-and-components-movement.md`. Carried forward unchanged into the cluster; Stage 6 contracts will consolidate." The F1 panel's sub-view enumeration is in cluster 01 line 465 (already absorbed), but the Stage-4 Autoload declaration of `MovementContext (F1)` as a child of `DebugOverlay` **must inline** into cluster 04 Autoloads section. |

---

## § 05-project-scaffold-movement.md → 05-project-scaffold-player-action-stack.md

| Legacy section | Class | Action |
|---|---|---|
| Godot Scene Tree Scaffold — Entity (CharacterBody3D) root, 14 motors, CombatContextStub | (c) Orphaned → **drop** | Superseded by cluster 05 Diagram A (Entity Node3D root with `Body` wrapper owning `PhysicsProxy: CharacterBody3D`, 16 motors, no CombatContextStub). |
| Autoloads — `GameOrchestrator (Node)` with PROCESS_MODE_ALWAYS + tick-slot list | (b) Delegated-to | Cluster 05 line 201 "[Declared in 05-project-scaffold-movement.md. Carried forward; not redeclared.]" is a provenance placeholder under a line that already restates the declaration. **Replace placeholder** with a one-line statement that this cluster is now the sole scaffold site, deleting the pointer. |
| Autoloads — `DebugOverlay (Node)` with PROCESS_MODE_ALWAYS + debug-build guard | (b) Delegated-to | Cluster 05 line 213 same placeholder pattern as above. **Replace placeholder** with a sole-declaration-site statement. |
| Node Rationale — Entity root, EntityController, VisualsPivot, StaminaComponent, LocomotionState, Services/Motors folders, Services probes, DebugOverlay, GameOrchestrator, CombatContextStub | (a) Absorbed | Cluster 05 Node Rationale covers every rationale that carries forward and supersedes the root-node rationale with the Node3D argument. `CombatContextStub` rationale is explicitly dropped by § "No `CombatContextStub` anywhere." |

---

## § 06-interfaces-and-contracts-movement.md → 06-interfaces-and-contracts-player-action-stack.md

The largest surface. The cluster 06 line 1051 "Explicitly **not redeclared**" clause is the authoritative delegation list. Every item on that list must be inlined.

| Legacy section | Class | Action |
|---|---|---|
| Pure Data Struct — `class_name Intents` (full field list, `NO_AIM_TARGET` sentinel, `has_aim_target()`, `validate()`) | (b) Delegated-to | Cluster 06 line 1051 says not redeclared; cluster § 1 Addendum adds `is_complete()`. **Inline the full `Intents` class declaration** into cluster 06 § 1, then collapse the Addendum into the unified declaration. |
| Pure Data Struct — `class_name TransitionProposal` with `Priority { DEFAULT, PLAYER_REQUESTED, OPPORTUNISTIC, FORCED }` enum, `_init(p_target, p_category, p_weight)` | (b) Delegated-to | **Inline** into cluster 06 § 1. |
| Pure Data Struct — `class_name DebugSnapshot` (timestamp, source_node_path, data) | (b) Delegated-to | **Inline** into cluster 06 § 1. |
| `class_name Body extends RefCounted` (old — wraps CharacterBody3D directly, no PhysicsProxy child, no Transform Sync Contract) | (c) Orphaned → **drop** | Explicitly superseded by cluster 06 § 2 `Body extends Node` with a child `PhysicsProxy: CharacterBody3D` and the Transform Sync Contract post-condition on `apply_motion`. |
| Reader Wrapper — `class_name BodyReader extends RefCounted` (`_init(body: Body)`, forwarded `grounded_changed` + `impact_detected` signals, getters) | (b) Delegated-to | Cluster 06 line 267 says "Movement-06 `BodyReader._init(body: Body)` remains valid — its getters are unchanged; the signal-forwarding is unchanged; only `Body`'s internals change." **Inline** the `BodyReader` declaration into cluster 06 § 2 alongside the new `Body`. |
| Reader Wrapper — `class_name StaminaReader` (`exhausted` + `stamina_changed` signals, `get_value` / `get_max` / `is_exhausted`) | (b) Delegated-to | **Inline** into cluster 06 § 2. |
| Reader Wrapper — `class_name LocomotionStateReader` (`state_changed` forwarded signal, `get_active_mode`) | (b) Delegated-to | **Inline** into cluster 06 § 2. |
| State Component — `class_name LocomotionState extends Node` (Mode enum: WALK, SPRINT, SNEAK, JUMP, FALL, GLIDE, CLIMB, WALL_JUMP, MANTLE, AUTO_VAULT, SWIM, MOUNT, CINEMATIC, RAGDOLL; `active_mode`, `set_state`, `state_changed` signal) | (b) Delegated-to | **Inline** into cluster 06. Note: cluster 05 scaffold adds StaggerMotor + DeathMotor states (`STAGGER_LIGHT`, `STAGGER_HEAVY`, `STAGGER_FINISHER`, `DEFEAT`) — the enum must be extended during inlining to match the cluster-wide motor set. Cluster 06 `_on_stagger_triggered` references `LocomotionState.Mode.STAGGER_LIGHT`, `STAGGER_HEAVY`, `STAGGER_FINISHER`, `DEFEAT` — these enum entries are required for cluster 06 to type-check. |
| Resource Component — `class_name StaminaComponent extends Node` (max_stamina, regen_rate, regen_delay exports; drain, tick_regen, clear_exhaustion; Progression TBD note) | (b) Delegated-to | **Inline** into cluster 06. Progression TBD note carries forward verbatim. |
| Base class — `class_name BaseMotor extends Node` (`gather_proposals`, `on_enter`, `on_exit`, `on_tick` virtuals with `assert(false, "%s must override …")` traps) | (b) Delegated-to | **Inline** into cluster 06 § "Base Classes". |
| Base class — `class_name BaseService extends Node` (`update_facts`, `gather_proposals` virtuals) | (b) Delegated-to | **Inline** into cluster 06 § "Base Classes". |
| `MovementBroker` public surface — `inject_forced_proposal(TransitionProposal)` with FORCED-only assert, `set_allowed_motors(Array[StringName])` | (b) Delegated-to | **Inline** into cluster 06 § "MovementBroker". Cluster 06 already references these surfaces in the `EntityController.forward_forced_proposal` and `forward_motor_mask` methods; making the Broker declaration local lets the cluster be the sole SSoT. |
| `class_name EntityController extends CharacterBody3D` (old — composition root as physics body) | (c) Orphaned → **drop** | Explicitly superseded by cluster 06 § 2 `EntityController extends Node3D` with the new composition pattern (four forward methods, bundle registration, handlers for form/state/stagger/outgoing-attack). |
| `EntityController` § **Signal-Listener Contract** table (9 rows: state_changed, exhausted, mount_ready, form_shifted, stagger_triggered, defeated, damage_taken, cinematic_requested, progression_changed) | (c) Orphaned → **inline** | Cluster 06's superseded `EntityController` has concrete `_on_form_shifted`, `_on_stagger_triggered`, `_on_locomotion_state_changed`, `_on_outgoing_attack_resolved` handlers that realize the Form / Combat / DEFEAT+CINEMATIC rows. The **remaining TBD rows** (`defeated` from Health, `damage_taken` from Health, `cinematic_requested` from Interaction, `progression_changed` from Progression, `exhausted` no-op, `mount_ready` entity-swap) document cross-cluster signal routing that future out-of-cluster Stage 1 artifacts (Health, Interaction, Progression, Mount) need to author against. **Must inline** the full table into cluster 06 under the new `EntityController` declaration, updated to reflect the cluster's realized handlers and preserved TBD rows. |
| `EntityController` § **Dependency-Injection Contract** table (3 rows: BodyReader, StaminaReader, LocomotionStateReader) | (c) Orphaned → **inline** | Cluster 04 has a broader SSoT Ownership section but does not re-state the Reader → Consumer mapping in the "enforces what" form the movement-06 table uses. **Inline** into cluster 06 alongside the inlined Readers, extended with cluster Readers (FormReader, AimingReader, LockOnTargetReader, CombatStateReader, CameraReader) that are already declared elsewhere in cluster 06. |
| `EntityController` § **Rule-13 Assertion** paragraph | (a) Absorbed | Cluster 03 Core Design Principles rule-13 row + cluster 04 no-sideways enforcement cover this. |
| Base class — `class_name BaseBrain extends Node` (`gather_intents()` virtual) | (b) Delegated-to | **Inline** into cluster 06 § "Base Classes". |
| `class_name BaseDebugContext extends Node` (`get_panel_key`, `render` virtuals) | (b) Delegated-to | **Inline** into cluster 06 § 6. `CameraContext` / `CombatContext` / `FormContext` already extend this class; making the base local keeps the cluster self-contained. |
| DebugOverlay singleton `push(context_key: int, snapshot: DebugSnapshot)` interface + release-build no-op guard | (b) Delegated-to | **Inline** into cluster 06 § 6 alongside `BaseDebugContext`. |

---

## Orphaned-inlined content summary (cluster 06 sole net growth)

Items explicitly pulled from movement-06 that cluster 06 must now own as a first-class declaration:

- `Intents`, `TransitionProposal`, `DebugSnapshot` (with `Intents.is_complete()` folded in)
- `BodyReader`, `StaminaReader`, `LocomotionStateReader`
- `LocomotionState` (with Mode enum extended to include `STAGGER_LIGHT`, `STAGGER_HEAVY`, `STAGGER_FINISHER`, `DEFEAT` to match cluster motors)
- `StaminaComponent` (with Progression-reader TBD note)
- `BaseMotor`, `BaseService`, `BaseBrain`
- `MovementBroker` public surface (`inject_forced_proposal`, `set_allowed_motors`)
- `BaseDebugContext` + `DebugOverlay.push` interface
- Signal-Listener Contract table (updated for cluster realized rows)
- Dependency-Injection Contract table (extended for cluster Readers)

Items explicitly dropped (superseded, not inlined):

- Old `Body extends RefCounted` (wraps CharacterBody3D root)
- Old `EntityController extends CharacterBody3D`
- `CombatContextStub` (scaffold-04 + scaffold-05 deletion)
- Movement-02 Trace 2 (enemy sprint stamina exhaustion)
- Movement-02 Trace 3 (glider deploy PLAYER_REQUESTED)

---

## Final verdict

**SAFE-AFTER-CONSOLIDATION** — inline the items listed in the Delegated-to rows and the "inline" rows of the Orphaned classification, then delete the five legacy files in a single batch. Every item marked (a) Absorbed is already carried by the cluster artifacts; every item marked (c) Orphaned → drop is explicitly superseded by a cluster-scoped replacement.

Post-consolidation verification (Step 5 of the plan):

- `grep -rn 'movement\.md' docs/architecture/` returns zero matches.
- `ls docs/architecture/*-movement.md` returns no files.
- Cluster 06 alone declares every class_name previously owned by movement-06 (except `Body (old)` and `EntityController (old)` which are superseded).
- Every `CONSTITUTION.md` rule cited by the legacy files is still cited in a cluster equivalent.

This report is retained as the provenance record for the merge. The Stage 07 architecture-audit session (`/start-stage architecture-audit player-action-stack`) uses it as the primary reference for Rule C (no partial-cluster leftovers) verification.
