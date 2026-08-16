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

## Pasto: historia resumida (2026-08-14/15) — el sistema descripto acá ya no existe, ver sección siguiente

`GrassField` (un `Node3D`/`@tool` que armaba su propio `MultiMeshInstance3D`)
fue el primer sistema de pasto — brizna modelada en Blender+Python (perfil de
"hoja" con cintura a 0,30 de la altura, punta en V, `tip_bend`), 3 variantes
comparadas objetivamente (simple cruzada/plana/mata — ganó la simple
cruzada), un bug real de distribución (`rng.randf()*field_radius` es
uniforme en *radio* no en *área* — fix: `sqrt(rng.randf())*field_radius`),
extraído a su propia escena instanciable (`grass_patch.tscn`) con
`Editable Children` para poder tunearlo viendo el resto del nivel, un
gradiente base-punta en el shader, y varios uniforms de viento expuestos
como `@export`. **Detalle completo de cada paso en `git log`, no repetido
acá** — el 2026-08-15 se decidió migrar todo esto al instancer nativo de
Terrain3D (ver abajo) y `GrassField`/`grass_field.gd`/`grass_field.tscn`/
`grass_patch.tscn`/`tools/grass_density_probe.gd` se borraron una vez
verificada la migración. Lecciones que sí siguen aplicando: un screenshot
estático puede mentir sobre geometría real (varios diseños de la mata solo
se vieron mal desde ángulos adicionales), y una escena de medición aislada
exagera huecos que la densidad real del juego disimula.

## Estado del código, al 2026-08-15

Godot **4.7**, `run/main_scene = terrain_base.tscn` (cambiado el 2026-08-15;
antes era `grass_field.tscn`, borrada — ver sección de migración de pasto).
Escenas: `main`, `player`, `horse`, `entity_base`, `terrain_base`. Sin
animación de personaje todavía — cápsulas graybox (player azul, enemigo/
target esfera roja, interactuable cilindro amarillo — 1 unidad = 1 metro).

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

**Mundo/terreno** — `Terrain3D` (plugin, no versionado) en `terrain_base.tscn`
(ahora la escena principal), regiones esculpidas en `world_data/terrain/`,
pasto plantado ahí mismo vía el instancer nativo de Terrain3D (ver abajo).

**Debug** — `DebugOverlay` autoload, F1 togglea el panel. Reporter para
Movement y Combat vía `BaseDebugContext`/`panel_key`, mismo panel, hacen
merge (ver auditoría arriba — antes se pisaban).

**Tests: 26 archivos, 93 tests, 93/93 en verde** (`godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`, corrido 2026-08-15,
tras borrar `test_grass_field.gd` tal cual). 5 escenas cargan headless sin
errores. **Ninguno de los dos reemplaza jugarlo** (§17) — la migración de
pasto a Terrain3D, la limpieza de `player_action_stack/`, y todo lo demás de
esta sesión todavía no se jugaron del todo en el editor real, sólo se
verificaron headless y con renders reales fuera del editor.

**Git:** repo inicializado 2026-08-14; sesión del 14 (terreno + fix de
`EntityController` + auditoría de `player_action_stack/`) quedó en 9 commits
sobre el pivote; sesión del 15 sumó la auditoría de `scripts/base/`+
`scripts/world/`+`debug_overlay.gd` y todo el arco del pasto (brizna
modelada → exploración de variantes → decisión final + fix de distribución,
ver sección arriba). Sin pushear todavía — hace el push la persona, no el
asistente.

## Pasto en Terrain3D real + limpieza de player_action_stack, 2026-08-15

**Decisión de arquitectura**: en vez de que `GrassField` siga resolviendo su
propio LOD a mano, investigado y confirmado que `addons/terrain_3d` trae un
instancer de foliage nativo (`Terrain3DInstancer`, scripteable —
`add_transforms()`/`add_multimesh()`, hasta 10 niveles de LOD por asset vía
`Terrain3DMeshAsset`) que acepta nuestro mesh (`grass_blade_single.blend`)
y nuestro `ShaderMaterial` (viento + gradiente) tal cual. Verificado contra
el motor real, no contra docs: `ClassDB.class_get_method_list()` para la API
completa, y una prueba real (no headless) que registró el mesh, generó
instancias con altura real del terreno (`Terrain3DData.get_height()`), y
renderizó — funcionó.

