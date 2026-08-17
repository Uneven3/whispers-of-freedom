# Plan: LOD geométrico de pasto sobre Terrain3D

Documento de diseño, escrito el 2026-08-15 para implementarse en una sesión
futura. Pasó por dos rondas de crítica con subagentes sin contexto previo de
la conversación (metodología `/iterate-safely`, aplicada dos veces seguidas
a pedido explícito). No se tocó código en la sesión donde se escribió esto
— es solo el plan.

## Objetivo

Diseñar un sistema de niveles de LOD para la brizula de pasto que ya
renderiza `scripts/world/grass_terrain_instancer.gd` vía
`Terrain3DInstancer`:

- **LOD0 (cerca)**: la malla actual, `art/blender/grass/grass_blade_single.blend`
  — 2 planos cruzados, 4 triángulos. Sin cambios.
- **LOD1 (media distancia)**: brizula sin cruzar, 2 triángulos.
- **LOD2 (lejos)**: 1 triángulo.
- **LOD3 (muy lejos)**: billboard mirando a cámara (cilíndrico, eje Y).

El número de niveles (4) es punto de partida a discutir, no decisión
cerrada. Dato para esa discusión: un proyecto hermano que recorrió este
mismo diseño terminó fusionando dos niveles con la misma forma en 3, no 4
(ver antecedente abajo) — no es una recomendación automática de bajar a 3
acá (su malla cercana era de 2 tris, la nuestra es de 4, la comparación no
es uno a uno), pero es evidencia real a sopesar, no una intuición.

## Antecedente directo: `docs/reference/breath-of-freedom/BOTWGrass.md`

Este documento (proyecto hermano, 1510 líneas, más `AUDIT_GRASS_2026-08-11.md`
y `GRASS_PERF_DATA.md` del mismo proyecto) recorrió este mismo diseño — hoja
/ púa de 1 triángulo / carta-billboard — antes que nosotros. Verificado
línea por línea contra el texto fuente en las dos rondas de crítica, no
parafraseado de memoria.

**Probado y falló, aplica directo a LOD1 y LOD2:** engordar la púa de 1
triángulo (sin billboard, con yaw al azar) no cambió nada jugado —
*"lo que ves depende del ángulo, no del número"*. Sin mirar a cámara,
cualquier geometría plana orientada al azar puede quedar de canto según el
ángulo, sin importar cuántos triángulos tenga. Esto extiende el riesgo ya
conocido de la variante plana archivada en este proyecto (`20169ca`, nunca
jugada en movimiento) a **ambos** LOD1 y LOD2 de este plan — los dos usan
orientación horneada aleatoria sin billboard, y no hay evidencia de que más
triángulos lo arregle. Hay que jugarlos y confirmarlo, no asumir que
"billboard en LOD3 ya cubrió el problema".

**Probado y NO resuelto, aplica directo a LOD3 — esta es la parte más
importante de todo el antecedente, y la que más fácil es leer mal:**
el billboard fue *"la queja que sobrevivió el día entero"*, varias sesiones
seguidas. Texturar la carta con una ilustración (en vez de color sólido)
+ alpha *mask* (cutoff 0,5, nunca *blend*) mejoró las cosas, pero **no
cerró el problema** — el propio documento lo vuelve a abrir después:
*"la carta cercana se leyó como una nueva textura de suelo y la línea
persistió"*, y el diagnóstico se afina a algo más profundo que apariencia:

> *"una púa es una brizna, pero una carta pretende representar varias...
> eso podía romper el círculo, nunca igualar masa, cobertura o silueta."*

Es decir: el problema de fondo no es visual (color, textura, ruido de
borde) — es que **una carta que cubre muchos píxeles con 2 triángulos está,
por diseño, representando más de una brizna**, mientras que una púa sigue
representando una sola. Esa es una diferencia de *cantidad representada*,
no de apariencia, y ninguna técnica de shader/textura la resuelve — hace
falta una arquitectura de "identidad de grupo" (varias púas + una carta
dueña) que el proyecto hermano **nunca llegó a implementar**: *"El
prototipo no se empieza todavía... faltan herramientas para juzgarlo"*.
`AUDIT_GRASS_2026-08-11.md` confirma independientemente que el checkpoint
jugado de la carta texturizada "no se cerró formalmente todavía".

**Consecuencia directa para este plan**: nuestra propuesta original —
"con un mesh card cubrís muchos píxeles con 2 triángulos" — es exactamente
la misma apuesta que el proyecto hermano hizo y no pudo cerrar del todo.
Este plan no puede prometer que LOD3 se resuelva con shader + textura; el
riesgo real, con nombre propio, es que haga falta la misma pregunta de
fondo que ellos dejaron abierta: ¿cuántas briznas representa cada carta, y
cómo se mantiene coherente esa cuenta con las briznas reales que reemplaza?
Se anota como riesgo de mayor orden en la sección de Riesgos, no se
resuelve acá.

**Salvedad importante: no está probado que el problema fuera el diseño, no
la ejecución.** `BOTWGrass.md` tiene su propia sección de autocrítica
("Errores que este documento ya cometió — no reintroducir", 20 ítems) que
documenta errores de ejecución concretos y ajenos al enfoque de LOD en sí,
varios de ellos graves:
- Un bug de indexado (`@builtin(vertex_index)` sin sumar `base_vertex` en
  un draw indexado) apagaba un nivel de LOD entero por corrida, de forma
  no determinista — y durante un tiempo se lo interpretó como "cambió el
  viento" o "el anillo no llega", no como un bug (ítems 16-18).
- Un modelo de densidad que parecía "mal en la forma" resultó tener un
  solo término mal calculado (huella de la brizula sobreestimada 2,83×) —
  el diagnóstico inicial (arquitectura equivocada) era falso; el síntoma
  era real, la causa no (ítems 9-10).
- Un rechazo previo de "carta de grupo" (la solución de identidad de
  grupo que después quedó pendiente) se apoyaba en una premisa nunca
  puesta a prueba (asumía alfa recortado); al probar una carta **opaca**
  específicamente, "ganó en los cuatro ejes" (ítem 6).
- Item 14, ya citado en la sección de metodología: optimizaron dos pasos
  seguidos contra una captura desde un mirador fijo que no mostraba las
  quejas reales (necesitaban cámara en movimiento y otra altura).

Ninguno de estos bugs es *el* que dejó el billboard sin cerrar — el
documento no lo dice así, y esto no reescribe la conclusión de arriba (la
pregunta de "cuántas briznas representa una carta" sigue sin resolver
ahí). Pero sí demuestra que ese proyecto tuvo, de forma documentada y
repetida, diagnósticos iniciales equivocados que después resultaron ser
errores de ejecución, no fallas del enfoque — así que tratar su resultado
no resuelto como prueba de que "una carta que cubre varias briznas es
inviable en general" sería ir más allá de lo que el propio documento
sostiene. Queda como riesgo real a vigilar, no como veredicto ya cerrado
contra la técnica.

**El "círculo" alrededor de la cámara es inherente a cualquier LOD por
distancia, no un bug a evitar.** Ni siquiera BOTW (según la referencia que
citan) lo evita — lo disimula (ruido, densidad decreciente, color
convergiendo al terreno). El criterio de éxito de este plan no es "sin
costura visible", es *disimulada lo suficiente*, medido jugando.

**Técnica de medición reutilizable:** el umbral entre niveles se define por
el **ancho en pantalla** de la brizula (ellos, ~1,5 px de referencia para
el salto hoja→carta), no por un valor de metros memorizado — varía con FOV
y resolución, hay que medirlo contra nuestra cámara real, no copiar su
número. Se adopta el mismo criterio acá (Decisión 7).

**Metodología reutilizable:** escena de laboratorio descartable (terreno
plano propio, sin campo real, solo las referencias de cada nivel lado a
lado) para juzgar la lectura visual de cada tier antes de tocar la
producción. Se adopta para la Fase 0/1 de este plan.

**Técnica ya resuelta y reusable si hace falta retomarla más adelante (no
en alcance de este plan):** `GRASS_PERF_DATA.md` documenta una técnica de
"ruido en el borde de tier" ya implementada (apagada por defecto, sin
validar jugando) — jitter determinista por celda, **restringido a ≤ 0**
(solo puede acercar el borde de LOD, nunca alejarlo, para no dejar nunca un
agujero de pasto), con un test que barre 900 celdas verificando esa
restricción. Si algún día hace falta atacar el "círculo" con ruido (Decisión
8), no hace falta reinventar el patrón — está documentado ahí.

**Lección barata sobre alpha y densidad, aplica si se llega a texturar
LOD3 (Decisión 3):** recortar una silueta con alpha no es solo un cambio de
apariencia, es un cambio de densidad — en el proyecto hermano, recortar el
42% del área con alpha bajó la cobertura real medida de 99,8% a 86,8% sin
que nada en el código lo declarara. Si este plan llega a texturar LOD3, hay
que medir cobertura real después del recorte alpha, no asumir que
`blade_count` sigue describiendo la densidad visible. Relacionado: la
textura de carta de BOTW nunca tuvo mipmaps (deuda explícita, riesgo de
shimmer) — barato de evitar acá generando mips al importar (default de
Godot), anotado como prevención, no como algo a investigar.

## Contexto verificado hoy contra el motor real

- `Terrain3DMeshAsset` expone `lod_count` (solo lectura), `last_lod`,
  `lod0_range`..`lod9_range` (10 niveles posibles), `fade_margin`,
  `last_shadow_lod`, `shadow_impostor`, y **una sola** propiedad
  `material_override` (no indexada por nivel de LOD, hint
  `BaseMaterial3D,ShaderMaterial`) — confirmado por reflexión
  (`ClassDB.class_get_property_list`) en ambas rondas de crítica. No se
  verificó si esa única propiedad de material aplica a todos los niveles
  de LOD por igual, o si cada submesh dentro del `scene_file` puede traer
  su propio material desde el `.blend`. Hueco real, no supuesto.
- `Terrain3DMeshAsset` también expone `generated_type` (hint exacto:
  `"None,Texture Card"`) — un modo de billboard/card **nativo** de
  Terrain3D, confirmado por reflexión en la segunda ronda (no inventado).
  La única entrada que lo usa hoy en `terrain_assets.tres` es "New Mesh"
  (el placeholder por defecto del plugin — el usuario confirmó que no lo
  creó él, así que no está configurado a propósito y no dice nada todavía
  sobre si auto-orienta a cámara). Pregunta de Fase 0: si genera una carta
  con orientación a cámara nativa, puede reemplazar directamente el plan
  de billboard-a-mano-en-shader.
