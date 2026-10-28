extends RefCounted
## Clima, estações e dia/noite (design, seção 11; sim/climate.gd).

const DT := 1.0 / GameConfig.SIM_HZ
const SEED := GameConfig.WORLD_SEED
const H := 3600.0
const ORIGIN := Vector3(200, 0, 200)


## Mundo de 512 m sem bots: só o que o teste puser.
func _world(bots := 0) -> WorldSim:
	return WorldSim.new(SEED, bots, 512.0)


func _player(w: WorldSim, player_name: String, species: String, pos: Vector3) -> Dino:
	var p: Dino = w.login_player(player_name, species)["dino"]
	p.growth = 1.0
	p.health = p.max_health()
	_place(w, p, pos)
	return p


func _bot(w: WorldSim, species: String, pos: Vector3) -> Dino:
	var d := Dino.create(w.new_id(), species, 1.0, pos)
	d.is_bot = true
	_place(w, d, pos)
	w.dinos[d.id] = d
	return d


func _place(w: WorldSim, d: Dino, pos: Vector3) -> void:
	d.pos = Vector3(pos.x, Movement.ground_y(w.terrain, pos.x, pos.z, d.body_height(), w.water_level), pos.z)


func _run(w: WorldSim, seconds: float) -> void:
	for i in int(seconds * GameConfig.SIM_HZ):
		w.step(DT)


func _winter() -> float:
	return Climate.next_season_start(0.0, Climate.Season.WINTER)


## Primeiro instante de um bloco da estação com esse tempo, sem seca nem chuva forte, ou -1.
func _block_with(c: Climate, season: int, weather: int) -> float:
	for b in range(1, 2400):
		var t := b * GameConfig.WEATHER_BLOCK_S + 1.0
		if Climate.season_at(t) == season and c.base_weather(t) == weather \
				and c.drought_at(t) == 0.0 and not c.heavy_rain(t):
			return t
	return -1.0


## Um ponto em terra na altura pedida (pra neve), dentro da área jogável.
func _spot(ter: Terrain, h_min: float, h_max: float, max_slope := 0.4) -> Vector3:
	var x := 60.0
	while x < ter.size - 60.0:
		var z := 60.0
		while z < ter.size - 60.0:
			var h := ter.height_at(x, z)
			if h >= h_min and h <= h_max and ter.slope_at(x, z) < max_slope:
				return Vector3(x, h, z)
			z += 6.0
		x += 6.0
	return Vector3(-1, -1, -1)


# ---------------------------------------------------------------- calendário

func test_clima_calendario_e_estacoes(t) -> void:
	t.near(Climate.year_s(), 80.0 * H, 0.01, "ano de 80 h de mundo (Marcelo: 70 a 90 h)")
	t.check(Climate.season_at(0.0) == Climate.Season.SPRING, "o mundo começa na primavera")
	t.check(Climate.season_at(14.0 * H - 1.0) == Climate.Season.SPRING, "primavera dura 14 h")
	t.check(Climate.season_at(14.0 * H) == Climate.Season.SUMMER, "depois vem o verão")
	t.check(Climate.season_at(56.0 * H - 1.0) == Climate.Season.SUMMER, "verão dura 42 h")
	t.check(Climate.season_at(56.0 * H) == Climate.Season.AUTUMN, "outono às 56 h")
	t.check(Climate.season_at(68.0 * H) == Climate.Season.WINTER, "inverno às 68 h")
	t.check(Climate.season_at(80.0 * H) == Climate.Season.SPRING, "o ano recomeça")
	t.check(Climate.season_at(80.0 * H * 3 + 70.0 * H) == Climate.Season.WINTER, "anos seguintes iguais")
	# Favorável ≈ 9X e desfavorável ≈ X a 2X (decisão do Marcelo); predomina o verão.
	var good := Climate.season_length(Climate.Season.SPRING) + Climate.season_length(Climate.Season.SUMMER)
	var x := good / 9.0
	var winter := Climate.season_length(Climate.Season.WINTER)
	t.check(winter >= x and winter <= 2.0 * x * 1.05, "inverno entre X e 2X (X = %.1f h, inverno %.1f h)" % [x / H, winter / H])
	for s in [0, 2, 3]:
		t.check(Climate.season_length(Climate.Season.SUMMER) > Climate.season_length(s), "verão é a estação mais longa")
	t.near(Climate.next_season_start(100.0, Climate.Season.WINTER), 68.0 * H, 0.001, "próximo inverno")
	t.near(Climate.last_season_start(70.0 * H, Climate.Season.WINTER), 68.0 * H, 0.001, "inverno atual")
	t.near(Climate.next_season_start(70.0 * H, Climate.Season.WINTER), 148.0 * H, 0.001, "o próximo é no ano seguinte")
	t.check(Climate.day_number(0.0) == 1 and Climate.day_number(H - 1.0) == 1 and Climate.day_number(H) == 2, "dia de 1 h")
	t.check(Climate.calendar_text(0.0) == "Dia 1 · Primavera · 05:00", "texto do HUD (veio \"%s\")" % Climate.calendar_text(0.0))
	t.check(Climate.calendar_text(20.0 * H + 1800.0) == "Dia 21 · Verão · 17:00", "texto do HUD no verão (veio \"%s\")" % Climate.calendar_text(20.0 * H + 1800.0))


