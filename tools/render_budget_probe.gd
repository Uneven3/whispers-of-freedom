extends SceneTree

## Mide GPU ms por capa de la escena principal y los compara contra el
## presupuesto de docs/presupuesto_render.md.
##
## NECESITA PANTALLA REAL, no --headless: bajo el driver dummy nada se
## rasteriza y viewport_get_measured_render_time_gpu() devuelve 0. Por eso
## esto es un tool y no un test de GUT -- el suite headless no puede ver
## GPU ms. Misma razon por la que tools/grass_density_probe.gd (borrado,
## ver docs/AHORA.md) tampoco podia correr headless.
##
##   godot --path . --resolution 1920x1080 -s tools/render_budget_probe.gd
##
## La resolucion importa: la escena es fill-bound (ms ~ 2,1 + 6,4 x
## megapixeles), asi que medir en una ventana chica subestima el costo.
## 1920x1080 es la resolucion objetivo declarada en el presupuesto.

const SCENE := "res://scenes/terrain_base.tscn"
const WARMUP := 45
const SAMPLES := 90

## docs/presupuesto_render.md. Si un numero de aca cambia, cambiarlo alla
## primero, con fecha y motivo -- este archivo es el reflejo, no la fuente.
const FRAME_BUDGET_MS := 16.67
const BUDGET := {
	"terreno": 4.5,
	"pasto": 3.0,
	"base (cielo/luz/player/UI)": 1.3,
}
## Reservados para sistemas que todavia no existen; se listan para que el
## total cierre y no aparezcan como sorpresa mas adelante.
const RESERVED := {
	"personajes + enemigos": 2.5,
	"VFX de combate": 1.0,
}

var _frame := 0
var _gpu: Array[float] = []
var _phase := 0
var _measured := {}
var _terrain: Node = null

func _init() -> void:
	root.add_child(load(SCENE).instantiate())
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	process_frame.connect(_on_frame)

func _find(pred: Callable, n: Node) -> Node:
	if pred.call(n):
		return n
	for c in n.get_children():
		var found := _find(pred, c)
		if found != null:
			return found
	return null

func _median(values: Array[float]) -> float:
	values.sort()
	return values[values.size() / 2]

func _on_frame() -> void:
	_frame += 1
	if _frame <= WARMUP:
		return
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	if _gpu.size() < SAMPLES:
		return

	var median := _median(_gpu)
	_gpu.clear()

	match _phase:
		0:
			_measured["total"] = median
			_terrain = _find(func(n): return n.has_method("get_instancer"), root)
			if _terrain == null:
				push_error("render_budget_probe: no Terrain3D node in " + SCENE)
				quit(1)
				return
			# Borrado solo en memoria: verificado que el guardado de
			# instancias de Terrain3D es especifico del contexto editor, o
			# sea correr esto NO ensucia world_data/terrain/*.res.
			for id in _terrain.get_assets().get_mesh_list().size():
				_terrain.get_instancer().clear_by_mesh(id)
		1:
			_measured["sin pasto"] = median
			_terrain.visible = false
		2:
			_measured["base"] = median
			_report()
			quit()
			return
	_phase += 1
	_frame = 0

func _line(label: String, measured: float, budget: float) -> String:
	var over := measured - budget
	var mark := "OK  " if over <= 0.0 else "SOBRE"
	return "  %-5s %-28s %6.2f ms / %5.2f ms  (%+.2f)" % [mark, label, measured, budget, over]

func _report() -> void:
	var total: float = _measured["total"]
	var base: float = _measured["base"]
	var terreno: float = _measured["sin pasto"] - base
	var pasto: float = total - _measured["sin pasto"]

	print("\n=== presupuesto de render (%dx%d) ===" % [root.size.x, root.size.y])
	print("objetivo: %.2f ms/frame (60 fps)\n" % FRAME_BUDGET_MS)
	print(_line("terreno", terreno, BUDGET["terreno"]))
	print(_line("pasto", pasto, BUDGET["pasto"]))
	print(_line("base (cielo/luz/player/UI)", base, BUDGET["base (cielo/luz/player/UI)"]))

	var reserved_total := 0.0
	print("\n  reservado, todavia sin construir:")
	for key in RESERVED:
		reserved_total += RESERVED[key]
		print("        %-28s        %5.2f ms" % [key, RESERVED[key]])

	var assigned := reserved_total
	for key in BUDGET:
		assigned += BUDGET[key]
	var projected := total + reserved_total

	print("\n  medido hoy                     %6.2f ms" % total)
	print("  proyectado con lo reservado    %6.2f ms" % projected)
	print("  trabajo asignado               %6.2f ms" % assigned)
	print("  sobre disponible               %6.2f ms" % FRAME_BUDGET_MS)
	if projected > FRAME_BUDGET_MS:
		print("\n  EXCEDIDO por %.2f ms. Se recorta contenido, no se sube el presupuesto." % (projected - FRAME_BUDGET_MS))
	else:
		print("\n  Dentro del sobre, con %.2f ms de contingencia." % (FRAME_BUDGET_MS - projected))
