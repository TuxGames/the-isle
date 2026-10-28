class_name WeatherView
extends Node3D
## Clima no cliente (design, seção 11). Calcula o MESMO Climate do servidor a partir da semente
## (login) e do tempo do mundo (ST_WORLD_TIME), e desenha:
## - dia e noite e o céu fechado (SkyView);
## - chuva e neve como partículas simples numa caixa em volta da câmera;
## - neve no chão, gelo no rio e o rio mais baixo na seca (TerrainView.set_climate);
## - o clarão do raio (evento do servidor) e clarões de fundo na tempestade.
## Só desenho: quem decide fome, neve nos pés, água e raio é o servidor.

signal weather_text_changed(text: String)

## Como cada tempo aparece: [céu fechado, chuva, neve] de 0 a 1 (ordem de Climate.Weather).
const LOOK := [
	[0.0, 0.0, 0.0],  # limpo
	[0.55, 0.0, 0.0],  # nublado
	[0.75, 0.5, 0.0],  # chuva
	[0.95, 1.0, 0.0],  # tempestade
	[0.7, 0.0, 0.45],  # neve
	[0.95, 0.0, 1.0],  # nevasca
]
## Segundos (de tela) pra um tempo virar o outro.
const BLEND_S := 10.0
const RAIN_MAX := 2600
const SNOW_MAX := 3200
## Metade do lado da caixa onde nascem as gotas e os flocos, em volta da câmera.
const FIELD := 30.0

var climate: Climate
var terrain_view: TerrainView
var sky: SkyView
## Tempo do mundo neste PC: o último ST_WORLD_TIME + o que passou desde ele. -1 = fora do jogo.
var time := -1.0

## Céu fechado, chuva e neve agora (suavizados).
var _look := Vector3.ZERO
var _snap_look := true
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _rain_mat: StandardMaterial3D
var _snow_mat: StandardMaterial3D
var _flash_rect: ColorRect
var _ice_tex: ImageTexture
var _ice_bytes := PackedByteArray()
var _ground_refresh := 0.0
var _text := ""
var _ambient_flash_in := 10.0


static func create(p_terrain: Terrain, p_view: TerrainView, p_seed: int) -> WeatherView:
	var v := WeatherView.new()
	v.name = "WeatherView"
	v.climate = Climate.new(p_seed, p_terrain)
	v.terrain_view = p_view
	return v


func _ready() -> void:
	sky = SkyView.new()
	sky.name = "Sky"
	add_child(sky)
	sky.setup(terrain_view)
	_rain_mat = _particle_material(BaseMaterial3D.BILLBOARD_FIXED_Y)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.75)
	_rain = _particles("Rain", drop, _rain_mat, RAIN_MAX, 0.9, 14.0)
	_rain.direction = Vector3(0.05, -1.0, 0.0)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 20.0
	_rain.initial_velocity_max = 24.0
	_rain.gravity = Vector3(0.0, -10.0, 0.0)
	_snow_mat = _particle_material(BaseMaterial3D.BILLBOARD_ENABLED)
	# Floco redondo e macio (bolinha branca que some na borda), sem arquivo de imagem.
	var round := Gradient.new()
	round.set_color(0, Color(1, 1, 1, 1))
	round.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = round
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 16
	dot.height = 16
	_snow_mat.albedo_texture = dot
	var flake := QuadMesh.new()
	flake.size = Vector2(0.14, 0.14)
	_snow = _particles("Snow", flake, _snow_mat, SNOW_MAX, 6.0, 11.0)
	_snow.direction = Vector3(0.0, -1.0, 0.0)
	_snow.spread = 25.0
	_snow.initial_velocity_min = 1.6
	_snow.initial_velocity_max = 2.6
	_snow.gravity = Vector3(0.0, -0.5, 0.0)
	# Clarão do raio na tela inteira, por baixo do HUD.
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.9, 0.93, 1.0, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash_rect)
	_ice_tex = ImageTexture.new()