func test_clima_dia_e_noite(t) -> void:
	var light_s := GameConfig.DAY_S - GameConfig.NIGHT_S
	t.near(Climate.daylight(light_s * 0.5), 1.0, 0.0001, "meio do dia: claro")
	t.near(Climate.daylight(light_s + GameConfig.NIGHT_S * 0.5), 0.0, 0.0001, "meio da noite: escuro")
	t.near(Climate.daylight(0.0), 0.5, 0.01, "nascer do sol: meio claro")
	t.near(Climate.daylight(light_s), 0.5, 0.01, "pôr do sol: meio claro")
	var dark := 0
	var max_jump := 0.0
	var prev := Climate.daylight(0.0)
	for s in range(0, int(GameConfig.DAY_S)):
		var d := Climate.daylight(float(s))
		if d < 0.5:
			dark += 1
		max_jump = maxf(max_jump, absf(d - prev))
		prev = d
	t.near(dark, GameConfig.NIGHT_S, 2.0, "noite de 20 min (%d s)" % dark)
	t.check(max_jump < 0.02, "amanhecer e entardecer suaves (maior salto %.3f por segundo)" % max_jump)
	t.check(Climate.is_night(light_s + 60.0) and not Climate.is_night(60.0), "is_night")
	t.check(Climate.clock_text(light_s) == "21:00", "anoitece às 21:00 (veio %s)" % Climate.clock_text(light_s))
	t.check(Climate.clock_text(H + 0.0) == "05:00", "amanhece às 05:00 todo dia")
	t.near(Climate.daylight(light_s * 0.5 + 7.0 * H), 1.0, 0.0001, "todo dia igual")


# ---------------------------------------------------------------- tempo determinístico

func test_clima_deterministico(t) -> void:
	var ter := Terrain.get_shared(SEED, 512.0)
	var a := Climate.new(SEED, ter)
	var b := Climate.new(SEED, ter)
	var samples := []
	for k in 600:
		samples.append(k * 1733.7)
	var same := true
	for s in samples:
		if a.weather_at(s) != b.weather_at(s) or a.snow_amount(s) != b.snow_amount(s) \
				or a.water_level(s) != b.water_level(s):
			same = false
	t.check(same, "mesma semente + mesmo tempo = mesmo clima")
	# A ordem das perguntas (e os caches) não muda a resposta.
	var c := Climate.new(SEED, ter)
	var rev := samples.duplicate()
	rev.reverse()
	var same_rev := true
	for s in rev:
		if c.snow_amount(s) != a.snow_amount(s) or c.weather_at(s) != a.weather_at(s):
			same_rev = false
	t.check(same_rev, "perguntando em outra ordem dá o mesmo")
	var other := Climate.new(SEED + 1, ter)
	var differ := false
	for s in samples:
		if other.weather_at(s) != a.weather_at(s):
			differ = true
	t.check(differ, "outra semente, outro tempo")
	t.check(a.base_weather(1.0) == Climate.Weather.CLEAR, "mundo novo começa com tempo limpo")

	# Neve só no inverno; pesos por estação.
	var counts := []
	for s in 4:
		counts.append([0, 0, 0, 0, 0, 0])
	var snow_outside := 0
	var blocks := int(30.0 * Climate.year_s() / GameConfig.WEATHER_BLOCK_S)
	for blk in range(1, blocks):
		var bt := blk * GameConfig.WEATHER_BLOCK_S + 1.0
		var w := a.base_weather(bt)
		var season := Climate.season_at(bt)
		counts[season][w] += 1
		if Climate.is_snow(w) and season != Climate.Season.WINTER:
			snow_outside += 1
	t.check(snow_outside == 0, "neve e nevasca só no inverno")
	var win: Array = counts[Climate.Season.WINTER]
	t.check(win[Climate.Weather.RAIN] == 0 and win[Climate.Weather.STORM] == 0, "inverno não tem chuva (neva)")
	t.check(win[Climate.Weather.BLIZZARD] > 0 and win[Climate.Weather.BLIZZARD] < win[Climate.Weather.SNOW] / 2, "nevasca é rara")
	var spring: Array = counts[Climate.Season.SPRING]
	var total := 0
	for n in spring:
		total += n
	for i in 4:
		var want := float(GameConfig.WEATHER_CHANCES[0][i]) / 100.0
		t.near(float(spring[i]) / total, want, 0.05, "primavera: chance de %s" % Climate.WEATHER_NAMES[i])


