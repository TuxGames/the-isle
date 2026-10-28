extends RefCounted
## Reprodução (design, seção 8): ninho, parceiro bot e jogador, postura e recarga, incubação,
## filhotes, nascer no ninho, ovos comidos, ninho de bot na reposição e save.

const DT := 1.0 / GameConfig.SIM_HZ
const A := Vector3(40, 0, 40)
const B := Vector3(470, 0, 470)


func _world(bots := 0) -> WorldSim:
	var w := WorldSim.new(GameConfig.WORLD_SEED, bots)
	w.nests.bot_nest_share = 0.0
	return w


func _run(w: WorldSim, seconds: float) -> void:
	for i in int(seconds * GameConfig.SIM_HZ):
		w.step(DT)


## Lugar plano em terra firme (com folga em volta), sempre o mesmo.
func _spot(w: WorldSim) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 2000:
		var p := w.terrain.random_land_point(rng)
		var ok := true
		for off in [Vector3.ZERO, Vector3(15, 0, 0), Vector3(-15, 0, 0), Vector3(0, 0, 15), Vector3(0, 0, -15)]:
			if Nests.spot_error(w.terrain, p + off) != "":
				ok = false
		if ok:
			return Vector3(p.x, 0.0, p.z)
	return Vector3(300, 0, 300)


func _place(w: WorldSim, d: Dino, pos: Vector3) -> void:
	d.pos = Vector3(pos.x, Movement.ground_y(w.terrain, pos.x, pos.z, d.body_height()), pos.z)


func _adult(w: WorldSim, player_name: String, species: String, pos: Vector3) -> Dino:
	var p: Dino = w.login_player(player_name, species)["dino"]
	p.growth = 1.0
	p.health = p.max_health()
	p.hunger = 100.0
	p.thirst = 100.0
	_place(w, p, pos)
	return p


func _bot(w: WorldSim, species: String, growth: float, pos: Vector3) -> Dino:
	var d := Dino.create(w.new_id(), species, growth, pos)
	d.is_bot = true
	d.hunger = 90.0
	d.thirst = 90.0
	_place(w, d, pos)
	w.dinos[d.id] = d
	return d


func _told(w: WorldSim, player_name: String, part: String) -> bool:
	for m in w.nests.messages:
		if m[0] == player_name and String(m[1]).contains(part):
			return true
	return false


func _eggs(w: WorldSim, player_name: String) -> int:
	var nest := w.nests.nest_of(player_name)
	return -1 if nest.is_empty() else nest["eggs"].size()


# ---------------------------------------------------------------- ninho

func test_ninho_so_para_adulto_alimentado(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "ana", "dryosaurus", spot)
	p.growth = 0.6
	t.check(w.nests.set_building(w, p, true).begins_with("Só adulto"), "jovem não faz ninho")
	p.growth = 1.0
	p.hunger = 40.0
	t.check(w.nests.set_building(w, p, true).contains("comida"), "com fome não faz ninho")
	p.hunger = 100.0
	p.thirst = 45.0
	t.check(w.nests.set_building(w, p, true).contains("água"), "com sede não faz ninho")
	p.thirst = 100.0
	Injuries.inflict(p, Injuries.BLEED, 60.0)
	t.check(w.nests.set_building(w, p, true).begins_with("Sangrando"), "sangrando não faz ninho")
	p.injuries.clear()
	_place(w, p, w.terrain.water_points[0])
	t.check(w.nests.set_building(w, p, true).contains("água"), "dentro do rio não faz ninho")
	t.check(_told(w, "ana", "Sangrando"), "o motivo vai pro jogador")
	_place(w, p, spot)
	t.check(w.nests.set_building(w, p, true) == "", "adulto alimentado em terra firme começa a fazer")
	_run(w, GameConfig.NEST_BUILD_S - 1.0)
	t.check(w.nests.nest_of("ana").is_empty(), "antes dos 8 s ainda não tem ninho")
	t.near(w.nests.status_of(w, p)["build"], (GameConfig.NEST_BUILD_S - 1.0) / GameConfig.NEST_BUILD_S, 0.02, "progresso no HUD")
	# Andou: a contagem recomeça (tem que ficar parado).
	p.moving_speed = 3.0
	w.step(DT)
	p.moving_speed = 0.0
	_run(w, GameConfig.NEST_BUILD_S - 1.0)
	t.check(w.nests.nest_of("ana").is_empty(), "andar recomeça a contagem")
	_run(w, 1.2)
	var nest := w.nests.nest_of("ana")
	t.check(not nest.is_empty(), "8 s parado segurando N: ninho pronto")
	if nest.is_empty():
		return
	t.check(Movement.flat_distance(nest["pos"], spot) < 0.1, "o ninho fica onde ele estava")
	t.check(nest["species"] == "dryosaurus" and nest["eggs"].is_empty(), "ninho vazio da espécie dele")
	t.check(_told(w, "ana", "Ninho pronto"), "avisa que o ninho ficou pronto")
	t.check(w.nests.status_of(w, p)["eggs"] == 0 and w.nests.status_of(w, p)["build"] < 0.0, "HUD: ninho vazio, sem construção")
	# Soltar N antes da hora cancela.
	w.nests.set_building(w, p, true)
	_run(w, 2.0)
	w.nests.set_building(w, p, false)
	t.check(w.nests.status_of(w, p)["build"] < 0.0, "soltar N cancela")


