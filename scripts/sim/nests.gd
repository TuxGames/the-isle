class_name Nests
extends RefCounted
## Reprodução (design, seção 8): ninho, parceiro, postura, incubação, filhotes e ovos comidos.
## Roda no servidor, dentro do WorldSim, e não sabe nada de rede. O servidor lê `messages`
## (avisos pra cada jogador) e `dirty` (os ninhos mudaram: manda s_nests pra todo mundo).
##
## Decisões (R) aprovadas pelo Marcelo que isso implementa (números em config.gd, seção
## "Reprodução", e `clutch`/`egg_kg` em species.gd):
## - Quem pode: adulto, comida e água a partir de REPRO_MIN_FOOD, sem sangramento.
## - Ninho: segurar N parado por NEST_BUILD_S em terra firme, sem ladeira forte. Um por jogador
##   (fazer outro abandona o antigo, menos com ovos chocando). Vai pro save.
## - Parceiro: bot ou jogador adulto da mesma espécie, perto, com quem pede a até MATE_NEST_DIST
##   do próprio ninho. Bot aceita se estiver alimentado, sem fugir/brigar e sem recarga; jogador
##   tem MATE_CONFIRM_S pra apertar R de volta.
## - Postura: `clutch` ovos no ninho de quem pediu, recarga de LAY_COOLDOWN_S. Os ovos chocam em
##   INCUBATION_S de mundo (com o mundo parado nada anda, como todo o resto).
## - Choco: um ovo fica pronto pro dono (se ele morrer, pode "Nascer no ninho", filhote); os
##   outros viram bots filhotes, até BOT_MAX bots (cheio, o ovo espera).
## - Carnívoro come ovo (jogador segurando E, bot com fome que passa perto); herbívoro não.
## - BOT_NEST_SHARE das reposições de bot vira um ninho de bot, fora da vista dos jogadores.
## - O ninho some quando acabam os ovos.

## Os ovos ficam em "vagas" fixas em volta do centro: comer um não faz os outros pularem.
const EGG_SLOTS := 6
const EGG_RING_M := 0.6
## Raio do ninho (desenho e busca de ovos).
const NEST_RADIUS_M := 1.15
## Quanto a boca alcança além do centro do ovo.
const EGG_REACH_M := 0.3
## Altura mínima do chão (acima da água) pra fazer ninho.
const NEST_MIN_HEIGHT := 0.4
## Texto do Action.RESPAWN pra nascer no próprio ninho.
const RESPAWN_ARG := "nest"
## Estados de bot que não aceitam parceiro (fugindo, brigando, caçando).
const BOT_BUSY_STATES := ["flee", "fight", "hunt"]

## id -> {"id", "owner" ("" = sem dono: de bot ou abandonado), "species", "pos": Vector3,
##        "eggs": [{"slot": int, "ready": bool}], "hatch_at" (world_time), "laid" (já teve ovos),
##        "bot_slot" (veio de uma reposição de bot: vale um bot enquanto tiver ovos)}
## "ready" = já chocou e está esperando o dono nascer nele.
var nests := {}
## Quando cada jogador pode fazer postura de novo (nome -> world_time). Vai pro save.
var lay_ready := {}
## Quando cada bot aceita parceiro de novo (id -> world_time). Só na memória.
var bot_ready := {}
## Pedidos de parceiro entre jogadores: nome de quem recebeu -> {"from": nome, "until": world_time}.
var requests := {}
## Jogadores segurando N: id do dino -> segundos parado segurando.
var building := {}
## Quem está comendo ovo: id do dino -> {"key": "ninho:vaga", "t": segundos, "at": world_time}.
var eating := {}
## Parte das reposições de bot que vira ninho de bot (os testes trocam).
var bot_nest_share: float = GameConfig.BOT_NEST_SHARE
## Avisos pros jogadores: [[nome, texto], ...]. O servidor manda e limpa.
var messages: Array = []
## Algo nos ninhos mudou: o servidor manda s_nests pra todos e põe false.
var dirty := false


# ---------------------------------------------------------------- regras

static func is_adult(d: Dino) -> bool:
	return d.growth >= GameConfig.ADULT_GROWTH


