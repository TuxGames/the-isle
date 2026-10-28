extends RefCounted
## Ferimentos (design, seção 6): sangramento, fratura e mordida funda.


func _dino(species: String, growth := 1.0) -> Dino:
	return Dino.create(1, species, growth, Vector3(200, 0, 200))


func _world() -> WorldSim:
	return WorldSim.new(GameConfig.WORLD_SEED, 0)


func _run(w: WorldSim, seconds: float) -> void:
	var dt := 1.0 / GameConfig.SIM_HZ
	for i in int(seconds * GameConfig.SIM_HZ):
		w.step(dt)


## Passos de 1 s só do metabolismo (sem mundo).
func _simulate(d: Dino, seconds: int, rest := false) -> void:
	d.moving_speed = 0.0
	d.resting = rest
	for i in seconds:
		Metabolism.step(d, 1.0)


# ---------------------------------------------------------------- qual golpe abre qual ferimento

func test_sangramento_so_com_golpe_forte(t) -> void:
	var a := _dino("carnotaurus")
	var b := _dino("carnotaurus")
	var hp := b.max_health()
	var got := Injuries.from_hit(b, a, hp * (GameConfig.BLEED_MIN_DAMAGE - 0.01), "tronco")
	t.check(not got.has(Injuries.BLEED) and not Injuries.has(b, Injuries.BLEED), "golpe fraco não sangra")
	got = Injuries.from_hit(b, a, hp * (GameConfig.BLEED_MIN_DAMAGE + 0.01), "tronco")
	t.check(got.has(Injuries.BLEED), "golpe acima do limite sangra")
	t.near(Injuries.remaining(b, Injuries.BLEED), GameConfig.BLEED_S, 0.001, "sangra pelo tempo todo")


func test_fratura_so_de_bicho_3x_mais_pesado(t) -> void:
	var carno := _dino("carnotaurus")
	var dryo := _dino("dryosaurus")
	var trike := _dino("triceratops")
	var other_carno := _dino("carnotaurus")
	Injuries.from_hit(dryo, carno, 1.0, "cauda")
	t.check(Injuries.has(dryo, Injuries.FRACTURE), "carnotauro (1.500 kg) quebra o osso do dryosaurus (90 kg)")
	Injuries.from_hit(other_carno, carno, 1.0, "cauda")
	t.check(not Injuries.has(other_carno, Injuries.FRACTURE), "mesmo peso não quebra")
	Injuries.from_hit(carno, dryo, 1.0, "cauda")
	t.check(not Injuries.has(carno, Injuries.FRACTURE), "o pequeno não quebra o osso do grande")
	Injuries.from_hit(carno, trike, 1.0, "cauda")
	t.check(Injuries.has(carno, Injuries.FRACTURE), "tricerátops (6.000 kg, 4x) quebra o do carnotauro")
	Injuries.from_hit(trike, null, 1.0, "cauda")
	t.check(trike.injuries.is_empty(), "dano sem atacante não quebra nada")
	# No limite: o atacante precisa de pelo menos FRACTURE_MASS_RATIO vezes a massa do alvo.
	var big := _dino("carnotaurus")
	var small := _dino("carnotaurus", 0.0)
	var ratio := big.mass() / small.mass()
	t.check(ratio >= GameConfig.FRACTURE_MASS_RATIO, "carnotauro adulto pesa 3x+ o filhote (%.0fx)" % ratio)
	Injuries.from_hit(small, big, 1.0, "cauda")
	t.check(Injuries.has(small, Injuries.FRACTURE), "adulto quebra o osso do filhote da mesma espécie")


func test_mordida_funda_no_golpe_certo(t) -> void:
	var a := _dino("carnotaurus")
	var cases := [
		["tronco", GameConfig.DEEP_MIN_DAMAGE + 0.01, true],
		["tronco", GameConfig.DEEP_MIN_DAMAGE - 0.01, false],
		["cabeça", GameConfig.DEEP_HEAD_DAMAGE + 0.01, true],
		["pescoço", GameConfig.DEEP_HEAD_DAMAGE + 0.01, true],
		["cabeça", GameConfig.DEEP_HEAD_DAMAGE - 0.01, false],
		["cauda", GameConfig.DEEP_HEAD_DAMAGE + 0.01, false],
	]
	for c in cases:
		var b := _dino("carnotaurus")
		Injuries.from_hit(b, a, b.max_health() * float(c[1]), c[0])
		t.check(Injuries.has(b, Injuries.DEEP) == c[2], "%s com %.0f%% da vida: mordida funda = %s" % [c[0], float(c[1]) * 100.0, c[2]])


