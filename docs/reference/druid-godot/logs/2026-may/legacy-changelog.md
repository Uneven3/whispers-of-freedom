# Workflow Changelog

---

## 2026-05-02: Fix Motor API Mismatch + Phase Enum + Spatial Apex Detection

**Problem:** Commit `76de5cb` changed `LedgeService.get_ledge_facts(body_reader)` to `get_ledge_facts()` (no args — values pre-cached in `update_facts`) but did not update `auto_vault_motor.gd` (2 call sites) or `climb_motor.gd` (1 call site), which still passed `_broker.get_body_reader()`. On machines without a stale GDScript bytecode cache (`.godot/`), the runtime errored with "too many arguments." Additionally: `auto_vault_motor` had a G2 violation (`_is_vaulting` + `_just_activated` booleans encoding a 3-state machine), and `climb_motor` used stale temporal state (`_last_climb_normal != ZERO`) as a proxy for "are we in a climbing context" in `gather_proposals`, which could false-positive on flat ground.

**Fix:** Full `/slice` cycle (`motor-api-fix-phase-enum`). Working-tree quick-fix (from the other machine) already had `auto_vault_motor` corrected with `enum Phase { INACTIVE, ACTIVATING, RUNNING }` and `ledge_facts.gd` with `has_head_hit` declared. This slice added the remaining work: removed `_last_climb_normal` entirely from `climb_motor` (field, tick fallback, `on_deactivate`), replacing the temporal gather_proposals proxy with a three-point spatial check (`on_floor and not has_head_hit and ledge_point != ZERO`). Test mock signatures updated; new `test_climb_motor.gd` with 3 tests added; `test_ledge_facts.gd` extended with missing default assertions. All 31 tests pass on clean run.

