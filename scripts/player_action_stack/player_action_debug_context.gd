class_name PlayerActionDebugContext
extends BaseDebugContext

var _label: Label
var _canvas: CanvasLayer
var _data: Dictionary = {}

func _ready() -> void:
	panel_key = 1 # F1 panel
	if has_node("/root/DebugOverlay"):
		var overlay = get_node("/root/DebugOverlay")
		if overlay.has_method("register_context"):
			overlay.register_context(self)
			
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.YELLOW)
	_canvas.add_child(_label)
	if has_node("/root/DebugOverlay"):
		var overlay = get_node("/root/DebugOverlay")
		if overlay.has_signal("visibility_changed"):
			overlay.visibility_changed.connect(_on_visibility_changed)
			if _canvas:
				_canvas.visible = overlay.panel_visible

func _on_visibility_changed(is_visible: bool) -> void:
	if _canvas:
		_canvas.visible = is_visible

func clear() -> void:
	_data.clear()
	if _label:
		_label.text = ""

## MovementBrokerDebugReporter and CombatDebugReporter both push to this same
## panel_key=1 context — merge into a persistent dict instead of replacing,
## so whichever pushes last on a physics frame doesn't wipe the other's
## fields (was: combat state visible for at most one frame before Movement's
## every-physics-frame push overwrote it).
func push_data(data: Dictionary) -> void:
	if not _label: return
	_data.merge(data, true)
	var debug_str = "[Player Action Stack]\n"
	for k in _data.keys():
		debug_str += "%s: %s\n" % [k, str(_data[k])]
	_label.text = debug_str
