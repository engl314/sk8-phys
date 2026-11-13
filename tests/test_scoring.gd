extends OllieTest

func test_points_for_composed_names() -> void:
	var cases := {
		"Ollie": 100, "Kickflip": 250, "FS 180 Kickflip": 400, "Fakie Kickflip": 275,
		"Double Kickflip": 450, "Triple Heelflip": 650, "Late Kickflip": 375, "Nollie Kickflip": 288,
		"360 Flip": 600, "BS 360 Ollie": 450, "Indy": 200, "Kickflip Indy": 450, "Revert": 100,
		"Switch Kickflip": 300, "Switch FS 180 Ollie": 300,
	}
	for name in cases:
		check(ScoreKeeper.points_for(name) == cases[name], "%s: %d points (expected %d)" % [name, ScoreKeeper.points_for(name), cases[name]])
