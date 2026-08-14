extends GutTest

# Tests for: LedgeFacts (scripts/player_action_stack/movement/services/ledge_facts.gd)

var subject: LedgeFacts

func before_each():
	subject = LedgeFacts.new()

func after_each():
	subject = null
	assert_no_new_orphans()

func test_default_values():
	assert_eq(subject.lip_height, -INF, "lip_height should default to -INF")
	assert_eq(subject.landing_height, -INF, "landing_height should default to -INF")
	assert_false(subject.is_occupied, "is_occupied should default to false")
	assert_false(subject.is_at_mantle_edge, "is_at_mantle_edge should default to false")
	assert_eq(subject.detection_range, 1.4, "detection_range should default to 1.4")
	assert_eq(subject.wall_normal, Vector3.ZERO, "wall_normal should default to ZERO")
	assert_eq(subject.target_position, Vector3.ZERO, "target_position should default to ZERO")
	assert_eq(subject.ledge_point, Vector3.ZERO, "ledge_point should default to ZERO")
	assert_false(subject.has_head_hit, "has_head_hit should default to false")
	assert_false(subject.has_wall_left, "has_wall_left should default to false")
	assert_false(subject.has_wall_right, "has_wall_right should default to false")
	assert_eq(subject.vault_target_position, Vector3.ZERO, "vault_target_position should default to ZERO")
	assert_false(subject.is_vaultable, "is_vaultable should default to false")

func test_field_assignment():
	subject.lip_height = 1.2
	subject.is_occupied = true
	subject.wall_normal = Vector3.FORWARD
	subject.vault_target_position = Vector3(0, 1, 2)
	subject.is_vaultable = true
	
	assert_eq(subject.lip_height, 1.2)
	assert_true(subject.is_occupied)
	assert_eq(subject.wall_normal, Vector3.FORWARD)
	assert_eq(subject.vault_target_position, Vector3(0, 1, 2))
	assert_true(subject.is_vaultable)
