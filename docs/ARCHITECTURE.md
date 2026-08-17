# Arquitectura y rationale

El código documenta lo hecho; este archivo (≤200 líneas) fija las **leyes**
y el **por qué**. Origen histórico: la Constitution y el System Map de
`druid-godot`, ya no vinculantes — su contenido vivo quedó destilado acá,
el resto se mandó a la papelera (recuperable en `git log`).

## Leyes (la Constitución — el código las cita por §)

Código que viole estas leyes no se implementa ni mergea.

- **§1** Responsabilidad única por nodo/script/recurso.
- **§2** SSoT también en máquinas de estado: cada hecho tiene un solo dueño;
  estados mutuamente excluyentes son un `enum`, nunca un trío de booleanos
  (`is_jumping`+`is_falling`+`is_climbing`). Trampa real: un enum expuesto
  en `.tscn` (`MovementBroker.motor_map: Dictionary[int, NodePath]`) se
  serializa como int crudo — agregar valores sólo al final, nunca
  reordenar/insertar en medio, o rompe escenas guardadas en silencio.
- **§3** Los datos fluyen hacia abajo, los eventos hacia arriba: el padre
  inyecta y llama métodos en los hijos; los hijos emiten señales hacia
  arriba. Nada de `get_parent()`/`$Hermano` fuera de la raíz de composición.
- **§4** Las estructuras de datos no llevan lógica: `Intents`,
  `TransitionProposal`, `LocomotionState` son hechos puros (getters
  calculados ok, nada que mute estado ajeno).
- **§5** `assert(cond, "mensaje")` para invariantes de programador (se
  recorta en release); `push_error`/`push_warning("mensaje")` + return
  temprano para fallos alcanzables en runtime (sobreviven a release).
  Mensaje siempre en inglés, sin prefijo de clase — Godot ya antepone
  `archivo:línea` al stack trace, duplicarlo se desincroniza al renombrar:
  ```gdscript
  # NO — prefijo redundante, español suelto
  push_warning("MovementBroker: brain_path '%s' no resuelve..." % p)

  # SÍ — Godot ya aporta la ubicación
  push_warning("brain_path '%s' does not resolve — entity has no input" % p)
  ```
- **§6** Composición sobre herencia profunda: herencia ≤2 niveles;
  comportamiento nuevo es un Node hijo, no una subclase más. (El "≤2
  niveles" es convención propia — Godot recomienda composición pero no fija
  un número.)
- **§7** `Brain → Intents → Broker`: el input de motor/hardware sólo entra a
  la simulación a través de un Brain. `Input.*` fuera de `*Brain.gd` es una
  violación.
- **§8** Exclusividad del motor activo: un solo Motor tickea por entidad por
  frame físico, despachado por el Broker vía arbitraje de
  `gather_proposals`. Ningún motor tickea si no ganó el arbitraje.
- **§9** Escritores SSoT específicos: sólo `MovementBroker` escribe
  `LocomotionState` (vía `LocomotionState.set_state`); sólo el Motor activo
  mueve el `Body`; sólo `StaminaComponent` muta stamina.
- **§10** Lectura cruzada por defecto: getter público en el Broker/
  componente dueño, nunca el objeto mutable (`MovementBroker.
  get_current_mode()`, no exponer `LocomotionState`). Un `*Reader`
  (`BodyReader`) sólo se justifica envolviendo un **nodo del motor** con
  mutadores públicos que Godot no deja ocultar (`CharacterBody3D.velocity`,
  `move_and_slide()`) — ahí tapa un hueco real del engine:
  ```gdscript
  # NO — Reader para una clase propia cuyo API ya controlamos
  class_name StaminaReader  # StaminaComponent no expone ningún setter público

  # SÍ — getter directo, cero ceremonia extra
  func get_stamina_pct() -> float:
  	return _stamina.get_current() / _stamina.get_max()
  ```
- **§11** Sin ticks implícitos: todo script que sobreescribe `_process`/
  `_physics_process` llama `set_*_process(false)` en `_ready()` salvo que
  esté en la lista explícita de dueños de loop (`MovementBroker`,
  `CameraRig`, `VisualsPivot`, hoy).
- **§12** Un autoload gestiona sólo su propio dominio, nunca estado ajeno
  (Godot permite estado en un autoload — `DebugOverlay._contexts` es
  válido — prohíbe que sistemas no relacionados lo usen como depósito
  compartido):
  ```gdscript
  # NO — CombatBroker escribiendo estado que no es suyo
  DebugOverlay.player_health = new_hp

  # SÍ — cada sistema empuja su propio snapshot; el autoload sólo lo guarda
  DebugOverlay.push(PANEL_KEY_COMBAT, {"hp": new_hp})
  ```