## Por que esse dino não pode fazer ninho nem postura ("" = pode).
static func breed_error(d: Dino) -> String:
	if not is_adult(d):
		return "Só adulto pode se reproduzir (você está com %d%% do crescimento)." % floori(d.growth * 100.0)
	if d.hunger < GameConfig.REPRO_MIN_FOOD or d.thirst < GameConfig.REPRO_MIN_FOOD:
		return "Pra se reproduzir, a comida e a água têm que estar acima de %d%%." % int(GameConfig.REPRO_MIN_FOOD)
	if Injuries.has(d, Injuries.BLEED):
		return "Sangrando não dá: espere o sangramento parar."
	return ""


## Por que não dá pra fazer ninho aqui ("" = dá): terra firme e sem ladeira forte.
static func spot_error(t: Terrain, p: Vector3) -> String:
	if t.height_at(p.x, p.z) < Terrain.WATER_LEVEL + NEST_MIN_HEIGHT:
		return "Aqui é água: o ninho precisa de terra firme."
	if t.slope_at(p.x, p.z) > GameConfig.NEST_MAX_SLOPE:
		return "Ladeira forte demais: procure um lugar mais plano."
	return ""


## Por que o bot não aceita ser parceiro ("" = aceita). Quem não é adulto nem entra na lista.
func bot_refusal(w: WorldSim, b: Dino) -> String:
	if b.hunger < GameConfig.REPRO_MIN_FOOD or b.thirst < GameConfig.REPRO_MIN_FOOD:
		return "está com fome ou sede"
	if BOT_BUSY_STATES.has(BotBrain.state_of(b)):
		return "está ocupado fugindo ou brigando"
	if w.world_time < float(bot_ready.get(b.id, -INF)):
		return "fez ninho há pouco"
	return ""


## Distância máxima entre os dois pra serem parceiros: MATE_RANGE_M além dos dois corpos.
static func mate_reach(a: Dino, b: Dino) -> float:
	return GameConfig.MATE_RANGE_M + Species.footprint_radius(a.species, a.growth) \
			+ Species.footprint_radius(b.species, b.growth)


## Por que esse jogador não pode fazer postura agora ("" = pode, falta só o parceiro).
func mate_error(w: WorldSim, d: Dino) -> String:
	var e := breed_error(d)
	if e != "":
		return e
	var nest := nest_of(d.player_name)
	if nest.is_empty():
		return "Primeiro faça um ninho: segure N parado por %d s." % int(GameConfig.NEST_BUILD_S)
	if String(nest["species"]) != d.species:
		return "Esse ninho é de %s: faça um novo." % Species.display_name(nest["species"])
	if incubating_count(nest) > 0:
		return "Seu ninho já tem ovos chocando."
	var wait := lay_cooldown(w, d.player_name)
	if wait > 0.0:
		return "Ainda não dá: nova postura em %s." % clock(wait)
	if Movement.flat_distance(d.pos, nest["pos"]) > GameConfig.MATE_NEST_DIST:
		return "Longe demais do seu ninho (tem que estar a até %d m dele)." % int(GameConfig.MATE_NEST_DIST)
	return ""


## Por que não dá pra fazer (ou mudar) o ninho aqui ("" = dá).
func build_error(w: WorldSim, d: Dino) -> String:
	var e := breed_error(d)
	if e != "":
		return e
	e = spot_error(w.terrain, d.pos)
	if e != "":
		return e
	var old := nest_of(d.player_name)
	if not old.is_empty() and incubating_count(old) > 0:
		return "Seu ninho ainda tem ovos chocando: não dá pra fazer outro agora."
	return ""


# ---------------------------------------------------------------- consultas

## O ninho do jogador, ou {}.
func nest_of(player_name: String) -> Dictionary:
	if player_name == "":
		return {}
	for nest: Dictionary in nests.values():
		if nest["owner"] == player_name:
			return nest
	return {}


static func incubating_count(nest: Dictionary) -> int:
	var n := 0
	for e: Dictionary in nest["eggs"]:
		if not e["ready"]:
			n += 1
	return n


static func ready_egg(nest: Dictionary) -> Dictionary:
	for e: Dictionary in nest["eggs"]:
		if e["ready"]:
			return e
	return {}


