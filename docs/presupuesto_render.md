# Presupuesto de render

Decidido 2026-08-20. Este documento fija **cuánto puede costar cada
sistema**, en milisegundos de GPU, y cómo se verifica. No describe
técnicas — para el historial de cómo se llegó acá ver
`docs/pasto_godot.md` (sesiones 17-22).

Regla de uso: cuando algo no entra, **se recorta contenido, no se sube el
presupuesto**. Si el presupuesto se sube, se sube acá, con fecha y motivo.

## El sobre

| decisión | valor | quién decidió |
|---|---|---|
| hardware piso | AMD Radeon Polaris 11 (clase RX 460/560, 2016) | usuario, 2026-08-20 |
| resolución objetivo | 1920×1080 | usuario, 2026-08-20 |
| framerate objetivo | 60 fps → **16,67 ms por frame** | usuario, 2026-08-20 |
| forma del pasto | denso por zonas; el presupuesto se fija contra la **peor zona** | usuario, 2026-08-20 |

El piso de hardware es la máquina de desarrollo, elegido a propósito: si
anda acá, anda en todos lados. No hay factor de conversión supuesto a
hardware más nuevo.

## Por qué milisegundos y no FPS

FPS no es aditivo ni lineal — de 60 a 30 fps se pierden 16,7 ms, de 30 a
20 fps otros 16,7. No se pueden sumar los FPS de dos sistemas; sí se
pueden sumar sus milisegundos. Todas las mediciones de pasto anteriores a
esta decisión (`docs/pasto_godot.md` sesiones 17-20) están en FPS y
primitivos, o sea en unidades que no se reparten en tajadas — por eso
nunca produjeron un presupuesto.

Además, en esta máquina el vsync clava a 60 fps: **por debajo del techo,
FPS no informa nada**. Los ms de GPU sí.

## El reparto

12,3 ms de trabajo sobre 16,67 (74%), 4,37 ms de contingencia (26%). La
contingencia no se gasta: absorbe picos (streaming, un combate cargado,
un frame con muchos VFX) para que no se vean como tirones. La
recomendación estándar es mantener la carga típica cómodamente por debajo
del 70-80% del sobre.

| sistema | asignado | medido hoy | qué falta |
|---|---|---|---|
| terreno Terrain3D (incl. sombra recibida) | 4,5 ms | **9,04 ms** | bajar 2,0x |
| pasto, peor zona | 3,0 ms | **5,06 ms** | bajar 1,7x |
| personajes + enemigos + sus sombras | 2,5 ms | ~0,2 ms | no existe todavía (cápsulas graybox, sin animación) |
| VFX de combate | 1,0 ms | 0 ms | no existe todavía |
| cielo + luz + post + UI | 1,3 ms | ~1,0 ms | dentro de presupuesto |
| **subtotal trabajo** | **12,3 ms** | **15,33 ms** | |
| contingencia | 4,37 ms | — | |
| **total** | **16,67 ms** | | |

Los sistemas que todavía no existen tienen casillero asignado **a
propósito**: es la diferencia entre un presupuesto y una medición. Si no
se reservan ahora, aparecen después como "sorpresa" y el presupuesto se
descubre roto cuando ya es caro arreglarlo.

## Estado: el presupuesto está excedido hoy

15,33 ms medidos contra 12,3 asignados, **con una escena que no tiene
enemigos, ni animación de personaje, ni VFX de combate, ni
post-procesado**. Sobran 1,34 ms sobre el sobre de 60 fps para todo el
juego que falta construir.

El pasto **no** es el problema principal: borrándolo entero quedan 10,3 ms
de terreno + base, que ya es el 62% del sobre.

## Conversiones medidas (Polaris 11 @ 1920×1080)

Medidas con render real fuera del editor, 75-120 muestras por punto,
medianas. Metodología y advertencias abajo.

**Costo por píxel — la escena es fill-bound, no vertex-bound:**

| resolución | MP | GPU ms |
|---|---|---|
| 1152×648 | 0,75 | 6,88 |
| 1280×720 | 0,92 | 8,09 |
| 1920×1080 | 2,07 | 15,31 |

