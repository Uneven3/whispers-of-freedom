# Solutions: motor-api-fix-phase-enum

**Problem:** Commit `76de5cb` changed `LedgeService.get_ledge_facts()` to a zero-argument form but left callers in `auto_vault_motor.gd` and `climb_motor.gd` passing a stale `body_reader` argument, causing a GDScript arity crash on machines without a bytecode cache. The same commit omitted the `has_head_hit` field declaration from `LedgeFacts`. An independent audit also surfaced two architectural violations in the same files: a G2 boolean-pair encoding a 3-state machine in `AutoVaultMotor`, and a stale temporal `_last_climb_normal` fallback in `ClimbMotor` that can false-positive on flat ground.
**Status:** Draft

---

## Solution 1: Minimal Surgical Fix

**Approach:**
Strip the `body_reader` argument at all three call sites (`auto_vault_motor.gd` ×2, `climb_motor.gd` ×1) and add the missing `has_head_hit: bool` declaration to `LedgeFacts`. Touch nothing else. The G2 enum conversion and the `_last_climb_normal` refactor are deferred as separate slices because they carry independent risk profiles and can be reviewed in isolation.

**Architecture Map Target:**
Motor layer (`AutoVaultMotor`, `ClimbMotor`), Data layer (`LedgeFacts`).

**Constitution Clauses at Risk:**
- G2 (deferred): Boolean flag soup in `AutoVaultMotor` remains until a follow-up slice.
- P4 (deferred): `_last_climb_normal` temporal state in `ClimbMotor` remains.

**Tradeoffs:**
- Pro: Smallest possible diff; easiest to review and revert if something unexpected breaks.
- Pro: Immediately unblocks fresh-machine builds with zero architectural side-effects.
- Con: Leaves two confirmed G2/P4 violations in the codebase for a follow-up slice, increasing the risk of another auditor flag.
- Con: The boolean pair in `AutoVaultMotor` can mutate into a genuine bug if a third contributor adds another boolean without reading the context.

**Edge Cases:**
- `_begin_vault()` reads `ledge.get_ledge_facts()` a second time inside `tick()`; both call sites must be updated or the second call still crashes.
- The `LedgeFacts.has_head_hit` field is already consumed in `climb_motor.gd` and `ledge_service.gd` — a missing declaration produces a silent ZERO value in GDScript 4 (not a crash), so this fix is correctness-only, not a crash fix.
- If `MockLedgeService` in `test_edge_leap_motor.gd` had an old `get_ledge_facts(_br)` signature, it would shadow the parent and prevent the crash but still be wrong — the mock signature must also be updated.

---

## Solution 2: Crash Fix + Phase Enum + Spatial Climb Guard

**Approach:**
Fix the `get_ledge_facts()` call-site arity and add `has_head_hit` to `LedgeFacts`, then also convert `AutoVaultMotor`'s `_is_vaulting`/`_just_activated` boolean pair to a proper `enum Phase { INACTIVE, ACTIVATING, RUNNING }` (G2 fix), and replace `ClimbMotor`'s stale `_last_climb_normal` temporal fallback with an authoritative spatial check: `on_floor and not facts.has_head_hit and facts.ledge_point != Vector3.ZERO`. All four issues resolved in one atomic commit because they all touch the same files and are logically cohesive — the spatial guard directly uses the newly declared `has_head_hit` field.

**Architecture Map Target:**
Motor layer (`AutoVaultMotor`, `ClimbMotor`), Data layer (`LedgeFacts`).

**Constitution Clauses at Risk:**
- G2: Replacing bool pair with enum in `AutoVaultMotor` — risk is low; the enum states map 1-to-1. Guard: verify `on_activate` sets `Phase.ACTIVATING`, `on_deactivate` sets `Phase.INACTIVE`, and `_begin_vault` sets `Phase.RUNNING`.
- P4: Removing `_last_climb_normal` field from `ClimbMotor` — the temporal fallback was the only consumer; removing it means the motor returns early when `get_climb_normal()` briefly returns ZERO at wall seams. Guard: add comment explaining why the early-return is safe (the Broker re-evaluates `gather_proposals` next frame).

**Tradeoffs:**
- Pro: Resolves all four confirmed violations in one reviewable diff; the `has_head_hit` field and the spatial guard are interlinked, so splitting them would require two separate slices with a data dependency.
- Pro: The enum and spatial guard are mechanically simpler than the boolean pair they replace — lower total cognitive load after the diff.
- Con: Larger diff increases review surface; a reviewer must understand both the Phase state machine and the spatial-vs-temporal substitution at the same time.
- Con: Removing `_last_climb_normal` introduces a brief single-frame normal loss at wall seams — playtest needed to confirm no perceptible stutter.

