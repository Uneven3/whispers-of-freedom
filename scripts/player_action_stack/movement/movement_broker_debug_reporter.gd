class_name MovementBrokerDebugReporter
extends Node

var _broker: MovementBroker
var _stamina: StaminaComponent
var _ledge_service: LedgeService
var _form_broker: Node

func _ready() -> void:
	_broker = get_parent() as MovementBroker
	if _broker:
		_broker.physics_tick_complete.connect(_on_physics_tick_complete)
		
	# Connect to siblings to avoid holding hard references to body state if possible
	_stamina = _broker.get_node_or_null("../StaminaComponent")
	_ledge_service = _broker.get_node_or_null("../Services/LedgeService")
	_form_broker = _broker.get_node_or_null("../FormBroker")

func _on_physics_tick_complete(intents: Intents, current_mode: int) -> void:
	if OS.is_debug_build() and has_node("/root/DebugOverlay"):
		var m_name: String = LocomotionState.ID.keys()[current_mode]
		var body_reader = _broker.get_body_reader()
		var vel = body_reader.get_velocity()
		var spd: float = Vector2(vel.x, vel.z).length()
		var stamina_cur: float = _stamina.get_current() if _stamina else 0.0
		var stamina_max: float = _stamina.get_max() if _stamina else 100.0
		var stamina_pct: int = roundi(stamina_cur / stamina_max * 100.0)
		
		# Collect active intents for debugging
		var active_intents: Array[String] = []
		if intents.wants_jump: active_intents.append("Jump")
		if intents.wants_sprint: active_intents.append("Sprint")
		if intents.wants_sneak: active_intents.append("Sneak")
		if intents.wants_climb: active_intents.append("Climb")
		if intents.wants_mantle: active_intents.append("Mantle")
		if intents.wants_vault: active_intents.append("Vault")
		if intents.wants_glide: active_intents.append("Glide")
		if intents.wants_form_shift != &"": active_intents.append("Form:%s" % intents.wants_form_shift)
		
		var intents_str: String = " ".join(active_intents.map(func(s): return "[" + s + "]"))
		
		# Semantic direction debug
		var dir_str: String = ""
		if intents.is_moving_forward: dir_str += "F"
		if intents.is_moving_back: dir_str += "B"
		if intents.is_moving_left: dir_str += "L"
		if intents.is_moving_right: dir_str += "R"
		if dir_str == "": dir_str = "-"
		
		var v_status: String = " (V)" if _ledge_service and _ledge_service.get_ledge_facts().is_vaultable else ""
		
		var ledge_debug: String = ""
		if _ledge_service:
			var facts = _ledge_service.get_ledge_facts()
			ledge_debug = facts.debug_text
		
		get_node("/root/DebugOverlay").push(1, {
			"state": m_name + v_status, 
			"form": _form_broker.get_current_form() if _form_broker and _form_broker.has_method("get_current_form") else "-", 
			"speed": snappedf(spd, 0.1), 
			"vel_y": snappedf(vel.y, 0.1), 
			"stamina": "%d%%" % stamina_pct,
			"wish": dir_str,
			"str": "%.2f" % intents.input_strength,
			"intents": intents_str if intents_str != "" else "None",
			"ledge": ledge_debug
		})