- No se verificó qué convención de nombres/estructura espera Terrain3D
  dentro de un `scene_file` para reconocer varios niveles de LOD. El
  addon (`addons/terrain_3d/`) es GDExtension compilado — confirmado que
  no hay fuente C++ local (solo GDScript de UI del editor plugin en
  `src/`, los binarios reales están en `bin/`) — no se puede grepear, solo
  probar empíricamente.
- `Terrain3D.mesh_lods = 7` (valor por defecto). **Corrección de la
  segunda ronda de crítica**: la v2 de este plan afirmaba que ese campo
  falla al leerse en un `Terrain3D.new()` aislado — eso es falso,
  verificado directo (`Terrain3D.new().mesh_lods` da 7 sin error). Lo que
  sí devuelve `null` en un nodo aislado es `get_assets()`/`get_data()`/
  `get_instancer()` — esa es la razón real para probar contra la escena
  real (`terrain_base.tscn`) en vez de un nodo suelto, no `mesh_lods` en
  sí. 7 ≥ 4 así que no debería bloquear este plan; semántica exacta
  (¿tope global de niveles reservados?) no confirmada.
- `density` en `Terrain3DMeshAsset` es para el pincel del Asset Dock, no
  aplica a la colocación programática (`_generate_instance_data()`);
  `Terrain3DInstancer` no expone ningún método de densidad-por-distancia
  entre sus métodos reales (confirmado por reflexión).
- `BaseMaterial3D.billboard_mode` incluye la opción nativa "Y-Billboard"
  (cilíndrico) — confirma que el concepto existe de primera clase en
  Godot, pero **esa opción es propia de `BaseMaterial3D`, no del
  lenguaje de shader**. Nuestro caso usa un `ShaderMaterial` con shader
  propio. **Corrección de la segunda ronda**: `render_mode billboard` en
  un spatial shader de Godot hace billboard **esférico completo**
  (encara la cámara en todos los ejes, incluida elevación) — no existe un
  `render_mode` equivalente a "Y-Billboard" para shaders propios. Las
  rutas reales para LOD3 no son "tres alternativas intercambiables" como
  decía la v2, son: (a) reconstrucción manual de la matriz modelo-vista
  en `vertex()`, restringida al eje Y (la única que da cilíndrico tal
  como se pide en el objetivo), o (b) lo que haga internamente
  `generated_type` nativo, sin confirmar todavía qué eje usa. `render_mode
  billboard` sin más queda descartado salvo que se acepte esférico
  completo (no es lo que pide el objetivo).
- Nadie en el código llama `Terrain3D.set_camera()` fuera de
  `scripts/player_action_stack/spawn_snap.gd:92` (confirmado por grep en
  todo el repo en la segunda ronda) — ahí es un parche puntual
  condicionado, solo para colisión dinámica, no una llamada general
  garantizada en todo camino de juego. Si el LOD nativo de mallas
  (Ruta A) también depende de que la cámara esté registrada así, el swap
  de LOD podría no dispararse en una partida real aunque funcione en el
  editor — mismo patrón de bug que `spawn_snap.gd` ya tuvo que resolver
  para colisión. Verificar esta dependencia es parte explícita de Fase 0.
- `scripts/world/grass_terrain_instancer.gd:100-104` confirma que
  `_generate_instance_data()` se llama una sola vez desde `_build()`, y el
  resultado se pasa a `instancer.add_transforms(mesh_id, ..., true)` — el
  sistema hornea posiciones/rotaciones una vez, sin recálculo por frame
  contra la cámara. Sostiene la Decisión 2 (billboard resuelto en shader,
  no en el transform horneado) y es la razón concreta por la que la
  Ruta B de la Decisión 6 no puede depender de distancia-al-origen-del-
  campo.
- Assets ya generados en sesiones anteriores, conservados en el repo, no
  wireados a nada hoy: `art/blender/grass/grass_blade_flat.blend` +
  `tools/blender/generate_grass_blade_flat.py` (un plano sin cruzar, 2
  tris) y `grass_blade_tuft.blend` (variante de mata, no aplica acá).
- `tools/blender/grass_blade_common.py::leaf_verts()` construye 2
  triángulos por hoja: superior (`tip`, `waist_l`, `waist_r`) e inferior
  (`base`, `waist_r`, `waist_l`). `place_leaf()` desempaqueta los vértices
  en la línea 93 y llama `bm.faces.new()` **dos veces sin condición** en
  las líneas 94-95 — no sirve para generar 1 solo triángulo tal cual está.
  El generador de LOD2 tiene que llamar `leaf_verts()` directo y armar un
  único `bm.faces.new()` con el triángulo inferior (más ancho, más
  cobertura).
- El shader actual (`grass_blade.gdshader`) es `unshaded`, sin UVs, sin
  textura. El degradado base/punta (`v_height_fraction`) **no** viene de
  un canal de vertex color pintado en Blender — se calcula en `vertex()`
  a partir de `VERTEX.y` (posición geométrica local) y se interpola como
  `varying` estándar (corrección de la segunda ronda de crítica sobre la
  redacción de la v2, que decía "vertex color interpolado" de forma
  ambigua). Buena noticia práctica: cualquier malla nueva de LOD1/LOD2/
  LOD3 hereda el degradado automáticamente según su propio rango de
  `VERTEX.y`, sin necesidad de pintar nada en Blender. El viento llega vía
  `INSTANCE_CUSTOM`, poblado desde el `PackedColorArray colors` que le
  pasamos a `add_transforms` — ese sí es un canal de color, pero de
  instancia, no de vértice.

## Precondición pendiente de una nota previa del propio proyecto

`docs/AHORA.md`, sección "Próximo foco" (mismo día, ítem 3), ya dejó
anotado, antes de este plan: verificar en el editor real que tunear
`TerrainGrassInstancer` en vivo no ensucia `world_data/terrain/*.res` antes
de agregarle setters de rebuild-en-vivo. La Fase 3 de este plan (cablear
niveles de LOD y ajustar rangos/fade) va a implicar tuneo iterativo — esa
verificación es una precondición real, no mencionada en ninguna versión
anterior de este plan, y hay que resolverla antes o durante la Fase 0.

Ese mismo ítem menciona que `GeometryInstance3D.visibility_range_*` "superó
a" el enfoque de LOD nativo de `Terrain3DMeshAsset" — pero la razón
("ver abajo, por qué") **no existe en el archivo actual**: es una
referencia colgada, confirmado leyendo `AHORA.md` hasta el final. Antes de
descartar `visibility_range_*` como alternativa en Fase 0, vale la pena
reconstruir esa razón (hipótesis más probable: las instancias de un
`Terrain3DInstancer`/MultiMesh no exponen `visibility_range` por instancia
como sí lo haría un nodo de escena individual) en vez de asumir que ya
está zanjado solo porque quedó escrito una vez.

## Decisiones de diseño

1. **Orientación aleatoria horneada en LOD0-LOD2; billboard resuelto en
   shader (no horneado) en LOD3.** De cerca y media distancia la
   orientación aleatoria por instancia es deseable — variación natural, y
   el ángulo de cámara respecto a cada brizula cambia constantemente con
   el movimiento del jugador. A muy larga distancia ese ángulo deja de
   cambiar de forma perceptible, así que billboard es correcto ahí — y
   **solo** ahí. LOD1 y LOD2 heredan el riesgo de "canto invisible" sin
   resolver (ver antecedente) — hay que jugarlos y confirmarlo, no asumir
   que billboard en LOD3 ya cubrió el problema para los niveles previos.

2. **Billboard cilíndrico (eje Y) calculado en el vertex shader — vía
   matriz modelo-vista manual, o el modo nativo `generated_type` de
   Terrain3D si Fase 0 confirma que orienta igual — no en el transform
   horneado.** `add_transforms()` hornea una vez, sin recálculo por
   cámara; la rotación horneada deja de importar en el tramo donde el
   shader la reemplaza. `render_mode billboard` de shader queda
   descartado tal cual (da esférico, no cilíndrico) salvo que se acepte
   ese resultado en vez del pedido.

3. **Textura en LOD3: en alcance como plan de respaldo, pero sin promesa
   de que cierre el problema.** Color sólido sin textura es el primer
   intento (nuestro campo es mucho más chico que el del antecedente,
   nuestro shader ya tiene degradado propio, la malla es distinta). Si no
   alcanza en el checkpoint jugado de Fase 4, el siguiente paso conocido
   es texturar con alpha *mask* (cutoff fijo, nunca *blend*) — pero el
   antecedente muestra que texturar **mejoró sin cerrar** el problema en
   un diseño casi idéntico, porque la causa de fondo resultó ser una
   diferencia de *cuántas briznas representa cada carta*, no de
   apariencia (ver antecedente, sección larga arriba). Si llegamos a esa
   instancia y el problema persiste después de texturar, la conclusión
   correcta no es seguir iterando textura/ruido — es que probablemente
   haga falta la misma pregunta de fondo que el proyecto hermano dejó sin
   resolver, y eso ya no entra en el alcance de "LOD geométrico", es un
   problema de arquitectura de representación aparte. Si se llega a
   texturar: medir cobertura real después del recorte alpha (no asumir
   que `blade_count` sigue describiéndola) y generar mips al importar
   desde el principio.

4. **Densidad por distancia queda fuera de este plan.** Cambio distinto
   (densidad radial horneada en `_generate_instance_data()`), ortogonal
   al LOD geométrico.

5. **Pipeline de generación, con nombres por forma, no por número de
   nivel.** El antecedente muestra un caso concreto de por qué importa:
   dos niveles con la misma forma se fusionaron sin que el campo cambiara
   ("no cambia el campo, quita un borde") — un archivo llamado
   `_lod1.py` queda mal nombrado si el esquema cambia.
   - LOD1 (2 tris, sin cruzar): reusar `grass_blade_flat.blend` /
     `generate_grass_blade_flat.py`, ya generados y archivados. Fase 1 se
     reduce, en el caso feliz, a solo LOD2.
   - LOD2 (1 tri): nuevo, `generate_grass_blade_spike.py` (vocabulario
     alineado con el antecedente — "púa"), llamando `leaf_verts()`
     directo con un único `bm.faces.new()`, no `place_leaf()`.
   - LOD3 (billboard): geometría mínima, nombre a definir según la ruta
     de Fase 0 — si es el modo nativo de Terrain3D, puede no requerir un
     `.blend` nuevo en absoluto.

