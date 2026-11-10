extends SceneTree
## Testes de unidade da lógica do jogo (sem rede, sem tela).
## Rodar: godot --headless --path . -s tests/run_tests.gd
##   -- --only=nome   roda só os testes (ou arquivos) com "nome" no nome
##   -- --dir=pasta   procura os test_*.gd em outra pasta (usado por tools/runner_test.sh)
## Cada arquivo tests/test_*.gd tem funções test_*; asserts via o objeto `t`.
##
## Um teste só sai "ok" se as três coisas valerem:
##  1. nenhum t.check / t.near falhou;
##  2. nenhum erro de script aconteceu enquanto ele rodava. O GDScript não tem exceção: num
##     erro de script (propriedade de um null, assert, etc.) ele abandona a função no meio e
##     segue a vida, e os t.check que vinham depois nem rodam. Como as funções de teste são
##     `-> void`, o executor não tem como ver pelo retorno que o teste não chegou ao fim;
##     por isso ele escuta os erros direto do motor (ErrorSpy, abaixo);
##  3. ele fez pelo menos uma verificação (teste que não confere nada não prova nada).
## Arquivo de teste que não compila também é falha (antes travava o executor pra sempre).

var failures := 0
var passes := 0
var current := ""
## Quantos t.check / t.near o teste atual já fez.
var checks := 0

var _spy := ErrorSpy.new()
## Só vira true na última linha de _run_all(): se ficar false, o executor foi abandonado no meio.
var _finished := false


## Recebe do motor todos os erros que vão pro log e guarda os de script (Logger, Godot 4.5+).
## É assim que o executor fica sabendo de um teste abandonado sem mexer nos testes.
class ErrorSpy extends Logger:
	var _mutex := Mutex.new()   # o motor pode chamar _log_error de qualquer thread
	var _errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		# Só erro de script abandona a função. push_error/push_warning e erro do motor não
		# interrompem nada, então não contam aqui.
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_errors.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])
		_mutex.unlock()

	## Devolve os erros de script guardados desde a última chamada e esvazia a lista.
	func take() -> Array[String]:
		_mutex.lock()
		var out := _errors
		_errors = []
		_mutex.unlock()
		return out


func _initialize() -> void:
	OS.add_logger(_spy)
	_run_all()
	OS.remove_logger(_spy)
	# Rede de segurança: um erro de script no próprio executor abandona _run_all() no meio e
	# deixa testes sem rodar. O resumo e o quit() ficam aqui fora pra rodarem de qualquer jeito.
	var stray := _spy.take()
	if not _finished or not stray.is_empty():
		current = "run_tests"
		_fail("o executor foi interrompido por um erro de script; pode haver teste que não rodou" + _first(stray))
	print("")
	if failures == 0:
		print("== TESTES DE UNIDADE: %d ok ==" % passes)
	else:
		print("== TESTES DE UNIDADE: %d falha(s), %d ok ==" % [failures, passes])
	quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var only := ""
	var dir_path := "res://tests"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--dir="):
			dir_path = a.substr(6)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		current = "run_tests"
		_fail("não consegui abrir a pasta de testes '%s'" % dir_path)
		_finished = true
		return
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		# Arquivo que não compila: load() devolve um script que não instancia (ou null).
		# Vira uma falha com o nome do arquivo, mesmo com --only (sem compilar não dá pra
		# saber que testes ele tem), e o executor segue pros outros arquivos.
		current = f.get_basename()
		var script := load(dir_path.path_join(f)) as GDScript
		var suite: Object = null
		if script != null and script.can_instantiate():
			suite = script.new()
		var load_errors := _spy.take()
		if suite == null:
			_fail("o arquivo %s não carregou e nenhum teste dele rodou%s" % [f, _first(load_errors)])
			continue
		if not load_errors.is_empty():
			_fail("erro de script ao carregar o arquivo %s%s" % [f, _first(load_errors)])
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if only != "" and not mname.contains(only) and not f.contains(only):
				continue
			current = "%s::%s" % [f.get_basename(), mname]
			var before := failures
			checks = 0
			var start := Time.get_ticks_msec()
			suite.call(mname, self)
			var ms := Time.get_ticks_msec() - start
			var errors := _spy.take()
			if not errors.is_empty():
				_fail("erro de script durante o teste (a função que deu erro foi abandonada no meio)" + _first(errors))
			elif checks == 0:
				_fail("o teste terminou sem fazer nenhuma verificação (t.check / t.near)")
			if failures == before:
				passes += 1
				print("  ok   %s (%d ms)" % [current, ms])
	_finished = true


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		_fail(msg)


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (esperado %.4f, veio %.4f)" % [msg, b, a])


func _fail(msg: String) -> void:
	failures += 1
	print("  FAIL %s: %s" % [current, msg])


## ": <primeiro erro> (+N)" pra pendurar numa mensagem de falha; vazio se não houve erro.
## O texto completo de cada erro já saiu no log como SCRIPT ERROR.
func _first(errors: Array[String]) -> String:
	if errors.is_empty():
		return ""
	if errors.size() == 1:
		return ": " + errors[0]
	return ": %s (+%d erro(s) de script, veja os SCRIPT ERROR acima)" % [errors[0], errors.size() - 1]
