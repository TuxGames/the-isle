class_name UpdateCheck
extends Node
## Confere no GitHub se saiu versão nova do jogo (a última Release) e avisa com
## `update_available`. Sem internet ou com qualquer erro, fica quieto: o jogo segue normal.

signal update_available(tag: String, url: String)

const TIMEOUT_S := 8.0

var _http: HTTPRequest


## Começa a conferência. `fake_latest` (ex.: "v9.9.9") pula a internet, pros prints e testes.
func start(fake_latest: String = "") -> void:
	if fake_latest != "":
		_report({"tag": fake_latest, "url": GameConfig.RELEASES_PAGE})
		return
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: DinoSurvival/%s" % GameConfig.VERSION,
	])
	if _http.request(GameConfig.RELEASES_API, headers) != OK:
		_http.queue_free()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	_report(latest_from_json(body.get_string_from_utf8()))


func _report(latest: Dictionary) -> void:
	if not latest.is_empty() and is_newer(String(latest["tag"]), GameConfig.VERSION):
		update_available.emit(String(latest["tag"]), String(latest["url"]))


## {"tag", "url"} da resposta do GitHub (releases/latest), ou {} se não der pra entender.
static func latest_from_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("tag_name"):
		return {}
	if bool(data.get("draft", false)) or bool(data.get("prerelease", false)):
		return {}
	var url := String(data.get("html_url", GameConfig.RELEASES_PAGE))
	if not url.begins_with("https://github.com/"):
		url = GameConfig.RELEASES_PAGE
	return {"tag": String(data["tag_name"]), "url": url}


## "v0.2.1" ou "0.2.1" → [0, 2, 1]. Parte que não é número vira 0.
static func parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	for part in v.strip_edges().trim_prefix("v").split("."):
		out.append(int(part) if part.is_valid_int() else 0)
	while out.size() < 3:
		out.append(0)
	return out


## Se `latest` é uma versão mais nova que `current`.
static func is_newer(latest: String, current: String) -> bool:
	var a := parse_version(latest)
	var b := parse_version(current)
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false
