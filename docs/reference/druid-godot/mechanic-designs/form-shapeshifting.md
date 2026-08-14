# Mechanic Design: Form Shapeshifting

**Phase:** mechanic-2
**Status:** Approved
**Started:** 2026-06-30
**Approved:** 2026-06-30

## Implementation Slice: 2026-06-30

Implemented in `graybox-prototype/`:
- `FormComponent`, `FormReader`, `FormBroker`, `FormDebugReporter`, and a thin `EntityController` composition root.
- `Intents.wants_form_shift` plus input actions: Z = panther, X = monkey, C = avian.
- `MovementBroker.set_allowed_motors(mask)` and `MovementBroker.inject_forced_proposal(proposal)`.
- Same-frame form tick from `MovementBroker` before proposal selection.
- Placeholder form visualization through `VisualsPivot.apply_form_visual(...)`.
- Unit coverage for intents, form component, and form broker.

Not yet implemented:
- Real collision shape swapping. The current slice keeps the API direction in the design but uses visual-only graybox placeholders until a Body wrapper or safe `CollisionShape3D` adapter is added.
- Manual feel validation in the running editor/game window.

## Feel Contract
The shift must feel explosive and instantaneous--zero animation delay. It should feel like a fluid extension of movement, not a menu swap.

## Level 1: Scope Adherence

**In scope:**
- **Three discrete forms:** `panther`, `monkey`, and `avian` — allowed by the Form system in `00-system-map.md`.
- **Instant same-frame shift:** `FormBroker` consumes a requested form from `Intents`, updates `FormComponent`, and emits `form_shifted(new_form)`.
- **Momentum preservation:** Form does not zero velocity or teleport the body. Movement continues from the existing `Body.velocity`.
- **Collision shape swap:** `EntityController` receives `form_shifted` and routes the selected `Shape3D` to `Body.swap_collision_shape(shape)`.
- **Motor mask swap:** `EntityController` receives `form_shifted` and routes the selected motor mask to `MovementBroker.set_allowed_motors(mask)`.
- **Movement interrupt:** the shift produces a FORCED `TransitionProposal` routed through `MovementBroker.inject_forced_proposal(...)`.
- **Read-only form access:** `FormReader` exposes current form for future Combat, UI, Audio, and Progression.

**Flagged / cut:**
- **Hybrid / partial forms** — explicitly out of scope; exactly three discrete forms.
- **Per-form HP pools** — out of scope; Health remains a separate future system.
- **Real combat movesets** — out of scope for this slice; Combat can later consume `FormReader`.
- **Progression gating** — deferred; all three forms are available in graybox.
- **Production VFX/audio/UI** — deferred; debug visualization is enough for graybox.
- **Per-form camera behavior** — banned by architecture; Camera receives no `FormReader`.

**Ambiguities resolved:**
- **"Instant"** means state, motor mask, collision shape, and visible placeholder scale/color update in the same physics frame.
- **"Preserving momentum"** means Form does not directly mutate `Body.velocity`.
- **Invalid requested form** fails loudly in debug via `push_error(...)` and does not mutate state.
- **Requesting the current form** is a no-op.
- **Shift disabled** means `FormBroker.tick(...)` returns before mutation; used later for defeat/cinematic gates.

## Level 2: Component Assignment

**Existing components used:**
- `EntityController > PlayerBrain` — adds requested form to the shared `Intents` struct.
- `EntityController > MovementBroker` — receives allowed motor masks and a FORCED proposal from the entity root.
- `EntityController > Body` — collision shape owner. This project currently uses `CharacterBody3D` directly, so the slice will add a minimal `swap_collision_shape(shape)` adapter only if needed.
- `EntityController > VisualsPivot` — visual placeholder updates by form without owning form state.
- `EntityController > PlayerActionDebugContext` / `DebugOverlay` — displays active form and shift requests.

**New nodes required:**
- `FormComponent` (`Node`) — child of `Player/EntityController` — owns active form SSoT.
- `FormBroker` (`Node`) — child of `Player/EntityController` — validates and commits shifts.
- `FormDebugReporter` (`Node`) — child of `Player/EntityController/FormBroker` — pushes F4/debug data if `DebugOverlay` is present.

**New scripts required:**
- `res://scripts/player_action_stack/form/form_reader.gd`
- `res://scripts/player_action_stack/form/form_component.gd`
- `res://scripts/player_action_stack/form/form_broker.gd`
- `res://scripts/player_action_stack/form/form_debug_reporter.gd`

**Composition decisions:**
- Active-form state lives in `FormComponent`, not `FormBroker`, because state cells must be isolated and reader-backed.
- Shift orchestration lives in `FormBroker`, not `PlayerBrain`, because input only requests facts; it does not decide whether a shift is valid.
- Motor masks and collision-shape catalogs live in `FormBroker`, because they are Form-owned mappings consumed by EntityController fan-out.
- Visual placeholder feedback is driven externally from `form_shifted`; visuals do not read input or own form state.

## Level 3: Data & State Flow

**Input:**
- Trigger: input actions `form_panther`, `form_monkey`, `form_avian`.
- Source: `PlayerBrain.get_intents()` writes `Intents.wants_form_shift: StringName`.
- Default: `&""` means no requested shift.

**State mutations:**
- `Intents.wants_form_shift: StringName` — written by `PlayerBrain` each frame; reset by `Intents.reset()`.
- `FormComponent.active_form: StringName` — written only by `FormBroker` through `FormComponent.set_form(new_form)`.
- `MovementBroker` allowed motor mask — written only through `MovementBroker.set_allowed_motors(mask)` called by `EntityController` / current prototype wiring on `form_shifted`.
- `Body` collision shape — written only through `Body.swap_collision_shape(shape)` or the current `CharacterBody3D/CollisionShape3D` adapter on `form_shifted`.

