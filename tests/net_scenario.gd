extends Node
## Cliente automático usado por tools/net_test.sh. Conecta num servidor de verdade,
## faz um roteiro e imprime "TEST PASS: ..." / "TEST FAIL: ...".
##
## Papéis (--role=):
##   alice       carnívoro: vira adulto, erra um golpe de costas, acerta o bob de frente,
##               confere que o bob some quando sai, fica jogando mais um pouco e sai.
##   bob         dryosaurus novo: confere que nasce jovem, espera ser mordido, grava o
##               próprio estado em --out e sai.
##   bob_return  entra de novo como bob e confere que voltou EXATAMENTE igual (--expect).
##   bob_die     entra, morre (/kill) e confere que renasce jovem.

var args := {}
var role := ""
var my_id := 0
var my_seq := 0
var my_pos := Vector3.ZERO
var my_yaw := 0.0
var stats := PackedFloat32Array()
var welcome := {}
var roster := {}
## id -> [pos, yaw, flags, species_index, growth]
var entities := {}
var events: Array = []
var died_cause := ""
var failures := 0
var passes := 0
var _send_accum := 0.0


func run(p_args: Dictionary) -> void:
	args = p_args
	role = String(args.get("role", "alice"))
	Net.welcome_received.connect(func(info): welcome = info; my_id = int(info["entity_id"]))
	Net.login_failed.connect(func(r): _fail("login recusado: " + r); _finish())
	Net.teleport_received.connect(func(seq, pos, yaw): my_seq = seq; my_pos = pos; my_yaw = yaw)
	Net.self_stats_received.connect(func(st): stats = st)
	Net.roster_received.connect(func(r): roster = r)
	Net.snapshot_received.connect(_on_snapshot)
	Net.event_received.connect(func(k, a, b, v, t): events.append([k, a, b, v, t]))
	Net.died.connect(func(c): died_cause = c)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("conexão falhou"); _finish())
	var err := Net.connect_to(String(args.get("host", "127.0.0.1")), int(args.get("port", GameConfig.DEFAULT_PORT)))
	if err != OK:
		_fail("connect_to: " + error_string(err))
		_finish()
	get_tree().create_timer(float(args.get("timeout", 60.0))).timeout.connect(func():
		_fail("tempo esgotado no papel " + role)
		_finish())


func _on_snapshot(data: PackedFloat32Array) -> void:
	entities.clear()
	var i := 0
	while i + Net.SNAP_STRIDE <= data.size():
		entities[int(data[i])] = [Vector3(data[i + 3], data[i + 4], data[i + 5]), data[i + 6],
				int(data[i + 7]), int(data[i + 1]), data[i + 2]]
		i += Net.SNAP_STRIDE


func _process(delta: float) -> void:
	if my_id == 0 or my_seq == 0:
		return
	_send_accum += delta
	if _send_accum >= 1.0 / GameConfig.CLIENT_SEND_HZ:
		_send_accum = 0.0
		Net.c_state.rpc_id(1, my_seq, my_pos, my_yaw, 0)


func _on_connected() -> void:
	var species := "carnotaurus" if role == "alice" else "dryosaurus"
	var pname := "alice" if role == "alice" else "bob"
	Net.c_login.rpc_id(1, pname, species, GameConfig.VERSION)
	match role:
		"alice":
			_alice()
		"bob":
			_bob()
		"bob_return":
			_bob_return()
		"bob_die":
			_bob_die()


# ---------------------------------------------------------------- utilitários

func _pass(what: String) -> void:
	passes += 1
	print("TEST PASS: [%s] %s" % [role, what])


func _fail(what: String) -> void:
	failures += 1
	print("TEST FAIL: [%s] %s" % [role, what])


func _check(cond: bool, what: String) -> void:
	if cond:
		_pass(what)
	else:
		_fail(what)


func _finish() -> void:
	print("TEST DONE: [%s] %d ok, %d falhas" % [role, passes, failures])
	Net.disconnect_from_server()
	get_tree().quit(1 if failures > 0 else 0)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


## Espera uma condição (Callable que devolve bool) até `secs`. Devolve se aconteceu.
func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _dev(cmd: String) -> void:
	Net.c_action.rpc_id(1, Net.Action.DEV, cmd)


func _id_of(pname: String) -> int:
	for k in roster:
		if roster[k] == pname:
			return int(k)
	return 0


func _hits_by(attacker: int) -> Array:
	return events.filter(func(e): return e[0] == WorldSim.Ev.HIT and e[1] == attacker)


# ---------------------------------------------------------------- papéis

