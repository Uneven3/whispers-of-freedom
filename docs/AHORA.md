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

## Brizna modelada en Blender, 2026-08-15 (misma sesión)

Pedido explícito: mejorar la malla de la brizna "con estándar de industria,
low poly", hecha con Blender + Python en vez de a mano en GDScript, como
ejercicio para aprender del modelo resultante. Ejecutado con
`/iterate-safely`: plan (geometría + pipeline de import) → crítica de un
subagente sin contexto → triage → ejecución, con dos verificaciones
empíricas contra el motor real antes de escribir el plan final (no
asumidas): que Godot puede importar un `.blend` nativo headless
(`godot --headless --editor --import`, ver bullet nuevo arriba) y, ya
ejecutando, que la primera versión de la geometría estaba tumbada de costado
(construida con la altura en el eje Y en vez de Z — Blender es Z-arriba
nativo, no Y — corregido y confirmado con un render de control antes de
integrarla).

**Geometría:** `tools/blender/generate_grass_blade_single.py` (bpy, corrido
headless — renombrado el 2026-08-15 al sumar la variante mata, ver abajo)
reemplaza el quad-cruzado rectangular de
`grass_field.gd::_build_blade_mesh()` (dos planos perpendiculares, 4
vértices/2 triángulos cada uno, ancho fijo) por la forma de "hoja"
investigada y medida en el proyecto hermano `breath-of-freedom`
(`docs/BOTWGrass.md`, sección "La brizna: dos triángulos unidos por una
arista horizontal"): cada plano termina en punta arriba y abajo (la punta de
abajo hundida 6 cm bajo el suelo, no infinitamente angosta contra la
tierra), con una fila de vértices media ("cintura") a 0,30 de la altura —
sin esa fila la brizna no puede arquearse con el viento, el borde va recto
de raíz a punta. **Mismo presupuesto de triángulos que antes** (4/instancia,
2 planos × 2 triángulos) — sólo cambia el perfil, no la arquitectura del
campo ni el shader de viento (`grass_blade.gdshader`, que ya sólo depende de
`VERTEX.y` local, sin UVs — verificado antes de tocar la geometría).

**Pipeline, deliberadamente distinto al del proyecto hermano:** breath-of-
freedom exporta a `.glb` con un validador de nomenclatura específico de Bevy
(`SM_/SK_/ROOT_/bof_*`) que no aplica acá — pedido explícito del usuario
("pensá uno mejor que se adapte a Godot") tras leer ese pipeline. Acá Godot
importa el `.blend` directo y nativo (`art/blender/grass/grass_blade_single.blend`,
versionado — es chico, sin texturas). El generador también renderiza un PNG
de control (`art/blender/grass/grass_blade_single_preview.png`) sin abrir
Blender ni Godot, para poder mirar la forma antes de integrarla.

**Integración en `grass_field.gd`:** `_load_base_blade_mesh()` carga y
cachea (`static var`, una vez por proceso — evita reinstanciar la escena
importada en cada rebuild del Inspector) la malla base a altura unitaria
(1,0 m); `_rescaled_blade_mesh()` reescala sólo el eje Y por
`max_blade_height` para no perder ese knob del Inspector. **Si el `.blend`
no importó** (máquina sin `Blender Path` configurado, ver bullet arriba) cae
a `_build_fallback_blade_mesh()` — el rectángulo viejo, no un crash —
verificado de verdad simulando el clon fresco (moviendo el `.blend` y su
caché de import fuera del proyecto y confirmando que el campo se sigue
construyendo, con warning y sin error).

**Validado headless, no jugado (§17):** 92/92 tests (3 nuevos:
`test_blade_mesh_uses_the_blender_authored_asset`,
`test_blade_height_scales_with_max_blade_height`,
`test_fallback_blade_mesh_is_still_valid_if_asset_missing`), 5 escenas
cargan sin error. El render de control confirma la silueta pero **no
reemplaza verlo en el campo real** con viento, densidad e iluminación —
pendiente jugarlo antes de dar esto por terminado.

## Dos variantes de brizna para comparar + LOD como próximo tema, 2026-08-15 (misma sesión)

