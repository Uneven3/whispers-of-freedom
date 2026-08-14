# Execution Plan: Ground Movement & Stamina

**Generated from:** `docs/mechanic-designs/ground-movement-and-stamina.md`
**Status:** Approved

## Files Affected

| File | Action | Depends On |
|------|--------|------------|
| `scenes/main.tscn` | modify | None |
| `scripts/player_action_stack/movement/player_brain.gd` | new | None |
| `scripts/player_action_stack/movement/stamina_component.gd` | new | None |
| `scripts/player_action_stack/movement/visuals_pivot.gd` | new | None |
| `scripts/player_action_stack/movement/services/ground_service.gd` | new | `BaseService` |
| `scripts/player_action_stack/movement/services/ledge_service.gd` | new | `BaseService` |
| `scripts/player_action_stack/movement/motors/walk_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/motors/sprint_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/motors/jump_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/motors/fall_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/motors/climb_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/motors/auto_vault_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/motors/mantle_motor.gd` | new | `BaseMotor` |
| `scripts/player_action_stack/movement/movement_broker.gd` | new | `PlayerBrain`, Motors, Services |
| `scripts/player_action_stack/camera/camera_rig.gd` | new | `MovementBroker` (signals) |

## Implementation Steps

### Step 1: `scenes/main.tscn` (modify)
**What this file is:** The root structural scene.
**Actions:**
1. Open the scene. Under `Player/EntityController`, add the missing child nodes for the motors that were not in the scaffold: `WalkMotor`, `SprintMotor`, `SneakMotor`, `JumpMotor`, `FallMotor`, `ClimbMotor`, `WallJumpMotor`, `AutoVaultMotor`, `MantleMotor`.
2. Configure `CharacterBody3D` (`Body`): set its collision layer to 2 (Player) and its mask to 1 (Environment).
3. Set `Body` property `step_height` to `0.3` natively to handle stairs without snagging.
4. Add a `SpringArm3D` named `Lens` to `CameraRig` and a `Camera3D` under it.

### Step 2: `scripts/player_action_stack/movement/stamina_component.gd` (new)
**What this file is:** Pure data node tracking player effort.
**Extends:** `Node`
**Actions:**
1. Define `@export var max_stamina: float = 100.0`.
2. Define `var current_stamina: float = max_stamina`.
3. Define signal `stamina_changed(current, max)`.
4. Implement `func drain(amount: float) -> void:` and `func recover(amount: float) -> void:` that clamp value and emit the signal.
5. Implement `func is_exhausted() -> bool:` returning true if stamina <= 0.
6. Attach to `StaminaComponent` node in `main.tscn`.

### Step 3: `scripts/player_action_stack/movement/player_brain.gd` (new)
**What this file is:** Input reader translating OS events to the `Intents` struct.
**Extends:** `Node`
**Actions:**
1. Implement `func get_intents() -> Intents:`
2. Create a new `Intents` object. 
3. Read `Input.get_vector("move_left", "move_right", "move_forward", "move_backward")` and assign to `intents.move_dir`.
4. Read `Input.is_action_pressed("jump")` and `sprint` into `wants_jump` and `wants_sprint`.
5. Return the struct.
6. Attach to `PlayerBrain` node in `main.tscn`.

### Step 4: `scripts/player_action_stack/movement/services/ground_service.gd` (new)
**What this file is:** Detects floor and stair geometry.
**Extends:** `BaseService`
**Actions:**
1. Implement `@export var max_slope_angle_deg: float = 45.0`.
2. In `_ready()`, create a `ShapeCast3D` child using a short, wide `CylinderShape3D` pointing down.
3. In `update_facts(body_reader: BodyReader) -> void:`, force-update the cast.
4. If it collides and the normal angle against Vector3.UP is `<= deg_to_rad(max_slope_angle_deg)`, set `_is_on_floor = true` and store `_floor_normal`. Otherwise, `false`. (Edge case: Slope Limit Reached).
5. Expose `is_on_floor()` and `get_floor_normal()` getters.
6. Attach to `GroundService` node.