6. **Integración con `Terrain3DMeshAsset`: dos rutas.**
   - **Ruta A (preferida si Fase 0 la confirma viable)**: las mallas
     entran en un solo `scene_file`/`Terrain3DMeshAsset`, usando el
     mecanismo nativo de LOD (`last_lod`, `lodN_range`, `fade_margin`).
   - **Ruta B (respaldo, más cara de lo que parece a primera vista)**:
     cada nivel como su propio `Terrain3DMeshAsset`/`mesh_id`, con
     `grass_terrain_instancer.gd` decidiendo a mano qué id usar. Para que
     esto sea LOD real (no densidad estática disfrazada) la asignación
     tiene que seguir la posición de la **cámara**, no un punto fijo como
     el origen del campo — lo que implica reevaluar en tiempo real, no
     hornear una vez. Es trabajo bastante mayor al que parece. Si Fase 0
     descarta la Ruta A, la conclusión correcta puede ser resolver lo que
     la bloquea, no caer por defecto a la Ruta B tal como está descripta.

7. **Distancias de corte (`lodN_range`): no se fijan en este plan.**
   Fijar metros de memoria repetiría el error ya cometido una vez con el
   pasto (`20169ca`, medir con una escena aislada no representativa). Se
   adopta el criterio del antecedente: el umbral entre niveles se define
   por el ancho en pantalla de la brizula, medido contra la cámara y
   resolución reales del juego — no un número copiado de otro proyecto.
   Antes de comprometer distancias hace falta una herramienta de medición
   (heredera conceptual de la ya borrada `grass_density_probe.gd`).

8. **El corte por distancia se acepta como artefacto inherente, no como
   bug a eliminar.** Ni siquiera BOTW lo evita, lo disimula. Criterio de
   éxito de Fase 4: disimulado lo suficiente jugando, no invisible. Si no
   alcanza con las técnicas de este plan, la próxima capa conocida y ya
   resuelta en el proyecto hermano (no en alcance acá, pero reusable sin
   reinvestigar) es el jitter unidireccional por celda de
   `GRASS_PERF_DATA.md` — Técnica 2, restringido a ≤ 0 para no dejar
   nunca un agujero de pasto.

## Fases propuestas para la implementación

- **Fase 0 — spikes de investigación, sin comprometer el diseño final:**
  a) **RESUELTO** (2026-08-16, ver "Actualización" arriba) — confirmar si un
     `scene_file` puede traer varios niveles de LOD y con qué convención los
     reconoce Terrain3D;
  b) **ACOTADO, no cerrado** (2026-08-16) — investigar `generated_type =
     "Texture Card"` — si auto-orienta a cámara y en qué eje, puede
     reemplazar el billboard a mano;
  c) si (b) no alcanza, implementar el billboard cilíndrico a mano en
     `vertex()` (no `render_mode billboard`, da esférico);
  d) **RESUELTO por código fuente, 2026-08-16** (ver "Actualización 2026-08-16
     (cuarta sesión)" más abajo) — confirmar si `fade_margin`/el LOD nativo
     produce cross-fade real o es un corte duro (jugarlo, no asumir por el
     nombre) — **matiz importante**: resuelto leyendo el código fuente real
     de Terrain3D, no jugándolo con la cámara en movimiento; la
     confirmación visual que este ítem pedía originalmente sigue pendiente;
  e) confirmar que el LOD nativo de mallas cambia en una partida jugada
     real (F5), no solo en el editor — depende de `Terrain3D.set_camera()`
     registrado, hoy solo llamado desde `spawn_snap.gd` con otro
     propósito;
  f) verificar que tunear rangos/fade en vivo no ensucia
     `world_data/terrain/*.res` (precondición ya anotada en
     `docs/AHORA.md`, nunca verificada);
  g) **RESUELTO** (2026-08-16) — reconstruir por qué
     `GeometryInstance3D.visibility_range_*` se descartó frente al LOD
     nativo de `Terrain3DMeshAsset` — la razón quedó anotada como pendiente
     en `docs/AHORA.md` sin explicarse.
- **Fase 1 — geometría, en una escena de laboratorio descartable** (no
  directo sobre `terrain_base.tscn`): **LOD2 generado** (2026-08-16,
  `generate_grass_blade_spike.py`); **LOD1 confirmado** sin trabajo
  adicional — `grass_blade_flat.blend` ya sirve tal cual.
- **Fase 2 — shader:** extender `grass_blade.gdshader` con el
  comportamiento de billboard para LOD3, según lo que confirme Fase 0b/0c.
  Expectativa calibrada por el antecedente: probablemente el paso de
  mayor riesgo del plan, no un paso mecánico — puede no bastar con color
  sólido, y texturar tampoco garantiza cerrarlo del todo (ver Decisión 3).
- **Fase 3 — integración:** cablear las mallas según la ruta (A o B)
  decidida en Fase 0, configurar rangos de distancia y fade. **PARCIAL,
  2026-08-16** — Ruta A (un solo `scene_file` con los 3 niveles reales,
  LOD0-LOD2) cableada y probada; LOD3/billboard queda para Fase 2. Ver
  "Actualización 2026-08-16 (tercera sesión)" más abajo.
- **Fase 4 — medir y jugar (§17):** herramienta de ancho-en-pantalla/
  cobertura + jugar de verdad con la cámara moviéndose. Criterio de
  éxito visual: disimulado lo suficiente, no invisible. **Agregado
  2026-08-16, pedido explícito del usuario:** también registrar una tabla
  real de costo (`blade_count` → `Primitives in Frame` del Debugger →
  Monitors → FPS) ANTES de comprometer Fase 3, como línea de base para
  comparar el costo de agregar LOD1-3 después — ver sección "Medir
  rendimiento" más abajo para la técnica (toggle de `GrassInstancer.visible`
  + comparar monitores).

## Actualización 2026-08-16: tunabilidad en editor + avance de Fase 0/Fase 1

Sesión posterior, pasada también por `/iterate-safely` (plan propio +
crítica de un subagente sin contexto previo + triage). Se implementó código
por primera vez (hasta acá el documento era solo diseño).

**Requisito nuevo, agregado por el usuario, no contemplado en el diseño
original:** todos los parámetros de ajuste fino deben ser editables en vivo
desde el Inspector de Godot, sin reiniciar la escena. `grass_terrain_instancer.gd`
ya lo cumple para sus 14 `@export` actuales (patrón setter +
`_queue_rebuild()` + `_ready_done`, igual al que ya tenía `GrassField`,
commit `530a4a0`). Precedente para cuando la Fase 3 agregue exports de
rangos de LOD (`lod1_range`, `lod2_range`, etc.): deben nacer con el mismo
patrón, no como exports estáticos.

**Bug real encontrado y corregido al implementar esto, más serio que el ya
conocido (duplicados en `terrain_assets.tres`):** `Terrain3DAssets.set_mesh_asset(id, mesh_asset)`,
llamado una segunda vez para sobrescribir un id ya existente, **no preserva
ese id de forma confiable** — confirmado con scripts de sondeo headless
descartables: reasignaba silenciosamente el nuevo objeto al id 0,
colisionando con una entrada no relacionada y corrompiendo `terrain_assets.tres`.
No se manifestaba antes porque el código original solo construía una vez
por proceso (`_ready()`); la tunabilidad en vivo lo expone al llamar
`rebuild()` repetidas veces en el mismo proceso. **Fix:** llamar
`mesh_asset.set_id(existing_id)` sobre el objeto nuevo, todavía sin
registrar, antes de pasarlo a `set_mesh_asset()` — verificado estable en 4
sobrescrituras seguidas (mismo id, sin corromper otras entradas). Relacionado
pero distinto: mutar `scene_file`/`material_override` directamente sobre una
entrada YA registrada (en vez de reconstruir el objeto y volver a
registrarlo) dispara la regeneración de miniatura del Asset Dock de
Terrain3D, que necesita un viewport real — inofensivo bajo un renderer real,
pero genera ruido de errores bajo el renderer dummy headless (confirmado con
una corrida real, `godot --headless scenes/terrain_base.tscn`, limpia). El
diseño final evita esto por completo: siempre construye un objeto nuevo con
las propiedades ya puestas antes de registrarlo, nunca muta una entrada ya
registrada. Relevante para quien toque este patrón en Fase 3.

**Fase 0a (¿un `scene_file` puede traer varios niveles de LOD?) — RESUELTO
empíricamente, no solo por `strings`.** Un `.blend` de prueba descartable
con dos objetos-malla nombrados `Probe_LOD0`/`Probe_LOD1`, cargado en
`Terrain3DMeshAsset.set_scene_file()`, produjo `get_lod_count() == 2` y
`get_last_lod() == 1` — Terrain3D reconoce automáticamente los niveles por
el sufijo `LOD#` en el nombre del objeto. Consistente con las cadenas del
binario (`addons/terrain_3d/bin/*.so`): *"meshes as LOD0-LOD3"*, *"meshes
using LOD# naming convention"*, *"No LOD# meshes found, assuming the root
mesh is LOD0"*.

**Fase 0b (¿"Texture Card" nativo auto-orienta a cámara?) — acotado, no
cerrado del todo.** Reflexión sobre `Terrain3DMeshAsset` con
`generated_type = Texture Card` solo expone `generated_faces` (int, default
2) y `generated_size` (Vector2, default 1×1) — ninguna propiedad de
eje/orientación en la clase. Sugiere que es una carta de tamaño fijo con la
misma orientación horneada estática que cualquier otro mesh, no un
billboard real. Baja la prioridad de esta ruta como reemplazo del billboard
manual en shader (Decisión 2), pero no se verificó jugado — sigue siendo un
hueco real, solo menos urgente.

