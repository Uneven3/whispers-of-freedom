extends SceneTree

## Genera el escenario "valle" (heightmap + mallas de agua). Corrida y
## rationale: docs/SISTEMAS.md, sección "Generación de terreno".
## Escribe SOLO a OUT_DIR y aborta si lo apuntan al esculpido a mano.

const OUT_DIR := "res://world_data/terrain_valley"
const PROTECTED_DIR := "res://world_data/terrain"
const GROUND_TEXTURE := "res://art/blender/grass/painterly-meadow-grass-002.png"

# region_size por defecto es 256, NO 1024. Sin change_region_size() una
# imagen de 1024x1024 se parte en 16 regiones de 256 en silencio -- no
# crashea, simplemente no es lo que uno cree que hizo.
const REGION_SIZE := 1024
const MAP := 1024

const PLATEAU_HEIGHT := 140.0
const VALLEY_FLOOR := 20.0
const PLATEAU_END := 280.0
const SLOPE_END := 1000.0

const LAKE_CENTER := Vector2(500.0, 165.0)
const LAKE_RADIUS := 135.0
const LAKE_LEVEL := 132.0
const LAKE_DEPTH := 9.0

const RIVER_HALF_WIDTH := 15.0
const RIVER_BANK := 55.0
const RIVER_DEPTH := 3.2
const RIVER_SAMPLE_STEP := 2.0

## Puntos de control del cauce, del desague del lago al borde sur. Meandros
## suaves a proposito: una curva cerrada hace que la cinta de agua se pliegue
## sobre si misma en el codo.
const RIVER_POINTS: Array[Vector2] = [
	Vector2(500.0, 165.0),
	Vector2(508.0, 300.0),
	Vector2(430.0, 430.0),
	Vector2(470.0, 580.0),
	Vector2(610.0, 700.0),
	Vector2(575.0, 850.0),
	Vector2(640.0, 1023.0),
]

var _noise := FastNoiseLite.new()
var _curve: PackedVector2Array = PackedVector2Array()
var _curve_dist: PackedFloat32Array = PackedFloat32Array()
var _river_length := 0.0
var _heights := PackedFloat32Array()


func _init() -> void:
	if OUT_DIR.rstrip("/").to_lower() == PROTECTED_DIR.rstrip("/").to_lower():
		push_error("generate_valley: la salida apunta al terreno esculpido. Abortado.")
		quit(1)
		return
	# Diferido: en _init() el arbol todavia no esta armado, y Terrain3D no
	# expone su Terrain3DData hasta estar dentro de el.
	_main.call_deferred()


func _main() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = 20260820
	_noise.frequency = 0.0022
	_noise.fractal_octaves = 4

	_build_curve()
	print("curva del rio: %d muestras, %.0f m de largo" % [_curve.size(), _river_length])

	var fields := _build_height_field()
	var heights: PackedFloat32Array = fields["heights"]
	_heights = heights
	print("alturas: min %.1f  max %.1f" % [fields["min"], fields["max"]])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_write_terrain(heights)
	_write_water_meshes()
	print("listo. escenario en ", OUT_DIR)
	quit()


## Remuestreada a paso constante: la distancia acumulada es lo que hace bajar
## el fondo del cauce, y con muestras desparejas el rio bajaria a saltos.
func _build_curve() -> void:
	var raw: PackedVector2Array = PackedVector2Array()
	var count := RIVER_POINTS.size()
	for i in count - 1:
		var p0: Vector2 = RIVER_POINTS[maxi(i - 1, 0)]
		var p1: Vector2 = RIVER_POINTS[i]
		var p2: Vector2 = RIVER_POINTS[i + 1]
		var p3: Vector2 = RIVER_POINTS[mini(i + 2, count - 1)]
		var steps := int(p1.distance_to(p2) / RIVER_SAMPLE_STEP) + 1
		for step in steps:
			raw.append(_catmull_rom(p0, p1, p2, p3, float(step) / float(steps)))
	raw.append(RIVER_POINTS[count - 1])

	_curve = raw
	_curve_dist.resize(raw.size())
	_curve_dist[0] = 0.0
	for i in range(1, raw.size()):
		_curve_dist[i] = _curve_dist[i - 1] + raw[i].distance_to(raw[i - 1])
	_river_length = _curve_dist[_curve_dist.size() - 1]


