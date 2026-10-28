class_name Climate
extends RefCounted
## Clima, estações e dia/noite (design, seção 11). Números em config.gd (seção "Clima").
##
## Tudo aqui é uma FUNÇÃO da semente do mapa e do tempo do mundo (world_time):
## - servidor e cliente calculam exatamente o mesmo clima sem mandar nada novo pela rede
##   (o tempo do mundo já vai no ST_WORLD_TIME e a semente no login);
## - nada vai pro save: tudo sai de novo do world_time salvo;
## - com ninguém online o tempo do mundo para, então o clima também para.
## A única exceção é o /weather dos comandos de dev: fica só na memória do servidor (`overrides`)
## e vai pros clientes por s_event (WorldSim.Ev.WEATHER) e no s_welcome.
##
## - Calendário: dia de DAY_S (claro + noite) e ano com as 4 estações de SEASON_HOURS.
## - Tempo (limpo, nublado, chuva, tempestade, neve, nevasca): muda em blocos de WEATHER_BLOCK_S,
##   sorteado por hash(semente, bloco) com os pesos da estação.
## - Neve acumulada (0 a 1): somada bloco a bloco desde o começo do último inverno.
## - Seca: no fim do verão, nos anos sorteados por hash(semente, ano).
## - Efeitos no mundo: o WorldSim chama apply() e lightning() todo passo.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW, BLIZZARD }

const SEASON_NAMES := ["Primavera", "Verão", "Outono", "Inverno"]
const WEATHER_NAMES := ["Limpo", "Nublado", "Chuva", "Tempestade", "Neve", "Nevasca"]
## Como se escreve no /time e no /weather (sem acento também vale).
const SEASON_WORDS := {"primavera": 0, "verao": 1, "verão": 1, "outono": 2, "inverno": 3}
const WEATHER_WORDS := {"limpo": 0, "nublado": 1, "chuva": 2, "tempestade": 3, "neve": 4, "nevasca": 5}

## "Sal" de cada sorteio (tempo, seca, raio), pra eles não saírem iguais.
const SALT_WEATHER := 1
const SALT_DROUGHT := 2
const SALT_LIGHTNING := 3
const SALT_LIGHTNING_PICK := 4
## De quantos em quantos metros (em z, ao longo do rio) guarda a altura das margens.
const BANK_STEP := 8.0
## A que distância do centro do rio mede a margem (fora do leito escavado).
const BANK_OFFSET := Terrain.RIVER_HALF_WIDTH + Terrain.BANK_WIDTH + 4.0

var seed_value: int
var terrain: Terrain
## /weather (dev): trechos de tempo forçado, [{"weather": int, "from": float, "until": float}],
## em ordem e sem se sobrepor (um novo corta o que vinha depois do começo dele). Vazio = normal.
var overrides: Array = []
## Quantos trechos forçados guarda (os mais velhos saem antes).
const MAX_OVERRIDES := 16

## Altura das margens do rio a cada BANK_STEP de z, e até que altura de margem o rio nunca congela.
var _bank_h := PackedFloat32Array()
var _open_h := 0.0
## Caches (o servidor pergunta a mesma coisa pra cada bicho no mesmo passo).
var _override_rev := 0
var _snow_block := -1
var _snow_rev := -1
var _snow_block_amount := 0.0
var _amount_t := NAN
var _amount_v := 0.0
## Último minuto de mundo em que o raio foi sorteado (servidor).
var _lightning_minute := -1


func _init(p_seed: int, p_terrain: Terrain) -> void:
	seed_value = p_seed
	terrain = p_terrain
	_measure_banks()


# ---------------------------------------------------------------- calendário

## Duração do ano em segundos de mundo.
static func year_s() -> float:
	var s := 0.0
	for h in GameConfig.SEASON_HOURS:
		s += float(h) * 3600.0
	return s


static func season_length(season: int) -> float:
	return float(GameConfig.SEASON_HOURS[season]) * 3600.0


## Onde a estação começa dentro do ano (segundos).
static func season_offset(season: int) -> float:
	var s := 0.0
	for i in season:
		s += season_length(i)
	return s


