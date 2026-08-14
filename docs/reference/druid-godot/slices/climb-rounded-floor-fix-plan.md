# Slice Plan: Fix "climbing the air" and "stuck on floor" bugs on rounded surfaces near the ground.

## Goal
Fix bugs where the player could "climb the air" on flat ground after climbing, or feel "stuck" at the base of rounded surfaces because orientation alignment was suppressed too early. This is achieved by moving from a height-based "mantle edge" check to a sensor-based "head hit" check (sensor-relative approach).

## Architecture Map Target
- `LedgeFacts` (`graybox-prototype/scripts/player_action_stack/movement/services/ledge_facts.gd`)
- `LedgeService` (`graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`)
- `ClimbMotor` (`graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`)

## Constitution Clauses Involved
- **G1 (Single Responsibility)**: Cleaning up redundant logic in `ClimbMotor`.
- **G2 (Single Source of Truth, including state machines)**: Ensuring CLIMB mode is only proposed/maintained when valid physical conditions (sensors) are met.
- **P3 (SSoT writers)**: Only the active Motor (ClimbMotor) writes Body motion; ensuring it does so correctly at the base of walls.
- **G5 (Boundary validation)**: Fixing broken test logic that attempted to call non-existent methods on engine classes.

## Playbooks Referenced
None.

## File Touches
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_facts.gd`:
    - Add `var has_head_hit: bool = false` to track the topmost horizontal sensor.
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`:
    - In `update_facts`, populate `has_head_hit` using the result of `hits[5]` (the head-level shapecast).
- `graybox-prototype/scripts/player_action_stack/movement/motors/climb_motor.gd`:
    - Redefine "apex" logic: `near_apex = on_floor and not facts.has_head_hit and facts.ledge_point != Vector3.ZERO`. The `ledge_point` check ensures we are actually at a ledge and not just on flat ground.
    - Update `gather_proposals`: Use the new `near_apex` logic and simplify the sticky-climb condition to `if climbing and (near_apex or ledge.can_continue_climbing()):`. This removes the redundant `can_continue_climbing` check.
    - Update `tick`: Use `near_apex` to suppress yaw alignment and wall-stick.
    - Clean up unused `has_climb_context` variable.
- `graybox-prototype/test/unit/test_climb_motor.gd`:
    - Add `TestBody` inner class that inherits from `CharacterBody3D` and overrides `is_on_floor()` with a mockable property.
    - Fix invalid `_body.set_on_floor(true)` calls by using the new `TestBody` mock.
    - Update regression tests to use `has_head_hit` instead of `is_at_mantle_edge` where appropriate.
    - Add test case for the "climbing the air" regression on flat ground.
- `graybox-prototype/test/unit/test_ledge_facts.gd`:
    - Add default value assertion for `has_head_hit`.

## Pre-implementation Checklist
- [x] Ensure `LedgeFacts` correctly exposes `has_head_hit`.
- [x] Verify that `facts.ledge_point` is `Vector3.ZERO` on flat ground in `LedgeService` (requires `mantle_rel_y > 0`).
- [x] Ensure `test_climb_motor.gd` is listed in File Touches.
- [x] Fix invalid `set_on_floor` call in `test_climb_motor.gd`.
