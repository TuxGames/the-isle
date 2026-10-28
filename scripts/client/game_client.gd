class_name GameClient
extends Node3D
## O jogo do lado do jogador: menu, conexão, controle do próprio dino, câmera,
## e o desenho dos outros dinos a partir dos snapshots do servidor.
##
## O próprio dino é movido aqui (fica suave mesmo com ping) e a posição vai pro
## servidor 20x por segundo. Vida, fome, mordidas etc. quem decide é o servidor.
##
## Argumentos úteis (depois do "--"):
##   --connect=IP[:porta] --name=Tux --password=... --species=carnotaurus   entra direto
##   --solo                                                   abre servidor local e entra
##   --screenshot=arquivo.png --screenshot-after=8            tira print (testes)
##   --open-settings=Vídeo|Controles|Interface|Conta          abre as configurações (prints)
##   --fake-latest=v9.9.9                                     finge que saiu versão nova (prints)
##   --auto-sniff=3                                           fareja sozinho N s depois de entrar (prints)

const MOUSE_SENS := 0.0035

var hud: Hud
var settings := Settings.new()
var terrain: Terrain
var terrain_view: TerrainView
var camera: Camera3D
## Rastro do faro (tecla F).
var scent_view: ScentView
## Ninhos e ovos (s_nests) e se estou segurando N.
var nest_view: NestView
var _nest_list: Array = []
var _holding_nest := false
## Clima: dia/noite, chuva, neve, gelo, seca e raio (o mesmo Climate do servidor).
var weather_view: WeatherView

## Outros dinos e carcaças: id -> DinoView
var views := {}
## id (texto) -> nome do jogador
var roster := {}

var my_id := 0
var my_species := "carnotaurus"
var my_view: DinoView
var my_pos := Vector3.ZERO
var my_yaw := 0.0
var my_seq := 0
var stats := PackedFloat32Array()
var alive := false
var in_game := false
var interacting := false

var cam_yaw := 0.0
var cam_pitch := -0.3

var _moving := false
var _sprinting := false
var _send_accum := 0.0
var _attack_cd := 0.0
var _shake := 0.0
var _server_pid := -1
var _pending_login := {}
var _args := {}
var _connect_timer: SceneTreeTimer
## Nome com que o servidor aceitou o login, e a chave nova de uma troca de senha em andamento.
var _my_name := ""
var _pending_new_key := ""
## Quando (Time.get_ticks_msec) o faro fica pronto de novo, pelo que o servidor disse.
## A recarga de verdade quem confere é o servidor; isto só serve pro HUD e pra não mandar à toa.
var _sniff_ready_ms := 0


