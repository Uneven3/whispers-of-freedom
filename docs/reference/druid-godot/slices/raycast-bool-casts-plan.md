# Slice Plan: Replace Boolean-Only ShapeCast3D Nodes with RayCast3D in LedgeService

## Goal
Replace the three ShapeCast3D nodes (`_head_cast`, `_left_cast`, `_right_cast`) in `LedgeService` with `RayCast3D` nodes. These three casts are used exclusively for `is_colliding()` boolean queries and never call `get_collision_point()` or `get_collision_normal()`, making the sphere-sweep overhead unnecessary.

## Architecture Map Target
Modification of an existing Service script (`LedgeService`) under `services/`. No public surface changes — all consumer-facing methods (`has_wall_left()`, `has_wall_right()`, `can_climb()`, `can_continue_climbing()`) remain identical in signature and semantics.

## Constitution Clauses Involved
- **P5** — RayCast3D does not register a process callback; it is driven manually via `force_raycast_update()` on demand. Compliance is maintained: no `_process` or `_physics_process` override is added. The existing `set_process(false)` / `set_physics_process(false)` calls in `_ready()` are unchanged.
- **G5** — No new public surfaces are introduced, so no new boundary assertions are required. The existing public methods remain unchanged.
- **G1** — No structural concern: line count decreases slightly; single concern (ledge detection) is maintained.

## Playbooks Referenced
None applicable.

## File Touches
- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`:
  1. Change the declared types of `_head_cast`, `_left_cast`, and `_right_cast` from `ShapeCast3D` to `RayCast3D`.
  2. Add a `_create_forward_raycast(y_pos: float) -> RayCast3D` helper that:
     - Creates a `RayCast3D` node.
     - Sets `target_position` to `Vector3(0, 0, -1.0)` (same placeholder as the old helper).
     - Sets `position` to `Vector3(0, y_pos, 0)`.
     - Sets `collision_mask` to `1`.
     - Calls `add_child(cast)` and returns the node.
     - Does NOT assign `.shape` (RayCast3D has no shape property).
     - Sets `enabled = false` so the node does not auto-process (P5 compliance); updates are driven entirely by `force_raycast_update()`.
  3. In `_ready()`, replace the two `_create_forward_cast(...)` calls that create `_head_cast`, `_left_cast`, and `_right_cast` with `_create_forward_raycast(...)` calls using the same `y_pos` arguments:
     - `_head_cast  = _create_forward_raycast(1.5)`
     - `_left_cast  = _create_forward_raycast(0.5)`
     - `_right_cast = _create_forward_raycast(0.5)`
  4. In `update_facts()`, replace every call to `_head_cast.force_shapecast_update()` with `_head_cast.force_raycast_update()`.
  5. In `update_facts()`, replace every call to `_left_cast.force_shapecast_update()` and `_right_cast.force_shapecast_update()` with `_left_cast.force_raycast_update()` and `_right_cast.force_raycast_update()` respectively. This covers both the `if _climb_normal != Vector3.ZERO` branch and the `else` branch.
  6. Leave `_waist_cast`, `_down_cast`, and `_vault_landing_cast` completely untouched — they remain `ShapeCast3D` and continue to use `force_shapecast_update()`.
  7. Leave the `_create_forward_cast` helper in place — it is still used by `_waist_cast`.

## Pre-implementation Checklist
- [x] `_head_cast`, `_left_cast`, `_right_cast` declared as `RayCast3D` (not `ShapeCast3D`).
- [x] `_create_forward_raycast` helper sets `enabled = false` to prevent implicit auto-process ticking (P5).
- [x] `_create_forward_raycast` does not assign `.shape` (RayCast3D has no shape).
- [x] All three new nodes use `force_raycast_update()` — no leftover `force_shapecast_update()` calls on them.
- [x] `_waist_cast`, `_down_cast`, `_vault_landing_cast` are untouched and still use `force_shapecast_update()`.
- [x] `_create_forward_cast` (ShapeCast3D) helper is preserved — still needed for `_waist_cast`.
- [x] No new public methods or signals introduced (G5 — no new boundary assertions needed).
- [x] No changes to `has_wall_left()`, `has_wall_right()`, `can_climb()`, `can_continue_climbing()` signatures or semantics.
