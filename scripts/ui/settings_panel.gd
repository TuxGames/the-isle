class_name SettingsPanel
extends Control
## Tela de configurações (abre pelo menu e pelo Esc). Mexe direto no objeto Settings e avisa
## com `changed`; quem aplica e grava é o GameClient. A aba Conta (senha e códigos) e a aba
## Admin (só aparece pra admin) falam com o servidor, então só funcionam dentro de um servidor.

signal changed
signal change_password_requested(old_password: String, new_password: String, repeat: String)
signal forget_password_requested
signal redeem_requested(code: String)
signal create_code_requested(reward: String, param: String, uses: int, days: int)
signal list_codes_requested
signal revoke_code_requested(code: String)
signal closed

const TABS := ["Vídeo", "Controles", "Interface", "Conta", "Admin"]
const OK_COLOR := Color(0.6, 0.9, 0.55)
const WARN_COLOR := Color(1.0, 0.75, 0.5)

var settings: Settings

var _tabs: TabContainer
var _fov_value: Label
var _sens_value: Label
var _account_label: Label
var _account_form: Control
var _old_pass: LineEdit
var _new_pass: LineEdit
var _repeat_pass: LineEdit
var _pass_status: Label
var _code_box: Control
var _code_edit: LineEdit
var _redeem_status: Label
var _perks_label: Label
var _perks := {}
var _boost_s := 0.0
var _reward_opt: OptionButton
var _minutes: SpinBox
var _minutes_row: Control
var _species_opt: OptionButton
var _species_row: Control
var _uses: SpinBox
var _days: SpinBox
var _created_code: LineEdit
var _staff_status: Label
var _codes_list: VBoxContainer


static func create(p_settings: Settings) -> SettingsPanel:
	var p := SettingsPanel.new()
	p.name = "Configuracoes"
	p.settings = p_settings
	# Ocupa a tela toda (âncoras e margens), senão o painel fica com tamanho zero no canto.
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return p


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Hud.PANEL_BG
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(600, 500)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label("Configurações", 26, Hud.ACCENT))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	for tab in [_video_tab(), _controls_tab(), _interface_tab(), _account_tab(), _admin_tab()]:
		_tabs.add_child(_scroll(tab))
	for i in TABS.size():
		_tabs.set_tab_title(i, TABS[i])
	set_admin(false)

	var close := Button.new()
	close.text = "Fechar"
	close.custom_minimum_size = Vector2(0, 38)
	close.pressed.connect(func():
		visible = false
		closed.emit())
	box.add_child(close)
	set_account("")


## Abre na aba pedida (nome de TABS) ou na que estava.
func open(tab: String = "") -> void:
	if TABS.has(tab) and not _tabs.is_tab_hidden(TABS.find(tab)):
		_tabs.current_tab = TABS.find(tab)
	visible = true


## Nome de quem está logado, ou "" fora de um servidor.
func set_account(player_name: String) -> void:
	if _account_label == null:
		return
	var online := player_name != ""
	_account_label.text = "Conectado como %s." % player_name if online \
			else "Entre num servidor pra trocar a sua senha e resgatar códigos."
	_account_form.visible = online
	_code_box.visible = online
	_pass_status.text = ""
	_redeem_status.text = ""


## A aba Admin só aparece pra quem o servidor diz que é admin.
func set_admin(on: bool) -> void:
	var i := TABS.find("Admin")
	if not on and _tabs.current_tab == i:
		_tabs.current_tab = TABS.find("Conta")
	_tabs.set_tab_hidden(i, not on)


## O que a conta ganhou com códigos ({"beta": bool, "species": [ids]}).
func set_perks(perks: Dictionary) -> void:
	_perks = perks
	_update_perks()


## Segundos de boost de crescimento que faltam (vem com os status do dino).
func set_boost(seconds: float) -> void:
	if absf(seconds - _boost_s) >= 1.0 or (seconds <= 0.0) != (_boost_s <= 0.0):
		_boost_s = seconds
		_update_perks()


