extends RefCounted

## Cuantifica overdraw (cuantas veces se sombrea cada pixel) leyendo el modo
## de depuracion OVERDRAW del propio motor y contando capas.
##
## El proyecto venia dando esto por imposible -- docs/AHORA.md decia que
## "Overdraw es visual, no scripteable". Es falso:
## RenderingServer.viewport_set_debug_draw(rid, VIEWPORT_DEBUG_DRAW_OVERDRAW)
## se puede activar por script, y el framebuffer resultante se puede leer.
##
## NECESITA PANTALLA REAL y build de debug. El modo OVERDRAW es el unico
## debug_draw que no funciona en builds de release.
##
## COMO FUNCIONA: en modo overdraw el motor dibuja todo con blend aditivo y
## un incremento fijo por capa. Sumando capas, el valor de un pixel es
## (capas x incremento). El readback viene codificado en sRGB, asi que hay
## que linealizarlo antes de dividir -- sin eso, 2 capas parecen 1,4.
##
## LIMITE DURO -- SATURACION: el incremento por capa lo fija el motor y no
## es configurable. Con ~0,04 en lineal por capa, el buffer se clava en 1,0
## alrededor de las 25 capas y a partir de ahi 26 capas y 200 capas son
## indistinguibles. Justo la zona de pasto denso es donde eso pasa, asi que
## esta herramienta SIEMPRE reporta el % de pixeles saturados: si ese
## numero no es ~0, el promedio y el maximo estan subestimados y no se
## deben citar como si fueran la medicion.

const SATURATION_EPSILON := 0.002
## Tamano del viewport de calibracion. Chico a proposito: sólo hace falta
## que entre el quad, y la lectura es por CPU.
const CALIBRATION_SIZE := Vector2i(64, 64)

var _srgb_to_linear: PackedFloat32Array = PackedFloat32Array()

func _init() -> void:
	# Tabla de 256 entradas: linealizar 2 millones de pixeles llamando a
	# Color.srgb_to_linear() uno por uno es inviable en GDScript.
	_srgb_to_linear.resize(256)
	for i in 256:
		var c := float(i) / 255.0
		_srgb_to_linear[i] = (
			c / 12.92 if c <= 0.04045
			else pow((c + 0.055) / 1.055, 2.4))

## Estado del viewport y del Environment que hay que forzar para medir, y
## restaurar despues. Sin restaurar, una fase posterior mediria GPU ms con
## el debug draw puesto en OVERDRAW -- un pase mucho mas barato que el
## shading real, o sea un numero creible y falso.
class ViewportState extends RefCounted:
	var debug_draw: int
	var msaa_3d: int
	var environment: Environment
	var tonemap_mode: int
	var glow_enabled: bool
	var adjustment_enabled: bool
	var hidden_canvas_layers: Array[CanvasLayer] = []

func apply(viewport: Viewport, env: Environment, tree: SceneTree = null) -> ViewportState:
	var state := ViewportState.new()
	state.debug_draw = viewport.debug_draw
	state.msaa_3d = viewport.msaa_3d
	state.environment = env

	# El debug draw NO afecta a los CanvasLayer: el DebugOverlay (autoload,
	# F1) se dibuja encima de la escena 3D y sus pixeles de texto entran al
	# histograma como si fueran capas de geometria. Verificado mirando la
	# captura, no deducido. Se ocultan para medir y se restauran despues.
	if tree != null:
		_hide_canvas_layers(tree.root, state)

	viewport.debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
	# MSAA promedia subsamples en el resolve: los bordes quedarian con
	# conteos fraccionarios de capa que no son overdraw real sino artefacto.
	# project.godot tiene msaa_3d=1 (2x), asi que esto importa de verdad.
	viewport.msaa_3d = Viewport.MSAA_DISABLED

	if env != null:
		state.tonemap_mode = env.tonemap_mode
		state.glow_enabled = env.glow_enabled
		state.adjustment_enabled = env.adjustment_enabled
		# Con tonemap filmic (terrain_base.tscn usa tonemap_mode=2) la suma
		# aditiva deja de ser lineal y el conteo de capas da cualquier cosa.
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.glow_enabled = false
		env.adjustment_enabled = false
	return state

func _hide_canvas_layers(node: Node, state: ViewportState) -> void:
	if node is CanvasLayer and (node as CanvasLayer).visible:
		state.hidden_canvas_layers.append(node)
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas_layers(child, state)

func restore(viewport: Viewport, state: ViewportState) -> void:
	viewport.debug_draw = state.debug_draw
	viewport.msaa_3d = state.msaa_3d
	for layer in state.hidden_canvas_layers:
		if is_instance_valid(layer):
			layer.visible = true
	if state.environment != null:
		state.environment.tonemap_mode = state.tonemap_mode
		state.environment.glow_enabled = state.glow_enabled
		state.environment.adjustment_enabled = state.adjustment_enabled

