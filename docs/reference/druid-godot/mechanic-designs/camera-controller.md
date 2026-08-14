# Mechanic Design: Camera Controller

**Phase:** mechanic-2
**Status:** Approved
**Started:** 2026-04-22
**Approved:** 2026-04-22

## Feel Contract
The camera feels like a physical observer. It smooths out jitter, snaps quickly when aiming, and frames combat dynamically without giving motion sickness.

## Level 1: Scope Adherence

**In scope:**
- **Follow Mode:** Default 3rd-person orbital camera. Allowed by Camera System.
- **Aim Mode:** Tight over-the-shoulder framing for the Bow. Allowed by Camera System.
- **Lock-On Mode:** Frames both the player and the combat target. Allowed by Camera System.
- **Effects (Shake, Dip, FOVZoom):** Allowed by Camera System.
- **Inputs:** `look_delta` (mouse/stick), `wants_aim`, `wants_lock_on_toggle`.

**Flagged / cut:**
- **Per-form reframing:** The camera will NOT change its baseline distance or height based on Form. The architecture explicitly bans the Camera from knowing about the Form system to maintain decoupling. 

**Ambiguities resolved:**
- **"Smooths out jitter":** The Camera will read the raw physics `Body` but strictly `lerp` its own translation on the Y-axis so it doesn't violently shake when walking up stairs.
- **"Without giving motion sickness":** The `SpringArm3D` automatically handles pushing the camera in when backed against a wall. Shifting into `LockOnMode` will use a dampened rotational `lerp` rather than an instantaneous snap to the enemy.

## Level 2: Component Assignment

**Existing components used:**
- `CameraRig (Node3D)` — The top-level scene root. It exposes the `set_target(BodyReader)` method.
- `CameraBrain (Node)` — Translates raw inputs into the immutable `CameraInput` struct.
- `CameraBroker (Node)` — The state machine. Reads `CameraInput`, routes it to the active Mode.
- `FollowMode (Node)` — The default orbital logic.
- `AimMode (Node)` — Over-the-shoulder logic for archery.
- `LockOnMode (Node)` — Two-target framing logic.
- `DipEffect`, `FOVZoomEffect (Node)` — Additive modifiers that tweak the final transform.
- `Lens (SpringArm3D)` — The proxy that physically rotates.
- `Camera3D` — The actual Godot camera, attached to the end of the `Lens`.

**Composition decisions:**
- **Wall Collisions** → Isolated from GDScript. By using `SpringArm3D` as the `Lens`, the C++ physics engine automatically handles pushing the camera inward when backed against a wall.
- **Input Decoupling** → Isolated into `CameraBrain`. If we want a `CinematicDirector` to take over, we swap the Brain; the Broker stays the same.
- **Additive Effects** → Shake and Dip are isolated into `Effect` nodes rather than hardcoded math in the modes, allowing them to stack on top of any active mode.

## Level 3: Data & State Flow

**Input:**
- **Trigger:** Godot `InputMap` actions (`camera_left`, `camera_right`, `camera_up`, `camera_down`, `aim_toggle`, `lock_on_toggle`).
- **Source:** The `CameraBrain` reads these during `_process` and populates the `CameraInput` struct.

**State mutations (occurring in `_process`):**
- `CameraRig.global_position` (Vector3) — Snaps instantly to the `BodyReader`'s X and Z coordinates, but uses `lerp()` on the Y-axis to smooth out stairs and slopes.
- `CameraBroker.current_mode` (Enum) — Transitions between Follow, Aim, and LockOn based on `CameraInput` toggles.
- `Lens.rotation` (Vector3) — Mutated by the active mode. (e.g., `FollowMode` adds the input `look_delta` to the yaw and pitch).
- `Lens.spring_length` (float) — Mutated by the active mode (e.g., pulling in to 1.5m for Aiming, pushing out to 4.0m for Follow).
- `Camera3D.fov` (float) — Mutated by `AimMode` (zooming in) or additive `FOVZoomEffect`.

**Output:**
- **World State:** The rendering viewport is updated.
- **Signals:** The Camera system acts as a sink. It listens to external systems:
  - `LocomotionStateReader.state_changed` → Triggers `DipEffect` on landing.
  - `CombatStateReader.hit_registered` → Triggers `ShakeEffect`.

**Flow compliance:**
- Validated against `02-data-flow-player-action-stack.md`. The Camera operates exclusively in `_process`. Because it interpolates using `delta`, it runs at the monitor's framerate, completely masking the stutter of the 60hz physics ticks happening underneath it.

## Level 4: Contract Mapping

### `CameraRig` (`res://scripts/player_action_stack/camera/camera_rig.gd`)
Top level camera root.

```gdscript
class_name CameraRig
extends Node3D

@export var y_smoothing_speed: float = 15.0

@onready var _lens: SpringArm3D = $Lens
@onready var _camera: Camera3D = $Lens/Camera3D

var _body_reader: BodyReader

func set_target(body_reader: BodyReader) -> void:
    _body_reader = body_reader

func _process(delta: float) -> void:
    pass # graybox-5: snap X/Z to target, lerp Y
```

### `CameraBroker` (`res://scripts/player_action_stack/camera/camera_broker.gd`)
State machine for camera modes.

```gdscript
class_name CameraBroker
extends Node

var current_mode: int = 0 # 0: Follow, 1: Aim, 2: LockOn

func tick(delta: float, input: CameraInput, current_transform: Transform3D) -> Transform3D:
    pass # graybox-5: route to active mode based on current_mode. If input.lock_on_target == null, force Follow.
```

### `BaseCameraMode` (`res://scripts/player_action_stack/camera/modes/base_camera_mode.gd`)
Base class for all modes.

