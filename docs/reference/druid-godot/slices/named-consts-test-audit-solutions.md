# Solutions: named-consts-test-audit

**Problem:** Inline numeric literals scattered through motor and service method bodies obscure their purpose, violating G5's intent-communication requirement. Separately, the existing unit test suite needs a signal-to-noise classification so future maintainers know which tests are worth preserving under refactors.
**Status:** Draft

---

## Solution 1: Inline const Declarations Per File

**Approach:**
For each in-scope file, declare a `const` immediately below the `@export` block (or at top of the class if no exports exist) for every unnamed literal found in method bodies. The constant lives in the same file as its consumer — no cross-file sharing. `@export` vars and already-named `const`s are left untouched. The test classification is delivered as a plain comment block at the top of each test file (`## SIGNAL: high / mixed / low — <one sentence reason>`).

**Architecture Map Target:**
Motors (WallJumpMotor, EdgeLeapMotor, SneakMotor, FallMotor, LadderMotor, StairsMotor), Service (LedgeService), Brain (PlayerBrain). Test files annotated in-place.

**Constitution Clauses at Risk:**
- G5 — this solution directly addresses G5 by naming every literal's intent; risk is that a poorly chosen name still fails to communicate intent (mitigated by requiring intent-first naming, e.g., `BODY_HALF_HEIGHT` not `HALF_H`).
- G1 — adding many `const` blocks to already-long files could push line counts higher; soft signal only since these are pure declarations, not logic.

**Tradeoffs:**
- Pro: Zero structural change — a reader sees the constant right above the method that uses it; each file is self-contained with no import dependency added.
- Pro: Minimal diff — one block of `const` lines per file; trivially reviewable and reversible.
- Con: Same logical constant may be named and valued slightly differently across files (e.g., `BODY_HALF_HEIGHT = 1.0` in WallJumpMotor vs. `CAPSULE_HALF_HEIGHT = 1.0` already in StairsMotor) — not a G5 violation but creates mild inconsistency.
- Con: Does not surface whether values are intentionally divergent or accidental duplicates; reader must still cross-reference.

**Edge Cases:**
- `wall_jump_motor.gd` line 49: `1.0` ("Keep contact" normal push) and line 78: `0.33` ("ledge_top_offset") are already described by inline comments — the const names must match or improve on those comments, not contradict them.
- `ledge_service.gd` line 47: array literal `[-0.8, -0.6, -0.2, 0.2, 0.4, 0.6]` — these are cast offsets keyed to body anatomy; extracting into a separate named const is warranted but must remain ordered (ankle through head) or the index-based `hits[1]` / `hits[5]` logic silently breaks.
- `sneak_motor.gd` line 11: `_original_height: float = 2.0` is an instance variable default (fallback for when `CollisionShape3D` is absent), not a method-body literal — it sits in the wrong category and should be handled as a named const `FALLBACK_CAPSULE_HEIGHT` only if it appears in a method body calculation; as a var default it is a lower priority.

---

## Solution 2: Shared Constants Resource Per Layer

**Approach:**
Create a new `MotorConstants` GDScript class (a plain `const`-only file, no node, no `extends`) and a matching `ServiceConstants` file. Each in-scope motor imports the relevant class and replaces its literals with fully-qualified references (`MotorConstants.BODY_HALF_HEIGHT`). The test classification is an entry in a new `docs/test-quality-register.md` table rather than inline comments.

**Architecture Map Target:**
A new shared-constants layer sitting below Motors and Services (no Architecture Map row today — would require a map amendment).

**Constitution Clauses at Risk:**
- G6 — introducing a new shared constants file is not an inheritance violation, but the Architecture Map has no row for it; adding it without a map amendment is itself a documentation gap.
- P4 — motors reading from a shared constant file is not a cross-system reader violation (it is a pure data resource), but the pattern could be misread as a sideways access if the reviewer is strict.
- G5 — still fully addressed by naming every literal.