# ---------------------------------------------------------------- neve

func test_clima_neve_por_altitude(t) -> void:
	var c := Climate.new(SEED, Terrain.get_shared(SEED, 512.0))
	var ws := _winter()
	t.check(c.snow_amount(ws - 1.0) == 0.0, "antes do inverno não tem neve")
	# Neve fraca por 2 h: a linha de neve desce das montanhas até os morros, baixada continua sem.
	c.set_override(Climate.Weather.SNOW, ws, ws + 2.0 * H)
	var lines := [Climate.snow_line(c.snow_amount(ws + 300.0)), Climate.snow_line(c.snow_amount(ws + 900.0)),
			Climate.snow_line(c.snow_amount(ws + 1800.0))]
	t.check(lines[0] > lines[1] and lines[1] > lines[2], "a linha de neve desce enquanto neva (%.0f → %.0f → %.0f m)" % lines)
	var light := c.snow_amount(ws + 2.0 * H - 1.0)
	t.check(light <= GameConfig.SNOW_LIGHT_MAX + 0.0001, "neve fraca não passa de %.1f (%.2f)" % [GameConfig.SNOW_LIGHT_MAX, light])
	t.check(Climate.snow_cover(45.0, light) > 0.99, "montanha branca com neve fraca")
	t.check(Climate.snow_cover(26.0, light) > 0.9, "morro alto branco")
	t.check(Climate.snow_cover(5.0, light) == 0.0, "baixada sem neve com neve fraca")
	# Nevasca: neva em tudo, mas as baixadas pegam menos.
	c.set_override(Climate.Weather.BLIZZARD, ws, ws + H)
	var full := c.snow_amount(ws + 1800.0)
	t.near(full, 1.0, 0.0001, "nevasca enche a neve acumulada")
	var low := Climate.snow_cover(2.0, full)
	var mid := Climate.snow_cover(8.0, full)
	var high := Climate.snow_cover(20.0, full)
	t.check(low > 0.0 and low < mid and mid < high and high > 0.99,
			"nevasca neva em tudo, baixada pega menos (%.2f < %.2f < %.2f)" % [low, mid, high])
	t.check(Climate.snow_cover(-1.0, full) == 0.0, "debaixo d'água não tem neve")
	# Picos brancos o inverno inteiro, mesmo sem nevar.
	c.set_override(Climate.Weather.CLEAR, ws, ws + 10.0 * H)
	var winter_min := c.snow_amount(ws + 10.0 * H - 1.0)
	t.near(winter_min, GameConfig.WINTER_SNOW_MIN, 0.0001, "inverno sem nevar fica no mínimo")
	t.check(Climate.snow_cover(48.0, winter_min) > 0.5 and Climate.snow_cover(20.0, winter_min) == 0.0,
			"só os picos ficam brancos")


func test_clima_neve_derrete_aos_poucos(t) -> void:
	var c := Climate.new(SEED, Terrain.get_shared(SEED, 512.0))
	# Nevasca forçada no outono (fora do inverno não tem mínimo nem neve natural).
	var autumn := Climate.next_season_start(0.0, Climate.Season.AUTUMN) + H
	var end := autumn + 1800.0
	c.set_override(Climate.Weather.BLIZZARD, autumn, end)
	t.near(c.snow_amount(end), 1.0, 0.0001, "nevasca encheu")
	var half := c.snow_amount(end + GameConfig.SNOW_MELT_S * 0.5)
	t.near(half, 0.5, 0.01, "uma hora depois, metade (%.2f)" % half)
	t.check(c.snow_amount(end + GameConfig.SNOW_MELT_S + 1.0) == 0.0, "2 h depois da última nevasca, derreteu tudo")
	var prev := 2.0
	var monotonic := true
	for k in 40:
		var a := c.snow_amount(end + k * 200.0)
		if a > prev + 0.000001:
			monotonic = false
		prev = a
	t.check(monotonic, "derrete aos poucos, sem voltar")
	# A neve natural do inverno também some depois: 2 h depois do fim do inverno, nada.
	var spring := Climate.next_season_start(_winter(), Climate.Season.SPRING)
	var n := Climate.new(SEED, Terrain.get_shared(SEED, 512.0))
	t.check(n.snow_amount(spring + GameConfig.SNOW_MELT_S + 1.0) == 0.0, "primavera: a neve do inverno derreteu")


# ---------------------------------------------------------------- inverno

