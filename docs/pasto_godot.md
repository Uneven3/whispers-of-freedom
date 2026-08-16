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
  a) confirmar si un `scene_file` puede traer varios niveles de LOD y con
     qué convención los reconoce Terrain3D;
  b) investigar `generated_type = "Texture Card"` — si auto-orienta a
     cámara y en qué eje, puede reemplazar el billboard a mano;
  c) si (b) no alcanza, implementar el billboard cilíndrico a mano en
     `vertex()` (no `render_mode billboard`, da esférico);
  d) confirmar si `fade_margin`/el LOD nativo produce cross-fade real o
     es un corte duro (jugarlo, no asumir por el nombre);
  e) confirmar que el LOD nativo de mallas cambia en una partida jugada
     real (F5), no solo en el editor — depende de `Terrain3D.set_camera()`
     registrado, hoy solo llamado desde `spawn_snap.gd` con otro
     propósito;
  f) verificar que tunear rangos/fade en vivo no ensucia
     `world_data/terrain/*.res` (precondición ya anotada en
     `docs/AHORA.md`, nunca verificada);
  g) reconstruir por qué `GeometryInstance3D.visibility_range_*` se
     descartó frente al LOD nativo de `Terrain3DMeshAsset` — la razón
     quedó anotada como pendiente en `docs/AHORA.md` sin explicarse.
- **Fase 1 — geometría, en una escena de laboratorio descartable** (no
  directo sobre `terrain_base.tscn`): generar LOD2
  (`generate_grass_blade_spike.py`); confirmar si `grass_blade_flat.blend`
  sirve tal cual para LOD1.
- **Fase 2 — shader:** extender `grass_blade.gdshader` con el
  comportamiento de billboard para LOD3, según lo que confirme Fase 0b/0c.
  Expectativa calibrada por el antecedente: probablemente el paso de
  mayor riesgo del plan, no un paso mecánico — puede no bastar con color
  sólido, y texturar tampoco garantiza cerrarlo del todo (ver Decisión 3).
- **Fase 3 — integración:** cablear las mallas según la ruta (A o B)
  decidida en Fase 0, configurar rangos de distancia y fade.
- **Fase 4 — medir y jugar (§17):** herramienta de ancho-en-pantalla/
  cobertura + jugar de verdad con la cámara moviéndose. Criterio de
  éxito: disimulado lo suficiente, no invisible.

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