**Files:**
- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/auto_vault_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_facts.gd`
- `graybox-prototype/test/unit/test_climb_motor.gd`
- `graybox-prototype/test/unit/test_edge_leap_motor.gd`
- `graybox-prototype/test/unit/test_ledge_facts.gd`
- `docs/slices/motor-api-fix-phase-enum-solutions.md`
- `docs/slices/motor-api-fix-phase-enum-plan.md`

## 2026-05-01: Fix Climb State Transitions and Toggle Clearing

**Problem:** `ClimbMotor` was unreachable from airborne and fast ground states: `SPRINT` and `GLIDE` outbid it via `FORCED` priority proposals, and `ClimbToggleComponent` erased the toggle on `JUMP` entry — preventing jump-then-grab. Additionally, `_on_locomotion_state_changed` in `ClimbToggleComponent` never fired because the signal was never connected: the component's `_ready()` ran before `MovementBroker._ready()` (scene node order), so `get_state_reader()` returned null silently.

**Fix:** Three motor-layer fixes using the established abstain pattern (`return []`): `SprintMotor` yields to `ClimbMotor` when `LedgeService.can_climb()` and `wants_climb`; `GlideMotor` downgrades its sticky `FORCED` proposal to `PLAYER_REQUESTED` under the same conditions, letting `ClimbMotor`'s weight-5 win the tiebreak; `GlideMotor.on_deactivate` resets `_previous_wants_glide` to prevent spurious re-entry. `ClimbToggleComponent` was fixed to use `call_deferred("_connect_to_broker")` so the connection to `broker.state_changed` happens after all `_ready()` calls complete. Toggle clear rules updated: `JUMP` removed (player may jump then grab), `AUTO_VAULT` added; `MANTLE`, `EDGE_LEAP`, and conditional `WALL_JUMP`-away preserved. Two new unit tests added for `AUTO_VAULT` clear and `JUMP` non-clear.

**Files:**
- `graybox-prototype/scripts/player_action_stack/movement/climb_toggle_component.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/sprint_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/glide_motor.gd`
- `graybox-prototype/test/unit/test_player_brain_toggle.gd`

## 2026-05-01: Redesign `/slice` Workflow — Solution Selection Loop

**Problem:** The `/slice` orchestrator had a shallow single-plan-draft → review loop. The Builder proposed one solution; there was no genuine deliberation about architectural approach before committing to implementation. Tests were also never run as a final gate.

**Fix:** Rewrote the `/slice` orchestrator to add a **solution selection phase** (Phase 1, max 5 iterations): Builder proposes 3 distinct solutions, Reviewer raises doubts and edge cases for each, they iterate until one is agreed upon, then the user confirms before implementation starts. Added a test-run gate (Phase 4) with a structured failure report instead of silent pass-through. Removed the manual pipeline skills (`slice-plan`, `implement-feature`, `audit`) from all three locations (`.agents/`, `.claude/skills/`, `.gemini/skills/`). Created `docs/slices/_solutions-template.md` as the artifact template for Phase 1. Cleaned up `AGENTS.md` to remove all manual pipeline references.

**Files:**
- `.agents/slice/SKILL.md`
- `.agents/slice-builder/SKILL.md`
- `.agents/slice-reviewer/SKILL.md`
- `docs/slices/_solutions-template.md`
- `.claude/skills/slice/SKILL.md`
- `.gemini/skills/slice/SKILL.md`
- `AGENTS.md`
- Deleted: `.agents/slice-plan/`, `.agents/implement-feature/`, `.agents/audit/` (and `.claude/skills/` + `.gemini/skills/` mirrors)

## 2026-04-30: Auto-Vault Refactor and Climb Vibration Fix

**Problem:** Auto-vault was triggering inappropriately (e.g., on flat ground, small stairs, or walking into walls at an angle) while missing valid low obstacles like the wide rail. Additionally, reaching the top of a climbable wall caused the player to violently vibrate.

**Fix:** Refactored `LedgeService` to implement a "Step-Up" vault paradigm. Standardized all horizontal profiling casts to `ShapeCast3D` with a `0.1m` radius for uniform detection regardless of approach angle. Adjusted vertical detection casts to clear the floor, added a `vault_min_height` check, and filtered out walkable slopes by checking collision normals. Fixed `ClimbMotor` vibration by replacing the hard position teleport with a soft velocity clamp based on distance to the ledge top. Spawned the player slightly higher in `main.tscn` to ensure a clean physics initialization.

**Files:**
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_facts.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/auto_vault_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd`
- `graybox-prototype/test/unit/test_ledge_facts.gd`
- `graybox-prototype/scenes/main.tscn`

## 2026-04-30: Fix Wall-Sucking and Optimize LedgeService Casts

**Problem:** Two related issues in `LedgeService` / `ClimbMotor`:
1. **Wall-sucking** — the `wall_stick` pull activated too early because `_waist_cast` and `_head_cast` detected walls at 1.0 unit, but player capsule radius is 0.5 units. The 0.5-unit gap meant climb state activated and wall_stick ran for ~1 second before the player touched the wall.
2. **Unnecessary ShapeCast3D usage** — `_head_cast`, `_left_cast`, and `_right_cast` only call `is_colliding()` (no `get_collision_point()` needed), yet were implemented as ShapeCast3D sphere-sweeps.

**Fix:**
1. Added `@export var wall_detection_reach: float = 0.6` to `LedgeService`. Changed `_waist_cast` and `_head_cast` `target_position` from `facing` (1.0 unit) to `facing * wall_detection_reach` (0.6 unit = capsule radius + 0.1 buffer). Climb activates at near-contact distance; wall_stick now closes a ~0.1-unit gap (~0.2s at 0.5 m/s).
2. Replaced `_head_cast`, `_left_cast`, `_right_cast` from `ShapeCast3D` to `RayCast3D`. Added `_create_forward_raycast()` helper alongside the existing `_create_forward_cast()`. All `force_shapecast_update()` calls on the three converted nodes replaced with `force_raycast_update()`. `_waist_cast`, `_down_cast`, and `_vault_landing_cast` remain `ShapeCast3D` (they use `get_collision_point()`).

