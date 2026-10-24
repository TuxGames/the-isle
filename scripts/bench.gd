class_name Bench
extends RefCounted
## Teste de desempenho do servidor neste PC (roadmap v0.2, etapa 4: o Lenovo aguenta?).
## Roda o mundo com bots e jogadores de mentira andando pelo mapa, o mais rápido possível,
## e mede cada parte do trabalho do servidor: simulação, snapshot e save em disco.
## Não abre rede nem mexe no save de verdade.
##
##   DinoSurvival.console.exe --headless -- --bench      (ou testar_desempenho.bat)
##   godot --headless --path . -- --bench --bots=100 --seconds=60

const PLAYER_SPECIES := ["carnotaurus", "triceratops", "dryosaurus", "carnotaurus", "triceratops"]
const GB := 1024.0 * 1024.0 * 1024.0
const SAVE_DIR := "user://bench"


## Roda os dois cenários (jogadores juntos e espalhados), imprime o relatório e devolve
## o código de saída do processo.
static func run(args: Dictionary) -> int:
	var bots := clampi(int(args.get("bots", 70)), 0, GameConfig.BOT_MAX)
	var players := clampi(int(args.get("players", GameConfig.MAX_PLAYERS)), 1, GameConfig.MAX_PLAYERS)
	var seconds := maxf(5.0, float(args.get("seconds", 120.0)))
	var lines: Array[String] = []

	_say(lines, "== Teste de desempenho do servidor (Dino Survival %s) ==" % GameConfig.VERSION)
	_say(lines, "PC: %s · %d núcleos lógicos · %s %s" % [
		OS.get_processor_name(), OS.get_processor_count(), OS.get_name(), OS.get_version()])
	var mem := OS.get_memory_info()
	if float(mem.get("physical", -1)) > 0.0:
		_say(lines, "RAM: %.1f GB no total, %.1f GB livres agora" % [
			float(mem["physical"]) / GB, float(mem.get("available", 0)) / GB])
	_say(lines, "Godot %s" % Engine.get_version_info()["string"])
	_say(lines, "")

	var worst := 0.0
	var spikes := false
	var slow_save := 0.0
	for together in [true, false]:
		_say(lines, "Cenário: %d jogador(es) %s, %d bots, %.0f s de mundo..." % [
			players, "juntos" if together else "espalhados", bots, seconds])
		var r := run_scenario(bots, players, seconds, together)
		_say(lines, "  simulação: %.2f ms por passo em média · 95%% dos passos até %.2f ms · pior %.1f ms" % [
			r["step_avg_ms"], r["step_p95_ms"], r["step_max_ms"]])
		var kb_s: float = r["snap_kb"] * GameConfig.SNAPSHOT_HZ
		_say(lines, "  snapshot: %.2f ms pra montar · %.1f KB · %.0f KB/s por jogador (%.1f Mbit/s de upload no total)" % [
			r["snap_avg_ms"], r["snap_kb"], kb_s, kb_s * players * 8.0 / 1024.0])
		if r["saves"] > 0:
			_say(lines, "  save em disco (a cada %.0f s): %.0f ms" % [GameConfig.SAVE_INTERVAL_S, r["save_ms"]])
		var tiers: Dictionary = r["tiers"]
		_say(lines, "  bots por faixa (média): perto %.0f · longe %.0f · congelados %.0f" % [
			tiers["full"], tiers["reduced"], tiers["frozen"]])
		_say(lines, "  => %.1f%% de um núcleo (o limite é 100%%)" % r["core_pct"])
		_say(lines, "")
		worst = maxf(worst, r["core_pct"])
		spikes = spikes or r["step_max_ms"] > 1000.0 / GameConfig.SIM_HZ
		slow_save = maxf(slow_save, r["save_ms"])

	if worst < 25.0:
		_say(lines, "VEREDITO: OK, aguenta com folga (no pior cenário usa %.0f%% de um núcleo)." % worst)
	elif worst < 60.0:
		_say(lines, "VEREDITO: aguenta, mas com pouca folga (%.0f%% de um núcleo). Não suba os bots." % worst)
	else:
		_say(lines, "VEREDITO: PESADO (%.0f%% de um núcleo). Vai engasgar: diminua os bots (--bots=N)." % worst)
	if spikes:
		_say(lines, "Atenção: algum passo passou de %.0f ms (o jogo pode dar um tranco de vez em quando)." % [
			1000.0 / GameConfig.SIM_HZ])
	if slow_save > 100.0:
		_say(lines, "Atenção: o save trava o servidor por %.0f ms a cada %.0f s. Um SSD resolve." % [
			slow_save, GameConfig.SAVE_INTERVAL_S])
	var static_mem := OS.get_static_memory_usage()
	if static_mem > 0:
		_say(lines, "Memória usada pelo jogo: %.0f MB" % (static_mem / 1024.0 / 1024.0))

	if args.has("out"):
		var path := String(args["out"]).replace("\\", "/")
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("ERRO ao gravar %s: %s" % [path, error_string(FileAccess.get_open_error())])
			return 1
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("Resultado salvo em %s" % path)
	return 0


