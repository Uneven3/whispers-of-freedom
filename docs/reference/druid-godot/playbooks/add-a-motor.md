# Playbook: Add a Motor

| Section | Contents |
|---|---|
| **Operation** | Add a new locomotion Motor for a single state. |
| **Data flow** | `PlayerBrain.get_intents()` → `Intents` struct → `MovementBroker._physics_process` → `Motor.gather_proposals()` (side-effect-free) → arbitration → `Motor.tick(delta, intents, body, stamina, services)` → `Body.move_and_slide()`. |
| **Files to create** | `graybox-prototype/scripts/player_action_stack/movement/motors/<name>_motor.gd` (extends `BaseMotor`). |
| **Files to edit** | (1) `LocomotionState.ID` enum — add the new ID. (2) `MovementBroker.motor_map` (in `main.tscn`) — register the new Motor. (3) `MovementBroker._guess_state_id` — add the name → ID match. (4) `ARCHITECTURE-MAP.md` — add a Built row. (5) If the Motor needs a new service, follow `add-a-service.md` first. |
| **Contract surface** | `gather_proposals(current_mode, intents, services, stamina) -> Array[TransitionProposal]` — side-effect-free; `tick(delta, intents, body, stamina, services) -> void` — only this calls Body mutators. |
| **Constitution clauses touched** | G1, G2, P2, P3, P7. |
| **Smoke test (≤ 2 lines)** | E.g., "Move from default state into the new state under expected input; verify `LocomotionState.get_active_mode()` reports the new ID and only this Motor's tick runs." |
| **Forbidden** | Reading `Input.*` from inside a Motor (P1). Calling `Body.move_and_slide()` outside tick. Mutating `LocomotionState._mode` directly. |