Tras jugar el campo (F5, `grass_field.tscn`), el usuario pidió una brizna que
"ocupe un poco más de espacio" y planteó, aparte, el problema que no logró
resolver en `breath-of-freedom`: transiciones de LOD visibles. Hipótesis del
usuario: la causa era usar briznas individuales en vez de "un modelo
estándar con medidas bien calculadas". Contraargumento dado (no
implementado, para la próxima sesión de LOD real): en la industria una
transición de LOD se nota casi siempre por el *mecanismo del corte* (un
plano de distancia fijo donde todo cambia de golpe) y por no preservar
densidad/cobertura entre niveles — no por la precisión de la malla de
origen. La lección real de `docs/reference/breath-of-freedom/BOTWGrass.md`
(#9-11: el footprint promedio subestimado 2,83× rompía la cobertura al
cambiar de nivel) apoya la parte de "medir bien", pero a nivel de fórmula de
densidad agregada, no de brizna individual. Godot trae nativo lo que
`breath-of-freedom` tuvo que reinventar en WGSL: `GeometryInstance3D.
visibility_range_begin/end` + `visibility_range_fade_mode = FADE_SELF` hace
cross-fade con dither entre niveles sin lógica custom — **no implementado
todavía**, queda pendiente para cuando haya terreno real donde probarlo a
distancia.

**Mientras tanto, para decidir con los ojos y no a ciegas:** dos variantes
de brizna instanciables por separado, comparten `grass_field.gd` sin
duplicar el mecanismo (viento, instanciado, clumps) — sólo cambia qué malla
cargan. Ejecutado con `/iterate-safely`.

- `blade_asset_path` (nuevo `@export_file("*.blend")` en `GrassField`,
  reemplaza la constante `BLADE_ASSET_PATH` fija) hace la malla-brizna
  intercambiable por Inspector. **Bug real que el propio refactor iba a
  introducir, encontrado por la crítica antes de escribir código:** el
  caché (`static var`, compartido entre instancias del mismo proceso — ej.
  el test suite entero) era una sola malla/flag, no por-path — dos
  `GrassField` con `blade_asset_path` distinto se hubieran pisado, el
  segundo recibiendo la malla del primero. Arreglado con
  `_cached_base_meshes`/`_load_failed_paths` como `Dictionary` keyeado por
  `blade_asset_path`. Cubierto por
  `test_blade_asset_path_caching_does_not_leak_across_variants` (nuevo).
- **`tools/blender/grass_blade_common.py`** (nuevo): saca lo compartido de
  los dos generadores — el perfil de una hoja (`leaf_verts()`), `place_leaf()`
  (rota + traslada una hoja completa, ver abajo por qué "completa" importa),
  setup de escena, material, guardado y render de control. Mismo patrón que
  `tools/blender_export.py`/`tools/export_blender_asset.py` del proyecto
  hermano (común importado, no duplicado).
- **`grass_blade_single.blend`** (renombrado desde `grass_blade.blend`,
  mismo generador refactorizado sobre el módulo común, geometría sin
  cambios — 2 hojas cruzadas, 4 triángulos) y **`grass_blade_tuft.blend`**
  (nuevo, `generate_grass_blade_tuft.py`): 4 hojas radiales
  (0°/90°/180°/270°) con jitter determinístico (semilla fija 7) de ±10° en
  ángulo, 0,82–1,05 en escala de alto, 0,06–0,09 en medio-ancho, y un
  offset de raíz ≤2,5cm — para que no se vea como un molinete perfecto. 8
  triángulos/instancia (2× la simple). **Corrección real de diseño que hizo
  la crítica antes de generar la malla:** el plan original decía mover "el
  punto base" de cada hoja para el offset — eso sólo hubiera desplazado un
  vértice suelto, no la hoja entera, dejando una esquina colgando en vez de
  trasladar la forma. `place_leaf()` rota y traslada los 4 vértices de la
  hoja como una unidad rígida, así el offset realmente cambia dónde nace
  cada hoja. Verificado con dos renders de control (lateral y oblicuo) antes
  de integrar — el lateral solo no mostraba el arreglo radial (las hojas
  quedan casi de canto desde ese ángulo), hizo falta el oblicuo para
  confirmarlo.
- **Dos vueltas de corrección real, ninguna encontrada por la crítica ni por
  los renders de control iniciales — sólo mirando el resultado (el usuario
  la primera vez, un chequeo nuevo desde arriba la segunda):**
  1. El diseño original tenía un error más profundo que el del "punto base":
     `angle_deg` es una rotación alrededor de Z, y `leaf_verts()` pone la
     punta y la base de cada hoja **sobre** ese mismo eje (x=y=0) — rotar un
     punto que ya está en su eje de rotación no lo mueve. Las 4 hojas seguían
     naciendo y terminando en el mismo punto central, sólo la "cintura" se
     abría un poco: de cualquier ángulo se veía como una columna apelotonada.
  2. Primer arreglo (`lean_deg`, inclinar la hoja entera alrededor de su eje
     X local antes de rotar en Z) sí separaba las puntas — pero el usuario
     aclaró que no era lo pedido: quería 4-5 briznas que **no nazcan del
     mismo origen** ("como una X" de raíces separadas, para tapar huecos
     entre briznas vecinas), y que sea la hoja misma la que se doble un poco
     — sólo el triángulo de arriba, "no mucho" — no toda la hoja inclinada
     rígida desde la base.
  - **Arreglo final:** `leaf_verts()` suma `tip_bend` — desplaza sólo la
    punta en X local, así el triángulo de arriba (punta/cintura) queda en un
    ángulo leve respecto al de abajo (base/cintura), un quiebre estático de
    reposo (distinto del arco dinámico del shader de viento). `place_leaf()`
    ya no inclina la hoja entera — `offset` pasa a ser el separador real: en
    `generate_grass_blade_tuft.py`, las 4 raíces se plantan en un patrón X de
    verdad (ángulos 45°/135°/225°/315° + jitter, radio ~9cm — comparable al
    medio-ancho de la hoja, no unos milímetros) en vez de pivotear desde un
    centro compartido. Verificado con coordenadas de vértice reales (no sólo
    con un render): las 4 raíces quedan en los 4 cuadrantes, separadas entre
    sí, cada punta claramente desplazada de su propia raíz.
