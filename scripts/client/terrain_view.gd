class_name TerrainView
extends Node3D
## Parte visual do mapa: terreno, água, arbustos, céu, sol e neblina.
## Usa o mesmo Terrain do servidor, então o que se vê bate com a simulação.
##
## O terreno é desenhado em pedaços de CHUNK metros, só num raio em volta do jogador (`focus`),
## com menos detalhe longe (design, seção 5: o mapa é grande, mas só carrega a área em volta
## de cada jogador). Os pedaços entram e saem conforme ele anda, poucos por quadro.

const COLOR_MUD := Color(0.33, 0.29, 0.22)
const COLOR_SAND := Color(0.74, 0.68, 0.5)
const COLOR_GRASS := Color(0.32, 0.46, 0.19)
const COLOR_GRASS_DRY := Color(0.52, 0.55, 0.27)
const COLOR_FOREST := Color(0.2, 0.33, 0.14)
const COLOR_ROCK := Color(0.38, 0.36, 0.33)
const COLOR_SNOW := Color(0.86, 0.88, 0.92)

## Lado de cada pedaço do terreno, em metros (múltiplo de 32, pra bater com a grade de arbustos).
const CHUNK := 128.0
## Níveis de detalhe: até que distância (do jogador até a borda do pedaço) cada um vale,
## de quantos em quantos metros vão os vértices e se o pedaço desenha os arbustos.
## O último limite fica perto do `camera.far` (1200 m); depois disso a neblina já cobriu tudo.
const LOD_DIST := [192.0, 448.0, 704.0, 1150.0]
const LOD_STEP := [2.0, 4.0, 8.0, 16.0]
const LOD_BUSHES := [true, true, false, false]
## Folga pra um pedaço na divisa entre dois níveis não ficar trocando de um pro outro.
const LOD_HYSTERESIS := 24.0
## Distância de visão máxima (igual ao último LOD_DIST) e a neblina que combina com ela.
## Com distância menor (configurações), a neblina engrossa na mesma proporção pra esconder a borda.
const MAX_VIEW_DIST := 1150.0
const FOG_DENSITY := 0.0012
## Tempo por quadro pra montar pedaços. Pedaço perto que falta, e o pedaço embaixo do
## jogador, são montados na hora mesmo passando disso (o chão dele nunca pode faltar).
const BUILD_BUDGET_MS := 4.0
## De quanto em quanto tempo recalcula quais pedaços devem estar carregados.
const REFRESH_S := 0.1

var terrain: Terrain
## Onde o jogador está. Até o cliente informar (depois do login), nada é montado.
var focus := Vector3(-1.0e9, 0.0, -1.0e9)

## Vector2i -> {"lod": int, "node": Node3D}
var _chunks := {}
var _ground_mat: StandardMaterial3D
var _bush_mesh: SphereMesh
var _tint := FastNoiseLite.new()
var _refresh_t := 0.0
## Até onde desenhar o terreno (configurações → distância de visão).
var view_distance := MAX_VIEW_DIST
var _env: Environment
var _sun: DirectionalLight3D


static func build(t: Terrain) -> TerrainView:
	var v := TerrainView.new()
	v.name = "TerrainView"
	v.terrain = t
	v._setup_materials()
	v._build_water()
	v._build_environment()
	return v


# ---------------------------------------------------------------- quais pedaços

