class_name WorldSim
extends RefCounted
## O mundo inteiro do lado do servidor: dinos, carcaças, arbustos, relógio, população.
## Não sabe nada de rede: o servidor chama step() e lê `events`.
## Isso permite testar toda a lógica do jogo sem abrir conexão.

## 1: v0.1 (sem tamanho do mapa, sempre 512 m). 2: grava "map_size".
const SAVE_FORMAT := 2

enum Ev { ATTACK = 1, HIT = 2, DEATH = 3 }
## Faixas da simulação por distância (ver _update_sim_tiers).
enum SimTier { FULL, REDUCED, FROZEN }

const BUSH_MAX_KG := 120.0
const BUSH_REGROW_S := 300.0
## Quanto a boca alcança além da ponta do focinho, em metros (escala com o tamanho).
const MOUTH_REACH := 1.2
const GRID_CELL := 32.0
## Carnívoros ficam pelo menos isso longe de onde um jogador novo nasce.
const SAFE_SPAWN_DIST := 70.0
## Bot novo aparece pelo menos isso longe de todos os jogadores (fora da vista).
const BOT_SPAWN_MIN_PLAYER_DIST := 90.0

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var world_time: float = 0.0
var next_id: int = 1
var bot_target: int = GameConfig.DEFAULT_BOT_TARGET

## Dinos presentes no mundo (bots + jogadores conectados). id -> Dino
var dinos := {}
## id -> {id, species, growth, pos: Vector3, yaw, meat, meat_max, t}
var carcasses := {}
var bush_food := PackedFloat32Array()
## Estado congelado dos jogadores: nome -> {"alive": bool, "dino": Dictionary}
var player_records := {}
## Momentos (world_time) em que um bot novo deve entrar.
var respawn_queue: Array = []
## Jogadores que saíram no meio de uma briga: id do dino -> world_time em que ele sai do mundo.
var lingering := {}
## Onde e qual bot entra, e quais congelados mudam de lugar (design, seção 3).
var director := PopulationDirector.new()
## Golpes em andamento: [{"id": atacante, "t": segundos até acertar}]
var pending_attacks: Array = []
## Eventos do último passo, lidos e limpos pelo servidor.
var events: Array = []

var _grid := {}
var _step_index := 0


func _init(p_seed: int = GameConfig.WORLD_SEED, p_bot_target: int = GameConfig.DEFAULT_BOT_TARGET,
		p_map_size: float = GameConfig.DEFAULT_MAP_SIZE) -> void:
	terrain = Terrain.get_shared(p_seed, p_map_size)
	rng.seed = p_seed * 31 + 7
	bot_target = clampi(p_bot_target, 0, GameConfig.BOT_MAX)
	bush_food.resize(terrain.bushes.size())
	bush_food.fill(BUSH_MAX_KG)


func new_id() -> int:
	next_id += 1
	return next_id - 1


# ---------------------------------------------------------------- consultas

func bots() -> Array:
	var out := []
	for d: Dino in dinos.values():
		if d.is_bot:
			out.append(d)
	return out


func players() -> Array:
	var out := []
	for d: Dino in dinos.values():
		if not d.is_bot:
			out.append(d)
	return out


func bot_count() -> int:
	var n := 0
	for d: Dino in dinos.values():
		if d.is_bot:
			n += 1
	return n


## Dino no mundo, ou null. Bot congelado conta como fora: ninguém persegue, foge ou revida
## contra ele (e ele também não está no _grid, então não é visto nem mordido).
func get_dino(id: int) -> Dino:
	var d: Dino = dinos.get(id)
	if d != null and d.sim_tier == SimTier.FROZEN:
		return null
	return d


## Quantos bots em cada faixa da simulação por distância: {"full", "reduced", "frozen"}.
func sim_tier_counts() -> Dictionary:
	var out := {"full": 0, "reduced": 0, "frozen": 0}
	for d: Dino in dinos.values():
		if d.is_bot:
			out[["full", "reduced", "frozen"][d.sim_tier]] += 1
	return out


