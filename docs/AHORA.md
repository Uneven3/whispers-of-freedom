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
- **Medir rendimiento: `tools/measure/`**, ver su `README.md`. Un solo
  comando (`godot --path . --resolution 1920x1080 -s
  tools/measure/scene_report.gd`) da ms por capa contra el presupuesto,
  costo del pase de sombras, overdraw cuantificado y conteos por pase.
  Necesita **pantalla real**, no `--headless` (el driver dummy no rasteriza:
  todo da 0). La resolución no es opcional — la escena es fill-bound.
  Guarda la captura de overdraw en `/tmp/godot_measure/`; mirarla es parte
  del método, no un extra (así se encontró que el `DebugOverlay` estaba
  contaminando el histograma).
- **CORRECCIÓN, 2026-08-20:** este archivo venía afirmando que "Overdraw es
  visual, no scripteable". **Es falso.**
  `RenderingServer.viewport_set_debug_draw(rid, VIEWPORT_DEBUG_DRAW_OVERDRAW)`
  se activa por script y el framebuffer se lee y se cuenta. Tiene un techo
  duro: satura a las ~25 capas, y ahí 26 capas y 200 son indistinguibles —
  por eso la herramienta reporta siempre el % de píxeles saturados.

## Historial cerrado 2026-08-14/15 — el detalle está en `git log`

Resumido acá porque ya no se toca; cada punto tiene sus commits.

- **Pivote**: se descartó el shapeshifting por un solo personaje con moveset
  completo, más cerca de BOTW. La crítica encontró un bug real antes de
  escribir código (apuntar el arco disparaba un golpe el mismo frame),
  resuelto con prioridad explícita en `CombatBroker.tick()`.
- **Terreno**: Terrain3D instalado, `terrain_base.tscn` creada, `SpawnSnap`
  reemplaza el spawn Y hardcodeado.
- **El bug de "player atascado"**: `EntityController` era `extends Node`, no
  `Node3D`, y `Node3D` sólo hereda transform de su padre **inmediato** —
  mover `Player` nunca movía la cápsula. Mismo bug en `horse.tscn`.
- **Dos auditorías `/code-review`** (52 archivos entre las dos): 17
  hallazgos reales arreglados. Notables: `Ladder`/`Stairs` se agregaban a su
  grupo *antes* de validar sus marcadores, así que un nodo mal armado quedaba
  descubrible y crasheaba al entrar; y el fallback de `apply_damage` estaba
  duplicado entre golpe y flecha, unificado en `DamageEvent.resolve_receiver()`.
- **Pasto**: `GrassField` propio → migración al instancer nativo de Terrain3D
  → tarjetas billboard autoradas a mano. Historia completa en
  `docs/pasto_godot.md`. Bugs de motor que salieron en el camino y siguen
  valiendo: `set_mesh_asset()` ignora el `id` que se le pasa para una entrada
  nueva; `get_height()` devuelve NAN si se llama antes del primer frame; y
  `Transform3D.scaled()` escala también el `origin` (usar `scaled_local()`).

**Patrón que se repite y conviene recordar:** el editor de Godot cachea
estado en memoria y no siempre recoge cambios externos al archivo. Ya mordió
con `project.godot`, con `SpawnSnap` y con `terrain_assets.tres`. Si algo no
refleja un cambio reciente, reiniciar Godot entero antes de asumir que el
código está mal.


## Estado del código, al 2026-08-20

Godot **4.7.2**, `run/main_scene = terrain_base.tscn`. Escenas: `main`,
`player`, `horse`, `entity_base`, `terrain_base`, `terrain_valley` (nueva,
**no renderiza todavía**), más las de comparación en `scenes/test/`. Sin
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

**Mundo/terreno** — `Terrain3D` (plugin, no versionado) en `terrain_base.tscn`,
regiones esculpidas en `world_data/terrain/`, pasto plantado vía el instancer
nativo. El pasto ya usa **material opaco** (`material_mode = 1`), no la
tarjeta con alfa. `terrain_valley/` es un segundo escenario generado
proceduralmente, con datos y assets propios.

