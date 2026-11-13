extends SceneTree

const TEST_DIR := "res://tests"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	var passed := 0
	var only := OS.get_environment("OLLIE_TEST")
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		var suite: OllieTest = script.new()
		suite.tree = self
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			if only != "" and not name.contains(only):
				continue
			suite.failures.clear()
			var start := Time.get_ticks_msec()
			await suite.call(name)
			var elapsed := Time.get_ticks_msec() - start
			if suite.failures.is_empty():
				passed += 1
				print("PASS %s.%s (%d ms)" % [file.get_basename(), name, elapsed])
			else:
				failures += 1
				print("FAIL %s.%s" % [file.get_basename(), name])
				for message in suite.failures:
					print("    " + message)
	print("%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)
