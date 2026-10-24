class_name Dino
extends RefCounted
## Estado de um dinossauro vivo (jogador ou bot). Só o servidor altera isso.
## Valores de fome, sede e fôlego vão de 0 a 100 (100 = cheio).

var id: int = 0
var species: String = "carnotaurus"
var is_bot: bool = true
var player_name: String = ""

var growth: float = 1.0
var pos: Vector3 = Vector3.ZERO
var yaw: float = 0.0

var health: float = 1.0
var hunger: float = 100.0
var thirst: float = 100.0
var stamina: float = 100.0
var alive: bool = true

## Estado de ação (vem do cliente pros jogadores, da IA pros bots).
var moving_speed: float = 0.0
var sprinting: bool = false
var resting: bool = false
var interacting: bool = false
## Resultado da interação no último passo: 0 nada, 1 comendo, 2 bebendo.
var interact_result: int = 0

var attack_cooldown: float = 0.0
var last_attacker_id: int = 0
var last_attacked_time: float = -1000.0

## Sequência de teleporte: o servidor ignora posições antigas do cliente
## depois de mover o jogador à força (spawn, comando de dev).
var client_seq: int = 0
var last_client_time: float = 0.0

## Memória da IA (só bots). Ver bot_brain.gd.
var brain := {}

## Simulação por distância (WorldSim.SimTier; não vai pro save, é recalculada todo passo).
var sim_tier: int = 0
## Tempo de mundo acumulado desde a última vez que o dino foi simulado.
var sim_dt: float = 0.0


static func create(p_id: int, p_species: String, p_growth: float, p_pos: Vector3) -> Dino:
	var d := Dino.new()
	d.id = p_id
	d.species = p_species
	d.growth = clampf(p_growth, 0.0, 1.0)
	d.pos = p_pos
	d.health = d.max_health()
	return d


func spec() -> Dictionary:
	return Species.DATA[species]


func is_carnivore() -> bool:
	return Species.is_carnivore(species)


func scale() -> float:
	return Species.scale_for(species, growth)


func size_factor() -> float:
	return Species.size_factor(species, growth)


func mass() -> float:
	return Species.mass_for(species, growth)


func max_health() -> float:
	return Species.max_health_for(species, growth)


func health_ratio() -> float:
	return clampf(health / max_health(), 0.0, 1.0)


## "Força" usada pela IA pra comparar bichos: massa ponderada pela vida.
func power() -> float:
	return mass() * (0.35 + 0.65 * health_ratio())


func forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func body_height() -> float:
	var h: float = spec()["hip_height"]
	return h * scale()


func stomach_kg() -> float:
	var f: float = spec()["stomach_fraction"]
	return mass() * f


func to_dict() -> Dictionary:
	return {
		"id": id,
		"species": species,
		"is_bot": is_bot,
		"player_name": player_name,
		"growth": growth,
		"pos": [pos.x, pos.y, pos.z],
		"yaw": yaw,
		"health": health,
		"hunger": hunger,
		"thirst": thirst,
		"stamina": stamina,
		"resting": resting,
		"brain_state": String(brain.get("state", "")),
	}


static func from_dict(d: Dictionary) -> Dino:
	var dino := Dino.new()
	dino.id = int(d.get("id", 0))
	dino.species = String(d.get("species", "carnotaurus"))
	if not Species.is_valid(dino.species):
		dino.species = "carnotaurus"
	dino.is_bot = bool(d.get("is_bot", true))
	dino.player_name = String(d.get("player_name", ""))
	dino.growth = float(d.get("growth", 1.0))
	var p: Array = d.get("pos", [0.0, 0.0, 0.0])
	dino.pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	dino.yaw = float(d.get("yaw", 0.0))
	dino.health = float(d.get("health", dino.max_health()))
	dino.hunger = float(d.get("hunger", 100.0))
	dino.thirst = float(d.get("thirst", 100.0))
	dino.stamina = float(d.get("stamina", 100.0))
	dino.resting = bool(d.get("resting", false))
	return dino