**Files:**
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`
- `docs/slices/wall-sucking-fix-plan.md`
- `docs/slices/raycast-bool-casts-plan.md`

## 2026-04-30: Add `/slice` Two-Agent Orchestrator

**Problem:** The graybox implementation workflow had four disconnected skills (`/slice-plan`, `/plan-eval`, `/implement-feature`, `/cold-audit`) that relied on the user to hand off between steps. Reviews were weak because the same session context carried into evaluation, eliminating the "cold" guarantee.

**Fix:** Introduced a two-agent orchestrator system: a **Builder** (`/slice-builder`) that plans and implements a slice end-to-end as a single Senior Godot Architect persona, and a cold **Reviewer** (`/slice-reviewer`) that receives only file paths and no session context, citing Constitution clauses by ID. The **Orchestrator** (`/slice`) scopes the feature with the user, then runs two gated loops — plan review then code audit — each capped at 3 iterations before surfacing a stalemate. The user sees every critique verbatim. On Claude Code, true cold isolation is achieved via the `Agent` tool (sub-agent spawn); on Gemini, isolation is best-effort and documented in the skill. Old manual skills remain intact, marked as `(manual)` in AGENTS.md.

**Files:**
- `.agents/slice/SKILL.md`
- `.agents/slice-builder/SKILL.md`
- `.agents/slice-reviewer/SKILL.md`
- `.claude/skills/slice/SKILL.md`
- `.claude/skills/slice-builder/SKILL.md`
- `.claude/skills/slice-reviewer/SKILL.md`
- `.gemini/skills/slice/SKILL.md`
- `.gemini/skills/slice-builder/SKILL.md`
- `.gemini/skills/slice-reviewer/SKILL.md`
- `AGENTS.md`

## 2026-04-30: Edge Leap Motor & Climbing Refinement
**Problem:** Lateral edge captures during climbing were inconsistent, and the wall-jump logic was overly complex. Previous attempts to modify `WallJumpMotor` compromised core movement feel.
**Fix:** Introduced a dedicated `EDGE_LEAP` state and `EdgeLeapMotor` to handle leaping away from wall edges. Refactored climbing to a toggle-based system in `PlayerBrain` with contextual reset logic. Corrected Rule P7 architectural violations by ensuring all Motors access world state through the `MovementBroker`. Expanded `LedgeService` to support lateral detection and verified the entire system with 25 unit tests.
**Files:**
- `docs/architecture/ARCHITECTURE-MAP.md`
- `graybox-prototype/scenes/main.tscn`
- `graybox-prototype/scripts/base/intents.gd`
- `graybox-prototype/scripts/player_action_stack/movement/locomotion_state.gd`
- `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd`
- `graybox-prototype/scripts/player_action_stack/movement/player_brain.gd`
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/edge_leap_motor.gd`

## 2026-04-30: Semantic Intent Refactor & Wall-Jump Fix
**Problem:** The `MantleMotor` was incorrectly hijacking lateral and backward wall jumps when the player was near a ledge. Additionally, the codebase used raw hardware coordinate checks (e.g., `raw_input.y < -0.5`) which was difficult to read and hardware-dependent.
**Fix:** Refactored the `Intents` system to use semantic, human-readable getters like `is_climbing_up` and `is_moving_forward`. Updated the `PlayerBrain` to handle hardware translation and populated a discrete `wish_dir`. Updated `MantleMotor`, `ClimbMotor`, and `WallJumpMotor` to use this new API. Enhanced the `DebugOverlay` to visualize semantic intents.
**Files:**
- `graybox-prototype/scripts/base/intents.gd`
- `graybox-prototype/scripts/player_action_stack/movement/player_brain.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/mantle_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/wall_jump_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd`
- `graybox-prototype/test/unit/test_intents.gd`
- `docs/architecture/ARCHITECTURE-MAP.md`

## 2026-04-30: Slice 3 — Tier 1 Unit Tests (Pure Data)

**Problem:** Need for foundational unit tests for pure data classes and basic components to ensure data integrity and boundary logic before moving to more complex integration tests.

