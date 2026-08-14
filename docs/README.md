# Docs — cómo está organizado esto

**Vivo, autoridad para este proyecto:** `NORTE.md` (visión), `ARCHITECTURE.md`
(leyes + pipeline), `SISTEMAS.md` (catálogo de sistemas mapeados a Godot),
`AHORA.md` (bitácora de trabajo). Documentación lean a propósito — el código
es el complemento, no hace falta duplicar en prosa lo que ya se lee en
`scripts/`.

**`reference/breath-of-freedom/`** — docs de un juego hermano en Bevy/Rust
(otro motor, no aplica directo a GDScript). Referencia de disciplina de
documentación y del patrón Actor/Intents/Brain en su forma más madura; no se
actualiza más.

**`reference/druid-godot/` ya no existe.** De ahí salió el código actual
(Movement/Combat/Camera, patrón Brain/Intents/Broker), pero al pivotear
lejos de su premisa (shapeshifting Panther/Monkey/Avian, corrupción/
rituales — ver "Pivote 2026-08-14" en `AHORA.md`) se revisó todo su
contenido a fondo: nada sobrevivió como archivo aparte — o ya estaba
destilado en `ARCHITECTURE.md`, o era diseño especulativo que el código
real nunca siguió, o era proceso de otro repo sin valor acá. Las dos
trampas reales que sí valían la pena quedaron como texto dentro de
`ARCHITECTURE.md` §2 y su rationale. Todo lo demás se mandó a la papelera
el 2026-08-14 — recuperable en `git log` si hace falta.

Si algo en `NORTE.md`/`ARCHITECTURE.md`/`AHORA.md` contradice lo que dice
`reference/breath-of-freedom/`, manda lo vivo.
