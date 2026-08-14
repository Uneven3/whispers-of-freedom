class_name GrassField
extends Node3D

## Procedural grass field rendered with a single MultiMeshInstance3D (one draw
## call for all blades) + vertex-shader wind animation on the GPU.
##
## Godot-recommended vegetation technique (see "Optimization using MultiMeshes"
## and "Animating thousands of fish" docs): thousands of instances, one node,
## no per-instance CPU animation, custom_aabb for correct frustum culling.

@export var blade_count: int = 10000:
	set(value):
		blade_count = maxi(1, value)
@export var field_radius: float = 40.0
@export var clump_count: int = 60
@export var clump_spread: float = 8.0
@export var min_blade_height: float = 0.4
@export var max_blade_height: float = 1.0
@export var min_scale: float = 0.7
@export var max_scale: float = 1.4
@export var cast_shadows: bool = false:
	set(value):
		cast_shadows = value
		if _mmi:
			_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not value else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

var _mmi: MultiMeshInstance3D
var _blade_positions: Array[Vector2] = []

func _ready() -> void:
	_build_field()

## Positions the generator computed for each blade (source of truth for the
## distribution). Readable under headless — MultiMesh buffers are not.
func get_blade_positions() -> Array[Vector2]:
	return _blade_positions

## Rebuilds the MultiMesh from current export values. Safe to call at runtime.
func rebuild() -> void:
	if _mmi:
		_mmi.queue_free()
	_mmi = null
	_blade_positions.clear()
	_build_field()

func _build_field() -> void:
	var mesh := _build_blade_mesh()

	# Fixed seed so the field looks the same on every launch (deterministic
	# graybox); tweak or export if you want random variation per run.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = blade_count

	# Clump centers — blades cluster near these for an organic look.
	var clumps: Array[Vector2] = []
	for c in clump_count:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf() * field_radius
		clumps.append(Vector2(cos(angle) * dist, sin(angle) * dist))

	_blade_positions.clear()
	_blade_positions.resize(blade_count)
	for i in blade_count:
		# Pick a clump, then scatter around it with gaussian-ish falloff.
		var center: Vector2 = clumps[rng.randi_range(0, clumps.size() - 1)]
		var offset := Vector2(
			rng.randfn(0.0, clump_spread),
			rng.randfn(0.0, clump_spread)
		)
		var pos2d := center + offset
		pos2d = pos2d.limit_length(field_radius)  # keep blades inside the field
		_blade_positions[i] = pos2d

		var scale := rng.randf_range(min_scale, max_scale)
		var height_frac := (scale - min_scale) / maxf(max_scale - min_scale, 0.001)
		var rot_y := rng.randf_range(0.0, TAU)
		# Random tilt so blades aren't perfectly vertical.
		var tilt := rng.randf_range(-0.12, 0.12)

		var xform := Transform3D(
			Basis(Vector3(0, 1, 0), rot_y) * Basis(Vector3(1, 0, 0), tilt),
			Vector3(pos2d.x, 0.0, pos2d.y)
		).scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, xform)
		# INSTANCE_CUSTOM: x=phase, y=height mult, z=wind mult.
		mm.set_instance_custom_data(i, Color(
			rng.randf_range(0.0, 1.0),
			height_frac,
			rng.randf_range(0.0, 1.0),
			0.0
		))

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Grass"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# MultiMesh has all-or-none instance culling — a correct AABB makes the
	# whole field (and only the field) frustum-culled as one unit.
	_mmi.custom_aabb = AABB(Vector3(-field_radius, 0.0, -field_radius), Vector3(field_radius * 2.0, max_blade_height, field_radius * 2.0))
	add_child(_mmi)

## A single crossed-quad blade (two thin planes) from primitives — graybox has
## no textures, so the shader colors it. Crossed quads read as grass from any
## angle without needing billboarding.
func _build_blade_mesh() -> Mesh:
	var blade := ArrayMesh.new()
	var h := max_blade_height
	var w := 0.08
	var surfaces := []

	# Quad 1 along X.
	surfaces.append(_make_quad(
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(-w, h, 0)
	))
	# Quad 2 along Z (crossed).
	surfaces.append(_make_quad(
		Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, h, w), Vector3(0, h, -w)
	))

	var idx := 0
	for verts: Array in surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
		# Two triangles per quad, counter-clockwise facing out.
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		idx += 1

	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/grass_blade.gdshader")
	blade.surface_set_material(0, mat)
	if blade.get_surface_count() > 1:
		blade.surface_set_material(1, mat)
	return blade

func _make_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Array:
	return [a, b, c, d]

func get_blade_count() -> int:
	var mm := _get_mm()
	return mm.instance_count if mm else 0

func get_custom_aabb() -> AABB:
	return _mmi.custom_aabb if _mmi else AABB()

func _get_mm() -> MultiMesh:
	return _mmi.multimesh if _mmi else null
