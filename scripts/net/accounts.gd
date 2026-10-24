class_name Accounts
extends RefCounted
## Contas dos jogadores: nome + senha. Fica no servidor, num arquivo à parte do save do mundo
## (trocar de mapa não apaga as senhas). Sem rede: o GameServer chama e grava em disco.
##
## A senha nunca viaja nem é guardada como texto. O cliente transforma a senha numa chave
## (client_key: PBKDF2 com o nome como sal) e manda só a chave; o servidor guarda um hash
## dessa chave com um sal aleatório por conta.
##
## O primeiro a entrar com um nome cria a conta com a senha que digitou. Isso vale também
## pra quem já tinha dino salvo de antes das contas existirem.

enum Result { OK, CREATED, WRONG, LOCKED, BAD_KEY }

const FORMAT := 1
## Senha mais curta aceita (o cliente confere antes de mandar).
const MIN_PASSWORD := 4
## Custo da chave no cliente (uma vez por login) e do hash no servidor.
const CLIENT_ITERATIONS := 20000
const SERVER_ITERATIONS := 1000
## Erros seguidos que bloqueiam o nome, e por quanto tempo (segundos).
const MAX_FAILS := 5
const LOCK_S := 60.0

## nome em minúsculas -> {"name": como foi cadastrado, "salt": hex, "hash": hex, "created": unix}
var accounts := {}
## nome em minúsculas -> {"count": erros seguidos, "until": unix até quando está bloqueado}
var _fails := {}


## Chave que o cliente manda no lugar da senha (64 caracteres hex).
static func client_key(player_name: String, password: String) -> String:
	var salt := ("dino-survival:" + player_name.strip_edges().to_lower()).to_utf8_buffer()
	return pbkdf2_sha256(password.to_utf8_buffer(), salt, CLIENT_ITERATIONS).hex_encode()


static func is_valid_key(key: String) -> bool:
	return key.length() == 64 and key.is_valid_hex_number()


## PBKDF2-HMAC-SHA256 com um bloco de saída (32 bytes).
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, block)
	var out := u.duplicate()
	for i in iterations - 1:
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		for j in out.size():
			out[j] ^= u[j]
	return out


func has_account(player_name: String) -> bool:
	return accounts.has(_norm(player_name))


## Nome do jeito que foi cadastrado ("tux" entra como "Tux"), ou o próprio se não tem conta.
func display_name(player_name: String) -> String:
	var acc: Dictionary = accounts.get(_norm(player_name), {})
	return String(acc.get("name", player_name.strip_edges()))


## Segundos até o nome poder tentar de novo (0 = livre).
func lock_seconds_left(player_name: String, now: float) -> float:
	var f: Dictionary = _fails.get(_norm(player_name), {})
	return maxf(0.0, float(f.get("until", 0.0)) - now)


## Confere a chave. Nome sem conta: cria a conta com essa chave e devolve CREATED.
func login(player_name: String, key: String, now: float) -> Result:
	if not is_valid_key(key):
		return Result.BAD_KEY
	var n := _norm(player_name)
	if lock_seconds_left(n, now) > 0.0:
		return Result.LOCKED
	if not accounts.has(n):
		accounts[n] = _new_record(player_name.strip_edges(), key, now)
		return Result.CREATED
	if not _matches(accounts[n], key):
		_count_fail(n, now)
		return Result.WRONG
	_fails.erase(n)
	return Result.OK


## Troca a senha de uma conta que já existe, conferindo a atual.
func change_key(player_name: String, old_key: String, new_key: String, now: float) -> Result:
	if not is_valid_key(new_key):
		return Result.BAD_KEY
	var n := _norm(player_name)
	if not accounts.has(n):
		return Result.WRONG
	if lock_seconds_left(n, now) > 0.0:
		return Result.LOCKED
	if not _matches(accounts[n], old_key):
		_count_fail(n, now)
		return Result.WRONG
	_fails.erase(n)
	var acc: Dictionary = accounts[n]
	accounts[n] = _new_record(String(acc["name"]), new_key, float(acc.get("created", now)))
	return Result.OK


func to_dict() -> Dictionary:
	return {"format": FORMAT, "accounts": accounts.duplicate(true)}


func load_dict(data: Dictionary) -> void:
	accounts.clear()
	_fails.clear()
	var list: Dictionary = data.get("accounts", {})
	for n in list:
		var acc: Dictionary = list[n]
		if acc.has("name") and acc.has("salt") and acc.has("hash"):
			accounts[_norm(String(n))] = acc.duplicate()


static func _norm(player_name: String) -> String:
	return player_name.strip_edges().to_lower()


static func _hash(key: String, salt_hex: String) -> String:
	return pbkdf2_sha256(key.hex_decode(), salt_hex.hex_decode(), SERVER_ITERATIONS).hex_encode()


static func _new_record(player_name: String, key: String, created: float) -> Dictionary:
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	return {"name": player_name, "salt": salt, "hash": _hash(key, salt), "created": created}


static func _matches(acc: Dictionary, key: String) -> bool:
	if not is_valid_key(key):
		return false
	var a := _hash(key, String(acc["salt"]))
	var b := String(acc["hash"])
	# Compara tudo, sem parar no primeiro caractere diferente.
	var diff := int(a.length() != b.length())
	for i in mini(a.length(), b.length()):
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0


func _count_fail(n: String, now: float) -> void:
	var f: Dictionary = _fails.get(n, {"count": 0, "until": 0.0})
	f["count"] = int(f["count"]) + 1
	if int(f["count"]) >= MAX_FAILS:
		f["count"] = 0
		f["until"] = now + LOCK_S
	_fails[n] = f