**Agua** — `water_stylized.gdshader`, opaca con reflejo de cielo por
especular estándar, sin lectura de pantalla. Escrita y usada por
`terrain_valley.tscn`, **sin medir todavía** porque esa escena no dibuja.

**Rendimiento** — presupuesto en `docs/presupuesto_render.md`, herramientas
en `tools/measure/`. A 1080p60 `terrain_base` entra en 8,53 ms de 16,67.

**Debug** — `DebugOverlay` autoload, F1 togglea el panel. Reporter para
Movement y Combat vía `BaseDebugContext`/`panel_key`, mismo panel, hacen
merge (ver auditoría arriba — antes se pisaban).

**Tests: 100 tests, 469 asserts, 100/100 en verde** (`godot --headless -s
addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`, corrido 2026-08-20).
**Los tests no reemplazan jugarlo** (§17), y a esta altura hay bastante
acumulado sin jugar — ver el foco de abajo.

**Git:** repo inicializado 2026-08-14. **Sin pushear todavía** — hace el
push la persona, no el asistente.

## Presupuesto de render decidido, 2026-08-20 — ver `docs/presupuesto_render.md`

Se dejó de medir para comparar y se pasó a medir contra un presupuesto.
Decisiones tomadas por el usuario: **piso de hardware = esta máquina
(Radeon Polaris 11, clase RX 460/560 de 2016), 1920x1080, 60 fps → sobre
de 16,67 ms por frame**, pasto denso por zonas con el presupuesto fijado
contra la peor zona. El reparto completo, las conversiones medidas y las
advertencias están en `docs/presupuesto_render.md`; se verifica con
`godot --path . --resolution 1920x1080 -s tools/render_budget_probe.gd`
(necesita pantalla real, no headless).

**Cambio de unidad, y por qué importa**: todo lo anterior estaba medido en
FPS y primitivos, que no se reparten en tajadas (los FPS no se suman ni
son lineales). Además el vsync clava a 60 acá, así que por debajo del
techo el FPS no informa nada. Ahora se mide en GPU ms reales
(`RenderingServer.viewport_get_measured_render_time_gpu()`, confirmado
que funciona en 4.7.2 Forward+/Vulkan y devuelve valores reales con
pantalla).

**Hallazgos que reordenan las prioridades:**

- **La escena es fill-bound, confirmado**: `ms ≈ 2,1 + 6,4 × megapíxeles`,
  con menos de 1% de error en tres resoluciones. Bajar triángulos no es
  la palanca — coincide con que las sesiones 17-18 midieran escalado
  perfecto de triángulos sin la mejora correspondiente.
- **El terreno es la tajada más grande, no el pasto**: a 1080p, terreno
  9,04 ms / pasto 5,06 ms / base 1,23 ms = 15,33 ms, o sea 92% del sobre
  de 60 fps **con una escena sin enemigos, sin animación de personaje,
  sin VFX de combate y sin post-procesado**. El punto 7 de abajo deja de
  ser curiosidad y pasa a bloquear todo lo demás. Hipótesis a verificar:
  el costo está en el shader por píxel de `Terrain3DMaterial` (macro
  variation, projection/triplanar, depth blur, noise, todo en default),
  no en el clipmap ni en los LOD de malla, porque ya sabemos que no
  somos vertex-bound.
- **El alfa cuesta 15x con geometría idéntica**: la misma mata, mismos
  vértices, mismas instancias, a 16000 — 26,46 ms con el shader de atlas
  contra 1,78 ms con material opaco unshaded. Y la opaca cubre *más*
  píxeles (724k vs 708k), porque no recorta nada. Es la confirmación
  empírica y en milisegundos de lo que la sesión 21 había concluido
  leyendo a BOTW y a `breath-of-freedom`.
