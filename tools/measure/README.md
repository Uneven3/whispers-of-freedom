# Herramientas de medición

Miden una escena contra `docs/presupuesto_render.md`. **No son código de
juego** — nada de acá se carga en una partida, por eso viven en `tools/` y
no en `scripts/`.

## Ninguna corre headless, y no es un descuido

Bajo `--headless` Godot usa el driver de render dummy: no rasteriza nada, así
que los GPU ms dan 0, los conteos dan 0 y el modo overdraw no dibuja. No hay
flag que lo arregle. Por eso esto no puede ser un test de GUT — el suite
headless no puede ver ninguna de estas métricas.

Las corridas abren una ventana real. Si molesta, la alternativa sería
instalar `xorg-server-xvfb` y usar `xvfb-run -a godot ...`; no está instalado
y es decisión de la persona, no del asistente.

## Uso

```
godot --path . --resolution 1920x1080 -s tools/measure/scene_report.gd
godot --path . --resolution 1920x1080 -s tools/measure/scene_report.gd -- --grass=opaque
```

Argumentos, después de `--`:

| argumento | qué hace |
|---|---|
| `--scene=res://...` | escena a medir (default `scenes/terrain_base.tscn`) |
| `--grass=opaque` | reemplaza el `GrassInstancer` por el probe de material opaco |
| `--blade=res://...` | malla de pasto a usar en modo opaco |
| `--count=N` | cantidad de instancias en modo opaco |
| `--png=/ruta` | dónde guardar la captura de overdraw |

**La resolución no es opcional.** La escena es fill-bound
(`ms ≈ 2,1 + 6,4 × megapíxeles`), así que medir en ventana chica subestima el
costo. 1920×1080 es la resolución objetivo declarada en el presupuesto.

## Los archivos

| archivo | qué es |
|---|---|
| `scene_report.gd` | el comando único. Reemplazó a `tools/render_budget_probe.gd` |
| `frame_metrics.gd` | muestreo por frame + estadística (mediana, p95) |
| `overdraw_probe.gd` | cuantificación de overdraw |
| `grass_instancer_probe.gd` | variante del instancer que planta pasto opaco |
| `grass_opaque_probe.gdshader` | shader opaco, sin atlas ni alfa |

## Qué mide y qué NO mide

**Costo en milisegundos, por diferencia.** El costo de cada capa (terreno,
pasto, sombras) sale de apagar esa capa y restar GPU ms — nunca de inferirlo
desde conteos de primitivas. Inferir ms desde primitivas es la falacia que
este proyecto ya midió y descartó: la escena no es vertex-bound, así que las
primitivas no predicen el costo.

**Los conteos por pase son diagnóstico, no costo.** `viewport_get_render_info()`
separa draw calls / primitivas / objetos entre el pase visible y el de
sombras. Sirve para entender *qué* se está dibujando, no *cuánto cuesta*: el
pase de sombras es depth-only y cuesta muchísimo menos por primitiva que el
de color. El costo real de las sombras se mide apagando `shadow_enabled`.

**Overdraw, con un techo duro.** El modo `DEBUG_DRAW_OVERDRAW` dibuja con
blend aditivo y un incremento fijo por capa (~0,04 en lineal, calibrado en
cada corrida y no hardcodeado). Eso significa que el buffer **satura
alrededor de las 25 capas**, y por encima de ese techo el motor no distingue
26 capas de 200. La herramienta siempre reporta el % de píxeles saturados: si
no es ~0, el promedio y el máximo son **cotas inferiores**, no la medición.
En el pasto con alfa de producción, el 10% de la pantalla satura — o sea que
ahí el número real de capas es desconocido y mayor que el reportado.

## Contaminaciones que la herramienta ya evita

Todas encontradas midiendo, no razonando:

- **MSAA** (`project.godot` tiene `msaa_3d=1`) promedia subsamples en el
  resolve y mete conteos fraccionarios de capa en los bordes. Se desactiva
  durante la captura.
- **Tonemap** — `terrain_base.tscn` usa filmic (`tonemap_mode=2`). Con un
  tonemap no lineal la suma aditiva deja de ser lineal y el conteo de capas
  da cualquier cosa. Se fuerza a lineal.
- **sRGB** — el readback viene codificado. Sin linealizar, 2 capas parecen
  1,4.
- **El overlay de debug** (`DebugOverlay`, autoload) se dibuja en un
  `CanvasLayer` encima del 3D, y el debug draw no lo afecta: sus píxeles de
  texto entraban al histograma como si fueran geometría. Se ocultan durante
  la captura.
- **Restaurar entre fases** — si la fase de overdraw no restaurara el
  `debug_draw`, una fase posterior mediría GPU ms con el modo overdraw
  puesto, que es un pase mucho más barato que el shading real. Número creíble
  y falso.

## Mirar las capturas, no sólo los números

`scene_report.gd` guarda la captura de overdraw en `/tmp/godot_measure/`.
Mirarla es parte del método, no un extra: la contaminación del overlay de
debug se encontró mirando la imagen, no leyendo la tabla. Es el mismo
precedente del viejo `tools/grass_density_probe.gd`, que guardaba capturas
porque el número solo no alcanza.

## Perfilado más profundo, si alguna vez hace falta

El RADV de esta máquina tiene compilado el soporte de trazas SQTT
(`MESA_VK_TRACE`, `MESA_VK_TRACE_FRAME`, `RADV_THREAD_TRACE_INSTRUCTION_TIMING`).
Eso permite capturar timing por draw y ocupación de waves a nivel hardware,
que es lo único que contestaría de verdad "por qué este shader es caro". Sólo
faltaría el visor RGP de AMD. No hace falta hoy: el cuello de botella ya está
localizado por diferencia de ms.
