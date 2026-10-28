extends RefCounted
## Códigos de resgate (scripts/net/codes.gd), recompensas (scripts/sim/rewards.gd), o que a
## conta ganha (Accounts.perks) e o boost de crescimento.


func test_codigo_gerado_legivel(t) -> void:
	var seen := {}
	for i in 200:
		var c := RedeemCodes.generate()
		seen[c] = true
		t.check(c.length() == 14 and c.begins_with("DINO-") and c[9] == "-", "formato DINO-XXXX-XXXX (%s)" % c)
		for ch in c.substr(5).replace("-", ""):
			if not RedeemCodes.ALPHABET.contains(ch):
				t.check(false, "letra fora do alfabeto em %s" % c)
	t.check(seen.size() == 200, "200 códigos, todos diferentes")
	for bad in ["0", "O", "1", "I"]:
		t.check(not RedeemCodes.ALPHABET.contains(bad), "sem %s (confunde)" % bad)


func test_digitado_de_qualquer_jeito(t) -> void:
	t.check(RedeemCodes.normalize("dino-abcd-2345") == "DINO-ABCD-2345", "minúsculas")
	t.check(RedeemCodes.normalize(" DINOABCD2345 ") == "DINO-ABCD-2345", "sem traços")
	t.check(RedeemCodes.normalize("abcd 2345") == "DINO-ABCD-2345", "sem o DINO")


func test_resgatar_uma_vez_por_conta(t) -> void:
	var c := RedeemCodes.new()
	var code := c.create("acesso_beta", "", 2, 0, "Tux", 0.0)
	var r: Dictionary = c.check(code.to_lower(), "Bob", 1.0)
	t.check(r["result"] == RedeemCodes.Result.OK, "bob resgata")
	c.consume(code, "Bob")
	t.check(c.check(code, "bob", 2.0)["result"] == RedeemCodes.Result.ALREADY, "bob não resgata de novo")
	t.check(c.check(code, "Ana", 3.0)["result"] == RedeemCodes.Result.OK, "ana resgata (2 usos)")
	c.consume(code, "Ana")
	t.check(c.check(code, "Eva", 4.0)["result"] == RedeemCodes.Result.USED_UP, "eva: usos esgotados")
	t.check(int(c.codes[code]["uses_left"]) == 0, "usos zerados")
	t.check(c.check("DINO-AAAA-2222", "Eva", 5.0)["result"] == RedeemCodes.Result.NOT_FOUND, "código que não existe")


func test_validade_e_cancelar(t) -> void:
	var c := RedeemCodes.new()
	var code := c.create("acesso_beta", "", 5, 2, "Tux", 1000.0)
	t.check(c.check(code, "Bob", 1000.0 + 86400.0)["result"] == RedeemCodes.Result.OK, "dentro da validade")
	t.check(c.check(code, "Bob", 1000.0 + 3.0 * 86400.0)["result"] == RedeemCodes.Result.EXPIRED, "depois de 2 dias venceu")
	var other := c.create("acesso_beta", "", 5, 0, "Tux", 0.0)
	t.check(c.revoke(other), "cancela")
	t.check(not c.revoke(other), "não cancela duas vezes")
	t.check(c.check(other, "Bob", 1.0)["result"] == RedeemCodes.Result.REVOKED, "cancelado não vale")


func test_chutar_codigos_bloqueia(t) -> void:
	var c := RedeemCodes.new()
	var code := c.create("acesso_beta", "", 1, 0, "Tux", 0.0)
	for i in RedeemCodes.MAX_FAILS:
		t.check(c.check("DINO-ZZZZ-%04d" % (2222 + i), "Chutador", 10.0)["result"] == RedeemCodes.Result.NOT_FOUND,
				"chute %d" % (i + 1))
	t.check(c.check(code, "Chutador", 11.0)["result"] == RedeemCodes.Result.LOCKED, "bloqueado até com o código certo")
	t.check(c.wait_seconds("chutador", 11.0) > 50.0, "espera quase um minuto")
	t.check(c.check(code, "Outro", 11.0)["result"] == RedeemCodes.Result.OK, "outra conta não é bloqueada")
	t.check(c.check(code, "Chutador", 10.0 + RedeemCodes.FAIL_WINDOW_S + 1.0)["result"] == RedeemCodes.Result.OK,
			"depois da janela volta a valer")


