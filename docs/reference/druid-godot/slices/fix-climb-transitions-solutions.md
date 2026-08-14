# Solutions: fix-climb-transitions

**Problem:** ClimbMotor cannot be entered from JUMP, SPRINT, or GLIDE states, and the ClimbToggleComponent incorrectly clears the toggle on JUMP and never clears it on AUTO_VAULT. Root causes are: (1) ClimbToggleComponent clears toggle on JUMP entry, preventing jump-then-grab; (2) SprintMotor proposes FORCED priority on floor near a wall, outbidding ClimbMotor's PLAYER_REQUESTED; (3) GlideMotor proposes FORCED while `wants_glide` is held mid-air, outbidding ClimbMotor's PLAYER_REQUESTED mid-glide; (4) AUTO_VAULT never clears the toggle.
**Status:** Draft

---

## Solution 1: Motor Abstention + Toggle Clear Patch

**Approach:**
Fix toggle clear rules directly in `ClimbToggleComponent`: remove JUMP from the clear list and add AUTO_VAULT. Fix the two competing motors at the arbitration layer: SprintMotor returns `[]` (abstain) when `ledge.can_climb()` is true (a wall is grabbable), using the existing stairs-abstain pattern; GlideMotor drops FORCED to PLAYER_REQUESTED when it detects a climbable wall — so ClimbMotor's `PLAYER_REQUESTED weight=5` wins the tiebreak via `override_weight`. No new layers or signals are introduced.

**Architecture Map Target:**
Motor layer (SprintMotor, GlideMotor), ClimbToggleComponent (sibling Node of PlayerBrain)

**Constitution Clauses at Risk:**
- **P2** (motor exclusivity): SprintMotor currently outbids ClimbMotor every frame on floor near wall — that is a P2 violation (wrong motor wins arbitration). The abstain fix restores correct exclusivity.
- **G2** (SSoT): ClimbToggleComponent clearing on JUMP corrupts the toggle state that drives `intents.wants_climb` — a G2 sub-violation (side-effect write from state-transition observer). Removing the JUMP case restores SSoT.
- **P3** (only broker writes LocomotionState): not at risk; no writes to LocomotionState outside broker.

**Tradeoffs:**
- Pro: Minimal surface area — three targeted edits across existing files; SprintMotor's abstain pattern is already established and auditable.
- Pro: ClimbMotor's priority logic (`OPPORTUNISTIC` sticky, `PLAYER_REQUESTED` entry) is unchanged; arbitration math already handles FALL correctly.
- Con: GlideMotor needs to read LedgeService to detect a climbable wall — GlideMotor gains a new service dependency it currently doesn't have.
- Con: SprintMotor abstaining on any climbable wall means sprint cuts out whenever the player runs near a wall face-on, even if they don't want to climb — could feel abrupt without a visual tell.

**Edge Cases:**
- Player sprints parallel to a wall: LedgeService `can_climb()` checks facing-relative raycasts, so lateral proximity should not trigger abstain; only direct approach will.
- Player holds glide while pressing into a wall at high speed: FORCED→PLAYER_REQUESTED downgrade means ClimbMotor wins but GlideMotor's `_previous_wants_glide` state may still be held, causing re-entry to GLIDE on the next frame after releasing the wall. Needs GlideMotor to reset `_previous_wants_glide` on CLIMB entry (could use `on_activate`/`on_deactivate` hooks).
- Player jumps, then immediately presses climb before any wall contact: toggle stays active (JUMP no longer clears it), but LedgeService won't report `can_climb()` until body is actually near a wall, so no spurious CLIMB entry.

---

## Solution 2: Priority Ceiling for Floor-Bound Motors

**Approach:**
Introduce a shared abstain rule at the `MovementBroker` level: before dispatching proposals, if `LedgeService.can_climb()` is true AND `intents.wants_climb` is true, the broker silently discards any proposal whose priority is `FORCED` from a set of "floor-bound" motors (SprintMotor, GlideMotor identified by class name or a new `is_floor_bound: bool` export). ClimbToggleComponent toggle-clear rules are patched identically to Solution 1. No changes to individual motor files.

**Architecture Map Target:**
Broker layer (MovementBroker), ClimbToggleComponent

**Constitution Clauses at Risk:**
- **P2** (motor exclusivity): The broker filtering proposals by motor identity is legal as long as each motor still only ticks once — this solution preserves that invariant.
- **G1** (single responsibility): MovementBroker gains climb-specific arbitration knowledge, spreading locomotion policy from motors into the broker — a G1 smell.
- **P7** (layer adjacency): Broker would need to call `LedgeService.can_climb()` directly, which is a service read — currently the broker only reads `Intents` and iterates proposals; adding a service read couples broker to gameplay specifics, violating the spirit of P7's adjacency contract.

