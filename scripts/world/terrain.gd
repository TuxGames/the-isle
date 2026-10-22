class_name Terrain
extends RefCounted
## Terreno do mapa v0.1: 512 m x 512 m, gerado por código a partir de uma semente.
## Servidor e clientes chamam Terrain.get_shared(seed) e obtêm exatamente o mesmo mapa.
## O servidor só usa a altura (pés dos dinos, água); o cliente também desenha a malha.

const SIZE := 512.0
const RES := 2.0
const N := 257  # vértices por lado = SIZE / RES + 1

const WATER_LEVEL := 0.0
const RIVER_HALF_WIDTH := 9.0
const RIVER_DEPTH := 3.0
const BANK_WIDTH := 12.0

const BORDER := 30.0
## Área jogável (os dinos não passam daqui).
const PLAY_MIN := 14.0
const PLAY_MAX := SIZE - 14.0

const BUSH_COUNT := 240
const BUSH_RADIUS := 1.4

static var _cache := {}

var seed_value: int
var heights := PackedFloat32Array()
## Posição de cada arbusto (comida dos herbívoros). O índice é o id do arbusto.
var bushes := PackedVector3Array()
## Pontos de água rasa onde os bots vão beber.
var water_points := PackedVector3Array()


## Use isso em vez de Terrain.new(): gera uma vez e reaproveita.
static func get_shared(p_seed: int) -> Terrain:
	if not _cache.has(p_seed):
		_cache[p_seed] = Terrain.new(p_seed)
	return _cache[p_seed]


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_generate_heights()
	_generate_bushes()
	_generate_water_points()


## Centro do rio (coordenada X) em cada Z. O rio atravessa o mapa de norte a sul.
static func river_center_x(z: float) -> float:
	return SIZE * 0.5 + 70.0 * sin(z * 0.012) + 22.0 * sin(z * 0.033 + 1.3)


func _generate_heights() -> void:
	var base := FastNoiseLite.new()
	base.seed = seed_value
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.0045
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 4

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 7
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.035
	detail.fractal_octaves = 2

	heights.resize(N * N)
	for iz in N:
		var z := iz * RES
		var cx := river_center_x(z)
		for ix in N:
			var x := ix * RES
			var n := base.get_noise_2d(x, z) * 0.5 + 0.5
			var h := 4.0 + n * n * 30.0 + detail.get_noise_2d(x, z) * 1.0

			# Montanhas na borda: fecham o mapa e têm neve no topo.
			var edge := minf(minf(x, z), minf(SIZE - x, SIZE - z))
			if edge < BORDER:
				var t := 1.0 - edge / BORDER
				h += smoothstep(0.0, 1.0, t) * 40.0

			# Rio: leito abaixo da água e margens suaves.
			var d := absf(x - cx)
			if d < RIVER_HALF_WIDTH:
				var t := d / RIVER_HALF_WIDTH
				h = WATER_LEVEL - 0.3 - RIVER_DEPTH * (1.0 - t * t)
			elif d < RIVER_HALF_WIDTH + BANK_WIDTH:
				var t := smoothstep(0.0, 1.0, (d - RIVER_HALF_WIDTH) / BANK_WIDTH)
				h = lerpf(WATER_LEVEL - 0.3, h, t)

			heights[iz * N + ix] = h


func _generate_bushes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 101
	var tries := 0
	while bushes.size() < BUSH_COUNT and tries < BUSH_COUNT * 40:
		tries += 1
		var x := rng.randf_range(BORDER, SIZE - BORDER)
		var z := rng.randf_range(BORDER, SIZE - BORDER)
		var h := height_at(x, z)
		if h < 0.8 or h > 26.0:
			continue
		if slope_at(x, z) > 0.6:
			continue
		if absf(x - river_center_x(z)) < RIVER_HALF_WIDTH + 3.0:
			continue
		bushes.append(Vector3(x, h, z))


func _generate_water_points() -> void:
	var z := 24.0
	while z < SIZE - 24.0:
		var cx := river_center_x(z)
		var off := RIVER_HALF_WIDTH * 0.75
		water_points.append(Vector3(cx - off, WATER_LEVEL, z))
		water_points.append(Vector3(cx + off, WATER_LEVEL, z))
		z += 8.0


## Altura do chão em (x, z), interpolada da grade.
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / RES, 0.0, N - 1.001)
	var fz := clampf(z / RES, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + N]
	var h11 := heights[i + N + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Inclinação (tangente) do terreno: 0 = plano, 1 = 45 graus.
func slope_at(x: float, z: float) -> float:
	var e := RES
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return sqrt(dx * dx + dz * dz)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_LEVEL - 0.05


func water_depth(x: float, z: float) -> float:
	return maxf(0.0, WATER_LEVEL - height_at(x, z))


static func clamp_to_play_area(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, PLAY_MIN, PLAY_MAX), p.y, clampf(p.z, PLAY_MIN, PLAY_MAX))


## Ponto aleatório em terra firme, dentro da área jogável e fora das montanhas.
func random_land_point(rng: RandomNumberGenerator) -> Vector3:
	for i in 200:
		var x := rng.randf_range(BORDER + 6.0, SIZE - BORDER - 6.0)
		var z := rng.randf_range(BORDER + 6.0, SIZE - BORDER - 6.0)
		var h := height_at(x, z)
		if h > 0.6 and h < 26.0 and slope_at(x, z) < 0.7:
			return Vector3(x, h, z)
	return Vector3(SIZE * 0.5 + 40.0, height_at(SIZE * 0.5 + 40.0, SIZE * 0.5), SIZE * 0.5)


func nearest_water_point(from: Vector3) -> Vector3:
	var best := water_points[0]
	var best_d := INF
	for p in water_points:
		var d := Vector2(p.x - from.x, p.z - from.z).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best
