# Mechanic Design: Ground Movement & Stamina

**Phase:** mechanic-2
**Status:** Approved
**Started:** 2026-04-22
**Approved:** 2026-04-22

## Feel Contract
Moving feels immediate—no input lag. Stopping feels deliberate, not floaty. Landing from high jumps has weight (camera dip, audio impact).

## Level 1: Scope Adherence

**In scope:**
- **Walk, Sprint, Sneak, Jump, Fall:** Explicitly allowed by the Movement System's motor list.
- **Climb, WallJump, Mantle, AutoVault:** Explicitly allowed by the Movement System's motor list. AutoVault handles small obstacles.
- **Stamina drain:** Allowed by the `StaminaComponent` definition. 
- **Camera Dip on landing:** Explicitly allowed by the Camera System's "Effects". 
- **Signal emission for audio:** Allowed by the cross-system data flow.

**Flagged / cut:**
- *(none)*

**Ambiguities resolved:**
- **"Immediate moving, deliberate stopping":** Resolved via `@export` tunable values for ground acceleration and friction.
- **Stair & Mantle Smoothing (Camera Decoupling):** The physics capsule will snap instantly to stairs and ledges, which can be violent. To prevent screen shake, the `CameraRig` will apply strict lerp/smoothing on the vertical (Y) axis. The visual mesh (`VisualsPivot`) will also be interpolated separately from the collision capsule.
- **Spherical Climbing:** Climbing will orient the player to the surface normal using `Quaternion` alignment, not just flat wall traces, allowing traversal of curved and spherical surfaces.
- **Small Obstacle Mantling:** Delegated to the `AutoVaultMotor`, which triggers automatically when running into waist-high obstacles, distinct from the heavy `MantleMotor` used at the top of high climbs.

## Level 2: Component Assignment

**Existing components used:**
- `EntityController > PlayerBrain` — Translates raw input into the unified `Intents` struct.
- `EntityController > MovementBroker` — Receives `Intents` and arbitrates which Motor gets to run.
- `EntityController > WalkMotor`, `SprintMotor`, `SneakMotor` — Ground locomotion handlers.
- `EntityController > JumpMotor`, `FallMotor` — Aerial handlers.
- `EntityController > ClimbMotor` — Handles spherical surface normal alignment and climbing velocity.
- `EntityController > WallJumpMotor` — Handles launching away from the climb normal.
- `EntityController > MantleMotor` — Heavy ledge pull-up.
- `EntityController > AutoVaultMotor` — Quick hop over small waist-high obstacles.
- `EntityController > StaminaComponent` — Pure data node tracking effort.
- `EntityController > Body` — The `CharacterBody3D` wrapper.
- `CameraRig` (Top level scene) — Follows the player.

**Composition decisions:**
- **Floor & Stair Physics** → Isolated into `GroundService`. The motors ask it for floor state rather than casting their own downward rays.
- **Ledge Detection** → Isolated into `LedgeService`. It runs dedicated `ShapeCast3D`s to find climbable surfaces, mantle lips, and small vaultable obstacles, exposing booleans like `can_mantle` or `can_vault`.
- **Stair & Mantle Smoothing (Camera Decoupling)** → *Note: We must focus heavily on proving stair movement works smoothly in graybox.* The `Body` node will use Godot's native `step_height` to instantly snap up stairs, preventing physics snags. To hide this jerky movement, the `VisualsPivot` and the `CameraRig` will independently `lerp()` their Y-axis positions to follow the `Body` smoothly.

## Level 3: Data & State Flow

**Input:**
- **Trigger:** Godot `InputMap` actions (`move_forward`, `jump`, `sprint`, `sneak`).
- **Source:** The `PlayerBrain` reads these in Slot 1 and populates the `Intents` struct (`move_dir`, `wants_jump`, etc.).

**State mutations:**
- `Body.velocity` (Vector3) — Mutated by the Active Motor in Slot 5.
- `StaminaComponent.value` (float) — Drained by `SprintMotor`, `ClimbMotor`, and `WallJumpMotor` in Slot 5. Regained by `WalkMotor`/`SneakMotor` when resting.
- `LocomotionState._active_mode` (int) — Changed by `MovementBroker` in Slot 4.
- `VisualsPivot.position` (Vector3) — Interpolated toward `Body.position` during `_process` (to decouple from `_physics_process` stair-snapping).