```gdscript
class_name BaseCameraMode
extends Node

@export var target_spring_length: float = 4.0
@export var target_fov: float = 75.0

func tick(delta: float, input: CameraInput, current_transform: Transform3D) -> Transform3D:
    return current_transform
```

### `FollowMode` (`res://scripts/player_action_stack/camera/modes/follow_mode.gd`)
Extends `BaseCameraMode`.

```gdscript
class_name FollowMode
extends BaseCameraMode

@export var look_sensitivity_x: float = 0.5
@export var look_sensitivity_y: float = 0.5
@export var pitch_limit_down_deg: float = -60.0
@export var pitch_limit_up_deg: float = 60.0

func tick(delta: float, input: CameraInput, current_transform: Transform3D) -> Transform3D:
    pass # graybox-5: apply mouse/stick delta to yaw and pitch, clamp pitch
```

### `AimMode` (`res://scripts/player_action_stack/camera/modes/aim_mode.gd`)
Extends `BaseCameraMode`.

```gdscript
class_name AimMode
extends BaseCameraMode

@export var aim_sensitivity_multiplier: float = 0.5
# spring_length inherited, set to 1.5 in inspector
# fov inherited, set to 60.0 in inspector

func tick(delta: float, input: CameraInput, current_transform: Transform3D) -> Transform3D:
    pass # graybox-5: apply dampened look delta
```

### `LockOnMode` (`res://scripts/player_action_stack/camera/modes/lock_on_mode.gd`)
Extends `BaseCameraMode`.

```gdscript
class_name LockOnMode
extends BaseCameraMode

@export var rotation_dampening: float = 10.0
@export var occlusion_break_time: float = 1.5

func tick(delta: float, input: CameraInput, current_transform: Transform3D) -> Transform3D:
    pass # graybox-5: check is_instance_valid(input.lock_on_target). If valid, compute midpoint and slerp rotation.
    # graybox-5: run occlusion raycast. If occluded, increment timer. Return to Follow if > occlusion_break_time.
```

### `DipEffect` (`res://scripts/player_action_stack/camera/effects/dip_effect.gd`)

```gdscript
class_name DipEffect
extends Node

@export var intensity: float = 0.5
@export var recovery_speed: float = 8.0

var _current_offset: float = 0.0

func trigger() -> void:
    _current_offset = intensity

func apply_effect(delta: float, base_transform: Transform3D) -> Transform3D:
    pass # graybox-5: subtract _current_offset from Y, lerp _current_offset to 0 over time
```

### `ShakeEffect` (`res://scripts/player_action_stack/camera/effects/shake_effect.gd`)

```gdscript
class_name ShakeEffect
extends Node

@export var max_shake_intensity: float = 1.0
@export var shake_decay: float = 5.0
@export var noise: FastNoiseLite

var _current_trauma: float = 0.0

func trigger(trauma: float) -> void:
    _current_trauma = min(_current_trauma + trauma, 1.0)

func apply_effect(delta: float, base_transform: Transform3D) -> Transform3D:
    pass # graybox-5: compute noise offset based on _current_trauma^2, decay trauma, add to transform
```

## Level 5: Edge Case Coverage

### System Edge Cases (from 03-edge-cases)

- **Hit-Stop & Transform Sync:** Engine timescale drops to `0.1` during heavy combat impacts. **Resolution:** Because the camera exclusively uses `_process(delta)` for its `lerp` operations, the delta will naturally shrink. The camera will slow down in perfect sync with the action, preventing it from wildly swinging around while the player is in slow-motion.

### Mechanic-Specific Edge Cases

- **Target Dies during LockOn:** The player is locked on, and the enemy is killed. → **Resolution:** The Camera System does not read internal enemy state. Instead, the `CameraBrain` listens to `CombatBroker`'s target clearing signals. If the target dies, `CameraBrain` passes `null` into `CameraInput.lock_on_target`. The `CameraBroker` sees `null` and instantly forces a return to `FollowMode`. Additionally, `LockOnMode` uses Godot's safe `is_instance_valid()` check to prevent crashes if the node is unexpectedly freed.
- **Target breaks Line of Sight:** The locked-on enemy runs behind a solid wall. → **Resolution:** To prevent the camera from staring at a blank wall indefinitely, `LockOnMode` implements a soft-break timer. If the target is occluded for more than 1.5 seconds, the lock is broken and it reverts to `FollowMode`.
- **Camera backed into a corner:** The player backs into a tight corner, forcing the `SpringArm3D` length to nearly `0`. → **Resolution:** The `SpringArm3D` natively prevents the camera from clipping through the wall. To prevent the camera from clipping into the back of the player's head, the `VisualsPivot` material will use Godot's built-in "Distance Fade" (Pixel Dither) to turn the player transparent when the camera is closer than 0.5 meters.

## Implementation Handoff

**Reading order for the Code Writer (`graybox-5`):**
1. Read this document top to bottom.
2. Read `docs/architecture/rationale/06-interfaces-and-contracts-player-action-stack.md` for base class definitions.
3. Open `graybox-prototype/` and instantiate the `CameraRig` scene structure exactly as described in Level 2.
4. Add a `SpringArm3D` named `Lens` and attach a `Camera3D` to it. Ensure the `SpringArm3D` collision mask is set to environment geometry only (not the player).
5. Implement the Level 4 stubs.
6. Verify that `CameraRig` operates exclusively in `_process`.

**Open questions for the implementing agent:**
- Ensure the transition between `FollowMode` and `LockOnMode` uses a smooth quaternion spherical-lerp (`slerp()`) rather than an instant `look_at()`. Instant snapping is the #1 cause of motion sickness in 3D cameras.


