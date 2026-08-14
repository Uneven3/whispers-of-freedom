# Slice Plan: Climb Wall Height Gate

## Goal
Replace the current `_detect_climb` gate (`waist_hit AND (head_hit OR _mantle_ledge_point != ZERO)`) with a three-ray simultaneous contact requirement (`knee_hit AND waist_hit AND head_hit`). This eliminates the `_mantle_ledge_point` fallback that allowed short walls — detectable only by the downward cast — to trigger climb entry erroneously.

## Architecture Map Target
Service (`LedgeService`) — `_detect_climb` private method and its call site in `update_facts`.

## Constitution Clauses Involved
- **G2 (Single Source of Truth):** `_can_climb` must remain written only inside `_detect_climb`. The change must not copy the gate condition anywhere else. The `_mantle_ledge_point` removal from `_detect_climb` eliminates the existing cross-method read-order dependency.
- **P3 (SSoT writers):** No new writers for `_can_climb`. The refactor touches only the condition inside the sole existing writer.
- **G5 (Boundary validation):** No public surface is being changed; internal logic change. No new asserts required, but the existing `rad_to_deg` angle guard inside `_detect_climb` must be preserved.

## Playbooks Referenced
None.

## File Touches

- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`:
  - In `update_facts`: extract `knee_hit = hits[1]` alongside the existing `waist_hit = hits[2]` and `head_hit = hits[5]` extractions. Pass `knee_hit` as a new argument to `_detect_climb`.
  - Change `_detect_climb` signature from `(facing, waist_hit, head_hit, pos)` to `(facing, knee_hit, waist_hit, head_hit, pos)`.
  - Inside `_detect_climb`: replace the inner condition `if head_hit or _mantle_ledge_point != Vector3.ZERO` with `if knee_hit and head_hit`. The outer `if waist_hit` guard and the angle check remain unchanged. The `_update_lateral_walls(pos)` call remains inside the now-narrower gate.

- `graybox-prototype/test/unit/test_ledge_facts.gd`:
  - No change required. `LedgeFacts` data class is not modified.

- `graybox-prototype/test/unit/test_edge_leap_motor.gd` *(check only)*:
  - Verify no test directly instantiates or stubs `_detect_climb`; if so, update the stub call signature. No functional change expected.

## Pre-implementation Checklist
- [x] `_detect_climb` is the only place that writes `_can_climb`; confirm no other path sets it before changing the condition.
- [x] The `_mantle_ledge_point != Vector3.ZERO` expression is removed **only** from `_detect_climb`; `_detect_mantle` still sets `_mantle_ledge_point` independently and other consumers (mantle motor, `get_ledge_facts`) are unaffected.
- [x] `knee_hit` is sourced from `hits[1]` (index 1 of `_h_offsets`, offset −0.6 m, labeled "Knee" in the `_detect_vault` comment) — confirm index before writing.
- [x] `update_facts` call order is preserved: `_detect_vault` and `_detect_mantle` fire before `_detect_climb`; the new gate does not read `_mantle_ledge_point`, so order no longer matters for `_detect_climb` — still keep order stable to avoid confusing future auditors.
- [x] No new `@export` variable is introduced; this is a pure code-path change.
- [x] GDScript syntax verified: `if knee_hit and head_hit` (lowercase `and`, consistent with existing style in this file).
