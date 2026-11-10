extends RefCounted
## Números não finitos (NaN, infinito) não podem entrar no mundo nem derrubar quem lê o save.
##
## O caminho do estrago era: um c_state com NaN passava pelo clampf (que devolve NaN) e ficava em
## Dino.pos; o snapshot levava pra todo mundo; o JSON gravava como null; e na volta o float(null)
## abortava o Dino.from_dict, então o jogador não entrava mais.
##
## GameServer, GameClient e DinoView usam o autoload Net, que só existe com o jogo rodando: por
## isso são carregados com load() dentro do teste em vez de pelo nome da classe.

const SERVER_SCRIPT := "res://scripts/net/game_server.gd"
const CLIENT_SCRIPT := "res://scripts/client/game_client.gd"
const VIEW_SCRIPT := "res://scripts/client/dino_view.gd"


func _world(bots := 0) -> WorldSim:
	return WorldSim.new(GameConfig.WORLD_SEED, bots)


## O save como ele fica no disco e volta: NaN vira null, infinito vira 1e99999 (e volta infinito).
func _through_json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _in_map(w: WorldSim, p: Vector3) -> bool:
	return p.is_finite() and p.x >= w.terrain.play_min and p.x <= w.terrain.play_max \
			and p.z >= w.terrain.play_min and p.z <= w.terrain.play_max


func _all_finite(data: PackedFloat32Array) -> bool:
	for f in data:
		if not is_finite(f):
			return false
	return true


# ---------------------------------------------------------------- Dino.from_dict

func test_from_dict_com_posicao_que_nao_presta(t) -> void:
	var good: Dino = Dino.from_dict({"species": "dryosaurus", "pos": [10.0, 2.0, 30.0], "yaw": 1.25})
	t.check(good != null, "posição boa: carrega")
	if good == null:
		return
	t.check(good.pos == Vector3(10.0, 2.0, 30.0) and not good.needs_relocate, "posição boa fica como veio")
	t.near(good.yaw, 1.25, 0.0001, "yaw bom fica como veio")

	var cases := {
		"null (o NaN depois do JSON)": [null, 2.0, null],
		"NaN": [NAN, 2.0, NAN],
		"infinito": [INF, 2.0, -INF],
		"altura NaN": [10.0, NAN, 30.0],
		"faltando número": [10.0, 2.0],
		"texto": ["a", "b", "c"],
		"não é lista": "aqui",
		"null no lugar da lista": null,
	}
	for label in cases:
		var d: Dino = Dino.from_dict({"species": "dryosaurus", "growth": 0.4, "pos": cases[label]})
		t.check(d != null, "posição %s: não quebra" % label)
		if d == null:
			continue
		t.check(d.needs_relocate, "posição %s: marcado pra ganhar um lugar novo" % label)
		t.check(d.pos.is_finite(), "posição %s: nada não finito fica no dino" % label)
		t.near(d.growth, 0.4, 0.0001, "posição %s: o resto do dino vem igual" % label)
	var missing: Dino = Dino.from_dict({"species": "dryosaurus"})
	t.check(missing != null and missing.needs_relocate, "sem o campo pos: marcado pra ganhar um lugar novo")


func test_from_dict_com_yaw_e_outros_numeros_que_nao_prestam(t) -> void:
	for bad in [null, NAN, INF, -INF, "norte"]:
		var d: Dino = Dino.from_dict({"species": "dryosaurus", "pos": [1.0, 2.0, 3.0], "yaw": bad})
		t.check(d != null, "yaw %s: não quebra" % str(bad))
		if d == null:
			continue
		t.check(d.yaw == 0.0, "yaw %s vira 0" % str(bad))
		t.check(not d.needs_relocate and d.pos == Vector3(1.0, 2.0, 3.0), "yaw %s: a posição boa fica" % str(bad))
	# Finito mas enorme: viraria infinito nos floats de 32 bits do snapshot.
	var huge: Dino = Dino.from_dict({"species": "dryosaurus", "pos": [1.0, 2.0, 3.0], "yaw": 1e300})
	t.check(huge != null and absf(huge.yaw) <= PI, "yaw enorme volta pra faixa de -PI a PI")

	# Os outros números caem no mesmo valor de quando o campo falta.
	var d2: Dino = Dino.from_dict({"species": "dryosaurus", "pos": [1.0, 2.0, 3.0], "id": null,
			"growth": null, "health": null, "hunger": INF, "thirst": NAN, "stamina": null,
			"growth_boost_s": null, "injuries": {"fratura": null, "sangramento": INF, "mordida_funda": 40.0}})
	t.check(d2 != null, "números null/não finitos: não quebra")
	if d2 == null:
		return
	t.check(d2.id == 0 and d2.growth == 1.0, "id e crescimento no padrão")
	t.near(d2.health, d2.max_health(), 0.0001, "vida no padrão (cheia)")
	t.check(d2.hunger == 100.0 and d2.thirst == 100.0 and d2.stamina == 100.0, "fome, sede e fôlego no padrão")
	t.check(d2.growth_boost_s == 0.0, "boost no padrão")
	t.check(d2.injuries.size() == 1 and d2.injuries.has(Injuries.DEEP), "ferimento com tempo não finito some, o bom fica")


