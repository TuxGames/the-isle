class_name Hud
extends CanvasLayer
## Toda a interface: menu de conexão, barras de status, mensagens, tela de morte,
## pausa e caixa de chat/comandos. Montada por código pra não depender do editor.

signal connect_requested(player_name: String, address: String, species_id: String, password: String)
signal host_requested(player_name: String, species_id: String, password: String)
signal respawn_requested(species_id: String)
signal chat_submitted(text: String)
signal leave_requested

const PANEL_BG := Color(0.06, 0.07, 0.06, 0.78)
const ACCENT := Color(0.85, 0.72, 0.42)

var menu: Control
var game: Control
var death: Control
var pause: Control
## Configurações (criado em setup_settings, que o GameClient chama com o objeto Settings).
var settings_panel: SettingsPanel

var _name_edit: LineEdit
var _pass_edit: LineEdit
var _remember: CheckBox
var _addr_edit: LineEdit
var _species_menu: OptionButton
var _menu_status: Label
var _update_row: Control
var _update_label: Label
var _update_url := ""
var _death_species: OptionButton
var _death_label: Label

var _bars := {}
var _species_label: Label
## Ferimentos com o tempo que falta ("Sangrando 2:10 · Osso quebrado 8:40"); some sem ferimento.
var _injury_label: Label
var _clock_label: Label
## Tempo (limpo, chuva, neve...), calculado pelo WeatherView.
var _weather_label: Label
var _roster_label: Label
var _sniff_label: Label
var _prompt_label: Label
var _messages: VBoxContainer
var _flash: ColorRect
var _chat: LineEdit
var _help: Label


func _ready() -> void:
	layer = 10
	_build_menu()
	_build_game()
	_build_death()
	_build_pause()
	show_menu("")


# ---------------------------------------------------------------- construção

func _panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	return p


