> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Component Examples

> **Scope of this artifact.** Contains the narrative examples extracted from `04-systems-and-components-player-action-stack.md` to keep the primary architecture contract dense.

### `EntityController` Forced-Interrupt Fan-Out
`FormBroker` emits `form_shifted(&"avian")` upward. `EntityController`'s handler synchronously calls `MovementBroker.set_allowed_motors(motor_mask_for(&"avian"))`, `MovementBroker.inject_forced_proposal(FormShiftProposal)`, and `Body.swap_collision_shape(shape_for(&"avian"))` — all downward, all on the same frame (Stage 2 Trace B 0-frame path).

### `PlayerBrain` Intent Production
Player holds Shift + W and taps Space → `{move_dir: forward, wants_sprint: true, wants_jump: true, ..., wants_form_shift: &""}`.

### `AIBrain` Intent Production (Panther-archetype)
Enemy spots the player at 4 m range. `AIBrain` writes `{move_dir: toward_player, wants_attack: true, aim_target: player_pos}` — the exact same struct shape `PlayerBrain` produces.

### `MovementBroker` Weight Registry Arbitration
Slot 3 enqueues a `FormShiftProposal(weight=100)`; last frame's slot 5 enqueued a `stagger_class=&"heavy"` (weight=80). Both FORCED. Form-shift wins on weight; stagger dies on the floor. Assert fires iff the registry ever becomes non-injective.