func test_um_ninho_por_jogador(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "ana", "dryosaurus", spot)
	w.nests.build(w, "ana", "dryosaurus", spot)
	# Ninho vazio: fazer outro muda de lugar.
	w.nests.build(w, "ana", "dryosaurus", spot + Vector3(10, 0, 0))
	t.check(w.nests.nests.size() == 1, "o ninho vazio antigo some")
	w.nests.lay(w, w.nests.nest_of("ana"))
	_place(w, p, spot)
	t.check(w.nests.set_building(w, p, true).contains("chocando"), "com ovos chocando não faz outro")
	t.check(w.nests.nests.size() == 1, "continua um só")


# ---------------------------------------------------------------- parceiro

func test_bot_aceita_ou_recusa(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "bia", "dryosaurus", spot)
	t.check(w.nests.press_mate(w, p).begins_with("Primeiro faça um ninho"), "sem ninho não tem postura")
	w.nests.build(w, "bia", "dryosaurus", spot)
	var b := _bot(w, "dryosaurus", 1.0, spot + Vector3(3, 0, 0))
	var carn := _bot(w, "carnotaurus", 1.0, spot + Vector3(0, 0, -4))
	b.hunger = 30.0
	t.check(w.nests.press_mate(w, p).contains("fome"), "bot com fome recusa")
	b.hunger = 90.0
	b.brain = {"state": "flee"}
	t.check(w.nests.press_mate(w, p).contains("ocupado"), "bot fugindo recusa")
	b.brain = {"state": "fight"}
	t.check(w.nests.press_mate(w, p).contains("ocupado"), "bot brigando recusa")
	b.brain = {}
	b.growth = 0.7
	t.check(w.nests.press_mate(w, p).begins_with("Nenhum Dryosaurus adulto"), "bot jovem não serve (e o carnotauro nem conta)")
	b.growth = 1.0
	_place(w, b, spot + Vector3(9, 0, 0))
	t.check(w.nests.press_mate(w, p).begins_with("Nenhum"), "bot longe demais não serve")
	_place(w, b, spot + Vector3(3, 0, 0))
	t.check(w.nests.press_mate(w, p) == "", "bot adulto, alimentado e tranquilo aceita")
	t.check(_eggs(w, "bia") == 4, "Dryosaurus põe 4 ovos (%d)" % _eggs(w, "bia"))
	t.check(_told(w, "bia", "Postura feita"), "avisa a postura")
	t.check(carn.alive, "o carnotauro só assistiu")
	# O mesmo bot não aceita de novo logo (outro jogador com ninho, a bia longe).
	_place(w, p, spot + Vector3(30, 0, 0))
	var q := _adult(w, "caio", "dryosaurus", spot + Vector3(5, 0, 0))
	w.nests.build(w, "caio", "dryosaurus", spot + Vector3(5, 0, 0))
	t.check(w.nests.press_mate(w, q).contains("há pouco"), "bot em recarga recusa")
	t.check(_eggs(w, "caio") == 0, "e o ninho do caio continua vazio")


