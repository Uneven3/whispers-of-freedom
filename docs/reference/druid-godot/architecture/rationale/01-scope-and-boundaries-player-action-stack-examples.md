> [!NOTE]
> **DESIGN RATIONALE** — read when changing the constitution or designing a new system.
> Daily reference: `docs/architecture/CONSTITUTION.md` + `docs/architecture/ARCHITECTURE-MAP.md`.

---

# Player Action Stack (Cluster A) — Non-Technical Examples

This artifact contains the non-technical gameplay examples for the architectural layers defined in `01-scope-and-boundaries-player-action-stack.md`. 

## Movement System

### 1. Brain (Input Generation)
The player presses W and holds Shift. `PlayerBrain` emits `{move_dir: forward, wants_sprint: true}`. An enemy's `AIBrain` decides to lunge and emits `{move_dir: toward_player, wants_attack: true}`. Both flow through identical pipelines.

### 2. Broker (Orchestrator + Arbiter)
Link is climbing. `PlayerBrain` sends `{wants_jump: true, move_dir: left}`. Broker's gather phase: `ClimbMotor` proposes `WALL_JUMP` (PLAYER_REQUESTED), `GlideMotor` proposes nothing, `LedgeService` proposes nothing forced. Broker picks `WALL_JUMP`, updates `LocomotionState`, dispatches `WallJumpMotor`.

### 3. Motors (Execution)
`GlideMotor.on_tick` reads wind-free fall math, applies horizontal drift from `intents.move_dir`, calls `stamina.drain(...)`, calls `body.apply_motion(...)`. When stamina hits zero, `GlideMotor` does not decide to stop — next frame `gather_proposals` sees stamina exhausted and stops proposing `GLIDE`; `LedgeService` may propose a fall. Broker picks the new winner.

### 4. Services & Body (Foundational Layer)
`LedgeService.update_facts()` casts rays from `BodyReader.position`, caches ledges and wall normals. `LedgeService.gather_proposals()` may emit a FORCED auto-vault proposal. Neither LedgeService nor the Motors know about each other.

---

## Camera System

### 1. CameraBrain (Input Generation)
The player moves the mouse 4 px right and presses the lock-on key. `PlayerCameraBrain` emits `{ look_delta: (4, 0), wants_lock_on_toggle: true, wants_aim: false }`. The brain does not know if there is a wall behind the camera or whether a target exists.

### 3. CameraModes & CameraEffects (Execution)
Player draws the bow → `AimingReader.is_aiming() = true`. `AimMode.gather_proposals` returns a PLAYER_REQUESTED proposal to enter `AIM`. Broker commits `AimMode`. Same frame, Combat calls `request_effect(shake, 0.4, 0.15)` on a hit. Broker iterates effects: `AimMode` produced over-shoulder transform; `ShakeEffect` adds noise; final written to `Lens`.

### 4. CameraServices & Lens (Foundational Layer)
`FollowMode` wants to sit 5 m behind the player at shoulder height. It computes the candidate, asks `OcclusionService.max_distance(target_pos, candidate_pos)`, clamps to 3 m if a wall blocks. The Mode does not know what was hit — just the maximum unobstructed distance.

---

## Combat System

### 1. Brain (Input Generation — shared with Movement)
An enemy `AIBrain` sees the player within 3 m and aggro'd. It produces `{move_dir: toward_player, wants_attack: true}`. Movement uses the move direction; Combat uses `wants_attack`.

### 3. Combat Actions (Execution)
Player hits Parry at the right moment while Monkey. `ParryAction.gather_decision` sees an incoming attack in the parry window (from AI perception signal). `CounterAction.execute` fires; produces a `DamageEvent` with `stagger_class = "heavy"` targeted at the attacker. The attacker's `EntityController` catches `stagger_triggered`, injects a FORCED `STAGGER` proposal into its Movement Broker.
