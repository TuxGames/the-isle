extends RefCounted
## IA dos bots + teste de carga (quantos bots o servidor aguenta).


func _bot(w: WorldSim, species: String, growth: float, pos: Vector3) -> Dino:
	var d := Dino.create(w.new_id(), species, growth, pos)
	d.is_bot = true
	d.pos.y = Movement.ground_y(w.terrain, pos.x, pos.z, d.body_height())
	w.dinos[d.id] = d
	return d


func _think(w: WorldSim, b: Dino) -> String:
	w._rebuild_grid()
	BotBrain.think(w, b)
	return BotBrain.state_of(b)


func test_carnivoro_com_fome_caca(t) -> void:
	var w := WorldSim.new()
	var carno := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	_bot(w, "dryosaurus", 0.6, Vector3(220, 0, 200))
	carno.hunger = 30.0
	t.check(_think(w, carno) == "hunt", "carnotauro com fome caça o dryosaurus")


func test_carnivoro_satisfeito_nao_caca(t) -> void:
	var w := WorldSim.new()
	var carno := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	_bot(w, "dryosaurus", 0.6, Vector3(220, 0, 200))
	carno.hunger = 95.0
	t.check(_think(w, carno) != "hunt", "de barriga cheia não caça")


func test_carnivoro_nao_caca_triceratops_adulto_saudavel(t) -> void:
	var w := WorldSim.new()
	var carno := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	_bot(w, "triceratops", 1.0, Vector3(215, 0, 200))
	carno.hunger = 30.0
	t.check(_think(w, carno) != "hunt", "triceratops adulto inteiro é grande demais")


func test_carnivoros_se_atacam(t) -> void:
	var w := WorldSim.new()
	var big := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	var small := _bot(w, "carnotaurus", 0.2, Vector3(215, 0, 200))
	big.hunger = 10.0
	t.check(_think(w, big) == "hunt" and int(big.brain["target_id"]) == small.id,
			"carnívoro faminto ataca carnívoro bem menor")


func test_dryosaurus_foge_de_predador(t) -> void:
	var w := WorldSim.new()
	_bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	var dryo := _bot(w, "dryosaurus", 1.0, Vector3(230, 0, 200))
	t.check(_think(w, dryo) == "flee", "dryosaurus foge ao ver o carnotauro")


func test_triceratops_encara_ou_foge_pela_vida(t) -> void:
	var w := WorldSim.new()
	var carno := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	var trike := _bot(w, "triceratops", 1.0, Vector3(206, 0, 200))
	w.apply_damage(trike, 100.0, carno)
	t.check(_think(w, trike) == "fight", "triceratops com vida alta revida")
	trike.health = trike.max_health() * 0.1
	t.check(_think(w, trike) == "flee", "triceratops com pouca vida foge")


func test_carnivoro_ferido_foge(t) -> void:
	var w := WorldSim.new()
	var a := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	var b := _bot(w, "carnotaurus", 1.0, Vector3(206, 0, 200))
	w.apply_damage(b, 50.0, a)
	t.check(_think(w, b) == "fight", "com vida alta briga")
	b.health = b.max_health() * 0.2
	t.check(_think(w, b) == "flee", "com pouca vida foge")


func test_jogador_filhote_e_percebido_mais_tarde(t) -> void:
	var w := WorldSim.new()
	var carno := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	var kid: Dino = w.login_player("tux", "dryosaurus")["dino"]
	kid.pos = Vector3(245, 0, 200)  # 45 m: dentro dos 60 m de percepção
	w._rebuild_grid()
	t.check(w.perceive(carno, 60.0).is_empty(), "filhote a 45 m passa despercebido")
	kid.growth = 1.0
	w._rebuild_grid()
	t.check(w.perceive(carno, 60.0).has(kid), "adulto a 45 m é visto")


func test_bot_com_sede_vai_beber(t) -> void:
	var w := WorldSim.new()
	var z := 300.0
	var cx := w.terrain.river_center_x(z)
	var d := _bot(w, "dryosaurus", 1.0, Vector3(cx + 40.0, 0, z))
	d.thirst = 20.0
	t.check(_think(w, d) == "drink", "decide beber")
	var dt := 1.0 / GameConfig.SIM_HZ
	for i in int(60.0 / dt):
		w.step(dt)
	t.check(d.thirst > 90.0, "chegou no rio e bebeu (sede %.0f)" % d.thirst)


func test_caca_de_verdade_termina_em_mordida(t) -> void:
	var w := WorldSim.new()
	var carno := _bot(w, "carnotaurus", 1.0, Vector3(200, 0, 200))
	# Triceratops jovem: lento demais pra escapar (um dryosaurus ágil costuma fugir).
	var prey := _bot(w, "triceratops", 0.3, Vector3(225, 0, 200))
	carno.hunger = 20.0
	var hp0 := prey.health
	var dt := 1.0 / GameConfig.SIM_HZ
	for i in int(30.0 / dt):
		w.step(dt)
		if not prey.alive or prey.health < hp0:
			break
	t.check(not prey.alive or prey.health < hp0, "o carnotauro alcançou e mordeu a presa")


## Mundo cheio rodando sozinho: não pode dar erro, a população se mantém,
## e mede o custo por passo pra estimar o notebook do servidor.
func test_carga_70_bots(t) -> void:
	_load_test(t, 70, 180.0)


func test_carga_100_bots(t) -> void:
	_load_test(t, 100, 60.0)


func _load_test(t, bots: int, seconds: float) -> void:
	# Mapa pequeno de propósito: todo mundo perto, brigando e ativo (o pior caso pro servidor).
	var w := WorldSim.new(GameConfig.WORLD_SEED, bots, 512.0)
	w.populate()
	var dt := 1.0 / GameConfig.SIM_HZ
	var steps := int(seconds / dt)
	var deaths := 0
	var hits := 0
	var start := Time.get_ticks_usec()
	for i in steps:
		w.step(dt)
		for e in w.events:
			if e["type"] == WorldSim.Ev.DEATH:
				deaths += 1
			elif e["type"] == WorldSim.Ev.HIT:
				hits += 1
		w.events.clear()
	var ms_per_step := (Time.get_ticks_usec() - start) / 1000.0 / steps
	var states := {}
	for b in w.bots():
		var s := BotBrain.state_of(b)
		states[s] = states.get(s, 0) + 1
	print("       %d bots, %.0f s de mundo: %.2f ms por passo (%.1f%% de 1 núcleo a 20 Hz) | golpes=%d mortes=%d | estados=%s" % [
		bots, seconds, ms_per_step, ms_per_step * GameConfig.SIM_HZ / 10.0, hits, deaths, states])
	t.check(w.bot_count() <= bots, "não passa do alvo")
	t.check(w.bot_count() >= bots - deaths, "população se mantém")
	t.check(states.size() >= 3, "bots fazendo coisas diferentes")
	t.check(ms_per_step < 25.0, "cabe folgado no passo de 50 ms")