func test_jogador_precisa_confirmar(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var a := _adult(w, "ana", "carnotaurus", spot)
	var b := _adult(w, "beto", "carnotaurus", spot + Vector3(4, 0, 0))
	w.nests.build(w, "ana", "carnotaurus", spot)
	t.check(w.nests.press_mate(w, a) == "", "pedido enviado")
	t.check(_eggs(w, "ana") == 0, "sem ovos antes do outro aceitar")
	t.check(_told(w, "beto", "quer fazer ninho"), "o outro jogador recebe o aviso")
	var st := w.nests.status_of(w, b)
	t.check(st["ask"] > GameConfig.MATE_CONFIRM_S - 0.1 and st["ask_from"] == a.id, "HUD do beto: pedido da ana com 15 s")
	_run(w, 3.0)
	t.check(w.nests.press_mate(w, b) == "", "beto aperta R e aceita")
	t.check(_eggs(w, "ana") == 3, "Carnotaurus põe 3 ovos no ninho de quem pediu (%d)" % _eggs(w, "ana"))
	t.check(w.nests.nest_of("beto").is_empty(), "quem aceitou não ganha ninho")
	t.near(w.nests.lay_cooldown(w, "ana"), GameConfig.LAY_COOLDOWN_S, 0.01, "recarga de 2 h pra quem fez a postura")
	t.check(w.nests.status_of(w, b)["ask"] == 0.0, "o pedido acabou")

	# Pedido vence em 15 s: apertar R depois disso não aceita nada.
	var w2 := _world()
	var a2 := _adult(w2, "ana", "carnotaurus", spot)
	var b2 := _adult(w2, "beto", "carnotaurus", spot + Vector3(4, 0, 0))
	w2.nests.build(w2, "ana", "carnotaurus", spot)
	w2.nests.press_mate(w2, a2)
	_run(w2, GameConfig.MATE_CONFIRM_S + 1.0)
	t.check(w2.nests.status_of(w2, b2)["ask"] == 0.0, "pedido venceu")
	t.check(w2.nests.press_mate(w2, b2).begins_with("Primeiro faça um ninho"), "R depois do prazo não aceita")
	t.check(_eggs(w2, "ana") == 0, "sem ovos")
	# Outra espécie não serve de parceiro.
	var c := _adult(w2, "cris", "triceratops", spot + Vector3(-5, 0, 0))
	_place(w2, b2, spot + Vector3(40, 0, 0))
	t.check(w2.nests.press_mate(w2, a2).begins_with("Nenhum"), "triceratops não é parceiro de carnotauro")
	t.check(not w2.nests.requests.has("cris") and c.alive, "nem recebe pedido")


func test_postura_e_recarga(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "dani", "dryosaurus", spot)
	var nest := w.nests.build(w, "dani", "dryosaurus", spot)
	_bot(w, "dryosaurus", 1.0, spot + Vector3(3, 0, 0))
	t.check(w.nests.press_mate(w, p) == "", "postura com bot")
	t.check(_eggs(w, "dani") == 4, "4 ovos")
	t.check(w.nests.press_mate(w, p).contains("chocando"), "com ovos chocando não põe mais")
	w.world_time += GameConfig.INCUBATION_S
	w.step(DT)
	t.check(_eggs(w, "dani") == 1 and not Nests.ready_egg(nest).is_empty(), "chocaram: sobra 1 ovo pronto pro dono")
	t.check(w.nests.press_mate(w, p).begins_with("Ainda não dá"), "recarga de 2 h entre posturas")
	w.world_time += GameConfig.LAY_COOLDOWN_S
	_place(w, p, spot + Vector3(GameConfig.MATE_NEST_DIST + 5.0, 0, 0))
	_bot(w, "dryosaurus", 1.0, p.pos + Vector3(3, 0, 0))
	t.check(w.nests.press_mate(w, p).begins_with("Longe demais"), "longe do ninho não tem postura")
	_place(w, p, spot + Vector3(0, 0, 6))
	_bot(w, "dryosaurus", 1.0, spot + Vector3(0, 0, 9))
	t.check(w.nests.press_mate(w, p) == "", "passada a recarga, põe de novo (outro bot)")
	t.check(_eggs(w, "dani") == 5, "4 ovos novos + o pronto que já estava (%d)" % _eggs(w, "dani"))
	p.growth = 0.9
	w.world_time += GameConfig.LAY_COOLDOWN_S + GameConfig.INCUBATION_S
	t.check(w.nests.press_mate(w, p).begins_with("Só adulto"), "subadulto não faz postura")


# ---------------------------------------------------------------- incubação e filhotes

func test_incubacao_pausa_com_o_mundo_parado(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "eli", "triceratops", spot)
	var vigia := _adult(w, "vigia", "triceratops", spot + Vector3(60, 0, 0))
	var nest := w.nests.build(w, "eli", "triceratops", spot)
	w.nests.lay(w, nest)
	t.near(w.nests.status_of(w, p)["hatch"], GameConfig.INCUBATION_S, 0.01, "chocam em 20 min")
	_run(w, 600.0)
	t.near(w.nests.status_of(w, p)["hatch"], GameConfig.INCUBATION_S - 600.0, 0.1, "10 min depois faltam 10")
	# O dono sai: o ninho continua no mundo (o vigia está online, o mundo anda).
	w.logout_player(p.id)
	# Ninguém online: o servidor não chama step(). Salva, "passa um tempo" e carrega: nada mudou.
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_save()))
	var w2 := _world()
	w2.load_save(data)
	var nest2 := w2.nests.nest_of("eli")
	t.near(float(nest2["hatch_at"]) - w2.world_time, GameConfig.INCUBATION_S - 600.0, 0.1, "o tempo que falta não andou com o mundo parado")
	var v2: Dino = w2.login_player("vigia", "triceratops")["dino"]
	t.check(v2 != null, "o vigia volta")
	_run(w2, 590.0)
	t.check(Nests.incubating_count(nest2) == 2, "ainda chocando")
	_run(w2, 15.0)
	t.check(Nests.incubating_count(nest2) == 0, "chocaram com o dono offline")
	t.check(not Nests.ready_egg(nest2).is_empty(), "o ovo do dono ficou esperando")
	t.check(vigia != null, "ok")