### Step 5: `scripts/player_action_stack/movement/services/ledge_service.gd` (new)
**What this file is:** Detects walls, climbable surfaces, and vault/mantle lips.
**Extends:** `BaseService`
**Actions:**
1. Add `@export var vault_max_height: float = 1.0` and `@export var mantle_max_height: float = 2.5`.
2. In `_ready()`, create three `ShapeCast3D`s (forward waist-height, forward head-height, downward from above-head).
2. In `update_facts(body_reader: BodyReader) -> void:`, update all casts based on current `move_dir` or facing direction.
3. Compute booleans: `_can_vault` (low hit, high miss), `_can_mantle` (high hit, down hit finds lip), `_can_climb` (high and low hit on vertical surface).
4. Expose getters for these booleans and the `_climb_normal`.
5. Attach to `LedgeService` node.

### Step 6: `scripts/player_action_stack/movement/visuals_pivot.gd` (new)
**What this file is:** Decouples the visible mesh from the physics body to smooth out stairs.
**Extends:** `Node3D`
**Actions:**
1. Add `@export var interpolation_speed: float = 20.0`.
2. Add `@onready var _body: CharacterBody3D = $"../Body"`.
3. In `_ready()`, call `set_as_top_level(true)` to decouple transform.
4. In `_process(delta: float) -> void:`, instantly snap X and Z to `_body.global_position.x` and `z`.
5. Lerp the Y position toward `_body.global_position.y` using `interpolation_speed * delta` (Edge case: Hit-Stop & Transform Sync).
6. Attach to `VisualsPivot` node.

### Step 7: `scripts/player_action_stack/movement/motors/walk_motor.gd` (new)
**What this file is:** Ground locomotion handler.
**Extends:** `BaseMotor`
**Actions:**
1. Add `@export var max_speed: float = 5.0`, `@export var acceleration: float = 20.0`, and `@export var friction: float = 15.0`.
2. Implement `gather_proposals`: Return `[TransitionProposal.new(1, Priority.PLAYER_REQUESTED)]` (1 = Walk) if `GroundService.is_on_floor()` and `intents.move_dir != Vector2.ZERO`.
2. Implement `tick`: Apply `max_speed` and `acceleration`/`friction` to `body.velocity.x` and `z` based on `intents.move_dir`.
3. Attach to `WalkMotor` node.

### Step 8: `scripts/player_action_stack/movement/motors/sprint_motor.gd` (new)
**What this file is:** High-speed ground locomotion handler.
**Extends:** `BaseMotor`
**Actions:**
1. Add `@export var sprint_speed: float = 8.0`, `@export var sprint_acceleration: float = 15.0`, and `@export var stamina_cost_per_sec: float = 10.0`.
2. Implement `gather_proposals`: Return proposal if on floor, moving, `intents.wants_sprint == true`, AND `!stamina.is_exhausted()`. (Edge case: Stamina Exhaustion).
2. Implement `tick`: Apply sprint speed, call `stamina.drain(cost * delta)`.
3. Attach to `SprintMotor` node.

### Step 9: `scripts/player_action_stack/movement/motors/fall_motor.gd` (new)
**What this file is:** Default aerial state applying gravity.
**Extends:** `BaseMotor`
**Actions:**
1. Implement `gather_proposals`: Return proposal as `OPPORTUNISTIC` (fallback) if `!GroundService.is_on_floor()`.
2. Implement `tick`: Apply Godot default gravity to `body.velocity.y`. Maintain horizontal momentum.
3. Attach to `FallMotor` node.

### Step 10: `scripts/player_action_stack/movement/motors/jump_motor.gd` (new)
**What this file is:** Impulse application for jumping.
**Extends:** `BaseMotor`
**Actions:**
1. Add `@export var jump_impulse: float = 12.0` and `@export var horizontal_speed_boost: float = 2.0`.
2. Implement `gather_proposals`: Return proposal if on floor and `intents.wants_jump == true`.
2. Implement `tick`: Apply instant `jump_impulse` to `body.velocity.y`, then immediately drop proposal so `FallMotor` takes over next frame.
3. Attach to `JumpMotor` node.

