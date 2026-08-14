extends SceneTree

func _init():
	var scene_path = "res://scenes/main.tscn"
	var packed_scene = ResourceLoader.load(scene_path)
	var root = packed_scene.instantiate()
	
	# Node paths relative to root
	var ec = root.get_node("Player/EntityController")
	var broker = root.get_node("Player/EntityController/MovementBroker")
	
	# Load scripts
	var s_stamina = load("res://scripts/player_action_stack/movement/stamina_component.gd")
	var s_brain = load("res://scripts/player_action_stack/movement/player_brain.gd")
	var s_ground = load("res://scripts/player_action_stack/movement/services/ground_service.gd")
	var s_ledge = load("res://scripts/player_action_stack/movement/services/ledge_service.gd")
	var s_pivot = load("res://scripts/player_action_stack/movement/visuals_pivot.gd")
	var s_walk = load("res://scripts/player_action_stack/movement/motors/walk_motor.gd")
	var s_sprint = load("res://scripts/player_action_stack/movement/motors/sprint_motor.gd")
	var s_fall = load("res://scripts/player_action_stack/movement/motors/fall_motor.gd")
	var s_jump = load("res://scripts/player_action_stack/movement/motors/jump_motor.gd")
	var s_vault = load("res://scripts/player_action_stack/movement/motors/auto_vault_motor.gd")
	var s_climb = load("res://scripts/player_action_stack/movement/motors/climb_motor.gd")
	var s_mantle = load("res://scripts/player_action_stack/movement/motors/mantle_motor.gd")
	var s_broker = load("res://scripts/player_action_stack/movement/movement_broker.gd")
	var s_cam = load("res://scripts/player_action_stack/camera/camera_rig.gd")
	
	# Attach scripts
	root.get_node("Player/EntityController/StaminaComponent").set_script(s_stamina)
	root.get_node("Player/EntityController/PlayerBrain").set_script(s_brain)
	root.get_node("Player/EntityController/Services/GroundService").set_script(s_ground)
	root.get_node("Player/EntityController/Services/LedgeService").set_script(s_ledge)
	root.get_node("Player/EntityController/VisualsPivot").set_script(s_pivot)
	root.get_node("Player/CameraRig").set_script(s_cam)
	
	var walk_node = broker.get_node("WalkMotor")
	walk_node.set_script(s_walk)
	var sprint_node = broker.get_node("SprintMotor")
	sprint_node.set_script(s_sprint)
	var fall_node = broker.get_node("FallMotor")
	fall_node.set_script(s_fall)
	var jump_node = broker.get_node("JumpMotor")
	jump_node.set_script(s_jump)
	var vault_node = broker.get_node("AutoVaultMotor")
	vault_node.set_script(s_vault)
	var climb_node = broker.get_node("ClimbMotor")
	climb_node.set_script(s_climb)
	var mantle_node = broker.get_node("MantleMotor")
	mantle_node.set_script(s_mantle)
	
	broker.set_script(s_broker)
	
	# Populate motor_map on Broker
	# State mapping: 1=Walk, 2=Sprint, 3=Fall, 4=Jump, 5=AutoVault, 6=Climb, 7=Mantle
	var motor_map = {
		1: NodePath("WalkMotor"),
		2: NodePath("SprintMotor"),
		3: NodePath("FallMotor"),
		4: NodePath("JumpMotor"),
		5: NodePath("AutoVaultMotor"),
		6: NodePath("ClimbMotor"),
		7: NodePath("MantleMotor")
	}
	broker.motor_map = motor_map
	
	# Save scene
	var new_packed = PackedScene.new()
	new_packed.pack(root)
	ResourceSaver.save(new_packed, scene_path)
	
	print("SCENE PATCHED SUCCESSFULLY")
	quit()