func test_golpe_no_mundo_abre_os_ferimentos(t) -> void:
	var w := _world()
	var a: Dino = w.login_player("a", "carnotaurus")["dino"]
	var b: Dino = w.login_player("b", "dryosaurus")["dino"]
	a.growth = 1.0
	b.growth = 1.0
	b.health = b.max_health()
	b.pos = Vector3(250, 0, 250)
	a.pos = Vector3(250, 0, 246.6)
	a.yaw = 0.0
	w.start_attack(a)
	_run(w, 0.6)
	t.check(b.health < b.max_health(), "acertou")
	for type in Injuries.TYPES:
		t.check(Injuries.has(b, type), "mordida de carnotauro no dryosaurus abre %s" % type)
	# O contrário: o golpe do dryosaurus mal arranha o carnotauro, em qualquer parte.
	for part in Species.PART_DAMAGE:
		Injuries.from_hit(a, b, Combat.damage(b, part), part)
	t.check(a.injuries.is_empty(), "golpe de dryosaurus não fere o carnotauro (%s)" % [a.injuries])


func test_golpe_novo_nao_encurta_ferimento(t) -> void:
	var d := _dino("dryosaurus")
	Injuries.inflict(d, Injuries.FRACTURE, 500.0)
	Injuries.inflict(d, Injuries.FRACTURE, 100.0)
	t.near(Injuries.remaining(d, Injuries.FRACTURE), 500.0, 0.001, "fica o mais longo")
	Injuries.inflict(d, "inventado", 100.0)
	t.check(not d.injuries.has("inventado"), "tipo desconhecido é ignorado")


# ---------------------------------------------------------------- efeitos

func test_sangramento_tira_vida_e_para(t) -> void:
	var d := _dino("dryosaurus")
	var max_hp := d.max_health()
	Injuries.inflict(d, Injuries.BLEED, GameConfig.BLEED_S)
	_simulate(d, int(GameConfig.BLEED_S))
	var lost := GameConfig.BLEED_LOSS_PER_MIN * GameConfig.BLEED_S / 60.0
	t.near(d.health, max_hp * (1.0 - lost), 0.001 * max_hp, "perde %.0f%% da vida em %d s" % [lost * 100.0, GameConfig.BLEED_S])
	t.check(not Injuries.has(d, Injuries.BLEED), "o sangramento para sozinho")
	var hp := d.health
	_simulate(d, 30)
	t.check(d.health > hp, "parou de sangrar: volta a curar")


func test_sangrando_nao_cura(t) -> void:
	var d := _dino("dryosaurus")
	d.health = d.max_health() * 0.5
	Injuries.inflict(d, Injuries.BLEED, 60.0)
	var hp := d.health
	_simulate(d, 30, true)
	t.check(d.health < hp, "bem alimentado e descansando, mas sangrando: só perde vida")


func test_fratura_limita_velocidade_e_correr(t) -> void:
	var d := _dino("dryosaurus")
	var before := Movement.speeds(d)
	t.check(before.y > before.x, "sem fratura corre mais rápido que anda")
	t.check(not Movement.is_limping(d), "vida cheia sem fratura não manca")
	Injuries.inflict(d, Injuries.FRACTURE, GameConfig.FRACTURE_S)
	var after := Movement.speeds(d)
	t.near(after.x, before.x * GameConfig.FRACTURE_SPEED_MULT, 0.001, "anda mais devagar")
	t.near(after.y, after.x, 0.001, "não corre (correr = andar)")
	t.check(Movement.is_limping(d), "manca com a vida cheia")
	# Apertando correr com osso quebrado: não gasta fôlego nem conta como corrida.
	d.stamina = 50.0
	d.moving_speed = after.x
	d.sprinting = true
	t.near(Metabolism.activity(d), Metabolism.ACTIVITY_WALK, 0.001, "gasta como andando")
	Metabolism.step(d, 1.0)
	t.check(d.stamina > 50.0, "o fôlego não cai (%.1f)" % d.stamina)