func test_choca_como_bot_e_respeita_o_maximo(t) -> void:
	var w := _world()
	w.bot_target = 0
	var spot := _spot(w)
	var nest := w.nests.build(w, "", "carnotaurus", spot)
	w.nests.lay(w, nest)
	t.check(nest["eggs"].size() == 3, "ninho de bot com 3 ovos de carnotauro")
	for i in GameConfig.BOT_MAX - 1:
		_bot(w, "dryosaurus", 1.0, B + Vector3((i % 10) * 4.0, 0, (i / 10) * 4.0))
	t.check(w.bot_count() == GameConfig.BOT_MAX - 1, "mundo quase cheio")
	w.world_time = float(nest["hatch_at"])
	w.step(DT)
	t.check(w.bot_count() == GameConfig.BOT_MAX, "choca só até o máximo de bots (%d)" % w.bot_count())
	t.check(nest["eggs"].size() == 2, "os outros ovos esperam (%d)" % nest["eggs"].size())
	var baby: Dino = null
	for b: Dino in w.bots():
		if b.species == "carnotaurus":
			baby = b
	t.check(baby != null and absf(baby.growth - GameConfig.HATCHLING_GROWTH) < 0.001, "nasceu um carnotauro filhote")
	t.check(baby != null and Movement.flat_distance(baby.pos, spot) < 3.0, "em cima do ninho")
	# Morreu um bot: abre vaga e o próximo ovo choca.
	w.kill(w.bots()[0], "teste")
	w.step(DT)
	t.check(w.bot_count() == GameConfig.BOT_MAX and nest["eggs"].size() == 1, "abriu vaga, chocou mais um")
	w.kill(w.bots()[0], "teste")
	w.step(DT)
	t.check(w.nests.nests.is_empty(), "o ninho some quando acabam os ovos")


