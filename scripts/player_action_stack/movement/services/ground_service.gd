class_name GroundService
extends BaseService

## Proveedor de hechos de piso, de sólo lectura: NUNCA muta el cuerpo, los
## motores son los únicos que escriben. Por qué is_on_floor() del frame
## anterior es la autoridad: docs/movimiento.md, "Suelo".

## Más empinado que esto, medido desde UP, no cuenta como piso. 60° pasa los
## frames de roce con la contrahuella (~27°) y sigue rechazando paredes.
@export var max_slope_angle_deg: float = 60.0

var _is_on_floor: bool      = false
var _floor_normal: Vector3  = Vector3.UP

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func update_facts(body_reader: BodyReader) -> void:
	var body_reports_floor: bool = body_reader.is_on_floor()
	_floor_normal = body_reader.get_floor_normal()
	if body_reports_floor and _floor_normal != Vector3.ZERO:
		var slope_deg: float = rad_to_deg(_floor_normal.angle_to(Vector3.UP))
		_is_on_floor = slope_deg <= max_slope_angle_deg
	else:
		_is_on_floor = body_reports_floor

func is_on_floor() -> bool:
	return _is_on_floor

func get_floor_normal() -> Vector3:
	return _floor_normal
