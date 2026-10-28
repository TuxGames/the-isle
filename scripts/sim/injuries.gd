class_name Injuries
extends RefCounted
## Ferimentos (design, seção 6): sangramento, fratura e mordida funda. Ficam em dino.injuries
## (tipo -> segundos que faltam pra sarar) e só correm dentro do Metabolism, ou seja, com o
## dino ativo no mundo: quem sai fica congelado com eles, como todo o resto.
## Números em config.gd (seção "Ferimentos"); cada espécie sara no ritmo de "injury_heal".

const BLEED := "sangramento"
const FRACTURE := "fratura"
const DEEP := "mordida_funda"
const TYPES := [BLEED, FRACTURE, DEEP]
## Nome que o jogador vê no HUD.
const NAMES := {BLEED: "Sangrando", FRACTURE: "Osso quebrado", DEEP: "Mordida funda"}
## Partes do corpo em que um golpe menor já abre uma mordida funda.
const VITAL_PARTS := ["cabeça", "pescoço"]


static func remaining(d: Dino, type: String) -> float:
	return float(d.injuries.get(type, 0.0))


static func has(d: Dino, type: String) -> bool:
	return remaining(d, type) > 0.0


## Põe o tempo que falta de um ferimento (seconds <= 0 cura na hora). Usado pelo /hurt.
static func set_remaining(d: Dino, type: String, seconds: float) -> void:
	if not TYPES.has(type):
		return
	if seconds <= 0.0:
		d.injuries.erase(type)
	else:
		d.injuries[type] = seconds


## Abre (ou renova) um ferimento. Golpe novo não encurta o que já estava mais longo.
static func inflict(d: Dino, type: String, seconds: float) -> void:
	set_remaining(d, type, maxf(remaining(d, type), seconds))


## Ferimentos causados por um golpe que já tirou `damage` de vida. Devolve os tipos abertos.
static func from_hit(target: Dino, attacker: Dino, damage: float, part: String) -> Array:
	var out := []
	var frac := damage / maxf(target.max_health(), 0.001)
	if frac > GameConfig.BLEED_MIN_DAMAGE:
		inflict(target, BLEED, GameConfig.BLEED_S)
		out.append(BLEED)
	if attacker != null and attacker.mass() >= target.mass() * GameConfig.FRACTURE_MASS_RATIO:
		inflict(target, FRACTURE, GameConfig.FRACTURE_S)
		out.append(FRACTURE)
	if frac > GameConfig.DEEP_MIN_DAMAGE or (VITAL_PARTS.has(part) and frac > GameConfig.DEEP_HEAD_DAMAGE):
		inflict(target, DEEP, GameConfig.DEEP_S)
		out.append(DEEP)
	return out


## Quanto da cura normal de vida o dino recebe: nada sangrando, metade com mordida funda.
static func heal_mult(d: Dino) -> float:
	if has(d, BLEED):
		return 0.0
	if has(d, DEEP):
		return GameConfig.DEEP_HEAL_MULT
	return 1.0


static func can_sprint(d: Dino) -> bool:
	return not has(d, FRACTURE)


static func speed_mult(d: Dino) -> float:
	return GameConfig.FRACTURE_SPEED_MULT if has(d, FRACTURE) else 1.0


## Um passo de dt segundos: o sangramento tira vida e os tempos andam (mais rápido descansando).
static func step(d: Dino, dt: float) -> void:
	if d.injuries.is_empty():
		return
	if has(d, BLEED):
		d.health -= d.max_health() * GameConfig.BLEED_LOSS_PER_MIN / 60.0 * dt
	var mult := float(d.spec().get("injury_heal", 1.0))
	if d.resting and d.moving_speed <= Metabolism.MOVING_EPS:
		mult *= GameConfig.INJURY_REST_MULT
	for type in d.injuries.keys():
		var left := float(d.injuries[type]) - dt * mult
		if left <= 0.0:
			d.injuries.erase(type)
		else:
			d.injuries[type] = left


## Ferimentos lidos do save: só tipos conhecidos com tempo positivo.
static func sanitize(raw) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for type in TYPES:
		var left := float(raw.get(type, 0.0))
		if left > 0.0:
			out[type] = left
	return out


## Texto do HUD: "Sangrando 2:10 · Osso quebrado 8:40" (vazio sem ferimentos).
static func describe(left: Dictionary) -> String:
	var parts := PackedStringArray()
	for type in TYPES:
		var s := float(left.get(type, 0.0))
		if s > 0.0:
			var total := ceili(s)
			parts.append("%s %d:%02d" % [NAMES[type], floori(total / 60.0), total % 60])
	return " · ".join(parts)