func test_clima_inverno_mais_fome(t) -> void:
	var drops := []
	for when in [20.0 * H, _winter() + H]:
		var w := _world()
		w.world_time = when
		var p := _player(w, "tux", "dryosaurus", ORIGIN)
		p.hunger = 100.0
		_run(w, 10.0)
		drops.append(100.0 - p.hunger)
	t.near(drops[1] / drops[0], GameConfig.WINTER_HUNGER_MULT, 0.01,
			"inverno gasta %.0f%% mais comida (%.3f vs %.3f)" % [(GameConfig.WINTER_HUNGER_MULT - 1.0) * 100.0, drops[1], drops[0]])


func test_clima_corre_menos_na_neve(t) -> void:
	var w := _world()
	var hill := _spot(w.terrain, 16.0, 30.0)
	var lowland := _spot(w.terrain, 1.0, 4.0, 1.0)
	t.check(hill.x > 0.0 and lowland.x > 0.0, "achou morro e baixada no mapa")
	var p := _player(w, "tux", "carnotaurus", hill)
	var b := _bot(w, "carnotaurus", hill + Vector3(4, 0, 0))
	_run(w, 0.1)
	var summer_speed := Movement.speeds(p)
	var ws := _winter()
	w.climate.set_override(Climate.Weather.BLIZZARD, ws, ws + H)
	w.world_time = ws + 1800.0
	_place(w, p, hill)
	_run(w, 0.1)
	var snow_speed := Movement.speeds(p)
	t.near(snow_speed.y / summer_speed.y, GameConfig.SNOW_SPRINT_MULT, 0.01,
			"no morro branco corre a %.0f%% (%.2f → %.2f m/s)" % [GameConfig.SNOW_SPRINT_MULT * 100.0, summer_speed.y, snow_speed.y])
	t.near(snow_speed.x, summer_speed.x, 0.0001, "andar não muda")
	t.near(b.climate_sprint_mult, GameConfig.SNOW_SPRINT_MULT, 0.01, "vale pros bots também")
	_place(w, p, lowland)
	_run(w, 0.1)
	var low_mult := Movement.speeds(p).y / summer_speed.y
	t.check(low_mult > GameConfig.SNOW_SPRINT_MULT + 0.01 and low_mult < 1.0, "na baixada (menos neve) corre mais (%.2f)" % low_mult)
	# Sem fôlego ou de osso quebrado, corre igual a andar (nunca mais devagar que andar).
	p.stamina = 0.0
	t.near(Movement.speeds(p).y, Movement.speeds(p).x, 0.0001, "sem fôlego: corrida = andar")


func _hunt_state(when: float) -> String:
	var w := _world()
	w.world_time = when
	var carn := _bot(w, "carnotaurus", ORIGIN)
	carn.hunger = 50.0
	_bot(w, "dryosaurus", ORIGIN + Vector3(0, 0, 12))
	w._rebuild_grid()
	BotBrain.think(w, carn)
	return BotBrain.state_of(carn)


func test_clima_inverno_menos_caca(t) -> void:
	var summer := _hunt_state(20.0 * H)
	var winter := _hunt_state(_winter() + H)
	t.check(summer == "hunt", "no verão, com fome 50, o carnívoro caça (%s)" % summer)
	t.check(winter != "hunt", "no inverno, com fome 50, não sai pra caçar (%s)" % winter)
	var w := _world()
	w.world_time = _winter() + H
	t.near(w.hunt_hunger_start(BotBrain.HUNGER_START_CARN), GameConfig.WINTER_HUNT_HUNGER, 0.001, "limiar de caça do inverno")


func test_clima_inverno_menos_bots_sem_matar(t) -> void:
	var w := _world(40)
	w.populate()
	t.check(w.bot_count() == 40, "primavera: 40 bots")
	w.world_time = _winter() + 60.0
	t.check(w.effective_bot_target() == 32, "inverno: alvo de 80%% (%d)" % w.effective_bot_target())
	_run(w, 1.0)
	t.check(w.bot_count() >= 39, "entrar no inverno não mata ninguém (%d)" % w.bot_count())
	var count := w.bot_count()
	var killed := 0
	for b: Dino in w.bots():
		if killed >= 12:
			break
		w.kill(b, "teste")
		killed += 1
	w.world_time += GameConfig.BOT_RESPAWN_DELAY_S + 1.0
	w._process_respawns()
	t.check(w.bot_count() == 32, "no inverno só repõe até 32 (%d → %d)" % [count - killed, w.bot_count()])
	# Primavera: a população volta pro alvo cheio.
	w.world_time = Climate.next_season_start(w.world_time, Climate.Season.SPRING)
	w._process_respawns()
	w.world_time += GameConfig.BOT_RESPAWN_DELAY_S + 1.0
	w._process_respawns()
	t.check(w.bot_count() == 40, "na primavera volta pra 40 (%d)" % w.bot_count())


