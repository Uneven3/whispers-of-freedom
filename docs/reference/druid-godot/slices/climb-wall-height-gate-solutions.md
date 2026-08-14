# Solutions: climb-wall-height-gate

**Problem:** `_detect_climb` grants `_can_climb` when `waist_hit AND (head_hit OR _mantle_ledge_point != ZERO)`. The `_mantle_ledge_point` fallback fires for any wall whose top is detectable by the down-cast — including short walls — so the player can initiate a climb on surfaces that should be handled by auto-vault instead.
**Status:** Draft

---

## Solution 1: Three-Ray Simultaneous Contact Gate

**Approach:**
Replace the current gate condition with `knee_hit AND waist_hit AND head_hit` (indices 1, 2, 5 of `_h_casts`). All three sensors must register a hit in the same frame before `_can_climb` is set. The `_mantle_ledge_point` check is removed entirely from `_detect_climb`; mantle and auto-vault continue to use their own independent paths. `update_facts` passes `knee_hit` alongside the existing `waist_hit` / `head_hit` arguments to `_detect_climb`.

**Architecture Map Target:**
Service (`LedgeService`)

**Constitution Clauses at Risk:**
- G2: `_can_climb` is still the single field in a single place — risk is low, but the change must not duplicate the gate logic anywhere else.
- P3: `_can_climb` is written only inside `_detect_climb`, which is called only by `update_facts` — the fix preserves this invariant.

**Tradeoffs:**
- Pro: Minimal blast radius — one condition change, one extra argument; no new state, no new nodes.
- Pro: Semantically unambiguous — a climbable wall is one tall enough to occupy all three sensor levels simultaneously, which is easy to reason about and test.
- Con: The gap between head-cast height (offset +0.6) and wall top must be at least one cast radius (~0.1 m); a wall that ends slightly below 0.6 m above waist will silently reject climb even if it "looks" climbable. Designer must set geometry to clear this threshold.
- Con: Does not add a minimum absolute wall height check; relies entirely on whether the head cast is blocked, which is a proxy for height.

**Edge Cases:**
- Player approaches a 0.7 m wall at an angle: waist hits, knee hits, head misses because the wall is too short — correctly blocked.
- Player approaches a tall wall with a ceiling immediately above: all three hit, `_can_climb` is true — correct; the climb motor's `can_continue_climbing()` handles headroom during the climb itself.
- Player stands close to a wall segment that has a small gap at head height (e.g., a window sill): head cast passes through the gap, so `_can_climb` is false — correct; the player must reposition.

---

## Solution 2: Explicit Minimum Height Constant

**Approach:**
Introduce an `@export var climb_min_wall_height: float = 1.5` constant in `LedgeService`. Inside `_detect_climb`, after confirming `waist_hit` and wall angle, compute the wall's apparent top by sampling `_down_cast.get_collision_point(0).y` (already available when `_mantle_ledge_point != ZERO`) and compare it against `body_position.y + climb_min_wall_height`. Only set `_can_climb = true` if the wall top exceeds that threshold. The `_mantle_ledge_point` path is retained but is used purely for height measurement, not as a gate bypass.

**Architecture Map Target:**
Service (`LedgeService`)

**Constitution Clauses at Risk:**
- G2: `_detect_climb` now reads `_mantle_ledge_point` (set by `_detect_mantle`) — introduces a read-order dependency between two private methods called from `update_facts`. Execution order must be documented; if order ever changes, the gate silently breaks.
- P3: No new writers; risk is low but the cross-method dependency is a soft violation of single-concern.

**Tradeoffs:**
- Pro: Gives designers a tunable numeric threshold for minimum climbable wall height, independent of cast geometry.
- Con: The `_mantle_ledge_point` path is kept alive as a height source, meaning the ledge down-cast must have already fired for `_detect_climb` to read it. Execution order in `update_facts` becomes a hidden constraint — a fragility that the scope summary explicitly wanted to remove.
- Con: Adds a public export whose value needs to be calibrated against the body-offset constants (`mantle_body_half_height`, cast offsets), increasing designer cognitive load.

**Edge Cases:**
- Wall height exactly at `climb_min_wall_height`: depending on floating-point margin, the result is flaky at the boundary — requires a small tolerance epsilon.
- Tall wall where `_down_cast` doesn't fire (no detectable top within `mantle_max_height`): `_mantle_ledge_point` is ZERO, the height check cannot run, `_can_climb` stays false even for a legitimately tall wall. This is the original bug inverted — now tall walls with no top block climb instead of short walls allowing it.
- Sloped ceiling just above waist-height wall: the down-cast may hit the ceiling geometry, reporting a false wall top — `_can_climb` could be true or false incorrectly.

---

## Solution 3: Dedicated Minimum-Cast-Count Threshold

**Approach:**
Count the number of horizontal cast hits across all six levels. Require a minimum hit count (e.g., `climb_min_hits: int = 4`) before allowing climb entry. `_detect_climb` receives the full `hits` array and counts how many of the upper-half sensors (indices 1–5) are colliding. This is a statistical gate rather than a named-sensor gate: it tolerates minor cast misses (e.g., a thin ledge overhang breaking one ray) while still rejecting short walls that only hit 1–2 levels.

**Architecture Map Target:**
Service (`LedgeService`)

**Constitution Clauses at Risk:**
- G2: `_can_climb` remains single-owner; risk low.
- G1: `_detect_climb` gains a loop over the full `hits` array, pulling it slightly toward a multi-concern helper — minor but auditable.

**Tradeoffs:**
- Pro: Tolerates irregular wall geometry (a single-cast miss doesn't block climb); robust against minor geometry imperfections.
- Con: Threshold tuning is opaque — changing `climb_min_hits` from 4 to 3 silently changes which wall heights are accepted, and the relationship between hit count and actual wall height is non-linear across the six offset levels.
- Con: A wide short wall with all six hits at the same horizontal level (flat obstacle) could satisfy the count threshold; the gate is not truly height-sensitive, only collision-density-sensitive.

**Edge Cases:**
- Corrugated or grated wall surface that intermittently blocks some casts: some frames pass the threshold, some don't — causes flickering `_can_climb` transitions.
- Short wall (0.5 m) with a ceiling directly above: all six casts hit, threshold met, `_can_climb` becomes true on a short wall — the bug is not fixed, just relocated.
- Tall wall with one cast level partially inside another collider (e.g., a thin trim piece): hit count inflated but behavior is correct since the wall is tall enough anyway.

---

## Chosen Solution

**Selected:** Solution 1 — Three-Ray Simultaneous Contact Gate
**Rationale:** Minimum blast radius — one condition change, one additional argument to `_detect_climb`. No new state, no new exports, no cross-method read-order dependencies. The gate is semantically unambiguous: a wall is climbable only when it occupies all three named sensor levels (knee, waist, head) simultaneously. This removes the `_mantle_ledge_point` fallback from `_detect_climb` entirely, which was the root cause of short-wall climb triggering. G2 and P3 are preserved: `_can_climb` remains written exclusively inside `_detect_climb`, and there is no new duplication of the gate logic.
