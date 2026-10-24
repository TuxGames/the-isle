class_name TerrainView
extends Node3D
## Parte visual do mapa: malha do terreno, água, arbustos, céu, sol e neblina.
## Usa o mesmo Terrain do servidor, então o que se vê bate com a simulação.

const COLOR_MUD := Color(0.33, 0.29, 0.22)
const COLOR_SAND := Color(0.74, 0.68, 0.5)
const COLOR_GRASS := Color(0.32, 0.46, 0.19)
const COLOR_GRASS_DRY := Color(0.52, 0.55, 0.27)
const COLOR_FOREST := Color(0.2, 0.33, 0.14)
const COLOR_ROCK := Color(0.38, 0.36, 0.33)
const COLOR_SNOW := Color(0.86, 0.88, 0.92)

var terrain: Terrain


static func build(t: Terrain) -> TerrainView:
	var v := TerrainView.new()
	v.name = "TerrainView"
	v.terrain = t
	v._build_ground()
	v._build_water()
	v._build_bushes()
	v._build_environment()
	return v


func _build_ground() -> void:
	var n := Terrain.N
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var tint := FastNoiseLite.new()
	tint.seed = terrain.seed_value + 55
	tint.frequency = 0.02
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var x := ix * Terrain.RES
			var z := iz * Terrain.RES
			var h := terrain.heights[i]
			verts[i] = Vector3(x, h, z)
			var hl := terrain.heights[iz * n + maxi(ix - 1, 0)]
			var hr := terrain.heights[iz * n + mini(ix + 1, n - 1)]
			var hd := terrain.heights[maxi(iz - 1, 0) * n + ix]
			var hu := terrain.heights[mini(iz + 1, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, 2.0 * Terrain.RES, hd - hu).normalized()
			normals[i] = nrm
			colors[i] = _ground_color(h, 1.0 - nrm.y, tint.get_noise_2d(x, z))

	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Ordem horária vista de cima (face da frente no Godot).
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# As cores acima estão em sRGB (como num editor de imagem).
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	add_child(mi)


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
	plane.size = Vector2(Terrain.SIZE, Terrain.SIZE)
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
	mi.position = Vector3(Terrain.SIZE * 0.5, Terrain.WATER_LEVEL, Terrain.SIZE * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_bushes() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = Terrain.BUSH_RADIUS
	sphere.height = Terrain.BUSH_RADIUS * 1.5
	sphere.radial_segments = 10
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.36, 0.13)
	mat.roughness = 1.0
	sphere.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = terrain.bushes.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value + 9
	for i in terrain.bushes.size():
		var p: Vector3 = terrain.bushes[i]
		var s := rng.randf_range(0.8, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s))
		mm.set_instance_transform(i, Transform3D(basis, p + Vector3(0, Terrain.BUSH_RADIUS * 0.45 * s, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bushes"
	mmi.multimesh = mm
	add_child(mmi)


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
	env.fog_density = 0.0012
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