func _label(text: String, size := 16, color := Color(0.95, 0.94, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _species_option() -> OptionButton:
	var o := OptionButton.new()
	for id in Species.IDS:
		var tag := "carnívoro" if Species.is_carnivore(id) else "herbívoro"
		o.add_item("%s (%s)" % [Species.display_name(id), tag])
	return o


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.13, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := _panel(Vector2(420, 0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("Dino Survival", 34, ACCENT))
	box.add_child(_label("protótipo v%s — nome provisório" % GameConfig.VERSION, 13, Color(0.7, 0.7, 0.65)))
	box.add_child(_label("Seu nome", 14))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "ex.: Marcelo"
	box.add_child(_name_edit)
	box.add_child(_label("Senha (na primeira vez, a que você digitar vira a sua)", 14))
	_pass_edit = LineEdit.new()
	_pass_edit.secret = true
	_pass_edit.max_length = 64
	box.add_child(_pass_edit)
	_remember = CheckBox.new()
	_remember.text = "Lembrar a senha neste PC"
	_remember.button_pressed = true
	box.add_child(_remember)
	_name_edit.text_changed.connect(func(_t): _update_pass_hint())
	box.add_child(_label("Endereço do servidor", 14))
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "IP do Tailscale do servidor, ex.: 100.64.0.5"
	box.add_child(_addr_edit)
	box.add_child(_label("Espécie (só vale se você não tem um dino vivo salvo)", 13))
	_species_menu = _species_option()
	box.add_child(_species_menu)
	var join := Button.new()
	join.text = "Entrar no servidor"
	join.custom_minimum_size = Vector2(0, 40)
	join.pressed.connect(func():
		connect_requested.emit(_name_edit.text.strip_edges(), _addr_edit.text.strip_edges(),
				_selected_species(_species_menu), _pass_edit.text))
	box.add_child(join)
	var host := Button.new()
	host.text = "Testar sozinho (abre um servidor neste PC)"
	host.pressed.connect(func():
		host_requested.emit(_name_edit.text.strip_edges(), _selected_species(_species_menu), _pass_edit.text))
	box.add_child(host)
	var cfg := Button.new()
	cfg.text = "Configurações"
	cfg.pressed.connect(func(): open_settings())
	box.add_child(cfg)
	# Aviso de versão nova (UpdateCheck); escondido até ter novidade.
	var update := HBoxContainer.new()
	update.visible = false
	_update_row = update
	_update_label = _label("", 14, Color(0.6, 0.9, 0.55))
	_update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update.add_child(_update_label)
	var download := Button.new()
	download.text = "Baixar"
	download.pressed.connect(func(): OS.shell_open(_update_url))
	update.add_child(download)
	box.add_child(update)
	_menu_status = _label("", 14, Color(1.0, 0.75, 0.5))
	_menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_status.custom_minimum_size = Vector2(390, 0)
	box.add_child(_menu_status)
	_load_prefs()


func _build_game() -> void:
	game = Control.new()
	game.set_anchors_preset(Control.PRESET_FULL_RECT)
	game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game)

	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(_flash)

	# Status (canto inferior esquerdo)
	var stats := _panel(Vector2(300, 0))
	stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stats.position = Vector2(16, -16)
	stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	game.add_child(stats)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 4)
	stats.add_child(sbox)
	_species_label = _label("", 17, ACCENT)
	sbox.add_child(_species_label)
	_injury_label = _label("", 14, Color(1.0, 0.45, 0.4))
	_injury_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_injury_label.visible = false
	sbox.add_child(_injury_label)
	for key in [["health", "Vida", Color(0.8, 0.2, 0.18)], ["hunger", "Comida", Color(0.85, 0.55, 0.2)],
			["thirst", "Água", Color(0.25, 0.55, 0.9)], ["stamina", "Fôlego", Color(0.9, 0.85, 0.3)],
			["growth", "Crescimento", Color(0.45, 0.75, 0.35)]]:
		sbox.add_child(_make_bar(key[0], key[1], key[2]))

	# Relógio e jogadores (canto superior direito)
	var info := _panel()
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.position = Vector2(-16, 16)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	game.add_child(info)
	var ibox := VBoxContainer.new()
	info.add_child(ibox)
	_clock_label = _label("", 14)
	ibox.add_child(_clock_label)
	_weather_label = _label("", 14, Color(0.75, 0.85, 0.95))
	ibox.add_child(_weather_label)
	_roster_label = _label("", 14, Color(0.85, 0.9, 0.8))
	ibox.add_child(_roster_label)
	_sniff_label = _label("", 14, Color(1.0, 0.86, 0.35))
	ibox.add_child(_sniff_label)

	# Mensagens (canto superior esquerdo)
	_messages = VBoxContainer.new()
	_messages.position = Vector2(16, 16)
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(_messages)

	# Dica de ação (centro, embaixo)
	_prompt_label = _label("", 20)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-150, -90)
	_prompt_label.custom_minimum_size = Vector2(300, 0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.add_child(_prompt_label)

	# Mira (ponto no centro)
	var dot := _label("·", 28, Color(1, 1, 1, 0.6))
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-4, -22)
	game.add_child(dot)

	_help = _label("WASD andar · Shift correr · Clique morder · E (segurar) comer/beber · C descansar\nF faro · Enter chat/comandos · F1 esconder ajuda · Esc menu", 13, Color(0.9, 0.9, 0.85, 0.85))
	_help.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_help.position = Vector2(-560, -58)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help.custom_minimum_size = Vector2(544, 0)
	game.add_child(_help)

	_chat = LineEdit.new()
	_chat.placeholder_text = "Mensagem pros outros, ou /comando (ex.: /grow 1)"
	_chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat.position = Vector2(332, -52)
	_chat.custom_minimum_size = Vector2(420, 0)
	_chat.visible = false
	_chat.text_submitted.connect(_on_chat_submitted)
	game.add_child(_chat)