Ajusta a **ms ≈ 2,1 + 6,4 × megapíxeles**, con menos de 1% de error en
los tres puntos. Término fijo chico, todo lo demás proporcional a
píxeles. Consecuencia directa: **bajar triángulos no es la palanca** —
coincide con que las sesiones 17-18 midieran escalado perfecto de
triángulos sin mejora de rendimiento correspondiente.

**Costo del pasto — lineal en cantidad de matas, pero de la malla
equivocada:**

| `blade_count` | GPU ms | delta sobre terreno solo |
|---|---|---|
| 0 | 10,26 | — |
| 1000 | 11,49 | +1,23 |
| 2000 | 12,91 | +2,65 |
| 4000 | 15,30 | +5,04 |
| 8000 | 20,67 | +10,41 |
| 16000 | 30,69 | +20,43 |

**≈ 1,28 ms por cada 1000 matas**, perfectamente lineal en todo el rango
medido — pero esto es `grass_billboard_clump`, la tarjeta con alfa, que
es **la técnica que la sesión 21 concluyó que no va en la capa densa**.
En un régimen fill-bound la diferencia entre alfa y opaco es la variable
dominante (el alfa pierde Early-Z), así que este número no se traslada a
la brizna opaca. La conversión válida está abajo.

**Alfa contra opaco, con la geometría fija** — sin Terrain3D, fondo negro,
suelo plano, cámara a altura de ojos, `field_radius=20`. La columna de ms
es el costo del pasto solo (restada la escena vacía, 0,749 ms), y los
píxeles cubiertos se cuentan sobre 2 073 600 de pantalla:

| malla | material | instancias | ms de pasto | px cubiertos | px/ms |
|---|---|---|---|---|---|
| mata | alfa (atlas) | 4 000 | 6,19 | 651 689 | 105 247 |
| mata | opaco | 4 000 | **0,35** | 722 962 | 2 083 464 |
| mata | alfa (atlas) | 16 000 | 25,70 | 707 998 | 27 549 |
| mata | opaco | 16 000 | **1,04** | 724 223 | 699 732 |
| brizna | alfa (atlas) | 4 000 / 16 000 | 0,30 / 0,86 | **0** | — |
| brizna | opaco | 4 000 | 0,15 | 229 063 | 1 506 993 |
| brizna | opaco | 16 000 | 0,46 | 532 952 | 1 171 323 |
| brizna | opaco | 32 000 | 0,74 | 654 039 | 889 849 |
| brizna | opaco | 64 000 | 1,16 | 709 586 | 611 712 |

Tres cosas salen de acá:

**1. El alfa cuesta entre 18x y 25x, con geometría idéntica.** Misma
malla, mismos vértices, mismas instancias: 6,19 vs 0,35 ms a 4 000
(17,8x) y 25,70 vs 1,04 ms a 16 000 (24,7x). Y la versión opaca cubre
*más* píxeles, porque no recorta nada. El alfa no está comprando
cobertura.

**2. El costo marginal va en direcciones opuestas.** Costo de agregar
1 000 instancias más:

| técnica | tramo | ms por 1 000 extra |
|---|---|---|
| brizna opaca | 4 k → 16 k | 0,025 |
| brizna opaca | 16 k → 32 k | 0,018 |
| brizna opaca | 32 k → 64 k | 0,013 |
| mata con alfa | 4 k → 16 k | 1,63 |

En opaco el costo marginal **baja** a medida que sube la densidad: las
briznas nuevas quedan tapadas por las anteriores y Early-Z las rechaza
antes de sombrearlas. En alfa **sube**, porque sin Early-Z cada capa se
sombrea igual. Es la demostración empírica, en milisegundos y en nuestro
hardware, de por qué la industria reserva el alfa para donde la cantidad
de instancias es naturalmente baja.

**3. La mata opaca no es una opción, es una sonda.** Sale barata porque
son 4 tarjetas grandes sin recorte — pero su silueta *sale del alfa del
atlas*, así que sin alfa se ve como rectángulos sólidos. Está en la tabla
para aislar la variable material, no como propuesta.