func test_nascer_no_ninho_como_filhote(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "fabi", "triceratops", spot + Vector3(20, 0, 0))
	var nest := w.nests.build(w, "fabi", "triceratops", spot)
	w.nests.lay(w, nest)
	t.check(nest["eggs"].size() == 2, "Triceratops põe 2 ovos")
	t.check(w.nests.respawn_in_nest(w, "fabi") == null, "ovo chocando ainda não serve pra nascer")
	w.world_time = float(nest["hatch_at"])
	var bots0 := w.bot_count()
	w.step(DT)
	t.check(w.bot_count() == bots0 + 1, "um ovo virou bot filhote")
	t.check(nest["eggs"].size() == 1 and nest["eggs"][0]["ready"], "o outro ficou pronto pro dono")
	t.check(w.nests.mine_of("fabi")["ready"], "s_nests: botão Nascer no ninho")
	t.check(_told(w, "fabi", "chocaram"), "avisa o dono")
	# Morre (com o boost de crescimento, que vai junto pro próximo dino).
	p.growth_boost_s = 120.0
	p.health = 0.0
	w.step(DT)
	t.check(not w.player_records["fabi"]["alive"], "morreu")
	var d := w.nests.respawn_in_nest(w, "fabi")
	t.check(d != null, "nasceu no ninho")
	if d == null:
		return
	t.check(not d.is_bot and d.player_name == "fabi" and d.species == "triceratops", "jogador, da espécie do ninho")
	t.near(d.growth, GameConfig.PLAYER_START_GROWTH, 0.0001, "recomeça jovem (filhote)")
	t.check(Movement.flat_distance(d.pos, spot) < Nests.NEST_RADIUS_M, "em cima do ninho")
	t.near(d.growth_boost_s, 120.0, 0.001, "o boost veio junto")
	t.check(w.player_records["fabi"]["alive"], "registro vivo de novo")
	t.check(w.nests.nest_of("fabi").is_empty(), "sem ovos, o ninho some")
	t.check(not w.nests.mine_of("fabi")["ready"], "sem botão")
	t.check(w.nests.respawn_in_nest(w, "fabi") == null, "não nasce duas vezes")


# ---------------------------------------------------------------- comer ovo

