class_name ScentView
extends Node3D
## Rastro do faro (design, seção 10): marcas amarelas no chão, mais fracas quanto mais velha a
## pegada, e uma mancha maior em cada carcaça. Some sozinho depois de SNIFF_SHOW_S. É uma
## MultiMesh só, então pesa quase nada mesmo com centenas de pegadas.

const PRINT_SIZE := Vector2(0.8, 1.2)
const CARCASS_SIZE := 2.6
## Altura acima do chão, pra marca não sumir dentro do terreno.
const LIFT := 0.15
## Nos últimos segundos o rastro vai sumindo devagar.
const FADE_S := 1.5
const COLOR_PRINT := Color(1.0, 0.86, 0.2)
const COLOR_CARCASS := Color(1.0, 0.62, 0.15)

var _mm_instance: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _left := 0.0


func _ready() -> void:
	name = "Faro"
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.material = _mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	_mm_instance = MultiMeshInstance3D.new()
	_mm_instance.multimesh = mm
	_mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_instance)
	visible = false


## Mostra o que o servidor mandou (ScentTrail.STRIDE floats por item).
func show_scent(data: PackedFloat32Array, terrain: Terrain) -> void:
	var mm := _mm_instance.multimesh
	var n := data.size() / ScentTrail.STRIDE
	mm.instance_count = n
	for i in n:
		var b := i * ScentTrail.STRIDE
		var x := data[b]
		var z := data[b + 1]
		var age := data[b + 2]
		var carcass := int(data[b + 4]) == ScentTrail.KIND_CARCASS
		var y := terrain.height_at(x, z) + LIFT
		var basis := Basis()
		var color := COLOR_CARCASS
		if carcass:
			basis = basis.scaled(Vector3(CARCASS_SIZE, 1.0, CARCASS_SIZE))
		else:
			# Cada pegada virada pra um lado (vem da posição: sempre a mesma pra mesma pegada).
			var yaw := fmod(absf(x * 12.9898 + z * 78.233), TAU)
			basis = Basis(Vector3.UP, yaw).scaled(Vector3(PRINT_SIZE.x, 1.0, PRINT_SIZE.y))
			color = COLOR_PRINT
			color.a = lerpf(0.95, 0.25, clampf(age / GameConfig.SCENT_MAX_AGE_S, 0.0, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		mm.set_instance_color(i, color)
	_left = GameConfig.SNIFF_SHOW_S
	_mat.albedo_color = Color(1, 1, 1, 1)
	visible = n > 0


func clear() -> void:
	_left = 0.0
	visible = false
	_mm_instance.multimesh.instance_count = 0


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	_mat.albedo_color = Color(1, 1, 1, clampf(_left / FADE_S, 0.0, 1.0))
	if _left <= 0.0:
		clear()
