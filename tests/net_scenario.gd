extends Node
## Cliente automático usado por tools/net_test.sh. Conecta num servidor de verdade,
## faz um roteiro e imprime "TEST PASS: ..." / "TEST FAIL: ...".
##
## Papéis (--role=):
##   alice       carnívoro: vira adulto, erra um golpe de costas, acerta o bob de frente,
##               confere que o bob some quando sai, fica jogando mais um pouco e sai.
##   bob         dryosaurus novo: confere que nasce jovem, espera ser mordido (fica sangrando,
##               com osso quebrado e mordida funda), para o sangramento (/hurt), grava o
##               próprio estado em --out e sai.
##   bob_return  entra de novo como bob e confere que voltou EXATAMENTE igual (--expect),
##               com os ferimentos congelados.
##   bob_die     entra, morre (/kill) e confere que renasce jovem.
##   map_check   entra como carla e confere que o mapa tem o tamanho de --expect-map-size
##               e que o servidor a colocou no chão desse mesmo terreno.
##   intruso     tenta entrar como bob com a senha errada e confere que é barrado.
##   troca_senha entra como dani, tenta trocar a senha com a atual errada (recusado) e
##               depois com a certa (aceito).
##   dani_nova   entra como dani com a senha nova.
##   admin_cria  entra como Tux (admin), cria um código de boost com 2 usos e grava em --out.
##   resgata     entra como eva (não é admin), resgata o código de --code-file, não consegue
##               resgatar de novo nem criar código, e recebe o boost nos próprios status.
##   rastro      entra como fred (dryosaurus), vai pra (150, 150) com /tp, anda 30 m pro leste e sai.
##   fareja      entra como gil (carnotaurus), vai pra perto do caminho do fred, anda um pouco,
##               fareja (F): recebe as pegadas do fred e não as próprias; farejar de novo logo
##               em seguida dá "em recarga".
##   ninho       entra como hana (dryosaurus), vira adulta, faz o ninho segurando N (c_nest),
##               faz postura com um bot (/spawn + R), recebe os ovos (s_nests), choca (/hatch),
##               morre e nasce no ninho como filhote ("Nascer no ninho").
##
## Cada nome entra com a senha "senha-<nome>" (só a chave dela viaja, como no jogo).

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
	Net.login_failed.connect(_on_login_failed)
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
	var species := "carnotaurus" if role in ["alice", "fareja"] else "dryosaurus"
	var pname := "alice" if role == "alice" else ("carla" if role == "map_check" else "bob")
	if role == "rastro":
		pname = "fred"
	elif role == "fareja":
		pname = "gil"
	elif role in ["troca_senha", "dani_nova"]:
		pname = "dani"
	elif role == "admin_cria":
		pname = "Tux"
	elif role == "resgata":
		pname = "eva"
	elif role == "ninho":
		pname = "hana"
	var password := "chute-errado" if role == "intruso" else "senha-" + pname
	if role == "dani_nova":
		password = "nova-dani"
	Net.c_password.rpc_id(1, Accounts.client_key(pname, password))
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
		"map_check":
			_map_check()
		"intruso":
			_intruso()
		"troca_senha":
			_troca_senha()
		"dani_nova":
			_dani_nova()
		"admin_cria":
			_admin_cria()
		"resgata":
			_resgata()
		"rastro":
			_rastro()
		"fareja":
			_fareja()
		"ninho":
			_ninho()


func _on_login_failed(reason: String) -> void:
	if role == "intruso":
		_check(reason.begins_with("Senha errada"), "barrado com a senha errada (\"%s\")" % reason)
	else:
		_fail("login recusado: " + reason)
	_finish()


func _troca_senha() -> void:
	var answers: Array = []
	Net.password_changed.connect(func(ok, text): answers.append([ok, text]))
	if not await _wait_for(func(): return not welcome.is_empty(), 10.0):
		_fail("não entrou")
		return _finish()
	Net.c_set_password.rpc_id(1, Accounts.client_key("dani", "chute"), Accounts.client_key("dani", "nova-dani"))
	if not await _wait_for(func(): return answers.size() >= 1, 10.0):
		_fail("sem resposta da troca de senha")
		return _finish()
	_check(not answers[0][0], "senha atual errada: não troca (\"%s\")" % answers[0][1])
	Net.c_set_password.rpc_id(1, Accounts.client_key("dani", "senha-dani"), Accounts.client_key("dani", "nova-dani"))
	if not await _wait_for(func(): return answers.size() >= 2, 10.0):
		_fail("sem resposta da segunda troca")
		return _finish()
	_check(answers[1][0], "senha atual certa: troca (\"%s\")" % answers[1][1])
	_finish()


