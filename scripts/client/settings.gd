class_name Settings
extends RefCounted
## Configurações do jogador, salvas no PC dele (user://configuracoes.cfg). Só o cliente usa:
## nada aqui muda regra de jogo. Valores fora da faixa (arquivo editado à mão, versão antiga)
## voltam pra faixa ao carregar.

const PATH := "user://configuracoes.cfg"

## Distância de visão: até onde o terreno é desenhado (TerrainView) e a câmera enxerga.
const VIEW_NAMES := ["Perto", "Média", "Longe"]
const VIEW_DISTANCES := [448.0, 704.0, 1150.0]
## Limite de quadros por segundo (0 = sem limite).
const FPS_OPTIONS := [30, 60, 120, 0]
const FOV_MIN := 60.0
const FOV_MAX := 100.0
## Multiplicador da sensibilidade do mouse (1 = a da v0.1).
const SENS_MIN := 0.25
const SENS_MAX := 3.0

var fullscreen := false
var vsync := true
var max_fps := 0
var view_distance := 1150.0
var shadows := true
var fov := 70.0
var mouse_sens := 1.0
var invert_y := false
var show_help := true


func load_file(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	fullscreen = bool(cfg.get_value("video", "tela_cheia", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	max_fps = int(cfg.get_value("video", "limite_fps", max_fps))
	view_distance = float(cfg.get_value("video", "distancia_visao", view_distance))
	shadows = bool(cfg.get_value("video", "sombras", shadows))
	fov = float(cfg.get_value("video", "campo_visao", fov))
	mouse_sens = float(cfg.get_value("controles", "sensibilidade", mouse_sens))
	invert_y = bool(cfg.get_value("controles", "inverter_y", invert_y))
	show_help = bool(cfg.get_value("interface", "mostrar_ajuda", show_help))
	sanitize()


func save_file(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "tela_cheia", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "limite_fps", max_fps)
	cfg.set_value("video", "distancia_visao", view_distance)
	cfg.set_value("video", "sombras", shadows)
	cfg.set_value("video", "campo_visao", fov)
	cfg.set_value("controles", "sensibilidade", mouse_sens)
	cfg.set_value("controles", "inverter_y", invert_y)
	cfg.set_value("interface", "mostrar_ajuda", show_help)
	return cfg.save(path)


## Traz tudo pra dentro das opções que existem.
func sanitize() -> void:
	if not FPS_OPTIONS.has(max_fps):
		max_fps = 0
	view_distance = VIEW_DISTANCES[view_index()]
	fov = clampf(fov, FOV_MIN, FOV_MAX)
	mouse_sens = clampf(mouse_sens, SENS_MIN, SENS_MAX)


## Índice em VIEW_DISTANCES da opção mais próxima de view_distance.
func view_index() -> int:
	var best := VIEW_DISTANCES.size() - 1
	for i in VIEW_DISTANCES.size():
		if absf(float(VIEW_DISTANCES[i]) - view_distance) < absf(float(VIEW_DISTANCES[best]) - view_distance):
			best = i
	return best


## Aplica o que é da janela (tela cheia, VSync, FPS). O resto quem aplica é o GameClient.
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
