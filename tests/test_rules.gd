extends RefCounted
## Terreno, metabolismo e combate.


func _dino(species: String, growth: float, pos := Vector3(200, 0, 200), yaw := 0.0) -> Dino:
	var d := Dino.create(1, species, growth, pos)
	d.yaw = yaw
	return d


# ---------------------------------------------------------------- terreno

func test_terreno_igual_com_mesma_semente(t) -> void:
	var a := Terrain.new(12345)
	var b := Terrain.new(12345)
	t.check(a.heights == b.heights, "alturas iguais")
	t.check(a.bushes == b.bushes, "arbustos iguais")
	var c := Terrain.new(999)
	t.check(a.heights != c.heights, "outra semente gera outro mapa")


func test_terreno_tem_rio_e_bordas(t) -> void:
	var ter := Terrain.get_shared(GameConfig.WORLD_SEED)
	for z in [50.0, 200.0, 400.0]:
		var cx := ter.river_center_x(z)
		t.check(ter.is_water(cx, z), "centro do rio é água em z=%d" % z)
		t.check(ter.water_depth(cx, z) > 2.0, "rio é fundo no meio")
	t.check(ter.height_at(2.0, 256.0) > 30.0, "borda oeste é montanha")
	t.check(ter.bushes.size() == ter.bush_count(), "todos os arbustos foram colocados")
	for p in ter.bushes:
		if ter.is_water(p.x, p.z):
			t.check(false, "arbusto dentro d'água em %s" % p)
			break
	for p in ter.water_points:
		t.check(ter.is_water(p.x, p.z), "ponto de água é água")


# ---------------------------------------------------------------- metabolismo

func _simulate(d: Dino, seconds: float, moving_speed := 0.0, sprint := false, rest := false) -> void:
	d.moving_speed = moving_speed
	d.sprinting = sprint
	d.resting = rest
	var steps := int(seconds)
	for i in steps:
		Metabolism.step(d, 1.0)


func test_carnotauro_adulto_esvazia_em_40min_andando(t) -> void:
	var d := _dino("carnotaurus", 1.0)
	d.thirst = 1.0e9  # isola a fome
	_simulate(d, 40 * 60 - 60, 4.0)
	t.check(d.hunger > 0.0, "ainda tem algo no estômago 1 min antes")
	_simulate(d, 120, 4.0)
	t.near(d.hunger, 0.0, 0.01, "estômago vazio depois de ~40 min")


func test_correr_gasta_mais_que_descansar(t) -> void:
	var run := _dino("carnotaurus", 1.0)
	var rest := _dino("carnotaurus", 1.0)
	_simulate(run, 300, 10.0, true)
	_simulate(rest, 300, 0.0, false, true)
	t.check(100.0 - run.hunger > 3.5 * (100.0 - rest.hunger), "correr gasta ~4x mais que descansar")


func test_filhote_come_mais_vezes(t) -> void:
	var adult := _dino("carnotaurus", 1.0)
	var young := _dino("carnotaurus", 0.1)
	t.check(Metabolism.hunger_per_second(young) > Metabolism.hunger_per_second(adult) * 1.5,
			"filhote esvazia o estômago bem mais rápido")
	t.check(young.stomach_kg() < adult.stomach_kg() * 0.1, "mas cabe bem menos comida")


func test_cura_bem_alimentado(t) -> void:
	var d := _dino("triceratops", 1.0)
	d.health = d.max_health() * 0.5
	_simulate(d, 4 * 60)
	t.near(d.health_ratio(), 1.0, 0.01, "metade da vida volta em 4 min (vida cheia em 8)")
	var r := _dino("triceratops", 1.0)
	r.health = r.max_health() * 0.5
	_simulate(r, 2 * 60, 0.0, false, true)
	t.near(r.health_ratio(), 1.0, 0.01, "descansando cura o dobro")


func test_fome_zerada_nao_mata_na_hora(t) -> void:
	var d := _dino("dryosaurus", 1.0)
	d.hunger = 0.0
	d.thirst = 100.0
	_simulate(d, 60)
	t.check(d.health > 0.9 * d.max_health(), "1 minuto de fome quase não tira vida")
	_simulate(d, 17 * 60)
	t.check(d.health <= 0.0, "17 minutos sem comer mata")


func test_so_cresce_alimentado_e_mantem_proporcao_de_vida(t) -> void:
	var d := _dino("dryosaurus", 0.1)
	d.health = d.max_health() * 0.5
	d.hunger = 30.0
	var g0 := d.growth
	Metabolism.step(d, 10.0)
	t.near(d.growth, g0, 0.00001, "com fome não cresce")
	d.hunger = 100.0
	d.thirst = 100.0
	d.health = d.max_health() * 0.5
	var ratio := d.health_ratio()
	d.health = d.max_health() * 0.5
	Metabolism.step(d, 60.0)
	t.check(d.growth > g0, "alimentado cresce")
	t.check(d.health_ratio() >= ratio, "crescer não derruba a proporção de vida")


func test_dryosaurus_vira_adulto_em_30min(t) -> void:
	var d := _dino("dryosaurus", 0.0)
	for i in 30 * 60:
		d.hunger = 100.0
		d.thirst = 100.0
		Metabolism.step(d, 1.0)
	t.near(d.growth, 1.0, 0.001, "adulto em 30 min jogados")


# ---------------------------------------------------------------- combate

func test_mordida_de_frente_acerta_de_costas_erra(t) -> void:
	var prey := _dino("dryosaurus", 1.0, Vector3(200, 0, 200))
	prey.id = 2
	var carno := _dino("carnotaurus", 1.0, Vector3(200, 0, 196.6), 0.0)  # olhando pra +Z
	t.check(Combat.hit_part(carno, prey) != "", "de frente acerta")
	carno.yaw = PI
	t.check(Combat.hit_part(carno, prey) == "", "de costas erra")
	carno.yaw = 0.0
	carno.pos = Vector3(200, 0, 190)
	t.check(Combat.hit_part(carno, prey) == "", "longe demais erra")


func test_bicho_grande_morde_filhote_no_chao(t) -> void:
	var baby := _dino("dryosaurus", 0.0, Vector3(200, 0, 200))
	baby.id = 2
	var carno := _dino("carnotaurus", 1.0, Vector3(200, 0, 196.5), 0.0)
	t.check(Combat.hit_part(carno, baby) != "", "a boca desce até o filhote")


func test_filhote_nao_alcanca_cabeca_de_adulto(t) -> void:
	var adult := _dino("carnotaurus", 1.0, Vector3(200, 0, 200), PI)
	adult.id = 2
	# Filhote de dryosaurus atrás do adulto, chutando a cauda: alcança.
	var baby := _dino("dryosaurus", 0.0, Vector3(200, 0, 200 - 4.6), 0.0)
	var part := Combat.hit_part(baby, adult)
	t.check(part == "" or part == "cauda" or part == "pernas", "filhote só alcança cauda/pernas (veio '%s')" % part)


func test_dano_depende_da_parte_e_do_tamanho(t) -> void:
	var carno := _dino("carnotaurus", 1.0)
	t.check(Combat.damage(carno, "cabeça") > Combat.damage(carno, "cauda"), "cabeça dói mais que cauda")
	var young := _dino("carnotaurus", 0.1)
	t.check(Combat.damage(young, "tronco") < Combat.damage(carno, "tronco") * 0.2, "filhote morde bem mais fraco")