# ---------------------------------------------------------------- save estragado

func test_jogador_com_posicao_estragada_no_save_entra_num_lugar_novo(t) -> void:
	var w := _world()
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	bob.growth = 0.6
	bob.health = bob.max_health() * 0.5
	bob.hunger = 37.0
	# O que o servidor guardava antes da correção quando chegava um c_state com NaN.
	bob.pos = Vector3(NAN, bob.pos.y, NAN)
	bob.yaw = NAN
	w.logout_player(bob.id)
	var data := _through_json(w.to_save())
	t.check(data["players"]["bob"]["dino"]["pos"][0] == null, "o NaN foi pro save como null")

	var w2 := _world()
	w2.load_save(data)
	var back: Dictionary = w2.login_player("bob", "carnotaurus")
	t.check(back.has("dino") and back["dino"] != null, "o bob consegue entrar")
	if not back.has("dino") or back["dino"] == null:
		return
	var b2: Dino = back["dino"]
	t.check(back["restored"] and b2.species == "dryosaurus", "com o dino dele (não recomeça)")
	t.near(b2.growth, 0.6, 0.0001, "mesmo crescimento")
	t.near(b2.health, b2.max_health() * 0.5, 0.01, "mesma vida")
	t.near(b2.hunger, 37.0, 0.0001, "mesma fome")
	t.check(_in_map(w2, b2.pos), "num lugar de verdade dentro do mapa (%s)" % b2.pos)
	t.near(b2.pos.y, Movement.ground_y(w2.terrain, b2.pos.x, b2.pos.z, b2.body_height()), 0.01, "no chão")
	t.check(is_finite(b2.yaw), "yaw finito")
	t.check(not b2.needs_relocate, "a marca de lugar novo foi desligada")
	t.check(_all_finite(load(SERVER_SCRIPT).build_snapshot(w2)), "snapshot só com números finitos")
	# O próximo save já sai limpo.
	t.check(not JSON.stringify(w2.to_save()).contains("null"), "o save seguinte não tem mais null")


