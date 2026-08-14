# Playbook: Extend Intents

| Section | Contents |
|---|---|
| **Operation** | Add a new field to `Intents`. |
| **Data flow** | `Intents` is pure data (G4). Brain populates → Broker passes through → Motor / Service consumes. |
| **Files to edit** | (1) `graybox-prototype/scripts/base/intents.gd` — add the field with a typed default. (2) `Intents.reset()` — reset the new field. (3) Every concrete Brain (`PlayerBrain`, future `AIBrain`) — populate the field every frame. (4) The consumer (Motor / Service) — read the field. (5) `ARCHITECTURE-MAP.md` Built row for `Intents` — update the surface line. |
| **Constitution clauses touched** | G4, P1. |
| **Smoke test (≤ 2 lines)** | E.g., "Trigger the input that sets the new field; verify the consuming Motor reacts." |
| **Forbidden** | Logic inside `Intents` (G4). Reading the new field outside a consumer that's downstream of the Brain (P1). |
