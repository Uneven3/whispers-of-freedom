extends Node3D

@export var landing_dip_intensity: float = 0.5
@export var landing_dip_recovery_speed: float = 8.0
@export var mouse_sensitivity: float = 0.003
@export var follow_spring_length: float = 4.0
@export var aim_spring_length: float = 2.25
@export var follow_lens_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
@export var aim_lens_offset: Vector3 = Vector3(0.72, 1.62, 0.0)
@export var follow_fov_degrees: float = 75.0
@export var aim_fov_degrees: float = 56.0
@export var aim_blend_speed: float = 12.0
## Relativo a este rig. Mismo patrón que MovementBroker.brain_path.
@export var entity_controller_path: NodePath = NodePath("../EntityController")

var _current_dip: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_aiming: bool = false

@onready var _entity_controller: Node = get_node_or_null(entity_controller_path)
@onready var _body: CharacterBody3D = (_entity_controller.get_node_or_null("Body") if _entity_controller else null) as CharacterBody3D
@onready var _lens: SpringArm3D = $Lens
@onready var _camera: Camera3D = $Lens/Camera3D
var _reticle_canvas: CanvasLayer
var _reticle_root: Control

func _ready() -> void:
	# Registered visual-update loop owner — _process intentionally always-on (smooth camera interpolation).
	set_as_top_level(true)
	if _body == null:
		push_warning("CameraRig could not resolve %s/Body — camera will not follow" % entity_controller_path)
	var broker = _entity_controller.get_node_or_null("MovementBroker") if _entity_controller else null
	if broker and broker.has_method("get_state_reader"):
		var state_reader = broker.get_state_reader()
		if state_reader:
			state_reader.state_changed.connect(_on_locomotion_state_changed)

	if _entity_controller and _entity_controller.has_node("PlayerBrain"):
		_entity_controller.get_node("PlayerBrain").mouse_motion_received.connect(_on_mouse_motion)
	var combat_broker = _entity_controller.get_node_or_null("CombatBroker") if _entity_controller else null
	if combat_broker and combat_broker.has_signal("aiming_changed"):
		combat_broker.connect("aiming_changed", _on_aiming_changed)
	
	if _lens:
		_lens.spring_length = follow_spring_length
		_lens.position = follow_lens_offset
	if _camera:
		_camera.fov = follow_fov_degrees
	_create_reticle()

func _on_mouse_motion(relative: Vector2) -> void:
	_yaw -= relative.x * mouse_sensitivity
	_pitch -= relative.y * mouse_sensitivity
	_pitch = clampf(_pitch, -1.2, 1.2)

func _process(delta: float) -> void:
	if not is_instance_valid(_body): return
	
	global_position.x = _body.global_position.x
	global_position.z = _body.global_position.z
	
	_current_dip = lerpf(_current_dip, 0.0, landing_dip_recovery_speed * delta)
	
	# Smooth Y to handle stairs, and apply dip
	var target_y: float = _body.global_position.y - _current_dip
	global_position.y = lerpf(global_position.y, target_y, 15.0 * delta)
	
	rotation.y = _yaw
	if _lens:
		_lens.rotation.x = _pitch
		var target_length := aim_spring_length if _is_aiming else follow_spring_length
		var target_offset := aim_lens_offset if _is_aiming else follow_lens_offset
		_lens.spring_length = lerpf(_lens.spring_length, target_length, aim_blend_speed * delta)
		_lens.position = _lens.position.lerp(target_offset, aim_blend_speed * delta)
	if _camera:
		var target_fov := aim_fov_degrees if _is_aiming else follow_fov_degrees
		_camera.fov = lerpf(_camera.fov, target_fov, aim_blend_speed * delta)
	if _reticle_root and _reticle_root.visible:
		_update_reticle_position()

## Estados alcanzables desde FALL que cuentan como aterrizaje para el bajón
## de cámara. Qué queda afuera y por qué: docs/movimiento.md, "Cámara".
const _LANDING_STATES: Array[LocomotionState.ID] = [
	LocomotionState.ID.WALK,
	LocomotionState.ID.SPRINT,
	LocomotionState.ID.STAIRS,
	LocomotionState.ID.SNEAK,
	LocomotionState.ID.LADDER,
]

func _on_locomotion_state_changed(old_mode: int, new_mode: int) -> void:
	if old_mode == LocomotionState.ID.FALL and new_mode in _LANDING_STATES:
		_current_dip += landing_dip_intensity

func _on_aiming_changed(is_aiming: bool) -> void:
	_is_aiming = is_aiming
	if _reticle_root:
		_reticle_root.visible = _is_aiming

func _create_reticle() -> void:
	_reticle_canvas = CanvasLayer.new()
	_reticle_canvas.layer = 20
	add_child(_reticle_canvas)
	_reticle_root = Control.new()
	_reticle_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_root.visible = false
	_reticle_canvas.add_child(_reticle_root)
	_add_reticle_line(Vector2(-18, 0), Vector2(-6, 0))
	_add_reticle_line(Vector2(6, 0), Vector2(18, 0))
	_add_reticle_line(Vector2(0, -18), Vector2(0, -6))
	_add_reticle_line(Vector2(0, 6), Vector2(0, 18))
	_add_reticle_dot()

func _add_reticle_line(from_center: Vector2, to_center: Vector2) -> void:
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(1.0, 0.96, 0.62, 0.92)
	line.points = PackedVector2Array([from_center, to_center])
	line.position = get_viewport().get_visible_rect().size * 0.5
	_reticle_root.add_child(line)

func _add_reticle_dot() -> void:
	var dot := ColorRect.new()
	dot.color = Color(1.0, 0.96, 0.62, 0.92)
	dot.size = Vector2(4, 4)
	dot.position = get_viewport().get_visible_rect().size * 0.5 - Vector2(2, 2)
	_reticle_root.add_child(dot)

func _update_reticle_position() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	for child in _reticle_root.get_children():
		if child is Line2D:
			child.position = center
		elif child is ColorRect:
			child.position = center - child.size * 0.5
