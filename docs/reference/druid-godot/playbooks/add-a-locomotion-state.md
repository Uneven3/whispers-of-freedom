# Playbook: Add a Locomotion State

| Section | Contents |
|---|---|
| **Operation** | Add a new value to `LocomotionState.ID`. |
| **Data flow** | `MovementBroker.set_state` → `LocomotionState._mode = new` → `state_changed(old, new)` signal → `LocomotionStateReader` consumers (Camera, UI, AI). |
| **Files to edit** | (1) `LocomotionState.ID` enum — append (do not reorder existing values; existing IDs are written into scenes). (2) `ARCHITECTURE-MAP.md` Built row for `LocomotionState`. (3) Any consumer that switches on `LocomotionState.ID` — handle the new case explicitly (G3 fail-closed). |
| **Constitution clauses touched** | G2, P3. |
| **Smoke test (≤ 2 lines)** | E.g., "Trigger the conditions for the new state; verify `LocomotionState.get_active_mode()` returns the new ID and the `state_changed` signal fired." |
| **Forbidden** | Reordering existing enum values. Skipping the consumer-side switch update (silent fall-through). |