func test_codigos_salvar_e_carregar(t) -> void:
	var c := RedeemCodes.new()
	var code := c.create("liberar_especie", "triceratops", 3, 7, "Marcelo", 500.0)
	c.consume(code, "Bob")
	var d := RedeemCodes.new()
	d.load_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	var e: Dictionary = d.codes.get(code, {})
	t.check(not e.is_empty(), "código voltou")
	t.check(int(e["uses_left"]) == 2 and String(e["param"]) == "triceratops" and String(e["created_by"]) == "Marcelo",
			"usos, parâmetro e criador")
	t.check(d.check(code, "bob", 600.0)["result"] == RedeemCodes.Result.ALREADY, "lembra quem já usou")
	t.check(d.list_for_admin().size() == 1, "aparece na lista do admin")


func test_recompensas_validas(t) -> void:
	t.check(Rewards.validate("boost_crescimento", "60") == "", "boost de 60 min")
	t.check(Rewards.validate("boost_crescimento", "0") != "", "boost de 0 min não")
	t.check(Rewards.validate("boost_crescimento", "abc") != "", "boost sem número não")
	t.check(Rewards.validate("liberar_especie", "triceratops") == "", "liberar espécie que existe")
	t.check(Rewards.validate("liberar_especie", "trex") != "", "espécie que não existe não")
	t.check(Rewards.validate("acesso_beta", "") == "", "acesso beta")
	t.check(Rewards.validate("level", "10") != "" and Rewards.validate("adulto", "") != "",
			"não existe level nem virar adulto (design, seção 9)")


func test_recompensas_entregam(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 0)
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	var perks := {"beta": false, "species": [], "codes": []}
	Rewards.apply("acesso_beta", "", "bob", w, perks)
	t.check(perks["beta"], "beta liberado")
	Rewards.apply("liberar_especie", "triceratops", "bob", w, perks)
	Rewards.apply("liberar_especie", "triceratops", "bob", w, perks)
	t.check(Array(perks["species"]) == ["triceratops"], "espécie liberada uma vez só")
	Rewards.apply("boost_crescimento", "60", "bob", w, perks)
	Rewards.apply("boost_crescimento", "30", "bob", w, perks)
	t.near(bob.growth_boost_s, 90.0 * 60.0, 0.01, "boost soma tempo")


func test_especie_trancada_ou_beta(t) -> void:
	var locked := {"name": "Rex", "locked": true}
	var beta := {"name": "Spino", "beta": true}
	var none := {"beta": false, "species": []}
	t.check(Species.choice_error_for(locked, "rex", none) != "", "trancada sem código: não")
	t.check(Species.choice_error_for(locked, "rex", {"beta": false, "species": ["rex"]}) == "", "liberada: sim")
	t.check(Species.choice_error_for(beta, "spino", none) != "", "beta sem acesso: não")
	t.check(Species.choice_error_for(beta, "spino", {"beta": true, "species": []}) == "", "beta com acesso: sim")
	for id in Species.IDS:
		t.check(Species.choice_error(id, none) == "", "%s continua livre pra todo mundo" % id)