- **§13** Adyacencia de capas: `Brain → Broker → Motors → Body`. Sin saltos.
  Un Motor nunca lee al Brain directo; un Brain nunca sostiene una
  referencia al Body; el Body sólo lo invoca el Motor activo.
- **§14** El receptor posee el contrato de interrupción forzada: un sistema
  hermano (`Combat`, futuro `Health`) nunca llama
  `MovementBroker.inject_forced_proposal()` directo — emite una señal hacia
  arriba (futuro `stagger_triggered`) y el padre (`EntityController`) la
  reenvía hacia abajo. Un frame de latencia documentado, no un bug.
  **Violación conocida:** `strike_action.gd` llama `inject_forced_proposal()`
  directo hoy (tiene la referencia a `MovementBroker` vía `CombatBroker`) —
  preexistente, pendiente de corregir, no motivo para debilitar la ley.
- **§15** Comentarios sólo para invariantes/restricciones/workarounds que no
  son obvios leyendo el código — nunca el *qué*, nunca prosa larga. Máximo 3
  líneas; si hace falta más, es señal de nombrar mejor la variable/función
  en vez de explicarla aparte. El rationale largo va a `docs/`.
  ```gdscript
  # NO — explica el qué, se explaya
  # Compute the fraction of the way this blade's height sits between
  # min_scale and max_scale, used later to blend the height gradient.
  var f := (blade_scale - min_scale) / maxf(max_scale - min_scale, 0.001)

  # SÍ — el nombre ya dice el qué, sin comentario
  var height_fraction := (blade_scale - min_scale) / maxf(max_scale - min_scale, 0.001)
  ```
- **§16** ~300 líneas por script es señal de dividir, no bloqueo duro.
- **§17** Checkpoint = comportamiento validado **jugándolo**, no sólo con
  tests en verde — código que compila y tests que pasan no prueban que se
  sienta bien jugado.
- **§18** Tipado estático siempre en `scripts/` — toda `var`/parámetro/
  retorno declara tipo (recomendación oficial de Godot,
  `gdscript_styleguide.html`). `test/` queda exento — bajo valor real en
  fixtures de GUT, mismo criterio que el `unwrap`/`expect` exento en tests
  de `breath-of-freedom`:
  ```gdscript
  # NO
  func drain(amount):
  	current -= amount

  # SÍ
  func drain(amount: float) -> void:
  	current -= amount
  ```
- **§19** `%NombreÚnico` cuando comparten owner dentro del mismo `.tscn` (no
  cruza el límite de una escena instanciada — `scene_unique_nodes.html`);
  `@export var x: NodePath` cuando sí lo cruza (`brain_path`: `PlayerBrain`
  vive en `player.tscn`, `MovementBroker` en `entity_base.tscn`). Migrado y
  verificado con test (`test_player_scene.gd`, `test_entity_base.gd`):
  ```gdscript
  # NO (era así en movement_broker.gd)
  @onready var _body := get_node_or_null("../Body")

  # SÍ — Body y MovementBroker comparten owner dentro de entity_base.tscn
  @onready var _body := get_node_or_null("%Body")
  ```

## El pipeline real (verificado en código, no en docs heredados)

```text
PreUpdate  Input:  hardware → Brain (Input.* vive sólo en *Brain.gd, §7)

_physics_process (MovementBroker, dueño del loop, §11):
  1. Brain.get_intents()                 → Intents (struct compartido,
                                            movimiento + combate)
  2. Services.update_facts(body_reader)   → GroundService/LedgeService/
                                            StairsService/LadderService
  3. Drena proposals externos (FORCED,    → inyectados el frame anterior
     de inject_forced_proposal)             por EntityController
  4. Cada Motor.gather_proposals(...)     → corren todos, sólo proponen
  5. Arbitraje: mejor por (Priority,      → LocomotionState.set_state()
     override_weight), único escritor       (§9) — dispara on_deactivate/
                                            on_activate en el borde
  6. Motor activo .tick(...)              → único que mueve el Body (§8/§13)
  7. physics_tick_complete.emit(intents,  → dispara CombatBroker.tick()
     current_mode)                          vía EntityController — combate
                                            resuelve golpes con posición
                                            YA post-movimiento
```

`EntityController` es el único suscriptor de señales hacia arriba de
`Combat` y el único llamador de `inject_forced_proposal()` (§14). No
implementa lógica de gameplay propia — sólo fan-out.

`Update`/`_process`: presentación (`CameraRig`, `VisualsPivot`) — sólo
interpola/lee, nunca escribe estado de simulación.

