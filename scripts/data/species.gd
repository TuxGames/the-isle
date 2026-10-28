class_name Species
extends RefCounted
## Tabela de espécies e valores de equilíbrio.
## TODOS OS NÚMEROS SÃO PROVISÓRIOS — ajustar jogando com o Marcelo.
##
## Convenções:
## - Medidas em metros, no tamanho ADULTO. O tamanho real é escalado pelo crescimento.
## - Eixo +Z local = frente do dinossauro. Y = altura a partir do chão (pés).
## - "body": esferas que formam o corpo E a hitbox. [centro, raio, parte]
## - "attack_point": de onde sai o golpe (boca/chifre/pata). O golpe é um segmento
##   vertical que desce de attack_point até attack_point.y * (1 - attack_reach_down),
##   pra um bicho grande conseguir morder um pequeno no chão.
## - Opcionais, pra códigos de resgate (Rewards): "locked": true = só escolhe quem liberou
##   a espécie com um código; "beta": true = só escolhe conta com acesso beta. Hoje nenhuma é.

enum Diet { CARNIVORE, HERBIVORE }

const IDS := ["carnotaurus", "triceratops", "dryosaurus"]

const DATA := {
	"carnotaurus": {
		"name": "Carnotaurus",
		"diet": Diet.CARNIVORE,
		"mass_kg": 1500.0,
		"max_health": 1200.0,
		"damage": 140.0,
		"grow_minutes": 120.0,
		# Minutos pra esvaziar o estômago ANDANDO, adulto. Filhote esvazia mais rápido.
		"hunger_minutes": 40.0,
		"thirst_minutes": 32.0,
		# Quanto cabe no estômago, em fração da massa.
		"stomach_fraction": 0.06,
		"walk_speed": 4.5,
		"sprint_speed": 11.0,
		"turn_deg": 140.0,
		"stamina_sprint_s": 20.0,
		"stamina_regen_s": 25.0,
		"juvenile_scale": 0.25,
		"hip_height": 2.0,
		"perception_m": 60.0,
		# IA: foge quando a vida cai abaixo dessa fração.
		"flee_health": 0.30,
		# IA: quanto maior, mais encara inimigos mais fortes.
		"courage": 1.2,
		"defensive": false,
		"attack_windup": 0.25,
		"attack_cooldown": 1.0,
		"attack_stamina": 8.0,
		"attack_name": "mordida",
		"attack_point": Vector3(0.0, 2.65, 3.6),
		"attack_radius": 0.6,
		"attack_reach_down": 0.8,
		"body": [
			[Vector3(0.0, 2.2, 0.0), 1.15, "tronco"],
			[Vector3(0.0, 2.35, 1.2), 0.95, "peito"],
			[Vector3(0.0, 2.6, 2.3), 0.55, "pescoço"],
			[Vector3(0.0, 2.7, 3.1), 0.55, "cabeça"],
			[Vector3(0.0, 2.15, -1.7), 0.65, "cauda"],
			[Vector3(0.0, 2.0, -3.1), 0.42, "cauda"],
			[Vector3(0.0, 1.9, -4.2), 0.25, "cauda"],
			[Vector3(0.0, 1.0, 0.1), 0.7, "pernas"],
		],
		"color": Color(0.55, 0.22, 0.16),
		"color2": Color(0.83, 0.68, 0.52),
	},
	"triceratops": {
		"name": "Triceratops",
		"diet": Diet.HERBIVORE,
		"mass_kg": 6000.0,
		"max_health": 2200.0,
		"damage": 160.0,
		"grow_minutes": 180.0,
		"hunger_minutes": 57.0,
		"thirst_minutes": 45.0,
		"stomach_fraction": 0.04,
		"walk_speed": 3.5,
		"sprint_speed": 7.5,
		"turn_deg": 80.0,
		"stamina_sprint_s": 15.0,
		"stamina_regen_s": 30.0,
		"juvenile_scale": 0.25,
		"hip_height": 1.6,
		"perception_m": 45.0,
		"flee_health": 0.20,
		"courage": 1.6,
		# Herbívoro que enfrenta o predador em vez de só fugir.
		"defensive": true,
		"attack_windup": 0.35,
		"attack_cooldown": 1.4,
		"attack_stamina": 10.0,
		"attack_name": "chifrada",
		"attack_point": Vector3(0.0, 1.5, 4.0),
		"attack_radius": 0.7,
		"attack_reach_down": 0.6,
		"body": [
			[Vector3(0.0, 1.9, 0.0), 1.5, "tronco"],
			[Vector3(0.0, 2.0, -1.2), 1.3, "tronco"],
			[Vector3(0.0, 1.75, 1.4), 1.25, "peito"],
			[Vector3(0.0, 1.6, 2.9), 1.0, "cabeça"],
			[Vector3(0.0, 1.6, -2.7), 0.7, "cauda"],
			[Vector3(0.0, 1.3, -3.9), 0.4, "cauda"],
			[Vector3(0.0, 0.7, 0.0), 0.9, "pernas"],
		],
		"color": Color(0.36, 0.42, 0.28),
		"color2": Color(0.78, 0.72, 0.55),
	},
	"dryosaurus": {
		"name": "Dryosaurus",
		"diet": Diet.HERBIVORE,
		"mass_kg": 90.0,
		"max_health": 250.0,
		"damage": 15.0,
		"grow_minutes": 60.0,
		"hunger_minutes": 20.0,
		"thirst_minutes": 16.0,
		"stomach_fraction": 0.08,
		"walk_speed": 4.0,
		"sprint_speed": 12.0,
		"turn_deg": 220.0,
		"stamina_sprint_s": 25.0,
		"stamina_regen_s": 20.0,
		"juvenile_scale": 0.3,
		"hip_height": 1.0,
		"perception_m": 70.0,
		# 1.0 = foge sempre que vê um predador perigoso.
		"flee_health": 1.0,
		"courage": 0.3,
		"defensive": false,
		"attack_windup": 0.2,
		"attack_cooldown": 0.8,
		"attack_stamina": 6.0,
		"attack_name": "coice",
		"attack_point": Vector3(0.0, 0.6, 0.6),
		"attack_radius": 0.35,
		"attack_reach_down": 0.5,
		"body": [
			[Vector3(0.0, 1.05, 0.0), 0.38, "tronco"],
			[Vector3(0.0, 1.35, 0.55), 0.2, "pescoço"],
			[Vector3(0.0, 1.55, 0.85), 0.17, "cabeça"],
			[Vector3(0.0, 1.0, -0.65), 0.24, "cauda"],
			[Vector3(0.0, 0.95, -1.25), 0.14, "cauda"],
			[Vector3(0.0, 0.5, 0.0), 0.3, "pernas"],
		],
		"color": Color(0.62, 0.55, 0.3),
		"color2": Color(0.9, 0.85, 0.7),
	},
}