**Tradeoffs:**
- Pro: Single canonical value for shared physics constants (`BODY_HALF_HEIGHT`, gravity settings); inconsistency between files is impossible.
- Pro: Grep-able: all motor tuning constants appear in one place.
- Con: Requires creating new files, which the scope summary explicitly prohibits ("no new files").
- Con: Changes every call site from a simple `1.0` to `MotorConstants.BODY_HALF_HEIGHT`, which is verbose if the constant is only used once in one file.

**Edge Cases:**
- `StairsMotor` already defines `CAPSULE_HALF_HEIGHT` and `CAPSULE_RADIUS` as local consts — these would need to migrate to the shared resource or remain local, creating the exact duplication the solution aims to eliminate.
- A `MotorConstants` resource cannot be `@export`-ed from a scene, so designer-tunable values must stay as `@export` vars in each motor; the boundary between "tunable" and "fixed geometry" needs explicit policy.
- If `MotorConstants` is ever changed, all motors referencing it hot-reload simultaneously in the editor — a desirable property in production but potentially surprising during iterative tuning sessions.

---

## Solution 3: Const Extraction Plus Inline Test Signal Comments

**Approach:**
Identical to Solution 1 for the const extraction portion (per-file `const` blocks, no new files). For the test classification, instead of annotating test files with a comment header, produce the analysis as a structured section in this solutions document (and surfaced to the Reviewer via the solutions doc itself) — zero changes to test files. The rationale is that test files are run artefacts; adding meta-commentary to them risks confusing the test runner or future contributors who mistake the comment for a test description.

**Architecture Map Target:**
Motors, Service, Brain (same as Solution 1). Test classification lives in docs only.

**Constitution Clauses at Risk:**
- G5 — same direct address as Solution 1.
- G1 — same soft risk as Solution 1.
- No additional risks compared to Solution 1.

**Tradeoffs:**
- Pro: Test files remain pure test code; the classification is durable in the docs slice artifact where it is less likely to be accidentally deleted during a test-file rewrite.
- Pro: Analysis can be richer (table form with columns: file, test name, classification, reason) without GDScript comment formatting constraints.
- Con: The classification is one extra layer removed from the code it describes — a reader looking at `test_ledge_facts.gd` must know to look in the docs slice for the signal rating.
- Con: If a test file is later refactored, the docs classification drifts out of sync silently (no enforcement mechanism).

**Edge Cases:**
- `test_ledge_facts.gd::test_default_values` hard-codes the literal `1.4` for `detection_range` — if `LedgeFacts` changes its default, this test will catch the regression, but the value `1.4` in the test has no named constant backing it, creating a dual-maintenance point (fixed by noting this in the analysis, not by changing the test per scope rules).
- `test_gut_setup.gd` is not yet read — if it contains structural boilerplate checks only, it is the clearest "low signal" candidate and should appear in the classification table.
- `test_climb_motor.gd::test_tick_near_apex_logic` uses `PI` and `0.01` (delta) directly — the `0.01` is a test fixture constant, not production code, so it is explicitly out of scope for const extraction but relevant for the signal classification (does the test actually validate a threshold?).

---

## Test Signal Classification (all solutions share this analysis)