func start(args: Dictionary) -> void:
	_args = args
	_setup_input()
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.connect_requested.connect(_join)
	hud.host_requested.connect(_host)
	hud.respawn_requested.connect(_respawn)
	hud.chat_submitted.connect(_on_chat)
	hud.leave_requested.connect(_leave)
	settings.load_file()
	settings.apply_window()
	hud.setup_settings(settings)
	hud.settings_panel.changed.connect(_apply_settings)
	hud.settings_panel.change_password_requested.connect(_change_password)
	hud.settings_panel.forget_password_requested.connect(func(): hud.forget_key())
	Net.password_changed.connect(_on_password_changed)
	# Códigos de resgate (aba Conta) e painel de admin (aba Admin). Quem confere tudo é o servidor.
	hud.settings_panel.redeem_requested.connect(_redeem_code)
	hud.settings_panel.create_code_requested.connect(func(reward, param, uses, days):
		if _my_name != "":
			Net.c_staff_create_code.rpc_id(1, reward, param, uses, days))
	hud.settings_panel.list_codes_requested.connect(func():
		if _my_name != "":
			Net.c_staff_list_codes.rpc_id(1))
	hud.settings_panel.revoke_code_requested.connect(func(code):
		if _my_name != "":
			Net.c_staff_revoke_code.rpc_id(1, code))
	Net.redeem_result.connect(func(ok, text, perks): hud.settings_panel.show_redeem_result(ok, text, perks))
	Net.staff_codes.connect(func(list, created, text): hud.settings_panel.show_staff_codes(list, created, text))

	Net.welcome_received.connect(_on_welcome)
	Net.login_failed.connect(_on_login_failed)
	Net.snapshot_received.connect(_on_snapshot)
	Net.self_stats_received.connect(_on_self_stats)
	Net.roster_received.connect(_on_roster)
	Net.teleport_received.connect(_on_teleport)
	Net.event_received.connect(_on_event)
	Net.died.connect(_on_died)
	Net.message_received.connect(func(t): hud.add_message(t))
	Net.scent_received.connect(_on_scent)
	Net.nests_received.connect(_on_nests)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = settings.fov
	camera.far = settings.view_distance + 50.0
	camera.position = Vector3(256, 80, 100)
	add_child(camera)
	camera.look_at(Vector3(256, 0, 256))
	scent_view = ScentView.new()
	add_child(scent_view)
	nest_view = NestView.new()
	add_child(nest_view)

	hud.fill_menu(String(args.get("name", "")), String(args.get("connect", "")), String(args.get("species", "")))
	if args.has("cam-yaw"):
		cam_yaw = float(args["cam-yaw"])
	if args.has("cam-pitch"):
		cam_pitch = float(args["cam-pitch"])
	if args.has("solo"):
		_host(String(args.get("name", "Jogador")), String(args.get("species", "carnotaurus")),
				String(args.get("password", "")))
	elif args.has("connect"):
		_join(String(args.get("name", "Jogador")), String(args["connect"]), String(args.get("species", "carnotaurus")),
				String(args.get("password", "")))
	if args.has("open-settings"):
		hud.open_settings(String(args["open-settings"]))
	var updates := UpdateCheck.new()
	updates.name = "UpdateCheck"
	add_child(updates)
	updates.update_available.connect(hud.show_update)
	updates.start(String(args.get("fake-latest", "")))
	if args.has("autopilot"):
		_autopilot()
	if args.has("screenshot"):
		var secs := float(args.get("screenshot-after", 8.0))
		get_tree().create_timer(secs).timeout.connect(_take_screenshot.bind(String(args["screenshot"])))


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "interact": [KEY_E], "rest": [KEY_C],
		"chat": [KEY_ENTER, KEY_KP_ENTER], "menu": [KEY_ESCAPE], "help": [KEY_F1],
		"sniff": [KEY_F], "nest": [KEY_N], "mate": [KEY_R],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


# ---------------------------------------------------------------- conexão

func _join(player_name: String, address: String, species_id: String, password: String = "") -> void:
	if player_name == "":
		hud.set_menu_status("Digite um nome.")
		return
	if address == "":
		hud.set_menu_status("Digite o endereço do servidor.")
		return
	# A senha vira uma chave aqui mesmo; a senha em si não sai deste PC.
	var key := ""
	if password != "":
		if password.length() < Accounts.MIN_PASSWORD:
			hud.set_menu_status("A senha precisa de pelo menos %d letras ou números." % Accounts.MIN_PASSWORD)
			return
		key = Accounts.client_key(player_name, password)
	else:
		key = hud.remembered_key(player_name)
		if key == "":
			hud.set_menu_status("Digite sua senha. Na primeira vez num servidor, a senha que você digitar vira a senha do seu nome.")
			return
	hud.save_prefs(key)
	var host := address
	var port := GameConfig.DEFAULT_PORT
	if address.count(":") == 1:
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	Net.disconnect_from_server()
	var err := Net.connect_to(host, port)
	if err != OK:
		hud.set_menu_status("Não consegui iniciar a conexão (%s)." % error_string(err))
		return
	_pending_login = {"name": player_name, "species": species_id, "key": key}
	hud.set_menu_status("Conectando em %s:%d..." % [host, port])
	_connect_timer = get_tree().create_timer(10.0)
	_connect_timer.timeout.connect(func():
		if not in_game and multiplayer.multiplayer_peer != null \
				and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			Net.disconnect_from_server()
			hud.set_menu_status("Sem resposta do servidor em %s:%d. Confira o IP, se o servidor está ligado e o Tailscale." % [host, port]))


## "Testar sozinho": abre um servidor dedicado neste PC (processo separado) e entra nele.
func _host(player_name: String, species_id: String, password: String = "") -> void:
	if player_name == "":
		player_name = "Jogador"
	if _server_pid <= 0:
		var exe := OS.get_executable_path()
		var cmd: PackedStringArray = ["--headless"]
		if OS.has_feature("editor"):
			cmd.append_array(["--path", ProjectSettings.globalize_path("res://")])
		cmd.append_array(["--", "--server", "--dev", "--port=%d" % GameConfig.DEFAULT_PORT,
				"--save=user://save/solo.json"])
		_server_pid = OS.create_process(exe, cmd)
		if _server_pid <= 0:
			hud.set_menu_status("Não consegui abrir o servidor local.")
			return
		hud.set_menu_status("Abrindo servidor local...")
		await get_tree().create_timer(2.0).timeout
	_join(player_name, "127.0.0.1", species_id, password)


