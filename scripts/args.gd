class_name Args
extends RefCounted
## Lê os argumentos de linha de comando depois do "--".
## Exemplo: godot --headless -- --server --port=7777 --bots=30
## vira {"server": "", "port": "7777", "bots": "30"}.


static func parse(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq := body.find("=")
		if eq == -1:
			out[body] = ""
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


static func current() -> Dictionary:
	return parse(OS.get_cmdline_user_args())