func _dani_nova() -> void:
	_check(await _wait_for(func(): return not welcome.is_empty(), 10.0), "entrou com a senha nova")
	_finish()


func _admin_cria() -> void:
	var answers: Array = []
	Net.staff_codes.connect(func(list, created, text): answers.append([list, created, text]))
	if not await _wait_for(func(): return not welcome.is_empty(), 10.0):
		_fail("não entrou")
		return _finish()
	_check(bool(welcome.get("admin", false)), "Tux é admin")
	Net.c_staff_create_code.rpc_id(1, "boost_crescimento", "60", 2, 0)
	if not await _wait_for(func(): return answers.any(func(a): return a[1] != ""), 10.0):
		_fail("o código não foi criado")
		return _finish()
	var made: Array = answers.filter(func(a): return a[1] != "")[0]
	var code: String = made[1]
	_check(code.begins_with("DINO-") and code.length() == 14, "código criado (%s)" % code)
	_check(Array(made[0]).any(func(e): return e["code"] == code), "aparece na lista")
	var f := FileAccess.open(String(args.get("out", "")), FileAccess.WRITE)
	f.store_string(code)
	f.close()
	_finish()


func _resgata() -> void:
	var results: Array = []
	var staff: Array = []
	Net.redeem_result.connect(func(ok, text, perks): results.append([ok, text, perks]))
	Net.staff_codes.connect(func(list, created, text): staff.append([list, created, text]))
	if not await _wait_for(func(): return not welcome.is_empty(), 10.0):
		_fail("não entrou")
		return _finish()
	_check(not bool(welcome.get("admin", false)), "eva não é admin")
	var code := FileAccess.get_file_as_string(String(args.get("code-file", ""))).strip_edges()
	Net.c_redeem_code.rpc_id(1, code.to_lower())
	if not await _wait_for(func(): return results.size() >= 1, 10.0):
		_fail("sem resposta do resgate")
		return _finish()
	_check(results[0][0], "resgatou (\"%s\")" % results[0][1])
	Net.c_redeem_code.rpc_id(1, code)
	if not await _wait_for(func(): return results.size() >= 2, 10.0):
		_fail("sem resposta do segundo resgate")
		return _finish()
	_check(not results[1][0], "não resgata o mesmo código de novo (\"%s\")" % results[1][1])
	_check(await _wait_for(func(): return stats.size() > Net.ST_GROWTH_BOOST and stats[Net.ST_GROWTH_BOOST] > 3000.0, 5.0),
			"recebeu o boost de 60 min")
	Net.c_staff_create_code.rpc_id(1, "acesso_beta", "", 1, 0)
	if not await _wait_for(func(): return staff.size() >= 1, 10.0):
		_fail("sem resposta ao tentar criar código")
		return _finish()
	_check(staff[0][1] == "" and Array(staff[0][0]).is_empty(), "quem não é admin não cria código (\"%s\")" % staff[0][2])
	_finish()


