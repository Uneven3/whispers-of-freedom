# Movimiento y combate — rationale

Por qué cada decisión no obvia del player action stack es como es. Vive acá y
no en comentarios por §15 de `ARCHITECTURE.md`: el rationale largo va a `docs/`.
`ARCHITECTURE.md` sigue siendo la Constitución y el mapa de módulos; esto es el
detalle de por qué.

## Spawn

`scripts/player_action_stack/spawn_snap.gd` apoya al padre `Node3D` en el suelo
una vez, al aparecer, consultando el `Terrain3D` que esté en el grupo `terrain`
— no por `NodePath` ni por hermano, porque la raíz de composición del Player no
puede saber en qué escena la van a soltar (§3). Que no haya nadie en el grupo
`terrain` es un caso normal, no una falla: no hace nada.

**Llamadas dinámicas a Terrain3D a propósito.** `addons/terrain_3d/` no está
commiteado, así que un tipo estático `Terrain3D` acá no parsearía para quien no
tenga el plugin instalado, y rompería al Player incluso en escenas sin terreno.

**La trampa de la colisión.** El modo de colisión Dynamic de Terrain3D sólo
genera shapes alrededor de la cámara que se le pasa por `set_camera()`, y **nada
la llama automáticamente fuera del editor**. El plugin del editor la llama en
cada interacción con el viewport 3D (`addons/terrain_3d/src/editor_plugin.gd`),
que es por qué esculpir y probar alturas en el editor puede verse bien mientras
una sesión de Play real —donde nadie cablea esto— no tiene colisión en ningún
lado y la cápsula cae de largo, pese a aparecer a la altura correcta.

`get_node_or_null("%Camera3D")` y no el atajo `%Camera3D`: el atajo tira
excepción en vez de devolver null cuando no existe ese nodo único, que es el
caso normal de cualquier cosa que no sea el `player.tscn` real (dobles de test,
escenas sin Player).

**Altura.** `get_height()` da la altura del suelo en el ORIGEN del Body, no en
sus pies — la cápsula está centrada en el Body. Apoyar el origen directo en el
terreno entierra la mitad de abajo, que es exactamente "el jugador está clavado
en el piso". Se le suma la media altura de la cápsula, leída de `BodyReader`
en vez de rederivar la matemática acá.

**`@tool`, y qué falla en el editor.** El script de `MovementBroker` no es
`@tool`, así que mientras se edita es sólo una instancia placeholder.
`has_method()` **miente**: reporta `get_body_reader()` (los placeholders
conservan la API declarada) pero llamarlo tira "Attempt to call a method on a
placeholder instance". Por eso se saltea la llamada de entrada en vez de
confiar en `has_method()`.

**Teletransportes e interpolación.** Con `physics_interpolation` activo
(`project.godot`) el motor dibuja posiciones intermedias entre ticks. El salto
del spawn no es movimiento: sin avisar, los primeros frames muestran al jugador
deslizándose desde donde estaba. `reset_physics_interpolation()` descarta el
estado previo. **Regla general: todo teletransporte la necesita; el movimiento
continuo no.**

## Escaleras

`stairs_motor.gd`. La geometría del cuerpo sale del `BodyReader` (SSoT), no de
un `@export` por motor.

**`floor_snap_length` achicado mientras se está en escalera.** El 0.4 por
defecto alcanza el escalón anterior (0,33 m abajo) y deshace el snap-up de cada
tick — esa era la causa del atasco al esprintar. 0.20 sigue fijando el cuerpo al
escalón actual (0,08 m abajo), así que `is_on_floor()` se mantiene true.

**Modo pegajoso.** Una vez activo, sigue activo mientras el `Area3D` reporte
on-stairs, aunque `is_on_floor()` parpadee en false por un frame después de un
snap-up. Sin esto la subida cae a Fall cada vez que el centro del cuerpo queda
brevemente fuera del escalón anterior y todavía no sobre el siguiente.

**La entrada inicial sí exige estar apoyado**, o la gravedad se suprime en el
aire.