func _particle_material(billboard: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _particles(p_name: String, mesh: PrimitiveMesh, mat: Material, amount: int, life: float, height: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = p_name
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = true
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(FIELD, 2.0, FIELD)
	p.position = Vector3(0.0, height, 0.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


# ---------------------------------------------------------------- vindo do servidor

## Tempo do mundo do servidor (ST_WORLD_TIME, 10x por segundo; ou o do s_welcome).
func sync_time(t: float) -> void:
	time = t


## /weather (dev) que o servidor mandou: weather < 0 = voltou ao normal a partir de `from`.
func set_override(weather: int, from: float, until: float) -> void:
	climate.set_override(weather, from, until)


## Os /weather que já valiam quando o jogador entrou (s_welcome).
func set_overrides(list: Array) -> void:
	climate.set_overrides(list)


## Saiu do jogo: para de andar o relógio e a chuva.
func pause() -> void:
	time = -1.0
	_snap_look = true
	_rain.emitting = false
	_snow.emitting = false


## Raio caiu em `pos` (Ev.LIGHTNING): risco de luz do céu até o chão e clarão.
func lightning(pos: Vector3) -> void:
	_flash(1.0)
	var bolt := Node3D.new()
	bolt.name = "Lightning"
	bolt.top_level = true  # este nó segue a câmera; o raio fica parado no mundo
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.95, 1.0)
	# Zigue-zague: pedaços curtos perto do chão, mais longos e tortos lá em cima.
	var heights := [4.0, 10.0, 18.0, 29.0, 43.0, 62.0, 88.0, 140.0]
	var a := pos
	for i in heights.size():
		var wobble := 1.5 + i * 1.2
		var b := pos + Vector3(randf_range(-wobble, wobble), heights[i], randf_range(-wobble, wobble))
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.35, a.distance_to(b))
		box.material = mat
		seg.mesh = box
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt.add_child(seg)
		seg.transform = Transform3D(Basis.looking_at(b - a, Vector3.RIGHT), (a + b) * 0.5)
		a = b
	add_child(bolt)
	get_tree().create_timer(0.25).timeout.connect(bolt.queue_free)


func _flash(strength: float) -> void:
	sky.flash = maxf(sky.flash, strength)
	_flash_rect.color.a = maxf(_flash_rect.color.a, 0.5 * strength)


# ---------------------------------------------------------------- consultas (GameClient)

func ready_to_use() -> bool:
	return time >= 0.0


func water_level() -> float:
	return climate.water_level(time) if time >= 0.0 else Terrain.WATER_LEVEL


func can_drink(x: float, z: float) -> bool:
	return climate.is_drinkable(x, z, time) if time >= 0.0 else climate.terrain.is_water(x, z)


func is_frozen(z: float) -> bool:
	return time >= 0.0 and climate.is_frozen(z, time)


# ---------------------------------------------------------------- quadro a quadro

func _process(delta: float) -> void:
	_flash_rect.color.a = maxf(0.0, _flash_rect.color.a - delta * 2.5)
	if time < 0.0:
		return
	time += delta
	var w := climate.weather_at(time)
	var want: Array = LOOK[w]
	var target := Vector3(want[0], want[1], want[2])
	_look = target if _snap_look else _look.lerp(target, clampf(delta / BLEND_S * 3.0, 0.0, 1.0))
	_snap_look = false

	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
	var day := Climate.daylight(time)
	_set_intensity(_rain, RAIN_MAX, _look.y)
	_rain_mat.albedo_color = Color(0.72, 0.78, 0.9, 0.32 * minf(1.0, _look.y * 2.0)) \
			* Color(1, 1, 1, 1).lerp(Color(0.3, 0.32, 0.4, 1), 1.0 - day)
	_set_intensity(_snow, SNOW_MAX, _look.z)
	# Nevasca: vento de lado e flocos mais rápidos.
	var wind := clampf((_look.z - 0.5) * 2.0, 0.0, 1.0)
	_snow.direction = Vector3(0.9 * wind, -1.0, 0.35 * wind)
	_snow.initial_velocity_max = 2.6 + 4.0 * wind
	_snow_mat.albedo_color = Color(0.95, 0.96, 1.0, 0.9 * minf(1.0, _look.z * 2.0)) \
			* Color(1, 1, 1, 1).lerp(Color(0.35, 0.38, 0.48, 1), 1.0 - day)

	var fog_base := TerrainView.FOG_DENSITY * TerrainView.MAX_VIEW_DIST / maxf(terrain_view.view_distance, 1.0)
	var fog_mult := 1.0 + 0.6 * _look.x + 0.8 * _look.y + 2.5 * _look.z
	sky.update(time, _look.x, 0.35 * maxf(_look.y, _look.z), fog_mult, fog_base, delta)

	_ground_refresh -= delta
	if _ground_refresh <= 0.0:
		_ground_refresh = 0.5
		_update_ground()

	var text := climate.weather_text(time)
	if text != _text:
		_text = text
		weather_text_changed.emit(text)

	# Tempestade: clarões de fundo de vez em quando (só desenho; o raio de verdade vem do servidor).
	if w == Climate.Weather.STORM:
		_ambient_flash_in -= delta
		if _ambient_flash_in <= 0.0:
			_ambient_flash_in = randf_range(8.0, 25.0)
			_flash(randf_range(0.25, 0.45))


## Quantas gotas/flocos: em degraus de 25% (trocar a quantidade reinicia as partículas, então
## só troca quando o tempo muda); a transparência acompanha a troca suave.
func _set_intensity(p: CPUParticles3D, max_amount: int, k: float) -> void:
	var step := ceilf(k * 4.0 - 0.05) / 4.0
	p.emitting = step > 0.0
	if step > 0.0:
		var want := maxi(1, roundi(max_amount * step))
		if p.amount != want:
			p.amount = want


## Neve no chão, nível do rio e gelo (meio segundo de atraso não aparece).
func _update_ground() -> void:
	var amount := climate.snow_amount(time)
	var line := Climate.snow_line(amount) if amount > 0.0 else 1000.0
	var mask := climate.frozen_mask(time)
	var tex: Texture2D = null
	if mask != _ice_bytes:
		_ice_bytes = mask
		var img := Image.create_from_data(mask.size(), 1, false, Image.FORMAT_L8, mask)
		if _ice_tex.get_width() == mask.size():
			_ice_tex.update(img)
		else:
			_ice_tex.set_image(img)
		tex = _ice_tex
	terrain_view.set_climate(line, climate.water_level(time), tex, mask.size())


## Texto do HUD agora ("Chuva", "Limpo · seca").
func weather_text() -> String:
	return _text