## Multiplicador de dano por parte do corpo atingida.
const PART_DAMAGE := {
	"cabeça": 1.25,
	"pescoço": 1.2,
	"peito": 1.05,
	"tronco": 1.0,
	"pernas": 0.9,
	"cauda": 0.6,
}


static func get_data(id: String) -> Dictionary:
	return DATA[id]


static func is_valid(id: String) -> bool:
	return DATA.has(id)


static func index_of(id: String) -> int:
	return IDS.find(id)


static func id_at(index: int) -> String:
	if index < 0 or index >= IDS.size():
		return IDS[0]
	return IDS[index]


static func is_locked(id: String) -> bool:
	return bool(DATA.get(id, {}).get("locked", false))


static func is_beta(id: String) -> bool:
	return bool(DATA.get(id, {}).get("beta", false))


## Se a conta pode escolher a espécie ("" = pode; senão o motivo, pro jogador ler).
## `perks` = o que a conta ganhou com códigos ({"beta": bool, "species": [ids]}).
static func choice_error(id: String, perks: Dictionary) -> String:
	return choice_error_for(DATA.get(id, {}), id, perks)


## Igual a choice_error, com os dados da espécie passados (dá pra testar com espécie de mentira).
static func choice_error_for(spec: Dictionary, id: String, perks: Dictionary) -> String:
	var shown := String(spec.get("name", id))
	if bool(spec.get("beta", false)) and not bool(perks.get("beta", false)):
		return "%s ainda está em teste: só quem tem acesso beta pode escolher." % shown
	if bool(spec.get("locked", false)) and not Array(perks.get("species", [])).has(id):
		return "%s ainda está trancado: precisa de um código pra liberar." % shown
	return ""


static func is_carnivore(id: String) -> bool:
	return int(DATA[id]["diet"]) == Diet.CARNIVORE


static func display_name(id: String) -> String:
	return String(DATA[id]["name"])


## Escala linear do corpo pelo crescimento (filhote → adulto).
static func scale_for(id: String, growth: float) -> float:
	var juv: float = DATA[id]["juvenile_scale"]
	return lerpf(juv, 1.0, clampf(growth, 0.0, 1.0))


## Fator usado em vida e dano: cresce com a "área" do bicho.
static func size_factor(id: String, growth: float) -> float:
	var s := scale_for(id, growth)
	return s * s


static func mass_for(id: String, growth: float) -> float:
	var s := scale_for(id, growth)
	var m: float = DATA[id]["mass_kg"]
	return m * s * s * s


static func max_health_for(id: String, growth: float) -> float:
	var hp: float = DATA[id]["max_health"]
	return hp * size_factor(id, growth)


## Raio aproximado da "pegada" do bicho no chão, usado pra separar corpos.
static func footprint_radius(id: String, growth: float) -> float:
	var body: Array = DATA[id]["body"]
	var r: float = body[0][1]
	return r * scale_for(id, growth) * 1.1


## Comprimento aproximado do focinho à ponta da cauda (adulto), em metros.
static func length_m(id: String) -> float:
	var body: Array = DATA[id]["body"]
	var front := -INF
	var back := INF
	for part in body:
		var c: Vector3 = part[0]
		var r: float = part[1]
		front = maxf(front, c.z + r)
		back = minf(back, c.z - r)
	return front - back