**Fix:**
- Implemented unit tests for `Intents`, `TransitionProposal`, `LedgeFacts`, and `StaminaComponent` using GUT 9.6.0.
- Adhered to `docs/testing-guidelines.md` patterns: `before_each`/`after_each`, `assert_no_new_orphans()`, and `watch_signals()`.
- Verified 15/15 tests passing (69 asserts) using the headless runner.

**Files:**
- `graybox-prototype/test/unit/test_intents.gd`
- `graybox-prototype/test/unit/test_transition_proposal.gd`
- `graybox-prototype/test/unit/test_ledge_facts.gd`
- `graybox-prototype/test/unit/test_stamina_component.gd`

---

## 2026-04-30: Slice 2 — Testing Scaffold (GUT 9.6.0)

**Problem:** No automated test infrastructure existed. GUT was documented in `workflow/stages/deferred/testing/` but never installed.

**Fix:**
- Downloaded and installed GUT 9.6.0 to `graybox-prototype/addons/gut/`.
- Enabled the plugin via `[editor_plugins]` in `project.godot`.
- Created `graybox-prototype/test/unit/` and `graybox-prototype/test/integration/` directories.
- Wrote `test/unit/test_gut_setup.gd` smoke test — verified 1/1 passing headless.
- Promoted `workflow/stages/deferred/testing/` → `workflow/stages/testing/`.
- Wrote `docs/testing-guidelines.md` with the four-tier structure, assert vs push_error policy, template, and GUT assertions quick reference.

