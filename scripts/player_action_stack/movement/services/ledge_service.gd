class_name LedgeService
extends BaseService

const MIN_DIRECTION_LENGTH_SQUARED: float = 0.001
const H_CAST_Y_OFFSETS: Array[float] = [-0.8, -0.6, -0.2, 0.2, 0.4, 0.6]  ## Ankle → Head profiling heights
const DOWN_CAST_MARGIN: float = 0.1          ## Extra height margin added above mantle_max_height for the down-cast origin
const DOWN_CAST_FORWARD_OFFSET: float = 1.0  ## Forward distance of the down-cast from the body
const FORWARD_CAST_SPHERE_RADIUS: float = 0.1 ## Sphere radius for all forward and down shape-casts
const LATERAL_CAST_Y_OFFSET: float = 0.5    ## Y offset for left/right wall-probe raycasts
const FORWARD_SAMPLE_OFFSET: float = 1.0    ## Forward distance used to position the down-cast each frame in update_facts
const VAULT_DIST_MARGIN: float = 0.2        ## Extra forward margin added to min_dist when positioning the vault down-cast
const STEEP_FACE_NORMAL_Y_MAX: float = 0.75 ## Max Y component of a collision normal to count as a steep (vaultable) face
const VAULT_FORWARD_RADIUS_MULT: float = 1.5 ## Multiplier on body radius for forward vault target placement

@export var vault_detection_range: float = 1.4
@export var vault_min_height: float = 0.3
@export var vault_surface_clearance: float = 0.08
@export var vault_landing_probe_distance: float = 1.6
@export var vault_landing_probe_height: float = 2.0
@export var mantle_max_height: float = 2.5
@export var lateral_cast_reach: float = 1.5
@export var mantle_forward_radius_multiplier: float = 2.0
@export var mantle_surface_clearance: float = 0.08
@export var mantle_edge_body_offset: float = 0.33
@export var mantle_edge_tolerance: float = 0.05
@export var climb_wall_angle_max_deg: float = 30.0
@export var continue_climb_angle_max_deg: float = 45.0
@export var wall_detection_reach: float = 0.65

## Body geometry (half_height / radius) is read from the entity's CollisionShape3D
## via the BodyReader passed to update_facts — no per-service @export duplicates.
## Cached each frame so the down-cast setup in _ready can stay static.
var _body_half_height: float = 1.0
var _body_radius: float = 0.5

var _can_climb: bool = false
var _climb_normal: Vector3 = Vector3.ZERO
var _has_wall_left: bool = false
var _has_wall_right: bool = false
var _vault_target_position: Vector3 = Vector3.ZERO
var _is_vaultable: bool = false
var _mantle_ledge_point: Vector3 = Vector3.ZERO
var _mantle_target_position: Vector3 = Vector3.ZERO
var _is_at_ledge_edge: bool = false
var _has_head_hit: bool = false
var _debug_text: String = ""
var _lip_height: float = 0.0
var _landing_height: float = 0.0
var _is_occupied: bool = false

var _down_cast: ShapeCast3D
var _vault_down_cast: ShapeCast3D
var _vault_landing_cast: ShapeCast3D
var _left_cast: RayCast3D
var _right_cast: RayCast3D

# Horizontal profiling casts (Ankle to Head)
var _h_casts: Array[ShapeCast3D] = []
var _h_offsets: Array[float] = H_CAST_Y_OFFSETS

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	
	for offset in _h_offsets:
		_h_casts.append(_create_forward_cast(offset))
	
	_down_cast = _create_down_cast(-mantle_max_height - DOWN_CAST_MARGIN)
	_down_cast.position = Vector3(0, mantle_max_height + DOWN_CAST_MARGIN, -DOWN_CAST_FORWARD_OFFSET)
	
	_vault_down_cast = _create_down_cast(-vault_detection_range - DOWN_CAST_MARGIN - _body_half_height)
	_vault_down_cast.position = Vector3(0, vault_detection_range + DOWN_CAST_MARGIN, 0) # Z set dynamically

	_vault_landing_cast = _create_down_cast(-vault_landing_probe_height - 0.2)
	_vault_landing_cast.position = Vector3(0, vault_landing_probe_height, -vault_landing_probe_distance)
	
	_left_cast  = _create_forward_raycast(LATERAL_CAST_Y_OFFSET)
	_left_cast.top_level = true
	_right_cast = _create_forward_raycast(LATERAL_CAST_Y_OFFSET)
	_right_cast.top_level = true

func _create_forward_cast(y_offset: float) -> ShapeCast3D:
	var cast: ShapeCast3D = ShapeCast3D.new()
	cast.shape = SphereShape3D.new()
	cast.shape.radius = FORWARD_CAST_SPHERE_RADIUS
	cast.position = Vector3(0, y_offset, 0)
	cast.target_position = Vector3(0, 0, -wall_detection_reach)
	cast.collision_mask = 1
	add_child(cast)
	return cast