func _on_connected() -> void:
	Net.c_password.rpc_id(1, String(_pending_login.get("key", "")))
	Net.c_login.rpc_id(1, String(_pending_login.get("name", "Jogador")),
			String(_pending_login.get("species", "carnotaurus")), GameConfig.VERSION)
	hud.set_menu_status("Conectado, entrando...")


func _on_connection_failed() -> void:
	Net.disconnect_from_server()
	hud.set_menu_status("Falha ao conectar. Confira o endereço e se o servidor está ligado.")


func _on_server_disconnected() -> void:
	_clear_world()
	hud.show_menu("A conexão com o servidor caiu.")


func _on_login_failed(reason: String) -> void:
	Net.disconnect_from_server()
	_clear_world()
	hud.show_menu(reason)
	if reason.begins_with("Versão diferente"):
		hud.show_update("", GameConfig.RELEASES_PAGE)


func _leave() -> void:
	Net.disconnect_from_server()
	_clear_world()
	hud.show_menu("Você saiu. Seu dino ficou congelado no servidor.")


func _clear_world() -> void:
	in_game = false
	alive = false
	for v in views.values():
		v.queue_free()
	views.clear()
	if my_view:
		my_view.queue_free()
		my_view = null
	my_id = 0
	my_seq = 0
	stats = PackedFloat32Array()
	_my_name = ""
	_sniff_ready_ms = 0
	scent_view.clear()
	nest_view.clear()
	_nest_list = []
	_holding_nest = false
	hud.set_nest_ready(false)
	hud.set_nest_status("")
	hud.set_mate_request("")
	if weather_view:
		weather_view.pause()
	hud.set_account("")
	hud.settings_panel.set_admin(false)
	hud.settings_panel.set_perks({})
	hud.settings_panel.set_boost(0.0)


# ---------------------------------------------------------------- mensagens do servidor

