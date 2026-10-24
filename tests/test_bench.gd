extends RefCounted
## Teste de desempenho (scripts/bench.gd): tem que rodar até o fim e medir tudo.


func test_bench_roda_e_mede(t) -> void:
	var r := Bench.run_scenario(10, 2, 31.0, true)
	t.check(r["steps"] == 31 * int(GameConfig.SIM_HZ), "rodou todos os passos")
	t.check(r["step_avg_ms"] > 0.0 and r["step_p95_ms"] >= 0.0, "mediu a simulação")
	t.check(r["snapshots"] >= 30 * int(GameConfig.SNAPSHOT_HZ), "~15 snapshots por segundo")
	t.check(r["snap_kb"] > 0.0, "mediu o snapshot")
	t.check(r["saves"] == 1, "um save a cada 30 s")
	t.check(r["players_in_world"] == 2, "os jogadores de mentira continuam no mundo")
	var tiers: Dictionary = r["tiers"]
	t.near(tiers["full"] + tiers["reduced"] + tiers["frozen"], 10.0, 1.0, "bots contados por faixa")
	t.check(r["core_pct"] > 0.0, "calculou o uso de CPU")
	t.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Bench.SAVE_DIR)),
			"apagou o save de teste")
