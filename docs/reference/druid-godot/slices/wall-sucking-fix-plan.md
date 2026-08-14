# Slice Plan: Wall-Sucking Fix

## Goal
Fix the wall-sucking artifact in ClimbMotor caused by `_waist_cast` and `_head_cast` in LedgeService detecting walls 0.5 units before the player capsule makes contact (cast reach = 1.0 unit, capsule radius = 0.5 units). The `wall_stick` velocity in ClimbMotor then takes ~1 second to close that 0.5-unit gap, producing a visible "suck" toward the wall. Constrain forward-cast reach to 0.6 units (capsule radius 0.5 + 0.1 buffer) so climb activates only when the capsule is already touching or nearly touching the wall.

## Architecture Map Target
Extends an existing Service: `LedgeService` (`graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`). No new nodes, motors, or services. A single tuning export is added and two `target_position` assignments in `update_facts()` are changed.

## Constitution Clauses Involved
- **G5** (Boundary validation communicates intent) — the new export is a designer-facing tuning knob; no validation is required on it (positive float, designer is responsible), but the existing pattern of other `@export` floats in the file is consistent and this fits without change.
- No other clauses are at risk. This is an intra-Service, intra-method change with no cross-system surface changes.

## Playbooks Referenced
None applicable.

## File Touches
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`:
  - Add `@export var wall_detection_reach: float = 0.6` to the exports block (after the last existing `@export` line, before the `var _can_climb` block).
  - In `update_facts()`, change:
    - `_waist_cast.target_position = facing` → `_waist_cast.target_position = facing * wall_detection_reach`
    - `_head_cast.target_position = facing` → `_head_cast.target_position = facing * wall_detection_reach`
  - No other lines in the file change.

## Pre-implementation Checklist
- [x] Only `_waist_cast.target_position` and `_head_cast.target_position` assignments are modified — `_left_cast`, `_right_cast`, `_down_cast`, and `_vault_landing_cast` are left exactly as-is.
- [x] The new export is placed in the exports block alongside existing tuning knobs, not mixed into the private `var` block.
- [x] `wall_detection_reach` default value is `0.6` (capsule radius 0.5 + 0.1 safety buffer), matching the scope specification.
- [x] No logic changes outside `update_facts()` — `can_continue_climbing()`, `get_wall_point()`, `get_climb_normal()`, and all other methods are untouched.
- [x] GDScript syntax verified: `facing * wall_detection_reach` produces a `Vector3` (Vector3 × float), which is the correct type for `target_position`.
