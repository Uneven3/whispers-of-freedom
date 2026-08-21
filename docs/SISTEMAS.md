# Sistemas — catálogo, mapeado a Godot

Destilado de `docs/reference/breath-of-freedom/*` (mismo norte, motor Bevy/Rust
distinto): la intención de diseño de cada sistema sirve, la implementación en
Rust no. Acá se traduce cada sistema a su equivalente real en Godot 4.7, con
regla de prioridad fija: **nativo de Godot > plugin > motor propio**, mismo
criterio de §10/rationale de `ARCHITECTURE.md`. Esto es catálogo de a dónde
apuntar, no compromiso de orden — la prioridad real vive en `NORTE.md` →
Mecánicas y en `AHORA.md`.

## Mundo y render

- **Pasto denso e interactivo** — `MultiMeshInstance3D` + shader propio
  (`shader_type spatial`) con LOD por distancia en el vértice (crecer, no
  desvanecer) vía `custom_data` por instancia. Densidad/scatter: plugin
  **Scatter**. El LOD/viento/crecimiento no lo cubre ningún plugin, hay que
  escribirlo.
- **Pasto pisado por el jugador** — `SubViewport` con cámara ortogonal
  top-down siguiendo al jugador, renderiza un "mapa de pisadas" que el shader
  del pasto samplea para doblar brizna. Nativo completo.
- **Viento en follaje** — desplazamiento en vértice usando `TIME` +
  *global shader uniform* (`Project Settings → Shader Globals`), sin estado
  por brizna. Nativo completo, sin plugin.
- **Terreno con múltiples materiales** (tierra/pasto/roca/arena en una malla)
  — sin heightmap nativo en Godot. Plugin **Terrain3D** (GDExtension,
  mantenido): esculpido + pintura de texturas por capas + grass instancing,
  todo dentro del editor. Es el hueco real más grande de autoría de mundo.
- **Día/noche** — `DirectionalLight3D` (sol) + uno para luna, `WorldEnvironment`
  con `Sky`/`ProceduralSkyMaterial` para el gradiente, animados por script/
  `Tween`. Nativo completo. Plugin **Sky3D** si se prefiere algo con
  nubes/estrellas ya armado en vez de a mano.
- **Clima** (lluvia/tormenta/niebla) — `GPUParticles3D` para lluvia/nieve,
  `Environment.fog_enabled`/volumetric fog para tormenta; **Sky3D** también
  empaqueta un módulo de clima si no se quiere a mano.
- **Sombras del sol** — `DirectionalLight3D.directional_shadow_mode` (PSSM
  2/4 splits) ya es el sistema de cascadas; sólo hay que tunear distancia/
  tamaño por perfil de calidad. Nativo, sin plugin.
- **Luces locales** (fogatas/antorchas) — `OmniLight3D` con
  `shadow_enabled = false` y `omni_range` acotado. Nativo, sin plugin.
- **Niebla de distancia / horizonte** — `Environment.fog_*` con color atado
  a la paleta de hora del día. Nativo, y a diferencia de un motor custom
  puede llegar a alpha 1.0 (cierra el horizonte de verdad).
- **Materiales planos/mate estilo BOTW** — `StandardMaterial3D` con
  roughness alto y metallic 0. Nativo, **no** agregar un shader toon/cel —
  el norte visual lo descarta explícitamente (`NORTE.md`).
- **Texturas** — importar con mipmaps + `VRAM Compressed` (Godot elige
  ASTC/ETC2/BPTC según plataforma de export). Nativo, sin pipeline propio.

## Generación de terreno

`tools/worldgen/generate_valley.gd` genera el escenario "valle": un heightmap
procedural de 1024x1024 m con meseta alta al norte, lago en la meseta y un río
grande bajando al sur, más las mallas de agua.

```
godot --headless --path . -s tools/worldgen/generate_valley.gd
```

Corre headless a propósito: no rasteriza nada, sólo escribe datos.