**Fase 0g (¿por qué se descartó `visibility_range_*`?) — RESUELTO.**
Reflexión sobre `Terrain3DInstancer`: cero métodos con "visib", "range" o
"camera" en el nombre. Confirma la hipótesis que ya estaba anotada como "más
probable": las instancias de un `Terrain3DInstancer` (MultiMesh) no exponen
control de `visibility_range` por instancia.

**Fase 1 — geometría, avanzada:** `tools/blender/generate_grass_blade_spike.py`
genera LOD2 (1 triángulo, el inferior de `leaf_verts()` — más ancho, más
cobertura), guardado en `art/blender/grass/grass_blade_spike.blend`.
Verificado con reflexión Blender headless: 3 vértices, 1 cara, sin geometría
suelta (`bbox max Z == WAIST_HEIGHT == 0.30`, no `TIP_HEIGHT == 1.0`).
LOD1 confirmado sin trabajo adicional: `grass_blade_flat.blend` ya es
"brizna sin cruzar, 2 triángulos" tal como pedía la Decisión 5.

**Fuera de alcance todavía:** wirear LOD1/LOD2/LOD3 dentro de un
`Terrain3DMeshAsset` real de `terrain_base.tscn` (Fase 3), geometría de
LOD3, y las Fase 0e/0f (dependen de jugar/tunear en el editor real — ver
nota abajo).

**Verificación pendiente del usuario, no resoluble sin GUI/juego real:**
- Fase 0f: abrir `terrain_base.tscn` en el editor real, tunear varios
  sliders de `GrassInstancer` seguidos, y confirmar con `git status`/`git
  diff --stat` que `world_data/terrain/*.res` no genera diffs inesperados
  mientras se tunea (fuera de guardar a propósito).
- Fase 0e: jugar la escena real (F5) una vez exista más de un nivel de LOD
  cableado (Fase 3), y confirmar que el LOD nativo cambia con la distancia
  real de la cámara del jugador, no solo en el editor.

## Riesgos explícitos

- `material_override` podría no soportar diferenciarse por nivel de LOD
  dentro de un mismo asset — condiciona si Ruta A alcanza tal cual o hace
  falta `generated_type` nativo o la Ruta B revisada.
- El "canto invisible" de LOD1 **y LOD2** tiene evidencia directa en
  contra de resolverse sin billboard (antecedente: la púa engordada no
  cambió nada jugado). Alto riesgo, no especulativo.
- **El riesgo de mayor orden de todo el plan**: LOD3 puede no cerrarse
  con shader + textura, porque la causa de fondo documentada en el
  antecedente no es visual — es que una carta representa más de una
  brizula y ninguna técnica de apariencia iguala esa diferencia de
  cantidad. Si esto ocurre acá también, la solución real queda fuera del
  alcance de "LOD geométrico" tal como está planteado en este documento.
  Salvedad: el proyecto hermano documentó por separado varios errores de
  ejecución reales (un bug de indexado no determinista que apagaba un
  nivel de LOD entero, un modelo de densidad mal diagnosticado por un
  término mal calculado, un rechazo de "carta de grupo" basado en una
  premisa nunca probada) — no hay evidencia de que ese sea *el* motivo
  del billboard sin cerrar, pero tampoco se puede descartar que la
  ejecución, no el enfoque, haya sido parte del problema allá. No tratar
  su resultado como veredicto cerrado contra la técnica.
- `Terrain3D.set_camera()` no está garantizado registrado en todo camino
  de juego real — el LOD nativo podría no dispararse fuera del editor sin
  que se note en pruebas headless. Verificar en Fase 0e.
- Tunear rangos/fade en vivo podría ensuciar `world_data/terrain/*.res`
  — precondición sin verificar, heredada de una nota previa del proyecto
  (`docs/AHORA.md`). Verificar en Fase 0f antes de iterar en Fase 3.
- Ruta B, si hace falta, es más cara de lo que parece — no es un
  fallback simétrico a la Ruta A, requiere lógica de reevaluación en
  tiempo real que hoy no existe en el proyecto.
- El costo de vertex shader del billboard-condicionado-por-distancia (o
  del `generated_type` nativo), multiplicado por la escala real objetivo
  (~2-3 millones de triángulos, según la experiencia del proyecto
  hermano), no está evaluado — Fase 0 tiene que medirlo.
- Sombra por nivel de LOD (`last_shadow_lod`/`shadow_impostor`) no se
  contempla en este plan — deliberadamente diferido.
- **No hay todavía ninguna herramienta ni número de referencia para medir
  qué le cuesta el pasto al frame** (ni triángulos, ni draw calls, ni FPS
  con/sin pasto) — ver sección "Medir rendimiento" abajo. Bloquea poder
  comparar objetivamente el costo de LOD0 solo vs. LOD0-3 mezclados una vez
  que Fase 3 los cablee.

## Actualización 2026-08-16 (segunda sesión): bug de acumulación en el
borde + vocabulario de la distribución + medir rendimiento

Encontrado jugando (`terrain_base.tscn`, editor real, primera vez que se
juega este sistema en el editor en vez de solo headless): screenshot del
usuario mostró un anillo visiblemente más denso justo en el borde del
campo circular de pasto.

**Bug real, no relacionado a LOD, en `_generate_instance_data()`:** la
línea `(center + offset).limit_length(field_radius)` no descarta los puntos
que caen fuera de `field_radius` — los **proyecta** sobre el borde exacto
del círculo, a la misma distancia para todos. Cualquier combinación de
mata+desvío que hubiera caído más allá del radio termina apilada exactamente
a `field_radius` metros del centro, produciendo el anillo visible. **Fix:**
descartar esos puntos (mismo criterio que ya se usaba para puntos fuera del
terreno esculpido — es un presupuesto de intentos, no una garantía de que
los `blade_count` briznas aparezcan todas) en vez de proyectarlos. Test de
regresión agregado (`test_positions_do_not_pile_up_at_the_field_radius_boundary`)
con un caso que antes generaba acumulación fuerte (`field_radius=5.0`,
`clump_spread` por defecto de `8.0`, más ancho que el campo).

**Vocabulario, no era obvio del código ni del documento:**
- `clump_count`: cuántos **centros de mata** (patches) hay, distribuidos
  uniformemente en área dentro de `field_radius`.
- `blade_count`: cuántas **briznas individuales** en total, cada una
  asignada a una mata al azar y desplazada alrededor de ese centro con
  caída gaussiana (`clump_spread` controla qué tan lejos se dispersan de
  su mata).
- La densidad global es `blade_count` sobre el área de `field_radius`;
  `clump_count`/`clump_spread` no cambian la densidad total, cambian el
  **patrón** — pocas matas grandes y separadas (clump_count bajo,
  clump_spread alto) se ve distinto a muchas matas chicas y apretadas
  (clump_count alto, clump_spread bajo), con el mismo `blade_count`.

## Medir rendimiento (agregado al plan, no implementado todavía)

Preguntado por el usuario ("cómo mido qué gasta más recursos") — no había
respuesta en el documento. Dos niveles:

**Ya disponible hoy, sin escribir código:** el panel *Debugger → Monitors*
del editor de Godot tiene una sección "3D" con `Primitives in Frame`
(triángulos reales enviados a la GPU ese frame), `Draw Calls in Frame`, y
`Objects in Frame`. Técnica más directa para aislar qué cuesta el pasto
específicamente: activar/desactivar `GrassInstancer.visible` en tiempo real
(el nodo ya es `@tool` y responde a cambios en vivo) y comparar FPS +
`Primitives in Frame` con pasto encendido vs. apagado — la diferencia es el
costo real del pasto, sin adivinar. `blade_count` × 4 triángulos (LOD0
actual, dos planos cruzados) da el número teórico esperado, para contrastar
contra lo que reporta el monitor. **Corrección, 2026-08-16**: esta técnica
estuvo rota hasta esta misma sesión — destildar `Visible` no ocultaba nada
(ver "Actualización 2026-08-16 (sexta sesión)" más abajo). Ya arreglado,
la técnica descripta acá ahora sí funciona tal como está escrita.

**Sospechosos concretos a revisar cuando se mida, no solo intuición:**
- `grass_blade.gdshader` tiene `cull_disabled` — cada quad sin sombrear
  rasteriza sus dos caras, el doble de *fill rate* del que un blade con
  culling normal tendría. Deliberado (para que no se vea "de canto"
  invisible desde ciertos ángulos — ver antecedente en la sección de LOD),
  pero es un costo real, no gratis.
- El *sway* del viento se recalcula en el `vertex()` para **cada vértice de
  cada instancia, cada frame** — a diferencia de la generación de
  posiciones (una sola vez, horneada), este es un costo por-frame que
  escala directo con `blade_count` × vértices por brizna.
- El riesgo ya anotado arriba en "Riesgos explícitos": el proyecto hermano
  trabajó a escala de ~2-3 millones de triángulos — no hay medición todavía
  de a qué `blade_count` este proyecto llega a un costo comparable.

**No implementado, agregado como tarea real de Fase 4** (la fase de
"medir y jugar" ya existía en el plan, pero no mencionaba costo/recursos,
solo lectura visual del LOD): antes de comprometer cualquier decisión de
Fase 3, registrar una tabla real (no estimada) de `blade_count` →
`Primitives in Frame` → FPS, con la cámara en un punto y ángulo fijos
reproducibles, para tener una línea de base contra la cual comparar el
costo de agregar LOD1-3 más adelante.

## Actualización 2026-08-16 (tercera sesión): Fase 3 parcial — LOD0-LOD2
cableados de verdad, sin billboard todavía

Pasada por `/iterate-safely` (plan propio + crítica de un subagente sin
contexto previo + triage) igual que las sesiones anteriores. Primera vez
que se prueban varios niveles de LOD reales en `terrain_base.tscn`, no solo
en un `.blend` de prueba descartable.

**Hallazgos nuevos, verificados contra el motor real antes de tocar
producción:**

- **Estructura real de un `scene_file` multi-LOD**: cada nivel es un
  `MeshInstance3D` **separado** dentro de la escena fuente (no un surface
  extra de un mismo `Mesh`) — confirmado instanciando la escena importada
  de un `.blend` de prueba. `Terrain3DMeshAsset.get_mesh(lod: int = 0) ->
  Mesh` expone el `ArrayMesh` horneado de cada nivel por separado.
