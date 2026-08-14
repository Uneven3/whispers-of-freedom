# Testing Guidelines

## Framework

- **GUT 9.6.0** — installed at `graybox-prototype/addons/gut/`
- **Test locations:** `res://test/unit/` (pure logic), `res://test/integration/` (scene/node tests)
- **Naming convention:** `test_<class_or_concern>.gd`, test methods prefixed `test_`
- **Run in editor:** GUT Panel in bottom dock → Run All
- **Run headless:** `godot --headless --path graybox-prototype -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`

## Assert vs push_error Policy

Per Constitution G5:
- Use `assert(condition, "intent message")` for **programmer-error invariants** — wrong type passed to `_init`, internal misuse. Stripped from release exports.
- Use `push_error("intent message")` + early-return for **runtime-reachable failures** — bad designer values, missing optional nodes, loaded data validation. Survives release.

## Test Tier Structure

| Tier | Directory | Dependencies | Examples |
|------|-----------|--------------|---------|
| 0 | `test/unit/` | None | Smoke test |
| 1 | `test/unit/` | None (pure GDScript classes) | `Intents`, `TransitionProposal`, `LedgeFacts`, `StaminaComponent` |
| 2 | `test/unit/` | Small scene fixture via `add_child_autofree` | `LocomotionState`, `BaseMotor._get_service`, Readers |
| 3 | `test/unit/` | Stub motors/services | `MovementBroker` arbitration, motor `gather_proposals` |
| 4 | `test/integration/` | Full scene + physics (`SubViewport`) | `Motor.tick`, `Service.update_facts` |

## What We Test

- **Data class contracts** — default values, field assignment, `reset()` clears all fields (Tier 1)
- **State machine transitions** — `LocomotionState.set_state` validation, `state_changed` signal with correct old/new mode (Tier 2)
- **Boundary validation** — `StaminaComponent.drain/recover` math, clamp to max, exhaustion threshold, `stamina_changed` signal (Tier 1)
- **Proposal arbitration** — `MovementBroker` selects correct motor by Priority category then `override_weight`; exactly one tick per frame; deterministic tie-breaking (Tier 3)
- **Motor proposals** — each motor's `gather_proposals` returns expected proposal (or none) given known intents + current_mode + stub services (Tier 3)

## What We Do NOT Test

The following require the scene tree, physics engine, or rendering and are verified by running the game:

- `_ready()`, `_process()`, `_physics_process()` callbacks
- `Input.*` callbacks and mouse events
- Physics simulation — `move_and_slide()`, raycasts, collision shapes
- Visual rendering, animations, particles
- Scene tree traversal with real node references

## Test File Template

```gdscript
extends GutTest

# Tests for: [ClassName]

var subject

func before_each():
    subject = [ClassName].new()

func after_each():
    subject.free()
    assert_no_new_orphans()

func test_[happy_path_description]():
    # Arrange
    # Act
    var result = subject.some_method(input)
    # Assert
    assert_eq(result, expected_value, "description of expectation")

func test_[edge_case_description]():
    pass  # implement
```

## GUT Assertions Quick Reference

| Assertion | What it checks |
|-----------|----------------|
| `assert_eq(got, expected)` | Equality |
| `assert_ne(got, expected)` | Not equal |
| `assert_true(value)` | Truthy |
| `assert_false(value)` | Falsy |
| `assert_null(value)` | Is null |
| `assert_not_null(value)` | Is not null |
| `assert_gt(got, expected)` | Greater than |
| `assert_lt(got, expected)` | Less than |
| `assert_between(got, from, to)` | In range |
| `assert_has(container, value)` | Array/dict contains value |
| `assert_signal_emitted(obj, "signal_name")` | Signal was emitted |
| `assert_signal_emitted_with_parameters(obj, "signal_name", [params])` | Signal emitted with specific args |
| `assert_no_new_orphans()` | No leaked nodes |

## Watching Signals

```gdscript
func test_signal_fires():
    watch_signals(subject)
    subject.some_method()
    assert_signal_emitted(subject, "some_signal")
```