func _make_bar(key: String, title: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	var l := _label(title, 13)
	l.custom_minimum_size = Vector2(92, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(176, 16)
	bar.show_percentage = false
	bar.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	_bars[key] = bar
	return row


func _build_death() -> void:
	death = Control.new()
	death.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(death)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.0, 0.0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.add_child(center)
	var panel := _panel(Vector2(380, 0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("Você morreu", 30, Color(0.95, 0.4, 0.35)))
	_death_label = _label("", 15)
	box.add_child(_death_label)
	box.add_child(_label("Escolha a espécie. Você recomeça jovem.", 14))
	_death_species = _species_option()
	box.add_child(_death_species)
	var b := Button.new()
	b.text = "Renascer"
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func(): respawn_requested.emit(_selected_species(_death_species)))
	box.add_child(b)


func _build_pause() -> void:
	pause = Control.new()
	pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pause)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.add_child(center)
	var panel := _panel(Vector2(300, 0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("Menu", 24, ACCENT))
	box.add_child(_label("O jogo NÃO pausa: o mundo continua\npros outros. Ao sair, seu dino\nfica congelado até você voltar.", 13))
	var cont := Button.new()
	cont.text = "Continuar"
	cont.pressed.connect(func(): pause.visible = false)
	box.add_child(cont)
	var cfg := Button.new()
	cfg.text = "Configurações"
	cfg.pressed.connect(func(): open_settings())
	box.add_child(cfg)
	var leave := Button.new()
	leave.text = "Sair do servidor"
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave)
	var quit := Button.new()
	quit.text = "Fechar o jogo"
	quit.pressed.connect(func(): get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	box.add_child(quit)


func _selected_species(o: OptionButton) -> String:
	return Species.id_at(o.selected)


# ---------------------------------------------------------------- telas

func show_menu(status: String) -> void:
	menu.visible = true
	game.visible = false
	death.visible = false
	pause.visible = false
	_menu_status.text = status
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_menu_status(text: String) -> void:
	_menu_status.text = text


## Mostra no menu o aviso de versão nova com o botão de baixar. Sem `tag`, só aponta a página
## de downloads (quando o servidor recusou por versão diferente).
func show_update(tag: String, url: String) -> void:
	_update_url = url
	_update_label.text = "Versão nova disponível: %s" % tag if tag != "" \
			else "Baixe a versão do servidor na página de downloads."
	_update_row.visible = true


func show_game() -> void:
	menu.visible = false
	game.visible = true
	death.visible = false
	pause.visible = false


func show_death(cause: String) -> void:
	death.visible = true
	pause.visible = false
	_death_label.text = "Causa: " + cause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_death() -> void:
	death.visible = false


func toggle_pause() -> void:
	pause.visible = not pause.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause.visible else Input.MOUSE_MODE_CAPTURED


func is_blocking_input() -> bool:
	return menu.visible or death.visible or pause.visible or _chat.visible \
			or (settings_panel != null and settings_panel.visible)


func toggle_help() -> void:
	_help.visible = not _help.visible


func set_help_visible(on: bool) -> void:
	_help.visible = on


func is_help_visible() -> bool:
	return _help.visible


func setup_settings(settings: Settings) -> void:
	settings_panel = SettingsPanel.create(settings)
	settings_panel.visible = false
	add_child(settings_panel)
	_help.visible = settings.show_help


## Abre as configurações por cima do que estiver na tela (menu ou Esc).
func open_settings(tab: String = "") -> void:
	if settings_panel:
		settings_panel.open(tab)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	if settings_panel:
		settings_panel.visible = false


func is_settings_open() -> bool:
	return settings_panel != null and settings_panel.visible


func set_account(player_name: String) -> void:
	if settings_panel:
		settings_panel.set_account(player_name)


# ---------------------------------------------------------------- dados

func set_stats(st: PackedFloat32Array, species_id: String) -> void:
	if st.size() < Net.ST_COUNT:
		return
	var max_hp := maxf(st[Net.ST_MAX_HEALTH], 0.001)
	_bars["health"].value = st[Net.ST_HEALTH] / max_hp * 100.0
	_bars["hunger"].value = st[Net.ST_HUNGER]
	_bars["thirst"].value = st[Net.ST_THIRST]
	_bars["stamina"].value = st[Net.ST_STAMINA]
	_bars["growth"].value = st[Net.ST_GROWTH] * 100.0
	var phase := "adulto"
	var g: float = st[Net.ST_GROWTH]
	if g < 0.25:
		phase = "filhote"
	elif g < 0.6:
		phase = "jovem"
	elif g < 1.0:
		phase = "subadulto"
	var rest := "  · descansando" if st[Net.ST_RESTING] > 0.5 else ""
	if st.size() > Net.ST_GROWTH_BOOST and st[Net.ST_GROWTH_BOOST] > 0.0 and g < 1.0:
		rest += "  · boost %d min" % ceili(st[Net.ST_GROWTH_BOOST] / 60.0)
	_species_label.text = "%s — %s%s" % [Species.display_name(species_id), phase, rest]
	_injury_label.text = Injuries.describe({Injuries.BLEED: st[Net.ST_BLEED],
			Injuries.FRACTURE: st[Net.ST_FRACTURE], Injuries.DEEP: st[Net.ST_DEEP]})
	_injury_label.visible = _injury_label.text != ""
	var wt: float = st[Net.ST_WORLD_TIME]
	_clock_label.text = Climate.calendar_text(wt)


## Tempo agora ("Chuva", "Limpo · seca"), do WeatherView.
func set_weather(text: String) -> void:
	_weather_label.text = "Tempo: " + text if text != "" else ""


func set_roster(names: Array) -> void:
	names.sort()
	_roster_label.text = "Online (%d/%d): %s" % [names.size(), GameConfig.MAX_PLAYERS, ", ".join(names)]


## Faro (tecla F): pronto ou quantos segundos faltam.
func set_sniff_status(seconds_left: float) -> void:
	_sniff_label.text = "Faro (F): pronto" if seconds_left <= 0.0 else "Faro (F): %d s" % ceili(seconds_left)


func set_prompt(text: String) -> void:
	_prompt_label.text = text


func add_message(text: String) -> void:
	var l := _label(text, 15)
	_messages.add_child(l)
	while _messages.get_child_count() > 7:
		_messages.get_child(0).queue_free()
		_messages.remove_child(_messages.get_child(0))
	var tw := create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func damage_flash(strength: float) -> void:
	_flash.color.a = clampf(0.15 + strength, 0.15, 0.5)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.5)


func open_chat() -> void:
	_chat.visible = true
	_chat.text = ""
	_chat.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_chat_submitted(text: String) -> void:
	_chat.visible = false
	_chat.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if text.strip_edges() != "":
		chat_submitted.emit(text.strip_edges())


func close_chat() -> void:
	_chat.visible = false
	_chat.release_focus()


# ---------------------------------------------------------------- preferências

const PREFS_PATH := "user://cliente.cfg"

## Chave da senha lembrada (nunca a senha): {"name": nome, "key": Accounts.client_key}.
var _remembered := {}


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) == OK:
		_name_edit.text = cfg.get_value("cliente", "nome", "")
		_addr_edit.text = cfg.get_value("cliente", "endereco", "127.0.0.1")
		_species_menu.selected = int(cfg.get_value("cliente", "especie", 0))
		_remember.button_pressed = bool(cfg.get_value("cliente", "lembrar_senha", true))
		var key := String(cfg.get_value("cliente", "chave", ""))
		if Accounts.is_valid_key(key):
			_remembered = {"name": String(cfg.get_value("cliente", "chave_nome", "")), "key": key}
	else:
		_addr_edit.text = "127.0.0.1"
	_update_pass_hint()