## Um cenário: os jogadores andam em grupo atrás do primeiro, ou cada um pro seu lado.
## Devolve os tempos medidos (ms), o tamanho do snapshot (KB) e a média de bots por faixa.
static func run_scenario(bots: int, players: int, seconds: float, together: bool) -> Dictionary:
	var w := WorldSim.new(GameConfig.WORLD_SEED, bots)
	w.populate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var names: Array[String] = []
	var goals: Array[Vector3] = []
	var ids: Array[int] = []
	var start := w.terrain.random_land_point(rng)
	for i in players:
		names.append("bench%d" % (i + 1))
		goals.append(w.terrain.random_land_point(rng))
		var pos: Vector3 = start + _group_offset(i) if together else goals[i]
		ids.append(_enter(w, names[i], PLAYER_SPECIES[i % PLAYER_SPECIES.size()], pos).id)
		if not together:
			goals[i] = w.terrain.random_land_point(rng)

	var dt := 1.0 / GameConfig.SIM_HZ
	var steps := int(seconds * GameConfig.SIM_HZ)
	var step_us := PackedInt64Array()
	step_us.resize(steps)
	var snap_acc := 0.0
	var snaps := 0
	var snap_us := 0
	var snap_bytes := 0
	var save_acc := 0.0
	var saves := 0
	var save_us := 0
	var tier_sum := {"full": 0.0, "reduced": 0.0, "frozen": 0.0}
	var tier_samples := 0
	var deaths := 0

	for s in steps:
		for i in players:
			var p: Dino = w.dinos.get(ids[i])
			if p == null:
				# Jogador de mentira morreu: renasce (adulto, pra manter a carga) e volta pro grupo.
				deaths += 1
				var first: Dino = w.dinos.get(ids[0])
				var at := goals[i]
				if together and first != null:
					at = first.pos + _group_offset(i)
				p = _enter(w, names[i], PLAYER_SPECIES[i % PLAYER_SPECIES.size()], at)
				ids[i] = p.id
			var leader: Dino = w.dinos.get(ids[0])
			var target := goals[i]
			if together and i > 0 and leader != null:
				target = leader.pos + _group_offset(i)
			if _walk(w, p, target, dt) and (i == 0 or not together):
				goals[i] = w.terrain.random_land_point(rng)

		var t0 := Time.get_ticks_usec()
		w.step(dt)
		step_us[s] = Time.get_ticks_usec() - t0
		w.events.clear()

		snap_acc += dt
		if snap_acc >= 1.0 / GameConfig.SNAPSHOT_HZ:
			snap_acc -= 1.0 / GameConfig.SNAPSHOT_HZ
			t0 = Time.get_ticks_usec()
			var data := GameServer.build_snapshot(w)
			snap_us += Time.get_ticks_usec() - t0
			snap_bytes += data.size() * 4
			snaps += 1

		save_acc += dt
		if save_acc >= GameConfig.SAVE_INTERVAL_S:
			save_acc = 0.0
			save_us += _timed_save(w)
			saves += 1

		if s % int(GameConfig.SIM_HZ) == 0:
			var c := w.sim_tier_counts()
			for k in tier_sum:
				tier_sum[k] += c[k]
			tier_samples += 1

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR + "/world.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))

	var total_us := 0
	for us in step_us:
		total_us += us
	var sorted := step_us.duplicate()
	sorted.sort()
	var r := {
		"steps": steps,
		"step_avg_ms": total_us / 1000.0 / maxi(steps, 1),
		"step_p95_ms": sorted[int(steps * 0.95)] / 1000.0 if steps > 0 else 0.0,
		"step_max_ms": sorted[steps - 1] / 1000.0 if steps > 0 else 0.0,
		"snapshots": snaps,
		"snap_avg_ms": snap_us / 1000.0 / maxi(snaps, 1),
		"snap_kb": snap_bytes / 1024.0 / maxi(snaps, 1),
		"saves": saves,
		"save_ms": save_us / 1000.0 / maxi(saves, 1),
		"player_deaths": deaths,
		"players_in_world": w.players().size(),
		"tiers": {},
	}
	for k in tier_sum:
		r["tiers"][k] = tier_sum[k] / maxi(tier_samples, 1)
	# CPU por segundo de jogo: 20 passos + 15 snapshots + o save dividido pelo intervalo.
	var ms_per_s: float = r["step_avg_ms"] * GameConfig.SIM_HZ + r["snap_avg_ms"] * GameConfig.SNAPSHOT_HZ \
			+ r["save_ms"] / GameConfig.SAVE_INTERVAL_S
	r["core_pct"] = ms_per_s / 10.0
	return r


