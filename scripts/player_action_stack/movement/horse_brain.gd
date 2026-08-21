extends Node

## Brain del caballo de graybox. Controles propios para no competir con WASD:
## I/K adelante-atrás, J/L strafe, U salto, O sprint. Sin formas ni combate.

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func get_intents() -> Intents:
	var intents: Intents = Intents.new()
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_I): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_K): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_J): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_L): input_dir.x += 1.0
	intents.raw_input = input_dir
	intents.input_strength = input_dir.length()
	intents.move_dir = input_dir
	if Input.is_key_pressed(KEY_U):
		intents.wants_jump = true
	if Input.is_key_pressed(KEY_O):
		intents.wants_sprint = true
	return intents