**Conversión para el presupuesto**: la capa densa es brizna opaca. En
esta escena de prueba, 64 000 briznas cuestan 1,16 ms y llenan el 34% de
la pantalla (que es donde la cobertura satura con esta cámara). Los 3,0
ms asignados compran holgadamente más densidad de la que satura la vista.

**Y esto ya se cerró, midiendo dentro de la escena real** (2026-08-20,
vía `tools/measure/scene_report.gd -- --grass=opaque`, que enchufa un
instancer con material opaco en lugar del de producción sin tocarlo).
Misma cantidad de instancias (4000), misma dispersión, misma cámara:

| | pasto de producción (alfa) | pasto opaco |
|---|---|---|
| costo del pasto | 5,01 ms | **2,34 ms** |
| capas de overdraw, promedio | 12,92 | **1,40** |
| capas máximas | 25,29 (saturado) | **9,01** |
| % del pasto con 8+ capas | 64,98 % | 0,01 % |
| frame proyectado con lo reservado | 18,38 ms — excedido | 15,66 ms — **dentro** |

**Cambiar la técnica del pasto, sin tocar densidad ni distancia, alcanza
por sí solo para meter el frame dentro del presupuesto**, con 1,01 ms de
contingencia. Pendiente antes de adoptarlo: la comparación es a igual
cantidad de instancias, no a igual densidad visual, y hay que mirarlo
jugado.

## Overdraw, medido (y su techo)

El proyecto daba el overdraw por no medible — `docs/AHORA.md` decía que
"Overdraw es visual, no scripteable". Es falso:
`RenderingServer.viewport_set_debug_draw(rid, VIEWPORT_DEBUG_DRAW_OVERDRAW)`
se activa por script, el framebuffer se lee, y como el modo dibuja con
blend aditivo y un incremento fijo por capa, se pueden **contar capas**.

**Techo duro**: el incremento lo fija el motor y no es configurable. Con
~0,0395 en lineal por capa, el buffer satura a las **~25 capas**, y a
partir de ahí 26 capas y 200 son indistinguibles. Por eso la herramienta
reporta siempre el % de píxeles saturados: si no es ~0, el promedio y el
máximo son **cotas inferiores, no la medición**.

Y no es hipotético: con el pasto de producción **el 10,19% de la pantalla
satura**. En esa zona no sabemos cuánto overdraw hay, sólo que es más de
25 capas.

## El pase de sombras cuesta 1,45 ms (9,7% del frame)

Medido por delta — apagando `shadow_enabled` del `DirectionalLight3D` y
restando GPU ms. **No** se infiere del conteo de primitivas del pase
SHADOW: ese pase es depth-only y cuesta muchísimo menos por primitiva que
el de color, así que los conteos no predicen el costo (misma razón por la
que los triángulos nunca predijeron el costo del pasto).

Los conteos igual sirven como diagnóstico de *qué* se dibuja. Dato
llamativo: el pase de sombras dibuja **más** primitivas (480 568) y más
draw calls (65) que el pase visible (269 792 / 44), y aun así cuesta una
fracción — que es exactamente la demostración de por qué no se pueden
convertir conteos en milisegundos.

## Bug encontrado midiendo: la brizna con el shader del atlas no dibuja nada

`grass_blade_single` renderizada con `scripts/world/grass_blade.gdshader`
cubre **0 píxeles**, medido en las dos densidades. La malla no tiene UV
(se le sacó a propósito en la sesión 20, ver `docs/pasto_godot.md`), así
que samplea el atlas en (0,0), obtiene alfa 0 y descarta cada fragmento.
Cuesta ~0,3-0,86 ms de vértices y no pinta un solo píxel.

Consecuencia: **toda comparación "brizna vs mata" hecha con ese shader
estaba midiendo una brizna invisible contra una mata visible.** Afecta a
partes de las sesiones 17-19 de `docs/pasto_godot.md`. La brizna sólo se
mide bien con material opaco, que es además la técnica que le corresponde.

## Advertencias sobre estos números