func test_bot_carcaca_e_ninho_estragados_nao_abortam_o_load(t) -> void:
	var w := _world()
	var bob: Dino = w.login_player("bob", "triceratops")["dino"]
	bob.growth = 0.7
	var good_bot := w.spawn_bot("dryosaurus", 1.0)
	var bad_bot := w.spawn_bot("carnotaurus", 0.8)
	var good_carcass := w.new_id()
	var bad_carcass := w.new_id()
	for cid in [good_carcass, bad_carcass]:
		w.carcasses[cid] = {"id": cid, "species": "dryosaurus", "growth": 1.0, "pos": good_bot.pos,
				"yaw": 0.3, "meat": 30.0, "meat_max": 30.0, "t": w.world_time}
	var good_nest: Dictionary = w.nests.build(w, "", "dryosaurus", good_bot.pos)
	var bad_nest: Dictionary = w.nests.build(w, "", "dryosaurus", good_bot.pos + Vector3(20, 0, 0))
	# Estraga o que um dino com NaN estragava: ele mesmo, a carcaça dele e o ninho que ele fez.
	bad_bot.pos = Vector3(NAN, 0.0, NAN)
	bad_bot.yaw = NAN
	w.carcasses[bad_carcass]["pos"] = Vector3(NAN, 0.0, NAN)
	bad_nest["pos"] = Vector3(NAN, 0.0, NAN)
	w.logout_player(bob.id)
	var data := _through_json(w.to_save())

	var w2 := _world()
	w2.load_save(data)
	# Antes, o float(null) da carcaça abortava o load_save no meio, antes de ler os jogadores.
	t.check(w2.player_records.has("bob"), "o registro do jogador carregou")
	t.check(w2.bot_count() == 2, "os dois bots continuam no mundo (%d)" % w2.bot_count())
	var moved: Dino = w2.dinos.get(bad_bot.id)
	t.check(moved != null, "o bot estragado carregou")
	if moved != null:
		t.check(_in_map(w2, moved.pos) and is_finite(moved.yaw), "num lugar novo de verdade (%s)" % moved.pos)
		t.check(moved.species == "carnotaurus" and absf(moved.growth - 0.8) < 0.0001, "o mesmo bot")
	var kept: Dino = w2.dinos.get(good_bot.id)
	t.check(kept != null and kept.pos.distance_to(good_bot.pos) < 0.001, "o bot bom ficou onde estava")
	t.check(w2.carcasses.has(good_carcass) and not w2.carcasses.has(bad_carcass), "só a carcaça boa carregou")
	t.check(w2.nests.nests.has(good_nest["id"]) and not w2.nests.nests.has(bad_nest["id"]), "só o ninho bom carregou")
	for i in 40:
		w2.step(1.0 / GameConfig.SIM_HZ)
	t.check(_all_finite(load(SERVER_SCRIPT).build_snapshot(w2)), "snapshot só com números finitos depois de 2 s de mundo")
	var back: Dictionary = w2.login_player("bob", "dryosaurus")
	t.check(back.get("restored", false), "e o jogador volta com o dino dele")


# ---------------------------------------------------------------- servidor (c_state)

func test_servidor_ignora_c_state_nao_finito(t) -> void:
	var gs = load(SERVER_SCRIPT).new()
	gs.sim = _world()
	var bob: Dino = gs.sim.login_player("bob", "dryosaurus")["dino"]
	gs.peers[7] = {"name": "bob", "dino_id": bob.id}
	# Uma posição boa primeiro, pra ter com o que comparar.
	var start: Vector3 = gs.sim.terrain.clamp_to_play_area(bob.pos + Vector3(2.0, 0.0, 1.0))
	gs.on_state(7, bob.client_seq, start, 0.5, Net.CF_MOVING)
	var pos0 := bob.pos
	t.check(Movement.flat_distance(pos0, start) < 0.001, "posição boa é aceita")
	t.near(bob.yaw, 0.5, 0.0001, "yaw bom é aceito")

	var bad := [
		["posição NaN", Vector3(NAN, 0.0, NAN), 1.0],
		["só o x NaN", Vector3(NAN, 0.0, start.z), 1.0],
		["altura NaN", Vector3(start.x, NAN, start.z), 1.0],
		["posição infinita", Vector3(INF, 0.0, -INF), 1.0],
		["yaw NaN", start + Vector3(1.0, 0.0, 0.0), NAN],
		["yaw infinito", start + Vector3(1.0, 0.0, 0.0), INF],
		["yaw menos infinito", start + Vector3(1.0, 0.0, 0.0), -INF],
	]
	for c in bad:
		gs.on_state(7, bob.client_seq, c[1], c[2], Net.CF_MOVING | Net.CF_SPRINT)
		t.check(bob.pos == pos0, "%s: o dino fica onde estava (%s)" % [c[0], bob.pos])
		t.near(bob.yaw, 0.5, 0.0001, "%s: o yaw fica como estava" % c[0])
		t.check(is_finite(bob.moving_speed), "%s: velocidade finita" % c[0])
	t.check(_all_finite(gs.build_snapshot(gs.sim)), "snapshot só com números finitos")
	t.check(not JSON.stringify(gs.sim.to_save()).contains("null"), "nada de null no save")

	# Depois de ignorar os pacotes ruins o jogador continua andando normalmente.
	var next: Vector3 = gs.sim.terrain.clamp_to_play_area(start + Vector3(1.5, 0.0, 0.0))
	gs.on_state(7, bob.client_seq, next, 7.0, Net.CF_MOVING)
	t.check(Movement.flat_distance(bob.pos, next) < 0.001, "o próximo pacote bom é aceito")
	t.check(absf(bob.yaw) <= PI, "yaw fora da faixa é trazido pra -PI a PI")
	gs.free()