**Output:**
- **World State:** The `Body` calls `move_and_slide()` in Slot 6.
- **Signals emitted:**
  - `LocomotionState.state_changed(old, new)` → Listened to by Camera/Audio.
  - `StaminaComponent.stamina_changed(value, max)` → Listened to by UI/Combat.

**Flow compliance:**
- Validated against `02-data-flow-player-action-stack.md`. Data strictly flows down the 6-slot execution array without skipping steps.

## Level 4: Contract Mapping

*Note: For brevity, only unique properties and overrides are stubbed. All Motors extend `BaseMotor` and all Services extend `BaseService`.*

### `GroundService` (`res://scripts/player_action_stack/movement/services/ground_service.gd`)
Extends `BaseService`. Owns floor/stair detection.

```gdscript
class_name GroundService
extends BaseService

# — Configuration —
@export var max_step_height: float = 0.3
@export var max_slope_angle_deg: float = 45.0

# — Internal state —
var _is_on_floor: bool = false
var _floor_normal: Vector3 = Vector3.UP

func update_facts(body_reader: BodyReader) -> void:
    pass # graybox-5: run Shapecast logic here

func is_on_floor() -> bool:
    return _is_on_floor

func get_floor_normal() -> Vector3:
    return _floor_normal
```

### `LedgeService` (`res://scripts/player_action_stack/movement/services/ledge_service.gd`)
Extends `BaseService`. Owns mantle, vault, and climb surface detection.

```gdscript
class_name LedgeService
extends BaseService

@export var vault_max_height: float = 1.0
@export var mantle_max_height: float = 2.5

func update_facts(body_reader: BodyReader) -> void:
    pass

func can_climb() -> bool:
    return false

func get_climb_normal() -> Vector3:
    return Vector3.ZERO

func can_vault() -> bool:
    return false
    
func can_mantle() -> bool:
    return false
```

### `WalkMotor` (`res://scripts/player_action_stack/movement/motors/walk_motor.gd`)
Extends `BaseMotor`.

```gdscript
class_name WalkMotor
extends BaseMotor

@export var max_speed: float = 5.0
@export var acceleration: float = 20.0
@export var friction: float = 15.0

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    return []

func tick(delta: float, intents: Intents, body: Body, stamina: StaminaComponent, services: Array) -> void:
    pass # graybox-5: apply acceleration/friction based on intents.move_dir
```

### `SprintMotor` (`res://scripts/player_action_stack/movement/motors/sprint_motor.gd`)
Extends `BaseMotor`.

```gdscript
class_name SprintMotor
extends BaseMotor

@export var sprint_speed: float = 8.0
@export var sprint_acceleration: float = 15.0
@export var stamina_cost_per_sec: float = 10.0

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    return []

func tick(delta: float, intents: Intents, body: Body, stamina: StaminaComponent, services: Array) -> void:
    pass 
```

### `JumpMotor` (`res://scripts/player_action_stack/movement/motors/jump_motor.gd`)
Extends `BaseMotor`.

```gdscript
class_name JumpMotor
extends BaseMotor

@export var jump_impulse: float = 12.0
@export var horizontal_speed_boost: float = 2.0

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    return []

func tick(delta: float, intents: Intents, body: Body, stamina: StaminaComponent, services: Array) -> void:
    pass 
```

### `ClimbMotor` (`res://scripts/player_action_stack/movement/motors/climb_motor.gd`)
Extends `BaseMotor`.

```gdscript
class_name ClimbMotor
extends BaseMotor

@export var climb_speed: float = 2.5
@export var stamina_cost_per_sec: float = 5.0

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    return []

func tick(delta: float, intents: Intents, body: Body, stamina: StaminaComponent, services: Array) -> void:
    pass # graybox-5: apply climbing velocity. Do NOT mutate visual root.
```

### `VisualsPivot` (`res://scripts/player_action_stack/movement/visuals_pivot.gd`)

```gdscript
class_name VisualsPivot
extends Node3D

@export var interpolation_speed: float = 20.0
@export var rotation_smoothing_speed: float = 12.0
@onready var _body: Body = $"../Body"

func _ready() -> void:
    top_level = true # Detach from parent transform so we can lerp independently

func _process(delta: float) -> void:
    pass # graybox-5: interpolate global_position.
    # graybox-5: align rotation using quaternion toward normal from Ground/Ledge service based on LocomotionState.
```

### `AutoVaultMotor` (`res://scripts/player_action_stack/movement/motors/auto_vault_motor.gd`)
Extends `BaseMotor`.

