# Slice Plan: Motor API Fix — Phase Enum + Climb Guard

## Goal
Fix the remaining confirmed architectural violations surfaced by commit `76de5cb`: remove the stale `_last_climb_normal` temporal fallback from `ClimbMotor` (G2 — stale duplicate state), update the two existing tests that reference the now-removed field, and extend the `LedgeFacts` and `ClimbMotor` test suites to cover the `has_head_hit` field and the spatial climb guard respectively. The call-site arity crash, `has_head_hit` field declaration, and `AutoVaultMotor` Phase enum are already correct at HEAD and are confirmed-done.

## Architecture Map Target

Motor layer (`ClimbMotor`), Data layer (`LedgeFacts`), Test layer (`test_climb_motor.gd`, `test_ledge_facts.gd`, `test_edge_leap_motor.gd`).

## Constitution Clauses Involved

- **G2** (primary): `_last_climb_normal` is a duplicate of `LedgeService._climb_normal` — removing it closes the only confirmed G2 stale-state violation in `ClimbMotor`. When `get_climb_normal()` returns `ZERO` at a wall seam apex, `tick()` returns early; the OPPORTUNISTIC proposal emitted by `gather_proposals` keeps the Broker in `CLIMB` mode for that frame — no mode flip, one frame of zero velocity at worst.
- **G2** (soft signal, do not fix): The `near_apex` formula is duplicated in `gather_proposals` and `tick`. Leave a one-line comment in each location flagging the duplication; do NOT extract a helper function (unnecessary abstraction at this scale).
- **P4** (resolved upstream): `_last_climb_normal` was the field that created a stale temporal reader; its removal is the P4 fix.

## Playbooks Referenced

None.

## File Touches

- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_facts.gd`
  - **No functional changes required** — `has_head_hit` is already declared at HEAD.
  - Add `has_wall_left` and `has_wall_right` default-value assertions to `test_ledge_facts.gd` (see test file below); this file itself needs no edits.

- `graybox-prototype/scripts/player_action_stack/movement/motors/auto_vault_motor.gd`
  - **No changes required** — `enum Phase { INACTIVE, ACTIVATING, RUNNING }` and all three Phase transitions are already correct at HEAD. File is touched only to confirm it is in the auditable-correct state.

- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`
  - **Remove** `var _last_climb_normal: Vector3 = Vector3.ZERO` (field declaration, line 12).
  - **Remove** the fallback block in `tick()` that reads `_last_climb_normal`:
    ```
    if climb_normal != Vector3.ZERO:
        _last_climb_normal = climb_normal
    elif _last_climb_normal != Vector3.ZERO:
        climb_normal = _last_climb_normal
    ```
    The `if climb_normal == Vector3.ZERO: return` guard that follows remains — it is the correct early-return.
  - **Remove** the `on_deactivate` method entirely (its sole body was `_last_climb_normal = Vector3.ZERO`).
  - **Add one-line comment** above the `near_apex` line in `tick()` flagging that the formula is duplicated in `gather_proposals` — do not extract a helper.
  - The spatial guard (`on_floor and not facts.has_head_hit and facts.ledge_point != Vector3.ZERO`) already exists in both `gather_proposals` and `tick` at HEAD; no change needed to that logic.

- `graybox-prototype/test/unit/test_edge_leap_motor.gd`
  - `MockLedgeService.get_ledge_facts()` already uses the zero-argument signature at HEAD — no change needed.
  - **Confirm** (no edit required) that no test in this file references `_last_climb_normal`.

- `graybox-prototype/test/unit/test_climb_motor.gd` (file already exists)
  - **Remove** `_motor._last_climb_normal = Vector3.BACK` assignment from `test_gather_proposals_climbing_the_air_regression()` — the field no longer exists.
  - **Remove** `_motor._last_climb_normal = Vector3.BACK` assignment from `test_gather_proposals_stays_climbing_at_apex_on_floor()` — the field no longer exists.
  - The test assertions remain unchanged; the tests validate `gather_proposals` behaviour that depends on `ledge.mock_facts.ledge_point` and `ledge.mock_facts.has_head_hit`, not on the removed field.
  - **Add** `test_tick_early_returns_when_climb_normal_zero()`: configure `MockLedgeService.mock_normal = Vector3.ZERO`, call `tick(0.1, intents, _body, _stamina, _services)`, assert `_body.velocity == Vector3.ZERO` (motor returned early without writing velocity).

- `graybox-prototype/test/unit/test_ledge_facts.gd`
  - **Extend** `test_default_values()` to assert `has_wall_left` defaults to `false` and `has_wall_right` defaults to `false` (currently missing from the test, already correct in the data carrier).

## Pre-implementation Checklist

- [x] `_last_climb_normal` field declaration removed from `climb_motor.gd`
- [x] Fallback block (`if climb_normal != ZERO / elif _last_climb_normal`) removed from `tick()`
- [x] `on_deactivate` method removed from `climb_motor.gd` (was the sole consumer of the field)
- [x] One-line duplication comment added above `near_apex` in `tick()` — no helper extracted
- [x] `test_climb_motor.gd`: both `_motor._last_climb_normal` assignments removed
- [x] `test_climb_motor.gd`: `test_tick_early_returns_when_climb_normal_zero` added
- [x] `test_ledge_facts.gd`: `has_wall_left` and `has_wall_right` default assertions added
- [x] `test_edge_leap_motor.gd`: confirmed no changes needed (already correct)
- [x] `auto_vault_motor.gd`: confirmed no changes needed (already correct)
- [x] `ledge_service.gd`: NOT touched (already correct at HEAD, per scope constraint)
- [x] GDScript syntax verified for every changed file