func lay_cooldown(w: WorldSim, player_name: String) -> float:
	return maxf(0.0, float(lay_ready.get(player_name, -INF)) - w.world_time)


## Ninhos de bot (de reposição) ainda com ovos: cada um vale um bot na conta da reposição.
func bot_slots() -> int:
	var n := 0
	for nest: Dictionary in nests.values():
		if nest["bot_slot"] and not nest["eggs"].is_empty():
			n += 1
	return n


## Deslocamento de cada vaga em volta do centro do ninho (igual no servidor e no cliente).
static func egg_offset(slot: int) -> Vector3:
	var ang := TAU * slot / EGG_SLOTS
	return Vector3(sin(ang), 0.0, cos(ang)) * EGG_RING_M


## Raio do desenho do ovo, pela comida que ele tem.
static func egg_radius(species_id: String) -> float:
	return 0.1 * pow(float(Species.DATA[species_id].get("egg_kg", 4.0)), 1.0 / 3.0)


static func egg_key(nest_id: int, slot: int) -> String:
	return "%d:%d" % [nest_id, slot]


func has_egg(key: String) -> bool:
	var parts := key.split(":")
	if parts.size() != 2:
		return false
	var nest: Dictionary = nests.get(int(parts[0]), {})
	if nest.is_empty():
		return false
	for e: Dictionary in nest["eggs"]:
		if int(e["slot"]) == int(parts[1]):
			return true
	return false


## Ovo ao alcance da boca de um carnívoro: {"key", "nest", "slot", "pos"} ou {}.
## Herbívoro não come ovo.
func egg_in_reach(w: WorldSim, d: Dino) -> Dictionary:
	if nests.is_empty() or not d.is_carnivore():
		return {}
	var m := w.mouth_point(d)
	var reach := EGG_REACH_M + WorldSim.MOUTH_REACH * maxf(d.scale(), 0.5)
	return _nearest_egg(m, reach, NEST_RADIUS_M + reach)


## Ovo mais perto de `from` até `radius` (bot carnívoro com fome procurando), ou {}.
func nearest_egg(from: Vector3, radius: float) -> Dictionary:
	if nests.is_empty():
		return {}
	return _nearest_egg(from, radius, NEST_RADIUS_M + radius)