func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Altura del fondo del cauce a lo largo del rio. Estrictamente decreciente:
## si el fondo subiera en algun tramo, la cinta de agua se veria trepando una
## cuesta, que es el error visual mas obvio que puede tener un rio.
func _channel_bottom(distance_along_river: float) -> float:
	var t: float = clampf(distance_along_river / maxf(_river_length, 1.0), 0.0, 1.0)
	return lerpf(LAKE_LEVEL - RIVER_DEPTH, VALLEY_FLOOR - 6.0, sqrt(t))


func _terrain_base_height(x: float, z: float) -> float:
	var slope: float = smoothstep(PLATEAU_END, SLOPE_END, z)
	var base: float = lerpf(PLATEAU_HEIGHT, VALLEY_FLOOR, slope)
	# Menos relieve en la meseta, para que el lago tenga donde apoyarse.
	var relief: float = lerpf(5.0, 16.0, slope)
	return base + _noise.get_noise_2d(x, z) * relief


## Por estampado, no por busqueda: recorrer las ~350 muestras de la curva
## para cada uno del millon de puntos serian 350 millones de operaciones en
## GDScript. Estampar y quedarse con el minimo da lo mismo, 100x mas barato.
func _stamp_river_field(dist: PackedFloat32Array, param: PackedFloat32Array) -> void:
	var reach := int(ceil(RIVER_BANK))
	for i in _curve.size():
		var p: Vector2 = _curve[i]
		var s: float = _curve_dist[i]
		var x0 := maxi(int(p.x) - reach, 0)
		var x1 := mini(int(p.x) + reach, MAP - 1)
		var z0 := maxi(int(p.y) - reach, 0)
		var z1 := mini(int(p.y) + reach, MAP - 1)
		for z in range(z0, z1 + 1):
			var row := z * MAP
			var dz := float(z) - p.y
			var dz2 := dz * dz
			for x in range(x0, x1 + 1):
				var dx := float(x) - p.x
				var d2 := dx * dx + dz2
				var idx := row + x
				if d2 < dist[idx]:
					dist[idx] = d2
					param[idx] = s


func _build_height_field() -> Dictionary:
	var dist := PackedFloat32Array()
	var param := PackedFloat32Array()
	dist.resize(MAP * MAP)
	param.resize(MAP * MAP)
	dist.fill(1.0e20)
	_stamp_river_field(dist, param)

	var heights := PackedFloat32Array()
	heights.resize(MAP * MAP)
	var lowest := 1.0e20
	var highest := -1.0e20

	for z in MAP:
		var row := z * MAP
		var fz := float(z)
		for x in MAP:
			var fx := float(x)
			var idx := row + x
			var h := _terrain_base_height(fx, fz)

			# --- cuenca del lago ---
			var lake_d := Vector2(fx, fz).distance_to(LAKE_CENTER)
			var lake_t: float = 1.0 - smoothstep(LAKE_RADIUS * 0.55, LAKE_RADIUS, lake_d)
			if lake_t > 0.0:
				# Fondo en cuenco, no plano: el borde sube hacia la orilla.
				var rim_fraction: float = clampf(lake_d / LAKE_RADIUS, 0.0, 1.0)
				var floor_h: float = LAKE_LEVEL - LAKE_DEPTH * (1.0 - rim_fraction * rim_fraction)
				h = lerpf(h, floor_h, lake_t)

			# --- cauce del rio ---
			var distance_to_channel: float = sqrt(dist[idx])
			if distance_to_channel < RIVER_BANK:
				var bottom := _channel_bottom(param[idx])
				var across_channel: float = clampf(distance_to_channel / RIVER_HALF_WIDTH, 0.0, 1.0)
				# Perfil en U dentro del cauce, y mezcla suave hacia el
				# terreno entre el cauce y el borde de la ribera.
				var channel: float = bottom + across_channel * across_channel * 2.5
				# Adentro de la cuenca la ribera se angosta en vez de apagarse:
				# los 55 m de hombro le comian el labio al lago y el agua
				# quedaba colgando, pero apagarla entera tapaba el desague.
				var bank_reach: float = lerpf(RIVER_BANK, RIVER_HALF_WIDTH * 1.5, lake_t)
				var blend: float = 1.0 - smoothstep(RIVER_HALF_WIDTH, bank_reach, distance_to_channel)
				h = lerpf(h, channel, blend)

			heights[idx] = h
			lowest = minf(lowest, h)
			highest = maxf(highest, h)

	return {"heights": heights, "min": lowest, "max": highest}