static func season_at(t: float) -> int:
	var y := fposmod(t, year_s())
	for i in 4:
		y -= season_length(i)
		if y < 0.0:
			return i
	return Season.WINTER


## Último começo da estação até t (negativo se ainda não aconteceu nenhum).
static func last_season_start(t: float, season: int) -> float:
	var ys := year_s()
	var start := floorf(t / ys) * ys + season_offset(season)
	if start > t:
		start -= ys
	return start


## Próximo começo da estação a partir de t (o próprio t se começa nele).
static func next_season_start(t: float, season: int) -> float:
	var start := last_season_start(t, season)
	return start if start == t else start + year_s()


static func day_number(t: float) -> int:
	return floori(t / GameConfig.DAY_S) + 1


static func time_of_day(t: float) -> float:
	return fposmod(t, GameConfig.DAY_S)


static func is_night(t: float) -> bool:
	return time_of_day(t) >= GameConfig.DAY_S - GameConfig.NIGHT_S


## Luz do dia: 1 = dia claro, 0 = noite. Sobe no amanhecer e desce no entardecer (TWILIGHT_S
## cada, centrados no nascer e no pôr do sol).
static func daylight(t: float) -> float:
	var light_s := GameConfig.DAY_S - GameConfig.NIGHT_S
	var half := GameConfig.TWILIGHT_S * 0.5
	var x := time_of_day(t)
	if x > GameConfig.DAY_S - half:
		x -= GameConfig.DAY_S  # pouco antes do nascer do sol
	return smoothstep(-half, half, x) * (1.0 - smoothstep(light_s - half, light_s + half, x))


## Minutos do relógio do HUD (0 a 1439): o dia de DAY_S vira 24 h, com o sol nascendo às
## CLOCK_SUNRISE_H.
static func clock_minutes(t: float) -> int:
	var h := GameConfig.CLOCK_SUNRISE_H + time_of_day(t) / GameConfig.DAY_S * 24.0
	# A folguinha evita 21:59 no lugar de 22:00 por erro de arredondamento.
	return floori(fposmod(h, 24.0) * 60.0 + 0.0001) % 1440


static func clock_text(t: float) -> String:
	var m := clock_minutes(t)
	return "%02d:%02d" % [m / 60, m % 60]


## "Dia 3 · Verão · 14:20" (HUD).
static func calendar_text(t: float) -> String:
	return "Dia %d · %s · %s" % [day_number(t), SEASON_NAMES[season_at(t)], clock_text(t)]


# ---------------------------------------------------------------- sorteio

static func _mix(h: int) -> int:
	h &= 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x45d9f3b) & 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x45d9f3b) & 0xFFFFFFFF
	h ^= h >> 16
	return h


## Número de 0 a 1 que só depende de (a, b, c): igual em qualquer PC, sem rng.
static func hash01(a: int, b: int, c: int) -> float:
	var h := _mix(a ^ 0x2545F491)
	h = _mix(h ^ (b & 0xFFFFFFFF) ^ ((b >> 32) & 0xFFFFFFFF))
	h = _mix(h ^ ((c * 0x27d4eb2d) & 0xFFFFFFFF))
	return float(h & 0xFFFFFF) / 16777216.0


# ---------------------------------------------------------------- tempo (chuva, neve...)

## Tempo sorteado pro bloco que contém t (sem o /weather).
func base_weather(t: float) -> int:
	var block := floori(t / GameConfig.WEATHER_BLOCK_S)
	if block <= 0:
		return Weather.CLEAR  # mundo novo começa com tempo limpo
	var start := block * GameConfig.WEATHER_BLOCK_S
	var chances: Array = GameConfig.WEATHER_CHANCES[season_at(start)]
	var weights := []
	var total := 0.0
	var dry := is_dry_spell(start)
	for i in chances.size():
		var wgt := float(chances[i])
		if dry and (i == Weather.RAIN or i == Weather.STORM):
			wgt = 0.0  # seca: não chove
		weights.append(wgt)
		total += wgt
	var r := hash01(seed_value, block, SALT_WEATHER) * total
	for i in weights.size():
		r -= weights[i]
		if r < 0.0:
			return i
	return Weather.CLEAR