| File | Test Name | Classification | Rationale |
|---|---|---|---|
| `test_intents.gd` | `test_default_values` | Low signal | Verifies field defaults hardcoded in the struct; will only catch a typo in the declaration, not a real behavioral regression. |
| `test_intents.gd` | `test_semantic_getters` | High signal | Validates the `wish_dir → is_climbing_left / is_moving_forward` semantic mapping; a future Intents refactor that breaks the mapping would be caught here. |
| `test_intents.gd` | `test_field_assignment` | Low signal | Round-trip write-then-read on a plain data struct — no logic exercised. |
| `test_intents.gd` | `test_reset_clears_all_fields` | Mixed | Validates `reset()` zeroes every field; useful as a completeness check when fields are added, but adds no behavioral assertion. |
| `test_ledge_facts.gd` | `test_default_values` | Low signal | Same pattern as `test_intents::test_default_values`; also hard-codes `1.4` which couples the test to the implementation default rather than the named constant. |
| `test_ledge_facts.gd` | `test_field_assignment` | Low signal | Plain struct round-trip; no logic path exercised. |
| `test_stamina_component.gd` | `test_default_values` | Low signal | Validates initial values — informative but not regression-catching for behavior. |
| `test_stamina_component.gd` | `test_drain_reduces_stamina` | High signal | Verifies drain amount, signal emission, and clamped current value in one assertion chain — catches arithmetic bugs and missing signal wires. |
| `test_stamina_component.gd` | `test_drain_clamps_at_zero` | High signal | Boundary condition on overdrain; catches clamping logic regressions. |
| `test_stamina_component.gd` | `test_recover_increases_stamina` | High signal | Mirror of drain; validates signal emission on recovery path. |
| `test_stamina_component.gd` | `test_recover_clamps_at_max` | High signal | Upper-bound boundary; catches over-recovery bugs. |
| `test_stamina_component.gd` | `test_get_normalized` | High signal | Validates the normalized ratio at two different levels including zero; catches division-by-zero regressions. |
| `test_stamina_component.gd` | `test_is_exhausted` | Mixed | Redundant with `test_drain_clamps_at_zero` — same state reached twice; retains value only as a named semantic test. |
| `test_transition_proposal.gd` | `test_init_assigns_values` | Mixed | Validates constructor parameter binding; not purely structural (the binding is non-trivial) but catches only authoring errors, not behavioral regressions. |
| `test_transition_proposal.gd` | `test_init_defaults` | Low signal | Verifies default argument values — will only catch a default value change, not logic. |
| `test_edge_leap_motor.gd` | `test_gather_proposals_triggers_at_left_edge` | High signal | Validates the exact precondition combination (CLIMB mode + wants_jump + no wall left) that gates EDGE_LEAP entry; catches future gather_proposals logic regressions. |
| `test_edge_leap_motor.gd` | `test_gather_proposals_does_not_trigger_when_wall_continues` | High signal | Negative case for the above; ensures WallJumpMotor space is preserved when wall continues — a regression here would cause visual glitch of leaping mid-wall. |
| `test_edge_leap_motor.gd` | `test_tick_applies_impulse_and_drains_stamina` | High signal | Validates tick side-effects (non-zero velocity, stamina drain); structural enough to catch wiring bugs but not a full physics assertion. |
| `test_player_brain_toggle.gd` | `test_climb_toggle` | High signal | End-to-end toggle on/off via real InputEventAction; catches the climb toggle state machine behavior. |
| `test_player_brain_toggle.gd` | `test_climb_reset_on_wall_jump_away` | High signal | Covers the critical lateral-vs-neutral disambiguation in wall jump exit; regression here means player loses wall-grab intent incorrectly. |
| `test_player_brain_toggle.gd` | `test_climb_stays_on_wall_jump_lateral` | High signal | Positive counterpart; player should retain climb intent when jumping laterally. |
| `test_player_brain_toggle.gd` | `test_climb_reset_on_wall_jump_back` | High signal | Third direction case (backward); distinct behavioral branch from neutral/lateral. |
| `test_player_brain_toggle.gd` | `test_climb_reset_on_mantle` | High signal | Validates MANTLE exit clears climb toggle — necessary for the mantle→walk flow. |
| `test_player_brain_toggle.gd` | `test_climb_reset_on_edge_leap` | High signal | Validates EDGE_LEAP exit clears climb toggle; added after the EdgeLeapMotor implementation. |
| `test_player_brain_toggle.gd` | `test_climb_reset_on_auto_vault` | High signal | Validates AUTO_VAULT exit clears climb toggle. |
| `test_player_brain_toggle.gd` | `test_climb_stays_on_jump` | High signal | Floor jump should NOT clear toggle — player may jump then grab; a regression here breaks the jump-to-grab flow entirely. |
| `test_climb_motor.gd` | `test_gather_proposals_climbing_the_air_regression` | High signal | Named regression test for a specific bug (climbing air on flat ground); highest-value test in the suite. |
| `test_climb_motor.gd` | `test_gather_proposals_stays_climbing_at_apex_on_floor` | High signal | Counter-case to the above regression — apex condition must not be suppressed by is_on_floor(). |
| `test_climb_motor.gd` | `test_tick_near_apex_logic` | High signal | Validates basis-alignment suppression at apex; catches any future refactor that erroneously re-enables yaw-snap at the top of a wall. |

