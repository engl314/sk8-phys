class_name TrickTable

## [flip, shuv] -> trick. flip: 1 = kickflip button, -1 = heelflip button.
## shuv: 1 = backside shove-it button, -1 = frontside.
const COMBOS := {
	Vector2i(0, 0): "Ollie",
	Vector2i(1, 0): "Kickflip",
	Vector2i(-1, 0): "Heelflip",
	Vector2i(0, 1): "PopShuvit",
	Vector2i(0, -1): "FSPopShuvit",
	Vector2i(1, 1): "VarialKickflip",
	Vector2i(1, -1): "Hardflip",
	Vector2i(-1, -1): "VarialHeelflip",
	Vector2i(-1, 1): "InwardHeelflip",
}

## Holding the shove-it button spins these round to their 360 versions.
const SPUN := {
	"PopShuvit": "360PopShuvit",
	"FSPopShuvit": "FS360PopShuvit",
	"VarialKickflip": "360Flip",
	"VarialHeelflip": "Laserflip",
	"Hardflip": "360Hardflip",
	"InwardHeelflip": "360InwardHeelflip",
}

const TRICKS := {
	"Ollie": {"name": "Ollie", "flip": 0.0, "shuv": 0.0, "hard": false, "time": 0.0},
	"Kickflip": {"name": "Kickflip", "flip": 1.0, "shuv": 0.0, "hard": false, "time": 0.36},
	"Heelflip": {"name": "Heelflip", "flip": -1.0, "shuv": 0.0, "hard": false, "time": 0.36},
	"PopShuvit": {"name": "Pop Shove-it", "flip": 0.0, "shuv": 0.5, "hard": false, "time": 0.32},
	"FSPopShuvit": {"name": "FS Pop Shove-it", "flip": 0.0, "shuv": -0.5, "hard": false, "time": 0.32},
	"360PopShuvit": {"name": "360 Shove-it", "flip": 0.0, "shuv": 1.0, "hard": false, "time": 0.42},
	"FS360PopShuvit": {"name": "FS 360 Shove-it", "flip": 0.0, "shuv": -1.0, "hard": false, "time": 0.42},
	"VarialKickflip": {"name": "Varial Kickflip", "flip": 1.0, "shuv": 0.5, "hard": false, "time": 0.4},
	"VarialHeelflip": {"name": "Varial Heelflip", "flip": -1.0, "shuv": -0.5, "hard": false, "time": 0.4},
	"Hardflip": {"name": "Hardflip", "flip": 1.0, "shuv": -0.5, "hard": true, "time": 0.42},
	"InwardHeelflip": {"name": "Inward Heelflip", "flip": -1.0, "shuv": 0.5, "hard": true, "time": 0.42},
	"360Flip": {"name": "360 Flip", "flip": 1.0, "shuv": 1.0, "hard": false, "time": 0.46},
	"Laserflip": {"name": "Laser Flip", "flip": -1.0, "shuv": -1.0, "hard": false, "time": 0.46},
	"360Hardflip": {"name": "360 Hardflip", "flip": 1.0, "shuv": -1.0, "hard": true, "time": 0.5},
	"360InwardHeelflip": {"name": "360 Inward Heelflip", "flip": -1.0, "shuv": 1.0, "hard": true, "time": 0.5},
}


## Trick key for a button combination; nollie keys carry an N_ prefix.
static func trick_for_buttons(flip: int, shuv: int, nollie: bool) -> String:
	var key: String = COMBOS[Vector2i(signi(flip), signi(shuv))]
	if not nollie:
		return key
	return "Nollie" if key == "Ollie" else "N_" + key


## The 360 version of a half-turn shove-it trick, or "" if there is none.
static func spun(key: String) -> String:
	var nollie := key.begins_with("N_")
	var base := key.substr(2) if nollie else key
	if not SPUN.has(base):
		return ""
	return ("N_" if nollie else "") + SPUN[base]


## Definition for a trick key; nollie keys reuse the base trick's motion.
static func definition(key: String) -> Dictionary:
	var nollie := key.begins_with("N_") or key == "Nollie"
	var base := key.substr(2) if key.begins_with("N_") else ("Ollie" if key == "Nollie" else key)
	var def: Dictionary = TRICKS.get(base, TRICKS.Ollie).duplicate()
	def["nollie"] = nollie
	if nollie:
		def.name = "Nollie" if base == "Ollie" else "Nollie " + def.name
	return def