func show_redeem_result(ok: bool, text: String, perks: Dictionary) -> void:
	_redeem_status.text = text
	_redeem_status.add_theme_color_override("font_color", OK_COLOR if ok else WARN_COLOR)
	if ok:
		_code_edit.text = ""
	set_perks(perks)


## Resposta do servidor às ações de admin: lista de códigos, código recém-criado e mensagem.
func show_staff_codes(list: Array, created: String, text: String) -> void:
	if created != "":
		_created_code.text = created
	if text != "":
		_staff_status.text = text
	for child in _codes_list.get_children():
		child.queue_free()
	if list.is_empty():
		_codes_list.add_child(_label("Nenhum código criado ainda.", 14, Color(0.8, 0.8, 0.75)))
	for e: Dictionary in list:
		_codes_list.add_child(_code_row(e))


func set_password_status(text: String, ok: bool) -> void:
	_pass_status.text = text
	_pass_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.55) if ok else Color(1.0, 0.75, 0.5))
	if ok:
		_old_pass.text = ""
		_new_pass.text = ""
		_repeat_pass.text = ""


# ---------------------------------------------------------------- abas

func _video_tab() -> Control:
	var b := _tab_box("Vídeo")
	b.add_child(_check("Tela cheia", settings.fullscreen, func(on): settings.fullscreen = on))
	b.add_child(_check("VSync (evita a imagem \"rasgar\" ao virar a câmera)", settings.vsync,
			func(on): settings.vsync = on))
	var fps_names: Array = []
	for f in Settings.FPS_OPTIONS:
		fps_names.append("Sem limite" if f == 0 else "%d por segundo" % f)
	b.add_child(_option("Limite de quadros", fps_names, Settings.FPS_OPTIONS.find(settings.max_fps),
			func(i): settings.max_fps = Settings.FPS_OPTIONS[i]))
	var view_names: Array = []
	for i in Settings.VIEW_NAMES.size():
		view_names.append("%s (%d m)" % [Settings.VIEW_NAMES[i], int(Settings.VIEW_DISTANCES[i])])
	b.add_child(_option("Distância de visão (perto pesa menos em PC fraco)", view_names, settings.view_index(),
			func(i): settings.view_distance = Settings.VIEW_DISTANCES[i]))
	b.add_child(_check("Sombras", settings.shadows, func(on): settings.shadows = on))
	_fov_value = _label("", 14)
	b.add_child(_slider("Campo de visão", Settings.FOV_MIN, Settings.FOV_MAX, 1.0, settings.fov, _fov_value,
			func(v): settings.fov = v; _fov_value.text = "%d°" % int(v)))
	_fov_value.text = "%d°" % int(settings.fov)
	return b


func _controls_tab() -> Control:
	var b := _tab_box("Controles")
	_sens_value = _label("", 14)
	b.add_child(_slider("Sensibilidade do mouse", Settings.SENS_MIN, Settings.SENS_MAX, 0.05, settings.mouse_sens,
			_sens_value, func(v): settings.mouse_sens = v; _sens_value.text = _sens_text(v)))
	_sens_value.text = _sens_text(settings.mouse_sens)
	b.add_child(_check("Inverter o mouse na vertical", settings.invert_y, func(on): settings.invert_y = on))
	var keys := _label("WASD andar · Shift correr · Clique morder · E (segurar) comer/beber\n"
			+ "C descansar · F faro · Enter chat/comandos · F1 ajuda · Esc menu", 13, Color(0.8, 0.8, 0.75))
	b.add_child(keys)
	return b


func _interface_tab() -> Control:
	var b := _tab_box("Interface")
	b.add_child(_check("Mostrar a ajuda dos controles na tela (F1 também liga e desliga)", settings.show_help,
			func(on): settings.show_help = on))
	return b


