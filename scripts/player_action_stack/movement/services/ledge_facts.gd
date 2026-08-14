class_name LedgeFacts
extends RefCounted

## Data carrier for ledge detection facts.
## Populated by LedgeService, consumed by traversal Motors.

var lip_height: float = -INF          ## Vertical distance from feet to ledge edge.
var landing_height: float = -INF     ## Vertical distance from feet to landing surface.
var is_occupied: bool = false        ## True if landing surface is clear/detected.
var is_at_mantle_edge: bool = false  ## True if player is at the correct height to pull up.
var detection_range: float = 1.4     ## The service's current vault detection limit.
var wall_normal: Vector3 = Vector3.ZERO
var has_wall_left: bool = false
var has_wall_right: bool = false
var target_position: Vector3 = Vector3.ZERO ## Pre-calculated mantle landing spot.
var ledge_point: Vector3 = Vector3.ZERO
var has_head_hit: bool = false ## True if the head-level sensor is colliding.
var vault_target_position: Vector3 = Vector3.ZERO ## Pre-calculated vault landing spot.
var is_vaultable: bool = false ## True if a clear vault path is detected.
var debug_text: String = "" ## Optional string to store debug output