## Inline Literal Inventory (all in-scope files)

### wall_jump_motor.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 21, 24 | `5` (override_weight) | `FORCED_WEIGHT` | Arbitration weight for FORCED wall-jump proposals |
| 49 | `1.0` (normal push) | `WALL_CONTACT_PUSH` | Keeps minimal wall contact during upward jump |
| 51 | `0.4` (UP mix for away dir) | `AWAY_UP_BLEND` | Vertical component of the away-leap direction |
| 52, 65 | `3.5` (away speed) | `AWAY_LEAP_SPEED` | Horizontal magnitude of away/downward leap |
| 52, 65 | `4.0` (normal push speed) | `AWAY_NORMAL_PUSH` | Wall-normal push on away leap |
| 55, 60 | `0.8` (lateral speed fraction) | `LATERAL_SPEED_FRACTION` | Lateral jumps at 80% of up-impulse |
| 56, 61 | `0.5` (minimal vertical) | `LATERAL_VERTICAL_LIFT` | Minimal y-velocity on lateral wall jumps |
| 57, 62 | `0.5` (normal retraction) | `LATERAL_NORMAL_RETRACTION` | Slight push away from wall on lateral jump |
| 64 | `0.4` (UP mix, identical to line 51) | `AWAY_UP_BLEND` | Same constant, second use site |
| 76 | `1.0` (body_half_height) | `BODY_HALF_HEIGHT` | Half-height for feet-y calculation |
| 78 | `0.33` (ledge_top_offset) | `LEDGE_TOP_OFFSET` | Clearance above lip to stop upward velocity |

### edge_leap_motor.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 34, 38 | `10` (override_weight) | `FORCED_WEIGHT` | Arbitration weight; higher than wall_jump to win on edge |
| 69 | `2.0` (normal push) | `WALL_PUSH_SPEED` | Away-from-wall component of leap velocity |

### ledge_service.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 47 | `[-0.8, -0.6, -0.2, 0.2, 0.4, 0.6]` | `H_CAST_Y_OFFSETS` | Body-anatomy cast heights (ankle→head); already a var `_h_offsets` but unnamed at declaration |
| 56 | `0.1` (down_cast margin) | `DOWN_CAST_MARGIN` | Small clearance added to max height for down cast positioning |
| 57 | `1.0` (Z offset for down_cast) | `DOWN_CAST_FORWARD_OFFSET` | Places downcast 1 m forward of body |
| 62 | `0.2` (vault_landing_cast margin) | `VAULT_LANDING_CAST_MARGIN` | Extra clearance for vault landing cast |
| 65, 67 | `0.5` (lateral cast y_offset) | `LATERAL_CAST_Y_OFFSET` | Waist-height origin for left/right wall raycasts |
| 73 | `0.1` (sphere radius) | `FORWARD_CAST_SPHERE_RADIUS` | Radius of horizontal profiling cast spheres |
| 91 | `0.1` (sphere radius, down cast) | `DOWN_CAST_SPHERE_RADIUS` | Radius of vertical detection cast spheres — same value as FORWARD_CAST_SPHERE_RADIUS, could unify |
| 120 | `1.0` (forward offset in update_facts) | `FORWARD_SAMPLE_OFFSET` | Down-cast placement 1 m in front of player |
| 127 | `0.2` (vault dist margin) | `VAULT_DIST_MARGIN` | Extra buffer past min wall contact distance for vault downcast |
| 173 | `0.75` (steep angle threshold) | `STEEP_FACE_NORMAL_Y_MAX` | Faces with normal.y < this are steep enough to be obstacles (≈cos(41°)) |
| 255 | `1.5` (vault forward distance multiplier) | `VAULT_FORWARD_RADIUS_MULT` | Vault target placed 1.5× body radius forward of wall contact |