**Directorio propio, y el script aborta si no lo es.** `world_data/terrain/`
tiene esculpido a mano y está versionado. Además el `Terrain3D` temporal nunca
apunta al directorio viejo ni un instante: `save_directory()` guarda *todas*
las regiones que tenga cargadas, no sólo las modificadas, así que un `Terrain3D`
que hubiera leído las esculpidas las escribiría también en el escenario nuevo.

**`region_size` por defecto es 256, no 1024.** Sin `change_region_size()` una
imagen de 1024x1024 se parte en 16 regiones en silencio.

**Verificación sin tests:** este script no lo cubre GUT. La forma de comprobar
que un cambio no alteró el comportamiento es regenerar y comparar `md5sum` de
`world_data/terrain_valley/*.res` contra la corrida anterior.

## Agua

Rationale del shader `scripts/world/water_stylized.gdshader` y del generador
`tools/worldgen/generate_valley.gd`, que por §15 no vive en comentarios.

**Opaca, no transparente.** Medido en este proyecto sobre la misma superficie:
transparente cuesta 1,98x y con refracción 2,26x (medido sobre un plano
sintético; ver `AHORA.md`). La
transparencia pierde Early-Z y la refracción fuerza una copia de pantalla por
frame. A diferencia del pasto, el agua no se puede ralear ni alejar — un lago
cubre lo que cubre.

**No `unshaded`,** que es la excepción a la regla del resto del proyecto: el
reflejo del cielo *es* el especular estándar contra el radiance map que Godot
genera del `Sky`. Sin evaluación de luz no hay reflejo, y el reflejo es lo que
hace que el agua se lea como agua. No hace falta `ReflectionProbe`.

**No lee `DEPTH_TEXTURE` ni `SCREEN_TEXTURE`.** La distancia a la orilla es
dato de generación, no algo que descubrir leyendo buffers: las mallas se
generan sabiendo dónde está la orilla.

**La normal viene guardada en una textura, no derivada.** La primera versión
sacaba la normal por diferencia central sobre ruido procedural: eso son cinco
evaluaciones de ruido por píxel, o **44 `sin()` por fragmento**. Y el ruido
procedural no tiene mipmaps, así que a distancia aliasaba a puntitos blancos y
hubo que agregar un fade de detalle — un parche a un problema que la técnica se
causaba sola. Con una `NoiseTexture2D` (`as_normal_map = true`, `seamless`) son
dos lecturas filtradas, los mipmaps aplanan el relieve solos con la distancia, y
el fade desapareció.

**`water_windwaker.gdshader` es un archivo aparte**, no un uniform: profundidad
cuantizada en bandas duras, parches de espuma de ruido celular recortados con
borde, contorno de orilla duro. La diferencia con la estilizada es de técnica,
no de parámetro — mismo criterio que `grass_blade_opaque.gdshader`.

**Todo en metros, no en UV.** El error original fue parametrizar bandas y ondas
en UV compartiendo un material entre lago y río: UV.y abarca 98 m en el lago y
13,5 m en el río, así que una banda de espuma de 0,07 medía 8,8 m en uno y
0,9 m en el otro. Hoy `uv_to_meters` declara cuántos metros abarca cada eje UV
de esa malla, y lago y río tienen materiales separados.

**`world_space_noise`.** El río tiene UV.y = 0/1/0 de orilla a orilla, así que
usar UV como dominio del ruido espeja el patrón sobre el eje del cauce. En
espacio de mundo no pasa. El costo es que la corriente va en una dirección fija
del mundo en vez de seguir las curvas.

**Fade de detalle con la distancia.** El ruido procedural no tiene mipmaps, así
que a distancia cae bajo el píxel y aliasa a puntitos blancos que titilan.
`detail_fade_*` apaga la perturbación de normal, la espuma y el brillo, y sube
`ROUGHNESS` a `far_roughness` para que el reflejo deje de espejear.

### Malla del lago

El radio no es constante: `_shore_radius()` marcha desde el centro hasta donde
el terreno generado cruza `LAKE_LEVEL`, y el borde se mete 1 m pasado el cruce
para que el terreno recorte el agua justo en la línea de agua. Tres trampas ya
resueltas, cada una visible como un defecto distinto:

