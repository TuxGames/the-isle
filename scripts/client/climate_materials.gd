class_name ClimateMaterials
extends RefCounted
## Materiais do terreno e da água que mostram o clima (design, seção 11), usados pelo TerrainView.
## Tudo é feito na placa de vídeo com contas simples (roda no renderizador Compatibilidade, em
## vídeo integrado): o terreno fica branco acima da linha de neve e o rio vira gelo nos trechos
## congelados. Os números vêm do mesmo Climate do servidor (WeatherView manda).

## Chão: cor dos vértices (sRGB, como antes) + neve pela altura, igual a Climate.snow_cover.
## Encosta íngreme segura um pouco menos de neve (só no desenho; a regra do jogo é só a altura).
const GROUND_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float snow_line = 1000.0;
uniform float snow_fade = 10.0;
uniform float lowland_h = 12.0;
uniform float lowland_min = 0.5;
uniform vec3 snow_color : source_color = vec3(0.8, 0.83, 0.88);

varying float world_y;
varying float up;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	up = NORMAL.y;
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	float cover = smoothstep(snow_line, snow_line + snow_fade, world_y);
	cover *= mix(lowland_min, 1.0, clamp(world_y / lowland_h, 0.0, 1.0));
	cover *= smoothstep(-0.2, 0.4, world_y);
	cover *= mix(0.6, 1.0, smoothstep(0.55, 0.85, up));
	ALBEDO = mix(COLOR.rgb, snow_color, clamp(cover, 0.0, 1.0));
	ROUGHNESS = 0.95;
}
"""

## Arbustos: verde de sempre, com neve por cima (onde a face aponta pro céu) pela mesma regra
## de altura do chão.
const BUSH_SHADER := """
shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.18, 0.36, 0.13);
uniform float snow_line = 1000.0;
uniform float snow_fade = 10.0;
uniform float lowland_h = 12.0;
uniform float lowland_min = 0.5;
uniform vec3 snow_color : source_color = vec3(0.8, 0.83, 0.88);

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float cover = smoothstep(snow_line, snow_line + snow_fade, wp.y);
	cover *= mix(lowland_min, 1.0, clamp(wp.y / lowland_h, 0.0, 1.0));
	cover *= smoothstep(0.15, 0.6, wn.y);
	ALBEDO = mix(albedo, snow_color, clamp(cover, 0.0, 1.0) * 0.9);
	ROUGHNESS = 1.0;
}
"""

## Água: um plano só no nível do rio. `ice_map` tem um texel por Climate.BANK_STEP metros de z
## (o rio corre de norte a sul): 1 = congelado. O plano desce na seca (TerrainView.set_climate).
const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 water_color : source_color = vec4(0.1, 0.26, 0.3, 0.86);
uniform vec4 ice_color : source_color = vec4(0.62, 0.76, 0.86, 0.95);
uniform sampler2D ice_map : hint_default_black, filter_linear, repeat_disable;
uniform float ice_step = 8.0;
uniform float ice_count = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ice = texture(ice_map, vec2((world_pos.z / ice_step + 0.5) / ice_count, 0.5)).r;
	ice = smoothstep(0.25, 0.75, ice);
	vec4 c = mix(water_color, ice_color, ice);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = mix(0.55, 0.8, ice);
	SPECULAR = 0.15;
	METALLIC = 0.0;
}
"""

static var _ground_shader: Shader
static var _bush_shader: Shader
static var _water_shader: Shader


static func ground() -> ShaderMaterial:
	if _ground_shader == null:
		_ground_shader = Shader.new()
		_ground_shader.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = _ground_shader
	m.set_shader_parameter("snow_fade", GameConfig.SNOW_FADE_M)
	m.set_shader_parameter("lowland_h", GameConfig.SNOW_LOWLAND_M)
	m.set_shader_parameter("lowland_min", GameConfig.SNOW_LOWLAND_MIN)
	m.set_shader_parameter("snow_line", 1000.0)
	return m


static func bush() -> ShaderMaterial:
	if _bush_shader == null:
		_bush_shader = Shader.new()
		_bush_shader.code = BUSH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _bush_shader
	m.set_shader_parameter("snow_fade", GameConfig.SNOW_FADE_M)
	m.set_shader_parameter("lowland_h", GameConfig.SNOW_LOWLAND_M)
	m.set_shader_parameter("lowland_min", GameConfig.SNOW_LOWLAND_MIN)
	m.set_shader_parameter("snow_line", 1000.0)
	return m


static func water() -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.set_shader_parameter("ice_step", Climate.BANK_STEP)
	return m