- **Bug que ensucia mediciones viejas**: `grass_blade_single` renderizado
  con `grass_blade.gdshader` **no dibuja absolutamente nada** — 0 píxeles
  cubiertos, medido. La malla no tiene UV (se le sacó a propósito en la
  sesión 20), así que samplea el atlas en (0,0), alfa 0, y descarta todo.
  Toda comparación "brizna vs mata" hecha con ese shader estaba midiendo
  una brizna invisible contra una mata visible. Afecta a partes de las
  sesiones 17-19. La brizna sólo se mide bien con material opaco.

## Herramientas de medición + el pasto opaco medido en la escena real, 2026-08-20

Ejecutado con `/iterate-safely`; la crítica de un subagente sin contexto
encontró tres bloqueantes antes de escribir código, y los tres eran reales
(detalle en el mensaje de commit). Nada de código de producción se tocó:
`tools/measure/grass_instancer_probe.gd` **hereda** de
`scripts/world/grass_terrain_instancer.gd` y sobreescribe un solo método.
Se prefirió heredar antes que duplicar las ~220 líneas del original porque
dos copias del algoritmo de dispersión divergirían en silencio y mediríamos
un campo de pasto que no es el que se shipea.

**Lo que ahora se puede medir y antes no:**

- **Overdraw cuantificado** (no sólo mirado). Ver la corrección arriba: el
  proyecto lo daba por no scripteable y no lo es. Se calibra en cada corrida
  contra un quad de una capa conocida en un `SubViewport` propio, en vez de
  hardcodear la constante del motor.
- **Costo real del pase de sombras**, por delta de ms (apagar
  `shadow_enabled` y restar). Da **1,45 ms, 9,7% del frame**. No se infiere
  de los conteos de primitivas del pase SHADOW: ese pase es depth-only y
  cuesta muchísimo menos por primitiva que el de color — inferir ms desde
  primitivas es la falacia que este proyecto ya descartó.
- **Conteos por pase** (`viewport_get_render_info`), visible vs sombra vs
  canvas. Diagnóstico, no costo. Dato llamativo: el pase de sombras dibuja
  **más** primitivas (480 568) y más draw calls (65) que el pase visible
  (269 792 / 44).

**El resultado que cierra la pregunta abierta del presupuesto** — la brizna
opaca medida dentro de `terrain_base.tscn`, misma cantidad de instancias
(4000), misma dispersión, misma cámara:

| | pasto de producción (alfa) | pasto opaco |
|---|---|---|
| costo del pasto | 5,01 ms | **2,34 ms** |
| capas promedio | 12,92 | **1,40** |
| capas máximas | 25,29 (clavado en el techo) | **9,01** (real) |
| % del pasto con 8+ capas | 64,98 % | 0,01 % |
| saturación | 10,19 % de la pantalla | ninguna |
| frame proyectado con lo reservado | 18,38 ms — **excedido** | 15,66 ms — **dentro del sobre** |

O sea: **cambiar la técnica del pasto, sin tocar densidad ni distancia,
alcanza por sí solo para meter el frame dentro del presupuesto**, con 1,01
ms de contingencia. El pasto con alfa no sólo cuesta el doble: está tan
fuera de escala que el instrumento satura en el 10% de la pantalla y el
número real de capas ahí es desconocido y mayor que 25.

**Verificado, no asumido:** correr las herramientas deja `git status`
limpio — `set_mesh_asset()` y `clear_by_mesh()` en contexto de juego no
tocan `world_data/terrain/`. La crítica marcó con razón que esto estaba
dicho como "ya verificado" cuando sólo se había verificado `clear_by_mesh`.

**Todavía no decidido:** la comparación es a igual cantidad de instancias,
no a igual densidad visual — una brizna cubre mucha menos pantalla que una
mata de 4 tarjetas, y en la captura las briznas además se ven demasiado
altas contra la cápsula del jugador. Antes de adoptar el cambio hay que
mirarlo jugado y decidir la escala real de la brizna.
## Agua, higiene, escenario nuevo y dos trampas de medición, 2026-08-20

