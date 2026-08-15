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
- **Assets Blender (`art/blender/`) se importan nativo, sin exportar a
  `.glb` a mano** — Godot invoca a Blender headless por su cuenta. Hace
  falta `Editor Settings → Filesystem → Import → Blender → Blender Path`
  apuntando al binario local (`/usr/bin/blender` acá; setting de editor, no
  versionado — mismo patrón que Terrain3D arriba). Sin eso configurado, el
  `.blend` no importa y el código que lo usa cae a un fallback en vez de
  crashear (ver `grass_field.gd::_load_base_blade_mesh()`), pero conviene
  configurarlo para ver el asset real. Tras clonar o pulear, correr una vez
  `godot --headless --editor --import` para forzar el reimport antes de
  abrir el proyecto normalmente. **Ojo:** ese comando (cualquier invocación
  con `--editor`) puede reescribir archivos abiertos en una sesión de editor
  cacheada de antes (ej. reindentó `ARCHITECTURE.md` de espacios a tabs sin
  que nadie lo pidiera) — correr `git status`/`git diff` después y revertir
  lo que no se pidió, antes de commitear.
- **`tools/grass_density_probe.gd`**: compara variantes de brizna por
  píxeles-de-silueta-por-triángulo (misma técnica que `breath-of-freedom`
  usó para su pradera — no hay tool nativo de Godot para esto, `Performance`
  mide la escena entera y "Overdraw" es visual, no scripteable). Necesita
  pantalla real, **no** `--headless` (el driver dummy no rasteriza nada):
  `godot --path . -s tools/grass_density_probe.gd`. Guarda capturas en
  `/tmp/grass_density_probe/` para revisar a ojo — el número solo no alcanza,
  dos vistas (pájaro/altura de jugador) pueden favorecer variantes distintas.

## Pivote 2026-08-14 (ver `NORTE.md`) — ejecutado

Se descartó el shapeshifting (Panther/Monkey/Avian) por un solo personaje
con moveset completo, más cerca de BOTW — mismo norte que `breath-of-freedom`.
Ejecutado con `/iterate-safely`; la crítica encontró un bug real antes de
escribir código (tickear las 4 acciones de combate sin gate dejaba que
apuntar el arco disparara un golpe cuerpo a cuerpo el mismo frame — resuelto
con prioridad explícita en `CombatBroker.tick()`, cubierto por
`test_aiming_suppresses_strike_on_the_same_frame`). De paso, §19 migrado
(`%Único` vs `@export NodePath` según cruce o no de escena, verificado
contra doc real de Godot) y §5/§18 auditados (ya cumplían casi del todo).
Deuda anotada, no cerrada: §14 en `strike_action.gd` (ver `ARCHITECTURE.md`).
Detalle completo en `git log` de los commits del pivote — no repetido acá.

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
archivos, buscando más bugs del tipo "asunción de motor no verificada"): 9
hallazgos reales, los 9 arreglados (commit `3d0dff7` — lista completa ahí,
no repetida acá). Notable: `StrikeMotor` casi se llevaba un bug *nuevo* en
el arreglo — la crítica encontró que si la propuesta perdía de plano el
arbitraje (no empate) `_active` quedaba trabado sin el watchdog agregado.

**Patrón repetido a tener en cuenta:** el editor de Godot cachea estado en
memoria y no siempre recoge cambios externos al archivo — ya nos mordió con
`project.godot` (el Input Map resucitó 3 acciones ya borradas) y con
`SpawnSnap` (sus perillas no hacían nada hasta agregar `@tool`, y aun con
`@tool` un nodo ya instanciado en una sesión vieja puede seguir corriendo el
script viejo). Si algo no refleja un cambio reciente: reiniciar Godot del
todo, no sólo recargar la escena, antes de asumir que el código está mal.

## Auditoría `/code-review` sobre `scripts/base/` + `scripts/world/` + `debug_overlay.gd`, 2026-08-15

Segunda auditoría, esta vez sobre los 14 archivos que quedaron fuera del
barrido de `player_action_stack/` de ayer (ver mapa de módulos en
`ARCHITECTURE.md`). Ejecutada con `/iterate-safely`: plan de scope
(archivos + leyes a chequear) → crítica de un subagente sin contexto previo
→ triage → `/code-review` → triage de los hallazgos → fix → tests.

**De paso, encontrado por la crítica antes de arrancar:** `attach_scripts.gd`
en la raíz del repo — tooling muerto del commit inicial, cero referencias,
`NodePath`s ya desactualizados contra la estructura actual de escenas.
Borrado.

**9 hallazgos del audit, 8 reales arreglados, 1 descartado por precedente
del propio repo** (mensaje `"Ladder '%s' is missing..."` con el nombre de
clase como sujeto de oración, no como prefijo `"Clase: mensaje"` — la
auditoría de ayer dejó ese patrón exacto sin tocar en `movement_broker.gd`/
`camera_rig.gd`, verificado con `git log -p` antes de descartar):

