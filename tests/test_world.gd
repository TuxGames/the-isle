extends RefCounted
## Mundo do servidor: login/logout, morte, população, save, comer e beber.


func _world(bots := 0) -> WorldSim:
	return WorldSim.new(GameConfig.WORLD_SEED, bots)


func _run(w: WorldSim, seconds: float) -> void:
	var dt := 1.0 / GameConfig.SIM_HZ
	for i in int(seconds * GameConfig.SIM_HZ):
		w.step(dt)


func test_logout_congela_o_dino(t) -> void:
	var w := _world()
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	var alice: Dino = w.login_player("alice", "carnotaurus")["dino"]
	bob.health = bob.max_health() * 0.4
	_run(w, 5.0)
	w.logout_player(bob.id)
	var frozen: Dictionary = w.player_records["bob"]["dino"].duplicate()
	t.check(not w.dinos.has(bob.id), "dino some do mundo ao sair")
	_run(w, 600.0)   # alice joga 10 minutos sozinha
	var back: Dictionary = w.login_player("bob", "carnotaurus")
	var b2: Dino = back["dino"]
	t.check(back["restored"], "volta com o dino salvo (ignora a espécie escolhida)")
	t.check(b2.species == "dryosaurus", "mesma espécie")
	t.near(b2.health, frozen["health"], 0.0001, "vida congelada")
	t.near(b2.hunger, frozen["hunger"], 0.0001, "fome congelada")
	t.near(b2.thirst, frozen["thirst"], 0.0001, "sede congelada")
	t.near(b2.growth, frozen["growth"], 0.0001, "crescimento congelado")
	t.check(alice.hunger < 100.0, "enquanto isso a alice passou fome normalmente")


func test_morte_vira_carcaca_e_jogador_recomeca_jovem(t) -> void:
	var w := _world()
	var bob: Dino = w.login_player("bob", "triceratops")["dino"]
	bob.growth = 1.0
	bob.health = 0.0
	w.step(0.05)
	t.check(not w.dinos.has(bob.id), "saiu do mundo")
	t.check(w.carcasses.size() == 1, "virou carcaça")
	t.check(not w.player_records["bob"]["alive"], "registro marcado como morto")
	var deaths := w.events.filter(func(e): return e["type"] == WorldSim.Ev.DEATH)
	t.check(deaths.size() == 1 and deaths[0]["player"] == "bob", "evento de morte do jogador")
	var again: Dictionary = w.login_player("bob", "carnotaurus")
	t.check(not again["restored"], "não restaura dino morto")
	var d: Dino = again["dino"]
	t.check(d.species == "carnotaurus", "escolhe espécie nova")
	t.near(d.growth, GameConfig.PLAYER_START_GROWTH, 0.0001, "recomeça jovem")


func test_bot_morto_e_reposto(t) -> void:
	var w := _world(20)
	w.populate()
	t.check(w.bot_count() == 20, "população inicial")
	var victim: Dino = w.bots()[0]
	victim.health = 0.0
	w.step(0.05)
	t.check(w.bot_count() == 19, "bot morreu")
	_run(w, GameConfig.BOT_RESPAWN_DELAY_S + 1.0)
	t.check(w.bot_count() == 20, "outro bot entrou no lugar")


func test_proporcao_herbivoros(t) -> void:
	var w := _world(70)
	w.populate()
	var herb := 0
	for b in w.bots():
		if not b.is_carnivore():
			herb += 1
	var share := float(herb) / w.bot_count()
	t.check(share > 0.6 and share < 0.7, "~65%% herbívoros (veio %.0f%%)" % (share * 100.0))


func test_bot_novo_nasce_longe_dos_jogadores(t) -> void:
	var w := _world()
	var p: Dino = w.login_player("tux", "carnotaurus")["dino"]
	for i in 10:
		var b := w.spawn_bot()
		t.check(Movement.flat_distance(b.pos, p.pos) >= WorldSim.BOT_SPAWN_MIN_PLAYER_DIST,
				"bot nasce fora da vista do jogador")


func test_jogador_novo_nasce_longe_de_carnivoros(t) -> void:
	var w := _world(30)
	w.populate()
	var p: Dino = w.login_player("tux", "dryosaurus")["dino"]
	var nearest := INF
	for b in w.bots():
		if b.is_carnivore():
			nearest = minf(nearest, Movement.flat_distance(b.pos, p.pos))
	t.check(nearest > 40.0, "carnívoro mais perto a %.0f m" % nearest)


