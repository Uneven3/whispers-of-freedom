> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) Architecture — Edge Cases

> **Scope of this artifact.** Cluster-scoped Stage 3 for Cluster A: **Movement, Camera, Combat, Form** (per `00-system-map.md` § 2–3, `01-scope-and-boundaries-player-action-stack.md`, and `02-data-flow-player-action-stack.md`). Defines conflict-resolution generalized across all four Brokers that reuse `TransitionProposal`, the cluster-only cross-system edge cases, cluster-wide Pause/Death/Cutscene handling given the `GameOrchestrator` tick model, the rollback baseline, and narrative traces exercising the cross-system paths.

> [!NOTE]
> All narrative traces and detailed step-by-step conflict resolution examples have been extracted to [`03-edge-cases-player-action-stack-examples.md`](file:///d:/Programming-Games-Ideas/Druid-Zelda/docs/architecture/rationale/03-edge-cases-player-action-stack-examples.md).

---

## Conflicting Resolutions

**Shared Resolution Rule (Cluster-wide):** All four Brokers in Cluster A arbitrate proposals using the same rule because all four reuse the `TransitionProposal` struct.
1. **Priority category:** `FORCED > OPPORTUNISTIC > PLAYER_REQUESTED > DEFAULT`.
2. **Weight tie-break:** `override_weight: int`.
3. **Stable-order final tie-break (safe ties only):** First-inserted wins if category, weight, and `target_state` match.
4. **Fail-early ambiguous-tie assert (hostile ties):** If category and weight match but `target_state` differs, fire `assert(false, "Ambiguous Transition Tie...")`. Godot's array-iteration order is NEVER allowed to silently pick the winner.

### Intra-System Conflict Rules
| System | Conflict Surface | Resolution Rule |
|---|---|---|
| **Movement** | Internal DEFAULT vs External FORCED | Category break resolves instantly. Weight tie-breaks enforce injective registration (e.g., Form Shift `100` vs Stagger `80`). Asserts on identical weights. |
| **Camera** | `AimMode` vs `LockOnMode` (Same frame) | Mode defines `override_weight`. `AimMode` weight > `LockOnMode` weight. Camera effects are pushed via `request_effect()` and compose, avoiding Mode conflict logic. |
| **Combat** | Intra-moveset action triggers (Same frame) | Each moveset declares an intra-moveset priority list in Combat Stage 4/6. Ambiguity assert discipline scales to Action arbitration. |
| **Form** | `wants_form_shift == current_form` | No-op. Early return in `FormBroker.tick`. No emission, no fan-out. |
| **Form** | Intent re-populated mid-slot | Impossible. Handled via `assert(false, "Intents mutated outside slot 1")` fallback. |

---

## Cross-System Edge Cases

| Case | Slot Collision | Resolution Mechanism | Contract Demonstrated |
|---|---|---|---|
| **Form Shift + Combat Stagger** (Same frame, different entities) | Player Slot 3 (Form shift completes)<br>Enemy Slot 5 (hit lands, injects to Player N+1) | Structurally independent. Shift finishes in N. Stagger queue drains in N+1. | The cross-system paths never share a proposal queue on the same frame. Same-frame co-occurrence is benign. |
| **Fall Impact + Form Shift** (Same frame) | Player Slot 3 (Form shift completes)<br>Player Slot 4 (Ground reattach impact) | Shift fan-out runs in Slot 3. Ground detection in Slot 4 reads the new Avian collision shape. Shift wins over ground-reattach by weight. | Physics post-shift is the ground truth. `impact_detected` reaches subscribers *after* the shift has committed. |
| **Mount Swap + Shift + Attack Intent** (Same frame) | Scene-level `set_target` (mount event) vs Player Slot 1 Intents | Human body's Brain is dormant. Mount Brain takes over. Intents on human body are ignored by the loop. | Missing FormBroker on Mount is a silent no-op structural property, not a fail-loud error. |
| **Parry During Climb** (Moveset gating) | Slot 1 Intent populated<br>Slot 5 Combat gate check | `CombatBroker.tick` sees `CLIMB`. Active-moveset gate refuses every action. `ParryAction` never called. | "Brain is blind" canonical proof. The intent is legally populated, but the action is structurally inert for this tick. |
| **Two Staggers Same Target** (Same frame) | Enemy 1 Slot 5<br>Enemy 2 Slot 5 | Both inject FORCED into Player `MovementBroker`. N+1 Slot 4 arbitrates via `override_weight`. Identical weights assert. | Combat Stage 4/6 constraint: `stagger_class -> weight` mapping MUST be injective. |

---

## External Interruptions (Pause/Death/Cutscene)

| Interrupt | Signal/Trigger | Movement/Locomotion | Form Response | Combat Response | Camera Response |
|---|---|---|---|---|---|
| **Pause** | `GameOrchestrator._paused` early-return | Entire 6-slot body skipped. | Entire 6-slot body skipped. | Entire 6-slot body skipped. | `Lens.process_mode = PROCESS_MODE_PAUSABLE`. Interpolation freezes. |
| **Death** | `EC.on_defeated` routes FORCED(200) `DEFEAT` proposal | `DeathMotor.on_enter`. Ragdoll physics engage. | **GATED.** `EC` calls `FormBroker.set_shifts_enabled(false)` on transition. | `CombatBroker` reads `DEFEAT`, moveset gated off. | Remains attached to body. `LockOnMode` auto-disengages. |
| **Cutscene**| `EC.on_cinematic_requested` routes FORCED(150) `CINEMATIC` proposal | `CinematicMotor.on_enter`. | **GATED.** `EC` calls `FormBroker.set_shifts_enabled(false)` on transition. | `CombatBroker` reads `CINEMATIC`, moveset gated off. | Remains attached to body (MVP has no explicit `CinematicMode`). |

> **Form-Gate Rationale:** Swapping the active skeleton *during* an active ragdoll simulation or mid-cutscene is volatile or corruptive in Godot. The `set_shifts_enabled(false)` downward call preserves the Stage 1 Form↔Movement seam (Form still does not read Movement state).

---

## Network / God-level Edge Cases

- **Deterministic Pipeline:** Intents are blind primitives. Motors must be predictable without `randf()`.
- **AIBrain Authority Split:** Networked builds run authoritative AIBrains on the server. AI decisions route through a seeded RNG, not `randf()`.
- **Camera is NEVER Networked:** Camera logic runs purely locally using the peer's view of authoritative state.
- **Lock-On Target Identity:** `Node3D` references are not stable over networks. Combat Stage 6 must expose a stable entity ID for networked lock-on.
- **Stamina & Form Serialization:** Trivial primitive serialization.
- **FORCED Queue Serialization (`_external_proposals`):** Snapshot MUST serialize `_external_proposals` because cross-entity stagger storms inject proposals in Slot 5 that wait for Frame N+1 Slot 4. A snapshot between ticks contains an active queue.

---

## Residual Risks

- **Snapshot size under cross-entity combat storms:** N attackers staggering one target queue N FORCED proposals. Snapshot size scales linearly. Mitigation: Snapshot compaction (collapse same-source proposals before serialization) is a future network-architecture stage concern.
- **Deterministic iteration order of `_entity_bundles`:** MVP uses registration order. Networked builds will require a stable-sort key (e.g., entity ID).

---

## Exit Criteria

- [x] Conflict resolution pattern is defined.
- [x] Edge cases and external interruptions are strictly formatted as matrices/tables.
- [x] Narrative examples provided for system edge case survival are extracted to `docs/architecture/rationale/03-edge-cases-player-action-stack-examples.md`.