func _account_tab() -> Control:
	var b := _tab_box("Conta")
	_account_label = _label("", 15)
	b.add_child(_account_label)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 6)
	_account_form = form
	b.add_child(form)
	_old_pass = _secret("Senha atual")
	_new_pass = _secret("Senha nova (pelo menos %d letras ou números)" % Accounts.MIN_PASSWORD)
	_repeat_pass = _secret("Repita a senha nova")
	for e in [_old_pass, _new_pass, _repeat_pass]:
		form.add_child(e)
	var change := Button.new()
	change.text = "Trocar senha"
	change.pressed.connect(func():
		change_password_requested.emit(_old_pass.text, _new_pass.text, _repeat_pass.text))
	form.add_child(change)
	_pass_status = _label("", 14)
	_pass_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(_pass_status)
	var forget := Button.new()
	forget.text = "Esquecer a senha lembrada neste PC"
	forget.pressed.connect(func():
		forget_password_requested.emit()
		set_password_status("Pronto: este PC não lembra mais a sua senha.", true))
	b.add_child(forget)

	var codes := VBoxContainer.new()
	codes.add_theme_constant_override("separation", 6)
	_code_box = codes
	b.add_child(codes)
	codes.add_child(HSeparator.new())
	codes.add_child(_label("Código de resgate", 16, Hud.ACCENT))
	var row := HBoxContainer.new()
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "DINO-XXXX-XXXX"
	_code_edit.max_length = 20
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_submitted.connect(func(t): redeem_requested.emit(t.strip_edges()))
	row.add_child(_code_edit)
	var redeem := Button.new()
	redeem.text = "Resgatar"
	redeem.pressed.connect(func(): redeem_requested.emit(_code_edit.text.strip_edges()))
	row.add_child(redeem)
	codes.add_child(row)
	_redeem_status = _label("", 14)
	_redeem_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codes.add_child(_redeem_status)
	_perks_label = _label("", 14, Color(0.85, 0.9, 0.8))
	_perks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codes.add_child(_perks_label)
	_update_perks()
	return b