## Tenta entrar como bob com a senha errada: o servidor tem que recusar, não pode dar o dino.
func _intruso() -> void:
	await _wait(8.0)
	_fail("entrou como bob com a senha errada" if not welcome.is_empty() else "o servidor não respondeu")
	_finish()


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
		# Carnotauro adulto (1.500 kg) quebra o osso de um dryosaurus (90 kg): os outros veem ele
		# mancar mesmo com a vida acima do limite de mancar.
		var limp := await _wait_for(func(): return entities.has(bob_id) and (int(entities[bob_id][2]) & Net.SF_LIMP) != 0, 2.0)
		_check(limp, "bob manca de osso quebrado (visto pela alice)")

	# Bob sai depois de ser mordido: o dino dele tem que sumir do mundo.
	var gone := await _wait_for(func(): return not entities.has(bob_id), 15.0 + GameConfig.COMBAT_LOGOUT_S)
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
	# Ferimentos da mordida (Injuries.from_hit): a mordida tira mais da metade da vida dele.
	var hurt := await _wait_for(func(): return stats[Net.ST_BLEED] > 0.0 and stats[Net.ST_FRACTURE] > 0.0 \
			and stats[Net.ST_DEEP] > 0.0, 2.0)
	_check(hurt, "ficou sangrando, com osso quebrado e mordida funda (%.0f / %.0f / %.0f s)" % [
			stats[Net.ST_BLEED], stats[Net.ST_FRACTURE], stats[Net.ST_DEEP]])
	_check(stats[Net.ST_SPRINT] <= stats[Net.ST_WALK] + 0.001,
			"osso quebrado não corre (andar %.2f, correr %.2f)" % [stats[Net.ST_WALK], stats[Net.ST_SPRINT]])
	var hp_bleed: float = stats[Net.ST_HEALTH]
	await _wait(1.0)
	_check(stats[Net.ST_HEALTH] < hp_bleed - 0.01, "sangrando perde vida (%.2f → %.2f)" % [hp_bleed, stats[Net.ST_HEALTH]])
	# Espera passar o tempo de briga: quem sai logo depois de apanhar deixa o dino mais um pouco
	# no mundo (test_world cobre isso). Aqui o bob tem que voltar exatamente igual.
	await _wait(GameConfig.COMBAT_LOGOUT_S + 0.5)
	# Fome e sede em 20%: não cura nem passa fome rápido, então a vida fica parada
	# e dá pra comparar com precisão quando ele voltar.
	# O sangramento também tiraria vida; para ele com o comando de dev. A fratura e a mordida
	# funda continuam e têm que voltar congeladas.
	_dev("/hurt sangramento 0")
	_dev("/food 20 20")
	await _wait(0.6)
	_check(stats[Net.ST_BLEED] == 0.0 and stats[Net.ST_FRACTURE] > 0.0, "/hurt parou só o sangramento")
	var snap := {
		"health": stats[Net.ST_HEALTH], "hunger": stats[Net.ST_HUNGER],
		"thirst": stats[Net.ST_THIRST], "growth": stats[Net.ST_GROWTH],
		"stamina": stats[Net.ST_STAMINA], "x": my_pos.x, "z": my_pos.z,
		"fracture": stats[Net.ST_FRACTURE], "deep": stats[Net.ST_DEEP],
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
	# Ferimentos: só andam com o bob online. Entre gravar e voltar ele fica online menos de 1 s
	# no total (a fome, com eps 0,05, já garante isso), então o tempo que falta caiu no máximo
	# esse tanto e nunca subiu.
	for key in [["fracture", Net.ST_FRACTURE, "osso quebrado"], ["deep", Net.ST_DEEP, "mordida funda"]]:
		var want := float(expect[key[0]])
		var got: float = stats[key[1]]
		_check(got <= want + 0.001 and got > want - 1.0, "%s congelado (%.2f s vs %.2f s)" % [key[2], got, want])
	_check(stats[Net.ST_BLEED] == 0.0, "sem sangramento (parou antes de sair)")
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


## O tamanho do mapa vem no s_welcome; o cliente gera o mesmo terreno e a posição que o
## servidor deu tem que cair dentro dele, no chão.
func _map_check() -> void:
	var ok := await _wait_for(func(): return not welcome.is_empty() and my_seq > 0, 5.0)
	_check(ok, "recebeu o welcome e a posição")
	if ok:
		var want := float(args.get("expect-map-size", GameConfig.DEFAULT_MAP_SIZE))
		var got := float(welcome.get("map_size", -1.0))
		_check(got == want, "mapa de %d m (veio %d)" % [want, got])
		var ter := Terrain.get_shared(int(welcome["seed"]), got)
		_check(ter.size == want, "terreno local do mesmo tamanho")
		var inside := my_pos.x >= ter.play_min and my_pos.x <= ter.play_max \
				and my_pos.z >= ter.play_min and my_pos.z <= ter.play_max
		_check(inside, "nasceu dentro do mapa (%.0f, %.0f)" % [my_pos.x, my_pos.z])
		_check(absf(my_pos.y - ter.height_at(my_pos.x, my_pos.z)) < 0.05, "nasceu no chão do mesmo terreno")
	_finish()


## Vai pra (x, z) com /tp e espera o servidor mandar a posição nova.
func _teleport(x: int, z: int) -> bool:
	var seq0 := my_seq
	_dev("/tp %d %d" % [x, z])
	return await _wait_for(func(): return my_seq > seq0 and Vector2(my_pos.x - x, my_pos.z - z).length() < 1.0, 5.0)


## Anda em linha reta, a ~5 m/s, mandando a posição como o jogo manda (c_state a 20 Hz).
func _walk_line(dir: Vector3, meters: float) -> void:
	var done := 0.0
	while done < meters:
		await get_tree().process_frame
		var step := minf(5.0 * get_process_delta_time(), meters - done)
		my_pos += dir * step
		done += step
	await _wait(0.3)


## Faro (design, seção 10): deixa um rastro de pegadas pro gil farejar.
func _rastro() -> void:
	if not await _wait_for(func(): return my_seq > 0, 10.0):
		_fail("não recebeu a posição")
		return _finish()
	if not await _teleport(150, 150):
		_fail("/tp não chegou")
		return _finish()
	await _wait(0.5)
	await _walk_line(Vector3(1, 0, 0), 30.0)
	_check(Vector2(my_pos.x - 180.0, my_pos.z - 150.0).length() < 0.5, "andou 30 m (até %.0f, %.0f)" % [my_pos.x, my_pos.z])
	_finish()


func _fareja() -> void:
	var answers: Array = []
	Net.scent_received.connect(func(ok, data, cooldown): answers.append([ok, data, cooldown]))
	if not await _wait_for(func(): return my_seq > 0, 10.0):
		_fail("não recebeu a posição")
		return _finish()
	if not await _teleport(165, 190):
		_fail("/tp não chegou")
		return _finish()
	await _wait(0.5)
	# Anda 12 m pro sul: deixa pegadas próprias, que o faro não pode mostrar.
	await _walk_line(Vector3(0, 0, -1), 12.0)
	Net.c_sniff.rpc_id(1)
	if not await _wait_for(func(): return answers.size() >= 1, 5.0):
		_fail("sem resposta do faro")
		return _finish()
	_check(bool(answers[0][0]), "farejou")
	var data: PackedFloat32Array = answers[0][1]
	var prints := 0
	var own := 0
	var dryo := Species.index_of("dryosaurus")
	for i in range(0, data.size(), ScentTrail.STRIDE):
		if int(data[i + 4]) != ScentTrail.KIND_PRINT:
			continue
		prints += 1
		if absf(data[i + 1] - 150.0) > 1.0 or int(data[i + 3]) != dryo:
			own += 1
	_check(prints >= 8, "recebeu as pegadas do fred (%d)" % prints)
	_check(own == 0, "nenhuma pegada própria nem de outro lugar (%d)" % own)
	Net.c_sniff.rpc_id(1)
	if not await _wait_for(func(): return answers.size() >= 2, 5.0):
		_fail("sem resposta do segundo faro")
		return _finish()
	_check(not bool(answers[1][0]) and float(answers[1][2]) > GameConfig.SNIFF_COOLDOWN_S - 5.0,
			"logo depois: em recarga (%.0f s)" % float(answers[1][2]))
	_finish()


## Reprodução (design, seção 8) pelo caminho de rede de verdade: N segurado (c_nest), R (c_mate),
## ovos no s_nests, choco, morte e "Nascer no ninho" (Action.RESPAWN com "nest").
func _ninho() -> void:
	var lists: Array = []
	Net.nests_received.connect(func(list, mine): lists.append([list, mine]))
	if not await _wait_for(func(): return stats.size() >= Net.ST_COUNT and my_seq > 0 and not welcome.is_empty(), 10.0):
		_fail("não recebeu os próprios status")
		return _finish()
	_check(await _wait_for(func(): return not lists.is_empty(), 3.0), "recebeu os ninhos no login")
	_check(int(stats[Net.ST_NEST_EGGS]) == -1, "começa sem ninho")
	_dev("/grow 1")
	_dev("/food 100 100")
	var spot := _flat_spot()
	if not await _teleport(int(spot.x), int(spot.z)):
		_fail("/tp não chegou")
		return _finish()
	await _wait_for(func(): return stats[Net.ST_GROWTH] > 0.99, 3.0)

	# Ninho: segura N parado; o servidor conta os 8 s.
	Net.c_nest.rpc_id(1, true)
	_check(await _wait_for(func(): return stats[Net.ST_NEST_BUILD] > 0.2, 4.0),
			"segurando N: o progresso aparece (%.0f%%)" % (stats[Net.ST_NEST_BUILD] * 100.0))
	var built := await _wait_for(func(): return int(stats[Net.ST_NEST_EGGS]) == 0, GameConfig.NEST_BUILD_S + 3.0)
	Net.c_nest.rpc_id(1, false)
	_check(built, "ninho pronto depois de 8 s parado")
	var mine := func() -> Dictionary:
		for n in (lists[-1][0] if not lists.is_empty() else []):
			if n["owner"] == "hana":
				return n
		return {}
	_check(await _wait_for(func(): return not mine.call().is_empty(), 2.0), "o ninho chegou no s_nests")
	if not built:
		return _finish()
	var nest_pos: Vector3 = mine.call()["pos"]

	# Parceiro: um dryosaurus adulto (bot) do lado; R faz a postura.
	var known := entities.keys()
	_dev("/spawn dryosaurus 1")
	var dryo := Species.index_of("dryosaurus")
	var find_bot := func() -> int:
		for id in entities:
			var e: Array = entities[id]
			if not known.has(id) and id != my_id and e[3] == dryo and (int(e[2]) & Net.SF_PLAYER) == 0 and e[4] > 0.99:
				return id
		return 0
	if not await _wait_for(func(): return find_bot.call() != 0, 5.0):
		_fail("o bot do /spawn não apareceu")
		return _finish()
	var bot_id: int = find_bot.call()
	var laid := false
	for attempt in 4:
		# O bot passeia: chega do lado dele (a ~2 m) logo antes de apertar R.
		var bp: Vector3 = entities[bot_id][0]
		var dir := Vector3(nest_pos.x - bp.x, 0, nest_pos.z - bp.z).normalized()
		my_pos = bp + dir * 2.0
		await _wait(0.25)
		Net.c_mate.rpc_id(1)
		laid = await _wait_for(func(): return int(stats[Net.ST_NEST_EGGS]) == 4, 2.0)
		if laid:
			break
	_check(laid, "postura com o bot: 4 ovos no ninho (%d)" % int(stats[Net.ST_NEST_EGGS]))
	_check(stats[Net.ST_LAY_COOLDOWN] > GameConfig.LAY_COOLDOWN_S - 60.0, "recarga da postura no HUD (%.0f s)" % stats[Net.ST_LAY_COOLDOWN])
	_check(stats[Net.ST_NEST_HATCH] > GameConfig.INCUBATION_S - 60.0, "chocam em 20 min (%.0f s)" % stats[Net.ST_NEST_HATCH])
	_check(await _wait_for(func(): return Array(mine.call().get("eggs", [])).size() == 4, 2.0), "o cliente recebeu os 4 ovos")
	if not laid:
		return _finish()

	# Choca agora: 1 ovo fica pronto pra hana, os outros 3 viram bots filhotes.
	var before := entities.keys()
	_dev("/hatch")
	_check(await _wait_for(func(): return Array(mine.call().get("eggs", [])).size() == 1 \
			and Array(mine.call().get("ready", [])).size() == 1, 3.0), "chocou: sobrou 1 ovo pronto pra ela")
	var babies := func() -> int:
		var n := 0
		for id in entities:
			var e: Array = entities[id]
			if not before.has(id) and e[3] == dryo and absf(e[4] - GameConfig.HATCHLING_GROWTH) < 0.01:
				n += 1
		return n
	_check(await _wait_for(func(): return babies.call() == 3, 2.0), "3 filhotes nasceram como bots (%d)" % babies.call())
	_check(bool(lists[-1][1].get("ready", false)), "o servidor avisa que tem ovo pronto pra ela")

	# Morre e nasce no ninho, filhote.
	_dev("/kill")
	if not await _wait_for(func(): return died_cause != "", 5.0):
		_fail("não morreu")
		return _finish()
	welcome = {}
	stats = PackedFloat32Array()
	Net.c_action.rpc_id(1, Net.Action.RESPAWN, Nests.RESPAWN_ARG)
	var back := await _wait_for(func(): return not welcome.is_empty() and stats.size() > 0, 5.0)
	_check(back, "nasceu no ninho")
	if back:
		await _wait(0.3)
		_check(welcome["species"] == "dryosaurus", "da espécie do ninho")
		_check(absf(stats[Net.ST_GROWTH] - GameConfig.PLAYER_START_GROWTH) < 0.01, "filhote (crescimento %.2f)" % stats[Net.ST_GROWTH])
		_check(Movement.flat_distance(my_pos, nest_pos) < Nests.NEST_RADIUS_M + 0.2,
				"em cima do ninho (%.1f m)" % Movement.flat_distance(my_pos, nest_pos))
		_check(await _wait_for(func(): return mine.call().is_empty(), 2.0), "sem ovos, o ninho sumiu")
	_finish()


## Lugar plano em terra firme (o mesmo terreno do servidor), com folga em volta.
func _flat_spot() -> Vector3:
	var ter := Terrain.get_shared(int(welcome["seed"]), float(welcome["map_size"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		var p := ter.random_land_point(rng)
		p = Vector3(roundi(p.x), 0.0, roundi(p.z))
		var ok := true
		for off in [Vector3.ZERO, Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 12), Vector3(0, 0, -12)]:
			if Nests.spot_error(ter, p + off) != "":
				ok = false
		if ok:
			return p
	return Vector3(300, 0, 300)
