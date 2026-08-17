# Auditoría de código y escenas — 2026-08-16 (madrugada, sin supervisión)

Hecha con `/iterate-safely` mientras el usuario dormía, a pedido explícito:
*"revisa que los script estén bien asociados a nodos, que las escenas
estén bien construidas y revisar si se pueden mejorar algunas cosas con
como las escenas están armadas."* Alcance: todo el repo, no solo el
sistema de pasto (eso sigue en `docs/pasto_godot.md`).

Metodología: 3 subagentes en paralelo (fork, sin contexto previo salvo lo
que se les pasó explícito), cada uno auditando una dimensión distinta
contra `docs/ARCHITECTURE.md` (las leyes §1-§19) como rúbrica, no contra
convenciones genéricas de Godot. Sin ceremonia de crítica-de-plan separada
para esta tarea — es en sí misma una tarea de auditoría/lectura, no un
cambio de código a criticar antes de escribir.

**Segunda pasada, más profunda, a pedido explícito** ("haz un audit
profundo... revisaste los modelos .blend, los scripts para generarlos, si
la normal apunta correctamente?"): la primera pasada no había tocado la
geometría de las mallas de pasto ni sus generadores — ver sección
"Segunda pasada: geometría y shader del pasto" más abajo.

**Qué se arregló ya, verificado (97/97 tests, partida real headless sin
errores):** ver "Arreglado" abajo. **Qué queda para que decidas vos:** ver
"Para revisar" — nada de eso se tocó sin tu confirmación.

## Arreglado (bajo riesgo, reversible, ya verificado)

### 1. `show_checkered = true` en `terrain_base.tscn` — probable causa real
del shimmer que veníamos persiguiendo toda la noche

**El hallazgo más importante de esta auditoría.** `Terrain3DMaterial` (línea
28) y el nodo `Terrain3D` (línea 60) tenían **los dos** `show_checkered =
true` — un flag de debug que fuerza el patrón de cuadros en vez de
renderear el terreno real. El default de esa propiedad es `false`
(confirmado por reflexión contra el motor real), así que alguien lo
prendió a mano — muy probablemente durante el esculpido del terreno, para
ver la forma sin depender de una textura, y quedó prendido.

Un patrón de cuadros de alta frecuencia, visto en ángulo rasante hacia el
horizonte, es un generador de moiré clásico — coincide con "no cambia con
el viento apagado" (no tiene nada que ver con el pasto) y con la forma de
cono hacia el fin del campo que describiste. **No se confirmó viéndolo
jugado** (no puedo verlo yo) — es el candidato más fuerte encontrado hasta
ahora, no una certeza. Apagado en las dos ubicaciones. **Esto es lo
primero que probaría al despertar, antes incluso de pasarme texturas** —
puede que ya no haga falta nada más para el shimmer.

### 2. `docs/ARCHITECTURE.md` desactualizado

La tabla "Mapa de módulos" seguía listando `GrassField` como parte de
`scripts/world/` — se borró hace varias sesiones (`grass_field.gd`
reemplazado por `TerrainGrassInstancer`/`grass_terrain_instancer.gd`,
documentado en `docs/AHORA.md`). Corregido a `TerrainGrassInstancer`.

### 3. Inconsistencia menor en `movement_broker_debug_reporter.gd`

`_on_physics_tick_complete()` llamaba `get_node("/root/DebugOverlay")` una
segunda vez al final de la función (ya la había resuelto indirectamente
con `has_node()` al entrar), sin el guard `has_method("push")` que sí
tienen los otros dos reporters de debug (`combat_debug_reporter.gd`,
`player_action_debug_context.gd`). Alineado al mismo patrón: cachear la
referencia una vez, chequear el método antes de llamarlo.

## Para revisar (necesitan tu criterio, no se tocó nada)

Ordenado por lo que creo que vale más la pena mirar primero.

### A. `grass_terrain_instancer.gd` pasó las ~300 líneas (§16, señal de dividir, no bloqueo duro)

Está en **365 líneas** ahora, después de toda la sesión de pasto. `§16` del
propio `ARCHITECTURE.md` lo marca como señal de dividir, no como violación
dura. No lo toqué — dividir esto bien (¿separar la generación de
posiciones de la integración con Terrain3D? ¿el cálculo de rangos de LOD
en otro lado?) es una decisión de diseño que prefiero que hagas vos, no
algo para partir a las 3am sin poder validarlo jugando.

### B. Nodos huérfanos en `player.tscn`: `CameraRig/CameraBrain`, `CameraBroker`, `Effects`

Tres nodos tipo `Node`, sin script, hijos de `CameraRig`, que
`camera_rig.gd` nunca referencia (solo usa `$Lens`/`$Lens/Camera3D`). Los
nombres sugieren un patrón Brain/Broker para cámara que se empezó a
scaffolder y nunca se completó. Puede ser a propósito (dejado ahí para
retomarlo) — no los borré por las dudas. Si no tenés planes de usarlos,
son candidatos limpios para borrar.

### C. `scenes/main.tscn` no está conectado a nada

No es la escena principal (`project.godot` → `terrain_base.tscn`), ningún
otro `.tscn` la instancia, ningún test la carga. Sí instancia `player.tscn`
+ `horse.tscn` (jugador y caballo juntos, sin terreno) — parece una escena
de prueba manual que abrís vos a mano en el editor. No es un bug, solo
quedó desconectada del resto — avisame si todavía la usás así a propósito.

### D. Hueco de test real: 8 de 14 motores de movimiento sin cobertura de comportamiento

`auto_vault_motor`, `fall_motor`, `glide_motor`, `jump_motor`,
`ladder_motor`, `mantle_motor`, `stairs_motor`, `wall_jump_motor` no tienen
ningún test dedicado — solo el wiring genérico de `test_entity_base.gd`
(que confirma que existen como nodos, no que su lógica funcione).
`ladder_motor` es el peor caso, cero cobertura ni siquiera estructural.
Combat, en cambio, está bien cubierto (`test_combat_broker.gd`, 13
funciones, tests conductuales de verdad). No escribí tests nuevos esta
madrugada — 8 motores es mucho para armar bien sin poder validar jugando
cada uno, y preferí no inflar el conteo con tests superficiales solo para
tener número verde. Si querés, la próxima sesión puedo arrancar por
`ladder_motor` (el más urgente) con vos mirando.

### E. 4 usos de `get_parent()` fuera de la raíz de composición (§3, letra literal violada, espíritu dudoso)

Por la letra de §3 ("nada de `get_parent()`/`$Hermano` fuera de la raíz de
composición"), estos 4 la violan:
- `combat_debug_reporter.gd:4` y `movement_broker_debug_reporter.gd:9`:
  ambos toman referencia a su broker dueño así — mismo idioma en los dos
  reporters, de solo lectura, parece deliberado más que descuido.
- `spawn_snap.gd:72`: `get_parent()` es el propósito mismo del nodo
  (reposicionar a su propio dueño) — coherente con su docstring.
- `damage_event.gd:35-36` (en `scripts/base/`, se supone contrato puro por
  §4): resuelve a quién aplicarle daño si el `target` no implementa
  `apply_damage` directo. Este es el que menos puedo evaluar sin ver el
  flujo de combate completo jugado — vale la pena que lo mires vos.

Ninguno es un bug funcional. O se documentan como excepción explícita en
`ARCHITECTURE.md` (si el idioma "reporter lee a su padre" es aceptado a
propósito), o se refactorizan con `NodePath` inyectado. Decisión de
arquitectura, no la tomé por vos.

### F. Nota aparte, no nueva: falta una escalera real en `main.tscn`

Ya estaba anotado en `docs/AHORA.md` como pendiente — lo confirmo de
nuevo: `ladder_motor.gd`/`ladder_service.gd`/`scripts/world/ladder.gd`
existen pero `main.tscn` (la única caja jugable de graybox) no tiene
ningún nodo `Ladder`. `LadderMotor` nunca se ejercita jugando de verdad.

## Todo lo demás, confirmado limpio (sin acción necesaria)

- **§7** (`Input.*` solo en `*Brain.gd`): limpio, sin excepciones.
- **§11** (sin ticks implícitos): limpio — todo `_process`/
  `_physics_process` activo está en la lista blanca (`MovementBroker`,
  `CameraRig`, `VisualsPivot`) o apagado correctamente en `_ready()`.
- **§12** (autoload aislado): `DebugOverlay` limpio, nadie le escribe
  estado directo fuera del patrón `push()`/`register_context()`.
- **§14** (violación ya conocida, `strike_action.gd` llamando
  `inject_forced_proposal()` directo): sigue ahí, sin agravarse — ningún
  otro lugar de `combat/` copió el patrón.
- **§18** (tipado estático): limpio en la muestra revisada.
- Asociación script↔nodo en las 5 escenas: sin mismatches — todo script
  referenciado existe, tipo de nodo coherente con lo que el script espera.
- `%NombreÚnico` vs `NodePath` (§19): usado correctamente en las 4 escenas
  revisadas — ningún `%Unique` cruza el límite de una escena instanciada.
- Sin scripts huérfanos reales (6 candidatos iniciales, los 6 resultaron
  falsos positivos — todos se usan vía `class_name`, no por nombre de
  archivo).
- Sin tests obsoletos apuntando a sistemas ya borrados (se verificó
  específicamente que no quedó ningún rastro roto de `GrassField`).
- Sin recursos `.tres` huérfanos fuera de lo ya auditado en la sesión de
  pasto.

## Segunda pasada: geometría y shader del pasto

No hecha con subagentes — inspección directa de los 6 `.blend` de pasto
(`grass_blade_single`, `_flat`, `_spike`, `_lod_set`, `_lod_set_straight_tip`,
`_tuft`) vía scripts de Blender headless, más relectura línea por línea de
los generadores y `grass_blade.gdshader`.

### Geometría: limpia, verificada, no solo asumida

Para cada uno de los 6 archivos, con `mesh.validate(verbose=True)` (0
issues encontrados/corregidos en los 6) y `poly.normal` por cara:

- **Conteo de vértices/caras correcto** en los 6: LOD0 crossed = 8v/4
  caras, LOD1 flat = 4v/2 caras, LOD2 spike = 3v/1 cara — sin vértices
  sueltos, sin geometría duplicada.
- **Shading plano correcto** (`use_smooth = False`) en las 42 caras
  revisadas — `shade_flat()` funcionó como se esperaba en los 6 archivos.
- **Normales**: dentro de cada grupo de caras conectado (cada plano
  individual), las dos caras que lo forman quedan con la **misma**
  normal — confirmado con números reales, no solo revisando el código
  (ej. LOD0: el plano en `angle_deg=0` da `(0,-1,0)` en sus 2 caras; el
  plano en `angle_deg=90` da `(1,0,0)` en las suyas — consistentes entre
  sí, girados 90° entre planos, como corresponde). **Matiz importante que
  el comentario original ("recalculates outward normals") no aclaraba**:
  para geometría plana sin volumen (un plano suelto no tiene "adentro"),
  el algoritmo de Blender (`normals_make_consistent(inside=False)`) sólo
  garantiza **consistencia dentro de cada grupo conectado**, no una
  dirección "hacia afuera" verdaderamente significativa — no importa hoy
  (el shader es `unshaded`, nunca lee `NORMAL`), pero si algún día se
  activa sombreado real, hay que verificar la dirección contra la luz de
  verdad, no asumir que quedó bien por herencia de este comentario.

### Bugs reales encontrados en `grass_blade.gdshader` — 2 comentarios
incorrectos, corregidos (0 cambios de comportamiento)

1. **Línea 12 (antes del fix): "Set by grass_field.gd..."** — referencia
   directa a un sistema borrado hace varias sesiones (`GrassField`).
   Corregido a `TerrainGrassInstancer._build_shader_material()`, que es
   quien realmente setea ese uniform hoy.

2. **Más importante — línea 34 (antes del fix): "Base on world position
   too so nearby blades stay coherent."** Esto es **falso**, no solo
   desactualizado: `VERTEX` dentro de `vertex()` en Godot es espacio
   **local** de cada instancia (Godot no lo transforma a mundo antes de
   correr el shader) — `VERTEX.x`/`VERTEX.z` son coordenadas dentro de
   **una sola brizna**, no la posición real de esa brizna en el mundo.
   El término `VERTEX.x * 1.5 + VERTEX.z * 1.3` que se suma a la fase del
   seno **no** logra coherencia entre briznas distintas — sólo agrega un
   desfase mínimo entre los vértices de la MISMA instancia (ej. entre los
   dos planos cruzados de LOD0). La desincronización real entre briznas
   distintas la hace `INSTANCE_CUSTOM.x` (fase aleatoria horneada en
   `_generate_instance_data()`), que sí funciona como está documentado en
   el encabezado del shader. Presente así desde el commit inicial del
   proyecto — no es una regresión de esta sesión, es un comentario
   impreciso de siempre. **No se tocó la matemática**, solo el comentario
   — cambiar el efecto real requeriría validarlo jugando (§17), no algo
   para las 3am sin supervisión.

### Resto revisado, sin hallazgos

- Los 3 generadores nuevos de esta sesión (`generate_grass_blade_spike.py`,
  `generate_grass_blade_lod_set.py`, `generate_grass_blade_lod_set_straight_tip.py`)
  reproducen exactamente el mismo orden de vértices/winding que los
  generadores originales (`generate_grass_blade_single.py`/`_flat.py`) —
  confirmado comparando los vértices reales exportados, no sólo leyendo el
  código fuente Python.
- `finish_object()` (`grass_blade_common.py`) asigna material vía
  `bpy.data.materials.new("M_Grass").node_tree.nodes` sin `use_nodes =
  True` explícito — funciona sin error en los 6 archivos (confirmado
  corriendo los 6 generadores), así que no es un bug real pese a parecer
  frágil a primera lectura. Nota cosmética, no arreglada: como
  `finish_object()` corre 3 veces por archivo en los sets combinados, Blender
  autorenombra el material a `M_Grass.001`/`.002` — sin efecto (Godot
  reemplaza todo con `material_override`), sólo prolijidad.
- `Terrain3DInstancer.add_transforms(mesh_id, transforms, colors:
  PackedColorArray, update: bool)` — firma confirmada por reflexión; el
  mapeo `Color(r,g,b,a)` → `INSTANCE_CUSTOM` en el shader (r=fase,
  g=multiplicador de altura, b=multiplicador de viento) coincide
  exactamente con cómo `_generate_instance_data()` arma cada `Color` y con
  el comentario de encabezado del shader — sin desajuste de canales.
- Caso límite `min_scale == max_scale` (el valor actual en la escena real,
  el usuario los dejó en 1.0/1.0 mientras probaba el viento): el guard
  `maxf(max_scale - min_scale, 0.001)` evita división por cero
  correctamente, da `height_frac = 0.0` de forma determinística. Sin bug.

## Verificación

97/97 tests (`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit`),
partida real headless (`godot --headless scenes/terrain_base.tscn`) sin
errores nuevos, después de cada cambio de esta lista (incluida esta
segunda pasada).
