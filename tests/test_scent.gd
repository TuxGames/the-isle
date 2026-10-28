extends RefCounted
## Faro (design, seção 10): pegadas guardadas no servidor (ScentTrail) e o WorldSim.sniff.

const DT := 1.0 / GameConfig.SIM_HZ
const ORIGIN := Vector3(200, 0, 200)


## Mundo de 512 m sem bots: só o que o teste puser.
func _world() -> WorldSim:
	return WorldSim.new(GameConfig.WORLD_SEED, 0, 512.0)


func _player(w: WorldSim, player_name: String, species: String, pos: Vector3) -> Dino:
	var p: Dino = w.login_player(player_name, species)["dino"]
	p.pos = pos
	return p


func _bot(w: WorldSim, species: String, pos: Vector3) -> Dino:
	var d := Dino.create(w.new_id(), species, 1.0, pos)
	d.is_bot = true
	w.dinos[d.id] = d
	return d


func _run(w: WorldSim, seconds: float) -> void:
	for i in int(seconds * GameConfig.SIM_HZ):
		w.step(DT)


## Anda `meters` em linha reta (no eixo x), `per_step` metros por passo, como o cliente faria.
func _walk(w: WorldSim, d: Dino, meters: float, per_step: float = 0.25) -> void:
	for i in int(meters / per_step):
		d.pos.x += per_step
		w.step(DT)


func _items(data: PackedFloat32Array, kind: int) -> Array:
	var out := []
	for i in range(0, data.size(), ScentTrail.STRIDE):
		if int(data[i + 4]) == kind:
			out.append(Vector3(data[i], data[i + 2], data[i + 1]))   # x, idade, z
	return out


func test_faro_pegada_so_andando(t) -> void:
	var w := _world()
	var p := _player(w, "tux", "carnotaurus", ORIGIN)
	_run(w, 5.0)
	t.check(w.scent.count() == 0, "parado não deixa pegada")
	_walk(w, p, 30.0)
	t.check(w.scent.count() == 10, "30 m andando = 10 pegadas de 3 em 3 m (veio %d)" % w.scent.count())
	_run(w, 5.0)
	t.check(w.scent.count() == 10, "parou: não deixa mais")


func test_faro_espacamento(t) -> void:
	var w := _world()
	var a := _player(w, "tux", "carnotaurus", ORIGIN)
	var b := _player(w, "marcelo", "carnotaurus", ORIGIN + Vector3(0, 0, 10))
	_run(w, 0.5)
	_walk(w, a, 40.0, 0.4)
	var prints := _items(w.sniff(b)["data"], ScentTrail.KIND_PRINT)
	t.check(prints.size() >= 12, "pegadas do caminho (veio %d)" % prints.size())
	for i in range(1, prints.size()):
		var gap := absf(prints[i].x - prints[i - 1].x)
		t.check(gap >= GameConfig.SCENT_SPACING_M - 0.01 and gap < GameConfig.SCENT_SPACING_M + 0.5,
				"uma pegada a cada ~%.0f m (veio %.2f)" % [GameConfig.SCENT_SPACING_M, gap])


func test_faro_raio_e_idade(t) -> void:
	var s := ScentTrail.new()
	var c := Vector3(100, 0, 100)
	s.add_print(c + Vector3(10, 0, 0), 0.0, 0, 7)
	s.add_print(c + Vector3(0, 0, 50), 0.0, 1, 7)
	s.add_print(c + Vector3(100, 0, 0), 0.0, 2, 7)
	var data := s.query(c, 60.0, 10.0, GameConfig.SCENT_MAX_AGE_S, -1)
	t.check(data.size() == 2 * ScentTrail.STRIDE, "só as 2 dentro de 60 m")
	t.near(data[2], 10.0, 0.001, "idade = tempo de mundo desde a pegada")
	t.check(int(data[3]) == 0 and int(data[ScentTrail.STRIDE + 3]) == 1, "espécie de quem passou")
	t.check(int(data[4]) == ScentTrail.KIND_PRINT, "tipo pegada")
	data = s.query(c, 60.0, 10.0 + GameConfig.SCENT_MAX_AGE_S, GameConfig.SCENT_MAX_AGE_S, -1)
	t.check(data.is_empty(), "mais velha que %d s não aparece" % int(GameConfig.SCENT_MAX_AGE_S))
	s.prune(10.0 + GameConfig.SCENT_MAX_AGE_S)
	t.check(s.count() == 0, "e sai da memória")