func test_conta_antiga_carrega_sem_perder_senha(t) -> void:
	var a := Accounts.new()
	var k := Accounts.client_key("Tux", "dino123")
	a.login("Tux", k, 0.0)
	var old: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	old["format"] = 1
	for n in old["accounts"]:
		old["accounts"][n].erase("perks")
	var b := Accounts.new()
	b.load_dict(old)
	t.check(b.login("tux", k, 1.0) == Accounts.Result.OK, "senha da conta antiga continua valendo")
	t.check(b.perks_summary("Tux") == {"beta": false, "species": []}, "começa sem nada ganho")
	b.perks("Tux")["beta"] = true
	b.mark_redeemed("Tux", "DINO-ABCD-2345")
	var k2 := Accounts.client_key("Tux", "nova123")
	t.check(b.change_key("Tux", k, k2, 2.0) == Accounts.Result.OK, "troca a senha")
	t.check(b.perks_summary("tux")["beta"], "trocar a senha não apaga o que a conta ganhou")
	var c := Accounts.new()
	c.load_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	t.check(Array(c.perks("Tux")["codes"]) == ["DINO-ABCD-2345"], "códigos usados ficam no arquivo")


func test_boost_cresce_50_por_cento_mais_rapido(t) -> void:
	var plain := Dino.create(1, "carnotaurus", 0.3, Vector3.ZERO)
	var boosted := Dino.create(2, "carnotaurus", 0.3, Vector3.ZERO)
	boosted.growth_boost_s = 3600.0
	for i in 60:
		Metabolism.step(plain, 1.0)
		Metabolism.step(boosted, 1.0)
	var gp := plain.growth - 0.3
	var gb := boosted.growth - 0.3
	t.check(gp > 0.0, "cresceu sem boost")
	t.near(gb / gp, GameConfig.GROWTH_BOOST_MULT, 0.001, "com boost cresce 50% mais rápido")
	t.near(boosted.growth_boost_s, 3600.0 - 60.0, 0.001, "gastou 60 s de boost")
	var short := Dino.create(3, "carnotaurus", 0.3, Vector3.ZERO)
	short.growth_boost_s = 10.0
	for i in 60:
		Metabolism.step(short, 1.0)
	t.near(short.growth_boost_s, 0.0, 0.0001, "o boost acaba")
	t.near((short.growth - 0.3) / gp, (10.0 * GameConfig.GROWTH_BOOST_MULT + 50.0) / 60.0, 0.001,
			"10 s com boost e 50 s sem")
	var adult := Dino.create(4, "carnotaurus", 1.0, Vector3.ZERO)
	adult.growth_boost_s = 100.0
	Metabolism.step(adult, 10.0)
	t.near(adult.growth_boost_s, 100.0, 0.0001, "adulto não gasta boost")


func test_boost_congela_fora_e_passa_pra_proxima_vida(t) -> void:
	var w := WorldSim.new(GameConfig.WORLD_SEED, 0)
	var bob: Dino = w.login_player("bob", "dryosaurus")["dino"]
	w.login_player("alice", "carnotaurus")
	w.add_growth_boost("bob", 600.0)
	w.logout_player(bob.id)
	var dt := 1.0 / GameConfig.SIM_HZ
	for i in int(60.0 / dt):
		w.step(dt)
	t.near(w.growth_boost_of("bob"), 600.0, 0.0001, "fora do jogo o boost não gasta")
	w.add_growth_boost("bob", 60.0)
	var back: Dino = w.login_player("bob", "dryosaurus")["dino"]
	t.near(back.growth_boost_s, 660.0, 0.0001, "volta com o boost (e o que ganhou fora)")
	var json := JSON.stringify(w.to_save())
	var w2 := WorldSim.new(GameConfig.WORLD_SEED, 0)
	w2.load_save(JSON.parse_string(json))
	t.near(w2.growth_boost_of("bob"), 660.0, 0.0001, "o boost vai pro save")
	back.health = 0.0
	w.step(dt)
	t.check(not w.dinos.has(back.id), "bob morreu")
	var reborn := w.respawn_player("bob", "carnotaurus")
	t.check(reborn.growth_boost_s > 600.0, "o boost passa pra próxima vida (%.0f s)" % reborn.growth_boost_s)
	t.near(reborn.growth, GameConfig.PLAYER_START_GROWTH, 0.0001, "mas recomeça jovem")