Todo lo de abajo salió de una sola sesión larga, la mayor parte con
`/iterate-safely`. Las tablas completas están en
`docs/presupuesto_render.md`; acá va lo que cambia decisiones.

**El pasto opaco se adoptó.** `TerrainGrassInstancer` tiene ahora
`material_mode` (atlas_alpha / opaque) y `grass_blade_opaque.gdshader`. Son
dos shaders y no un uniform porque `alpha_to_coverage` es un `render_mode`,
o sea que se fija al compilar. Con eso, a 1080p60 la escena entera entra en
8,53 ms de 16,67, con 4,64 ms de contingencia después de reservar
personajes y VFX — sin bajar resolución ni framerate.

**El pasto opaco tiene costo NEGATIVO** (−1,34 ms a 1080p): la escena con
pasto cuesta menos que sin él. Los opacos se ordenan de adelante hacia
atrás, así que el pasto se dibuja antes que el terreno y Early-Z rechaza los
fragmentos de terreno de atrás — el caro shader de `Terrain3DMaterial` nunca
corre ahí. La prueba de que es oclusión y no un artefacto es el cambio de
signo: el mismo pasto en alfa cuesta +5,01 ms. **El pasto opaco no compite
con el presupuesto del terreno, lo alivia.**

**Guardián nuevo:** el instancer avisa si se le pone una malla sin UV en
modo `atlas_alpha`. Es el bug que hizo desaparecer el pasto al cambiar
`blade_asset_path` en el editor — la malla se renderiza invisible y no hay
un solo error en consola. `push_warning` y no `assert` (§5): lo produce un
diseñador desde el Inspector.

**Higiene de frame pacing.** Casi todo ya estaba bien (vsync activo,
`max_fps=0`, cachés de pipeline y de shaders encendidas); lo único que
faltaba era `physics/common/physics_interpolation`, ahora en `true`. El
riesgo real son los teletransportes; hay exactamente uno (`SpawnSnap`) y ya
llama `reset_physics_interpolation()`.

**Costo de lo que todavía no existe**, medido encendiendo una cosa por vez:
niebla de profundidad +0,12 ms, niebla volumétrica +1,11 (y **cuesta lo
mismo con cualquier densidad** — es una grilla de froxels de costo fijo),
una luz omni con sombras +0,99, glow +2,48, **SSAO +6,97 y SSR +8,17, los
dos inviables** en este hardware. El pase de sombras actual cuesta 1,45 ms
(9,7% del frame), medido por delta y no por conteos.

**El agua es el peor caso del proyecto**, no por el número sino porque no
tiene perilla: el pasto se ralea o se aleja, un lago cubre lo que cubre. A
igual superficie, transparente cuesta 1,98x y con refracción 2,26x contra
opaca.

**Regla operativa que sale de todo esto:** antes de agregar cualquier cosa,
preguntar si es opaca o transparente. Opaca es casi gratis y probablemente
ayude. Transparente con muchas capas superpuestas es la categoría que ya
costó el presupuesto una vez.

### Dos correcciones a cosas que este mismo archivo afirmaba

**El VFX de estela nunca fue un problema de rendimiento.** El punto 6 del
foco viejo pedía bajarle el poly count: `SphereMesh` en 64x32 por defecto,
~63000 triángulos por golpe. Se arregló (6x3), pero medido en milisegundos:
**62640 triángulos cuestan 0,027 ms**, y el efecto entero sin arreglar
costaba 0,040 ms. La preocupación venía de contar triángulos, que es
exactamente lo que este proyecto ya había demostrado que no predice el
costo. El arreglo queda porque saca desperdicio evidente, no porque haya
comprado nada.

**El overdraw sí es medible**, contra lo que decía la sección "Cómo
trabajar" hasta hoy. Ver la corrección allá arriba.

### Dos trampas de medición que costaron corridas enteras

