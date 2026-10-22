class_name BotBrain
extends RefCounted
## IA dos bots: uma máquina de estados simples que roda no servidor.
##
## Estados: wander, idle, drink, eat, hunt, fight, flee, rest.
## Decisões do Marcelo implementadas aqui (docs/design.md, seção 4):
## - Ataca ou foge de acordo com o % de vida (pouca vida → foge).
## - Carnívoros também se atacam (carnívoro ataca carnívoro menor).
## - Jogador filhote é percebido mais tarde (WorldSim.perceive).
##
## A memória fica em dino.brain (Dictionary). "think" decide a cada 0,25 s;
## "_act" move o bicho todo passo.

const THINK_INTERVAL := 0.25
const ATTACKED_MEMORY_S := 8.0
const HUNT_TIMEOUT_S := 30.0
const FLEE_TIMEOUT_S := 15.0
const FIGHT_LEASH_M := 35.0
const WANDER_RADIUS := 45.0
const HERD_RADIUS := 40.0

const THIRST_START := 40.0
const HUNGER_START_CARN := 60.0
const HUNGER_START_HERB := 55.0
const SATISFIED := 95.0


static func update(world: WorldSim, b: Dino, dt: float) -> void:
	var br := b.brain
	if not br.has("state"):
		br["state"] = "wander"
		br["think_t"] = world.rng.randf() * THINK_INTERVAL
		br["since"] = world.world_time
	br["think_t"] = float(br["think_t"]) - dt
	if float(br["think_t"]) <= 0.0:
		br["think_t"] = float(br["think_t"]) + THINK_INTERVAL
		think(world, b)
	_act(world, b, dt)


static func _set_state(world: WorldSim, b: Dino, state: String, target_id: int = 0) -> void:
	var br := b.brain
	if br.get("state", "") != state or int(br.get("target_id", 0)) != target_id:
		br["since"] = world.world_time
		br.erase("dest")
	br["state"] = state
	br["target_id"] = target_id
	b.interacting = false
	b.resting = state == "rest"


static func state_of(b: Dino) -> String:
	return String(b.brain.get("state", "wander"))


## Decide o que fazer agora.
static func think(world: WorldSim, b: Dino) -> void:
	var br := b.brain
	var sp := b.spec()
	var state := state_of(b)
	var now := world.world_time
	var hp := b.health_ratio()
	var flee_hp: float = sp["flee_health"]
	var courage: float = sp["courage"]
	var defensive: bool = sp["defensive"]
	var perception: float = sp["perception_m"]
	var my_power := b.power()
	var seen := world.perceive(b, perception)

	# --- 1. Fui atacado? Revida ou foge conforme a vida e o tamanho do inimigo.
	var attacker: Dino = null
	if now - b.last_attacked_time < ATTACKED_MEMORY_S:
		attacker = world.get_dino(b.last_attacker_id)
	if attacker != null and attacker.alive:
		var outmatched := attacker.power() > my_power * courage * 1.5
		var fighter := b.is_carnivore() or defensive
		if hp < flee_hp or outmatched or not fighter:
			_set_state(world, b, "flee", attacker.id)
		else:
			_set_state(world, b, "fight", attacker.id)
		return

	# --- 2. Continua o que já está fazendo, se ainda faz sentido.
	if state == "flee":
		var threat_f: Dino = world.get_dino(int(br.get("target_id", 0)))
		var timed_out := now - float(br.get("since", now)) > FLEE_TIMEOUT_S
		if threat_f != null and threat_f.alive and not timed_out \
				and Movement.flat_distance(b.pos, threat_f.pos) < perception * 1.1:
			return
		_set_state(world, b, "rest")
		return
	if state == "fight" or state == "hunt":
		var target: Dino = world.get_dino(int(br.get("target_id", 0)))
		var ok := target != null and target.alive
		if ok:
			var dist := Movement.flat_distance(b.pos, target.pos)
			if state == "fight":
				ok = dist < FIGHT_LEASH_M and hp >= flee_hp
			else:
				ok = dist < perception * 1.4 and b.stamina > 3.0 \
						and now - float(br.get("since", now)) < HUNT_TIMEOUT_S \
						and b.hunger < SATISFIED
		if ok:
			return
		if state == "hunt":
			br["hunt_cooldown_until"] = now + 20.0
		_set_state(world, b, "wander")

	# --- 3. Ameaças à vista.
	var threat: Dino = null
	var threat_d := INF
	for o in seen:
		if not o.is_carnivore():
			continue
		if b.is_carnivore():
			if o.mass() < b.mass() * 2.0:
				continue
		elif o.mass() < b.mass() * 0.15:
			continue
		var d := Movement.flat_distance(b.pos, o.pos)
		if d < threat_d:
			threat_d = d
			threat = o
	if threat != null:
		if b.is_carnivore():
			if threat_d < 25.0:
				_set_state(world, b, "flee", threat.id)
				return
		elif defensive:
			if hp < flee_hp:
				_set_state(world, b, "flee", threat.id)
				return
			if threat_d < 15.0:
				_set_state(world, b, "fight", threat.id)
				return
		elif threat_d < perception * 0.7:
			_set_state(world, b, "flee", threat.id)
			return

	# --- 4. Necessidades: beber, comer, descansar.
	if state == "drink" and b.thirst < SATISFIED:
		return
	if state == "eat" and b.hunger < SATISFIED and _food_still_there(world, b):
		return
	if state == "rest":
		var rest_long := now - float(br.get("since", now))
		if rest_long < 40.0 and (b.stamina < 80.0 or (hp < 0.7 and rest_long < 30.0)):
			return

	if b.thirst < THIRST_START:
		_set_state(world, b, "drink")
		br["dest"] = world.terrain.nearest_water_point(b.pos)
		return

	var hunger_start := HUNGER_START_CARN if b.is_carnivore() else HUNGER_START_HERB
	if b.hunger < hunger_start:
		if b.is_carnivore():
			var carcass := world.nearest_carcass(b.pos, perception * 1.5)
			if not carcass.is_empty():
				_set_state(world, b, "eat")
				br["food"] = int(carcass["id"])
				br["dest"] = carcass["pos"]
				return
			if now >= float(br.get("hunt_cooldown_until", 0.0)) and b.stamina > 25.0:
				var prey := _choose_prey(b, seen)
				if prey != null:
					_set_state(world, b, "hunt", prey.id)
					return
		else:
			var bush := world.nearest_bush_with_food(b.pos)
			if bush != -1:
				_set_state(world, b, "eat")
				br["food"] = bush
				br["dest"] = world.terrain.bushes[bush]
				return

	if b.stamina < 15.0 or hp < 0.5:
		_set_state(world, b, "rest")
		return

	if state != "wander" and state != "idle":
		_set_state(world, b, "wander")