func _write_terrain(heights: PackedFloat32Array) -> void:
	var terrain: Node = ClassDB.instantiate("Terrain3D")
	# Nunca apuntarlo al directorio esculpido, ni un instante: save_directory()
	# guarda TODAS las regiones cargadas, no solo las modificadas, y se
	# colarian aca. Sin asignarlo, get("data") da null y no hay donde importar.
	terrain.set("data_directory", OUT_DIR)
	root.add_child(terrain)
	terrain.call("change_region_size", REGION_SIZE)

	var image := Image.create_from_data(
		MAP, MAP, false, Image.FORMAT_RF, heights.to_byte_array())

	var data: Object = terrain.get("data")
	if data == null:
		push_error("generate_valley: Terrain3D no expuso su data; abortado sin escribir")
		quit(1)
		return
	# import_images exige un Array de EXACTAMENTE 3 (altura, control, color);
	# los que no se usan van en null. Pasarle un Image suelto es un error de
	# tipo, y un array de 1 elemento lo rechaza explicitamente.
	data.call("import_images", [image, null, null], Vector3.ZERO, 0.0, 1.0)
	data.call("update_maps", 0, true, true)
	data.call("calc_height_range", true)
	data.call("save_directory", OUT_DIR)
	print("regiones escritas: ", data.call("get_region_count") if data.has_method("get_region_count") else "?")

	# Assets propios, nunca el terrain_assets.tres del terreno esculpido:
	# ese recurso es compartido por path, y el @tool del instancer de pasto
	# lo muta en memoria con solo abrir la escena en el editor.
	var assets: Resource = ClassDB.instantiate("Terrain3DAssets")
	var ground: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
	ground.set("name", "Painterly Meadow Grass")
	ground.set("albedo_texture", load(GROUND_TEXTURE))
	assets.call("set_texture", 0, ground)
	var assets_path := OUT_DIR + "/valley_assets.tres"
	ResourceSaver.save(assets, assets_path)
	print("assets propios en ", assets_path)

	terrain.queue_free()


func _write_water_meshes() -> void:
	ResourceSaver.save(_build_lake_mesh(), OUT_DIR + "/lake_mesh.res")
	ResourceSaver.save(_build_river_mesh(), OUT_DIR + "/river_mesh.res")
	print("mallas de agua escritas")


func _sampled_height(x: float, z: float) -> float:
	var xi := clampi(int(round(x)), 0, MAP - 1)
	var zi := clampi(int(round(z)), 0, MAP - 1)
	return _heights[zi * MAP + xi]


## Radio de la orilla en un angulo: donde el terreno generado cruza
## LAKE_LEVEL. Antes la malla usaba un radio fijo y quedaba 28 m adentro del
## cerro por un lado y colgando en el aire por el sur.
func _shore_radius(angle: float) -> float:
	var dir := Vector2(cos(angle), sin(angle))
	var r := 8.0
	# El tope es el radio de la cuenca, no mas: por el cauce del rio el
	# terreno sigue bajo el nivel del lago kilometros, y sin tope la orilla
	# se iba 60 m canal abajo formando dos puas.
	while r < LAKE_RADIUS:
		var p: Vector2 = LAKE_CENTER + dir * r
		if _sampled_height(p.x, p.y) >= LAKE_LEVEL:
			# Un metro pasado el cruce: el borde queda enterrado y el terreno
			# recorta el agua justo en la linea de agua, sin juntura visible.
			return minf(r + 1.0, LAKE_RADIUS)
		r += 0.5
	return -1.0


