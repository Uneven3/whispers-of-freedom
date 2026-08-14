# Arquitectura y rationale

El código documenta lo hecho; este archivo (≤200 líneas) fija las **leyes** y
el **por qué**. Detalle histórico del proceso que originó este patrón:
`docs/reference/druid-godot/architecture/CONSTITUTION.md` y `00-system-map.md`
— ninguno de los dos es vinculante hoy, son el origen documentado.

## Leyes (la Constitución — el código las cita por §)

Código que viole estas leyes no se implementa ni mergea.

- **§1** Responsabilidad única por nodo/script/recurso.
- **§2** SSoT también en máquinas de estado: cada hecho tiene un solo dueño;
  estados mutuamente excluyentes son un `enum`, nunca un trío de booleanos
  (`is_jumping`+`is_falling`+`is_climbing`).
- **§3** Los datos fluyen hacia abajo, los eventos hacia arriba: el padre
  inyecta y llama métodos en los hijos; los hijos emiten señales hacia
  arriba. Nada de `get_parent()`/`$Hermano` fuera de la raíz de composición.
- **§4** Las estructuras de datos no llevan lógica: `Intents`,
  `TransitionProposal`, `LocomotionState` son hechos puros (getters
  calculados ok, nada que mute estado ajeno).
- **§5** Validación de frontera con intención: `assert(cond, "mensaje")`
  para invariantes de programador (tipo incorrecto, mal uso interno —
  se recortan en release). `push_error("mensaje")` + return temprano para
  fallos alcanzables en runtime (valor de diseño malo, nodo opcional
  faltante, dato cargado inválido — sobrevive a release).
- **§6** Composición sobre herencia profunda: herencia ≤2 niveles;
  comportamiento nuevo es un Node hijo, no una subclase más.
- **§7** `Brain → Intents → Broker`: el input de motor/hardware sólo entra a
  la simulación a través de un Brain. `Input.*` fuera de `*Brain.gd` es una
  violación.
- **§8** Exclusividad del motor activo: un solo Motor tickea por entidad por
  frame físico, despachado por el Broker vía arbitraje de
  `gather_proposals`. Ningún motor tickea si no ganó el arbitraje.
- **§9** Escritores SSoT específicos: sólo `MovementBroker` escribe
  `LocomotionState` (vía `LocomotionState.set_state`); sólo el Motor activo
  mueve el `Body`; sólo `StaminaComponent` muta stamina.
- **§10** Lectura cruzada entre sistemas vía `*Reader`, nunca el dueño
  mutable — `BodyReader`, `LocomotionStateReader`, futuros `FormReader`/
  `HealthReader`.
- **§11** Sin ticks implícitos: todo script que sobreescribe `_process`/
  `_physics_process` llama `set_*_process(false)` en `_ready()` salvo que
  esté en la lista explícita de dueños de loop (`MovementBroker`,
  `CameraRig`, `VisualsPivot`, hoy).
- **§12** Sin estado global de juego: los autoloads son utilidades sin
  estado u observadores pasivos (`DebugOverlay`). Las variables de partida
  viven en el árbol de escena.
- **§13** Adyacencia de capas: `Brain → Broker → Motors → Body`. Sin saltos.
  Un Motor nunca lee al Brain directo; un Brain nunca sostiene una
  referencia al Body; el Body sólo lo invoca el Motor activo.
- **§14** El receptor posee el contrato de interrupción forzada: un sistema
  hermano (`Combat`/`Form`/futuro `Health`) nunca llama
  `MovementBroker.inject_forced_proposal()` directo — emite una señal hacia
  arriba (`form_shifted`, futuro `stagger_triggered`) y el padre
  (`EntityController`) la reenvía hacia abajo. Un frame de latencia
  documentado, no un bug.
- **§15** Comentarios sólo para invariantes/restricciones/workarounds, nunca
  el *qué*. El rationale largo va a `docs/`.
- **§16** ~300 líneas por script es señal de dividir, no bloqueo duro.
- **§17** Checkpoint = comportamiento validado **jugándolo**, no sólo con
  tests en verde (ver `docs/reference/druid-godot/mechanic-spec.md` para el
  historial de por qué esta regla existe: código con tests pasando marcado
  `[x] Done` sin haberse jugado, dos veces).

## El pipeline real (verificado en código, no en docs heredados)

```text
PreUpdate  Input:  hardware → Brain (Input.* vive sólo en *Brain.gd, §7)

_physics_process (MovementBroker, dueño del loop, §11):
  1. Brain.get_intents()                 → Intents (struct compartido,
                                            movimiento + combate + forma)
  2. FormBroker.tick(intents, delta)      → resuelve shapeshift ANTES de
                                            que Movement arbitre, así el
                                            frame ya arbitra con la máscara
                                            de motores de la forma nueva
  3. Services.update_facts(body_reader)   → GroundService/LedgeService/
                                            StairsService/LadderService
  4. Drena proposals externos (FORCED,    → inyectados el frame anterior
     de inject_forced_proposal)             por EntityController
  5. Cada Motor.gather_proposals(...)     → corren todos, sólo proponen
  6. Arbitraje: mejor por (Priority,      → LocomotionState.set_state()
     override_weight), único escritor       (§9) — dispara on_deactivate/
                                            on_activate en el borde
  7. Motor activo .tick(...)              → único que mueve el Body (§8/§13)
  8. physics_tick_complete.emit(intents,  → dispara CombatBroker.tick()
     current_mode)                          vía EntityController — combate
                                            resuelve golpes con posición
                                            YA post-movimiento
```

