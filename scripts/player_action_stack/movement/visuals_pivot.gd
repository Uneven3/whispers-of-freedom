extends Node3D

@export var interpolation_speed: float = 20.0
@onready var _body: CharacterBody3D = get_node_or_null("%Body")
@onready var _mesh: MeshInstance3D = $MeshInstance3D
var _target_y_offset: float = 0.0
var _state_reader: LocomotionStateReader
var _base_mesh_scale: Vector3 = Vector3.ONE

# — Weapon & VFX —
var _staff: MeshInstance3D = null
var _swing_trail: CPUParticles3D = null

func _ready() -> void:
	set_as_top_level(true)
	set_physics_process(false)
	if _mesh:
		_base_mesh_scale = _mesh.scale
	var broker = get_node_or_null("%MovementBroker")
	if broker and broker.has_method("get_state_reader"):
		_state_reader = broker.get_state_reader()

	var combat_broker = get_node_or_null("../CombatBroker")
	if combat_broker and combat_broker.has_signal("combat_state_changed"):
		combat_broker.connect("combat_state_changed", _on_combat_state_changed)
		# Weapon + swing VFX are player combat features — only build them on
		# entities that own a CombatBroker (the horse gets no phantom weapon).
		_setup_weapon()
		_setup_swing_vfx()

func _setup_weapon() -> void:
	_staff = MeshInstance3D.new()
	_staff.name = "Weapon"
	
	var staff_mesh := CylinderMesh.new()
	staff_mesh.top_radius = 0.025
	staff_mesh.bottom_radius = 0.025
	staff_mesh.height = 2.2
	_staff.mesh = staff_mesh
	
	var staff_mat := StandardMaterial3D.new()
	staff_mat.albedo_color = Color(0.48, 0.28, 0.10) # Wood brown
	staff_mat.roughness = 0.7
	_staff.material_override = staff_mat
	
	add_child(_staff)
	
	# Default diagonal carry position on back/hand
	_staff.position = Vector3(0.2, 0.3, -0.3)
	_staff.rotation_degrees = Vector3(0, 45, 90)
	_staff.visible = true

func _setup_swing_vfx() -> void:
	_swing_trail = CPUParticles3D.new()
	_swing_trail.name = "SwingTrailVFX"
	_swing_trail.emitting = false
	_swing_trail.one_shot = true
	_swing_trail.amount = 15
	_swing_trail.lifetime = 0.18
	_swing_trail.explosiveness = 0.95
	_swing_trail.local_coords = true
	
	# Small white spheres representing the wind trail
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.08
	sphere_mesh.height = 0.16
	# Saca desperdicio evidente (~63000 triángulos por golpe a ~720), pero NO
	# es la palanca: el costo real es overdraw, no vértices
	# (docs/movimiento.md, "Visuales").
	sphere_mesh.radial_segments = 6
	sphere_mesh.rings = 3
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mesh.material = mat
	_swing_trail.mesh = sphere_mesh
	
	# Set emission shape to a forward arc
	_swing_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	var points := PackedVector3Array()
	for i in range(12):
		var angle = lerp(-PI / 3.0, PI / 3.0, i / 11.0)
		# Arc of 1.2 meters radius in front of player
		points.append(Vector3(sin(angle) * 1.3, 0.1, -cos(angle) * 1.3))
	_swing_trail.emission_points = points
	
	# Scale curve fading out
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 1.0))
	scale_curve.add_point(Vector2(1, 0.0))
	_swing_trail.scale_amount_curve = scale_curve
	
	# Color curve fading alpha
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1, 1, 1, 0.8))
	color_ramp.set_color(1, Color(1, 1, 1, 0.0))
	_swing_trail.color_ramp = color_ramp
	
	_swing_trail.gravity = Vector3.ZERO
	add_child(_swing_trail)

func _on_combat_state_changed(new_state: StringName) -> void:
	# Trigger swing trail VFX and staff rotation animation on strike
	if new_state in [&"strike_dash", &"strike_swing"]:
		_trigger_swing_vfx()

func _trigger_swing_vfx() -> void:
	if _swing_trail:
		_swing_trail.emitting = true
		_swing_trail.restart()
		
	if _staff:
		# Swing animation: rotate the staff quickly from right to left
		var tween = create_tween()
		_staff.rotation_degrees = Vector3(0, -45, 90)
		tween.tween_property(_staff, "rotation_degrees", Vector3(0, 135, 90), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_staff, "rotation_degrees", Vector3(0, 45, 90), 0.20).set_delay(0.08)

## Explicit loop owner for visual interpolation.
func _process(delta: float) -> void:
	if not is_instance_valid(_body): return
	
	if _state_reader:
		if _state_reader.get_current_mode() == LocomotionState.ID.SNEAK:
			_target_y_offset = -0.4
		else:
			_target_y_offset = 0.0
			
	global_position.x = _body.global_position.x
	global_position.z = _body.global_position.z
	global_position.y = lerpf(global_position.y, _body.global_position.y + _target_y_offset, interpolation_speed * delta)
	# orthonormalized() de los dos lados: Basis.slerp() exige rotaciones puras
	# y el error de punto flotante se acumula hasta que tira (~80 s medidos).
	basis = basis.orthonormalized().slerp(_body.basis.orthonormalized(), interpolation_speed * delta).orthonormalized()