## Por qué (rationale destilado)

- **Herramientas nativas primero, ceremonia propia sólo ante un hueco real
  del motor.** `assert`/`push_error` (§5) + tipado estático (§18) son la
  primera defensa; un patrón custom (`*Reader`, §10) se justifica sólo si
  Godot no da una vía nativa equivalente.
- **`Brain`/`Intents`/`Broker`/Motor, no "Controller".** Cualquier cuerpo
  controlable (jugador, horse, futuro enemigo/red) es un Brain nuevo que
  llena el mismo `Intents` — cero motores nuevos. `PlayerBrain` y
  `HorseBrain` ya conviven así (`scripts/player_action_stack/movement/`).
- **Arbitraje central, escritor único.** Los motores *proponen*
  (`TransitionProposal`: `target_state`, `Priority`, `override_weight`,
  `source_id`); `MovementBroker` es el único que decide y el único que
  escribe `LocomotionState`. Esto es lo que permite que agregar un motor
  nuevo no toque ningún motor existente (§1/§2 arriba) — sólo hay que
  recordar sumarlo también a `MovementBroker._guess_state_id()` (match por
  nombre de nodo, sin fallback automático si te olvidás).
- **Combat después de Movement, nunca antes.** Sus raycasts de golpe
  necesitan posición post-movimiento — si tickeara antes, usarían la
  posición del frame anterior (un frame de retraso invisible).
- **Un solo personaje, prioridad en vez de gate.** `CombatBroker.tick()`
  prioriza bow(aim) > takedown > parry > strike en vez de tickear las
  cuatro a ciegas: liberar una flecha también deja `wants_attack` en true
  el mismo frame, así que sin prioridad dispararía un golpe encima —
  cubierto por `test_aiming_suppresses_strike_on_the_same_frame`.
- **`EntityController` como único punto de fan-out.** Combat no conoce a
  Movement lateralmente (§3): todo cruce pasa por el padre — único punto de
  entrada auditable para `inject_forced_proposal()` (§14).
- **Debug: un snapshot por sistema, un solo overlay.** `DebugOverlay`
  (autoload, F1 togglea el panel) recibe `push_data()` de cada
  `BaseDebugContext` por `panel_key` — el mismo patrón para Movement y
  Combat hoy (`MovementBrokerDebugReporter`, `CombatDebugReporter`). No hay
  un segundo sink de texto por sistema — evita que HUD y log se contradigan.

## Mapa de módulos

| Módulo | Posee | Frontera |
|---|---|---|
| `scripts/base/` | `Intents`, `TransitionProposal`, `BaseMotor`, `BaseService`, `BodyReader`, `LocomotionStateReader`, `DamageEvent`, `BaseDebugContext` | Contratos puros (§4) y helpers compartidos; nada específico de Movement/Combat vive acá |
| `scripts/player_action_stack/movement/` | `MovementBroker` (único escritor de `LocomotionState`), `motors/*` (un `BaseMotor` por estado), `services/*` (Ground/Ledge/Stairs/Ladder), `PlayerBrain`, `HorseBrain`, `StaminaComponent`, `LocomotionState` | Locomoción; expone `BodyReader`/`LocomotionStateReader`, nunca `Body` ni `LocomotionState` mutable |
| `scripts/player_action_stack/combat/` | `CombatBroker` (prioriza bow/takedown/parry/strike, las cuatro siempre disponibles), `BowAction`/`ParryCounterAction`/`TakedownAction`/`StrikeAction`, `HitPauseComponent` | Resolución de golpes post-movimiento; lee `BodyReader`, nunca mueve el `Body` |
| `scripts/player_action_stack/camera/` | `CameraRig` | Presentación pura; único dueño de loop declarado además de `MovementBroker`/`VisualsPivot` (§11) |
| `scripts/player_action_stack/` (raíz) | `EntityController` | Fan-out único entre Movement/Combat (§14); sin lógica de gameplay propia |
| `scripts/world/` | `Ladder`, `Stairs`, `CombatDummy`, `ArrowProjectile`, `TerrainGrassInstancer` | Geometría/props del mundo y sus contratos de interacción (`apply_damage`, `is_parry_vulnerable`, etc.) |
| `scripts/debug_overlay.gd` (autoload) | Registro de `BaseDebugContext` por `panel_key`, toggle F1 | Estado propio del autoload permitido por §12; nunca escribe estado de otro sistema, sólo formatea lo que cada contexto le empuja |

Lo no listado sigue la regla general: posee su dato, lo publica por señal o
`*Reader`, y nadie más lo escribe.