- **`scenes/grass_field_single.tscn`** y **`scenes/grass_field_tuft.tscn`**
  (nuevas, directo en `scenes/` — sin subcarpeta `components/`, `scenes/`
  hoy es plana y no valía la pena una convención nueva a mitad de sesión):
  sólo el nodo `GrassField` con `blade_asset_path` apuntando a su variante.
  **`scenes/grass_comparison.tscn`** (nueva): instancia las dos, separadas
  en X (-25 y +25, `field_radius=20` cada una — no se superponen, pasillo
  libre de 10m en el medio) con el Player en el medio para caminar de una a
  otra y mirarlas con viento real.

**Validado headless, no jugado (§17):** 95/95 tests (6 nuevos, ver arriba +
`test_blade_asset_path_rebuilds_live_after_ready` y
`test_grass_comparison_scene_loads_both_variants`), 8 escenas cargan sin
error (+3: las dos nuevas componente y la de comparación). Los renders de
control confirman que ninguna hoja quedó degenerada, pero **no reemplazan
caminar por `grass_comparison.tscn` con viento real** — pendiente antes de
elegir una variante (o de decidir seguir con ambas para probar LOD después).

## Punta en V + variante plana + experimento de instancias, 2026-08-15 (misma sesión)

Jugada la comparación de 3 (simple/plana/mata, coloreadas distinto para
distinguirlas — ver arriba), la diferencia entre variantes "no se nota
mucho" a ojo. Dos ideas del usuario, ejecutadas con `/iterate-safely`:

**Punta en V en `single`:** `generate_grass_blade_single.py` ahora llama
`place_leaf(..., tip_bend=0.05)` en los dos planos (antes convergían a un
único punto en `(0,0,1.0)`). Como los dos planos son perpendiculares por
construcción, las puntas dobladas quedan en direcciones distintas, no sobre
la misma línea — no hay elección de signo que lo evite, es inherente a
cruzar dos planos. Verificado con dos ángulos de render (no sólo el de
siempre) antes de aceptarlo, y con las coordenadas de vértice reales en
Godot. `HALF_WIDTH=0.08` confirmado en `grass_blade_common.py` antes de
elegir `0.05` (mismo orden de magnitud que usa `tuft`). Cubierto por
`test_single_blade_tip_is_bent_not_a_rigid_spike` (nuevo). Como
`grass_blade_single.blend` es el default real de `blade_asset_path`, este
cambio afecta a `scenes/grass_field.tscn` (el nivel principal) además de
las escenas de comparación — se revisó que ningún test dependiera de la
forma exacta anterior (sólo cantidades de vértices/superficies).

**Experimento: ¿la mata necesita menos instancias para la misma sensación?**
`tools/grass_density_probe.gd` medía a igual cantidad de instancias — no es
la pregunta correcta, importa el presupuesto total de triángulos. Ahora
`VARIANTS` es una lista de `{name, path, blade_count}` (antes sólo rutas)
con 3 entradas: `single_3000`, `tuft_3000` (referencia) y `tuft_1500` (la
mitad de instancias — `8 tris × 1500 = 4 tris × 3000 = 12.000`, mismo costo
total exacto que `single_3000`). **Bug real que la crítica encontró antes
de correrlo:** el cálculo de triángulos totales seguía usando una constante
global fija en vez del `blade_count` de cada entrada — hubiera dado
`tuft_1500` con el doble de triángulos de los que realmente se dibujaban,
invalidando exactamente la comparación que el experimento buscaba hacer.