**Implementado**: `scripts/world/grass_terrain_instancer.gd`
(`class_name TerrainGrassInstancer`, `@tool`), nodo `GrassInstancer` nuevo
en `terrain_base.tscn`. Reusa el mismo algoritmo de dispersión en clumps que
tenía `GrassField` (uniforme-en-área, misma seed), pero samplea la altura
real del terreno por punto en vez de asumir un plano y=0, y entrega las
transforms a `Terrain3DInstancer` en vez de armar su propio
`MultiMeshInstance3D`.

Bugs reales encontrados y arreglados en el camino (todos verificados contra
el motor, no asumidos):
- `Terrain3DAssets.set_mesh_asset(id, asset)` ignora el `id` que le pasás
  para una entrada nueva — siempre asigna el siguiente índice secuencial, y
  solo sobreescribe si el `id` coincide con algo ya existente. Hay que leer
  `asset.get_id()` después de registrar, nunca asumir el valor pasado.
- `Terrain3DData.get_height()` devuelve `NAN` para puntos genuinamente
  válidos si se llama antes de que corra un frame — `_build()` corre
  sincrónico en `_ready()` habría descartado el campo entero como "fuera de
  región", pasto invisible sin error. Arreglado con `call_deferred()`.
- `Transform3D.scaled(v)` escala también el `origin` (confirmado:
  `Transform3D(basis, Vector3(3,0,4)).scaled(Vector3(2,2,2)).origin ==
  (6,0,8)`), no solo la base — cada brizna con `scale` != 1.0 derivaba su
  posición hasta un 40%. Bug real, preexistente también en `grass_field.gd`
  (mismo patrón, nadie lo notó porque el margen del test de bounds era
  generoso). Arreglado en los dos archivos con `scaled_local()`.
- Bajo el renderer dummy headless, `Terrain3DInstancer.add_transforms()`
  falla con "Mesh ID out of range" aunque el mesh esté bien registrado — no
  se resuelve esperando más frames. Por eso los tests
  (`test_grass_terrain_instancer.gd`) solo ejercitan la generación pura de
  posiciones (`_generate_instance_data`, sí testeable headless via
  `Terrain3DData` real), nunca llaman `add_transforms` directo.

**Reducción de alcance reconocida**: `TerrainGrassInstancer` no tiene
`max_blade_height`/`blade_width_scale` como `GrassField` — Terrain3D consume
el mesh del `.blend` tal cual, sin gancho para re-escalar vértices antes de
registrarlo. El tamaño total sigue variando por instancia vía
`min_scale`/`max_scale` (uniforme en los 3 ejes), pero no independiente por
eje. Revisar si hace falta más adelante (pre-hornear una variante
re-escalada del mesh, por ejemplo).

**De paso, arreglados 2 hallazgos de una revisión de arquitectura anterior**
(`scripts/player_action_stack/`, ver auditoría de esta sesión):
- `camera_rig.gd` tenía rutas hardcodeadas (`"../EntityController/..."`) que
  romperían en silencio si se reusara en otra entidad (ej. Horse). Ahora
  `entity_controller_path` es un `@export NodePath`, mismo patrón que
  `MovementBroker.brain_path`. Sin cambios de comportamiento en
  `player.tscn` (el default sigue resolviendo igual). Quedan 2 casos menores
  del mismo patrón sin tocar (`climb_toggle_component.gd:31`,
  `visuals_pivot.gd:23`) — defensivos, no rotos hoy, deuda conocida.
- `walk_motor.gd`/`sprint_motor.gd`/`sneak_motor.gd` duplicaban el mismo
  patrón de aceleración/desaceleración horizontal — extraído a
  `BaseMotor.apply_ground_velocity()`. Agregados tests mínimos para los tres
  (no existían antes).

117/117 tests. No jugado en el editor real todavía — solo verificado con
scripts headless/con-display-real fuera del editor.

**Cierre de la migración, mismo día:** verificado en el editor real que el
pasto se ve. Con eso, borrado lo obsoleto: `scenes/grass_field.tscn`,
`scenes/grass_patch.tscn`, `scripts/world/grass_field.gd`,
`test/unit/test_grass_field.gd`, y `tools/grass_density_probe.gd` (su única
razón de ser era comparar variantes de `GrassField`, ya no aplica — decisión
tomada sin preguntar, marcarla si hace falta reconsiderar). `project.godot`:
`run/main_scene` → `terrain_base.tscn`. 93/93 tests tras el borrado.

