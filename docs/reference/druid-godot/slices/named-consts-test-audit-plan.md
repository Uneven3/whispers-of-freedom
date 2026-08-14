# Slice Plan: Named Constants Extraction and Test Signal Audit

## Goal

Extract every unnamed numeric literal from method bodies in the in-scope motor, service, and brain scripts into per-file `const` declarations, naming each constant by its intent. Separately, record a signal-to-noise classification for the existing unit test suite in the solutions doc (no changes to test files).

## Architecture Map Target

- **Motors** (WallJumpMotor, EdgeLeapMotor, SneakMotor, FallMotor, LadderMotor, StairsMotor): per-file `const` blocks added to each motor script.
- **Service** (LedgeService): per-file `const` declarations for method-body literals; the `_h_offsets` array literal is extracted to a named `const`.
- **Brain** (PlayerBrain): the repeated `0.5` / `-0.5` wish_dir thresholds are extracted to a single named `const`.
- No new files. No changes to test files. No changes to `@export` vars or already-named `const`s (e.g., StairsMotor's `CAPSULE_HALF_HEIGHT`, `ASCEND_THRESHOLD`, `DESCEND_THRESHOLD`).

## Constitution Clauses Involved

- **G5** (Boundary validation communicates intent) — primary target: naming every literal makes the intent of each numeric value explicit to future readers and auditors.
- **G1** (Single Responsibility, soft) — adding `const` blocks increases raw line count in already-long files; acceptable because these are pure declarations with zero logic.

## Playbooks Referenced

None.

## File Touches

- `graybox-prototype/scripts/player_action_stack/movement/motors/wall_jump_motor.gd`:
  Add a `const` block after the existing named `JUMP_DURATION` constant. Declare: `WALL_CONTACT_PUSH = 1.0`, `AWAY_UP_BLEND = 0.4`, `AWAY_LEAP_SPEED = 3.5`, `AWAY_NORMAL_PUSH = 4.0`, `LATERAL_SPEED_FRACTION = 0.8`, `LATERAL_VERTICAL_LIFT = 0.5`, `LATERAL_NORMAL_RETRACTION = 0.5`, `BODY_HALF_HEIGHT = 1.0`, `LEDGE_TOP_OFFSET = 0.33`, `FORCED_WEIGHT = 5`. Replace every matching literal in `gather_proposals` and `tick` with the named constant. `AWAY_UP_BLEND` has two use sites (lines 51 and 64) — both must be replaced. `AWAY_LEAP_SPEED` and `AWAY_NORMAL_PUSH` each appear in two branches (lines 52 and 65) — both must be replaced.

- `graybox-prototype/scripts/player_action_stack/movement/motors/edge_leap_motor.gd`:
  Add a `const` block after the existing `LEAP_DURATION` constant. Declare: `FORCED_WEIGHT = 10`, `WALL_PUSH_SPEED = 2.0`. Replace all matching literals in `gather_proposals` and `tick`. Note: `FORCED_WEIGHT = 10` appears at line 34 (entry proposal) and line 38 (sticky proposal) — both must be replaced.

- `graybox-prototype/scripts/player_action_stack/movement/motors/sneak_motor.gd`:
  Add a `const` block at class scope (after `@export` block). Declare: `MOVE_DIR_THRESHOLD_SQ = 0.01`, `ROTATION_SLERP_SPEED = 10.0`, `SNEAK_STAMINA_RECOVER_RATE = 5.0`. The instance var default `_original_height: float = 2.0` is a var default, not a method-body literal — do not extract it (out of scope per solutions analysis). Replace the three literals in `tick`.

- `graybox-prototype/scripts/player_action_stack/movement/motors/fall_motor.gd`:
  Add a single `const` at class scope. Declare: `FALL_STAMINA_RECOVER_FRACTION = 0.25`. Replace the literal `0.25` in the `_stamina.recover(stamina_recover_per_sec * 0.25 * delta)` call inside `tick`.

- `graybox-prototype/scripts/player_action_stack/movement/motors/ladder_motor.gd`:
  Add a `const` block at class scope (after `@export` block). Declare: `MOVE_DIR_THRESHOLD_SQ = 0.01`, `LADDER_TOP_EXIT_CLEARANCE = 0.1`. Replace the two matching literals in `gather_proposals` and `tick`.

- `graybox-prototype/scripts/player_action_stack/movement/motors/stairs_motor.gd`:
  The only unnamed method-body literal is `0.01` (the `has_input` guard at line 75). Add `const INPUT_THRESHOLD_SQ = 0.01` to the class-level const block (alongside the existing `CAPSULE_HALF_HEIGHT`, `CAPSULE_RADIUS`, `LOOKAHEAD_MARGIN`, `DESCEND_TRAIL`). Replace the `0.01` literal in `tick`. Do not touch `ASCEND_THRESHOLD` or `DESCEND_THRESHOLD` — they are already named as local consts inside `tick` and are compliant.

- `graybox-prototype/scripts/player_action_stack/movement/services/ledge_service.gd`:
  Add a `const` block at class scope (after the existing `MIN_DIRECTION_LENGTH_SQUARED` const). Declare:
  - `H_CAST_Y_OFFSETS: Array[float] = [-0.8, -0.6, -0.2, 0.2, 0.4, 0.6]` — replaces the inline array literal in the `_h_offsets` var declaration. The var becomes `var _h_offsets: Array[float] = H_CAST_Y_OFFSETS`. Order must be preserved (ankle → head) because `hits[1]`, `hits[2]`, `hits[5]` are index-dependent.
  - `DOWN_CAST_MARGIN = 0.1` — replaces `0.1` in `_ready` at the `_down_cast` position y calculation.
  - `DOWN_CAST_FORWARD_OFFSET = 1.0` — replaces `1.0` in `_ready` at `_down_cast.position = Vector3(0, ..., -1.0)`.
  - `FORWARD_CAST_SPHERE_RADIUS = 0.1` — replaces `0.1` in `_create_forward_cast` and `_create_down_cast` (both sphere radius assignments). The two sites share the same value; a single const is correct.
  - `LATERAL_CAST_Y_OFFSET = 0.5` — replaces `0.5` in `_ready` at both `_left_cast` and `_right_cast` `_create_forward_raycast(0.5)` calls.
  - `FORWARD_SAMPLE_OFFSET = 1.0` — replaces `1.0` in `update_facts` at `pos + facing * 1.0` for the `_down_cast` global position.
  - `VAULT_DIST_MARGIN = 0.2` — replaces `0.2` in `update_facts` at `var v_dist: float = min_dist + 0.2`.
  - `STEEP_FACE_NORMAL_Y_MAX = 0.75` — replaces `0.75` in `_detect_vault` at the `n.y < 0.75` steep-face check. Note: the solutions doc lists this as `0.75`; the code at line 173 confirms `0.75`.
  - Do not extract `vault_landing_probe_distance`, `vault_detection_range`, `vault_body_half_height`, or any `@export` var — those are designer-tunable and already named.
  - Do not extract `mantle_body_radius * 1.5` in `_update_vault_target`; the `1.5` multiplier is a geometric constant that could be named `VAULT_FORWARD_RADIUS_MULT = 1.5` — include it.

- `graybox-prototype/scripts/player_action_stack/movement/player_brain.gd`:
  Add a single `const` at class scope (before `_ready`). Declare: `WISH_DIR_THRESHOLD: float = 0.5`. Replace all four threshold literals in `get_intents`: `input_dir.x > 0.5`, `input_dir.x < -0.5`, `input_dir.y < -0.5`, `input_dir.y > 0.5` become comparisons against `WISH_DIR_THRESHOLD` and `-WISH_DIR_THRESHOLD` respectively.

## Pre-implementation Checklist

- [x] Every replacement literal in a method body is covered by a named `const`; no bare numeric literals remain in the targeted method bodies of the eight files.
- [x] `H_CAST_Y_OFFSETS` array order is preserved (ankle → head); index-based accesses `hits[1]`, `hits[2]`, `hits[5]` are unaffected.
- [x] `WISH_DIR_THRESHOLD` is used with negation (`-WISH_DIR_THRESHOLD`) for negative comparisons — no second constant introduced.
- [x] `AWAY_UP_BLEND`, `AWAY_LEAP_SPEED`, `AWAY_NORMAL_PUSH`, `FORCED_WEIGHT` (wall_jump), and `FORCED_WEIGHT` (edge_leap) each replace every use site, not just the first occurrence.
- [x] StairsMotor's existing named consts (`CAPSULE_HALF_HEIGHT`, `CAPSULE_RADIUS`, `LOOKAHEAD_MARGIN`, `DESCEND_TRAIL`, `ASCEND_THRESHOLD`, `DESCEND_THRESHOLD`) are left untouched.
- [x] No `@export` vars are changed; no new files are created; no test files are modified.
- [x] The `_original_height: float = 2.0` var default in SneakMotor is not extracted (var default, not method-body literal — out of scope).
- [x] GDScript syntax verified for each file: const declarations use `:= type` or bare `=` consistently with the file's existing style; typed array const (`H_CAST_Y_OFFSETS`) uses `Array[float]` annotation.