func _alice() -> void:
	if not await _wait_for(func(): return stats.size() > 0, 10.0):
		_fail("não recebeu os próprios status")
		return _finish()
	_dev("/grow 1")
	await _wait_for(func(): return stats[Net.ST_GROWTH] > 0.99, 3.0)
	_check(stats[Net.ST_GROWTH] > 0.99, "comando /grow virou adulto")

	if not await _wait_for(func(): return _id_of("bob") != 0 and entities.has(_id_of("bob")), 20.0):
		_fail("bob não apareceu no mundo")
		return _finish()
	var bob_id := _id_of("bob")
	var bob_pos: Vector3 = entities[bob_id][0]
	_pass("vê o bob no mundo (id %d)" % bob_id)

	# Fica a ~3,4 m do bob. De costas pra ele, o golpe tem que errar.
	var dir := Vector3(1.0, 0.0, 0.0)
	my_pos = bob_pos - dir * 3.4
	my_yaw = atan2(-dir.x, -dir.z)
	await _wait(0.5)
	events.clear()
	Net.c_action.rpc_id(1, Net.Action.ATTACK, "")
	await _wait(1.3)
	_check(_hits_by(my_id).is_empty(), "mordida de costas NÃO acerta (hitbox)")

	# De frente pro bob o golpe tem que acertar.
	my_yaw = atan2(dir.x, dir.z)
	await _wait(0.5)
	events.clear()
	Net.c_action.rpc_id(1, Net.Action.ATTACK, "")
	var hit := await _wait_for(func(): return not _hits_by(my_id).is_empty(), 2.0)
	_check(hit, "mordida de frente acerta o bob")
	if hit:
		var e: Array = _hits_by(my_id)[0]
		_check(e[2] == bob_id and e[3] > 0.0, "dano registrado no bob (%.1f, parte: %s)" % [e[3], e[4]])

	# Bob sai depois de ser mordido: o dino dele tem que sumir do mundo.
	var gone := await _wait_for(func(): return not entities.has(bob_id), 15.0)
	_check(gone, "dino do bob some quando ele sai")

	# Alice continua jogando sozinha: o mundo segue andando.
	var t0: float = stats[Net.ST_WORLD_TIME]
	await _wait(4.0)
	_check(stats[Net.ST_WORLD_TIME] > t0 + 3.0, "mundo anda com alguém online (%.1f → %.1f)" % [t0, stats[Net.ST_WORLD_TIME]])
	_finish()


func _bob() -> void:
	if not await _wait_for(func(): return stats.size() > 0, 10.0):
		_fail("não recebeu os próprios status")
		return _finish()
	_check(not bool(welcome.get("restored", true)), "conta nova (não restaurada)")
	_check(absf(stats[Net.ST_GROWTH] - GameConfig.PLAYER_START_GROWTH) < 0.01, "nasce jovem (crescimento %.2f)" % stats[Net.ST_GROWTH])
	# Vira adulto pra aguentar a mordida da alice sem morrer.
	_dev("/grow 1")
	await _wait_for(func(): return stats[Net.ST_GROWTH] > 0.99, 3.0)
	await _wait(0.3)
	var hp0: float = stats[Net.ST_HEALTH]
	var bitten := await _wait_for(func(): return stats[Net.ST_HEALTH] < hp0 - 0.01, 40.0)
	_check(bitten, "levou a mordida (vida %.1f → %.1f)" % [hp0, stats[Net.ST_HEALTH]])
	# Fome e sede em 20%: não cura nem passa fome rápido, então a vida fica parada
	# e dá pra comparar com precisão quando ele voltar.
	_dev("/food 20 20")
	await _wait(0.6)
	var snap := {
		"health": stats[Net.ST_HEALTH], "hunger": stats[Net.ST_HUNGER],
		"thirst": stats[Net.ST_THIRST], "growth": stats[Net.ST_GROWTH],
		"stamina": stats[Net.ST_STAMINA], "x": my_pos.x, "z": my_pos.z,
	}
	var f := FileAccess.open(String(args.get("out", "user://bob_state.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap))
	f.close()
	_pass("estado gravado: " + JSON.stringify(snap))
	_finish()


func _bob_return() -> void:
	if not await _wait_for(func(): return stats.size() > 0 and my_seq > 0, 10.0):
		_fail("não recebeu os próprios status")
		return _finish()
	_check(bool(welcome.get("restored", false)), "voltou com o dino salvo")
	var expect: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(args.get("expect", ""))))
	# O servidor manda status a 10 Hz; a primeira leitura já vale.
	var eps := 0.05
	_check(absf(stats[Net.ST_HEALTH] - float(expect["health"])) < 0.01, "vida igual (%.3f vs %.3f)" % [stats[Net.ST_HEALTH], expect["health"]])
	_check(absf(stats[Net.ST_HUNGER] - float(expect["hunger"])) < eps, "fome igual (%.3f vs %.3f)" % [stats[Net.ST_HUNGER], expect["hunger"]])
	_check(absf(stats[Net.ST_THIRST] - float(expect["thirst"])) < eps, "sede igual (%.3f vs %.3f)" % [stats[Net.ST_THIRST], expect["thirst"]])
	_check(absf(stats[Net.ST_GROWTH] - float(expect["growth"])) < 0.001, "crescimento igual (%.4f vs %.4f)" % [stats[Net.ST_GROWTH], expect["growth"]])
	_check(Vector2(my_pos.x - float(expect["x"]), my_pos.z - float(expect["z"])).length() < 0.5, "mesma posição")
	_finish()


func _bob_die() -> void:
	if not await _wait_for(func(): return stats.size() > 0, 10.0):
		_fail("não recebeu os próprios status")
		return _finish()
	_dev("/kill")
	var dead := await _wait_for(func(): return died_cause != "", 5.0)
	_check(dead, "morreu (%s)" % died_cause)
	welcome = {}
	stats = PackedFloat32Array()
	Net.c_action.rpc_id(1, Net.Action.RESPAWN, "carnotaurus")
	var back := await _wait_for(func(): return not welcome.is_empty() and stats.size() > 0, 5.0)
	_check(back, "renasceu")
	if back:
		await _wait(0.3)
		_check(welcome["species"] == "carnotaurus", "renasceu como a espécie escolhida")
		_check(absf(stats[Net.ST_GROWTH] - GameConfig.PLAYER_START_GROWTH) < 0.01, "renasceu jovem (crescimento %.2f)" % stats[Net.ST_GROWTH])
	_finish()