func _on_welcome(info: Dictionary) -> void:
	my_id = int(info["entity_id"])
	my_species = String(info["species"])
	var map_size := Terrain.normalize_size(float(info.get("map_size", GameConfig.DEFAULT_MAP_SIZE)))
	if terrain == null or terrain.seed_value != int(info["seed"]) or terrain.size != map_size:
		if terrain_view:
			terrain_view.queue_free()
		terrain = Terrain.get_shared(int(info["seed"]), map_size)
		terrain_view = TerrainView.build(terrain)
		add_child(terrain_view)
		terrain_view.set_view_distance(settings.view_distance)
		terrain_view.set_shadows(settings.shadows)
		if weather_view:
			weather_view.queue_free()
		weather_view = WeatherView.create(terrain, terrain_view, int(info["seed"]))
		add_child(weather_view)
		weather_view.weather_text_changed.connect(hud.set_weather)
	var forced = info.get("weather_override", [])
	weather_view.set_overrides(forced if forced is Array else [])
	weather_view.sync_time(float(info.get("world_time", 0.0)))
	_holding_nest = false
	if my_view:
		my_view.queue_free()
	if views.has(my_id):
		views[my_id].queue_free()
		views.erase(my_id)
	my_view = DinoView.create(my_id, my_species, GameConfig.PLAYER_START_GROWTH)
	my_view.is_local = true
	add_child(my_view)
	alive = true
	in_game = true
	stats = PackedFloat32Array()
	_my_name = String(info.get("name", _pending_login.get("name", "")))
	_draw_nests()
	hud.set_account(_my_name)
	hud.settings_panel.set_perks(info.get("perks", {}))
	var admin := bool(info.get("admin", false))
	hud.settings_panel.set_admin(admin)
	if admin:
		Net.c_staff_list_codes.rpc_id(1)
	# --open-settings=Admin só funciona depois que o servidor diz quem é admin (prints).
	if _args.has("open-settings"):
		hud.open_settings(String(_args["open-settings"]))
	hud.show_game()
	hud.hide_death()
	if bool(info.get("account_created", false)):
		hud.add_message("Conta criada: \"%s\" agora tem senha. Guarde ela, é o que protege o seu dino." % String(info.get("name", "")))
	if bool(info.get("restored", false)):
		hud.add_message("Bem-vindo de volta! Seu %s estava te esperando." % Species.display_name(my_species))
	else:
		hud.add_message("Você nasceu como %s jovem. Coma, beba e cresça." % Species.display_name(my_species))
	if bool(info.get("dev", false)):
		hud.add_message("Servidor em modo dev: Enter → /grow 1, /tp x z, /hp 50, /food 100 100, /kill, /time inverno, /weather chuva")
	if not _args.has("screenshot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# --cmd="/grow 1;/tp 200 200": comandos de dev automáticos (prints e testes).
	if _args.has("cmd"):
		for c in String(_args["cmd"]).split(";", false):
			Net.c_action.rpc_id(1, Net.Action.DEV, c.strip_edges())
	if _args.has("auto-sniff"):
		get_tree().create_timer(float(_args["auto-sniff"])).timeout.connect(_sniff)


func _on_teleport(seq: int, pos: Vector3, yaw: float) -> void:
	my_seq = seq
	my_pos = pos
	my_yaw = yaw
	if not _args.has("cam-yaw"):
		cam_yaw = yaw
	if my_view:
		my_view.position = pos
		my_view.rotation.y = yaw


func _on_snapshot(data: PackedFloat32Array) -> void:
	if not in_game:
		return
	var seen := {}
	var i := 0
	while i + Net.SNAP_STRIDE <= data.size():
		var id := int(data[i])
		var flags := int(data[i + 7])
		i += Net.SNAP_STRIDE
		if id == my_id:
			continue
		seen[id] = true
		var dead := (flags & Net.SF_DEAD) != 0
		var v: DinoView = views.get(id)
		var sp_id := Species.id_at(int(data[i - Net.SNAP_STRIDE + 1]))
		if v == null or v.is_dead != dead or v.species != sp_id:
			if v:
				v.queue_free()
			v = DinoView.create(id, sp_id, data[i - Net.SNAP_STRIDE + 2], dead)
			add_child(v)
			views[id] = v
			v.set_player_name(String(roster.get(str(id), "")))
		var b := i - Net.SNAP_STRIDE
		v.set_growth(data[b + 2])
		v.set_target(Vector3(data[b + 3], data[b + 4], data[b + 5]), data[b + 6], flags)
		if dead:
			v.position = Vector3(data[b + 3], data[b + 4], data[b + 5])
			v.rotation.y = data[b + 6]
	for id in views.keys():
		if not seen.has(id):
			views[id].queue_free()
			views.erase(id)


func _on_self_stats(st: PackedFloat32Array) -> void:
	stats = st
	hud.set_stats(st, my_species)
	if weather_view and st.size() > Net.ST_WORLD_TIME:
		weather_view.sync_time(st[Net.ST_WORLD_TIME])
	if st.size() > Net.ST_GROWTH_BOOST:
		hud.settings_panel.set_boost(st[Net.ST_GROWTH_BOOST])
	if my_view:
		my_view.set_growth(st[Net.ST_GROWTH])
		var f := 0
		if st[Net.ST_RESTING] > 0.5:
			f |= Net.SF_REST
		if st[Net.ST_INTERACT] > 0.5:
			f |= Net.SF_EAT
		if st[Net.ST_HEALTH] / maxf(st[Net.ST_MAX_HEALTH], 0.001) < Movement.LIMP_HEALTH:
			f |= Net.SF_LIMP
		# Osso quebrado também manca (a velocidade já vem limitada em ST_WALK/ST_SPRINT).
		if st.size() > Net.ST_FRACTURE and st[Net.ST_FRACTURE] > 0.0:
			f |= Net.SF_LIMP
		my_view.flags = f
	_update_nest_hud(st)


func _on_roster(r: Dictionary) -> void:
	roster = r
	for id in views:
		views[id].set_player_name(String(roster.get(str(id), "")))
	hud.set_roster(roster.values())


func _on_event(kind: int, a: int, b: int, value: float, text: String) -> void:
	match kind:
		WorldSim.Ev.ATTACK:
			if a != my_id and views.has(a):
				views[a].play_attack()
		WorldSim.Ev.HIT:
			if b == my_id:
				var max_hp := stats[Net.ST_MAX_HEALTH] if stats.size() > 0 else 100.0
				hud.damage_flash(value / maxf(max_hp, 1.0))
				_shake = 0.35
				var who := "um " + Species.display_name(views[a].species) if views.has(a) else "algo"
				if roster.has(str(a)):
					who = roster[str(a)]
				hud.add_message("Você levou um golpe de %s no(a) %s (−%d)" % [who, text, roundi(value)])
			elif views.has(b):
				views[b].flash_damage()
			if a == my_id:
				hud.add_message("Acertou: %s (−%d)" % [text, roundi(value)])
		WorldSim.Ev.LIGHTNING:
			# Raio (só cai em bot): "x;y;z" no texto.
			var p := text.split(";")
			if weather_view and p.size() == 3:
				weather_view.lightning(Vector3(float(p[0]), float(p[1]), float(p[2])))
		WorldSim.Ev.WEATHER:
			# /weather (dev): "de;até" no texto; a < 0 volta ao normal.
			var span := text.split(";")
			if weather_view and span.size() == 2:
				weather_view.set_override(a, float(span[0]), float(span[1]))


## Resposta do faro. `ok` false: ainda em recarga (o servidor diz quanto falta).
func _on_scent(ok: bool, data: PackedFloat32Array, cooldown: float) -> void:
	_sniff_ready_ms = Time.get_ticks_msec() + int(cooldown * 1000.0)
	if not ok:
		hud.add_message("Faro em recarga: %d s" % ceili(cooldown))
		return
	if terrain:
		scent_view.show_scent(data, terrain)
	if data.is_empty():
		hud.add_message("Nenhum cheiro por perto.")


## Ninhos (s_nests): desenha todos; o meu decide o botão "Nascer no ninho" da tela de morte.
func _on_nests(list: Array, mine: Dictionary) -> void:
	_nest_list = list
	_draw_nests()
	hud.set_nest_ready(bool(mine.get("ready", false)), String(mine.get("species", "")))


func _draw_nests() -> void:
	if terrain:
		nest_view.show_nests(_nest_list, terrain, _my_name)


## Reprodução no HUD: ninho, recarga da postura e pedido de parceiro de outro jogador.
func _update_nest_hud(st: PackedFloat32Array) -> void:
	if st.size() < Net.ST_COUNT:
		return
	hud.set_nest_status(Nests.status_text(int(st[Net.ST_NEST_EGGS]), int(st[Net.ST_NEST_READY]),
			st[Net.ST_NEST_HATCH], st[Net.ST_LAY_COOLDOWN]))
	var ask: float = st[Net.ST_MATE_ASK]
	var who := String(roster.get(str(int(st[Net.ST_MATE_FROM])), "Alguém"))
	hud.set_mate_request("" if ask <= 0.0 else "%s quer fazer ninho com você · aperte R (%d s)" % [who, ceili(ask)])


func _on_died(cause: String) -> void:
	alive = false
	interacting = false
	_holding_nest = false
	if my_view:
		my_view.queue_free()
		my_view = null
	hud.set_mate_request("")
	hud.show_death(cause)


func _respawn(species_id: String) -> void:
	Net.c_action.rpc_id(1, Net.Action.RESPAWN, species_id)


func _on_chat(text: String) -> void:
	if text.begins_with("/"):
		Net.c_action.rpc_id(1, Net.Action.DEV, text)
	else:
		Net.c_action.rpc_id(1, Net.Action.CHAT, text)


# ---------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and hud.is_settings_open():
		hud.close_settings()
		get_viewport().set_input_as_handled()
		return
	if not in_game:
		return
	if event.is_action_pressed("menu"):
		if hud.death.visible:
			return
		hud.close_chat()
		hud.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if hud.is_blocking_input():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * settings.mouse_sens
		cam_yaw -= event.relative.x * sens
		cam_pitch = clampf(cam_pitch - event.relative.y * sens * (-1.0 if settings.invert_y else 1.0), -1.25, 0.35)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") and alive:
		_try_attack()
	elif event.is_action_pressed("rest") and alive:
		Net.c_action.rpc_id(1, Net.Action.REST_TOGGLE, "")
	elif event.is_action_pressed("sniff") and alive:
		_sniff()
	elif event.is_action_pressed("mate") and alive:
		Net.c_mate.rpc_id(1)
	elif event.is_action_pressed("chat"):
		hud.open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		hud.toggle_help()
		settings.show_help = hud.is_help_visible()
		settings.save_file()


# ---------------------------------------------------------------- configurações

## Chamado a cada mudança na tela de configurações: aplica na hora e grava.
func _apply_settings() -> void:
	settings.apply_window()
	camera.fov = settings.fov
	camera.far = settings.view_distance + 50.0
	if terrain_view:
		terrain_view.set_view_distance(settings.view_distance)
		terrain_view.set_shadows(settings.shadows)
	hud.set_help_visible(settings.show_help)
	settings.save_file()


func _change_password(old_password: String, new_password: String, repeat: String) -> void:
	if _my_name == "":
		hud.settings_panel.set_password_status("Entre num servidor pra trocar a senha.", false)
	elif new_password.length() < Accounts.MIN_PASSWORD:
		hud.settings_panel.set_password_status("A senha nova precisa de pelo menos %d letras ou números." % Accounts.MIN_PASSWORD, false)
	elif new_password != repeat:
		hud.settings_panel.set_password_status("A senha nova e a repetição não batem.", false)
	else:
		_pending_new_key = Accounts.client_key(_my_name, new_password)
		Net.c_set_password.rpc_id(1, Accounts.client_key(_my_name, old_password), _pending_new_key)
		hud.settings_panel.set_password_status("Trocando...", false)


func _redeem_code(code: String) -> void:
	if _my_name == "":
		hud.settings_panel.show_redeem_result(false, "Entre num servidor pra resgatar códigos.", {})
	elif code == "":
		hud.settings_panel.show_redeem_result(false, "Digite o código.", {})
	else:
		Net.c_redeem_code.rpc_id(1, code)


func _on_password_changed(ok: bool, text: String) -> void:
	hud.settings_panel.set_password_status(text, ok)
	# Se este PC lembrava a senha velha, passa a lembrar a nova.
	if ok and hud.remembered_key(_my_name) != "":
		hud.save_prefs(_pending_new_key)
	_pending_new_key = ""


func _sniff() -> void:
	if not in_game or not alive:
		return
	var left := _sniff_seconds_left()
	if left > 0.0:
		hud.add_message("Faro em recarga: %d s" % ceili(left))
		return
	Net.c_sniff.rpc_id(1)


func _sniff_seconds_left() -> float:
	return maxf(0.0, (_sniff_ready_ms - Time.get_ticks_msec()) / 1000.0)


func _try_attack() -> void:
	if _attack_cd > 0.0 or my_view == null:
		return
	_attack_cd = float(Species.DATA[my_species]["attack_cooldown"])
	Net.c_action.rpc_id(1, Net.Action.ATTACK, "")
	my_view.play_attack()


# ---------------------------------------------------------------- quadro a quadro

func _process(delta: float) -> void:
	if not in_game:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if alive and my_view:
		_update_local(delta)
	_update_camera(delta)
	if terrain_view:
		terrain_view.focus = my_pos
	_send_accum += delta
	if alive and my_seq > 0 and _send_accum >= 1.0 / GameConfig.CLIENT_SEND_HZ:
		_send_accum = 0.0
		var flags := 0
		if _moving:
			flags |= Net.CF_MOVING
		if _sprinting:
			flags |= Net.CF_SPRINT
		Net.c_state.rpc_id(1, my_seq, my_pos, my_yaw, flags)
	hud.set_prompt(_prompt_text())
	hud.set_sniff_status(_sniff_seconds_left())


func _growth() -> float:
	return stats[Net.ST_GROWTH] if stats.size() > 0 else GameConfig.PLAYER_START_GROWTH


func _body_height() -> float:
	var hip: float = Species.DATA[my_species]["hip_height"]
	return hip * Species.scale_for(my_species, _growth())


func _update_local(delta: float) -> void:
	var blocked := hud.is_blocking_input()
	var want_interact := not blocked and Input.is_action_pressed("interact")
	if want_interact != interacting:
		interacting = want_interact
		Net.c_action.rpc_id(1, Net.Action.INTERACT_START if interacting else Net.Action.INTERACT_STOP, "")
	# Ninho: segurar N parado (quem conta o tempo e confere tudo é o servidor).
	var want_nest := not blocked and Input.is_action_pressed("nest")
	if want_nest != _holding_nest:
		_holding_nest = want_nest
		Net.c_nest.rpc_id(1, _holding_nest)

	var input := Vector2.ZERO
	if not blocked and not interacting:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var walk := stats[Net.ST_WALK] if stats.size() > 0 else 3.0
	var sprint := stats[Net.ST_SPRINT] if stats.size() > 0 else walk
	var cam_fwd := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var cam_right := cam_fwd.cross(Vector3.UP)
	var move := cam_fwd * -input.y + cam_right * input.x
	_sprinting = not blocked and Input.is_action_pressed("sprint")
	_moving = move.length() > 0.1
	if _moving:
		var want := atan2(move.x, move.z)
		my_yaw = Movement.rotate_toward(my_yaw, want, Movement.turn_rate_rad(my_species) * delta)
		var align := cos(wrapf(want - my_yaw, -PI, PI))
		var spd := (sprint if _sprinting else walk) * clampf(align, 0.3, 1.0) * clampf(move.length(), 0.0, 1.0)
		if Movement.is_swimming(terrain, my_pos.x, my_pos.z, _body_height(), _water_level()):
			spd *= Movement.SWIM_SPEED_MULT
		my_pos += Vector3(sin(my_yaw), 0.0, cos(my_yaw)) * spd * delta
	_push_out_of_others()
	my_pos = terrain.clamp_to_play_area(my_pos)
	my_pos.y = Movement.ground_y(terrain, my_pos.x, my_pos.z, _body_height(), _water_level())
	my_view.position = my_pos
	my_view.rotation.y = my_yaw
	if _moving and my_view.flags & Net.SF_REST:
		my_view.flags &= ~Net.SF_REST


## Não atravessa os outros bichos. Quem é mais leve sai mais do caminho.
func _push_out_of_others() -> void:
	var g := _growth()
	var my_r := Species.footprint_radius(my_species, g)
	var my_m := Species.mass_for(my_species, g)
	for v in views.values():
		if v.is_dead:
			continue
		var r: float = Species.footprint_radius(v.species, v.growth) + my_r
		var d := Vector2(my_pos.x - v.position.x, my_pos.z - v.position.z)
		var dist := d.length()
		if dist >= r or dist < 0.001:
			continue
		var m: float = Species.mass_for(v.species, v.growth)
		var share := m / (m + my_m)
		var push := d / dist * (r - dist) * share
		my_pos.x += push.x
		my_pos.z += push.y


func _update_camera(delta: float) -> void:
	var g := _growth()
	var s := Species.scale_for(my_species, g)
	var length := Species.length_m(my_species) * s
	var dist := 3.0 + length * 1.15
	var focus := my_pos + Vector3(0, _body_height() * 1.5 + 0.4, 0)
	var target := _camera_position(focus, dist, cam_pitch)
	if terrain:
		# Morro entre a câmera e o dino? Sobe a câmera aos poucos até enxergar o corpo.
		var body := my_pos + Vector3(0, _body_height() * 0.8, 0)
		var pitch := cam_pitch
		while not _line_clear(body, target) and pitch > -1.3:
			pitch -= 0.08
			target = _camera_position(focus, dist, pitch)
		target.y = maxf(target.y, terrain.height_at(target.x, target.z) + 0.6)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		target += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.4
	camera.global_position = target
	camera.look_at(focus)


func _camera_position(focus: Vector3, dist: float, pitch: float) -> Vector3:
	var dir := Vector3(sin(cam_yaw) * cos(pitch), sin(pitch), cos(cam_yaw) * cos(pitch))
	return focus - dir * dist


func _line_clear(from: Vector3, to: Vector3) -> bool:
	for i in range(1, 13):
		var p := from.lerp(to, i / 12.0)
		if terrain.height_at(p.x, p.z) + 0.3 > p.y:
			return false
	return true


func _prompt_text() -> String:
	if not alive or stats.size() == 0:
		return ""
	if _holding_nest and stats.size() >= Net.ST_COUNT:
		var built: float = stats[Net.ST_NEST_BUILD]
		if built > 0.0:
			return "Fazendo o ninho... %d%%" % floori(built * 100.0)
		if built == 0.0:
			return "Fique parado pra fazer o ninho"
	var res := int(stats[Net.ST_INTERACT])
	if interacting:
		if res == 2:
			return "Bebendo..."
		if res == 1:
			return "Comendo..."
		return "Nada pra comer ou beber aqui"
	var s := Species.scale_for(my_species, _growth())
	var ap: Vector3 = Species.DATA[my_species]["attack_point"]
	var carn := Species.is_carnivore(my_species)
	var fwd := Vector3(sin(my_yaw), 0, cos(my_yaw))
	var mouth := my_pos + fwd * ((ap.z if carn else ap.z * 0.85) * s)
	var reach := WorldSim.MOUTH_REACH * maxf(s, 0.5)
	if _can_drink_at(mouth.x, mouth.z) or _can_drink_at(mouth.x + fwd.x * reach, mouth.z + fwd.z * reach):
		return "[E] beber"
	if weather_view and terrain.is_water(mouth.x, mouth.z) and weather_view.is_frozen(mouth.z):
		return "Água congelada"
	if carn:
		for v in views.values():
			if v.is_dead:
				var cr := Species.length_m(v.species) * Species.scale_for(v.species, v.growth) * 0.5
				if Movement.flat_distance(mouth, v.position) <= cr + reach:
					return "[E] comer"
		for egg in nest_view.egg_positions:
			if Movement.flat_distance(mouth, egg) <= Nests.EGG_REACH_M + reach:
				return "[E] comer ovo"
	else:
		if not terrain.bushes_near(mouth, Terrain.BUSH_RADIUS + reach).is_empty():
			return "[E] comer"
	return _mate_prompt()


## "[R]" quando dá pra chamar alguém pra postura: ninho vazio perto, sem recarga, adulto e um
## adulto da mesma espécie ao lado. Quem confere de verdade é o servidor.
func _mate_prompt() -> String:
	if stats.size() < Net.ST_COUNT or stats[Net.ST_LAY_COOLDOWN] > 0.0 \
			or int(stats[Net.ST_NEST_EGGS]) - int(stats[Net.ST_NEST_READY]) != 0 \
			or _growth() < GameConfig.ADULT_GROWTH:
		return ""
	var near_nest := false
	for n in _nest_list:
		if String(n.get("owner", "")) == _my_name and _my_name != "":
			near_nest = Movement.flat_distance(my_pos, n["pos"]) <= GameConfig.MATE_NEST_DIST
	if not near_nest:
		return ""
	var mine := Species.footprint_radius(my_species, _growth())
	for v in views.values():
		if v.is_dead or v.species != my_species or v.growth < GameConfig.ADULT_GROWTH:
			continue
		var reach: float = GameConfig.MATE_RANGE_M + mine + Species.footprint_radius(v.species, v.growth)
		if Movement.flat_distance(my_pos, v.position) <= reach:
			return "[R] chamar pra fazer ninho"
	return ""


## Nível do rio agora (baixa na seca), pelo clima calculado aqui.
func _water_level() -> float:
	return weather_view.water_level() if weather_view else Terrain.WATER_LEVEL


## Dá pra beber aqui? Água congelada ou que secou não serve (o servidor confere igual).
func _can_drink_at(x: float, z: float) -> bool:
	return weather_view.can_drink(x, z) if weather_view else terrain.is_water(x, z)


# ---------------------------------------------------------------- utilidades

## --autopilot: aperta as teclas sozinho (anda, corre, vira, morde, tenta comer).
## Usado nos testes pra exercitar o controle de verdade sem ninguém no teclado.
func _autopilot() -> void:
	while not in_game or stats.size() == 0:
		await get_tree().process_frame
	var start := my_pos
	Input.action_press("move_forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_press("sprint")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("sprint")
	Input.action_press("move_left")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_left")
	Input.action_release("move_forward")
	_try_attack()
	await get_tree().create_timer(1.2).timeout
	_try_attack()
	Input.action_press("interact")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("interact")
	print("AUTOPILOT: andou %.1f m, fôlego %.0f, prompt='%s'" % [
		Movement.flat_distance(start, my_pos), stats[Net.ST_STAMINA], _prompt_text()])


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("print salvo em ", path)


func _ready() -> void:
	# Quem fecha o jogo somos nós (ver _notification): primeiro sai do servidor
	# pra ele salvar o dino, depois fecha o servidor local (se tiver) e o jogo.
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()
	elif what == NOTIFICATION_EXIT_TREE and _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


var _quitting := false


func _quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	var was_online := in_game
	Net.disconnect_from_server()
	if _server_pid > 0:
		# Dá tempo do servidor local perceber a saída e salvar antes de fechar.
		if was_online:
			await get_tree().create_timer(0.8).timeout
		OS.kill(_server_pid)
		_server_pid = -1
	get_tree().quit()
