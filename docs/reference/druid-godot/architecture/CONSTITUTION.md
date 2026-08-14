> [!NOTE]
> Long-form rationale for each clause: see `docs/architecture/rationale/` (cluster Stage 1–6 artifacts).

# Architecture Constitution

## Tier 1 — General rules (engine/language-agnostic)

| # | Rule | Auditable signal |
|---|---|---|
| **G1** | **Single Responsibility** — each node/resource/script owns exactly one concern. | Heuristic flag: scripts > 300 lines, or with > 5 unrelated public methods. Soft signal — auditor flags as candidate, not auto-violation. |
| **G2** | **Single Source of Truth, including state machines** — every fact has exactly one owner; no local copies. Mutually exclusive states are encoded as enums or state-machine cells, never as boolean trios (`is_jumping` + `is_falling` + `is_climbing`). | Duplicate state fields across sibling scripts; boolean flag soup for exclusive states. |
| **G3** | **Data flows down, events flow up** — parents inject and call methods on children; children emit signals upward. Signals describe things that have happened (`landed`, `health_depleted`); method calls request things to happen (`drain()`, `apply_motion()`). No sideways access. | `get_parent()` / `$Sibling` outside composition roots; signals named `request_X` / `do_X`; sibling-to-sibling method calls between non-composition nodes. |
| **G4** | **Data structures carry zero logic** — structs are pure facts. | Method bodies (other than `_init` or pure getters) inside `Intents` / `TransitionProposal` / `LocomotionState` data classes. |
| **G5** | **Boundary validation communicates intent** — public surfaces validate inputs and name what was expected vs what was received. Bare `assert(condition)` is not enough. Use `assert(condition, "intent message")` for **programmer-error invariants** (wrong type, internal misuse) — these are stripped from release exports. Use `push_error("intent message")` + early-return for **runtime-reachable failures** (bad designer values, missing optional nodes, loaded data) — these survive release. | Public surface methods missing assertions OR with assertions lacking an intent message. Best-effort heuristic. |
| **G6** | **Composition over deep inheritance** — inheritance ≤ 2 levels. Behaviors are added as child Nodes, not by extending the class hierarchy. | Inheritance depth ≥ 3; god-class with many unrelated public methods that should be sibling Nodes. |

## Tier 2 — Project-specific rules

| # | Rule | Auditable signal |
|---|---|---|
| **P1** | **Brain → Intents → Broker** — engine input enters the simulation only through a Brain. AI and Player Brains share the same Intents shape. | `Input.*` calls outside `*Brain.gd`. |
| **P2** | **Active Motor exclusivity** — exactly one Motor ticks per entity per physics frame, dispatched by the Broker via `gather_proposals` arbitration. | Motor `tick()` reachable without going through a Broker; multiple Motor `tick()` calls in one frame for one entity. |
| **P3** | **SSoT writers — specific owners** — only MovementBroker writes `LocomotionState`; only the active Motor writes Body motion; only StaminaComponent mutates stamina. | Direct write to `LocomotionState._mode` outside `LocomotionState.set_state`; `Body.velocity` / `move_and_slide()` called outside an active Motor's tick; stamina mutated outside StaminaComponent's `drain`/`recover`. |
| **P4** | **Readers for cross-system reads** — code outside a system holds a `*Reader`, never the mutable owner. | Direct field access on another system's mutable component from outside that system's folder. |
| **P5** | **No implicit ticks** — every script that overrides `_process` or `_physics_process` calls `set_*_process(false)` in `_ready()` unless it is a registered loop owner. Registered loop owners: `MovementBroker` (_physics_process, motor arbitration), `CameraRig` (_process, visual interpolation — always-on by design, annotated in code), `VisualsPivot` (_process, visual interpolation — explicitly owned). | Process override without `set_*_process(false)` in `_ready()` and not in the registered owner list. |
| **P6** | **No global game state** — Autoloads are stateless utilities or passive observers (DebugOverlay). Game variables live in scene-tree nodes. | Autoload var outside an explicit allowlist (initial allowlist: `DebugOverlay.panel_visible`, `DebugOverlay._contexts`). |
| **P7** | **Layer adjacency** — Brain → Broker → Motors → Body. No skipping. A Motor never reads Brain directly; a Brain never holds a Body reference; a Body is invoked only by the active Motor. | Brain held by a non-Broker; Body methods called outside the active Motor; Motor reaching past Broker. |

> **Enforcement:** GDScript cannot enforce all of these structurally. Treat violations as bugs. Flag every breach regardless of intent. Constitution amendments go through `/constitution-violation`.