### Step 11: `scripts/player_action_stack/movement/motors/auto_vault_motor.gd` (new)
**What this file is:** Quick hop over low obstacles.
**Extends:** `BaseMotor`
**Actions:**
1. Add `@export var vault_speed: float = 8.0` and `@export var vault_height_boost: float = 1.2`.
2. Implement `gather_proposals`: Return proposal if `LedgeService.can_vault()` and moving into it. (Edge case: Sprinting into a Low Wall).
2. Implement `tick`: Apply short upward and forward impulse, drop proposal.
3. Attach to `AutoVaultMotor` node.

### Step 12: `scripts/player_action_stack/movement/motors/climb_motor.gd` (new)
**What this file is:** Handles spherical surface climbing.
**Extends:** `BaseMotor`
**Actions:**
1. Add `@export var climb_speed: float = 2.5` and `@export var stamina_cost_per_sec: float = 5.0`.
2. Implement `gather_proposals`: Return proposal if `LedgeService.can_climb()`.
2. Implement `tick`: Use `LedgeService.get_climb_normal()` to align `body.up_direction`. Drain stamina. Apply climbing velocity. Disable gravity.
3. Attach to `ClimbMotor` node.

### Step 13: `scripts/player_action_stack/movement/motors/mantle_motor.gd` (new)
**What this file is:** Heavy ledge pull-up.
**Extends:** `BaseMotor`
**Actions:**
1. Add `@export var mantle_vertical_speed: float = 4.0` and `@export var mantle_forward_speed: float = 3.0`.
2. Implement `gather_proposals`: Return proposal if `LedgeService.can_mantle()`.
2. Implement `tick`: Disable gravity, interpolate `body` up and over the lip.
3. Attach to `MantleMotor` node.

### Step 14: `scripts/player_action_stack/movement/movement_broker.gd` (new)
**What this file is:** Central state machine arbitrating motors.
**Extends:** `Node`
**Actions:**
1. Add `signal state_changed(old_mode, new_mode)`.
2. Add `@export var motor_map: Dictionary` to map integer states to `NodePath`s for the respective motors.
3. In `_ready()`, gather the motors from the `motor_map` into a fast lookup dictionary.
4. In `_physics_process(delta)`:
   - Call `PlayerBrain.get_intents()`.
   - Call `update_facts()` on all Services.
   - Loop motors and call `gather_proposals()`.
   - Find highest Priority/Weight proposal (Edge case: Multi-Source Transition Collision).
   - If the proposal array is empty, default the `current_mode` to Fall (e.g., state `3`).
   - Update `current_mode`. If changed, emit `state_changed(old, new)`.
   - Lookup the winning motor using the state-to-motor dictionary and call `tick()` on it.
   - Call `body.move_and_slide()`.
4. **Debug hook:** Call `DebugOverlay.push(1, {"state": current_mode, "vel": body.velocity})`.
5. Attach to `MovementBroker` node.

### Step 15: `scripts/player_action_stack/camera/camera_rig.gd` (new)
**What this file is:** Top level camera controller.
**Extends:** `Node3D`
**Actions:**
1. Add `@export var landing_dip_intensity: float = 0.5` and `@export var landing_dip_recovery_speed: float = 8.0`. Add `var _current_dip: float = 0.0`.
2. Implement `_ready()`: Find `MovementBroker` and connect to `state_changed` signal.
3. Implement `_process(delta)`: Instantly snap X/Z to `Body.global_position`. Lerp `_current_dip` back to `0.0` using `landing_dip_recovery_speed`. Lerp Y toward `Body.global_position.y - _current_dip` to smooth out stairs and dips.
4. Implement `_on_locomotion_state_changed`: If transitioning from Fall to Ground (Walk/Sprint/Idle), subtract `landing_dip_intensity` from `_current_dip` to trigger the landing dip effect.
4. Attach to `CameraRig` node.

## Verification Checklist

- [ ] Press F5 — project launches without errors.
- [ ] Walk into a slope > 45 degrees — player slides down. (Edge Case 1)
- [ ] Sprint until stamina is exhausted — player forces back to walk. (Edge Case 3)
- [ ] Run into a waist-high block — player automatically hops over without losing speed. (Edge Case 2)
- [ ] Jump and land — camera applies a visual "dip" upon hitting the ground. (Feel Contract)
- [ ] Walk up stairs — camera and visuals glide smoothly upwards without jitter. (Feel Contract)
- [ ] Press F1 — debug panel appears showing `state` and `vel`.
