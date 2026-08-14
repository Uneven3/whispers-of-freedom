# Slice Plan: Fix Wall Jump / Mantle Conflict

## Goal
Prevent the `MantleMotor` from incorrectly hijacking lateral or backward wall jumps when the player is near a ledge, while still allowing forward/upward wall jumps to smoothly transition into a mantle.

## Architecture Map Target
Modifying an existing Motor: `MantleMotor`.

## Constitution Clauses Involved
- **G4 (Data structures carry zero logic)**: We will read the `Intents` data structure without adding logic to it.
- **P2 (Active Motor exclusivity)**: Ensuring the `MantleMotor` and `WallJumpMotor` do not conflict over priority inappropriately during state arbitration.

## Playbooks Referenced
None directly (modifying existing Motor logic).

## File Touches
- `graybox-prototype/scripts/player_action_stack/movement/motors/mantle_motor.gd`: Update the condition in `gather_proposals` to require upward intent (`intents.raw_input.y < -0.5`) when triggered from a wall jump. Change `if requesting or is_wall_jumping:` to `if requesting or (is_wall_jumping and intents.raw_input.y < -0.5):`

## Pre-implementation Checklist
- [x] Ensure `intents.raw_input.y < -0.5` perfectly mirrors the upward check used in `wall_jump_motor.gd`.
- [x] Verify that reading `intents.raw_input` inside `gather_proposals` does not mutate the `Intents` object or violate G4.