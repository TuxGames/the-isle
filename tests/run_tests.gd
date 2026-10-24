extends SceneTree
## Testes de unidade da lógica do jogo (sem rede, sem tela).
## Rodar: godot --headless --path . -s tests/run_tests.gd
## Cada arquivo tests/test_*.gd tem funções test_*; asserts via o objeto `t`.

var failures := 0
var passes := 0
var current := ""


func _initialize() -> void:
	var files := []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var suite: Object = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if only != "" and not mname.contains(only) and not f.contains(only):
				continue
			current = "%s::%s" % [f.get_basename(), mname]
			var before := failures
			var start := Time.get_ticks_msec()
			suite.call(mname, self)
			var ms := Time.get_ticks_msec() - start
			if failures == before:
				passes += 1
				print("  ok   %s (%d ms)" % [current, ms])
	print("")
	if failures == 0:
		print("== TESTES DE UNIDADE: %d ok ==" % passes)
	else:
		print("== TESTES DE UNIDADE: %d falha(s), %d ok ==" % [failures, passes])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("  FAIL %s: %s" % [current, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (esperado %.4f, veio %.4f)" % [msg, b, a])
