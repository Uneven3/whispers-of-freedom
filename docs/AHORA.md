# Ahora — el trabajo presente

Trabajo vivo entre sesiones (≤500 líneas); lo cerrado queda en git. Reglas en
`ARCHITECTURE.md`, visión en `NORTE.md`. Historial de diseño previo a este
repo (Constitution, System Map, rationale de cada cluster, mechanic-designs,
slices) en `docs/reference/druid-godot/` — es la fuente de la que salió el
código actual, pero no se actualiza más: este archivo es la bitácora viva de
acá en adelante.

## Cómo trabajar en este repo

- **Tests (GUT 9.6.0):** panel GUT en el editor, o headless:
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`
- **Tiers de test** (detalle completo en
  `docs/reference/druid-godot/testing-guidelines.md`): 1 clases de datos
  puras sin Godot (`Intents`, `TransitionProposal`), 2 fixture chica vía
  `add_child_autofree`, 3 motores/servicios con stubs (arbitraje de
  `MovementBroker`). Lo que necesita motor de físicas real o rendering
  (`move_and_slide`, colisiones, animación) **no se testea, se juega**.
- **`assert()` vs `push_error()`** — §5 de `ARCHITECTURE.md`: invariante de
  programador vs. fallo alcanzable en runtime. No usar `assert()` para datos
  que puede producir un diseñador o una carga de archivo.
- **Un mecanismo no se marca `[x] Done` sólo porque compila y los tests
  pasan.** Ese error ya pasó en el proyecto origen (`mechanic-spec.md` en la
  referencia): graybox + tests en verde revalidado como "Not started" hasta
  jugarlo contra su Feel Contract. Antes de cerrar algo acá: correr el
  suite, abrir la escena principal y jugar el checklist relevante.
- Commits pequeños, sin push sin pedido explícito.

## Estado del código, al 2026-08-14 (primera lectura, no jugado por mí todavía)

Godot **4.7**, `run/main_scene = grass_field.tscn`. Escenas: `main`,
`player`, `horse`, `entity_base`, `grass_field`. Sin animación de personaje
todavía — capsulas graybox (ver
`docs/reference/druid-godot/graybox-visual-language.md`).

**Movimiento — pipeline `Brain → Intents → MovementBroker → Motors → Body`
implementado y con la mayoría de los estados de `LocomotionState.ID`
presentes:** `IDLE`, `WALK`, `SPRINT`, `FALL`, `JUMP`, `AUTO_VAULT`, `CLIMB`,
`MANTLE`, `STAIRS`, `LADDER`, `GLIDE`, `SNEAK`, `WALL_JUMP`, `EDGE_LEAP`,
`STRIKE` — un motor por estado en `scripts/player_action_stack/movement/
motors/`, más los servicios `GroundService`/`LedgeService`/`StairsService`/
`LadderService`. `PlayerBrain` (mouse+teclado) y `HorseBrain` ya conviven
sobre el mismo stack. **No hay `SwimMotor`** — nadar/bucear (pilar 8 de
`NORTE.md`) sigue sin arrancar.

**Shapeshifting — `FormBroker`/`FormComponent` resuelven Panther/Monkey/
Avian**, cada forma con su máscara de motores (`FormBroker.motor_mask_for`)
y color/escala placeholder (`visual_color_for`/`visual_scale_for` — sin
mesh real todavía). **Deuda conocida y sin resolver: el ShapeCast de
validación de colisión al cambiar de forma** que pide `NORTE.md` no existe
— hoy el swap es incondicional, así que un cambio de forma en un espacio
angosto puede clippear.

**Combate — un `*Action` por forma sobre `CombatBroker`:** `BowAction`
(Avian, arco de dos fases contra `ArrowProjectile`/`CombatDummy`),
`ParryCounterAction` + `StrikeAction` (Monkey), `PantherTakedownAction`
(Panther), `HitPauseComponent` para el freeze de golpe perfecto. Todo
resuelve contra `CombatDummy` en `scripts/world/` — no hay IA enemiga real
todavía (pilar de Investigación/Ritual/Zona/Defensa/Ecosistema de `NORTE.md`
sigue en `[ ] Not started` salvo lo que ya cubre `mechanic-spec.md` en la
referencia).

**Cámara — `CameraRig` (`Node3D` + `SpringArm3D`) tercera persona
orbital.** Apuntado/lock-on no confirmados en código propio todavía (usar
`docs/reference/druid-godot/mechanic-designs/camera-controller.md` como
diseño de referencia, no como estado).

**Debug — `DebugOverlay` autoload, F1 togglea el panel.** `panel_key` por
sistema vía `BaseDebugContext`; hoy hay reporter para Movement
(`MovementBrokerDebugReporter`) y Combat (`CombatDebugReporter`). Form no
tiene panel propio.

**Tests: 32 archivos en `test/unit/`**, cubriendo `BodyReader`, `ClimbMotor`,
`CombatBroker`, `CombatDummy`, `EdgeLeapMotor`, `EntityBase`, `FormBroker`,
`FormComponent`, `GrassField`, `Horse`, `Intents`, `LedgeFacts`,
`PlayerBrainToggle`, `StaminaComponent`, `TransitionProposal`, entre otros.
No corrí el suite todavía en esta sesión — antes de asumir algo de esto
"anda", correrlo.

**Sin git hasta esta sesión.** Se inicializó el repo y se migraron los docs
de `docs/from-*` a `docs/reference/*` (archivo, no se borró nada) el
2026-08-14 — ver commit inicial.

## Próximo foco (propuesto, no comprometido)

1. Correr el suite GUT completo y jugar la escena principal para tener una
   lectura real de qué "anda" antes de tocar nada — este documento se
   escribió leyendo código, no jugando.
2. Cerrar la deuda del ShapeCast de validación de colisión al cambiar de
   forma (riesgo técnico #1 de `NORTE.md`) antes de sumar más formas o
   geometría angosta al graybox.
3. Decidir si `docs/reference/druid-godot/mechanic-designs/` y
   `execution-plans/` siguen siendo el diseño vigente para Combate/Cámara o
   si diverieron del código real — falta una pasada de reconciliación.