static func _food_still_there(world: WorldSim, b: Dino) -> bool:
	var food := int(b.brain.get("food", -1))
	if b.is_carnivore():
		return world.carcasses.has(food) and float(world.carcasses[food]["meat"]) > 1.0
	return food >= 0 and food < world.bush_food.size() and world.bush_food[food] > 1.0


## Melhor presa à vista: perto, fraca e que vale a pena. Carnívoro só ataca carnívoro menor.
static func _choose_prey(b: Dino, seen: Array) -> Dino:
	var best: Dino = null
	var best_score := INF
	var my_power := b.power()
	for o in seen:
		if o.is_carnivore():
			if o.species == b.species and b.hunger > 15.0:
				continue
			if o.mass() > b.mass() * 0.8:
				continue
		elif o.mass() > b.mass() * 1.3 and o.health_ratio() > 0.4:
			continue
		var d := Movement.flat_distance(b.pos, o.pos)
		var score := d * (0.3 + o.power() / my_power)
		if score < best_score:
			best_score = score
			best = o
	return best


# ---------------------------------------------------------------- ação

static func _act(world: WorldSim, b: Dino, dt: float) -> void:
	var br := b.brain
	var state := state_of(b)
	var speeds := Movement.speeds(b)
	b.interacting = false
	match state:
		"wander":
			if not br.has("dest"):
				br["dest"] = _wander_destination(world, b)
			if _steer(world, b, br["dest"], speeds.x, dt, 2.0):
				br.erase("dest")
				if world.rng.randf() < 0.45:
					_set_state(world, b, "idle")
					br["idle_until"] = world.world_time + world.rng.randf_range(3.0, 9.0)
		"idle":
			_stop(b)
			if world.world_time >= float(br.get("idle_until", 0.0)):
				_set_state(world, b, "wander")
		"rest":
			_stop(b)
			b.resting = true
		"drink":
			if world.can_drink(b):
				_stop(b)
				b.interacting = true
			else:
				var dest: Vector3 = br.get("dest", world.terrain.nearest_water_point(b.pos))
				if _steer(world, b, dest, speeds.x, dt, 0.5):
					# Chegou no ponto e ainda não alcança a água: anda mais pra dentro do rio.
					var cx := Terrain.river_center_x(b.pos.z)
					br["dest"] = Vector3(lerpf(b.pos.x, cx, 0.5), 0.0, b.pos.z)
		"eat":
			if (b.is_carnivore() and not world.carcass_in_reach(b).is_empty()) \
					or (not b.is_carnivore() and world.bush_in_reach(b) != -1):
				_stop(b)
				b.interacting = true
				var dest_e: Vector3 = br.get("dest", b.pos)
				b.yaw = Movement.rotate_toward(b.yaw, Movement.yaw_to(b.pos, dest_e),
						Movement.turn_rate_rad(b.species) * dt)
			else:
				var dest2: Vector3 = br.get("dest", b.pos)
				_steer(world, b, dest2, speeds.x, dt, 0.0)
		"hunt", "fight":
			var target: Dino = world.get_dino(int(br.get("target_id", 0)))
			if target == null:
				_stop(b)
				return
			var dist := Movement.flat_distance(b.pos, target.pos)
			var speed := speeds.y if dist > 5.0 else speeds.x * 0.6
			if Combat.in_reach(b, target):
				_face(b, target.pos, dt)
				_stop(b)
				world.start_attack(b)
			else:
				_steer(world, b, target.pos, speed, dt, 0.0, speed > speeds.x)
		"flee":
			var threat: Dino = world.get_dino(int(br.get("target_id", 0)))
			if threat == null:
				_stop(b)
				return
			var away := Vector3(b.pos.x - threat.pos.x, 0.0, b.pos.z - threat.pos.z).normalized()
			if away == Vector3.ZERO:
				away = b.forward()
			var dest3 := _clamp_inside(b.pos + away * 30.0)
			# Se encostou na borda do mapa, corre pela lateral.
			if Movement.flat_distance(dest3, b.pos) < 10.0:
				dest3 = _clamp_inside(b.pos + Vector3(-away.z, 0.0, away.x) * 30.0)
			var sprint := b.stamina > 0.0
			_steer(world, b, dest3, speeds.y if sprint else speeds.x, dt, 0.0, sprint)