## Um dryosaurus bot fugindo de um carnotauro parado por 3 s: devolve a velocidade média.
func _flee_speed(fractured: bool) -> float:
	var w := _world()
	var alice: Dino = w.login_player("alice", "carnotaurus")["dino"]
	alice.growth = 1.0
	var b := w.spawn_bot("dryosaurus", 1.0)
	var p := w.terrain.clamp_to_play_area(alice.pos + Vector3(12, 0, 0))
	b.pos = Vector3(p.x, Movement.ground_y(w.terrain, p.x, p.z, b.body_height()), p.z)
	if fractured:
		Injuries.inflict(b, Injuries.FRACTURE, GameConfig.FRACTURE_S)
	b.brain = {"state": "flee", "target_id": alice.id, "since": w.world_time, "think_t": 0.0}
	var start := b.pos
	_run(w, 3.0)
	return Movement.flat_distance(start, b.pos) / 3.0


func test_bot_com_fratura_anda_mais_devagar(t) -> void:
	var normal := _flee_speed(false)
	var slow := _flee_speed(true)
	var d := _dino("dryosaurus")
	Injuries.inflict(d, Injuries.FRACTURE, GameConfig.FRACTURE_S)
	var limit := Movement.speeds(d).x
	t.check(slow > 0.5, "o bot com fratura foge (%.2f m/s)" % slow)
	t.check(slow <= limit + 0.05, "não passa de andar com fratura (%.2f m/s, limite %.2f)" % [slow, limit])
	t.check(slow < normal * 0.7, "bem mais lento que sem fratura (%.2f vs %.2f m/s)" % [slow, normal])


func test_mordida_funda_corta_a_cura_pela_metade(t) -> void:
	var ok := _dino("dryosaurus")
	var hurt := _dino("dryosaurus")
	ok.health = ok.max_health() * 0.5
	hurt.health = hurt.max_health() * 0.5
	Injuries.inflict(hurt, Injuries.DEEP, GameConfig.DEEP_S)
	var hp0 := ok.health
	_simulate(ok, 60)
	_simulate(hurt, 60)
	t.near((hurt.health - hp0) / (ok.health - hp0), GameConfig.DEEP_HEAL_MULT, 0.001, "cura na metade do ritmo")


func test_descansar_sara_mais_rapido(t) -> void:
	var a := _dino("dryosaurus")
	var b := _dino("dryosaurus")
	Injuries.inflict(a, Injuries.FRACTURE, 600.0)
	Injuries.inflict(b, Injuries.FRACTURE, 600.0)
	_simulate(a, 100)
	_simulate(b, 100, true)
	t.near(Injuries.remaining(a, Injuries.FRACTURE), 500.0, 0.01, "acordado: 1 s por segundo")
	t.near(Injuries.remaining(b, Injuries.FRACTURE), 600.0 - 100.0 * GameConfig.INJURY_REST_MULT, 0.01,
			"descansando: %.0fx mais rápido" % GameConfig.INJURY_REST_MULT)
	# Descansar andando não conta.
	var c := _dino("dryosaurus")
	Injuries.inflict(c, Injuries.FRACTURE, 600.0)
	c.resting = true
	c.moving_speed = 2.0
	Metabolism.step(c, 10.0)
	t.near(Injuries.remaining(c, Injuries.FRACTURE), 590.0, 0.01, "descansando andando sara normal")
	for id in Species.IDS:
		t.check(Species.DATA[id].has("injury_heal"), "%s tem ritmo de cura de ferimentos" % id)


func test_ferimentos_saram_e_somem(t) -> void:
	var d := _dino("dryosaurus")
	Injuries.inflict(d, Injuries.DEEP, 5.0)
	_simulate(d, 6)
	t.check(d.injuries.is_empty(), "sarou e saiu da lista")


# ---------------------------------------------------------------- mundo, save, morte

