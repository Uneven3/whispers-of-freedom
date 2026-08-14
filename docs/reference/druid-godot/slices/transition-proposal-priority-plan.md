# Slice: transition-proposal-priority

**Status:** Audited <!-- Draft / Plan-Approved / Plan-Blocked / Implemented / Audited / Committed -->

## Operation type
Refactoring / Contract Alignment

## Files to touch (≤ 5)
- `graybox-prototype/scripts/base/transition_proposal.gd` — Align `Priority` enum to 4-tier (`DEFAULT`, `PLAYER_REQUESTED`, `OPPORTUNISTIC`, `FORCED`) per architecture docs, and update `_init` default value to `Priority.DEFAULT`.
- `graybox-prototype/scripts/player_action_stack/movement/motors/walk_motor.gd` — Replace magic number `1` with `TransitionProposal.Priority.PLAYER_REQUESTED`.
- `graybox-prototype/scripts/player_action_stack/movement/motors/sneak_motor.gd` — Replace magic number `2` with `TransitionProposal.Priority.PLAYER_REQUESTED` and an override weight of `1` (so it cleanly wins over walk).

## Playbook used
N/A (Core framework alignment)

## Constitution clauses touched
- G4 — `TransitionProposal` struct remains pure data.
- P2 — Ensures Motor arbitration via `gather_proposals` correctly sorts proposals based on the aligned 4-tier priority system.

## Measurable test (≤ 2 lines)
Play the game; press walk and then press sneak. Verify the `SneakMotor` correctly overrides `WalkMotor` and the transition occurs smoothly.

## ARCHITECTURE-MAP diff
**Built (additions / edits):**
- `TransitionProposal` — update constructor defaults and enum in map row if applicable (map only lists struct names right now, so no surface changes).

**Deferred (removals — only if activation trigger met):**
- None

## Risks / open questions
- The `MovementBroker` relies on integer comparisons (`>` operator) to arbitrate. Updating the enum values from `0, 1, 2` to `0, 1, 2, 3` keeps sorting correct, provided no Motor expects `OPPORTUNISTIC` to lose to `PLAYER_REQUESTED` under the old 0 vs 1 scheme. Under the new scheme, `OPPORTUNISTIC` (2) beats `PLAYER_REQUESTED` (1), which matches the architectural rule `FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT`.
