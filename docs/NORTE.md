# Norte — qué estamos construyendo

**Whispers of Freedom** — acción-aventura de mundo abierto en Godot 4
(GDScript). Busca el *feeling* de **The Legend of Zelda: Breath of the
Wild** sin nada de la IP de Zelda: mundo, historia, razas y assets propios.
Mismo norte que el proyecto hermano en Bevy/Rust, `breath-of-freedom`
(`docs/reference/breath-of-freedom/NORTE.md`), adaptado a Godot. (≤200
líneas; visión. Táctico en `AHORA.md`, reglas en `ARCHITECTURE.md`.)

**Pivote 2026-08-14:** se descarta la premisa previa (*Druid:
Shape-Shifter's Ritual* — shapeshifting Panther/Monkey/Avian, corrupción
morada, rituales de restauración de zona). El objetivo pasa a ser un solo
personaje con moveset completo, más cerca de BOTW. Detalle de qué código
queda obsoleto por esto en `AHORA.md`.

## Postura legal / IP

- Cero nombres, lore, personajes, música o assets de Zelda.
- Lo "prestado" es mecánico y de sensación (escalada, stamina, glide,
  combate con peso) — no protegible por copyright.
- Referencias de tono/arte (no de assets): BotW, Genshin Impact, Monster
  Hunter Stories 3.

## Pilares

1. **Movimiento primero** — respuesta instantánea con momentum leve; la
   stamina limita el esfuerzo; escalar/nadar/planear se sienten físicos.
2. **Traversal abierto** — casi cualquier superficie es escalable, a un
   costo.
3. **Combate con peso** — lento y deliberado; leer al enemigo importa más
   que la velocidad de input. Un solo personaje, un solo moveset (espada +
   arco + sigilo) — nada gateado por forma ni clase.
4. **Exploración contemplativa** — sin urgencia narrativa impuesta.
5. **Multiplayer desde el día uno** — arquitectura multi-actor
   (`Brain`/`Intents`) y host-autoritativo desde temprano; single-player es
   la misma simulación con un jugador local. Aspiracional: la arquitectura
   ya lo permite (`PlayerBrain`/`HorseBrain` conviven hoy), la red no
   empezó.
6. **UI mínima** — el mundo comunica el estado.

## Mundo y narrativa

- Fantasía, sin humanos; razas inteligentes humanoides (diseño abierto).
- Sin villano ni trama central obligatoria — inspiración *Majora's Mask*:
  personajes con problemas propios que el jugador puede optar por resolver.
- Tono sereno y contemplativo.

## Dirección visual y sonora

- **El norte es el *feeling* de Breath of the Wild, en low-poly.** No su
  fidelidad ni su escala: la sensación — el mundo que invita a caminarlo, el
  pasto que responde, la luz que cambia la hora. Cuando una decisión visual
  esté en duda, la pregunta es *"¿se siente como BOTW?"*, y la respuesta se
  da jugando.
- **Low-poly porque los assets son más fáciles de hacer.** Sin artista
  dedicado, es lo único cost-efficient de autorear. No depende de ninguna
  meta de rendimiento.
- **Dirección artística por sobre fidelidad.** La belleza es *luz + color +
  atmósfera*, no detalle geométrico ni texturas complejas; silueta legible y
  paleta coherente antes que polígonos. Referencias: Journey (norte
  aspiracional), art of rally, Halo 1, WoW Classic, Super Mario 64.
- **Materiales PBR estilizados, inclinados a lo plano**: mate (roughness
  alto, cero metal), color e iluminación mandando por sobre texturas
  complejas.
- Assets de prototipado (graybox: cápsulas, formas primitivas) reemplazables
  sin tocar identidad de gameplay ni colisión.
- Música ambiental minimalista; SFX estilizados.

## Mecánicas (orden de prioridad; ✅/⏳ refleja el código real, ver `AHORA.md`)

1. **Movimiento** ✅ base jugable — walk/sprint/sneak/jump/fall/climb/
   mantle/auto-vault/wall-jump/edge-leap/stairs/ladder/glide. Falta nadar/
   bucear ⏳.
2. **Cámara** ✅ base — tercera persona orbital. Apuntado/lock-on: diseño
   de referencia existe, sin confirmar contra código propio.
3. **Combate** — arco ✅, parry/counter ✅, takedown de sigilo ✅, todos
   ya implementados pero hoy gateados por forma; el trabajo pendiente es
   unificarlos en un solo personaje sin ese gate. Escudo/durabilidad de
   armas ⏳.
4. **Monturas** ✅ horse base (montar; `HorseBrain` ya convive con
   `PlayerBrain` sobre el mismo stack Movement). Diseño final más ambicioso
   queda abierto (criaturas variadas, vínculo personal) sin comprometerse
   todavía.
5. **Mundo y entorno** — hoy sólo graybox (`grass_field`, `entity_base`);
   sin día/noche, sin bosque, sin mundo real construido. Todo ⏳.
6. **Multiplayer** — arquitectura multi-actor ya soporta un `Brain` nuevo
   sin motores nuevos (pilar 5); red sin empezar.
7. **Personajes/problemas** — quests opcionales estilo Majora's Mask, sin
   empezar.

## Detalle mecánico (visión, no todo implementado — ver `AHORA.md`)

- **Arco:** apuntado libre en dos fases, carga estilo Bannerlord (soltar
  rápido = flecha lenta e imprecisa), caída parabólica real.
- **Melee:** pocas armas bien diferenciadas por peso/velocidad/alcance,
  todas con durabilidad.
- **Sigilo:** multiplicador de daño en ataque sorpresa; bonus, no pilar.
- **IA enemiga:** percepción gradual, flanqueo, reacciones grupales y huida
  al estar heridos — nada de esto existe todavía, sólo `CombatDummy`.
- **Traversal:** escalar/planear ✅, nadar/bucear ⏳ (con oxígeno y
  corrientes), snowboard en pendientes ⏳.
- **Clima/día-noche ⏳:** ciclo visual y noche iluminada; frío/calor exigen
  preparación; lluvia moja y afecta el agarre.
- **Crafteo ⏳:** equipo a partir de materiales del mundo.

## Qué NO estamos construyendo

- **Shapeshifting/formas** (Panther/Monkey/Avian) — descartado explícitamente
  en el pivote 2026-08-14; el código que las implementa queda obsoleto.
- Corrupción de zonas, rituales de restauración, gestión de ecosistema —
  descartado con las formas, no se reemplaza por otra premisa de mundo por
  ahora (ver Decisiones abiertas).
- Gacha, live service, battle pass.
- Assets, historia o motor de Zelda.
- Trama principal obligatoria con checklist de misiones.

## Decisiones abiertas

- Licencia del proyecto (breath-of-freedom es GNU GPL — confirmar si
  whispers-of-freedom adopta la misma postura o una distinta).
- Premisa de mundo/narrativa concreta más allá de "fantasía sin villano
  obligatorio" — queda abierta tras descartar corrupción/rituales.
- Número objetivo de jugadores co-op.
- Diseño de razas (cuántas, cuáles, rasgos).
- Estructura del sistema de "problemas resolubles".
- Diseño concreto de monturas (criaturas, domado/vínculo, voladoras).
- Árbol de crafteo/recetas.
- Tamaño del mundo y modelo de persistencia.
- Pipeline concreto de arte propio low-poly (¿Blender, como
  breath-of-freedom?).