# ---------------------------------------------------------------- comandos de dev

func test_time_nao_aceita_salto_infinito(t) -> void:
	var w := _world()
	var before := w.world_time
	for bad in ["+1e999h", "+1e305d", "+1e30"]:
		var reply := w.climate.dev_command(w, PackedStringArray(["/time", bad]))
		t.check(reply.begins_with("Uso:"), "/time %s é recusado (\"%s\")" % [bad, reply.substr(0, 20)])
		t.check(w.world_time == before, "/time %s não mexe no tempo do mundo" % bad)
	w.climate.dev_command(w, PackedStringArray(["/time", "+2h"]))
	t.near(w.world_time, before + 7200.0, 0.001, "um salto normal continua valendo")


# ---------------------------------------------------------------- cliente

func test_cliente_ignora_entidade_nao_finita(t) -> void:
	var client = load(CLIENT_SCRIPT).new()
	client.in_game = true
	client.my_id = 1
	client.my_species = "carnotaurus"
	client.my_pos = Vector3(100.0, 5.0, 100.0)
	var tri := Species.index_of("triceratops")
	var entity := func(id: int, x: float, yaw: float) -> Array:
		return [id, tri, 1.0, x, 5.0, 100.5, yaw, Net.SF_PLAYER]
	# 2 chega bom; 3 com posição NaN; 4 com yaw infinito.
	var snap := PackedFloat32Array(entity.call(2, 100.5, 0.0) + entity.call(3, NAN, 0.0) + entity.call(4, 101.0, INF))
	client._on_snapshot(snap)
	t.check(client.views.has(2), "a entidade boa aparece")
	t.check(not client.views.has(3) and not client.views.has(4), "as de posição ou yaw não finitos são ignoradas")

	# O bicho 2, que já estava na tela, passa a vir com NaN: some em vez de ficar com NaN.
	client._on_snapshot(PackedFloat32Array(entity.call(2, NAN, 0.0)))
	t.check(not client.views.has(2), "a que passa a vir com NaN some")

	# Mesmo com um bicho de posição NaN na lista (não devia acontecer), o meu dino não pega o NaN.
	var ghost = load(VIEW_SCRIPT).create(9, "triceratops", 1.0)
	client.add_child(ghost)
	ghost.position = Vector3(NAN, 5.0, NAN)
	client.views[9] = ghost
	client._push_out_of_others()
	t.check(client.my_pos == Vector3(100.0, 5.0, 100.0), "bicho com NaN não empurra o meu dino (%s)" % client.my_pos)
	# E um bicho bom em cima de mim continua empurrando.
	ghost.position = Vector3(100.2, 5.0, 100.0)
	client._push_out_of_others()
	t.check(client.my_pos.is_finite() and client.my_pos.x < 100.0, "bicho bom continua empurrando (%s)" % client.my_pos)
	client.free()


func test_dino_view_ignora_alvo_nao_finito(t) -> void:
	var v = load(VIEW_SCRIPT).create(5, "dryosaurus", 1.0)
	v.set_target(Vector3(10.0, 2.0, 30.0), 0.7, Net.SF_MOVING)
	for c in [[Vector3(NAN, 2.0, 30.0), 0.1], [Vector3(10.0, INF, 30.0), 0.1], [Vector3(11.0, 2.0, 31.0), NAN],
			[Vector3(11.0, 2.0, 31.0), INF]]:
		v.set_target(c[0], c[1], 0)
		t.check(v.target_pos == Vector3(10.0, 2.0, 30.0) and v.position == Vector3(10.0, 2.0, 30.0),
				"alvo %s / yaw %s: fica onde estava" % [c[0], c[1]])
		t.check(v.target_yaw == 0.7 and v.flags == Net.SF_MOVING, "alvo %s / yaw %s: yaw e flags não mudam" % [c[0], c[1]])
	v.set_target(Vector3(11.0, 2.0, 31.0), 0.9, 0)
	t.check(v.target_pos == Vector3(11.0, 2.0, 31.0) and v.target_yaw == 0.9, "o próximo alvo bom é aceito")
	v.free()