func test_carnivoro_come_ovo_e_herbivoro_nao(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var nest := w.nests.build(w, "gabi", "dryosaurus", spot)
	w.nests.lay(w, nest)
	var egg_pos: Vector3 = nest["pos"] + Nests.egg_offset(0)
	# Carnotauro jogador com a boca em cima do ovo (olhando pra +Z).
	var rex := _adult(w, "rex", "carnotaurus", egg_pos - Vector3(0, 0, 3.6))
	rex.yaw = 0.0
	rex.hunger = 50.0
	rex.interacting = true
	t.check(not w.nests.egg_in_reach(w, rex).is_empty(), "o ovo está ao alcance da boca")
	_run(w, GameConfig.EGG_EAT_S - 0.5)
	t.check(nest["eggs"].size() == 4, "ainda comendo")
	t.check(rex.interact_result == 1, "HUD: comendo")
	var h0 := rex.hunger
	_run(w, 1.0)
	t.check(nest["eggs"].size() == 3, "comeu o ovo (%d sobraram)" % nest["eggs"].size())
	t.check(rex.hunger > h0 + 2.0, "ganhou comida (%.1f → %.1f)" % [h0, rex.hunger])
	t.check(_told(w, "gabi", "comeu um ovo"), "o dono fica sabendo")
	rex.interacting = false
	_place(w, rex, spot + Vector3(30, 0, 0))
	# Triceratops jogador com a boca em cima de outro ovo: herbívoro não come ovo.
	var egg2: Vector3 = nest["pos"] + Nests.egg_offset(3)
	var trike := _adult(w, "tri", "triceratops", egg2 - Vector3(0, 0, 4.0 * 0.85))
	trike.yaw = 0.0
	trike.hunger = 30.0
	trike.interacting = true
	t.check(w.nests.egg_in_reach(w, trike).is_empty(), "herbívoro não alcança ovo")
	_run(w, GameConfig.EGG_EAT_S * 2.0)
	t.check(nest["eggs"].size() == 3, "herbívoro não come ovo")


func test_bot_carnivoro_com_fome_come_ovo(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var nest := w.nests.build(w, "", "triceratops", spot)
	w.nests.lay(w, nest)
	var carn := _bot(w, "carnotaurus", 1.0, spot + Vector3(15, 0, 0))
	carn.hunger = 30.0
	var fed := _bot(w, "carnotaurus", 1.0, spot + Vector3(-15, 0, 0))
	fed.hunger = 90.0
	var herb := _bot(w, "dryosaurus", 1.0, spot + Vector3(0, 0, 12))
	herb.hunger = 20.0
	var h0 := carn.hunger
	_run(w, 30.0)
	t.check(nest["eggs"].size() < 2 or w.nests.nests.is_empty(), "o carnotauro com fome comeu ovo")
	t.check(carn.hunger > h0, "e ganhou comida (%.1f → %.1f)" % [h0, carn.hunger])
	t.check(BotBrain.state_of(fed) != "eat_egg", "de barriga cheia não vai atrás de ovo")
	t.check(BotBrain.state_of(herb) != "eat_egg", "herbívoro não vai atrás de ovo")


# ---------------------------------------------------------------- bots

func test_ninho_de_bot_na_reposicao(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 10)
	w.nests.bot_nest_share = 1.0
	var pa: Dino = w.login_player("a", "triceratops")["dino"]
	_place(w, pa, A)
	for i in 10:
		_bot(w, "dryosaurus", 1.0, B + Vector3((i % 5) * 5.0, 0, (i / 5) * 5.0))
	for b: Dino in w.bots().slice(0, 3):
		b.health = 0.0
	_run(w, GameConfig.BOT_RESPAWN_DELAY_S + 1.0)
	t.check(w.nests.nests.size() == 3, "as 3 reposições viraram ninho (%d)" % w.nests.nests.size())
	t.check(w.bot_count() == 7 and w.nests.bot_slots() == 3, "cada ninho vale um bot")
	var expected := 7
	for nest: Dictionary in w.nests.nests.values():
		t.check(nest["owner"] == "" and nest["bot_slot"], "ninho de bot")
		t.check(nest["eggs"].size() == int(Species.DATA[nest["species"]]["clutch"]), "com a postura da espécie")
		t.check(Movement.flat_distance(nest["pos"], pa.pos) >= WorldSim.BOT_SPAWN_MIN_PLAYER_DIST, "fora da vista do jogador")
		t.check(Nests.spot_error(w.terrain, nest["pos"]) == "", "em chão firme")
		expected += nest["eggs"].size()
	_run(w, GameConfig.BOT_RESPAWN_DELAY_S + 1.0)
	t.check(w.bot_count() == 7 and w.nests.nests.size() == 3, "sem reposição extra enquanto os ninhos esperam")
	t.check(w.respawn_queue.is_empty(), "nem fila de reposição (%d)" % w.respawn_queue.size())
	w.world_time += GameConfig.INCUBATION_S
	w.step(DT)
	t.check(w.bot_count() == expected, "os ovos chocaram como bots e contam na população (%d de %d)" % [w.bot_count(), expected])
	t.check(w.nests.nests.is_empty(), "os ninhos sumiram")
	var babies := w.bots().filter(func(b): return absf(b.growth - GameConfig.HATCHLING_GROWTH) < 0.001).size()
	t.check(babies == expected - 7, "todos filhotes (%d)" % babies)
	# Sem jogador no mundo a reposição não vira ninho.
	var w2 := WorldSim.new(GameConfig.WORLD_SEED, 5)
	w2.nests.bot_nest_share = 1.0
	for i in 5:
		_bot(w2, "dryosaurus", 1.0, B + Vector3(i * 5.0, 0, 0))
	w2.bots()[0].health = 0.0
	_run(w2, GameConfig.BOT_RESPAWN_DELAY_S + 1.0)
	t.check(w2.nests.nests.is_empty() and w2.bot_count() == 5, "sem jogador: bot normal")


func test_parte_dos_bots_nasce_adulta(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 100)
	w.populate()
	var adults := w.bots().filter(func(b): return Nests.is_adult(b)).size()
	t.check(adults >= 15 and adults <= 50, "uns 30%% dos bots novos são adultos (%d de 100)" % adults)


# ---------------------------------------------------------------- save, HUD

func test_save_load_e_migracao_do_formato_4(t) -> void:
	var w := _world()
	var spot := _spot(w)
	var p := _adult(w, "hugo", "carnotaurus", spot)
	_bot(w, "carnotaurus", 1.0, spot + Vector3(4, 0, 0))
	w.nests.build(w, "hugo", "carnotaurus", spot)
	t.check(w.nests.press_mate(w, p) == "", "postura")
	var bot_nest := w.nests.build(w, "", "dryosaurus", spot + Vector3(200, 0, 0))
	bot_nest["bot_slot"] = true
	w.nests.lay(w, bot_nest)
	_run(w, 10.0)
	w.logout_player(p.id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_save()))
	t.check(int(data["format"]) == 5, "formato 5")
	var w2 := _world()
	w2.load_save(data)
	t.check(w2.nests.nests.size() == 2, "os dois ninhos voltaram")
	var n1 := w.nests.nest_of("hugo")
	var n2 := w2.nests.nest_of("hugo")
	t.check(not n2.is_empty() and n2["species"] == "carnotaurus", "o ninho do hugo")
	t.check(n2["eggs"].size() == 3 and Nests.incubating_count(n2) == 3, "com os 3 ovos chocando")
	t.near(float(n2["hatch_at"]), float(n1["hatch_at"]), 0.001, "mesma hora de chocar")
	t.check(Movement.flat_distance(n2["pos"], n1["pos"]) < 0.001, "mesmo lugar")
	t.near(w2.nests.lay_cooldown(w2, "hugo"), w.nests.lay_cooldown(w, "hugo"), 0.01, "mesma recarga de postura")
	t.check(w2.nests.bot_slots() == 1, "o ninho de bot continua valendo um bot")
	var ids := {}
	for nest: Dictionary in w2.nests.nests.values():
		ids[nest["id"]] = true
	t.check(not ids.has(w2.new_id()), "ids novos não repetem os dos ninhos")
	# Save do formato 4 (v0.3): sem "nests". Carrega sem ninhos e ninguém perde o dino.
	var old := data.duplicate(true)
	old.erase("nests")
	old["format"] = 4
	var w3 := _world()
	w3.load_save(old)
	t.check(w3.nests.nests.is_empty(), "formato 4: mundo sem ninhos")
	t.check(w3.nests.lay_cooldown(w3, "hugo") == 0.0, "e sem recarga")
	var back: Dictionary = w3.login_player("hugo", "dryosaurus")
	t.check(back["restored"] and back["dino"].species == "carnotaurus", "o dino do hugo voltou igual")
	t.near(back["dino"].growth, 1.0, 0.0001, "adulto como era")


func test_textos_do_hud(t) -> void:
	t.check(Nests.clock(750.0) == "12:30", "12:30")
	t.check(Nests.clock(6130.0) == "1:42:10", "1:42:10")
	t.check(Nests.status_text(-1, 0, 0.0, 0.0) == "", "sem ninho nem recarga: nada")
	t.check(Nests.status_text(3, 0, 750.0, 0.0) == "Ninho: 3 ovos · chocam em 12:30", Nests.status_text(3, 0, 750.0, 0.0))
	t.check(Nests.status_text(1, 0, 59.0, 0.0) == "Ninho: 1 ovo · choca em 0:59", "singular")
	t.check(Nests.status_text(1, 1, 0.0, 0.0) == "Ovo pronto: se morrer, nasce nele", "só o ovo pronto")
	t.check(Nests.status_text(4, 1, 60.0, 0.0) == "Ninho: 3 ovos · chocam em 1:00\nOvo pronto: se morrer, nasce nele",
			"chocando + pronto")
	t.check(Nests.status_text(0, 0, 0.0, 6130.0) == "Ninho vazio: R perto de um adulto\nNova postura em 1:42:10",
			"vazio + recarga")
	t.check(Nests.status_text(-1, 0, 0.0, 60.0) == "Nova postura em 1:00", "só a recarga")
