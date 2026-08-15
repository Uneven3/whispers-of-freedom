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

## Terreno + auditoría de player_action_stack, 2026-08-14 (misma sesión)

**Terrain3D instalado y en uso.** Plugin no versionado (`addons/terrain_3d/`
en `.gitignore`, ver arriba); nueva escena `scenes/terrain_base.tscn`
(`Terrain3D` + sky/sol propios, sin `Ground` plano) con regiones ya
esculpidas en `world_data/terrain/` (sí versionado — es dato, no el binario
del plugin).

**`SpawnSnap`** (`scripts/player_action_stack/spawn_snap.gd`, nodo hijo de
`Player`, `@tool`) reemplaza el spawn Y hardcodeado: busca un nodo del grupo
`"terrain"`, lee `Terrain3DData.get_height()`, suma el half-height real de la
cápsula (`BodyReader.get_body_half_height()`) + un margen de caída, y
opcionalmente llama `Terrain3D.set_camera()` (nada más lo hacía fuera del
editor — sin eso, el modo de colisión `Dynamic` de Terrain3D podía no generar
colisión en ningún lado durante una partida real). Sin nodo `"terrain"` en la
escena (caso `grass_field.tscn`) es no-op — no rompe lo que ya andaba.

**El bug real de "player atascado en el terreno" — no era `SpawnSnap`.**
`EntityController` era `extends Node` (no `Node3D`), sentado entre `Player` y
tanto `Body` como `VisualsPivot`. Godot's `Node3D` sólo hereda transform de su
padre **inmediato** — no busca un ancestro `Node3D` más lejano a través de un
`Node` plano. Mover `Player` nunca movía la cápsula real, ni en editor ni en
partida — confirmado contra el motor real (Godot 4.7.1), no asumido.
Arreglado: `EntityController extends Node3D` (script y `.tscn`), sigue sin
transform propia, sólo deja de cortar la cadena. Mismo bug afectaba a
`horse.tscn` (comparte `entity_base.tscn`), arreglado gratis. Encontrado y
arreglado con `/iterate-safely` — dos rondas de crítica de un subagente sin
contexto antes de escribir código, porque los primeros intentos (bug de
`groups=` mal ubicado, crash de instancia placeholder en editor) no eran la
causa de fondo.

**Auditoría `/code-review` sobre `player_action_stack/` completo** (38
archivos), pedida explícitamente para buscar más bugs del mismo tipo
(asunciones de motor no verificadas). 9 hallazgos reales, los 9 arreglados
(commit `3d0dff7`): path frágil sin guard en `CameraRig`; `StrikeMotor`
perdía el arbitraje contra Stairs/Ladder por empate de prioridad (y casi
introduzco un bug nuevo — la crítica encontró que si la propuesta pierde de
plano en vez de empatar, `_active` quedaba trabado para siempre sin el
watchdog que se agregó); arco/parry/takedown no gastaban stamina; input de
ataque perdido en el frame exacto que expira el cooldown; tiro de arco
descartado si había un golpe en cooldown; ints crudos en vez de
`LocomotionState.ID`; overlay de debug de Movement y Combat pisándose;
cámara de aterrizaje sin cubrir Stairs/Sneak/Ladder; casts de `LedgeService`
sin gate de estado (arreglo acotado a `STRIKE` únicamente — extenderlo a
stairs/ladder/sprint necesita jugarlo, no sólo tests en verde, §17).

**Patrón repetido a tener en cuenta:** el editor de Godot cachea estado en
memoria y no siempre recoge cambios externos al archivo — ya nos mordió con
`project.godot` (el Input Map resucitó 3 acciones ya borradas) y con
`SpawnSnap` (sus perillas no hacían nada hasta agregar `@tool`, y aun con
`@tool` un nodo ya instanciado en una sesión vieja puede seguir corriendo el
script viejo). Si algo no refleja un cambio reciente: reiniciar Godot del
todo, no sólo recargar la escena, antes de asumir que el código está mal.

## Estado del código, al 2026-08-14

Validado headless: 79/79 tests, 5 escenas cargan sin errores
(`player`/`grass_field`/`terrain_base`/`horse`/`main`) — falta jugarlo.

Godot **4.7**, `run/main_scene = grass_field.tscn` (sin cambiar; terreno se
prueba desde `terrain_base.tscn` con F6). Escenas: `main`, `player`, `horse`,
`entity_base`, `grass_field`, `terrain_base`. Sin animación de personaje
todavía — cápsulas graybox (player azul, enemigo/target esfera roja, suelo
gris, interactuable cilindro amarillo — 1 unidad = 1 metro).

**Movimiento** — pipeline `Brain → Intents → MovementBroker → Motors → Body`,
15 estados de `LocomotionState.ID` (`IDLE`…`STRIKE`), un motor por estado,
servicios `Ground`/`Ledge`/`Stairs`/`Ladder`. `PlayerBrain` y `HorseBrain`
conviven sobre el mismo stack. **No hay `SwimMotor`** — nadar/bucear sigue
sin arrancar.

**Combate** — `CombatBroker` con las 4 acciones (`BowAction`,
`ParryCounterAction`, `TakedownAction`, `StrikeAction`) siempre disponibles
en el personaje único, arbitradas por prioridad (ver Pivote arriba), las 4
gastan y respetan stamina (ver auditoría arriba). No hay IA enemiga real,
todo resuelve contra `CombatDummy` en `scripts/world/`.

**Cámara** — `CameraRig` (`Node3D` + `SpringArm3D`) tercera persona orbital.
Apuntado/lock-on no confirmados en código propio todavía.

**Mundo/terreno** — `Terrain3D` (plugin, no versionado) en `terrain_base.tscn`,
regiones esculpidas en `world_data/terrain/`. `grass_field.tscn` sigue con su
plano `Ground` fijo, sin terreno esculpido — son dos escenas de prueba
separadas, no una migró a la otra todavía.

**Debug** — `DebugOverlay` autoload, F1 togglea el panel. Reporter para
Movement y Combat vía `BaseDebugContext`/`panel_key`, mismo panel, hacen
merge (ver auditoría arriba — antes se pisaban).

**Tests: 20 archivos, 79 tests, 79/79 en verde** (`godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`, corrido esta sesión).
5 escenas cargan headless sin errores (`godot --headless --quit-after`).
**Ninguno de los dos reemplaza jugarlo** (§17) — todo lo de terreno en
particular todavía no se jugó, sólo se verificó headless.

**Git:** repo inicializado 2026-08-14; esta sesión (terreno + fix de
`EntityController` + auditoría) quedó en 9 commits separados sobre el pivote,
sin pushear todavía — hace el push la persona, no el asistente.

## Próximo foco (propuesto, no comprometido)

1. **Seguir modificando terreno y probando Terrain3D** (explícito, siguiente
   sesión) — esculpido, texturas, más regiones. Con `EntityController` ya
   arreglado, el player debería moverse/reposicionarse con normalidad; probar
   eso primero antes de asumir que algo nuevo está roto.
2. **Jugar la caja completa** — movimiento, las 4 acciones de combate (con
   stamina real ahora), horse — nada de esto se verificó jugado todavía,
   sólo headless.
3. Corregir la violación de §14 en `strike_action.gd` (llama
   `inject_forced_proposal()` directo en vez de señal-hacia-arriba +
   `EntityController` reenvía) — antes de que otro sistema copie el patrón.
4. Decidir la premisa de mundo/narrativa (`NORTE.md` → Decisiones abiertas)
   y la licencia del proyecto — ambas quedaron abiertas al pivotear lejos de
   Druid.
