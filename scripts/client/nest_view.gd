class_name NestView
extends Node3D
## Ninhos e ovos (design, seção 8) com formas simples: um anel marrom no chão e os ovos cor de
## creme em volta do centro (o ovo pronto pro dono fica dourado). Os dados vêm do s_nests, que o
## servidor manda quando algo muda; aqui só redesenha tudo (são poucos ninhos).

const RING_COLOR := Color(0.4, 0.27, 0.13)
const BED_COLOR := Color(0.55, 0.42, 0.24)
const EGG_COLOR := Color(0.93, 0.89, 0.76)
const READY_COLOR := Color(1.0, 0.8, 0.3)
const MINE_COLOR := Color(1.0, 0.86, 0.45)

## Onde está cada ovo (pro aviso "[E] comer ovo" do cliente).
var egg_positions := PackedVector3Array()
var _mats := {}


func _ready() -> void:
	name = "Ninhos"


func clear() -> void:
	for c in get_children():
		c.queue_free()
	egg_positions.clear()


## Redesenha a lista do s_nests (Nests.public_list). `my_name` marca o ninho do jogador.
func show_nests(list: Array, terrain: Terrain, my_name: String) -> void:
	clear()
	for n in list:
		var center: Vector3 = n["pos"]
		var root := Node3D.new()
		root.position = Vector3(center.x, terrain.height_at(center.x, center.z), center.z)
		add_child(root)
		_add_ring(root)
		var sp_id := Species.id_at(int(n["sp"]))
		var r := Nests.egg_radius(sp_id)
		var ready: PackedInt32Array = n.get("ready", PackedInt32Array())
		for slot in PackedInt32Array(n.get("eggs", PackedInt32Array())):
			var off := Nests.egg_offset(slot)
			var world := root.position + off
			world.y = terrain.height_at(world.x, world.z)
			egg_positions.append(world)
			var egg := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = r
			mesh.height = r * 2.6
			mesh.radial_segments = 12
			mesh.rings = 6
			egg.mesh = mesh
			egg.material_override = _mat(READY_COLOR if ready.has(slot) else EGG_COLOR)
			egg.position = Vector3(off.x, world.y - root.position.y + r * 1.1, off.z)
			# Cada ovo meio deitado pra um lado (fixo por vaga).
			egg.rotation = Vector3(0.35, slot * 1.1, 0.0)
			root.add_child(egg)
		if String(n.get("owner", "")) != "" and String(n["owner"]) == my_name:
			var label := Label3D.new()
			label.text = "Seu ninho"
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = MINE_COLOR
			label.outline_size = 8
			label.font_size = 40
			label.pixel_size = 0.01
			label.position = Vector3(0.0, 1.4, 0.0)
			label.no_depth_test = true
			root.add_child(label)


func _add_ring(root: Node3D) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = Nests.NEST_RADIUS_M - 0.3
	torus.outer_radius = Nests.NEST_RADIUS_M
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _mat(RING_COLOR)
	ring.scale = Vector3(1.0, 0.6, 1.0)
	ring.position.y = 0.06
	root.add_child(ring)
	# Fundo de folhas e terra dentro do anel.
	var bed := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = Nests.NEST_RADIUS_M - 0.15
	disc.bottom_radius = Nests.NEST_RADIUS_M - 0.15
	disc.height = 0.06
	disc.radial_segments = 20
	bed.mesh = disc
	bed.material_override = _mat(BED_COLOR)
	bed.position.y = 0.02
	root.add_child(bed)


func _mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_mats[color] = m
	return _mats[color]