## Tempo agora (com o /weather, se tiver).
func weather_at(t: float) -> int:
	for o: Dictionary in overrides:
		if t >= float(o["from"]) and t < float(o["until"]):
			return int(o["weather"])
	return base_weather(t)


static func is_snow(weather: int) -> bool:
	return weather == Weather.SNOW or weather == Weather.BLIZZARD


## Chuva forte: tempestade, ou chuva há mais de um bloco seguido.
func heavy_rain(t: float) -> bool:
	var w := weather_at(t)
	if w == Weather.STORM:
		return true
	if w == Weather.RAIN:
		var before := weather_at(t - GameConfig.WEATHER_BLOCK_S)
		return before == Weather.RAIN or before == Weather.STORM
	return false


## /weather (dev): força um tempo de `from` até `until`; o que estava forçado depois de `from`
## acaba ali. weather < 0 só corta (volta ao normal a partir de `from`). O cliente recebe os
## mesmos números e faz a mesma conta, então os dois ficam com a mesma lista.
func set_override(weather: int, from: float, until: float) -> void:
	var kept: Array = []
	for o: Dictionary in overrides:
		if float(o["from"]) >= from:
			continue
		var c := o.duplicate()
		c["until"] = minf(float(c["until"]), from)
		kept.append(c)
	if weather >= 0 and until > from:
		kept.append({"weather": weather, "from": from, "until": until})
	while kept.size() > MAX_OVERRIDES:
		kept.pop_front()
	_set_overrides(kept)


## Lista inteira (s_welcome: o que já estava forçado quando o jogador entrou).
func set_overrides(list: Array) -> void:
	var clean: Array = []
	for o in list:
		if o is Dictionary and o.has("weather") and o.has("from") and o.has("until"):
			clean.append({"weather": int(o["weather"]), "from": float(o["from"]), "until": float(o["until"])})
	_set_overrides(clean)


func _set_overrides(list: Array) -> void:
	overrides = list
	_override_rev += 1
	_amount_t = NAN


## O trecho forçado que vale agora, ou {}.
func override_at(t: float) -> Dictionary:
	for o: Dictionary in overrides:
		if t >= float(o["from"]) and t < float(o["until"]):
			return o
	return {}


## Os próximos `count` blocos a partir de t: [[início, tempo], ...] (pro /weather).
func forecast(t: float, count: int) -> Array:
	var out := []
	var start := floorf(t / GameConfig.WEATHER_BLOCK_S) * GameConfig.WEATHER_BLOCK_S
	for i in count:
		var bt := start + i * GameConfig.WEATHER_BLOCK_S
		out.append([bt, weather_at(maxf(bt, t))])
	return out


# ---------------------------------------------------------------- seca

## Se o ano `year` (0 = o primeiro) tem seca no fim do verão.
func has_drought(year: int) -> bool:
	return year >= 0 and hash01(seed_value, year, SALT_DROUGHT) < GameConfig.DROUGHT_CHANCE


## Fim do verão do ano que contém t.
static func _summer_end(t: float) -> float:
	var ys := year_s()
	return floorf(t / ys) * ys + season_offset(Season.AUTUMN)


## Força da seca (0 a 1): o rio baixa durante DROUGHT_RAMP_S, fica baixo até o fim do verão e
## volta a encher no começo do outono.
func drought_at(t: float) -> float:
	var ys := year_s()
	if not has_drought(floori(t / ys)):
		return 0.0
	var end := _summer_end(t)
	var start := end - GameConfig.DROUGHT_S
	var ramp := GameConfig.DROUGHT_RAMP_S
	if t < start:
		return 0.0
	if t < start + ramp:
		return smoothstep(0.0, 1.0, (t - start) / ramp)
	if t < end:
		return 1.0
	if t < end + ramp:
		return 1.0 - smoothstep(0.0, 1.0, (t - end) / ramp)
	return 0.0


