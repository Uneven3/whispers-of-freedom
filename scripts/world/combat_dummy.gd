class_name CombatDummy
extends StaticBody3D

signal damage_received(event: RefCounted)
signal defeated()

@export var max_health: float = 150.0
@export var auto_telegraph: bool = true
@export var telegraph_interval: float = 2.2
@export var parry_window: float = 0.28

var _current_health: float = 150.0
var _is_parry_vulnerable: bool = false
var _defeated: bool = false
var _base_material: StandardMaterial3D
var _mesh: MeshInstance3D
var _telegraph_timer: Timer
var _window_timer: Timer

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	add_to_group("combat_target")
	_current_health = max_health
	_mesh = get_node_or_null("MeshInstance3D")
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = Color(0.55, 0.58, 0.62)
	if _mesh:
		_mesh.material_override = _base_material
	_setup_timers()

func apply_damage(event: RefCounted) -> void:
	if _defeated or not event:
		return
	_current_health = maxf(0.0, _current_health - event.amount)
	damage_received.emit(event)
	_flash(Color(0.95, 0.18, 0.10))
	if _current_health <= 0.0:
		_defeated = true
		_is_parry_vulnerable = false
		_flash(Color(0.10, 0.10, 0.10))
		defeated.emit()

func is_defeated() -> bool:
	return _defeated

func get_current_health() -> float:
	return _current_health

func is_parry_vulnerable() -> bool:
	return _is_parry_vulnerable and not _defeated

func consume_parry() -> void:
	_is_parry_vulnerable = false
	_flash(Color(0.20, 0.85, 0.95))

func can_be_takedown(_source_position: Vector3) -> bool:
	return not _defeated

func reset_dummy() -> void:
	_current_health = max_health
	_defeated = false
	_is_parry_vulnerable = false
	_flash(Color(0.55, 0.58, 0.62))

func _setup_timers() -> void:
	_telegraph_timer = Timer.new()
	_telegraph_timer.one_shot = false
	_telegraph_timer.wait_time = telegraph_interval
	_telegraph_timer.timeout.connect(_begin_telegraph)
	add_child(_telegraph_timer)
	_window_timer = Timer.new()
	_window_timer.one_shot = true
	_window_timer.wait_time = parry_window
	_window_timer.timeout.connect(_end_telegraph)
	add_child(_window_timer)
	if auto_telegraph:
		_telegraph_timer.start()

func _begin_telegraph() -> void:
	if _defeated:
		return
	_is_parry_vulnerable = true
	_flash(Color(0.95, 0.80, 0.12))
	_window_timer.start(parry_window)

func _end_telegraph() -> void:
	_is_parry_vulnerable = false
	if not _defeated:
		_flash(Color(0.55, 0.58, 0.62))

func _flash(color: Color) -> void:
	if not _mesh:
		return
	_base_material.albedo_color = color