func test_faro_raio_por_especie(t) -> void:
	# Pegada a 50 m: o Carnotaurus (80 m) sente, o Triceratops (40 m) não.
	t.check(float(Species.DATA["carnotaurus"]["smell_radius"]) > 50.0, "carnotaurus > 50 m")
	t.check(float(Species.DATA["triceratops"]["smell_radius"]) < 50.0, "triceratops < 50 m")
	var w := _world()
	var walker := _player(w, "tux", "dryosaurus", ORIGIN + Vector3(0, 0, 50))
	var carno := _player(w, "marcelo", "carnotaurus", ORIGIN)
	var trike := _player(w, "ana", "triceratops", ORIGIN)
	_run(w, 0.5)
	_walk(w, walker, 3.0)
	t.check(_items(w.sniff(carno)["data"], ScentTrail.KIND_PRINT).size() == 1, "carnotaurus sente a 50 m")
	t.check(_items(w.sniff(trike)["data"], ScentTrail.KIND_PRINT).is_empty(), "triceratops não")


func test_faro_nao_mostra_as_proprias(t) -> void:
	var w := _world()
	var a := _player(w, "tux", "carnotaurus", ORIGIN)
	var b := _player(w, "marcelo", "carnotaurus", ORIGIN + Vector3(0, 0, 10))
	_run(w, 0.5)
	_walk(w, a, 15.0)
	t.check(w.sniff(a)["data"].is_empty(), "quem andou não vê as próprias pegadas")
	t.check(_items(w.sniff(b)["data"], ScentTrail.KIND_PRINT).size() == 5, "o outro vê as 5")


func test_faro_mundo_parado_nao_envelhece(t) -> void:
	var w := _world()
	var a := _player(w, "tux", "carnotaurus", ORIGIN)
	var b := _player(w, "marcelo", "carnotaurus", ORIGIN + Vector3(0, 0, 10))
	_run(w, 0.5)
	_walk(w, a, 3.0)
	var made := w.world_time
	# Sem ninguém online o servidor não chama o step: o relógio do mundo não anda, e o tempo
	# de verdade que passou não conta.
	OS.delay_msec(50)
	var data: PackedFloat32Array = w.sniff(b)["data"]
	t.check(data.size() == ScentTrail.STRIDE, "uma pegada")
	t.near(data[2], 0.0, 0.001, "não envelheceu com o mundo parado")
	_run(w, 60.0)
	t.near(w.scent.query(b.pos, 50.0, w.world_time, 1e9, -1)[2], w.world_time - made, 0.01,
			"com o mundo rodando, envelhece")
	_run(w, GameConfig.SCENT_MAX_AGE_S - 59.0)
	t.check(w.scent.count() == 0, "depois de %d s de mundo some" % int(GameConfig.SCENT_MAX_AGE_S))


func test_faro_limite_de_memoria(t) -> void:
	var s := ScentTrail.new()
	var total := GameConfig.SCENT_MAX_PRINTS * 3 + 17
	for i in total:
		s.add_print(Vector3(i % 100, 0, 0), float(i) * 0.001, 0, 1)
		if i % 50 == 0:
			s.prune(float(i) * 0.001)
	s.prune(float(total) * 0.001)
	t.check(s.count() == GameConfig.SCENT_MAX_PRINTS, "guarda no máximo %d (veio %d)" % [GameConfig.SCENT_MAX_PRINTS, s.count()])
	t.check(s._x.size() <= GameConfig.SCENT_MAX_PRINTS * 2 + 1024, "e não acumula o que já saiu")
	var data := s.query(Vector3(50, 0, 0), 1000.0, float(total) * 0.001, 1e9, -1)
	t.near(data[2], float(GameConfig.SCENT_MAX_PRINTS) * 0.001, 0.0005, "as mais velhas saíram primeiro")


