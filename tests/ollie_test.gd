class_name OllieTest
extends RefCounted

var failures: Array[String] = []
var tree: SceneTree


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if not (absf(actual - expected) <= tolerance):
		failures.append("%s: got %.6f, expected %.6f (tolerance %s)" % [message, actual, expected, tolerance])