func _rebuild_grid() -> void:
	_grid.clear()
	for d: Dino in dinos.values():
		if d.sim_tier == SimTier.FROZEN:
			continue
		var key := Vector2i(floori(d.pos.x / GRID_CELL), floori(d.pos.z / GRID_CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(d)


## Dinos vivos num raio (inclui o próprio, se estiver no raio).
func query(center: Vector3, radius: float) -> Array:
	var out := []
	var r2 := radius * radius
	var c0 := Vector2i(floori((center.x - radius) / GRID_CELL), floori((center.z - radius) / GRID_CELL))
	var c1 := Vector2i(floori((center.x + radius) / GRID_CELL), floori((center.z + radius) / GRID_CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell: Array = _grid.get(Vector2i(cx, cz), [])
			for d in cell:
				var dx: float = d.pos.x - center.x
				var dz: float = d.pos.z - center.z
				if dx * dx + dz * dz <= r2:
					out.append(d)
	return out


## O que um bot enxerga. Jogadores filhotes são percebidos mais tarde
## (design: o jogo favorece o jogador em crescimento).
func perceive(b: Dino, radius: float) -> Array:
	var out := []
	for o: Dino in query(b.pos, radius):
		if o == b or not o.alive:
			continue
		if not o.is_bot:
			var eff := radius * lerpf(0.5, 1.0, o.growth)
			if Movement.flat_distance(b.pos, o.pos) > eff:
				continue
		out.append(o)
	return out


func mouth_point(d: Dino) -> Vector3:
	var ap: Vector3 = d.spec()["attack_point"]
	var head_z := ap.z if d.is_carnivore() else ap.z * 0.85
	return d.pos + d.forward() * (head_z * d.scale())


func can_drink(d: Dino) -> bool:
	var m := mouth_point(d)
	var mid := d.pos.lerp(m, 0.5)
	var ahead := m + d.forward() * (MOUTH_REACH * d.scale())
	return terrain.is_water(m.x, m.z) or terrain.is_water(mid.x, mid.z) or terrain.is_water(ahead.x, ahead.z)


## Carcaça com carne ao alcance da boca, ou {}.
func carcass_in_reach(d: Dino) -> Dictionary:
	var m := mouth_point(d)
	var reach := MOUTH_REACH * maxf(d.scale(), 0.5)
	for c in carcasses.values():
		if c["meat"] <= 0.0:
			continue
		var cr := Species.length_m(c["species"]) * Species.scale_for(c["species"], c["growth"]) * 0.5
		if Movement.flat_distance(m, c["pos"]) <= cr + reach:
			return c
	return {}


## Índice do arbusto com comida ao alcance da boca, ou -1.
func bush_in_reach(d: Dino) -> int:
	var m := mouth_point(d)
	var reach := Terrain.BUSH_RADIUS + MOUTH_REACH * maxf(d.scale(), 0.5)
	var best := -1
	var best_d := INF
	for i in terrain.bushes.size():
		if bush_food[i] < 1.0:
			continue
		var dist := Movement.flat_distance(m, terrain.bushes[i])
		if dist <= reach and dist < best_d:
			best_d = dist
			best = i
	return best


func nearest_bush_with_food(from: Vector3, min_kg: float = 10.0) -> int:
	var best := -1
	var best_d := INF
	for i in terrain.bushes.size():
		if bush_food[i] < min_kg:
			continue
		var d := Movement.flat_distance(from, terrain.bushes[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func nearest_carcass(from: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for c in carcasses.values():
		if c["meat"] < 5.0:
			continue
		var d := Movement.flat_distance(from, c["pos"])
		if d < best_d:
			best_d = d
			best = c
	return best


# ---------------------------------------------------------------- passo

func step(dt: float) -> void:
	world_time += dt
	_step_index += 1
	_update_sim_tiers(dt)
	_rebuild_grid()

	for d: Dino in dinos.values():
		if d.is_bot and _runs_now(d):
			BotBrain.update(self, d, d.sim_dt)

	_separate_bots()

	for d: Dino in dinos.values():
		if not _runs_now(d):
			continue
		Metabolism.step(d, d.sim_dt)
		if d.interacting:
			_interact(d, d.sim_dt)
		else:
			d.interact_result = 0
		d.sim_dt = 0.0

	_resolve_attacks(dt)

	for d: Dino in dinos.values().duplicate():
		if d.alive and d.health <= 0.0:
			var cause := "fome e sede" if (d.hunger <= 0.0 or d.thirst <= 0.0) else "ferimentos"
			var killer: Dino = dinos.get(d.last_attacker_id)
			if killer != null and world_time - d.last_attacked_time < 10.0:
				cause = "morto por " + (killer.player_name if not killer.is_bot else Species.display_name(killer.species))
			kill(d, cause)

	_update_carcasses(dt)
	_regrow_bushes(dt)
	_process_respawns()
	director.update(self, dt)
	_finish_lingering()


## Simulação por distância (design, seção 5), contando o jogador mais próximo de cada bot:
## perto roda todo passo; mais longe roda 1 passo a cada SIM_REDUCED_EVERY; bem longe congela
## (ferido continua ferido, briga para no meio). Congelado só acorda mais perto do que
## congelou (histerese). Sem jogador no mundo ninguém congela: isso só acontece em teste,
## porque o servidor nem roda o passo com o mundo vazio.
func _update_sim_tiers(dt: float) -> void:
	var ps := players()
	for d: Dino in dinos.values():
		var near := 0.0
		if d.is_bot and not ps.is_empty():
			near = INF
			for p: Dino in ps:
				near = minf(near, Movement.flat_distance(d.pos, p.pos))
		var was_frozen := d.sim_tier == SimTier.FROZEN
		if near > (GameConfig.SIM_WAKE_DIST if was_frozen else GameConfig.SIM_FREEZE_DIST):
			if not was_frozen:
				_freeze(d)
			continue
		d.sim_tier = SimTier.FULL if near <= GameConfig.SIM_FULL_DIST else SimTier.REDUCED
		d.sim_dt += dt


func _freeze(d: Dino) -> void:
	d.sim_tier = SimTier.FROZEN
	d.sim_dt = 0.0
	# Fica parado no lugar: o cliente não pode mostrar ele correndo ou comendo sem sair do lugar.
	d.moving_speed = 0.0
	d.sprinting = false
	d.interacting = false
	d.interact_result = 0


## Se o dino é simulado neste passo. Na faixa do meio, o id espalha os bots entre os passos.
func _runs_now(d: Dino) -> bool:
	match d.sim_tier:
		SimTier.FULL:
			return true
		SimTier.REDUCED:
			return (_step_index + d.id) % GameConfig.SIM_REDUCED_EVERY == 0
	return false


func _interact(d: Dino, dt: float) -> void:
	var result := 0
	var want_drink := d.thirst < 99.5 and can_drink(d)
	var want_eat := false
	var carcass := {}
	var bush := -1
	if d.hunger < 99.5:
		if d.is_carnivore():
			carcass = carcass_in_reach(d)
			want_eat = not carcass.is_empty()
		else:
			bush = bush_in_reach(d)
			want_eat = bush != -1
	if want_drink and (not want_eat or d.thirst <= d.hunger):
		Metabolism.drink(d, dt)
		result = 2
	elif want_eat:
		if d.is_carnivore():
			carcass["meat"] -= Metabolism.eat(d, carcass["meat"], dt)
		else:
			bush_food[bush] -= Metabolism.eat(d, bush_food[bush], dt)
		result = 1
	d.interact_result = result


func _separate_bots() -> void:
	for b: Dino in dinos.values():
		if not b.is_bot or not _runs_now(b):
			continue
		var rb := Species.footprint_radius(b.species, b.growth)
		for o: Dino in query(b.pos, rb + 6.0):
			if o == b:
				continue
			var ro := Species.footprint_radius(o.species, o.growth)
			var delta := Vector2(b.pos.x - o.pos.x, b.pos.z - o.pos.z)
			var dist := delta.length()
			var min_d := rb + ro
			if dist >= min_d:
				continue
			if dist < 0.001:
				delta = Vector2(1.0, 0.0)
				dist = 0.001
			# O mais leve é empurrado mais; jogadores não são empurrados pelo servidor.
			var share := 1.0
			if o.is_bot:
				share = o.mass() / (o.mass() + b.mass())
			var push := delta / dist * (min_d - dist) * share
			b.pos.x += push.x
			b.pos.z += push.y
			b.pos = terrain.clamp_to_play_area(b.pos)
			b.pos.y = Movement.ground_y(terrain, b.pos.x, b.pos.z, b.body_height())


# ---------------------------------------------------------------- combate

## Começa um golpe. Devolve false se ainda está em recarga.
func start_attack(d: Dino) -> bool:
	if not d.alive or d.attack_cooldown > 0.0:
		return false
	var sp := d.spec()
	d.attack_cooldown = sp["attack_cooldown"]
	d.stamina = maxf(0.0, d.stamina - float(sp["attack_stamina"]))
	pending_attacks.append({"id": d.id, "t": float(sp["attack_windup"])})
	events.append({"type": Ev.ATTACK, "a": d.id})
	return true


func _resolve_attacks(dt: float) -> void:
	var still := []
	for pa in pending_attacks:
		var attacker: Dino = dinos.get(pa["id"])
		# Atacante congelado: o golpe fica parado no meio, junto com ele.
		if attacker != null and attacker.sim_tier == SimTier.FROZEN:
			still.append(pa)
			continue
		pa["t"] -= dt
		if pa["t"] > 0.0:
			still.append(pa)
			continue
		if attacker == null or not attacker.alive:
			continue
		var candidates := query(attacker.pos, 16.0)
		var hit := Combat.resolve_attack(attacker, candidates)
		if hit.is_empty():
			continue
		var target: Dino = hit["target"]
		var part: String = hit["part"]
		var dmg := Combat.damage(attacker, part)
		apply_damage(target, dmg, attacker)
		events.append({"type": Ev.HIT, "a": attacker.id, "b": target.id, "value": dmg, "part": part})
	pending_attacks = still


func apply_damage(target: Dino, amount: float, attacker: Dino) -> void:
	target.health -= amount
	if attacker != null:
		target.last_attacker_id = attacker.id
		target.last_attacked_time = world_time


## Mata um dino: vira carcaça; bot entra na fila de reposição; jogador fica marcado como morto.
func kill(d: Dino, cause: String) -> void:
	d.alive = false
	d.health = 0.0
	dinos.erase(d.id)
	pending_attacks = pending_attacks.filter(func(pa): return pa["id"] != d.id)
	var meat := d.mass() * 0.4
	var cid := new_id()
	carcasses[cid] = {
		"id": cid, "species": d.species, "growth": d.growth,
		"pos": d.pos, "yaw": d.yaw, "meat": meat, "meat_max": meat, "t": world_time,
	}
	if d.is_bot:
		respawn_queue.append(world_time + GameConfig.BOT_RESPAWN_DELAY_S)
	else:
		player_records[d.player_name] = {"alive": false, "dino": {"species": d.species}}
	events.append({"type": Ev.DEATH, "a": d.id, "carcass": cid, "cause": cause,
			"player": d.player_name if not d.is_bot else ""})


func _update_carcasses(_dt: float) -> void:
	for cid in carcasses.keys():
		var c: Dictionary = carcasses[cid]
		if c["meat"] <= 0.5 or world_time - float(c["t"]) > GameConfig.CARCASS_LIFETIME_S:
			carcasses.erase(cid)


func _regrow_bushes(dt: float) -> void:
	var grow := BUSH_MAX_KG / BUSH_REGROW_S * dt
	for i in bush_food.size():
		if bush_food[i] < BUSH_MAX_KG:
			bush_food[i] = minf(BUSH_MAX_KG, bush_food[i] + grow)


# ---------------------------------------------------------------- população

## Escolhe a espécie do próximo bot mantendo ~65% herbívoros / 35% carnívoros.
## `need` ("herb" ou "carn") é o que a área pede (PopulationDirector); vale só enquanto a
## proporção geral fica a até DIRECTOR_SHARE_TOLERANCE dos 65%.
func choose_bot_species(need: String = "") -> String:
	var herb := 0
	var total := 0
	for d: Dino in dinos.values():
		if d.is_bot:
			total += 1
			if not d.is_carnivore():
				herb += 1
	var as_herb := herb < roundi((total + 1) * GameConfig.HERBIVORE_SHARE)
	if need != "":
		var share := float(herb + int(need == "herb")) / (total + 1)
		if absf(share - GameConfig.HERBIVORE_SHARE) <= GameConfig.DIRECTOR_SHARE_TOLERANCE:
			as_herb = need == "herb"
	if as_herb:
		return "triceratops" if rng.randf() < 0.4 else "dryosaurus"
	return "carnotaurus"


func spawn_bot(species_id: String = "", growth: float = -1.0) -> Dino:
	var plan := director.pick_spawn(self)
	if species_id == "":
		species_id = choose_bot_species(String(plan.get("need", "")))
	if growth < 0.0:
		growth = rng.randf_range(0.45, 1.0)
	var pos: Vector3 = plan["pos"] if plan.has("pos") else _bot_spawn_point()
	var d := Dino.create(new_id(), species_id, growth, pos)
	d.is_bot = true
	d.yaw = rng.randf_range(-PI, PI)
	d.hunger = rng.randf_range(60.0, 100.0)
	d.thirst = rng.randf_range(60.0, 100.0)
	d.pos.y = Movement.ground_y(terrain, pos.x, pos.z, d.body_height())
	dinos[d.id] = d
	return d


## Enche o mundo até a população-alvo (usado num mundo novo).
func populate() -> void:
	while bot_count() < bot_target:
		spawn_bot()


func _process_respawns() -> void:
	if respawn_queue.is_empty():
		return
	var still := []
	for due in respawn_queue:
		if world_time >= due:
			if bot_count() < bot_target:
				spawn_bot()
		else:
			still.append(due)
	respawn_queue = still
	# Garante a reposição mesmo se a fila se perder (ex.: save antigo).
	if respawn_queue.is_empty() and bot_count() < bot_target:
		var missing := bot_target - bot_count()
		for i in missing:
			respawn_queue.append(world_time + GameConfig.BOT_RESPAWN_DELAY_S)


func _bot_spawn_point() -> Vector3:
	var ps := players()
	var best := terrain.random_land_point(rng)
	if ps.is_empty():
		return best
	var best_score := -INF
	for i in 30:
		var p := terrain.random_land_point(rng)
		var nearest := INF
		for pl: Dino in ps:
			nearest = minf(nearest, Movement.flat_distance(p, pl.pos))
		if nearest >= BOT_SPAWN_MIN_PLAYER_DIST:
			return p
		if nearest > best_score:
			best_score = nearest
			best = p
	return best


## Onde um jogador novo nasce: longe de carnívoros e perto de água.
func _player_spawn_point() -> Vector3:
	var best := terrain.random_land_point(rng)
	var best_score := -INF
	for i in 40:
		var p := terrain.random_land_point(rng)
		var nearest_carn := SAFE_SPAWN_DIST * 2.0
		for d: Dino in dinos.values():
			if d.is_bot and d.is_carnivore():
				nearest_carn = minf(nearest_carn, Movement.flat_distance(p, d.pos))
		var water := Movement.flat_distance(p, terrain.nearest_water_point(p))
		var score := minf(nearest_carn, SAFE_SPAWN_DIST * 1.5) - water * 0.3
		if score > best_score:
			best_score = score
			best = p
	return best


# ---------------------------------------------------------------- jogadores

## Coloca o jogador no mundo. Se ele tem um dino vivo salvo, volta exatamente igual.
## Devolve {"dino": Dino, "restored": bool}.
func login_player(player_name: String, species_choice: String) -> Dictionary:
	# Voltou antes do dino sair do mundo (saiu no meio de uma briga): assume o mesmo dino.
	for id in lingering:
		var ld: Dino = dinos.get(id)
		if ld != null and ld.player_name == player_name:
			lingering.erase(id)
			ld.client_seq += 1
			return {"dino": ld, "restored": true}
	var rec: Dictionary = player_records.get(player_name, {})
	if not rec.is_empty() and bool(rec.get("alive", false)):
		var d := Dino.from_dict(rec["dino"])
		d.id = new_id()
		d.is_bot = false
		d.player_name = player_name
		d.alive = true
		d.client_seq = 1
		if bool(rec.get("relocate", false)):
			# Veio de outro mapa: mesmo dino, lugar novo.
			var p := _player_spawn_point()
			d.pos = Vector3(p.x, Movement.ground_y(terrain, p.x, p.z, d.body_height()), p.z)
			rec.erase("relocate")
		dinos[d.id] = d
		return {"dino": d, "restored": true}
	return {"dino": respawn_player(player_name, species_choice), "restored": false}


## Dino novo, sempre jovem (design: ao morrer recomeça jovem).
func respawn_player(player_name: String, species_choice: String) -> Dino:
	if not Species.is_valid(species_choice):
		species_choice = "dryosaurus"
	var p := _player_spawn_point()
	var d := Dino.create(new_id(), species_choice, GameConfig.PLAYER_START_GROWTH, p)
	d.is_bot = false
	d.player_name = player_name
	d.yaw = rng.randf_range(-PI, PI)
	d.pos.y = Movement.ground_y(terrain, p.x, p.z, d.body_height())
	d.client_seq = 1
	dinos[d.id] = d
	player_records[player_name] = {"alive": true, "dino": d.to_dict()}
	return d


## O jogador saiu. Se levou um golpe há menos de COMBAT_LOGOUT_S, o dino fica esse tempo no
## mundo, parado e vulnerável, e só depois sai (decisão de 28/10: não dá pra fugir de uma briga
## fechando o jogo). Devolve true se saiu na hora.
func request_logout(id: int) -> bool:
	var d: Dino = dinos.get(id)
	if d == null or d.is_bot:
		return true
	if GameConfig.COMBAT_LOGOUT_S <= 0.0 or world_time - d.last_attacked_time >= GameConfig.COMBAT_LOGOUT_S:
		logout_player(id)
		return true
	d.interacting = false
	d.sprinting = false
	d.resting = false
	d.moving_speed = 0.0
	lingering[id] = world_time + GameConfig.COMBAT_LOGOUT_S
	return false


func _finish_lingering() -> void:
	for id in lingering.keys():
		if not dinos.has(id):
			lingering.erase(id)  # morreu enquanto esperava
		elif world_time >= float(lingering[id]):
			lingering.erase(id)
			logout_player(id)


## Leva os jogadores de um save de outro mapa (semente ou tamanho) pra este mundo novo: mesmo
## dino (espécie, crescimento, vida, fome, sede), num lugar novo quando entrar. Os bots não vêm.
## Devolve quantos dinos vivos vieram.
func adopt_players(old_save: Dictionary) -> int:
	var count := 0
	var old: Dictionary = old_save.get("players", {})
	for player_name in old:
		var rec: Dictionary = Dictionary(old[player_name]).duplicate(true)
		if bool(rec.get("alive", false)) and rec.has("dino"):
			rec["relocate"] = true
			count += 1
		player_records[player_name] = rec
	return count


## Tira o jogador do mundo e congela o estado dele (não cura, não passa fome, não cresce).
func logout_player(id: int) -> void:
	var d: Dino = dinos.get(id)
	if d == null or d.is_bot:
		return
	d.interacting = false
	d.sprinting = false
	d.moving_speed = 0.0
	player_records[d.player_name] = {"alive": true, "dino": d.to_dict()}
	dinos.erase(id)
	pending_attacks = pending_attacks.filter(func(pa): return pa["id"] != id)


## Atualiza o registro salvo de todos os jogadores conectados (antes de salvar em disco).
func snapshot_player_records() -> void:
	for d: Dino in dinos.values():
		if not d.is_bot and d.alive:
			player_records[d.player_name] = {"alive": true, "dino": d.to_dict()}


# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	snapshot_player_records()
	var bot_list := []
	for d: Dino in dinos.values():
		if d.is_bot:
			bot_list.append(d.to_dict())
	var carc := []
	for c in carcasses.values():
		var cc: Dictionary = c.duplicate()
		var p: Vector3 = c["pos"]
		cc["pos"] = [p.x, p.y, p.z]
		carc.append(cc)
	return {
		"format": SAVE_FORMAT,
		"version": GameConfig.VERSION,
		"seed": terrain.seed_value,
		"map_size": terrain.size,
		"world_time": world_time,
		"next_id": next_id,
		"bots": bot_list,
		"carcasses": carc,
		"bush_food": Array(bush_food),
		"players": player_records.duplicate(true),
		"respawn_queue": respawn_queue.duplicate(),
	}


## Tamanho do mapa de um save. Save da v0.1 (formato 1) não grava: era sempre 512 m.
static func save_map_size(data: Dictionary) -> float:
	return Terrain.normalize_size(float(data.get("map_size", 512.0)))


## Por que um save não serve pra este mundo ("" = serve). Mapa diferente (semente ou tamanho)
## deixaria os dinos salvos em lugares que não existem mais.
func save_mismatch(data: Dictionary) -> String:
	if int(data.get("seed", -1)) != terrain.seed_value:
		return "o save é de outro mapa (semente %d, este é %d)" % [int(data.get("seed", -1)), terrain.seed_value]
	if save_map_size(data) != terrain.size:
		return "o save é de um mapa de %d m (este é de %d m)" % [int(save_map_size(data)), int(terrain.size)]
	return ""


## Carrega um save. Jogadores ficam só nos registros (entram de novo quando conectam).
## Confira antes com save_mismatch. Formato 1 (v0.1) lê igual: só não tinha "map_size".
func load_save(data: Dictionary) -> void:
	world_time = float(data.get("world_time", 0.0))
	next_id = int(data.get("next_id", 1))
	dinos.clear()
	for bd in data.get("bots", []):
		var d := Dino.from_dict(bd)
		d.is_bot = true
		if d.id <= 0 or dinos.has(d.id):
			d.id = new_id()
		next_id = maxi(next_id, d.id + 1)
		dinos[d.id] = d
	carcasses.clear()
	for c in data.get("carcasses", []):
		var cc: Dictionary = c.duplicate()
		var p: Array = cc["pos"]
		cc["pos"] = Vector3(float(p[0]), float(p[1]), float(p[2]))
		cc["id"] = int(cc["id"])
		carcasses[cc["id"]] = cc
		next_id = maxi(next_id, cc["id"] + 1)
	var bf: Array = data.get("bush_food", [])
	if bf.size() == bush_food.size():
		for i in bf.size():
			bush_food[i] = float(bf[i])
	player_records = data.get("players", {}).duplicate(true)
	respawn_queue = []
	for t in data.get("respawn_queue", []):
		respawn_queue.append(float(t))
