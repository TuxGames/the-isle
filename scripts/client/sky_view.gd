class_name SkyView
extends Node3D
## Dia e noite no cliente (design, seção 11): sol, lua, cor do céu, luz ambiente e neblina,
## calculados do tempo do mundo (Climate.daylight), mais o céu fechado do tempo ruim e o clarão
## do raio. Só desenho: nada aqui muda o jogo. O WeatherView chama update() todo quadro.
## A noite é escura mas dá pra jogar: a lua ilumina e a luz ambiente fica azulada, nunca preta.

const SUN_ENERGY := 0.85
const MOON_ENERGY := 0.3
const SUN_MAX_ELEV := 55.0
const MOON_MAX_ELEV := 40.0
## Luz ambiente (o céu do Godot ilumina pela metade; a outra metade é esta cor). De dia fica
## preta, como antes do clima: só a noite ganha o azul que deixa tudo visível.
const NIGHT_AMBIENT := Color(0.36, 0.42, 0.6)
const DAY_AMBIENT_ENERGY := 0.3
const NIGHT_AMBIENT_ENERGY := 0.95

const DAY_TOP := Color(0.32, 0.5, 0.75)
const DAY_HORIZON := Color(0.62, 0.7, 0.76)
const DAY_GROUND_HORIZON := Color(0.6, 0.62, 0.6)
const DAY_GROUND_BOTTOM := Color(0.25, 0.28, 0.25)
const DUSK_TOP := Color(0.3, 0.33, 0.52)
const DUSK_HORIZON := Color(0.92, 0.56, 0.32)
const NIGHT_TOP := Color(0.03, 0.045, 0.1)
const NIGHT_HORIZON := Color(0.09, 0.12, 0.2)
const NIGHT_GROUND := Color(0.05, 0.06, 0.08)
## Céu fechado (nublado, chuva, neve), na luz do dia.
const OVERCAST := Color(0.56, 0.58, 0.61)
const DAY_FOG := Color(0.55, 0.62, 0.68)
const NIGHT_FOG := Color(0.07, 0.09, 0.14)
const SUN_WARM := Color(1.0, 0.6, 0.36)
const SUN_WHITE := Color(1.0, 0.96, 0.88)

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var moon: DirectionalLight3D
## Clarão do raio (0 a 1); apaga sozinho.
var flash := 0.0


func setup(terrain_view: TerrainView) -> void:
	env = terrain_view.get_environment()
	sun = terrain_view.get_sun()
	sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


## t: tempo do mundo; overcast: 0 (limpo) a 1 (tempestade); gloom: quanto o tempo pesado
## escurece o céu (chuva forte, nevasca); fog_mult: quanto a neblina engrossa (chuva e neve);
## fog_base: a neblina da distância de visão (TerrainView).
func update(t: float, overcast: float, gloom: float, fog_mult: float, fog_base: float, delta: float) -> void:
	if env == null:
		return
	flash = maxf(0.0, flash - delta * 5.0)
	var d := Climate.daylight(t)
	var tod := Climate.time_of_day(t)
	var light_s := GameConfig.DAY_S - GameConfig.NIGHT_S
	var half := GameConfig.TWILIGHT_S * 0.5

	# Sol: arco de leste a oeste, do começo do amanhecer ao fim do entardecer.
	var x := tod
	if x > GameConfig.DAY_S - half:
		x -= GameConfig.DAY_S
	var f := clampf((x + half) / (light_s + 2.0 * half), 0.0, 1.0)
	var elev := sin(PI * f) * SUN_MAX_ELEV
	sun.rotation_degrees = Vector3(-maxf(elev, 4.0), lerpf(95.0, -95.0, f), 0.0)
	sun.light_energy = SUN_ENERGY * d * (1.0 - 0.72 * overcast)
	sun.light_color = SUN_WARM.lerp(SUN_WHITE, smoothstep(2.0, 25.0, elev))
	sun.visible = sun.light_energy > 0.002
	# Céu fechado esconde o disco do sol.
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if overcast < 0.5 else DirectionalLight3D.SKY_MODE_LIGHT_ONLY

	# Lua: arco durante a noite, nunca rente ao chão.
	var g := clampf((tod - light_s) / GameConfig.NIGHT_S, 0.0, 1.0)
	moon.rotation_degrees = Vector3(-(15.0 + sin(PI * g) * (MOON_MAX_ELEV - 15.0)), lerpf(80.0, -80.0, g), 0.0)
	moon.light_energy = MOON_ENERGY * (1.0 - d) * (1.0 - 0.5 * overcast)
	moon.visible = moon.light_energy > 0.002

	# Céu: noite → dia, laranja no amanhecer/entardecer, cinza com tempo fechado.
	var dusk := clampf(1.0 - absf(d * 2.0 - 1.0), 0.0, 1.0) * (1.0 - overcast)
	var gray := OVERCAST * lerpf(0.14, 1.0, d) * (1.0 - gloom)
	var top := NIGHT_TOP.lerp(DAY_TOP, d).lerp(DUSK_TOP, dusk * 0.6).lerp(gray * 0.9, overcast)
	var hor := NIGHT_HORIZON.lerp(DAY_HORIZON, d).lerp(DUSK_HORIZON, dusk * 0.75).lerp(gray, overcast)
	var ground_h := NIGHT_GROUND.lerp(DAY_GROUND_HORIZON, d).lerp(gray * 0.95, overcast)
	var ground_b := NIGHT_GROUND.lerp(DAY_GROUND_BOTTOM, d)
	var white := Color(0.85, 0.88, 1.0)
	sky_mat.sky_top_color = top.lerp(white, flash * 0.7)
	sky_mat.sky_horizon_color = hor.lerp(white, flash * 0.7)
	sky_mat.ground_horizon_color = ground_h.lerp(white, flash * 0.4)
	sky_mat.ground_bottom_color = ground_b

	# Luz ambiente: a noite nunca fica preta.
	env.ambient_light_color = NIGHT_AMBIENT * (1.0 - d) + white * flash
	env.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, d) + flash * 1.5

	# Neblina: escura à noite, cinza e mais grossa com chuva e neve.
	env.fog_light_color = NIGHT_FOG.lerp(DAY_FOG, d).lerp(gray, overcast * 0.8).lerp(white, flash * 0.5)
	env.fog_density = fog_base * fog_mult
