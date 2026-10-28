class_name RedeemCodes
extends RefCounted
## Códigos de resgate: o admin cria no jogo, o jogador resgata na aba Conta. Fica no servidor,
## em <save>.codigos.json (ao lado do save e do contas.json). Sem rede: o GameServer chama.
## O que cada código dá está em Rewards; o que a conta já ganhou, em Accounts.perks.

enum Result { OK, NOT_FOUND, REVOKED, EXPIRED, USED_UP, ALREADY, LOCKED }

const FORMAT := 1
## Sem 0/O e 1/I, pra ninguém confundir lendo o código em voz alta.
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const PREFIX := "DINO"
## Usos e validade (dias, 0 = sem validade) que o admin pode escolher.
const MAX_USES := 100
const MAX_DAYS := 365
## Tentativas erradas de resgate por conta dentro da janela; passou disso, espera a janela.
const MAX_FAILS := 5
const FAIL_WINDOW_S := 60.0

## código -> {"code", "reward", "param", "max_uses", "uses_left", "expires" (unix, 0 = nunca),
##            "created_by", "created" (unix), "revoked", "redeemed_by" [nomes]}
var codes := {}
## conta (minúsculas) -> [unix de cada tentativa errada]
var _fails := {}


## Código novo, aleatório: DINO-XXXX-XXXX (32^8 combinações).
static func generate() -> String:
	var bytes := Crypto.new().generate_random_bytes(8)
	var chars := ""
	for b in bytes:
		chars += ALPHABET[b % ALPHABET.length()]
	return "%s-%s-%s" % [PREFIX, chars.substr(0, 4), chars.substr(4, 4)]


## Do jeito que a pessoa digitou pro formato guardado: maiúsculas, sem espaços, com os traços
## no lugar ("dino abcd 2345" e "DINOABCD2345" viram "DINO-ABCD-2345").
static func normalize(text: String) -> String:
	var raw := ""
	for ch in text.to_upper():
		if ALPHABET.contains(ch) or "DINO".contains(ch):
			raw += ch
	if raw.begins_with(PREFIX):
		raw = raw.substr(PREFIX.length())
	if raw.length() != 8:
		return text.strip_edges().to_upper()
	return "%s-%s-%s" % [PREFIX, raw.substr(0, 4), raw.substr(4, 4)]


## Cria um código. Confira a recompensa com Rewards.validate antes.
func create(reward: String, param: String, uses: int, days: int, created_by: String, now: float) -> String:
	var code := generate()
	while codes.has(code):
		code = generate()
	uses = clampi(uses, 1, MAX_USES)
	days = clampi(days, 0, MAX_DAYS)
	codes[code] = {
		"code": code, "reward": reward, "param": param,
		"max_uses": uses, "uses_left": uses,
		"expires": 0.0 if days == 0 else now + days * 86400.0,
		"created_by": created_by, "created": now,
		"revoked": false, "redeemed_by": [],
	}
	return code


## Confere se a conta pode resgatar o código (sem gastar). Erro conta como tentativa errada.
## Devolve {"result": Result, "entry": Dictionary}.
func check(text: String, player_name: String, now: float) -> Dictionary:
	var n := player_name.strip_edges().to_lower()
	if fails_left(n, now) <= 0:
		return {"result": Result.LOCKED, "entry": {}}
	var entry: Dictionary = codes.get(normalize(text), {})
	var result := Result.OK
	if entry.is_empty():
		result = Result.NOT_FOUND
	elif bool(entry["revoked"]):
		result = Result.REVOKED
	elif float(entry["expires"]) > 0.0 and now > float(entry["expires"]):
		result = Result.EXPIRED
	elif Array(entry["redeemed_by"]).has(n):
		result = Result.ALREADY
	elif int(entry["uses_left"]) <= 0:
		result = Result.USED_UP
	if result != Result.OK:
		_count_fail(n, now)
	return {"result": result, "entry": entry}


## Gasta um uso do código pra essa conta (depois de entregar a recompensa).
func consume(code: String, player_name: String) -> void:
	var entry: Dictionary = codes.get(code, {})
	if entry.is_empty():
		return
	entry["uses_left"] = maxi(0, int(entry["uses_left"]) - 1)
	var who: Array = entry["redeemed_by"]
	who.append(player_name.strip_edges().to_lower())


func revoke(text: String) -> bool:
	var entry: Dictionary = codes.get(normalize(text), {})
	if entry.is_empty() or bool(entry["revoked"]):
		return false
	entry["revoked"] = true
	return true


## Lista pro painel de admin, do mais novo pro mais velho.
func list_for_admin() -> Array:
	var out := codes.values()
	out.sort_custom(func(a, b): return float(a["created"]) > float(b["created"]))
	return out.map(func(e): return (e as Dictionary).duplicate(true))


## Tentativas erradas que ainda sobram na janela.
func fails_left(player_name: String, now: float) -> int:
	var n := player_name.strip_edges().to_lower()
	var recent: Array = Array(_fails.get(n, [])).filter(func(t): return now - float(t) < FAIL_WINDOW_S)
	_fails[n] = recent
	return MAX_FAILS - recent.size()


## Segundos até poder tentar de novo (0 = livre).
func wait_seconds(player_name: String, now: float) -> float:
	if fails_left(player_name, now) > 0:
		return 0.0
	var recent: Array = _fails[player_name.strip_edges().to_lower()]
	return maxf(0.0, float(recent.min()) + FAIL_WINDOW_S - now)


static func message(result: Result) -> String:
	match result:
		Result.NOT_FOUND:
			return "Esse código não existe. Confira as letras."
		Result.REVOKED:
			return "Esse código foi cancelado."
		Result.EXPIRED:
			return "Esse código venceu."
		Result.USED_UP:
			return "Esse código já foi usado o máximo de vezes."
		Result.ALREADY:
			return "Você já usou esse código."
		Result.LOCKED:
			return "Muitos códigos errados. Espere um pouco e tente de novo."
	return ""


func to_dict() -> Dictionary:
	return {"format": FORMAT, "codes": codes.duplicate(true)}


func load_dict(data: Dictionary) -> void:
	codes.clear()
	_fails.clear()
	var list: Dictionary = data.get("codes", {})
	for code in list:
		var e: Dictionary = list[code]
		if not e.has("reward"):
			continue
		var entry := {
			"code": String(code), "reward": String(e["reward"]), "param": String(e.get("param", "")),
			"max_uses": int(e.get("max_uses", 1)), "uses_left": int(e.get("uses_left", 0)),
			"expires": float(e.get("expires", 0.0)), "created_by": String(e.get("created_by", "")),
			"created": float(e.get("created", 0.0)), "revoked": bool(e.get("revoked", false)),
			"redeemed_by": Array(e.get("redeemed_by", [])),
		}
		codes[String(code)] = entry


func _count_fail(n: String, now: float) -> void:
	var recent: Array = _fails.get(n, [])
	recent.append(now)
	_fails[n] = recent
