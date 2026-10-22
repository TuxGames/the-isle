class_name DinoView
extends Node3D
## Visual de um dinossauro, montado com formas simples a partir das esferas da hitbox
## (o que você vê é exatamente o que a mordida acerta). Modelos 3D de verdade
## entram no lugar disso quando o Marcelo achar os assets.
##
## O nó fica nos pés do bicho; +Z local = frente; rotation.y = yaw.

var entity_id := 0
var species := ""
var growth := 1.0
var is_dead := false
## true = é o dino do próprio jogador (posição vem direto do controle, sem suavizar).
var is_local := false
var flags := 0

var target_pos := Vector3.ZERO
var target_yaw := 0.0

var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _materials: Array[StandardMaterial3D] = []
var _label: Label3D
var _phase := 0.0
var _attack_t := -1.0
var _flash_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _has_target := false


static func create(id: int, p_species: String, p_growth: float, dead: bool = false) -> DinoView:
	var v := DinoView.new()
	v.entity_id = id
	v.species = p_species
	v.growth = p_growth
	v.is_dead = dead
	v.name = "Dino_%d" % id
	v._build()
	return v


func _build() -> void:
	var sp: Dictionary = Species.DATA[species]
	var main_mat := _material(sp["color"])
	var belly_mat := _material(sp["color2"])
	var dark_mat := _material(Color(0.08, 0.07, 0.06))
	var horn_mat := _material(Color(0.86, 0.82, 0.7))

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var head_parts := []
	for part in sp["body"]:
		var pname: String = part[2]
		if pname == "pernas":
			continue
		if pname == "cabeça" or pname == "pescoço":
			head_parts.append(part)
			continue
		var stretch := Vector3(0.9, 0.85, 1.35) if pname != "peito" else Vector3(0.95, 0.95, 1.15)
		_add_sphere(_body, part[0], part[1], stretch, main_mat)
		# Barriga mais clara
		if pname == "tronco" or pname == "peito":
			var c: Vector3 = part[0]
			var r: float = part[1]
			_add_sphere(_body, c + Vector3(0, -r * 0.35, 0), r * 0.8, Vector3(0.85, 0.7, 1.3), belly_mat)

	# A cabeça fica num pivô próprio pra animar a mordida.
	var neck_base := Vector3.ZERO
	for part in head_parts:
		if part[2] == "pescoço":
			neck_base = part[0]
	if neck_base == Vector3.ZERO and not head_parts.is_empty():
		neck_base = head_parts[0][0]
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = neck_base
	_body.add_child(_head)
	for part in head_parts:
		var c: Vector3 = part[0]
		var r: float = part[1]
		var st := Vector3(0.85, 0.8, 1.4) if part[2] == "cabeça" else Vector3(0.8, 0.85, 1.3)
		_add_sphere(_head, c - neck_base, r, st, main_mat)
		if part[2] == "cabeça":
			# Olhos
			for side in [-1.0, 1.0]:
				_add_sphere(_head, c - neck_base + Vector3(side * r * 0.7, r * 0.3, r * 0.35), r * 0.16, Vector3.ONE, dark_mat)
			_add_species_head_extras(c - neck_base, r, horn_mat, main_mat)

	_build_legs(sp, main_mat, _material((sp["color"] as Color).darkened(0.35)))
	if species == "carnotaurus":
		# Bracinhos
		for side in [-1.0, 1.0]:
			var arm := _add_capsule(_body, Vector3(side * 0.75, 1.9, 1.75), 0.1, 0.5, main_mat)
			arm.rotation_degrees = Vector3(60, 0, 0)

	_body.scale = Vector3.ONE * Species.scale_for(species, growth)
	if is_dead:
		_apply_dead_pose()


func _add_species_head_extras(head_c: Vector3, r: float, horn_mat: StandardMaterial3D, main_mat: StandardMaterial3D) -> void:
	match species:
		"carnotaurus":
			for side in [-1.0, 1.0]:
				var horn := _add_cone(_head, head_c + Vector3(side * r * 0.55, r * 0.75, -r * 0.1), 0.12, 0.4, horn_mat)
				horn.rotation_degrees = Vector3(0, 0, -side * 35.0)
		"triceratops":
			# Babado (frill)
			var frill := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = r * 1.25
			disc.bottom_radius = r * 1.25
			disc.height = 0.12
			disc.radial_segments = 16
			disc.material = main_mat
			frill.mesh = disc
			frill.position = head_c + Vector3(0, r * 0.55, -r * 0.55)
			frill.rotation_degrees = Vector3(70, 0, 0)
			_head.add_child(frill)
			# Dois chifres na testa e um no nariz
			for side in [-1.0, 1.0]:
				var horn := _add_cone(_head, head_c + Vector3(side * r * 0.45, r * 0.55, r * 0.55), 0.13, 1.0, horn_mat)
				horn.rotation_degrees = Vector3(70, 0, 0)
			var nose := _add_cone(_head, head_c + Vector3(0, r * 0.1, r * 1.25), 0.1, 0.35, horn_mat)
			nose.rotation_degrees = Vector3(50, 0, 0)


func _build_legs(sp: Dictionary, mat: StandardMaterial3D, foot_mat: StandardMaterial3D) -> void:
	var hip: float = sp["hip_height"]
	var torso_r: float = sp["body"][0][1]
	var positions: Array = []
	if species == "triceratops":
		positions = [Vector3(-0.85, hip, 1.3), Vector3(0.85, hip, 1.3), Vector3(-0.9, hip, -1.2), Vector3(0.9, hip, -1.2)]
	else:
		positions = [Vector3(-torso_r * 0.55, hip, -0.1), Vector3(torso_r * 0.55, hip, -0.1)]
	var leg_r := torso_r * (0.32 if species == "triceratops" else 0.28)
	for p in positions:
		var pivot := Node3D.new()
		pivot.position = p
		_body.add_child(pivot)
		var leg := _add_capsule(pivot, Vector3(0, -hip * 0.5, 0), leg_r, hip + leg_r, mat)
		leg.name = "Leg"
		var foot := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(leg_r * 1.6, leg_r * 0.5, leg_r * 2.2)
		box.material = foot_mat
		foot.mesh = box
		foot.position = Vector3(0, -hip + leg_r * 0.3, leg_r * 0.6)
		pivot.add_child(foot)
		_legs.append(pivot)


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_materials.append(m)
	return m


