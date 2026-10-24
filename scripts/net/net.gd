extends Node
## Autoload "Net": TODAS as chamadas de rede (RPCs) do jogo ficam aqui.
## Godot exige que servidor e cliente tenham as mesmas funções @rpc no mesmo caminho
## (/root/Net), então o jogo inteiro passa por este arquivo.
##
## Prefixo c_ = cliente → servidor. Prefixo s_ = servidor → cliente.
## Do lado do servidor, as chamadas c_ são repassadas para `server` (GameServer).
## Do lado do cliente, as chamadas s_ viram sinais que o jogo escuta.

enum Action { ATTACK = 1, INTERACT_START = 2, INTERACT_STOP = 3, REST_TOGGLE = 4, RESPAWN = 5, DEV = 6, CHAT = 7 }

## Bits de c_state.flags
const CF_SPRINT := 1
const CF_MOVING := 2

## Bits de flags no snapshot
const SF_DEAD := 1
const SF_SPRINT := 2
const SF_REST := 4
const SF_EAT := 8
const SF_PLAYER := 16
const SF_LIMP := 32
const SF_SWIM := 64
const SF_MOVING := 128

## Floats por entidade no snapshot: id, espécie, crescimento, x, y, z, yaw, flags
const SNAP_STRIDE := 8

## Índices de s_self_stats
const ST_HEALTH := 0
const ST_MAX_HEALTH := 1
const ST_HUNGER := 2
const ST_THIRST := 3
const ST_STAMINA := 4
const ST_GROWTH := 5
const ST_WALK := 6
const ST_SPRINT := 7
const ST_INTERACT := 8
const ST_RESTING := 9
const ST_WORLD_TIME := 10
const ST_COUNT := 11

signal welcome_received(info: Dictionary)
signal login_failed(reason: String)
signal snapshot_received(data: PackedFloat32Array)
signal self_stats_received(stats: PackedFloat32Array)
signal roster_received(roster: Dictionary)
signal teleport_received(seq: int, pos: Vector3, yaw: float)
signal event_received(kind: int, a: int, b: int, value: float, text: String)
signal died(cause: String)
signal message_received(text: String)
signal password_changed(ok: bool, text: String)

## GameServer quando este processo é o servidor; null no cliente.
var server: Node = null


func is_server_process() -> bool:
	return server != null


# ============================================================ cliente → servidor

@rpc("any_peer", "call_remote", "reliable")
func c_login(player_name: String, species_id: String, version: String) -> void:
	if server:
		server.on_login(multiplayer.get_remote_sender_id(), player_name, species_id, version)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(seq: int, pos: Vector3, yaw: float, flags: int) -> void:
	if server:
		server.on_state(multiplayer.get_remote_sender_id(), seq, pos, yaw, flags)


@rpc("any_peer", "call_remote", "reliable")
func c_action(action: int, arg: String) -> void:
	if server:
		server.on_action(multiplayer.get_remote_sender_id(), action, arg)


## Chave da senha (Accounts.client_key), mandada logo antes do c_login. Fica separada do
## c_login pra ele não mudar: um jogo de outra versão ainda recebe "versão diferente".
@rpc("any_peer", "call_remote", "reliable")
func c_password(key: String) -> void:
	if server:
		server.on_password(multiplayer.get_remote_sender_id(), key)


## Troca de senha (aba Conta). A resposta vem por s_password_changed.
@rpc("any_peer", "call_remote", "reliable")
func c_set_password(old_key: String, new_key: String) -> void:
	if server:
		server.on_change_password(multiplayer.get_remote_sender_id(), old_key, new_key)


# ============================================================ servidor → cliente

@rpc("authority", "call_remote", "reliable")
func s_welcome(info: Dictionary) -> void:
	welcome_received.emit(info)


@rpc("authority", "call_remote", "reliable")
func s_login_failed(reason: String) -> void:
	login_failed.emit(reason)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_snapshot(data: PackedFloat32Array) -> void:
	snapshot_received.emit(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_self_stats(stats: PackedFloat32Array) -> void:
	self_stats_received.emit(stats)


@rpc("authority", "call_remote", "reliable")
func s_roster(roster: Dictionary) -> void:
	roster_received.emit(roster)


@rpc("authority", "call_remote", "reliable")
func s_teleport(seq: int, pos: Vector3, yaw: float) -> void:
	teleport_received.emit(seq, pos, yaw)


@rpc("authority", "call_remote", "reliable")
func s_event(kind: int, a: int, b: int, value: float, text: String) -> void:
	event_received.emit(kind, a, b, value, text)


@rpc("authority", "call_remote", "reliable")
func s_died(cause: String) -> void:
	died.emit(cause)


@rpc("authority", "call_remote", "reliable")
func s_message(text: String) -> void:
	message_received.emit(text)


## Resposta do c_set_password.
@rpc("authority", "call_remote", "reliable")
func s_password_changed(ok: bool, text: String) -> void:
	password_changed.emit(ok, text)


# ============================================================ conexão (cliente)

func connect_to(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