**Output:**
- Signal emitted: `FormComponent.form_changed(old_form: StringName, new_form: StringName)`.
- Signal emitted: `FormBroker.form_shifted(new_form: StringName)` intended listener: `EntityController`.
- FORCED movement proposal: `TransitionProposal.new(current_mode, TransitionProposal.Priority.FORCED, weight, &"form_shift")`, preserving the active locomotion mode during the shift.
- Debug data: active form, requested form, and shifts-enabled flag.

**Flow compliance:**
- Input follows P1: `Input.*` remains in `PlayerBrain`.
- Form follows G2/P4: `FormComponent` owns mutable form state; external systems receive `FormReader`.
- Cross-system fan-out follows G3/P7: Form emits upward; parent/root wiring calls Movement/Body downward.
- Form never talks to Camera; no `FormReader` field exists on `CameraRig`.
- Violations found: none in the current graybox slice. The implementation adds a thin `EntityController.gd` composition root for parent fan-out.

## Level 4: Contract Mapping

### `Intents` extension (`res://scripts/base/intents.gd`)

Extends: `RefCounted`

```gdscript
var wants_form_shift: StringName = &""  # requested form, or empty for no request
```

`reset()` must clear `wants_form_shift` to `&""`.

### `FormReader` (`res://scripts/player_action_stack/form/form_reader.gd`)

```gdscript
func get_current_form() -> StringName
func is_form(form_id: StringName) -> bool
func get_allowed_forms() -> Array[StringName]
```

### `FormComponent` (`res://scripts/player_action_stack/form/form_component.gd`)

```gdscript
signal form_changed(old_form: StringName, new_form: StringName)

func get_current_form() -> StringName
func get_allowed_forms() -> Array[StringName]
func can_shift_to(form_id: StringName) -> bool
func set_form(form_id: StringName) -> bool
```

### `FormBroker` (`res://scripts/player_action_stack/form/form_broker.gd`)

```gdscript
signal form_shifted(new_form: StringName)

func tick(intents: Intents, _delta: float) -> void
func get_form_reader() -> RefCounted
func set_shifts_enabled(enabled: bool, _caller: Object = null) -> void
func get_current_form() -> StringName
func motor_mask_for(form_id: StringName) -> Array[StringName]
func visual_color_for(form_id: StringName) -> Color
func visual_scale_for(form_id: StringName) -> Vector3
func form_shift_proposal_for(form_id: StringName, current_mode: int) -> TransitionProposal
```

### `PlayerBrain` extension (`res://scripts/player_action_stack/movement/player_brain.gd`)

Reads input actions:
- `form_panther` → `intents.wants_form_shift = &"panther"`
- `form_monkey` → `intents.wants_form_shift = &"monkey"`
- `form_avian` → `intents.wants_form_shift = &"avian"`

### `MovementBroker` extension (`res://scripts/player_action_stack/movement/movement_broker.gd`)

```gdscript
func set_allowed_motors(mask: Array[StringName]) -> void:
	pass  # implementation slice filters proposal/tick candidates by motor node names

func inject_forced_proposal(proposal: TransitionProposal) -> void:
	pass  # implementation slice queues proposal for same-frame/next-frame arbitration
```

### `VisualsPivot` extension (`res://scripts/player_action_stack/movement/visuals_pivot.gd`)

```gdscript
func apply_form_visual(form: StringName, color: Color, scale_multiplier: Vector3) -> void:
	pass  # implementation slice updates graybox mesh material/scale only
```

## Level 5: Edge Case Coverage

### System Edge Cases

- **Current-form request:** no-op in `FormBroker.tick`; no signal emitted.
- **Invalid form request:** `push_error(...)` and no mutation.
- **Shift disabled:** `_shifts_enabled == false` causes early return before state change.
- **Camera coupling:** Camera receives no `FormReader`; per-form camera changes are not implemented.
- **Movement same-frame shift:** `form_shifted` fan-out must happen before Movement arbitration in the same physics frame where possible.
- **Missing Body wrapper:** slice may implement visual-only collision placeholder first, but must keep the `shape_for(...)` surface so Body swap can be added without redesign.

### Mechanic-Specific Edge Cases

- **Button mash across forms:** last pressed form in `PlayerBrain` wins for that frame; only one `wants_form_shift` value exists.
- **Shift while airborne:** allowed; velocity preserved; Avian form may immediately allow `GlideMotor`.
- **Shift while climbing:** allowed only if motor mask still permits climb; if new form excludes climb, Movement falls back via allowed proposals.
- **Catalog missing form entry:** `FormBroker` uses default motor/visual values; no crash for graybox catalogs.
- **Future progression lock:** not implemented; `available_forms()` is intentionally omitted until Progression exists.

## Implementation Handoff

**Reading order for the implementing `/slice` Builder:**
1. Read this document top to bottom.
2. Read `docs/architecture/CONSTITUTION.md` and `docs/architecture/ARCHITECTURE-MAP.md`.
3. Read `docs/playbooks/extend-intents.md` because this mechanic extends `Intents`.
4. Open the existing movement prototype and wire Form without changing camera behavior.
5. Implement minimum graybox feedback: active form visible through color/scale and debug data.
6. Run GUT unit tests.

**Open questions for the implementing agent:**
- None. Use the defaults in this document for the graybox slice.
