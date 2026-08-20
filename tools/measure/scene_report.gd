extends SceneTree

## Informe de render de una escena, contra el presupuesto de
## docs/presupuesto_render.md. Reemplaza al viejo tools/render_budget_probe.gd
## (mismas fases de ms, más overdraw, costo de sombras y conteos por pase).
##
## NECESITA PANTALLA REAL, no --headless: bajo el driver dummy nada se
## rasteriza, los GPU ms dan 0 y los conteos dan 0. Por eso esto es un tool
## y no un test de GUT. Ver tools/measure/README.md.
##
##   godot --path . --resolution 1920x1080 -s tools/measure/scene_report.gd
##   godot --path . --resolution 1920x1080 -s tools/measure/scene_report.gd -- --grass=opaque
##
## Argumentos (después de `--`):
##   --scene=res://...   escena a medir (default: scenes/terrain_base.tscn)
##   --grass=opaque|alpha fuerza el material_mode del GrassInstancer
##   --png=/ruta         dónde guardar la captura de overdraw
##   --play              no mide: deja la escena corriendo para jugarla
##
## La resolución importa: la escena es fill-bound (ms ≈ 2,1 + 6,4 x
## megapíxeles), así que medir en ventana chica subestima el costo. 1920x1080
## es la resolución objetivo declarada en el presupuesto.

const FrameMetrics := preload("res://tools/measure/frame_metrics.gd")
const OverdrawProbe := preload("res://tools/measure/overdraw_probe.gd")

const DEFAULT_SCENE := "res://scenes/terrain_base.tscn"
const WARMUP_FRAMES := 45
const SAMPLE_FRAMES := 90

## docs/presupuesto_render.md. Si un número de acá cambia, cambiarlo allá
## primero, con fecha y motivo -- este archivo es el reflejo, no la fuente.
const FRAME_BUDGET_MS := 16.67
const BUDGET := {
	"terreno": 4.5,
	"pasto": 3.0,
	"base (cielo/luz/player/UI)": 1.3,
}
const RESERVED := {
	"personajes + enemigos": 2.5,
	"VFX de combate": 1.0,
}

var _args := {}
var _metrics
var _overdraw
var _terrain: Node = null
var _grass: Node = null
var _lights: Array[DirectionalLight3D] = []

func _init() -> void:
	_main.call_deferred()

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "true"

func _find(pred: Callable, node: Node) -> Node:
	if pred.call(node):
		return node
	for child in node.get_children():
		var found := _find(pred, child)
		if found != null:
			return found
	return null

func _collect_lights(node: Node) -> void:
	if node is DirectionalLight3D:
		_lights.append(node)
	for child in node.get_children():
		_collect_lights(child)

## Pone el GrassInstancer de producción en modo opaco, ANTES de que la
## escena entre al árbol: si se hiciera después, su _ready() ya habría
## plantado las instancias con el material viejo.
##
## Antes esto reemplazaba el nodo por una subclase instrumental. Ya no hace
## falta: TerrainGrassInstancer tiene material_mode propio, así que la
## herramienta mide exactamente el código que se shipea, no un primo suyo.
func _configure_grass(root_node: Node) -> void:
	var grass := _find(
		func(n): return n.name == "GrassInstancer" and n.get_script() != null,
		root_node)
	if grass == null:
		push_warning("scene_report: no hay GrassInstancer que configurar")
		return
	var mode: String = _args.get("grass", "")
	if mode == "opaque":
		grass.material_mode = grass.MATERIAL_OPAQUE
	elif mode == "alpha":
		grass.material_mode = grass.MATERIAL_ATLAS_ALPHA
	if _args.has("blade"):
		grass.blade_asset_path = _args["blade"]
	if _args.has("count"):
		grass.blade_count = int(_args["count"])