func test_save_e_load(t) -> void:
	var w := _world(15)
	w.populate()
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	_run(w, 3.0)
	w.logout_player(bob.id)
	w.bush_food[3] = 7.0
	var json := JSON.stringify(w.to_save())
	var w2 := _world(15)
	w2.load_save(JSON.parse_string(json))
	t.near(w2.world_time, w.world_time, 0.0001, "relógio do mundo")
	t.check(w2.bot_count() == w.bot_count(), "mesmos bots")
	t.near(w2.bush_food[3], 7.0, 0.001, "comida dos arbustos")
	for id in w.dinos:
		var a: Dino = w.dinos[id]
		var b: Dino = w2.dinos.get(id)
		if b == null:
			t.check(false, "bot %d sumiu" % id)
			continue
		t.check(a.pos.distance_to(b.pos) < 0.001 and absf(a.health - b.health) < 0.001, "bot %d igual" % id)
	t.check(w2.player_records.has("bob") and w2.player_records["bob"]["alive"], "jogador salvo")
	var nid := w2.new_id()
	t.check(not w2.dinos.has(nid) and not w2.carcasses.has(nid), "ids novos não colidem")


func test_comer_e_beber(t) -> void:
	var w := _world()
	var ter := w.terrain
	# Herbívoro de frente pra um arbusto
	var bush: Vector3 = ter.bushes[0]
	var herb: Dino = w.login_player("h", "dryosaurus")["dino"]
	herb.growth = 1.0
	herb.pos = bush - Vector3(0, 0, 1.6)
	herb.yaw = 0.0
	herb.hunger = 10.0
	herb.interacting = true
	_run(w, 3.0)
	t.check(herb.hunger > 30.0, "herbívoro come do arbusto (fome %.1f)" % herb.hunger)
	t.check(w.bush_food[0] < WorldSim.BUSH_MAX_KG, "arbusto perdeu comida")
	# Carnívoro de frente pra uma carcaça
	var carn: Dino = w.login_player("c", "carnotaurus")["dino"]
	carn.growth = 1.0
	var victim := w.spawn_bot("triceratops", 1.0)
	carn.pos = victim.pos - Vector3(0, 0, 6.0)
	carn.yaw = 0.0
	w.kill(victim, "teste")
	carn.hunger = 5.0
	carn.interacting = true
	_run(w, 3.0)
	t.check(carn.hunger > 20.0, "carnívoro come da carcaça (fome %.1f)" % carn.hunger)
	# Beber: de frente pro rio
	var z := 250.0
	var cx := Terrain.river_center_x(z)
	var thirsty: Dino = w.login_player("s", "carnotaurus")["dino"]
	thirsty.growth = 1.0
	thirsty.pos = Vector3(cx - Terrain.RIVER_HALF_WIDTH - 4.0, 0, z)
	thirsty.yaw = PI / 2.0  # olhando pra +X, pro rio
	thirsty.thirst = 10.0
	thirsty.interacting = true
	_run(w, 2.0)
	t.check(thirsty.thirst > 30.0, "bebe no rio (sede %.1f)" % thirsty.thirst)


func test_golpe_leva_tempo_e_tem_recarga(t) -> void:
	var w := _world()
	var a: Dino = w.login_player("a", "carnotaurus")["dino"]
	var b: Dino = w.login_player("b", "dryosaurus")["dino"]
	a.growth = 1.0
	b.growth = 1.0
	b.health = b.max_health()
	b.pos = Vector3(250, 0, 250)
	a.pos = Vector3(250, 0, 246.6)
	a.yaw = 0.0
	t.check(w.start_attack(a), "golpe começa")
	t.check(not w.start_attack(a), "recarga impede outro golpe na hora")
	var hp0 := b.health
	w.step(0.05)
	t.near(b.health, hp0, 0.001, "ainda não acertou (preparação do golpe)")
	_run(w, 0.5)
	t.check(b.health < hp0, "acertou depois da preparação")
	t.check(b.last_attacker_id == a.id, "alvo sabe quem atacou")