func _create_forward_raycast(y_offset: float) -> RayCast3D:
	var cast: RayCast3D = RayCast3D.new()
	cast.position = Vector3(0, y_offset, 0)
	cast.target_position = Vector3(0, 0, -wall_detection_reach)
	cast.collision_mask = 1
	cast.enabled = false
	add_child(cast)
	return cast

func _create_down_cast(target_y: float) -> ShapeCast3D:
	var cast: ShapeCast3D = ShapeCast3D.new()
	cast.shape = SphereShape3D.new()
	cast.shape.radius = FORWARD_CAST_SPHERE_RADIUS
	cast.target_position = Vector3(0, target_y, 0)
	cast.collision_mask = 1
	add_child(cast)
	return cast

func update_facts(body_reader: BodyReader) -> void:
	_reset_facts()
	_body_half_height = body_reader.get_body_half_height()
	_body_radius = body_reader.get_body_radius()
	var pos: Vector3 = body_reader.get_global_position()
	var facing: Vector3 = -body_reader.get_basis().z
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > MIN_DIRECTION_LENGTH_SQUARED else Vector3.FORWARD
	# Update horizontal casts
	var hits: Array[bool] = []
	var min_dist: float = wall_detection_reach
	for i in range(_h_casts.size()):
		var cast: ShapeCast3D = _h_casts[i]
		cast.global_position = pos + Vector3(0, _h_offsets[i], 0)
		cast.target_position = facing * wall_detection_reach
		cast.force_shapecast_update()
		hits.append(cast.is_colliding())

		if hits[i]:
			var c_point = cast.get_collision_point(0)
			min_dist = minf(min_dist, c_point.distance_to(cast.global_position))


	# Update special vertical casts (positions are global because parent is a Node)
	_down_cast.global_position = pos + facing * FORWARD_SAMPLE_OFFSET + Vector3.UP * (mantle_max_height + DOWN_CAST_MARGIN)
	_down_cast.force_shapecast_update()

	_vault_landing_cast.global_position = pos + facing * vault_landing_probe_distance + Vector3.UP * vault_landing_probe_height
	_vault_landing_cast.force_shapecast_update()

	# Vault downcast refresh
	var v_dist: float = min_dist + VAULT_DIST_MARGIN
	_vault_down_cast.global_position = pos + facing * v_dist + Vector3.UP * (vault_detection_range + DOWN_CAST_MARGIN)
	_vault_down_cast.force_shapecast_update()

	var feet_y: float = pos.y - _body_half_height
	_detect_vault(pos, facing, hits, feet_y)
	_detect_mantle(pos, feet_y)

	var knee_hit: bool = hits[1]
	var waist_hit: bool = hits[2]
	var head_hit: bool = hits[5]
	_has_head_hit = head_hit
	_detect_climb(facing, knee_hit, waist_hit, head_hit, pos)
	
	if _down_cast.is_colliding():
		_lip_height = _down_cast.get_collision_point(0).y - feet_y
	if _vault_landing_cast.is_colliding():
		_landing_height = _vault_landing_cast.get_collision_point(0).y - feet_y
		_is_occupied = true

func _reset_facts() -> void:
	_can_climb = false
	_climb_normal = Vector3.ZERO
	_vault_target_position = Vector3.ZERO
	_is_vaultable = false
	_mantle_ledge_point = Vector3.ZERO
	_mantle_target_position = Vector3.ZERO
	_is_at_ledge_edge = false
	_has_head_hit = false
	_debug_text = ""
	_lip_height = 0.0
	_landing_height = 0.0
	_is_occupied = false

func _detect_vault(pos: Vector3, facing: Vector3, hits: Array[bool], feet_y: float) -> void:
	# Ankle(0), Knee(1), Waist(2), Chest(3) hits vs Limit(4) and Head(5) miss
	_debug_text = "H:" + ("1" if hits[0] else "0") + ("1" if hits[1] else "0") + ("1" if hits[2] else "0") + ("1" if hits[3] else "0") + ("1" if hits[4] else "0") + ("1" if hits[5] else "0")
	var obstacle_hit: bool = hits[0] or hits[1] or hits[2] or hits[3]
	
	if obstacle_hit and not hits[4] and not hits[5]:
		# Check if the face we hit is steep enough to be an obstacle (not a walkable slope)
		var steep_enough: bool = false
		for i in range(4):
			if hits[i]:
				var n: Vector3 = _h_casts[i].get_collision_normal(0)
				# 45 deg or steeper (cos(45) approx 0.707) -> y < 0.75 means mostly vertical
				if n.y < STEEP_FACE_NORMAL_Y_MAX:
					steep_enough = true
					break
		
		if steep_enough:
			if _vault_down_cast.is_colliding():
				var lip: Vector3 = _vault_down_cast.get_collision_point(0)
				var rel_y: float = lip.y - feet_y
				_debug_text += " ry:" + str(snappedf(rel_y, 0.1))
				if rel_y >= vault_min_height and rel_y <= vault_detection_range:
					_is_vaultable = true
					_update_vault_target(facing, pos, lip)
			else:
				_debug_text += " vdc:miss"
		else:
			_debug_text += " slope"

