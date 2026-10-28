extends RefCounted
## Aviso de versão nova (scripts/client/update_check.gd), sem internet.


func test_compara_versoes(t) -> void:
	t.check(UpdateCheck.is_newer("v0.3.0", "0.2.1"), "0.3.0 é mais nova que 0.2.1")
	t.check(UpdateCheck.is_newer("v0.2.10", "0.2.9"), "compara número, não texto (10 > 9)")
	t.check(UpdateCheck.is_newer("v1.0", "0.9.9"), "versão com duas partes")
	t.check(not UpdateCheck.is_newer("v0.2.1", "0.2.1"), "a mesma não é nova")
	t.check(not UpdateCheck.is_newer("v0.2.0", "0.2.1"), "mais velha não é nova")
	t.check(not UpdateCheck.is_newer("lixo", "0.2.1"), "texto estranho não é nova")
	t.check(UpdateCheck.parse_version("v0.2.1") == [0, 2, 1], "lê v0.2.1")


func test_le_a_resposta_do_github(t) -> void:
	var ok := UpdateCheck.latest_from_json(JSON.stringify({
		"tag_name": "v0.3.0", "html_url": "https://github.com/TuxGames/the-isle/releases/tag/v0.3.0",
		"draft": false, "prerelease": false}))
	t.check(ok.get("tag") == "v0.3.0", "pega a tag")
	t.check(String(ok.get("url")).ends_with("/v0.3.0"), "pega o link da release")
	t.check(UpdateCheck.latest_from_json("{não é json").is_empty(), "resposta quebrada: nada")
	t.check(UpdateCheck.latest_from_json(JSON.stringify({"message": "Not Found"})).is_empty(), "sem release: nada")
	t.check(UpdateCheck.latest_from_json(JSON.stringify({"tag_name": "v9.0.0", "prerelease": true})).is_empty(),
			"pré-lançamento não conta")
	var odd := UpdateCheck.latest_from_json(JSON.stringify({"tag_name": "v0.3.0", "html_url": "https://outro.site/x"}))
	t.check(odd.get("url") == GameConfig.RELEASES_PAGE, "link de fora do GitHub vira a página de downloads")