static func _stop(b: Dino) -> void:
	b.moving_speed = 0.0
	b.sprinting = false


static func _face(b: Dino, target: Vector3, dt: float) -> void:
	b.yaw = Movement.rotate_toward(b.yaw, Movement.yaw_to(b.pos, target),
			Movement.turn_rate_rad(b.species) * dt)


## Anda em direção a dest. Devolve true quando chegou (distância <= stop_dist).
static func _steer(world: WorldSim, b: Dino, dest: Vector3, speed: float, dt: float,
		stop_dist: float, sprint: bool = false) -> bool:
	var dist := Movement.flat_distance(b.pos, dest)
	if dist <= maxf(stop_dist, 0.3):
		_stop(b)
		return true
	var want_yaw := Movement.yaw_to(b.pos, dest)
	b.yaw = Movement.rotate_toward(b.yaw, want_yaw, Movement.turn_rate_rad(b.species) * dt)
	# Desacelera em curva fechada, como um bicho de verdade.
	var align := cos(wrapf(want_yaw - b.yaw, -PI, PI))
	var v := speed * clampf(align, 0.25, 1.0)
	if Movement.is_swimming(world.terrain, b.pos.x, b.pos.z, b.body_height()):
		v *= Movement.SWIM_SPEED_MULT
	v = minf(v, dist / dt)
	b.pos += b.forward() * v * dt
	b.pos = Terrain.clamp_to_play_area(b.pos)
	b.pos.y = Movement.ground_y(world.terrain, b.pos.x, b.pos.z, b.body_height())
	b.moving_speed = v
	b.sprinting = sprint
	return false


static func _clamp_inside(p: Vector3) -> Vector3:
	var lo := Terrain.BORDER + 6.0
	var hi := Terrain.SIZE - Terrain.BORDER - 6.0
	return Vector3(clampf(p.x, lo, hi), p.y, clampf(p.z, lo, hi))


## Passeio: ponto aleatório, puxado em direção ao grupo da mesma espécie (manada).
static func _wander_destination(world: WorldSim, b: Dino) -> Vector3:
	var ang := world.rng.randf_range(-PI, PI)
	var r := world.rng.randf_range(12.0, WANDER_RADIUS)
	var dest := b.pos + Vector3(sin(ang), 0.0, cos(ang)) * r
	if not b.is_carnivore():
		var sum := Vector3.ZERO
		var n := 0
		for o in world.query(b.pos, HERD_RADIUS):
			if o != b and o.species == b.species:
				sum += o.pos
				n += 1
		if n > 0:
			dest = dest.lerp(sum / n, 0.5)
	# Evita mandar o bicho pra dentro do rio fundo à toa.
	dest = _clamp_inside(dest)
	if world.terrain.water_depth(dest.x, dest.z) > b.body_height() * 0.5:
		dest = dest.lerp(b.pos, 0.6)
	return dest
