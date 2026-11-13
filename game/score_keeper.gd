class_name ScoreKeeper
extends RefCounted

signal trick_scored(name: String, points: int)
signal line_banked(points: int, tricks: int)
signal line_lost()

const BASE := {
	"Ollie": 100, "Nollie": 120, "Pop Shove-it": 150, "FS Pop Shove-it": 150, "360 Shove-it": 320, "FS 360 Shove-it": 320,
	"Kickflip": 250, "Heelflip": 250, "Varial Kickflip": 400, "Varial Heelflip": 400, "Hardflip": 450, "Inward Heelflip": 450,
	"360 Flip": 600, "Laser Flip": 600, "360 Hardflip": 750, "360 Inward Heelflip": 750,
	"Mute": 200, "Melon": 220, "Indy": 200, "Stalefish": 260, "Nosegrab": 240, "Tailgrab": 220,
	"Revert": 100,
}
## Grinds: entry points plus points per second, by family.
const GRIND_RATE := {"50-50": 140, "5-0": 170, "Nosegrind": 190, "Boardslide": 170, "Noseslide": 210, "Tailslide": 200, "Darkslide": 400}
const MANUAL_RATE := 120
## Plain riding this long banks the line.
const BANK_DELAY := 1.3

var session := 0
var line_points := 0
var line_tricks: Array[String] = []
var _quiet := 0.0
var _skater: SkaterController


func _init(skater: SkaterController) -> void:
	_skater = skater
	skater.director.trick_landed.connect(_on_trick)
	skater.director.bailed.connect(_on_bail)
	skater.grind.grind_ended.connect(_on_grind)


func multiplier() -> int:
	return maxi(line_tricks.size(), 1)


func update(dt: float) -> void:
	var rider := _skater.rider
	var busy := not rider.is_grounded() or rider.state == RidingModel.State.GRIND or rider.manual_time > 0.0 or rider.state == RidingModel.State.SLIDE
	if line_tricks.is_empty() or busy:
		_quiet = 0.0
		return
	_quiet += dt
	if _quiet > BANK_DELAY:
		var total := line_points * multiplier()
		session += total
		line_banked.emit(total, line_tricks.size())
		line_points = 0
		line_tricks.clear()
		_quiet = 0.0


## Points for a landed trick name such as "Fakie FS 180 Double Kickflip Indy"
## (or "Switch ...").
static func points_for(name: String) -> int:
	if name.ends_with("Manual"):
		return 0
	var points := 0
	var words := name
	var factor := 1.0
	if words.begins_with("Fakie "):
		factor *= 1.1
		words = words.substr(6)
	elif words.begins_with("Switch "):
		factor *= 1.2
		words = words.substr(7)
	for spin in [[" 1080", 1400], [" 900", 1000], [" 720", 800], [" 540", 600], [" 360", 350], [" 180", 150]]:
		if words.contains(spin[0]) and (words.begins_with("FS") or words.begins_with("BS")):
			points += spin[1]
			words = words.substr(words.find(spin[0]) + spin[0].length() + 1)
			break
	if words.begins_with("Late "):
		factor *= 1.5
		words = words.substr(5)
	if words.begins_with("Nollie ") and words != "Nollie":
		factor *= 1.15
		words = words.substr(7)
	for multiple in [["Triple ", 2.6], ["Double ", 1.8]]:
		if words.contains(multiple[0]):
			factor *= multiple[1]
			words = words.replace(multiple[0], "")
	var best := ""
	for key in BASE:
		if words.begins_with(key) and key.length() > best.length():
			best = key
	if best != "":
		points += BASE[best]
		words = words.substr(best.length()).strip_edges()
	for grab in ["Mute", "Melon", "Indy", "Stalefish", "Nosegrab", "Tailgrab"]:
		if words.contains(grab):
			points += BASE[grab]
	return int(round(points * factor))


func _add(name: String, points: int) -> void:
	if points <= 0:
		return
	line_tricks.append(name)
	line_points += points
	_quiet = 0.0
	trick_scored.emit(name, points)


func _on_trick(name: String) -> void:
	if name.ends_with("Manual"):
		_add(name, int(_skater.director._last_manual_time * MANUAL_RATE) + 50)
		return
	_add(name, points_for(name))


func _on_grind(name: String, seconds: float) -> void:
	var family := name.get_slice(" ", 1) if name.contains(" ") else name
	var rate: int = GRIND_RATE.get(family, 150)
	_add(name, 100 + int(rate * seconds))


func _on_bail(_reason: String) -> void:
	if not line_tricks.is_empty():
		line_lost.emit()
	line_points = 0
	line_tricks.clear()
	_quiet = 0.0
