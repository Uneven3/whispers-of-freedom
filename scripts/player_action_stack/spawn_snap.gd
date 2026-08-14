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

## Relative to this node's parent (the Player root) — matches brain_path's
## own pattern (movement_broker.gd) of a NodePath default that already
## matches player.tscn's real layout.
@export var body_reader_source: NodePath = NodePath("../EntityController/MovementBroker")
@export var clearance: float = 0.5

## Matches BodyReader's own fallback when no capsule shape is found.
const _DEFAULT_HALF_HEIGHT: float = 1.0

func _ready() -> void:
	# One frame so a sibling Terrain3D (loaded earlier or later in tree order)
	# has finished loading its regions, and MovementBroker has built its
	# BodyReader, before we query either.
	await get_tree().process_frame
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