- **Bug real, mismo patrón que el crash de `EntityController` de ayer:**
  `Ladder`/`Stairs._ready()` llamaban `add_to_group()` **antes** de
  chequear si faltaban los nodos marcador, así que un `Ladder`/`Stairs` mal
  armado en el editor igual quedaba descubrible por
  `LadderService`/`StairsService` — el `push_error` decía "disabled" pero
  nada lo deshabilitaba. `LadderMotor.tick()`/`StairsMotor.tick()` derefencian
  los markers sin guardia → crash real la primera vez que el jugador entra.
  Arreglado: el guard corta antes de `add_to_group()`. Cubierto por
  `test_ladder_stairs.gd` (nuevo).
- **§10 (Reader como fachada real):** `BodyReader._body` no tenía getter
  público — `combat_broker.gd`, `bow_action.gd`, `strike_action.gd` lo leían
  directo, rompiendo la encapsulación que el propio Reader existe para dar.
  Agregado `get_body()`, los 3 call sites migrados.
- **§5 (fallo alcanzable sin log):** `DebugOverlay.register_context()`
  descartaba en silencio un context con `panel_key` en su default `-1` (p.ej.
  olvidado en el Inspector) — ahora `push_warning`. Cubierto por
  `test_debug_overlay.gd` (nuevo).
- `BodyReader.get_body_half_height()`/`get_body_radius()` caían en silencio a
  los defaults del player (1.0/0.5) si el `CollisionShape3D` no tenía
  `CapsuleShape3D` — ahora avisan una vez por instancia (`_warned_no_capsule`,
  no por frame — se llaman en el `tick()` de `StairsMotor`).
- **Duplicación real:** el fallback "si el collider no tiene `apply_damage`,
  probar el padre" vivía copiado en `combat_broker.gd` y
  `arrow_projectile.gd` — unificado en `DamageEvent.resolve_receiver()`
  (`scripts/base/`) para que golpe cuerpo a cuerpo y flecha no puedan
  divergir. Cubierto por `test_damage_event.gd` (nuevo).
- `transition_proposal.gd` estaba indentado con espacios en vez de tabs
  (único archivo de `scripts/` así) — corregido.
- `CombatDummy._flash()` creaba un `StandardMaterial3D` nuevo en cada golpe/
  telegraph en vez de reusar el `_base_material` ya creado en `_ready()` —
  ahora muta `albedo_color` sobre el mismo material.

**Validado headless, no jugado (§17):** 89/89 tests (`godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`), 5 escenas cargan sin
error. `Ladder`/`Stairs`/`CombatDummy`/`ArrowProjectile`/`GrassField`
interactúan con física/rendering real en runtime — ninguno de estos 8 fixes
se jugó todavía, sólo se verificó headless. Pendiente antes de cerrar: subir
una escalera y una escalera de mano reales, y pegarle a un `CombatDummy` con
las 4 acciones, para confirmar que el arreglo del guard no cambió el feel de
nada que ya andaba.

## Pasto: de graybox a brizna modelada, exploración de variantes, y decisión final (2026-08-14/15)