- **La pregunta que había quedado "acotada pero no cerrada" sobre
  `material_override` — CERRADA esta sesión, sin necesitar un render
  real.** El subagente de crítica trajo el código fuente público de
  Terrain3D en la tag exacta que fija `docs/AHORA.md` (`v1.0.2-stable`):
  `Terrain3DInstancer` arma un `MultiMeshInstance3D` por cada nivel de LOD
  y llama `mmi->set_material_override(ma->get_material_override())` **en
  cada iteración del loop**, no solo para LOD0. Confirma que la única
  propiedad `material_override` del asset se aplica a los 3 niveles por
  igual — no hace falta un material por nivel. (Confianza alta pero de
  segunda mano — código fuente real de la versión pinneada, no
  decompilado ni adivinado; si hace falta blindarlo más, alcanza con
  clonar esa tag exacta y grepear directo.)
- **Bug real encontrado y arreglado, en el mismo lugar que ya había dado
  problemas antes**: `_register_mesh_asset()` (ex-`_register_mesh_asset`
  de la sesión anterior) llamaba `mesh_asset.set_last_lod(0)` sin
  condición. Con un asset de un solo nivel esto era invisible (0 ya era lo
  correcto, por accidente) — pero con un asset de 3 niveles reales,
  hardcodear `last_lod=0` le diría a Terrain3D que ignore LOD1 y LOD2
  aunque existan en la malla. **Fix**: `mesh_asset.set_last_lod(mini(mesh_asset.get_lod_count() - 1, 9))`
  — se deriva del `lod_count` real de la malla cargada, con un clamp
  defensivo al techo de 10 niveles de Terrain3D (`lod0_range`..`lod9_range`).
  Test de regresión agregado, contra ambos casos (malla de 1 nivel y la
  nueva de 3).

**Trabajo hecho:**

1. `tools/blender/generate_grass_blade_lod_set.py` — combina las 3 mallas
   YA GENERADAS en sesiones anteriores (no rediseña ninguna forma) en un
   solo `.blend`, con los objetos nombrados `GrassBladeLOD0`/`LOD1`/`LOD2`
   por la convención confirmada en Fase 0a. Verificado por reflexión
   Blender headless: 8/4/3 vértices y 4/2/1 polígonos respectivamente,
   igual que los generadores individuales — sin geometría suelta ni
   contaminación cruzada entre niveles (cuidado explícito: deseleccionar
   antes de cada `finish_object()`, porque Blender 2.8+ edita
   multi-objeto si hay más de uno seleccionado al entrar a Edit Mode).
2. `grass_terrain_instancer.gd`: `blade_asset_path` por defecto ahora
   apunta a `grass_blade_lod_set.blend` (ninguna otra escena del repo
   tenía un override de este export, confirmado por grep — el cambio de
   default es seguro). Agregados 4 exports nuevos, tunables en vivo con el
   mismo patrón que los 14 anteriores: `lod0_range` (32.0), `lod1_range`
   (64.0), `lod2_range` (96.0), `fade_margin` (0.0) — valores por defecto
   reales de Terrain3D, punto de arranque para tunear, no una decisión
   final (Decisión 7: los umbrales reales se miden con la herramienta de
   ancho-en-pantalla de Fase 4, todavía no existe).
3. Reimport headless (`godot --headless --editor --import`) corrido tras
   generar el `.blend` nuevo — paso que el plan original había olvidado
   mencionar (un `.blend` recién escrito no es cargable por `load()` hasta
   que el editor lo importa una vez) y que la crítica marcó como
   bloqueante. Sin diffs colaterales inesperados, mismo patrón ya
   documentado.

**Importante, no resuelto todavía — por qué el archivo en disco no cambió
solo:** correr `godot --headless --editor --import` reimporta *assets*
pendientes (como el `.blend` nuevo), pero **no** instancia
`terrain_base.tscn` ni corre el `_ready()`/`rebuild()` del `GrassInstancer`
real, así que no persiste nada nuevo en `world_data/terrain/terrain_assets.tres`.
Confirmado leyendo el archivo después del reimport: seguía con la
referencia vieja a `grass_blade_single.blend`, `last_lod=0`. El código
está verificado correcto por otras vías (tests headless + una sonda
directa que confirma `lod_count=3`/`last_lod=2` al registrar el asset
nuevo, más una corrida real `godot --headless scenes/terrain_base.tscn`
sin errores) — pero el archivo en disco recién se actualiza la próxima vez
que se abra `terrain_base.tscn` en el editor interactivo real, que es
además el momento para hacer las dos verificaciones visuales pendientes:

## Verificación pendiente del usuario (Fase 3 parcial)

Al abrir `terrain_base.tscn` en el editor real:
- **Confirmar que el pasto cambia de forma con la distancia** — de cerca,
  brizna cruzada (LOD0); a media distancia, brizna plana (LOD1); lejos, la
  púa de 1 triángulo (LOD2). Si no cambia, revisar que
  `Terrain3D.set_camera()` esté registrado (Fase 0e, todavía sin cerrar).
  **CONFIRMADO, 2026-08-16** — el usuario jugó y reportó el pasto
  cambiando de nivel (aunque con corte brusco — ver siguiente sección);
  Fase 0e queda de hecho confirmada de paso, el LOD nativo sí cambia en
  una partida real, no solo en el editor.
- **Confirmar que el shader de viento/degradado se ve en los 3 niveles**,
  no solo en LOD0 — la sección de arriba lo da por confirmado por código
  fuente, pero vale la pena el chequeo visual barato antes de construir
  más encima. El usuario no reportó ningún nivel con apariencia distinta
  (verde plano sin degradado ni viento) — evidencia a favor, no una
  confirmación explícita pedida y respondida punto por punto.
- Aprovechar la misma sesión para hacer, por fin, la verificación de Fase
  0f que sigue pendiente (tunear sliders, mirar `git diff --stat
  world_data/terrain/`). **Sigue pendiente** — el usuario tuneó
  `blade_count`/`field_radius`/`clump_count` y quedaron guardados
  correctamente en la escena (confirmado por diff), pero nadie miró
  todavía si CADA arrastre de slider individual generó una escritura a
  disco separada, solo que el resultado final es correcto.

## Actualización 2026-08-16 (cuarta sesión): 3 problemas reales del primer
playtest — cross-fade de LOD, antialiasing, warning de shadowing

El usuario jugó por primera vez con el sistema de LOD cableado (sesión
anterior) y reportó 3 problemas concretos, más una captura del monitor de
rendimiento. Pasado por `/iterate-safely` igual que las sesiones previas.

**1. Warning de GDScript arreglado**: `grass_terrain_instancer.gd:300`, la
variable local `scale` (dentro de `_generate_instance_data()`) shadowaba
la propiedad `scale` de `Node3D`. Renombrada a `blade_scale` en sus 3 usos
— función pura, sin ningún uso de `self.scale`, cambio mecánico sin riesgo.

**2. Fase 0d cerrada por código fuente real, no por juego** (matiz
importante, anotado arriba en la lista de Fase 0): el usuario reportó "el
cambio brusco entre un LOD y otro, se nota mucho". Trajimos el código
fuente público de Terrain3D en la tag exacta (`v1.0.2-stable`,
`docs/AHORA.md`), función `Terrain3DInstancer::_setup_mmi_lod_ranges()`:
con `fade_margin > 0` aplica `set_visibility_range_fade_mode(FADE_SELF)`
(dithering nativo de Godot); con `fade_margin == 0` (nuestro default hasta
ahora) no configura ningún modo de fade — corte duro. La crítica de
`/iterate-safely` confirmó independientemente, con su propio fetch al
mismo código fuente, que no hay ningún multiplicador de `lod_overlap`
oculto en la rama de margin>0 (ese factor solo existe en la rama de corte
duro), así que el cálculo de que un margin de 8m no se solapa con el hueco
de 32m entre niveles es correcto. **Fix**: default de `fade_margin` subido
de `0.0` a `8.0`. Sigue tuneable en vivo. **Lo que sigue sin confirmarse
visualmente** (la propia Fase 0d pedía jugarlo, no solo leer el nombre):
que el dithering de `FADE_SELF` efectivamente se vea bien contra nuestro
`ShaderMaterial` `unshaded` custom — no hay razón técnica para que no
funcione (es un mecanismo inyectado por el renderer, no depende del
shader), pero es una confirmación visual barata pendiente para la próxima
sesión de juego.

