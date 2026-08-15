extends SceneTree

## Objective density-per-triangle comparison between GrassField blade variants.
##
## No built-in Godot tool measures this: Performance.get_monitor() reports
## whole-scene aggregates (draw calls, total primitives) that won't
## discriminate a 40k-vs-80k-triangle difference at typical frame budgets,
## and the editor's "Overdraw" debug draw mode is a visual/interactive aid
## (additive-blend overlap), not something scriptable for a repeatable
## number. This is the same kind of instrumentation the sibling
## breath-of-freedom project built for itself (docs/reference/breath-of-
## freedom/BOTWGrass.md's "px/tri" measurement) -- there's no shortcut here,
## someone has to actually render and count.
##
## Must run with a REAL rendering backend, NOT --headless (the dummy driver
## never rasterizes anything, so get_viewport().get_texture() would be
## blank). Run from the repo root with a real display available:
##   godot --path . -s tools/grass_density_probe.gd
##
## Renders each variant, from two camera angles, alone against a solid black
## background. Two angles because a single number can be misleading: a
## bird's-eye view (mostly canopy/top coverage) and a walking-height view
## (closer to how CameraRig's actual third-person camera sees grass) can
## favor different blade designs. The blade shader is unshaded
## (grass_blade.gdshader: ALBEDO = blade_color.rgb, no lighting), so every
## grass pixel is a constant flat color -- "not background" is an exact
## classification here, not a fuzzy heuristic. Triangle count is read from
## each mesh's own index array, not hardcoded, so this stays correct if
## either asset's geometry changes later.
##
## Known limitation, not worth engineering around for an estimate tool: the
## wind shader reads the global TIME uniform, which keeps advancing between
## captures, so each shot samples a slightly different sway phase. The sway
## amplitude is small relative to blade height; treat the numbers as a good
## estimate, not a bit-exact one.

const GrassFieldScript = preload("res://scripts/world/grass_field.gd")

const VARIANT_PATHS: Array[String] = [
	"res://art/blender/grass/grass_blade_single.blend",
	"res://art/blender/grass/grass_blade_tuft.blend",
]

# angle_deg=0 look_at_from_position()'s "up" ambiguity isn't a concern here --
# neither view looks straight down the world Y axis.
const CAMERA_VIEWS := [
	{"name": "birdseye", "position": Vector3(0.0, 9.0, 9.0), "target": Vector3.ZERO},
	{"name": "eyelevel", "position": Vector3(0.0, 1.6, 8.0), "target": Vector3(0.0, 0.3, 0.0)},
]

const BLADE_COUNT := 3000
const FIELD_RADIUS := 6.0
const VIEWPORT_SIZE := Vector2i(480, 360)
const OUTPUT_DIR := "/tmp/grass_density_probe"  # screenshots for a human to sanity-check

var _field: Node3D
var _cam: Camera3D

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_setup_scene()
	call_deferred("_run")

func _setup_scene() -> void:
	# root.size set here (during _init()) is silently overridden by the
	# engine's own window init that happens slightly later -- confirmed by
	# running this: the saved screenshots came out at the project's default
	# window size (1152x648), not VIEWPORT_SIZE. Set it in _run() instead,
	# once the tree is actually running.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	_field = GrassFieldScript.new()
	_field.blade_count = BLADE_COUNT
	_field.field_radius = FIELD_RADIUS
	root.add_child(_field)

func _run() -> void:
	root.size = VIEWPORT_SIZE
	await process_frame

	# results[view_name][variant_name] = px_per_tri
	var results := {}
	for view in CAMERA_VIEWS:
		# look_at() requires the node to already be inside the tree and
		# ready; during _init() it isn't yet (confirmed by running this: it
		# silently left the camera at its default orientation, pointed the
		# wrong way, and every pixel count was measuring nothing
		# meaningful). Use the _from_position() variant, which doesn't
		# depend on tree state -- safe here too even though _run() is later,
		# no reason to rely on the timing working out.
		_cam.look_at_from_position(view["position"], view["target"], Vector3.UP)

		var view_results := {}
		for path in VARIANT_PATHS:
			_field.blade_asset_path = path
			# _queue_rebuild() defers; give it frames to land (same pattern
			# as test_grass_field.gd's live-rebuild tests), plus one extra
			# so the GPU has actually drawn a frame with the new mesh/camera
			# before capture.
			await process_frame
			await process_frame
			await process_frame

			var variant_name := path.get_file().get_basename()
			var image := root.get_viewport().get_texture().get_image()
			image.save_png("%s/%s_%s.png" % [OUTPUT_DIR, view["name"], variant_name])

			var mesh: ArrayMesh = _field.get_node("Grass").multimesh.mesh
			var tris_per_instance := _triangle_count(mesh)
			var total_tris := tris_per_instance * BLADE_COUNT
			var grass_pixels := _count_non_background_pixels(image)
			var px_per_tri := float(grass_pixels) / float(total_tris)

			view_results[variant_name] = px_per_tri
			print("[%s] %s: %d tris/instance, %d total tris submitted, %d grass px, %.4f px/tri" % [
				view["name"], variant_name, tris_per_instance, total_tris, grass_pixels, px_per_tri
			])
		results[view["name"]] = view_results

	print("")
	for view_name in results:
		var view_results: Dictionary = results[view_name]
		var names := view_results.keys()
		if names.size() == 2:
			var a: String = names[0]
			var b: String = names[1]
			var ratio: float = view_results[b] / view_results[a] if view_results[a] > 0.0 else INF
			print("[%s] %s covers %.2fx the pixels per triangle of %s" % [view_name, b, ratio, a])
	print("Screenshots saved to ", OUTPUT_DIR, " -- look at them, these numbers alone aren't the answer.")
	quit()

func _count_non_background_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r > 0.02 or c.g > 0.02 or c.b > 0.02:
				count += 1
	return count

func _triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() / 3
	return total