func test_clima_agua_congela_mas_baixada_nunca(t) -> void:
	var w := _world()
	var c := w.climate
	var ws := _winter()
	c.set_override(Climate.Weather.BLIZZARD, ws, ws + H)
	w.world_time = ws + 1800.0
	var share := c.frozen_share(w.world_time)
	t.check(share > 0.3, "nevasca congela boa parte do rio (%.0f%%)" % (share * 100.0))
	t.check(share <= 1.0 - GameConfig.RIVER_NEVER_FREEZE + 0.02, "a baixada nunca congela (%.0f%% congelado)" % (share * 100.0))
	# Pior caso em outros mapas: com toda a neve, sempre sobra rio pra beber.
	for case in [[SEED + 5, 512.0], [SEED + 9, 1024.0], [12345, 768.0]]:
		var o := Climate.new(case[0], Terrain.get_shared(case[0], case[1]))
		var worst := 0.0
		for i in o.bank_count():
			if o.is_frozen_at(i * Climate.BANK_STEP, 1.0):
				worst += 1.0
		t.check(worst / o.bank_count() <= 1.0 - GameConfig.RIVER_NEVER_FREEZE + 0.02,
				"semente %d: no máximo %.0f%% do rio congela" % [case[0], (1.0 - GameConfig.RIVER_NEVER_FREEZE) * 100.0])
	t.check(c.frozen_share(20.0 * H) == 0.0, "no verão nada congela")
	var frozen_p := Vector3.INF
	var open_p := Vector3.INF
	for p in w.terrain.water_points:
		if c.is_frozen(p.z, w.world_time):
			if frozen_p == Vector3.INF:
				frozen_p = p
		elif open_p == Vector3.INF:
			open_p = p
	t.check(frozen_p != Vector3.INF and open_p != Vector3.INF, "tem trecho congelado e trecho aberto")
	var d := _player(w, "tux", "carnotaurus", frozen_p)
	d.yaw = Movement.yaw_to(d.pos, Vector3(w.terrain.river_center_x(d.pos.z), 0.0, d.pos.z))
	t.check(not w.can_drink(d), "na água congelada não bebe")
	var near := w.nearest_water_point(frozen_p)
	t.check(not c.is_frozen(near.z, w.world_time), "o bebedouro mais perto pula o gelo")
	_place(w, d, open_p)
	d.yaw = Movement.yaw_to(d.pos, Vector3(w.terrain.river_center_x(d.pos.z), 0.0, d.pos.z))
	t.check(w.can_drink(d), "na baixada bebe")
	w.world_time = 20.0 * H
	_place(w, d, frozen_p)
	d.yaw = Movement.yaw_to(d.pos, Vector3(w.terrain.river_center_x(d.pos.z), 0.0, d.pos.z))
	t.check(w.can_drink(d), "no verão o mesmo trecho dá pra beber")


func test_clima_bot_com_sede_acha_agua_aberta(t) -> void:
	var w := _world()
	var ws := _winter()
	w.climate.set_override(Climate.Weather.BLIZZARD, ws, ws + 2.0 * H)
	w.world_time = ws + 1800.0
	var frozen_p := Vector3.INF
	for p in w.terrain.water_points:
		if w.climate.is_frozen(p.z, w.world_time) and p.x < w.terrain.river_center_x(p.z):
			frozen_p = p
			break
	var b := _bot(w, "dryosaurus", frozen_p - Vector3(12, 0, 0))
	b.thirst = 20.0
	_run(w, 120.0)
	t.check(b.thirst > 60.0, "bot com sede achou água aberta e bebeu (sede %.0f)" % b.thirst)


# ---------------------------------------------------------------- verão, seca e chuva forte

func test_clima_verao_mais_comida_e_herbivoros(t) -> void:
	var w := _world()
	var spring := _block_with(w.climate, Climate.Season.SPRING, Climate.Weather.CLEAR)
	var summer := _block_with(w.climate, Climate.Season.SUMMER, Climate.Weather.CLEAR)
	var grown := []
	for when in [spring, summer]:
		w.world_time = when
		w.bush_food[0] = 0.0
		w._regrow_bushes(10.0)
		grown.append(w.bush_food[0])
	t.near(grown[1] / grown[0], GameConfig.SUMMER_REGROW_MULT, 0.001, "verão: arbustos rebrotam 50% mais rápido")
	var shares := []
	for when in [spring, summer]:
		var p := _world(100)
		p.world_time = when
		p.populate()
		var herbs := 0
		for b: Dino in p.bots():
			if not b.is_carnivore():
				herbs += 1
		shares.append(herbs / 100.0)
	t.near(shares[0], GameConfig.HERBIVORE_SHARE, 0.011, "primavera: 65%% herbívoros (%.2f)" % shares[0])
	t.near(shares[1], GameConfig.SUMMER_HERBIVORE_SHARE, 0.011, "verão: 70%% herbívoros (%.2f)" % shares[1])
	t.check(shares[1] <= GameConfig.HERBIVORE_SHARE + GameConfig.DIRECTOR_SHARE_TOLERANCE, "dentro dos limites do diretor")