func _detect_mantle(pos: Vector3, feet_y: float) -> void:
	if _down_cast.is_colliding():
		var down_point: Vector3 = _down_cast.get_collision_point(0)
		var mantle_rel_y: float = down_point.y - feet_y
		if mantle_rel_y > 0 and mantle_rel_y <= mantle_max_height:
			_mantle_ledge_point = down_point
			_is_at_ledge_edge = _is_at_mantle_edge(pos, down_point)
			_update_mantle_target(_h_casts[5].target_position.normalized(), pos) # Use head cast facing

func _detect_climb(facing: Vector3, knee_hit: bool, waist_hit: bool, head_hit: bool, pos: Vector3) -> void:
	if waist_hit:
		var normal: Vector3 = _h_casts[2].get_collision_normal(0)
		if rad_to_deg(facing.angle_to(-normal)) <= climb_wall_angle_max_deg:
			_climb_normal = normal
			if knee_hit and head_hit:
				_can_climb = true
				_update_lateral_walls(pos)

func _update_lateral_walls(pos: Vector3) -> void:
	var right_dir: Vector3 = Vector3.UP.cross(_climb_normal).normalized()
	_left_cast.global_position  = pos + (-right_dir * 0.45)
	_right_cast.global_position = pos + (right_dir  * 0.45)
	_left_cast.target_position  = -_climb_normal * lateral_cast_reach
	_right_cast.target_position = -_climb_normal * lateral_cast_reach
	_left_cast.force_raycast_update()
	_right_cast.force_raycast_update()
	_has_wall_left  = _left_cast.is_colliding()
	_has_wall_right = _right_cast.is_colliding()

func get_ledge_facts() -> LedgeFacts:
	var facts: LedgeFacts = LedgeFacts.new()
	facts.lip_height = _lip_height
	facts.landing_height = _landing_height
	facts.is_occupied = _is_occupied
	facts.is_at_mantle_edge = _is_at_ledge_edge
	facts.detection_range = vault_detection_range
	facts.wall_normal = _climb_normal
	facts.has_wall_left = _has_wall_left
	facts.has_wall_right = _has_wall_right
	facts.target_position = _mantle_target_position
	facts.ledge_point = _mantle_ledge_point
	facts.has_head_hit = _has_head_hit
	facts.vault_target_position = _vault_target_position
	facts.is_vaultable = _is_vaultable
	facts.debug_text = _debug_text
	return facts

func get_wall_point() -> Vector3:
	if _h_casts[2].is_colliding():
		return _h_casts[2].get_collision_point(0)
	return Vector3.ZERO

func can_climb() -> bool: return _can_climb
func get_climb_normal() -> Vector3: return _climb_normal
func has_wall_left() -> bool: return _has_wall_left
func has_wall_right() -> bool: return _has_wall_right
func can_continue_climbing() -> bool:
	if not _h_casts[2].is_colliding(): return false
	return rad_to_deg(_h_casts[2].target_position.normalized().angle_to(-_h_casts[2].get_collision_normal(0))) <= continue_climb_angle_max_deg

func _is_at_mantle_edge(body_position: Vector3, ledge_point: Vector3) -> bool:
	return body_position.y >= (ledge_point.y - mantle_edge_body_offset) - mantle_edge_tolerance

func _update_vault_target(facing: Vector3, body_position: Vector3, lip_point: Vector3) -> void:
	# "Step-up" paradigm: Vaulting places the player slightly over the lip, like a mini-mantle.
	var vault_forward_distance: float = _body_radius * VAULT_FORWARD_RADIUS_MULT
	_vault_target_position = body_position + facing * vault_forward_distance
	_vault_target_position.y = lip_point.y + _body_half_height + vault_surface_clearance

func _update_mantle_target(fallback_forward: Vector3, body_position: Vector3) -> void:
	var fwd = -_climb_normal if _climb_normal != Vector3.ZERO else fallback_forward
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > MIN_DIRECTION_LENGTH_SQUARED else Vector3.FORWARD
	_mantle_target_position = body_position + fwd * (_body_radius * mantle_forward_radius_multiplier)
	_mantle_target_position.y = _mantle_ledge_point.y + _body_half_height + mantle_surface_clearance
