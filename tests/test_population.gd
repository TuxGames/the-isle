extends RefCounted
## Diretor de população (design, seção 3): onde e qual bot entra, e bots congelados que
## mudam de lugar pra perto dos jogadores. Os cantos opostos do mapa ficam a ~600 m.

const DT := 1.0 / GameConfig.SIM_HZ
const A := Vector3(40, 0, 40)
const B := Vector3(470, 0, 470)


func _bot(w: WorldSim, species: String, pos: Vector3) -> Dino:
	var d := Dino.create(w.new_id(), species, 1.0, pos)
	d.is_bot = true
	d.pos.y = Movement.ground_y(w.terrain, pos.x, pos.z, d.body_height())
	w.dinos[d.id] = d
	return d


func _player(w: WorldSim, player_name: String, species: String, pos: Vector3) -> Dino:
	var p: Dino = w.login_player(player_name, species)["dino"]
	p.growth = 1.0
	p.health = p.max_health()
	p.pos = pos
	return p


## Vários bots em volta de um ponto (até ~25 m).
func _herd(w: WorldSim, species: Array, center: Vector3) -> void:
	for i in species.size():
		_bot(w, species[i], center + Vector3((i % 5) * 5.0 - 10.0, 0, (i / 5) * 5.0 - 10.0))


func _near(w: WorldSim, p: Dino, ids: Array = []) -> int:
	var n := 0
	for b: Dino in w.bots():
		if (ids.is_empty() or ids.has(b.id)) and Movement.flat_distance(b.pos, p.pos) <= GameConfig.DIRECTOR_AREA_RADIUS:
			n += 1
	return n


func _spawn(w: WorldSim, count: int) -> Array:
	var out := []
	for i in count:
		out.append(w.spawn_bot())
	return out


func _min_player_dist(w: WorldSim, pos: Vector3) -> float:
	var m := INF
	for p: Dino in w.players():
		m = minf(m, Movement.flat_distance(pos, p.pos))
	return m


func _repeat(n: int, what: String) -> Array:
	var out := []
	for i in n:
		out.append(what)
	return out


func test_separados_cada_um_recebe_populacao(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 30)
	var pa := _player(w, "a", "triceratops", A)
	var pb := _player(w, "b", "triceratops", B)
	_herd(w, _repeat(10, "triceratops") + _repeat(5, "carnotaurus"), A + Vector3(120, 0, 0))
	var gs := PopulationDirector.groups(w)
	t.check(gs.size() == 2, "dois grupos")
	t.near(gs[0]["wanted"], 9.0, 0.001, "cada grupo quer 60% de 30 dividido por 2")
	var born := _spawn(w, 10)
	var ids := born.map(func(b): return b.id)
	t.check(_near(w, pb, ids) >= 9, "quem estava sem bots ganhou população (%d perto do b)" % _near(w, pb, ids))
	t.check(_near(w, pa) >= 9, "e o a continua com a dele")
	for b: Dino in born:
		t.check(_min_player_dist(w, b.pos) >= WorldSim.BOT_SPAWN_MIN_PLAYER_DIST, "nasceu fora da vista")


func test_juntos_concentra(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 30)
	var pa := _player(w, "a", "triceratops", A)
	_player(w, "b", "triceratops", A + Vector3(15, 0, 0))
	_herd(w, _repeat(10, "triceratops") + _repeat(5, "carnotaurus"), B)
	var gs := PopulationDirector.groups(w)
	t.check(gs.size() == 1, "um grupo só")
	t.near(gs[0]["wanted"], 18.0, 0.001, "juntos, o grupo quer o dobro (60% de 30)")
	var born := _spawn(w, 10)
	var ids := born.map(func(b): return b.id)
	t.check(_near(w, pa, ids) >= 9, "os bots novos vêm pra perto deles (%d de 10)" % _near(w, pa, ids))


func test_carnivoro_com_fome_puxa_herbivoros(t) -> void:
	var herbs_hungry := _herbs_born_near_carnivore(t, 20.0)
	var herbs_fed := _herbs_born_near_carnivore(t, 100.0)
	t.check(herbs_hungry >= 9, "com fome: %d de 10 bots novos são herbívoros" % herbs_hungry)
	t.check(herbs_fed <= 8, "sem fome: segue os 65/35 (%d de 10)" % herbs_fed)


func _herbs_born_near_carnivore(t, hunger: float) -> int:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 50)
	var carn := _player(w, "c", "carnotaurus", A)
	carn.hunger = hunger
	_herd(w, _repeat(26, "triceratops") + _repeat(14, "carnotaurus"), B)  # 65/35 longe
	var born := _spawn(w, 10)
	var herbs := 0
	for b: Dino in born:
		if not b.is_carnivore():
			herbs += 1
		t.check(Movement.flat_distance(b.pos, carn.pos) <= GameConfig.DIRECTOR_AREA_RADIUS, "nasceu na área do jogador")
	# A proporção geral não pode passar da tolerância, mesmo com muita reposição.
	_spawn(w, 40)
	var total := w.bot_count()
	var share := float(total - _carnivores(w)) / total
	t.check(share <= GameConfig.HERBIVORE_SHARE + GameConfig.DIRECTOR_SHARE_TOLERANCE + 0.0001
			and share >= GameConfig.HERBIVORE_SHARE - GameConfig.DIRECTOR_SHARE_TOLERANCE - 0.0001,
			"proporção geral continua perto dos 65%% (%.2f)" % share)
	return herbs


