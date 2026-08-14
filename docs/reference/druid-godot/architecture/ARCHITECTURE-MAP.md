# Architecture Map

## Section 1 — Built

| Class | Path | Public surface | Constitution clauses |
|---|---|---|---|
| `Intents` | `graybox-prototype/scripts/base/intents.gd` | `var move_dir`, `raw_input`, `wish_dir`, `input_strength`, `aim_origin`, `aim_direction`; `is_moving_forward/back/left/right`, `is_climbing_up/down/left/right`; `wants_jump`, `wants_sprint`, `wants_sneak`, `wants_climb`, `wants_mantle`, `wants_vault`, `wants_glide`, `wants_form_shift`, `wants_attack`, `wants_parry`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`; `reset()` | G4, P1 |
| `TransitionProposal` | `graybox-prototype/scripts/base/transition_proposal.gd` | `enum Priority { OPPORTUNISTIC, PLAYER_REQUESTED, FORCED }`; fields `target_state`, `category`, `override_weight`, `source_id` | G4 |
| `DamageEvent` | `graybox-prototype/scripts/base/damage_event.gd` | fields `source`, `target`, `amount`, `damage_type`, `stagger_class`, `hit_position` | G4 |
| `BodyReader` | `graybox-prototype/scripts/base/body_reader.gd` | `_init(body)`; `get_global_position()`, `get_velocity()`, `get_basis()`, `is_on_floor()`, `get_floor_normal()` | P4 |
| `LocomotionStateReader` | `graybox-prototype/scripts/base/locomotion_state_reader.gd` | `_init(state)`; `get_current_mode()`; signal `state_changed` | P4 |
| `BaseMotor` | `graybox-prototype/scripts/base/base_motor.gd` | `gather_proposals(...)`, `tick(...)`, `_get_service(...)` | P2 |
| `BaseService` | `graybox-prototype/scripts/base/base_service.gd` | `update_facts(body_reader)` | — |
| `BaseDebugContext` | `graybox-prototype/scripts/base/base_debug_context.gd` | `clear()`, `push_data(_data: Dictionary)` | P6 |
| `LocomotionState` | `graybox-prototype/scripts/player_action_stack/movement/locomotion_state.gd` | `enum ID { IDLE, WALK, SPRINT, FALL, JUMP, AUTO_VAULT, CLIMB, MANTLE, STAIRS, LADDER, GLIDE, SNEAK, WALL_JUMP, EDGE_LEAP }`; `set_state()`, `get_active_mode()`; signal `state_changed` | G2, P3 |
| `EntityController` | `graybox-prototype/scripts/player_action_stack/entity_controller.gd` | Parent fan-out for `FormBroker.form_shifted`: movement motor mask, forced movement proposal, visual placeholder update | G3, P7 |
| `MovementBroker` | `graybox-prototype/scripts/player_action_stack/movement/movement_broker.gd` | `get_current_mode()`, `get_body_reader()`, `get_state_reader()`, `set_allowed_motors(mask)`, `inject_forced_proposal(proposal)`; signals `state_changed`, `physics_tick_complete` | P2, P3, P7 |
| `StaminaComponent` | `graybox-prototype/scripts/player_action_stack/movement/stamina_component.gd` | `drain()`, `recover()`, `is_exhausted()`, `get_current()`, `get_max()`, `get_normalized()`; signal `stamina_changed` | P3 |
| `PlayerBrain` | `graybox-prototype/scripts/player_action_stack/movement/player_brain.gd` | `get_intents() -> Intents` | P1 |
| `EdgeLeapMotor` | `graybox-prototype/scripts/player_action_stack/movement/motors/edge_leap_motor.gd` | `gather_proposals`, `tick` | P2 |
| `VisualsPivot` | `graybox-prototype/scripts/player_action_stack/movement/visuals_pivot.gd` | `apply_form_visual(form_id, color, scale_multiplier)`; visual follower | P5 |
| `FormComponent` | `graybox-prototype/scripts/player_action_stack/form/form_component.gd` | `get_current_form()`, `get_allowed_forms()`, `can_shift_to(form_id)`, `set_form(form_id)`; signal `form_changed` | G2, P3 |
| `FormReader` | `graybox-prototype/scripts/player_action_stack/form/form_reader.gd` | `get_current_form()`, `is_form(form_id)`, `get_allowed_forms()` | P4 |
| `FormBroker` | `graybox-prototype/scripts/player_action_stack/form/form_broker.gd` | `tick(intents, delta)`, `get_form_reader()`, `set_shifts_enabled(enabled)`, `get_current_form()`, `motor_mask_for(form_id)`, `visual_color_for(form_id)`, `visual_scale_for(form_id)`, `form_shift_proposal_for(form_id, current_mode)`; signal `form_shifted` | G3, P2, P7 |
| `FormDebugReporter` | `graybox-prototype/scripts/player_action_stack/form/form_debug_reporter.gd` | Displays active form in `DebugOverlay` when present | P6 |
| `CombatBroker` | `graybox-prototype/scripts/player_action_stack/combat/combat_broker.gd` | `configure(body_reader, form_reader, stamina, projectile_parent)`, `tick(intents, delta)`, `set_aiming(is_enabled)`, `set_combat_state(state)`, `apply_damage(...)`, `find_nearest_target(origin, max_distance)`; signals `hit_landed`, `aiming_changed`, `combat_state_changed` | G3, P4, P7 |
| `BowAction` | `graybox-prototype/scripts/player_action_stack/combat/bow_action.gd` | `tick(intents, delta, broker)`; spawns graybox arrow projectiles for Avian form | P1, P4 |
| `ParryCounterAction` | `graybox-prototype/scripts/player_action_stack/combat/parry_counter_action.gd` | `tick(intents, delta, broker)`; resolves Monkey parry/counter against vulnerable targets | P1, P4 |
| `PantherTakedownAction` | `graybox-prototype/scripts/player_action_stack/combat/panther_takedown_action.gd` | `tick(intents, delta, broker)`; resolves close-range Panther takedown | P1, P4 |
| `HitPauseComponent` | `graybox-prototype/scripts/player_action_stack/combat/hit_pause_component.gd` | `request_hit_pause(scale, duration)`, `force_restore()` | G1 |
| `CombatDummy` | `graybox-prototype/scripts/world/combat_dummy.gd` | `apply_damage(event)`, `is_parry_vulnerable()`, `consume_parry()`, `can_be_takedown(source_position)`, `reset_dummy()`; signals `damage_received`, `defeated` | G1 |
| `ArrowProjectile` | `graybox-prototype/scripts/world/arrow_projectile.gd` | `launch(source, origin, direction, speed, max_range, damage)`; ray-marched graybox projectile | G1 |
| `CameraRig` | `graybox-prototype/scripts/player_action_stack/camera/camera_rig.gd` | (no public methods at present) | — |
| Per-Motor scripts | `graybox-prototype/scripts/player_action_stack/movement/motors/*.gd` | One row each: list `gather_proposals` and `tick` if overridden | P2 |
| Per-Service scripts | `graybox-prototype/scripts/player_action_stack/movement/services/*.gd` | One row each: list `update_facts` and any `gather_proposals` | — |
| `DebugOverlay` | `graybox-prototype/scripts/debug_overlay.gd` | `var panel_visible`, `register_context()`, `push()` | P6 |
| `PlayerActionDebugContext` | `graybox-prototype/scripts/player_action_stack/player_action_debug_context.gd` | `clear()`, `push_data(data: Dictionary)` | P6 |

> Splitting trigger: when this section exceeds 300 lines, split per cluster (e.g., ARCHITECTURE-MAP-player-action-stack.md). See Splitting Strategy.

## Section 2 — Deferred

| Pattern | Activation trigger |
|---|---|
| `GameOrchestrator` autoload + `EntityTickBundle` / `CameraTickBundle` / `MountTickBundle` registration | A 3rd Broker (Combat or Form) needs to tick per entity, OR multi-entity tick determinism becomes a measurable requirement (multiplayer milestone). |
| Body wrapper + `PhysicsProxy`: CharacterBody3D child + Transform Sync Contract | EntityController ever needs to expose a non-physics method whose name conflicts with CharacterBody3D, OR a ragdoll-swap requirement appears. |
| 4-tier priority (`DEFAULT` > `PLAYER_REQUESTED` > `OPPORTUNISTIC` > `FORCED`) + injective `FORCED` weight registry | Out-of-system `FORCED` interrupts ship (Combat stagger, Form shift, Health defeat). Today's 3-tier prototype is sufficient. |
| `IncomingAttackBuffer` + cross-entity `EntityController.receive_incoming_attack` | Combat ships AND ≥ 2 entities can damage each other in the same frame. |
| Caller-identity asserts (`set_shifts_enabled(enabled, caller)`, similar) | A real misuse case appears in code review. Default: do not introduce. |
| Remaining `Intents` combat fields (`wants_dodge`, lock-on target fields) | The consumer ships. Add fields one by one as Combat actions are written. `wants_form_shift`, `wants_attack`, `wants_parry`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`, `aim_origin`, and `aim_direction` have shipped with the Form/Combat graybox slices. |
| `EntityController` extends Node3D composition root with `forward_*` methods | Any sibling system other than Movement needs a per-frame upward-signal route, OR the prototype's `EntityController: Node` no longer fits. |
| `LocomotionState.Mode` extension (`STAGGER_LIGHT/HEAVY/FINISHER`, `DEFEAT`, `CINEMATIC`, `MOUNT`, `SWIM`, `RAGDOLL`) | The corresponding Motor ships. Don't pre-add. |
