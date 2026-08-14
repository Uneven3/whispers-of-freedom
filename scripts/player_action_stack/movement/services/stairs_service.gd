class_name StairsService
extends BaseService

## Tracks which Stairs marker (if any) the body is currently overlapping.
## Self-wires at _ready by walking the "stairs" group and connecting to each
## marker's body_entered/body_exited signals. Same pattern any future authored
## affordance can reuse — broker stays out of scene wiring.

var _active_stair: Stairs = null
var _body: CharacterBody3D = null

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	## Path: Services/StairsService → Services → EntityController → Body
	_body = get_node_or_null("../../Body") as CharacterBody3D
	if _body == null:
		push_warning("StairsService: could not locate sibling Body — stairs disabled.")
		return
	## Defer one frame so any Stairs added by scene instantiation order are present.
	call_deferred("_connect_stairs")

func _connect_stairs() -> void:
	for s in get_tree().get_nodes_in_group("stairs"):
		if s is Stairs:
			s.body_entered.connect(_on_stair_body_entered.bind(s))
			s.body_exited.connect(_on_stair_body_exited.bind(s))

func _on_stair_body_entered(body: Node3D, stair: Stairs) -> void:
	if body == _body:
		_active_stair = stair

func _on_stair_body_exited(body: Node3D, stair: Stairs) -> void:
	if body == _body and _active_stair == stair:
		_active_stair = null

func is_on_stairs() -> bool:
	return _active_stair != null

func get_active_stair() -> Stairs:
	return _active_stair

func update_facts(_body_reader: BodyReader) -> void:
	pass  ## Signal-driven; the broker still iterates services but we have nothing to poll
