extends Node

signal mouse_motion_received(relative: Vector2)

const WISH_DIR_THRESHOLD: float = 0.5

var _camera_rig: Node3D
var _camera_3d: Camera3D
@onready var _climb_toggle_component: ClimbToggleComponent = $"../ClimbToggleComponent"

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	_camera_rig = get_node_or_null("../../CameraRig")
	_camera_3d = get_node_or_null("../../CameraRig/Lens/Camera3D")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_motion_received.emit(event.relative)
		
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			get_tree().quit() # Allow easy quitting if they press ESC twice

func get_intents() -> Intents:
	var intents: Intents = Intents.new()
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	intents.raw_input = input_dir
	intents.input_strength = input_dir.length()
	
	# Populate wish_dir (discrete semantic intent)
	var wd_x: int = 0
	if input_dir.x > WISH_DIR_THRESHOLD: wd_x = 1
	elif input_dir.x < -WISH_DIR_THRESHOLD: wd_x = -1

	var wd_y: int = 0
	if input_dir.y < -WISH_DIR_THRESHOLD: wd_y = 1 # move_forward is negative Y in get_vector
	elif input_dir.y > WISH_DIR_THRESHOLD: wd_y = -1
	
	intents.wish_dir = Vector2i(wd_x, wd_y)
	
	if _camera_rig and input_dir != Vector2.ZERO:
		var cam_basis: Basis = _camera_rig.global_transform.basis
		var forward: Vector3 = -cam_basis.z
		var right: Vector3 = cam_basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		
		# input_dir.y is negative when moving forward (since move_forward is the -Y axis of get_vector)
		var world_dir: Vector3 = (right * input_dir.x - forward * input_dir.y).normalized()
		intents.move_dir = Vector2(world_dir.x, world_dir.z)
	else:
		intents.move_dir = input_dir
		
	if Input.is_action_pressed("jump"):
		intents.wants_jump = true
		intents.wants_glide = true
	if Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT):
		intents.wants_sprint = true
	
	# Use toggle for climbing
	intents.wants_climb = _climb_toggle_component.is_active() if _climb_toggle_component else false
	
	if Input.is_action_pressed("mantle_debug"):
		intents.wants_mantle = true
	if Input.is_key_pressed(KEY_3):
		intents.wants_vault = true
	if Input.is_key_pressed(KEY_CTRL):
		intents.wants_sneak = true
	if Input.is_action_just_pressed("form_panther"):
		intents.wants_form_shift = &"panther"
	if Input.is_action_just_pressed("form_monkey"):
		intents.wants_form_shift = &"monkey"
	if Input.is_action_just_pressed("form_avian"):
		intents.wants_form_shift = &"avian"
	
	if _camera_3d:
		intents.aim_origin = _camera_3d.global_position
		intents.aim_direction = (-_camera_3d.global_transform.basis.z).normalized()
	elif _camera_rig:
		intents.aim_origin = _camera_rig.global_position
		intents.aim_direction = (-_camera_rig.global_transform.basis.z).normalized()
	
	intents.wants_attack = Input.is_action_just_pressed("combat_attack")
	intents.wants_parry = Input.is_action_just_pressed("combat_parry")
	intents.wants_assassinate = Input.is_action_just_pressed("combat_takedown")
	intents.wants_archery_aim = Input.is_action_pressed("combat_aim")
	intents.wants_archery_release = Input.is_action_just_released("combat_aim") or (
		intents.wants_archery_aim and intents.wants_attack
	)
	return intents