**Resultado medido:** a presupuesto igual, `tuft_1500` cubre *menos*
píxeles que `single_3000` (0,93× vista de pájaro, 0,97× altura de
jugador) — la hipótesis de "menos instancias, misma sensación" no se
sostiene, ni en el número ni mirando las capturas (a mitad de densidad la
mata deja de cerrar huecos tan convincentemente). El `px/tri` de
`tuft_1500` mejora respecto a `tuft_3000` (menos solapamiento entre
instancias vecinas al haber menos de ellas — 3,72 vs. 2,63 vista de
pájaro) pero sigue sin alcanzar el de `single_3000` (4,01): la eficiencia
por triángulo más baja de la mata no es sólo un efecto de solapamiento
entre instancias, es en parte propia de la forma — 4 hojas parcialmente
tapándose entre sí dentro de una misma instancia rinden menos área única
por triángulo que 2 planos cruzados bien separados, y reducir instancias
no cambia eso.

99/99 tests, 9 escenas cargan sin error. Sin decidir ganador todavía —
falta jugar la punta en V (¿se nota caminando o sigue siendo sutil?) y
mirar las capturas nuevas en `/tmp/grass_density_probe/`.

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
9 escenas cargan headless sin errores (`godot --headless --quit-after`).
**Ninguno de los dos reemplaza jugarlo** (§17) — todo lo de terreno en
particular, los 8 fixes de la auditoría de `scripts/base/`+`scripts/world/`,
y las variantes de brizna modeladas en Blender, todos del 2026-08-15,
todavía no se jugaron del todo, sólo se verificaron headless.

**Git:** repo inicializado 2026-08-14; sesión del 14 (terreno + fix de
`EntityController` + auditoría de `player_action_stack/`) quedó en 9 commits
sobre el pivote; sesión del 15 sumó la auditoría de `scripts/base/`+
`scripts/world/`+`debug_overlay.gd`, las 3 variantes de brizna comparables
(simple/plana/mata) con la investigación de LOD pendiente, y el experimento
de punta-en-V + presupuesto de triángulos igual. Sin pushear todavía — hace
el push la persona, no el asistente.

**Medido con `tools/grass_density_probe.gd`** (2026-08-15, campo chico —
3000 blades, radio 6m — para que quepa en cuadro): la mata es *menos*
eficiente por triángulo que la simple en las dos vistas (0,67× a vista de
pájaro, 0,54× a altura de jugador — paga 2× triángulos por instancia por
menos de 2× de cobertura), pero las capturas a altura de jugador muestran
algo que ese número no cuenta: la simple deja huecos grandes y contiguos
entre briznas cerca de cámara, la mata los cierra casi del todo. Sin
decidir ganador — capturas en `/tmp/grass_density_probe/` (no versionadas).

**Jugado de verdad (F5) y el número no coincidió con la sensación**: la
diferencia simple/mata "no se nota mucho" caminando por
`grass_comparison.tscn` — la escena de medición estaba aislada (fondo
negro, campo chico y cerca) y eso exageraba huecos que a densidad real se
disimulan. Lección §17 de manual. Hipótesis nueva del usuario: la que sí
vale la pena probar es la *tercera* dirección — una brizna de **un solo
plano sin cruzar** (2 triángulos, la mitad de la simple). Riesgo conocido y
deliberado (no descubierto, anotado antes de generarla): un plano sin
cruzar se vuelve invisible de canto, y la cámara en tercera persona orbita
todo el tiempo — un screenshot estático no lo puede mostrar, hace falta
jugarlo con la cámara moviéndose.

**`grass_blade_flat.blend`** (nuevo, `generate_grass_blade_flat.py`, mismo
`leaf_verts()`/`place_leaf()` compartido, un solo `place_leaf(angle_deg=0)`)
+ **`blade_color`** (nuevo `@export` en `GrassField`, pisa el uniform
`blade_color` del shader — actualiza el material en el lugar, sin rebuild
completo, mismo patrón que `cast_shadows`) para distinguir las 3 variantes
a simple vista: simple=verde (default, sin cambios), plano=azul, mata=
naranja. `grass_comparison.tscn` ahora instancia las 3 (radio 15 c/u, en
x=-35/0/35, jugador arrancando en z=25 fuera de los tres campos).
98/98 tests, 9 escenas cargan sin error. Todavía sin jugar esta variante en
particular — pendiente mirarla girando cámara cerca, el riesgo específico
que se está probando.

## Próximo foco (propuesto, no comprometido)

1. **Seguir modificando terreno y probando Terrain3D** (explícito, siguiente
   sesión) — esculpido, texturas, más regiones. Con `EntityController` ya
   arreglado, el player debería moverse/reposicionarse con normalidad; probar
   eso primero antes de asumir que algo nuevo está roto.
2. **Jugar la caja completa** — movimiento, las 4 acciones de combate (con
   stamina real ahora), horse, escaleras/escalera de mano y `CombatDummy`
   tras los fixes de hoy, y **caminar `grass_comparison.tscn`** para elegir
   simple vs. mata (o decidir seguir con ambas) — nada de esto se verificó
   jugado todavía, sólo headless.
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
