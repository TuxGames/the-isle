extends RefCounted
## Tamanho do mapa configurável e terreno desenhado por partes (design, seção 5).

const SEED := GameConfig.WORLD_SEED


func test_512_e_o_mapa_da_v01(t) -> void:
	# Valores tirados do Terrain da v0.1: com 512 m o mapa tem que sair igual, senão os
	# dinos dos saves antigos acordam em lugar errado.
	var ter := Terrain.get_shared(SEED, 512.0)
	t.check(ter.n == 257 and ter.play_min == 14.0 and ter.play_max == 498.0, "grade e área jogável da v0.1")
	t.near(ter.heights[1000], V01_HEIGHT_1000, 0.0001, "altura igual à da v0.1 (vértice 1000)")
	t.near(ter.heights[33000], V01_HEIGHT_33000, 0.0001, "altura igual à da v0.1 (vértice 33000)")
	t.check(ter.bushes.size() == 240, "240 arbustos, como na v0.1")
	t.check(ter.bushes[0].distance_to(V01_BUSH_0) < 0.001, "primeiro arbusto no mesmo lugar")
	t.check(ter.bushes[239].distance_to(V01_BUSH_239) < 0.001, "último arbusto no mesmo lugar")
	t.near(ter.river_center_x(200.0), V01_RIVER_200, 0.0001, "rio passa no mesmo lugar")


func test_mesma_semente_e_tamanho_mesmo_mapa(t) -> void:
	var a := Terrain.new(SEED, 1024.0)
	var b := Terrain.new(SEED, 1024.0)
	t.check(a.heights == b.heights and a.bushes == b.bushes, "servidor e cliente geram igual")
	t.check(Terrain.get_shared(SEED, 1024.0) != Terrain.get_shared(SEED, 512.0), "um mapa por tamanho")
	t.check(Terrain.get_shared(SEED, 1000.0) == Terrain.get_shared(SEED, 1024.0), "tamanho é arredondado")


func test_tamanho_arredondado_e_limitado(t) -> void:
	t.near(Terrain.normalize_size(1000.0), 1024.0, 0.0, "1000 vira 1024 (múltiplo de 64)")
	t.near(Terrain.normalize_size(10.0), Terrain.MIN_SIZE, 0.0, "mínimo")
	t.near(Terrain.normalize_size(1.0e6), Terrain.MAX_SIZE, 0.0, "máximo")


func test_mapa_grande_escala(t) -> void:
	var ter := Terrain.get_shared(SEED, 2048.0)
	t.near(ter.play_max, 2048.0 - Terrain.PLAY_MARGIN, 0.0, "área jogável vai até a borda do mapa grande")
	t.check(ter.bush_count() == 240 * 16 and ter.bushes.size() == ter.bush_count(),
			"arbustos proporcionais à área (%d)" % ter.bushes.size())
	var far_bushes := 0
	for p in ter.bushes:
		if p.x > 512.0 or p.z > 512.0:
			far_bushes += 1
	t.check(far_bushes > ter.bushes.size() / 2, "arbustos espalhados pelo mapa todo")
	for z in [100.0, 1000.0, 1900.0]:
		var cx := ter.river_center_x(z)
		t.check(ter.is_water(cx, z) and ter.water_depth(cx, z) > 2.0, "rio fundo em z=%d" % z)
	t.check(ter.height_at(2.0, 1024.0) > 30.0 and ter.height_at(2046.0, 1024.0) > 30.0, "montanhas nas duas bordas")
	t.check(ter.water_points.size() > 400, "pontos de água pelo rio inteiro")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var beyond := 0
	for i in 50:
		var p := ter.random_land_point(rng)
		t.check(p.x >= ter.play_min and p.x <= ter.play_max and p.z >= ter.play_min and p.z <= ter.play_max,
				"ponto aleatório dentro do mapa")
		if p.x > 512.0 or p.z > 512.0:
			beyond += 1
	t.check(beyond > 25, "pontos aleatórios usam o mapa todo")


func test_arbustos_perto(t) -> void:
	var ter := Terrain.get_shared(SEED, 1024.0)
	var p := ter.bushes[10]
	var near := ter.bushes_near(p, 5.0)
	t.check(near.has(10), "acha o arbusto do lado")
	for i in near:
		t.check(Movement.flat_distance(ter.bushes[i], p) <= 5.0, "só os que estão no raio")
	var brute := 0
	for b in ter.bushes:
		if Movement.flat_distance(b, p) <= 40.0:
			brute += 1
	t.check(ter.bushes_near(p, 40.0).size() == brute, "grade acha os mesmos que olhar um por um")


func test_bot_anda_pelo_mapa_grande(t) -> void:
	var w := WorldSim.new(SEED, 0, 2048.0)
	var p := BotBrain._clamp_inside(w, Vector3(1500.0, 0.0, 1800.0))
	t.check(p.x == 1500.0 and p.z == 1800.0, "destino longe da v0.1 não é puxado pro canto de 512 m")
	var q := w.terrain.clamp_to_play_area(Vector3(5000.0, 0.0, -10.0))
	t.check(q.x == w.terrain.play_max and q.z == w.terrain.play_min, "não sai do mapa")


# ---------------------------------------------------------------- save

func test_save_grava_o_tamanho(t) -> void:
	var w := WorldSim.new(SEED, 3, 1024.0)
	w.populate()
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_save()))
	t.check(int(data["format"]) == WorldSim.SAVE_FORMAT and float(data["map_size"]) == 1024.0, "save tem o tamanho")
	t.check(WorldSim.new(SEED, 3, 1024.0).save_mismatch(data) == "", "serve pro mesmo mapa")
	t.check(WorldSim.new(SEED, 3, 512.0).save_mismatch(data) != "", "não serve pra outro tamanho")
	t.check(WorldSim.new(SEED + 1, 3, 1024.0).save_mismatch(data) != "", "nem pra outra semente")