## Pedaços que devem estar carregados com o jogador em `focus`: {Vector2i: nível de detalhe}.
## `current` é o que já está carregado ({Vector2i: nível}), pra histerese. Nada além de
## `max_dist` (distância de visão) é carregado.
static func wanted_chunks(p_focus: Vector3, map_size: float, current: Dictionary = {},
		max_dist: float = MAX_VIEW_DIST) -> Dictionary:
	var out := {}
	var count := ceili(map_size / CHUNK)
	var reach: float = minf(max_dist, MAX_VIEW_DIST) + LOD_HYSTERESIS
	var c0x := clampi(floori((p_focus.x - reach) / CHUNK), 0, count - 1)
	var c1x := clampi(floori((p_focus.x + reach) / CHUNK), 0, count - 1)
	var c0z := clampi(floori((p_focus.z - reach) / CHUNK), 0, count - 1)
	var c1z := clampi(floori((p_focus.z + reach) / CHUNK), 0, count - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var key := Vector2i(cx, cz)
			var dist := chunk_distance(p_focus, key)
			if dist > max_dist + (LOD_HYSTERESIS if current.has(key) else 0.0):
				continue
			var lod := lod_for(dist, int(current.get(key, -1)))
			if lod >= 0:
				out[key] = lod
	return out


## Distância no plano do ponto até o pedaço (0 se está dentro dele).
static func chunk_distance(p: Vector3, key: Vector2i) -> float:
	var x0 := key.x * CHUNK
	var z0 := key.y * CHUNK
	var dx := maxf(maxf(x0 - p.x, p.x - (x0 + CHUNK)), 0.0)
	var dz := maxf(maxf(z0 - p.z, p.z - (z0 + CHUNK)), 0.0)
	return sqrt(dx * dx + dz * dz)


## Nível de detalhe pra esta distância (-1 = longe demais, não carrega). Quem já está num
## nível só sai dele passando LOD_HYSTERESIS além da divisa.
static func lod_for(dist: float, current: int = -1) -> int:
	if current >= 0 and current < LOD_DIST.size():
		var lo: float = -INF if current == 0 else float(LOD_DIST[current - 1]) - LOD_HYSTERESIS
		var hi: float = float(LOD_DIST[current]) + LOD_HYSTERESIS
		if dist > lo and dist <= hi:
			return current
	for i in LOD_DIST.size():
		if dist <= float(LOD_DIST[i]):
			return i
	return -1


# ---------------------------------------------------------------- quadro a quadro

func _process(delta: float) -> void:
	if focus.x < -1.0e8:
		return
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = REFRESH_S
	update_chunks()


## Descarrega o que saiu do raio e monta o que falta, do mais perto pro mais longe.
## Devolve quantos pedaços montou (pros testes e pra medir).
func update_chunks(budget_ms: float = BUILD_BUDGET_MS) -> int:
	var current := {}
	for key in _chunks:
		current[key] = _chunks[key]["lod"]
	var wanted := wanted_chunks(focus, terrain.size, current, view_distance)
	for key in _chunks.keys():
		if not wanted.has(key):
			_chunks[key]["node"].queue_free()
			_chunks.erase(key)
	var todo := []
	for key in wanted:
		if not _chunks.has(key) or int(_chunks[key]["lod"]) != int(wanted[key]):
			todo.append(key)
	var f := focus
	todo.sort_custom(func(a, b): return chunk_distance(f, a) < chunk_distance(f, b))
	var start := Time.get_ticks_usec()
	var built := 0
	for key in todo:
		# Urgente: pedaço perto que ainda não existe, ou o pedaço embaixo do jogador com pouco
		# detalhe (depois de um teleporte o dino ficaria flutuando ou afundado).
		var urgent: bool = int(wanted[key]) == 0 and (not _chunks.has(key) or chunk_distance(f, key) == 0.0)
		if not urgent and Time.get_ticks_usec() - start > budget_ms * 1000.0:
			break
		_build_chunk(key, int(wanted[key]))
		built += 1
	return built


func loaded_chunks() -> Dictionary:
	var out := {}
	for key in _chunks:
		out[key] = _chunks[key]["lod"]
	return out


# ---------------------------------------------------------------- montagem

func _setup_materials() -> void:
	_tint.seed = terrain.seed_value + 55
	_tint.frequency = 0.02
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	# As cores abaixo estão em sRGB (como num editor de imagem).
	_ground_mat.vertex_color_is_srgb = true
	_ground_mat.roughness = 0.95
	# As "saias" dos pedaços (ver _chunk_arrays) são vistas dos dois lados.
	_ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bush_mesh = SphereMesh.new()
	_bush_mesh.radius = Terrain.BUSH_RADIUS
	_bush_mesh.height = Terrain.BUSH_RADIUS * 1.5
	_bush_mesh.radial_segments = 10
	_bush_mesh.rings = 6
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.18, 0.36, 0.13)
	bush_mat.roughness = 1.0
	_bush_mesh.material = bush_mat


