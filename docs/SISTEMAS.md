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
