# Norte — qué estamos construyendo

**Whispers of Freedom** (nombre de trabajo previo: *Druid: Shape-Shifter's
Ritual*) — acción-aventura en tercera persona en Godot 4 (GDScript). Un druida
metamorfo restaura biomas corrompidos alternando entre tres formas —Panther
(sigilo), Monkey (melee rítmico), Avian (arco)— y usa el mismo set de
herramientas para luchar, sanar y reconstruir. (≤200 líneas; visión. Lo
táctico vive en `AHORA.md`, las reglas en `ARCHITECTURE.md`. GDD extendido
original en `docs/reference/druid-godot/human-gdd.md`.)

## Pilares

1. **Movimiento primero** — respuesta instantánea, momentum leve; la stamina
   limita el esfuerzo; escalar/planear se sienten físicos. Referencia: BotW.
2. **Un solo toolkit, tres formas** — Panther, Monkey y Avian no son disfraces
   ni clases separadas: son la misma herramienta aplicada distinto. El cambio
   de forma preserva velocidad, es de un frame, sin pausa de animación.
3. **Combate con identidad por forma** — Panther: takedown mágnetico y
   silencioso. Monkey: parry/counter rítmico con hitpause extremo en el golpe
   perfecto. Avian: arco con carga tensa y caída real.
4. **Restauración como el loop central** — cada zona sigue el arco Entrar →
   Investigar → Infiltrar/Pelear → Ritual → Defender → Gestionar ecosistema →
   Salir. No hay misiones secundarias: restaurar es la misión.
5. **Estado del mundo es visual y sonoro, no UI** — color, densidad de
   partículas y capas de ambiente comunican salud de zona; el HUD es mínimo y
   contextual.
6. **Progresión por uso** — las habilidades mejoran jugándolas (parries más
   anchos, más daño elemental), no por árbol de skills ni grindeo de XP.

## Mundo y narrativa

- Un mundo fracturado por una corrupción morada eldritch; el druida no
  "salva el mundo" en un clímax, restaura zona por zona.
- Sin diálogo de NPC con árbol de quests ni marcadores de misión: la
  investigación y el descubrimiento están embebidos en la exploración.
- Misterio de fondo: por qué algunas zonas restauradas muestran señales de
  re-corrupción — se revela por descubrimiento ambiental, no exposición.

## Dirección visual y sonora

- **Low-poly 3D con proporciones realistas y ancladas** (referencia: Shadow
  of the Colossus), no cartoon. Riqueza por atmósfera —partículas, luz,
  niebla de distancia— no por densidad de geometría.
- **Lenguaje de color por estado de zona**: morado/azul frío = corrupción;
  gris/tierra agrietada = muerte; verde transicional/agua turbia =
  restauración parcial; verde suave + azul claro + calidez = zona viva.
- **Cada elemento tiene firma visual reconocible al instante**: agua
  (celeste fluido), tierra (ámbar, partículas de polvo), viento
  (verde-teal, espirales), fuego (rojo-naranja, calor).
- **UI mínima y diegética cuando sea posible**: stamina por respiración/
  fatiga del personaje, forma por apariencia, salud por animación.
- **Música reactiva, no intrusiva** (referencia: BotW) — responde a acción y
  estado del mundo. Zona muerta = silencio con el zumbido de la corrupción;
  cada capa de vida restaurada suma una capa de audio.

## Mecánicas (orden de prioridad, ver `AHORA.md` para estado real de código)

1. **Movimiento y stamina** — walk/sprint/sneak/jump/fall/climb/mantle/
   auto-vault/wall-jump/edge-leap/stairs/ladder/glide.
2. **Shapeshifting** — swap instantáneo Panther/Monkey/Avian, máscara de
   motores por forma, momentum preservado.
3. **Combate por forma** — Avian: arco de dos fases apuntado. Monkey: parry/
   counter con hitpause. Panther: takedown de sigilo.
4. **Cámara** — tercera persona orbital, apuntado sobre el hombro, lock-on.
5. **Investigación y ritual** — descubrir objetos rituales, minijuego de
   timing musical, cascada de transformación de zona.
6. **Estado de zona** — Dead → Restoring → Alive, gatea Defensa y Ecosistema.
7. **Defensa** — oleadas de corrupción post-ritual (3-5, no infinitas).
8. **Gestión de ecosistema** — colocar agua/semillas/viento/fuego para
   llevar el bioma a autosuficiencia.
9. **Progresión por uso** — parries anchan su ventana, hechizos suben de
   daño, todo por practicarlo.

## Riesgos técnicos conocidos

- **Colisión al cambiar de forma**: Panther/Monkey/Avian tienen shapes
  distintas; un shape nuevo puede solaparse con geometría. Necesita
  ShapeCast de validación antes de aplicar el swap (no implementado aún).
- **Pathfinding de oleada de Defensa** con props de ecosistema dinámicos
  como obstáculos: validar `NavigationServer` con 5-10 enemigos simultáneos.
- **Timing del ritual**: sincronizar `AudioStreamPlayer` con ventanas
  visuales; tolerancia objetivo ±50-100ms.

## Qué NO estamos construyendo

- Árbol de diálogo con quest log ni marcadores de misión.
- Inventario de armas genéricas — las formas y la magia reemplazan armas.
- Crafteo con grindeo de materiales — los objetos rituales se encuentran.
- Gacha, live service, battle pass.

## Decisiones abiertas

- Cantidad y diseño final de biomas/zonas.
- Economía de recursos elementales para la gestión de ecosistema (cuánto
  cuesta cada colocación, si son limitados o regenerables por zona).
- Formato y esquema concreto de save (`user://save_data.json` es el plan,
  sin implementar).
- Alcance de multiplayer co-op (arquitectura listen-server queda abierta a
  futuro; hoy es sólo single-player).
