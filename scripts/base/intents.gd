class_name Intents
extends RefCounted

# -- Internal Data (Populated by Brain) --
var move_dir: Vector2 = Vector2.ZERO   # The normalized direction in 3D (Z/X)
var raw_input: Vector2 = Vector2.ZERO  # Raw hardware vector
var wish_dir: Vector2i = Vector2i.ZERO # Discrete: x (Left/Right), y (Forward/Back)
var input_strength: float = 0.0        # 0.0 to 1.0 magnitude
var aim_origin: Vector3 = Vector3.ZERO
var aim_direction: Vector3 = Vector3.ZERO

# -- Semantic Getters (Ground Context) --
var is_moving_forward: bool:
	get:
		return wish_dir.y == 1
var is_moving_back: bool:
	get:
		return wish_dir.y == -1
var is_moving_left: bool:
	get:
		return wish_dir.x == -1
var is_moving_right: bool:
	get:
		return wish_dir.x == 1

# -- Semantic Getters (Climb/Wall Context) --
var is_climbing_up: bool:
	get:
		return wish_dir.y == 1
var is_climbing_down: bool:
	get:
		return wish_dir.y == -1
var is_climbing_left: bool:
	get:
		return wish_dir.x == -1
var is_climbing_right: bool:
	get:
		return wish_dir.x == 1

# -- Action Triggers --
var wants_jump: bool = false
var wants_sprint: bool = false
var wants_sneak: bool = false
var wants_climb: bool = false
var wants_mantle: bool = false
var wants_vault: bool = false
var wants_glide: bool = false
var wants_attack: bool = false
var wants_parry: bool = false
var wants_archery_aim: bool = false
var wants_archery_release: bool = false
var wants_assassinate: bool = false

func reset() -> void:
	move_dir = Vector2.ZERO
	raw_input = Vector2.ZERO
	wish_dir = Vector2i.ZERO
	input_strength = 0.0
	aim_origin = Vector3.ZERO
	aim_direction = Vector3.ZERO
	
	wants_jump = false
	wants_sprint = false
	wants_sneak = false
	wants_climb = false
	wants_mantle = false
	wants_vault = false
	wants_glide = false
	wants_attack = false
	wants_parry = false
	wants_archery_aim = false
	wants_archery_release = false
	wants_assassinate = false
