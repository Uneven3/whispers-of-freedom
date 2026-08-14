# Enforcement Checklist: Ground Movement & Stamina

**Derived from:** mechanic-designs/ground-movement-and-stamina.md + execution-plans/ground-movement-and-stamina.md
**Version:** 2026-04-22

## Universal Rules

| # | Rule | Source | Violation Pattern |
|---|------|--------|------------------|
| U1 | Full static typing | `06-interfaces-and-contracts` | `var x` without type annotation |
| U2 | No magic numbers | `06-interfaces-and-contracts` | Numeric literal in logic (not in `@export` or `const`) |
| U3 | `_process`/`_physics_process` restricted | `02-data-flow` | Running `_physics_process` arbitrarily instead of strictly separating logic (e.g. Visuals must use `_process` for lerp, Brokers use `_physics_process` for ticks). |
| U4 | No sideways node access | `02-data-flow` | Calling methods directly on siblings instead of routing through the Broker or relying on explicit `@export`/`@onready` dependency injection mapped in the plan. |
| U5 | Signal-only cross-node communication | `02-data-flow` | Direct method call on a non-child node across systems. |
| U6 | No group iteration in hot paths | `02-data-flow` | `get_tree().get_nodes_in_group()` inside `_process` or `_physics_process`. |
| U7 | Input decoupled to Brain | `06-interfaces-and-contracts` | `Input.get_action_strength()` used directly inside a Motor instead of reading from `Intents`. |
| U8 | Subclass compliance | `06-interfaces-and-contracts` | Motor extending `Node` instead of `BaseMotor`. |

## Mechanic-Specific Rules

| # | Rule | Source | Violation Pattern | Consequence |
|---|------|--------|------------------|-------------|
| M1 | **Visuals decoupling** | Design Level 2 | Modifying `VisualsPivot` global position directly inside a Motor's `tick()`. | Jitter returns. The VisualsPivot must `lerp` independently in `_process` using the Body's position as a target, completely ignoring the motors. |
| M2 | **Camera framerate sync** | Design Level 3 | `CameraRig` using `_physics_process`. | Camera movement will lock to 60hz, causing massive visual stutter on high refresh rate monitors during physics snaps. |
| M3 | **Motor State Mapping** | Execution Plan Step 14 | `MovementBroker` uses hardcoded `if/else` block to call `tick()` on child nodes. | Brittle state machine. Broker must use the `@export var motor_map: Dictionary` to map integers dynamically. |
| M4 | **Stamina Encapsulation** | Design Level 4 | Motors directly mutating `stamina.current_stamina -= x`. | Bypasses limits and signal emission. Must use `stamina.drain()` and `stamina.recover()`. |

## Edge Case Rules

| # | Edge Case | Required Handling | Violation |
|---|-----------|------------------|-----------|
| E1 | Multi-Source Transition Collision | `MovementBroker` must find the highest Priority/Weight proposal. If empty, default to Fall state (e.g. `3`). | Broker crashes if array is empty, or uses arbitrary array index `[0]`. |
| E2 | Hit-Stop & Transform Sync | `VisualsPivot` MUST use `_process(delta)` for interpolation. | Using `_physics_process` or fixed interpolation that ignores engine time scale. |
| E3 | Stamina Exhaustion Mid-Action | `SprintMotor` and `ClimbMotor` MUST check `!stamina.is_exhausted()` before returning a proposal. | Proposing a stamina-draining transition while exhausted. |
| E4 | Slope Limit Reached | `GroundService` MUST compute slope angle against Vector3.UP. If `> max_slope_angle_deg`, it must return `false` for `is_on_floor()`. | Using a built-in `is_on_floor()` without checking the angle explicitly, causing climbing on walls. |
| E5 | Sprinting into a Low Wall | `AutoVaultMotor` MUST propose a transition if `LedgeService.can_vault()` is true. | Ignoring the service and getting stuck on waist-high geometry. |
| E6 | Reaching the Top of a Climb | `MantleMotor` MUST disable gravity and manually interpolate the `Body` over the lip. | Leaving gravity enabled, causing the player to fall while mantling. |
