extends RefCounted

## Muestreo por frame de las metricas de render de un viewport.
## Helper compartido por las herramientas de tools/measure/ para que no
## dupliquen el muestreo ni la estadistica.
##
## NECESITA PANTALLA REAL. Bajo --headless el driver dummy no rasteriza:
## los GPU ms dan 0 y los conteos dan 0. Ver tools/measure/README.md.
##
## Uso:
##   var m = preload("res://tools/measure/frame_metrics.gd").new()
##   m.start(get_tree().root.get_viewport_rid())
##   ... cada frame: m.sample()
##   var r = m.report()   # dict de series -> {mediana, p95, min, max}
##   m.reset()            # para empezar otra fase

## Mediana y percentil, no promedio: un solo frame de compilacion de
## pipeline (Performance.PIPELINE_COMPILATIONS_*) ensucia el promedio de
## una serie corta y no representa el estado estable.

const INFO_TYPES := {
	RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE: "visible",
	RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW: "sombra",
	RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS: "canvas",
}
const INFO_KINDS := {
	RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME: "objetos",
	RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME: "primitivas",
	RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME: "draw_calls",
}

var _viewport: RID
var _series: Dictionary = {}

func start(viewport_rid: RID) -> void:
	_viewport = viewport_rid
	RenderingServer.viewport_set_measure_render_time(_viewport, true)
	reset()

func reset() -> void:
	_series = {}

func sample() -> void:
	_push("gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(_viewport))
	_push("cpu_ms", RenderingServer.viewport_get_measured_render_time_cpu(_viewport))
	for type in INFO_TYPES:
		for kind in INFO_KINDS:
			var key: String = "%s_%s" % [INFO_TYPES[type], INFO_KINDS[kind]]
			_push(key, float(RenderingServer.viewport_get_render_info(_viewport, type, kind)))

func sample_count() -> int:
	return (_series["gpu_ms"] as Array).size() if _series.has("gpu_ms") else 0

func _push(key: String, value: float) -> void:
	if not _series.has(key):
		_series[key] = ([] as Array[float])
	(_series[key] as Array[float]).append(value)

func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := int(round(fraction * float(sorted_values.size() - 1)))
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]

func report() -> Dictionary:
	var out := {}
	for key in _series:
		var values: Array[float] = (_series[key] as Array[float]).duplicate()
		values.sort()
		out[key] = {
			"mediana": _percentile(values, 0.5),
			"p95": _percentile(values, 0.95),
			"min": values[0] if not values.is_empty() else 0.0,
			"max": values[-1] if not values.is_empty() else 0.0,
		}
	return out

## Mediana de una sola serie, que es lo que casi siempre se quiere.
func median(key: String) -> float:
	if not _series.has(key):
		return 0.0
	var values: Array[float] = (_series[key] as Array[float]).duplicate()
	values.sort()
	return _percentile(values, 0.5)
