class_name DebugOverlay
extends CanvasLayer

var skater: SkaterController
var _label := Label.new()
var _visible := false
var _tab_was_down := false


func _ready() -> void:
	_label.position = Vector2(16, 230)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)


func _process(_delta: float) -> void:
	var tab_down := Input.is_physical_key_pressed(KEY_TAB)
	if tab_down and not _tab_was_down:
		_visible = not _visible
	_tab_was_down = tab_down
	_label.visible = _visible
	if not _visible or skater == null:
		return
	var board := skater.board
	var lines: Array[String] = []
	lines.append("speed %.2f m/s   solver %.2f ms   fps %d" % [board.speed(), board.last_step_usec / 1000.0, Engine.get_frames_per_second()])
	lines.append("contacts %d   wheels down %d   trucks %.3f / %.3f" % [skater.collisions.size(), board.wheel_contact_count(), skater.truck_targets.x, skater.truck_targets.y])
	var held: Array[String] = []
	for action in VirtualPad.Action.size():
		if skater.pad.down(action):
			held.append(VirtualPad.Action.keys()[action].to_lower())
	lines.append("steer %+.2f   held %s%s" % [skater.pad.steer, " ".join(held) if not held.is_empty() else "-", "   pumping" if skater.pumping else ""])
	for line in skater.debug_lines():
		lines.append(line)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		lines.append("click to capture the mouse (Esc releases)")
	_label.text = "\n".join(lines)