func _admin_tab() -> Control:
	var b := _tab_box("Admin")
	b.add_child(_label("Criar código", 16, Hud.ACCENT))
	_reward_opt = OptionButton.new()
	for id in Rewards.ids():
		_reward_opt.add_item(Rewards.display_name(id))
	_reward_opt.item_selected.connect(func(_i): _update_reward_param())
	b.add_child(_row("Recompensa", _reward_opt))
	_minutes = _spin(Rewards.BOOST_MIN_MINUTES, Rewards.BOOST_MAX_MINUTES, GameConfig.GROWTH_BOOST_DEFAULT_MIN)
	_minutes_row = _row("Minutos de boost", _minutes)
	b.add_child(_minutes_row)
	_species_opt = OptionButton.new()
	for id in Species.IDS:
		_species_opt.add_item(Species.display_name(id))
	_species_row = _row("Espécie", _species_opt)
	b.add_child(_species_row)
	_uses = _spin(1, RedeemCodes.MAX_USES, 1)
	b.add_child(_row("Quantas pessoas podem usar", _uses))
	_days = _spin(0, RedeemCodes.MAX_DAYS, 0)
	b.add_child(_row("Vale por quantos dias (0 = sempre)", _days))
	var create := Button.new()
	create.text = "Criar código"
	create.pressed.connect(_on_create_pressed)
	b.add_child(create)
	var made := HBoxContainer.new()
	_created_code = LineEdit.new()
	_created_code.editable = false
	_created_code.placeholder_text = "o código criado aparece aqui"
	_created_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.add_child(_created_code)
	var copy := Button.new()
	copy.text = "Copiar"
	copy.pressed.connect(_on_copy_pressed)
	made.add_child(copy)
	b.add_child(made)
	_staff_status = _label("", 14, OK_COLOR)
	_staff_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(_staff_status)
	b.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	var title := _label("Códigos", 16, Hud.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var refresh := Button.new()
	refresh.text = "Atualizar lista"
	refresh.pressed.connect(func(): list_codes_requested.emit())
	head.add_child(refresh)
	b.add_child(head)
	_codes_list = VBoxContainer.new()
	_codes_list.add_theme_constant_override("separation", 4)
	b.add_child(_codes_list)
	_update_reward_param()
	return b


func _on_create_pressed() -> void:
	var reward: String = Rewards.ids()[_reward_opt.selected]
	var param := ""
	match String(Rewards.TYPES[reward]["param"]):
		"minutes":
			param = str(int(_minutes.value))
		"species":
			param = Species.IDS[_species_opt.selected]
	create_code_requested.emit(reward, param, int(_uses.value), int(_days.value))


func _on_copy_pressed() -> void:
	if _created_code.text != "":
		DisplayServer.clipboard_set(_created_code.text)
		_staff_status.text = "Copiado: %s" % _created_code.text


func _update_reward_param() -> void:
	var kind := String(Rewards.TYPES[Rewards.ids()[_reward_opt.selected]]["param"])
	_minutes_row.visible = kind == "minutes"
	_species_row.visible = kind == "species"


func _update_perks() -> void:
	if _perks_label == null:
		return
	var lines: Array = []
	if _boost_s > 0.0:
		lines.append("Boost de crescimento: mais %d min (só gasta enquanto você cresce)." % ceili(_boost_s / 60.0))
	if bool(_perks.get("beta", false)):
		lines.append("Acesso beta: sim.")
	var unlocked: Array = Array(_perks.get("species", [])).map(func(id): return Species.display_name(id))
	if not unlocked.is_empty():
		lines.append("Espécies liberadas: %s." % ", ".join(unlocked))
	_perks_label.text = "\n".join(lines) if not lines.is_empty() else "Nenhum código usado ainda."


## Uma linha da lista do admin: código, o que dá, usos, validade e o botão de cancelar.
func _code_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var info := "%s · %s · %d/%d usos" % [e["code"], Rewards.describe(e["reward"], e["param"]),
			int(e["max_uses"]) - int(e["uses_left"]), int(e["max_uses"])]
	if float(e["expires"]) > 0.0:
		var d := Time.get_datetime_dict_from_unix_time(int(e["expires"]))
		info += " · vence %02d/%02d" % [d["day"], d["month"]]
	var active := not bool(e["revoked"]) and int(e["uses_left"]) > 0
	if bool(e["revoked"]):
		info += " · cancelado"
	var l := _label(info, 13, Color(0.95, 0.94, 0.9) if active else Color(0.6, 0.6, 0.58))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	if active:
		var cancel := Button.new()
		cancel.text = "Cancelar"
		var code := String(e["code"])
		cancel.pressed.connect(func(): revoke_code_requested.emit(code))
		row.add_child(cancel)
	return row


# ---------------------------------------------------------------- peças

func _tab_box(title: String) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.name = title
	b.add_theme_constant_override("separation", 10)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## Cada aba rola na vertical se não couber (a Conta e a Admin são compridas).
func _scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = content.name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.add_child(content)
	return s


func _row(title: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var l := _label(title, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(control)
	return row


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	return s


func _label(text: String, size := 15, color := Color(0.95, 0.94, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _check(text: String, on: bool, apply: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(func(v): apply.call(v); changed.emit())
	return c


func _option(title: String, items: Array, selected: int, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := _label(title, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = maxi(selected, 0)
	o.item_selected.connect(func(i): apply.call(i); changed.emit())
	row.add_child(o)
	return row


func _slider(title: String, lo: float, hi: float, step: float, value: float, value_label: Label,
		apply: Callable) -> Control:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	var l := _label(title, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	top.add_child(value_label)
	box.add_child(top)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.value_changed.connect(func(v): apply.call(v); changed.emit())
	box.add_child(s)
	return box


func _secret(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.secret = true
	e.max_length = 64
	e.placeholder_text = placeholder
	return e


static func _sens_text(v: float) -> String:
	return ("%.2fx" % v).replace(".", ",")
