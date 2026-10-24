class_name SettingsPanel
extends Control
## Tela de configurações (abre pelo menu e pelo Esc). Mexe direto no objeto Settings e avisa
## com `changed`; quem aplica e grava é o GameClient. A aba Conta pede a troca de senha ao
## servidor, então só funciona com o jogador dentro de um servidor.

signal changed
signal change_password_requested(old_password: String, new_password: String, repeat: String)
signal forget_password_requested
signal closed

const TABS := ["Vídeo", "Controles", "Interface", "Conta"]

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
	panel.custom_minimum_size = Vector2(560, 440)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label("Configurações", 26, Hud.ACCENT))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_tabs.add_child(_video_tab())
	_tabs.add_child(_controls_tab())
	_tabs.add_child(_interface_tab())
	_tabs.add_child(_account_tab())
	for i in TABS.size():
		_tabs.set_tab_title(i, TABS[i])

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
	if TABS.has(tab):
		_tabs.current_tab = TABS.find(tab)
	visible = true


## Nome de quem está logado, ou "" fora de um servidor.
func set_account(player_name: String) -> void:
	if _account_label == null:
		return
	var online := player_name != ""
	_account_label.text = "Conectado como %s." % player_name if online \
			else "Entre num servidor pra trocar a sua senha."
	_account_form.visible = online
	_pass_status.text = ""


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
			+ "C descansar · Enter chat/comandos · F1 ajuda · Esc menu", 13, Color(0.8, 0.8, 0.75))
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
	return b


# ---------------------------------------------------------------- peças

func _tab_box(title: String) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.name = title
	b.add_theme_constant_override("separation", 10)
	return b


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
