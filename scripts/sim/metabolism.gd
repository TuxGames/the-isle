class_name Metabolism
extends RefCounted
## Fome, sede, fôlego, cura e crescimento. Roda só no servidor, só com o mundo ativo.
##
## Decisões do Marcelo que isso implementa (docs/design.md, seção 7):
## - Fome vem do desgaste físico + tempo; correr gasta mais que andar, descansar gasta menos.
## - Crescendo dá mais fome (moderado).
## - Grande come mais quantidade; pequeno esvazia mais rápido (come mais vezes).
## - Fome/sede zerada não mata na hora: para de curar e a vida cai devagar.

const ACTIVITY_REST := 0.5
const ACTIVITY_IDLE := 0.75
const ACTIVITY_WALK := 1.0
const ACTIVITY_SPRINT := 2.0
const GROWING_HUNGER_MULT := 1.25

## Com fome OU sede zerada, a vida cheia acaba em 17 minutos (as duas zeradas: metade).
const STARVE_MINUTES := 17.0
## Bem alimentado, a vida enche em 8 min (descansando: 4 min).
const HEAL_MINUTES := 8.0
const WELL_FED := 25.0
## Só cresce com fome e sede acima disso.
const GROW_MIN_FOOD := 40.0
const MOVING_EPS := 0.3


static func activity(d: Dino) -> float:
	var moving := d.moving_speed > MOVING_EPS
	if d.resting and not moving:
		return ACTIVITY_REST
	if moving and d.sprinting and Injuries.can_sprint(d):
		return ACTIVITY_SPRINT
	if moving:
		return ACTIVITY_WALK
	return ACTIVITY_IDLE


## Filhote esvazia o estômago mais rápido (estômago menor), mas nunca menos que metade do tempo.
static func size_time_factor(d: Dino) -> float:
	return maxf(0.5, sqrt(d.scale()))


static func hunger_per_second(d: Dino) -> float:
	var minutes: float = d.spec()["hunger_minutes"]
	var rate := 100.0 / (minutes * 60.0 * size_time_factor(d))
	rate *= activity(d)
	if d.growth < 1.0:
		rate *= GROWING_HUNGER_MULT
	return rate


static func thirst_per_second(d: Dino) -> float:
	var minutes: float = d.spec()["thirst_minutes"]
	return 100.0 / (minutes * 60.0 * size_time_factor(d)) * activity(d)


static func step(d: Dino, dt: float) -> void:
	# Vida zerada: o mundo mata o bicho neste passo; não pode curar antes disso.
	if not d.alive or d.health <= 0.0:
		return
	var sp := d.spec()

	d.hunger = maxf(0.0, d.hunger - hunger_per_second(d) * dt)
	d.thirst = maxf(0.0, d.thirst - thirst_per_second(d) * dt)

	var starving_count := int(d.hunger <= 0.0) + int(d.thirst <= 0.0)

	# Fôlego
	var sprint_s: float = sp["stamina_sprint_s"]
	var regen_s: float = sp["stamina_regen_s"]
	if d.sprinting and d.moving_speed > MOVING_EPS and Injuries.can_sprint(d):
		d.stamina = maxf(0.0, d.stamina - 100.0 / sprint_s * dt)
	else:
		var regen := 100.0 / regen_s
		if d.resting:
			regen *= 2.0
		if starving_count > 0:
			regen *= 0.5
		d.stamina = minf(100.0, d.stamina + regen * dt)

	# Vida
	var max_hp := d.max_health()
	if starving_count > 0:
		d.health -= max_hp / (STARVE_MINUTES * 60.0) * starving_count * dt
	elif d.hunger > WELL_FED and d.thirst > WELL_FED and d.health < max_hp:
		var heal := max_hp / (HEAL_MINUTES * 60.0) * Injuries.heal_mult(d)
		if d.resting and d.moving_speed <= MOVING_EPS:
			heal *= 2.0
		d.health = minf(max_hp, d.health + heal * dt)
	# Ferimentos: sangramento tira vida; os tempos só andam aqui (dino ativo no mundo).
	Injuries.step(d, dt)

	# Crescimento (mantém a proporção de vida quando a vida máxima aumenta)
	if d.growth < 1.0 and d.hunger > GROW_MIN_FOOD and d.thirst > GROW_MIN_FOOD:
		var ratio := d.health / max_hp
		var grow_min: float = sp["grow_minutes"]
		var mult := 1.0
		if d.growth_boost_s > 0.0:
			# Boost de crescimento (código de resgate): só gasta enquanto cresce.
			mult = GameConfig.GROWTH_BOOST_MULT
			d.growth_boost_s = maxf(0.0, d.growth_boost_s - dt)
		d.growth = minf(1.0, d.growth + dt / (grow_min * 60.0) * mult)
		d.health = ratio * d.max_health()

	if d.attack_cooldown > 0.0:
		d.attack_cooldown = maxf(0.0, d.attack_cooldown - dt)


## Comer: devolve quantos kg entraram. rate_s = segundos pra encher o estômago vazio.
static func eat(d: Dino, available_kg: float, dt: float, rate_s: float = 12.0) -> float:
	var stomach := d.stomach_kg()
	var room := (100.0 - d.hunger) / 100.0 * stomach
	var amount := minf(minf(stomach / rate_s * dt, room), available_kg)
	if amount <= 0.0:
		return 0.0
	d.hunger = minf(100.0, d.hunger + amount / stomach * 100.0)
	return amount


static func drink(d: Dino, dt: float, rate_s: float = 8.0) -> void:
	d.thirst = minf(100.0, d.thirst + 100.0 / rate_s * dt)
