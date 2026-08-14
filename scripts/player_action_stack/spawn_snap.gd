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

@export var height_offset: float = 0.1

func _ready() -> void:
	# One frame so a sibling Terrain3D (loaded earlier or later in tree order)
	# has finished loading its regions before we query height.
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
	parent.global_position.y = height + height_offset
