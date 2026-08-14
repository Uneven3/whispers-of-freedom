# Mechanic Spec

## Current Status Policy

Implementation status is not marked `[x] Done` from historical evidence alone. A mechanic can have graybox code and passing tests but still remain unclosed until revalidated.

Minimum revalidation before setting `Implementation Status: [x] Done`:
- Run the GUT unit suite with `godot --headless --path graybox-prototype -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`.
- Open the main scene and complete the relevant manual feel/behavior checklist.
- Confirm there are no blocking runtime errors in the current Godot version.

## Mechanics

### 1. Ground Movement, Climbing & Stamina
**Description:** Basic BotW-style traversal (walk, sprint, sneak, jump, fall, land) plus climbing and mantling. Sprinting and climbing drain stamina.
**Feel Contract:** Moving feels immediate—no input lag. Stopping feels deliberate, not floaty. Landing from high jumps has weight (camera dip, audio impact).
**Owner System:** Movement (`EntityController` + `MovementBroker` + `BaseMotor` subclasses)
**Analysis Status:** [x] Done
**Implementation Status:** [ ] Not started
**Current Evidence:** Graybox code exists in `graybox-prototype/` and unit tests cover several movement components. Revalidation is required before marking implemented.

### 2. Camera Controller
**Description:** Third-person camera that follows the player, with states for aiming (over-the-shoulder) and lock-on (framing player and target).
**Feel Contract:** The camera feels like a physical observer. It smooths out jitter, snaps quickly when aiming, and frames combat dynamically without giving motion sickness.
**Owner System:** Camera (`CameraRig` + `CameraBroker` + `CameraMode` subclasses)
**Analysis Status:** [x] Done
**Implementation Status:** [ ] Not started
**Current Evidence:** A graybox `CameraRig` exists and follows the player. Aim/lock-on behavior requires revalidation before marking implemented.

### 3. Form Shapeshifting
**Description:** Instant snap between Panther, Monkey, and Avian forms, preserving momentum.
**Feel Contract:** The shift must feel explosive and instantaneous—zero animation delay. It should feel like a fluid extension of movement, not a menu swap.
**Owner System:** Form (`FormBroker` + `FormComponent`)
**Analysis Status:** [x] Done
**Implementation Status:** [~] In progress
**Current Evidence:** Graybox slice exists: Z/X/C shift between panther/monkey/avian, `FormComponent` state, `FormBroker` validation, parent fan-out through `EntityController`, movement motor masks, forced same-frame movement proposal, placeholder color/scale visuals, unit tests, and headless scene-load validation. Collision shape swapping and manual feel validation remain before `[x] Done`.

### 4. Monkey Rhythm Parry & Counter
**Description:** Rhythmic combat counter. Player reads enemy telegraph and hits the parry window (±100ms tolerance).
**Feel Contract:** Extremely satisfying, heavy feedback. Hitting a counter triggers extreme hitpause, making the player feel like a timing master.
**Owner System:** Combat (`CombatBroker` + `ParryAction` / `CounterAction`)
**Analysis Status:** [x] Done
**Implementation Status:** [~] In progress
**Current Evidence:** Graybox combat slice exists: `CombatDummy` periodically opens a parry window; Monkey form uses `ParryCounterAction` on `E` to counter vulnerable targets, apply damage, update combat state, and trigger hitpause. Formal mechanic-2 design and manual timing feel validation remain.

### 5. Panther Stealth Takedown
**Description:** Silent approach into a magnetic takedown when undetected.
**Feel Contract:** Predatory and fluid. Takedowns should snap magnetically if in range, rewarding patient approach over frantic button mashing.
**Owner System:** Combat (`CombatBroker` + `TakedownAction`)
**Analysis Status:** [ ] Not started
**Implementation Status:** [~] In progress
**Current Evidence:** Graybox combat slice exists: Panther form uses `PantherTakedownAction` on `F` against close combat targets, applies finisher-class damage, updates combat state, and triggers hitpause. Stealth/detection and magnetic snap feel remain unimplemented.

### 6. Avian Ranged Bow
**Description:** Drawing and releasing a projectile weapon from an over-the-shoulder aim mode.
**Feel Contract:** Drawing feels tense and heavy. Releasing has sharp recoil and satisfying contact audio on hit.
**Owner System:** Combat (`CombatBroker` + `BowAction`)
**Analysis Status:** [ ] Not started
**Implementation Status:** [~] In progress
**Current Evidence:** Graybox combat slice exists: Avian form can hold right mouse to aim/draw and release right mouse or click left mouse while aiming to fire `ArrowProjectile` at the `CombatDummy`. Projectile hits apply `DamageEvent` damage. Camera aim mode, draw tension tuning, recoil, and audio remain unvalidated.

### 7. Climbing & Wall Jump
**Description:** Grabbing surfaces to climb or leaping off them, heavily gated by stamina.
**Feel Contract:** Effort is visible. Climbing should feel rhythmic and deliberate, not like sliding up a frictionless wall.
**Owner System:** Movement (`ClimbMotor`, `WallJumpMotor`)
**Analysis Status:** [x] Merged into Mechanic 1
**Implementation Status:** [x] Merged into Mechanic 1

### 8. Gliding
**Description:** Deployable mid-air glide state.
**Feel Contract:** Smooth, swooping, and momentum-preserving.
**Owner System:** Movement (`GlideMotor`)
**Analysis Status:** [ ] Not started
**Implementation Status:** [ ] Not started

### 9. Swimming
**Description:** Water traversal with stamina constraints.
**Feel Contract:** Buoyant but resistant. Movement is noticeably heavier than ground movement.
**Owner System:** Movement (`SwimMotor`)
**Analysis Status:** [ ] Not started
**Implementation Status:** [ ] Not started

---

## Out of Scope (TO BE IMPLEMENTED)

The following mechanics from the GDD are intentionally deferred from the MVP and will be architected in future clusters:
- Use-to-Improve Progression Backend
- Ritual Rhythm Timing & Cascade System
- Zone State Machine (Dead → Restoring → Alive)
- Wave Defense Manager
- Ecosystem Resource Management
- Enemy AI / Behavior (beyond basic target dummies for combat testing)

---

## Revalidation Needed

- **Ground Movement, Climbing & Stamina:** run unit tests, playtest walk/sprint/sneak/jump/fall/climb/mantle/auto-vault/stairs/ladder/glide/wall-jump/edge-leap against the feel contract, then update implementation status if clean.
- **Camera Controller:** playtest follow smoothing, mouse look, landing dip, and any implemented aim/lock-on behavior; update implementation status only for behavior that is actually present.
- **Form Shapeshifting:** playtest Z/X/C form changes during walk/sprint/jump/climb/glide, verify no velocity reset, verify form-specific motor masks feel correct, then add/validate collision shape swapping before marking done.
- **Combat Graybox:** playtest form-specific controls: Avian RMB/LMB bow against dummy, Monkey `E` during dummy parry telegraph, Panther `F` near dummy. Validate no runtime errors, hit feedback readability, hitpause feel, and whether dummy placement/ranges need tuning before writing formal per-mechanic design corrections.
- **Historical slices:** several `docs/slices/*` artifacts predate the current status policy. Treat logs, commits, tests, and current code as evidence, not automatic completion.