## Período da seca (fim do verão, nos anos com seca): não chove.
func is_dry_spell(t: float) -> bool:
	var end := _summer_end(t)
	return t >= end - GameConfig.DROUGHT_S and t < end and has_drought(floori(t / year_s()))


## Quando a próxima seca chega no máximo (a partir de t), ou -1 se não tiver nos próximos 50 anos.
func next_drought_peak(t: float) -> float:
	var ys := year_s()
	for y in range(maxi(0, floori(t / ys)), floori(t / ys) + 50):
		if not has_drought(y):
			continue
		var end := y * ys + season_offset(Season.AUTUMN)
		var peak := end - GameConfig.DROUGHT_S + GameConfig.DROUGHT_RAMP_S
		if t <= peak:
			return peak
		if t < end:
			return t  # já está no máximo
	return -1.0


## Altura do leito em que o rio fica com `frac` da largura (mesma conta do leito em
## Terrain._generate_heights).
static func river_level_for_width(frac: float) -> float:
	return Terrain.WATER_LEVEL - 0.3 - Terrain.RIVER_DEPTH * (1.0 - frac * frac)


## Nível da água do rio. Normal: Terrain.WATER_LEVEL; na seca, mais baixo (rio mais estreito).
func water_level(t: float) -> float:
	return lerpf(Terrain.WATER_LEVEL, river_level_for_width(GameConfig.DROUGHT_RIVER_WIDTH), drought_at(t))


## Largura do rio em relação ao normal (1 = normal).
func river_width(t: float) -> float:
	return lerpf(1.0, GameConfig.DROUGHT_RIVER_WIDTH, drought_at(t))


# ---------------------------------------------------------------- neve

## Altura da linha de neve pra neve acumulada `amount` (0 a 1).
static func snow_line(amount: float) -> float:
	return lerpf(GameConfig.SNOW_LINE_HIGH_M, GameConfig.SNOW_LINE_LOW_M, amount)