func test_save_da_v01_vira_512(t) -> void:
	# Formato 1 (v0.1): sem "map_size".
	var old := {
		"format": 1, "version": "0.1.0", "seed": SEED, "world_time": 42.0, "next_id": 10,
		"bots": [], "carcasses": [], "bush_food": [], "respawn_queue": [],
		"players": {"bob": {"alive": true, "dino": {"species": "dryosaurus", "growth": 0.4,
			"pos": [200.0, 5.0, 300.0], "health": 50.0}}},
	}
	t.near(WorldSim.save_map_size(old), 512.0, 0.0, "save antigo era de 512 m")
	var w := WorldSim.new(SEED, 0, 512.0)
	t.check(w.save_mismatch(old) == "", "serve pro mapa de 512 m")
	w.load_save(old)
	var back: Dictionary = w.login_player("bob", "carnotaurus")
	t.check(back["restored"] and back["dino"].species == "dryosaurus", "o bob volta com o dino dele")
	t.check(WorldSim.new(SEED, 0, 2048.0).save_mismatch(old) != "", "não serve pra um mapa maior")


# ---------------------------------------------------------------- pedaços do terreno (cliente)

func test_pedacos_em_volta_do_jogador(t) -> void:
	# Mapa de 512 m com o jogador no meio: tudo perto, tudo com detalhe máximo.
	var small := TerrainView.wanted_chunks(Vector3(256, 0, 256), 512.0)
	t.check(small.size() == 16, "512 m: os 16 pedaços (veio %d)" % small.size())
	t.check(small.values().all(func(l): return l == 0), "512 m: todos com detalhe máximo")
	# Mapa de 4096 m: só carrega em volta, com menos detalhe longe.
	var focus := Vector3(2048, 0, 2048)
	var big := TerrainView.wanted_chunks(focus, 4096.0)
	t.check(big.size() < (4096 / 128) * (4096 / 128) / 2, "4096 m: carrega só uma parte (%d pedaços)" % big.size())
	t.check(big[Vector2i(16, 16)] == 0, "o pedaço do jogador tem detalhe máximo")
	var reach: float = TerrainView.LOD_DIST[TerrainView.LOD_DIST.size() - 1]
	for key in big:
		var d := TerrainView.chunk_distance(focus, key)
		t.check(d <= reach, "nada além de %.0f m" % reach)
		t.check(big[key] == TerrainView.lod_for(d), "nível pela distância")
	t.check(not big.has(Vector2i(0, 0)), "o canto do mapa não carrega")
	# Andou: o que ficou pra trás sai, o que está na frente entra.
	var moved := TerrainView.wanted_chunks(focus + Vector3(1000, 0, 0), 4096.0, big)
	t.check(not moved.has(Vector2i(8, 16)) and big.has(Vector2i(8, 16)), "pedaço que ficou pra trás sai")
	t.check(moved.has(Vector2i(31, 16)) and not big.has(Vector2i(31, 16)), "pedaço da frente entra")


func test_pedaco_nao_fica_trocando_de_detalhe(t) -> void:
	var edge: float = TerrainView.LOD_DIST[0]
	var h: float = TerrainView.LOD_HYSTERESIS
	t.check(TerrainView.lod_for(edge + h * 0.5, 0) == 0, "logo depois da divisa continua no nível que estava")
	t.check(TerrainView.lod_for(edge + h * 0.5) == 1, "quem chega agora pega o nível da distância")
	t.check(TerrainView.lod_for(edge + h * 1.5, 0) == 1, "passando a folga troca")
	var last: float = TerrainView.LOD_DIST[TerrainView.LOD_DIST.size() - 1]
	t.check(TerrainView.lod_for(last + h * 0.5, TerrainView.LOD_DIST.size() - 1) >= 0, "não descarrega logo depois do limite")
	t.check(TerrainView.lod_for(last + h * 1.5, TerrainView.LOD_DIST.size() - 1) == -1, "descarrega passando a folga")


func test_pedacos_montados_de_verdade(t) -> void:
	var view := TerrainView.build(Terrain.get_shared(SEED, 2048.0))
	view.focus = Vector3(1024, 0, 1024)
	view.update_chunks(1.0e9)
	var loaded := view.loaded_chunks()
	t.check(loaded == TerrainView.wanted_chunks(view.focus, 2048.0, loaded), "montou o que devia")
	# Teleporte pra longe: lá só havia pedaço com pouco detalhe.
	t.check(int(loaded.get(Vector2i(14, 14), 0)) > 0, "longe, o pedaço tinha pouco detalhe")
	view.focus = Vector3(1900, 0, 1900)
	var first := view.update_chunks(0.0)
	t.check(first >= 1, "sem tempo sobrando, monta na hora o que é urgente (%d)" % first)
	t.check(int(view.loaded_chunks().get(Vector2i(14, 14), -1)) == 0, "o chão embaixo do jogador já está com detalhe máximo")
	while view.update_chunks(4.0) > 0:
		pass
	loaded = view.loaded_chunks()
	t.check(loaded == TerrainView.wanted_chunks(view.focus, 2048.0, loaded), "aos poucos, termina de montar tudo")
	view.free()


## Valores do Terrain da v0.1 (commit 6d18547), semente WORLD_SEED.
const V01_HEIGHT_1000 := 43.82288
const V01_HEIGHT_33000 := 8.089235
const V01_BUSH_0 := Vector3(362.84702, 11.004859, 68.91183)
const V01_BUSH_239 := Vector3(47.364822, 11.081005, 228.41713)
const V01_RIVER_200 := 325.2591321590555