func _carnivores(w: WorldSim) -> int:
	var n := 0
	for b: Dino in w.bots():
		if b.is_carnivore():
			n += 1
	return n


func test_herbivoro_demais_puxa_carnivoros(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 40)
	_player(w, "h", "dryosaurus", A)
	_herd(w, _repeat(10, "triceratops"), A + Vector3(120, 0, 0))
	_herd(w, _repeat(3, "triceratops") + _repeat(7, "carnotaurus"), B)  # geral: 13/20 = 65%
	var born := _spawn(w, 4)
	var carn := born.filter(func(b): return b.is_carnivore()).size()
	t.check(carn >= 3, "área cheia de herbívoros recebe carnívoros (%d de 4)" % carn)


## Bots congelados longe de todo mundo mudam de lugar pra perto dos jogadores, poucos por vez,
## nunca saindo de onde alguém pode ver e nunca aparecendo perto de alguém.
func test_congelados_mudam_de_lugar_sem_ninguem_ver(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 11)
	var pa := _player(w, "a", "triceratops", A)
	_player(w, "b", "triceratops", A + Vector3(15, 0, 0))
	# Congelado a 400 m (na folga da histerese): alguém pode estar vendo, então não pode sair dali.
	# Criado primeiro pra ser o primeiro candidato da lista.
	var watched := _bot(w, "triceratops", A + Vector3(1, 0, 1).normalized() * 400.0)
	watched.sim_tier = WorldSim.SimTier.FROZEN
	var watched_pos := watched.pos
	# Congelado no meio de uma briga, longe de todos: a luta congela onde está.
	var fighter := _bot(w, "triceratops", B + Vector3(-20, 0, 0))
	fighter.brain = {"state": "fight", "since": 0.0, "target_id": watched.id}
	var fighter_pos := fighter.pos
	_herd(w, _repeat(7, "triceratops") + _repeat(3, "carnotaurus"), B)
	var moved_ids := {}
	var max_per_tick := 0
	for i in int(30.0 * GameConfig.SIM_HZ):
		var before := {}
		for b: Dino in w.bots():
			before[b.id] = b.pos
		w.step(DT)
		var moved_now := 0
		for b: Dino in w.bots():
			if before.has(b.id) and Movement.flat_distance(before[b.id], b.pos) > 30.0:
				moved_now += 1
				t.check(not moved_ids.has(b.id), "o mesmo bot não muda de lugar duas vezes seguidas")
				moved_ids[b.id] = true
				t.check(_min_player_dist(w, before[b.id]) >= GameConfig.DIRECTOR_SOURCE_MIN_DIST,
						"saiu de onde ninguém via")
				t.check(_min_player_dist(w, b.pos) >= GameConfig.DIRECTOR_RELOCATE_MIN_DIST,
						"apareceu longe dos jogadores (%.0f m)" % _min_player_dist(w, b.pos))
		max_per_tick = maxi(max_per_tick, moved_now)
	t.check(moved_ids.size() >= 6, "trouxe bots pra perto (%d mudaram)" % moved_ids.size())
	t.check(max_per_tick <= GameConfig.DIRECTOR_RELOCATE_MAX, "poucos por vez (%d)" % max_per_tick)
	t.check(_near(w, pa) >= 5, "os jogadores agora têm população em volta (%d)" % _near(w, pa))
	t.check(watched.pos.distance_to(watched_pos) < 0.001, "o congelado que dava pra ver ficou no lugar")
	t.check(fighter.pos.distance_to(fighter_pos) < 0.001, "o congelado no meio da briga ficou no lugar")


func test_reposicao_continua_com_diretor(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 20)
	_player(w, "a", "triceratops", A)
	_player(w, "b", "triceratops", B)
	w.populate()
	t.check(w.bot_count() == 20, "população inicial")
	var known := {}
	for b: Dino in w.bots():
		known[b.id] = true
	for b: Dino in w.bots().slice(0, 5):
		b.health = 0.0
	for i in int((GameConfig.BOT_RESPAWN_DELAY_S + 2.0) * GameConfig.SIM_HZ):
		w.step(DT)
		for b: Dino in w.bots():
			if not known.has(b.id):
				known[b.id] = true
				t.check(_min_player_dist(w, b.pos) >= WorldSim.BOT_SPAWN_MIN_PLAYER_DIST,
						"bot reposto nasceu fora da vista")
	# Parte das reposições vira ninho de bot (Nests): o ninho com ovos vale um bot.
	t.check(w.bot_count() + w.nests.bot_slots() == 20, "os 5 mortos foram repostos (%d bots + %d ninhos)" % [
			w.bot_count(), w.nests.bot_slots()])


## Sem jogador o diretor não faz nada e nem sorteia: o mundo dos testes de carga não muda.
func test_sem_jogador_nao_mexe_em_nada(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 10)
	w.populate()
	var state := w.rng.state
	t.check(w.director.pick_spawn(w).is_empty(), "sem preferência de onde nascer")
	w.director.update(w, GameConfig.DIRECTOR_INTERVAL_S + 1.0)
	t.check(w.rng.state == state, "não gastou sorteio")