## Quanto de neve tem no chão (0 a 1) a `h` metros de altura, com a neve acumulada `amount`.
## Acima da linha de neve fica branco; as baixadas pegam menos; debaixo d'água não tem.
static func snow_cover(h: float, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var line := snow_line(amount)
	var c := smoothstep(line, line + GameConfig.SNOW_FADE_M, h)
	c *= lerpf(GameConfig.SNOW_LOWLAND_MIN, 1.0, clampf(h / GameConfig.SNOW_LOWLAND_M, 0.0, 1.0))
	return c * smoothstep(-0.2, 0.4, h)


## Neve acumulada (0 a 1) no instante t.
func snow_amount(t: float) -> float:
	if t == _amount_t:
		return _amount_v
	var block := floori(t / GameConfig.WEATHER_BLOCK_S)
	var b0 := block * GameConfig.WEATHER_BLOCK_S
	if block != _snow_block or _snow_rev != _override_rev:
		_snow_block = block
		_snow_rev = _override_rev
		_snow_block_amount = _integrate(0.0, _snow_zero_before(b0), b0)
	_amount_t = t
	_amount_v = _integrate(_snow_block_amount, b0, t)
	return _amount_v


## Neve no chão (0 a 1) no ponto (x, z).
func snow_cover_at(x: float, z: float, t: float) -> float:
	return snow_cover(terrain.height_at(x, z), snow_amount(t))


## Um instante <= at em que a neve acumulada com certeza é zero, pra somar a partir dele.
func _snow_zero_before(at: float) -> float:
	var z := _natural_zero_before(at)
	# Neve forçada por /weather (dev) pode ainda estar no chão: soma desde antes dela.
	for i in range(overrides.size() - 1, -1, -1):
		var o: Dictionary = overrides[i]
		if float(o["from"]) < at and float(o["until"]) + GameConfig.SNOW_MELT_S > z:
			z = minf(z, _natural_zero_before(float(o["from"])))
	return z


## Sem /weather: no começo do último inverno a neve é zero (o outono não neva e a do inverno
## anterior já derreteu); depois que a neve desse inverno derreteu toda, também.
static func _natural_zero_before(at: float) -> float:
	var ws := last_season_start(at, Season.WINTER)
	if ws < 0.0 or at >= ws + season_length(Season.WINTER) + GameConfig.SNOW_MELT_S:
		return at
	return ws


## Soma a neve de `a` até `b`, trecho a trecho (blocos do tempo e os limites do /weather).
func _integrate(amount: float, a: float, b: float) -> float:
	var x := a
	var block_s := GameConfig.WEATHER_BLOCK_S
	var guard := 0
	while x < b and guard < 100000:
		guard += 1
		var seg_end := minf(b, (floorf(x / block_s) + 1.0) * block_s)
		for o: Dictionary in overrides:
			var f := float(o["from"])
			var u := float(o["until"])
			if f > x and f < seg_end:
				seg_end = f
			if u > x and u < seg_end:
				seg_end = u
		amount = _snow_step(amount, weather_at(x), season_at(x) == Season.WINTER, seg_end - x)
		x = seg_end
	return amount


## Neve acumulada depois de `dt` segundos com esse tempo.
static func _snow_step(amount: float, weather: int, winter: bool, dt: float) -> float:
	var light_rate := GameConfig.SNOW_LIGHT_MAX / GameConfig.SNOW_LIGHT_FILL_S
	if weather == Weather.BLIZZARD:
		return minf(1.0, amount + dt / GameConfig.BLIZZARD_FILL_S)
	if weather == Weather.SNOW:
		if amount >= GameConfig.SNOW_LIGHT_MAX:
			return amount  # neve fraca não derrete o que a nevasca deixou, mas também não soma
		return minf(GameConfig.SNOW_LIGHT_MAX, amount + dt * light_rate)
	# Sem nevar: derrete até o mínimo (picos brancos no inverno, nada fora dele).
	var low := GameConfig.WINTER_SNOW_MIN if winter else 0.0
	if amount > low:
		return maxf(low, amount - dt / GameConfig.SNOW_MELT_S)
	return minf(low, amount + dt * light_rate)


# ---------------------------------------------------------------- água

## Altura das margens ao longo do rio. Os trechos mais baixos (a baixada) nunca congelam.
func _measure_banks() -> void:
	var count := int(terrain.size / BANK_STEP) + 1
	_bank_h.resize(count)
	for i in count:
		var z := i * BANK_STEP
		var cx := terrain.river_center_x(z)
		_bank_h[i] = 0.5 * (terrain.height_at(cx - BANK_OFFSET, z) + terrain.height_at(cx + BANK_OFFSET, z))
	var sorted := Array(_bank_h)
	sorted.sort()
	_open_h = float(sorted[clampi(int(GameConfig.RIVER_NEVER_FREEZE * count), 0, count - 1)])


func bank_count() -> int:
	return _bank_h.size()


func _bank_index(z: float) -> int:
	return clampi(roundi(z / BANK_STEP), 0, _bank_h.size() - 1)


## O trecho do rio que passa em z está congelado com a neve acumulada `amount`?
func is_frozen_at(z: float, amount: float) -> bool:
	var h := _bank_h[_bank_index(z)]
	return h > _open_h and snow_cover(h, amount) >= GameConfig.WATER_FREEZE_COVER


func is_frozen(z: float, t: float) -> bool:
	return is_frozen_at(z, snow_amount(t))


## Dá pra beber em (x, z)? Tem que ter água (o nível baixa na seca) e ela não pode estar congelada.
func is_drinkable(x: float, z: float, t: float) -> bool:
	return terrain.height_at(x, z) < water_level(t) - 0.05 and not is_frozen(z, t)


## Um byte por BANK_STEP de z: 255 = água congelada (pro desenho do gelo no cliente).
func frozen_mask(t: float) -> PackedByteArray:
	var amount := snow_amount(t)
	var out := PackedByteArray()
	out.resize(_bank_h.size())
	for i in _bank_h.size():
		out[i] = 255 if is_frozen_at(i * BANK_STEP, amount) else 0
	return out


## Fração do rio congelada agora (0 a 1).
func frozen_share(t: float) -> float:
	var mask := frozen_mask(t)
	var n := 0
	for b in mask:
		if b > 0:
			n += 1
	return float(n) / maxf(1.0, mask.size())


## Ponto de beber mais perto de `from`, pulando a água congelada; na seca, puxado pro meio do
## rio (que ficou mais estreito). A baixada nunca congela, então sempre acha um.
func nearest_open_water(from: Vector3, t: float) -> Vector3:
	var amount := snow_amount(t)
	if amount <= 0.0 and drought_at(t) <= 0.0:
		return terrain.nearest_water_point(from)  # nada congelado nem seco: o de sempre
	var best := Vector3.ZERO
	var best_d := INF
	for p in terrain.water_points:
		var d := (p.x - from.x) * (p.x - from.x) + (p.z - from.z) * (p.z - from.z)
		if d < best_d and not is_frozen_at(p.z, amount):
			best_d = d
			best = p
	if best_d == INF:
		return terrain.nearest_water_point(from)
	var cx := terrain.river_center_x(best.z)
	return Vector3(cx + (best.x - cx) * river_width(t), water_level(t), best.z)


# ---------------------------------------------------------------- efeitos no mundo

func hunger_mult(t: float) -> float:
	return GameConfig.WINTER_HUNGER_MULT if season_at(t) == Season.WINTER else 1.0


## Corrida em quem está pisando em `cover` de neve (1 = chão todo branco).
static func sprint_mult(cover: float) -> float:
	return lerpf(1.0, GameConfig.SNOW_SPRINT_MULT, clampf(cover, 0.0, 1.0))


## Rebrota dos arbustos: mais no verão; menos na seca e na chuva forte.
func regrow_mult(t: float) -> float:
	var m := GameConfig.SUMMER_REGROW_MULT if season_at(t) == Season.SUMMER else 1.0
	m *= lerpf(1.0, GameConfig.DROUGHT_REGROW_MULT, drought_at(t))
	if heavy_rain(t):
		m *= GameConfig.HEAVY_RAIN_REGROW_MULT
	return m


## Fração de herbívoros que a reposição de bots busca. No verão sobe, mas nunca sai dos limites
## do diretor de população.
func herbivore_share(t: float) -> float:
	if season_at(t) != Season.SUMMER:
		return GameConfig.HERBIVORE_SHARE
	return clampf(GameConfig.SUMMER_HERBIVORE_SHARE,
			GameConfig.HERBIVORE_SHARE - GameConfig.DIRECTOR_SHARE_TOLERANCE,
			GameConfig.HERBIVORE_SHARE + GameConfig.DIRECTOR_SHARE_TOLERANCE)


## População-alvo de bots com a estação (inverno: menos). Ninguém é morto pra chegar nela.
func bot_target(base: int, t: float) -> int:
	if season_at(t) == Season.WINTER:
		return roundi(base * GameConfig.WINTER_BOT_TARGET_MULT)
	return base


## Fome abaixo da qual o bot carnívoro sai pra caçar (inverno: precisa estar com mais fome).
func hunt_hunger_start(normal: float, t: float) -> float:
	if season_at(t) == Season.WINTER:
		return minf(normal, GameConfig.WINTER_HUNT_HUNGER)
	return normal


## Todo passo (WorldSim.step): nível do rio e, em cada bicho ativo, a fome do inverno e a corrida
## na neve (Metabolism e Movement.speeds leem; chega no cliente pelo ST_WALK/ST_SPRINT).
func apply(w: WorldSim) -> void:
	var t := w.world_time
	w.water_level = water_level(t)
	var amount := snow_amount(t)
	var hunger := hunger_mult(t)
	for d: Dino in w.dinos.values():
		if d.sim_tier == WorldSim.SimTier.FROZEN:
			continue
		d.climate_hunger_mult = hunger
		d.climate_sprint_mult = 1.0
		if amount > 0.0:
			d.climate_sprint_mult = sprint_mult(snow_cover(terrain.height_at(d.pos.x, d.pos.z), amount))


## Raio (servidor): cai no minuto `m` de mundo? Só em tempestade, com LIGHTNING_CHANCE_PER_MIN.
func lightning_due(m: int) -> bool:
	return weather_at(m * 60.0) == Weather.STORM \
			and hash01(seed_value, m, SALT_LIGHTNING) < GameConfig.LIGHTNING_CHANCE_PER_MIN


## Todo passo (WorldSim.step): sorteia o raio uma vez por minuto de mundo. Devolve o bot atingido.
func lightning(w: WorldSim) -> Dino:
	var m := floori(w.world_time / 60.0)
	if m == _lightning_minute:
		return null
	_lightning_minute = m
	if not lightning_due(m):
		return null
	return strike(w, hash01(seed_value, m, SALT_LIGHTNING_PICK))


## Raio num bot ativo, escolhido por `pick` (0 a 1). NUNCA num jogador (decisão do Marcelo): só
## entram bots, e só os que estão rodando (congelado não existe pros outros). O bot morre de
## "raio" e vira carcaça. Devolve o bot, ou null se não tinha nenhum.
static func strike(w: WorldSim, pick: float) -> Dino:
	var targets := []
	for d: Dino in w.dinos.values():
		if not d.is_bot:
			continue  # jogador nunca
		if not d.alive or d.sim_tier == WorldSim.SimTier.FROZEN:
			continue
		targets.append(d)
	if targets.is_empty():
		return null
	targets.sort_custom(func(a: Dino, b: Dino): return a.id < b.id)
	var hit: Dino = targets[clampi(int(pick * targets.size()), 0, targets.size() - 1)]
	w.events.append({"type": WorldSim.Ev.LIGHTNING, "a": hit.id, "pos": hit.pos, "species": hit.species})
	w.kill(hit, "raio")
	return hit


# ---------------------------------------------------------------- textos e comandos de dev

## "Chuva", "Limpo · seca"... (HUD).
func weather_text(t: float) -> String:
	var s: String = WEATHER_NAMES[weather_at(t)]
	if drought_at(t) > 0.25:
		s += " · seca"
	return s


## Destino do /time (só pra frente). Palavras: estação ("inverno"), "seca", hora ("22:00", "6")
## e "+N" em tempo de MUNDO: "+2" ou "+2h" (horas; 1 h de mundo = 1 dia no relógio), "+30m"
## (minutos), "+3d" (dias). Devolve {"t": tempo novo} ou {"error": texto}.
func skip_target(t: float, words: PackedStringArray) -> Dictionary:
	var target := t
	for raw in words:
		var w := raw.strip_edges().to_lower()
		if SEASON_WORDS.has(w):
			var s: int = SEASON_WORDS[w]
			if season_at(target) != s:
				target = next_season_start(target, s)
		elif w == "seca":
			var peak := next_drought_peak(target)
			if peak < 0.0:
				return {"error": "Nenhuma seca nos próximos 50 anos com esta semente."}
			target = peak
		elif w.begins_with("+") and _parse_span(w.substr(1)) > 0.0:
			target += _parse_span(w.substr(1))
		elif _parse_clock(w) >= 0:
			var tod := fposmod((_parse_clock(w) / 60.0 - GameConfig.CLOCK_SUNRISE_H) / 24.0, 1.0) * GameConfig.DAY_S
			var at := floorf(target / GameConfig.DAY_S) * GameConfig.DAY_S + tod
			if at < target:
				at += GameConfig.DAY_S
			target = at
		else:
			return {"error": "Uso: /time [primavera|verao|outono|inverno|seca] [hh:mm] [+2h|+30m|+3d] (tempo de mundo)"}
	return {"t": target}


## "2", "2h", "30m", "30min", "3d" → segundos de mundo; -1 se não entender.
static func _parse_span(w: String) -> float:
	var units := {"min": 60.0, "m": 60.0, "h": 3600.0, "d": GameConfig.DAY_S, "": 3600.0}
	for suffix in ["min", "m", "h", "d", ""]:
		if w.ends_with(suffix):
			var num := w.substr(0, w.length() - suffix.length())
			if num.is_valid_float() and num.to_float() > 0.0:
				return num.to_float() * float(units[suffix])
	return -1.0


## "22:00", "22h", "6" → minutos do relógio (0 a 1439); -1 se não for hora.
static func _parse_clock(w: String) -> int:
	var parts := w.trim_suffix("h").split(":")
	if parts.size() > 2 or not parts[0].is_valid_int():
		return -1
	var h := parts[0].to_int()
	var m := parts[1].to_int() if parts.size() == 2 and parts[1].is_valid_int() else 0
	if parts.size() == 2 and not parts[1].is_valid_int():
		return -1
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m


## Comandos de dev do clima (só o servidor em --dev): /time, /weather, /clima, /raio. Mexe no
## mundo e põe em w.events o que os clientes precisam saber. Devolve o texto da resposta.
func dev_command(w: WorldSim, words: PackedStringArray) -> String:
	var cmd := words[0].to_lower()
	var args := words.slice(1)
	var t := w.world_time
	match cmd:
		"/time":
			if args.is_empty():
				return "Agora: %s · %s (tempo do mundo %.0f s)" % [calendar_text(t), weather_text(t), t]
			var r := skip_target(t, args)
			if r.has("error"):
				return r["error"]
			w.world_time = float(r["t"])
			return "Tempo pulou %.1f h: %s · %s" % [(w.world_time - t) / 3600.0,
					calendar_text(w.world_time), weather_text(w.world_time)]
		"/weather":
			if args.is_empty():
				var next := []
				for f in forecast(t, 6).slice(1):
					next.append("%s %s" % [clock_text(f[0]), WEATHER_NAMES[f[1]]])
				return "Tempo: %s%s · depois: %s" % [WEATHER_NAMES[weather_at(t)],
						" (forçado)" if not override_at(t).is_empty() else "", ", ".join(next)]
			var word := args[0].to_lower()
			if word == "auto":
				set_override(-1, t, t)
				w.events.append({"type": WorldSim.Ev.WEATHER, "weather": -1, "from": t, "until": t})
				return "Tempo volta ao normal: " + weather_text(t)
			if not WEATHER_WORDS.has(word):
				return "Uso: /weather limpo|nublado|chuva|tempestade|neve|nevasca [minutos] (ou auto)"
			var minutes := args[1].to_float() if args.size() > 1 and args[1].is_valid_float() else 20.0
			minutes = clampf(minutes, 1.0, 600.0)
			set_override(WEATHER_WORDS[word], t, t + minutes * 60.0)
			w.events.append({"type": WorldSim.Ev.WEATHER, "weather": WEATHER_WORDS[word],
					"from": t, "until": t + minutes * 60.0})
			return "Tempo forçado: %s por %.0f min (só até o servidor reiniciar)" % [WEATHER_NAMES[WEATHER_WORDS[word]], minutes]
		"/raio":
			var hit := strike(w, randf())
			if hit == null:
				return "Nenhum bot ativo perto pra cair o raio (raio nunca atinge jogador)."
			return "Raio caiu num %s" % Species.display_name(hit.species)
		"/clima":
			return status_line(w)
	return ""


## Estado do clima pro /clima. O pedaço entre colchetes é lido pelo teste de rede.
func status_line(w: WorldSim) -> String:
	var t := w.world_time
	var amount := snow_amount(t)
	return "%s · %s · neve %d%% · rio %d%% congelado · água %.2f m · rebrota x%.2f · bots alvo %d · herbívoros %d%% [t=%.4f neve=%.5f tempo=%d agua=%.4f estacao=%d]" % [
		calendar_text(t), weather_text(t), roundi(amount * 100.0), roundi(frozen_share(t) * 100.0),
		water_level(t), regrow_mult(t), w.effective_bot_target(), roundi(herbivore_share(t) * 100.0),
		t, amount, weather_at(t), water_level(t), season_at(t)]