func _add_sphere(parent: Node3D, center: Vector3, radius: float, stretch: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	mesh.material = mat
	mi.mesh = mesh
	mi.position = center
	mi.scale = stretch
	parent.add_child(mi)
	return mi


func _add_capsule(parent: Node3D, center: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 10
	mesh.rings = 4
	mesh.material = mat
	mi.mesh = mesh
	mi.position = center
	parent.add_child(mi)
	return mi


func _add_cone(parent: Node3D, base: Vector3, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.material = mat
	mi.mesh = mesh
	mi.position = base + Vector3(0, height * 0.5, 0)
	parent.add_child(mi)
	return mi


func _apply_dead_pose() -> void:
	_body.rotation_degrees = Vector3(0, 0, 88)
	var hip: float = Species.DATA[species]["hip_height"]
	_body.position = Vector3(hip * 0.95 * _body.scale.x, -hip * 0.55 * _body.scale.x, 0)
	for m in _materials:
		m.albedo_color = m.albedo_color.darkened(0.45)


# ---------------------------------------------------------------- estado vindo da rede

func set_growth(g: float) -> void:
	if absf(g - growth) > 0.001:
		growth = g
		_body.scale = Vector3.ONE * Species.scale_for(species, growth)
		_update_label_height()


func set_target(pos: Vector3, yaw: float, p_flags: int) -> void:
	flags = p_flags
	if not _has_target or position.distance_to(pos) > 25.0:
		position = pos
		rotation.y = yaw
		_last_pos = pos
	target_pos = pos
	target_yaw = yaw
	_has_target = true


func set_player_name(text: String) -> void:
	if text == "":
		if _label:
			_label.queue_free()
			_label = null
		return
	if _label == null:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 48
		_label.pixel_size = 0.006
		_label.outline_size = 10
		_label.modulate = Color(1, 1, 0.92)
		_label.fixed_size = false
		add_child(_label)
	_label.text = text
	_update_label_height()


func _update_label_height() -> void:
	if _label:
		var hip: float = Species.DATA[species]["hip_height"]
		_label.position = Vector3(0, hip * 1.9 * Species.scale_for(species, growth) + 0.5, 0)


func play_attack() -> void:
	_attack_t = 0.0


func flash_damage() -> void:
	_flash_t = 0.2


# ---------------------------------------------------------------- animação

func _process(delta: float) -> void:
	if is_dead:
		return
	if not is_local and _has_target:
		var k := 1.0 - exp(-12.0 * delta)
		position = position.lerp(target_pos, k)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-10.0 * delta))

	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length()
	_speed = lerpf(_speed, moved / maxf(delta, 0.0001), 0.2)
	_last_pos = position

	var s := Species.scale_for(species, growth)
	var hip: float = Species.DATA[species]["hip_height"]

	# Pernas: balançam conforme a velocidade
	var stride := _speed / maxf(hip * s, 0.2) * 2.2
	if flags & Net.SF_LIMP:
		stride *= 0.7
	_phase += delta * stride
	var amp := clampf(_speed / (2.0 * maxf(s, 0.3)), 0.0, 1.0) * 0.6
	for i in _legs.size():
		var offset := PI if i % 2 == 1 else 0.0
		if _legs.size() == 4 and i >= 2:
			offset += PI
		_legs[i].rotation.x = sin(_phase + offset) * amp

	# Corpo: abaixa descansando, balança andando
	var rest := 1.0 if (flags & Net.SF_REST) else 0.0
	var bob := sin(_phase * 2.0) * amp * 0.04 * hip * s
	_body.position.y = lerpf(_body.position.y, -hip * 0.4 * s * rest + bob, 1.0 - exp(-6.0 * delta))

	# Cabeça: mordida, comendo, normal
	var head_target := Vector3.ZERO
	var head_rot := 0.0
	if flags & Net.SF_EAT:
		head_rot = 0.5 + sin(Time.get_ticks_msec() / 180.0) * 0.12
		head_target = Vector3(0, -hip * 0.35, 0.2)
	if _attack_t >= 0.0:
		_attack_t += delta
		var a := sin(clampf(_attack_t / 0.35, 0.0, 1.0) * PI)
		head_target = Vector3(0, -0.25 * a, 0.8 * a)
		head_rot = 0.25 * a
		if _attack_t > 0.35:
			_attack_t = -1.0
	_head.position = _head.position.lerp(_neck_base() + head_target, 1.0 - exp(-20.0 * delta))
	_head.rotation.x = lerpf(_head.rotation.x, head_rot, 1.0 - exp(-14.0 * delta))

	# Pisca vermelho ao tomar dano
	if _flash_t > 0.0:
		_flash_t -= delta
		for m in _materials:
			m.emission_enabled = _flash_t > 0.0
			m.emission = Color(0.9, 0.05, 0.02)
			m.emission_energy_multiplier = 1.5


func _neck_base() -> Vector3:
	for part in Species.DATA[species]["body"]:
		if part[2] == "pescoço":
			return part[0]
	for part in Species.DATA[species]["body"]:
		if part[2] == "cabeça":
			return part[0]
	return Vector3.ZERO