func test_clima_chuva_forte_reduz_rebrota(t) -> void:
	var c := Climate.new(SEED, Terrain.get_shared(SEED, 512.0))
	var spring := _block_with(c, Climate.Season.SPRING, Climate.Weather.CLEAR)
	t.near(c.regrow_mult(spring), 1.0, 0.0001, "tempo bom: rebrota normal")
	c.set_override(Climate.Weather.STORM, spring, spring + 600.0)
	t.check(c.heavy_rain(spring + 10.0), "tempestade é chuva forte")
	t.near(c.regrow_mult(spring + 10.0), GameConfig.HEAVY_RAIN_REGROW_MULT, 0.0001, "tempestade: rebrota menos")
	# Chuva logo depois do bloco limpo: o primeiro bloco de chuva ainda não é "longa".
	var b0 := (floorf(spring / GameConfig.WEATHER_BLOCK_S) + 1.0) * GameConfig.WEATHER_BLOCK_S
	c.set_override(Climate.Weather.RAIN, b0, b0 + 2.0 * GameConfig.WEATHER_BLOCK_S)
	t.check(not c.heavy_rain(b0 + 10.0), "chuva curta não é chuva forte")
	t.check(c.heavy_rain(b0 + GameConfig.WEATHER_BLOCK_S + 10.0), "chuva longa (2 blocos) é")


func test_clima_seca_rio_encolhe(t) -> void:
	var w := _world()
	var c := w.climate
	var ys := Climate.year_s()
	var year := -1
	var count := 0
	for y in 200:
		if c.has_drought(y):
			count += 1
			if year < 0:
				year = y
	t.check(count > 60 and count < 140, "seca em mais ou menos metade dos anos (%d de 200)" % count)
	t.check(year >= 0, "achou um ano com seca")
	var peak := c.next_drought_peak(year * ys)
	var summer_end := year * ys + Climate.season_offset(Climate.Season.AUTUMN)
	t.check(Climate.season_at(peak) == Climate.Season.SUMMER and peak > summer_end - GameConfig.DROUGHT_S,
			"a seca é no fim do verão")
	t.near(c.drought_at(peak), 1.0, 0.0001, "no pico, seca total")
	t.check(c.drought_at(year * ys + Climate.season_offset(Climate.Season.SUMMER) + H) == 0.0, "começo do verão: sem seca")
	t.check(c.drought_at(summer_end + GameConfig.DROUGHT_RAMP_S + 1.0) == 0.0, "o rio volta no outono")
	var dry_rain := 0
	var b := floori((summer_end - GameConfig.DROUGHT_S) / GameConfig.WEATHER_BLOCK_S)
	while b * GameConfig.WEATHER_BLOCK_S < summer_end:
		var wt := c.base_weather(b * GameConfig.WEATHER_BLOCK_S + 1.0)
		if wt == Climate.Weather.RAIN or wt == Climate.Weather.STORM:
			dry_rain += 1
		b += 1
	t.check(dry_rain == 0, "não chove na seca")
	t.near(c.river_width(peak), GameConfig.DROUGHT_RIVER_WIDTH, 0.0001, "rio com 60% da largura")
	t.check(c.water_level(peak) < Terrain.WATER_LEVEL - 1.5, "nível do rio baixou (%.2f m)" % c.water_level(peak))
	# Na beira (80% da largura normal) tinha água; na seca não tem mais. No meio continua.
	var z := 200.0
	var cx := w.terrain.river_center_x(z)
	var edge := cx + Terrain.RIVER_HALF_WIDTH * 0.8
	t.check(c.is_drinkable(edge, z, peak - GameConfig.DROUGHT_S), "antes da seca bebia na beira")
	t.check(not c.is_drinkable(edge, z, peak), "na seca a beira secou")
	t.check(c.is_drinkable(cx, z, peak), "no meio do rio ainda tem água")
	w.world_time = peak
	_run(w, 0.05)
	var spot := w.nearest_water_point(Vector3(cx - 40.0, 0, z))
	t.check(c.is_drinkable(spot.x, spot.z, peak), "o bebedouro dos bots foi pro rio menor")
	t.near(w.water_level, c.water_level(peak), 0.0001, "o mundo usa o nível baixo")
	var d := _player(w, "tux", "triceratops", Vector3(edge, 0, z))
	t.check(d.pos.y > c.water_level(peak), "na beira seca o bicho anda no leito (não boia no nível antigo)")
	t.near(c.regrow_mult(peak), GameConfig.SUMMER_REGROW_MULT * GameConfig.DROUGHT_REGROW_MULT, 0.0001,
			"na seca os arbustos rebrotam mais devagar")
	# O mapa só tem o rio (nenhuma poça ou lago): na seca só ele encolhe.
	var only_river := true
	for p in w.terrain.water_points:
		if absf(p.x - w.terrain.river_center_x(p.z)) > Terrain.RIVER_HALF_WIDTH:
			only_river = false
	t.check(only_river, "toda a água do mapa é o rio (não tem água pequena pra secar)")


