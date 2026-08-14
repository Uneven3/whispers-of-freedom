class_name PlayerActionDebugContext
extends BaseDebugContext

var _label: Label
var _canvas: CanvasLayer

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
	if _label:
		_label.text = ""

func push_data(data: Dictionary) -> void:
	if not _label: return
	var debug_str = "[Player Action Stack]\n"
	for k in data.keys():
		debug_str += "%s: %s\n" % [k, str(data[k])]
	_label.text = debug_str
