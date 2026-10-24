extends RefCounted
## Configurações do jogador (scripts/client/settings.gd) e a distância de visão do terreno.

const TMP_PATH := "user://teste_configuracoes.cfg"


func test_padroes_iguais_a_v01(t) -> void:
	var s := Settings.new()
	t.near(s.fov, 70.0, 0.001, "campo de visão da v0.1")
	t.near(s.mouse_sens, 1.0, 0.001, "sensibilidade da v0.1")
	t.near(s.view_distance, TerrainView.MAX_VIEW_DIST, 0.001, "distância de visão da v0.1")
	t.check(s.shadows and s.vsync and s.show_help and not s.fullscreen and not s.invert_y, "o resto como era")


func test_salvar_e_carregar(t) -> void:
	var s := Settings.new()
	s.fullscreen = true
	s.max_fps = 60
	s.view_distance = 448.0
	s.shadows = false
	s.fov = 85.0
	s.mouse_sens = 1.5
	s.invert_y = true
	s.show_help = false
	t.check(s.save_file(TMP_PATH) == OK, "gravou")
	var b := Settings.new()
	b.load_file(TMP_PATH)
	t.check(b.fullscreen and b.max_fps == 60 and not b.shadows and b.invert_y and not b.show_help, "opções voltaram")
	t.near(b.view_distance, 448.0, 0.001, "distância de visão")
	t.near(b.fov, 85.0, 0.001, "campo de visão")
	t.near(b.mouse_sens, 1.5, 0.001, "sensibilidade")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))


func test_valores_fora_da_faixa_voltam_pra_faixa(t) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "limite_fps", 47)
	cfg.set_value("video", "distancia_visao", 600.0)
	cfg.set_value("video", "campo_visao", 500.0)
	cfg.set_value("controles", "sensibilidade", -3.0)
	cfg.save(TMP_PATH)
	var s := Settings.new()
	s.load_file(TMP_PATH)
	t.check(s.max_fps == 0, "limite de FPS que não existe vira sem limite")
	t.near(s.view_distance, 704.0, 0.001, "distância vai pra opção mais próxima")
	t.near(s.fov, Settings.FOV_MAX, 0.001, "campo de visão no máximo")
	t.near(s.mouse_sens, Settings.SENS_MIN, 0.001, "sensibilidade no mínimo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))


func test_sem_arquivo_fica_o_padrao(t) -> void:
	var s := Settings.new()
	s.load_file("user://nao_existe_configuracoes.cfg")
	t.near(s.fov, 70.0, 0.001, "sem arquivo, padrão")


func test_distancia_de_visao_corta_o_terreno(t) -> void:
	var p := Vector3(1024, 0, 1024)
	var far := TerrainView.wanted_chunks(p, 2048.0)
	var near := TerrainView.wanted_chunks(p, 2048.0, {}, 448.0)
	t.check(near.size() < far.size(), "perto carrega menos pedaços (%d < %d)" % [near.size(), far.size()])
	var max_d := 0.0
	for key in near:
		max_d = maxf(max_d, TerrainView.chunk_distance(p, key))
	t.check(max_d <= 448.0, "nenhum pedaço além da distância (%.0f m)" % max_d)
	t.check(near.has(Vector2i(8, 8)), "o pedaço embaixo do jogador continua")
	# Um pedaço já carregado na divisa não some por poucos metros (histerese).
	var edge := {}
	for key in far:
		var d := TerrainView.chunk_distance(p, key)
		if d > 448.0 and d <= 448.0 + TerrainView.LOD_HYSTERESIS:
			edge[key] = far[key]
	t.check(not edge.is_empty(), "achou pedaço na divisa pra testar")
	if not edge.is_empty():
		var kept := TerrainView.wanted_chunks(p, 2048.0, edge, 448.0)
		t.check(kept.has(edge.keys()[0]), "pedaço na divisa fica")