**Compilación de pipelines.** Un shader se compila en su primer dibujo y
estanca el frame: la escena del valle daba 2 fps y 581 ms de CPU en la
primera fase, y 101 fps apenas terminaba. Un warmup fijo no alcanza porque
no se sabe cuánto tarda. `scene_report.gd` ahora espera a que los contadores
`PIPELINE_COMPILATIONS_*` dejen de moverse. Síntoma para reconocerlo: el
temporizador de GPU deja de moverse entre fases mientras los FPS cambian
muchísimo.

**`emitting = true` no re-emite un `one_shot` ya terminado** — hace falta
`restart()`, que es lo que hace el código real. Sin eso las partículas nunca
se dibujaron y los conteos daban idénticos en todas las variantes. Y un
efecto que dura ~11 frames medido con una ventana de 90 mide 79 frames de
nada: hay que re-dispararlo durante toda la ventana y reportarlo como peor
caso continuo.

### Escenario nuevo, a medio terminar

`tools/worldgen/generate_valley.gd` genera un heightmap procedural de
1024x1024 m con meseta alta, lago y un río tallado por una curva
Catmull-Rom, más las mallas de agua (disco con UV radial para el lago, cinta
de 3 vértices por sección para el río). Escribe **sólo** a
`world_data/terrain_valley/`, con su propio `Terrain3DAssets` — reusar el
`terrain_assets.tres` del terreno esculpido habría dejado que el `@tool` del
instancer lo mutara con sólo abrir la escena. `world_data/terrain/` se
verificó limpio después de cada corrida.

El dato es correcto pero **la escena no renderiza** — ver el foco de abajo.

## §15 aplicado, densidad de pasto, agua y niebla — 2026-08-21

### Comentarios: 762 → 403 líneas, 62 bloques ilegales → 0

§15 no dice "sin comentarios": dice invariantes de ≤3 líneas, nunca el *qué*,
y el rationale largo a `docs/`. Se hicieron las tres cosas por separado, y el
conocimiento no se perdió — se mudó y ahora tiene índice en `docs/README.md`.

`docs/movimiento.md` es nuevo: spawn, escaleras, suelo, trepar, visuales,
jerarquía de nodos, arbitraje de combate, cámara.

**La trampa que casi se pierde:** `##` pegado a una declaración **es API que
consume el editor** (descripción de clase en Ayuda, tooltip del Inspector).
Mudarlo entero a `docs/` le saca el tooltip a quien tunea desde el Inspector.
Se comprime en el lugar; sólo el `##` suelto dentro de una función es prosa
mudable.

Verificación: el generador del valle regenera **byte a byte idéntico** (md5
de los tres `.res`), y los renders salieron iguales. Los tests no validan
comentarios, así que ninguna de las dos cosas la cubre GUT.

### El valle renderiza y se mide — las entradas "roto" eran falsas

Medido: **8,47 ms**, mediana 8,47 / p95 8,48 / max 8,50. Los dos
temporizadores funcionan. Las tres entradas de "lo que está roto" del foco
anterior estaban desactualizadas.

### Densidad de pasto: la curva es en U

Tabla completa en `presupuesto_render.md`. Resumen: **más pasto sale más
barato hasta las ~192 000 briznas**, porque cada brizna opaca ocluye píxeles
del shader caro de Terrain3D vía Early-Z. Adoptado **96 000 (8,5/m²)** y no
el mínimo, porque a 192 000 el instrumento de overdraw satura y el margen
para lo que no existe todavía vale más que 0,41 ms.

`terrain_valley` pasó de 8,46 a 5,82 ms **subiendo** el pasto x6.

### Agua: dos variantes, misma plata

`water_stylized.gdshader` reescrito: la normal viene guardada en una
`NoiseTexture2D` en vez de derivarse por diferencia central sobre ruido
procedural. Eran **44 `sin()` por píxel** y sin mipmaps, que es por qué había
un fade de detalle — un parche a un problema que la técnica se causaba sola.