## Mide cuanto vale UNA capa, en vez de hardcodear la constante: el
## incremento por capa es un detalle interno del motor y puede cambiar entre
## versiones. Se calibra en un SubViewport propio para no perturbar la
## escena que se esta midiendo.
func calibrate(tree: SceneTree) -> Dictionary:
	var sub := SubViewport.new()
	sub.size = CALIBRATION_SIZE
	sub.own_world_3d = true
	sub.world_3d = World3D.new()
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(sub)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	sub.add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 2)
	cam.current = true
	sub.add_child(cam)

	# Un quad grande y de frente: cubre el centro del viewport con
	# exactamente una capa.
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mi.material_override = mat
	sub.add_child(mi)

	for i in 6:
		await tree.process_frame

	var img: Image = sub.get_texture().get_image()
	var per_layer := _modal_nonzero_linear(img)
	sub.queue_free()

	return {
		"linear_por_capa": per_layer,
		"capas_hasta_saturar": (1.0 / per_layer) if per_layer > 0.0 else 0.0,
	}

## El valor lineal no-nulo mas frecuente en el quad de calibracion es una
## capa. Modal y no minimo: un minimo se lo lleva cualquier pixel de borde.
func _modal_nonzero_linear(img: Image) -> float:
	var counts := {}
	var data := img.get_data()
	var stride := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
	var i := 0
	while i < data.size():
		var byte := data[i]
		if byte > 0:
			counts[byte] = counts.get(byte, 0) + 1
		i += stride
	var best_byte := 0
	var best_count := 0
	for byte in counts:
		if counts[byte] > best_count:
			best_count = counts[byte]
			best_byte = byte
	return _srgb_to_linear[best_byte] if best_byte > 0 else 0.0

## Analiza una captura ya hecha en modo overdraw.
## linear_per_layer viene de calibrate().
func analyse(img: Image, linear_per_layer: float) -> Dictionary:
	if linear_per_layer <= 0.0:
		return {"error": "calibracion invalida"}

	var data := img.get_data()
	var stride := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
	var total_pixels := img.get_width() * img.get_height()

	# Histograma sobre los 256 valores posibles del canal rojo: barato y
	# exacto, en vez de recorrer pixeles dos veces.
	var hist := PackedInt32Array()
	hist.resize(256)
	var i := 0
	while i < data.size():
		hist[data[i]] += 1
		i += stride

	var covered := 0
	var saturated := 0
	var layer_sum := 0.0
	var max_layers := 0.0
	var over_4 := 0
	var over_8 := 0
	for byte in 256:
		var count := hist[byte]
		if count == 0 or byte == 0:
			continue
		var linear := _srgb_to_linear[byte]
		var layers := linear / linear_per_layer
		covered += count
		layer_sum += layers * float(count)
		max_layers = maxf(max_layers, layers)
		if linear >= 1.0 - SATURATION_EPSILON:
			saturated += count
		if layers >= 4.0:
			over_4 += count
		if layers >= 8.0:
			over_8 += count

	return {
		"pixeles_totales": total_pixels,
		"pixeles_cubiertos": covered,
		"cobertura_pct": 100.0 * float(covered) / float(total_pixels),
		"capas_promedio_sobre_cubierto": (layer_sum / float(covered)) if covered > 0 else 0.0,
		"capas_promedio_sobre_pantalla": layer_sum / float(total_pixels),
		"capas_max": max_layers,
		"pct_cubierto_sobre_4_capas": 100.0 * float(over_4) / float(covered) if covered > 0 else 0.0,
		"pct_cubierto_sobre_8_capas": 100.0 * float(over_8) / float(covered) if covered > 0 else 0.0,
		"pixeles_saturados": saturated,
		"pct_saturado": 100.0 * float(saturated) / float(total_pixels),
		"medicion_confiable": saturated == 0,
	}

func format(result: Dictionary) -> String:
	if result.has("error"):
		return "  overdraw: " + str(result["error"])
	var lines := [
		"  cobertura de geometria       %6.2f %% de la pantalla" % result["cobertura_pct"],
		"  capas promedio (donde hay geometria) %6.2f" % result["capas_promedio_sobre_cubierto"],
		"  capas promedio (pantalla)    %6.2f" % result["capas_promedio_sobre_pantalla"],
		"  capas maximas                %6.2f" % result["capas_max"],
		"  %% del pasto con 4+ capas     %6.2f %%" % result["pct_cubierto_sobre_4_capas"],
		"  %% del pasto con 8+ capas     %6.2f %%" % result["pct_cubierto_sobre_8_capas"],
	]
	if result["medicion_confiable"]:
		lines.append("  sin pixeles saturados: la medicion vale.")
	else:
		lines.append("  SATURADO en %.2f %% de la pantalla (%d px)." % [
			result["pct_saturado"], result["pixeles_saturados"]])
		lines.append("  El promedio y el maximo de arriba son COTAS INFERIORES,")
		lines.append("  no la medicion: por encima del techo del buffer el motor")
		lines.append("  no distingue 26 capas de 200.")
	return "\n".join(lines)