- **Una sola vista.** Todo se midió desde la cámara de spawn de
  `terrain_base.tscn`. Un presupuesto serio se fija contra la **vista
  peor caso** representativa, no contra una cómoda. Falta definir cuál es
  esa vista (candidata: la peor zona de pasto denso, mirando al
  horizonte, en el ángulo que maximiza overdraw).
- **Sin viento.** La escena tiene `wind_*`/`sway_*` en 0 — quedaron así
  de las mediciones de la sesión 19. El viento es costo de vertex shader,
  probablemente despreciable en un régimen fill-bound, pero **no está
  medido**.
- **Sin gameplay.** Los números son de una escena estática. Falta medir
  sobre 1-2 minutos de gameplay real recorrido, que es donde aparecen los
  picos que la contingencia tiene que absorber.
- **`clear_by_mesh` en runtime no toca disco** — verificado con
  `git status` limpio después de cada corrida. El guardado de instancias
  de Terrain3D es específico del contexto editor.
- **Dos escenas distintas.** El reparto del presupuesto y las
  conversiones por resolución se midieron en `terrain_base.tscn`; la
  tabla de alfa-contra-opaco se midió sin Terrain3D, con
  `GrassProbeField`. No mezclar los ms absolutos entre las dos.
- **`Terrain3DMeshAsset.set_material_override()` sobre un asset ya
  registrado se ignora** — el primer intento de medir opaco dentro de
  `terrain_base.tscn` falló así, en silencio: los casos "opaco" daban
  exactamente el mismo número que los de alfa. Si dos configuraciones
  distintas miden idéntico, la explicación por defecto es que el cambio
  nunca se aplicó, no que no importe.

## Hipótesis abierta sobre el terreno

Los 9,04 ms del terreno son la tajada más grande y la que más lejos está
de su asignación. Como el escalado con resolución ya demostró que **no**
somos vertex-bound, el sospechoso no es el clipmap ni los LOD de malla,
sino el **costo por píxel del shader de `Terrain3DMaterial`**: hoy está
con todas sus features en default (macro variation, projection/triplanar,
depth blur, dual scaling, noise). Verificable apagándolas de a una y
midiendo ms. No hecho todavía.

## Cuánto cuesta cada cosa que todavía no existe

Medido 2026-08-20 sobre `terrain_base.tscn` con el pasto opaco ya puesto
(base 8,52 ms), a 1920×1080, encendiendo **una cosa por vez** y apagándola
antes de la siguiente, para que cada delta sea atribuible.

| agregado | GPU ms | delta | veredicto |
|---|---|---|---|
| base (escena actual) | 8,52 | — | |
| niebla de profundidad | 8,64 | **+0,12** | prácticamente gratis |
| niebla volumétrica | 9,64 | **+1,11** | asequible, y no depende de la densidad |
| 1 luz omni con sombras | 9,51 | **+0,99** | cada luz con sombras agrega su propio pase |
| 1 luz omni sin sombras | 9,27 | +0,75 | la sombra es sólo 0,24 de eso |
| glow | 11,01 | **+2,48** | caro para lo que aporta |
| SSAO | 15,49 | **+6,97** | inviable: se come el 42% del sobre |
| reflejos en espacio de pantalla | 16,69 | **+8,17** | inviable: solo, ya no entra en 60 fps |

Dos cosas que salen de acá:

**La niebla volumétrica cuesta lo mismo con cualquier densidad** (+1,11 vs
+1,12 al subir a `density = 0.01`). Es costo fijo por frame: una grilla de
froxels que se computa entera independientemente de lo que haya en la
escena. O sea que se paga o no se paga, no se "dosifica".

**SSAO y SSR están fuera de discusión en este hardware.** Cualquiera de los
dos solo cuesta más que todo el resto de la escena junta. Si en algún
momento se quiere oclusión ambiental, tiene que venir horneada o del
gradiente del propio shader, no de un pase de pantalla.