**Edge Cases:**
- Wall seam crossing: when `get_climb_normal()` returns ZERO for one frame at a concave seam, the motor now returns early instead of using the stale normal. The Broker re-enters `FALL` or stays in `CLIMB` depending on `gather_proposals` next frame — net effect is one frame of zero velocity, not a mode flip, because the sticky `OPPORTUNISTIC` proposal in `gather_proposals` keeps `CLIMB` active.
- Flat-ground false positive: `_last_climb_normal` could persist from a previous climb session (normal not yet zeroed) and cause the motor to output climb velocity on flat ground. The spatial guard eliminates this class of bug entirely.
- `on_deactivate` now clears `_last_climb_normal` to `ZERO` — this is vestigial with the spatial guard but harmless; it can be removed in a follow-up cleanup.

---

## Solution 3: Crash Fix + Phase Enum + Dedicated ClimbContext Service

**Approach:**
Fix the call-site arity and `has_head_hit` declaration (same as Solutions 1/2), convert `AutoVaultMotor` to use the `Phase` enum (same as Solution 2), then go further: extract the climb-normal persistence logic into a new `ClimbContextService` that tracks `current_normal`, `near_apex: bool`, and `can_continue: bool` as pre-computed facts, cached by `update_facts(body_reader)`. `ClimbMotor` reads these cached fields instead of calling `LedgeService` methods directly, which fully satisfies P4 (readers for cross-system reads). `LedgeService` methods (`get_climb_normal`, `can_climb`, `can_continue_climbing`) become `ClimbContextService` delegators or are deprecated.

**Architecture Map Target:**
Motor layer (`AutoVaultMotor`, `ClimbMotor`), Service layer (new `ClimbContextService`), Data layer (`LedgeFacts`, new `ClimbFacts`).

**Constitution Clauses at Risk:**
- G1: `ClimbContextService` is a new script — must stay focused on climb-context pre-computation only; no overlap with `LedgeService` vault/mantle concerns.
- G3: `ClimbContextService.update_facts` is called by the Broker via `BaseService` contract — this is correct; no sideways access.
- P4: Correctly resolved — `ClimbMotor` holds a `ClimbContextService` reference (same-system reader), satisfying the reader pattern. However, `LedgeService` and `ClimbContextService` would share underlying raycast nodes, creating an implicit coupling that violates G1 unless the raycasts are owned by one service and lent to the other.
- G2: Fully resolved (enum + pre-computed facts, no boolean soup).

**Tradeoffs:**
- Pro: Maximum architectural clarity — climb-context state has a single declared home; future Combat/Form motors can read climb context without depending on `LedgeService`.
- Pro: Fully satisfies P4 and G1 for climb-related data flow.
- Con: Significantly larger scope — introduces a new class, new `ClimbFacts` data carrier, and refactors `ClimbMotor` in ways that go well beyond the crash fix. High risk of introducing regressions in a file that was just stabilized.
- Con: Shared raycast node ownership between `LedgeService` and `ClimbContextService` is architecturally unresolved without further design work (violates G3 if `ClimbContextService` calls into `LedgeService`).

**Edge Cases:**
- If `ClimbContextService.update_facts` runs after `LedgeService.update_facts` in the same frame, the climb normal is always one frame behind the vault/mantle facts — the Broker's service update order must be documented and enforced.
- `LedgeService.can_climb()` is consumed by `ClimbMotor.gather_proposals`; delegating it through `ClimbContextService` adds a call chain that the Broker's service-array iteration doesn't guarantee will execute in order.
- Deprecating `LedgeService.get_climb_normal()` breaks `EdgeLeapMotor` which also calls it — requires updating that motor in the same PR or using a transitional shim.

---

## Chosen Solution

**Selected:** Solution 2 — Crash Fix + Phase Enum + Spatial Climb Guard
**Rationale:** All four confirmed violations (call-site arity, missing `has_head_hit` declaration, G2 boolean-pair in AutoVaultMotor, stale temporal `_last_climb_normal` in ClimbMotor) are logically cohesive and touch the same files. Resolving them atomically avoids a cascading sequence of slices with data dependencies between them. The spatial guard directly uses the newly declared `has_head_hit` field, making the two changes inseparable at the correctness level. Solution 1 defers two confirmed violations, increasing future audit risk. Solution 3 introduces unnecessary scope (new service, new data carrier) that would require resolving shared raycast ownership — out of proportion to the problem.