func _nearest_egg(from: Vector3, radius: float, nest_radius: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for nest: Dictionary in nests.values():
		if nest["eggs"].is_empty() or Movement.flat_distance(from, nest["pos"]) > nest_radius:
			continue
		for e: Dictionary in nest["eggs"]:
			var p: Vector3 = nest["pos"] + egg_offset(int(e["slot"]))
			var dist := Movement.flat_distance(from, p)
			if dist <= radius and dist < best_d:
				best_d = dist
				best = {"key": egg_key(nest["id"], e["slot"]), "nest": nest["id"], "slot": int(e["slot"]), "pos": p}
	return best


# ---------------------------------------------------------------- ninho

## Jogador começou (holding = true) ou parou de segurar N. Recusa na hora se não pode
## (o motivo vai pra `messages`). Devolve o motivo ou "".
func set_building(w: WorldSim, d: Dino, holding: bool) -> String:
	if not holding:
		building.erase(d.id)
		return ""
	var err := build_error(w, d)
	if err != "":
		building.erase(d.id)
		_tell(d.player_name, err)
		return err
	building[d.id] = 0.0
	return ""


## Cria um ninho. `owner` "" = ninho sem dono (de bot). O ninho antigo do mesmo dono: vazio,
## some; só com o ovo pronto, fica abandonado (o ovo choca como bot).
func build(w: WorldSim, owner: String, species_id: String, pos: Vector3) -> Dictionary:
	if owner != "":
		var old := nest_of(owner)
		if not old.is_empty():
			if old["eggs"].is_empty():
				nests.erase(old["id"])
			else:
				old["owner"] = ""
				_tell(owner, "Seu ninho antigo foi abandonado: o ovo que estava lá vai chocar como filhote.")
	var id := w.new_id()
	var nest := {
		"id": id, "owner": owner, "species": species_id,
		"pos": Vector3(pos.x, w.terrain.height_at(pos.x, pos.z), pos.z),
		"eggs": [], "hatch_at": 0.0, "laid": false, "bot_slot": false,
	}
	nests[id] = nest
	dirty = true
	return nest


## Postura: `count` ovos (padrão: `clutch` da espécie) nas vagas livres. Chocam em INCUBATION_S.
## Devolve quantos entraram.
func lay(w: WorldSim, nest: Dictionary, count: int = -1) -> int:
	if count < 0:
		count = int(Species.DATA[nest["species"]].get("clutch", 2))
	var used := {}
	for e: Dictionary in nest["eggs"]:
		used[int(e["slot"])] = true
	var added := 0
	for slot in EGG_SLOTS:
		if added >= count:
			break
		if not used.has(slot):
			nest["eggs"].append({"slot": slot, "ready": false})
			added += 1
	if added > 0:
		nest["hatch_at"] = w.world_time + GameConfig.INCUBATION_S
		nest["laid"] = true
		dirty = true
	return added


# ---------------------------------------------------------------- parceiro

## Jogador apertou R. Aceita o pedido de outro jogador, se tiver um valendo; senão procura um
## parceiro perto (bot aceita ou recusa na hora; jogador recebe o pedido). Devolve "" se deu certo
## (postura feita ou pedido enviado) ou o motivo. Os avisos vão pra `messages`.
func press_mate(w: WorldSim, d: Dino) -> String:
	if d.is_bot or not d.alive:
		return "sem dino"
	var req: Dictionary = requests.get(d.player_name, {})
	requests.erase(d.player_name)
	if not req.is_empty() and w.world_time <= float(req["until"]):
		return _accept(w, d, String(req["from"]))
	var err := mate_error(w, d)
	if err != "":
		_tell(d.player_name, err)
		return err
	var refusal := ""
	for o: Dino in partners_near(w, d):
		if not o.is_bot:
			requests[o.player_name] = {"from": d.player_name, "until": w.world_time + GameConfig.MATE_CONFIRM_S}
			_tell(o.player_name, "%s quer fazer ninho com você: aperte R em %d s pra aceitar." % [
					d.player_name, int(GameConfig.MATE_CONFIRM_S)])
			_tell(d.player_name, "Pedido enviado pra %s: tem %d s pra apertar R." % [
					o.player_name, int(GameConfig.MATE_CONFIRM_S)])
			return ""
		var why := bot_refusal(w, o)
		if why == "":
			bot_ready[o.id] = w.world_time + GameConfig.LAY_COOLDOWN_S
			_lay_for(w, d)
			return ""
		if refusal == "":
			refusal = "O %s não quis: %s." % [Species.display_name(o.species), why]
	if refusal == "":
		refusal = "Nenhum %s adulto perto o bastante: chegue a uns %d m de um." % [
				Species.display_name(d.species), ceili(mate_reach(d, d))]
	_tell(d.player_name, refusal)
	return refusal


## Adultos da mesma espécie ao alcance de `d` (bots e jogadores), do mais perto pro mais longe.
## Bot congelado fica de fora (pros outros bichos ele não existe).
func partners_near(w: WorldSim, d: Dino) -> Array:
	var out := []
	for o: Dino in w.dinos.values():
		if o == d or not o.alive or o.species != d.species or not is_adult(o):
			continue
		if o.sim_tier == WorldSim.SimTier.FROZEN:
			continue
		if Movement.flat_distance(d.pos, o.pos) <= mate_reach(d, o):
			out.append(o)
	out.sort_custom(func(a: Dino, b: Dino):
		return Movement.flat_distance(d.pos, a.pos) < Movement.flat_distance(d.pos, b.pos))
	return out


## `d` aceitou o pedido de `from_name`: confere tudo de novo e faz a postura no ninho de quem pediu.
func _accept(w: WorldSim, d: Dino, from_name: String) -> String:
	var r := _player_dino(w, from_name)
	var err := ""
	if r == null:
		err = "%s não está mais no mundo." % from_name
	elif r.species != d.species:
		err = "%s agora é de outra espécie." % from_name
	else:
		err = breed_error(d)
		if err == "":
			err = mate_error(w, r)
			if err != "":
				err = "%s não pode agora: %s" % [from_name, err]
		if err == "" and Movement.flat_distance(d.pos, r.pos) > mate_reach(d, r):
			err = "Vocês se afastaram: cheguem mais perto e peçam de novo."
	if err != "":
		_tell(d.player_name, err)
		_tell(from_name, "%s aceitou, mas não deu: %s" % [d.player_name, err])
		return err
	var n := _lay_for(w, r)
	_tell(d.player_name, "Você ajudou %s: %d ovos no ninho." % [from_name, n])
	return ""


func _lay_for(w: WorldSim, owner: Dino) -> int:
	var nest := nest_of(owner.player_name)
	var n := lay(w, nest)
	lay_ready[owner.player_name] = w.world_time + GameConfig.LAY_COOLDOWN_S
	_tell(owner.player_name, "Postura feita: %d ovos no ninho. Chocam em %s; cuide deles, carnívoro come ovo." % [
			n, clock(GameConfig.INCUBATION_S)])
	return n


static func _player_dino(w: WorldSim, player_name: String) -> Dino:
	for o: Dino in w.dinos.values():
		if not o.is_bot and o.player_name == player_name and o.alive:
			return o
	return null


# ---------------------------------------------------------------- passo

## Chamado todo passo pelo WorldSim: ninho sendo feito, pedidos vencidos e ovos chocando.
func step(w: WorldSim, dt: float) -> void:
	if not building.is_empty():
		_step_building(w, dt)
	if not requests.is_empty():
		for target in requests.keys():
			if w.world_time > float(requests[target]["until"]):
				requests.erase(target)
	if not bot_ready.is_empty():
		for id in bot_ready.keys():
			if w.world_time >= float(bot_ready[id]) or not w.dinos.has(id):
				bot_ready.erase(id)
	if not nests.is_empty():
		_step_hatching(w)
	# Sem servidor (testes, --bench) ninguém lê os avisos: não deixa acumular.
	if messages.size() > 200:
		messages = messages.slice(messages.size() - 50)


func _step_building(w: WorldSim, dt: float) -> void:
	for id in building.keys():
		var d: Dino = w.dinos.get(id)
		if d == null or not d.alive or d.is_bot:
			building.erase(id)
			continue
		if d.moving_speed > Metabolism.MOVING_EPS:
			building[id] = 0.0  # tem que ficar parado: andou, recomeça
			continue
		building[id] = float(building[id]) + dt
		if float(building[id]) < GameConfig.NEST_BUILD_S:
			continue
		building.erase(id)
		var err := build_error(w, d)
		if err != "":
			_tell(d.player_name, err)
			continue
		build(w, d.player_name, d.species, d.pos)
		_tell(d.player_name, "Ninho pronto! Chegue perto de um %s adulto (bot ou jogador), a até %d m do ninho, e aperte R." % [
				Species.display_name(d.species), int(GameConfig.MATE_NEST_DIST)])


## Ovos que já chocaram: o primeiro do dono fica pronto pra ele; os outros viram bots filhotes
## enquanto couber (BOT_MAX). Ninho que já teve ovos e ficou sem nenhum some.
func _step_hatching(w: WorldSim) -> void:
	var room := -1
	for nest: Dictionary in nests.values().duplicate():
		var eggs: Array = nest["eggs"]
		if eggs.is_empty():
			if nest["laid"]:
				_remove(nest)
			continue
		var owner: String = nest["owner"]
		var due := w.world_time >= float(nest["hatch_at"]) and incubating_count(nest) > 0
		if not due and (owner != "" or ready_egg(nest).is_empty()):
			continue
		var born := 0
		var kept := false
		for e: Dictionary in eggs.duplicate():
			if e["ready"]:
				if owner != "":
					continue
			elif not due:
				continue
			elif owner != "" and ready_egg(nest).is_empty():
				e["ready"] = true
				kept = true
				dirty = true
				continue
			if room < 0:
				room = GameConfig.BOT_MAX - w.bot_count()
			if room <= 0:
				break  # cheio: o ovo espera
			hatch_bot(w, nest, e)
			room -= 1
			born += 1
		if owner != "" and (born > 0 or kept):
			var txt := "Seus ovos chocaram"
			if born > 0:
				txt += ": %d filhote(s) nasceram" % born
			if kept:
				txt += (" e " if born > 0 else ": ") + "1 ovo ficou pronto pra você (se morrer, dá pra nascer no ninho)"
			_tell(owner, txt + ".")
		if nest["eggs"].is_empty():
			_remove(nest)


## O ovo vira um bot filhote da espécie, em cima do ninho.
func hatch_bot(w: WorldSim, nest: Dictionary, egg: Dictionary) -> Dino:
	nest["eggs"].erase(egg)
	dirty = true
	var p: Vector3 = nest["pos"] + egg_offset(int(egg["slot"])) * 2.0
	p = w.terrain.clamp_to_play_area(p)
	var d := Dino.create(w.new_id(), nest["species"], GameConfig.HATCHLING_GROWTH, p)
	d.is_bot = true
	d.yaw = w.rng.randf_range(-PI, PI)
	d.pos.y = Movement.ground_y(w.terrain, p.x, p.z, d.body_height())
	w.dinos[d.id] = d
	return d


func _remove(nest: Dictionary) -> void:
	nests.erase(nest["id"])
	dirty = true


# ---------------------------------------------------------------- nascer no ninho

## O jogador morto escolheu "Nascer no ninho": vira filhote em cima do ovo pronto (continua
## valendo "morreu → recomeça jovem"). Devolve o dino novo, ou null se não tem ovo pronto.
func respawn_in_nest(w: WorldSim, player_name: String) -> Dino:
	var nest := nest_of(player_name)
	if nest.is_empty():
		return null
	var egg := ready_egg(nest)
	if egg.is_empty():
		return null
	nest["eggs"].erase(egg)
	dirty = true
	var d := w.respawn_player(player_name, nest["species"])
	var p: Vector3 = nest["pos"] + egg_offset(int(egg["slot"]))
	d.pos = Vector3(p.x, Movement.ground_y(w.terrain, p.x, p.z, d.body_height()), p.z)
	w.player_records[player_name] = {"alive": true, "dino": d.to_dict()}
	if nest["eggs"].is_empty():
		_remove(nest)
	return d


# ---------------------------------------------------------------- comer ovo

## Um passo comendo o ovo `egg` (de egg_in_reach). Depois de EGG_EAT_S segurando, o ovo some e
## vira comida (`egg_kg` da espécie). Devolve true quando terminou de comer.
func eat_egg(w: WorldSim, d: Dino, egg: Dictionary, dt: float) -> bool:
	var cur: Dictionary = eating.get(d.id, {})
	if cur.get("key", "") != egg["key"] or w.world_time - float(cur.get("at", -INF)) > 0.5:
		cur = {"key": egg["key"], "t": 0.0}
	cur["t"] = float(cur["t"]) + dt
	cur["at"] = w.world_time
	eating[d.id] = cur
	if float(cur["t"]) < GameConfig.EGG_EAT_S:
		return false
	eating.erase(d.id)
	var nest: Dictionary = nests.get(egg["nest"], {})
	var eaten := {}
	for e: Dictionary in nest.get("eggs", []):
		if int(e["slot"]) == int(egg["slot"]):
			eaten = e
	if eaten.is_empty():
		return false  # o ovo sumiu antes (chocou, outro comeu, o dono nasceu nele)
	nest["eggs"].erase(eaten)
	dirty = true
	var kg := float(Species.DATA[nest["species"]].get("egg_kg", 4.0))
	var stomach := d.stomach_kg()
	var room := (100.0 - d.hunger) / 100.0 * stomach
	d.hunger = minf(100.0, d.hunger + minf(kg, room) / stomach * 100.0)
	var owner: String = nest["owner"]
	if owner != "" and owner != d.player_name:
		var who := d.player_name if not d.is_bot else "um " + Species.display_name(d.species)
		_tell(owner, "Seu ninho foi atacado: %s comeu um ovo!" % who)
	if nest["eggs"].is_empty():
		_remove(nest)
	return true


# ---------------------------------------------------------------- bots

## Reposição de bot que vira ninho de bot (bot_nest_share das vezes, só com jogador no mundo,
## que é quando os ovos servem de comida pros carnívoros). Usa o mesmo lugar e a mesma espécie
## que a reposição escolheria (diretor de população: perto dos jogadores, fora da vista).
## Devolve true se virou ninho (aí não nasce bot agora).
func try_bot_nest(w: WorldSim) -> bool:
	if bot_nest_share <= 0.0 or w.players().is_empty():
		return false
	if w.rng.randf() >= bot_nest_share:
		return false
	var plan := w.director.pick_spawn(w)
	var species_id := w.choose_bot_species(String(plan.get("need", "")))
	for attempt in 3:
		var pos: Vector3 = plan["pos"] if plan.has("pos") else w._bot_spawn_point()
		if spot_error(w.terrain, pos) != "":
			# Procura chão plano ali perto, ainda fora da vista.
			for i in 8:
				var p := w.terrain.clamp_to_play_area(pos + Vector3(w.rng.randf_range(-12.0, 12.0), 0.0, w.rng.randf_range(-12.0, 12.0)))
				if spot_error(w.terrain, p) == "" and _min_player_dist(w, p) >= WorldSim.BOT_SPAWN_MIN_PLAYER_DIST:
					pos = p
					break
		if spot_error(w.terrain, pos) == "":
			var nest := build(w, "", species_id, pos)
			nest["bot_slot"] = true
			lay(w, nest)
			return true
		plan = w.director.pick_spawn(w)
	return false


static func _min_player_dist(w: WorldSim, p: Vector3) -> float:
	var m := INF
	for pl: Dino in w.players():
		m = minf(m, Movement.flat_distance(p, pl.pos))
	return m


# ---------------------------------------------------------------- dev (/nest, /eggs, /hatch)

## /eggs N: troca os ovos chocando do ninho do jogador por N novos (cria o ninho se não tiver).
func dev_eggs(w: WorldSim, d: Dino, count: int) -> int:
	var nest := nest_of(d.player_name)
	if nest.is_empty():
		nest = build(w, d.player_name, d.species, d.pos)
	nest["eggs"] = nest["eggs"].filter(func(e): return e["ready"])
	return lay(w, nest, clampi(count, 1, EGG_SLOTS))


## /hatch: os ovos do ninho do jogador (ou de todos, com owner "*") chocam agora.
func hatch_now(w: WorldSim, owner: String) -> int:
	var n := 0
	for nest: Dictionary in nests.values():
		if owner == "*" or nest["owner"] == owner:
			if incubating_count(nest) > 0:
				nest["hatch_at"] = w.world_time
				n += incubating_count(nest)
	_step_hatching(w)
	return n


# ---------------------------------------------------------------- rede e HUD

## O que o HUD mostra do ninho do jogador (vai no s_self_stats).
func status_of(w: WorldSim, d: Dino) -> Dictionary:
	var nest := nest_of(d.player_name)
	var out := {"eggs": -1, "ready": 0, "hatch": 0.0, "cooldown": lay_cooldown(w, d.player_name),
			"build": -1.0, "ask": 0.0, "ask_from": 0}
	if not nest.is_empty():
		out["eggs"] = nest["eggs"].size()
		out["ready"] = 0 if ready_egg(nest).is_empty() else 1
		if incubating_count(nest) > 0:
			out["hatch"] = maxf(0.0, float(nest["hatch_at"]) - w.world_time)
	if building.has(d.id):
		out["build"] = clampf(float(building[d.id]) / GameConfig.NEST_BUILD_S, 0.0, 1.0)
	var req: Dictionary = requests.get(d.player_name, {})
	if not req.is_empty():
		var asker := _player_dino(w, String(req["from"]))
		if asker != null:
			out["ask"] = maxf(0.0, float(req["until"]) - w.world_time)
			out["ask_from"] = asker.id
	return out


## Todos os ninhos, pro cliente desenhar (s_nests): id, posição, espécie (índice), dono,
## vagas com ovo e vagas com o ovo pronto pro dono.
func public_list() -> Array:
	var out := []
	for nest: Dictionary in nests.values():
		var slots := PackedInt32Array()
		var ready := PackedInt32Array()
		for e: Dictionary in nest["eggs"]:
			slots.append(int(e["slot"]))
			if e["ready"]:
				ready.append(int(e["slot"]))
		out.append({"id": nest["id"], "pos": nest["pos"], "sp": Species.index_of(nest["species"]),
				"owner": nest["owner"], "eggs": slots, "ready": ready})
	return out


## O ninho de um jogador, pro cliente (s_nests): tem ninho, quantos ovos e se tem ovo pronto
## (o botão "Nascer no ninho" da tela de morte).
func mine_of(player_name: String) -> Dictionary:
	var nest := nest_of(player_name)
	if nest.is_empty():
		return {"has_nest": false, "eggs": 0, "ready": false, "species": ""}
	return {"has_nest": true, "eggs": nest["eggs"].size(), "ready": not ready_egg(nest).is_empty(),
			"species": nest["species"]}


## "12:30" ou "1:42:10".
static func clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## Texto do HUD, uma coisa por linha: "Ninho: 3 ovos · chocam em 12:30", o ovo pronto pro dono
## e a recarga da postura.
static func status_text(eggs: int, ready: int, hatch_s: float, cooldown_s: float) -> String:
	var lines := PackedStringArray()
	if eggs >= 0:
		var incub := eggs - ready
		if incub > 0:
			lines.append("Ninho: %d %s · %s em %s" % [incub, "ovo" if incub == 1 else "ovos",
					"choca" if incub == 1 else "chocam", clock(hatch_s)])
		elif ready == 0:
			lines.append("Ninho vazio: R perto de um adulto")
		if ready > 0:
			lines.append("Ovo pronto: se morrer, nasce nele")
	if cooldown_s > 0.0:
		lines.append("Nova postura em %s" % clock(cooldown_s))
	return "\n".join(lines)


func _tell(player_name: String, text: String) -> void:
	if player_name != "":
		messages.append([player_name, text])


# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var list := []
	for nest: Dictionary in nests.values():
		var p: Vector3 = nest["pos"]
		var eggs := []
		for e: Dictionary in nest["eggs"]:
			eggs.append({"slot": int(e["slot"]), "ready": bool(e["ready"])})
		list.append({"id": nest["id"], "owner": nest["owner"], "species": nest["species"],
				"pos": [p.x, p.y, p.z], "eggs": eggs, "hatch_at": nest["hatch_at"],
				"laid": nest["laid"], "bot_slot": nest["bot_slot"]})
	return {"list": list, "lay_ready": lay_ready.duplicate()}


## Lê o que to_save gravou. Save sem ninhos (formato 4 ou antes) chega como {}: mundo sem ninhos.
func load_save(w: WorldSim, data: Dictionary) -> void:
	nests.clear()
	lay_ready.clear()
	bot_ready.clear()
	requests.clear()
	building.clear()
	eating.clear()
	for raw in data.get("list", []):
		if not (raw is Dictionary) or not Species.is_valid(String(raw.get("species", ""))):
			continue
		var id := int(raw.get("id", 0))
		if id <= 0 or nests.has(id):
			id = w.new_id()
		w.next_id = maxi(w.next_id, id + 1)
		var p: Array = raw.get("pos", [0.0, 0.0, 0.0])
		var eggs := []
		var used := {}
		for e in raw.get("eggs", []):
			if not (e is Dictionary):
				continue
			var slot := int(e.get("slot", -1))
			if slot >= 0 and slot < EGG_SLOTS and not used.has(slot):
				used[slot] = true
				eggs.append({"slot": slot, "ready": bool(e.get("ready", false))})
		nests[id] = {
			"id": id, "owner": String(raw.get("owner", "")), "species": String(raw["species"]),
			"pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "eggs": eggs,
			"hatch_at": float(raw.get("hatch_at", 0.0)), "laid": bool(raw.get("laid", not eggs.is_empty())),
			"bot_slot": bool(raw.get("bot_slot", false)),
		}
	var lr: Dictionary = data.get("lay_ready", {})
	for player_name in lr:
		lay_ready[String(player_name)] = float(lr[player_name])
	dirty = true
