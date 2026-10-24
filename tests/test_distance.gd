extends RefCounted
## Simulação por distância (design, seção 5): bot perto roda todo passo, mais longe roda
## passo sim, passo não, e bem longe congela. Conta o jogador mais próximo.

const DT := 1.0 / GameConfig.SIM_HZ
const ORIGIN := Vector3(40, 0, 40)


func _bot(w: WorldSim, species: String, pos: Vector3) -> Dino:
	var d := Dino.create(w.new_id(), species, 1.0, pos)
	d.is_bot = true
	d.pos.y = Movement.ground_y(w.terrain, pos.x, pos.z, d.body_height())
	w.dinos[d.id] = d
	return d


func _player(w: WorldSim, player_name: String, pos: Vector3) -> Dino:
	var p: Dino = w.login_player(player_name, "dryosaurus")["dino"]
	p.pos = pos
	return p


func _run(w: WorldSim, seconds: float) -> void:
	for i in int(seconds * GameConfig.SIM_HZ):
		w.step(DT)


## Ponto a `dist` metros de `from` na diagonal: o mapa de 512 m só tem mais de 480 m
## de distância entre cantos opostos.
static func _diag(from: Vector3, dist: float) -> Vector3:
	return from + Vector3(1, 0, 1).normalized() * dist


func test_faixas_pelo_jogador_mais_proximo(t) -> void:
	var w := WorldSim.new()
	_player(w, "tux", ORIGIN)
	var near := _bot(w, "triceratops", _diag(ORIGIN, 100.0))
	var mid := _bot(w, "triceratops", _diag(ORIGIN, 250.0))
	var far := _bot(w, "triceratops", _diag(ORIGIN, 560.0))
	w.step(DT)
	t.check(near.sim_tier == WorldSim.SimTier.FULL, "a 100 m roda todo passo")
	t.check(mid.sim_tier == WorldSim.SimTier.REDUCED, "a 250 m roda passo sim, passo não")
	t.check(far.sim_tier == WorldSim.SimTier.FROZEN, "a 560 m congela")
	t.check(w.sim_tier_counts() == {"full": 1, "reduced": 1, "frozen": 1}, "contagem por faixa")
	_player(w, "marcelo", _diag(ORIGIN, 540.0))
	w.step(DT)
	t.check(far.sim_tier == WorldSim.SimTier.FULL, "acorda com outro jogador perto dele")


func test_histerese(t) -> void:
	var w := WorldSim.new()
	var spot := Vector3(460, 0, 460)
	var bot := _bot(w, "triceratops", spot)
	var p := _player(w, "tux", _diag(spot, -500.0))
	var expect := [
		[500.0, WorldSim.SimTier.FROZEN, "a 500 m congela"],
		[400.0, WorldSim.SimTier.FROZEN, "a 400 m continua congelado (só acorda a 320 m)"],
		[300.0, WorldSim.SimTier.REDUCED, "a 300 m acorda"],
		[400.0, WorldSim.SimTier.REDUCED, "a 400 m continua acordado (só congela a 480 m)"],
		[470.0, WorldSim.SimTier.REDUCED, "a 470 m ainda acordado"],
		[500.0, WorldSim.SimTier.FROZEN, "a 500 m congela de novo"],
	]
	for e in expect:
		p.pos = _diag(bot.pos, -float(e[0]))
		w.step(DT)
		t.check(bot.sim_tier == e[1], e[2])


func test_congelado_nao_muda_nada(t) -> void:
	var w := WorldSim.new()
	_player(w, "tux", ORIGIN)
	var bot := _bot(w, "carnotaurus", _diag(ORIGIN, 560.0))
	bot.growth = 0.6
	bot.health = bot.max_health() * 0.3
	bot.hunger = 50.0
	bot.thirst = 50.0
	var before := bot.to_dict()
	_run(w, 120.0)
	t.check(bot.sim_tier == WorldSim.SimTier.FROZEN, "congelado")
	t.near(bot.health, before["health"], 0.0001, "ferido continua ferido")
	t.near(bot.hunger, before["hunger"], 0.0001, "fome parada")
	t.near(bot.thirst, before["thirst"], 0.0001, "sede parada")
	t.near(bot.growth, before["growth"], 0.0001, "crescimento parado")
	t.check(bot.to_dict()["pos"] == before["pos"], "não saiu do lugar")
	t.check(w.get_dino(bot.id) == null, "a IA dos outros não enxerga o congelado")
	t.check(not w.query(bot.pos, 5.0).has(bot), "fora do alcance de mordidas")


func test_briga_congela_no_meio(t) -> void:
	var w := WorldSim.new()
	var p := _player(w, "tux", ORIGIN)
	var a := _bot(w, "carnotaurus", _diag(ORIGIN, 60.0))
	t.check(w.start_attack(a), "golpe começa")
	var windup: float = w.pending_attacks[0]["t"]
	var cooldown := a.attack_cooldown
	p.pos = Vector3(470, 0, 470)  # ~550 m
	_run(w, 30.0)
	t.check(a.sim_tier == WorldSim.SimTier.FROZEN, "congelou")
	t.check(w.pending_attacks.size() == 1, "golpe continua pendente")
	t.near(float(w.pending_attacks[0]["t"]), windup, 0.0001, "preparação do golpe parada")
	t.near(a.attack_cooldown, cooldown, 0.0001, "recarga parada")
	p.pos = ORIGIN
	_run(w, 2.0)
	t.check(w.pending_attacks.is_empty(), "o golpe termina quando o jogador volta")
	t.check(a.attack_cooldown < cooldown, "a recarga volta a correr")


## Dois bots iguais parados, um perto (todo passo) e um longe (passo sim, passo não):
## fome e sede caem igual, porque o tempo é somado. Só a IA decide menos vezes.
func test_longe_passa_fome_no_mesmo_ritmo(t) -> void:
	var w := WorldSim.new()
	_player(w, "tux", ORIGIN)
	var near := _bot(w, "triceratops", _diag(ORIGIN, 80.0))
	var mid := _bot(w, "triceratops", _diag(ORIGIN, 250.0))
	for b: Dino in [near, mid]:
		b.brain = {"state": "idle", "since": 0.0, "idle_until": 1.0e9}
	_run(w, 60.0)
	t.check(near.sim_tier == WorldSim.SimTier.FULL and mid.sim_tier == WorldSim.SimTier.REDUCED,
			"um em cada faixa")
	t.check(near.hunger < 99.0, "a fome caiu de verdade (%.2f)" % near.hunger)
	t.near(mid.hunger, near.hunger, 0.01, "fome no mesmo ritmo")
	t.near(mid.thirst, near.thirst, 0.01, "sede no mesmo ritmo")


func test_sem_jogador_ninguem_congela(t) -> void:
	var w := WorldSim.new()
	var b := _bot(w, "triceratops", Vector3(460, 0, 460))
	w.step(DT)
	t.check(b.sim_tier == WorldSim.SimTier.FULL, "mundo sem jogador (só em teste): tudo roda")