1. **Radio fijo** (`LAKE_RADIUS * 0.93`): el agua quedaba 28 m adentro del
   cerro por un lado y colgando en el aire por el sur.
2. **Marcha sin tope**: por el cauce del río el terreno sigue bajo el nivel del
   lago kilómetros, así que la orilla se iba 60 m canal abajo y salían dos
   púas. Tope en `LAKE_RADIUS`, y los ángulos sin cruce se tapan con la mediana
   de los que sí cruzaron.
3. **Púas de 2-3 muestras** donde el rayo corre por el hombro del cauce: las
   borra una mediana circular de 5 sobre los radios.

Y la ribera del río se angosta adentro de la cuenca (`bank_reach`): sus 55 m de
hombro le comían el labio al lago, pero apagarla del todo tapaba el desagüe.

**Defecto conocido:** el borde sur todavía cuelga ~1 m sobre el terreno a los
costados de la boca del río, donde el terreno queda apenas bajo `LAKE_LEVEL`.

## VFX y feedback de combate

- **Golpes/chispas/humo** — `GPUParticles3D` pooleado (crear una vez,
  reiniciar `one_shot`, nunca instanciar material/malla por evento). Nativo.
- **Flash de pantalla / hit flash / shake de cámara / daño flotante** —
  `ColorRect` en `CanvasLayer` (screen flash), `material_override` propio
  por instancia (hit flash, nunca un resource compartido), offset de trauma/
  ruido en `Camera3D` (shake), `Label3D` o `Control` vía
  `Camera3D.unproject_position` (daño flotante). Todo nativo.

## Personaje y animación

- **Máquina de locomoción** — lado animación: `AnimationTree` →
  `AnimationNodeStateMachine`. Lado gameplay: enum/match propio en el script
  de `CharacterBody3D` (Godot no tiene FSM de gameplay nativa, sólo la de
  animación). Plugin **LimboAI** si el FSM de gameplay crece mucho; no
  partir de ahí.
- **Blend direccional/strafe** — `AnimationNodeBlendSpace2D` (X strafe,
  Y velocidad). Encaje nativo directo, sin plugin.
- **Sin deslizamiento de pies** — escalar `playback_speed` del clip por
  `velocidad_real / velocidad_autoreada` (con guard de división por cero).
  Nativo, es scripting simple.
- **Capas superior/inferior** (combate con piernas locomoviendo) —
  `AnimationNodeBlendTree` con `Blend2`/`Add2` filtrados por hueso. Nativo,
  feature de primera clase de `AnimationTree`.
