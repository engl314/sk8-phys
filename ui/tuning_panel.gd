class_name TuningPanel
extends CanvasLayer

const SAVE_PATH := "res://tuning/default_tuning.tres"

var skater: SkaterController
var _panel := PanelContainer.new()
var _list := VBoxContainer.new()
var _status := Label.new()
var _f1_was_down := false
var _built := false


func _ready() -> void:
	layer = 10
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Tuning (F1 closes)"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var save := Button.new()
	save.text = "Save as default"
	save.pressed.connect(_save)
	buttons.add_child(save)
	var reset := Button.new()
	reset.text = "Reset to built-in"
	reset.pressed.connect(_reset)
	buttons.add_child(reset)
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	scroll.add_child(_list)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _process(_delta: float) -> void:
	var down := Input.is_physical_key_pressed(KEY_F1)
	if down and not _f1_was_down:
		_toggle()
	_f1_was_down = down
	if _panel.visible:
		var view := get_viewport().get_visible_rect().size
		_panel.position = Vector2(view.x - 500.0, 60.0)
		_panel.size = Vector2(480.0, view.y - 80.0)


func _toggle() -> void:
	_panel.visible = not _panel.visible
	skater.pad.ui_open = _panel.visible
	if _panel.visible:
		if not _built:
			_build()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	_built = true
	for child in _list.get_children():
		child.queue_free()
	# The rider's feel first: it is the part tuned by eye.
	for source: Array in [["Rider: ", skater.animator.feel], ["", skater.tuning]]:
		var resource: Resource = source[1]
		for property in resource.get_property_list():
			var usage: int = property.usage
			if usage & PROPERTY_USAGE_GROUP and property.name != "Resource":
				var header := Label.new()
				header.text = source[0] + property.name
				header.add_theme_font_size_override("font_size", 16)
				header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
				_list.add_child(header)
				continue
			if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
				continue
			if property.type != TYPE_FLOAT and property.type != TYPE_INT:
				continue
			_add_row(resource, property.name, property.type == TYPE_INT)


func _add_row(tuning: Resource, property: String, integer: bool) -> void:
	var value: float = tuning.get(property)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = property
	label.custom_minimum_size = Vector2(230, 0)
	label.clip_text = true
	row.add_child(label)
	var slider := HSlider.new()
	var magnitude := maxf(absf(value) * 3.0, 1.0)
	slider.min_value = -magnitude if value < 0.0 else 0.0
	slider.max_value = magnitude
	slider.step = 1.0 if integer else magnitude / 1000.0
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 0)
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(70, 0)
	readout.text = str(int(value)) if integer else _format(value)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		tuning.set(property, int(v) if integer else v)
		readout.text = str(int(v)) if integer else _format(v))
	_list.add_child(row)


static func _format(value: float) -> String:
	if absf(value) >= 100.0:
		return "%.1f" % value
	if absf(value) >= 1.0:
		return "%.3f" % value
	return "%.4f" % value


func _save() -> void:
	var error := ResourceSaver.save(skater.tuning, SAVE_PATH)
	if error == OK:
		error = ResourceSaver.save(skater.animator.feel, RiderFeel.SAVE_PATH)
	_status.text = "Saved to res://tuning" if error == OK else "Save failed (error %d)" % error


func _reset() -> void:
	for pair: Array in [[SkateTuning.new(), skater.tuning], [RiderFeel.new(), skater.animator.feel]]:
		var fresh: Resource = pair[0]
		for property in fresh.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
				pair[1].set(property.name, fresh.get(property.name))
	_built = false
	_build()
	_status.text = "Reset to the built-in values (not saved)"