Reemplazado el quad rectangular a mano por una brizna modelada en
Blender+Python (`tools/blender/generate_grass_blade_single.py`, perfil de
"hoja" investigado en `breath-of-freedom` — punta y base en punta, cintura a
0,30 de la altura para que arquee con el viento), importada nativa en Godot
(`blade_asset_path`, nuevo `@export_file("*.blend")` en `GrassField`, con
caché por-path — sin exportar a `.glb`, pedido explícito del usuario: "pensá
un pipeline que se adapte a Godot", no el de Bevy del proyecto hermano). Si
el `.blend` no importa (máquina sin `Blender Path` configurado) cae a
`_build_fallback_blade_mesh()`, no crashea — verificado de verdad simulando
el clon fresco.

Se probaron 3 variantes intercambiables: simple cruzada (2 planos, 4 tris),
plana sin cruzar (2 tris, riesgo conocido de desaparecer de canto al orbitar
la cámara), y mata (4 hojas con raíces separadas en X, 8 tris). Medidas con
`tools/grass_density_probe.gd` (herramienta propia de píxeles-por-triángulo
— no hay nada nativo en Godot para esto) y jugadas en una escena de
comparación con colores distintos por variante.

**Decisión final: la simple cruzada gana, con una punta en V** (`tip_bend`,
dobla sólo el triángulo de arriba, no la hoja entera). Ni la plana ni la
mata mostraron ventaja clara — la mata con la mitad de instancias (mismo
presupuesto de triángulos que la simple) seguía cubriendo *menos* píxeles
(0,93–0,97×), en parte porque su eficiencia por triángulo más baja es
propia de la forma (hojas tapándose entre sí), no sólo del solapamiento
entre instancias. Assets de `tuft`/`flat` **conservados en disco** (`.blend`
+ generadores Python + `grass_blade_common.py` compartido) por si sirven
para LOD más adelante, pero sacados de toda escena
(`grass_field_tuft.tscn`/`grass_field_flat.tscn`/`grass_comparison.tscn`
borrados el 2026-08-15).

**Lecciones que quedaron (detalle completo en `git log` de los commits del
14/15, no repetido acá):**
- Un screenshot estático puede mentir sobre geometría real — 3 diseños
  sucesivos de la mata (raíces compartidas por rotar un punto sobre su
  propio eje, inclinación rígida en vez de quiebre en la punta, offset
  insuficiente) sólo se vieron mal con renders desde ángulos adicionales o
  coordenadas de vértice reales, nunca con el primer render "que se veía
  bien".
- Una escena de medición aislada (fondo negro, campo chico y cerca) exagera
  huecos que la densidad real del juego disimula — jugar la comparación
  real contradijo lo que decían las capturas más de una vez.
- **LOD, próximo tema, todavía no implementado:** la hipótesis de que
  "briznas individuales sin medir bien" causaba pop de LOD no se sostiene
  del todo — el mecanismo real es casi siempre el *corte* (transición dura
  entre niveles) más que la brizna de origen, y Godot trae nativo lo que
  `breath-of-freedom` tuvo que reinventar a mano en WGSL:
  `GeometryInstance3D.visibility_range_begin/end` +
  `visibility_range_fade_mode = FADE_SELF` (dither entre niveles, sin lógica
  custom). Sin terreno real todavía donde probarlo a distancia.

**Bug de distribución real, encontrado y arreglado el 2026-08-15:** los
centros de clump en `grass_field.gd::_build_field()` usaban
`rng.randf() * field_radius` — uniforme en *radio*, no en *área* (el área de
un anillo crece con r, así que esto amontonaba clumps cerca del centro del
campo). Arreglado con `sqrt(rng.randf()) * field_radius` (muestreo uniforme
estándar en disco). Verificado empíricamente antes de fijar el umbral del
test nuevo, no adivinado: con el bug, radio medio de brizna ≈22,9 (default
`field_radius=40`); con el fix, ≈27,5 (el teórico uniforme-en-área es
26,7). Cubierto por `test_blade_positions_are_not_biased_toward_field_center`.

99/99 tests, 6 escenas cargan sin error. **No jugado con el fix de
distribución ni la punta en V puestos juntos** — pendiente antes de dar
esto por cerrado del todo.

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

**Tests: 24 archivos, 99 tests, 99/99 en verde** (`godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`, corrido 2026-08-15).
6 escenas cargan headless sin errores (`godot --headless --quit-after`).
**Ninguno de los dos reemplaza jugarlo** (§17) — todo lo de terreno en
particular, los 8 fixes de la auditoría de `scripts/base/`+`scripts/world/`,
y el pasto (brizna + fix de distribución), todos del 2026-08-15, todavía no
se jugaron del todo, sólo se verificaron headless.

**Git:** repo inicializado 2026-08-14; sesión del 14 (terreno + fix de
`EntityController` + auditoría de `player_action_stack/`) quedó en 9 commits
sobre el pivote; sesión del 15 sumó la auditoría de `scripts/base/`+
`scripts/world/`+`debug_overlay.gd` y todo el arco del pasto (brizna
modelada → exploración de variantes → decisión final + fix de distribución,
ver sección arriba). Sin pushear todavía — hace el push la persona, no el
asistente.

## Próximo foco (propuesto, no comprometido)

1. **Seguir modificando terreno y probando Terrain3D** (explícito, siguiente
   sesión) — esculpido, texturas, más regiones. Con `EntityController` ya
   arreglado, el player debería moverse/reposicionarse con normalidad; probar
   eso primero antes de asumir que algo nuevo está roto.
2. **Jugar la caja completa** — movimiento, las 4 acciones de combate (con
   stamina real ahora), horse, escaleras/escalera de mano, `CombatDummy` y el
   pasto con la punta en V + el fix de distribución ya puestos — nada de
   esto se verificó jugado todavía, sólo headless.
3. **LOD real cuando haya terreno esculpido donde probarlo**: investigar
   `GeometryInstance3D.visibility_range_begin/end` +
   `visibility_range_fade_mode = FADE_SELF` para el cross-fade entre
   niveles de densidad — discutido esta sesión, nada implementado todavía.
4. Corregir la violación de §14 en `strike_action.gd` (llama
   `inject_forced_proposal()` directo en vez de señal-hacia-arriba +
   `EntityController` reenvía) — antes de que otro sistema copie el patrón.
5. Decidir la premisa de mundo/narrativa (`NORTE.md` → Decisiones abiertas)
   y la licencia del proyecto — ambas quedaron abiertas al pivotear lejos de
   Druid.
