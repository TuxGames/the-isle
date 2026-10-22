class_name GameServer
extends Node
## Servidor dedicado. Roda sem tela (--headless) no PC que fica ligado 24h.
## Recebe os jogadores, roda o WorldSim e manda o estado do mundo pra cada um.
##
## Regras do Marcelo cumpridas aqui:
## - Sem nenhum jogador conectado, o mundo inteiro fica parado (não chama sim.step).
## - Ao sair, o dino do jogador some e fica congelado (WorldSim.logout_player).

var sim: WorldSim
var port: int = GameConfig.DEFAULT_PORT
var save_path: String = "user://save/world.json"
var dev_mode: bool = false

## peer_id -> {"name": String, "dino_id": int}
var peers := {}

var _sim_accum := 0.0
var _snap_accum := 0.0
var _stats_accum := 0.0
var _save_accum := 0.0
var _paused_logged := false
var _roster_dirty := false


func start(args: Dictionary) -> Error:
	port = int(args.get("port", GameConfig.DEFAULT_PORT))
	dev_mode = args.has("dev")
	if args.has("save"):
		save_path = String(args["save"])
	var seed_value := int(args.get("seed", GameConfig.WORLD_SEED))
	var bots := int(args.get("bots", GameConfig.DEFAULT_BOT_TARGET))

	sim = WorldSim.new(seed_value, bots)
	if not _load():
		sim.populate()
		_log("mundo novo criado: semente=%d bots=%d" % [seed_value, sim.bot_count()])
	else:
		sim.bot_target = clampi(bots, 0, GameConfig.BOT_MAX)
		_log("save carregado: world_time=%.2f bots=%d jogadores salvos=%d" % [
			sim.world_time, sim.bot_count(), sim.player_records.size()])

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, GameConfig.MAX_PLAYERS + 3)
	if err != OK:
		_log("ERRO: não consegui abrir a porta %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.server = self
	# Servidor não desenha nada: 30 quadros por segundo bastam e poupam o notebook.
	Engine.max_fps = 30
	_log("servidor ouvindo na porta %d (máx. %d jogadores)%s" % [
		port, GameConfig.MAX_PLAYERS, " [modo dev]" if dev_mode else ""])
	_log("[mundo] pausado em world_time=%.3f (ninguém online)" % sim.world_time)
	_paused_logged = true
	return OK


func _process(delta: float) -> void:
	if sim == null:
		return
	if peers.is_empty():
		# Mundo parado: nada acontece até alguém entrar.
		return

	var step := 1.0 / GameConfig.SIM_HZ
	_sim_accum += minf(delta, 0.25)
	while _sim_accum >= step:
		_sim_accum -= step
		sim.step(step)
		_flush_events()

	_snap_accum += delta
	if _snap_accum >= 1.0 / GameConfig.SNAPSHOT_HZ:
		_snap_accum = 0.0
		_send_snapshots()

	_stats_accum += delta
	if _stats_accum >= 1.0 / GameConfig.SELF_STATS_HZ:
		_stats_accum = 0.0
		_send_self_stats()

	if _roster_dirty:
		_roster_dirty = false
		_send_roster()

	_save_accum += delta
	if _save_accum >= GameConfig.SAVE_INTERVAL_S:
		_save_accum = 0.0
		save()


# ---------------------------------------------------------------- conexões

func _on_peer_connected(id: int) -> void:
	_log("conexão nova (peer %d), aguardando login" % id)


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	var info: Dictionary = peers[id]
	peers.erase(id)
	var dino_id: int = info["dino_id"]
	if dino_id > 0:
		sim.logout_player(dino_id)
	_log("[login] %s saiu (world_time=%.3f)" % [info["name"], sim.world_time])
	_broadcast_message("%s saiu do servidor" % info["name"])
	save()
	_roster_dirty = true
	if peers.is_empty():
		_log("[mundo] pausado em world_time=%.3f (ninguém online)" % sim.world_time)
		_paused_logged = true
		_send_roster()


func on_login(peer_id: int, player_name: String, species_id: String, version: String) -> void:
	if peers.has(peer_id):
		return
	player_name = player_name.strip_edges().substr(0, 16)
	var reason := ""
	if version != GameConfig.VERSION:
		reason = "Versão diferente: o servidor está na %s e o seu jogo na %s." % [GameConfig.VERSION, version]
	elif player_name.is_empty():
		reason = "Digite um nome."
	elif _name_online(player_name):
		reason = "Já tem alguém com o nome \"%s\" no servidor." % player_name
	elif peers.size() >= GameConfig.MAX_PLAYERS:
		reason = "Servidor cheio (%d jogadores)." % GameConfig.MAX_PLAYERS
	if reason != "":
		Net.s_login_failed.rpc_id(peer_id, reason)
		_log("login recusado (peer %d, \"%s\"): %s" % [peer_id, player_name, reason])
		get_tree().create_timer(1.0).timeout.connect(func():
			if multiplayer.multiplayer_peer != null and not peers.has(peer_id):
				multiplayer.multiplayer_peer.disconnect_peer(peer_id))
		return

	var result := sim.login_player(player_name, species_id)
	var dino: Dino = result["dino"]
	var restored: bool = result["restored"]
	peers[peer_id] = {"name": player_name, "dino_id": dino.id}
	if _paused_logged:
		_log("[mundo] retomado em world_time=%.3f" % sim.world_time)
		_paused_logged = false
	_log("[login] %s entrou como %s (%s, crescimento %.0f%%) world_time=%.3f" % [
		player_name, Species.display_name(dino.species),
		"dino salvo" if restored else "novo", dino.growth * 100.0, sim.world_time])

	Net.s_welcome.rpc_id(peer_id, _welcome_info(dino, restored))
	Net.s_teleport.rpc_id(peer_id, dino.client_seq, dino.pos, dino.yaw)
	_broadcast_message("%s entrou no servidor" % player_name)
	_roster_dirty = true


func _welcome_info(dino: Dino, restored: bool) -> Dictionary:
	return {
		"entity_id": dino.id,
		"species": dino.species,
		"restored": restored,
		"seed": sim.terrain.seed_value,
		"world_time": sim.world_time,
		"version": GameConfig.VERSION,
		"dev": dev_mode,
	}


func _name_online(player_name: String) -> bool:
	for info in peers.values():
		if String(info["name"]).to_lower() == player_name.to_lower():
			return true
	return false


func _dino_for_peer(peer_id: int) -> Dino:
	if not peers.has(peer_id):
		return null
	return sim.get_dino(int(peers[peer_id]["dino_id"]))


func _peer_for_dino(dino_id: int) -> int:
	for pid in peers:
		if int(peers[pid]["dino_id"]) == dino_id:
			return pid
	return 0


# ---------------------------------------------------------------- entrada dos jogadores

## O cliente calcula o próprio movimento (jogo entre amigos: sem anticheat) e manda
## a posição. O servidor só confere a sequência de teleporte e mantém no mapa.
func on_state(peer_id: int, seq: int, pos: Vector3, yaw: float, flags: int) -> void:
	var d := _dino_for_peer(peer_id)
	if d == null or seq != d.client_seq:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var elapsed := clampf(now - d.last_client_time, 0.01, 1.0)
	d.last_client_time = now
	var p := Terrain.clamp_to_play_area(pos)
	p.y = Movement.ground_y(sim.terrain, p.x, p.z, d.body_height())
	var moved := Movement.flat_distance(p, d.pos)
	d.moving_speed = moved / elapsed if (flags & Net.CF_MOVING) else 0.0
	d.sprinting = (flags & Net.CF_SPRINT) != 0 and d.stamina > 0.0
	if d.moving_speed > Metabolism.MOVING_EPS:
		d.resting = false
	d.pos = p
	d.yaw = wrapf(yaw, -PI, PI)


func on_action(peer_id: int, action: int, arg: String) -> void:
	if not peers.has(peer_id):
		return
	var d := _dino_for_peer(peer_id)
	match action:
		Net.Action.ATTACK:
			if d != null:
				sim.start_attack(d)
				_flush_events()
		Net.Action.INTERACT_START:
			if d != null:
				d.interacting = true
				d.resting = false
		Net.Action.INTERACT_STOP:
			if d != null:
				d.interacting = false
		Net.Action.REST_TOGGLE:
			if d != null:
				d.resting = not d.resting
				d.interacting = false
		Net.Action.RESPAWN:
			if d == null:
				_respawn(peer_id, arg)
		Net.Action.DEV:
			_dev_command(peer_id, d, arg)


func _respawn(peer_id: int, species_id: String) -> void:
	var player_name: String = peers[peer_id]["name"]
	var d := sim.respawn_player(player_name, species_id)
	peers[peer_id]["dino_id"] = d.id
	_log("[login] %s renasceu como %s jovem" % [player_name, Species.display_name(d.species)])
	Net.s_welcome.rpc_id(peer_id, _welcome_info(d, false))
	Net.s_teleport.rpc_id(peer_id, d.client_seq, d.pos, d.yaw)
	_roster_dirty = true
	save()


## Comandos de teste (só com o servidor em --dev). Ex.: /grow 1, /tp 200 300, /hp 10
func _dev_command(peer_id: int, d: Dino, text: String) -> void:
	if not dev_mode:
		Net.s_message.rpc_id(peer_id, "Comandos de dev desligados (inicie o servidor com --dev).")
		return
	var parts := text.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var reply := ""
	if d == null and cmd != "/bots":
		reply = "Você não está com um dino vivo."
	else:
		match cmd:
			"/grow":
				var g := float(parts[1]) if parts.size() > 1 else 1.0
				var ratio := d.health_ratio()
				d.growth = clampf(g, 0.0, 1.0)
				d.health = ratio * d.max_health()
				reply = "Crescimento = %.0f%%" % (d.growth * 100.0)
			"/tp":
				if parts.size() >= 3:
					var p := Terrain.clamp_to_play_area(Vector3(float(parts[1]), 0.0, float(parts[2])))
					p.y = Movement.ground_y(sim.terrain, p.x, p.z, d.body_height())
					if parts.size() >= 4:
						d.yaw = float(parts[3])
					d.pos = p
					d.client_seq += 1
					Net.s_teleport.rpc_id(peer_id, d.client_seq, d.pos, d.yaw)
					reply = "Teleportado"
			"/hp":
				var v := float(parts[1]) if parts.size() > 1 else 100.0
				d.health = d.max_health() * clampf(v, 0.0, 100.0) / 100.0
				reply = "Vida = %.0f%%" % v
			"/food":
				d.hunger = clampf(float(parts[1]) if parts.size() > 1 else 100.0, 0.0, 100.0)
				d.thirst = clampf(float(parts[2]) if parts.size() > 2 else d.hunger, 0.0, 100.0)
				reply = "Fome %.0f / sede %.0f" % [d.hunger, d.thirst]
			"/kill":
				d.health = 0.0
				d.last_attacker_id = 0
				reply = "Morte forçada"
			"/bots":
				reply = "Bots: %d (alvo %d)" % [sim.bot_count(), sim.bot_target]
			_:
				reply = "Comandos: /grow 0-1, /tp x z [yaw], /hp 0-100, /food fome sede, /kill, /bots"
	if reply != "":
		Net.s_message.rpc_id(peer_id, reply)


# ---------------------------------------------------------------- saída pros clientes

func _flush_events() -> void:
	for ev in sim.events:
		var kind: int = ev["type"]
		match kind:
			WorldSim.Ev.ATTACK:
				_broadcast_event(kind, ev["a"], 0, 0.0, "")
			WorldSim.Ev.HIT:
				_broadcast_event(kind, ev["a"], ev["b"], ev["value"], ev["part"])
			WorldSim.Ev.DEATH:
				_broadcast_event(kind, ev["a"], ev["carcass"], 0.0, "")
				var pname: String = ev["player"]
				if pname != "":
					var pid := _peer_for_dino(ev["a"])
					if pid != 0:
						peers[pid]["dino_id"] = 0
						Net.s_died.rpc_id(pid, ev["cause"])
					_log("[morte] %s morreu (%s)" % [pname, ev["cause"]])
					_broadcast_message("%s morreu (%s)" % [pname, ev["cause"]])
					_roster_dirty = true
					save()
	sim.events.clear()


func _broadcast_event(kind: int, a: int, b: int, value: float, text: String) -> void:
	for pid in peers:
		Net.s_event.rpc_id(pid, kind, a, b, value, text)


func _broadcast_message(text: String) -> void:
	for pid in peers:
		Net.s_message.rpc_id(pid, text)


func build_snapshot() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize((sim.dinos.size() + sim.carcasses.size()) * Net.SNAP_STRIDE)
	var i := 0
	for d in sim.dinos.values():
		var flags := 0
		if d.sprinting and d.moving_speed > Metabolism.MOVING_EPS:
			flags |= Net.SF_SPRINT
		if d.moving_speed > Metabolism.MOVING_EPS:
			flags |= Net.SF_MOVING
		if d.resting:
			flags |= Net.SF_REST
		if d.interact_result != 0:
			flags |= Net.SF_EAT
		if not d.is_bot:
			flags |= Net.SF_PLAYER
		if d.health_ratio() < Movement.LIMP_HEALTH:
			flags |= Net.SF_LIMP
		if Movement.is_swimming(sim.terrain, d.pos.x, d.pos.z, d.body_height()):
			flags |= Net.SF_SWIM
		_put(data, i, d.id, Species.index_of(d.species), d.growth, d.pos, d.yaw, flags)
		i += Net.SNAP_STRIDE
	for c in sim.carcasses.values():
		_put(data, i, c["id"], Species.index_of(c["species"]), c["growth"], c["pos"], c["yaw"], Net.SF_DEAD)
		i += Net.SNAP_STRIDE
	return data


static func _put(data: PackedFloat32Array, i: int, id: int, sp: int, growth: float,
		pos: Vector3, yaw: float, flags: int) -> void:
	data[i] = id
	data[i + 1] = sp
	data[i + 2] = growth
	data[i + 3] = pos.x
	data[i + 4] = pos.y
	data[i + 5] = pos.z
	data[i + 6] = yaw
	data[i + 7] = flags


func _send_snapshots() -> void:
	var data := build_snapshot()
	for pid in peers:
		Net.s_snapshot.rpc_id(pid, data)


func _send_self_stats() -> void:
	for pid in peers:
		var d := _dino_for_peer(pid)
		if d == null:
			continue
		var st := PackedFloat32Array()
		st.resize(Net.ST_COUNT)
		var speeds := Movement.speeds(d)
		st[Net.ST_HEALTH] = d.health
		st[Net.ST_MAX_HEALTH] = d.max_health()
		st[Net.ST_HUNGER] = d.hunger
		st[Net.ST_THIRST] = d.thirst
		st[Net.ST_STAMINA] = d.stamina
		st[Net.ST_GROWTH] = d.growth
		st[Net.ST_WALK] = speeds.x
		st[Net.ST_SPRINT] = speeds.y
		st[Net.ST_INTERACT] = d.interact_result
		st[Net.ST_RESTING] = 1.0 if d.resting else 0.0
		st[Net.ST_WORLD_TIME] = sim.world_time
		Net.s_self_stats.rpc_id(pid, st)


func _send_roster() -> void:
	var roster := {}
	for pid in peers:
		var did: int = peers[pid]["dino_id"]
		roster[str(did)] = peers[pid]["name"]
	for pid in peers:
		Net.s_roster.rpc_id(pid, roster)


# ---------------------------------------------------------------- save

func save() -> void:
	var data := sim.to_save()
	var dir := save_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_log("ERRO ao salvar em %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))
	if err != OK:
		_log("ERRO ao trocar o save: %s" % error_string(err))


func _load() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var text := FileAccess.get_file_as_string(save_path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("AVISO: save ilegível em %s, começando mundo novo" % save_path)
		return false
	if int(parsed.get("seed", -1)) != sim.terrain.seed_value:
		_log("AVISO: save é de outro mapa (semente diferente), começando mundo novo")
		return false
	sim.load_save(parsed)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if sim != null:
			save()


func _log(text: String) -> void:
	var t := Time.get_datetime_string_from_system()
	print("[%s] %s" % [t, text])