### sneak_motor.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 11 | `2.0` (default `_original_height`) | `FALLBACK_CAPSULE_HEIGHT` | Fallback for when CollisionShape3D is absent; not used in any method body calculation — borderline candidate; include for completeness |
| 50 | `0.01` (move_dir length_sq threshold) | `MOVE_DIR_THRESHOLD_SQ` | Minimum squared length to treat move_dir as non-zero for rotation |
| 52 | `10.0` (slerp speed) | `ROTATION_SLERP_SPEED` | Speed of body basis rotation toward movement direction |
| 55 | `5.0` (stamina recovery rate) | `SNEAK_STAMINA_RECOVER_RATE` | Stamina recovered per second while sneaking |

### fall_motor.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 36 | `0.25` (stamina recover fraction) | `FALL_STAMINA_RECOVER_FRACTION` | Stamina recovery while falling is 25% of the per-second rate |

### ladder_motor.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 13 | `0.01` (move_dir length_sq threshold) | `MOVE_DIR_THRESHOLD_SQ` | Same threshold as sneak_motor; consistent value |
| 36 | `0.1` (top exit clearance) | `LADDER_TOP_EXIT_CLEARANCE` | How close to ladder top triggers the exit bump |

### stairs_motor.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 75 | `0.01` (input length_sq threshold) | `INPUT_THRESHOLD_SQ` | Minimum squared length to count world_input as non-zero (already-named ASCEND_THRESHOLD / DESCEND_THRESHOLD handle the slope gate; this is the general input gate) |
| 88–89 | `0.3`, `-0.3` (ASCEND_THRESHOLD, DESCEND_THRESHOLD) | already named as local `const` inside `tick` — compliant, no change needed | — |

### player_brain.gd
| Line | Literal | Proposed Name | Rationale |
|---|---|---|---|
| 34 | `0.5` (wish_dir x positive threshold) | `WISH_DIR_THRESHOLD` | Minimum input axis value to register as a discrete directional intent |
| 35 | `-0.5` (wish_dir x negative threshold) | (reuse `WISH_DIR_THRESHOLD` with negation) | Same magnitude, opposite sign |
| 38 | `-0.5` (wish_dir y forward threshold) | (reuse `WISH_DIR_THRESHOLD`) | Same magnitude |
| 39 | `0.5` (wish_dir y back threshold) | (reuse `WISH_DIR_THRESHOLD`) | Same magnitude |

---

## Chosen Solution

**Selected:** Solution 3 — Const Extraction Plus Inline Test Signal Comments
**Rationale:** Solution 3 shares all the structural benefits of Solution 1 (per-file `const` blocks, zero new files, trivially reversible diff) while keeping test files free of meta-commentary that would pollute the test runner output or confuse contributors. The test signal classification belongs in the docs layer — it is architectural knowledge, not test logic. The documented indirection risk (reader must look in the solutions doc for the rating) is acceptable: the classification table already lives here, was produced alongside the slice, and is the natural place for reviewers to consult when evaluating test coverage. Solution 2 was ruled out because the solutions doc itself flags "no new files" as a hard scope constraint. Solution 1 was superseded by Solution 3 on the test-classification dimension alone — the const extraction approach is identical.