# ---------------------------------------------------------------- raio

func test_clima_raio_so_mata_bot(t) -> void:
	var w := _world()
	var p := _player(w, "tux", "dryosaurus", Vector3(60, 0, 60))
	var far := _bot(w, "triceratops", Vector3(470, 0, 470))
	_run(w, 0.1)
	t.check(far.sim_tier == WorldSim.SimTier.FROZEN, "bot longe congelou")
	t.check(Climate.strike(w, 0.0) == null and Climate.strike(w, 0.99) == null,
			"só jogador e bot congelado: o raio não atinge ninguém")
	t.check(p.alive and w.dinos.has(p.id) and w.dinos.has(far.id), "jogador e bot congelado continuam vivos")
	var near := _bot(w, "dryosaurus", Vector3(80, 0, 60))
	_run(w, 0.1)
	w.events.clear()
	var hit := Climate.strike(w, 0.5)
	t.check(hit == near and not w.dinos.has(near.id), "o raio mata o bot ativo")
	t.check(p.alive and w.dinos.has(p.id), "o jogador do lado continua vivo")
	var cause := ""
	var flash := false
	for ev in w.events:
		if ev["type"] == WorldSim.Ev.DEATH:
			cause = ev["cause"]
		if ev["type"] == WorldSim.Ev.LIGHTNING and ev["a"] == near.id:
			flash = true
	t.check(cause == "raio", "morreu de raio (\"%s\")" % cause)
	t.check(flash, "evento de raio pro clarão no cliente")
	t.check(w.carcasses.size() == 1, "virou carcaça")


func test_clima_raio_so_em_tempestade(t) -> void:
	var c := Climate.new(SEED, Terrain.get_shared(SEED, 512.0))
	var wrong := 0
	var storms := 0
	for m in range(0, int(3.0 * Climate.year_s() / 60.0)):
		if c.lightning_due(m):
			if c.weather_at(m * 60.0) != Climate.Weather.STORM:
				wrong += 1
			storms += 1
	t.check(wrong == 0, "raio só cai em tempestade")
	t.check(storms > 0, "cai de vez em quando (%d em 3 anos)" % storms)
	var from := 20.0 * H
	c.set_override(Climate.Weather.STORM, from, from + 10.0 * H)
	var hits := 0
	for m in range(int(from / 60.0), int((from + 10.0 * H) / 60.0)):
		if c.lightning_due(m):
			hits += 1
	var want := 600.0 * GameConfig.LIGHTNING_CHANCE_PER_MIN
	t.check(hits > want * 0.4 and hits < want * 1.8, "10 h de tempestade: ~%.0f raios (veio %d)" % [want, hits])

	# Pelo passo do mundo: numa tempestade longa morrem bots de raio e o jogador nunca.
	var w := _world()
	w.climate.set_override(Climate.Weather.STORM, from, from + 10.0 * H)
	var p := _player(w, "tux", "dryosaurus", ORIGIN)
	var strikes := 0
	for m in range(int(from / 60.0), int((from + 10.0 * H) / 60.0)):
		if not w.climate.lightning_due(m):
			continue
		_bot(w, "dryosaurus", ORIGIN + Vector3(15, 0, 0))
		w.world_time = m * 60.0 + 1.0
		w.step(DT)
		for ev in w.events:
			if ev["type"] == WorldSim.Ev.DEATH and ev["cause"] == "raio":
				strikes += 1
		w.events.clear()
	t.check(strikes == hits, "cada raio matou um bot (%d de %d)" % [strikes, hits])
	t.check(p.alive and w.dinos.has(p.id), "o jogador passou a tempestade inteira vivo")
	# Sem bot por perto: o raio cai e não mata ninguém.
	var lone := _world()
	lone.climate.set_override(Climate.Weather.STORM, from, from + 10.0 * H)
	var q := _player(lone, "tux", "dryosaurus", ORIGIN)
	for m in range(int(from / 60.0), int((from + 10.0 * H) / 60.0)):
		if lone.climate.lightning_due(m):
			lone.world_time = m * 60.0 + 1.0
			lone.step(DT)
	t.check(q.alive and lone.dinos.has(q.id), "sozinho na tempestade: o jogador nunca é atingido")