**Hallazgo al reimportar con el editor real** (`godot --headless --editor
--import`): Terrain3D efectivamente hornea las instancias de pasto en los
`.res` de región (`world_data/terrain/*.res` casi duplicaron su tamaño) y en
`terrain_assets.tres` (el `Terrain3DMeshAsset` + `ShaderMaterial` quedan
serializados ahí) — a diferencia de `GrassField`, que regeneraba todo en
cada `_ready()` sin tocar disco. Verificado que esto es **determinista y
estable**: correr el import dos veces produce bytes idénticos (mismo seed),
y correr el juego real (`godot --headless scenes/terrain_base.tscn`, sin
`--editor`) no toca esos archivos en absoluto — el guardado es específico
del contexto editor, no pasa en gameplay. Coincide con el modelo real de
Terrain3D (instancias persistidas junto con el terreno, como el esculpido),
no es un bug.

**Efecto colateral a revisar**: el mismo reimport creó 2 archivos de región
nuevos (`terrain3d-02-01.res`, `terrain3d-02_00.res`, chicos — 9,8KB y
37KB contra ~300KB de los reales) que no existían antes. Hipótesis: el
`field_radius=40` de `GrassInstancer` (heredado del default de `GrassField`)
alcanza un poco más allá del área realmente esculpida (~grid 3x3 alrededor
del origen), y algunos puntos cerca del borde devuelven una altura válida
(no NAN) en celdas de grilla sin esculpir de verdad, generando ahí instancias
sueltas. No es peligroso (determinista, archivos chicos) pero probablemente
valga la pena bajar `field_radius` para que coincida con el área realmente
esculpida, en vez de dejar que Terrain3D siga creando regiones vacías.
Pendiente, no resuelto en este pase.

**Bug real encontrado por el usuario mirando el Asset Dock de Terrain3D**:
`_build()` no buscaba una entrada existente antes de registrar el mesh —
cada vez que `terrain_base.tscn` se abre en el editor (ni hace falta
jugarlo, `_ready()` de un `@tool` corre solo con tener la escena cargada
para editar), `next_index := assets.get_mesh_list().size()` crecía y se
agregaba OTRA entrada de pasto en vez de reusar la anterior — duplicados
horneables en `terrain_assets.tres` cada sesión de editor. Arreglado
buscando una entrada existente por nombre (`mesh_name`) antes de decidir el
índice; si existe, se reusa (overwrite in place); si no, recién ahí se
agrega. Verificado corriendo el reimport 3 veces seguidas: se mantiene en 2
entradas (`New Mesh` + la nuestra), estable/idéntico byte a byte.

## Próximo foco (propuesto, no comprometido)

1. **Seguir modificando terreno y probando Terrain3D** (explícito, siguiente
   sesión) — esculpido, texturas, más regiones. Con `EntityController` ya
   arreglado, el player debería moverse/reposicionarse con normalidad; probar
   eso primero antes de asumir que algo nuevo está roto.
2. **Jugar la caja completa** — movimiento, las 4 acciones de combate (con
   stamina real ahora), horse, escaleras/escalera de mano, `CombatDummy` y el
   pasto con la punta en V + el fix de distribución ya puestos — nada de
   esto se verificó jugado todavía, sólo headless.
3. **Verificar en el editor real que tunear `TerrainGrassInstancer` en vivo
   no ensucia `world_data/terrain/*.res`** (ver sección de migración a
   Terrain3D abajo) antes de agregarle setters de rebuild-en-vivo como los
   que tiene `GrassField`. Después de eso: tunear niveles de LOD reales vía
   `Terrain3DMeshAsset.set_last_lod()`/`set_lodN_range()` (superó a la idea
   original de `GeometryInstance3D.visibility_range_*` — ver abajo, por qué).
4. Corregir la violación de §14 en `strike_action.gd` (llama
   `inject_forced_proposal()` directo en vez de señal-hacia-arriba +
   `EntityController` reenvía) — antes de que otro sistema copie el patrón.
5. Decidir la premisa de mundo/narrativa (`NORTE.md` → Decisiones abiertas)
   y la licencia del proyecto — ambas quedaron abiertas al pivotear lejos de
   Druid.