## Grava nome, servidor e espécie. Com "lembrar" marcado, guarda também a chave da senha.
func save_prefs(key: String) -> void:
	if _remember.button_pressed and Accounts.is_valid_key(key):
		_remembered = {"name": _name_edit.text.strip_edges(), "key": key}
	elif not _remember.button_pressed:
		_remembered = {}
	var cfg := ConfigFile.new()
	cfg.set_value("cliente", "nome", _name_edit.text)
	cfg.set_value("cliente", "endereco", _addr_edit.text)
	cfg.set_value("cliente", "especie", _species_menu.selected)
	cfg.set_value("cliente", "lembrar_senha", _remember.button_pressed)
	cfg.set_value("cliente", "chave_nome", String(_remembered.get("name", "")))
	cfg.set_value("cliente", "chave", String(_remembered.get("key", "")))
	cfg.save(PREFS_PATH)
	_pass_edit.text = ""
	_update_pass_hint()


## Apaga a chave lembrada neste PC (aba Conta).
func forget_key() -> void:
	_remember.button_pressed = false
	save_prefs("")


## Chave lembrada pra esse nome, ou "".
func remembered_key(player_name: String) -> String:
	if String(_remembered.get("name", "")).to_lower() == player_name.strip_edges().to_lower():
		return String(_remembered.get("key", ""))
	return ""


func _update_pass_hint() -> void:
	var has_key := remembered_key(_name_edit.text) != ""
	_pass_edit.placeholder_text = "senha lembrada neste PC" if has_key else "sua senha"


func fill_menu(player_name: String, address: String, species_id: String) -> void:
	if player_name != "":
		_name_edit.text = player_name
	if address != "":
		_addr_edit.text = address
	if Species.is_valid(species_id):
		_species_menu.selected = Species.index_of(species_id)
