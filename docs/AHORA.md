# Ahora — el trabajo presente

Trabajo vivo entre sesiones (≤500 líneas); lo cerrado queda en git. Reglas en
`ARCHITECTURE.md`, visión en `NORTE.md`. `docs/reference/druid-godot/` (de
ahí salió el código actual) se revisó a fondo y se mandó a la papelera
2026-08-14 — nada sobrevivió aparte, ver `docs/README.md`. Este archivo es
la bitácora viva de acá en adelante.

## Cómo trabajar en este repo

- **Tests (GUT 9.6.0):** panel GUT en el editor, o headless:
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`
- **Tiers de test:** 1 clases de datos puras sin Godot (`Intents`,
  `TransitionProposal`), 2 fixture chica vía `add_child_autofree`, 3
  motores/servicios con stubs (arbitraje de `MovementBroker`). Lo que
  necesita motor de físicas real o rendering (`move_and_slide`, colisiones,
  animación) **no se testea, se juega**.
- **`assert()` vs `push_error()`** — §5 de `ARCHITECTURE.md`: invariante de
  programador vs. fallo alcanzable en runtime. No usar `assert()` para datos
  que puede producir un diseñador o una carga de archivo.
- **Un mecanismo no se marca `[x] Done` sólo porque compila y los tests
  pasan** (§17) — graybox + tests en verde se revalida como "Not started"
  hasta jugarlo contra su feel contract. Antes de cerrar algo acá: correr el
  suite, abrir la escena principal y jugar el checklist relevante.
- Commits pequeños, sin push sin pedido explícito.
- **Terrain3D no está versionado** (`addons/terrain_3d/` en `.gitignore` —
  son ~52MB de binarios por plataforma, no vale la pena en el historial).
  Instalar local antes de abrir el proyecto: descargar
  `Terrain3D_v1.0.2-stable.zip` de
  [github.com/TokisanGames/Terrain3D/releases](https://github.com/TokisanGames/Terrain3D/releases)
  (confirmado compatible con Godot 4.7.1 aunque el release sólo declara
  "4.4-4.6+"; `terrain.gdextension` fija `compatibility_minimum = 4.4` sin
  techo), descomprimir en la raíz del repo (crea `addons/terrain_3d/`).
  `project.godot` ya lo lista en `editor_plugins/enabled` — sólo hace falta
  que el archivo exista en disco.

## Pivote 2026-08-14 (ver `NORTE.md`) — ejecutado

Se descartó el shapeshifting (Panther/Monkey/Avian) y la premisa de
corrupción/rituales; el objetivo pasa a un solo personaje con moveset
completo, más cerca de BOTW — mismo norte que `breath-of-freedom`. Ejecutado
con `/iterate-safely` (plan → crítica de un subagente sin contexto → triage →
ejecución), validado en cada tanda con `godot --headless` (GUT + carga de
escena), nunca sólo "compila".

**Sacado:** `scripts/player_action_stack/form/` entero (`FormBroker`/
`FormComponent`/`FormReader`/`FormDebugReporter`), `Intents.wants_form_shift`,
los 3 input actions `form_*` de `project.godot`, los nodos `Form*` de
`player.tscn`. `CombatBroker` unifica las 4 acciones (antes una por forma)
con prioridad explícita en vez de gate — ver §rationale de `ARCHITECTURE.md`.
`PantherTakedownAction` → `TakedownAction`; los `damage_type` vestigiales
(`avian_arrow`/`panther_takedown`/`monkey_counter`/`monkey_strike`) →
genéricos.

**Bug real encontrado por la crítica antes de escribir código, no después:**
tickear las 4 acciones sin gate deja que liberar una flecha apuntando
(`wants_archery_release`, derivado en parte de `wants_attack`) también
dispare un golpe cuerpo a cuerpo el mismo frame. Arreglado con prioridad
explícita en `CombatBroker.tick()` (bow-mientras-se-apunta > takedown >
parry > strike, strike-en-curso siempre resuelve primero) y cubierto por
`test_aiming_suppresses_strike_on_the_same_frame` — no es sólo lectura de
código, el test lo ejercita.

**De paso, aplicadas las leyes de `ARCHITECTURE.md` que todavía no se habían
tocado en código:**
- **§19** (NodePaths frágiles): `%NombreÚnico` donde el nodo destino
  comparte owner (`Body`/`StaminaComponent`/`Services/*`/`MovementBroker`
  dentro de `entity_base.tscn`; `CameraRig`/`Camera3D` dentro de
  `player.tscn`), `@export NodePath` donde cruza instancia (`brain_path`,
  sin cambios). La semántica exacta de qué cruza y qué no se verificó contra
  la doc real de Godot (no de memoria) y con dos tests nuevos
  (`test_player_scene.gd`, más assertions en `test_entity_base.gd`) — la
  primera versión tenía `unique_name_in_owner=true` en el lugar equivocado
  del `.tscn` (adentro del header `[node ...]` en vez de como property line)
  y fallaba en silencio hasta correr el suite.
- **§5** (mensajes): sólo 3 de los 8 `push_error`/`push_warning` existentes
  violaban la ley de verdad (prefijo de clase redundante) —
  `movement_broker.gd`, `ladder_service.gd`, `stairs_service.gd`. Los otros 5
  interpolan el nombre de instancia del nodo, no un literal de clase; eso no
  es lo que la ley prohíbe, se dejaron igual.
- **§18** (tipado estático): auditado — `scripts/` ya cumplía. `test/` tiene
  ~67 `var x = ...` sin tipar, exento por bajo valor real (ya escrito en
  `ARCHITECTURE.md` §18, mismo criterio que `unwrap`/`expect` exento en
  tests de `breath-of-freedom`).

**Deuda anotada, no cerrada esta sesión:** `strike_action.gd` llama
`MovementBroker.inject_forced_proposal()` directo, violando §14
(preexistente, no introducido por este pivote — la crítica lo encontró
mientras revisaba el patrón; ya está anotado en `ARCHITECTURE.md` §14 en vez
de quedar como sorpresa la próxima vez que alguien lea esa ley).

## Estado del código, al 2026-08-14

Validado headless: 53/53 tests, carga de escena principal sin errores —
falta jugarlo.

Godot **4.7**, `run/main_scene = grass_field.tscn`. Escenas: `main`,
`player`, `horse`, `entity_base`, `grass_field`. Sin animación de personaje
todavía — cápsulas graybox (player azul, enemigo/target esfera roja, suelo
gris, interactuable cilindro amarillo — 1 unidad = 1 metro).

**Movimiento** — pipeline `Brain → Intents → MovementBroker → Motors → Body`,
15 estados de `LocomotionState.ID` (`IDLE`…`STRIKE`), un motor por estado,
servicios `Ground`/`Ledge`/`Stairs`/`Ladder`. `PlayerBrain` y `HorseBrain`
conviven sobre el mismo stack. **No hay `SwimMotor`** — nadar/bucear sigue
sin arrancar.

**Combate** — `CombatBroker` con las 4 acciones (`BowAction`,
`ParryCounterAction`, `TakedownAction`, `StrikeAction`) siempre disponibles
en el personaje único, arbitradas por prioridad (ver Pivote arriba). No hay
IA enemiga real, todo resuelve contra `CombatDummy` en `scripts/world/`.

**Cámara** — `CameraRig` (`Node3D` + `SpringArm3D`) tercera persona orbital.
Apuntado/lock-on no confirmados en código propio todavía.

**Debug** — `DebugOverlay` autoload, F1 togglea el panel. Reporter para
Movement y Combat vía `BaseDebugContext`/`panel_key`.

**Tests: 15 archivos, 53 tests, 53/53 en verde** (`godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`, corrido esta sesión).
Escena principal carga headless sin errores (`godot --headless
--quit-after`). **Ninguno de los dos reemplaza jugarlo** (§17).

**Git:** repo inicializado 2026-08-14; el pivote de hoy quedó en su propio
commit, separado del de reorganización de docs.

## Próximo foco (propuesto, no comprometido)

1. **Jugar la caja completa** — movimiento, las 4 acciones de combate
   (incluyendo el caso de prioridad aim+attack), horse — nada de esto se
   verificó jugado todavía, sólo headless.
2. Corregir la violación de §14 en `strike_action.gd` (llama
   `inject_forced_proposal()` directo en vez de señal-hacia-arriba +
   `EntityController` reenvía) — antes de que otro sistema copie el patrón.
3. Decidir la premisa de mundo/narrativa (`NORTE.md` → Decisiones abiertas)
   y la licencia del proyecto — ambas quedaron abiertas al pivotear lejos de
   Druid.