## Por la boca del rio no hay orilla que encontrar, y sin tapar ese caso el
## lago se derrama 60 m valle abajo. La mediana de los angulos que si
## cruzaron deja el borde donde estaria si la cuenca se cerrara.
func _shore_radii(segments: int) -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	var found: Array[float] = []
	for i in segments:
		var r := _shore_radius(TAU * float(i) / float(segments))
		radii.append(r)
		if r > 0.0:
			found.append(r)
	found.sort()
	var fallback: float = LAKE_RADIUS * 0.8 if found.is_empty() else found[found.size() / 2]
	var patched := 0
	for i in segments:
		if radii[i] < 0.0:
			radii[i] = fallback
			patched += 1
	# Mediana circular de 5: donde el rayo corre por el hombro del cauce el
	# cruce aparece 30 m tarde y sale una pua de 2-3 muestras. La mediana la
	# borra; la forma general del lago, que varia despacio, no se mueve.
	var smoothed := PackedFloat32Array()
	for i in segments:
		var window: Array[float] = []
		for k in range(-2, 3):
			window.append(radii[posmod(i + k, segments)])
		window.sort()
		smoothed.append(window[2])
	print("orilla del lago: %d/%d angulos sin cruce, tapados con %.1f m" % [patched, segments, fallback])
	return smoothed


func _build_lake_mesh() -> ArrayMesh:
	const SEGMENTS := 96
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var center := Vector3(LAKE_CENTER.x, LAKE_LEVEL, LAKE_CENTER.y)
	verts.append(center)
	uvs.append(Vector2(0.5, 1.0))
	normals.append(Vector3.UP)

	var radii := _shore_radii(SEGMENTS)
	for i in SEGMENTS:
		var a := TAU * float(i) / float(SEGMENTS)
		var r := radii[i]
		verts.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
		uvs.append(Vector2(float(i) / float(SEGMENTS), 0.0))
		normals.append(Vector3.UP)

	for i in SEGMENTS:
		indices.append(0)
		indices.append(1 + i)
		indices.append(1 + (i + 1) % SEGMENTS)

	return _commit(verts, uvs, normals, indices)


## Cinta de 3 vertices por seccion (izquierda, centro, derecha) para que UV.y
## sea 0 en las dos orillas y 1 en el medio, que es lo que el shader espera.
## Con 2 vertices por seccion no habria forma de tener centro.
func _build_river_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var count := _curve.size()
	for i in count:
		var p: Vector2 = _curve[i]
		var prev: Vector2 = _curve[maxi(i - 1, 0)]
		var next: Vector2 = _curve[mini(i + 1, count - 1)]
		var tangent := (next - prev)
		if tangent.length() < 0.0001:
			tangent = Vector2(0, 1)
		tangent = tangent.normalized()
		var side := Vector2(-tangent.y, tangent.x) * RIVER_HALF_WIDTH * 0.9
		var y := _channel_bottom(_curve_dist[i]) + RIVER_DEPTH * 0.75
		var uv_along_river := _curve_dist[i] / 40.0

		verts.append(Vector3(p.x - side.x, y, p.y - side.y))
		uvs.append(Vector2(uv_along_river, 0.0))
		verts.append(Vector3(p.x, y, p.y))
		uvs.append(Vector2(uv_along_river, 1.0))
		verts.append(Vector3(p.x + side.x, y, p.y + side.y))
		uvs.append(Vector2(uv_along_river, 0.0))
		for n in 3:
			normals.append(Vector3.UP)

	for i in count - 1:
		var a := i * 3
		var b := (i + 1) * 3
		# izquierda-centro
		indices.append_array([a, b, a + 1, a + 1, b, b + 1])
		# centro-derecha
		indices.append_array([a + 1, b + 1, a + 2, a + 2, b + 1, b + 2])

	return _commit(verts, uvs, normals, indices)


func _commit(verts: PackedVector3Array, uvs: PackedVector2Array,
		normals: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
