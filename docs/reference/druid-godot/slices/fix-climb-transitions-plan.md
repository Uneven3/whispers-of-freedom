# Slice Plan: Fix Climb Transitions

## Goal
Repair the four root causes that prevent ClimbMotor from winning arbitration when entered from JUMP, SPRINT, or GLIDE states, and from being properly cleared on AUTO_VAULT exit: (1) ClimbToggleComponent clears toggle on JUMP entry; (2) ClimbToggleComponent never clears toggle on AUTO_VAULT entry; (3) SprintMotor's SPRINT proposal outbids ClimbMotor's PLAYER_REQUESTED when the player runs into a climbable wall; (4) GlideMotor's FORCED sticky proposal outbids ClimbMotor's PLAYER_REQUESTED when the player holds the glide key near a wall.

## Architecture Map Target
- **Motor layer**: SprintMotor (`motors/sprint_motor.gd`) — add wall-climbable abstain guard (mirrors existing StairsService abstain pattern).
- **Motor layer**: GlideMotor (`motors/glide_motor.gd`) — downgrade sticky FORCED to PLAYER_REQUESTED when `LedgeService.can_climb()` is true; reset `_previous_wants_glide` in `on_deactivate`.
- **ClimbToggleComponent** (`movement/climb_toggle_component.gd`) — remove JUMP from clear list; add AUTO_VAULT to clear list.

No changes to MovementBroker, LocomotionState, BaseMotor, LedgeService, or ClimbMotor.

## Constitution Clauses Involved
- **P2** (motor exclusivity): SprintMotor and GlideMotor currently win arbitration over ClimbMotor when a wall is grabbable and climb is requested — wrong motor wins, violating exclusive-tick invariant. Fixed by abstain and priority downgrade respectively.
- **G2** (SSoT): ClimbToggleComponent clearing `_is_active` on JUMP corrupts the toggle state that is the sole source of `intents.wants_climb`, causing the side-effect to destroy a valid player intention. Removing JUMP from the clear list restores SSoT.
- **P3** (SSoT writers): no writes to LocomotionState or Body outside their designated owners — not at risk; no changes to those paths.
- **P5** (no implicit ticks): GlideMotor's `on_deactivate` hook is a lifecycle callback, not a `_process` override — not at risk.

## Playbooks Referenced
None.

## File Touches

- `graybox-prototype/scripts/player_action_stack/movement/climb_toggle_component.gd`:
  - In `_on_locomotion_state_changed`: remove `LocomotionState.ID.JUMP` from the `_is_active = false` branch.
  - Add `LocomotionState.ID.AUTO_VAULT` to the same `_is_active = false` branch (alongside MANTLE and EDGE_LEAP).

- `graybox-prototype/scripts/player_action_stack/movement/motors/sprint_motor.gd`:
  - In `gather_proposals`: after the existing StairsService abstain guard, add a second abstain guard: retrieve `LedgeService` from `services`; if `ledge != null and ledge.can_climb() and intents.wants_climb`, return `[]`. This mirrors the stairs abstain pattern exactly.

- `graybox-prototype/scripts/player_action_stack/movement/motors/glide_motor.gd`:
  - Add a `LedgeService` lookup at the top of `gather_proposals`.
  - In the `current_mode == LocomotionState.ID.GLIDE` sticky branch: if `ledge != null and ledge.can_climb() and intents.wants_climb`, emit `PLAYER_REQUESTED` instead of `FORCED` so ClimbMotor's `PLAYER_REQUESTED weight=5` wins the tiebreak via `override_weight`.
  - Add `on_deactivate(_body: CharacterBody3D) -> void` override: set `_previous_wants_glide = false`. This prevents a re-entry to GLIDE on the first frame after leaving a wall, because `_previous_wants_glide` would otherwise remain `true` from the last frame in GLIDE, causing `fresh_glide_press` to evaluate `false` incorrectly on re-entry.

## Pre-implementation Checklist
- [x] ClimbToggleComponent no longer clears `_is_active` on JUMP — verified by reading the updated condition list.
- [x] ClimbToggleComponent clears `_is_active` on AUTO_VAULT — verified by reading the updated condition list.
- [x] SprintMotor abstain on `ledge.can_climb() and intents.wants_climb` uses `_get_service(services, LedgeService)`, not a direct node reference (no sideways access, G3 safe).
- [x] GlideMotor's `LedgeService` lookup uses `_get_service(services, LedgeService)` — not a stored field or `get_parent()` call.
- [x] GlideMotor sticky branch: the priority downgrade path only fires when `intents.wants_climb` is also true — avoids silently losing GLIDE priority whenever near any wall.
- [x] GlideMotor `on_deactivate` resets `_previous_wants_glide` to `false` — prevents spurious fresh-press suppression after CLIMB exit.
- [x] No changes made outside the three listed files.
- [x] No new public methods added to any file (all additions are internal or lifecycle overrides already on BaseMotor).