- **IK de 2 huesos (pies/manos, escalada/mantle)** — Godot ≥4.6 trae
  `TwoBoneIK3D`, solver determinístico (cerrado, no iterativo) sobre el
  stack de `SkeletonModifier3D`/`IKModifier3D` — nativo, no hace falta
  escribir un solver propio. Requiere `target` (raycast desde tobillo/mano
  con `PhysicsDirectSpaceState3D.intersect_ray`, o el punto de contacto de
  pared en escalada) y **`pole` obligatorio** — sin pole target la rodilla/
  codo puede resolver hacia el lado equivocado; animar el pole si la
  dirección de flexión cambia (patada, alcanzar cruzado). Corrección:
  antes de 4.6 el único IK nativo era `SkeletonIK3D` (FABRIK, con bugs de
  comportamiento documentados) — no aplica más, `TwoBoneIK3D` lo reemplaza
  para exactamente este caso. Nota menor: hay una regresión reportada
  (godot-proposals #14456) sobre control de rotación del hueso final vs. el
  viejo `SkeletonIK3D` — revisar si importa para el rig final antes de
  cerrarlo.
- **Sockets de arma/carga** — `BoneAttachment3D` por hueso
  (`SKT_MainHand`, `SKT_OffHand`, ...). Nativo.
- **Retargeting entre rigs** — `SkeletonProfileHumanoid` + `BoneMap`
  (sistema de retargeting nativo de Godot 4.x). No escribir un mapeo de
  huesos a mano.
- **Swap de equipo/malla modular** — varios `MeshInstance3D` apuntando al
  mismo `Skeleton3D` compartido. Nativo, skinning estándar.
- **Cápsula de física vs. escala visual** — verificar `CapsuleShape3D`
  contra los bounds de la malla importada una vez, no por cada tuneo. No es
  problema de tooling, es de proceso.

## Pipeline de arte

- **Blender → Godot** — apuntar *Editor Settings → FileSystem → Import →
  Blender → Blender Path* al ejecutable y dejar que Godot importe `.blend`
  directo (usa el exportador glTF de Blender por debajo, reimporta al
  guardar). Menos pasos que exportar `.glb` a mano.
- **Colliders por convención de nombre** — sufijos `-col`/`-convcol`/
  `-colonly`/`-convcolonly` en Blender generan `CollisionShape3D` y
  ocultan/quitan la malla de render al importar. Nativo — adaptar la
  convención de autoría a los sufijos de Godot, no al revés.
- **Metadata custom** (licencia, tipo de material, escalable) — propiedades
  custom de Blender exportan a `extras` de glTF; leerlas con un
  `GLTFDocumentExtension._import_node` y guardarlas como `set_meta`. Único
  punto del pipeline que sí pide un script propio, chico.
- **LOD** — dos sistemas nativos complementarios: LOD de malla automático al
  importar (`meshoptimizer`, prendido por defecto, el renderer elige nivel
  por tamaño en pantalla — no requiere nada) para simplificar la misma
  malla; `visibility_range_begin/end` + fade para esconder objetos enteros
  o cambiar a una malla distinta a cierta distancia. Sin modifier de
  Decimate a mano. Caveat: en mallas grandes (terreno) el LOD automático
  puede volver el import lento — issue conocido del engine, no asumir que
  algo está roto antes de revisar esto.
- **Validación de assets antes de runtime** — sin equivalente a un build
  script. Hueco real: script de validación corrido headless
  (`godot --headless --script validate.gd`) en CI. No hay atajo nativo acá.

## Audio

- **Pisadas** — track de "call method"/audio en `AnimationPlayer` disparado
  en el frame exacto de contacto (más preciso que acumular distancia),
  raycast hacia abajo para leer superficie (tag en el collider). Variación
  de pitch/clip con `AudioStreamRandomizer` (nativo Godot ≥4.3).
- **Cues de combate** (golpe/impacto/flecha) — gameplay emite `Signal`s
  propias; un autoload `SfxManager` conectado a esas señales es el único
  dueño de la tabla cue→sonido. Encaje nativo mejor que un bus de eventos
  genérico — es exactamente para esto que existen las señales de Godot.
- **Distancia/polifonía/buses** — `AudioStreamPlayer3D.max_distance` y
  `max_polyphony` ya resuelven el corte por distancia y el tope de voces
  simultáneas; buses Master/SFX/Música/UI con Limiter en Master para techo
  global. Completamente nativo — no portar lógica de corte manual.
- **Modulación continua** (respiración/esfuerzo según stamina) — `Tween`
  sobre `pitch_scale`/`volume_db`, actualizando sólo cuando el delta supera
  un umbral audible (no cada frame). Scripting simple, agnóstico de motor.

## Mundo / sistemas de juego (alcance amplio, sin comprometer orden)

- **Nadar/bucear** — `Area3D` de volumen de agua override de gravedad/
  damping/velocidad adentro. Sin buoyancy nativa, es matemática propia.
- **Snowboard en pendiente** — mismo patrón de motor propio sobre
  `CharacterBody3D`, leyendo el ángulo de la normal del piso.
- **Monturas (terrestres y voladoras)** — reparent del jugador bajo un
  `Marker3D`/`RemoteTransform3D` de asiento al montar; la montura voladora
  reusa el motor tipo glide. Sin sistema nativo de monturas, es diseño
  propio en ambos casos.
- **IA enemiga** — `NavigationAgent3D`/`NavigationServer3D` nativo para
  pathing. Plugin **LimboAI** para árboles de comportamiento si la
  percepción/flanqueo/reacción grupal de `NORTE.md` crece más allá de un
  FSM simple.
- **Problemas opcionales (estilo Majora's Mask)** — `Resource` propio +
  autoload de tracking, sin sistema de quests nativo. Plugin
  **Dialogue Manager** para diálogo ramificado de NPC si hace falta.
- **Guardado** — autoload `SaveManager` con `ResourceSaver`/`ResourceLoader`
  sobre `Resource` propios, o `FileAccess` + JSON para estado de partida.
  Nativo completo.
- **Escala de mundo** — Godot usa precisión simple por defecto; mundo
  grande necesita evaluar precisión doble o origin-rebasing, y streaming
  por región vía `ResourceLoader.load_threaded_request` (no hay streaming
  de mundo nativo). Only-if-needed, no partir de acá.
- **Multiplayer co-op host-autoritativo** — API de multiplayer de alto
  nivel: `MultiplayerSynchronizer`, `MultiplayerSpawner`, `@rpc`, transporte
  ENet por defecto. Nativo completo, sin plugin — ya es lo que
  `NORTE.md` pilar 5 pide.
- **Crafteo/inventario/durabilidad** — `Resource` propio para ítems/recetas
  + autoload de inventario. Nativo, sin plugin destacado.

## Autoría de mundo/nivel

El editor de Godot ya **es** buena parte de la herramienta que
`breath-of-freedom` tuvo que construir a mano (su doc `MAP_EDITOR.md`
describe un editor in-game entero porque Bevy no trae uno):

- Cámara orbital/top-down, undo/redo, y colocar puntos/volúmenes
  (`Marker3D`/`Area3D`) ya son gratis en el editor nativo — no hace falta
  tooling propio para eso.
- El hueco real es esculpido de relieve + pintura semántica + scatter de
  foliage, sin equivalente nativo. **Terrain3D** lo cubre entero dentro del
  editor. Alternativa liviana para props discretos sin terreno esculpido:
  `GridMap` (ya trae modo pincel) + **Scatter**.
- Persistencia como datos puros (nivel ≠ presentación) es el mismo patrón
  `Resource`/`ResourceSaver` que el resto del proyecto — no un formato
  aparte.

## Plugins a evaluar

| Plugin | Para qué | Reemplaza hueco nativo en | Estado |
|---|---|---|---|
| **Terrain3D** | Terreno esculpible + splat + grass instancing | Mundo/render | Adoptado 2026-08-14, ver `AHORA.md` |
| **LimboAI** | Behavior trees / HFSM | IA enemiga, FSM de gameplay si crece | Sin evaluar |
| **Dialogue Manager** | Diálogo ramificado | Problemas opcionales/NPCs | Sin evaluar |
| **Sky3D** | Día/noche + clima empaquetado | Mundo/render (opcional, alternativa a mano) | Sin evaluar |
| **Scatter** | Placement/densidad de instancias | Pasto, foliage, props | Sin evaluar |

Ninguno se adopta sin probarlo contra la filosofía del proyecto: nativo
primero, plugin sólo si ahorra ingeniería real (mismo criterio que §10 de
`ARCHITECTURE.md`).

## Lecciones de arquitectura, agnósticas de motor

De la auditoría de límites de `breath-of-freedom` (`AUDIT_BOUNDARIES_
2026-08-11.md`), aplicable tal cual acá:

- Un solo escritor por estado compartido — ya es ley (`ARCHITECTURE.md`,
  `LocomotionState`/`CombatBroker`).
- La capa de presentación (visuals/VFX) puede mutar sus propios objetos,
  nunca datos de dominio/gameplay directamente.
- Tamaño de archivo grande no es por sí solo violación de límites — puede
  ser una sola responsabilidad bien cohesionada; verificar antes de partir.
- Auditorías manuales de límites agarran drift que ningún test en verde
  agarra — vale la pena programarlas, no sólo confiar en CI.