**Snap por escalón, sin clamp por frame.** El punto de muestreo depende de la
dirección: subiendo, borde de ataque más un margen (levanta el cuerpo sobre la
próxima contrahuella antes de que el frente de la cápsula la golpee); bajando,
borde de atrás apenas adentro del escalón de arriba (baja sólo cuando la cápsula
lo libera del todo, si no la mitad trasera se incrusta). La distancia de
lookahead está calibrada al radio de la cápsula, así que la muestra sigue el
frente del cuerpo sin pasarse. Limitar a un escalón por frame dejaba la esfera
delantera incrustada en la caja del escalón siguiente al esprintar, y
`move_and_slide` resuelve eso matando la velocidad horizontal — el "choque".

**Cota inferior y gate direccional.** El snap sólo ocurre dentro de un escalón
de la huella esperada, arriba y abajo. Sin la cota inferior, caminar contra el
COSTADO de la escalera desde el piso teletransportaba el cuerpo hasta escalones
a la altura del cuello, porque el `Area3D` encierra la escalera entera. Y el
snap está condicionado a intención direccional clara (`|slope_input| > 0.3`):
el movimiento lateral puro sobre una huella se lo deja a `floor_snap_length`,
porque sin ese gate la deriva mínima a lo largo de la pendiente cruza bordes de
escalón y hace saltar el cuerpo por `step_rise`.

## Suelo

`ground_service.gd` es un proveedor de hechos de sólo lectura. **Nunca muta el
cuerpo** — los motores son los únicos que escriben.

`CharacterBody3D.is_on_floor()` es la autoridad: se actualiza en cada
`move_and_slide()` y refleja el estado del final del frame de física ANTERIOR,
que es exactamente lo que hace falta para decisiones consistentes de un frame.
Encima se filtra por ángulo: 60° alcanza para pasar los frames de roce con la
contrahuella (~27° desde UP al tocar la huella) y sigue rechazando paredes.

La traversía de escaleras ya no es asunto de este servicio — ver
`StairsService` / `StairsMotor`.

## Trepar

`climb_motor.gd`. **El ápice de una superficie curva.** Arriba de una esfera o
un cilindro el motor de física clasifica el contacto como piso (normal ≈ UP), no
pared. `is_on_floor()` es el detector autoritativo: funciona sin importar hacia
dónde apunte el cast de la cintura, a diferencia de mirar `climb_normal`, que
refleja el punto de impacto del cast y no el contacto del cuerpo. Cerca del
ápice se suprimen el snap de yaw y el `wall_stick` enteros.

Sin esto el modo oscila Climb↔Walk cada frame: una convulsión de yaw. Sólo se
considera "cerca del ápice" si está apoyado Y NO golpea algo a la altura de la
cabeza; el chequeo de `ledge_point` confirma que hay borde y no piso plano.

**La dirección de encare se aplana siempre a horizontal.** En superficies
curvas la normal de trepado tiene componente vertical, y pasarla cruda a
`Basis.looking_at` inclina el eje Y del cuerpo para igualar la normal — junto
con el parpadeo de `is_on_wall()` en el ápice, eso produce la convulsión
"perpendicular a la esfera ↔ perpendicular al piso".

## Visuales

`visuals_pivot.gd`. **`orthonormalized()` de los dos lados.** `Basis.slerp()`
exige rotaciones puras y llama `get_rotation_quaternion()` internamente, que
tira si alguna base derivó aunque sea un poco. Reasignar `basis` al resultado de
su propio slerp cada frame acumula error de punto flotante hasta que el chequeo
estricto `is_rotation()` salta (~80 s en un playtest).

**Los segmentos de la SphereMesh de partículas.** Por defecto son 64x32 = 4224
triángulos; a radio 0,08 eso ocupa unos pocos píxeles, o sea que la tesela es
invisible. 15 partículas x 4224 eran ~63000 triángulos por golpe; con 6x3 son
~720. **Lo que este arreglo NO arregla:** la escena es fill-bound, no
vertex-bound (`presupuesto_render.md`), y ese material es `TRANSPARENCY_ALPHA`,
sin Early-Z. Su costo real vive en el overdraw de esferas superpuestas. Medido,
el delta de GPU ms es despreciable. Las palancas de verdad serían `amount`, el
radio, y recuperar Early-Z.

## Jerarquía de nodos

