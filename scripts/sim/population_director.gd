class_name PopulationDirector
extends RefCounted
## Diretor de população (design, seção 3). Roda no servidor, dentro do WorldSim.
##
## Decisões do Marcelo que isso implementa:
## - Jogadores juntos → concentra bots perto deles; separados → espalha, sempre com população
##   considerável perto de cada um. Os jogadores viram "grupos" (DIRECTOR_GROUP_DIST) e cada grupo
##   quer DIRECTOR_NEAR_SHARE da população-alvo dividida pelo número de grupos.
## - Carnívoro jogador com fome → mais herbívoros na área; herbívoro demais → mais carnívoros.
##   A proporção geral só sai DIRECTOR_SHARE_TOLERANCE dos 65/35.
##
## Duas alavancas, sempre fora da vista dos jogadores:
## - Reposição: o bot novo nasce na área do grupo que mais precisa, com a espécie que a área pede.
## - Mudança de lugar: de tempos em tempos, bots congelados bem longe de todo mundo vão pra
##   área de um grupo com pouca população (poucos por vez, cada bot no máximo a cada
##   DIRECTOR_RELOCATE_COOLDOWN_S).
## Sem jogador no mundo não faz nada, nem sorteia no rng (os testes de carga não mudam).

## Tentativas de achar um lugar bom em volta do grupo antes de desistir.
const SPOT_TRIES := 40

var _timer := 0.0
## id do bot -> world_time da última vez que ele mudou de lugar.
var _relocated_at := {}


## Grupos de jogadores e a situação da área de cada um. Cada grupo é um Dictionary:
## players (Array de Dino), bots e herbs (bots na área), wanted (quantos o diretor quer lá),
## deficit (wanted - bots) e need ("herb", "carn" ou "": espécie que a área pede).
static func groups(w: WorldSim) -> Array:
	var ps := w.players()
	if ps.is_empty():
		return []
	# Junta quem está perto de alguém do grupo (até 5 jogadores: força bruta basta).
	var gid := range(ps.size())
	var changed := true
	while changed:
		changed = false
		for i in ps.size():
			for j in range(i + 1, ps.size()):
				if gid[i] != gid[j] and Movement.flat_distance(ps[i].pos, ps[j].pos) <= GameConfig.DIRECTOR_GROUP_DIST:
					var old: int = gid[j]
					for k in ps.size():
						if gid[k] == old:
							gid[k] = gid[i]
					changed = true
	var by_id := {}
	var out := []
	for i in ps.size():
		if not by_id.has(gid[i]):
			by_id[gid[i]] = out.size()
			out.append({"players": [], "bots": 0, "herbs": 0})
		out[by_id[gid[i]]]["players"].append(ps[i])
	var group_of := {}
	for i in ps.size():
		group_of[ps[i].id] = by_id[gid[i]]

	# Cada bot conta pra área do jogador mais próximo, se estiver dentro do raio.
	for b: Dino in w.bots():
		var best: Dino = null
		var best_d := INF
		for p: Dino in ps:
			var d := Movement.flat_distance(b.pos, p.pos)
			if d < best_d:
				best_d = d
				best = p
		if best_d <= GameConfig.DIRECTOR_AREA_RADIUS:
			var g: Dictionary = out[group_of[best.id]]
			g["bots"] += 1
			if not b.is_carnivore():
				g["herbs"] += 1

	for g: Dictionary in out:
		g["wanted"] = w.bot_target * GameConfig.DIRECTOR_NEAR_SHARE / out.size()
		g["deficit"] = g["wanted"] - g["bots"]
		g["need"] = _need(g)
	return out


static func _need(g: Dictionary) -> String:
	for p: Dino in g["players"]:
		if p.is_carnivore() and p.hunger < GameConfig.DIRECTOR_HUNGRY:
			return "herb"
	if g["bots"] >= GameConfig.DIRECTOR_MIN_LOCAL \
			and float(g["herbs"]) / g["bots"] > GameConfig.DIRECTOR_HERB_EXCESS:
		return "carn"
	return ""


## Onde e com que necessidade nasce o próximo bot: {"pos": Vector3, "need": String},
## ou {} quando o diretor não tem preferência (aí vale a regra antiga do WorldSim).
## Vai pro grupo com mais falta de bots; sem falta em nenhum, pro grupo que pede uma espécie.
func pick_spawn(w: WorldSim) -> Dictionary:
	var gs := groups(w)
	if gs.is_empty():
		return {}
	var target: Dictionary = _most_lacking(gs)
	if target.is_empty():
		for g: Dictionary in gs:
			if g["need"] != "":
				target = g
				break
	if target.is_empty():
		return {}
	var spot = _spot_near(w, target, WorldSim.BOT_SPAWN_MIN_PLAYER_DIST)
	if spot == null:
		return {}
	return {"pos": spot, "need": target["need"]}