**Partículas: NO MEDIDO.** El intento falló y se deja anotado en vez de
reportar el número: `visible_objetos` se quedó en 88 con 500, 2000 y 8000
partículas, o sea que nunca entraron al conjunto visible (se ubicaron
respecto de una cámara que reportaba posición (0,0,0)). El +0,03 ms que dio
significa "no se dibujó nada". Lo que sí se sabe por teoría y por lo ya
medido con el pasto: las partículas son transparentes y aditivas, así que
**no tienen Early-Z** — su costo va a escalar con píxeles cubiertos por
capas superpuestas, no con la cantidad de partículas. Es exactamente el
mismo régimen que hizo que el pasto con alfa costara 18-25x. Medir con la
cámara real antes de presupuestarlas.

## Flores, arbustos y árboles: ya están medidos, indirectamente

Son el mismo problema que el pasto, y la respuesta ya la tenemos:

- **Flores y arbustos** son capa densa: van opacos, geometría instanciada,
  color por gradiente de vértice. En ese régimen el costo marginal *baja*
  con la densidad (Early-Z rechaza lo tapado) y encima **ocluyen el terreno
  caro**, igual que el pasto opaco, que mide costo negativo.
- **Árboles** son el caso donde el alfa sí se justifica, pero por una razón
  de cantidad, no de técnica: con cientos de instancias en vez de miles, N
  nunca crece lo suficiente para que perder Early-Z duela. Lo que sí van a
  costar es el **pase de sombras**, que hoy ya vale 1,45 ms con sólo terreno
  y pasto.

La regla operativa que sale de todo esto, y que conviene aplicar antes de
agregar cualquier cosa nueva: **¿esto es opaco o transparente?** Si es
opaco, es casi gratis y probablemente ayude. Si es transparente y va a
haber muchos superpuestos, es la categoría que ya nos costó el presupuesto
una vez.

## Cómo se verifica

`tools/measure/scene_report.gd` mide y compara contra este documento:

```
godot --path . --resolution 1920x1080 -s tools/measure/scene_report.gd
godot --path . --resolution 1920x1080 -s tools/measure/scene_report.gd -- --grass=opaque
```

Da ms por capa contra el presupuesto, costo del pase de sombras, overdraw
cuantificado y conteos por pase. El inventario completo y las
contaminaciones que evita están en `tools/measure/README.md`.

Necesita **pantalla real** — bajo `--headless` el driver dummy no
rasteriza y `viewport_get_measured_render_time_gpu()` devuelve 0. Por eso
esto no puede ser un test de GUT: el suite headless no puede ver GPU ms.

Correrlo antes de cerrar cualquier trabajo que agregue geometría, material
o efectos. Un presupuesto que sólo vive en un documento se erosiona —
que es exactamente lo que le pasó a la referencia (`breath-of-freedom`
llegó a que el pasto costara 85% del frame GPU teniendo aplicada toda la
técnica correcta, por no haber fijado nunca un presupuesto de
densidad/distancia y trabajado hacia atrás desde ahí).

## Fuentes

- [Don't Use Frames to Measure Performance](https://medium.com/@polyph4ntom/dont-use-frames-to-measure-performance-bef66c4f4214)
- [Best practices for profiling game performance — Unity](https://unity.com/how-to/best-practices-for-profiling-game-performance)
- [What Is a Frame Time Budget in Optimization?](https://pulsegeek.com/articles/what-is-a-frame-time-budget-in-optimization/)
- [Game Performance Optimization: A Complete Checklist](https://pulsegeek.com/articles/game-performance-optimization-a-complete-checklist/)
- [Advanced Graphics Summit: Procedural Grass in 'Ghost of Tsushima' — GDC 2021](https://gdcvault.com/play/1027033/Advanced-Graphics-Summit-Procedural-Grass)
- [Samurai Landscapes: Building and Rendering Tsushima Island on PS4 — GDC](https://gdcvault.com/play/1027352/Samurai-Landscapes-Building-and-Rendering)
- [Plants, Polygons and Pixels: Large-Scale Vegetation Rendering in Godot — GodotFest](https://godotfest.com/talks/plants-polygons-and-pixels-large-scale-vegetation-rendering-in-godot/)