static func _say(lines: Array[String], text: String) -> void:
	print(text)
	lines.append(text)


## Jogador adulto (pra ser percebido e caçado como um de verdade).
static func _enter(w: WorldSim, player_name: String, species: String, pos: Vector3) -> Dino:
	var d: Dino = w.login_player(player_name, species)["dino"]
	d.growth = 1.0
	d.health = d.max_health()
	d.pos = Terrain.clamp_to_play_area(pos)
	d.pos.y = Movement.ground_y(w.terrain, d.pos.x, d.pos.z, d.body_height())
	return d


## Posição de cada um no grupo: em volta do primeiro, a uns 10 m.
static func _group_offset(i: int) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	var ang := TAU * i / float(GameConfig.MAX_PLAYERS)
	return Vector3(sin(ang), 0.0, cos(ang)) * 10.0


## Anda no ritmo de caminhada, como o cliente faria. Devolve true quando chegou.
static func _walk(w: WorldSim, p: Dino, target: Vector3, dt: float) -> bool:
	var delta := Vector3(target.x - p.pos.x, 0.0, target.z - p.pos.z)
	var dist := delta.length()
	if dist < 2.0:
		p.moving_speed = 0.0
		return true
	var v := Movement.speeds(p).x
	p.yaw = atan2(delta.x, delta.z)
	p.pos += delta / dist * minf(v * dt, dist)
	p.pos = Terrain.clamp_to_play_area(p.pos)
	p.pos.y = Movement.ground_y(w.terrain, p.pos.x, p.pos.z, p.body_height())
	p.moving_speed = v
	p.sprinting = false
	return false


## Grava o mundo do mesmo jeito que o servidor (num arquivo à parte) e devolve os microssegundos.
static func _timed_save(w: WorldSim) -> int:
	var t0 := Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var f := FileAccess.open(SAVE_DIR + "/world.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(w.to_save()))
		f.close()
	return Time.get_ticks_usec() - t0