## Chamado todo passo. A cada DIRECTOR_INTERVAL_S muda até DIRECTOR_RELOCATE_MAX bots congelados
## de lugar, pra área do grupo com mais falta de bots.
func update(w: WorldSim, dt: float) -> void:
	_timer += dt
	if _timer < GameConfig.DIRECTOR_INTERVAL_S:
		return
	_timer = 0.0
	for id in _relocated_at.keys():
		if not w.dinos.has(id):
			_relocated_at.erase(id)
	var gs := groups(w)
	var target: Dictionary = _most_lacking(gs)
	if target.is_empty():
		return
	var left := mini(GameConfig.DIRECTOR_RELOCATE_MAX, ceili(target["deficit"]))
	for b: Dino in _sources(w, target):
		if left <= 0:
			break
		var spot = _spot_near(w, target, GameConfig.DIRECTOR_RELOCATE_MIN_DIST)
		if spot == null:
			break
		_move(w, b, spot)
		_relocated_at[b.id] = w.world_time
		left -= 1


static func _most_lacking(gs: Array) -> Dictionary:
	var best := {}
	for g: Dictionary in gs:
		if g["deficit"] > 0.0 and (best.is_empty() or g["deficit"] > best["deficit"]):
			best = g
	return best


## Bots que podem mudar de lugar: congelados, longe de todos os jogadores, fora de briga (a luta
## congelada fica onde está: design, seção 5) e sem ter mudado há pouco. A espécie que a área
## pede vem primeiro.
func _sources(w: WorldSim, target: Dictionary) -> Array:
	var ps := w.players()
	var busy := {}
	for pa in w.pending_attacks:
		busy[int(pa["id"])] = true
	var want_herb: bool
	match String(target["need"]):
		"herb":
			want_herb = true
		"carn":
			want_herb = false
		_:
			want_herb = target["bots"] == 0 or float(target["herbs"]) / target["bots"] < GameConfig.HERBIVORE_SHARE
	var first := []
	var rest := []
	for b: Dino in w.bots():
		if b.sim_tier != WorldSim.SimTier.FROZEN or busy.has(b.id):
			continue
		if BotBrain.state_of(b) in ["fight", "hunt", "flee"]:
			continue
		if w.world_time - float(_relocated_at.get(b.id, -INF)) < GameConfig.DIRECTOR_RELOCATE_COOLDOWN_S:
			continue
		var near := INF
		for p: Dino in ps:
			near = minf(near, Movement.flat_distance(b.pos, p.pos))
		if near < GameConfig.DIRECTOR_SOURCE_MIN_DIST:
			continue
		if b.is_carnivore() != want_herb:
			first.append(b)
		else:
			rest.append(b)
	return first + rest


## Lugar em terra firme na área do grupo, a pelo menos min_dist de TODOS os jogadores, ou null.
static func _spot_near(w: WorldSim, g: Dictionary, min_dist: float) -> Variant:
	var members: Array = g["players"]
	var ps := w.players()
	for i in SPOT_TRIES:
		var center: Dino = members[w.rng.randi() % members.size()]
		var ang := w.rng.randf_range(-PI, PI)
		var r := w.rng.randf_range(min_dist, GameConfig.DIRECTOR_AREA_RADIUS)
		var p := center.pos + Vector3(sin(ang), 0.0, cos(ang)) * r
		if not _is_good_spot(w, p):
			continue
		var ok := true
		for pl: Dino in ps:
			if Movement.flat_distance(p, pl.pos) < min_dist:
				ok = false
				break
		if ok:
			return Vector3(p.x, w.terrain.height_at(p.x, p.z), p.z)
	return null


## Mesmo critério de Terrain.random_land_point: dentro da área jogável, em terra firme, fora
## das montanhas e sem ladeira forte.
static func _is_good_spot(w: WorldSim, p: Vector3) -> bool:
	var c := w.terrain.clamp_to_play_area(p)
	if c.x != p.x or c.z != p.z:
		return false
	var h := w.terrain.height_at(p.x, p.z)
	return h > 0.6 and h < 26.0 and w.terrain.slope_at(p.x, p.z) < 0.7


static func _move(w: WorldSim, b: Dino, spot: Vector3) -> void:
	b.pos = Vector3(spot.x, Movement.ground_y(w.terrain, spot.x, spot.z, b.body_height()), spot.z)
	b.yaw = w.rng.randf_range(-PI, PI)
	# Esquece o que estava fazendo lá longe (presa, destino, bebedouro).
	b.brain = {}
	b.moving_speed = 0.0
	b.sprinting = false