**Tradeoffs:**
- Pro: Motor files are untouched; the fix is in one place (broker), easier to audit in one pass.
- Con: Broker accumulates locomotion-specific knowledge about which motors are "floor-bound", violating G1 and the spirit of P7 — the broker's job is arbitration, not knowing about motor capabilities.
- Con: Future motors that should also abstain near walls need broker edits rather than self-contained motor edits, making the pattern harder to discover and maintain.

**Edge Cases:**
- A combat motor (future) uses FORCED to interrupt climbing: the broker's "ceiling" logic could inadvertently block it if that motor is also classified as "floor-bound". The allowlist must be carefully maintained.
- Two PLAYER_REQUESTED proposals at equal weight during a GLIDE→CLIMB transition: tiebreaking falls to `override_weight`; ClimbMotor's weight=5 should still win, but the broker filtering path must reach the tiebreak after discarding FORCED, not short-circuit.
- Player is simultaneously near a wall and on stairs: both the stairs abstain (already in SprintMotor) and the climb-ceiling apply, resulting in correct WALK takeover — no double-abstain issue since StairsMotor still proposes.

---

## Solution 3: Climb-Priority Escalation on Contact

**Approach:**
Instead of patching competing motors, escalate ClimbMotor's own priority: when `ledge.can_climb()` is true and `intents.wants_climb` is true, ClimbMotor proposes `FORCED` with a very high weight (e.g., 50) rather than `PLAYER_REQUESTED`. The rationale is that an explicit climb request at a valid wall is a player intention that should always win. ClimbToggleComponent toggle-clear rules are patched identically to Solution 1 (remove JUMP, add AUTO_VAULT). The sticky-climb path (already OPPORTUNISTIC weight=5) is unchanged.

**Architecture Map Target:**
Motor layer (ClimbMotor only), ClimbToggleComponent

**Constitution Clauses at Risk:**
- **P2** (motor exclusivity): Escalating to FORCED ensures climb always wins — this is correct behavior, but FORCED is semantically reserved for "motor that is already running and must not be interrupted" (see GlideMotor's sticky logic, AutoVaultMotor's mid-vault lock). Using FORCED for entry misuses the priority tier's semantic contract.
- **G2** (SSoT): If ClimbMotor uses FORCED for entry, any future FORCED-priority system interrupt (combat stagger, mount) could have unexpected interaction — FORCED is currently an upper-ceiling semantic, not an entry-priority semantic.
- **Section 2 Deferred** (4-tier priority registry): The architecture map explicitly defers a 4-tier priority system until "out-of-system FORCED interrupts ship". Escalating ClimbMotor to FORCED for entry preempts that deferral and ties the design to the current 3-tier system in a way that conflicts with the intended future expansion.

**Tradeoffs:**
- Pro: One-file change in ClimbMotor — extremely small diff, no new service dependencies for other motors.
- Con: Misuses FORCED semantics (FORCED = "this motor is mid-sequence and cannot be interrupted", not "player wants this"). This corrupts the priority tier's meaning for every future motor author reading the code.
- Con: Breaks future FORCED-based combat interrupts: a stagger at weight=10 would lose to ClimbMotor's FORCED at weight=50 whenever near a wall, requiring the combat motor to use even higher weights — a weight-inflation arms race.

**Edge Cases:**
- Player near a wall during a mid-vault (AutoVaultMotor FORCED weight=20): ClimbMotor FORCED weight=50 would interrupt a running vault, pulling the player off the arc mid-animation — a severe gameplay bug.
- Player wants_climb but stamina is exhausted: ClimbMotor already gates on exhaustion before proposing; the FORCED escalation only activates when a proposal would be emitted anyway — no new risk here.
- Player holds climb while SprintMotor is active and walks away from wall: LedgeService `can_climb()` returns false immediately, ClimbMotor drops back to `[]`, sprint resumes — correct behavior, no sticky FORCED issue.

---

## Chosen Solution

**Selected:** Solution 1 — Motor Abstention + Toggle Clear Patch
**Rationale:** Solution 1 fixes each bug at the layer that owns the decision: SprintMotor owns whether it should run (abstain pattern already in use for stairs), GlideMotor owns its sticky priority, and ClimbToggleComponent owns which state transitions reset the toggle. No broker-level locomotion knowledge is introduced (avoiding G1/P7 risks of Solution 2), and FORCED semantics remain reserved for mid-sequence locks (avoiding the priority corruption and weight-inflation arms race of Solution 3). The new LedgeService dependency for GlideMotor is the sole structural addition, and it follows the existing pattern that SprintMotor already uses for StairsService.