# ---------------------------------------------------------------- mundo parado, save e /time

func _state(w: WorldSim) -> Array:
	var c := w.climate
	var t0 := w.world_time
	return [Climate.season_at(t0), c.weather_at(t0), c.snow_amount(t0), c.water_level(t0),
			Climate.daylight(t0), c.frozen_share(t0), Climate.calendar_text(t0)]


func test_clima_mundo_parado_clima_parado(t) -> void:
	var w := _world()
	var ws := _winter()
	w.climate.set_override(Climate.Weather.BLIZZARD, ws, ws + H)
	w.world_time = ws + 600.0
	var before := _state(w)
	OS.delay_msec(30)
	t.check(_state(w) == before, "sem passo do mundo (ninguém online) o clima não muda")
	_run(w, 1.0)
	t.near(w.world_time, ws + 601.0, 0.001, "o clima só anda com o tempo do mundo")
	t.check(_state(w)[2] > before[2], "com o mundo andando, a nevasca acumula")
	# Nada do clima vai pro save: volta igual a partir do world_time salvo.
	var a := _world()
	a.world_time = ws + 5.0 * H
	var saved := a.to_save()
	t.check(not saved.has("climate") and not saved.has("weather"), "o save não tem clima")
	var b := _world()
	b.load_save(JSON.parse_string(JSON.stringify(saved)))
	t.check(_state(b) == _state(a), "depois de carregar o save o clima é o mesmo")


func test_clima_comandos_de_dev(t) -> void:
	var w := _world()
	var c := w.climate
	w.world_time = 100.0
	var r := c.dev_command(w, PackedStringArray(["/time", "inverno"]))
	t.check(Climate.season_at(w.world_time) == Climate.Season.WINTER, "/time inverno pula pro inverno (%s)" % r)
	var t1 := w.world_time
	c.dev_command(w, PackedStringArray(["/time", "inverno"]))
	t.check(w.world_time == t1, "já é inverno: não mexe (o tempo nunca volta)")
	c.dev_command(w, PackedStringArray(["/time", "22:00"]))
	t.check(Climate.clock_text(w.world_time) == "22:00" and w.world_time > t1 and w.world_time - t1 < GameConfig.DAY_S,
			"/time 22:00 vai pra próxima 22:00 (%s)" % Climate.clock_text(w.world_time))
	var t2 := w.world_time
	c.dev_command(w, PackedStringArray(["/time", "+2"]))
	t.near(w.world_time - t2, 2.0 * H, 0.001, "/time +2 anda 2 h")
	c.dev_command(w, PackedStringArray(["/time", "seca"]))
	t.near(c.drought_at(w.world_time), 1.0, 0.0001, "/time seca vai pro pico da próxima seca")
	var t3 := w.world_time
	var bad := c.dev_command(w, PackedStringArray(["/time", "ontem"]))
	t.check(w.world_time == t3 and bad.begins_with("Uso"), "palavra errada não mexe no tempo")
	w.events.clear()
	c.dev_command(w, PackedStringArray(["/weather", "nevasca", "30"]))
	t.check(c.weather_at(w.world_time) == Climate.Weather.BLIZZARD, "/weather nevasca força nevasca")
	t.near(float(c.override["until"]) - w.world_time, 1800.0, 0.001, "por 30 min")
	var ev: Dictionary = w.events.back() if not w.events.is_empty() else {}
	t.check(ev.get("type", 0) == WorldSim.Ev.WEATHER and ev.get("weather", -1) == Climate.Weather.BLIZZARD,
			"avisa os clientes (evento WEATHER)")
	# O cliente recebe o mesmo /weather e calcula a mesma neve.
	var client := Climate.new(SEED, w.terrain)
	client.set_override(int(ev["weather"]), float(ev["from"]), float(ev["until"]))
	var later := w.world_time + 900.0
	t.check(client.snow_amount(later) == c.snow_amount(later) and client.weather_at(later) == c.weather_at(later),
			"cliente com o mesmo /weather calcula a mesma neve")
	c.dev_command(w, PackedStringArray(["/weather", "auto"]))
	t.check(c.override.is_empty(), "/weather auto volta ao normal")
	var status := c.dev_command(w, PackedStringArray(["/clima"]))
	t.check(status.contains("[t=") and status.contains("neve="), "/clima mostra o estado (%s)" % status)
