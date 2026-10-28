class_name Movement
extends RefCounted
## Regras de movimento compartilhadas entre servidor (bots) e cliente (jogador local).
## Não há física: o dino "anda" sobre a função de altura do terreno.

## Abaixo dessa profundidade (em fração da altura do quadril) o bicho nada.
const SWIM_DEPTH_FRACTION := 0.75
const SWIM_SPEED_MULT := 0.55
const LIMP_HEALTH := 0.25
const LIMP_SPEED_MULT := 0.7


## Altura em que os pés do dino ficam. Na água funda ele "boia".
static func ground_y(terrain: Terrain, x: float, z: float, body_height: float) -> float:
	var h := terrain.height_at(x, z)
	var float_y := Terrain.WATER_LEVEL - body_height * SWIM_DEPTH_FRACTION
	return maxf(h, float_y)


static func is_swimming(terrain: Terrain, x: float, z: float, body_height: float) -> bool:
	return terrain.height_at(x, z) < Terrain.WATER_LEVEL - body_height * SWIM_DEPTH_FRACTION


## Velocidades atuais [andar, correr] em m/s, sem contar a água (o cliente aplica).
static func speeds(d: Dino) -> Vector2:
	var sp := d.spec()
	var walk: float = sp["walk_speed"]
	var sprint: float = sp["sprint_speed"]
	var mult := lerpf(0.85, 1.0, d.growth)
	if d.health_ratio() < LIMP_HEALTH:
		mult *= LIMP_SPEED_MULT
	# Fratura: anda mais devagar e não corre (Injuries).
	mult *= Injuries.speed_mult(d)
	if d.stamina <= 0.0 or not Injuries.can_sprint(d):
		sprint = walk
	return Vector2(walk * mult, sprint * mult)


## Manca (animação e velocidade menor): vida baixa ou osso quebrado.
static func is_limping(d: Dino) -> bool:
	return d.health_ratio() < LIMP_HEALTH or Injuries.has(d, Injuries.FRACTURE)


static func turn_rate_rad(species_id: String) -> float:
	var deg: float = Species.DATA[species_id]["turn_deg"]
	return deg_to_rad(deg)


## Gira um ângulo em direção a outro, no máximo max_step radianos.
static func rotate_toward(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= max_step:
		return to
	return from + signf(diff) * max_step


static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