`water_windwaker.gdshader` es nuevo: bandas duras, parches de espuma celular,
contorno de orilla. Archivo aparte porque la diferencia es de técnica.

Parado en la orilla: **11,81 ms la estilizada, 11,63 el Wind Waker**. La
elección es estética.

**El peor caso de la escena es mirar el lago, no estar parado en el pasto**:
sin pasto que ocluya se paga el terreno entero.

### Niebla de perspectiva aérea: +0,48 ms

Agregada a `terrain_valley.tscn`. No tapa una distancia corta — hace que la
profundidad se lea, y de yapa disuelve el fondo plano de Terrain3D contra el
cielo.

Reencuadre verificado: la distancia de visión del *terreno* en BOTW es larga
y sin niebla; lo corto es el LOD de detalle y actores.

### Dos experimentos que NO funcionaron — no repetirlos

1. **Normal map horneado desde el albedo del suelo.** Se probó a fuerza 4,0 y
   1,2. Las dos veces el terreno lejano chispea: relieve por debajo del píxel
   sin nada que lo filtre, la misma clase de problema que tenía el ruido del
   agua. Cerca no gana casi nada porque el relieve pintado de
   `painterly-meadow-grass-002` ya hace ese trabajo. Revertido entero.
2. **Igualar `blade_color`/`tip_color` al promedio de la textura del suelo.**
   La comparación estaba mal hecha: el pasto es `unshaded` y el terreno está
   iluminado, así que comparar albedo crudo contra albedo crudo mide lo que
   no es. Medido sobre píxeles renderizados el escalón es de **+10,9% de
   luminancia** — los colores originales ya estaban bien. Revertido.

## Próximo foco — acordado 2026-08-21

### Dos decisiones de un número, que sólo se pueden tomar mirando

1. **`blade_height`.** Con 1,4 briznas/m² no se notaba; con 8,5 el pasto le
   llega al cuello a la cápsula. Hay que decidir si esa escala es la que se
   quiere.
2. **Cuál de las dos aguas.** Cuestan lo mismo (0,18 ms de diferencia).
   `--water=stylized|windwaker` en `scene_report.gd` las intercambia sin
   tocar la escena.

Las dos son §17: se juegan, no se miran quietas. Y el shader de agua es
animado, así que una captura fija esconde problemas de movimiento.

### Lo que está hecho pero nunca se jugó (§17)

3. **La caja completa**: movimiento, las 4 acciones de combate con stamina,
   horse, escaleras y escalera de mano, `CombatDummy`.
4. **La interpolación de física**, activada el 2026-08-20. Sólo se juzga
   moviéndose; atención al spawn, el único teletransporte del proyecto.

### Deuda anotada, sin urgencia

5. `world_data/terrain/terrain_assets.tres` está modificado por el editor: el
   `@tool` del instancer horneó el shader opaco adentro de un archivo
   versionado con sólo abrir la escena. Hoy coincide con la realidad, pero el
   mecanismo se va a repetir.
6. El generador no preserva el UID de `valley_assets.tres`, así que la escena
   avisa `invalid UID` y cae al path de texto. Funciona, pero ensucia el log.
7. Corregir la violación de §14 en `strike_action.gd`.
8. Decidir la premisa de mundo/narrativa (`NORTE.md`) y la licencia.
9. **El terreno sigue siendo la tajada más grande** (8,6 ms de 16,67).
   Hipótesis sin probar: el costo está en el shader por píxel de
   `Terrain3DMaterial`, no en el clipmap — ya sabemos que no somos
   vertex-bound.

## Rendimiento del pasto — superado, ver `docs/presupuesto_render.md`

Esta sección tenía el resumen de las sesiones 17-21 en FPS y primitivos.
Quedó obsoleta el 2026-08-20 al pasar a medir en milisegundos de GPU: los
FPS no se reparten en tajadas y el vsync clava a 60, así que por debajo del
techo no informan nada. El historial completo sigue en
`docs/pasto_godot.md`; los números vigentes, en
`docs/presupuesto_render.md`.