```gdscript
class_name AutoVaultMotor
extends BaseMotor

@export var vault_speed: float = 8.0
@export var vault_height_boost: float = 1.2

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    return []

func tick(delta: float, intents: Intents, body: Body, stamina: StaminaComponent, services: Array) -> void:
    pass # graybox-5: apply quick root motion over low obstacle
```

### `MantleMotor` (`res://scripts/player_action_stack/movement/motors/mantle_motor.gd`)
Extends `BaseMotor`.

```gdscript
class_name MantleMotor
extends BaseMotor

@export var mantle_vertical_speed: float = 4.0
@export var mantle_forward_speed: float = 3.0

func gather_proposals(current_mode: int, intents: Intents, services: Array) -> Array[TransitionProposal]:
    return []

func tick(delta: float, intents: Intents, body: Body, stamina: StaminaComponent, services: Array) -> void:
    pass # graybox-5: disable gravity, interpolate Body up and over the lip
```

### `CameraRig` (`res://scripts/player_action_stack/camera/camera_rig.gd`)
Top level camera controller.

```gdscript
class_name CameraRig
extends Node3D

@export var y_smoothing_speed: float = 15.0
@export var landing_dip_intensity: float = 0.5
@export var landing_dip_recovery_speed: float = 8.0

func _ready() -> void:
    # graybox-5: connect to LocomotionStateReader.state_changed
    pass

func _on_locomotion_state_changed(old_mode: int, new_mode: int) -> void:
    pass # graybox-5: if old_mode == FALL and new_mode == WALK/SPRINT/IDLE, trigger landing dip
```

## Level 5: Edge Case Coverage

### System Edge Cases (from 03-edge-cases)

- **Multi-Source Transition Collision:** (e.g., Player inputs 'Jump' on the exact same frame Combat injects a `FORCED` Stagger). **Resolution:** `MovementBroker` arbitrates. `JumpMotor` proposes as `PLAYER_REQUESTED`, which strictly loses to the `FORCED` stagger. Player gets staggered.
- **Hit-Stop & Transform Sync:** Time scales down during combat hitpause. **Resolution:** `VisualsPivot` uses `_process` delta for interpolation. Because `_process` respects `Engine.time_scale`, the visual smoothing will correctly slow down in sync with the physics engine.
- **Stamina Exhaustion Mid-Action:** Stamina hits 0 while climbing or sprinting. **Resolution:** `SprintMotor` checks `StaminaComponent.is_exhausted()`; if true, it stops proposing, allowing `WalkMotor` to take over. `ClimbMotor` stops proposing, allowing `FallMotor` to take over (player falls off wall).

### Mechanic-Specific Edge Cases

- **Slope Limit Reached:** Player walks into a slope steeper than 45 degrees. → **Resolution:** `GroundService` evaluates floor normal against `max_slope_angle_deg`. If exceeded, `is_on_floor()` returns false. `WalkMotor` drops its proposal, `FallMotor` takes over, and gravity slides the player down.
- **Sprinting into a Low Wall:** Player maintains sprint momentum into a knee-high obstacle. → **Resolution:** `LedgeService` detects the low obstacle and returns true for `can_vault()`. `AutoVaultMotor` proposes an `OPPORTUNISTIC` transition to snap over it without losing speed.
- **Reaching the Top of a Climb:** Player climbs past the top edge of a spherical or flat wall. → **Resolution:** `LedgeService.can_mantle()` returns true when the raycasts clear the lip. `MantleMotor` proposes, disabling gravity and interpolating the `Body` up and over the ledge.

## Implementation Handoff

**Reading order for the Code Writer (`graybox-5`):**
1. Read this document top to bottom.
2. Read `docs/architecture/rationale/06-interfaces-and-contracts-player-action-stack.md` for base class definitions.
3. Open `graybox-prototype/` and locate the nodes listed in Level 2.
4. Implement each stub from Level 4 in order, ensuring `GroundService` and `LedgeService` use proper `ShapeCast3D` setups.
5. Apply Godot native `step_height` to the `CharacterBody3D` (`Body`).
6. Verify each edge case from Level 5 manually after implementation.
7. Test against the feel contract.

**Open questions for the implementing agent:**
- Ensure the `VisualsPivot` Y-axis lerp speed (`interpolation_speed`) is tuned high enough to avoid a "laggy" camera feeling, but low enough to absorb the harsh instantaneous Z-axis steps of the `CharacterBody3D` on stairs.