**Headless run command:** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit` (run from `graybox-prototype/`)

**Files:**
- `graybox-prototype/addons/gut/` (new)
- `graybox-prototype/project.godot` (plugin entry added)
- `graybox-prototype/test/unit/test_gut_setup.gd` (new)
- `graybox-prototype/test/unit/` (new)
- `graybox-prototype/test/integration/` (new)
- `docs/testing-guidelines.md` (new)
- `workflow/stages/testing/` (promoted from deferred)

---

## 2026-04-30: Slice 1 — Architectural Drift Fixes

**Problem:** A cold audit against the Architecture Constitution and Architecture Map found three drift items: a P5 implicit-tick violation in CameraRig, a misleading `_brain` field on BaseMotor (actually injected with the Broker), and `PlayerActionDebugContext` missing from the Architecture Map. G5 also lacked the GDScript-specific assert vs push_error guidance.

**Fix:**
- **1A (P5):** Added `set_process(false)` to `CameraRig._ready()`. `MovementBroker` now explicitly enables it on `_ready`, mirroring the existing `VisualsPivot` pattern.
- **1B (Naming):** Renamed `BaseMotor._brain: Node` → `_broker: MovementBroker`. Updated the injection site in `MovementBroker._ready()` and all six call sites in `auto_vault_motor`, `climb_motor`, `mantle_motor`, and `wall_jump_motor`. The Broker layer is now explicit in the type system.
- **1C (Map drift):** Added `PlayerActionDebugContext` row to `docs/architecture/ARCHITECTURE-MAP.md` Section 1.
- **1D (Constitution G5 amendment):** Clarified G5 to distinguish `assert()` (programmer-error invariants, stripped from release) from `push_error()` + early-return (runtime-reachable failures, survives release).

**Files:**
- `graybox-prototype/scripts/player_action_stack/camera/camera_rig.gd`
- `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd`
- `graybox-prototype/scripts/base/base_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/auto_vault_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/mantle_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/wall_jump_motor.gd`
- `docs/architecture/ARCHITECTURE-MAP.md`
- `docs/architecture/CONSTITUTION.md`

---

## 2026-04-29: Mantle Priority Refinement & Intent Debugging

**Problem:** The Mantle mechanic was unreliable: the manual trigger often failed, it couldn't reliably interrupt the sticky Climb state, and it suffered from regressions like automatic triggering and low-wall activation. Additionally, debugging input was difficult without visual feedback.

**Fix:**
- Refactored `MantleMotor.gd` to use the `FORCED` (3) priority category, ensuring manual Mantle requests successfully override the `OPPORTUNISTIC` (2) Climb state at wall ceilings.
- Restricted Mantle context strictly to `CLIMB` (manual) and `WALL_JUMP` (auto-grab) states.
- Re-introduced a `tall_enough` threshold (1.2m) to block unintended low-wall mantles while preserving the climb-to-mantle transition.
- Updated `MovementBroker.gd` telemetry to display active `Intents` (e.g., `[Jump] [Mantle]`) in the F1 debug panel for real-time verification.
- Adjusted `ClimbMotor.gd` to use `PLAYER_REQUESTED` (1) priority with specific weighting (5) to ensure deterministic arbitration against Mantle (weight 10).

**Files:**
- `graybox-prototype/scripts/player_action_stack/movement/motors/mantle_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd`

---

## 2026-04-29: Architectural Refactor & Constitution Compliance

**Problem:** The graybox-prototype violated several clauses of the Architecture Constitution (P1, P3, P5, P7) and lacked G5 boundary validations.

**Fix:** 
- Isolated engine input to `PlayerBrain` by implementing a `mouse_motion_received` signal, consumed by `CameraRig` for zero-latency rotation (P1).
- Delegated physics execution and rotation to individual motors. Moved `move_and_slide()` to all 12 motors and added `apply_locomotion_rotation()` helper to `BaseMotor` (P3, P7).
- Implemented explicit loop ownership for `VisualsPivot`, disabling it by default and enabling it through `MovementBroker` (P5).
- Added public boundary assertions to core classes (`BodyReader`, `StaminaComponent`, etc.) to enforce design contracts (G5).

**Files:**
- `graybox-prototype/scripts/player_action_stack/movement/player_brain.gd`
- `graybox-prototype/scripts/player_action_stack/camera/camera_rig.gd`
- `graybox-prototype/scripts/base/base_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd`
- `graybox-prototype/scripts/player_action_stack/movement/visuals_pivot.gd`
- `graybox-prototype/scripts/base/body_reader.gd`
- `graybox-prototype/scripts/base/locomotion_state_reader.gd`
- `graybox-prototype/scripts/player_action_stack/movement/stamina_component.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/*.gd` (12 files)

---

## 2026-04-29: Workflow Restructure & GitHub Prep

**Problem:** The file structure contained redundant layers (`.agent-utils/`), obsolete workflow artifacts (scripts, shared protocols, auto-export hooks), and branch-specific metadata that wasn't suited for a standalone GitHub repository.

**Fix:** 
- Consolidated all skill/agent content into `.agents/` and eliminated `.agent-utils/`.
- Promoted `stage-0` and `teacher` to first-class skills in `.agents/` and archived phase-0.
- Retired the auto-export paradigm and replaced it with a manual `/log-session` skill that appends directly to the changelog using session context.
- Embedded the Existing Artifact Protocol directly into the `start-stage` skill and deleted `workflow/shared/`.
- Repurposed `gdd_to_pdf.py` into a `.agents/gdd-to-pdf/` skill and deleted obsolete scripts and hooks.
- Standardized `.claude/skills/` as thin wrappers pointing to `.agents/` and mirrored them perfectly to `.gemini/skills/` to support both agents.
- Cleaned up the repository to be standalone by deleting `BRANCH-INFORMATION.md`, `PREREQUISITES.md`, and updating `README.md` and `.gitignore`.

**Files:**
- `.agents/` (created new structure, migrated skills)
- `.claude/skills/` (updated wrappers)
- `.gemini/skills/` (created mirror)
- `AGENTS.md`
- `README.md`
- `.gitignore`
- `.claude/settings.json`
- `workflow/shared/` (deleted)
- `workflow/scripts/` (deleted)
- `workflow/stages/phase-0/` (archived to legacy)
- `BRANCH-INFORMATION.md` (deleted)
- `PREREQUISITES.md` (deleted)

---

## 2026-04-29: Workflow Architecture Reform (Phase 1-3) & Slice Loop Adoption

**Problem:** The stage-based workflow in the graybox phase (graybox-2 through graybox-6) was too heavy. It required the implementing agent to parse 150KB+ of architecture documentation, leading to cognitive overload. Mechanics were often too large to be vertical slices, and the Auditor role operated post-implementation rather than intercepting bad plans.

**Fix:** Completely overhauled the architecture documentation and the implementation loop. 
- **Documentation Foundation (Phase 1):** Extracted invariants into a 13-clause `CONSTITUTION.md` and a compact `ARCHITECTURE-MAP.md`. Relocated the heavy cluster rationale docs (Stages 1-6) to `docs/architecture/rationale/` for reference only. Drafted operation playbooks (`add-a-motor.md`, `extend-intents.md`, `add-a-locomotion-state.md`).
- **Tooling (Phase 2):** Deprecated the graybox stages in favor of the **Slice Loop**. Created four core skills (`/slice-plan`, `/plan-eval`, `/implement-feature`, `/audit`) and a formal exception flow (`/constitution-violation`). Rewrote `AGENTS.md` to enforce the slice loop.
- **First Slice (Phase 3):** Validated the loop by executing the `transition-proposal-priority` slice, aligning the `TransitionProposal.Priority` enum to a robust 4-tier model without needing magic numbers in the Motors.

**Files Created/Moved:**
- `docs/architecture/CONSTITUTION.md`
- `docs/architecture/ARCHITECTURE-MAP.md`
- `docs/playbooks/` (3 playbooks)
- `.agent-utils/skills/` (slice-plan, plan-eval, implement-feature, audit, constitution-violation)
- `docs/slices/_template.md`
- `docs/architecture/rationale/` (moved old docs)
- `workflow/stages/legacy/` and `workflow/stages/deferred/` (reorganized old stages)

**Files Modified:**
- `AGENTS.md`
- `graybox-prototype/scripts/base/transition_proposal.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/walk_motor.gd`
- `graybox-prototype/scripts/player_action_stack/movement/motors/sneak_motor.gd`

---

## 2026-03-09 to 2026-04-24: Workflow Evolution (Archived Summary)

**March 2026 — Foundation**
The project started as a web+game shared workflow, migrated to a standalone game-only branch (2026-03-19), then underwent a major redesign: the engine was switched from Bevy to Godot, `feel` and `fusion` phases were added, and the `gameconcept` phase was expanded from 4 to 9 stages (2026-03-20). The graybox mechanic loop was upgraded from 6 to 9 design levels with a persistent design journal (2026-03-26), and a full artifact-reference audit fixed broken cross-stage paths left over from the redesign.

**Early April 2026 — Architecture and Tooling**
The `architecture` phase was created (6 stages: scope, data-flow, edge cases, systems, scaffold, interfaces) to bridge design and code (2026-04-14). `plan-eval` was added as an on-demand evaluator stage to catch bad plans before implementation, using cold-context evaluation (2026-04-09). Performance guidelines (`graybox-5`) became a dedicated stage; the three mechanic loop variants were merged into a single `graybox-6` (2026-04-02). The `PlayerInput` isolation pattern was generalized into the Godot Composition Pattern. Multiplayer support, asset format standards, and static typing enforcement were added to the workflow.

**Mid April 2026 — Polish and Infrastructure**
A repository-wide audit fixed stale stage names, broken artifact references, and misleading skill examples (2026-04-04, 2026-04-14, 2026-04-15). The `Common Techniques` library was indexed, enriched with Nintendo references and Godot 4.x code snippets for all 11 technique files (2026-04-04). The GDD template was formalized with an 8-section skeleton and image gallery, and a `gdd_to_pdf.py` export script was created (2026-04-15). The architecture phase stage files were updated to include DebugOverlay contracts and game-type-agnostic framing.

**Tldr:** March was engine choice + phase structure. Early April was adding architecture discipline and performance gates. Mid-April was cleanup, tooling, and documentation quality.
