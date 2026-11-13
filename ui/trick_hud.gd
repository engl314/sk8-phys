class_name TrickHud
extends CanvasLayer

const CONTROLS := """W   push (pump in a ramp)      S   brake      A / D   carve, spin, balance
SPACE   hold to crouch, let go to ollie
Q kickflip   E heelflip   Z shove-it   X frontside shove-it
    tap two together to combine, hold one for double flips and 360s
C   hold: manual on the ground, grab in the air (with W / S / Q / E: other grabs)
SHIFT   hold for nollies and nose manuals
S + A / D   powerslide (straight after landing: revert)
MOUSE   look around      R   respawn      TAB   debug      F1   tuning      H   hide this"""

var skater: SkaterController
var score: ScoreKeeper

var _score_label := Label.new()
var _line_label := Label.new()
var _popup := Label.new()
var _controls := Label.new()
var _controls_visible := true
var _h_was_down := false
var _popup_tween: Tween


func _ready() -> void:
	for label in [_score_label, _line_label, _popup, _controls]:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 8)
		add_child(label)
	_score_label.add_theme_font_size_override("font_size", 26)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.size = Vector2(360, 40)
	_line_label.add_theme_font_size_override("font_size", 22)
	_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line_label.size = Vector2(1000, 40)
	_line_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_popup.add_theme_font_size_override("font_size", 40)
	_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.size = Vector2(1000, 60)
	_popup.pivot_offset = Vector2(500, 30)
	_popup.modulate.a = 0.0
	_controls.add_theme_font_size_override("font_size", 14)
	_controls.text = CONTROLS
	score.trick_scored.connect(_on_trick)
	score.line_banked.connect(_on_banked)
	score.line_lost.connect(func() -> void: _flash("Line lost", Color(1.0, 0.35, 0.3)))
	skater.director.bailed.connect(func(reason: String) -> void: _flash("Bail! " + reason, Color(1.0, 0.35, 0.3)))


func _process(_delta: float) -> void:
	var h_down := Input.is_physical_key_pressed(KEY_H)
	if h_down and not _h_was_down:
		_controls_visible = not _controls_visible
	_h_was_down = h_down
	_controls.visible = _controls_visible
	var view := get_viewport().get_visible_rect().size
	_score_label.position = Vector2(view.x - 380.0, 14.0)
	_line_label.position = Vector2(view.x * 0.5 - 500.0, view.y - 70.0)
	_popup.position = Vector2(view.x * 0.5 - 500.0, view.y - 150.0)
	_controls.position = Vector2(16.0, 14.0)
	_score_label.text = "SCORE  %s" % _thousands(score.session)
	if score.line_tricks.is_empty():
		_line_label.text = ""
	else:
		var names := " + ".join(score.line_tricks.slice(maxi(score.line_tricks.size() - 5, 0)))
		if score.line_tricks.size() > 5:
			names = "... + " + names
		_line_label.text = "%s     %s x %d" % [names, _thousands(score.line_points), score.multiplier()]


func _on_trick(name: String, points: int) -> void:
	_flash("%s   +%s" % [name, _thousands(points)], Color(1, 1, 1))


func _on_banked(points: int, tricks: int) -> void:
	if tricks > 1:
		_flash("Line  +%s" % _thousands(points), Color(0.6, 1.0, 0.6))


## Punch the popup in, hold, then fade.
func _flash(text: String, color: Color) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_color", color)
	if _popup_tween:
		_popup_tween.kill()
	_popup.scale = Vector2(1.35, 1.35)
	_popup.modulate.a = 1.0
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_interval(1.1)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.5)


static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out