func _build_chunk(key: Vector2i, lod: int) -> void:
	if _chunks.has(key):
		_chunks[key]["node"].queue_free()
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _chunk_arrays(key, lod))
	mesh.surface_set_material(0, _ground_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	node.add_child(mi)
	if LOD_BUSHES[lod]:
		var bushes := _chunk_bushes(key)
		if bushes != null:
			node.add_child(bushes)
	add_child(node)
	_chunks[key] = {"lod": lod, "node": node}


## Linha de índices da grade de `a` até `b` pulando `stride` (sempre inclui o `b`).
static func _grid_line(a: int, b: int, stride: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := a
	while i < b:
		out.append(i)
		i += stride
	out.append(b)
	return out


## Malha de um pedaço: vértices tirados da grade do Terrain de LOD_STEP em LOD_STEP metros,
## mais uma "saia" descendo em volta das bordas, que esconde as frestas entre pedaços vizinhos
## com detalhe diferente.
func _chunk_arrays(key: Vector2i, lod: int) -> Array:
	var step: float = LOD_STEP[lod]
	var stride := int(step / Terrain.RES)
	var n := terrain.n
	var per_chunk := int(CHUNK / Terrain.RES)
	var xs := _grid_line(key.x * per_chunk, mini((key.x + 1) * per_chunk, n - 1), stride)
	var zs := _grid_line(key.y * per_chunk, mini((key.y + 1) * per_chunk, n - 1), stride)
	var w := xs.size()
	var hgt := zs.size()
	var skirt_depth := step + 1.0

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * hgt)
	normals.resize(w * hgt)
	colors.resize(w * hgt)
	for zi in hgt:
		var iz := zs[zi]
		var z := iz * Terrain.RES
		for xi in w:
			var ix := xs[xi]
			var x := ix * Terrain.RES
			var h := terrain.heights[iz * n + ix]
			var hl := terrain.heights[iz * n + maxi(ix - stride, 0)]
			var hr := terrain.heights[iz * n + mini(ix + stride, n - 1)]
			var hd := terrain.heights[maxi(iz - stride, 0) * n + ix]
			var hu := terrain.heights[mini(iz + stride, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var i := zi * w + xi
			verts[i] = Vector3(x, h, z)
			normals[i] = nrm
			colors[i] = _ground_color(h, 1.0 - nrm.y, _tint.get_noise_2d(x, z))

	var indices := PackedInt32Array()
	indices.resize(((w - 1) * (hgt - 1) + 2 * (w - 1) + 2 * (hgt - 1)) * 6)
	var k := 0
	for zi in hgt - 1:
		for xi in w - 1:
			var a := zi * w + xi
			var b := a + 1
			var c := a + w
			var d := c + 1
			# Ordem horária vista de cima (face da frente no Godot).
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	# Saia: cada borda ganha uma cópia dos vértices, mais embaixo, ligada por uma faixa.
	var edges: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for xi in w:
		edges[0].append(xi)
		edges[1].append((hgt - 1) * w + xi)
	for zi in hgt:
		edges[2].append(zi * w)
		edges[3].append(zi * w + w - 1)
	for edge in edges:
		var first := verts.size()
		for top in edge:
			verts.append(verts[top] - Vector3(0.0, skirt_depth, 0.0))
			normals.append(normals[top])
			colors.append(colors[top])
		for e in edge.size() - 1:
			indices[k] = edge[e]
			indices[k + 1] = edge[e + 1]
			indices[k + 2] = first + e
			indices[k + 3] = edge[e + 1]
			indices[k + 4] = first + e + 1
			indices[k + 5] = first + e
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _chunk_bushes(key: Vector2i) -> MultiMeshInstance3D:
	var x0 := key.x * CHUNK
	var z0 := key.y * CHUNK
	var ids := PackedInt32Array()
	for i in terrain.bushes_in_rect(x0, z0, x0 + CHUNK, z0 + CHUNK):
		var p := terrain.bushes[i]
		# A grade devolve as células da borda também; cada arbusto fica num pedaço só.
		if p.x >= x0 and p.x < x0 + CHUNK and p.z >= z0 and p.z < z0 + CHUNK:
			ids.append(i)
	if ids.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _bush_mesh
	mm.instance_count = ids.size()
	var rng := RandomNumberGenerator.new()
	for k in ids.size():
		var i := ids[k]
		# Cada arbusto tem seu tamanho e giro fixos, venha em que pedaço vier.
		rng.seed = terrain.seed_value * 7919 + i
		var p := terrain.bushes[i]
		var s := rng.randf_range(0.8, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s))
		mm.set_instance_transform(k, Transform3D(basis, p + Vector3(0, Terrain.BUSH_RADIUS * 0.45 * s, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bushes"
	mmi.multimesh = mm
	return mmi


func _ground_color(h: float, steep: float, noise: float) -> Color:
	var c: Color
	if h < -0.2:
		c = COLOR_MUD
	elif h < 1.2:
		c = COLOR_SAND.lerp(COLOR_GRASS, clampf((h - 0.4) / 0.8, 0.0, 1.0))
	else:
		var g := COLOR_GRASS.lerp(COLOR_FOREST, clampf(noise * 0.9 + 0.35, 0.0, 1.0))
		g = g.lerp(COLOR_GRASS_DRY, clampf(-noise - 0.25, 0.0, 0.6))
		c = g
	# Pedra só em encosta íngreme de verdade (margem do rio continua terra/areia).
	var rock_from := 0.5 if h < 12.0 else 0.3
	if steep > rock_from:
		c = c.lerp(COLOR_ROCK, clampf((steep - rock_from) / 0.25, 0.0, 1.0))
	if h > 44.0:
		c = c.lerp(COLOR_SNOW, clampf((h - 44.0) / 10.0 + noise * 0.2, 0.0, 0.85))
	return c


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain.size, terrain.size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.26, 0.3, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.55
	mat.metallic = 0.0
	mat.metallic_specular = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position = Vector3(terrain.size * 0.5, Terrain.WATER_LEVEL, terrain.size * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.75)
	sky_mat.sky_horizon_color = Color(0.62, 0.7, 0.76)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky_mat.ground_bottom_color = Color(0.25, 0.28, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.ambient_light_sky_contribution = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.62, 0.68)
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	_env = env
	_sun = sun


## Distância de visão (configurações). A câmera do cliente acompanha (camera.far).
func set_view_distance(d: float) -> void:
	view_distance = clampf(d, CHUNK, MAX_VIEW_DIST)
	if _env:
		_env.fog_density = FOG_DENSITY * MAX_VIEW_DIST / view_distance
	_refresh_t = 0.0


func set_shadows(on: bool) -> void:
	if _sun:
		_sun.shadow_enabled = on
