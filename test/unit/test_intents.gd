extends GutTest

var subject: Intents

func before_each():
	subject = Intents.new()

func after_each():
	subject = null

func test_default_values():
	assert_eq(subject.move_dir, Vector2.ZERO, "move_dir should be Vector2.ZERO")
	assert_eq(subject.raw_input, Vector2.ZERO, "raw_input should be Vector2.ZERO")
	assert_eq(subject.wish_dir, Vector2i.ZERO, "wish_dir should be Vector2i.ZERO")
	assert_eq(subject.input_strength, 0.0, "input_strength should be 0.0")
	
	assert_false(subject.is_moving_forward, "is_moving_forward should be false")
	assert_false(subject.is_climbing_up, "is_climbing_up should be false")
	
	assert_false(subject.wants_jump, "wants_jump should be false")
	assert_false(subject.wants_sprint, "wants_sprint should be false")
	assert_false(subject.wants_sneak, "wants_sneak should be false")
	assert_false(subject.wants_climb, "wants_climb should be false")
	assert_false(subject.wants_mantle, "wants_mantle should be false")
	assert_false(subject.wants_vault, "wants_vault should be false")
	assert_false(subject.wants_glide, "wants_glide should be false")
	assert_eq(subject.wants_form_shift, &"", "wants_form_shift should be empty")
	assert_false(subject.wants_attack, "wants_attack should be false")
	assert_false(subject.wants_parry, "wants_parry should be false")
	assert_false(subject.wants_archery_aim, "wants_archery_aim should be false")
	assert_false(subject.wants_archery_release, "wants_archery_release should be false")
	assert_false(subject.wants_assassinate, "wants_assassinate should be false")

func test_semantic_getters():
	subject.wish_dir = Vector2i(0, 1)
	assert_true(subject.is_moving_forward, "should be moving forward")
	assert_true(subject.is_climbing_up, "should be climbing up")
	assert_false(subject.is_moving_back, "should NOT be moving back")
	
	subject.wish_dir = Vector2i(-1, 0)
	assert_true(subject.is_moving_left, "should be moving left")
	assert_true(subject.is_climbing_left, "should be climbing left")
	assert_false(subject.is_moving_right, "should NOT be moving right")

func test_field_assignment():
	subject.move_dir = Vector2.UP
	subject.wants_jump = true
	subject.input_strength = 0.8
	subject.wants_form_shift = &"monkey"
	subject.wants_attack = true
	subject.aim_direction = Vector3.FORWARD
	
	assert_eq(subject.move_dir, Vector2.UP, "move_dir assignment failed")
	assert_true(subject.wants_jump, "wants_jump assignment failed")
	assert_eq(subject.input_strength, 0.8, "input_strength assignment failed")
	assert_eq(subject.wants_form_shift, &"monkey", "wants_form_shift assignment failed")
	assert_true(subject.wants_attack, "wants_attack assignment failed")
	assert_eq(subject.aim_direction, Vector3.FORWARD, "aim_direction assignment failed")

func test_reset_clears_all_fields():
	subject.move_dir = Vector2.ONE
	subject.raw_input = Vector2.ONE
	subject.wish_dir = Vector2i(1, 1)
	subject.input_strength = 1.0
	
	subject.wants_jump = true
	subject.wants_sprint = true
	subject.wants_sneak = true
	subject.wants_climb = true
	subject.wants_mantle = true
	subject.wants_vault = true
	subject.wants_glide = true
	subject.wants_form_shift = &"avian"
	subject.wants_attack = true
	subject.wants_parry = true
	subject.wants_archery_aim = true
	subject.wants_archery_release = true
	subject.wants_assassinate = true
	subject.aim_origin = Vector3.ONE
	subject.aim_direction = Vector3.FORWARD
	
	subject.reset()
	
	assert_eq(subject.move_dir, Vector2.ZERO, "move_dir should be reset")
	assert_eq(subject.raw_input, Vector2.ZERO, "raw_input should be reset")
	assert_eq(subject.wish_dir, Vector2i.ZERO, "wish_dir should be reset")
	assert_eq(subject.input_strength, 0.0, "input_strength should be reset")
	
	assert_false(subject.wants_jump, "wants_jump should be reset")
	assert_false(subject.wants_sprint, "wants_sprint should be reset")
	assert_false(subject.wants_sneak, "wants_sneak should be reset")
	assert_false(subject.wants_climb, "wants_climb should be reset")
	assert_false(subject.wants_mantle, "wants_mantle should be reset")
	assert_false(subject.wants_vault, "wants_vault should be reset")
	assert_false(subject.wants_glide, "wants_glide should be reset")
	assert_eq(subject.wants_form_shift, &"", "wants_form_shift should be reset")
	assert_false(subject.wants_attack, "wants_attack should be reset")
	assert_false(subject.wants_parry, "wants_parry should be reset")
	assert_false(subject.wants_archery_aim, "wants_archery_aim should be reset")
	assert_false(subject.wants_archery_release, "wants_archery_release should be reset")
	assert_false(subject.wants_assassinate, "wants_assassinate should be reset")
	assert_eq(subject.aim_origin, Vector3.ZERO, "aim_origin should be reset")
	assert_eq(subject.aim_direction, Vector3.ZERO, "aim_direction should be reset")