**3. Antialiasing activado — decisión delegada explícitamente por el
usuario ("no sé cuál es más barato, decidí vos")**: `project.godot` no
tenía ninguna configuración de AA. Diagnóstico: el síntoma reportado ("veo
una V al caminar") es shimmer *temporal* de geometría fina en movimiento
— exactamente el pasto (mallas de 1-4 triángulos, sin sombrear,
`cull_disabled`, animadas por vértice cada frame). Se comparó:
- FXAA: más barato, pero es post-proceso sobre un solo frame — no ataca
  parpadeo temporal entre frames, que es el síntoma real.
- TAA: bueno contra shimmer temporal en general, pero acumula muestras
  entre frames y genera *ghosting* conocido en geometría que se anima
  rápido — exactamente lo que hace el pasto con el viento. Hubiera
  cambiado un artefacto visual por otro.
- MSAA: multi-muestrea cobertura de geometría opaca sin recalcular
  shading completo por muestra — ataca directamente bordes de triángulos
  finos, sin acumulación entre frames (sin riesgo de ghosting en
  geometría animada). El shader del pasto es 100% opaco, sin alpha ni
  discard — caso ideal para MSAA, confirmado por la crítica sin ningún
  caveat documentado de conflicto con `unshaded`/`cull_disabled`.

**Decisión: `rendering/anti_aliasing/quality/msaa_3d = 1` (2x)** — el nivel
más barato dentro de las opciones que realmente atacan el síntoma
reportado, con margen para subir a 4x si no alcanza (la GPU real de la
máquina de desarrollo, según el log de arranque de Godot, es una AMD
Radeon RX de gama media de 2016, RADV POLARIS11 — no la más reciente).
Nota de la crítica, no aplicada todavía: Godot permite combinar MSAA +
FXAA sin costo relevante; no se agregó en este pase por no ser necesario
para el síntoma específico del pasto, pero queda como opción barata si
aparece aliasing de otro tipo (texturas, specular) en otro material del
juego más adelante.

96/96 tests, partida real headless sin errores/warnings nuevos, y
verificación directa (`godot --headless --check-only`) de que el warning
de shadowing ya no aparece.

## Actualización 2026-08-16 (quinta sesión): la V no era antialiasing,
rangos de LOD con cálculo real, y rendimiento a 120k briznas

Segundo playtest, con MSAA 2x ya activado. Resultado: la V **no
desapareció** — señal fuerte de que el diagnóstico anterior estaba mal.

**Diagnóstico corregido**: `tools/blender/generate_grass_blade_single.py`
(y la copia de LOD0 dentro de `grass_blade_lod_set.blend`) usan
`tip_bend=0.05` en las dos hojas cruzadas de LOD0 — la punta se abre en V
**a propósito**, decisión tomada en la sesión de diseño original de la
brizna (`docs/AHORA.md`, "Pasto: historia resumida") para "no converger en
un pico rígido". Esa decisión se validó comparando capturas estáticas,
nunca caminando de verdad — coincide exactamente con la lección que el
propio `docs/AHORA.md` ya tenía anotada: *"un screenshot estático puede
mentir sobre geometría real (varios diseños de la mata solo se vieron mal
desde ángulos adicionales)"*. MSAA no lo iba a arreglar porque no es
aliasing, es la forma real de la malla.

**No resuelto todavía, a propósito**: en vez de revertir la decisión
unilateralmente, se generó `art/blender/grass/grass_blade_lod_set_straight_tip.blend`
(`tools/blender/generate_grass_blade_lod_set_straight_tip.py`) — mismo set
de 3 niveles, LOD0 con `tip_bend=0.0` (punta a un solo punto) en vez de
`0.05`. Comparación visual de los renders de preview confirma la
diferencia claramente (dos picos separados vs. uno solo). Queda como
asset alternativo, no como reemplazo — comparar en vivo cambiando
`blade_asset_path` en el Inspector (ya tunable en vivo) antes de decidir,
en vez de asumir desde un render aislado que "sin V" es automáticamente
mejor.

**Cálculo matemático para los rangos de LOD** (pedido explícito del
usuario: "no sé si hay un cálculo... para lo más óptimo"): nuevo
`tools/grass_lod_range_calculator.py`, sin dependencias de Blender/Godot.
Deriva distancia de cambio de nivel a partir del ancho real de la brizna
(`HALF_WIDTH*2 = 0.08m`) y el FOV real de la cámara del juego
(`camera_rig.gd`: 75° en modo seguimiento, 56° apuntando), resolviendo a
qué distancia una brizna de ese ancho ocupa un umbral dado de píxeles de
alto de pantalla. Con FOV de seguimiento y 1080px de alto: umbral de 3px
→ 18.8m, umbral de 1.5px (la referencia que ya tenía anotado el
antecedente del proyecto hermano) → 37.5m. El usuario había probado a mano
"de 20 en 20" jugando, sin saber si tenía sentido — coincide de cerca con
el cálculo (18.8m ≈ 20m). **Nuevos defaults**: `lod0_range` 32→**20**,
`lod1_range` 64→**40**, `lod2_range` 96→**60** (este último sin base en
píxeles — no hay un nivel más barato después hasta el billboard de LOD3,
que no existe todavía; se mantuvo el mismo espaciado de 20m que los
anteriores dos). `fade_margin` bajado de 8.0 a **5.0** en consecuencia
(con escalones de 20m en vez de 32m, un margen de 8 dejaba muy poco aire
limpio entre zonas de fade consecutivas). Sigue siendo el punto de
partida, no la palabra final — la validación real sigue siendo jugarlo,
tal como pide la Decisión 7 del documento.

**Rendimiento — reportado, no resuelto en este pase**: el usuario probó
`blade_count=120000` y el juego corrió a 30 FPS. No se investigó todavía
cuál es el cuello de botella real (CPU vs. GPU, fill-rate del
`cull_disabled` — doble cara rasterizada por cada blade — vs. costo del
`vertex()` del viento recalculado cada frame para cada vértice de cada
instancia). Achicar `lod0_range` de 32 a 20 ya reduce el área que se
renderea en el nivel más caro (4 triángulos por brizna, doble fill-rate)
en términos de área a **~39% de la anterior** ((20/32)² ≈ 0,39) — debería
ayudar, pero no está medido todavía con los números reales de
`Primitives Drawn` a la densidad que preocupa. Pendiente explícito para la
próxima sesión: repetir la medición del Debugger → Monitors → Raster →
`Total Primitives Drawn` con los rangos nuevos y `blade_count=120000`, y
si sigue pesado, revisar puntualmente si `cull_disabled` es
verdaderamente necesario en los 3 niveles o si se puede acotar (hoy es una
sola decisión de shader para todo el asset, atada al material único —
ver Decisión 1 y el riesgo de "canto invisible" que es la razón original
de tenerlo).

**Corrección sobre la V, mismo día**: el usuario aclaró que la V/punta de
LOD0 está bien como está — el problema real es otro, un patrón de
aliasing/shimmer en forma de cono que se extiende desde adelante del
jugador hacia el fondo del campo de pasto, ya visto antes en otro
contexto y resuelto ahí con MSAA 2x. Es el patrón clásico de geometría
fina (brizulas) convergiendo hacia el punto de fuga de la perspectiva —
justo la zona donde más geometría sub-píxel se superpone por pantalla, y
que acá se agrava por `cull_disabled` (duplica bordes rasterizados) y el
patrón cruzado en X de LOD0. Confirmado con el usuario: reinició el editor
después de activar MSAA (así que sí está activo) y en su experiencia
anterior 2x alcanzaba — acá no. Subido a `msaa_3d=2` (4x) en
`project.godot`, con plan explícito del usuario de escalar a 8x si 4x
tampoco alcanza. Sin resolver todavía cuál nivel hace falta — pendiente de
que lo pruebe jugando.

## Actualización 2026-08-16 (sexta sesión): el shimmer sigue sin resolverse,
descartado el viento, sospecha de textura de terreno, y un bug real de
`Visible` encontrado en el camino

**4x tampoco arregló el shimmer.** Bajado de nuevo a `msaa_3d=1` (2x) —
no vale la pena pagar el costo de 4x por algo que no lo ataca.

**Test del usuario, viento en 0: el shimmer sigue igual.** Descarta la
hipótesis de animación por viento como causa principal (esa hipótesis
había sido bien fundamentada — el balanceo movía la punta hasta 3.8cm,
comparable al ancho de la brizna — pero la evidencia empírica no la
sostuvo). El usuario también aclaró algo que se había entendido mal: el
shimmer está en **todo** el campo, no solo en LOD0 — descarta también que
sea específico de la punta en V (que de todos modos el usuario confirmó
que quiere mantener, no es un problema).

**Hallazgo nuevo, sin confirmar todavía**: `world_data/terrain/terrain_assets.tres`
no tiene **ninguna** textura de terreno registrada — el terreno no tiene
pintado nada todavía, probablemente rendereando con el patrón de
cuadros de placeholder por defecto de Terrain3D (visible en una captura
anterior del usuario). Un patrón de alta frecuencia como ese, visto en
ángulo rasante hacia el horizonte, es un generador de moiré clásico,
independiente del pasto — encajaría con "no cambia con el viento apagado"
y con la forma de cono/V hacia el horizonte. **Sin confirmar** — pendiente
del test de aislar activando/desactivando el pasto (ver abajo, que
resultó estar roto).

**Bug real encontrado en el camino, arreglado con `/iterate-safely`**: al
proponer "destildá Visible en `GrassInstancer` para aislar si el shimmer
es del pasto o del terreno", el usuario encontró que **destildar Visible
no ocultaba nada**. Causa: el pasto vive en los `MultiMeshInstance3D`
internos de `Terrain3D`, no como hijos de `GrassInstancer` — la propiedad
`visible` de `Node3D` nunca estuvo conectada a nada real, desde que existe
este script. **Fix** (`scripts/world/grass_terrain_instancer.gd`):
- `_ready()` conecta la señal nativa `visibility_changed` a
  `_queue_rebuild()` (mismo debounce que ya usan los `@export`).
- `rebuild()` reestructurado: `clear_by_mesh(mesh_id)` corre siempre
  (confirmado contra el código fuente real de Terrain3D, `v1.0.2-stable`,
  que es un no-op seguro sobre un mesh_id sin instancias previas), pero
  `_generate_instance_data()`/`add_transforms()` solo corren si `visible`
  es `true` — si no, corta ahí.
- Test de regresión agregado. La crítica de `/iterate-safely` encontró un
  riesgo real en el plan de testing original (poner un `terrain_path` real
  "para que sea más representativo" hubiera reproducido el fallo ya
  documentado de `add_transforms()` bajo el renderer dummy de GUT) — el
  test final sigue el mismo patrón que ya usa `_build_instancer()`, sin
  `terrain_path`, y la aserción es síncrona (sin `await`): la señal se
  emite sincrónicamente estando en el árbol, y `_queue_rebuild()` marca
  `_rebuild_queued = true` antes de programar el `call_deferred()` real.
- **Limitación conocida, no arreglada a propósito** (encontrada por la
  crítica, confirmada contra el código fuente real de Godot 4.7):
  `visibility_changed` también se dispara por visibilidad **heredada** de
  un ancestro, no solo la propia — hoy es inofensivo (`GrassInstancer`
  cuelga directo de la raíz de `terrain_base.tscn`, nada alterna un
  ancestro), pero si la jerarquía cambia algún día, un ancestro
  cambiando de visibilidad dispararía un rebuild completo sin que
  `GrassInstancer.visible` haya cambiado. Anotado en el comentario de
  clase del archivo, no resuelto — no había caso real que lo justificara
  todavía.

97/97 tests, partida real headless sin errores/warnings nuevos. Con esto,
la técnica de aislar el costo/causa del pasto tildando `Visible` (ya
sugerida dos veces en este documento) por fin funciona de verdad — sigue
pendiente usarla para terminar de confirmar o descartar la hipótesis de la
textura de terreno.

## Actualización 2026-08-16 (séptima sesión): `show_checkered` realmente
apagado, primera textura de terreno real, y el shimmer sigue sin
resolverse — billboard en LOD1/LOD2 + sombra apagada, como hipótesis
nueva, sin confirmar todavía

**Corrección sobre un fix que se había documentado pero nunca se guardó**:
la sesión anterior (madrugada, auditoría sin supervisión) documentó haber
apagado `show_checkered` en `terrain_base.tscn` como la causa más probable
del shimmer. Al retomar, `git diff` mostró que el archivo real seguía
con `show_checkered = true` en las dos ubicaciones (`Terrain3DMaterial` y
el nodo `Terrain3D`) — el `Edit` nunca quedó aplicado (o se pisó con otro
guardado). Apagado de verdad esta vez, verificado contra `git diff`, no
solo contra lo que dice este documento. **El usuario confirmó jugando que
el shimmer sigue** — así que, sea lo que sea, no era (solo) esto.

**Primera textura real de terreno registrada**: `painterly-meadow-grass-002.png`
(1024×1024), como primer `Terrain3DTextureAsset` (id 0) en
`terrain_assets.tres`, `uv_scale=0.1` (default de Terrain3D, ~10m por
tile). Se le prendió `mipmaps/generate` en el `.import` (estaba en
`false` — candidato directo a aliasing de alto contraste visto de lejos).
**El usuario confirmó jugando que tampoco era la textura** — shimmer
sigue igual con ella puesta.

**Nueva hipótesis, propuesta por el usuario**: LOD1 y LOD2 son un solo
plano con orientación aleatoria horneada (`rot_y` en
`_generate_instance_data()`) — a diferencia de LOD0 (dos planos cruzados a
90°, nunca queda de canto del todo), un plano único casi de canto respecto
a la cámara tiene ancho en pantalla que tiende a cero, generando
parpadeo/shimmer resistente a MSAA, textura y viento — los tres ya
descartados contra este mismo síntoma. El usuario, con experiencia previa
en otro proyecto (breath of freedom) con el mismo problema, pidió billboard
(giro hacia cámara) en LOD1/LOD2, dejando LOD0 como está. **Importante,
dicho explícitamente para no perder el hilo**: esto NO quedó confirmado
como la causa real antes de implementarlo (la técnica de aislar con
`GrassInstancer.visible`/`lod0_range` no llegó a correrse) — es la
hipótesis más fuerte disponible después de descartar todo lo demás, no una
certeza. Decisión explícita del usuario (vía pregunta con opciones):
resolver el billboard primero, dejar el LOD3 impostor real (que reduciría
instancias/rendimiento, no solo el parpadeo) para después.

**También, en paralelo, se encontró que el pasto castea sombra en los 3
LOD por default de Terrain3D** (`cast_shadows` nunca se tocaba, default
`1`/"On") — con `blade_count=120000` eso es sombra completa en cada
instancia, cada nivel, sin beneficio visual real en briznas finas. El
usuario eligió apagarla del todo (no solo en los tiers lejanos).

**Implementación, vía `/iterate-safely`** (`scripts/world/grass_terrain_instancer.gd`,
`scripts/world/grass_blade.gdshader`, `test/unit/test_grass_terrain_instancer.gd`):

- `_register_mesh_asset()` ahora llama `mesh_asset.set_cast_shadows(0)`
  ("Off", confirmado vía `hint_string = "Off,On,Double-Sided,Shadows Only"`
  de la propiedad real, reflexión esta sesión).
- El billboard requiere un material *distinto por nivel de LOD* dentro del
  mismo `.blend` combinado — lo cual `material_override` no permite:
  confirmado contra la fuente real de Terrain3D (`v1.0.2-stable`,
  `terrain_3d_instancer.cpp`) que esa propiedad aplica el mismo
  `Ref<Material>` a los `MultiMeshInstance3D` de los 3 niveles por igual.
  La única vía real es que cada `MeshInstance3D` traiga su propio
  `surface_override_material` ANTES de pasar la escena a
  `set_scene_file()` (confirmado también contra la fuente real,
  `terrain_3d_mesh_asset.cpp`, y verificado en vivo con una sonda headless
  descartable: instanciar el `.blend`, setear overrides distintos por
  nodo, empaquetar con `PackedScene.pack()`, y confirmar que cada LOD
  vuelve con el material correcto tras pasar por un `Terrain3DMeshAsset`
  real). Hallazgo aparte de esa misma sonda: el importador de `.blend` de
  Godot YA pone un `surface_override_material` en cada nodo (el `M_Grass`
  original de Blender) incluso en LOD0 — así que LOD0 también necesita su
  propio override explícito (el material natural, sin billboard), o
  perdería el shader de viento/gradiente en silencio.
- Nueva función `_build_multi_material_scene()`: instancia el `.blend`,
  asigna `surface_override_material` por nodo según el sufijo `LOD#` de su
  nombre (LOD0 → natural, LOD1/LOD2 → billboard), empaqueta con
  `PackedScene.pack()`, libera el nodo instanciado (`.free()`, nunca
  estuvo en un árbol — dejarlo sin liberar sería un leak real, `rebuild()`
  puede correr muchas veces en una sesión de tuning en vivo). `_build_shader_material()`
  ahora acepta `billboard: bool`.
- **El billboard en el shader NO usa `skip_vertex_transform`** (que hubiera
  obligado a reescribir a mano el camino de LOD0 también, con riesgo real
  de regresión ahí) — alternativa encontrada en la crítica del plan: cancelar
  solo la rotación/escala horneada de la instancia (`inverse(mat3(MODEL_MATRIX))`)
  y aplicar en su lugar una base ortonormal mirando a la cámara
  (`CAMERA_POSITION_WORLD`, proyectada en XZ para mantener la brizna
  vertical — billboard cilíndrico, no esférico), dejando que Godot siga
  aplicando `MODEL_MATRIX` automáticamente como siempre (se cancela contra
  la inversa, dando exactamente la base cámara-facing más la posición
  real). Escala de la instancia (`blade_scale`) leída de un canal antes sin
  usar (`INSTANCE_CUSTOM.w`, alfa del color por-instancia) en vez de
  derivarla de `MODEL_MATRIX` — la inversa cancela también la escala
  horneada, así que hay que reintroducirla explícitamente.
  Caso degenerado (cámara casi directo arriba, dirección XZ hacia cámara
  con longitud ~0) manejado con un fallback fijo antes del `normalize()`
  — sin eso daría NaN, mucho peor que el shimmer que se busca arreglar.
  **Verificado antes de tocar el shader real**: 500 combinaciones
  aleatorias de rotación/tilt/escala + 500 casos de cámara cenital, en
  GDScript puro (`Basis`/`Transform3D`, mismo álgebra que `mat3`/`mat4` en
  GLSL) — 0 discrepancias, 0 NaN. El shader completo (con el branch de
  billboard ya escrito) también se compiló de verdad contra el motor real
  (`Shader.set_code()` bajo el renderer headless, que sí valida el
  lenguaje de shader aunque no compile a GPU — confirmado que SÍ detecta
  errores reales con un identificador inventado a propósito como control).
- Se pierde el `tilt` horneado (no solo el `rot_y`) en LOD1/LOD2 al
  reemplazar la base completa por la cámara-facing — a la distancia de
  esos tiers (±7° de variación) se asume imperceptible, no confirmado
  jugando.
- Tests: 2 nuevos (`cast_shadows` queda en 0; LOD0 recibe el material
  natural, LOD1 y LOD2 el de billboard), 4 sitios de test existentes
  actualizados (perdieron el parámetro `material` que `_register_mesh_asset()`
  ya no recibe — ahora arma la escena multi-material internamente).

**Crítica del plan (`/iterate-safely`) — hallazgos descartados, con
evidencia**: el subagente crítico (sin acceso a este documento ni a las
sondas ya corridas esta sesión) señaló, correctamente por su cuenta pero
ya cubierto: (a) dudaba de que `cast_shadows`/`set_cast_shadows()`
existiera en `Terrain3DMeshAsset` — sí existe, confirmado por reflexión en
vivo esta sesión Y contra la fuente real de GitHub, cosa que el
subagente no pudo hacer (sin acceso a internet); (b) cuestionó si "LOD0
mantiene sombra, LOD1/2 no" era la intención real — error de redacción
en el pedido de crítica, la decisión real del usuario fue apagar del
todo, que es exactamente lo que hace `set_cast_shadows(0)` (propiedad
única por asset, no por LOD); (c) la afirmación sobre `set_scene_file()`
respetando `surface_override_material` por nodo — ya estaba verificada en
vivo esta sesión con una sonda real, el subagente no tenía ese contexto.
Hallazgos que sí cambiaron el plan: la alternativa a `skip_vertex_transform`
(adoptada, ver arriba), el canal de escala vía `INSTANCE_CUSTOM.w` en vez
de derivarlo de `MODEL_MATRIX` (adoptada), el caso degenerado de cámara
cenital (adoptado), y los 4 sitios de test que iban a romper (corregidos).

99/99 tests (97 + 2 nuevos), partida real headless sin errores/warnings
nuevos. **Pendiente, sin resolver**: el usuario todavía tiene que jugarlo
para confirmar si el billboard de LOD1/LOD2 de verdad ataca el shimmer
reportado — la cadena de hipótesis descartadas hasta acá es larga
(`show_checkered`, textura de terreno, viento, MSAA en 2x/4x) y esta es la
siguiente, no una certeza.

## Actualización 2026-08-16 (octava sesión): el shimmer sigue sin resolverse
con LOD0 solo, TAA probado sin aislar bien, y dos bugs reales de geometría/
rango encontrados por el usuario — no por nada de este documento

**Test decisivo, sin confirmar todavía del todo**: el usuario había dejado
`lod0_range=200` (el test de aislar sugerido antes) y reportó que el
shimmer seguía igual — con LOD0 SOLO renderizando en todo el campo (nunca
se llega a LOD1/LOD2). LOD0 es geometría cruzada (2 planos a 90°), que
matemáticamente nunca debería quedar casi de canto. Si esto se confirma
limpio, **descarta la hipótesis de "plano único casi de canto" como causa
dominante** del shimmer — la que motivó todo el trabajo de billboard de la
sesión anterior. El billboard en sí no está mal, pero puede no estar
atacando la causa real.

**Investigación web (a pedido del usuario, "buscá si es algo común")**:
confirmado que es un problema conocido — aliasing geométrico sub-píxel en
geometría delgada e instanciada, documentado explícitamente para pasto en
Godot (serie "Grass Rendering Series" de hexaquo.at). Dato clave: la propia
documentación de Godot dice que **MSAA no resuelve aliasing inducido por
shader/alpha-scissor** — coincide con que MSAA 2x/4x no tuvo ningún efecto.
TAA es la herramienta citada para exactamente este caso (acumula
información entre frames, ataca inestabilidad *temporal*, no solo
espacial). Se probó `use_taa=true`/`msaa_3d=0`, pero el reporte del usuario
sobre esa prueba vino mezclado con la reversión de `lod0_range` — **no hay
todavía una lectura limpia de TAA solo**, pendiente de reprobar.

**Chunks cuadrados de LOD confirmados como diseño intencional de
Terrain3D, no un bug**: la doc oficial dice explícito que el instancer
cambia de LOD por celda completa (32×32m por defecto), no por instancia
individual. Nuestro `lod0_range=20` es más chico que esa celda —
mismatch real que produce el pop-in en bloques que describió el usuario.
Confirmado como un problema *distinto* del shimmer, no la misma causa.

**Dos bugs reales encontrados por el usuario, no por este documento ni por
la auditoría anterior — ambos arreglados:**

1. **`grass_blade_tuft.blend` "tenía LOD" sin tener LOD en Blender.**
   El usuario lo revisó en Blender, confirmó que es un solo mesh (4 hojas
   fusionadas en un único objeto `GrassBladeTuft`, sin sufijo `LOD#`), y
   sin embargo en el juego se veía "con menos detalle en distintos LOD".
   Causa real, confirmada por reflexión: `_register_mesh_asset()` llamaba
   `set_lod0_range(lod0_range)` **sin condicionar a cuántos niveles reales
   tiene el asset** — un asset de un solo LOD (`get_lod_count()==1`)
   igual quedaba con su único nivel capado a `lod0_range` (20m por
   default), sin ningún LOD1 al que hacer *hand-off* — más allá de esos
   20m simplemente se desvanece/desaparece por el dither del
   `fade_margin`, no cambia a un modelo "menos detallado" (no existe tal
   cosa para este asset). Eso es lo que el usuario percibió como "menos
   detalle": pasto real desapareciendo, no un LOD más simple tomando
   protagonismo. Confirmado con reflexión: el default propio de Terrain3D
   para el último LOD de un asset sin tocar es >=128m
   (`Terrain3DMeshAsset::_clear_lod_ranges()`), muy por encima de
   `field_radius`. **Fix**: solo se aplican los rangos propios
   (`lod0_range`/`lod1_range`/`lod2_range`) a niveles que no son el
   último del asset — el último nivel de CADA asset queda con el default
   generoso de Terrain3D, inofensivo porque nunca se coloca ninguna
   instancia más allá de `field_radius` de todos modos. Test de
   regresión agregado.

2. **LOD2 (spike) con un tercio de la altura de los otros y "al revés" —
   confirmado con datos reales de vértices, no solo mirando el código.**
   `aabb.size.y` de LOD0/LOD1 = 1.06; de LOD2 (antes del fix) = **0.36** —
   un tercio. Y el triángulo tenía su único punto en la BASE (suelo) y el
   borde ancho en la CINTURA (30% de la altura) — al revés de cómo se ve
   una brizna real (ancha en la base, angosta en la punta). Causa: el
   "fix" de esta misma sesión anterior para un bug de vértice suelto
   (`generate_grass_blade_spike.py`, ver su propio historial) resolvió el
   *warning* descartando el vértice de la punta por completo, en vez de
   construir una punta real — cambió un bug por otro, y nadie lo notó
   porque la auditoría de esa sesión verificó conteos de vértices/caras y
   consistencia de normales, pero nunca proporciones ni silueta cruzada
   entre LODs. **Fix**: nueva función compartida `place_spike()` en
   `grass_blade_common.py` — un triángulo de altura completa
   (`BASE_SINK` a `TIP_HEIGHT`, igual que LOD0/LOD1), ancho en la base,
   angosto en la punta, construido con puntos nuevos en vez de reusar 3 de
   los 4 puntos de `leaf_verts()` (así no queda ningún vértice sin usar
   para volver a tropezar con el bug original). Aplicado en las 3
   generadoras que lo duplicaban (`generate_grass_blade_spike.py`,
   `generate_grass_blade_lod_set.py`, `generate_grass_blade_lod_set_straight_tip.py`),
   los 3 `.blend` regenerados y reimportados de verdad
   (`godot --headless --editor`, no solo el modo juego). Verificado con
   vértices reales tras el fix: `aabb.size.y` de LOD2 ahora es 1.06,
   idéntico a LOD0/LOD1.

**Malentendido de terminología, aclarado explícitamente por el usuario**:
"billboard" para él es específicamente una tarjeta de 2 triángulos **con
una imagen/textura** que reemplaza geometría para ahorrar polígonos — no
cualquier quad que rota hacia cámara. Lo que se construyó en la sesión
anterior (LOD1/LOD2 rotando en el shader) sigue siendo geometría procedural
sin textura — el usuario lo llama "modelos planos", explícitamente NO un
billboard en su vocabulario. Documentado para no repetir la confusión.

100/100 tests, partida real headless sin errores nuevos. **Todavía sin
resolver**: la causa raíz del shimmer. Estos dos bugs eran reales e
independientes del shimmer (encontrados por inspección directa del
usuario en Blender y en juego, no por la investigación del shimmer en
sí) — arreglarlos no se reporta como un intento de arreglar el shimmer.

## Actualización 2026-08-16 (novena sesión): pivote completo — pasto
procedural (LOD0/1/2 + billboard-facing-cámara) reemplazado por billboards
texturizados clásicos

Con el shimmer confirmado presente incluso con LOD0 solo (geometría
cruzada, teóricamente inmune a quedar de canto), el usuario decidió
abandonar el enfoque procedural entero y volver a la técnica clásica de
la industria: tarjetas con textura y canal alfa. Referencia concreta: el
video de Kammerbild "6 simple tips to improve grass billboards in CGI" —
6 técnicas, todas implementadas:

1. 3-4 planos por clump (no la cruz de 2) — 4 quads.
2. Centro desplazado, escala individual, texturas diversas por plano —
   atlas de 3 columnas, cada quad usa una vía UV horneada en Blender.
3. Inclinación en un eje además del yaw — visibilidad top-down.
4. Fade de alfa en la base — `smoothstep` sobre `UV.y` en el shader,
   tuneable en vivo (`base_fade_height`).

**Textura**: renderizada desde la geometría 3D ya existente (perfil de
`leaf_verts()`), cámara ortográfica, fondo transparente
(`tools/blender/render_grass_card_alpha.py`) — decisión del usuario, no
arte externo. Confirmado con datos reales que Godot invierte el eje V al
importar `.blend` (autorado base=0/punta=1 vuelve base=1/punta=0) — el
shader usa `1.0 - UV.y`, no `UV.y` directo.

**Shader**: `render_mode alpha_to_coverage` — confirmado que compila
limpio contra el motor real, y confirmado (grep contra la fuente real de
Terrain3D) que el addon no toca ninguna propiedad de transparencia/cull
en los `MultiMeshInstance3D` que pudiera interferir. `alpha_to_coverage`
necesita MSAA activo — vuelto a `msaa_3d=1`. TAA se dejó apagado a
propósito (no `true` como había quedado de una prueba anterior): la
interacción MSAA+TAA+alpha-to-coverage-dithering no está verificada y
es candidata a *ghosting* — variable aparte para probar después, no
mezclada con esta prueba.

**Simplificación real de `grass_terrain_instancer.gd`**: un solo mesh/
material registrado — `_build_multi_material_scene()`,
`lod0_range`/`lod1_range`/`lod2_range`/`fade_margin` y el flag
`billboard` del shader desaparecen enteros. `_register_mesh_asset()`
vuelve a `set_material_override()` simple (ya no hace falta el rodeo de
material-por-nodo, porque ya no hay más de un nivel). Limpieza: 3
generadores huérfanos (`generate_grass_blade_spike.py`,
`generate_grass_blade_lod_set.py`, `_straight_tip.py`) y `place_spike()`
borrados — sin costo real, estaban sin commitear.

**Corrección de un bug propio encontrado en la crítica**: un test nuevo
comprobaba `get_mesh(0).surface_get_material(0)` para verificar el
shader aplicado — eso es el material horneado por Blender, no
`material_override` (que vive en el `Terrain3DMeshAsset`/
`MultiMeshInstance3D`, nunca en el `Mesh`). Corregido a
`get_material_override()`.

Terminología (definida explícitamente con el usuario esta sesión, ver
memoria del proyecto): "billboard" = tarjeta con textura, "cardmesh" =
billboard de un solo plano, "modelo plano" = geometría sin textura
aunque rote hacia cámara (lo que se abandona en este pivote).

98/98 tests, partida real headless y reimport real sin errores nuevos.
**Sin confirmar todavía por el usuario jugando** — es un cambio de
arquitectura completo, no una iteración sobre lo anterior.

**Corrección del usuario, mismo día, jugado**: el mecanismo funciona —
**el shimmer se fue** con `alpha_to_coverage` — pero el contenido de la
textura estaba mal enfocado. Cada columna del atlas mostraba **una sola
brizna** (renderizada de `leaf_verts()`), así que los 4 planos se leían
como 4 briznas sueltas, no como una mata densa — "defeat the purpose of
the billboard, la idea es lograr densidad con menos triángulos". La
textura de cada plano tiene que mostrar la **mata completa** (referencia:
`grass_blade_tuft.blend`, ya armada de una sesión anterior), no una
brizna individual. Ajustes pendientes para la próxima sesión:

1. `render_grass_card_alpha.py`: renderizar la mata completa por columna
   del atlas (no una brizna sola), con variación entre columnas.
2. `generate_grass_billboard_clump.py`: bajar de 4 a 3 planos, cruce no
   compartido en el mismo centro (ya está, validar contra la referencia
   visual del usuario), y agregar rotación de cada plano hacia el centro
   (no solo el tilt vertical actual) para que nunca lea 100% plano.
3. El fade de base y la variación de escala por plano ya están bien,
   se mantienen sin cambios.

Sesión cortada acá a pedido del usuario ("sigamos mañana") — el
mecanismo (alpha_to_coverage, MSAA, atlas horneado en UV) queda validado,
solo falta ajustar contenido/cantidad de planos.
