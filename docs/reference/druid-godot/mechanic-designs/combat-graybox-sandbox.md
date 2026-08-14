# Mechanic Design: Combat Graybox Sandbox

**Phase:** graybox implementation handoff
**Status:** Implemented First / Needs Backfill
**Started:** 2026-06-30
**Approved:** —

## Purpose

This document records the combat implementation built before formal per-mechanic design backfill, per user direction to finish a playable combat pass before playtest.

## Implemented Scope

- `CombatDummy` world target with HP, damage feedback, defeat state, and repeating parry telegraph window.
- `CombatBroker` under `Player/EntityController`, configured by `EntityController` with `BodyReader`, `FormReader`, stamina, and projectile parent.
- `BowAction` for Avian form:
  - Hold RMB to aim/draw.
  - Release RMB or click LMB while aiming to fire.
  - Camera shifts into an over-shoulder aim view with reticle while the bow is drawn.
  - Spawns `ArrowProjectile`; projectile uses ballistic velocity + gravity, ray-marches between physics frames, and applies `DamageEvent` on hit.
- `ParryCounterAction` for Monkey form:
  - Press `E` during dummy telegraph/parry window.
  - Applies counter damage and hitpause.
- `PantherTakedownAction` for Panther form:
  - Press `F` near dummy.
  - Applies finisher damage and hitpause.
- Combat fields added to `Intents`: `aim_origin`, `aim_direction`, `wants_attack`, `wants_parry`, `wants_archery_aim`, `wants_archery_release`, `wants_assassinate`.

## Controls

- `Z`: Panther form.
- `X`: Monkey form.
- `C`: Avian form.
- RMB hold/release: Avian bow draw/release.
- LMB while holding RMB: Avian bow release.
- `E`: Monkey parry/counter.
- `F`: Panther takedown.

## Known Backfill

- Formal mechanic-2 designs still need to be written for Monkey parry/counter, Panther takedown, and Avian bow.
- Camera aim presentation is directly wired to `CombatBroker.aiming_changed` in the graybox `CameraRig`. Formal `AimingReader`/Camera mode backfill remains.
- Dummy has no real AI, attack damage, perception, or stealth state.
- Panther takedown uses simple range gating, not stealth detection or magnetic snap.
- Hitpause is implemented locally through `HitPauseComponent`; a future `TimeScaleService` should own production time-scale effects.
- Health is still represented by `CombatDummy`, not a reusable Health system.

## Validation

- GUT suite: 43/43 passing after this implementation.
- `main.tscn` headless load: clean.