## Espera a que el motor termine de compilar pipelines antes de medir.
##
## Un shader nuevo se compila la primera vez que se dibuja, y eso estanca el
## frame -- medido: la escena del valle daba 2 fps y 581 ms de CPU en la
## primera fase, y 101 fps apenas terminaba de compilar. Un warmup de N
## frames fijo no alcanza, porque no se sabe cuantos frames tarda. Hay que
## esperar a que el contador deje de subir.
func _await_pipelines_settled() -> void:
	var last := -1
	var stable := 0
	var waited := 0
	while stable < 30 and waited < 900:
		await process_frame
		waited += 1
		var now := 0
		for monitor in [Performance.PIPELINE_COMPILATIONS_CANVAS,
				Performance.PIPELINE_COMPILATIONS_MESH,
				Performance.PIPELINE_COMPILATIONS_SURFACE,
				Performance.PIPELINE_COMPILATIONS_DRAW,
				Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
			now += int(Performance.get_monitor(monitor))
		if now == last:
			stable += 1
		else:
			stable = 0
			last = now
	if waited >= 900:
		push_warning("scene_report: los pipelines nunca se estabilizaron; la medicion puede incluir picos de compilacion")


func _measure(label: String) -> Dictionary:
	_metrics.reset()
	await _await_pipelines_settled()
	for i in WARMUP_FRAMES:
		await process_frame
	for i in SAMPLE_FRAMES:
		await process_frame
		_metrics.sample()
	return {"label": label, "gpu_ms": _metrics.median("gpu_ms"), "report": _metrics.report()}

func _main() -> void:
	_parse_args()
	var scene_path: String = _args.get("scene", DEFAULT_SCENE)

	_overdraw = OverdrawProbe.new()
	# Calibrar ANTES de cargar la escena: usa un SubViewport propio, así no
	# perturba nada de lo que se va a medir.
	var calibration: Dictionary = await _overdraw.calibrate(self)

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("scene_report: no se pudo cargar " + scene_path)
		quit(1)
		return
	var world := packed.instantiate()
	var grass_mode: String = _args.get("grass", "escena")
	_configure_grass(world)
	root.add_child(world)

	# --play: no mide nada, sólo deja la escena corriendo para jugarla. Es la
	# única forma de VER el pasto opaco sin tocar código de producción --
	# §17: un mecanismo no se valida porque los números den bien, se valida
	# jugándolo.
	if _args.has("play"):
		print("modo --play: escena corriendo con pasto '%s'. Cerrar la ventana para salir." % grass_mode)
		return

	_metrics = FrameMetrics.new()
	_metrics.start(root.get_viewport_rid())

	_terrain = _find(func(n): return n.has_method("get_instancer"), root)
	_grass = _find(
		func(n): return n.get_script() != null and n.name == "GrassInstancer",
		root)
	_collect_lights(root)

	var results := []

	# --- Fase 1: escena completa ---
	var full: Dictionary = await _measure("total")
	results.append(full)

	# --- Fase 2: sin sombras ---
	# El costo del pase de sombras se mide por DELTA de ms, no por el conteo
	# de primitivas del pase SHADOW: el pase de sombra es depth-only y cuesta
	# muchísimo menos por primitiva que el pase de color. Inferir ms desde
	# conteos es exactamente la falacia que este proyecto ya descartó
	# (docs/presupuesto_render.md: "no somos vertex-bound").
	var shadow_states := []
	for light in _lights:
		shadow_states.append(light.shadow_enabled)
		light.shadow_enabled = false
	var no_shadows: Dictionary = await _measure("sin sombras")
	for i in _lights.size():
		_lights[i].shadow_enabled = shadow_states[i]

	# --- Fase 3: sin pasto ---
	# Borrado sólo en memoria: verificado que el guardado de instancias de
	# Terrain3D es específico del contexto editor.
	if _terrain != null:
		for id in _terrain.get_assets().get_mesh_list().size():
			_terrain.get_instancer().clear_by_mesh(id)
	var no_grass: Dictionary = await _measure("sin pasto")

	# --- Fase 4: sin terreno ---
	if _terrain != null:
		_terrain.visible = false
	var empty: Dictionary = await _measure("base")
	if _terrain != null:
		_terrain.visible = true
	if _grass != null:
		_grass.rebuild()

	# --- Fase 5: overdraw, con la escena completa de vuelta ---
	var state = _overdraw.apply(root, _find_environment(root), self)
	for i in 12:
		await process_frame
	var image: Image = root.get_texture().get_image()
	_overdraw.restore(root, state)
	var overdraw_result: Dictionary = _overdraw.analyse(image, calibration["linear_por_capa"])
	var png_path: String = _args.get("png", "/tmp/godot_measure/overdraw.png")
	DirAccess.make_dir_recursive_absolute(png_path.get_base_dir())
	image.save_png(png_path)

	_report(scene_path, grass_mode, calibration, full, no_shadows, no_grass, empty,
		overdraw_result, png_path)
	quit()

func _find_environment(node: Node) -> Environment:
	var we := _find(func(n): return n is WorldEnvironment, node)
	return (we as WorldEnvironment).environment if we != null else null

func _line(label: String, measured: float, budget: float) -> String:
	var over := measured - budget
	var mark := "OK   " if over <= 0.0 else "SOBRE"
	return "  %-5s %-28s %6.2f ms / %5.2f ms  (%+.2f)" % [mark, label, measured, budget, over]

func _report(scene_path: String, grass_mode: String, calibration: Dictionary,
		full: Dictionary, no_shadows: Dictionary, no_grass: Dictionary,
		empty: Dictionary, overdraw_result: Dictionary, png_path: String) -> void:
	var total: float = full["gpu_ms"]
	var base: float = empty["gpu_ms"]
	var terrain: float = no_grass["gpu_ms"] - base
	var grass: float = total - no_grass["gpu_ms"]
	var shadows: float = total - no_shadows["gpu_ms"]

	print("\n=== informe de render ===")
	print("escena:     %s" % scene_path)
	print("pasto:      %s" % grass_mode)
	print("viewport:   %dx%d" % [root.size.x, root.size.y])
	print("objetivo:   %.2f ms/frame (60 fps)" % FRAME_BUDGET_MS)

	print("\n-- presupuesto --")
	print(_line("terreno", terrain, BUDGET["terreno"]))
	print(_line("pasto", grass, BUDGET["pasto"]))
	if grass < 0.0:
		# No es un error de medicion. El pasto opaco se dibuja antes que el
		# terreno (los opacos se ordenan de adelante hacia atras), asi que
		# Early-Z descarta los pixeles de terreno que quedan detras y el caro
		# shader de Terrain3DMaterial nunca corre ahi. Si tapa mas de lo que
		# cuesta, el saldo da negativo: agregar pasto sale GRATIS y ademas
		# ahorra. Con alfa el signo se invierte, porque sin Early-Z el terreno
		# de atras se sombrea igual -- ese cambio de signo es la evidencia.
		print("        (negativo y no es un bug: el pasto opaco ocluye terreno")
		print("         mas caro del que cuesta. Ver README, seccion de oclusion.)")
	print(_line("base (cielo/luz/player/UI)", base, BUDGET["base (cielo/luz/player/UI)"]))

	var reserved_total := 0.0
	print("\n  reservado, todavia sin construir:")
	for key in RESERVED:
		reserved_total += RESERVED[key]
		print("        %-28s        %5.2f ms" % [key, RESERVED[key]])

	var projected := total + reserved_total
	print("\n  medido hoy                     %6.2f ms" % total)
	print("  proyectado con lo reservado    %6.2f ms" % projected)
	print("  sobre disponible               %6.2f ms" % FRAME_BUDGET_MS)
	if projected > FRAME_BUDGET_MS:
		print("\n  EXCEDIDO por %.2f ms. Se recorta contenido, no se sube el presupuesto." % (projected - FRAME_BUDGET_MS))
	else:
		print("\n  Dentro del sobre, con %.2f ms de contingencia." % (FRAME_BUDGET_MS - projected))

	print("\n-- costo del pase de sombras (por delta de ms, no por conteos) --")
	print("  con sombras                    %6.2f ms" % total)
	print("  sin sombras                    %6.2f ms" % no_shadows["gpu_ms"])
	print("  el pase de sombras cuesta      %6.2f ms  (%.1f %% del frame)" % [
		shadows, 100.0 * shadows / total if total > 0.0 else 0.0])

	print("\n-- overdraw --")
	print("  calibracion: 1 capa = %.4f lineal; el buffer satura a las %.1f capas" % [
		calibration["linear_por_capa"], calibration["capas_hasta_saturar"]])
	print(_overdraw.format(overdraw_result))
	print("  captura: %s" % png_path)

	print("\n-- conteos por pase (diagnostico, NO son costo) --")
	var series: Dictionary = full["report"]
	for key in ["visible_draw_calls", "visible_primitivas", "visible_objetos",
			"sombra_draw_calls", "sombra_primitivas", "sombra_objetos"]:
		if series.has(key):
			print("  %-22s %12d" % [key, int(series[key]["mediana"])])

	print("\n-- estabilidad --")
	print("  gpu_ms  mediana %.2f   p95 %.2f   max %.2f" % [
		series["gpu_ms"]["mediana"], series["gpu_ms"]["p95"], series["gpu_ms"]["max"]])
	print("  cpu_ms  mediana %.2f" % series["cpu_ms"]["mediana"])
	print("  memoria de video %.1f MB" % (
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0))