func test_ferimentos_congelam_offline(t) -> void:
	var w := _world()
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	w.login_player("alice", "carnotaurus")
	bob.growth = 1.0
	bob.health = bob.max_health() * 0.6
	Injuries.inflict(bob, Injuries.BLEED, 100.0)
	Injuries.inflict(bob, Injuries.FRACTURE, 400.0)
	_run(w, 2.0)
	var hp := bob.health
	var left := bob.injuries.duplicate()
	w.logout_player(bob.id)
	_run(w, 300.0)   # alice joga 5 minutos sozinha
	var b2: Dino = w.login_player("bob", "dryosaurus")["dino"]
	t.near(b2.health, hp, 0.0001, "não sangrou fora do jogo")
	for type in left:
		t.near(Injuries.remaining(b2, type), float(left[type]), 0.0001, "%s congelado" % type)


func test_save_e_load_com_ferimentos(t) -> void:
	var w := _world()
	var bot := w.spawn_bot("triceratops", 1.0)
	Injuries.inflict(bot, Injuries.DEEP, 123.0)
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	Injuries.inflict(bob, Injuries.FRACTURE, 456.0)
	w.logout_player(bob.id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_save()))
	t.check(int(data["format"]) == WorldSim.SAVE_FORMAT, "grava o formato atual")
	var w2 := _world()
	w2.load_save(data)
	t.near(Injuries.remaining(w2.get_dino(bot.id), Injuries.DEEP), 123.0, 0.001, "bot volta com a mordida funda")
	var b2: Dino = w2.login_player("bob", "dryosaurus")["dino"]
	t.near(Injuries.remaining(b2, Injuries.FRACTURE), 456.0, 0.001, "jogador volta com o osso quebrado")


func test_save_antigo_sem_ferimentos(t) -> void:
	var w := _world()
	w.spawn_bot("dryosaurus", 1.0)
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	w.logout_player(bob.id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_save()))
	# Formato 3 (v0.2.1): igual, só sem "injuries".
	data["format"] = 3
	for bd in data["bots"]:
		bd.erase("injuries")
	var pd: Dictionary = data["players"]["bob"]["dino"]
	pd.erase("injuries")
	var w2 := _world()
	w2.load_save(data)
	t.check(w2.bot_count() == 1 and w2.bots()[0].injuries.is_empty(), "bot do save antigo sem ferimentos")
	var back: Dictionary = w2.login_player("bob", "dryosaurus")
	var b2: Dino = back["dino"]
	t.check(back["restored"] and b2.injuries.is_empty(), "jogador do save antigo volta sem ferimentos")
	# Lixo no save não vira ferimento.
	var junk := Injuries.sanitize({"sangramento": -5.0, "xyz": 10.0, "fratura": 30.0})
	t.check(junk == {"fratura": 30.0}, "só tipos conhecidos com tempo positivo (%s)" % [junk])
	t.check(Injuries.sanitize("não é dicionário").is_empty(), "formato errado vira vazio")


func test_morte_por_sangramento(t) -> void:
	var w := _world()
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	bob.growth = 1.0
	bob.health = bob.max_health() * 0.01
	Injuries.inflict(bob, Injuries.BLEED, GameConfig.BLEED_S)
	_run(w, 30.0)
	t.check(not w.dinos.has(bob.id), "morreu sangrando")
	var deaths := w.events.filter(func(e): return e["type"] == WorldSim.Ev.DEATH)
	t.check(deaths.size() == 1 and deaths[0]["cause"] == "sangramento", "causa: sangramento (%s)" % [deaths])
	var again: Dino = w.login_player("bob", "dryosaurus")["dino"]
	t.check(again.injuries.is_empty(), "renasce sem ferimentos")


func test_texto_do_hud(t) -> void:
	var text := Injuries.describe({Injuries.BLEED: 129.2, Injuries.FRACTURE: 520.0})
	t.check(text == "Sangrando 2:10 · Osso quebrado 8:40", "texto (%s)" % text)
	t.check(Injuries.describe({Injuries.DEEP: 5.0}) == "Mordida funda 0:05", "segundos com dois dígitos")
	t.check(Injuries.describe({Injuries.BLEED: 0.0}) == "", "sem ferimento: vazio")
