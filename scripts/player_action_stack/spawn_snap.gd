@tool
class_name SpawnSnap
extends Node

## Apoya al padre en el suelo una vez, al aparecer, contra el Terrain3D del
## grupo "terrain". Que no haya ninguno es un caso normal, no una falla.
## Rationale y las tres trampas de este archivo: docs/movimiento.md, "Spawn".

## Relativo al padre, mismo patrón que MovementBroker.brain_path.
@export var body_reader_source: NodePath = NodePath("../EntityController/MovementBroker"):
	set(value):
		body_reader_source = value
		_queue_snap()
@export var clearance: float = 0.5:
	set(value):
		clearance = value
		_queue_snap()

@export_tool_button("Snap to terrain now")
var snap_now_action: Callable = _snap_to_terrain

## Igual al fallback de BodyReader cuando no encuentra cápsula.
const _DEFAULT_HALF_HEIGHT: float = 1.0

var _ready_done: bool = false
var _snap_queued: bool = false

func _ready() -> void:
	_ready_done = true
	# Un frame: el Terrain3D tiene que terminar de cargar sus regiones y
	# MovementBroker de construir su BodyReader antes de consultarlos.
	await get_tree().process_frame
	_snap_to_terrain()

## Godot escribe cada @export una vez al deserializar: esto los junta en uno.
func _queue_snap() -> void:
	if not _ready_done or _snap_queued:
		return
	_snap_queued = true
	_snap_to_terrain.call_deferred()

func _snap_to_terrain() -> void:
	_snap_queued = false
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain == null:
		return
	var parent := get_parent() as Node3D
	if parent == null:
		return
	if not Engine.is_editor_hint():
		# Sin esto NO HAY COLISION en una sesión de Play y la cápsula cae de
		# largo, sin error (docs/movimiento.md, "La trampa de la colisión").
		# get_node_or_null y no %Camera3D: el atajo tira en vez de dar null.
		var collision_camera: Camera3D = get_node_or_null("%Camera3D") as Camera3D
		if collision_camera:
			terrain.call("set_camera", collision_camera)
	var terrain_data: Object = terrain.get("data")
	if terrain_data == null:
		return
	var height: float = terrain_data.call("get_height", parent.global_position)
	if is_nan(height):
		return
	parent.global_position.y = height + _get_body_half_height() + clearance
	# Todo teletransporte necesita esto con physics_interpolation activo, o
	# los primeros frames muestran al jugador deslizándose desde la posición
	# vieja. El movimiento continuo no.
	parent.reset_physics_interpolation()

func _get_body_half_height() -> float:
	if Engine.is_editor_hint():
		# MovementBroker no es @tool: en el editor es un placeholder y
		# has_method() MIENTE — reporta get_body_reader() pero llamarlo tira.
		return _DEFAULT_HALF_HEIGHT
	var broker: Node = get_node_or_null(body_reader_source)
	if broker == null or not broker.has_method("get_body_reader"):
		return _DEFAULT_HALF_HEIGHT
	var reader: BodyReader = broker.get_body_reader()
	if reader == null:
		return _DEFAULT_HALF_HEIGHT
	return reader.get_body_half_height()
