class_name Terrain
extends RefCounted
## Terreno gerado por código a partir de uma semente e do tamanho do mapa (lado, em metros).
## Servidor e clientes chamam Terrain.get_shared(seed, tamanho) e obtêm exatamente o mesmo mapa.
## O servidor só usa a altura (pés dos dinos, água); o cliente também desenha a malha.
## Com 512 m sai o mesmo mapa da v0.1, então os saves antigos continuam batendo.

const RES := 2.0
## Tamanhos aceitos; o pedido é arredondado pra múltiplo de SIZE_STEP.
const MIN_SIZE := 256.0
const MAX_SIZE := 8192.0
const SIZE_STEP := 64.0

const WATER_LEVEL := 0.0
const RIVER_HALF_WIDTH := 9.0
const RIVER_DEPTH := 3.0
const BANK_WIDTH := 12.0

const BORDER := 30.0
## Os dinos param a esta distância da borda do mapa.
const PLAY_MARGIN := 14.0

## Arbustos (comida dos herbívoros) a cada 512 m x 512 m; num mapa maior, proporcional à área.
const BUSHES_PER_512 := 240
const BUSH_RADIUS := 1.4
## Lado da célula da grade de arbustos (pra achar os arbustos perto de um ponto sem olhar todos).
const BUSH_CELL := 32.0

static var _cache := {}

var seed_value: int
## Lado do mapa em metros.
var size: float
## Vértices por lado (size / RES + 1).
var n: int
## Área jogável (os dinos não passam daqui).
var play_min: float
var play_max: float
var heights := PackedFloat32Array()
## Posição de cada arbusto (comida dos herbívoros). O índice é o id do arbusto.
var bushes := PackedVector3Array()
## Pontos de água rasa onde os bots vão beber.
var water_points := PackedVector3Array()
## Célula (Vector2i) -> índices dos arbustos nela.
var _bush_grid := {}


## Use isso em vez de Terrain.new(): gera uma vez e reaproveita.
static func get_shared(p_seed: int, p_size: float = GameConfig.DEFAULT_MAP_SIZE) -> Terrain:
	var s := normalize_size(p_size)
	var key := "%d:%d" % [p_seed, int(s)]
	if not _cache.has(key):
		_cache[key] = Terrain.new(p_seed, s)
	return _cache[key]


## Tamanho válido mais próximo do pedido (múltiplo de SIZE_STEP, entre MIN_SIZE e MAX_SIZE).
static func normalize_size(s: float) -> float:
	return clampf(snappedf(s, SIZE_STEP), MIN_SIZE, MAX_SIZE)


func _init(p_seed: int, p_size: float = GameConfig.DEFAULT_MAP_SIZE) -> void:
	seed_value = p_seed
	size = normalize_size(p_size)
	n = int(size / RES) + 1
	play_min = PLAY_MARGIN
	play_max = size - PLAY_MARGIN
	_generate_heights()
	_generate_bushes()
	_generate_water_points()


## Centro do rio (coordenada X) em cada Z. O rio atravessa o mapa de norte a sul e as curvas
## crescem junto com o mapa (com 512 m é o mesmo rio da v0.1).
func river_center_x(z: float) -> float:
	var k := size / 512.0
	return size * 0.5 + 70.0 * k * sin(z * 0.012 / k) + 22.0 * k * sin(z * 0.033 / k + 1.3)


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

	heights.resize(n * n)
	for iz in n:
		var z := iz * RES
		var cx := river_center_x(z)
		for ix in n:
			var x := ix * RES
			var nv := base.get_noise_2d(x, z) * 0.5 + 0.5
			var h := 4.0 + nv * nv * 30.0 + detail.get_noise_2d(x, z) * 1.0

			# Montanhas na borda: fecham o mapa e têm neve no topo.
			var edge := minf(minf(x, z), minf(size - x, size - z))
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

			heights[iz * n + ix] = h


## Quantos arbustos este mapa tem (240 a cada 512 m x 512 m).
func bush_count() -> int:
	return roundi(BUSHES_PER_512 * (size / 512.0) * (size / 512.0))


func _generate_bushes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 101
	var want := bush_count()
	var tries := 0
	while bushes.size() < want and tries < want * 40:
		tries += 1
		var x := rng.randf_range(BORDER, size - BORDER)
		var z := rng.randf_range(BORDER, size - BORDER)
		var h := height_at(x, z)
		if h < 0.8 or h > 26.0:
			continue
		if slope_at(x, z) > 0.6:
			continue
		if absf(x - river_center_x(z)) < RIVER_HALF_WIDTH + 3.0:
			continue
		var key := Vector2i(floori(x / BUSH_CELL), floori(z / BUSH_CELL))
		if not _bush_grid.has(key):
			_bush_grid[key] = PackedInt32Array()
		_bush_grid[key].append(bushes.size())
		bushes.append(Vector3(x, h, z))


func _generate_water_points() -> void:
	var z := 24.0
	while z < size - 24.0:
		var cx := river_center_x(z)
		var off := RIVER_HALF_WIDTH * 0.75
		water_points.append(Vector3(cx - off, WATER_LEVEL, z))
		water_points.append(Vector3(cx + off, WATER_LEVEL, z))
		z += 8.0


## Altura do chão em (x, z), interpolada da grade.
func height_at(x: float, z: float) -> float:
	var fx := clampf(x / RES, 0.0, n - 1.001)
	var fz := clampf(z / RES, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + n]
	var h11 := heights[i + n + 1]
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


func clamp_to_play_area(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, play_min, play_max), p.y, clampf(p.z, play_min, play_max))


## Ponto aleatório em terra firme, dentro da área jogável e fora das montanhas.
func random_land_point(rng: RandomNumberGenerator) -> Vector3:
	for i in 200:
		var x := rng.randf_range(BORDER + 6.0, size - BORDER - 6.0)
		var z := rng.randf_range(BORDER + 6.0, size - BORDER - 6.0)
		var h := height_at(x, z)
		if h > 0.6 and h < 26.0 and slope_at(x, z) < 0.7:
			return Vector3(x, h, z)
	return Vector3(size * 0.5 + 40.0, height_at(size * 0.5 + 40.0, size * 0.5), size * 0.5)


func nearest_water_point(from: Vector3) -> Vector3:
	var best := water_points[0]
	var best_d := INF
	for p in water_points:
		var d := Vector2(p.x - from.x, p.z - from.z).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best


## Índices dos arbustos dentro do retângulo [x0, x1] x [z0, z1] (pelas células da grade,
## então pode trazer alguns um pouco de fora; confira a distância se precisar).
func bushes_in_rect(x0: float, z0: float, x1: float, z1: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for cz in range(floori(z0 / BUSH_CELL), floori(z1 / BUSH_CELL) + 1):
		for cx in range(floori(x0 / BUSH_CELL), floori(x1 / BUSH_CELL) + 1):
			var cell: PackedInt32Array = _bush_grid.get(Vector2i(cx, cz), PackedInt32Array())
			out.append_array(cell)
	return out


## Índices dos arbustos a até `radius` metros (no plano) de `p`.
func bushes_near(p: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	for i in bushes_in_rect(p.x - radius, p.z - radius, p.x + radius, p.z + radius):
		var b := bushes[i]
		var dx := b.x - p.x
		var dz := b.z - p.z
		if dx * dx + dz * dz <= r2:
			out.append(i)
	return out