func test_faro_recarga(t) -> void:
	var w := _world()
	var a := _player(w, "tux", "carnotaurus", ORIGIN)
	var b := _player(w, "marcelo", "dryosaurus", ORIGIN + Vector3(5, 0, 0))
	t.check(bool(w.sniff(a)["ok"]), "primeira vez: fareja")
	var again := w.sniff(a)
	t.check(not bool(again["ok"]), "logo depois: em recarga")
	t.near(float(again["wait"]), GameConfig.SNIFF_COOLDOWN_S, 0.001, "diz quanto falta")
	t.check(bool(w.sniff(b)["ok"]), "a recarga é de cada jogador")
	_run(w, GameConfig.SNIFF_COOLDOWN_S - 1.0)
	t.check(not bool(w.sniff(a)["ok"]), "1 s antes ainda não")
	# Sair e voltar não zera a recarga.
	w.logout_player(a.id)
	a = _player(w, "tux", "carnotaurus", ORIGIN)
	t.check(not bool(w.sniff(a)["ok"]), "relogar não zera a recarga")
	_run(w, 1.1)
	t.check(bool(w.sniff(a)["ok"]), "depois de %d s fareja de novo" % int(GameConfig.SNIFF_COOLDOWN_S))


func test_faro_teleporte_nao_deixa_rastro(t) -> void:
	var w := _world()
	var p := _player(w, "tux", "carnotaurus", ORIGIN)
	_run(w, 0.5)
	p.pos += Vector3(100, 0, 0)   # /tp, renascer, diretor
	w.step(DT)
	t.check(w.scent.count() == 0, "pulo de 100 m num passo não vira pegada")
	_walk(w, p, 6.0)
	t.check(w.scent.count() == 2, "andando depois do pulo volta a deixar")


func test_faro_carcacas(t) -> void:
	var w := _world()
	var p := _player(w, "tux", "carnotaurus", ORIGIN)
	var near := _bot(w, "dryosaurus", ORIGIN + Vector3(20, 0, 0))
	var far := _bot(w, "dryosaurus", ORIGIN + Vector3(0, 0, 200))
	w.kill(near, "teste")
	w.kill(far, "teste")
	var carc := _items(w.sniff(p)["data"], ScentTrail.KIND_CARCASS)
	t.check(carc.size() == 1, "carcaça perto aparece, a longe não")
	t.near(carc[0].x, near.pos.x, 0.01, "no lugar da carcaça")


func test_faro_bot_congelado_nao_deixa_rastro(t) -> void:
	var w := _world()
	var p := _player(w, "tux", "carnotaurus", Vector3(40, 0, 40))
	var bot := _bot(w, "triceratops", Vector3(460, 0, 460))   # ~590 m: congela
	var walker := _bot(w, "triceratops", Vector3(60, 0, 40))   # perto: roda
	_run(w, 0.5)
	t.check(bot.sim_tier == WorldSim.SimTier.FROZEN, "bot longe congela")
	for i in 40:
		bot.pos.x -= 0.25
		walker.pos.z += 0.25
		w.step(DT)
	var owners := {}
	for i in range(w.scent._start, w.scent._owner.size()):
		owners[w.scent._owner[i]] = true
	t.check(not owners.has(bot.id), "congelado não deixa pegada")
	t.check(owners.has(walker.id), "bot perto deixa")
	t.check(not owners.has(p.id), "jogador parado não deixa")
