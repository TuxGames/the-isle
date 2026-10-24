extends RefCounted
## Contas (scripts/net/accounts.gd): nome + senha, sem rede.


func test_pbkdf2_bate_com_a_referencia(t) -> void:
	# Valores de referência do PBKDF2-HMAC-SHA256 (senha "password", sal "salt").
	var p := "password".to_utf8_buffer()
	var s := "salt".to_utf8_buffer()
	t.check(Accounts.pbkdf2_sha256(p, s, 1).hex_encode() == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "1 iteração")
	t.check(Accounts.pbkdf2_sha256(p, s, 2).hex_encode() == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "2 iterações")
	t.check(Accounts.pbkdf2_sha256(p, s, 4096).hex_encode() == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "4096 iterações")


func test_chave_do_cliente(t) -> void:
	var k := Accounts.client_key("Tux", "dino123")
	t.check(Accounts.is_valid_key(k), "64 caracteres hex")
	t.check(k == Accounts.client_key(" tux ", "dino123"), "nome sem diferença de maiúscula/espaço")
	t.check(k != Accounts.client_key("Marcelo", "dino123"), "mesma senha, outro nome: outra chave")
	t.check(k != Accounts.client_key("Tux", "dino124"), "outra senha: outra chave")
	t.check(not k.contains("dino123"), "a senha não aparece na chave")


func test_primeiro_login_cria_a_conta(t) -> void:
	var a := Accounts.new()
	var k := Accounts.client_key("Tux", "dino123")
	t.check(a.login("Tux", k, 0.0) == Accounts.Result.CREATED, "nome novo cria a conta")
	t.check(a.login("Tux", k, 1.0) == Accounts.Result.OK, "mesma senha entra")
	t.check(a.login("tux", k, 2.0) == Accounts.Result.OK, "nome sem diferença de maiúscula")
	t.check(a.display_name("tux") == "Tux", "volta o nome como foi cadastrado")
	t.check(a.login("Tux", Accounts.client_key("Tux", "errada"), 3.0) == Accounts.Result.WRONG, "senha errada")
	t.check(a.login("Tux", "abc", 4.0) == Accounts.Result.BAD_KEY, "chave mal formada")
	var raw := JSON.stringify(a.to_dict())
	t.check(not raw.contains(k), "o arquivo não guarda a chave que o cliente manda")


func test_erros_seguidos_bloqueiam(t) -> void:
	var a := Accounts.new()
	var k := Accounts.client_key("Bob", "certa1")
	a.login("Bob", k, 0.0)
	var bad := Accounts.client_key("Bob", "errada")
	for i in Accounts.MAX_FAILS:
		t.check(a.login("Bob", bad, 10.0) == Accounts.Result.WRONG, "erro %d" % (i + 1))
	t.check(a.login("Bob", k, 11.0) == Accounts.Result.LOCKED, "bloqueado até com a senha certa")
	t.near(a.lock_seconds_left("bob", 11.0), Accounts.LOCK_S - 1.0, 0.001, "tempo de bloqueio")
	t.check(a.login("Bob", k, 10.0 + Accounts.LOCK_S + 0.1) == Accounts.Result.OK, "depois do bloqueio entra")
	t.check(a.login("Bob", bad, 100.0) == Accounts.Result.WRONG and a.lock_seconds_left("Bob", 100.0) == 0.0,
			"acertar zera a contagem de erros")


func test_trocar_senha(t) -> void:
	var a := Accounts.new()
	var old := Accounts.client_key("Ana", "velha1")
	var new := Accounts.client_key("Ana", "nova12")
	a.login("Ana", old, 0.0)
	t.check(a.change_key("Ana", Accounts.client_key("Ana", "chute"), new, 1.0) == Accounts.Result.WRONG,
			"sem a senha atual não troca")
	t.check(a.change_key("Ana", old, new, 2.0) == Accounts.Result.OK, "troca com a senha atual")
	t.check(a.login("Ana", old, 3.0) == Accounts.Result.WRONG, "a senha velha não entra mais")
	t.check(a.login("Ana", new, 4.0) == Accounts.Result.OK, "a nova entra")
	t.check(a.change_key("Zé", old, new, 5.0) == Accounts.Result.WRONG, "nome sem conta não troca")


func test_salvar_e_carregar(t) -> void:
	var a := Accounts.new()
	var k := Accounts.client_key("Tux", "dino123")
	a.login("Tux", k, 0.0)
	var b := Accounts.new()
	b.load_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	t.check(b.has_account("TUX"), "conta veio do arquivo")
	t.check(b.login("Tux", k, 1.0) == Accounts.Result.OK, "a senha continua valendo")
	t.check(b.login("Tux", Accounts.client_key("Tux", "outra"), 2.0) == Accounts.Result.WRONG, "e a errada continua errada")
	var c := Accounts.new()
	c.login("Tux", k, 0.0)
	t.check(String(c.accounts["tux"]["salt"]) != String(a.accounts["tux"]["salt"]), "cada conta tem um sal próprio")
