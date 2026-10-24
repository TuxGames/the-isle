extends Node
## Ponto de entrada. Decide o papel deste processo:
##   --server (ou rodando --headless)  → servidor dedicado
##   --test-client                       → cliente automático dos testes de rede
##   --bench                             → teste de desempenho do servidor neste PC (e fecha)
##   (nada)                              → jogo normal, com menu
##
## Exemplos:
##   Godot.exe --headless -- --server --port=7777 --bots=30
##   Godot.exe -- --name=Tux --connect=100.64.0.5   (entra direto, sem menu)


func _ready() -> void:
	var args := Args.current()
	if args.has("auto-quit"):
		var secs := float(args["auto-quit"])
		get_tree().create_timer(secs).timeout.connect(func():
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			get_tree().quit(0))

	if args.has("test-client"):
		var scenario: Node = load("res://tests/net_scenario.gd").new()
		scenario.name = "NetScenario"
		add_child(scenario)
		scenario.call("run", args)
	elif args.has("bench"):
		# Mede quanto o servidor pesa neste PC e fecha (ver scripts/bench.gd).
		get_tree().quit(Bench.run(args))
	elif args.has("server") or DisplayServer.get_name() == "headless":
		var server := GameServer.new()
		server.name = "GameServer"
		add_child(server)
		if server.start(args) != OK:
			get_tree().quit(1)
	else:
		var client := GameClient.new()
		client.name = "GameClient"
		add_child(client)
		client.start(args)