`entity_controller.gd` es `Node3D` y no `Node`. Godot hereda transform sólo del
padre INMEDIATO casteado a `Node3D`: no camina hacia arriba a través de un
`Node` plano para encontrar un `Node3D` más lejano. Como `Node` plano,
`EntityController` rompía la cadena entre `Player` (la raíz espacial, la que
mueve `SpawnSnap`) y `Body`/`VisualsPivot` debajo: mover `Player` nunca movía la
cápsula, ni en el editor ni en Play. Verificado empíricamente contra el motor.
Sigue sin transform propio (identidad, pasamanos transparente): es espacial sólo
para no romper la cadena, no para cargar significado (§3/§13).

## Arbitraje de combate

**`STRIKE_PRIORITY_WEIGHT = 8`** (`strike_motor.gd`) le gana al FORCED(0)
incondicional de `StairsMotor`/`LadderMotor` —les perdía los empates a mitad del
dash— y a `WallJumpMotor` (5), sin pasar a `MantleMotor`/`EdgeLeapMotor` (10) ni
`AutoVaultMotor` (20): esos también son pegajosos y ganarles es un cambio de
diseño real (si un golpe interrumpe un vault en curso), no algo que este fix
deba decidir.

**`MAX_PENDING_FRAMES = 30`** es la red de seguridad: si la propuesta FORCED
pierde el arbitraje de plano en vez de ganar o empatar, `tick()` nunca corre
—el único lugar donde se limpia `_active`— y `_active` quedaría true para
siempre, reproponiendo cada frame hasta ganar y hacer un dash de golpe hacia un
objetivo viejo, sin input, quizás segundos después. Se cuenta en frames y no en
tiempo porque `gather_proposals()` no recibe delta.

**`CombatBroker.tick()` elige exactamente una acción por frame** en vez de
depender del orden: un golpe en curso resuelve primero (nunca se interrumpe a
mitad), después apuntar/arco, takedown, parry, y recién ahí un golpe nuevo. Sin
esto, soltar un tiro apuntado (`wants_archery_release`) también deja
`wants_attack` en true ese mismo frame y saldría además un golpe cuerpo a cuerpo.

**`StrikeAction.is_active()` no es `is_in_progress()`.** El primero es sólo
durante el dash; el segundo incluye el enfriamiento. `CombatBroker` usa
`is_active()` para decidir el ruteo exclusivo, así que otra acción en el mismo
frame durante puro enfriamiento no se descarta en silencio. Que
`is_in_progress()` siga true durante el enfriamiento es intencional para su
propio propósito: una pulsación nueva no debe interrumpir un enfriamiento ya
empezado. Y una pulsación encolada cae al chequeo de golpe nuevo sólo cuando el
enfriamiento se termina de verdad — sin esa rama, una pulsación que caía justo
en el frame en que el enfriamiento llegaba a cero se perdía, porque
`is_action_just_pressed` es de un disparo.

**`LedgeService._current_mode`** permite saltear el cómputo de hechos de borde
mientras STRIKE está activo. Es un salteo angosto y verificado: ningún consumidor
de prioridad FORCED puede ganarle el arbitraje a STRIKE (Mantle exige CLIMB o
WALL_JUMP previo, la continuación pegajosa de AutoVault exige ya estar en
AUTO_VAULT), y la entrada no pegajosa de AutoVault es sólo PLAYER_REQUESTED. **No
extender a otros estados sin jugarlo** (§17).

**`GlideMotor` baja a PLAYER_REQUESTED** cuando el jugador además pide trepar en
una pared trepable: FORCED le ganaría al PLAYER_REQUESTED de `ClimbMotor` y
dejaría al jugador encerrado en GLIDE pegado a la pared.

**El toggle de trepar se resetea** con mantle, edge leap y auto-vault, pero
**no con JUMP**: un salto desde el piso estando en una pared trepable no debería
borrar la intención de trepar.

## Cámara

`camera_rig.gd`. `_LANDING_STATES` son los estados alcanzables desde FALL que
cuentan como "aterrizaje" para el bajón de cámara. Excluye a propósito
AUTO_VAULT / MANTLE / CLIMB / GLIDE / WALL_JUMP / EDGE_LEAP / JUMP / STRIKE:
son traversía o combate que el jugador dispara aposta, no un "toqué el piso"
pasivo, aunque algunos también sean alcanzables directo desde FALL.
