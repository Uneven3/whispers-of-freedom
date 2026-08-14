# Docs — cómo está organizado esto

**Vivo, autoridad para este proyecto:** `NORTE.md` (visión), `ARCHITECTURE.md`
(leyes + pipeline), `AHORA.md` (bitácora de trabajo). Se actualizan cada
sesión; son los únicos que hay que leer para entender el estado actual.

**`reference/` — archivo de dos proyectos ajenos, no se actualiza más:**

- `reference/druid-godot/` — el proceso de diseño (Constitution, System Map,
  rationale por cluster, mechanic-designs, playbooks, slices) del que salió
  el código actual de `scripts/`. Es la fuente más detallada de *por qué*
  el pipeline Brain/Intents/Broker quedó así, y el GDD completo
  (`human-gdd.md`/`human-gdd-español.md`) del que sale `NORTE.md`.
- `reference/breath-of-freedom/` — docs de un juego hermano en Bevy/Rust
  (otro motor, no aplica directo a GDScript). Referencia de disciplina de
  documentación y del patrón Actor/Intents/Brain en su forma más madura.

Si algo en `NORTE.md`/`ARCHITECTURE.md`/`AHORA.md` contradice lo que dice
`reference/`, manda lo vivo — `reference/` quedó congelado el día que se
archivó.
