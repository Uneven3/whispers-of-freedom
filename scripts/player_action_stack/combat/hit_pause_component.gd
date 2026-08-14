class_name HitPauseComponent
extends Node

@export var default_time_scale: float = 0.18
@export var default_duration: float = 0.08

var _restore_generation: int = 0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS

func request_hit_pause(scale: float = default_time_scale, duration: float = default_duration) -> void:
	if duration <= 0.0:
		return
	_restore_generation += 1
	var generation := _restore_generation
	Engine.time_scale = clampf(scale, 0.05, 1.0)
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		if generation == _restore_generation:
			Engine.time_scale = 1.0
	)

func force_restore() -> void:
	_restore_generation += 1
	Engine.time_scale = 1.0