`EntityController` es el único suscriptor de señales hacia arriba de
`Form`/`Combat` y el único llamador de `inject_forced_proposal()` (§14). No
implementa lógica de gameplay propia — sólo fan-out.

`Update`/`_process`: presentación (`CameraRig`, `VisualsPivot`) — sólo
interpola/lee, nunca escribe estado de simulación.

## Por qué (rationale destilado)

- **`Brain`/`Intents`/`Broker`/Motor, no "Controller".** Cualquier cuerpo
  controlable (jugador, horse, futuro enemigo/red) es un Brain nuevo que
  llena el mismo `Intents` — cero motores nuevos. `PlayerBrain` y
  `HorseBrain` ya conviven así (`scripts/player_action_stack/movement/`).
  El vocabulario es deliberado: ver
  `docs/reference/druid-godot/playbooks/extend-intents.md` para el
  procedimiento de agregar un campo a `Intents` sin romper el contrato.
- **Arbitraje central, escritor único.** Los motores *proponen*
  (`TransitionProposal`: `target_state`, `Priority`, `override_weight`,
  `source_id`); `MovementBroker` es el único que decide y el único que
  escribe `LocomotionState`. Esto es lo que permite que agregar un motor
  nuevo (`docs/reference/druid-godot/playbooks/add-a-motor.md`) no toque
  ningún motor existente (§1/§2 arriba).
- **Forma antes que Movement, Combat después.** El orden del pipeline no es
  arbitrario: si Form tickeara después de Movement, este último arbitraría
  un frame con la máscara de motores vieja. Si Combat tickeara antes de
  Movement, sus raycasts de golpe usarían posición pre-movimiento (un frame
  de retraso invisible). Documentado con el motivo en
  `docs/reference/druid-godot/architecture/00-system-map.md` §4.
- **`EntityController` como único punto de fan-out.** Movement, Combat y
  Form no se conocen entre sí lateralmente (§3): todo cruce pasa por el
  padre. Esto es lo que hace que `set_allowed_motors()` (máscara de motores
  por forma) y `inject_forced_proposal()` (interrupción forzada, ej.
  shapeshift a mitad de salto) tengan un solo punto de entrada auditable.
- **Debug: un snapshot por sistema, un solo overlay.** `DebugOverlay`
  (autoload, F1 togglea el panel) recibe `push_data()` de cada
  `BaseDebugContext` por `panel_key` — el mismo patrón para Movement y
  Combat hoy (`MovementBrokerDebugReporter`, `CombatDebugReporter`); Form no
  tiene contexto propio todavía. No hay un segundo sink de texto por
  sistema — evita que HUD y log se contradigan.

## Mapa de módulos

| Módulo | Posee | Frontera |
|---|---|---|
| `scripts/base/` | `Intents`, `TransitionProposal`, `BaseMotor`, `BaseService`, `BodyReader`, `LocomotionStateReader`, `DamageEvent`, `BaseDebugContext` | Contratos puros (§4) y helpers compartidos; nada específico de Movement/Combat/Form vive acá |
| `scripts/player_action_stack/movement/` | `MovementBroker` (único escritor de `LocomotionState`), `motors/*` (un `BaseMotor` por estado), `services/*` (Ground/Ledge/Stairs/Ladder), `PlayerBrain`, `HorseBrain`, `StaminaComponent`, `LocomotionState` | Locomoción; expone `BodyReader`/`LocomotionStateReader`, nunca `Body` ni `LocomotionState` mutable |
| `scripts/player_action_stack/form/` | `FormBroker`, `FormComponent`, `FormReader` | Único dueño del shapeshift; expone máscara de motores y color/escala visual por forma vía `FormReader`, nunca escribe `MovementBroker` directo (§14) |
| `scripts/player_action_stack/combat/` | `CombatBroker`, `BowAction`/`ParryCounterAction`/`PantherTakedownAction`/`StrikeAction` (una acción por forma), `HitPauseComponent` | Resolución de golpes post-movimiento; lee `BodyReader`/`FormReader`, nunca mueve el `Body` |
| `scripts/player_action_stack/camera/` | `CameraRig` | Presentación pura; único dueño de loop declarado además de `MovementBroker`/`VisualsPivot` (§11) |
| `scripts/player_action_stack/` (raíz) | `EntityController` | Fan-out único entre Movement/Form/Combat (§14); sin lógica de gameplay propia |
| `scripts/world/` | `Ladder`, `Stairs`, `CombatDummy`, `ArrowProjectile`, `GrassField` | Geometría/props del mundo y sus contratos de interacción (`apply_damage`, `is_parry_vulnerable`, etc.) |
| `scripts/debug_overlay.gd` (autoload) | Registro de `BaseDebugContext` por `panel_key`, toggle F1 | Sin estado de juego (§12); sólo formatea lo que cada contexto le empuja |

Lo no listado sigue la regla general: posee su dato, lo publica por señal o
`*Reader`, y nadie más lo escribe.
