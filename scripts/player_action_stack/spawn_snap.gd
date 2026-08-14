@tool
class_name SpawnSnap
extends Node

## Snaps the parent Node3D to ground height on spawn, once, by querying a
## Terrain3D node registered in the "terrain" group — not a NodePath/sibling
## reach, since Player's composition root (this scene) can't know what scene
## it'll be dropped into (§3 of ARCHITECTURE.md). No "terrain" group member
## (eg grass_field.tscn's flat Ground) is a normal case, not a failure: no-op.
##
## Untyped/dynamic calls into Terrain3D on purpose: addons/terrain_3d/ isn't
## committed to this repo (see AHORA.md), so a static Terrain3D type here
## would fail to parse for anyone who hasn't installed the plugin, breaking
## Player even in scenes that don't use terrain at all.
##
## get_height() returns the ground height at the Body's ORIGIN, not its
## feet — the capsule collider is centered on the Body. Landing the origin
## directly on the terrain buries the bottom half of the capsule in the
## mesh, which is exactly "the player is stuck in the ground". The fix adds
## the capsule's half-height on top, read from BodyReader
## (get_body_half_height()) instead of re-deriving capsule math here — same
## single-source-of-truth BodyReader that motors/services already use.
##
## @tool so this previews live in the editor too — see _queue_snap(). If
## MovementBroker's own script isn't @tool (it isn't), get_body_reader()
## has nothing to return while editing, so half-height falls back to
## _DEFAULT_HALF_HEIGHT there; only the running game reads the real capsule.

## Relative to this node's parent (the Player root) — matches brain_path's
## own pattern (movement_broker.gd) of a NodePath default that already
## matches player.tscn's real layout.
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

## Matches BodyReader's own fallback when no capsule shape is found.
const _DEFAULT_HALF_HEIGHT: float = 1.0

var _ready_done: bool = false
var _snap_queued: bool = false

func _ready() -> void:
	_ready_done = true
	# One frame so a sibling Terrain3D (loaded earlier or later in tree order)
	# has finished loading its regions, and MovementBroker has built its
	# BodyReader, before we query either.
	await get_tree().process_frame
	_snap_to_terrain()

## Debounces Inspector edits (Godot sets every exported var once while
## deserializing the scene, before _ready runs) into a single snap —
## same pattern as GrassField._queue_rebuild().
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
	var terrain_data: Object = terrain.get("data")
	if terrain_data == null:
		return
	var height: float = terrain_data.call("get_height", parent.global_position)
	if is_nan(height):
		return
	parent.global_position.y = height + _get_body_half_height() + clearance

func _get_body_half_height() -> float:
	var broker: Node = get_node_or_null(body_reader_source)
	if broker == null or not broker.has_method("get_body_reader"):
		return _DEFAULT_HALF_HEIGHT
	var reader: BodyReader = broker.get_body_reader()
	if reader == null:
		return _DEFAULT_HALF_HEIGHT
	return reader.get_body_half_height()
