class_name LadderService
extends BaseService

## Tracks which Ladder marker (if any) the body is currently overlapping.
## Self-wires at _ready by walking the "ladder" group. Mirror of StairsService.

var _active_ladder: Ladder = null
var _body: CharacterBody3D = null

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_body = get_node_or_null("../../Body") as CharacterBody3D
	if _body == null:
		push_warning("LadderService: could not locate sibling Body — ladders disabled.")
		return
	call_deferred("_connect_ladders")

func _connect_ladders() -> void:
	for l in get_tree().get_nodes_in_group("ladder"):
		if l is Ladder:
			l.body_entered.connect(_on_ladder_body_entered.bind(l))
			l.body_exited.connect(_on_ladder_body_exited.bind(l))

func _on_ladder_body_entered(body: Node3D, ladder: Ladder) -> void:
	if body == _body:
		_active_ladder = ladder

func _on_ladder_body_exited(body: Node3D, ladder: Ladder) -> void:
	if body == _body and _active_ladder == ladder:
		_active_ladder = null

func is_on_ladder() -> bool:
	return _active_ladder != null

func get_active_ladder() -> Ladder:
	return _active_ladder

func update_facts(_body_reader: BodyReader) -> void:
	pass
